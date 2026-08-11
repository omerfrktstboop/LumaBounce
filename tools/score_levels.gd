extends SceneTree

## GELISTIRME ARACI - oyuna dahil degildir, calisma zamaninda hic yuklenmez.
##
## Her bolum icin GERCEK LevelSolver ile tek bir "ilk atis" izgara taramasi
## yapar (bloklar kirilmamis, hicbir durum aramasi yok) ve karsilastirilabilir
## bir zorluk skoru basar: robust hucre sayisi + en az sekme sayisi.
##
## verify_levels.gd "bu bolum cozulebilir mi" sorusunu cok atisli durum
## aramasiyla yanitlar (dogru ama bolumler arasi kiyaslanamaz); bu arac
## "oyuncunun ilk gordugu an ne kadar zor" sorusunu tek, sabit bir izgarada
## yanitlar - level-progression yeniden siralamasi icin gereken budur.
##
## Kullanim:
##   godot --headless --path . --script res://tools/score_levels.gd
##   godot --headless --path . --script res://tools/score_levels.gd -- --level 41
##   godot --headless --path . --script res://tools/score_levels.gd -- --angle-step 3 --power-step 100

var _angle_step := 3.0
var _power_step := 100.0
var _only_level := -1

var _solver: LevelSolver
var _world: LevelWorld


func _initialize() -> void:
	_parse_args()
	_run.call_deferred()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--angle-step" and i + 1 < args.size():
			_angle_step = maxf(float(args[i + 1]), 0.25)
		elif args[i] == "--power-step" and i + 1 < args.size():
			_power_step = maxf(float(args[i + 1]), 5.0)
		elif args[i] == "--level" and i + 1 < args.size():
			_only_level = int(args[i + 1])


func _run() -> void:
	await physics_frame
	_solver = LevelSolver.from_scenes()

	var scored := 0
	var errors := 0
	for level_id in range(LevelLibrary.FIRST_LEVEL_ID, LevelLibrary.last_level_id() + 1):
		if _only_level > 0 and level_id != _only_level:
			continue
		var ok := await _score_level(level_id)
		if ok:
			scored += 1
		else:
			errors += 1
		_teardown_world()

	print("SUMMARY scored=%d errors=%d" % [scored, errors])
	quit(0 if errors == 0 else 1)


func _score_level(level_id: int) -> bool:
	var level := LevelLibrary.load_level(level_id)

	var _log = FileAccess.open("res://scratchpad/scores.log", FileAccess.READ_WRITE)
	if _log == null: _log = FileAccess.open("res://scratchpad/scores.log", FileAccess.WRITE)
	if _log != null: _log.seek_end()

	if level.level_id != level_id:
		var load_msg = "LEVEL %d ERROR load_mismatch_got=%d" % [level_id, level.level_id]
		print(load_msg)
		if _log != null: _log.store_line(load_msg)
		return false
	var problems := level.validate()
	if not problems.is_empty():
		var validation_msg = "LEVEL %d ERROR validate_failed=%s" % [level_id, "|".join(problems)]
		print(validation_msg)
		if _log != null: _log.store_line(validation_msg)
		return false

	_world = LevelWorld.new()
	root.add_child(_world)
	_world.build(level)
	_solver.bind_space(_world.get_space(), _world.get_block_rids(), _world.get_obstacles())
	# Yeni govdelerin fizik uzayina girmesi icin iki kare bekle (verify_levels.gd ile ayni).
	await physics_frame
	await physics_frame

	var scan := _solver.scan(
		_solver.spawn_position(level.launcher_position),
		level.target_position,
		_world.get_play_rect(),
		[], _angle_step, _power_step)
	var analysis := LevelSolver.analyse_robust(scan)

	var kinds := PackedStringArray()
	for obstacle in level.obstacles:
		if obstacle == null:
			continue
		var kind_id := String(ObstacleData.KIND_IDS.get(obstacle.kind, "metal_ring"))
		if not kinds.has(kind_id):
			kinds.append(kind_id)

	var solvable := int(scan["hit_count"]) > 0
	var msg = "LEVEL %d robust=%d bounces=%d panels=%d blocks=%d obstacles=%d kinds=%s solvable=%s" % [
		level_id,
		int(analysis["robust"]),
		int(analysis["bounces"]) if solvable else -1,
		level.panels.size(),
		level.breakable_blocks.size(),
		level.obstacles.size(),
		(",".join(kinds) if not kinds.is_empty() else "-"),
		"true" if solvable else "false",
	]
	print(msg)
	if _log != null: _log.store_line(msg)
	return true


func _teardown_world() -> void:
	if _world != null:
		_world.queue_free()
		_world = null
