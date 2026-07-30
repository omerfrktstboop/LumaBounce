class_name MenuDecor
extends Control

## Ana menudeki sade dekoratif kompozisyon: iki mat egimli panel, kare hedef
## ve neon top.
##
## Bilerek oynanisi TAKLIT ETMEZ - top firlatilmaz, sekmez, panellere carpmaz.
## Yalnizca cok yavas bir suzulme (top) ve cok yavas bir nabiz (hedef) vardir;
## amac dikkat dagitmadan oyunun ne oldugunu bir bakista anlatmak.
##
## Kompozisyon tasarim uzayinda (design_size) kurulur ve Control'un rect'ine
## sigacak sekilde olceklenir; boylece farkli ekran oranlarinda bozulmaz.

@export var design_size := Vector2(560.0, 470.0)
@export var ball_radius := 26.0
@export var target_size := 62.0
@export var panel_length := 210.0
@export var panel_thickness := 26.0

@export_group("Idle Hareket")
@export var float_distance := 7.0
@export var float_time := 3.4
@export var target_pulse_time := 3.0

var _root: Node2D
var _orb: NeonOrb
var _target: NeonSquare
var _float_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	resized.connect(_layout)
	_layout()
	_start_idle()


func _build() -> void:
	_root = Node2D.new()
	_root.name = "Composition"
	add_child(_root)

	# Iki mat panel capraz bir denge kuruyor.
	_add_panel(Vector2(-132.0, -18.0), -20.0)
	_add_panel(Vector2(128.0, 46.0), 20.0)

	_target = NeonSquare.new()
	_target.name = "Target"
	_target.square_size = target_size
	_target.corner_radius = target_size * 0.22
	_target.position = Vector2(0.0, -168.0)
	_root.add_child(_target)

	_orb = NeonOrb.new()
	_orb.name = "Orb"
	_orb.radius = ball_radius
	_orb.position = Vector2(0.0, 168.0)
	_root.add_child(_orb)


## bounce_panel.gd ile ayni gorsel dil: mat govde + ince kontur + ust isik.
func _add_panel(at: Vector2, rotation_deg: float) -> void:
	var panel := Node2D.new()
	panel.position = at
	panel.rotation = deg_to_rad(rotation_deg)
	_root.add_child(panel)

	var body := ShapeBuilder.stadium(panel_length, panel_thickness)
	panel.add_child(ShapeBuilder.make_polygon(body, Palette.SURFACE))
	panel.add_child(ShapeBuilder.make_outline(body, Palette.SURFACE_EDGE, 3.0))

	var top_light := ShapeBuilder.make_polygon(
		ShapeBuilder.stadium(panel_length - panel_thickness * 1.4, panel_thickness * 0.2),
		Color(Palette.SURFACE_LIGHT, 0.5))
	top_light.position = Vector2(0.0, -panel_thickness * 0.27)
	panel.add_child(top_light)


func _layout() -> void:
	if _root == null:
		return
	_root.position = size * 0.5
	var fit := minf(size.x / design_size.x, size.y / design_size.y)
	_root.scale = Vector2.ONE * clampf(fit, 0.5, 1.0)


func _start_idle() -> void:
	_target.start_idle_pulse(1.06, target_pulse_time)

	var base_y := _orb.position.y
	if _float_tween != null and _float_tween.is_valid():
		_float_tween.kill()
	_float_tween = create_tween().set_loops()
	_float_tween.tween_property(_orb, "position:y", base_y - float_distance, float_time * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_float_tween.tween_property(_orb, "position:y", base_y + float_distance, float_time * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
