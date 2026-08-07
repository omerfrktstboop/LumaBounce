extends SceneTree

## GELISTIRME ARACI - oyuna dahil degildir.
##
## Play Store surumu icin yapilandirmayi DENETLER ve raporlar. Hicbir seyi
## KENDILIGINDEN DEGISTIRMEZ: paket adi, surum numarasi ve imzalama gibi
## kararlar yayinciya aittir; bir aracin bunlari sessizce degistirmesi
## yanlis paketle magazaya cikmak demektir.
##
## Iki siddet seviyesi:
##   BLOKER - bu haliyle magazaya yuklenemez veya yuklenirse hatali olur.
##   UYARI  - calisir ama duzeltilmesi onerilir.
##
## Cikis kodu: BLOKER varsa 1, yoksa 0 (CI'da kullanilabilir).
##
## Kullanim:
##   godot --headless --path . --script res://tools/check_release_readiness.gd

const EXPORT_PRESETS := "res://export_presets.cfg"
## Yayinci tarafindan istenen paket adi. Farkliysa RAPORLANIR, degistirilmez.
const EXPECTED_PACKAGE := "com.ofsgames.lumabounce"

var _blockers: Array[String] = []
var _warnings: Array[String] = []
var _notes: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("LumaBounce yayin hazirlik denetimi")
	print("  oyun surumu : %s" % GameVersion.GAME)
	print("  kayit semasi: %d" % GameVersion.SAVE_SCHEMA)
	print("  icerik      : %d" % GameVersion.CONTENT)
	print("")

	_check_export_preset()
	_check_project_settings()
	_check_level_library()
	_report()
	quit(1 if not _blockers.is_empty() else 0)


func _check_export_preset() -> void:
	var config := ConfigFile.new()
	if config.load(EXPORT_PRESETS) != OK:
		_blockers.append("export_presets.cfg okunamadi - Android preset'i yok.")
		return

	var section := "preset.0.options"
	var preset := "preset.0"

	var package := String(config.get_value(section, "package/unique_name", ""))
	if package != EXPECTED_PACKAGE:
		_blockers.append(
			"Paket adi '%s'; istenen '%s'. ELLE degistirilmeli - paket adi magazada "
			% [package, EXPECTED_PACKAGE]
			+ "DEGISTIRILEMEZ, ilk yuklemeden sonra sabittir.")

	# Play Store yalnizca .aab kabul eder; .aab uretmek icin gradle build sart.
	var export_format := int(config.get_value(section, "gradle_build/export_format", 0))
	if export_format != 1:
		_blockers.append(
			"gradle_build/export_format=%d (APK). Play Store .aab ister -> 1 olmali."
			% export_format)
	if not bool(config.get_value(section, "gradle_build/use_gradle_build", false)):
		_blockers.append(
			"gradle_build/use_gradle_build=false. .aab uretimi gradle build ister -> true olmali.")

	if not bool(config.get_value(section, "package/signed", false)):
		_blockers.append("package/signed=false - magaza imzasiz paket kabul etmez.")

	var version_name := String(config.get_value(section, "version/name", ""))
	if version_name != GameVersion.GAME:
		_warnings.append(
			"version/name='%s' ile GameVersion.GAME='%s' ayni degil - ikisi elle eslenmeli."
			% [version_name, GameVersion.GAME])

	var version_code := int(config.get_value(section, "version/code", 0))
	if version_code < 1:
		_blockers.append("version/code=%d - en az 1 olmali." % version_code)
	_notes.append(
		"version/code su an %d. HER Play Store yuklemesinde ARTMALI; ayni kod ikinci kez kabul edilmez."
		% version_code)

	var excludes := String(config.get_value(preset, "exclude_filter", ""))
	for pattern in ["tools/*", "addons/*"]:
		if not excludes.contains(pattern):
			_warnings.append(
				"exclude_filter '%s' icermiyor - gelistirme dosyalari pakete giriyor." % pattern)

	var icon := String(config.get_value(section, "launcher_icons/main_192x192", ""))
	if icon.is_empty():
		_warnings.append("launcher_icons/main_192x192 bos - varsayilan Godot ikonu ile cikar.")

	if bool(config.get_value(section, "permissions/internet", false)):
		_notes.append(
			"permissions/internet=true. AI uretici icin gerekliydi ama o ozellik "
			+ "OS.is_debug_build() ile kapali; reklam/analitik eklenmeyecekse bu izin kaldirilabilir.")


func _check_project_settings() -> void:
	var declared := String(ProjectSettings.get_setting("application/config/version", ""))
	if declared.is_empty():
		_warnings.append(
			"project.godot'ta application/config/version bos - GameVersion.GAME (%s) ile doldurulabilir."
			% GameVersion.GAME)
	elif declared != GameVersion.GAME:
		_warnings.append("application/config/version='%s' != GameVersion.GAME='%s'."
			% [declared, GameVersion.GAME])

	# Gelistirme autoload'lari release'de calismamali.
	var autoloads := []
	for key in ProjectSettings.get_property_list():
		var name := String(key.get("name", ""))
		if name.begins_with("autoload/"):
			autoloads.append(name.trim_prefix("autoload/"))
	for name in autoloads:
		var path := String(ProjectSettings.get_setting("autoload/" + name, ""))
		if path.contains("addons/"):
			_notes.append(
				"Autoload '%s' bir addon'a bakiyor (%s). Kendi icinde " % [name, path.trim_prefix("*")]
				+ "OS.has_feature(\"editor\") korumasi var, yani export'ta calismaz; "
				+ "yine de exclude_filter'a addons/* eklenirse paket kuculur.")


func _check_level_library() -> void:
	var missing: Array[int] = []
	var invalid: Array[int] = []
	for level_id in range(LevelLibrary.FIRST_LEVEL_ID, LevelLibrary.last_level_id() + 1):
		var path := LevelLibrary.level_path(level_id)
		if not ResourceLoader.exists(path):
			missing.append(level_id)
			continue
		var level := load(path) as LevelData
		if level == null or not level.validate().is_empty():
			invalid.append(level_id)
	if not missing.is_empty():
		_blockers.append("Eksik bolum dosyasi: %s" % str(missing))
	if not invalid.is_empty():
		_blockers.append("Dogrulamadan gecmeyen bolum: %s" % str(invalid))
	_notes.append("Bolum sayisi: %d (LevelLibrary.LEVEL_COUNT)." % LevelLibrary.LEVEL_COUNT)


func _report() -> void:
	_print_group("BLOKER", _blockers)
	_print_group("UYARI", _warnings)
	_print_group("NOT", _notes)
	print("")
	if _blockers.is_empty():
		print("SONUC: bloker yok. Uyarilar gozden gecirilmeli.")
	else:
		print("SONUC: %d BLOKER var - bu haliyle yayinlanmamali." % _blockers.size())


func _print_group(label: String, items: Array[String]) -> void:
	if items.is_empty():
		return
	print("--- %s (%d) ---" % [label, items.size()])
	for item in items:
		print("  * %s" % item)
	print("")
