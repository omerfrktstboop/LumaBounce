extends SceneTree

## Play Store release zincirini salt-okunur olarak denetler.
##
## Cikis kodu: en az bir BLOKER varsa 1, aksi halde 0.
## Kullanim:
##   godot --headless --path . --script res://tools/check_release_readiness.gd

const EXPORT_PRESETS := "res://export_presets.cfg"
const APP_ROOT_SCENE := "res://scenes/app_root.tscn"
const APP_ROOT_SCRIPT := "res://scripts/app_root.gd"
const DEBUG_PANEL_SCENE := "res://scenes/debug_panel.tscn"
const DEBUG_PANEL_SCRIPT := "res://scripts/debug/debug_panel.gd"
const GITIGNORE := "res://.gitignore"
const MCP_EXPORT_STRIP := "res://addons/godot_mcp_toolkit/core/export_strip.gd"
const ANDROID_GRADLE_BUILD := "res://android/build/build.gradle"
const ADMOB_PLUGIN := "res://addons/AdmobPlugin/plugin.cfg"
const ADMOB_EXPORT_CONFIG := "res://addons/AdmobPlugin/android_export.cfg"
const ADMOB_DEBUG_AAR := "res://addons/AdmobPlugin/bin/debug/AdmobPlugin-debug.aar"
const ADMOB_RELEASE_AAR := "res://addons/AdmobPlugin/bin/release/AdmobPlugin-release.aar"
const ADMOB_PROVIDER := "res://scripts/monetization/providers/admob_ad_provider.gd"
const ADMOB_CONFIG := "res://scripts/monetization/luma_admob_config.gd"
const BILLING_PLUGIN := "res://addons/GodotGooglePlayBilling/plugin.cfg"
const BILLING_EXPORT_PLUGIN := "res://addons/GodotGooglePlayBilling/export_plugin.gd"
const BILLING_DEBUG_AAR := "res://addons/GodotGooglePlayBilling/bin/debug/GodotGooglePlayBilling-debug.aar"
const BILLING_RELEASE_AAR := "res://addons/GodotGooglePlayBilling/bin/release/GodotGooglePlayBilling-release.aar"
const BILLING_PROVIDER := "res://scripts/monetization/providers/google_play_billing_provider.gd"
const PURCHASE_SERVICE := "res://scripts/monetization/purchase_service.gd"
const MONETIZATION_CONFIG := "res://scripts/monetization/monetization_config.gd"

const RELEASE_PRESET_NAME := "Android Release"
const DEBUG_PRESET_NAME := "Android Debug"
const EXPECTED_PACKAGE := "com.ofsgames.lumabounce"
const EXPECTED_TARGET_SDK := 36
const EXPECTED_ADMOB_APP_ID := "ca-app-pub-4666663369729289~4144593249"
const MAX_ANDROID_VERSION_CODE := 2_100_000_000

const REQUIRED_RELEASE_EXCLUDES := [
	"tools/*",
	"tmp/*",
	"addons/godot_mcp_toolkit/*",
	"scripts/debug/*",
	"scripts/editor/*",
	"scenes/debug_panel.tscn",
	"scenes/level_editor.tscn",
	"test107.gd",
	"test_level.gd",
]
const TRACKED_SIGNING_KEYS := [
	"keystore/release",
	"keystore/release_user",
	"keystore/release_password",
]

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

	var config := ConfigFile.new()
	if config.load(EXPORT_PRESETS) != OK:
		_blockers.append("export_presets.cfg okunamadi - Android presetleri yok.")
	else:
		_check_export_presets(config)
	_check_project_settings()
	_check_release_debug_leakage()
	_check_admob_integration()
	_check_billing_integration()
	_check_gitignore()
	_check_level_library()
	_report()
	quit(1 if not _blockers.is_empty() else 0)


func _check_export_presets(config: ConfigFile) -> void:
	var release_preset := _find_preset(config, RELEASE_PRESET_NAME)
	if release_preset.is_empty():
		_blockers.append("'%s' Android export preset'i yok." % RELEASE_PRESET_NAME)
	else:
		_check_release_preset(config, release_preset)

	var debug_preset := _find_preset(config, DEBUG_PRESET_NAME)
	if debug_preset.is_empty():
		_warnings.append("'%s' APK preset'i yok; cihaz playtest export'u korunmuyor." % DEBUG_PRESET_NAME)
	else:
		_check_debug_preset(config, debug_preset)


func _find_preset(config: ConfigFile, wanted_name: String) -> String:
	for section in config.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		if String(config.get_value(section, "name", "")) == wanted_name:
			return section
	return ""


func _check_release_preset(config: ConfigFile, preset: String) -> void:
	var options := preset + ".options"
	_check_android_identity(config, preset, options, RELEASE_PRESET_NAME)

	if bool(config.get_value(preset, "runnable", true)):
		_warnings.append("Android Release runnable=true; AAB cihazda dogrudan calistirilamaz.")
	var output := String(config.get_value(preset, "export_path", ""))
	if not output.to_lower().ends_with(".aab"):
		_blockers.append("Android Release export_path .aab ile bitmiyor: '%s'." % output)
	if not bool(config.get_value(options, "gradle_build/use_gradle_build", false)):
		_blockers.append("Android Release Gradle build kullanmiyor.")
	var export_format := int(config.get_value(options, "gradle_build/export_format", 0))
	if export_format != 1:
		_blockers.append("Android Release export_format=%d; Play Store icin AAB (1) olmali." % export_format)

	var custom_features := String(config.get_value(preset, "custom_features", ""))
	if "debug" in custom_features.to_lower() or "development" in custom_features.to_lower():
		_blockers.append("Android Release debug/development custom feature iceriyor.")

	var patterns := _filter_patterns(String(config.get_value(preset, "exclude_filter", "")))
	for required in REQUIRED_RELEASE_EXCLUDES:
		if not patterns.has(required):
			_blockers.append("Android Release exclude_filter '%s' icermiyor." % required)
	if patterns.has("addons/*") or patterns.has("res://addons/*"):
		_blockers.append(
			"Android Release tum addons/* klasorunu disliyor. Yalnizca dev-only addonlar dislanmali; "
			+ "AdMob/Billing runtime pluginleri addons altinda kalacak.")

	for key in TRACKED_SIGNING_KEYS:
		if not String(config.get_value(options, key, "")).strip_edges().is_empty():
			_blockers.append(
				"Android Release '%s' degerini repoda tasiyor. GODOT_ANDROID_KEYSTORE_RELEASE_* " % key
				+ "ortam degiskenlerini kullan; preset bos kalmali.")


func _check_debug_preset(config: ConfigFile, preset: String) -> void:
	var options := preset + ".options"
	_check_android_identity(config, preset, options, DEBUG_PRESET_NAME)
	var output := String(config.get_value(preset, "export_path", ""))
	if not output.to_lower().ends_with(".apk"):
		_warnings.append("Android Debug export_path .apk ile bitmiyor: '%s'." % output)
	if not bool(config.get_value(options, "gradle_build/use_gradle_build", false)):
		_blockers.append("Android Debug Gradle build kullanmiyor; gelecek Android pluginleri test edilemez.")
	if int(config.get_value(options, "gradle_build/export_format", 1)) != 0:
		_warnings.append("Android Debug export_format APK (0) degil.")


func _check_android_identity(config: ConfigFile, preset: String, options: String,
		label: String) -> void:
	if String(config.get_value(preset, "platform", "")) != "Android":
		_blockers.append("%s platform=Android degil." % label)
	var package := String(config.get_value(options, "package/unique_name", ""))
	if package != EXPECTED_PACKAGE:
		_blockers.append("%s paket adi '%s'; beklenen '%s'." % [label, package, EXPECTED_PACKAGE])
	var target_sdk := int(String(config.get_value(options, "gradle_build/target_sdk", "0")))
	if target_sdk != EXPECTED_TARGET_SDK:
		_blockers.append("%s target API=%d; 31 Agustos 2026 hedefi icin %d olmali."
			% [label, target_sdk, EXPECTED_TARGET_SDK])
	if not bool(config.get_value(options, "package/signed", false)):
		_blockers.append("%s package/signed=false." % label)
	if not bool(config.get_value(options, "screen/edge_to_edge", false)):
		_blockers.append(
			"%s screen/edge_to_edge=false; sistem cubuklari siyah alan birakabilir." % label)
	if not bool(config.get_value(options, "screen/immersive_mode", false)):
		_blockers.append("%s screen/immersive_mode=false; tam ekran Android deneyimi bozulur." % label)

	var version_name := String(config.get_value(options, "version/name", ""))
	if version_name != GameVersion.GAME:
		_blockers.append("%s version/name='%s' != GameVersion.GAME='%s'."
			% [label, version_name, GameVersion.GAME])
	var version_code := int(config.get_value(options, "version/code", 0))
	if version_code < 1 or version_code > MAX_ANDROID_VERSION_CODE:
		_blockers.append("%s version/code=%d; 1..%d araliginda olmali."
			% [label, version_code, MAX_ANDROID_VERSION_CODE])
	_notes.append("%s versionCode=%d; her Play yuklemesinden once benzersiz ve daha buyuk yap."
		% [label, version_code])


func _filter_patterns(raw_filter: String) -> PackedStringArray:
	var result := PackedStringArray()
	for raw_pattern in raw_filter.split(",", false):
		var pattern := raw_pattern.strip_edges().trim_prefix("res://")
		if not pattern.is_empty():
			result.append(pattern)
	return result


func _check_project_settings() -> void:
	var declared := String(ProjectSettings.get_setting("application/config/version", ""))
	if declared.is_empty():
		_warnings.append("project.godot application/config/version bos.")
	elif declared != GameVersion.GAME:
		_warnings.append("application/config/version='%s' != GameVersion.GAME='%s'."
			% [declared, GameVersion.GAME])

	if not FileAccess.file_exists(ANDROID_GRADLE_BUILD):
		_blockers.append(
			"Gradle build template yok (res://android/build). Godot 4.7.1 export template paketini "
			+ "kurup Project > Install Android Build Template calistir.")

	var mcp_autoload := String(ProjectSettings.get_setting("autoload/MCPRuntimeServer", ""))
	if not mcp_autoload.is_empty():
		if not FileAccess.file_exists(MCP_EXPORT_STRIP):
			_blockers.append("MCPRuntimeServer autoload var ama export_strip.gd yok.")
		var enabled_plugins: PackedStringArray = ProjectSettings.get_setting(
			"editor_plugins/enabled", PackedStringArray())
		if not enabled_plugins.has("res://addons/godot_mcp_toolkit/plugin.cfg"):
			_blockers.append("MCPRuntimeServer autoload var ama MCP export-strip plugin'i etkin degil.")
		_notes.append("MCPRuntimeServer editor playtest autoload'u; release export plugin'i bake sirasinda kaldirir.")


func _check_release_debug_leakage() -> void:
	var scene_text := _read_text(APP_ROOT_SCENE)
	for forbidden in ["debug_panel.tscn", "level_editor.tscn", "DebugLayer", "text = \"DBG\""]:
		if scene_text.contains(forbidden):
			_blockers.append("app_root.tscn release bagimliligi/DBG izi iceriyor: %s" % forbidden)

	var app_root_text := _read_text(APP_ROOT_SCRIPT)
	if not app_root_text.contains("func _setup_debug_tools()"):
		_blockers.append("AppRoot debug araclarini ayri kurulum yolunda toplamiyor.")
	if not app_root_text.contains("if not OS.is_debug_build():"):
		if not app_root_text.contains("if not OS.is_debug_build() or OS.has_feature(\"production\"):"):
			_blockers.append("AppRoot debug kurulumunda release guard bulunamadi.")
	if not app_root_text.contains("OS.has_feature(\"production\")"):
		_blockers.append("AppRoot production feature guard'i yok.")

	var debug_scene_text := _read_text(DEBUG_PANEL_SCENE)
	if not debug_scene_text.contains("text = \"DBG\""):
		_warnings.append("DBG regression fixture'i debug_panel.tscn icinde bulunamadi.")
	var debug_script_text := _read_text(DEBUG_PANEL_SCRIPT)
	if not debug_script_text.contains("OS.is_debug_build()"):
		_blockers.append("DebugPanel release guard'i yok.")
	if not debug_script_text.contains("OS.has_feature(\"production\")"):
		_blockers.append("DebugPanel production feature guard'i yok.")
	if not debug_script_text.contains("queue_free()"):
		_blockers.append("DebugPanel release build'de kendini agactan kaldirmiyor.")


func _check_admob_integration() -> void:
	for path in [ADMOB_PLUGIN, ADMOB_EXPORT_CONFIG, ADMOB_DEBUG_AAR, ADMOB_RELEASE_AAR,
			ADMOB_PROVIDER, ADMOB_CONFIG]:
		if not FileAccess.file_exists(path):
			_blockers.append("AdMob entegrasyon dosyasi yok: %s" % path)

	var enabled_plugins: PackedStringArray = ProjectSettings.get_setting(
		"editor_plugins/enabled", PackedStringArray())
	if not enabled_plugins.has(ADMOB_PLUGIN):
		_blockers.append("AdMob export plugin'i editor_plugins/enabled icinde etkin degil.")

	var export_config := ConfigFile.new()
	if export_config.load(ADMOB_EXPORT_CONFIG) != OK:
		_blockers.append("AdMob android_export.cfg okunamadi.")
	else:
		for section in ["Debug", "Release"]:
			var app_id := String(export_config.get_value(section, "app_id", ""))
			if app_id != EXPECTED_ADMOB_APP_ID:
				_blockers.append("AdMob %s app_id hatali: '%s'." % [section, app_id])

	var provider_text := _read_text(ADMOB_PROVIDER)
	if provider_text.find("update_consent_info") < 0:
		_blockers.append("AdMob provider her acilista UMP consent bilgisini guncellemiyor.")
	if provider_text.find("update_consent_info") > provider_text.find("_admob.initialize()"):
		_blockers.append("AdMob SDK, UMP consent guncellemesinden once initialize ediliyor.")
	if not provider_text.contains("Engine.has_singleton"):
		_blockers.append("AdMob provider native singleton yoklugunda guvenli fallback kullanmiyor.")

	var config_text := _read_text(ADMOB_CONFIG)
	for required in ["OS.has_feature(\"production\")", "TEST_REWARDED", "TEST_INTERSTITIAL"]:
		if not config_text.contains(required):
			_blockers.append("AdMob debug/production korumasi eksik: %s" % required)
	_notes.append("AdMob uygulama kimligi ve uc placement kimligi public config'te; secret degildir.")


func _check_billing_integration() -> void:
	for path in [BILLING_PLUGIN, BILLING_EXPORT_PLUGIN, BILLING_DEBUG_AAR,
			BILLING_RELEASE_AAR, BILLING_PROVIDER, PURCHASE_SERVICE, MONETIZATION_CONFIG]:
		if not FileAccess.file_exists(path):
			_blockers.append("Billing entegrasyon dosyasi yok: %s" % path)

	var enabled_plugins: PackedStringArray = ProjectSettings.get_setting(
		"editor_plugins/enabled", PackedStringArray())
	if not enabled_plugins.has(BILLING_PLUGIN):
		_blockers.append("GodotGooglePlayBilling export plugin'i etkin degil.")

	var plugin_text := _read_text(BILLING_PLUGIN)
	if not plugin_text.contains('version="3.3.0"'):
		_warnings.append("GodotGooglePlayBilling beklenen 3.3.0 surumunde degil.")
	var export_text := _read_text(BILLING_EXPORT_PLUGIN)
	if not export_text.contains("com.android.billingclient:billing-ktx:9.1.0"):
		_blockers.append("Billing plugin Google Play Billing 9.1.0 bagimliligini tasimiyor.")

	var config_text := _read_text(MONETIZATION_CONFIG)
	if not config_text.contains('PRODUCT_REMOVE_ADS := &"remove_ads"'):
		_blockers.append("Play Console urun kimligi remove_ads olarak sabitlenmemis.")
	var provider_text := _read_text(BILLING_PROVIDER)
	for contract in ["query_product_details", "query_purchases", "PurchaseState.PENDING",
			"PurchaseState.PURCHASED", "acknowledge_purchase"]:
		if not provider_text.contains(contract):
			_blockers.append("Billing provider yasam dongusu eksik: %s" % contract)
	var service_text := _read_text(PURCHASE_SERVICE)
	if not service_text.contains("_apply_authoritative_records"):
		_blockers.append("Billing restore sonucu entitlement'i authoritative yenilemiyor.")
	if service_text.contains("purchase_token\"") and service_text.contains("track_event"):
		_notes.append("Billing token servis icinde islenir; analytics payloadlarinda token olmadigini test et.")
	_notes.append("remove_ads client-side restore/ack kullanir; coin paketi veya subscription eklenmemistir.")


func _check_gitignore() -> void:
	var ignore_text := _read_text(GITIGNORE)
	for required in ["*.keystore", "*.jks", "*.p12", "keystores/", "keystore.properties", "builds/"]:
		if not ignore_text.contains(required):
			_blockers.append(".gitignore '%s' kalibini icermiyor." % required)
	for line in ignore_text.split("\n"):
		if line.strip_edges() == "export_presets.cfg":
			_blockers.append("export_presets.cfg ignore ediliyor; guvenli release ayarlari surumlenmeli.")


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		_blockers.append("Gerekli dosya yok: %s" % path)
		return ""
	return FileAccess.get_file_as_string(path)


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
