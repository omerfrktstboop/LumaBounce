class_name HintPath
extends Node2D

## Satin alinmis ipucunun ornek atis rotasi. Noktalar LevelSolver'dan gelir;
## burada fizik yeniden yazilmaz, yalnizca okunakli bir neon iz cizilir.

@export var glow_width := 11.0
@export var core_width := 3.2
@export var marker_spacing := 76.0
@export var pulse_speed := 2.4

var _points := PackedVector2Array()
var _pulse_time := 0.0


func _ready() -> void:
	hide_path()


func show_path(points: PackedVector2Array) -> void:
	_points = _simplify(points)
	if _points.size() < 2:
		hide_path()
		return
	_pulse_time = 0.0
	show()
	set_process(true)
	queue_redraw()


func hide_path() -> void:
	_points.clear()
	hide()
	set_process(false)
	queue_redraw()


func is_showing() -> bool:
	return visible and _points.size() >= 2


func _process(delta: float) -> void:
	_pulse_time += delta * pulse_speed
	queue_redraw()


func _draw() -> void:
	if _points.size() < 2:
		return
	var pulse := (sin(_pulse_time) + 1.0) * 0.5
	draw_polyline(_points, Color(Palette.ACCENT, 0.18 + pulse * 0.08), glow_width, true)
	draw_polyline(_points, Color(Palette.ACCENT_CORE, 0.78 + pulse * 0.18), core_width, true)

	var distance_since_marker := 0.0
	for i in range(1, _points.size()):
		var from := _points[i - 1]
		var to := _points[i]
		var segment := from.distance_to(to)
		while distance_since_marker + segment >= marker_spacing:
			var needed := marker_spacing - distance_since_marker
			var marker := from.lerp(to, needed / maxf(segment, 0.001))
			draw_circle(marker, 5.0 + pulse * 1.5, Color(Palette.ACCENT_CORE, 0.9))
			from = marker
			segment = from.distance_to(to)
			distance_since_marker = 0.0
		distance_since_marker += segment

	draw_circle(_points[0], 10.0, Color(Palette.ACCENT, 0.28), false, 3.0, true)
	draw_circle(_points[-1], 14.0 + pulse * 2.0, Color(Palette.ACCENT_CORE, 0.9), false, 3.0, true)


## Solver her uc fizik karesinde bir nokta verir. Cizgi icin birbirine cok
## yakin noktalar gereksizdir; carpisma koselerini koruyup duz kismi seyrelt.
func _simplify(source: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	if source.is_empty():
		return result
	result.append(source[0])
	for i in range(1, source.size() - 1):
		if result[-1].distance_to(source[i]) >= 10.0:
			result.append(source[i])
	if source.size() > 1 and result[-1].distance_to(source[-1]) > 0.5:
		result.append(source[-1])
	return result
