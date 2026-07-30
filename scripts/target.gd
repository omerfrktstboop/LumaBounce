class_name Target
extends Area2D

## Ekranin ustundeki parlayan kare hedef.
##
## Gorsel dil: top DOLU bir kure, hedef ise ICI BOS neon bir kare.
## Ikisi ayni vurgu rengini paylasir ama silueti farklidir; oyuncu
## bir bakista hangisinin ne oldugunu ayirt eder.
##
## Fiziksel carpisma yapmaz; sadece "ball" grubundaki cismi algilar ve
## [signal hit] yayar. Durdurma karari gameplay.gd'ye aittir.

signal hit(body: Node2D)

@export var size := 92.0
@export var corner_radius := 20.0

@export_group("Gorunum")
@export var accent := Palette.ACCENT
@export var core_color := Palette.ACCENT_CORE
## Isabet ve basari icin ikincil vurgu.
@export var success_color := Palette.ACCENT_ALT
@export var outline_width := 3.5
@export var glow_scale := 2.0

@export_group("Animasyon")
@export var idle_scale := 1.06
@export var idle_time := 2.2
@export var hit_scale := 1.45
@export var hit_time := 0.45
@export var ring_scale := 2.8
@export var ring_time := 0.55

@onready var _shape: CollisionShape2D = $Shape
@onready var _visual: Node2D = $Visual

var _glow_group: Node2D
var _core: Polygon2D
var _ring: Line2D
var _idle_tween: Tween
var _hit_tween: Tween
var _ring_tween: Tween
var _already_hit := false


func _ready() -> void:
	_apply_shape()
	_build_visual()
	body_entered.connect(_on_body_entered)
	_start_idle_pulse()


# --- Dis API -----------------------------------------------------------------

func reset() -> void:
	_already_hit = false
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	if _ring_tween != null and _ring_tween.is_valid():
		_ring_tween.kill()
	_visual.scale = Vector2.ONE
	_visual.modulate = Color.WHITE
	_glow_group.scale = Vector2.ONE
	_ring.scale = Vector2.ONE
	_ring.modulate.a = 0.0
	_start_idle_pulse()


## Temiz kazanma efekti: kisa buyume + parlama + disa acilan menekse halka.
func play_hit_effect() -> void:
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	_visual.scale = Vector2.ONE
	_visual.modulate = Color.WHITE

	_hit_tween = create_tween()
	_hit_tween.set_parallel(true)
	_hit_tween.tween_property(_visual, "scale", Vector2.ONE * hit_scale, hit_time * 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hit_tween.tween_property(_visual, "modulate", Color(1.55, 1.5, 1.5, 1.0), hit_time * 0.2)
	_hit_tween.chain().tween_property(_visual, "scale", Vector2.ONE * 1.1, hit_time * 0.65) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hit_tween.parallel().tween_property(_visual, "modulate", Color.WHITE, hit_time * 0.65)

	_play_ring()


# --- Ic isleyis --------------------------------------------------------------

func _on_body_entered(body: Node2D) -> void:
	if _already_hit or not body.is_in_group("ball"):
		return
	_already_hit = true
	play_hit_effect()
	hit.emit(body)


func _apply_shape() -> void:
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size, size)
	_shape.shape = rect


func _build_visual() -> void:
	for child in _visual.get_children():
		child.queue_free()

	# 1) Kontrollu dis hale (nabiz gibi yavasca atar).
	_glow_group = Node2D.new()
	_glow_group.name = "Glow"
	_visual.add_child(_glow_group)
	_glow_group.add_child(_make_square(glow_scale, Color(accent, 0.045)))
	_glow_group.add_child(_make_square(glow_scale * 0.76, Color(accent, 0.075)))
	_glow_group.add_child(_make_square(glow_scale * 0.58, Color(accent, 0.12)))

	# 2) Buzlu cam dolgusu + net neon kontur.
	_visual.add_child(_make_square(1.0, Color(accent, 0.14)))
	_visual.add_child(ShapeBuilder.make_outline(
		ShapeBuilder.rounded_rect(Vector2.ONE * size, corner_radius, 7),
		accent, outline_width))

	# 3) Merkezdeki parlak nokta: "tam burasi" isareti.
	_core = _make_square(0.26, Color(core_color, 0.9))
	_visual.add_child(_core)

	# 4) Isabet halkasi (normalde gorunmez).
	_ring = ShapeBuilder.make_outline(
		ShapeBuilder.rounded_rect(Vector2.ONE * size, corner_radius, 7),
		success_color, outline_width)
	_ring.modulate.a = 0.0
	_visual.add_child(_ring)


func _make_square(scale_factor: float, color: Color) -> Polygon2D:
	return ShapeBuilder.make_polygon(
		ShapeBuilder.rounded_rect(
			Vector2.ONE * size * scale_factor, corner_radius * scale_factor, 7),
		color)


func _start_idle_pulse() -> void:
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_property(_glow_group, "scale", Vector2.ONE * idle_scale, idle_time * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(_glow_group, "scale", Vector2.ONE, idle_time * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _play_ring() -> void:
	if _ring_tween != null and _ring_tween.is_valid():
		_ring_tween.kill()
	_ring.scale = Vector2.ONE
	_ring.modulate.a = 0.85
	_ring_tween = create_tween()
	_ring_tween.set_parallel(true)
	_ring_tween.tween_property(_ring, "scale", Vector2.ONE * ring_scale, ring_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_ring_tween.tween_property(_ring, "modulate:a", 0.0, ring_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
