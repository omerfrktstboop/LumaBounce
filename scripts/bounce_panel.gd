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
@export var surface_color := Palette.SURFACE
@export var edge_color := Palette.SURFACE_EDGE
@export var top_light_color := Palette.SURFACE_LIGHT
## Zeminden ayrisip okunakli olmasi icin kontur belirgin tutulur (neon degil).
@export var outline_width := 3.2
@export_range(0.0, 1.0, 0.01) var top_light_alpha := 0.6

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

	var body_points := ShapeBuilder.stadium(length, thickness)

	# Mat govde.
	_visual.add_child(ShapeBuilder.make_polygon(body_points, surface_color))

	# Ince kontur - derinlik hissini bu veriyor.
	_visual.add_child(ShapeBuilder.make_outline(body_points, edge_color, outline_width))

	# Ust kenarda guclendirilmis isik tanimi - okunabilirligi bu artirir.
	var top_light := ShapeBuilder.make_polygon(
		ShapeBuilder.stadium(length - thickness * 1.4, thickness * 0.22),
		Color(top_light_color, top_light_alpha))
	top_light.position = Vector2(0.0, -thickness * 0.27)
	_visual.add_child(top_light)
