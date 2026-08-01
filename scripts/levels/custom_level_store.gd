class_name CustomLevelStore
extends RefCounted

## Editorde tasarlanan bolumlerin kaydi.
##
## NEDEN user:// : export edilmis bir APK'da res:// SALT OKUNURDUR. Telefonda
## tasarlanan bolum o APK'nin "resmi" bolumu olamaz; kendi listesinde yasar.
## Repoya girip yeni bir APK'ya dahil olmasi icin metninin geri tasinmasi
## gerekir - copy_to_clipboard() tam olarak bunun icindir. Bir bolum ~30
## satirlik duz metindir, panodan not/mesaj yoluyla tasinmasi dosya
## yoneticisiyle ugrasmaktan cok daha pratiktir.
##
## Masaustunde (editor/debug calistirmasi) repoya DOGRUDAN yazilabilir; o
## durumda transfer adimi hic olmaz (bkz. repo_path).

const DIR := "user://custom_levels"
const REPO_DIR := "res://levels"
## ResourceSaver metne cevirmek icin dogrudan bir API sunmadigi icin once
## gecici bir dosyaya yazip geri okuruz.
const SCRATCH_PATH := "user://custom_levels/.clipboard.tres"


static func ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)


static func path_for(level_name: String) -> String:
	return "%s/%s.tres" % [DIR, _sanitize(level_name)]


## Masaustunde repoya dogrudan yazmak icin. Disa aktarilmis bir yapida
## res:// yazilamaz, bu yuzden yalnizca editor/debug calistirmasinda anlamli.
static func repo_path(level_id: int) -> String:
	return "%s/level_%02d.tres" % [REPO_DIR, level_id]


static func can_write_to_repo() -> bool:
	# OS.has_feature("editor") hem editorde hem de "editor" ozellikli
	# calistirmalarda true doner; disa aktarilmis oyunda false.
	return OS.has_feature("editor")


static func list_names() -> PackedStringArray:
	ensure_dir()
	var names := PackedStringArray()
	var dir := DirAccess.open(DIR)
	if dir == null:
		return names
	for file_name in dir.get_files():
		if file_name.begins_with(".") or not file_name.ends_with(".tres"):
			continue
		names.append(file_name.trim_suffix(".tres"))
	names.sort()
	return names


## Kaydeder ve yazilan yolu doner; basarisizsa bos string.
static func save(level: LevelData, level_name: String) -> String:
	ensure_dir()
	var path := path_for(level_name)
	var error := ResourceSaver.save(level, path)
	if error != OK:
		push_warning("CustomLevelStore: %s yazilamadi (hata %d)." % [path, error])
		return ""
	return path


static func load_level(level_name: String) -> LevelData:
	var path := path_for(level_name)
	if not ResourceLoader.exists(path):
		return null
	# CACHE_MODE_IGNORE: ayni bolumu ikinci kez acarken bellekteki eski
	# kopyanin degil diskteki halin gelmesi icin.
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData


static func delete(level_name: String) -> void:
	var path := path_for(level_name)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Bolumun .tres metni. Repoya elle tasimak icin panoya bu konur.
static func to_text(level: LevelData) -> String:
	ensure_dir()
	# Kaynagin kendi yolu varsa ResourceSaver onu alt kaynak yerine harici
	# referans olarak yazabilir; kopyayi bagimsiz kilmak icin yolu temizleriz.
	var copy := level.duplicate(true) as LevelData
	copy.take_over_path("")
	if ResourceSaver.save(copy, SCRATCH_PATH) != OK:
		return ""
	var text := FileAccess.get_file_as_string(SCRATCH_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_PATH))
	return text


static func copy_to_clipboard(level: LevelData) -> bool:
	var text := to_text(level)
	if text.is_empty():
		return false
	DisplayServer.clipboard_set(text)
	return true


## Yalnizca masaustunde: bolumu dogrudan res://levels/level_XX.tres olarak
## yazar, yani transfer adimi olmadan repoya girer.
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
