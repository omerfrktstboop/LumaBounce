class_name BouncePanel
extends StaticBody2D

## Sabit egimli sekme paneli.
##
## Bilerek SESSIZ bir eleman: mat yuzey rengi, ince kenar, cok hafif ust
## kenar tanimi. Neon yok - top ve hedefle yarismamali, sadece bulmacanin
## okunabilirligini desteklemeli.
##
## Carpisma sekli olarak CapsuleShape2D kullanilir; boylece uclar gercekten
## yuvarlaktir ve top kose yakalayip takilmaz. Gorsel de ayni stadyum
## seklinden uretildigi icin gorunum ve fizik birebir ortusur.

@export var length := 250.0:
	set(value):
		length = maxf(value, 1.0)
		if is_node_ready():
			_rebuild()
@export var thickness := 27.0:
	set(value):
		thickness = maxf(value, 2.0)
		if is_node_ready():
			_rebuild()

@export_group("Gorunum")
## Zeminden ~%10 daha acik mat govde (bkz. Palette.SURFACE_PANEL).
@export var surface_color := Palette.SURFACE_PANEL
@export var edge_color := Palette.SURFACE_EDGE
@export var top_light_color := Palette.SURFACE_LIGHT
## Zeminden ayrisip okunakli olmasi icin kontur belirgin tutulur (neon degil).
@export var outline_width := 3.2
@export_range(0.0, 1.0, 0.01) var top_light_alpha := 0.75
## CIZIM kalinligi carpani. Collision kapsulu her zaman ham [member thickness]
## degerini kullanir; bu carpan yalnizca goruntuyu kalinlastirir, boylece
## paneller daha okunur olurken sekme fizigi birebir ayni kalir.
@export_range(1.0, 1.3, 0.01) var visual_thickness_scale := 1.1

@onready var _shape: CollisionShape2D = $Shape
@onready var _visual: Node2D = $Visual


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	_apply_shape()
	_build_visual()


func _apply_shape() -> void:
	# Her panel kendi sekline sahip olsun (sahne alt kaynagi paylasilmasin).
	var capsule := CapsuleShape2D.new()
	capsule.radius = thickness * 0.5
	capsule.height = maxf(length, thickness)
	_shape.shape = capsule
	# CapsuleShape2D dikey uretilir; paneli yerel X ekseni boyunca yatirmak icin cevir.
	_shape.rotation = PI * 0.5


func _build_visual() -> void:
	for child in _visual.get_children():
		child.queue_free()

	# Yalnizca cizim kalinlasir; _apply_shape ham thickness'i kullanmaya devam
	# eder, dolayisiyla carpisma yaricapi ve tum yorungeler degismez.
	var draw_thickness := thickness * visual_thickness_scale
	var body_points := ShapeBuilder.stadium(length, draw_thickness)

	# Mat govde.
	_visual.add_child(ShapeBuilder.make_polygon(body_points, surface_color))

	# Ince kontur - derinlik hissini bu veriyor.
	_visual.add_child(ShapeBuilder.make_outline(body_points, edge_color, outline_width))

	# Ust kenarda guclendirilmis isik tanimi - okunabilirligi bu artirir.
	var top_light := ShapeBuilder.make_polygon(
		ShapeBuilder.stadium(length - draw_thickness * 1.4, draw_thickness * 0.26),
		Color(top_light_color, top_light_alpha))
	top_light.position = Vector2(0.0, -draw_thickness * 0.27)
	_visual.add_child(top_light)
