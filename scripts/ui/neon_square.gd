class_name NeonSquare
extends Node2D

## Ici bos neon kare hedef isareti: yumusak hale + buzlu dolgu + net kontur.
##
## target.gd'nin gorsel dilinin sunum amacli, FIZIKSIZ karsiligi. Logo
## kilidinde ve menu dekorunda kullanilir.
## Gorsel dil kurali korunur: top DOLU kure, hedef ICI BOS kare.

@export var square_size := 64.0
@export var corner_radius := 14.0
@export var accent := Palette.ACCENT
@export var core_color := Palette.ACCENT_CORE
@export var outline_width := 2.6
## Buton gibi degil, havada duran net bir isaret gibi dursun diye hale kucuk.
@export var glow_scale := 1.55

var _glow: Node2D
var _idle_tween: Tween
var _flash_tween: Tween


func _ready() -> void:
	_rebuild()


## Cok yavas, sakin bir nabiz. Sadece hale katmani olceklenir.
func start_idle_pulse(peak := 1.07, duration := 2.8) -> void:
	if _glow == null:
		return
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_property(_glow, "scale", Vector2.ONE * peak, duration * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(_glow, "scale", Vector2.ONE, duration * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Tek seferlik kisa parlama (splash'te logo belirdikten sonra).
func flash(duration := 0.45) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	scale = Vector2.ONE
	modulate = Color.WHITE

	_flash_tween = create_tween()
	_flash_tween.set_parallel(true)
	_flash_tween.tween_property(self, "scale", Vector2.ONE * 1.26, duration * 0.34) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(self, "modulate", Color(1.45, 1.4, 1.4, 1.0), duration * 0.28)
	_flash_tween.chain().tween_property(self, "scale", Vector2.ONE, duration * 0.66) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_flash_tween.parallel().tween_property(self, "modulate", Color.WHITE, duration * 0.66)


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	_glow = Node2D.new()
	_glow.name = "Glow"
	add_child(_glow)
	_glow.add_child(_make_square(glow_scale, Color(accent, 0.05)))
	_glow.add_child(_make_square(glow_scale * 0.74, Color(accent, 0.09)))

	# Buzlu cam dolgusu + net neon kontur.
	add_child(_make_square(1.0, Color(accent, 0.14)))
	add_child(ShapeBuilder.make_outline(
		ShapeBuilder.rounded_rect(Vector2.ONE * square_size, corner_radius, 6),
		accent, outline_width))

	# Merkezdeki kucuk parlak nokta.
	add_child(_make_square(0.28, Color(core_color, 0.9)))


func _make_square(scale_factor: float, color: Color) -> Polygon2D:
	return ShapeBuilder.make_polygon(
		ShapeBuilder.rounded_rect(
			Vector2.ONE * square_size * scale_factor, corner_radius * scale_factor, 6),
		color)
