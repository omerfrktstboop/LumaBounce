class_name AILevelMapper
extends RefCounted

## AI JSON'unu yalnizca izinli veri alanlarindan yeni LevelData kaynaklarina
## donusturur. Model ciktisindan path, script veya resource yuklenmez.

const PANEL_THICKNESS := 26.0
const BLOCK_HEIGHT := 44.0
const MIN_WALL_GAP := 96.0
const WALL_MIN_Y := 120.0
const WALL_MAX_Y := 1160.0


func map_document(document: Dictionary) -> Dictionary:
	var raw_levels = document.get("levels", null)
	if not raw_levels is Array:
		return {"ok": false, "blueprints": [], "errors": ["levels dizisi eksik."]}
	if raw_levels.is_empty() or raw_levels.size() > AILevelContract.MAX_LEVELS:
		return {
			"ok": false,
			"blueprints": [],
			"errors": ["Taslak sayisi 1-%d araliginda olmali." % AILevelContract.MAX_LEVELS],
		}

	var blueprints: Array[Dictionary] = []
	var errors := PackedStringArray()
	for i in raw_levels.size():
		var mapped := map_blueprint(raw_levels[i], i)
		if bool(mapped["ok"]):
			blueprints.append(mapped["blueprint"])
		else:
			errors.append("Taslak %d: %s" % [i + 1, String(mapped["error"])])
	return {
		"ok": not blueprints.is_empty(),
		"blueprints": blueprints,
		"errors": errors,
	}


func map_blueprint(raw: Variant, index := 0) -> Dictionary:
	if not raw is Dictionary:
		return _error("obje olmali.")
	for required in ["display_name", "launcher", "target", "panels", "blocks"]:
		if not raw.has(required):
			return _error("%s eksik." % required)
	if not raw["display_name"] is String:
		return _error("display_name metin olmali.")
	if not raw["panels"] is Array or not raw["blocks"] is Array:
		return _error("panels ve blocks dizi olmali.")
	if not raw.get("obstacles", []) is Array:
		return _error("obstacles dizi olmali.")
	if raw["panels"].size() > AILevelContract.MAX_PANELS:
		return _error("en fazla %d panel kullanilabilir." % AILevelContract.MAX_PANELS)
	if raw["blocks"].size() > AILevelContract.MAX_BLOCKS:
		return _error("en fazla %d blok kullanilabilir." % AILevelContract.MAX_BLOCKS)
	if raw.get("obstacles", []).size() > AILevelContract.MAX_OBSTACLES:
		return _error("en fazla %d engel kullanilabilir." % AILevelContract.MAX_OBSTACLES)

	var launcher := _map_point(raw["launcher"], Vector2(100.0, 980.0), Vector2(620.0, 1180.0))
	if not bool(launcher["ok"]):
		return _error("launcher %s" % launcher["error"])
	var target := _map_point(raw["target"], Vector2(80.0, 180.0), Vector2(640.0, 560.0))
	if not bool(target["ok"]):
		return _error("target %s" % target["error"])

	var panels: Array[PanelData] = []
	for i in raw["panels"].size():
		var mapped_panel := _map_panel(raw["panels"][i])
		if not bool(mapped_panel["ok"]):
			return _error("panel %d %s" % [i + 1, mapped_panel["error"]])
		panels.append(mapped_panel["value"])

	var blocks: Array[BreakableBlockData] = []
	for i in raw["blocks"].size():
		var mapped_block := _map_block(raw["blocks"][i])
		if not bool(mapped_block["ok"]):
			return _error("blok %d %s" % [i + 1, mapped_block["error"]])
		blocks.append(mapped_block["value"])

	var obstacles: Array[ObstacleData] = []
	for i in raw.get("obstacles", []).size():
		var mapped_obstacle := _map_obstacle(raw["obstacles"][i])
		if not bool(mapped_obstacle["ok"]):
			return _error("engel %d %s" % [i + 1, mapped_obstacle["error"]])
		obstacles.append(mapped_obstacle["value"])

	var level := LevelData.new()
	# level_id bilerek AI'dan okunmaz; resmi ilerleme kimligi olamaz.
	level.level_id = 1
	level.display_name = _safe_text(raw["display_name"], AILevelContract.MAX_DISPLAY_NAME)
	if level.display_name.is_empty():
		level.display_name = "AI Taslak %d" % (index + 1)
	level.launcher_position = launcher["value"]
	level.target_position = target["value"]
	level.panels = panels
	level.breakable_blocks = blocks
	level.obstacles = obstacles
	level.left_wall_segments = _map_wall_gap(raw.get("left_wall_gap", {}))
	level.right_wall_segments = _map_wall_gap(raw.get("right_wall_gap", {}))
	level.max_lives = clampi(int(raw.get("max_lives", 4)), 1, 8)
	level.two_star_max_shots = mini(4, level.max_lives)
	level.three_star_max_shots = mini(2, level.two_star_max_shots)
	level.two_star_max_seconds = 100.0
	level.three_star_max_seconds = 50.0

	var expected := _map_expected_solution(raw.get("expected_solution", {}))
	return {
		"ok": true,
		"blueprint": {
			"level": level,
			"blueprint_index": index,
			"design_intent": _safe_text(
				raw.get("design_intent", ""), AILevelContract.MAX_DESIGN_INTENT),
			"expected_solution": expected,
		},
	}


func _map_point(raw: Variant, minimum: Vector2, maximum: Vector2) -> Dictionary:
	if not raw is Dictionary or not raw.has("x") or not raw.has("y"):
		return _error("x/y koordinatlari eksik.")
	if not _valid_number(raw["x"]) or not _valid_number(raw["y"]):
		return _error("koordinatlari sonlu sayi olmali.")
	return {
		"ok": true,
		"value": Vector2(
			clampf(float(raw["x"]), minimum.x, maximum.x),
			clampf(float(raw["y"]), minimum.y, maximum.y)),
	}


func _map_panel(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return _error("obje olmali.")
	for key in ["x", "y", "rotation_degrees", "length"]:
		if not raw.has(key) or not _valid_number(raw[key]):
			return _error("%s sonlu sayi olmali." % key)
	var panel := PanelData.new()
	panel.position = Vector2(
		clampf(float(raw["x"]), 60.0, 660.0),
		clampf(float(raw["y"]), 180.0, 1080.0))
	panel.rotation_degrees = clampf(float(raw["rotation_degrees"]), -80.0, 80.0)
	panel.length = clampf(float(raw["length"]), 140.0, 420.0)
	panel.thickness = PANEL_THICKNESS
	return {"ok": true, "value": panel}


func _map_block(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return _error("obje olmali.")
	for key in ["x", "y", "rotation_degrees", "width"]:
		if not raw.has(key) or not _valid_number(raw[key]):
			return _error("%s sonlu sayi olmali." % key)
	var block := BreakableBlockData.new()
	block.position = Vector2(
		clampf(float(raw["x"]), 60.0, 660.0),
		clampf(float(raw["y"]), 180.0, 1080.0))
	block.rotation_degrees = clampf(float(raw["rotation_degrees"]), -80.0, 80.0)
	block.size = Vector2(clampf(float(raw["width"]), 120.0, 360.0), BLOCK_HEIGHT)
	return {"ok": true, "value": block}


func _map_obstacle(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return _error("obje olmali.")
	for key in ["kind", "x", "y", "rotation_degrees", "width", "height"]:
		if not raw.has(key):
			return _error("%s eksik." % key)
	if not raw["kind"] is String or not String(raw["kind"]) in [
			"metal_ring", "bomb", "rotating_wheel", "moving_bar"]:
		return _error("kind gecersiz.")
	for key in [
			"x", "y", "rotation_degrees", "width", "height", "inner_radius",
			"spoke_count", "speed_degrees", "motion_direction_degrees",
			"travel_distance", "motion_period", "phase_degrees"]:
		if raw.has(key) and not _valid_number(raw[key]):
			return _error("%s sonlu sayi olmali." % key)

	var obstacle := ObstacleData.new()
	obstacle.kind = ObstacleData.from_kind_id(String(raw["kind"]))
	obstacle.position = Vector2(
		clampf(float(raw["x"]), 70.0, 650.0),
		clampf(float(raw["y"]), 180.0, 1060.0))
	obstacle.rotation_degrees = clampf(float(raw["rotation_degrees"]), -180.0, 180.0)
	match obstacle.kind:
		ObstacleData.Kind.METAL_RING:
			obstacle.size = Vector2(clampf(float(raw["width"]), 88.0, 260.0), 28.0)
			obstacle.inner_radius = clampf(
				float(raw.get("inner_radius", 42.0)), 28.0, obstacle.outer_radius() - 12.0)
		ObstacleData.Kind.BOMB:
			var diameter := clampf(float(raw["width"]), 48.0, 120.0)
			obstacle.size = Vector2.ONE * diameter
		ObstacleData.Kind.ROTATING_WHEEL:
			obstacle.size = Vector2(
				clampf(float(raw["width"]), 84.0, 240.0),
				clampf(float(raw["height"]), 14.0, 40.0))
			obstacle.spoke_count = clampi(int(raw.get("spoke_count", 6)), 3, 8)
			obstacle.angular_speed_degrees = clampf(
				float(raw.get("speed_degrees", 55.0)), -180.0, 180.0)
			if absf(obstacle.angular_speed_degrees) < 10.0:
				obstacle.angular_speed_degrees = 10.0
		ObstacleData.Kind.MOVING_BAR:
			obstacle.size = Vector2(
				clampf(float(raw["width"]), 80.0, 360.0),
				clampf(float(raw["height"]), 20.0, 72.0))
			obstacle.motion_direction_degrees = clampf(
				float(raw.get("motion_direction_degrees", 0.0)), -180.0, 180.0)
			obstacle.travel_distance = clampf(
				float(raw.get("travel_distance", 100.0)), 20.0, 240.0)
			obstacle.motion_period = clampf(
				float(raw.get("motion_period", 2.8)), 1.0, 8.0)
			obstacle.phase_degrees = clampf(
				float(raw.get("phase_degrees", 0.0)), -180.0, 180.0)
		ObstacleData.Kind.PULSE_LASER:
			# Lazer su an AI sozlesmesinde SUNULMUYOR (bkz. AILevelContract:
			# turler listesi) - AI isinin ritmini kurmayi bilmiyor. Yine de
			# kisitlama burada duruyor: elle duzenlenmis bir JSON bu yoldan
			# gecerse degerler yine guvenli araliga cekilsin. Bu dosyanin isi
			# AI'dan gelen HICBIR degere guvenmemektir.
			obstacle.size = Vector2(
				clampf(float(raw["width"]), 90.0, 460.0),
				clampf(float(raw.get("height", 14.0)), 8.0, 30.0))
			obstacle.motion_period = clampf(
				float(raw.get("motion_period", 3.0)), 1.2, 6.0)
			obstacle.pulse_on_ratio = clampf(
				float(raw.get("pulse_on_ratio", 0.667)), 0.15, 0.85)
			obstacle.phase_degrees = clampf(
				float(raw.get("phase_degrees", 0.0)), -180.0, 180.0)
	return {"ok": true, "value": obstacle}


func _map_wall_gap(raw: Variant) -> Array[Vector2]:
	var segments: Array[Vector2] = []
	if not raw is Dictionary or not bool(raw.get("enabled", false)):
		return segments
	if not _valid_number(raw.get("top", null)) or not _valid_number(raw.get("bottom", null)):
		return segments
	var top := clampf(float(raw["top"]), WALL_MIN_Y, WALL_MAX_Y - MIN_WALL_GAP)
	var bottom := clampf(float(raw["bottom"]), WALL_MIN_Y + MIN_WALL_GAP, WALL_MAX_Y)
	if bottom - top < MIN_WALL_GAP:
		return segments
	segments.append(Vector2(-LevelData.WALL_OVERSHOOT, top))
	segments.append(Vector2(bottom, 1280.0 + LevelData.WALL_OVERSHOOT))
	return segments


func _map_expected_solution(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var expected := {}
	if _valid_number(raw.get("estimated_bounces", null)):
		expected["estimated_bounces"] = clampi(int(raw["estimated_bounces"]), 0, 12)
	if _valid_number(raw.get("blocks_required", null)):
		expected["blocks_required"] = clampi(int(raw["blocks_required"]), 0, AILevelContract.MAX_BLOCKS)
	if raw.get("route_description", null) is String:
		expected["route_description"] = _safe_text(raw["route_description"], 240)
	return expected


func _safe_text(value: Variant, maximum: int) -> String:
	if not value is String:
		return ""
	return String(value).replace("\n", " ").replace("\r", " ").strip_edges().left(maximum)


func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
