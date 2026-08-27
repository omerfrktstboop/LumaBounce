class_name SafeAreaMargin
extends MarginContainer

## Icerigi cihazin guvenli alani disinda tutar (centik, yuvarlak koseler,
## alt gesture cubugu).
##
## DisplayServer guvenli alani PENCERE pikseli olarak verir; oyun ise
## canvas_items stretch ile 720x1280 referans birimlerinde calisir. Bu yuzden
## inset'ler once orana cevrilip sonra viewport birimine olceklenir.
## Masaustunde guvenli alan pencerenin tamami oldugu icin inset 0 cikar ve
## yalnizca base_padding uygulanir.

## Guvenli alandan bagimsiz, her zaman uygulanan temel bosluk (x = yatay, y = dikey).
@export var base_padding := Vector2(28.0, 24.0)
## Tablet ve yatay pencerelerde metin, kart ve HUD elemanlarinin tum ekrana
## gerilmesini engeller. Arka plan tam ekran kalir; etkilesimli icerik ortalanir.
## 960, Godot'un dikey tabletler icin onerilen 3:4 referans genisligidir.
@export_range(0.0, 4096.0, 1.0) var max_content_width := 960.0


func _ready() -> void:
	_apply_margins()
	get_viewport().size_changed.connect(_apply_margins)


func _apply_margins() -> void:
	var insets := _safe_area_insets()
	var center_inset := centering_inset(get_viewport_rect().size.x, max_content_width)
	add_theme_constant_override("margin_left", int(base_padding.x + insets.x + center_inset))
	add_theme_constant_override("margin_top", int(base_padding.y + insets.y))
	add_theme_constant_override("margin_right", int(base_padding.x + insets.z + center_inset))
	add_theme_constant_override("margin_bottom", int(base_padding.y + insets.w))


static func centering_inset(viewport_width: float, content_width: float) -> float:
	if content_width <= 0.0:
		return 0.0
	return maxf((viewport_width - content_width) * 0.5, 0.0)


## (sol, ust, sag, alt) inset'leri viewport birimlerinde dondurur.
func _safe_area_insets() -> Vector4:
	var window_size := Vector2(DisplayServer.window_get_size())
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return Vector4.ZERO

	var safe := Rect2(DisplayServer.get_display_safe_area())
	if safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return Vector4.ZERO

	var viewport_size := get_viewport_rect().size
	return Vector4(
		maxf(safe.position.x, 0.0) / window_size.x * viewport_size.x,
		maxf(safe.position.y, 0.0) / window_size.y * viewport_size.y,
		maxf(window_size.x - safe.end.x, 0.0) / window_size.x * viewport_size.x,
		maxf(window_size.y - safe.end.y, 0.0) / window_size.y * viewport_size.y)
