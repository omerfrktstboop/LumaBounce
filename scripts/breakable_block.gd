class_name BreakableBlock
extends StaticBody2D

## Top temaslariyla catlayip kirilan engel.
##
## Normal tugla tek temasta, kilit tugla iki temasta kirilir. Hasar atislar
## arasinda kalir; ayni atis dogru sekmeyle geri donerse ikinci temasi da
## sayilir. Puan uretmez, yalnizca rota geometrisini degistirir.
##
## Fizik acisindan yalnizca "obstacle" katmanindaki siradan bir StaticBody2D'dir;
## topun sekme matematigi (bkz. ball.gd) bu dosyayi hic bilmez. Kirilma
## kararini gameplay.gd verir, blok sadece kendi durumunu ve efektini yonetir.
##
## Gorsel dil: panel "saglam" (acik mat govde, yuvarlak stadyum) hissi verir;
## blok "modulup kirilabilir" hissi verir - daha koyu govde, daha parlak ince
## kenar ve merkezde bir dikis cizgisi. Ikisi ilk bakista ayirt edilebilir.

## Blok gercekten bu cagriyla kirildi (tekrar cagrilarda yayilmaz).
signal broken(at: Vector2)
## Tugla kirilmadi ama bir can kaybetti.
signal damaged(at: Vector2, remaining_hits: int, maximum_hits: int)

@export var block_size := Vector2(160.0, 44.0):
	set(value):
		block_size = Vector2(maxf(value.x, 8.0), maxf(value.y, 8.0))
		if is_node_ready():
			_rebuild()

@export_range(1, 2, 1) var hit_points := 1:
	set(value):
		hit_points = clampi(value, 1, 2)
		if is_node_ready():
			_remaining_hits = hit_points
			_rebuild()

@export_group("Gorunum")
## Tek darbelik (hit_points == 1) tugla renkleri.
@export var surface_color := Palette.SURFACE_BLOCK
@export var edge_color := Palette.SURFACE_BLOCK_EDGE
@export var seam_color := Palette.SURFACE_BLOCK_SEAM
## Iki darbelik (hit_points == 2) tugla renkleri - bilerek FARKLI bir ton
## ailesi (bronz/amber). Oyuncu kac temas gerektigini denemeden, tek bakista
## renkten anlar. Renk tek basina birakilmaz: _build_armor_marks() ayrica
## cift kenar centigi de cizer, boylece renk ayrimini goremeyen oyuncular
## icin de bilgi kaybolmaz.
@export var strong_surface_color := Palette.SURFACE_BLOCK_STRONG
@export var strong_edge_color := Palette.SURFACE_BLOCK_STRONG_EDGE
@export var strong_seam_color := Palette.SURFACE_BLOCK_STRONG_SEAM
## Panellerin yuvarlak stadyumuna karsilik blok bilerek kose hatlidir.
@export var corner_radius := 6.0
@export var outline_width := 2.6
@export_range(0.0, 1.0, 0.01) var seam_alpha := 0.55

@export_group("Kirilma Efekti")
## Toplam efekt suresi. Kisa tutulur: bu bir patlama degil, kisa bir onay.
@export_range(0.12, 0.20, 0.01) var break_time := 0.18
@export var punch_scale := 1.14
@export_range(3, 6, 1) var shard_count := 4
@export var shard_travel := 34.0

@onready var _shape: CollisionShape2D = $Shape
@onready var _visual: Node2D = $Visual

var _broken := false
var _remaining_hits := 1
var _last_hit_physics_frame := -1
var _damage_tween: Tween
## 0 -> 1 arasi kirilma ilerlemesi; parcalar bununla cizilir.
var _shatter := 0.0:
	set(value):
		_shatter = value
		queue_redraw()


func _ready() -> void:
	# Parcalar _draw() ile bu dugumun uzerinde cizilir; govde sonene kadar
	# onu ortmemeleri icin gorsel katman ebeveynin ARKASINA alinir.
	# (z_index yerine bu bayrak: kardes bloklarin siralamasini etkilemez.)
	_visual.show_behind_parent = true
	_remaining_hits = hit_points
	_rebuild()


func is_broken() -> bool:
	return _broken


func get_remaining_hits() -> int:
	return _remaining_hits


func get_max_hits() -> int:
	return hit_points


## Bir fizik karesinde yalnizca bir hasar kabul eder. Bu, ayni temas icin
## move_and_collide alt adimlarindan gelebilecek cift bildirimi engeller;
## top daha sonra geri donerse yeni karede yeniden hasar verebilir.
func take_hit() -> bool:
	if _broken:
		return false
	var physics_frame := Engine.get_physics_frames()
	if physics_frame == _last_hit_physics_frame:
		return false
	_last_hit_physics_frame = physics_frame
	_remaining_hits = maxi(_remaining_hits - 1, 0)
	if _remaining_hits == 0:
		shatter()
		return true
	damaged.emit(global_position, _remaining_hits, hit_points)
	_rebuild()
	_play_damage_effect()
	return false


## Topun temasiyla cagrilir. Idempotenttir: ayni blok icin ikinci cagri
## hicbir sey yapmaz, boylece ayni atista iki kez ses/efekt uretilmez.
func shatter() -> void:
	if _broken:
		return
	_broken = true
	_remaining_hits = 0
	if _damage_tween != null and _damage_tween.is_valid():
		_damage_tween.kill()
	_disable_collision()
	broken.emit(global_position)
	_play_break_effect()


## Fizik geri cagrisinin (Ball._physics_process -> move_and_collide) ICINDEN
## cagriliyoruz; carpisma durumunu o an degistirmek guvenli degildir. Godot
## bu iki degisikligi fizik adimi bittikten sonra uygular, yani top ayni
## karede blogu hala kati gorur (gercek sekmeyi zaten yapti) ve BIR SONRAKI
## kareden itibaren blok tamamen yok olur.
func _disable_collision() -> void:
	set_deferred("collision_layer", 0)
	_shape.set_deferred("disabled", true)


func _rebuild() -> void:
	_apply_shape()
	_build_visual()


func _apply_shape() -> void:
	# Her blok kendi sekline sahip olsun (sahne alt kaynagi paylasilmasin).
	var rect := RectangleShape2D.new()
	rect.size = block_size
	_shape.shape = rect


## Bu tuglanin renk seti - dayanikliligina gore secilir (bkz. strong_* exportlari).
func get_body_color() -> Color:
	return strong_surface_color if hit_points > 1 else surface_color


func get_rim_color() -> Color:
	return strong_edge_color if hit_points > 1 else edge_color


func get_seam_color() -> Color:
	return strong_seam_color if hit_points > 1 else seam_color


func _build_visual() -> void:
	_visual.scale = Vector2.ONE
	_visual.modulate = Color.WHITE
	for child in _visual.get_children():
		child.queue_free()

	var body := ShapeBuilder.rounded_rect(block_size, corner_radius, 3)
	_visual.add_child(ShapeBuilder.make_polygon(body, get_body_color()))
	_visual.add_child(ShapeBuilder.make_outline(body, get_rim_color(), outline_width))
	_build_seam()
	if hit_points > 1:
		_build_armor_marks()
	if _remaining_hits < hit_points:
		_build_cracks()


## Merkezdeki dikis: govdeyi ikiye bolen ince bir cizgi ve iki ucundaki kisa
## centikler. "Bu yuzey tek parca degil" bilgisini neon kullanmadan verir.
func _build_seam() -> void:
	var half := block_size * 0.5
	var inset := minf(half.y * 0.42, 8.0)
	var color := Color(get_seam_color(), seam_alpha)

	var seam := Line2D.new()
	seam.points = PackedVector2Array([
		Vector2(0.0, -half.y + inset),
		Vector2(0.0, half.y - inset),
	])
	seam.default_color = color
	seam.width = 2.0
	seam.antialiased = true
	_visual.add_child(seam)

	# Ust ve alt kenardaki kisa centikler - dikisin kenara ciktigi yer.
	for direction in [-1.0, 1.0]:
		var notch := Line2D.new()
		notch.points = PackedVector2Array([
			Vector2(-inset * 0.7, direction * half.y),
			Vector2(inset * 0.7, direction * half.y),
		])
		notch.default_color = color
		notch.width = 2.0
		notch.antialiased = true
		_visual.add_child(notch)


## Iki canli tuglayi normal tugladan ilk bakista ayiran cift kenar isareti.
func _build_armor_marks() -> void:
	var half := block_size * 0.5
	var color := Color(get_rim_color(), 0.72)
	for side in [-1.0, 1.0]:
		var mark := Line2D.new()
		mark.points = PackedVector2Array([
			Vector2(side * (half.x - 18.0), -half.y + 7.0),
			Vector2(side * (half.x - 18.0), half.y - 7.0),
		])
		mark.default_color = color
		mark.width = 3.0
		mark.begin_cap_mode = Line2D.LINE_CAP_ROUND
		mark.end_cap_mode = Line2D.LINE_CAP_ROUND
		mark.antialiased = true
		_visual.add_child(mark)


## Ilk darbeden sonra kalan kalici catlak. Yeni partikule gerek kalmadan
## oyuncuya "bir temas daha" bilgisini verir.
func _build_cracks() -> void:
	var crack := Line2D.new()
	var half_y := block_size.y * 0.5
	crack.points = PackedVector2Array([
		Vector2(-18.0, -half_y + 5.0), Vector2(-7.0, -6.0),
		Vector2(-14.0, 2.0), Vector2(3.0, 9.0),
		Vector2(12.0, half_y - 5.0),
	])
	crack.default_color = Color(Palette.TEXT, 0.82)
	crack.width = 2.8
	crack.joint_mode = Line2D.LINE_JOINT_ROUND
	crack.antialiased = true
	_visual.add_child(crack)


func _play_damage_effect() -> void:
	if _damage_tween != null and _damage_tween.is_valid():
		_damage_tween.kill()
	_damage_tween = create_tween()
	_damage_tween.tween_property(_visual, "scale", Vector2.ONE * 1.07, 0.05) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_damage_tween.tween_property(_visual, "scale", Vector2.ONE, 0.11) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Kisa scale punch + fade. Efekt bitince blok kendini agactan siler; kirilmis
## blok node'u ortalikta birakilmaz (bkz. BreakableField.get_remaining_count).
func _play_break_effect() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_visual, "scale", Vector2.ONE * punch_scale, break_time * 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual, "scale", Vector2.ONE * 0.82, break_time * 0.7) \
		.set_delay(break_time * 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "modulate:a", 0.0, break_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_method(_set_shatter, 0.0, 1.0, break_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(queue_free)


func _set_shatter(value: float) -> void:
	_shatter = value


## Govde uzun ekseni boyunca esit parcalara ayrilir ve parcalar disari savrulur.
## Rastgelelik yoktur - ayni atis ayni goruntuyu uretir (bkz. SparkBurst).
func _draw() -> void:
	if _shatter <= 0.0 or _shatter >= 1.0:
		return

	var fade := 1.0 - _shatter
	var alpha := fade * fade
	if alpha <= 0.01:
		return

	var half := block_size * 0.5
	var slice_width := block_size.x / float(shard_count)
	var shard_half := Vector2(slice_width * 0.40, half.y * 0.72)
	var body_color := Color(get_body_color(), alpha)
	var rim_color := Color(get_rim_color(), alpha * 0.9)

	for i in shard_count:
		var center_x := -half.x + slice_width * (float(i) + 0.5)
		# Merkezden uzaklastikca daha genis aciyla, hepsi hafifce yukari.
		var direction := Vector2(center_x / maxf(half.x, 1.0), -0.5).normalized()
		var spin := (1.0 if i % 2 == 0 else -1.0) * 0.55 * _shatter
		draw_set_transform(
			Vector2(center_x, 0.0) + direction * shard_travel * _shatter,
			spin,
			Vector2.ONE * lerpf(1.0, 0.5, _shatter))
		var rect := Rect2(-shard_half, shard_half * 2.0)
		draw_rect(rect, body_color)
		draw_rect(rect, rim_color, false, 1.6)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
