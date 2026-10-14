class_name HintPath
extends Node2D

## Satin alinmis ipucunun ornek atis rotasi. Noktalar LevelSolver'dan gelir;
## burada fizik yeniden yazilmaz, yalnizca okunakli bir neon iz cizilir.

@export var glow_width := 11.0
@export var core_width := 3.2
@export var marker_spacing := 76.0
@export var pulse_speed := 2.4

## Ardisik iki nokta arasi bundan uzunsa top portaldan isinlanmistir: solver
## karede en fazla 50 px ilerler (3000 px/sn, 60 FPS), carpisma noktalari da
## arada kalir. Cizgi orada kesilir, yoksa ekrani boydan boya kesen sahte bir
## rota cizilirdi.
const TELEPORT_GAP := 75.0

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
	for run in split_at_teleports(_points):
		if run.size() < 2:
			continue
		draw_polyline(run, Color(Palette.ACCENT, 0.18 + pulse * 0.08), glow_width, true)
		draw_polyline(run, Color(Palette.ACCENT_CORE, 0.78 + pulse * 0.18), core_width, true)

	var distance_since_marker := 0.0
	for i in range(1, _points.size()):
		var from := _points[i - 1]
		var to := _points[i]
		var segment := from.distance_to(to)
		if segment > TELEPORT_GAP:
			# Isinlanma: giris ve cikis noktalarini portal renkleriyle isaretle.
			draw_circle(from, 9.0, Color(Palette.PORTAL_IN, 0.9), false, 3.0, true)
			draw_circle(to, 9.0, Color(Palette.PORTAL_OUT, 0.9), false, 3.0, true)
			continue
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


## Rotayi portal isinlanmalarindan (TELEPORT_GAP) parcalara boler.
static func split_at_teleports(points: PackedVector2Array) -> Array[PackedVector2Array]:
	var runs: Array[PackedVector2Array] = []
	var current := PackedVector2Array()
	for i in points.size():
		if i > 0 and points[i - 1].distance_to(points[i]) > TELEPORT_GAP:
			runs.append(current)
			current = PackedVector2Array()
		current.append(points[i])
	if not current.is_empty():
		runs.append(current)
	return runs


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
