extends SceneTree

## FAZ 2 SDK-bagimsiz monetization sozlesmesi. Network, SDK veya gercek
## user://entitlements.cfg kullanmaz; Mock provider sonuclari deterministiktir.

var _failures := 0
var _cache_path := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_config_and_analytics_contract()
	_test_entitlement_cache()
	_test_policy_cadence()
	_test_policy_cooldowns()
	_test_policy_remove_ads()
	_test_admob_config()
	await _test_rewarded_results()
	await _test_interstitial_results()
	await _test_privacy_options()
	_cleanup_cache()
	if _failures == 0:
		print("PASS monetization phase 2: provider results, policy, cache, analytics")
		quit(0)
	else:
		push_error("FAIL monetization phase 2: %d assertion(s)" % _failures)
		quit(1)


func _test_config_and_analytics_contract() -> void:
	var expected := [
		&"session_start", &"level_start", &"level_complete", &"level_fail",
		&"hint_offer_open", &"hint_short_requested", &"hint_full_unlocked",
		&"rewarded_offer", &"rewarded_result", &"interstitial_result", &"iap_result",
	]
	for event_name in expected:
		_check(AnalyticsService.NORMALIZED_EVENTS.has(event_name),
			"normalized event exists: %s" % event_name)
	var analytics := AnalyticsService.new(false, true)
	_check(analytics.track_event(AnalyticsService.IAP_RESULT, {"result": "unavailable"}),
		"normalized event is accepted")
	_check(analytics.captured_events().size() == 1, "analytics capture stays deterministic")


func _test_admob_config() -> void:
	_check(LumaAdmobConfig.ANDROID_APP_ID.begins_with("ca-app-pub-")
		and LumaAdmobConfig.ANDROID_APP_ID.contains("~"), "AdMob application ID shape")
	_check(LumaAdmobConfig.REWARDED_EXTRA_BALL != LumaAdmobConfig.REWARDED_SHORT_HINT,
		"rewarded placements use separate production units")
	_check(LumaAdmobConfig.rewarded_unit_id(MonetizationConfig.PLACEMENT_SHORT_HINT)
		== LumaAdmobConfig.TEST_REWARDED, "debug short hint uses Google test unit")
	_check(LumaAdmobConfig.rewarded_unit_id(MonetizationConfig.PLACEMENT_REVIVE)
		== LumaAdmobConfig.TEST_REWARDED, "debug extra ball uses Google test unit")
	_check(LumaAdmobConfig.interstitial_unit_id() == LumaAdmobConfig.TEST_INTERSTITIAL,
		"debug interstitial uses Google test unit")


func _test_entitlement_cache() -> void:
	_cache_path = "user://entitlements_phase2_%d.cfg" % Time.get_ticks_usec()
	var store := EntitlementStore.load_from_path(_cache_path)
	_check(not store.remove_ads, "remove_ads defaults to false")
	_check(store.update_remove_ads(true, 1234.0), "entitlement cache saves")
	var reloaded := EntitlementStore.load_from_path(_cache_path)
	_check(reloaded.remove_ads, "remove_ads survives cache reload")
	_check(is_equal_approx(reloaded.verified_at_unix, 1234.0),
		"entitlement verification time survives reload")


func _test_policy_cadence() -> void:
	var policy := AdPolicy.new(EntitlementStore.new("user://unused_phase2.cfg"))
	for completed in range(1, 6):
		_check(not policy.register_successful_completion(completed),
			"first five normal completions are protected (%d)" % completed)
	for completed in range(6, 9):
		_check(not policy.register_successful_completion(completed),
			"completion is not fourth candidate (%d)" % completed)
	_check(policy.register_successful_completion(9),
		"ninth total completion is the fourth post-protection candidate")
	_check(not policy.register_successful_completion(10, false),
		"bonus completion is never an interstitial candidate")


func _test_policy_cooldowns() -> void:
	var policy := AdPolicy.new(EntitlementStore.new("user://unused_phase2.cfg"))
	var context := MonetizationConfig.CONTEXT_LEVEL_COMPLETE
	_check(policy.can_show_interstitial(context, true, 1000.0),
		"eligible completion can show interstitial")
	policy.record_interstitial_shown(1000.0)
	_check(not policy.can_show_interstitial(context, true, 1179.9),
		"interstitial 180-second cooldown blocks early show")
	_check(policy.can_show_interstitial(context, true, 1180.0),
		"interstitial cooldown expires at 180 seconds")
	policy.reset_session_state()
	policy.record_rewarded_shown(2000.0)
	_check(not policy.can_show_interstitial(context, true, 2119.9),
		"rewarded suppresses interstitial for 120 seconds")
	_check(policy.can_show_interstitial(context, true, 2120.0),
		"rewarded suppression expires at 120 seconds")
	_check(not policy.can_show_interstitial(MonetizationConfig.CONTEXT_LEVEL_FAIL, true, 2200.0),
		"failure never shows interstitial")
	_check(not policy.can_show_interstitial(MonetizationConfig.CONTEXT_RETRY, true, 2200.0),
		"retry never shows interstitial")


func _test_policy_remove_ads() -> void:
	var entitlements := EntitlementStore.new("user://unused_phase2.cfg")
	entitlements.remove_ads = true
	var policy := AdPolicy.new(entitlements)
	_check(not policy.register_successful_completion(20),
		"remove_ads disables cadence candidates")
	_check(not policy.can_show_interstitial(
		MonetizationConfig.CONTEXT_LEVEL_COMPLETE, true, 3000.0),
		"remove_ads disables interstitial entirely")


func _test_rewarded_results() -> void:
	var entitlements := EntitlementStore.new("user://unused_phase2.cfg")
	var analytics := AnalyticsService.new(false, true)
	var provider := MockAdProvider.new()
	var service := AdService.new()
	service.configure(provider, AdPolicy.new(entitlements), analytics)
	root.add_child(service)
	_check(service.initialize(), "mock provider initializes")
	var placement := MonetizationConfig.PLACEMENT_SHORT_HINT
	provider.set_rewarded_ready(placement, true)
	provider.queue_rewarded_result(AdResult.Code.EARNED)
	provider.queue_rewarded_result(AdResult.Code.CLOSED_WITHOUT_REWARD)
	provider.queue_rewarded_result(AdResult.Code.FAILED)
	_check(int(await service.show_rewarded(placement)) == AdResult.Code.EARNED,
		"rewarded earned result is preserved")
	_check(int(await service.show_rewarded(placement)) == AdResult.Code.CLOSED_WITHOUT_REWARD,
		"rewarded cancelled result is preserved")
	_check(int(await service.show_rewarded(placement)) == AdResult.Code.FAILED,
		"rewarded failed result is preserved")
	provider.set_rewarded_ready(placement, false)
	_check(int(await service.show_rewarded(placement)) == AdResult.Code.UNAVAILABLE,
		"rewarded unavailable returns immediately")
	_check(provider.rewarded_calls.size() == 3,
		"unavailable rewarded never calls provider show")

	# No-ads yalnizca zorunlu fullscreen'i kapatir; istege bagli rewarded kalir.
	entitlements.remove_ads = true
	provider.set_rewarded_ready(placement, true)
	provider.queue_rewarded_result(AdResult.Code.EARNED)
	_check(service.is_rewarded_ready(placement), "remove_ads keeps voluntary rewarded ready")
	_check(int(await service.show_rewarded(placement)) == AdResult.Code.EARNED,
		"remove_ads user can voluntarily earn rewarded result")
	_check(analytics.captured_events().size() == 10,
		"every rewarded request emits offer and result analytics")
	root.remove_child(service)
	service.queue_free()
	await process_frame


func _test_interstitial_results() -> void:
	var analytics := AnalyticsService.new(false, true)
	var provider := MockAdProvider.new()
	var policy := AdPolicy.new(EntitlementStore.new("user://unused_phase2.cfg"))
	var service := AdService.new()
	service.configure(provider, policy, analytics)
	root.add_child(service)
	service.initialize()
	provider.set_interstitial_ready(true)
	provider.queue_interstitial_result(AdResult.Code.DISPLAYED)
	_check(int(await service.maybe_show_interstitial(
		MonetizationConfig.CONTEXT_LEVEL_COMPLETE, true, 4000.0)) == AdResult.Code.DISPLAYED,
		"eligible interstitial displayed result is preserved")
	_check(int(await service.maybe_show_interstitial(
		MonetizationConfig.CONTEXT_RETRY, true, 5000.0)) == AdResult.Code.SKIPPED_POLICY,
		"retry candidate is rejected before provider")
	provider.set_interstitial_ready(false)
	policy.reset_session_state()
	_check(int(await service.maybe_show_interstitial(
		MonetizationConfig.CONTEXT_LEVEL_COMPLETE, true, 6000.0)) == AdResult.Code.UNAVAILABLE,
		"unready interstitial never delays gameplay")
	_check(provider.interstitial_calls.size() == 1,
		"policy and readiness failures never call provider show")
	root.remove_child(service)
	service.queue_free()
	await process_frame


func _cleanup_cache() -> void:
	if _cache_path.is_empty():
		return
	var absolute := ProjectSettings.globalize_path(_cache_path)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)


func _test_privacy_options() -> void:
	var provider := MockAdProvider.new()
	provider.privacy_options_available = true
	var service := AdService.new()
	service.configure(
		provider,
		AdPolicy.new(EntitlementStore.new("user://unused_phase2.cfg")),
		AnalyticsService.new(false, true))
	root.add_child(service)
	service.initialize()
	_check(service.is_privacy_options_available(), "privacy entry point follows provider")
	_check(bool(await service.show_privacy_options()), "privacy options result is preserved")
	_check(provider.privacy_options_calls == 1, "privacy options delegates once")
	root.remove_child(service)
	service.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
