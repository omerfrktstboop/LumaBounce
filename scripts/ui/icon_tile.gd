class_name IconTile
extends PanelContainer

## Kucuk yuvarlatilmis kare yuzey icinde bir GlyphIcon (marka rehberi SS16).
## NavigationCard, magaza "Reklamlari Kaldir" karti ve Ayarlar aksiyon
## satirlarinda ikon tek basina degil bu yuzeyin icinde kullanilir.

@export var glyph: GlyphIcon.Glyph = GlyphIcon.Glyph.SETTINGS:
	set(value):
		glyph = value
		if _icon != null:
			_icon.glyph = value
## Alfasi 0 iken (varsayilan) Palette.TEXT kullanilir.
@export var icon_color := Color(0.0, 0.0, 0.0, 0.0):
	set(value):
		icon_color = value
		if _icon != null:
			_icon.color = value if value.a > 0.0 else Palette.TEXT
## Karo zemini. Alfasi 0 iken Palette.SURFACE_ELEVATED kullanilir.
@export var tile_accent := Color(0.0, 0.0, 0.0, 0.0)
@export var tile_size := 48.0
## Sifirdan buyukse kare yerine yatay rozet olusturur. Normal navigasyon
## ikonlari kare kalir; premium kart gibi vurgu alanlari genisleyebilir.
@export var tile_width := 0.0
@export var icon_inset := 12.0

var _icon: GlyphIcon


func _ready() -> void:
	custom_minimum_size = Vector2(tile_width if tile_width > 0.0 else tile_size, tile_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	if tile_accent.a > 0.0:
		style.bg_color = Color(tile_accent, 0.22)
	else:
		style.bg_color = Color(Palette.SURFACE_ELEVATED, 0.9)
	style.set_corner_radius_all(UIMetrics.RADIUS_MD)
	style.corner_detail = 8
	style.anti_aliasing = true
	style.content_margin_left = icon_inset
	style.content_margin_top = icon_inset
	style.content_margin_right = icon_inset
	style.content_margin_bottom = icon_inset
	add_theme_stylebox_override("panel", style)

	_icon = GlyphIcon.new()
	_icon.glyph = glyph
	_icon.color = icon_color if icon_color.a > 0.0 else Palette.TEXT
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
