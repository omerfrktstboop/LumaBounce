class_name AnalyticsService
extends RefCounted

## Oyunun tek analytics yuzeyi. Event adlari ve alanlari burada allowlist ile
## sinirlanir; kabul edilen event provider'a ertelenmis olarak iletilir.

const SESSION_START := &"session_start"
const SESSION_END := &"session_end"
const LEVEL_START := &"level_start"
const LEVEL_COMPLETE := &"level_complete"
const LEVEL_FAIL := &"level_fail"
const RESTART := &"restart"
const HINT_OFFER_OPEN := &"hint_offer_open"
const SHORT_HINT_REWARDED_EARNED := &"short_hint_rewarded_earned"
const FULL_HINT_UNLOCK := &"full_hint_unlock"
const REWARDED_OFFER := &"rewarded_offer"
const REWARDED_CLICK := &"rewarded_click"
const REWARDED_RESULT := &"rewarded_result"
const INTERSTITIAL_CANDIDATE := &"interstitial_candidate"
const INTERSTITIAL_SHOWN := &"interstitial_shown"
const INTERSTITIAL_FAILED := &"interstitial_failed"
const REMOVE_ADS_PURCHASE_RESULT := &"remove_ads_purchase_result"
const SHOP_OPEN := &"shop_open"
const COSMETIC_PURCHASE := &"cosmetic_purchase"
const COSMETIC_SELECT := &"cosmetic_select"
const DAILY_OPEN := &"daily_open"
const DAILY_COMPLETE := &"daily_complete"
const DAILY_THREE_STAR := &"daily_three_star"
const QUEST_COMPLETE := &"quest_complete"
const ALL_DAILY_QUESTS_COMPLETE := &"all_daily_quests_complete"
const STREAK_MILESTONE := &"streak_milestone"
const ACHIEVEMENT_UNLOCK := &"achievement_unlock"

# Onceki fazdaki adlari kullanan test/entegrasyonlar icin kaynak uyumlulugu.
const HINT_SHORT_REQUESTED := REWARDED_CLICK
const HINT_FULL_UNLOCKED := FULL_HINT_UNLOCK
const INTERSTITIAL_RESULT := INTERSTITIAL_FAILED
const IAP_RESULT := REMOVE_ADS_PURCHASE_RESULT

const NORMALIZED_EVENTS := [
	SESSION_START, SESSION_END,
	LEVEL_START, LEVEL_COMPLETE, LEVEL_FAIL, RESTART,
	HINT_OFFER_OPEN, SHORT_HINT_REWARDED_EARNED, FULL_HINT_UNLOCK,
	REWARDED_OFFER, REWARDED_CLICK, REWARDED_RESULT,
	INTERSTITIAL_CANDIDATE, INTERSTITIAL_SHOWN, INTERSTITIAL_FAILED,
	REMOVE_ADS_PURCHASE_RESULT,
	SHOP_OPEN, COSMETIC_PURCHASE, COSMETIC_SELECT,
	DAILY_OPEN, DAILY_COMPLETE, DAILY_THREE_STAR,
	QUEST_COMPLETE, ALL_DAILY_QUESTS_COMPLETE, STREAK_MILESTONE,
	ACHIEVEMENT_UNLOCK,
]

const EVENT_FIELDS := {
	SESSION_START: [&"game_version", &"environment", &"analytics_provider", &"ad_provider", &"reason"],
	SESSION_END: [&"seconds_bucket", &"reason"],
	LEVEL_START: [&"level_id", &"world", &"is_bonus"],
	LEVEL_COMPLETE: [&"level_id", &"world", &"stars", &"seconds_bucket", &"shots", &"first_clear", &"is_bonus"],
	LEVEL_FAIL: [&"level_id", &"world", &"reason", &"shots_bucket", &"is_bonus"],
	RESTART: [&"level_id", &"world", &"shots_bucket", &"source"],
	HINT_OFFER_OPEN: [&"level_id", &"short_available", &"full_unlocked"],
	SHORT_HINT_REWARDED_EARNED: [&"level_id", &"placement"],
	FULL_HINT_UNLOCK: [&"level_id", &"cost"],
	REWARDED_OFFER: [&"level_id", &"placement"],
	REWARDED_CLICK: [&"level_id", &"placement", &"provider"],
	REWARDED_RESULT: [&"placement", &"provider", &"result"],
	INTERSTITIAL_CANDIDATE: [&"context"],
	INTERSTITIAL_SHOWN: [&"context", &"provider"],
	INTERSTITIAL_FAILED: [&"context", &"provider", &"reason"],
	REMOVE_ADS_PURCHASE_RESULT: [&"product_id", &"action", &"result", &"provider"],
	SHOP_OPEN: [&"balance"],
	COSMETIC_PURCHASE: [&"cosmetic_id", &"kind", &"price"],
	COSMETIC_SELECT: [&"cosmetic_id", &"kind"],
	DAILY_OPEN: [&"day_index", &"streak_bucket"],
	DAILY_COMPLETE: [&"day_index", &"reward"],
	DAILY_THREE_STAR: [&"day_index"],
	QUEST_COMPLETE: [&"quest_id", &"quest_type"],
	ALL_DAILY_QUESTS_COMPLETE: [&"day_index", &"reward"],
	STREAK_MILESTONE: [&"streak_bucket"],
	ACHIEVEMENT_UNLOCK: [&"achievement_id", &"reward"],
}

const MAX_PENDING_EVENTS := 128
const MAX_TOKEN_LENGTH := 64
const FAILURE_REASONS := [
	"settled", "out_of_bounds", "manual_cancel", "laser", "bomb",
	"spike", "hazard", "pulse_gate", "other",
]

var debug_logging := false
var capture_events := false
var _captured: Array[Dictionary] = []
var _provider: AnalyticsProvider
var _config: GameAnalyticsConfig
var _initialized := false
var _pending: Array[Dictionary] = []
var _flush_scheduled := false
var _provider_warning_shown := false


func _init(enable_debug_logging := OS.is_debug_build(), enable_capture := false) -> void:
	debug_logging = enable_debug_logging
	capture_events = enable_capture
	_provider = NoOpAnalyticsProvider.new()
	_config = GameAnalyticsConfig.new()


func configure(provider: AnalyticsProvider, config: GameAnalyticsConfig) -> void:
	_provider = provider if provider != null else NoOpAnalyticsProvider.new()
	_config = config if config != null else GameAnalyticsConfig.new()


func initialize() -> bool:
	_initialized = _provider != null and _provider.initialize(_config)
	if not _initialized:
		_provider = NoOpAnalyticsProvider.new()
		_initialized = _provider.initialize(_config)
		_warn_provider_once("provider baslatilamadi; NoOp kullaniliyor")
	return _initialized


func provider_name() -> StringName:
	return _provider.provider_name() if _provider != null else &"none"


func environment() -> StringName:
	return _config.environment if _config != null else GameAnalyticsConfig.ENVIRONMENT_STAGING


func track_event(event_name: StringName, properties := {}) -> bool:
	if not NORMALIZED_EVENTS.has(event_name):
		push_warning("AnalyticsService: normalize edilmemis event reddedildi: %s" % event_name)
		return false
	var safe_properties := _sanitize_properties(event_name, properties)
	var event := {"name": event_name, "properties": safe_properties}
	if capture_events:
		_captured.append(event.duplicate(true))
	if debug_logging:
		print("[Analytics] %s %s" % [event_name, JSON.stringify(safe_properties)])
	if _pending.size() >= MAX_PENDING_EVENTS:
		_pending.pop_front()
	_pending.append(event)
	_schedule_flush()
	return true


## Analytics izni UMP reklam izninden ayri yonetilir. UI/consent katmani
## eklendiginde save semasini bilmeden bu tek giris noktasini kullanabilir.
func set_collection_enabled(enabled: bool) -> void:
	if _config != null:
		_config.collection_enabled = enabled
	if _provider != null:
		_provider.set_collection_enabled(enabled)


func flush_pending() -> void:
	_flush_scheduled = false
	if not _initialized or _provider == null:
		_pending.clear()
		return
	while not _pending.is_empty():
		var event := _pending.pop_front() as Dictionary
		if not _provider.send_event(event["name"], event["properties"]):
			_warn_provider_once("event gonderimi basarisiz; oyun akisi devam ediyor")


func shutdown() -> void:
	flush_pending()
	if _provider != null:
		_provider.shutdown()


func captured_events() -> Array[Dictionary]:
	return _captured.duplicate(true)


func clear_captured_events() -> void:
	_captured.clear()


static func seconds_bucket(seconds: float) -> StringName:
	if seconds < 15.0:
		return &"0_14"
	if seconds < 30.0:
		return &"15_29"
	if seconds < 60.0:
		return &"30_59"
	if seconds < 120.0:
		return &"60_119"
	return &"120_plus"


static func shots_bucket(shots: int) -> StringName:
	if shots <= 0:
		return &"0"
	if shots <= 3:
		return StringName(str(shots))
	if shots <= 5:
		return &"4_5"
	return &"6_plus"


static func failure_reason(reason: String) -> StringName:
	var normalized := reason.strip_edges().to_lower()
	return StringName(normalized if FAILURE_REASONS.has(normalized) else "other")


func _sanitize_properties(event_name: StringName, properties: Dictionary) -> Dictionary:
	var safe := {}
	var allowed: Array = EVENT_FIELDS.get(event_name, [])
	for raw_key in allowed:
		var key := StringName(raw_key)
		if not properties.has(key) and not properties.has(String(key)):
			continue
		var value: Variant = properties.get(key, properties.get(String(key)))
		match typeof(value):
			TYPE_BOOL, TYPE_INT:
				safe[key] = value
			TYPE_FLOAT:
				if is_finite(float(value)):
					safe[key] = value
			TYPE_STRING, TYPE_STRING_NAME:
				safe[key] = _bounded_token(String(value))
	return safe


func _bounded_token(value: String) -> String:
	var source := value.strip_edges().to_lower().left(MAX_TOKEN_LENGTH)
	var output := ""
	for character in source:
		if character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789_.-":
			output += character.to_lower()
		else:
			output += "_"
	return output if not output.is_empty() else "other"


func _schedule_flush() -> void:
	if _flush_scheduled:
		return
	_flush_scheduled = true
	flush_pending.call_deferred()


func _warn_provider_once(message: String) -> void:
	if not debug_logging or _provider_warning_shown:
		return
	_provider_warning_shown = true
	push_warning("AnalyticsService: %s" % message)
