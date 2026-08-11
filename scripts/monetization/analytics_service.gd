class_name AnalyticsService
extends RefCounted

## Network SDK'si olmayan normalize event yuzeyi. Release'te no-op; debug'da
## istenirse yerel log yazar. Testler capture_events ile deterministik okur.

const SESSION_START := &"session_start"
const LEVEL_START := &"level_start"
const LEVEL_COMPLETE := &"level_complete"
const LEVEL_FAIL := &"level_fail"
const HINT_OFFER_OPEN := &"hint_offer_open"
const HINT_SHORT_REQUESTED := &"hint_short_requested"
const HINT_FULL_UNLOCKED := &"hint_full_unlocked"
const REWARDED_OFFER := &"rewarded_offer"
const REWARDED_RESULT := &"rewarded_result"
const INTERSTITIAL_RESULT := &"interstitial_result"
const IAP_RESULT := &"iap_result"

const NORMALIZED_EVENTS := [
	SESSION_START,
	LEVEL_START,
	LEVEL_COMPLETE,
	LEVEL_FAIL,
	HINT_OFFER_OPEN,
	HINT_SHORT_REQUESTED,
	HINT_FULL_UNLOCKED,
	REWARDED_OFFER,
	REWARDED_RESULT,
	INTERSTITIAL_RESULT,
	IAP_RESULT,
]

var debug_logging := false
var capture_events := false
var _captured: Array[Dictionary] = []


func _init(enable_debug_logging := OS.is_debug_build(), enable_capture := false) -> void:
	debug_logging = enable_debug_logging
	capture_events = enable_capture


func track_event(event_name: StringName, properties := {}) -> bool:
	if not NORMALIZED_EVENTS.has(event_name):
		push_warning("AnalyticsService: normalize edilmemis event reddedildi: %s" % event_name)
		return false
	var safe_properties := properties.duplicate(true) as Dictionary
	if capture_events:
		_captured.append({
			"name": event_name,
			"properties": safe_properties,
		})
	if debug_logging:
		print("[Analytics] %s %s" % [event_name, JSON.stringify(safe_properties)])
	return true


func captured_events() -> Array[Dictionary]:
	return _captured.duplicate(true)


func clear_captured_events() -> void:
	_captured.clear()
