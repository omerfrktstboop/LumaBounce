class_name MockPurchaseProvider
extends PurchaseProvider

## FAZ 7 headless testleri icin deterministik Billing provider.

var available := false
var product_ready := true
var price := "₺49,99"
var purchase_calls: Array[StringName] = []
var restore_calls := 0
var acknowledge_calls: Array[String] = []

var _purchase_results: Array[Dictionary] = []
var _restore_results: Array[Dictionary] = []
var _acknowledge_results: Array[bool] = []


func provider_name() -> StringName:
	return &"mock_billing"


func is_available() -> bool:
	return available


func is_product_ready(product_id: StringName) -> bool:
	return available and product_ready and product_id == MonetizationConfig.PRODUCT_REMOVE_ADS


func formatted_price(product_id: StringName) -> String:
	return price if is_product_ready(product_id) else ""


func set_available(value: bool) -> void:
	available = value
	availability_changed.emit()


func queue_purchase(result: int, records: Array = []) -> void:
	_purchase_results.append({"result": result, "records": records.duplicate(true)})


func queue_restore(success: bool, records: Array = []) -> void:
	_restore_results.append({"success": success, "records": records.duplicate(true)})


func queue_acknowledge(success: bool) -> void:
	_acknowledge_results.append(success)


func purchase(product_id: StringName) -> Dictionary:
	purchase_calls.append(product_id)
	await get_tree().process_frame
	if _purchase_results.is_empty():
		return {"result": PurchaseResult.Code.UNAVAILABLE, "records": []}
	return _purchase_results.pop_front()


func restore_purchases() -> Dictionary:
	restore_calls += 1
	await get_tree().process_frame
	if _restore_results.is_empty():
		return {"success": false, "records": []}
	return _restore_results.pop_front()


func acknowledge_purchase(purchase_token: String) -> bool:
	acknowledge_calls.append(purchase_token)
	await get_tree().process_frame
	if _acknowledge_results.is_empty():
		return true
	return _acknowledge_results.pop_front()


static func record(state: String, acknowledged := false,
		token := "purchase-token") -> Dictionary:
	return {
		"product_id": MonetizationConfig.PRODUCT_REMOVE_ADS,
		"state": state,
		"acknowledged": acknowledged,
		"purchase_token": token,
	}
