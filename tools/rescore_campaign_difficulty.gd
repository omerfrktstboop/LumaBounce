extends SceneTree

## Bölüm editöründeki "Zorluk skoru" işlemini ana kampanyanın tamamında
## çalıştırır. Kaynak dosyalarını değiştirmez; her bölüm için makine tarafından
## okunabilen bir DIFFICULTY_RESULT satırı üretir. Böylece yalnızca difficulty
## alanları kontrollü bir yama ile güncellenebilir.

const ANGLE_STEP := LevelGenerator.FINE_ANGLE_STEP
const POWER_STEP := LevelGenerator.FINE_POWER_STEP
const SIMS_PER_FRAME := LevelGenerator.SIMS_PER_FRAME

var _solver: LevelSolver
var _world: LevelWorld


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await physics_frame
	_solver = LevelSolver.from_scenes()
	var tier_counts := [0, 0, 0, 0, 0, 0]
	var failures := 0

	print("DIFFICULTY_BEGIN|%d|%d" % [
		LevelLibrary.FIRST_LEVEL_ID, LevelLibrary.last_level_id()])
	for level_id in range(LevelLibrary.FIRST_LEVEL_ID, LevelLibrary.last_level_id() + 1):
		var level := load(LevelLibrary.level_path(level_id)) as LevelData
		if level == null or level.level_id != level_id:
			push_error("Zorluk puanı: level_%02d yüklenemedi veya kimliği yanlış." % level_id)
			failures += 1
			continue
		var result := await _score_level(level)
		var tier := clampi(int(result.get("tier", 5)), 1, 5)
		tier_counts[tier] += 1
		print("DIFFICULTY_RESULT|%d|%d|%d|%s|%d|%s" % [
			level_id,
			int(result.get("score", 100)),
			tier,
			String(result.get("label", "USTA")),
			int(result.get("solution_count", 0)),
			String(result.get("route_state", "none")),
		])
		# Ayrinti satiri: skorun bilesenleri ve bolum bilgisi (tablo icin).
		# DIFFICULTY_RESULT bicimi degismez; ona bagli okuyucular etkilenmez.
		var breakdown: Dictionary = result.get("breakdown", {})
		var kinds := PackedStringArray()
		for obstacle in level.obstacles:
			kinds.append(obstacle.kind_id())
		print("DIFFICULTY_DETAIL|%d|%.5f|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%s|%s" % [
			level_id,
			float(result.get("hit_ratio", 0.0)),
			int(result.get("bounces", -1)),
			int(result.get("robust", 0)),
			int(breakdown.get("precision", 0)),
			int(breakdown.get("solution_variety", 0)),
			int(breakdown.get("bounces", 0)),
			int(breakdown.get("complexity", 0)),
			int(breakdown.get("block_gate", 0)),
			level.difficulty,
			level.panels.size(),
			level.breakable_blocks.size(),
			",".join(kinds),
			level.display_name,
		])
		_teardown_world()
		await physics_frame

	print("DIFFICULTY_COUNTS|%d|%d|%d|%d|%d" % [
		tier_counts[1], tier_counts[2], tier_counts[3],
		tier_counts[4], tier_counts[5]])
	print("DIFFICULTY_END|%d" % failures)
	quit(0 if failures == 0 else 1)


func _score_level(level: LevelData) -> Dictionary:
	_world = LevelWorld.new()
	root.add_child(_world)
	_world.build(level)
	await physics_frame
	await physics_frame
	_solver.bind_space(
		_world.get_space(), _world.get_block_rids(), _world.get_obstacles())

	var spawn := _solver.spawn_position(level.launcher_position)
	var play_rect := _world.get_play_rect()
	var none: Array[RID] = []
	var free_scan: Dictionary
	if level.breakable_blocks.is_empty():
		free_scan = await _solver.scan_for_solution_async(
			spawn, level.target_position, play_rect, none,
			ANGLE_STEP, POWER_STEP, SIMS_PER_FRAME)
	else:
		free_scan = await _solver.scan_async(
			spawn, level.target_position, play_rect, none,
			ANGLE_STEP, POWER_STEP, SIMS_PER_FRAME)
	var free_analysis := LevelSolver.analyse_robust(free_scan)

	var opened_scan := {}
	var opened_analysis := {}
	if not level.breakable_blocks.is_empty():
		var all_broken := _world.get_all_broken_state()
		opened_scan = await _solver.scan_for_solution_async(
			spawn, level.target_position, play_rect,
			_world.rids_for_state(all_broken),
			ANGLE_STEP, POWER_STEP, SIMS_PER_FRAME)
		opened_analysis = LevelSolver.analyse_robust(opened_scan)

	return LevelDifficultyScorer.evaluate(
		level, free_scan, free_analysis, opened_scan, opened_analysis)


func _teardown_world() -> void:
	if _world == null:
		return
	root.remove_child(_world)
	_world.free()
	_world = null
