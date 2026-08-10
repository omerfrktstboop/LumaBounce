class_name LevelSolutionOverlay
extends Node2D

enum Mode { OFF, MAIN, ALTERNATIVE }

var _routes: Array[Dictionary] = []
var _mode := Mode.OFF
var _route_index := -1


func set_routes(routes: Array[Dictionary]) -> void:
	_routes.assign(routes)
	_mode = Mode.OFF
	_route_index = -1
	queue_redraw()


func clear() -> void:
	_routes.clear()
	_mode = Mode.OFF
	_route_index = -1
	queue_redraw()


func show_main() -> void:
	_mode = Mode.MAIN if not _routes.is_empty() else Mode.OFF
	_route_index = 0 if not _routes.is_empty() else -1
	queue_redraw()


func cycle() -> int:
	if _routes.is_empty():
		_mode = Mode.OFF
		_route_index = -1
	elif _mode == Mode.OFF:
		_mode = Mode.MAIN
		_route_index = 0
	elif _route_index + 1 < _routes.size():
		_mode = Mode.ALTERNATIVE
		_route_index += 1
	else:
		_mode = Mode.OFF
		_route_index = -1
	queue_redraw()
	return _mode


func get_mode() -> int:
	return _mode


func has_routes() -> bool:
	return not _routes.is_empty()


func has_alternative() -> bool:
	return _routes.size() > 1


func route_count() -> int:
	return _routes.size()


func current_index() -> int:
	return _route_index


func current_info() -> String:
	var route := _current_route()
	if route.is_empty():
		return "Cozum kapali"
	var broken: PackedInt32Array = route.get("broken_order", PackedInt32Array())
	var block_text := "yok"
	if not broken.is_empty():
		var labels := PackedStringArray()
		for index in broken:
			labels.append(str(index + 1))
		block_text = " -> ".join(labels)
	elif int(route.get("prebroken_count", 0)) > 0:
		block_text = "%d onceden kirik" % int(route["prebroken_count"])
	var search_text := ""
	if int(route.get("solution_search_passes", 1)) > 1:
		search_text = "  Hassas %.1f derece/%.0f guc" % [
			float(route.get("solution_angle_step", 0.0)),
			float(route.get("solution_power_step", 0.0))]
	var score_text := ""
	if route.has("difficulty_score"):
		score_text = "  Skor %d/100 %s  Toplam cozum %d" % [
			int(route.get("difficulty_score", 0)),
			String(route.get("difficulty_label", "")),
			int(route.get("solution_count", 0))]
	return "%s | Aci %.1f..%.1f  Guc %.0f..%.0f  Sekme %d  Saglam %d  Blok %s%s%s" % [
		String(route.get("label", "Rota")),
		float(route.get("angle_lo", 0.0)), float(route.get("angle_hi", 0.0)),
		float(route.get("power_lo", 0.0)), float(route.get("power_hi", 0.0)),
		int(route.get("bounces", 0)), int(route.get("robust", 0)), block_text,
		search_text, score_text,
	]


func _draw() -> void:
	var route := _current_route()
	if route.is_empty():
		return
	var points: PackedVector2Array = route.get("trace_points", PackedVector2Array())
	if points.size() >= 2:
		var color := Palette.ACCENT if _route_index == 0 else Palette.ACCENT_ALT
		draw_polyline(points, Color(color, 0.88), 4.0, true)
	var font := ThemeDB.fallback_font
	var collisions: Array = route.get("collision_points", [])
	for i in collisions.size():
		var point: Vector2 = collisions[i].get("position", Vector2.ZERO)
		draw_circle(point, 9.0, Palette.ACCENT_CORE)
		draw_string(font, point + Vector2(12, -8), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.TEXT)
	var hit: Vector2 = route.get("target_hit_position", Vector2.ZERO)
	if hit != Vector2.ZERO:
		draw_circle(hit, 13.0, Color(Palette.ACCENT_ALT, 0.95), false, 4.0, true)


func _current_route() -> Dictionary:
	if _mode != Mode.OFF and _route_index >= 0 and _route_index < _routes.size():
		return _routes[_route_index]
	return {}
