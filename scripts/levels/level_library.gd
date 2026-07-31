class_name LevelLibrary
extends RefCounted

## Bolum kaynaklarina tek erisim noktasi.
##
## Gecersiz bolum numarasi, eksik dosya veya dogrulamadan gecmeyen veri
## durumunda level_01 guvenli varsayilan olarak kullanilir; oyun asla
## bos/bozuk bir bolumle acilmaz.

const FIRST_LEVEL_ID := 1
const LEVEL_COUNT := 20
const PATH_FORMAT := "res://levels/level_%02d.tres"


static func last_level_id() -> int:
	return FIRST_LEVEL_ID + LEVEL_COUNT - 1


static func is_valid_id(level_id: int) -> bool:
	return level_id >= FIRST_LEVEL_ID and level_id <= last_level_id()


static func clamp_id(level_id: int) -> int:
	return clampi(level_id, FIRST_LEVEL_ID, last_level_id())


static func has_next(level_id: int) -> bool:
	return is_valid_id(level_id + 1)


static func level_path(level_id: int) -> String:
	return PATH_FORMAT % level_id


## Istenen bolumu yukler. Bulunamaz veya gecersizse level_01'e, o da
## yuklenemezse bos ama calisir bir varsayilana duser.
static func load_level(level_id: int, play_rect := LevelData.DEFAULT_PLAY_RECT) -> LevelData:
	var wanted := level_id
	if not is_valid_id(wanted):
		push_warning("LevelLibrary: gecersiz bolum numarasi %d, level_01 kullanilacak." % wanted)
		wanted = FIRST_LEVEL_ID

	var level := _load_validated(wanted, play_rect)
	if level != null:
		return level

	if wanted != FIRST_LEVEL_ID:
		level = _load_validated(FIRST_LEVEL_ID, play_rect)
		if level != null:
			return level

	push_error("LevelLibrary: level_01 yuklenemedi, bos varsayilan bolum uretildi.")
	return LevelData.new()


static func _load_validated(level_id: int, play_rect: Rect2) -> LevelData:
	var path := level_path(level_id)
	if not ResourceLoader.exists(path):
		push_warning("LevelLibrary: %s bulunamadi." % path)
		return null

	var level := load(path) as LevelData
	if level == null:
		push_warning("LevelLibrary: %s bir LevelData degil." % path)
		return null

	var problems := level.validate(play_rect)
	if not problems.is_empty():
		push_warning("LevelLibrary: %s gecersiz -> %s" % [path, ", ".join(problems)])
		return null

	return level
