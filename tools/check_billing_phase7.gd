extends SceneTree

## Google Play olmadan PurchaseService yasam dongusunu deterministik dogrular.

var _failures := 0
var _cache_paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_contract()
	await _test_purchase_states()
	await _test_restore_and_revocation()
	await _test_already_owned_restore()
	await _test_automatic_restore()
	_cleanup()
	if _failures == 0:
		print("PASS billing phase 7: purchase, pending, acknowledge, restore, revocation")
		quit(0)
	else:
		push_error("FAIL billing phase 7: %d assertion(s)" % _failures)
		quit(1)


func _test_contract() -> void:
	_check(String(MonetizationConfig.PRODUCT_REMOVE_ADS) == "remove_ads",
		"Play product id is stable")
	_check(PurchaseResult.key(PurchaseResult.Code.PENDING) == "pending",
		"pending result is normalized")
	_check(FileAccess.file_exists("res://addons/GodotGooglePlayBilling/BillingClient.gd"),
		"official BillingClient script is vendored")
	_check(FileAccess.file_exists(
		"res://addons/GodotGooglePlayBilling/bin/release/GodotGooglePlayBilling-release.aar"),
		"release Billing AAR is vendored")


func _test_purchase_states() -> void:
	var setup := _make_service()
	var service := setup["service"] as PurchaseService
	var provider := setup["provider"] as MockPurchaseProvider
	var store := setup["store"] as EntitlementStore
	var analytics := setup["analytics"] as AnalyticsService
	provider.available = true

	_check(service.is_product_ready(MonetizationConfig.PRODUCT_REMOVE_ADS),
		"localized product is ready")
	_check(service.formatted_price(MonetizationConfig.PRODUCT_REMOVE_ADS) == "₺49,99",
		"localized Play price reaches UI contract")
	provider.queue_purchase(PurchaseResult.Code.PURCHASED, [
		MockPurchaseProvider.record("purchased", false, "token-purchased")])
	_check(int(await service.purchase_remove_ads()) == PurchaseResult.Code.PURCHASED,
		"purchased result is returned")
	_check(store.remove_ads, "PURCHASED grants remove_ads")
	_check(provider.acknowledge_calls == ["token-purchased"],
		"unacknowledged non-consumable is acknowledged")
	var reloaded := EntitlementStore.load_from_path(setup["path"])
	_check(reloaded.remove_ads, "remove_ads survives offline cache reload")
	_check(not JSON.stringify(analytics.captured_events()).contains("token-purchased"),
		"purchase token never enters analytics")

	store.update_remove_ads(false)
	provider.queue_purchase(PurchaseResult.Code.PENDING, [
		MockPurchaseProvider.record("pending", false, "token-pending")])
	_check(int(await service.purchase_remove_ads()) == PurchaseResult.Code.PENDING,
		"pending result is returned")
	_check(not store.remove_ads, "PENDING never grants entitlement")
	_check(not provider.acknowledge_calls.has("token-pending"),
		"PENDING is never acknowledged")

	provider.queue_purchase(PurchaseResult.Code.CANCELLED)
	_check(int(await service.purchase_remove_ads()) == PurchaseResult.Code.CANCELLED,
		"cancelled result is returned")
	_check(not store.remove_ads, "cancelled purchase grants nothing")
	provider.queue_purchase(PurchaseResult.Code.FAILED)
	_check(int(await service.purchase_remove_ads()) == PurchaseResult.Code.FAILED,
		"failed result is returned")
	_check(not store.remove_ads, "failed purchase grants nothing")
	provider.product_ready = false
	_check(int(await service.purchase_remove_ads()) == PurchaseResult.Code.UNAVAILABLE,
		"unavailable product returns immediately")
	_destroy_service(service)
	await process_frame


func _test_restore_and_revocation() -> void:
	var setup := _make_service(true)
	var service := setup["service"] as PurchaseService
	var provider := setup["provider"] as MockPurchaseProvider
	var store := setup["store"] as EntitlementStore
	provider.available = true
	provider.queue_restore(false, [])
	_check(not bool(await service.restore_purchases()), "offline restore reports unavailable")
	_check(store.remove_ads, "offline restore preserves the cached entitlement")

	provider.queue_restore(true, [])
	_check(bool(await service.restore_purchases()), "authoritative empty restore succeeds")
	_check(not store.remove_ads, "successful empty restore revokes stale cache")

	provider.queue_restore(true, [
		MockPurchaseProvider.record("purchased", false, "token-restored")])
	_check(bool(await service.restore_purchases()), "owned purchase restore succeeds")
	_check(store.remove_ads, "owned purchase restores entitlement")
	_check(provider.acknowledge_calls.has("token-restored"),
		"restored unacknowledged purchase is acknowledged")
	_destroy_service(service)
	await process_frame


func _test_already_owned_restore() -> void:
	var setup := _make_service()
	var service := setup["service"] as PurchaseService
	var provider := setup["provider"] as MockPurchaseProvider
	var store := setup["store"] as EntitlementStore
	provider.available = true
	provider.queue_purchase(PurchaseResult.Code.ALREADY_OWNED)
	provider.queue_restore(true, [MockPurchaseProvider.record("purchased", true)])
	_check(int(await service.purchase_remove_ads()) == PurchaseResult.Code.RESTORED,
		"already-owned flow restores instead of charging again")
	_check(store.remove_ads, "already-owned restore grants entitlement")
	_destroy_service(service)
	await process_frame


func _test_automatic_restore() -> void:
	var setup := _make_service()
	var service := setup["service"] as PurchaseService
	var provider := setup["provider"] as MockPurchaseProvider
	var store := setup["store"] as EntitlementStore
	provider.queue_restore(true, [MockPurchaseProvider.record("purchased", true)])
	provider.set_available(true)
	await process_frame
	await process_frame
	await process_frame
	_check(provider.restore_calls == 1, "first Play connection automatically restores once")
	_check(store.remove_ads, "automatic launch restore refreshes entitlement")
	_destroy_service(service)
	await process_frame


func _make_service(cached_remove_ads := false) -> Dictionary:
	var path := "user://billing_phase7_%d.cfg" % Time.get_ticks_usec()
	_cache_paths.append(path)
	var store := EntitlementStore.new(path)
	if cached_remove_ads:
		store.update_remove_ads(true, 1.0)
	var analytics := AnalyticsService.new(false, true)
	var provider := MockPurchaseProvider.new()
	var service := PurchaseService.new()
	service.configure(provider, store, analytics)
	root.add_child(service)
	service.initialize()
	return {
		"path": path,
		"store": store,
		"analytics": analytics,
		"provider": provider,
		"service": service,
	}


func _destroy_service(service: PurchaseService) -> void:
	if service != null and is_instance_valid(service):
		root.remove_child(service)
		service.queue_free()


func _cleanup() -> void:
	for path in _cache_paths:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
