extends SceneTree

var _solver: LevelSolver
var _world: LevelWorld
var _rng := RandomNumberGenerator.new()

var _log_file: FileAccess

func _initialize() -> void:
	_log_file = FileAccess.open("res://harden.log", FileAccess.WRITE)
	_print("Started harden_levels.gd")
	_run.call_deferred()

func _print(msg: String) -> void:
	if _log_file:
		_log_file.store_line(msg)
		_log_file.flush()
	print(msg)

func _run() -> void:
	await physics_frame
	_solver = LevelSolver.from_scenes()
	
	var hardened_count = 0
	_print("Kolay bolumler taraniyor (51-155)...")
	for level_id in range(51, LevelLibrary.last_level_id() + 1):
		var level := LevelLibrary.load_level(level_id)
		if level == null: continue
		
		# Sadece az engelli bolumlere odaklanalim
		if level.obstacles.size() >= 3:
			continue
			
		var initial_score = await _score(level)
		if not initial_score["solvable"]:
			continue
			
		# Eger hic engeli yoksa cok kolaydir, 1-2 engel varsa orta kolaydir.
		# Biz en az 1 engel ekleyecegiz eger cozulebilir kalirsa.
		_print("LEVEL %3d (Engeller: %d, Robust: %d) -> Zorlastiriliyor..." % [level_id, level.obstacles.size(), initial_score["robust"]])
		
		var valid_kinds = _allowed_kinds(level_id)
		if valid_kinds.is_empty():
			continue
			
		var original_obstacles = level.obstacles.duplicate(true)
		var best_obstacles = original_obstacles
		var best_robust = initial_score["robust"]
		var success = false
		
		for attempt in 15:
			level.obstacles = original_obstacles.duplicate(true)
			
			var data = _make_obstacle(valid_kinds[_rng.randi() % valid_kinds.size()])
			var valid_pos = false
			for j in 15:
				data.position = Vector2(_rng.randf_range(110.0, 610.0), _rng.randf_range(330.0, 960.0))
				if data.position.distance_to(level.launcher_position) > 200.0 and data.position.distance_to(level.target_position) > 200.0:
					valid_pos = true
					break
			
			if valid_pos:
				level.obstacles.append(data)
			
			var score = await _score(level)
			# Yeni eklenen engel sonrasi hala cozulebilirse ve cok da imkansiz degilse
			if score["solvable"] and score["robust"] > 0:
				best_robust = score["robust"]
				best_obstacles = level.obstacles.duplicate(true)
				success = true
				break # Ilk buldugumuz basarili zorlastirmayi kabul edelim, islemi hizlandiralim
				
		if success:
			level.obstacles = best_obstacles
			var path = "res://levels/level_%02d.tres" % level_id if level_id < 100 else "res://levels/level_%d.tres" % level_id
			ResourceSaver.save(level, path)
			_print("  -> BASARILI! Yeni engel eklendi. (Yeni robust: %d)" % best_robust)
			hardened_count += 1
		else:
			level.obstacles = original_obstacles
			
	_print("ISLEM TAMAMLANDI. %d bolum zorlastirildi." % hardened_count)
	quit(0)

func _allowed_kinds(level_id: int) -> Array:
	var k = []
	if level_id >= 51:
		k.append(ObstacleData.Kind.ROTATING_WHEEL)
		k.append(ObstacleData.Kind.METAL_RING)
		k.append(ObstacleData.Kind.BOMB)
	if level_id >= 56:
		k.append(ObstacleData.Kind.MOVING_BAR)
	if level_id >= 126:
		k.append(ObstacleData.Kind.PULSE_LASER)
	return k

func _make_obstacle(kind: int) -> ObstacleData:
	var data = ObstacleData.new()
	data.kind = kind
	if kind == ObstacleData.Kind.METAL_RING:
		data.size = Vector2(80, 28)
		data.inner_radius = _rng.randf_range(35.0, 50.0)
		data.rotation_degrees = _rng.randf_range(0.0, 360.0)
	elif kind == ObstacleData.Kind.BOMB:
		data.size = Vector2(70, 70)
		data.inner_radius = 42.0
	elif kind == ObstacleData.Kind.ROTATING_WHEEL:
		data.size = Vector2(100, 20)
		data.inner_radius = 40.0
		data.spoke_count = (_rng.randi() % 3) + 3
		data.angular_speed_degrees = _rng.randf_range(45.0, 120.0)
	elif kind == ObstacleData.Kind.MOVING_BAR:
		data.size = Vector2(_rng.randf_range(100.0, 180.0), 28.0)
		data.travel_distance = _rng.randf_range(80.0, 140.0)
		data.motion_period = _rng.randf_range(2.0, 4.0)
		data.rotation_degrees = _rng.randf_range(-45.0, 45.0)
	elif kind == ObstacleData.Kind.PULSE_LASER:
		data.size = Vector2(_rng.randf_range(180, 300), 14)
		data.motion_period = _rng.randf_range(2.2, 4.5)
		data.pulse_on_ratio = _rng.randf_range(0.4, 0.65)
		data.rotation_degrees = _rng.randf_range(-15.0, 15.0)
	return data

func _score(level: LevelData) -> Dictionary:
	_world = LevelWorld.new()
	root.add_child(_world)
	_world.build(level)
	_solver.bind_space(_world.get_space(), _world.get_block_rids(), _world.get_obstacles())
	await physics_frame
	await physics_frame
	var scan := _solver.scan(
		_solver.spawn_position(level.launcher_position),
		level.target_position,
		_world.get_play_rect(),
		[], 4.0, 150.0) 
	var analysis := LevelSolver.analyse_robust(scan)
	var solvable = int(scan["hit_count"]) > 0
	_world.queue_free()
	_world = null
	await physics_frame
	return {"solvable": solvable, "robust": int(analysis["robust"])}
