class_name Arena
extends Node2D

## Oyun alani: sakin murekkep-lacivert gradient zemin ve sekilebilir kenarlar.
##
## Bilerek cok sade: leke yok, desen yok, doku yok. Zeminin tek isi
## kontrast saglayip top / kilavuz / hedefin one cikmasini kolaylastirmak.
## Alt kenar aciktir; top asagi duserse atis sifirlanir.

## Obstacle katmani (project.godot -> 2d_physics/layer_1).
const OBSTACLE_LAYER := 1

@export var play_size := Vector2(720.0, 1280.0)
@export var wall_thickness := 80.0

@export_group("Renkler")
@export var ink_top := Palette.INK_TOP
@export var ink_mid := Palette.INK_MID
@export var ink_bottom := Palette.INK_BOTTOM
@export var frame_color := Palette.FRAME
@export var frame_edge_color := Palette.SURFACE_EDGE

@export_group("Cerceve")
## Kenari belirginlestiren cok soluk genis cizgi.
@export var frame_soft_width := 26.0
@export_range(0.0, 1.0, 0.01) var frame_soft_alpha := 0.22
## Net, ince kenar cizgisi.
@export var frame_line_width := 3.0


func _ready() -> void:
	_build_background()
	_build_frame()
	_build_walls()


func get_play_rect() -> Rect2:
	return Rect2(Vector2.ZERO, play_size)


# --- Gorunum -----------------------------------------------------------------

func _build_background() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, ink_top)
	gradient.set_color(1, ink_bottom)
	gradient.add_point(0.55, ink_mid)

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = int(play_size.x)
	texture.height = int(play_size.y)
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)

	var sky := Sprite2D.new()
	sky.name = "Sky"
	sky.texture = texture
	sky.centered = false
	sky.z_index = -100
	add_child(sky)


## Alt kenar cizilmez: orasi acik.
func _build_frame() -> void:
	var outline := PackedVector2Array([
		Vector2(0.0, play_size.y),
		Vector2.ZERO,
		Vector2(play_size.x, 0.0),
		Vector2(play_size.x, play_size.y),
	])
	add_child(_make_frame_line(
		"FrameSoft", outline, Color(frame_color, frame_soft_alpha), frame_soft_width, -60))
	add_child(_make_frame_line(
		"FrameLine", outline, frame_edge_color, frame_line_width, -50))


func _make_frame_line(line_name: String, points: PackedVector2Array,
		color: Color, width: float, z: int) -> Line2D:
	var line := Line2D.new()
	line.name = line_name
	line.points = points
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.z_index = z
	return line


# --- Fizik -------------------------------------------------------------------

func _build_walls() -> void:
	var walls := Node2D.new()
	walls.name = "Walls"
	add_child(walls)

	var tall := play_size.y + wall_thickness * 4.0
	var wide := play_size.x + wall_thickness * 4.0
	_add_wall(walls, "WallLeft",
		Vector2(-wall_thickness * 0.5, play_size.y * 0.5), Vector2(wall_thickness, tall))
	_add_wall(walls, "WallRight",
		Vector2(play_size.x + wall_thickness * 0.5, play_size.y * 0.5), Vector2(wall_thickness, tall))
	_add_wall(walls, "WallTop",
		Vector2(play_size.x * 0.5, -wall_thickness * 0.5), Vector2(wide, wall_thickness))


func _add_wall(parent: Node, wall_name: String, center: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.name = wall_name
	body.position = center
	body.collision_layer = OBSTACLE_LAYER
	body.collision_mask = 0

	var rect := RectangleShape2D.new()
	rect.size = size

	var shape := CollisionShape2D.new()
	shape.shape = rect
	body.add_child(shape)
	parent.add_child(body)
