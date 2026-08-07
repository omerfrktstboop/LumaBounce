class_name CustomLevelStore
extends RefCounted

## Editorde tasarlanan ve uretilen bolumlerin kaydi.
##
## IKI KOVA vardir ve ayri durmalari kasitlidir:
##   KAYITLAR   - senin bilerek sakladiklarin. Yalnizca sen silersin.
##   URETILENLER- son uretim partisi. Yeni bir "Uret" bunun UZERINE yazar.
## Uretilen bir bolumu kalici yapmanin yolu onu kayitlara tasimaktir; boylece
## "begendigim bolum bir sonraki uretimde ucar" durumu olusmaz.
##
## Uretim biter bitmez tum parti diske yazilir. Onceki surumde parti yalnizca
## bellekte duruyordu ve listeden birini secmek digerlerini yok ediyordu -
## 10 adayi gozden gecirip birkacini secmek imkansizdi.
##
## NEDEN user:// : export edilmis bir APK'da res:// SALT OKUNURDUR. Telefonda
## tasarlanan bolum o APK'nin "resmi" bolumu olamaz. Repoya donmesi icin
## metninin tasinmasi gerekir - copy_to_clipboard() ve bulk_text() bunun
## icindir. Masaustunde repoya dogrudan yazilabilir (bkz. save_to_repo).

enum Bucket { SAVED, GENERATED }

const SAVED_DIR := "user://custom_levels"
const GENERATED_DIR := "user://generated_levels"
const GENERATED_MANIFEST_PATH := "user://generated_levels/generated_manifest.json"
const REPO_DIR := "res://levels"
## ResourceSaver metne cevirmek icin dogrudan bir API sunmadigi icin once
## gecici bir dosyaya yazip geri okuruz.
const SCRATCH_PATH := "user://custom_levels/.clipboard.tres"
## Toplu kopyalamada bolumleri ayiran satir. Yapistirilan metni tekrar
## dosyalara bolmek gerektiginde bu satir aranir.
const BULK_SEPARATOR := "===== %s ====="


static func dir_for(bucket: Bucket) -> String:
	return GENERATED_DIR if bucket == Bucket.GENERATED else SAVED_DIR


static func ensure_dir(bucket: Bucket) -> void:
	var path := dir_for(bucket)
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)


static func path_for(bucket: Bucket, level_name: String) -> String:
	return "%s/%s.tres" % [dir_for(bucket), _sanitize(level_name)]


## Bir bolum adinin LISTEDE gorunecek hali (dosya adi govdesi). Sidecar JSON
## girislerinin anahtari da budur; list_names() ile ayni degeri uretmesi sart,
## yoksa kayit ile metadata eslesmez.
static func entry_name_for(level_name: String) -> String:
	return _sanitize(level_name)


static func list_names(bucket: Bucket) -> PackedStringArray:
	ensure_dir(bucket)
	var names := PackedStringArray()
	var dir := DirAccess.open(dir_for(bucket))
	if dir == null:
		return names
	for file_name in dir.get_files():
		if file_name.begins_with(".") or not file_name.ends_with(".tres"):
			continue
		names.append(file_name.trim_suffix(".tres"))
	names.sort()
	return names


## Kaydeder ve yazilan yolu doner; basarisizsa bos string.
static func save(bucket: Bucket, level: LevelData, level_name: String) -> String:
	ensure_dir(bucket)
	var path := path_for(bucket, level_name)
	# Kaynagin kendi yolu varsa ResourceSaver onu harici referans olarak
	# yazabilir; kopyayi bagimsiz kilmak icin yol temizlenir.
	var copy := level.duplicate(true) as LevelData
	copy.take_over_path("")
	var error := ResourceSaver.save(copy, path)
	if error != OK:
		push_warning("CustomLevelStore: %s yazilamadi (hata %d)." % [path, error])
		return ""
	return path


static func load_level(bucket: Bucket, level_name: String) -> LevelData:
	var path := path_for(bucket, level_name)
	if not ResourceLoader.exists(path):
		return null
	# CACHE_MODE_IGNORE: ayni bolumu ikinci kez acarken bellekteki eski
	# kopyanin degil diskteki halin gelmesi icin.
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData


static func delete(bucket: Bucket, level_name: String) -> void:
	var path := path_for(bucket, level_name)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Uretim partisini diske yazar. ONCEKI PARTIYI SILER - "uretilenler" son
## aramanin sonucudur, birikmis bir yigin degil. Kalici olmasini istedigin
## bolumu kayitlara tasirsin.
static func replace_generated(levels: Array[LevelData]) -> PackedStringArray:
	ensure_dir(Bucket.GENERATED)
	# Yerel generator yeni parti yazdiginda eski AI sidecar'i ayni dosya
	# adlarina yanlis metadata baglamasin. AI coordinator partiden sonra yeni
	# manifesti yazar.
	if FileAccess.file_exists(GENERATED_MANIFEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GENERATED_MANIFEST_PATH))
	for existing in list_names(Bucket.GENERATED):
		delete(Bucket.GENERATED, existing)

	var names := PackedStringArray()
	for i in levels.size():
		# Sirali on ek: dosya adina gore siralama uretim sirasini korur.
		var level_name := "%02d_%s" % [i + 1, levels[i].display_name]
		if not save(Bucket.GENERATED, levels[i], level_name).is_empty():
			names.append(_sanitize(level_name))
	return names


# --- Disari aktarma -----------------------------------------------------------

## Bolumun .tres metni. Repoya elle tasimak icin panoya bu konur.
static func to_text(level: LevelData) -> String:
	ensure_dir(Bucket.SAVED)
	var copy := level.duplicate(true) as LevelData
	copy.take_over_path("")
	if ResourceSaver.save(copy, SCRATCH_PATH) != OK:
		return ""
	var text := FileAccess.get_file_as_string(SCRATCH_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_PATH))
	return text


## Birden fazla bolumu tek metinde toplar. Ayrac satirlari sayesinde
## yapistirilan blok tekrar dosyalara bolunebilir.
static func bulk_text(levels: Array[LevelData], names: PackedStringArray) -> String:
	var parts := PackedStringArray()
	for i in levels.size():
		var label: String = names[i] if i < names.size() else "level_%02d" % (i + 1)
		var text := to_text(levels[i])
		if text.is_empty():
			continue
		parts.append(BULK_SEPARATOR % (label + ".tres"))
		parts.append(text)
	return "\n".join(parts)


static func copy_to_clipboard(level: LevelData) -> bool:
	var text := to_text(level)
	if text.is_empty():
		return false
	DisplayServer.clipboard_set(text)
	return true


static func copy_many_to_clipboard(levels: Array[LevelData], names: PackedStringArray) -> bool:
	var text := bulk_text(levels, names)
	if text.is_empty():
		return false
	DisplayServer.clipboard_set(text)
	return true


# --- Repoya dogrudan yazma (yalnizca masaustu) --------------------------------

## OS.has_feature("editor") disa aktarilmis oyunda false doner; orada res://
## yazilamaz, bu yuzden repoya yazma yalnizca masaustunde anlamlidir.
static func can_write_to_repo() -> bool:
	return OS.has_feature("editor")


static func repo_path(level_id: int) -> String:
	return "%s/level_%02d.tres" % [REPO_DIR, level_id]


## Bir sonraki bos bolum numarasi - var olan bolumlerin uzerine yazmamak icin.
static func next_free_repo_id() -> int:
	var level_id := 1
	while ResourceLoader.exists(repo_path(level_id)) and level_id < 999:
		level_id += 1
	return level_id


static func save_to_repo(level: LevelData, level_id: int) -> String:
	if not can_write_to_repo():
		return ""
	var path := repo_path(level_id)
	var copy := level.duplicate(true) as LevelData
	copy.take_over_path("")
	copy.level_id = level_id
	if ResourceSaver.save(copy, path) != OK:
		push_warning("CustomLevelStore: %s yazilamadi." % path)
		return ""
	return path


## Secilenleri bos numaralardan baslayarak sirayla repoya yazar; yazilan
## bolum sayisini doner.
static func save_many_to_repo(levels: Array[LevelData]) -> int:
	if not can_write_to_repo():
		return 0
	var written := 0
	var level_id := next_free_repo_id()
	for level in levels:
		if save_to_repo(level, level_id).is_empty():
			continue
		written += 1
		level_id += 1
	return written


## Dosya adi olarak guvenli bir ad uretir. Turkce karakterler ASCII
## karsiliklarina cevrilir; geri kalan her sey alt cizgi olur.
static func _sanitize(level_name: String) -> String:
	const TR := {"ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u"}
	const ALLOWED := "abcdefghijklmnopqrstuvwxyz0123456789_-"

	var clean := level_name.strip_edges().to_lower()
	var out := ""
	for i in clean.length():
		var c: String = clean[i]
		if TR.has(c):
			c = TR[c]
		if ALLOWED.contains(c):
			out += c
		elif c == " ":
			out += "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "bolum"
