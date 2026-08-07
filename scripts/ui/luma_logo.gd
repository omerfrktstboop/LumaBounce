class_name LumaLogo
extends Control

## "LumaBounce" logo kilidi: kucuk neon kare hedef + kelime isareti.
##
## Ayni bilesen hem splash hem ana menude kullanilir. Kare hedef, oyunun
## gorsel dilinden dogrudan alinir (bkz. [NeonSquare]) - boylece logo ile
## oynanis ayni kimligi paylasir.

@export var text := "LumaBounce"
@export var font_size := 60
@export var glyph_size := 40.0
@export var separation := 20.0
@export var text_color := Palette.TEXT
## Gizli baslangic durumunun olcegi (play_reveal buradan 1.0'a acilir).
@export_range(0.1, 1.0, 0.01) var hidden_scale := 0.82

var _row: HBoxContainer
var _glyph_slot: Control
var _glyph: NeonSquare
var _label: Label
var _reveal_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	resized.connect(_center_pivot)
	_center_pivot()


# --- Dis API -----------------------------------------------------------------

## Logoyu gizli baslangic durumuna alir (splash icin).
func prepare_reveal() -> void:
	_kill_reveal()
	_center_pivot()
	scale = Vector2.ONE * hidden_scale
	modulate.a = 0.0


## Scale + fade ile belirir.
func play_reveal(duration := 0.3) -> void:
	_kill_reveal()
	_center_pivot()
	_reveal_tween = create_tween()
	_reveal_tween.set_parallel(true)
	_reveal_tween.tween_property(self, "scale", Vector2.ONE, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_property(self, "modulate:a", 1.0, duration * 0.75)


## Animasyonu atlayip son duruma aninda gecer.
func show_revealed() -> void:
	_kill_reveal()
	_center_pivot()
	scale = Vector2.ONE
	modulate.a = 1.0


func flash_glyph(duration := 0.45) -> void:
	if _glyph != null:
		_glyph.flash(duration)


func start_glyph_pulse() -> void:
	if _glyph != null:
		_glyph.start_idle_pulse()


# --- Ic isleyis --------------------------------------------------------------

func _build() -> void:
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", int(separation))
	add_child(_row)
	# set_anchors_PRESET degil, set_anchors_AND_OFFSETS_preset: birincisi
	# capalari degistirirken offsetleri korudugu icin satir kendi icerik
	# genisliginde (720 yerine 440 px) kaliyordu. Boyle olunca
	# ALIGNMENT_CENTER'in ortalayacagi bos alan olmuyor ve logo kilidi
	# ekranin sol kenarina yapisiyordu.
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Kare hedef, satir yuksekliginden bagimsiz olarak kendi boyutunda kalsin.
	_glyph_slot = Control.new()
	_glyph_slot.name = "GlyphSlot"
	_glyph_slot.custom_minimum_size = Vector2.ONE * glyph_size
	_glyph_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_glyph_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_glyph_slot)

	_glyph = NeonSquare.new()
	_glyph.name = "Glyph"
	_glyph.square_size = glyph_size
	_glyph.corner_radius = glyph_size * 0.26
	_glyph.outline_width = 2.4
	_glyph_slot.add_child(_glyph)
	_glyph_slot.resized.connect(_center_glyph)
	_center_glyph()

	_label = Label.new()
	_label.name = "Wordmark"
	_label.text = text
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", text_color)
	_row.add_child(_label)


func _center_glyph() -> void:
	if _glyph != null:
		_glyph.position = _glyph_slot.size * 0.5


## Olcek animasyonlari merkezden buyusun diye pivot hep ortada tutulur.
func _center_pivot() -> void:
	pivot_offset = size * 0.5


func _kill_reveal() -> void:
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
