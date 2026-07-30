class_name Arena
extends Node2D

## Oyun alani: sekilebilir kenarlar ve fiziksel arena sinirlari.
##
## Tam ekran zemin Gameplay sahnesindeki InkBackground tarafindan cizilir.
## Arena yalnizca 720x1280 oyun alaninin cerceve ve collision sinirlarini
## uretir. Alt kenar aciktir; top asagi duserse atis sifirlanir.

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

@export_group("Kenar Yuzeyleri")
## Duvarin collision yuzeyinden oyun alanina dogru uzandigi mat bant genisligi.
@export_range(8.0, 24.0, 1.0) var wall_visual_width := 14.0
## Bandin IC kenarindaki daha acik vurgu seridi.
@export_range(1.0, 6.0, 0.5) var wall_highlight_width := 2.5
## Segment uclarinin yuvarlatma yaricapi. Bosluklarin nerede basladigi
## boylece ilk bakista okunur.
@export var wall_cap_radius := 6.0
@export var wall_surface_color := Palette.SURFACE
@export var wall_highlight_color := Palette.SURFACE_LIGHT
@export_range(0.0, 1.0, 0.01) var wall_highlight_alpha := 0.85


func _ready() -> void:
	rebuild()


func get_play_rect() -> Rect2:
	return Rect2(Vector2.ZERO, play_size)


## Bolum verisinden gelen kenar segmentlerini uygular ve arenayi yeniden kurar.
## gameplay.gd bunu kendi _ready'sinde cagirir (Arena'nin _ready'si once calisir).
func configure(left_segments: Array[Vector2], right_segments: Array[Vector2]) -> void:
	left_wall_segments_y = left_segments
	right_wall_segments_y = right_segments
	if is_node_ready():
		rebuild()


## Uretilmis tum zemin/cerceve/duvar dugumlerini atip bastan olusturur.
## remove_child sart: yalnizca queue_free eski duvarlari kare sonuna kadar
## fizik dunyasinda birakir ve yeni bolumde hayalet carpisma yaratirdi.
func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build_frame()
	_build_walls()


# --- Gorunum -----------------------------------------------------------------

## Alt kenar hicbir zaman cizilmez. Sol/sag kenarlar, kendi fizik
## duvarlariyla birebir ayni y araliginda cizilir; boslukta hicbir sey yoktur,
## boylece oyuncu acigin tam olarak nerede oldugunu gorur.
##
## Bant collision yuzeyinden OYUN ALANINA DOGRU uzanir. aspect="expand"
## dikey bosluk uretir, yatayda oyun alani ekran genisligini tam doldurur -
## disari dogru cizilen bir bant telefonlarda gorunmezdi.
func _build_frame() -> void:
	_build_side_surface("Left", left_wall_segments_y, 0.0, 1.0)
	_build_side_surface("Right", right_wall_segments_y, play_size.x, -1.0)
	_build_top_surface()


## [param outer_x] collision yuzeyi, [param direction] oyun alanina dogru yon.
func _build_side_surface(side_name: String, segments: Array[Vector2],
		outer_x: float, direction: float) -> void:
	for i in segments.size():
		var segment: Vector2 = segments[i]
		var y_start := clampf(segment.x, 0.0, play_size.y)
		var y_end := clampf(segment.y, 0.0, play_size.y)
		var height := y_end - y_start
		if height < 1.0:
			continue

		var center_y := (y_start + y_end) * 0.5
		add_child(_make_wall_surface(
			"Wall%sSurface%d" % [side_name, i],
			Vector2(outer_x + direction * wall_visual_width * 0.5, center_y),
			Vector2(wall_visual_width, height),
			wall_surface_color))
		add_child(_make_wall_surface(
			"Wall%sHighlight%d" % [side_name, i],
			Vector2(outer_x + direction * (wall_visual_width - wall_highlight_width * 0.5), center_y),
			Vector2(wall_highlight_width, height),
			Color(wall_highlight_color, wall_highlight_alpha)))


## Tavan da ayni mat dille cizilir; yoksa kalin yan bantlarin yaninda
## ince bir cizgi olarak yarim kalirdi.
func _build_top_surface() -> void:
	add_child(_make_wall_surface(
		"WallTopSurface",
		Vector2(play_size.x * 0.5, wall_visual_width * 0.5),
		Vector2(play_size.x, wall_visual_width),
		wall_surface_color))
	add_child(_make_wall_surface(
		"WallTopHighlight",
		Vector2(play_size.x * 0.5, wall_visual_width - wall_highlight_width * 0.5),
		Vector2(play_size.x, wall_highlight_width),
		Color(wall_highlight_color, wall_highlight_alpha)))


func _make_wall_surface(surface_name: String, center: Vector2, size: Vector2,
		color: Color) -> Polygon2D:
	var polygon := ShapeBuilder.make_polygon(
		ShapeBuilder.rounded_rect(size, wall_cap_radius, 4), color)
	polygon.name = surface_name
	polygon.position = center
	polygon.z_index = -50
	return polygon


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
