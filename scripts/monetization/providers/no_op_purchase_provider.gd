class_name NoOpPurchaseProvider
extends PurchaseProvider

## Editor, masaustu ve Billing plugin'i olmayan exportlar icin guvenli provider.


func provider_name() -> StringName:
	return &"noop"
