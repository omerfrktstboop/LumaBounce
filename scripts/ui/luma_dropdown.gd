class_name LumaDropdown
extends OptionButton

## Ayarlar icin tek secimli, kart diliyle uyumlu acilir liste.
## Secenekler ekranda yer kaplamaz; acildiginda buyuk satirlar halinde sunulur.


func setup(labels: Array, selected_index := 0) -> void:
	clear()
	for label in labels:
		add_item(String(label))
	if not labels.is_empty():
		select(clampi(selected_index, 0, labels.size() - 1))


func _ready() -> void:
	custom_minimum_size = Vector2(236.0, UIMetrics.MIN_TOUCH)
	focus_mode = Control.FOCUS_NONE
	fit_to_longest_item = false
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_theme_font_size_override("font_size", UIMetrics.FONT_BODY + 1)
	add_theme_color_override("font_color", Palette.TEXT)
	add_theme_color_override("font_hover_color", Palette.TEXT)
	add_theme_color_override("font_pressed_color", Palette.ACCENT_CORE)
	add_theme_color_override("font_focus_color", Palette.TEXT)
	add_theme_stylebox_override("normal", _style(
		Color(Palette.SURFACE_ELEVATED, 0.72), Color(Palette.SURFACE_EDGE, 0.9), 2))
	add_theme_stylebox_override("hover", _style(
		Color(Palette.SURFACE_ELEVATED, 0.94), Color(Palette.ACCENT, 0.7), 2))
	add_theme_stylebox_override("pressed", _style(
		Color(Palette.INK_MID, 1.0), Palette.ACCENT, 3))
	add_theme_stylebox_override("focus", _style(
		Color(Palette.SURFACE_ELEVATED, 0.94), Color(Palette.ACCENT, 0.7), 2))
	_style_popup()


func _style_popup() -> void:
	var popup := get_popup()
	popup.transparent_bg = true
	popup.add_theme_font_size_override("font_size", UIMetrics.FONT_BODY + 1)
	popup.add_theme_color_override("font_color", Palette.TEXT)
	popup.add_theme_color_override("font_hover_color", Palette.ACCENT_CORE)
	popup.add_theme_constant_override("v_separation", UIMetrics.SPACE_LG)
	popup.add_theme_constant_override("item_start_padding", UIMetrics.SPACE_LG)
	popup.add_theme_constant_override("item_end_padding", UIMetrics.SPACE_LG)
	popup.add_theme_stylebox_override("panel", _style(
		Color(Palette.INK_MID, 0.98), Color(Palette.SURFACE_EDGE, 0.95), 2))
	popup.add_theme_stylebox_override("hover", _style(
		Color(Palette.ACCENT_DIM, 0.78), Color(Palette.ACCENT, 0.45), 1))


func _style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(UIMetrics.RADIUS_MD)
	style.content_margin_left = UIMetrics.SPACE_XL
	style.content_margin_right = UIMetrics.SPACE_XL
	style.content_margin_top = UIMetrics.SPACE_MD
	style.content_margin_bottom = UIMetrics.SPACE_MD
	style.corner_detail = 10
	style.anti_aliasing = true
	return style
