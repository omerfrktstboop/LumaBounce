class_name DailyStore
extends RefCounted

## Daily challenge, uc gunluk gorev ve daily-completion streak kaydi.
##
## ProgressStore'dan AYRI dosyadir: "ilerlemeyi sifirla" claim gecmisini
## silmez ve ayni gun odulunu yeniden vermez. V1 cihaz tarihine guvenir; ancak
## saat geriye alinirsa en son odullu tarihten eski gunler Coin uretemez.

const SAVE_PATH := "user://daily_retention.cfg"
const SECTION_DAILY := "daily"
const SECTION_QUESTS := "quests"
const SECTION_STREAK := "streak"
const DAILY_REWARD := 2
const ALL_QUESTS_REWARD := 2
const CHALLENGE_UNLOCK_LEVEL := 10
const QUESTS_UNLOCK_LEVEL := 8
const DAILY_LEVEL_POOL := [
	6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
	16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
]
const STREAK_REWARDS := {3: 1, 7: 2, 14: 3}

var active_date := ""
var challenge_level_id := DAILY_LEVEL_POOL[0]
var quest_ids := PackedStringArray()
var quest_progress: Dictionary = {}
var completed_quest_ids: Dictionary = {}
var current_streak := 0
var best_streak := 0
var last_daily_completed_date := ""

var _claimed_daily_dates: Dictionary = {}
var _claimed_quest_dates: Dictionary = {}
var _claimed_streak_milestones: Dictionary = {}
var _latest_daily_reward_date := ""
var _latest_quest_reward_date := ""
var _save_path := SAVE_PATH


static func load_from_disk(date_key := "") -> DailyStore:
	return load_from_path(SAVE_PATH, date_key)


static func load_from_path(path: String, date_key := "") -> DailyStore:
	var store := DailyStore.new()
	store._save_path = path
	var config := ConfigFile.new()
	if config.load(path) == OK:
		store._read(config)
	store.refresh_for_date(date_key)
	return store


static func local_date_key() -> String:
	var date := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(date.year), int(date.month), int(date.day)]


static func day_index(date_key: String) -> int:
	var unix := int(Time.get_unix_time_from_datetime_string(date_key + "T12:00:00"))
	return maxi(unix / 86400, 0)


func refresh_for_date(date_key := "") -> bool:
	var wanted := date_key.strip_edges()
	if wanted.is_empty():
		wanted = local_date_key()
	if wanted == active_date and quest_ids.size() == DailyQuestCatalog.QUESTS_PER_DAY:
		return false
	# Seri, kacirilan gunun ardindan ekranda eski degeri gostermemeli. Saat
	# geriye alindiysa burada sifirlamayiz; odul kapisi bunu ayrica engeller.
	if not last_daily_completed_date.is_empty() \
			and day_index(wanted) > day_index(last_daily_completed_date) + 1:
		current_streak = 0
	active_date = wanted
	challenge_level_id = DAILY_LEVEL_POOL[
		DailyQuestCatalog.stable_hash(wanted + ":challenge") % DAILY_LEVEL_POOL.size()]
	quest_ids = DailyQuestCatalog.ids_for_date(wanted)
	quest_progress.clear()
	completed_quest_ids.clear()
	for quest_id in quest_ids:
		quest_progress[quest_id] = 0
	save()
	return true


func is_daily_claimed(date_key := "") -> bool:
	var key := active_date if date_key.is_empty() else date_key
	return _claimed_daily_dates.has(key)


func is_all_quests_claimed(date_key := "") -> bool:
	var key := active_date if date_key.is_empty() else date_key
	return _claimed_quest_dates.has(key)


func quest_progress_for(quest_id: String) -> int:
	return maxi(int(quest_progress.get(quest_id, 0)), 0)


func quest_is_complete(quest_id: String) -> bool:
	return completed_quest_ids.has(quest_id)


func all_quests_complete() -> bool:
	return not quest_ids.is_empty() and completed_quest_ids.size() == quest_ids.size()


func record_bounce(count := 1, date_key := "") -> PackedStringArray:
	refresh_for_date(date_key)
	var completed := PackedStringArray()
	var changed := false
	for quest_id in quest_ids:
		var quest := DailyQuestCatalog.find(quest_id)
		if quest != null and quest.kind == DailyQuestData.Kind.BOUNCES:
			var before := quest_progress_for(quest.id)
			if _advance_quest(quest, maxi(count, 0)):
				completed.append(quest.id)
			changed = changed or quest_progress_for(quest.id) != before
	if changed:
		save()
	return completed


func record_bonus_attempt(date_key := "") -> PackedStringArray:
	refresh_for_date(date_key)
	var completed := PackedStringArray()
	for quest_id in quest_ids:
		var quest := DailyQuestCatalog.find(quest_id)
		if quest != null and quest.kind == DailyQuestData.Kind.BONUS_ATTEMPT:
			if _advance_quest(quest, 1):
				completed.append(quest.id)
	save()
	return completed


func record_level_completion(stars: int, shots: int, full_hint_used: bool,
		date_key := "") -> PackedStringArray:
	refresh_for_date(date_key)
	var completed := PackedStringArray()
	for quest_id in quest_ids:
		var quest := DailyQuestCatalog.find(quest_id)
		if quest == null:
			continue
		var amount := 0
		match quest.kind:
			DailyQuestData.Kind.COMPLETE_LEVELS:
				amount = 1
			DailyQuestData.Kind.ONE_SHOT:
				amount = 1 if shots <= 1 else 0
			DailyQuestData.Kind.THREE_STAR:
				amount = 1 if stars >= LevelData.NORMAL_MAX_STARS else 0
			DailyQuestData.Kind.NO_FULL_HINT:
				amount = 1 if not full_hint_used else 0
		if amount > 0 and _advance_quest(quest, amount):
			completed.append(quest.id)
	save()
	return completed


func complete_daily(date_key := "") -> Dictionary:
	refresh_for_date(date_key)
	if is_daily_claimed(active_date) or _is_rollback(active_date, _latest_daily_reward_date):
		return {"first_completion": false, "reward": 0, "streak": current_streak,
			"milestone": 0, "milestone_reward": 0, "blocked_by_clock": true}

	_claimed_daily_dates[active_date] = true
	_latest_daily_reward_date = active_date
	var today := day_index(active_date)
	var previous := day_index(last_daily_completed_date) if not last_daily_completed_date.is_empty() else -1
	current_streak = current_streak + 1 if previous >= 0 and today == previous + 1 else 1
	best_streak = maxi(best_streak, current_streak)
	last_daily_completed_date = active_date

	var milestone := current_streak if STREAK_REWARDS.has(current_streak) else 0
	var milestone_reward := 0
	if milestone > 0 and not _claimed_streak_milestones.has(str(milestone)):
		_claimed_streak_milestones[str(milestone)] = true
		milestone_reward = int(STREAK_REWARDS[milestone])
	save()
	return {
		"first_completion": true,
		"reward": DAILY_REWARD + milestone_reward,
		"daily_reward": DAILY_REWARD,
		"streak": current_streak,
		"milestone": milestone,
		"milestone_reward": milestone_reward,
		"cosmetic_hook": "streak_%d" % milestone if milestone > 0 else "",
		"blocked_by_clock": false,
	}


func claim_all_quests_reward(date_key := "") -> int:
	refresh_for_date(date_key)
	if not all_quests_complete() or is_all_quests_claimed(active_date):
		return 0
	if _is_rollback(active_date, _latest_quest_reward_date):
		return 0
	_claimed_quest_dates[active_date] = true
	_latest_quest_reward_date = active_date
	save()
	return ALL_QUESTS_REWARD


func save() -> Error:
	var config := ConfigFile.new()
	config.set_value(SECTION_DAILY, "active_date", active_date)
	config.set_value(SECTION_DAILY, "challenge_level_id", challenge_level_id)
	config.set_value(SECTION_DAILY, "claimed_dates", _sorted_keys(_claimed_daily_dates))
	config.set_value(SECTION_DAILY, "latest_reward_date", _latest_daily_reward_date)
	config.set_value(SECTION_QUESTS, "ids", quest_ids)
	config.set_value(SECTION_QUESTS, "progress", quest_progress)
	config.set_value(SECTION_QUESTS, "completed", _sorted_keys(completed_quest_ids))
	config.set_value(SECTION_QUESTS, "claimed_dates", _sorted_keys(_claimed_quest_dates))
	config.set_value(SECTION_QUESTS, "latest_reward_date", _latest_quest_reward_date)
	config.set_value(SECTION_STREAK, "current", current_streak)
	config.set_value(SECTION_STREAK, "best", best_streak)
	config.set_value(SECTION_STREAK, "last_date", last_daily_completed_date)
	config.set_value(SECTION_STREAK, "claimed_milestones", _sorted_keys(
		_claimed_streak_milestones))
	var error := config.save(_save_path)
	if error != OK:
		push_warning("DailyStore: retention kaydi yazilamadi (hata %d)." % error)
	return error


func _advance_quest(quest: DailyQuestData, amount: int) -> bool:
	if amount <= 0 or completed_quest_ids.has(quest.id):
		return false
	var value := mini(quest_progress_for(quest.id) + amount, quest.target)
	quest_progress[quest.id] = value
	if value < quest.target:
		return false
	completed_quest_ids[quest.id] = true
	return true


func _is_rollback(date_key: String, latest_key: String) -> bool:
	return not latest_key.is_empty() and day_index(date_key) <= day_index(latest_key)


func _read(config: ConfigFile) -> void:
	active_date = String(config.get_value(SECTION_DAILY, "active_date", ""))
	challenge_level_id = int(config.get_value(
		SECTION_DAILY, "challenge_level_id", DAILY_LEVEL_POOL[0]))
	_read_set(config.get_value(SECTION_DAILY, "claimed_dates", []), _claimed_daily_dates)
	_latest_daily_reward_date = String(config.get_value(
		SECTION_DAILY, "latest_reward_date", ""))
	var raw_ids: Variant = config.get_value(SECTION_QUESTS, "ids", PackedStringArray())
	if raw_ids is Array or raw_ids is PackedStringArray:
		quest_ids = PackedStringArray(raw_ids)
	var raw_progress: Variant = config.get_value(SECTION_QUESTS, "progress", {})
	if raw_progress is Dictionary:
		quest_progress = (raw_progress as Dictionary).duplicate(true)
	_read_set(config.get_value(SECTION_QUESTS, "completed", []), completed_quest_ids)
	_read_set(config.get_value(SECTION_QUESTS, "claimed_dates", []), _claimed_quest_dates)
	_latest_quest_reward_date = String(config.get_value(
		SECTION_QUESTS, "latest_reward_date", ""))
	current_streak = maxi(int(config.get_value(SECTION_STREAK, "current", 0)), 0)
	best_streak = maxi(int(config.get_value(SECTION_STREAK, "best", 0)), current_streak)
	last_daily_completed_date = String(config.get_value(SECTION_STREAK, "last_date", ""))
	_read_set(config.get_value(SECTION_STREAK, "claimed_milestones", []),
		_claimed_streak_milestones)


func _read_set(raw: Variant, output: Dictionary) -> void:
	output.clear()
	if not (raw is Array or raw is PackedStringArray):
		return
	for value in raw:
		var key := String(value).strip_edges()
		if not key.is_empty():
			output[key] = true


func _sorted_keys(values: Dictionary) -> PackedStringArray:
	var keys := PackedStringArray(values.keys())
	keys.sort()
	return keys
