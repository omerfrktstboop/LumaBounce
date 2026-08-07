class_name LevelLibrary
extends RefCounted

## Bolum kaynaklarina tek erisim noktasi.
##
## Gecersiz bolum numarasi, eksik dosya veya dogrulamadan gecmeyen veri
## durumunda level_01 guvenli varsayilan olarak kullanilir; oyun asla
## bos/bozuk bir bolumle acilmaz.

const FIRST_LEVEL_ID := 1
const LEVEL_COUNT := 125
const PATH_FORMAT := "res://levels/level_%02d.tres"

## Yildiz kapilari: bolum_id -> o bolumun acilmasi icin gereken yildiz sayisi.
## Sirali ilerlemeye EK bir kosuldur (bkz. ProgressStore.is_unlocked).
##
## Sayim her zaman kapinin ONUNDEKI bolumlerden yapilir (bkz.
## ProgressStore.get_stars_before): 21'in kapisi 1-20'yi sayar, 21 sonrasini
## saymaz. Bu kural kapiya ozel bir ayar degil, sistemin tanimidir - ileride
## eklenecek her kapi kendiliginden dogru araligi sayar ve bir bolum asla
## kendi kilidini acmaya katkida bulunamaz.
const LEVEL_21_REQUIRED_STARS := 40
const STAR_GATES := {
	21: LEVEL_21_REQUIRED_STARS,
}


## Bolumun acilmasi icin gereken yildiz; kapisi yoksa 0.
static func required_stars_for(level_id: int) -> int:
	return int(STAR_GATES.get(level_id, 0))


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


## uid -> bolum numarasi ("level_027" -> 27). Taninmayan bicimde -1 doner,
## boylece cagiran (kayit okuyucusu) girisi sessizce atlar.
##
## Bugun uid'ler numaradan turetildigi icin cevrim saf metin islemidir ve
## 125 dosyayi acmak gerekmez. Ileride bir bolume numarasindan BAGIMSIZ bir
## uid verilirse burasi bir indeks tablosuna bakacak sekilde genisletilmeli;
## cagiranlarin hicbiri degismek zorunda kalmaz.
static func number_for_uid(uid: String) -> int:
	var clean := uid.strip_edges()
	if not clean.begins_with("level_"):
		return -1
	var digits := clean.substr(6)
	if digits.is_empty() or not digits.is_valid_int():
		return -1
	return int(digits)


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
