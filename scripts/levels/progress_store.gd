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
## Her basarili yazimdan ONCE eldeki dosya buraya kopyalanir. Kayit bozulursa
## (disk dolu, yazma yarida kesildi, dosya elle kurcalandi) oyun buradan
## kurtarir - bkz. load_from_disk().
const BACKUP_PATH := "user://save.cfg.bak"
const SECTION := "progress"
## Ayarlar ILERLEMEDEN AYRI bir bolumde tutulur: "ilerlemeyi sifirla" oyuncunun
## titresim tercihini de silmemeli (bkz. reset()).
const SECTION_SETTINGS := "settings"
const SECTION_META := "meta"

## --- Sema surumu 1 anahtarlari (BOLUM UID'I ile) ---
## Bolumler DEGISMEZ uid ile anilir ("level_027"). Sebep: eskiden ilerleme
## tamsayi bolum numarasiyla tutuluyordu; araya yeni bir bolum eklemek veya
## sirayi degistirmek, oyuncunun tamamladigi bolumleri BASKA bolumlere
## kaydiriyordu. uid dosyaya sabitlendigi icin sira degisse de kayit dogru
## bolumu gosterir.
const KEY_SCHEMA_VERSION := "save_schema_version"
const KEY_GAME_VERSION := "last_game_version"
const KEY_COMPLETED_UIDS := "completed_level_ids"
const KEY_STARS_BY_UID := "level_stars_by_id"
const KEY_LAST_COMPLETED_UID := "last_completed_level_id"
const KEY_HIGHEST := "highest_unlocked_level"

## --- Sema surumu 0 (eski, tamsayi anahtarli) - yalnizca goc icin okunur ---
const KEY_LEGACY_COMPLETED := "completed_levels"
const KEY_LEGACY_STARS := "level_stars"

const KEY_SEEN_OBSTACLE_KINDS := "seen_obstacle_kinds"
const KEY_SEEN_BLOCK_MECHANIC := "seen_block_mechanic"
const KEY_HAPTICS_ENABLED := "haptics_enabled"
const KEY_LANGUAGE := "language"
const KEY_SHAKE_SCALE := "shake_scale"
const KEY_AIM_ASSIST := "aim_assist"

## NORMAL bir bolumun azami yildizi. Bonus bolumler daha fazla verir, bu
## yuzden yildiz SINIRLAMASI ve TOPLAMLARI bu sabite degil bolumun kendi
## kapasitesine bakar (bkz. max_stars_for). Sabit yalnizca "bilinmeyen bolum"
## icin guvenli bir tavan olarak durur.
const MAX_STARS_PER_LEVEL := LevelData.NORMAL_MAX_STARS

var highest_unlocked_level := LevelLibrary.FIRST_LEVEL_ID
var completed_levels: Array[int] = []
## level_id -> kazanilmis en yuksek yildiz (1..3). Yildizi olmayan bolum
## hic anahtar tutmaz; get_level_stars 0 doner.
var level_stars: Dictionary = {}
## Oyuncunun daha once gordugu ObstacleData.Kind degerleri (int). Bir bolum
## ilk kez bu turlerden birini iceriyorsa gameplay tanitim toast'i gosterir -
## bkz. Gameplay._newly_seen_obstacle_kinds().
var seen_obstacle_kinds: Array[int] = []
## Kirilabilir blok mekanigi (tur degil, tek mekanik) daha once gorulmus mu -
## bkz. Gameplay._pending_block_intro.
var seen_block_mechanic := false
## Dokunsal geri bildirim (titresim) acik mi. Titresim bazi oyuncular icin
## rahatsiz edicidir ve pilden yer; kapatilabilir olmali. Tek okuma noktasi
## Haptics.enabled'dir - AppRoot bu degeri oraya aktarir.
var haptics_enabled := true
## Oyuncunun SECTIGI dil kodu ("tr"/"en"). BOS = henuz secim yapilmadi; o
## durumda cihazin dili kullanilir (bkz. Locale.apply_saved). Bos ile "tr"
## bilerek AYRI tutulur: Ingilizce bir telefonda oyun Ingilizce acilmali,
## ama oyuncu bir kez Turkce sectiyse telefonun dili ne olursa olsun Turkce
## kalmali.
var language := ""
## Ekran sarsintisi carpani. 0.0 = kapali. Hareket duyarliligi olan oyuncular
## icin gerekli; sarsinti oyunun geri bildiriminin parcasi oldugu icin
## silinmek yerine OLCEKLENIR.
var shake_scale := 1.0
## Nisan izi yardimi. Acikken ileri bolumlerde kisalan nisan onizlemesi tam
## uzunlukta kalir (bkz. Gameplay._preview_ratio_for_level) - zorlanan oyuncu
## icin kolaylik secenegi.
var aim_assist := false


## Kaydi diskten okur. SIRAYLA: asil dosya -> yedek -> bos ilerleme.
## Hicbir asamada oyun acilmaz olmaz; en kotu durumda oyuncu bastan baslar
## ve bu durum loglanir.
static func load_from_disk() -> ProgressStore:
	var store := ProgressStore.new()
	var config := ConfigFile.new()

	if config.load(SAVE_PATH) == OK:
		store._read(config)
		return store

	# Asil dosya okunamiyor. Bu ya ilk calistirma (dosya yok) ya da bozulma.
	# Ikisini ayirmak onemli: dosya VARSA ve okunamiyorsa yedege gitmeliyiz.
	if FileAccess.file_exists(SAVE_PATH):
		push_warning("ProgressStore: %s okunamadi, yedek deneniyor." % SAVE_PATH)
		var backup := ConfigFile.new()
		if backup.load(BACKUP_PATH) == OK:
			store._read(backup)
			push_warning("ProgressStore: ilerleme yedekten kurtarildi.")
			# Kurtarilan durum hemen asil dosyaya yazilir ki bir sonraki acilis
			# yine yedege dusmesin.
			store.save()
			return store
		push_error("ProgressStore: kayit ve yedek okunamadi, ilerleme sifirdan baslatildi.")
	return store


func save() -> void:
	_rotate_backup()

	var config := ConfigFile.new()
	config.set_value(SECTION_META, KEY_SCHEMA_VERSION, GameVersion.SAVE_SCHEMA)
	config.set_value(SECTION_META, KEY_GAME_VERSION, GameVersion.GAME)

	config.set_value(SECTION, KEY_HIGHEST, highest_unlocked_level)
	config.set_value(SECTION, KEY_COMPLETED_UIDS, _completed_uids())
	config.set_value(SECTION, KEY_STARS_BY_UID, _stars_by_uid())
	config.set_value(SECTION, KEY_LAST_COMPLETED_UID, _last_completed_uid())
	config.set_value(SECTION, KEY_SEEN_OBSTACLE_KINDS, seen_obstacle_kinds)
	config.set_value(SECTION, KEY_SEEN_BLOCK_MECHANIC, seen_block_mechanic)
	config.set_value(SECTION_SETTINGS, KEY_HAPTICS_ENABLED, haptics_enabled)
	config.set_value(SECTION_SETTINGS, KEY_LANGUAGE, language)
	config.set_value(SECTION_SETTINGS, KEY_SHAKE_SCALE, shake_scale)
	config.set_value(SECTION_SETTINGS, KEY_AIM_ASSIST, aim_assist)

	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("ProgressStore: kayit yazilamadi (hata %d)." % error)


## Yazmadan once eldeki SAGLAM dosyayi yedekler. Bozuk bir dosyayi yedeklemek
## kurtarma sansini yok ederdi, bu yuzden once okunabilirligi dogrulanir.
func _rotate_backup() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var existing := ConfigFile.new()
	if existing.load(SAVE_PATH) != OK:
		return
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	if text.is_empty():
		return
	var backup := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
	if backup == null:
		return
	backup.store_string(text)
	backup.close()


# --- uid <-> tamsayi donusumleri ----------------------------------------------
#
# Bellekte ilerleme hala tamsayi bolum numarasiyla tutulur (tum cagiranlar
# boyle kullaniyor); DISKE yazarken uid'e cevrilir. Boylece kayit dosyasi
# sirali degisimlere dayanikli olurken oyun kodunun tamami degismeden kalir.

func _completed_uids() -> PackedStringArray:
	var uids := PackedStringArray()
	for level_id in completed_levels:
		uids.append(LevelData.uid_for(level_id))
	return uids


func _stars_by_uid() -> Dictionary:
	var out := {}
	for level_id in level_stars:
		out[LevelData.uid_for(int(level_id))] = int(level_stars[level_id])
	return out


func _last_completed_uid() -> String:
	if completed_levels.is_empty():
		return ""
	return LevelData.uid_for(completed_levels[completed_levels.size() - 1])


# --- Kilit durumu -------------------------------------------------------------

## Iki kosul BIRLIKTE saglanmali:
##   1) sirali ilerleme - onceki bolum tamamlanmis olmali
##   2) varsa yildiz kapisi - onundeki bolumlerden yeterince yildiz toplanmis olmali
## Bu yuzden 40 yildizi olan ama 20. bolumu bitirmemis oyuncuya 21 acilmaz.
func is_unlocked(level_id: int) -> bool:
	if not LevelLibrary.is_valid_id(level_id):
		return false
	# BONUS bolumler sirali ilerlemeye TABI DEGILDIR: numaralari 151+ oldugu
	# icin "onceki bolumu bitir" kurali onlari asla acmazdi. Kosul tek: ait
	# olduklari dunyadan yeterince yildiz toplamak. Zaten amaclari da bu -
	# bir dunyanin tamamina hakim olanin sinavi.
	if LevelWorlds.is_bonus_id(level_id):
		return get_world_stars(LevelWorlds.world_of_bonus(level_id)) 			>= LevelWorlds.bonus_required_stars(level_id)
	if level_id > highest_unlocked_level:
		return false
	var required := LevelLibrary.required_stars_for(level_id)
	if required <= 0:
		return true
	return get_stars_before(level_id) >= required


## Bir dunyanin NORMAL bolumlerinden toplanmis yildiz. Bonus bolumlerin
## yildizi SAYILMAZ: bonus, esigin kendisi degil odulu.
func get_world_stars(world_index: int) -> int:
	if world_index < 0 or world_index >= LevelWorlds.count():
		return 0
	var total := 0
	for level_id in range(LevelWorlds.first_level(world_index),
			LevelWorlds.last_level(world_index) + 1):
		total += get_level_stars(level_id)
	return total


## Yildiz kapisi olan bir bolum icin (mevcut, gerekli). Kapi yoksa ikisi de
## 0 doner. Kilitli buton "34 / 40" bilgisini bundan uretir.
func get_star_gate_progress(level_id: int) -> Vector2i:
	if LevelWorlds.is_bonus_id(level_id):
		var needed := LevelWorlds.bonus_required_stars(level_id)
		if needed <= 0:
			return Vector2i.ZERO
		return Vector2i(get_world_stars(LevelWorlds.world_of_bonus(level_id)), needed)
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
		return clampi(int(value), 0, max_stars_for(level_id))
	return 0


## Yalnizca daha iyi sonuc kaydedilir: eski 3, yeni 1 ise kayit 3 kalir.
## Gercekten degistiyse true doner (yeni kisisel rekor).
func set_level_stars_if_higher(level_id: int, stars: int) -> bool:
	if not LevelLibrary.is_valid_id(level_id):
		return false
	var clamped := clampi(stars, 0, max_stars_for(level_id))
	if clamped <= get_level_stars(level_id):
		return false
	level_stars[level_id] = clamped
	save()
	return true


## Tum bolumlerin toplami - bolum secim ekranindaki "N / 150" sayaci.
func get_total_stars() -> int:
	return get_stars_before(LevelLibrary.last_level_id() + 1)


## [param level_id]'den ONCEKI bolumlerin yildiz toplami. Yildiz kapilari
## bunu kullanir: kapinin arkasindaki bolumler kendi kilidini acamaz, yani
## 21-40'ta kazanilan yildizlar 21'in 40-yildiz sartina sayilmaz.
func get_stars_before(level_id: int) -> int:
	var total := 0
	for id in range(LevelLibrary.FIRST_LEVEL_ID, level_id):
		# Bonus bolumler kapi sayimina GIRMEZ: bir kapinin arkasindaki odul,
		# bir sonraki kapiyi acmaya katkida bulunmamali.
		if LevelWorlds.is_bonus_id(id):
			continue
		total += get_level_stars(id)
	return total


func get_max_available_stars() -> int:
	var total := 0
	for level_id in range(LevelLibrary.FIRST_LEVEL_ID, LevelLibrary.last_level_id() + 1):
		total += max_stars_for(level_id)
	return total


## Bolumun yildiz kapasitesi. Bonus bolumler 5, digerleri 3 verir.
##
## Bolum dosyasindan OKUNUR, numaraya bakilarak tahmin edilmez: kapasite
## bolumun bir ozelligi (LevelData.is_bonus), numaralarin bir ozelligi degil.
static func max_stars_for(level_id: int) -> int:
	if not LevelLibrary.is_valid_id(level_id):
		return LevelData.NORMAL_MAX_STARS
	return LevelLibrary.load_level(level_id).max_stars()


# --- Engel tanitimi -------------------------------------------------------------

func has_seen_obstacle_kind(kind: int) -> bool:
	return seen_obstacle_kinds.has(kind)


## Yeni bir tur ilk kez goruluyorsa true doner (ve kaydeder); zaten
## goruldugunde false donup hicbir sey yazmaz.
func mark_obstacle_kind_seen(kind: int) -> bool:
	if seen_obstacle_kinds.has(kind):
		return false
	seen_obstacle_kinds.append(kind)
	save()
	return true


func has_seen_block_mechanic() -> bool:
	return seen_block_mechanic


## Ilk kez isaretleniyorsa true doner (ve kaydeder); tekrarinda false.
func mark_block_mechanic_seen() -> bool:
	if seen_block_mechanic:
		return false
	seen_block_mechanic = true
	save()
	return true


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


## Yalnizca ILERLEMEYI sifirlar. [code][settings][/code] bolumunun tamami
## (dil, titresim, sarsinti, nisan yardimi) bilerek KORUNUR: bunlar oyuncu
## tercihidir, kazanilmis ilerleme degil. "Bastan basla" diyen oyuncunun
## oyunu anlamadigi bir dile donmesi ya da kapattigi titresimin geri gelmesi
## kabul edilemez.
func reset() -> void:
	highest_unlocked_level = LevelLibrary.FIRST_LEVEL_ID
	completed_levels.clear()
	level_stars.clear()
	seen_obstacle_kinds.clear()
	seen_block_mechanic = false
	save()


# --- Ayarlar ------------------------------------------------------------------

## Titresim tercihini degistirir ve kalici yazar. Gercekten degistiyse true
## doner, boylece cagiran gereksiz yere Haptics'i tazelemez.
func set_haptics_enabled(value: bool) -> bool:
	if haptics_enabled == value:
		return false
	haptics_enabled = value
	save()
	return true


## Dil tercihini kaydeder. Uygulamak Locale'in isidir - burasi yalnizca
## KALICILIGI bilir, tek sorumluluk kurali.
func set_language(code: String) -> bool:
	var wanted := Locale.normalize(code)
	if language == wanted:
		return false
	language = wanted
	save()
	return true


func set_shake_scale(value: float) -> bool:
	var wanted := clampf(value, 0.0, 1.0)
	if is_equal_approx(shake_scale, wanted):
		return false
	shake_scale = wanted
	save()
	return true


func set_aim_assist(value: bool) -> bool:
	if aim_assist == value:
		return false
	aim_assist = value
	save()
	return true


## Tanitim kartlarini yeniden gosterilir hale getirir ("Ogreticileri tekrar
## goster"). Ilerlemeyi ETKILEMEZ: bolumler kilitli kalmaz, yildizlar durur.
func forget_seen_mechanics() -> void:
	seen_obstacle_kinds.clear()
	seen_block_mechanic = false
	save()


## Beklenmeyen tip veya aralik disi deger gelirse o alan varsayilanda birakilir.
##
## SEMA GOCU: dosyadaki save_schema_version'a bakilir. Anahtar yoksa kayit
## sema 0'dir (tamsayi anahtarli, uid'den onceki surum) ve _migrate_from_v0()
## ile okunur. Goc KAYIPSIZDIR: eski tamsayi anahtarlari uid'e cevrilir, bir
## sonraki save() dosyayi yeni semada yazar. Oyuncu bunu fark etmez.
func _read(config: ConfigFile) -> void:
	var raw_highest: Variant = config.get_value(SECTION, KEY_HIGHEST, LevelLibrary.FIRST_LEVEL_ID)
	if raw_highest is int or raw_highest is float:
		highest_unlocked_level = LevelLibrary.clamp_id(int(raw_highest))

	var schema := int(config.get_value(SECTION_META, KEY_SCHEMA_VERSION, 0))
	if schema <= 0:
		_migrate_from_v0(config)
	else:
		if schema > GameVersion.SAVE_SCHEMA:
			# ILERI surumden gelen kayit: oyuncu eski surume dondu. Tanidigimiz
			# alanlari okuruz, tanimadiklarimiza dokunmayiz; veri silmeyiz.
			push_warning(
				"ProgressStore: kayit semasi %d, bu surum %d taniyor - bilinen alanlar okunuyor."
				% [schema, GameVersion.SAVE_SCHEMA])
		_read_v1(config)

	_read_shared(config)


## Sema 1: bolumler uid ile anilir.
func _read_v1(config: ConfigFile) -> void:
	var raw_completed: Variant = config.get_value(SECTION, KEY_COMPLETED_UIDS, PackedStringArray())
	if raw_completed is PackedStringArray or raw_completed is Array:
		for value in raw_completed:
			var id := LevelLibrary.number_for_uid(String(value))
			if LevelLibrary.is_valid_id(id) and not completed_levels.has(id):
				completed_levels.append(id)
		completed_levels.sort()

	var raw_stars: Variant = config.get_value(SECTION, KEY_STARS_BY_UID, {})
	if raw_stars is Dictionary:
		for key in (raw_stars as Dictionary):
			var id := LevelLibrary.number_for_uid(String(key))
			if not LevelLibrary.is_valid_id(id):
				continue
			var value: Variant = (raw_stars as Dictionary)[key]
			if not (value is int or value is float):
				continue
			var stars := clampi(int(value), 0, MAX_STARS_PER_LEVEL)
			if stars > 0:
				level_stars[id] = stars


## Sema 0 -> 1 gocu: eski kayitlar bolumleri TAMSAYI ile aniyordu.
## Cevrim LevelData.uid_for() ile yapilir, yani "7" -> "level_007". Bu esleme
## sabittir, dolayisiyla goc tekrarlanabilir ve kayipsizdir.
func _migrate_from_v0(config: ConfigFile) -> void:
	var raw_completed: Variant = config.get_value(SECTION, KEY_LEGACY_COMPLETED, [])
	if raw_completed is Array:
		for value in (raw_completed as Array):
			if not (value is int or value is float):
				continue
			var id := int(value)
			if LevelLibrary.is_valid_id(id) and not completed_levels.has(id):
				completed_levels.append(id)
		completed_levels.sort()

	# Eski kayitlarda bu anahtar yok - bos sozluk kalir, yani 0 yildiz.
	var raw_stars: Variant = config.get_value(SECTION, KEY_LEGACY_STARS, {})
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


## Semadan BAGIMSIZ alanlar: her iki surumde de ayni bicimde tutulur, bu
## yuzden goc yolundan ayri okunur.
func _read_shared(config: ConfigFile) -> void:
	# Eski kayitlarda bu anahtar yok - bos dizi kalir, yani hicbir tur
	# gorulmemis (o bolumlere tekrar girildiginde tanitim toast'i bir kez
	# daha gorunur; kayit dosyasi ile bolum icerigi arasindaki tek makul
	# uzlasi budur).
	var raw_seen: Variant = config.get_value(SECTION, KEY_SEEN_OBSTACLE_KINDS, [])
	if raw_seen is Array:
		for value in (raw_seen as Array):
			if not (value is int or value is float):
				continue
			var kind := int(value)
			if not seen_obstacle_kinds.has(kind):
				seen_obstacle_kinds.append(kind)

	var raw_block_seen: Variant = config.get_value(SECTION, KEY_SEEN_BLOCK_MECHANIC, false)
	if raw_block_seen is bool:
		seen_block_mechanic = raw_block_seen

	# Eski kayitlarda ayar bolumu hic yok - titresim ACIK varsayilir (oyunun
	# bugunku davranisi), yani mevcut oyuncular icin hicbir sey degismez.
	var raw_haptics: Variant = config.get_value(SECTION_SETTINGS, KEY_HAPTICS_ENABLED, true)
	if raw_haptics is bool:
		haptics_enabled = raw_haptics

	# Dil anahtari sema 1 kayitlarinda YOKTUR; bos kalmasi dogru sonuctur
	# (= "oyuncu henuz secmedi" -> cihaz dili kullanilir). Taninmayan bir kod
	# yazilmissa bos sayilir, boylece bozuk bir deger oyunu anlasilmaz bir
	# dile dusurmez.
	var raw_language: Variant = config.get_value(SECTION_SETTINGS, KEY_LANGUAGE, "")
	if raw_language is String and Locale.is_supported(String(raw_language)):
		language = String(raw_language)

	var raw_shake: Variant = config.get_value(SECTION_SETTINGS, KEY_SHAKE_SCALE, 1.0)
	if raw_shake is float or raw_shake is int:
		shake_scale = clampf(float(raw_shake), 0.0, 1.0)

	var raw_aim: Variant = config.get_value(SECTION_SETTINGS, KEY_AIM_ASSIST, false)
	if raw_aim is bool:
		aim_assist = raw_aim
