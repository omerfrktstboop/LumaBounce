class_name RestartIcon
extends Control

## Prosedurel "yeniden baslat" ikonu: donen tek bir ok.
## Harici asset kullanilmaz; _draw() ile Control'un boyutuna gore cizilir.

@export var stroke_color := Palette.TEXT
@export var stroke_width := 3.6
@export var arrow_size := 8.0
@export_range(0.3, 0.9, 0.01) var radius_ratio := 0.62
@export var start_deg := -35.0
@export var end_deg := 225.0


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 * radius_ratio
	var start_rad := deg_to_rad(start_deg)
	var end_rad := deg_to_rad(end_deg)
	draw_arc(center, radius, start_rad, end_rad, 24, stroke_color, stroke_width, true)

	# Yayin bittigi noktada, tesetten (tangent) yonlu kucuk bir ok ucu.
	var tip := center + Vector2(cos(end_rad), sin(end_rad)) * radius
	var tangent := Vector2(-sin(end_rad), cos(end_rad))
	var outward := Vector2(cos(end_rad), sin(end_rad))
	var p1 := tip + tangent * arrow_size - outward * arrow_size * 0.35
	var p2 := tip - tangent * arrow_size - outward * arrow_size * 0.35
	var p3 := tip + outward * arrow_size * 0.85
	draw_polygon(PackedVector2Array([p1, p2, p3]), PackedColorArray([stroke_color]))
