class_name NeonOrb
extends Node2D

## Neon camgobegi kure: icten aydinlanmis govde + disa yumusayan hale.
##
## ball.gd'nin gorsel dilinin sunum amacli, FIZIKSIZ karsiligi. Splash
## animasyonunda ve menu dekorunda kullanilir; oyun ici topa hic dokunmaz.

@export var radius := 26.0
@export var accent := Palette.ACCENT
@export var core_color := Palette.ACCENT_CORE
## Dis halenin yaricap carpani.
@export var glow_scale := 2.2
@export var squash_amount := 0.18
@export var squash_time := 0.18

var _shell: Node2D
var _squash_tween: Tween


func _ready() -> void:
	_rebuild()


## Carpma yonune dik kisa bir ezilme. [param strength] 0..1 arasi olcekler.
func squash(normal: Vector2, strength := 1.0) -> void:
	if _shell == null:
		return
	if _squash_tween != null and _squash_tween.is_valid():
		_squash_tween.kill()

	var amount := squash_amount * clampf(strength, 0.0, 1.0)
	_shell.rotation = normal.angle() + PI * 0.5
	_shell.scale = Vector2(1.0 + amount, 1.0 - amount)
	_squash_tween = create_tween()
	_squash_tween.tween_property(_shell, "scale", Vector2.ONE, squash_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	_shell = Node2D.new()
	_shell.name = "Shell"
	add_child(_shell)

	# Kontrollu hale katmanlari (disaridan iceriye) - asiri neon degil.
	var halos := [
		{"scale": glow_scale, "alpha": 0.05},
		{"scale": glow_scale * 0.72, "alpha": 0.09},
		{"scale": glow_scale * 0.53, "alpha": 0.16},
	]
	for halo in halos:
		var halo_scale: float = halo["scale"]
		var halo_alpha: float = halo["alpha"]
		_shell.add_child(ShapeBuilder.make_polygon(
			ShapeBuilder.circle(radius * halo_scale, 40), Color(accent, halo_alpha)))

	_shell.add_child(ShapeBuilder.make_polygon(
		ShapeBuilder.circle(radius, 40), accent))
	_shell.add_child(ShapeBuilder.make_polygon(
		ShapeBuilder.circle(radius * 0.52, 28), Color(core_color, 0.92)))
