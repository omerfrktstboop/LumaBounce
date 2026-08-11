class_name PurchaseService
extends Node

## Tek urunluk v1 Billing orkestrasyonu. Provider Google Play cevaplarini
## normalize eder; bu servis entitlement, acknowledge ve analytics sirasini
## uygular. Purchase token analytics'e veya ProgressStore'a yazilmaz.

signal state_changed()
signal entitlement_changed(product_id: StringName, active: bool)
signal purchase_finished(product_id: StringName, result: int)

var _provider: PurchaseProvider
var _entitlements: EntitlementStore
var _analytics: AnalyticsService
var _initialized := false
var _purchase_busy := false
var _restore_busy := false
var _initial_restore_started := false


func configure(provider: PurchaseProvider, entitlements: EntitlementStore,
		analytics: AnalyticsService) -> void:
	_provider = provider
	_entitlements = entitlements
	_analytics = analytics


func initialize() -> bool:
	if _initialized or _provider == null or _entitlements == null:
		return false
	_initialized = true
	_provider.availability_changed.connect(_on_provider_availability_changed)
	_provider.catalog_changed.connect(_on_provider_catalog_changed)
	_provider.unsolicited_purchases.connect(_on_unsolicited_purchases)
	add_child(_provider)
	var started := _provider.initialize()
	if _provider.is_available():
		_start_initial_restore.call_deferred()
	state_changed.emit()
	return started


func provider_name() -> StringName:
	return _provider.provider_name() if _provider != null else &"none"


func is_available() -> bool:
	return _initialized and _provider != null and _provider.is_available()


func is_remove_ads_active() -> bool:
	return _entitlements != null and _entitlements.remove_ads


func is_product_ready(product_id: StringName) -> bool:
	return (
		_initialized
		and not _purchase_busy
		and _provider != null
		and _provider.is_product_ready(product_id))


func formatted_price(product_id: StringName) -> String:
	return _provider.formatted_price(product_id) if _provider != null else ""


func is_busy() -> bool:
	return _purchase_busy or _restore_busy


func purchase_remove_ads() -> int:
	var product_id := MonetizationConfig.PRODUCT_REMOVE_ADS
	if is_remove_ads_active():
		return _finish_purchase(product_id, PurchaseResult.Code.ALREADY_OWNED)
	if not is_product_ready(product_id):
		return _finish_purchase(product_id, PurchaseResult.Code.UNAVAILABLE)

	_purchase_busy = true
	state_changed.emit()
	var response := await _provider.purchase(product_id)
	var result := int(response.get("result", PurchaseResult.Code.FAILED))
	var records: Array = response.get("records", [])
	if result == PurchaseResult.Code.PURCHASED:
		await _apply_incremental_records(records)
		if not is_remove_ads_active():
			result = PurchaseResult.Code.FAILED
	elif result == PurchaseResult.Code.ALREADY_OWNED:
		var restored := await _restore_internal()
		if restored and is_remove_ads_active():
			result = PurchaseResult.Code.RESTORED
	_purchase_busy = false
	state_changed.emit()
	return _finish_purchase(product_id, result)


func restore_purchases() -> bool:
	if not _initialized or _provider == null or _restore_busy or _purchase_busy:
		return false
	_restore_busy = true
	state_changed.emit()
	var success := await _restore_internal()
	_restore_busy = false
	state_changed.emit()
	_track_iap("restore", "success" if success else "unavailable")
	return success


func shutdown() -> void:
	if _provider != null:
		_provider.shutdown()


func _exit_tree() -> void:
	shutdown()


func _restore_internal() -> bool:
	var response := await _provider.restore_purchases()
	if not bool(response.get("success", false)):
		return false
	await _apply_authoritative_records(response.get("records", []))
	return true


func _apply_authoritative_records(records: Array) -> void:
	var purchased := false
	for record in records:
		if _is_purchased_remove_ads(record):
			purchased = true
			break
	_update_remove_ads(purchased)
	if purchased:
		await _acknowledge_records(records)


func _apply_incremental_records(records: Array) -> void:
	var purchased := false
	for record in records:
		if _is_purchased_remove_ads(record):
			purchased = true
			break
	if not purchased:
		return
	_update_remove_ads(true)
	await _acknowledge_records(records)


func _acknowledge_records(records: Array) -> void:
	for raw_record in records:
		if raw_record is not Dictionary:
			continue
		var record := raw_record as Dictionary
		if not _is_purchased_remove_ads(record) or bool(record.get("acknowledged", false)):
			continue
		var token := String(record.get("purchase_token", ""))
		if token.is_empty():
			continue
		# Hak once verilir, ardindan Google bilgilendirilir. Basarisiz ack bir
		# sonraki launch/resume restore sorgusunda yeniden denenir.
		await _provider.acknowledge_purchase(token)


func _is_purchased_remove_ads(raw_record: Variant) -> bool:
	if raw_record is not Dictionary:
		return false
	var record := raw_record as Dictionary
	return (
		record.get("product_id") == MonetizationConfig.PRODUCT_REMOVE_ADS
		and String(record.get("state", "")) == "purchased")


func _update_remove_ads(active: bool) -> void:
	var changed := _entitlements.remove_ads != active
	_entitlements.update_remove_ads(active, Time.get_unix_time_from_system())
	if changed:
		entitlement_changed.emit(MonetizationConfig.PRODUCT_REMOVE_ADS, active)
	state_changed.emit()


func _finish_purchase(product_id: StringName, result: int) -> int:
	_track_iap("purchase", PurchaseResult.key(result))
	purchase_finished.emit(product_id, result)
	return result


func _track_iap(action: String, result: String) -> void:
	if _analytics == null:
		return
	_analytics.track_event(AnalyticsService.REMOVE_ADS_PURCHASE_RESULT, {
		"product_id": String(MonetizationConfig.PRODUCT_REMOVE_ADS),
		"action": action,
		"result": result,
		"provider": String(provider_name()),
	})


func _on_provider_availability_changed() -> void:
	state_changed.emit()
	if _provider.is_available() and not _initial_restore_started:
		_start_initial_restore.call_deferred()


func _on_provider_catalog_changed(_product_id: StringName) -> void:
	state_changed.emit()


func _start_initial_restore() -> void:
	if _initial_restore_started or not _provider.is_available():
		return
	_initial_restore_started = true
	await restore_purchases()


func _on_unsolicited_purchases(records: Array) -> void:
	_apply_incremental_records.call_deferred(records)
