class_name PlaytestStats
extends RefCounted

## Yerel, tamamen cihaz-ici playtest sayaclari: user://playtest_stats.cfg.
##
## Harici analytics veya internet baglantisi YOK. Sadece debug build'lerde
## anlamlidir: her record_*/save cagrisi, release export'ta OS.is_debug_build()
## false oldugu icin sessizce hicbir sey yapmaz. Bu sayede Gameplay.gd
## build turunu hic bilmeden bu metodlari kosulsuz cagirabilir - "debug kodu
## oynanis mantigindan ayri tutulsun" kurali boylece saglanir.

const SAVE_PATH := "user://playtest_stats.cfg"


## level_id -> LevelPlaytestEntry, LevelLibrary.FIRST_LEVEL_ID'den baslar.
var _entries: Array[LevelPlaytestEntry] = []


static func load_from_disk() -> PlaytestStats:
	var stats := PlaytestStats.new()
	stats._entries = _make_empty_entries()
	if not OS.is_debug_build():
		return stats

	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return stats

	for level_id in range(LevelLibrary.FIRST_LEVEL_ID, LevelLibrary.last_level_id() + 1):
		stats._entry_for(level_id).load_from(config, _section(level_id))
	return stats


static func _make_empty_entries() -> Array[LevelPlaytestEntry]:
	var entries: Array[LevelPlaytestEntry] = []
	for _i in LevelLibrary.LEVEL_COUNT:
		entries.append(LevelPlaytestEntry.new())
	return entries


static func _section(level_id: int) -> String:
	return "level_%02d" % level_id


func get_entry(level_id: int) -> LevelPlaytestEntry:
	return _entry_for(level_id)


func get_entry_snapshot(level_id: int) -> Dictionary:
	if not OS.is_debug_build():
		return {}
	return _entry_for(level_id).to_dictionary()


# --- Kayit noktalari ----------------------------------------------------------
#
# Her biri bir Gameplay yasam-dongusu olayina karsilik gelir ve kendi
# icinde save() cagirir; gameplay.gd bunlari kosulsuz cagirir.

func record_entry(level_id: int) -> void:
	if not OS.is_debug_build():
		return
	_entry_for(level_id).entries += 1
	save()


func record_restart(level_id: int) -> void:
	if not OS.is_debug_build():
		return
	_entry_for(level_id).restarts += 1
	save()


func record_shot(level_id: int) -> void:
	if not OS.is_debug_build():
		return
	_entry_for(level_id).total_shots += 1
	save()


func record_failure(level_id: int, reason: String) -> void:
	if not OS.is_debug_build():
		return
	_entry_for(level_id).record_failure(reason)
	save()


func record_completion(level_id: int, shots_used: int, elapsed_seconds: float) -> void:
	if not OS.is_debug_build():
		return
	_entry_for(level_id).record_completion(shots_used, elapsed_seconds)
	save()


func add_time_spent(level_id: int, seconds: float) -> void:
	if not OS.is_debug_build() or seconds <= 0.0:
		return
	_entry_for(level_id).total_time_seconds += seconds
	save()


func reset_all() -> void:
	_entries = _make_empty_entries()
	if OS.is_debug_build():
		save()


func save() -> void:
	if not OS.is_debug_build():
		return
	var config := ConfigFile.new()
	for level_id in range(LevelLibrary.FIRST_LEVEL_ID, LevelLibrary.last_level_id() + 1):
		_entry_for(level_id).save_to(config, _section(level_id))
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("PlaytestStats: kayit yazilamadi (hata %d)." % error)


func _entry_for(level_id: int) -> LevelPlaytestEntry:
	var index := level_id - LevelLibrary.FIRST_LEVEL_ID
	if index < 0 or index >= _entries.size():
		# Gecersiz bolum numarasi: kaybolabilir bir tekil giris don, kaydetme.
		return LevelPlaytestEntry.new()
	return _entries[index]
