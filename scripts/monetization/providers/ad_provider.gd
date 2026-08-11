class_name AdProvider
extends Node

## Gercek SDK adapterlerinin uygulayacagi dar provider arayuzu.
## Bu sinifin disina SDK nesnesi, reklam birimi kimligi veya plugin class'i
## cikmaz. Tum show metodlari tek bir AdResult.Code ile tamamlanir.

signal availability_changed()
signal privacy_options_availability_changed(available: bool)


func provider_name() -> StringName:
	return &"base"


func initialize() -> bool:
	return false


func is_rewarded_ready(_placement: StringName) -> bool:
	return false


func show_rewarded(_placement: StringName) -> int:
	await get_tree().process_frame
	return AdResult.Code.UNAVAILABLE


func is_interstitial_ready() -> bool:
	return false


func show_interstitial(_context: StringName) -> int:
	await get_tree().process_frame
	return AdResult.Code.UNAVAILABLE


func is_privacy_options_available() -> bool:
	return false


func show_privacy_options() -> bool:
	await get_tree().process_frame
	return false
