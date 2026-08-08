extends SceneTree

## GELISTIRME ARACI - oyuna dahil degildir.
##
## BONUS bolumleri (151-156) uretir: her dunyanin sonunda duran, numarasiz
## gosterilen, gecildiginde yildizin tamamini veren iki zor sinav.
##
## NORMAL URETICIDEN FARKI - kabul bandi TERS YONDE dar:
##   normal bolum : saglam hucre >= 6   ("piksel hassasiyeti istemesin")
##   bonus bolum  : saglam hucre 6..14  ("zor OLSUN ama imkansiz olmasin")
##
## Ust siniri koymanin sebebi olculebilir: saglam hucre sayisi "kac farkli
## aci/guc kombinasyonu isabet ediyor" demektir. 40 hucreli bir bolum rahat,
## 8 hucreli bolum dar bir pencere ister. Alt sinir yine 6'dir - verifier'in
## bariyeri ve "sans degil beceri" cizgisi. Bonus zor olmali, adaletsiz degil.
##
## Ayrica bonus bolumler EN AZ iki sekme ister: tek atista dogrudan giden bir
## bolum, ne kadar dar olursa olsun bir sinav gibi okunmaz.
##
## Kullanim:
##   godot --headless --path . --script res://tools/generate_bonus_levels.gd
##   godot --headless --path . --script res://tools/generate_bonus_levels.gd -- --only 151

const MIN_ROBUST := 6
const MAX_ROBUST := 14
const MIN_BOUNCES := 2
const ANGLE_STEP := 2.0
const POWER_STEP := 50.0
const ATTEMPTS := 900
const CLEARANCE := 26.0

const RING := ObstacleData.Kind.METAL_RING
const BOMB := ObstacleData.Kind.BOMB
const WHEEL := ObstacleData.Kind.ROTATING_WHEEL
const BAR := ObstacleData.Kind.MOVING_BAR
const LASER := ObstacleData.Kind.PULSE_LASER

## Her bonus, ait oldugu dunyanin mekaniklerinden kurulur: 1. dunyanin sinavi
## o dunyada ogretilenlerle cozulmeli, oyuncuya hic gormedigi bir engel
## cikarmamali. Ikinci bonus birincisinden bir kademe agirdir.
const PLAN := {
	151: {"name": "Sınav I", "kinds": [], "bricks": 4, "strong": 2},
	152: {"name": "Sınav II", "kinds": [RING, BOMB], "bricks": 4, "strong": 3},
	153: {"name": "Kinetik Sınav I", "kinds": [WHEEL, BAR], "bricks": 0, "strong": 0},
	154: {"name": "Kinetik Sınav II", "kinds": [WHEEL, BAR, RING], "bricks": 0, "strong": 0},
	155: {"name": "Son Sınav I", "kinds": [LASER, WHEEL], "bricks": 3, "strong": 2},
	156: {"name": "Son Sınav II", "kinds": [LASER, LASER, BAR, RING], "bricks": 4, "strong": 3},
}

var _only: Array[int] = []
var _solver: LevelSolver
var _world: LevelWorld
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--only" and i + 1 < args.size():
			for piece in args[i + 1].split(",", false):
				var clean := piece.strip_edges()
				if clean.is_valid_int():
					_only.append(int(clean))
	_run.call_deferred()


func _run() -> void:
	await physics_frame
	_solver = LevelSolver.from_scenes()

	var wanted: Array[int] = _only.duplicate()
	if wanted.is_empty():
		for id in PLAN:
			wanted.append(int(id))
		wanted.sort()

	var ok := 0
	var failed: Array[int] = []
	for level_id in wanted:
		if await _build(level_id):
			ok += 1
		else:
			failed.append(level_id)
	print("")
	print("OZET uretildi=%d basarisiz=%d" % [ok, failed.size()])
	if not failed.is_empty():
		print("basarisiz: %s" % str(failed))
	quit(0 if failed.is_empty() else 1)


func _build(level_id: int) -> bool:
	if not PLAN.has(level_id):
		print("LEVEL %3d plani yok" % level_id)
		return false
	var spec: Dictionary = PLAN[level_id]
	_rng.seed = 1230000 + level_id * 7919

	var rejects := {"validate": 0, "geometry": 0, "place": 0, "shortcut": 0,
		"low": 0, "high": 0, "flat": 0}
	for attempt in ATTEMPTS:
		var level := _candidate(level_id, spec)
		if level == null:
			rejects["place"] += 1
			continue
		if not level.validate().is_empty():
			rejects["validate"] += 1
			continue

		var verdict := await _evaluate(level)
		if not bool(verdict["geometry"]):
			rejects["geometry"] += 1
			continue
		if int(spec["bricks"]) > 0 and int(verdict["free"]) >= MIN_ROBUST:
			rejects["shortcut"] += 1
			continue
		var robust := int(verdict["robust"])
		if robust < MIN_ROBUST:
			rejects["low"] += 1
			continue
		if robust > MAX_ROBUST:
			rejects["high"] += 1
			continue
		if int(verdict["bounces"]) < MIN_BOUNCES:
			rejects["flat"] += 1
			continue

		_apply_identity(level, level_id, spec)
		var error := ResourceSaver.save(level, "res://levels/level_%d.tres" % level_id)
		if error != OK:
			push_error("kayit hatasi level %d: %d" % [level_id, error])
			return false
		print("LEVEL %3d ok  deneme=%d engel=%d tugla=%d saglam=%d sekme=%d" % [
			level_id, attempt + 1, level.obstacles.size(),
			level.breakable_blocks.size(), robust, int(verdict["bounces"])])
		return true

	print("LEVEL %3d BASARISIZ - %d deneme yetmedi  ret: %s" % [
		level_id, ATTEMPTS, str(rejects)])
	return false


## Yerlestirilemezse null doner - engel eksik bir bonus, planladigi sinavi
## vermez (bkz. generate_band_51_125.gd'deki ayni ders).
func _candidate(level_id: int, spec: Dictionary) -> LevelData:
	var level := LevelData.new()
	level.level_id = level_id
	level.is_bonus = true
	level.launcher_position = Vector2(360.0, 1120.0)
	level.max_lives = 5

	var panels: Array[PanelData] = []
	for i in _rng.randi_range(2, 3):
		var panel := PanelData.new()
		panel.position = Vector2(
			_rng.randf_range(150.0, 570.0), _rng.randf_range(480.0, 950.0))
		panel.rotation_degrees = _rng.randf_range(-52.0, 52.0)
		panel.length = _rng.randf_range(230.0, 400.0)
		panel.thickness = 26.0
		panels.append(panel)
	level.panels = panels
	level.target_position = Vector2(
		_rng.randf_range(130.0, 590.0), _rng.randf_range(215.0, 400.0))

	var placed: Array[ObstacleData] = []
	for kind in (spec["kinds"] as Array):
		var data := _make_obstacle(int(kind))
		var seated := false
		for _try in 60:
			data.position = Vector2(
				_rng.randf_range(110.0, 610.0), _rng.randf_range(330.0, 960.0))
			if _position_is_clear(data.position, _obstacle_radius(data), level, placed):
				placed.append(data)
				seated = true
				break
		if not seated:
			return null
	level.obstacles = placed

	var count := int(spec["bricks"])
	if count > 0:
		var width := 104.0
		var gap := 30.0
		var total := float(count) * width + float(count - 1) * gap
		var left := clampf(level.target_position.x - total * 0.5,
			60.0, maxf(660.0 - total, 60.0))
		var row_y := level.target_position.y + _rng.randf_range(110.0, 200.0)
		var bricks: Array[BreakableBlockData] = []
		for i in count:
			var brick := BreakableBlockData.new()
			brick.position = Vector2(left + width * 0.5 + float(i) * (width + gap), row_y)
			brick.size = Vector2(width, 34.0)
			brick.hit_points = 2 if i < int(spec["strong"]) else 1
			bricks.append(brick)
		level.breakable_blocks = bricks
	return level


## Bonus engelleri bandin en agir ucundan: en hizli cark, en dar lazer penceresi.
func _make_obstacle(kind: int) -> ObstacleData:
	var data := ObstacleData.new()
	data.kind = kind as ObstacleData.Kind
	match kind:
		RING:
			data.size = Vector2(180.0, 28.0)
			data.inner_radius = 58.0
			data.rotation_degrees = 180.0
		BOMB:
			data.size = Vector2(88.0, 88.0)
		WHEEL:
			data.size = Vector2(130.0, 20.0)
			data.spoke_count = 6
			data.angular_speed_degrees = 130.0 * (1.0 if _rng.randf() < 0.5 else -1.0)
		BAR:
			data.size = Vector2(150.0, 26.0)
			data.travel_distance = 150.0
			data.motion_period = 1.9
		LASER:
			data.size = Vector2(340.0, 14.0)
			data.motion_period = 2.1
			data.pulse_on_ratio = 0.60
			data.phase_degrees = _rng.randf_range(0.0, 360.0)
	return data


func _apply_identity(level: LevelData, level_id: int, spec: Dictionary) -> void:
	level.display_name = String(spec["name"])
	level.is_bonus = true
	# Bonus bolumde sure/atis esigi ANLAMSIZDIR: gecmek zaten yildizin
	# tamamini verir (bkz. LevelData.calculate_stars). Alanlar yine de
	# gecerli birakilir, cunku LevelData.validate() pozitif deger bekliyor.
	level.two_star_max_seconds = 999.0
	level.two_star_max_shots = level.max_lives
	level.three_star_max_seconds = 999.0
	level.three_star_max_shots = level.max_lives


func _obstacle_radius(data: ObstacleData) -> float:
	if data.kind == BAR:
		return data.size.length() * 0.5 + data.travel_distance
	if data.kind == LASER:
		return data.size.x * 0.5
	return data.outer_radius()


func _position_is_clear(position: Vector2, radius: float, level: LevelData,
		placed: Array[ObstacleData]) -> bool:
	var spawn := _solver.spawn_position(level.launcher_position)
	if position.distance_to(level.target_position) \
			< radius + _solver.target_size * 0.5 + CLEARANCE:
		return false
	if position.distance_to(spawn) < radius + _solver.radius + CLEARANCE:
		return false
	for other in placed:
		if position.distance_to(other.position) < radius + _obstacle_radius(other) + 10.0:
			return false
	for panel in level.panels:
		if _distance_to_panel(position, panel) < radius + CLEARANCE:
			return false
	return true


func _distance_to_panel(point: Vector2, panel: PanelData) -> float:
	var axis := Vector2.RIGHT.rotated(deg_to_rad(panel.rotation_degrees))
	var half := panel.length * 0.5
	var offset := point - panel.position
	var along := clampf(offset.dot(axis), -half, half)
	return point.distance_to(panel.position + axis * along) - panel.thickness * 0.5


func _static_geometry_ok(level: LevelData, spawn: Vector2) -> bool:
	if _solver.overlaps_obstacle(level.target_position, _solver.target_size * 0.5):
		return false
	if _solver.overlaps_obstacle(spawn, _solver.radius):
		return false
	if _solver.overlaps_obstacle(level.launcher_position, 60.0):
		return false
	return level.target_position.y - _solver.target_size * 0.5 >= 150.0


func _evaluate(level: LevelData) -> Dictionary:
	_world = LevelWorld.new()
	root.add_child(_world)
	_world.build(level)
	_solver.bind_space(_world.get_space(), _world.get_block_rids(), _world.get_obstacles())
	await physics_frame
	await physics_frame

	var spawn := _solver.spawn_position(level.launcher_position)
	var play_rect := _world.get_play_rect()
	var result := {
		"geometry": _static_geometry_ok(level, spawn),
		"free": 0, "robust": 0, "bounces": -1,
	}
	if bool(result["geometry"]):
		var free_scan := _solver.scan(
			spawn, level.target_position, play_rect, [], ANGLE_STEP, POWER_STEP)
		result["free"] = int(LevelSolver.analyse_robust(free_scan)["robust"])
		var scan := free_scan
		if not level.breakable_blocks.is_empty():
			scan = _solver.scan(spawn, level.target_position, play_rect,
				_world.rids_for_state(_world.get_all_broken_state()),
				ANGLE_STEP, POWER_STEP)
		var analysis := LevelSolver.analyse_robust(scan)
		result["robust"] = int(analysis["robust"])
		result["bounces"] = int(analysis["bounces"]) if int(scan["hit_count"]) > 0 else -1

	root.remove_child(_world)
	_world.queue_free()
	_world = null
	await process_frame
	return result
