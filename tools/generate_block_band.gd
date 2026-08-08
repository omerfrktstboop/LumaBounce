extends SceneTree

## GELISTIRME ARACI - oyuna dahil degildir.
##
## 26-40 BLOK BANDI icin bolum uretir ve yazmadan once gercek LevelSolver ile
## dogrular.
##
## BANDIN SOZLESMESI (bkz. CLAUDE.md "Level arcs", check_blocks_and_gate.gd
## ::_test_library_bounds):
##   - ENGEL YOK. Engeller 41'den itibaren tanitilir; burada bir engel gorunmesi
##     ogretme sirasini bozar.
##   - Kirmadan SAGLAM kestirme OLMAMALI: yoksa tuglalar dekor olur.
##   - Tuglalar kirildiginda rahat bir rota ACILMALI.
##   - En az bir DAYANIKLI (hit_points = 2) tugla: bandin ikinci yarisi bunun
##     uzerine kurulu ve renk kodu (mavi-gri / bronz) onunla ogretiliyor.
##
## Tuglalar TEK SIRA halinde ve aralari topun capindan (48) DAR: kirilmamis bir
## sira eski kati duvar gibi davranir, tek tugla kirmak ise gercekten gecilebilir
## bir delik acar.
##
## Kullanim:
##   godot --headless --path . --script res://tools/generate_block_band.gd -- --only 37,38

const MIN_ROBUST := 6
const MAX_ROBUST := 60
## Izgara verify_levels.gd'nin BLOKLU bolumler icin kullandigi varsayilanla ayni.
const ANGLE_STEP := 3.0
const POWER_STEP := 100.0
const ATTEMPTS := 400
## Tugla genisligi ve aralari. Aralik topun capindan (48) kucuk olmali.
const BRICK_HEIGHT := 34.0
const BRICK_GAP := 30.0

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
	if _only.is_empty():
		print("--only ile bolum listesi verilmeli.")
		quit(1)
		return
	await physics_frame
	_solver = LevelSolver.from_scenes()

	var ok := 0
	var failed: Array[int] = []
	for level_id in _only:
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
	var original := LevelLibrary.load_level(level_id)
	# Sabit tohum: ayni girdi ayni bolumu uretir (determinizm kurali).
	_rng.seed = 990000 + level_id * 7919

	var rejects := {"validate": 0, "geometry": 0, "shortcut": 0, "low": 0, "high": 0}
	for attempt in ATTEMPTS:
		var level := _candidate(original, level_id)
		if not level.validate().is_empty():
			rejects["validate"] += 1
			continue

		var verdict := await _evaluate(level)
		if not bool(verdict["geometry"]):
			rejects["geometry"] += 1
			continue
		# Kirmadan saglam bir rota varsa tuglalar dekordur.
		if int(verdict["free"]) >= MIN_ROBUST:
			rejects["shortcut"] += 1
			continue
		var opened := int(verdict["opened"])
		if opened < MIN_ROBUST:
			rejects["low"] += 1
			continue
		if opened > MAX_ROBUST:
			rejects["high"] += 1
			continue

		var error := ResourceSaver.save(level, "res://levels/level_%d.tres" % level_id)
		if error != OK:
			push_error("kayit hatasi level %d: %d" % [level_id, error])
			return false
		print("LEVEL %3d ok  deneme=%d tugla=%d dayanikli=%d serbest=%d acik=%d" % [
			level_id, attempt + 1, level.breakable_blocks.size(),
			_durable_count(level), int(verdict["free"]), opened])
		return true

	print("LEVEL %3d BASARISIZ - %d deneme yetmedi  ret: %s" % [
		level_id, ATTEMPTS, str(rejects)])
	return false


## Bolumun KIMLIGINI korur (ad, yildiz esikleri, firlatici), geometriyi arar.
func _candidate(original: LevelData, level_id: int) -> LevelData:
	var level := original.duplicate(true) as LevelData
	level.level_id = level_id
	# Bant engelsizdir - eldeki engeller neyse temizlenir.
	level.obstacles = [] as Array[ObstacleData]

	var panels: Array[PanelData] = []
	for i in _rng.randi_range(1, 2):
		var panel := PanelData.new()
		panel.position = Vector2(
			_rng.randf_range(150.0, 570.0), _rng.randf_range(640.0, 940.0))
		panel.rotation_degrees = _rng.randf_range(-46.0, 46.0)
		panel.length = _rng.randf_range(240.0, 400.0)
		panel.thickness = 26.0
		panels.append(panel)
	level.panels = panels

	level.target_position = Vector2(
		_rng.randf_range(140.0, 580.0), _rng.randf_range(220.0, 380.0))

	# Tugla sirasi hedefin ALTINDA durur: rotayi gercekten kapatmasi gerekiyor.
	var count := _rng.randi_range(3, 5)
	var width := 112.5
	var total := float(count) * width + float(count - 1) * BRICK_GAP
	var left := clampf(level.target_position.x - total * 0.5,
		60.0, maxf(660.0 - total, 60.0))
	var row_y := level.target_position.y + _rng.randf_range(120.0, 220.0)
	# En az bir dayanikli tugla SART; sayisi bolum ilerledikce artar.
	var durable := 1 if level_id < 33 else 2
	var bricks: Array[BreakableBlockData] = []
	for i in count:
		var brick := BreakableBlockData.new()
		brick.position = Vector2(left + width * 0.5 + float(i) * (width + BRICK_GAP), row_y)
		brick.size = Vector2(width, BRICK_HEIGHT)
		brick.hit_points = 2 if i < durable else 1
		bricks.append(brick)
	level.breakable_blocks = bricks
	return level


func _durable_count(level: LevelData) -> int:
	var total := 0
	for brick in level.breakable_blocks:
		if brick.hit_points >= 2:
			total += 1
	return total


## verify_levels.gd::_check_static_geometry ile ayni kontroller.
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
	var result := {"geometry": _static_geometry_ok(level, spawn), "free": 0, "opened": 0}
	if bool(result["geometry"]):
		var free_scan := _solver.scan(
			spawn, level.target_position, play_rect, [], ANGLE_STEP, POWER_STEP)
		result["free"] = int(LevelSolver.analyse_robust(free_scan)["robust"])
		var opened := _solver.scan(spawn, level.target_position, play_rect,
			_world.rids_for_state(_world.get_all_broken_state()), ANGLE_STEP, POWER_STEP)
		result["opened"] = int(LevelSolver.analyse_robust(opened)["robust"])

	root.remove_child(_world)
	_world.queue_free()
	_world = null
	await process_frame
	return result
