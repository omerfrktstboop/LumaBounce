class_name Launcher
extends Node2D

## Ekranin altindaki sabit firlatici.
##
## Gorsel olarak SESSIZ bir eleman: mat surface tonlari, sadece namlu ucunda
## kucuk bir vurgu. Parlak olan sey nisan kilavuzu ve topun kendisi.
##
## Oyuncu ekrana basip GERIYE dogru surukler: suruklemenin tersi yon = atis yonu,
## surukleme uzunlugu = guc. Birakinca [signal shot_fired] yayilir.
## Girdi olaylarini kendisi dinlemez; gameplay.gd isaretci konumlarini iletir.
## begin_aim/release_aim cagrilari idempotenttir, boylece dokunma + emule
## edilmis fare olaylarinin birlikte gelmesi cift atis yaratmaz.

signal aim_started()
signal aim_updated(power_ratio: float, direction: Vector2)
signal aim_cancelled()
signal shot_fired(impulse: Vector2)

## Yorunge ornekleme adimi (saniye). Kucuk = daha duzgun yay ve daha ince
## carpisma kontrolu (her mikro-adimda bir raycast atilir).
const SIM_STEP := 0.005
const SIM_MAX_ITERATIONS := 400

@export_group("Guc")
@export var min_power := 900.0
@export var max_power := 2300.0
## Bu mesafeden kisa suruklemeler atis saymaz.
@export var min_drag_distance := 30.0
## Bu mesafeden sonra guc artmaz.
@export var max_drag_distance := 340.0

@export_group("Aci")
## Dik yukari yonden sapabilecegi en buyuk aci.
@export_range(10.0, 89.0, 1.0) var max_aim_angle_deg := 78.0

@export_group("Yerlesim")
## Topun firlatici merkezine gore bekleme yuksekligi.
## Nisan kilavuzu da buradan basladigi icin onizleme gercek yorungeyle ortusur.
@export var ball_spawn_offset := 70.0

@export_group("Nisan Kilavuzu")
## gameplay.gd bunu topun gravity degeriyle esitler.
@export var preview_gravity := 1500.0
## gameplay.gd bunu topun bounciness degeriyle esitler.
@export_range(0.5, 1.0, 0.01) var preview_bounciness := 0.94
## Noktalar arasi ekran mesafesi.
@export var dot_spacing := 27.0
@export var max_dots := 20
## Kilavuzun en dusuk / en yuksek gucteki uzunlugu (fiziksel bir yuzeye
## carpmadigi surece gecerlidir - carparsa kilavuz orada durur).
@export var guide_length_min := 190.0
@export var guide_length_max := 560.0

@export_group("Gorunum")
@export var accent := Palette.ACCENT
@export var accent_core := Palette.ACCENT_CORE
@export var base_size := Vector2(132.0, 56.0)
@export var base_corner := 25.0
@export var barrel_length := 64.0
@export var barrel_width := 22.0
## Nisan sirasinda namlu ucundaki vurgunun guce gore buyume carpani.
@export var tip_power_scale := 1.7

## Kapatilinca nisan alma iptal edilir.
var enabled := true:
	set(value):
		enabled = value
		if not value and is_node_ready():
			cancel_aim()

@onready var _base: Node2D = $Base
@onready var _barrel: Node2D = $Barrel
@onready var _guide: AimGuide = $AimGuide

var _barrel_tip: Polygon2D

var _aiming := false
var _drag_start := Vector2.ZERO
var _drag_distance := 0.0
var _direction := Vector2.UP
var _power_ratio := 0.0


func _ready() -> void:
	_build_base()
	_build_barrel()
	_guide.clear_guide()
	_barrel.rotation = 0.0


# --- Dis API -----------------------------------------------------------------

## Topun bekledigi nokta.
func get_spawn_position() -> Vector2:
	return global_position + Vector2.UP * ball_spawn_offset


func get_power() -> float:
	return lerpf(min_power, max_power, _power_ratio)


func is_aiming() -> bool:
	return _aiming


func begin_aim(pointer_position: Vector2) -> void:
	if not enabled or _aiming:
		return
	_aiming = true
	_drag_start = pointer_position
	_drag_distance = 0.0
	_power_ratio = 0.0
	_refresh_aim_visual()
	aim_started.emit()


func update_aim(pointer_position: Vector2) -> void:
	if not _aiming:
		return
	_evaluate_drag(pointer_position)
	_refresh_aim_visual()
	aim_updated.emit(_power_ratio, _direction)


## Nisani birakir. Gecerli bir atis olustuysa true doner.
func release_aim() -> bool:
	if not _aiming:
		return false
	_aiming = false
	_guide.clear_guide()
	if _drag_distance < min_drag_distance:
		aim_cancelled.emit()
		return false
	shot_fired.emit(_direction * get_power())
	return true


func cancel_aim() -> void:
	var was_aiming := _aiming
	_aiming = false
	_drag_distance = 0.0
	_power_ratio = 0.0
	_guide.clear_guide()
	if was_aiming:
		aim_cancelled.emit()


# --- Nisan hesabi ------------------------------------------------------------

func _evaluate_drag(pointer_position: Vector2) -> void:
	# Geriye cekilir, ileriye atilir.
	var drag := _drag_start - pointer_position
	_drag_distance = minf(drag.length(), max_drag_distance)
	if _drag_distance > 0.001:
		_direction = _clamp_direction(drag.normalized())
	_power_ratio = clampf(
		inverse_lerp(min_drag_distance, max_drag_distance, _drag_distance), 0.0, 1.0)


## Yonu yukari yarim duzleme sikistirir; asagi dogru atis yapilamaz.
func _clamp_direction(direction: Vector2) -> Vector2:
	var limit := deg_to_rad(max_aim_angle_deg)
	var angle := clampf(Vector2.UP.angle_to(direction), -limit, limit)
	return Vector2.UP.rotated(angle)


## Topun gercekte kullandigi ivmeyle yorungeyi ornekler VE fiziksel yuzeylere
## karsi mikro-adim basina raycast atar; kilavuz asla bir yuzeyin icinden
## gecmez. Ilk carpismada topun gercek sekme mantigiyla (velocity.bounce)
## bir kez yansitilip ikinci carpismaya veya guc sinirina kadar devam eder,
## boylece oyuncu "ilk sekmeyi" de onceden gorebilir.
## Noktalar esit ARC uzunluklarinda birakilir -> ekranda esit aralikli noktalar.
func _build_guide_dots() -> PackedVector2Array:
	var space_state := get_world_2d().direct_space_state
	var dots := PackedVector2Array()
	var total_length := lerpf(guide_length_min, guide_length_max, _power_ratio)
	var point := Vector2.UP * ball_spawn_offset
	var velocity := _direction * get_power()
	var travelled := 0.0
	var next_dot := 0.0
	var has_bounced := false

	for _i in SIM_MAX_ITERATIONS:
		if travelled >= next_dot:
			dots.append(point)
			next_dot += dot_spacing
			if dots.size() >= max_dots:
				break

		var next_point := point + velocity * SIM_STEP
		velocity.y += preview_gravity * SIM_STEP

		var hit := _cast_obstacle(space_state, point, next_point)
		if not hit.is_empty():
			dots.append(hit["position"])
			if has_bounced or dots.size() >= max_dots:
				break
			has_bounced = true
			velocity = velocity.bounce(hit["normal"]) * preview_bounciness
			travelled += point.distance_to(hit["position"])
			point = hit["position"]
			next_dot = travelled + dot_spacing
			continue

		travelled += point.distance_to(next_point)
		point = next_point
		if travelled >= total_length:
			break

	return dots


## Iki yerel nokta arasinda "obstacle" katmanina (paneller + duvarlar) karsi
## raycast atar. Hedef (Area2D) ve top bu katmanda olmadigi icin etkilenmez.
func _cast_obstacle(
		space_state: PhysicsDirectSpaceState2D, from_local: Vector2, to_local_point: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(
		to_global(from_local), to_global(to_local_point), Arena.OBSTACLE_LAYER)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return {}
	var inverse_basis := global_transform.affine_inverse()
	return {
		"position": to_local(result["position"]),
		"normal": inverse_basis.basis_xform(result["normal"]).normalized(),
	}


# --- Gorunum -----------------------------------------------------------------

func _refresh_aim_visual() -> void:
	_barrel.rotation = Vector2.UP.angle_to(_direction)
	if not _aiming or _drag_distance < min_drag_distance:
		_guide.clear_guide()
		_set_tip_power(0.0)
		return
	# Guc arttikca kilavuz hem uzar hem beyaza dogru parlar.
	_guide.set_guide(_build_guide_dots(), accent.lerp(accent_core, _power_ratio * 0.5))
	_set_tip_power(_power_ratio)


## Namlu ucundaki vurgu, sürükleme gucuyle birlikte buyuyup parlayarak
## yon + guc geri bildirimini firlaticinin uzerinde de belirginlestirir.
func _set_tip_power(power_ratio: float) -> void:
	if _barrel_tip == null:
		return
	_barrel_tip.scale = Vector2.ONE * lerpf(1.0, tip_power_scale, power_ratio)
	_barrel_tip.color = Color(accent.lerp(accent_core, power_ratio * 0.4), lerpf(0.75, 1.0, power_ratio))


## Mat, sessiz bir kaide: koyu yuzey + ince kenar.
func _build_base() -> void:
	for child in _base.get_children():
		child.queue_free()

	var edge := ShapeBuilder.make_polygon(
		ShapeBuilder.rounded_rect(base_size + Vector2(6.0, 6.0), base_corner + 3.0),
		Palette.SURFACE_EDGE)
	edge.position = Vector2(0.0, 2.0)
	_base.add_child(edge)

	_base.add_child(ShapeBuilder.make_polygon(
		ShapeBuilder.rounded_rect(base_size, base_corner), Palette.SURFACE))

	# Cok hafif ust kenar tanimi.
	var top_edge := ShapeBuilder.make_polygon(
		ShapeBuilder.rounded_rect(Vector2(base_size.x - 34.0, 5.0), 2.5),
		Color(Palette.SURFACE_LIGHT, 0.5))
	top_edge.position = Vector2(0.0, -base_size.y * 0.5 + 8.0)
	_base.add_child(top_edge)


func _build_barrel() -> void:
	for child in _barrel.get_children():
		child.queue_free()

	# Stadyum yatay uretilir; -90 derece cevirip yukari bakan namlu yapariz.
	var barrel := ShapeBuilder.make_polygon(
		ShapeBuilder.stadium(barrel_length, barrel_width), Palette.SURFACE_LIGHT)
	barrel.rotation = -PI * 0.5
	barrel.position = Vector2(0.0, -barrel_length * 0.5)
	_barrel.add_child(barrel)

	# Namlu ucundaki tek vurgu: sürükleme gucuyle buyur (bkz. _set_tip_power).
	# Merkez, poligon noktalarina degil node pozisyonuna verilir; boylece
	# _set_tip_power'daki "scale" konumu kaydirmadan sadece boyutu degistirir.
	_barrel_tip = ShapeBuilder.make_polygon(
		ShapeBuilder.circle(barrel_width * 0.34, 16), Color(accent, 0.75))
	_barrel_tip.position = Vector2(0.0, -barrel_length + 7.0)
	_barrel.add_child(_barrel_tip)
