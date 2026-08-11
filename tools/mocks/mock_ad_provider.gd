class_name MockAdProvider
extends AdProvider

## Yalnizca headless testlerde kullanilan deterministik provider.

var initialize_result := true
var rewarded_calls: Array[StringName] = []
var interstitial_calls: Array[StringName] = []
var privacy_options_calls := 0
var privacy_options_available := false
var privacy_options_result := true

var _rewarded_ready := {}
var _rewarded_results: Array[int] = []
var _interstitial_ready := false
var _interstitial_results: Array[int] = []


func provider_name() -> StringName:
	return &"mock"


func initialize() -> bool:
	return initialize_result


func set_rewarded_ready(placement: StringName, is_ready: bool) -> void:
	_rewarded_ready[placement] = is_ready


func queue_rewarded_result(result: int) -> void:
	_rewarded_results.append(result)


func is_rewarded_ready(placement: StringName) -> bool:
	return bool(_rewarded_ready.get(placement, false))


func show_rewarded(placement: StringName) -> int:
	rewarded_calls.append(placement)
	await get_tree().process_frame
	if _rewarded_results.is_empty():
		return AdResult.Code.UNAVAILABLE
	return _rewarded_results.pop_front()


func set_interstitial_ready(is_ready: bool) -> void:
	_interstitial_ready = is_ready


func queue_interstitial_result(result: int) -> void:
	_interstitial_results.append(result)


func is_interstitial_ready() -> bool:
	return _interstitial_ready


func show_interstitial(context: StringName) -> int:
	interstitial_calls.append(context)
	await get_tree().process_frame
	if _interstitial_results.is_empty():
		return AdResult.Code.UNAVAILABLE
	return _interstitial_results.pop_front()


func is_privacy_options_available() -> bool:
	return privacy_options_available


func show_privacy_options() -> bool:
	privacy_options_calls += 1
	await get_tree().process_frame
	return privacy_options_result
