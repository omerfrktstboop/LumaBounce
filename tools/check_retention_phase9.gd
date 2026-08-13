extends SceneTree

## FAZ 9 retention regresyonlari. Testler yalnizca benzersiz user:// gecici
## dosyalarina yazar; gercek progress/wallet/daily kayitlarina dokunmaz.

var _failures := 0
var _temp_paths: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_catalogs_and_contracts()
	_test_daily_determinism_and_double_claim()
	_test_quest_refresh_and_reward()
	_test_streak_and_clock_safety()
	_test_achievements()
	_cleanup()
	if _failures == 0:
		print("PASS retention phase 9: daily, quests, streak, achievements")
		quit(0)
	else:
		push_error("FAIL retention phase 9: %d assertion(s)" % _failures)
		quit(1)


func _test_catalogs_and_contracts() -> void:
	_check(DailyStore.DAILY_LEVEL_POOL.size() >= 20,
		"daily challenge has at least 20 curated levels")
	for level_id in DailyStore.DAILY_LEVEL_POOL:
		_check(LevelLibrary.is_valid_id(level_id),
			"daily pool level exists: %d" % level_id)
		var level := LevelLibrary.load_level(level_id)
		_check(level != null and level.has_hint(),
			"daily pool level has a verified hint solution: %d" % level_id)
	_check(DailyStore.SAVE_PATH != ProgressStore.SAVE_PATH,
		"daily claims are isolated from campaign reset")
	_check(AchievementStore.SAVE_PATH != ProgressStore.SAVE_PATH,
		"achievements are isolated from campaign reset")
	for event_name in [
		AnalyticsService.DAILY_OPEN,
		AnalyticsService.DAILY_COMPLETE,
		AnalyticsService.DAILY_THREE_STAR,
		AnalyticsService.QUEST_COMPLETE,
		AnalyticsService.ALL_DAILY_QUESTS_COMPLETE,
		AnalyticsService.STREAK_MILESTONE,
		AnalyticsService.ACHIEVEMENT_UNLOCK,
	]:
		_check(AnalyticsService.NORMALIZED_EVENTS.has(event_name),
			"analytics event is normalized: %s" % event_name)
	_check(AchievementCatalog.all().size() == 5,
		"five data-driven v1 achievements exist")


func _test_daily_determinism_and_double_claim() -> void:
	var path := _temp_path("daily_claim")
	var day := "2026-08-10"
	var store := DailyStore.load_from_path(path, day)
	var first_level := store.challenge_level_id
	var first_quests := store.quest_ids.duplicate()
	var campaign := ProgressStore.new()
	campaign.completed_levels = [8, 10]
	var campaign_before := campaign.completed_levels.duplicate()
	var first := store.complete_daily(day)
	_check(int(first.get("daily_reward", 0)) == DailyStore.DAILY_REWARD,
		"first daily completion grants exactly the base reward")
	_check(int(store.complete_daily(day).get("reward", -1)) == 0,
		"same-day daily reward cannot be claimed twice")

	var reloaded := DailyStore.load_from_path(path, day)
	_check(reloaded.challenge_level_id == first_level,
		"same date selects the same challenge after reload")
	_check(reloaded.quest_ids == first_quests,
		"same date selects the same three quests after reload")
	_check(int(reloaded.complete_daily(day).get("reward", -1)) == 0,
		"double claim stays blocked after process restart")
	_check(campaign.completed_levels == campaign_before,
		"daily completion does not mutate campaign progress")


func _test_quest_refresh_and_reward() -> void:
	var path := _temp_path("quests")
	var store := DailyStore.load_from_path(path, "2026-08-11")
	var old_ids := store.quest_ids.duplicate()
	_check(old_ids.size() == DailyQuestCatalog.QUESTS_PER_DAY,
		"exactly three daily quests are selected")
	var unique := {}
	for quest_id in old_ids:
		unique[quest_id] = true
	_check(unique.size() == DailyQuestCatalog.QUESTS_PER_DAY,
		"daily quest selection contains no duplicates")

	# Tum olasi v1 hedeflerini gerceklestir; o gun secilen uclu tamamlanmali.
	store.record_bounce(25, "2026-08-11")
	store.record_bonus_attempt("2026-08-11")
	for _index in 3:
		store.record_level_completion(3, 1, false, "2026-08-11")
	_check(store.all_quests_complete(), "the selected quest trio can be completed")
	_check(store.claim_all_quests_reward("2026-08-11") == DailyStore.ALL_QUESTS_REWARD,
		"all three quests grant one +2 Coin bundle")
	_check(store.claim_all_quests_reward("2026-08-11") == 0,
		"all-quests reward cannot be claimed twice")

	store.refresh_for_date("2026-08-12")
	_check(not store.all_quests_complete(), "new day resets quest progress")
	_check(not store.is_all_quests_claimed(), "new day has a fresh quest claim")
	_check(store.quest_ids == DailyQuestCatalog.ids_for_date("2026-08-12"),
		"new-day quests remain deterministic")


func _test_streak_and_clock_safety() -> void:
	var path := _temp_path("streak")
	var store := DailyStore.load_from_path(path, "2026-08-20")
	_check(int(store.complete_daily("2026-08-20").get("reward", 0)) == 2,
		"streak day 1 grants base reward")
	_check(int(store.complete_daily("2026-08-21").get("streak", 0)) == 2,
		"consecutive date increments streak")
	var day_three := store.complete_daily("2026-08-22")
	_check(int(day_three.get("streak", 0)) == 3,
		"third consecutive date reaches streak 3")
	_check(int(day_three.get("milestone_reward", 0)) == 1,
		"streak 3 milestone grants its one-time v1 reward")
	_check(int(store.complete_daily("2026-08-24").get("streak", 0)) == 1,
		"missed date breaks the streak safely")
	_check(int(store.complete_daily("2026-08-23").get("reward", -1)) == 0,
		"moving the local clock backwards never creates Coin")
	_check(store.current_streak == 1,
		"clock rollback does not corrupt current streak")
	store.refresh_for_date("2026-08-26")
	_check(store.current_streak == 0,
		"opening after another missed date displays a broken streak immediately")


func _test_achievements() -> void:
	var path := _temp_path("achievements")
	var store := AchievementStore.load_from_path(path)
	var unlock_count := 0
	for index in range(1, 11):
		unlock_count += store.record_completion(
			"one:%d" % index, index, 1, 1, false).size()
	_check(store.is_unlocked("one_shot_10"), "ten unique one-shots unlock achievement")
	for index in range(11, 36):
		unlock_count += store.record_completion(
			"star:%d" % index, index, 2, 3, false).size()
	_check(store.is_unlocked("three_star_25"),
		"twenty-five unique three-star completions unlock achievement")
	unlock_count += store.record_bounce(1000).size()
	unlock_count += store.record_completion("campaign:100", 100, 2, 1, true).size()
	_check(store.unlocked_count() == 5, "all five v1 achievements can unlock")
	_check(unlock_count == 5, "each achievement unlocks exactly once")
	_check(store.record_completion("campaign:100", 100, 1, 3, true).is_empty(),
		"unlocked achievement cannot grant its reward again")
	var reloaded := AchievementStore.load_from_path(path)
	_check(reloaded.unlocked_count() == 5,
		"achievement unlocks survive process restart")

func _temp_path(label: String) -> String:
	var path := "user://phase9_%s_%d.cfg" % [label, Time.get_ticks_usec()]
	_temp_paths.append(path)
	return path


func _cleanup() -> void:
	for path in _temp_paths:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
