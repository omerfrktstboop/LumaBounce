class_name BreakableBlock
extends StaticBody2D

## Topun TEK vurusta kirdigi engel.
##
## Bu bir brick-breaker tuglasi DEGILDIR: puan vermez, kirilmasi zorunlu
## degildir. Islevi rotayi acmak ve sekme geometrisini degistirmektir.
## Bu yuzden dayaniklilik/HP alani bilerek yoktur.
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

@export var block_size := Vector2(160.0, 44.0):
	set(value):
		block_size = Vector2(maxf(value.x, 8.0), maxf(value.y, 8.0))
		if is_node_ready():
			_rebuild()

@export_group("Gorunum")
@export var surface_color := Palette.SURFACE_BLOCK
@export var edge_color := Palette.SURFACE_BLOCK_EDGE
@export var seam_color := Palette.SURFACE_BLOCK_SEAM
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
	_rebuild()


func is_broken() -> bool:
	return _broken


## Topun temasiyla cagrilir. Idempotenttir: ayni blok icin ikinci cagri
## hicbir sey yapmaz, boylece ayni atista iki kez ses/efekt uretilmez.
func shatter() -> void:
	if _broken:
		return
	_broken = true
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


func _build_visual() -> void:
	for child in _visual.get_children():
		child.queue_free()

	var body := ShapeBuilder.rounded_rect(block_size, corner_radius, 3)
	_visual.add_child(ShapeBuilder.make_polygon(body, surface_color))
	_visual.add_child(ShapeBuilder.make_outline(body, edge_color, outline_width))
	_build_seam()


## Merkezdeki dikis: govdeyi ikiye bolen ince bir cizgi ve iki ucundaki kisa
## centikler. "Bu yuzey tek parca degil" bilgisini neon kullanmadan verir.
func _build_seam() -> void:
	var half := block_size * 0.5
	var inset := minf(half.y * 0.42, 8.0)
	var color := Color(seam_color, seam_alpha)

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
	var body_color := Color(surface_color, alpha)
	var rim_color := Color(edge_color, alpha * 0.9)

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
