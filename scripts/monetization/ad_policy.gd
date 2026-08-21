class_name AdPolicy
extends RefCounted

## Reklam saglayicisindan tamamen bagimsiz merkezi gosterim kurallari.
## Basari adayi kalicidir; reklam hazir degilse/cooldown varsa sonraki dogal
## gameplay gecisinde yeniden denenir. Failure suresi ise oturuma ve aktif
## bolume ozeldir; menu/background/reklam suresi bu sinifa hic verilmez.

const DECISION_ALLOWED := &"allowed"
const SKIP_NOT_ELIGIBLE := &"not_eligible"
const SKIP_REMOVE_ADS := &"remove_ads"
const SKIP_GLOBAL_COOLDOWN := &"global_cooldown"

const STATE_SECTION := "interstitial"
const STATE_COMPLETION_COUNT := "successful_completion_count"
const STATE_COMPLETION_PENDING := "completion_pending"

var _entitlements: EntitlementStore
var _state_path := ""
var _debug_logging := false
var _successful_completion_count := 0
var _completion_pending := false
var _failure_level_key := ""
var _failure_playtime_seconds := 0.0
var _failure_pending := false
var _last_interstitial_at := -1.0
var _last_skip_reason := SKIP_NOT_ELIGIBLE


func _init(entitlements: EntitlementStore = null, state_path := "",
		enable_debug_logging := OS.is_debug_build() and not OS.has_feature("production")) -> void:
	_entitlements = entitlements if entitlements != null else EntitlementStore.new()
	_state_path = state_path
	_debug_logging = enable_debug_logging
	_load_state()


func register_successful_completion(level_key: String, is_normal_level := true) -> bool:
	reset_failure_level(level_key)
	if not is_normal_level or _entitlements.remove_ads:
		return false
	if not _completion_pending:
		_successful_completion_count += 1
		if _successful_completion_count >= MonetizationConfig.COMPLETIONS_PER_INTERSTITIAL:
			_successful_completion_count = 0
			_completion_pending = true
	_save_state()
	_debug("Successful completion %d/%d%s" % [
		MonetizationConfig.COMPLETIONS_PER_INTERSTITIAL if _completion_pending \
			else _successful_completion_count,
		MonetizationConfig.COMPLETIONS_PER_INTERSTITIAL,
		" - interstitial eligible" if _completion_pending else "",
	])
	return _completion_pending


func begin_level(level_key: String) -> void:
	if level_key == _failure_level_key:
		return
	_failure_level_key = level_key
	_failure_playtime_seconds = 0.0
	_failure_pending = false


func register_failed_attempt(level_key: String, active_playtime_seconds: float,
		is_normal_level := true) -> bool:
	if not is_normal_level or _entitlements.remove_ads:
		return false
	begin_level(level_key)
	if not _failure_pending:
		_failure_playtime_seconds += maxf(active_playtime_seconds, 0.0)
		if _failure_playtime_seconds >= MonetizationConfig.FAILURE_INTERSTITIAL_INTERVAL_SEC:
			_failure_pending = true
	_debug("Failure playtime: %d/%d sec" % [
		mini(int(_failure_playtime_seconds), int(MonetizationConfig.FAILURE_INTERSTITIAL_INTERVAL_SEC)),
		int(MonetizationConfig.FAILURE_INTERSTITIAL_INTERVAL_SEC),
	])
	if _failure_pending:
		_debug("Failure threshold reached")
	return _failure_pending


func reset_failure_level(level_key: String) -> void:
	if level_key != _failure_level_key:
		return
	_failure_playtime_seconds = 0.0
	_failure_pending = false


func has_interstitial_candidate(context: StringName) -> bool:
	match context:
		MonetizationConfig.CONTEXT_LEVEL_COMPLETE:
			return _completion_pending or _failure_pending
		MonetizationConfig.CONTEXT_LEVEL_FAIL:
			return _failure_pending or _completion_pending
		_:
			return false


func can_show_interstitial(context: StringName, now_seconds := -1.0) -> bool:
	if not has_interstitial_candidate(context):
		_last_skip_reason = SKIP_NOT_ELIGIBLE
		return false
	if _entitlements.remove_ads:
		_last_skip_reason = SKIP_REMOVE_ADS
		return false
	var now := _resolve_time(now_seconds)
	if _last_interstitial_at >= 0.0 and (
			now - _last_interstitial_at < MonetizationConfig.INTERSTITIAL_GLOBAL_COOLDOWN_SEC):
		_last_skip_reason = SKIP_GLOBAL_COOLDOWN
		return false
	_last_skip_reason = DECISION_ALLOWED
	return true


func interstitials_enabled() -> bool:
	return not _entitlements.remove_ads


func record_interstitial_shown(_context: StringName, now_seconds := -1.0) -> void:
	_last_interstitial_at = _resolve_time(now_seconds)
	# Ayni anda iki mekanizma da adaysa tek gosterim ikisini birden tuketir.
	_completion_pending = false
	_failure_pending = false
	_failure_playtime_seconds = 0.0
	_save_state()


func reset_session_state() -> void:
	_successful_completion_count = 0
	_completion_pending = false
	_failure_level_key = ""
	_failure_playtime_seconds = 0.0
	_failure_pending = false
	_last_interstitial_at = -1.0
	_last_skip_reason = SKIP_NOT_ELIGIBLE
	_save_state()


func last_skip_reason() -> StringName:
	return _last_skip_reason


func debug_logging_enabled() -> bool:
	return _debug_logging


func debug_snapshot() -> Dictionary:
	return {
		"successful_completion_count": _successful_completion_count,
		"completion_pending": _completion_pending,
		"failure_level_key": _failure_level_key,
		"failure_playtime_seconds": _failure_playtime_seconds,
		"failure_pending": _failure_pending,
		"last_interstitial_at": _last_interstitial_at,
		"remove_ads": _entitlements.remove_ads,
	}


func _resolve_time(value: float) -> float:
	if value >= 0.0:
		return value
	return float(Time.get_ticks_msec()) / 1000.0


func _load_state() -> void:
	if _state_path.is_empty():
		return
	var config := ConfigFile.new()
	if config.load(_state_path) != OK:
		return
	_successful_completion_count = clampi(
		int(config.get_value(STATE_SECTION, STATE_COMPLETION_COUNT, 0)),
		0, MonetizationConfig.COMPLETIONS_PER_INTERSTITIAL - 1)
	_completion_pending = bool(config.get_value(
		STATE_SECTION, STATE_COMPLETION_PENDING, false))


func _save_state() -> void:
	if _state_path.is_empty():
		return
	var config := ConfigFile.new()
	config.set_value(STATE_SECTION, STATE_COMPLETION_COUNT, _successful_completion_count)
	config.set_value(STATE_SECTION, STATE_COMPLETION_PENDING, _completion_pending)
	var error := config.save(_state_path)
	if error != OK and _debug_logging:
		push_warning("[ADS] Policy state could not be saved: %d" % error)


func _debug(message: String) -> void:
	if _debug_logging:
		print("[ADS] %s" % message)
