class_name NoOpAdProvider
extends AdProvider

## SDK kurulmadan kullanilan guvenli production provider'i. Hazirlik her zaman
## false oldugu icin oyun reklam beklemeden devam eder.


func provider_name() -> StringName:
	return &"noop"


func initialize() -> bool:
	return true


func show_rewarded(_placement: StringName) -> int:
	await get_tree().process_frame
	return AdResult.Code.UNAVAILABLE


func show_interstitial(_context: StringName) -> int:
	await get_tree().process_frame
	return AdResult.Code.UNAVAILABLE
