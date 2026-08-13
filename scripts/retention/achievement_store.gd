class_name AchievementStore
extends RefCounted

## Achievement sayaçlari ayri dosyada tutulur. Campaign reset'i acilan
## basarilari/odulleri geri almaz ve ayni esik ikinci kez Coin vermez.

const SAVE_PATH := "user://achievements.cfg"
const SECTION := "achievements"

var counters := {
	"one_shots": 0,
	"campaign_completions": 0,
	"bounces": 0,
	"three_stars": 0,
	"worlds_unlocked": 0,
}
var _one_shot_keys: Dictionary = {}
var _three_star_keys: Dictionary = {}
var _unlocked: Dictionary = {}
var _save_path := SAVE_PATH


static func load_from_disk() -> AchievementStore:
	return load_from_path(SAVE_PATH)


static func load_from_path(path: String) -> AchievementStore:
	var store := AchievementStore.new()
	store._save_path = path
	var config := ConfigFile.new()
	if config.load(path) == OK:
		store._read(config)
	return store


func record_bounce(count := 1) -> Array[Dictionary]:
	if count <= 0:
		return []
	counters["bounces"] = int(counters.get("bounces", 0)) + count
	var unlocked := _evaluate()
	# Her sekmede disk yazmak yerine besli paketler; unlock aninda her zaman yazar.
	if not unlocked.is_empty() or int(counters["bounces"]) % 5 == 0:
		save()
	return unlocked


func record_completion(completion_key: String, campaign_completed_count: int,
		shots: int, stars: int, all_worlds_unlocked: bool) -> Array[Dictionary]:
	var clean_key := completion_key.strip_edges()
	if shots <= 1 and not clean_key.is_empty():
		_one_shot_keys[clean_key] = true
	if stars >= LevelData.NORMAL_MAX_STARS and not clean_key.is_empty():
		_three_star_keys[clean_key] = true
	counters["one_shots"] = _one_shot_keys.size()
	counters["three_stars"] = _three_star_keys.size()
	counters["campaign_completions"] = maxi(
		int(counters.get("campaign_completions", 0)), campaign_completed_count)
	if all_worlds_unlocked:
		counters["worlds_unlocked"] = 1
	var unlocked := _evaluate()
	save()
	return unlocked


func sync_campaign(progress: ProgressStore) -> Array[Dictionary]:
	if progress == null:
		return []
	counters["campaign_completions"] = maxi(
		int(counters.get("campaign_completions", 0)), progress.completed_levels.size())
	var final_world_start := LevelWorlds.first_level(LevelWorlds.count() - 1)
	if progress.is_unlocked(final_world_start):
		counters["worlds_unlocked"] = 1
	var unlocked := _evaluate()
	save()
	return unlocked


func is_unlocked(achievement_id: String) -> bool:
	return _unlocked.has(achievement_id)


func progress_for(achievement: AchievementData) -> int:
	if achievement == null:
		return 0
	return clampi(int(counters.get(achievement.counter_key, 0)), 0, achievement.target)


func unlocked_count() -> int:
	return _unlocked.size()


func save() -> Error:
	var config := ConfigFile.new()
	config.set_value(SECTION, "counters", counters)
	config.set_value(SECTION, "one_shot_keys", _sorted_keys(_one_shot_keys))
	config.set_value(SECTION, "three_star_keys", _sorted_keys(_three_star_keys))
	config.set_value(SECTION, "unlocked", _sorted_keys(_unlocked))
	var error := config.save(_save_path)
	if error != OK:
		push_warning("AchievementStore: kayit yazilamadi (hata %d)." % error)
	return error


func _evaluate() -> Array[Dictionary]:
	var newly_unlocked: Array[Dictionary] = []
	for achievement in AchievementCatalog.all():
		if _unlocked.has(achievement.id):
			continue
		if progress_for(achievement) < achievement.target:
			continue
		_unlocked[achievement.id] = true
		newly_unlocked.append({
			"id": achievement.id,
			"title_key": achievement.title_key,
			"coin_reward": achievement.coin_reward,
		})
	return newly_unlocked


func _read(config: ConfigFile) -> void:
	var raw_counters: Variant = config.get_value(SECTION, "counters", {})
	if raw_counters is Dictionary:
		for key in counters.keys():
			var value: Variant = (raw_counters as Dictionary).get(key, counters[key])
			if value is int or value is float:
				counters[key] = maxi(int(value), 0)
	_read_set(config.get_value(SECTION, "one_shot_keys", []), _one_shot_keys)
	_read_set(config.get_value(SECTION, "three_star_keys", []), _three_star_keys)
	_read_set(config.get_value(SECTION, "unlocked", []), _unlocked)


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
