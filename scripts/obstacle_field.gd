class_name ObstacleField
extends Node2D

## LevelData.obstacles dizisini runtime veya editor onizlemesine kurar.
##
## Zamanlama (start/stop/reset_motion) her LevelObstacle'a YONLENDIRILIR - kendi
## _elapsed sayacini burada tutmuyoruz. Sebep: Godot 4.7.1'de sync_to_physics=true
## + gercek CollisionShape2D'si olan bir AnimatableBody2D, pozisyonu yazan dugum
## TORUNU ise (bu dugum -> LevelObstacle -> govde, iki seviye) yazimlari sessizce
## yok sayiyor; ayni govde DOGRUDAN COCUK olarak yazilirsa (LevelObstacle kendi
## _physics_process'inde kendi govdesini yaziyorsa) sorunsuz calisiyor. Bkz.
## level_obstacle.gd'deki LevelObstacle._physics_process.

signal hazard_triggered(reason: String, at: Vector2)

@export var preview_only := false

var _nodes: Array[LevelObstacle] = []


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
	for obstacle in _nodes:
		if is_instance_valid(obstacle):
			remove_child(obstacle)
			obstacle.queue_free()
	_nodes.clear()


func start_motion() -> void:
	for obstacle in _nodes:
		if is_instance_valid(obstacle):
			obstacle.start_motion()


func stop_motion() -> void:
	for obstacle in _nodes:
		if is_instance_valid(obstacle):
			obstacle.stop_motion()


func reset_motion() -> void:
	for obstacle in _nodes:
		if is_instance_valid(obstacle):
			obstacle.reset_motion()


func get_obstacle_node(index: int) -> LevelObstacle:
	return _nodes[index] if index >= 0 and index < _nodes.size() else null


func set_obstacle_position(index: int, value: Vector2) -> void:
	var obstacle := get_obstacle_node(index)
	if obstacle != null:
		obstacle.set_data_position(value)


## LevelSolver hareketli/tehlikeli engelleri ObstacleData'dan kendi zaman
## cizelgesiyle simule eder. Runtime govdeleri de ayni fizik uzayinda kaldigi
## icin cift carpisma olmamasi adina katman-1 govdeleri sorgudan dislanir.
func get_solver_excluded_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for obstacle in _nodes:
		if not is_instance_valid(obstacle):
			continue
		for raw in obstacle.find_children("*", "CollisionObject2D", true, false):
			var body := raw as CollisionObject2D
			if body != null \
					and (body.collision_layer & LevelObstacle.OBSTACLE_LAYER) != 0:
				rids.append(body.get_rid())
	return rids
