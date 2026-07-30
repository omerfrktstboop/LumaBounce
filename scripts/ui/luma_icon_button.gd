class_name LumaIconButton
extends LumaButton

## Metin yerine prosedurel bir ikon tasiyan, tam yuvarlak kucuk buton.
## [LumaButton]'un basis animasyonunu ve cyan kenar vurgusunu aynen devralir.

@export var glyph: GlyphIcon.Glyph = GlyphIcon.Glyph.SETTINGS:
	set(value):
		glyph = value
		if _icon != null:
			_icon.glyph = value
@export var icon_inset := 18.0
@export var idle_color := Palette.TEXT_DIM
@export var active_color := Palette.TEXT

var _icon: GlyphIcon


func _ready() -> void:
	# Ikon butonlari her zaman yuvarlak ve metin bosluksuzdur.
	circular = true
	content_margin = Vector2.ZERO
	super._ready()
	_build_icon()
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))


func _build_icon() -> void:
	_icon = GlyphIcon.new()
	_icon.name = "Glyph"
	_icon.glyph = glyph
	_icon.color = idle_color
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = icon_inset
	_icon.offset_top = icon_inset
	_icon.offset_right = -icon_inset
	_icon.offset_bottom = -icon_inset


func _set_hovered(hovered: bool) -> void:
	if _icon != null:
		_icon.color = active_color if hovered else idle_color
