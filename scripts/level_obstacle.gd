class_name LevelObstacle
extends Node2D

## Tek bir ObstacleData'nin gorselini ve (gameplay'de) fizik govdesini kurar.

signal hazard_triggered(reason: String, at: Vector2)

const OBSTACLE_LAYER := 1
const BALL_LAYER := 2
const HAZARD_LAYER := 8

var data: ObstacleData
var preview_only := false

var _motion_root: Node2D
var _visual: Node2D
var _path_visual: Node2D


func setup(value: ObstacleData, as_preview := false) -> void:
	data = value
	preview_only = as_preview


func _ready() -> void:
	if data == null:
		queue_free()
		return
	position = data.position
	_build()
	apply_motion_time(0.0)


func apply_motion_time(seconds: float) -> void:
	if _motion_root == null or data == null:
		return
	_motion_root.position = data.motion_position(seconds) - data.position
	_motion_root.rotation = data.motion_rotation(seconds)


func set_data_position(value: Vector2) -> void:
	if data == null:
		return
	data.position = value
	position = value
	apply_motion_time(0.0)


func _build() -> void:
	if data.kind == ObstacleData.Kind.MOVING_BAR:
		_build_motion_path()
	_motion_root = _make_motion_root()
	_motion_root.name = "MotionRoot"
	add_child(_motion_root)
	_visual = Node2D.new()
	_visual.name = "Visual"
	_motion_root.add_child(_visual)

	match data.kind:
		ObstacleData.Kind.METAL_RING:
			_build_ring()
		ObstacleData.Kind.BOMB:
			_build_bomb()
		ObstacleData.Kind.ROTATING_WHEEL:
			_build_wheel()
		ObstacleData.Kind.MOVING_BAR:
			_build_moving_bar()


func _make_motion_root() -> Node2D:
	if preview_only and data.kind != ObstacleData.Kind.METAL_RING:
		return Node2D.new()
	match data.kind:
		ObstacleData.Kind.BOMB:
			var area := Area2D.new()
			area.collision_layer = HAZARD_LAYER
			area.collision_mask = BALL_LAYER
			area.monitoring = true
			area.body_entered.connect(_on_bomb_body_entered)
			return area
		ObstacleData.Kind.ROTATING_WHEEL, ObstacleData.Kind.MOVING_BAR:
			var body := AnimatableBody2D.new()
			body.collision_layer = OBSTACLE_LAYER
			body.collision_mask = 0
			body.sync_to_physics = true
			return body
		_:
			var body := StaticBody2D.new()
			body.collision_layer = OBSTACLE_LAYER
			body.collision_mask = 0
			return body


func _build_ring() -> void:
	for rect_data in ObstacleGeometry.ring_rects(data):
		_add_rect_shape(rect_data["center"], rect_data["size"], rect_data["rotation"])

	var outer := data.outer_radius()
	var inner := data.inner_radius
	var middle := (outer + inner) * 0.5
	var rim := outer - inner
	_visual.add_child(_circle_line(middle, rim, Palette.SURFACE_BLOCK_EDGE, 72))
	_visual.add_child(_circle_line(
		middle - rim * 0.18, maxf(rim * 0.12, 2.0),
		Color(Palette.SURFACE_LIGHT, 0.9), 72))
	for angle in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		var rivet := ShapeBuilder.make_polygon(
			ShapeBuilder.circle(maxf(rim * 0.10, 2.2), 12), Palette.SURFACE)
		rivet.position = Vector2.RIGHT.rotated(angle) * middle
		_visual.add_child(rivet)


func _build_bomb() -> void:
	var radius := data.bomb_radius()
	_add_circle_shape(Vector2.ZERO, radius)
	_visual.add_child(ShapeBuilder.make_polygon(
		ShapeBuilder.circle(radius, 40), Palette.HAZARD_DARK))
	_visual.add_child(ShapeBuilder.make_outline(
		ShapeBuilder.circle(radius, 40), Palette.HAZARD, 3.2))
	_visual.add_child(ShapeBuilder.make_polygon(
		ShapeBuilder.circle(radius * 0.30, 24, Vector2(-radius * 0.22, -radius * 0.20)),
		Color(Palette.HAZARD_CORE, 0.82)))
	var fuse := Line2D.new()
	fuse.points = PackedVector2Array([
		Vector2(radius * 0.18, -radius * 0.82),
		Vector2(radius * 0.42, -radius * 1.12),
		Vector2(radius * 0.30, -radius * 1.36),
	])
	fuse.default_color = Palette.SURFACE_BLOCK_SEAM
	fuse.width = 5.0
	fuse.joint_mode = Line2D.LINE_JOINT_ROUND
	fuse.begin_cap_mode = Line2D.LINE_CAP_ROUND
	fuse.end_cap_mode = Line2D.LINE_CAP_ROUND
	fuse.antialiased = true
	_visual.add_child(fuse)
	var spark := ShapeBuilder.make_polygon(
		ShapeBuilder.circle(5.0, 12), Palette.HAZARD_CORE)
	spark.position = fuse.points[-1]
	_visual.add_child(spark)


func _build_wheel() -> void:
	var local_shapes := ObstacleGeometry.wheel_local_shapes(data)
	for shape in local_shapes:
		if String(shape["shape"]) == "circle":
			_add_circle_shape(shape["center"], float(shape["radius"]))
			continue
		_add_rect_shape(shape["center"], shape["size"], float(shape["rotation"]))

	var outer := data.outer_radius()
	var thickness := data.size.y
	for i in data.spoke_count:
		var angle := TAU * float(i) / float(data.spoke_count)
		var spoke_length := outer * 0.88
		var spoke := ShapeBuilder.make_polygon(
			ShapeBuilder.stadium(spoke_length, thickness, 6), Palette.SURFACE_PANEL)
		spoke.position = Vector2.RIGHT.rotated(angle) * spoke_length * 0.5
		spoke.rotation = angle
		_visual.add_child(spoke)
		var edge := ShapeBuilder.make_outline(
			ShapeBuilder.stadium(spoke_length, thickness, 6), Palette.SURFACE_EDGE, 2.4)
		edge.position = spoke.position
		edge.rotation = angle
		_visual.add_child(edge)
	var hub_radius := maxf(thickness * 0.82, outer * 0.19)
	_visual.add_child(ShapeBuilder.make_polygon(
		ShapeBuilder.circle(hub_radius, 32), Palette.SURFACE_BLOCK))
	_visual.add_child(ShapeBuilder.make_outline(
		ShapeBuilder.circle(hub_radius, 32), Palette.SURFACE_BLOCK_EDGE, 3.0))
	_visual.add_child(ShapeBuilder.make_polygon(
		ShapeBuilder.circle(hub_radius * 0.34, 20), Palette.SURFACE_LIGHT))


func _build_moving_bar() -> void:
	_add_rect_shape(Vector2.ZERO, data.size, 0.0)
	var body := ShapeBuilder.rounded_rect(data.size, minf(8.0, data.size.y * 0.25), 4)
	_visual.add_child(ShapeBuilder.make_polygon(body, Palette.SURFACE_PANEL))
	_visual.add_child(ShapeBuilder.make_outline(body, Palette.SURFACE_BLOCK_EDGE, 3.0))
	var chevron_color := Color(Palette.SURFACE_LIGHT, 0.9)
	for raw_direction in [-1.0, 1.0]:
		var direction: float = raw_direction
		var mark := Line2D.new()
		var x: float = direction * minf(data.size.x * 0.30, 74.0)
		mark.points = PackedVector2Array([
			Vector2(x - direction * 10.0, -7.0),
			Vector2(x, 0.0),
			Vector2(x - direction * 10.0, 7.0),
		])
		mark.default_color = chevron_color
		mark.width = 3.0
		mark.joint_mode = Line2D.LINE_JOINT_ROUND
		mark.antialiased = true
		_visual.add_child(mark)


func _build_motion_path() -> void:
	_path_visual = Node2D.new()
	_path_visual.name = "MotionPath"
	add_child(_path_visual)
	var direction := Vector2.RIGHT.rotated(deg_to_rad(data.motion_direction_degrees))
	var path := Line2D.new()
	path.points = PackedVector2Array([
		-direction * data.travel_distance,
		direction * data.travel_distance,
	])
	path.default_color = Color(Palette.SURFACE_LIGHT, 0.28)
	path.width = 3.0
	path.begin_cap_mode = Line2D.LINE_CAP_ROUND
	path.end_cap_mode = Line2D.LINE_CAP_ROUND
	path.antialiased = true
	_path_visual.add_child(path)


func _add_rect_shape(at: Vector2, shape_size: Vector2, angle: float) -> void:
	if not _motion_root is CollisionObject2D:
		return
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = shape_size
	shape_node.shape = shape
	shape_node.position = at
	shape_node.rotation = angle
	_motion_root.add_child(shape_node)


func _add_circle_shape(at: Vector2, radius: float) -> void:
	if not _motion_root is CollisionObject2D:
		return
	var shape_node := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	shape_node.shape = shape
	shape_node.position = at
	_motion_root.add_child(shape_node)


func _circle_line(radius: float, width: float, color: Color, segments: int) -> Line2D:
	var line := Line2D.new()
	line.points = ShapeBuilder.closed_loop(ShapeBuilder.circle(radius, segments))
	line.default_color = color
	line.width = width
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.antialiased = true
	return line


func _on_bomb_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		hazard_triggered.emit("bomb", global_position)
