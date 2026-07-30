class_name SplashScreen
extends Control

## Acilis ekrani (~1.3 sn).
##
## Zaman cizelgesi:
##   0.00  neon top ekranin ustunden dusmeye baslar
##   0.34  tek sekme: kucuk cyan kivilcim + ezilme
##   0.78  top yerine oturur, "LumaBounce" logosu scale + fade ile belirir
##   0.96  logodaki kucuk kare hedef kisa sure parlar
##   1.32  [signal finished] -> app_root ana menuye gecer
##
## Kullanici herhangi bir yere dokunursa animasyon atlanir: son kare aninda
## kurulur ve gecis hemen baslar.

signal finished()

@export_group("Zamanlama")
@export var fall_time := 0.34
@export var rise_time := 0.24
@export var settle_time := 0.20
@export var logo_reveal_time := 0.30
@export var floor_fade_out_time := 0.18
@export var glyph_flash_time := 0.42
## Logo tamamen belirdikten sonra menuye gecmeden once beklenen sure.
@export var hold_time := 0.36

@export_group("Yerlesim")
## Tumu ekran merkezine gore (Node2D pivot uzayinda).
@export var start_offset_y := -430.0
@export var impact_offset_y := -70.0
@export var apex_offset_y := -178.0
@export var floor_half_width := 82.0

@export_group("Kivilcim")
@export var spark_count := 6
@export var spark_length := 26.0

@onready var _stage: Control = $Stage
@onready var _pivot: Node2D = $Stage/Pivot
@onready var _floor_line: Line2D = $Stage/Pivot/FloorLine
@onready var _orb: NeonOrb = $Stage/Pivot/Orb
@onready var _logo: LumaLogo = $Logo

var _tween: Tween
var _finished := false


func _ready() -> void:
	_stage.resized.connect(_center_pivot)
	_center_pivot()
	_setup_floor_line()
	_play()


# --- Animasyon ---------------------------------------------------------------

func _play() -> void:
	_orb.position = Vector2(0.0, start_offset_y)
	_orb.modulate.a = 0.0
	_floor_line.modulate.a = 0.0
	_logo.prepare_reveal()

	_tween = create_tween()

	# Dusus: top belirginlesirken zemin cizgisi de hafifce aciliyor.
	_tween.tween_property(_orb, "position:y", impact_offset_y, fall_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_orb, "modulate:a", 1.0, fall_time * 0.45)
	_tween.parallel().tween_property(_floor_line, "modulate:a", 0.55, fall_time * 0.5) \
		.set_delay(fall_time * 0.35)

	# Tek sekme.
	_tween.chain().tween_callback(_on_impact)
	_tween.tween_property(_orb, "position:y", apex_offset_y, rise_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_orb, "position:y", impact_offset_y, settle_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Yumusak konus + logo.
	_tween.tween_callback(_on_settle)
	_tween.tween_callback(_logo.play_reveal.bind(logo_reveal_time))
	_tween.parallel().tween_property(_floor_line, "modulate:a", 0.0, floor_fade_out_time)

	# Kare hedefin kisa parlamasi, ardindan gecis.
	_tween.chain().tween_callback(_logo.flash_glyph.bind(glyph_flash_time))
	_tween.tween_interval(hold_time)
	_tween.tween_callback(_finish)


func _on_impact() -> void:
	_orb.squash(Vector2.UP)
	SparkBurst.burst(
		_pivot, Vector2(0.0, impact_offset_y + _orb.radius), Vector2.UP, 0.9,
		Palette.ACCENT, Palette.ACCENT_CORE, spark_count, spark_length)


func _on_settle() -> void:
	_orb.squash(Vector2.UP, 0.45)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	finished.emit()


# --- Atlama ------------------------------------------------------------------
#
# Dokunma olaylari Control'lar tarafindan yutulmadigi icin hem dokunma hem
# fare olayi ayri ayri gelebilir; _finished bayragi cift tetiklemeyi onler.

func _unhandled_input(event: InputEvent) -> void:
	if _finished:
		return

	var touch := event as InputEventScreenTouch
	if touch != null and touch.pressed:
		_skip()
		return

	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		_skip()
		return

	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_skip()


func _skip() -> void:
	if _finished:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# Son kareyi aninda kur: yarim kalmis bir animasyonla gecis yapilmasin.
	_orb.position = Vector2(0.0, impact_offset_y)
	_orb.modulate.a = 1.0
	_floor_line.modulate.a = 0.0
	_logo.show_revealed()
	_finish()


# --- Yerlesim ----------------------------------------------------------------

func _center_pivot() -> void:
	_pivot.position = _stage.size * 0.5


func _setup_floor_line() -> void:
	_floor_line.points = PackedVector2Array([
		Vector2(-floor_half_width, 0.0),
		Vector2(floor_half_width, 0.0),
	])
	_floor_line.width = 3.0
	_floor_line.default_color = Palette.SURFACE_EDGE
	_floor_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_floor_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_floor_line.antialiased = true
	_floor_line.position = Vector2(0.0, impact_offset_y + _orb.radius)
