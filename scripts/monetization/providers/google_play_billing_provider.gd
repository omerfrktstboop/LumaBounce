class_name GooglePlayBillingProvider
extends PurchaseProvider

## Godot Foundation GodotGooglePlayBilling 3.3.0 adaptoru. Native BillingClient
## sinifi ve Google cevap kodlari yalnizca bu dosyada kullanilir.

signal _purchase_completed(request_id: int, response: Dictionary)
signal _restore_completed(request_id: int, response: Dictionary)
signal _acknowledge_completed(request_id: int, success: bool)

const PLUGIN_SINGLETON_NAME := "GodotGooglePlayBilling"
const PURCHASE_TIMEOUT_SECONDS := 300.0
const QUERY_TIMEOUT_SECONDS := 30.0
const RECONNECT_SECONDS := 5.0

var _billing: BillingClient
var _connected := false
var _product_details := {}
var _request_id := 0
var _active_purchase_request := 0
var _active_purchase_product := &""
var _active_restore_request := 0
var _active_acknowledge_request := 0
var _active_acknowledge_token := ""
var _shutting_down := false
var _reconnect_scheduled := false


func provider_name() -> StringName:
	return &"google_play"


func initialize() -> bool:
	if OS.get_name() != "Android" or not Engine.has_singleton(PLUGIN_SINGLETON_NAME):
		return false
	_billing = BillingClient.new()
	_billing.name = "GooglePlayBillingClient"
	_billing.process_mode = Node.PROCESS_MODE_ALWAYS
	_connect_signals()
	add_child(_billing)
	_billing.start_connection()
	return true


func is_available() -> bool:
	return _connected and _billing != null and _billing.is_ready()


func is_product_ready(product_id: StringName) -> bool:
	return is_available() and _product_details.has(product_id)


func formatted_price(product_id: StringName) -> String:
	var details: Dictionary = _product_details.get(product_id, {})
	var offer := _first_offer(details)
	return String(offer.get("formatted_price", ""))


func purchase(product_id: StringName) -> Dictionary:
	if not is_product_ready(product_id) or _active_purchase_request != 0:
		return {"result": PurchaseResult.Code.UNAVAILABLE, "records": []}

	var details: Dictionary = _product_details[product_id]
	var offer := _first_offer(details)
	var purchase_option_id := String(offer.get("purchase_option_id", ""))
	var offer_id := ""
	var raw_offer_id: Variant = offer.get("offer_id")
	if raw_offer_id != null:
		offer_id = String(raw_offer_id)

	_request_id += 1
	_active_purchase_request = _request_id
	_active_purchase_product = product_id
	var request_id := _active_purchase_request
	var launch := _billing.purchase(String(product_id), purchase_option_id, offer_id, false)
	var launch_code := int(launch.get("response_code", BillingClient.BillingResponseCode.ERROR))
	if launch_code != BillingClient.BillingResponseCode.OK:
		var failed := {
			"result": _result_from_billing_code(launch_code),
			"records": [],
		}
		_clear_purchase_request()
		return failed

	get_tree().create_timer(PURCHASE_TIMEOUT_SECONDS, true).timeout.connect(
		_on_purchase_timeout.bind(request_id), CONNECT_ONE_SHOT)
	var completed: Array = await _purchase_completed
	return completed[1] as Dictionary


func restore_purchases() -> Dictionary:
	if not is_available() or _active_restore_request != 0:
		return {"success": false, "records": []}
	_request_id += 1
	_active_restore_request = _request_id
	var request_id := _active_restore_request
	_billing.query_purchases(BillingClient.ProductType.INAPP)
	get_tree().create_timer(QUERY_TIMEOUT_SECONDS, true).timeout.connect(
		_on_restore_timeout.bind(request_id), CONNECT_ONE_SHOT)
	var completed: Array = await _restore_completed
	return completed[1] as Dictionary


func acknowledge_purchase(purchase_token: String) -> bool:
	if not is_available() or purchase_token.is_empty() or _active_acknowledge_request != 0:
		return false
	_request_id += 1
	_active_acknowledge_request = _request_id
	_active_acknowledge_token = purchase_token
	var request_id := _active_acknowledge_request
	_billing.acknowledge_purchase(purchase_token)
	get_tree().create_timer(QUERY_TIMEOUT_SECONDS, true).timeout.connect(
		_on_acknowledge_timeout.bind(request_id), CONNECT_ONE_SHOT)
	var completed: Array = await _acknowledge_completed
	return bool(completed[1])


func shutdown() -> void:
	_shutting_down = true
	if _billing != null:
		_billing.end_connection()


func _exit_tree() -> void:
	shutdown()


func _connect_signals() -> void:
	_billing.connected.connect(_on_connected)
	_billing.disconnected.connect(_on_disconnected)
	_billing.connect_error.connect(_on_connect_error)
	_billing.query_product_details_response.connect(_on_product_details_response)
	_billing.query_purchases_response.connect(_on_query_purchases_response)
	_billing.on_purchase_updated.connect(_on_purchase_updated)
	_billing.acknowledge_purchase_response.connect(_on_acknowledge_response)


func _on_connected() -> void:
	_connected = true
	availability_changed.emit()
	_billing.query_product_details(
		PackedStringArray([String(MonetizationConfig.PRODUCT_REMOVE_ADS)]),
		BillingClient.ProductType.INAPP)


func _on_disconnected() -> void:
	_connected = false
	_product_details.clear()
	availability_changed.emit()
	catalog_changed.emit(MonetizationConfig.PRODUCT_REMOVE_ADS)
	if _active_purchase_request != 0:
		var purchase_request := _active_purchase_request
		_clear_purchase_request()
		_purchase_completed.emit(purchase_request, {
			"result": PurchaseResult.Code.UNAVAILABLE,
			"records": [],
		})
	if _active_restore_request != 0:
		var restore_request := _active_restore_request
		_active_restore_request = 0
		_restore_completed.emit(restore_request, {"success": false, "records": []})
	if _active_acknowledge_request != 0:
		var acknowledge_request := _active_acknowledge_request
		_clear_acknowledge_request()
		_acknowledge_completed.emit(acknowledge_request, false)
	if not _shutting_down and not _reconnect_scheduled:
		_reconnect_scheduled = true
		get_tree().create_timer(RECONNECT_SECONDS, true).timeout.connect(
			_reconnect, CONNECT_ONE_SHOT)


func _on_connect_error(_response_code: int, _debug_message: String) -> void:
	_on_disconnected()


func _reconnect() -> void:
	_reconnect_scheduled = false
	if not _shutting_down and _billing != null and not _billing.is_ready():
		_billing.start_connection()


func _on_product_details_response(response: Dictionary) -> void:
	if int(response.get("response_code", BillingClient.BillingResponseCode.ERROR)) \
			!= BillingClient.BillingResponseCode.OK:
		_product_details.erase(MonetizationConfig.PRODUCT_REMOVE_ADS)
		catalog_changed.emit(MonetizationConfig.PRODUCT_REMOVE_ADS)
		return
	for raw_details in response.get("product_details", []):
		if raw_details is not Dictionary:
			continue
		var details := raw_details as Dictionary
		var product_id := StringName(String(details.get("product_id", "")))
		if product_id == MonetizationConfig.PRODUCT_REMOVE_ADS:
			_product_details[product_id] = details.duplicate(true)
	catalog_changed.emit(MonetizationConfig.PRODUCT_REMOVE_ADS)


func _on_query_purchases_response(response: Dictionary) -> void:
	var normalized := {
		"success": int(response.get("response_code", BillingClient.BillingResponseCode.ERROR))
			== BillingClient.BillingResponseCode.OK,
		"records": _normalize_records(response.get("purchases", [])),
	}
	if _active_restore_request == 0:
		if normalized["success"]:
			unsolicited_purchases.emit(normalized["records"])
		return
	var request_id := _active_restore_request
	_active_restore_request = 0
	_restore_completed.emit(request_id, normalized)


func _on_purchase_updated(response: Dictionary) -> void:
	var billing_code := int(response.get(
		"response_code", BillingClient.BillingResponseCode.ERROR))
	var records := _normalize_records(response.get("purchases", []))
	if _active_purchase_request == 0:
		if billing_code == BillingClient.BillingResponseCode.OK and not records.is_empty():
			unsolicited_purchases.emit(records)
		return

	var result := _result_from_billing_code(billing_code)
	if billing_code == BillingClient.BillingResponseCode.OK:
		result = _result_from_records(records, _active_purchase_product)
	var payload := {"result": result, "records": records}
	var request_id := _active_purchase_request
	_clear_purchase_request()
	_purchase_completed.emit(request_id, payload)


func _on_acknowledge_response(response: Dictionary) -> void:
	if _active_acknowledge_request == 0:
		return
	var token := String(response.get("token", ""))
	if not token.is_empty() and token != _active_acknowledge_token:
		return
	var success := int(response.get("response_code", BillingClient.BillingResponseCode.ERROR)) \
		== BillingClient.BillingResponseCode.OK
	var request_id := _active_acknowledge_request
	_clear_acknowledge_request()
	_acknowledge_completed.emit(request_id, success)


func _on_purchase_timeout(request_id: int) -> void:
	if request_id != _active_purchase_request:
		return
	_clear_purchase_request()
	_purchase_completed.emit(request_id, {
		"result": PurchaseResult.Code.FAILED,
		"records": [],
	})


func _on_restore_timeout(request_id: int) -> void:
	if request_id != _active_restore_request:
		return
	_active_restore_request = 0
	_restore_completed.emit(request_id, {"success": false, "records": []})


func _on_acknowledge_timeout(request_id: int) -> void:
	if request_id != _active_acknowledge_request:
		return
	_clear_acknowledge_request()
	_acknowledge_completed.emit(request_id, false)


func _clear_purchase_request() -> void:
	_active_purchase_request = 0
	_active_purchase_product = &""


func _clear_acknowledge_request() -> void:
	_active_acknowledge_request = 0
	_active_acknowledge_token = ""


func _first_offer(details: Dictionary) -> Dictionary:
	var raw_offers: Variant = details.get("one_time_purchase_offer_details_list", [])
	if raw_offers is Array and not (raw_offers as Array).is_empty():
		var first: Variant = (raw_offers as Array)[0]
		if first is Dictionary:
			return first as Dictionary
	return {}


func _normalize_records(raw_records: Variant) -> Array:
	var normalized: Array = []
	if raw_records is not Array:
		return normalized
	for raw_record in raw_records as Array:
		if raw_record is not Dictionary:
			continue
		var purchase := raw_record as Dictionary
		var state := "unknown"
		match int(purchase.get("purchase_state", BillingClient.PurchaseState.UNSPECIFIED_STATE)):
			BillingClient.PurchaseState.PURCHASED:
				state = "purchased"
			BillingClient.PurchaseState.PENDING:
				state = "pending"
		for raw_product_id in purchase.get("product_ids", PackedStringArray()):
			normalized.append({
				"product_id": StringName(String(raw_product_id)),
				"state": state,
				"acknowledged": bool(purchase.get("is_acknowledged", false)),
				"purchase_token": String(purchase.get("purchase_token", "")),
			})
	return normalized


func _result_from_records(records: Array, product_id: StringName) -> int:
	for record in records:
		if record is not Dictionary or record.get("product_id") != product_id:
			continue
		match String(record.get("state", "unknown")):
			"purchased":
				return PurchaseResult.Code.PURCHASED
			"pending":
				return PurchaseResult.Code.PENDING
	return PurchaseResult.Code.FAILED


func _result_from_billing_code(response_code: int) -> int:
	match response_code:
		BillingClient.BillingResponseCode.USER_CANCELED:
			return PurchaseResult.Code.CANCELLED
		BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED:
			return PurchaseResult.Code.ALREADY_OWNED
		BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE, \
				BillingClient.BillingResponseCode.BILLING_UNAVAILABLE, \
				BillingClient.BillingResponseCode.NETWORK_ERROR, \
				BillingClient.BillingResponseCode.SERVICE_DISCONNECTED:
			return PurchaseResult.Code.UNAVAILABLE
		_:
			return PurchaseResult.Code.FAILED
