class_name PurchaseProvider
extends Node

## Billing SDK'sindan bagimsiz provider yuzeyi. Gameplay ve magazaya yalnizca
## PurchaseService ulasir; native siniflar bu katmanin disina cikmaz.

signal availability_changed()
signal catalog_changed(product_id: StringName)
signal unsolicited_purchases(records: Array)


func provider_name() -> StringName:
	return &"noop"


func initialize() -> bool:
	return true


func is_available() -> bool:
	return false


func is_product_ready(_product_id: StringName) -> bool:
	return false


func formatted_price(_product_id: StringName) -> String:
	return ""


func purchase(_product_id: StringName) -> Dictionary:
	return {
		"result": PurchaseResult.Code.UNAVAILABLE,
		"records": [],
	}


func restore_purchases() -> Dictionary:
	return {
		"success": false,
		"records": [],
	}


func acknowledge_purchase(_purchase_token: String) -> bool:
	return false


func shutdown() -> void:
	pass
