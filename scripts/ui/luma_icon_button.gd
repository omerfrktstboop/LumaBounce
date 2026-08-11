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
## BELIRGIN muamele: koyu dolgu + vurgu renginde halka + disinda hafif isima.
##
## Neden secenek: menu ikonlari sakin bir zeminde durur ve sessiz kalmalari
## dogrudur. Oynanis HUD'u ise arenanin uzerindedir; orada ayni sessiz stil
## "pasif buton" gibi okunuyordu. Varsayilan false, yani mevcut ekranlarin
## gorunumu DEGISMEZ.
@export var prominent := false:
	set(value):
		prominent = value
		if is_node_ready():
			_apply_prominence()
## Belirgin halde ikonun ve halkanin rengi.
@export var prominent_accent := Palette.ACCENT

var _icon: GlyphIcon
var _halo: Panel


func _ready() -> void:
	# Ikon butonlari her zaman yuvarlak ve metin bosluksuzdur.
	circular = true
	content_margin = Vector2.ZERO
	super._ready()
	_build_icon()
	_apply_prominence()
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


## Isima, butonun ARKASINDA duran ayri bir Panel'dir; StyleBox kenarini
## kalinlastirmak yerine boyle yapiliyor cunku kenari kalinlastirmak butonun
## basis animasyonunda da olceklenir ve titrer.
func _apply_prominence() -> void:
	if not prominent:
		if _halo != null and is_instance_valid(_halo):
			_halo.queue_free()
			_halo = null
		if _icon != null:
			_icon.color = idle_color
		return

	if _halo == null or not is_instance_valid(_halo):
		_halo = Panel.new()
		_halo.name = "Halo"
		_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_halo.show_behind_parent = true
		add_child(_halo)
		move_child(_halo, 0)
	var radius := int(maxf(size.x, size.y) * 0.5) + 6
	var style := StyleBoxFlat.new()
	style.bg_color = Color(prominent_accent, 0.0)
	style.border_color = Color(prominent_accent, 0.16)
	style.set_border_width_all(5)
	style.set_corner_radius_all(radius)
	style.corner_detail = 12
	style.anti_aliasing = true
	_halo.add_theme_stylebox_override("panel", style)
	_halo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_halo.offset_left = -5.0
	_halo.offset_top = -5.0
	_halo.offset_right = 5.0
	_halo.offset_bottom = 5.0

	idle_color = prominent_accent
	active_color = Palette.ACCENT_CORE
	if _icon != null:
		_icon.color = idle_color
		_icon.stroke_width = 3.0
	# Kenari vurgu renginde ve dolguyu koyu yapmak icin PRIMARY yeterli:
	# LumaButton zaten birincil vurguda cyan kenar ciziyor.
	emphasis = LumaButton.Emphasis.PRIMARY
	high_contrast = true


func _set_hovered(hovered: bool) -> void:
	if _icon != null:
		_icon.color = active_color if hovered else idle_color
