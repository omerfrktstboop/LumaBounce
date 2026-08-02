extends SceneTree

const AUDIO_AUTOLOAD := "autoload/AudioManager"

var _passed := 0
var _failed := 0
var _owned_audio_manager: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_register_audio_manager()
	_test_data_and_geometry()
	await _test_world_and_solver()
	await _test_gameplay_bomb()
	_test_resource_roundtrip()
	_test_ai_mapping()
	_test_generation_contract()
	_test_official_obstacle_levels()
	await _unregister_audio_manager()
	print("ENGEL TESTI: %d gecti, %d kaldi." % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_data_and_geometry() -> void:
	var ring := _ring(Vector2(360.0, 600.0))
	_check("halka verisi gecerli", ring.validate(0).is_empty(), true)
	var ring_shapes := ObstacleGeometry.all_shapes([ring], 0.0)
	_check("halka merkezi bos", ObstacleGeometry.overlaps_circle(
		Vector2(360.0, 600.0), 20.0, ring_shapes), false)
	_check("halka cemberi kati", ObstacleGeometry.overlaps_circle(
		Vector2(430.0, 600.0), 20.0, ring_shapes), true)

	var mover := _mover(Vector2(360.0, 600.0))
	var start_shapes := ObstacleGeometry.dynamic_shapes([mover], 0.0)
	var later_shapes := ObstacleGeometry.dynamic_shapes([mover], mover.motion_period * 0.25)
	_check("kayan engel zamanla tasiniyor",
		(start_shapes[0]["center"] as Vector2).distance_to(later_shapes[0]["center"]) > 80.0,
		true)

	var bomb := _bomb(Vector2(360.0, 600.0))
	var hazard := ObstacleGeometry.cast_circle(
		Vector2(360.0, 760.0), Vector2(0.0, -260.0), 24.0,
		ObstacleGeometry.hazard_shapes([bomb]))
	_check("bomba supurme testi", String(hazard.get("hazard_reason", "")), "bomb")


func _test_world_and_solver() -> void:
	var holder := Node2D.new()
	get_root().add_child(holder)
	var world := LevelWorld.new()
	holder.add_child(world)
	var level := LevelData.new()
	level.obstacles = [_ring(Vector2(360.0, 600.0)), _wheel(Vector2(220.0, 760.0))]
	world.build(level)
	await physics_frame
	await physics_frame
	var solver := LevelSolver.from_scenes()
	solver.bind_space(world.get_space(), world.get_block_rids(), world.get_obstacles())
	_check("solver halka merkezini bos goruyor",
		solver.overlaps_obstacle(Vector2(360.0, 600.0), 20.0), false)
	_check("solver halka kenarini kati goruyor",
		solver.overlaps_obstacle(Vector2(430.0, 600.0), 20.0), true)
	holder.queue_free()
	await process_frame


func _test_gameplay_bomb() -> void:
	var level := LevelData.new()
	level.level_id = 1
	level.launcher_position = Vector2(360.0, 1120.0)
	level.target_position = Vector2(120.0, 260.0)
	level.max_lives = 5
	level.obstacles = [_bomb(Vector2(360.0, 930.0))]
	var gameplay: Node = (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	gameplay.level_data = level
	get_root().add_child(gameplay)
	await process_frame
	gameplay.call("_on_shot_fired", Vector2.UP * 1100.0)
	for _frame in 30:
		await physics_frame
		var frame_snapshot: Dictionary = gameplay.call("get_debug_snapshot")
		if String(frame_snapshot["last_failure_reason"]) == "bomb":
			break
	var snapshot: Dictionary = gameplay.call("get_debug_snapshot")
	_check("gameplay bomba nedeni", String(snapshot["last_failure_reason"]), "bomb")
	_check("bomba tek hak dusuruyor", int(snapshot["lives_remaining"]), 4)
	gameplay.queue_free()
	await process_frame


func _register_audio_manager() -> void:
	if Engine.has_singleton("AudioManager"):
		return
	var path := String(ProjectSettings.get_setting(AUDIO_AUTOLOAD, "")).trim_prefix("*")
	var script := load(path) as GDScript
	if script == null:
		push_error("AudioManager yuklenemedi: %s" % path)
		return
	var node := script.new() as Node
	node.name = "AudioManager"
	root.add_child(node)
	Engine.register_singleton("AudioManager", node)
	_owned_audio_manager = node


func _unregister_audio_manager() -> void:
	if _owned_audio_manager == null:
		return
	_owned_audio_manager.call("stop_transient_sounds")
	await create_timer(0.1).timeout
	Engine.unregister_singleton("AudioManager")
	root.remove_child(_owned_audio_manager)
	_owned_audio_manager.free()
	_owned_audio_manager = null


func _test_resource_roundtrip() -> void:
	var path := "user://obstacle_roundtrip_test.tres"
	var level := LevelData.new()
	level.obstacles = [
		_ring(Vector2(200.0, 500.0)), _bomb(Vector2(500.0, 500.0)),
		_wheel(Vector2(240.0, 760.0)), _mover(Vector2(480.0, 760.0)),
	]
	_check("engel kaydi", ResourceSaver.save(level, path), OK)
	var loaded := ResourceLoader.load(path, "LevelData", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	_check("dort engel geri yuklendi", loaded.obstacles.size(), 4)
	_check("hareket suresi korundu", loaded.obstacles[3].motion_period, 2.8)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_ai_mapping() -> void:
	var raw := {
		"display_name": "Engel AI",
		"launcher": {"x": 360, "y": 1120},
		"target": {"x": 420, "y": 300},
		"panels": [], "blocks": [],
		"obstacles": [{
			"kind": "moving_bar", "x": 360, "y": 650,
			"rotation_degrees": 0, "width": 180, "height": 34,
			"inner_radius": 40, "spoke_count": 6, "speed_degrees": 55,
			"motion_direction_degrees": 90, "travel_distance": 100,
			"motion_period": 3.2, "phase_degrees": 0,
		}],
		"left_wall_gap": {"enabled": false, "top": 420, "bottom": 720},
		"right_wall_gap": {"enabled": false, "top": 420, "bottom": 720},
		"max_lives": 5,
		"expected_solution": {
			"estimated_bounces": 2, "blocks_required": 0,
			"route_description": "Kayan bariyeri gec",
		},
	}
	var mapped := AILevelMapper.new().map_blueprint(raw)
	_check("AI engel taslagi map edildi", bool(mapped["ok"]), true)
	var level: LevelData = mapped["blueprint"]["level"]
	_check("AI kayan engel turu", level.obstacles[0].kind, ObstacleData.Kind.MOVING_BAR)
	_check("AI hareket mesafesi", level.obstacles[0].travel_distance, 100.0)


func _test_generation_contract() -> void:
	var schema := AILevelContract.response_schema(2)
	var level_properties: Dictionary = schema["properties"]["levels"]["items"]["properties"]
	_check("AI semasinda engel dizisi", level_properties.has("obstacles"), true)
	_check("AI semasi dort engel turu", level_properties["obstacles"]["items"]
		["properties"]["kind"]["enum"].size(), 4)
	var kinetic := AIGeneratorSettings.new().sanitize({
		"template": "kinetic_course", "mechanics": PackedStringArray(),
	})
	_check("hareketli parkur carki zorunlu tutuyor",
		kinetic["mechanics"].has("rotating_wheel"), true)
	_check("hareketli parkur kayan engeli zorunlu tutuyor",
		kinetic["mechanics"].has("moving_bar"), true)
	var messages := AILevelPromptBuilder.build_messages({
		"template": "kinetic_course", "difficulty": "hard",
		"mechanics": PackedStringArray(["rotating_wheel", "moving_bar"]),
	}, 2)
	_check("AI promptu halka deligini acikliyor",
		String(messages[0]["content"]).contains("inner_radius"), true)
	var profile := LevelGenerator.Profile.kinetic()
	_check("yerel engelli profil engel uretiyor", profile.obstacle_count.y > 0, true)


func _test_official_obstacle_levels() -> void:
	var kinds := {}
	for level_id in range(41, 51):
		var level := LevelLibrary.load_level(level_id)
		for obstacle in level.obstacles:
			kinds[obstacle.kind] = true
	_check("41-50 halka kullaniyor", kinds.has(ObstacleData.Kind.METAL_RING), true)
	_check("41-50 bomba kullaniyor", kinds.has(ObstacleData.Kind.BOMB), true)
	_check("41-50 donen cark kullaniyor", kinds.has(ObstacleData.Kind.ROTATING_WHEEL), true)
	_check("41-50 kayan engel kullaniyor", kinds.has(ObstacleData.Kind.MOVING_BAR), true)


func _ring(at: Vector2) -> ObstacleData:
	var data := ObstacleData.new()
	data.kind = ObstacleData.Kind.METAL_RING
	data.position = at
	data.size = Vector2(160.0, 28.0)
	data.inner_radius = 52.0
	return data


func _bomb(at: Vector2) -> ObstacleData:
	var data := ObstacleData.new()
	data.kind = ObstacleData.Kind.BOMB
	data.position = at
	data.size = Vector2.ONE * 68.0
	return data


func _wheel(at: Vector2) -> ObstacleData:
	var data := ObstacleData.new()
	data.kind = ObstacleData.Kind.ROTATING_WHEEL
	data.position = at
	data.size = Vector2(150.0, 24.0)
	data.spoke_count = 6
	data.angular_speed_degrees = 55.0
	return data


func _mover(at: Vector2) -> ObstacleData:
	var data := ObstacleData.new()
	data.kind = ObstacleData.Kind.MOVING_BAR
	data.position = at
	data.size = Vector2(180.0, 34.0)
	data.motion_direction_degrees = 0.0
	data.travel_distance = 100.0
	data.motion_period = 2.8
	return data


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
		return
	_failed += 1
	push_error("%s: beklenen=%s gercek=%s" % [label, expected, actual])
