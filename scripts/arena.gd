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

@export_group("Yan Duvar Segmentleri")
## Her Vector2(baslangic_y, bitis_y) bir DUVAR segmentidir; aralarda kalan
## bosluklardan topun o taraftan ekran disina cikmasi mumkun olur. Alt kenar
## zaten tamamen aciktir (hicbir segment onu kapatmaz). Sol ve sag bagimsiz
## dizilerdir; farkli acikliklara sahip olabilirler.
@export var left_wall_segments_y: Array[Vector2] = [
	Vector2(-320.0, 260.0),
	Vector2(460.0, 760.0),
	Vector2(960.0, 1440.0),
]
@export var right_wall_segments_y: Array[Vector2] = [
	Vector2(-320.0, 260.0),
	Vector2(460.0, 760.0),
	Vector2(960.0, 1440.0),
]

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


## Alt kenar hicbir zaman cizilmez. Sol/sag kenarlar, kendi fizik
## duvarlariyla birebir eslesecek sekilde segment segment cizilir; boslukta
## cizgi de yoktur - oyuncu acigin nerede oldugunu gorsel olarak da anlar.
func _build_frame() -> void:
	var top_points := PackedVector2Array([Vector2(0.0, 0.0), Vector2(play_size.x, 0.0)])
	add_child(_make_frame_line(
		"FrameTopSoft", top_points, Color(frame_color, frame_soft_alpha), frame_soft_width, -60))
	add_child(_make_frame_line(
		"FrameTopLine", top_points, frame_edge_color, frame_line_width, -50))

	_build_side_frame("Left", left_wall_segments_y, 0.0)
	_build_side_frame("Right", right_wall_segments_y, play_size.x)


func _build_side_frame(side_name: String, segments: Array[Vector2], x: float) -> void:
	for i in segments.size():
		var segment: Vector2 = segments[i]
		var y_start := clampf(segment.x, 0.0, play_size.y)
		var y_end := clampf(segment.y, 0.0, play_size.y)
		if y_end - y_start < 1.0:
			continue

		var points := PackedVector2Array([Vector2(x, y_start), Vector2(x, y_end)])
		add_child(_make_frame_line("Frame%sSoft%d" % [side_name, i],
			points, Color(frame_color, frame_soft_alpha), frame_soft_width, -60))
		add_child(_make_frame_line("Frame%sLine%d" % [side_name, i],
			points, frame_edge_color, frame_line_width, -50))


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

## Sol/sag duvarlar artik tek parca degil; ilgili segment dizisindeki her
## aralik icin ayri bir StaticBody2D uretilir. Segmentler arasindaki
## bosluklarda hicbir collision shape olmadigi icin top gercekten disari cikabilir.
func _build_walls() -> void:
	var walls := Node2D.new()
	walls.name = "Walls"
	add_child(walls)

	for i in left_wall_segments_y.size():
		var segment: Vector2 = left_wall_segments_y[i]
		var height := segment.y - segment.x
		var center_y := (segment.x + segment.y) * 0.5
		_add_wall(walls, "WallLeft%d" % i,
			Vector2(-wall_thickness * 0.5, center_y), Vector2(wall_thickness, height))

	for i in right_wall_segments_y.size():
		var segment: Vector2 = right_wall_segments_y[i]
		var height := segment.y - segment.x
		var center_y := (segment.x + segment.y) * 0.5
		_add_wall(walls, "WallRight%d" % i,
			Vector2(play_size.x + wall_thickness * 0.5, center_y), Vector2(wall_thickness, height))

	var wide := play_size.x + wall_thickness * 4.0
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
