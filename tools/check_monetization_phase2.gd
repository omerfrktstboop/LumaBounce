extends SceneTree

## SDK-bagimsiz reklam politikasi regresyonu. Network, gercek AdMob veya
## production user:// dosyalari kullanmaz; Mock provider deterministiktir.

var _failures := 0
var _paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_config_and_analytics_contract()
	_test_entitlement_cache()
	_test_completion_cadence_and_persistence()
	_test_failure_playtime()
	_test_global_cooldown_and_priority()
	_test_remove_ads_policy()
	_test_revive_cleanup()
	await _test_rewarded_hint_only()
	await _test_interstitial_service()
	await _test_fullscreen_double_show_guard()
	await _test_privacy_options()
	_cleanup_paths()
	if _failures == 0:
		print("PASS monetization: 3-completion cadence, failure timer, cooldown, hint, remove_ads")
		quit(0)
	else:
		push_error("FAIL monetization: %d assertion(s)" % _failures)
		quit(1)


func _test_config_and_analytics_contract() -> void:
	_check(MonetizationConfig.COMPLETIONS_PER_INTERSTITIAL == 3,
		"completion interval is three")
	_check(is_equal_approx(MonetizationConfig.FAILURE_INTERSTITIAL_INTERVAL_SEC, 600.0),
		"failure interval is ten minutes")
	_check(is_equal_approx(MonetizationConfig.INTERSTITIAL_GLOBAL_COOLDOWN_SEC, 180.0),
		"global interstitial cooldown is three minutes")
	_check(MonetizationConfig.is_rewarded_placement(
		MonetizationConfig.PLACEMENT_SHORT_HINT), "short hint is rewarded")
	_check(LumaAdmobConfig.rewarded_unit_id(MonetizationConfig.PLACEMENT_SHORT_HINT)
		== LumaAdmobConfig.TEST_REWARDED, "debug hint uses Google rewarded test unit")
	_check(LumaAdmobConfig.interstitial_unit_id() == LumaAdmobConfig.TEST_INTERSTITIAL,
		"debug interstitial uses Google test unit")
	var analytics := AnalyticsService.new(false, true)
	_check(analytics.track_event(AnalyticsService.INTERSTITIAL_SHOWN, {
		"context": MonetizationConfig.CONTEXT_LEVEL_COMPLETE,
		"provider": &"mock",
	}), "interstitial analytics remains normalized")


func _test_entitlement_cache() -> void:
	var path := _new_path("entitlements")
	var store := EntitlementStore.load_from_path(path)
	_check(not store.remove_ads, "remove_ads defaults to false")
	_check(store.update_remove_ads(true, 1234.0), "entitlement cache saves")
	var reloaded := EntitlementStore.load_from_path(path)
	_check(reloaded.remove_ads, "remove_ads survives cache reload")


func _test_completion_cadence_and_persistence() -> void:
	var path := _new_path("completion")
	var policy := _policy(path)
	_check(not policy.register_successful_completion("level_001"),
		"TEST A/B: first completion shows no ad")
	_check(not policy.register_successful_completion("level_002"),
		"TEST B: second completion shows no ad")
	policy = _policy(path)
	_check(int(policy.debug_snapshot()["successful_completion_count"]) == 2,
		"completion count survives session reload")
	_check(policy.register_successful_completion("level_003"),
		"TEST A: third completion becomes eligible")
	_check(policy.has_interstitial_candidate(MonetizationConfig.CONTEXT_LEVEL_COMPLETE),
		"third completion candidate remains pending")
	var reloaded := _policy(path)
	_check(bool(reloaded.debug_snapshot()["completion_pending"]),
		"pending completion survives restart without auto-show")
	var bonus := _policy(_new_path("bonus"))
	_check(not bonus.register_successful_completion("level_126", false),
		"bonus completion does not increment normal cadence")
	_check(int(bonus.debug_snapshot()["successful_completion_count"]) == 0,
		"bonus completion leaves counter unchanged")


func _test_failure_playtime() -> void:
	var policy := _policy()
	policy.begin_level("level_020")
	_check(not policy.register_failed_attempt("level_020", 540.0),
		"TEST D: nine active minutes show no ad")
	_check(not policy.register_failed_attempt("level_020", 59.9),
		"failure remains below ten-minute boundary")
	_check(policy.register_failed_attempt("level_020", 0.1),
		"TEST E: ten active minutes become eligible")
	policy.begin_level("level_021")
	var changed: Dictionary = policy.debug_snapshot()
	_check(float(changed["failure_playtime_seconds"]) == 0.0
		and not bool(changed["failure_pending"]),
		"changing level discards the previous failure timer")
	policy.register_failed_attempt("level_021", 599.0)
	policy.register_successful_completion("level_021")
	var completed: Dictionary = policy.debug_snapshot()
	_check(float(completed["failure_playtime_seconds"]) == 0.0,
		"TEST L: successful level resets its failure timer")
	var background := _policy()
	background.register_failed_attempt("level_022", 300.0)
	_check(is_equal_approx(float(background.debug_snapshot()["failure_playtime_seconds"]), 300.0),
		"TEST K: unreported background time never accumulates")
	_check(not background.register_failed_attempt("level_022", 299.0),
		"active time remains below threshold after resume")
	_check(background.register_failed_attempt("level_022", 1.0),
		"only the remaining active second reaches threshold")


func _test_global_cooldown_and_priority() -> void:
	var policy := _policy()
	for id in range(1, 4):
		policy.register_successful_completion("level_%03d" % id)
	_check(policy.can_show_interstitial(MonetizationConfig.CONTEXT_LEVEL_COMPLETE, 1000.0),
		"eligible completion can show")
	policy.record_interstitial_shown(MonetizationConfig.CONTEXT_LEVEL_COMPLETE, 1000.0)
	policy.register_failed_attempt("level_020", 600.0)
	_check(not policy.can_show_interstitial(MonetizationConfig.CONTEXT_LEVEL_FAIL, 1179.9),
		"TEST F: failure candidate is blocked by global cooldown")
	_check(policy.last_skip_reason() == AdPolicy.SKIP_GLOBAL_COOLDOWN,
		"cooldown skip reason is explicit")
	_check(policy.can_show_interstitial(MonetizationConfig.CONTEXT_LEVEL_FAIL, 1180.0),
		"TEST G: candidate is allowed when cooldown expires")
	policy.reset_session_state()
	for id in range(1, 4):
		policy.register_successful_completion("level_%03d" % id)
	policy.register_failed_attempt("level_020", 600.0)
	policy.record_interstitial_shown(MonetizationConfig.CONTEXT_LEVEL_FAIL, 2000.0)
	var snapshot: Dictionary = policy.debug_snapshot()
	_check(not bool(snapshot["completion_pending"]) and not bool(snapshot["failure_pending"]),
		"one display consumes simultaneous completion and failure candidates")


func _test_remove_ads_policy() -> void:
	var entitlements := EntitlementStore.new("user://unused_monetization.cfg")
	var policy := AdPolicy.new(entitlements, "", false)
	for id in range(1, 4):
		policy.register_successful_completion("level_%03d" % id)
	entitlements.remove_ads = true
	_check(not policy.can_show_interstitial(
		MonetizationConfig.CONTEXT_LEVEL_COMPLETE, 3000.0),
		"TEST H: remove_ads blocks automatic completion interstitial")
	_check(policy.last_skip_reason() == AdPolicy.SKIP_REMOVE_ADS,
		"remove_ads skip reason is explicit")
	_check(not policy.register_failed_attempt("level_020", 600.0),
		"remove_ads blocks failure candidates")


func _test_revive_cleanup() -> void:
	var combined := "\n".join([
		FileAccess.get_file_as_string("res://scripts/gameplay.gd"),
		FileAccess.get_file_as_string("res://scripts/app_root.gd"),
		FileAccess.get_file_as_string("res://scripts/ui/result_panel.gd"),
		FileAccess.get_file_as_string("res://scenes/gameplay.tscn"),
		FileAccess.get_file_as_string("res://scripts/monetization/luma_admob_config.gd"),
	])
	for forbidden in [
		"PLACEMENT_REVIVE", "REWARDED_EXTRA_BALL", "ReviveButton",
		"ReviveCoinButton", "grant_extra_ball", "revive_requested",
	]:
		_check(not combined.contains(forbidden), "revive artifact removed: %s" % forbidden)
	_check(combined.contains("set_fullscreen_ad_active(true)")
		and combined.contains("set_fullscreen_ad_active(false)"),
		"rewarded hint explicitly pauses active-playtime accounting")


func _test_rewarded_hint_only() -> void:
	var entitlements := EntitlementStore.new("user://unused_monetization.cfg")
	entitlements.remove_ads = true
	var provider := MockAdProvider.new()
	var service := AdService.new()
	service.configure(provider, AdPolicy.new(entitlements, "", false),
		AnalyticsService.new(false, true))
	root.add_child(service)
	_check(service.initialize(), "mock provider initializes")
	provider.set_rewarded_ready(MonetizationConfig.PLACEMENT_SHORT_HINT, true)
	provider.queue_rewarded_result(AdResult.Code.EARNED)
	provider.queue_rewarded_result(AdResult.Code.CLOSED_WITHOUT_REWARD)
	_check(int(await service.show_rewarded(MonetizationConfig.PLACEMENT_SHORT_HINT))
		== AdResult.Code.EARNED,
		"TEST I: remove_ads owner may voluntarily earn rewarded hint")
	_check(int(await service.show_rewarded(MonetizationConfig.PLACEMENT_SHORT_HINT))
		== AdResult.Code.CLOSED_WITHOUT_REWARD,
		"cancelled rewarded hint grants no earned result")
	_check(provider.rewarded_calls.size() == 2,
		"rewarded is called only after explicit requests")
	root.remove_child(service)
	service.queue_free()
	await process_frame


func _test_interstitial_service() -> void:
	var policy := _policy()
	for id in range(1, 4):
		policy.register_successful_completion("level_%03d" % id)
	var provider := MockAdProvider.new()
	var service := AdService.new()
	service.configure(provider, policy, AnalyticsService.new(false, true))
	root.add_child(service)
	service.initialize()
	_check(provider.interstitial_calls.is_empty(),
		"TEST M: initialization never opens an interstitial")
	_check(int(await service.request_interstitial(
		MonetizationConfig.CONTEXT_LEVEL_COMPLETE, 4000.0)) == AdResult.Code.UNAVAILABLE,
		"TEST C: unloaded ad returns immediately")
	_check(bool(policy.debug_snapshot()["completion_pending"]),
		"unloaded ad keeps candidate for a later natural transition")
	provider.set_interstitial_ready(true)
	provider.queue_interstitial_result(AdResult.Code.DISPLAYED)
	_check(int(await service.request_interstitial(
		MonetizationConfig.CONTEXT_LEVEL_COMPLETE, 4000.0)) == AdResult.Code.DISPLAYED,
		"ready completion interstitial displays exactly once")
	_check(provider.interstitial_calls.size() == 1,
		"readiness failure never called provider")
	root.remove_child(service)
	service.queue_free()
	await process_frame


func _test_fullscreen_double_show_guard() -> void:
	var policy := _policy()
	for id in range(1, 4):
		policy.register_successful_completion("level_%03d" % id)
	var provider := MockAdProvider.new()
	provider.set_interstitial_ready(true)
	provider.queue_interstitial_result(AdResult.Code.DISPLAYED)
	provider.queue_interstitial_result(AdResult.Code.DISPLAYED)
	var service := AdService.new()
	service.configure(provider, policy, AnalyticsService.new(false, true))
	root.add_child(service)
	service.initialize()
	service.request_interstitial(MonetizationConfig.CONTEXT_LEVEL_COMPLETE, 5000.0)
	service.request_interstitial(MonetizationConfig.CONTEXT_LEVEL_COMPLETE, 5000.0)
	await process_frame
	await process_frame
	await process_frame
	_check(provider.interstitial_calls.size() == 1,
		"duplicate callbacks cannot double-show an interstitial")
	policy.reset_session_state()
	for id in range(1, 4):
		policy.register_successful_completion("level_%03d" % id)
	provider.set_rewarded_ready(MonetizationConfig.PLACEMENT_SHORT_HINT, true)
	provider.queue_rewarded_result(AdResult.Code.EARNED)
	var before := provider.interstitial_calls.size()
	service.show_rewarded(MonetizationConfig.PLACEMENT_SHORT_HINT)
	service.request_interstitial(MonetizationConfig.CONTEXT_LEVEL_COMPLETE, 6000.0)
	await process_frame
	await process_frame
	await process_frame
	_check(provider.interstitial_calls.size() == before,
		"TEST J: rewarded hint and interstitial cannot overlap")
	root.remove_child(service)
	service.queue_free()
	await process_frame


func _test_privacy_options() -> void:
	var provider := MockAdProvider.new()
	provider.privacy_options_available = true
	var service := AdService.new()
	service.configure(provider, _policy(), AnalyticsService.new(false, true))
	root.add_child(service)
	service.initialize()
	_check(service.is_privacy_options_available(), "UMP privacy entry point remains available")
	_check(bool(await service.show_privacy_options()), "privacy options delegates to provider")
	root.remove_child(service)
	service.queue_free()
	await process_frame


func _policy(path := "") -> AdPolicy:
	return AdPolicy.new(
		EntitlementStore.new("user://unused_monetization.cfg"), path, false)


func _new_path(tag: String) -> String:
	var path := "user://monetization_%s_%d.cfg" % [tag, Time.get_ticks_usec()]
	_paths.append(path)
	return path


func _cleanup_paths() -> void:
	for path in _paths:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
