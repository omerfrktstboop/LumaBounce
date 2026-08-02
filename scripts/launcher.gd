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
signal power_step_crossed(step_index: int, step_count: int)

## Guvenlik siniri: kilavuz en fazla bu kadar fizik "tick"i ileri simule eder.
const SIM_MAX_ITERATIONS := 400
## Tek bir tick icinde (mikro-carpismalar icin) en fazla sekme denemesi.
## ball.gd'deki max_bounces_per_step ile ayni degeri kullanir.
const MAX_BOUNCES_PER_TICK := 6

@export_group("Guc")
@export var min_power := 900.0
@export var max_power := 2200.0
## Bu mesafeden kisa suruklemeler atis saymaz.
@export var min_drag_distance := 30.0
## Bu mesafeden sonra guc artmaz.
@export var max_drag_distance := 140.0

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
## gameplay.gd bunu topun radius degeriyle esitler. Carpisma testi (shape
## cast) bu yaricapi kullanir; boylece onizleme, topun kendisi gibi yuzeye
## merkezi degil govdesi degdiginde durur.
@export var preview_ball_radius := 24.0
## gameplay.gd bunu topun max_speed degeriyle esitler.
@export var preview_max_speed := 3000.0
## Noktalar arasi ekran mesafesi.
@export var dot_spacing := 27.0
@export var max_dots := 20
## Kilavuzun en dusuk / en yuksek gucteki uzunlugu (fiziksel bir yuzeye
## carpmadigi surece gecerlidir - carparsa kilavuz orada durur).
@export var guide_length_min := 190.0
@export var guide_length_max := 560.0
## Bolum ilerledikce gameplay tarafindan 1.0'dan 0.5'e indirilir. Yalnizca
## gorunen nokta sayisini/mesafeyi etkiler; hesaplanan impuls degismez.
var guide_visibility_ratio := 1.0

@export_group("Gorunum")
@export var accent := Palette.ACCENT
@export var accent_core := Palette.ACCENT_CORE
@export var base_size := Vector2(132.0, 56.0)
@export var base_corner := 25.0
@export var barrel_length := 64.0
@export var barrel_width := 22.0
## Nisan sirasinda namlu ucundaki vurgunun guce gore buyume carpani.
@export var tip_power_scale := 1.7

@export_group("Guc Gostergesi")
@export_range(3, 8, 1) var power_step_count := 6
@export var power_segment_size := Vector2(16.0, 7.0)
@export var power_meter_offset := Vector2(82.0, 22.0)
@export var power_segment_spacing := 13.0
## Hazir topun gorseli tam gucte namlu boyunca bu kadar geriye gelir.
## Ball govdesinin fizik konumu degismez.
@export var loaded_ball_pullback_distance := 14.0

@export_group("Surukleme Alani")
## Firlaticinin altinda, parmagin cekilebilecegi bolgeyi sessizce tarif eden
## yarim halka. Dis yaricap dogrudan tam guc mesafesini kullanir.
@export_range(0.02, 0.3, 0.01) var drag_hint_fill_alpha := 0.09
@export_range(0.1, 1.0, 0.05) var drag_hint_idle_alpha := 0.62

@export_group("Geri Tepme")
## Atis birakildiginda namlunun ters yonde kacacagi kisa mesafe.
@export var recoil_distance := 9.0
@export var recoil_out_time := 0.05
@export var recoil_return_time := 0.16
## Guc maksimuma ulastiginda namlu ucunda oynayan kontrollu kucuk vurgu.
@export_range(1.0, 1.6, 0.01) var max_power_pulse_scale := 1.22
@export var max_power_pulse_time := 0.16

## Kapatilinca nisan alma iptal edilir.
var enabled := true:
	set(value):
		enabled = value
		if is_node_ready():
			if not value:
				cancel_aim()
			_set_drag_hint(_aiming)

@onready var _base: Node2D = $Base
@onready var _drag_hint: Node2D = $DragHint
@onready var _power_meter: Node2D = $PowerMeter
@onready var _barrel: Node2D = $Barrel
@onready var _guide: AimGuide = $AimGuide

var _barrel_tip: Polygon2D
var _power_segments: Array[Polygon2D] = []
var _recoil_tween: Tween
var _max_power_tween: Tween
var _barrel_rest_position := Vector2.ZERO

var _aiming := false
var _drag_start := Vector2.ZERO
var _drag_distance := 0.0
var _direction := Vector2.UP
var _power_ratio := 0.0
var _was_at_max_power := false
var _highest_power_step := 0


func _ready() -> void:
	_build_drag_hint()
	_build_base()
	_build_barrel()
	_build_power_meter()
	_guide.clear_guide()
	_set_barrel_pose(0.0)
	_set_power_meter(0, false)
	_set_drag_hint(false)


# --- Dis API -----------------------------------------------------------------

## Topun bekledigi nokta.
func get_spawn_position() -> Vector2:
	return global_position + Vector2.UP * ball_spawn_offset


func get_power() -> float:
	return lerpf(min_power, max_power, _power_ratio)


func get_power_ratio() -> float:
	return _power_ratio


func get_aim_direction() -> Vector2:
	return _direction


func get_power_step() -> int:
	return _power_step_for_ratio(_power_ratio)


func set_guide_visibility_ratio(value: float) -> void:
	guide_visibility_ratio = clampf(value, 0.4, 1.0)
	if is_node_ready() and _aiming:
		_refresh_aim_visual()


func get_guide_visibility_ratio() -> float:
	return guide_visibility_ratio


func is_aiming() -> bool:
	return _aiming


## Surukleme minimum esigi gecti mi - yani su an birakilirsa gercek bir atis
## olusur mu. Salt okunur; nisan hesabina veya fizige dokunmaz.
func has_valid_aim() -> bool:
	return _aiming and _drag_distance >= min_drag_distance


func begin_aim(pointer_position: Vector2) -> void:
	if not enabled or _aiming:
		return
	_aiming = true
	_drag_start = pointer_position
	_drag_distance = 0.0
	_power_ratio = 0.0
	_was_at_max_power = false
	_highest_power_step = 0
	if _recoil_tween != null and _recoil_tween.is_valid():
		_recoil_tween.kill()
	_refresh_aim_visual()
	_set_power_meter(0, true)
	_set_drag_hint(true)
	aim_started.emit()


func update_aim(pointer_position: Vector2) -> void:
	if not _aiming:
		return
	_evaluate_drag(pointer_position)
	_update_power_step()
	_refresh_aim_visual()
	aim_updated.emit(_power_ratio, _direction)


## Nisani birakir. Gecerli bir atis olustuysa true doner.
func release_aim() -> bool:
	if not _aiming:
		return false
	_aiming = false
	_guide.clear_guide()
	_set_power_meter(0, false)
	_set_drag_hint(false)
	_set_barrel_pose(0.0)
	# Tam guc titresimi ortasinda birakilmis olabilir; ipucu her durumda
	# sifira donsun diye tweeni once iptal ediyoruz.
	if _max_power_tween != null and _max_power_tween.is_valid():
		_max_power_tween.kill()
	_set_tip_power(0.0)
	if _drag_distance < min_drag_distance:
		aim_cancelled.emit()
		return false
	_play_recoil()
	shot_fired.emit(_direction * get_power())
	return true


func cancel_aim() -> void:
	var was_aiming := _aiming
	_aiming = false
	_drag_distance = 0.0
	_power_ratio = 0.0
	_guide.clear_guide()
	_highest_power_step = 0
	_set_power_meter(0, false)
	_set_drag_hint(false)
	_set_barrel_pose(0.0)
	if _max_power_tween != null and _max_power_tween.is_valid():
		_max_power_tween.kill()
	_set_tip_power(0.0)
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


## Topun gercek fizik dongusunu (ball.gd) birebir taklit eder: her "tick"te
## once yer cekimi eklenir (velocity.y += gravity*delta), sonra hiz sinirlanir
## ve o sabit hizla bir DUZ segment kadar hareket denenir - tipki
## move_and_collide(velocity*delta)'nin yaptigi gibi. Carpisma testi topun
## gercek yaricapini kullanan bir CircleShape2D shape-cast'i ile yapilir;
## boylece onizleme merkez-nokta degil govde temasina gore durur.
## Ilk carpismada topun gercek sekme formuluyle (velocity.bounce * bounciness)
## bir kez yansitilip ikinci carpismaya veya guc sinirina kadar devam eder,
## boylece oyuncu "ilk sekmeyi" de onceden gorebilir.
## Her duz segment boyunca (fizik adimindan bagimsiz) esit ARC araliklarinda
## nokta yerlestirilir -> ekranda esit aralikli, pürüzsüz noktalar.
func _build_guide_dots() -> PackedVector2Array:
	var space_state := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = preview_ball_radius

	var dots := PackedVector2Array()
	var total_length := (
		lerpf(guide_length_min, guide_length_max, _power_ratio)
		* guide_visibility_ratio)
	var visible_dot_limit := maxi(8, roundi(float(max_dots) * guide_visibility_ratio))
	var point := Vector2.UP * ball_spawn_offset
	var velocity := _direction * get_power()
	var travelled := 0.0
	var next_dot := 0.0
	var has_bounced := false
	# ball.gd'nin _physics_process'i her fizik "tick"inde calisir; onizleme
	# ayni sabit adimla ilerlemezse egri ve carpisma noktalari kayar.
	var fixed_delta := 1.0 / float(Engine.physics_ticks_per_second)

	for _tick in SIM_MAX_ITERATIONS:
		# ball.gd ile ayni sira: once yer cekimi, sonra hiz sinirlama, sonra hareket.
		velocity.y += preview_gravity * fixed_delta
		velocity = velocity.limit_length(preview_max_speed)
		var motion := velocity * fixed_delta

		for _sub_step in MAX_BOUNCES_PER_TICK:
			var hit := _cast_ball_motion(space_state, shape, point, motion)
			var has_hit := not hit.is_empty()
			# Dictionary degerleri Variant doner; ternary/aritmetikte tip
			# belirsizligi olusmasin diye acikca Vector2/float'a sabitlenir.
			var segment_end: Vector2 = hit["position"] if has_hit else (point + motion)
			var segment_length := point.distance_to(segment_end)

			while next_dot <= travelled + segment_length:
				var t := 0.0 if segment_length <= 0.0001 else (next_dot - travelled) / segment_length
				dots.append(point.lerp(segment_end, t))
				next_dot += dot_spacing
				if dots.size() >= visible_dot_limit:
					return dots

			travelled += segment_length
			point = segment_end

			if travelled >= total_length:
				return dots
			if not has_hit:
				break

			# Tam carpisma noktasini net bir "sekme" isareti olarak da ekle.
			dots.append(point)
			if dots.size() >= visible_dot_limit or has_bounced:
				return dots
			has_bounced = true

			var hit_normal: Vector2 = hit["normal"]
			var hit_fraction: float = hit["fraction"]
			var remainder := motion * (1.0 - hit_fraction)
			velocity = velocity.bounce(hit_normal) * preview_bounciness
			motion = remainder.bounce(hit_normal) * preview_bounciness

	return dots


## Yarıçapı topunkiyle ayni olan bir CircleShape2D'yi from_local -> from_local+motion
## boyunca "obstacle" katmanina (paneller + duvarlar) karsi supurur. Godot'ta
## normal donen tek bir sweep fonksiyonu olmadigi icin standart iki adimli
## yontem kullanilir: once cast_motion ile ilk temasin oldugu fraction bulunur,
## sonra tam o pozisyonda get_rest_info ile temas noktasi/normali okunur.
## Hedef (Area2D) ve topun kendisi bu katmanda olmadigi icin etkilenmez.
func _cast_ball_motion(
		space_state: PhysicsDirectSpaceState2D, shape: CircleShape2D,
		from_local: Vector2, motion_local: Vector2) -> Dictionary:
	if motion_local.is_zero_approx():
		return {}

	var from_global := to_global(from_local)
	var motion_global := global_transform.basis_xform(motion_local)

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.collision_mask = Arena.OBSTACLE_LAYER
	params.transform = Transform2D(0.0, from_global)
	params.motion = motion_global

	var fractions := space_state.cast_motion(params)
	if fractions.is_empty() or fractions[1] >= 1.0:
		return {}

	var unsafe_fraction: float = fractions[1]
	params.transform = Transform2D(0.0, from_global + motion_global * unsafe_fraction)
	params.motion = Vector2.ZERO
	var rest := space_state.get_rest_info(params)
	if rest.is_empty():
		return {}

	var inverse_basis := global_transform.affine_inverse()
	return {
		"position": to_local(rest["point"]),
		"normal": inverse_basis.basis_xform(rest["normal"]).normalized(),
		"fraction": unsafe_fraction,
	}


# --- Gorunum -----------------------------------------------------------------

## Guc bu esigin ustundeyken "maksimuma ulasildi" sayilir.
const MAX_POWER_THRESHOLD := 0.98


func _refresh_aim_visual() -> void:
	_set_barrel_pose(_power_ratio if _aiming else 0.0)
	if not _aiming or _drag_distance < min_drag_distance:
		_guide.clear_guide()
		_set_tip_power(0.0)
		return
	# Guc arttikca kilavuz hem uzar hem beyaza dogru parlar.
	_guide.set_guide(_build_guide_dots(), accent.lerp(accent_core, _power_ratio * 0.5))
	_set_tip_power(_power_ratio)
	_check_max_power_pulse()


func _power_step_for_ratio(power_ratio: float) -> int:
	return clampi(floori(clampf(power_ratio, 0.0, 1.0) * power_step_count), 0, power_step_count)


func _update_power_step() -> void:
	var step := _power_step_for_ratio(_power_ratio)
	_set_power_meter(step, true)
	if step <= _highest_power_step:
		return
	_highest_power_step = step
	power_step_crossed.emit(step, power_step_count)


func _set_barrel_pose(power_ratio: float) -> void:
	_barrel.rotation = Vector2.UP.angle_to(_direction)
	var loaded_ball_position := (
		Vector2.UP * ball_spawn_offset
		- _direction * loaded_ball_pullback_distance * clampf(power_ratio, 0.0, 1.0))
	var tip_distance := barrel_length - 7.0
	_barrel_rest_position = loaded_ball_position - _direction * tip_distance
	_barrel.position = _barrel_rest_position


func _set_power_meter(active_steps: int, show_meter: bool) -> void:
	if _power_meter == null:
		return
	_power_meter.visible = show_meter
	for i in _power_segments.size():
		var segment := _power_segments[i]
		var active := i < active_steps
		var strength := float(i + 1) / float(maxi(power_step_count, 1))
		segment.color = (
			Color(accent.lerp(accent_core, strength * 0.65), 0.95)
			if active else Color(Palette.SURFACE_LIGHT, 0.32))
		segment.scale = Vector2.ONE * (1.12 if active and i == active_steps - 1 else 1.0)


func _set_drag_hint(active: bool) -> void:
	if _drag_hint == null:
		return
	_drag_hint.visible = enabled
	_drag_hint.modulate.a = 1.0 if active else drag_hint_idle_alpha


## Namlu ucundaki vurgu, sürükleme gucuyle birlikte buyuyup parlayarak
## yon + guc geri bildirimini firlaticinin uzerinde de belirginlestirir.
## Maksimum-guc titresimi calisirken (bkz. _play_max_power_pulse) devreye
## girmez; yoksa her karede cagrilan bu fonksiyon tweeni ezerdi.
func _set_tip_power(power_ratio: float) -> void:
	if _barrel_tip == null:
		return
	if _max_power_tween != null and _max_power_tween.is_valid():
		return
	_barrel_tip.scale = Vector2.ONE * lerpf(1.0, tip_power_scale, power_ratio)
	_barrel_tip.color = Color(accent.lerp(accent_core, power_ratio * 0.4), lerpf(0.75, 1.0, power_ratio))


## Guc maksimuma ULASTIGI ANDA (surekli degil, bir kereligine) kucuk,
## kontrollu bir vurgu oynatir.
func _check_max_power_pulse() -> void:
	var at_max := _power_ratio >= MAX_POWER_THRESHOLD
	if at_max and not _was_at_max_power:
		_play_max_power_pulse()
	_was_at_max_power = at_max


func _play_max_power_pulse() -> void:
	if _barrel_tip == null:
		return
	if _max_power_tween != null and _max_power_tween.is_valid():
		_max_power_tween.kill()
	_max_power_tween = create_tween()
	_max_power_tween.tween_property(
			_barrel_tip, "scale", Vector2.ONE * max_power_pulse_scale, max_power_pulse_time * 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Tweenin son degeri _set_tip_power'in bu guc oraninda uretecegi degerle
	# aynidir; kontrol devri sirasinda gorsel sicrama olmaz.
	_max_power_tween.tween_property(
			_barrel_tip, "scale", Vector2.ONE * tip_power_scale, max_power_pulse_time * 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Atis birakildiginda namlunun yaptigi cok kisa, hafif geri tepme.
func _play_recoil() -> void:
	if _recoil_tween != null and _recoil_tween.is_valid():
		_recoil_tween.kill()
	_barrel.position = _barrel_rest_position - _direction * recoil_distance
	_recoil_tween = create_tween()
	_recoil_tween.tween_interval(recoil_out_time)
	_recoil_tween.tween_property(_barrel, "position", _barrel_rest_position, recoil_return_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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


## Asagi dogru cekis hareketinin kullanilabilir alanini gosteren ince bir
## yarim halka. Metin kullanmadan yonu ve tam guc sinirini okunur kilar.
func _build_drag_hint() -> void:
	for child in _drag_hint.get_children():
		child.queue_free()

	var outer_radius := max_drag_distance
	var inner_radius := maxf(min_drag_distance + 12.0, 48.0)
	var start_angle := deg_to_rad(18.0)
	var end_angle := deg_to_rad(162.0)
	var arc_segments := 28
	var outer_points := PackedVector2Array()
	var inner_points := PackedVector2Array()
	for i in arc_segments + 1:
		var angle := lerpf(start_angle, end_angle, float(i) / float(arc_segments))
		outer_points.append(Vector2.from_angle(angle) * outer_radius)
		inner_points.append(Vector2.from_angle(angle) * inner_radius)

	var area_points := outer_points.duplicate()
	for i in range(inner_points.size() - 1, -1, -1):
		area_points.append(inner_points[i])
	_drag_hint.add_child(ShapeBuilder.make_polygon(
		area_points, Color(Palette.SURFACE_LIGHT, drag_hint_fill_alpha)))

	var outer_line := Line2D.new()
	outer_line.points = outer_points
	outer_line.default_color = Color(Palette.SURFACE_LIGHT, 0.48)
	outer_line.width = 2.0
	outer_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	outer_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	outer_line.antialiased = true
	_drag_hint.add_child(outer_line)

	var inner_line := Line2D.new()
	inner_line.points = inner_points
	inner_line.default_color = Color(Palette.SURFACE_LIGHT, 0.24)
	inner_line.width = 1.5
	inner_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	inner_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	inner_line.antialiased = true
	_drag_hint.add_child(inner_line)

	var chevron := Line2D.new()
	chevron.points = PackedVector2Array([
		Vector2(-9.0, outer_radius - 24.0),
		Vector2(0.0, outer_radius - 15.0),
		Vector2(9.0, outer_radius - 24.0),
	])
	chevron.default_color = Color(accent, 0.72)
	chevron.width = 3.0
	chevron.begin_cap_mode = Line2D.LINE_CAP_ROUND
	chevron.end_cap_mode = Line2D.LINE_CAP_ROUND
	chevron.joint_mode = Line2D.LINE_JOINT_ROUND
	chevron.antialiased = true
	_drag_hint.add_child(chevron)


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


func _build_power_meter() -> void:
	for child in _power_meter.get_children():
		child.queue_free()
	_power_segments.clear()
	for i in power_step_count:
		var segment := ShapeBuilder.make_polygon(
			ShapeBuilder.stadium(power_segment_size.x, power_segment_size.y),
			Color(Palette.SURFACE_LIGHT, 0.32))
		segment.position = power_meter_offset + Vector2.UP * power_segment_spacing * i
		_power_meter.add_child(segment)
		_power_segments.append(segment)
