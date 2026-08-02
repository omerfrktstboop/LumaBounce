class_name ObstacleField
extends Node2D

## LevelData.obstacles dizisini runtime veya editor onizlemesine kurar.

signal hazard_triggered(reason: String, at: Vector2)

@export var preview_only := false

var _nodes: Array[LevelObstacle] = []
var _elapsed := 0.0
var _running := false


func _ready() -> void:
	process_physics_priority = -10
	set_physics_process(false)


func build(obstacles: Array[ObstacleData]) -> void:
	clear()
	for data in obstacles:
		if data == null:
			continue
		var obstacle := LevelObstacle.new()
		obstacle.setup(data, preview_only)
		obstacle.hazard_triggered.connect(hazard_triggered.emit)
		add_child(obstacle)
		_nodes.append(obstacle)
	reset_motion()


func clear() -> void:
	_running = false
	set_physics_process(false)
	for obstacle in _nodes:
		if is_instance_valid(obstacle):
			remove_child(obstacle)
			obstacle.queue_free()
	_nodes.clear()


func start_motion() -> void:
	_elapsed = 0.0
	_apply_time(0.0)
	_running = true
	set_physics_process(true)


func stop_motion() -> void:
	_running = false
	set_physics_process(false)


func reset_motion() -> void:
	_elapsed = 0.0
	_running = false
	set_physics_process(false)
	_apply_time(0.0)


func get_obstacle_node(index: int) -> LevelObstacle:
	return _nodes[index] if index >= 0 and index < _nodes.size() else null


func set_obstacle_position(index: int, value: Vector2) -> void:
	var obstacle := get_obstacle_node(index)
	if obstacle != null:
		obstacle.set_data_position(value)


func _physics_process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	_apply_time(_elapsed)


func _apply_time(seconds: float) -> void:
	for obstacle in _nodes:
		if is_instance_valid(obstacle):
			obstacle.apply_motion_time(seconds)
