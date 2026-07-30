class_name ProgressStore
extends RefCounted

## Oyuncu ilerlemesi: user://save.cfg.
##
## Yalnizca iki sey saklanir - acilan en yuksek bolum ve tamamlananlar.
## Dosya yoksa, bozuksa veya beklenmeyen tipler iceriyorsa sessizce
## varsayilana (yalnizca bolum 1 acik) donulur; oyun hicbir durumda
## kayit yuzunden acilmaz olmaz.

const SAVE_PATH := "user://save.cfg"
const SECTION := "progress"
const KEY_HIGHEST := "highest_unlocked_level"
const KEY_COMPLETED := "completed_levels"

var highest_unlocked_level := LevelLibrary.FIRST_LEVEL_ID
var completed_levels: Array[int] = []


static func load_from_disk() -> ProgressStore:
	var store := ProgressStore.new()
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return store
	store._read(config)
	return store


func save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, KEY_HIGHEST, highest_unlocked_level)
	config.set_value(SECTION, KEY_COMPLETED, completed_levels)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("ProgressStore: kayit yazilamadi (hata %d)." % error)


func is_unlocked(level_id: int) -> bool:
	return LevelLibrary.is_valid_id(level_id) and level_id <= highest_unlocked_level


func is_completed(level_id: int) -> bool:
	return completed_levels.has(level_id)


## Bolumu tamamlanmis isaretler ve varsa sonrakini acar.
func mark_completed(level_id: int) -> void:
	if not LevelLibrary.is_valid_id(level_id):
		return
	if not completed_levels.has(level_id):
		completed_levels.append(level_id)
		completed_levels.sort()
	if LevelLibrary.has_next(level_id):
		highest_unlocked_level = maxi(highest_unlocked_level, level_id + 1)
	save()


func reset() -> void:
	highest_unlocked_level = LevelLibrary.FIRST_LEVEL_ID
	completed_levels.clear()
	save()


## Beklenmeyen tip veya aralik disi deger gelirse o alan varsayilanda birakilir.
func _read(config: ConfigFile) -> void:
	var raw_highest: Variant = config.get_value(SECTION, KEY_HIGHEST, LevelLibrary.FIRST_LEVEL_ID)
	if raw_highest is int or raw_highest is float:
		highest_unlocked_level = LevelLibrary.clamp_id(int(raw_highest))

	var raw_completed: Variant = config.get_value(SECTION, KEY_COMPLETED, [])
	if raw_completed is Array:
		for value in (raw_completed as Array):
			if not (value is int or value is float):
				continue
			var id := int(value)
			if LevelLibrary.is_valid_id(id) and not completed_levels.has(id):
				completed_levels.append(id)
		completed_levels.sort()
