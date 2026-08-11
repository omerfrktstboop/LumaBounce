extends SceneTree

## Faz 10: normalize sozlesme, gizlilik filtresi, ertelenmis provider ve
## resmi GameAnalytics adaptorunu network olmadan deterministik dogrular.

var _failures := 0
var _config_path := ""


class FakeGameAnalytics:
	extends RefCounted
	var calls: Array[Dictionary] = []

	func useRandomizedId(value: bool) -> void:
		calls.append({"method": "useRandomizedId", "value": value})

	func configureBuild(value: String) -> void:
		calls.append({"method": "configureBuild", "value": value})

	func setEnabledErrorReporting(value: bool) -> void:
		calls.append({"method": "setEnabledErrorReporting", "value": value})

	func setEnabledEventSubmission(value: bool) -> void:
		calls.append({"method": "setEnabledEventSubmission", "value": value})

	func init(game_key: String, secret_key: String) -> void:
		calls.append({"method": "init", "game_key": game_key, "secret_key": secret_key})

	func addProgressionEvent(status: String, world: String, level: String,
			phase: String, options: Dictionary) -> void:
		calls.append({
			"method": "addProgressionEvent", "status": status, "world": world,
			"level": level, "phase": phase, "options": options,
		})

	func addDesignEvent(event_id: String, options: Dictionary) -> void:
		calls.append({"method": "addDesignEvent", "event_id": event_id, "options": options})


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_contract_and_privacy()
	await _test_deferred_provider_and_fallback()
	_test_buckets()
	_test_gameanalytics_adapter()
	_test_config_guards()
	_cleanup()
	if _failures == 0:
		print("PASS analytics phase 10: contract, privacy, async provider, GA adapter")
		quit(0)
	else:
		push_error("FAIL analytics phase 10: %d assertion(s)" % _failures)
		quit(1)


func _test_contract_and_privacy() -> void:
	var expected := [
		AnalyticsService.SESSION_START, AnalyticsService.SESSION_END,
		AnalyticsService.LEVEL_START, AnalyticsService.LEVEL_COMPLETE,
		AnalyticsService.LEVEL_FAIL, AnalyticsService.RESTART,
		AnalyticsService.HINT_OFFER_OPEN, AnalyticsService.SHORT_HINT_REWARDED_EARNED,
		AnalyticsService.FULL_HINT_UNLOCK, AnalyticsService.REWARDED_OFFER,
		AnalyticsService.REWARDED_CLICK, AnalyticsService.REWARDED_RESULT,
		AnalyticsService.INTERSTITIAL_CANDIDATE, AnalyticsService.INTERSTITIAL_SHOWN,
		AnalyticsService.INTERSTITIAL_FAILED, AnalyticsService.REMOVE_ADS_PURCHASE_RESULT,
		AnalyticsService.SHOP_OPEN, AnalyticsService.COSMETIC_PURCHASE,
		AnalyticsService.COSMETIC_SELECT, AnalyticsService.DAILY_OPEN,
		AnalyticsService.DAILY_COMPLETE, AnalyticsService.QUEST_COMPLETE,
		AnalyticsService.STREAK_MILESTONE,
	]
	for event_name in expected:
		_check(AnalyticsService.NORMALIZED_EVENTS.has(event_name),
			"event contract includes %s" % event_name)
	var service := AnalyticsService.new(false, true)
	service.track_event(AnalyticsService.LEVEL_COMPLETE, {
		"level_id": 9,
		"world": "WORLD 01",
		"stars": 3,
		"purchase_token": "must-not-leak",
		"email": "player@example.com",
		"advertising_id": "must-not-leak",
		"free_form_error": "stack trace",
	})
	var properties: Dictionary = service.captured_events()[0]["properties"]
	_check(properties.get("level_id") == 9, "allowed level field survives")
	_check(properties.get("world") == "world_01", "string fields become bounded tokens")
	for forbidden in ["purchase_token", "email", "advertising_id", "free_form_error"]:
		_check(not properties.has(forbidden), "privacy filter removes %s" % forbidden)
	_check(not service.track_event(&"raw_sdk_error", {"message": "x"}),
		"unknown event is rejected")


func _test_deferred_provider_and_fallback() -> void:
	var provider := MockAnalyticsProvider.new()
	var service := AnalyticsService.new(false, true)
	service.configure(provider, GameAnalyticsConfig.new())
	_check(service.initialize(), "mock provider initializes")
	service.track_event(AnalyticsService.SHOP_OPEN, {"balance": 12})
	_check(provider.received.is_empty(), "provider call is deferred off gameplay stack")
	await process_frame
	_check(provider.received.size() == 1, "deferred event reaches provider")
	provider.next_send_result = false
	_check(service.track_event(AnalyticsService.SHOP_OPEN, {"balance": 13}),
		"provider failure does not reject gameplay event")
	await process_frame
	_check(provider.received.size() == 2, "failed provider call is contained")

	var broken := MockAnalyticsProvider.new()
	broken.initialize_result = false
	var fallback := AnalyticsService.new(false, true)
	fallback.configure(broken, GameAnalyticsConfig.new())
	_check(fallback.initialize(), "failed provider falls back to NoOp")
	_check(fallback.provider_name() == &"no_op", "fallback provider is explicit")


func _test_buckets() -> void:
	_check(AnalyticsService.seconds_bucket(14.9) == &"0_14", "seconds lower bucket")
	_check(AnalyticsService.seconds_bucket(120.0) == &"120_plus", "seconds upper bucket")
	_check(AnalyticsService.shots_bucket(4) == &"4_5", "shots grouped bucket")
	_check(AnalyticsService.shots_bucket(9) == &"6_plus", "shots capped bucket")
	_check(AnalyticsService.failure_reason("laser") == &"laser", "known failure is retained")
	_check(AnalyticsService.failure_reason("secret raw error") == &"other",
		"unknown failure is bounded")


func _test_gameanalytics_adapter() -> void:
	var api := FakeGameAnalytics.new()
	var config := GameAnalyticsConfig.new()
	config.enabled = true
	config.environment = GameAnalyticsConfig.ENVIRONMENT_STAGING
	config.game_key = "test-game-key"
	config.secret_key = "test-secret-key"
	var provider := GameAnalyticsProvider.new(api)
	_check(provider.initialize(config), "GameAnalytics adapter initializes with injected API")
	_check(api.calls[0].get("method") == "useRandomizedId" and api.calls[0].get("value"),
		"randomized SDK identity is forced")
	_check(api.calls[2].get("method") == "setEnabledErrorReporting"
		and not api.calls[2].get("value"), "raw SDK error reporting is disabled")
	provider.send_event(AnalyticsService.LEVEL_START, {
		"level_id": 12, "world": "world_01", "is_bonus": false,
	})
	provider.send_event(AnalyticsService.SHOP_OPEN, {"balance": 4})
	provider.set_collection_enabled(false)
	_check(api.calls[-2].get("method") == "addDesignEvent"
		and api.calls[-2].get("event_id") == "shop:open", "other event maps to design")
	_check(api.calls[-3].get("method") == "addProgressionEvent"
		and api.calls[-3].get("status") == "start", "level event maps to progression")
	_check(api.calls[-1].get("method") == "setEnabledEventSubmission"
		and not api.calls[-1].get("value"), "analytics consent can stop collection")


func _test_config_guards() -> void:
	_config_path = "user://analytics_phase10_%d.cfg" % Time.get_ticks_usec()
	var file := ConfigFile.new()
	file.set_value("analytics", "enabled", true)
	file.set_value("analytics", "environment", "production")
	file.set_value("analytics", "game_key", "key")
	file.set_value("analytics", "secret_key", "secret")
	file.save(_config_path)
	var debug_config := GameAnalyticsConfig.load_from_path(_config_path, true)
	_check(not debug_config.is_ready()
		and debug_config.rejection_reason == "production_blocked_in_debug",
		"debug build cannot submit to production project")
	var release_config := GameAnalyticsConfig.load_from_path(_config_path, false)
	_check(release_config.is_ready(), "release build may use explicit production config")


func _cleanup() -> void:
	if _config_path.is_empty():
		return
	var absolute := ProjectSettings.globalize_path(_config_path)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
