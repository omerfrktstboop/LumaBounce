class_name LivesDisplay
extends Control

## Kalan top hakkini sade noktalarla gosteren HUD gostergesi.
##
## Bilerek notr renklerde: bu bir HUD bilgisi, "tek vurgu" kuralinin
## kapsadigi top/hedef/nisan cizgisi degil - bu yuzden neon kullanmaz.

@export var pip_radius := 7.0
@export var pip_spacing := 24.0
@export var filled_color := Palette.TEXT
@export var empty_color := Color(Palette.TEXT_DIM, 0.35)

var _total := 5
var _remaining := 5


func set_lives(remaining: int, total: int) -> void:
	_remaining = remaining
	_total = total
	queue_redraw()


func _draw() -> void:
	for i in _total:
		var x := pip_radius + pip_spacing * float(i)
		var color := filled_color if i < _remaining else empty_color
		draw_circle(Vector2(x, pip_radius), pip_radius, color)
