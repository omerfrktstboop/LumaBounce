class_name GlyphIcon
extends Control

## Prosedurel UI ikonlari. Harici asset yok; hepsi Control'un boyutuna gore
## _draw() ile cizilir (bkz. ayni desen: restart_icon.gd).

enum Glyph {
	SOUND_ON,
	SOUND_OFF,
	SETTINGS,
	HOME,
	CHECK,
}

@export var glyph: Glyph = Glyph.SETTINGS:
	set(value):
		glyph = value
		queue_redraw()
@export var color := Palette.TEXT_DIM:
	set(value):
		color = value
		queue_redraw()
@export var stroke_width := 2.8


func _draw() -> void:
	var center := size * 0.5
	var unit := minf(size.x, size.y) * 0.5
	if unit <= 0.0:
		return

	match glyph:
		Glyph.SOUND_ON:
			_draw_speaker(center, unit, true)
		Glyph.SOUND_OFF:
			_draw_speaker(center, unit, false)
		Glyph.SETTINGS:
			_draw_gear(center, unit)
		Glyph.HOME:
			_draw_home(center, unit)
		Glyph.CHECK:
			_draw_check(center, unit)


func _draw_speaker(center: Vector2, unit: float, sound_on: bool) -> void:
	var body := PackedVector2Array([
		center + Vector2(-unit * 0.78, -unit * 0.26),
		center + Vector2(-unit * 0.34, -unit * 0.26),
		center + Vector2(unit * 0.06, -unit * 0.68),
		center + Vector2(unit * 0.06, unit * 0.68),
		center + Vector2(-unit * 0.34, unit * 0.26),
		center + Vector2(-unit * 0.78, unit * 0.26),
	])
	draw_colored_polygon(body, color)

	if sound_on:
		var arc_center := center + Vector2(unit * 0.1, 0.0)
		draw_arc(arc_center, unit * 0.44, -PI * 0.42, PI * 0.42, 16, color, stroke_width, true)
		draw_arc(arc_center, unit * 0.74, -PI * 0.40, PI * 0.40, 20, color, stroke_width, true)
		return

	# Kapali: kucuk bir carpi.
	var a := center + Vector2(unit * 0.34, -unit * 0.30)
	var b := center + Vector2(unit * 0.82, unit * 0.30)
	draw_line(a, b, color, stroke_width, true)
	draw_line(Vector2(a.x, b.y), Vector2(b.x, a.y), color, stroke_width, true)


func _draw_home(center: Vector2, unit: float) -> void:
	# Cati: tek parca ucgen.
	var roof := PackedVector2Array([
		center + Vector2(0.0, -unit * 0.78),
		center + Vector2(unit * 0.84, -unit * 0.02),
		center + Vector2(-unit * 0.84, -unit * 0.02),
	])
	draw_colored_polygon(roof, color)

	# Govde: ince konturlu kutu.
	var half := unit * 0.5
	var top := -unit * 0.02
	var bottom := unit * 0.72
	var box := PackedVector2Array([
		center + Vector2(-half, top),
		center + Vector2(half, top),
		center + Vector2(half, bottom),
		center + Vector2(-half, bottom),
		center + Vector2(-half, top),
	])
	draw_polyline(box, color, stroke_width, true)


func _draw_check(center: Vector2, unit: float) -> void:
	var points := PackedVector2Array([
		center + Vector2(-unit * 0.62, unit * 0.02),
		center + Vector2(-unit * 0.16, unit * 0.48),
		center + Vector2(unit * 0.64, -unit * 0.46),
	])
	draw_polyline(points, color, stroke_width, true)


func _draw_gear(center: Vector2, unit: float) -> void:
	var ring_radius := unit * 0.46
	draw_arc(center, ring_radius, 0.0, TAU, 28, color, stroke_width, true)

	var teeth := 8
	for i in teeth:
		var angle := TAU * float(i) / float(teeth)
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(
			center + direction * (ring_radius + stroke_width * 0.5),
			center + direction * (unit * 0.88),
			color, stroke_width, true)
