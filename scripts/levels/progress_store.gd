class_name ProgressStore
extends RefCounted

## Oyuncu ilerlemesi: user://save.cfg.
##
## Uc sey saklanir - acilan en yuksek bolum, tamamlananlar ve bolum basina
## kazanilmis EN YUKSEK yildiz. Dosya yoksa, bozuksa veya beklenmeyen tipler
## iceriyorsa sessizce varsayilana (yalnizca bolum 1 acik, 0 yildiz) donulur;
## oyun hicbir durumda kayit yuzunden acilmaz olmaz.
##
## GERIYE UYUMLULUK: yildiz alani sonradan eklendi. Eski bir kayitta
## level_stars anahtari bulunmaz; bu durumda tamamlanmis bolumler icin yildiz
## TAHMIN EDILMEZ, 0 kabul edilir ve oyuncu tekrar oynayarak kazanabilir.

const SAVE_PATH := "user://save.cfg"
const SECTION := "progress"
const KEY_HIGHEST := "highest_unlocked_level"
const KEY_COMPLETED := "completed_levels"
const KEY_LEVEL_STARS := "level_stars"

const MAX_STARS_PER_LEVEL := 3

var highest_unlocked_level := LevelLibrary.FIRST_LEVEL_ID
var completed_levels: Array[int] = []
## level_id -> kazanilmis en yuksek yildiz (1..3). Yildizi olmayan bolum
## hic anahtar tutmaz; get_level_stars 0 doner.
var level_stars: Dictionary = {}


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
	config.set_value(SECTION, KEY_LEVEL_STARS, level_stars)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("ProgressStore: kayit yazilamadi (hata %d)." % error)


# --- Kilit durumu -------------------------------------------------------------

## Iki kosul BIRLIKTE saglanmali:
##   1) sirali ilerleme - onceki bolum tamamlanmis olmali
##   2) varsa yildiz kapisi - onundeki bolumlerden yeterince yildiz toplanmis olmali
## Bu yuzden 40 yildizi olan ama 20. bolumu bitirmemis oyuncuya 21 acilmaz.
func is_unlocked(level_id: int) -> bool:
	if not LevelLibrary.is_valid_id(level_id):
		return false
	if level_id > highest_unlocked_level:
		return false
	var required := LevelLibrary.required_stars_for(level_id)
	if required <= 0:
		return true
	return get_stars_before(level_id) >= required


## Yildiz kapisi olan bir bolum icin (mevcut, gerekli). Kapi yoksa ikisi de
## 0 doner. Kilitli buton "34 / 40" bilgisini bundan uretir.
func get_star_gate_progress(level_id: int) -> Vector2i:
	var required := LevelLibrary.required_stars_for(level_id)
	if required <= 0:
		return Vector2i.ZERO
	return Vector2i(get_stars_before(level_id), required)


func is_completed(level_id: int) -> bool:
	return completed_levels.has(level_id)


## Ana menudeki "OYNA" butonunun acacagi bolum. highest_unlocked_level tek
## basina YETMEZ: sirali ilerleme 21'i acsa bile yildiz kapisi kapaliysa o
## bolum oynanabilir degildir ve menuden dogrudan girmek kapiyi delerdi.
## Bu yuzden geriye dogru, gercekten acik olan ilk bolume inilir.
func get_resume_level_id() -> int:
	var level_id := LevelLibrary.clamp_id(highest_unlocked_level)
	while level_id > LevelLibrary.FIRST_LEVEL_ID and not is_unlocked(level_id):
		level_id -= 1
	return level_id


# --- Yildizlar ----------------------------------------------------------------

func get_level_stars(level_id: int) -> int:
	var value: Variant = level_stars.get(level_id, 0)
	if value is int or value is float:
		return clampi(int(value), 0, MAX_STARS_PER_LEVEL)
	return 0


## Yalnizca daha iyi sonuc kaydedilir: eski 3, yeni 1 ise kayit 3 kalir.
## Gercekten degistiyse true doner (yeni kisisel rekor).
func set_level_stars_if_higher(level_id: int, stars: int) -> bool:
	if not LevelLibrary.is_valid_id(level_id):
		return false
	var clamped := clampi(stars, 0, MAX_STARS_PER_LEVEL)
	if clamped <= get_level_stars(level_id):
		return false
	level_stars[level_id] = clamped
	save()
	return true


## Tum bolumlerin toplami - bolum secim ekranindaki "N / 105" sayaci.
func get_total_stars() -> int:
	return get_stars_before(LevelLibrary.last_level_id() + 1)


## [param level_id]'den ONCEKI bolumlerin yildiz toplami. Yildiz kapilari
## bunu kullanir: kapinin arkasindaki bolumler kendi kilidini acamaz, yani
## 21-35'te kazanilan yildizlar 21'in 40-yildiz sartina sayilmaz.
func get_stars_before(level_id: int) -> int:
	var total := 0
	for id in range(LevelLibrary.FIRST_LEVEL_ID, level_id):
		total += get_level_stars(id)
	return total


func get_max_available_stars() -> int:
	return LevelLibrary.LEVEL_COUNT * MAX_STARS_PER_LEVEL


# --- Tamamlama ----------------------------------------------------------------

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
	level_stars.clear()
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

	# Eski kayitlarda bu anahtar yok - bos sozluk kalir, yani 0 yildiz.
	var raw_stars: Variant = config.get_value(SECTION, KEY_LEVEL_STARS, {})
	if raw_stars is Dictionary:
		for key in (raw_stars as Dictionary):
			if not (key is int or key is float):
				continue
			var id := int(key)
			if not LevelLibrary.is_valid_id(id):
				continue
			var value: Variant = (raw_stars as Dictionary)[key]
			if not (value is int or value is float):
				continue
			var stars := clampi(int(value), 0, MAX_STARS_PER_LEVEL)
			if stars > 0:
				level_stars[id] = stars
