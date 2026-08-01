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
	if raw["panels"].size() > AILevelContract.MAX_PANELS:
		return _error("en fazla %d panel kullanilabilir." % AILevelContract.MAX_PANELS)
	if raw["blocks"].size() > AILevelContract.MAX_BLOCKS:
		return _error("en fazla %d blok kullanilabilir." % AILevelContract.MAX_BLOCKS)

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
