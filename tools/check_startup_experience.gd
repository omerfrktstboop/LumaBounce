extends SceneTree

## Uygulama markalama ve sessiz acilis regresyonu.
##
## Godot'un varsayilan logosunun veya ikonunun geri gelmesini ve gürültülü
## ambient_loop'un yeniden autoplay ile baglanmasini engeller.

const PROJECT_ICON := "res://assets/icons/luma_bounce_icon.png"
const ANDROID_MAIN_ICON := "res://assets/icons/luma_bounce_icon_192.png"
const ANDROID_FOREGROUND := "res://assets/icons/luma_bounce_adaptive_foreground.png"
const ANDROID_BACKGROUND := "res://assets/icons/luma_bounce_adaptive_background.png"

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check("proje ikonu Luma Bounce", String(ProjectSettings.get_setting(
		"application/config/icon", "")), PROJECT_ICON)
	_check("Godot boot logosu kapali", bool(ProjectSettings.get_setting(
		"application/boot_splash/show_image", true)), false)
	_check_texture(PROJECT_ICON, Vector2i(512, 512))

	var preset := ConfigFile.new()
	_check("Android export ayarlari okunuyor", preset.load(
		"res://export_presets.cfg"), OK)
	var section := "preset.0.options"
	_check("Android ana ikon yolu", String(preset.get_value(
		section, "launcher_icons/main_192x192", "")), ANDROID_MAIN_ICON)
	_check("Android adaptif on plan", String(preset.get_value(
		section, "launcher_icons/adaptive_foreground_432x432", "")), ANDROID_FOREGROUND)
	_check("Android adaptif arka plan", String(preset.get_value(
		section, "launcher_icons/adaptive_background_432x432", "")), ANDROID_BACKGROUND)
	_check_texture(ANDROID_MAIN_ICON, Vector2i(192, 192))
	_check_texture(ANDROID_FOREGROUND, Vector2i(432, 432))
	_check_texture(ANDROID_BACKGROUND, Vector2i(432, 432))

	var root_scene := FileAccess.get_file_as_string("res://scenes/app_root.tscn")
	_check("acilista ambient_loop yuklenmiyor", root_scene.contains(
		"ambient_loop.wav"), false)
	_check("acilista autoplay ses yok", root_scene.contains(
		"autoplay = true"), false)

	print("ACILIS DENEYIMI: %d gecti, %d kaldi." % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _check_texture(path: String, expected_size: Vector2i) -> void:
	var texture := load(path) as Texture2D
	_check("%s yukleniyor" % path, texture != null, true)
	if texture != null:
		_check("%s boyutu" % path, Vector2i(texture.get_width(), texture.get_height()),
			expected_size)


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
		return
	_failed += 1
	print("HATA %s: beklenen %s, gelen %s" % [label, expected, actual])
