class_name AimGuide
extends Node2D

## Ince, noktali nisan kilavuzu.
##
## Line2D gercek "dotted" gorunum veremedigi icin noktalar dogrudan
## _draw() ile cizilir. Launcher yorungeyi esit ARC uzunluklarinda
## ornekleyip buraya iletir; boylece hiz ne olursa olsun noktalar
## ekranda esit araliklarla gorunur.

@export var dot_radius := 4.0
## Uzaktaki noktalarin kucultme orani.
@export_range(0.3, 1.0, 0.01) var far_scale := 0.55
## Firlaticiya en yakin noktanin opakligi.
@export_range(0.0, 1.0, 0.01) var near_alpha := 0.95
## En uzak noktanin opakligi.
@export_range(0.0, 1.0, 0.01) var far_alpha := 0.12

var _dots := PackedVector2Array()
var _color := Palette.ACCENT


func set_guide(dots: PackedVector2Array, color: Color) -> void:
	_dots = dots
	_color = color
	queue_redraw()


func clear_guide() -> void:
	if _dots.is_empty():
		return
	_dots = PackedVector2Array()
	queue_redraw()


func _draw() -> void:
	var count := _dots.size()
	if count == 0:
		return
	var last := float(maxi(count - 1, 1))
	for i in count:
		var t := float(i) / last
		draw_circle(
			_dots[i],
			lerpf(dot_radius, dot_radius * far_scale, t),
			Color(_color, lerpf(near_alpha, far_alpha, t)))
