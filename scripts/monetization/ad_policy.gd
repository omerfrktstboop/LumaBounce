class_name AdPolicy
extends RefCounted

## Reklam saglayicisindan tamamen bagimsiz v1 gosterim kurallari.
## Cadence adayi her dorduncu basarili completion'da TUKETILIR; reklam hazir
## degilse sonraki ekrana gecis gecikmez ve reklam borcu birikmez.

var _entitlements: EntitlementStore
var _completions_since_candidate := 0
var _last_interstitial_at := -1.0
var _last_rewarded_at := -1.0


func _init(entitlements: EntitlementStore = null) -> void:
	_entitlements = entitlements if entitlements != null else EntitlementStore.new()


func register_successful_completion(completed_normal_levels: int,
		is_normal_level := true) -> bool:
	if not is_normal_level or _entitlements.remove_ads:
		return false
	if completed_normal_levels <= MonetizationConfig.NORMAL_COMPLETIONS_WITHOUT_INTERSTITIAL:
		_completions_since_candidate = 0
		return false
	_completions_since_candidate += 1
	if _completions_since_candidate < MonetizationConfig.INTERSTITIAL_COMPLETION_INTERVAL:
		return false
	_completions_since_candidate = 0
	return true


func can_show_interstitial(context: StringName, is_candidate: bool,
		now_seconds := -1.0) -> bool:
	if not is_candidate or _entitlements.remove_ads:
		return false
	if context != MonetizationConfig.CONTEXT_LEVEL_COMPLETE:
		return false
	var now := _resolve_time(now_seconds)
	if _last_interstitial_at >= 0.0 and (
			now - _last_interstitial_at < MonetizationConfig.INTERSTITIAL_COOLDOWN_SECONDS):
		return false
	if _last_rewarded_at >= 0.0 and (
			now - _last_rewarded_at < MonetizationConfig.REWARDED_SUPPRESSION_SECONDS):
		return false
	return true


func interstitials_enabled() -> bool:
	return not _entitlements.remove_ads


func record_interstitial_shown(now_seconds := -1.0) -> void:
	_last_interstitial_at = _resolve_time(now_seconds)


func record_rewarded_shown(now_seconds := -1.0) -> void:
	_last_rewarded_at = _resolve_time(now_seconds)


func reset_session_state() -> void:
	_completions_since_candidate = 0
	_last_interstitial_at = -1.0
	_last_rewarded_at = -1.0


func debug_snapshot() -> Dictionary:
	return {
		"completions_since_candidate": _completions_since_candidate,
		"last_interstitial_at": _last_interstitial_at,
		"last_rewarded_at": _last_rewarded_at,
		"remove_ads": _entitlements.remove_ads,
	}


func _resolve_time(value: float) -> float:
	if value >= 0.0:
		return value
	return float(Time.get_ticks_msec()) / 1000.0
