class_name Target
extends Area2D

## Ekranin ustundeki parlayan kare hedef.
##
## Gorsel dil: top DOLU bir kure, hedef ise ICI BOS neon bir kare.
## Ikisi ayni vurgu rengini paylasir ama silueti farklidir; oyuncu
## bir bakista hangisinin ne oldugunu ayirt eder.
##
## KIMLIK: karenin ortasinda yavasca nefes alan iki tonlu bir KRISTAL durur.
## Isabette kristal parlayip buyur, kare ikincil vurguyla DOLAR ve oyle kalir
## ("yanan" hedef); disa isinlar ve iki halka acilir. Sonuc karti acilana
## kadar ekranda kalan bu dolu hal, "vurdun" bilgisini sesten bagimsiz verir.
##
## Fiziksel carpisma yapmaz; sadece "ball" grubundaki cismi algilar ve
## [signal hit] yayar. Durdurma karari gameplay.gd'ye aittir.

signal hit(body: Node2D)

@export var size := 92.0
@export var corner_radius := 20.0

@export_group("Gorunum")
@export var accent := Palette.ACCENT
@export var core_color := Palette.ACCENT_CORE
## Isabet ve basari icin ikincil vurgu.
@export var success_color := Palette.ACCENT_ALT
@export var outline_width := 3.5
## Buton degil, havada duran net bir hedef hissi icin hale kucuk ve yumusak tutulur.
@export var glow_scale := 1.6

@export_group("Animasyon")
@export var idle_scale := 1.045
@export var idle_time := 2.2
@export var hit_scale := 1.45
@export var hit_time := 0.45
## Acilmadan ONCE cok kisa bir sikisma (anticipation). Oncesinde hedef
## dogrudan buyumeye gidiyordu ve temas ani "yumusak" okunuyordu; kucuk bir
## on-sikisma darbeyi tok hissettirir. Sure bilerek ~1 goz kirpmasi altinda:
## uzatildiginda isabet "gecikmis" gibi gorunuyor.
@export var hit_compress_scale := 0.92
@export var hit_compress_time := 0.065
@export var ring_scale := 2.8
@export var ring_time := 0.55
## Ikinci (vurgu renkli) halkanin gecikmesi: tek halka "bir dalga", ikisi
## art arda "patlama" okunur.
@export var second_ring_delay := 0.12
## Kristalin bostaki nefes periyodu (sn). Hale nabzindan bilerek farkli: ikisi
## ayni anda atarsa hedef tek parca "zonkluyor" gibi gorunuyor.
@export var crystal_breath_time := 1.6
## Isabetten sonra karenin dolgu opakligi ("yanik" hal).
@export_range(0.0, 1.0, 0.01) var lit_fill_alpha := 0.34

@onready var _shape: CollisionShape2D = $Shape
@onready var _visual: Node2D = $Visual

var _glow_group: Node2D
var _core: Node2D
var _lit_fill: Polygon2D
var _ring: Line2D
var _ring_second: Line2D
var _rays: Node2D
var _idle_tween: Tween
var _crystal_tween: Tween
var _hit_tween: Tween
var _ignite_tween: Tween
var _ring_tween: Tween
var _already_hit := false


func _ready() -> void:
	_apply_shape()
	_build_visual()
	body_entered.connect(_on_body_entered)
	_start_idle_pulse()


# --- Dis API -----------------------------------------------------------------

func reset() -> void:
	_already_hit = false
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	if _ring_tween != null and _ring_tween.is_valid():
		_ring_tween.kill()
	if _ignite_tween != null and _ignite_tween.is_valid():
		_ignite_tween.kill()
	_visual.scale = Vector2.ONE
	_visual.modulate = Color.WHITE
	_glow_group.scale = Vector2.ONE
	_ring.scale = Vector2.ONE
	_ring.modulate.a = 0.0
	_ring_second.scale = Vector2.ONE
	_ring_second.modulate.a = 0.0
	_rays.scale = Vector2.ONE
	_rays.modulate.a = 0.0
	_lit_fill.modulate.a = 0.0
	_core.modulate = Color.WHITE
	_core.scale = Vector2.ONE
	_start_idle_pulse()


## Temiz kazanma efekti: kisa buyume + parlama + disa acilan menekse halka.
func play_hit_effect() -> void:
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	if _crystal_tween != null and _crystal_tween.is_valid():
		_crystal_tween.kill()
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	_visual.scale = Vector2.ONE
	_visual.modulate = Color.WHITE

	# Sira: kisa sikisma -> hizli acilma (+ parlama) -> yerine oturma.
	_hit_tween = create_tween()
	_hit_tween.tween_property(_visual, "scale", Vector2.ONE * hit_compress_scale,
		hit_compress_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hit_tween.tween_property(_visual, "scale", Vector2.ONE * hit_scale, hit_time * 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hit_tween.parallel().tween_property(
		_visual, "modulate", Color(1.55, 1.5, 1.5, 1.0), hit_time * 0.2)
	_hit_tween.chain().tween_property(_visual, "scale", Vector2.ONE * 1.1, hit_time * 0.65) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hit_tween.parallel().tween_property(_visual, "modulate", Color.WHITE, hit_time * 0.65)

	_ignite()
	_play_ring()


## "Yanma": kristal beyaza parlayip buyur ve ikincil vurguda kalir, kare dolar.
## Hepsi kalici - sifirlama reset()'te.
func _ignite() -> void:
	_core.scale = Vector2.ONE
	_core.modulate = Color(2.2, 2.2, 2.2, 1.0)
	_lit_fill.modulate.a = 0.0
	_rays.scale = Vector2.ONE * 0.55
	_rays.modulate.a = 1.0
	if _ignite_tween != null and _ignite_tween.is_valid():
		_ignite_tween.kill()
	_ignite_tween = create_tween().set_parallel(true)
	var ignite := _ignite_tween
	ignite.tween_property(_core, "scale", Vector2.ONE * 1.9, hit_time * 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ignite.tween_property(_core, "scale", Vector2.ONE * 1.35, hit_time * 0.7) \
		.set_delay(hit_time * 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ignite.tween_property(_core, "modulate", Color(success_color.lightened(0.45), 1.0),
		hit_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ignite.tween_property(_lit_fill, "modulate:a", 1.0, hit_time * 0.4)
	ignite.tween_property(_rays, "scale", Vector2.ONE * 1.6, ring_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ignite.tween_property(_rays, "modulate:a", 0.0, ring_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# --- Ic isleyis --------------------------------------------------------------

func _on_body_entered(body: Node2D) -> void:
	if _already_hit or not body.is_in_group("ball"):
		return
	_already_hit = true
	play_hit_effect()
	hit.emit(body)


func _apply_shape() -> void:
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size, size)
	_shape.shape = rect


func _build_visual() -> void:
	for child in _visual.get_children():
		child.queue_free()

	# 1) Kontrollu dis hale (nabiz gibi yavasca atar).
	_glow_group = Node2D.new()
	_glow_group.name = "Glow"
	_visual.add_child(_glow_group)
	_glow_group.add_child(_make_square(glow_scale, Color(accent, 0.03)))
	_glow_group.add_child(_make_square(glow_scale * 0.76, Color(accent, 0.05)))
	_glow_group.add_child(_make_square(glow_scale * 0.58, Color(accent, 0.085)))

	# 2) Buzlu cam dolgusu + net neon kontur.
	_visual.add_child(_make_square(1.0, Color(accent, 0.14)))
	_visual.add_child(ShapeBuilder.make_outline(
		ShapeBuilder.rounded_rect(Vector2.ONE * size, corner_radius, 7),
		accent, outline_width))

	# 3) "Yanik" dolgu (isabete kadar gorunmez).
	_lit_fill = _make_square(0.94, Color(success_color, lit_fill_alpha))
	_lit_fill.name = "LitFill"
	_lit_fill.modulate.a = 0.0
	_visual.add_child(_lit_fill)

	# 4) Merkezdeki kristal: "tam burasi" isareti ve hedefin kimligi.
	_core = _make_crystal(size * 0.15)
	_visual.add_child(_core)

	# 5) Isabet isinlari (normalde gorunmez).
	_rays = _make_rays(8, size * 0.62, size * 0.98)
	_rays.modulate.a = 0.0
	_visual.add_child(_rays)

	# 6) Isabet halkalari (normalde gorunmez): once menekse, sonra vurgu.
	_ring = ShapeBuilder.make_outline(
		ShapeBuilder.rounded_rect(Vector2.ONE * size, corner_radius, 7),
		success_color, outline_width)
	_ring.modulate.a = 0.0
	_visual.add_child(_ring)
	_ring_second = ShapeBuilder.make_outline(
		ShapeBuilder.rounded_rect(Vector2.ONE * size, corner_radius, 7),
		accent, outline_width * 0.8)
	_ring_second.modulate.a = 0.0
	_visual.add_child(_ring_second)


## Iki tonlu eskenar dortgen: aydinlik yuz (cekirdek rengi) + golgeli yuz
## (vurgu) + ince parlama cizgisi. 4 noktali iki ucgen; maliyeti bir kareyle ayni.
func _make_crystal(half_width: float) -> Node2D:
	var crystal := Node2D.new()
	crystal.name = "Crystal"
	var h := half_width * 1.3
	var top := Vector2(0.0, -h)
	var bottom := Vector2(0.0, h)
	var left := Vector2(-half_width, 0.0)
	var right := Vector2(half_width, 0.0)
	crystal.add_child(ShapeBuilder.make_polygon(
		PackedVector2Array([top, right, bottom, left]), Color(core_color, 0.95)))
	crystal.add_child(ShapeBuilder.make_polygon(
		PackedVector2Array([top, bottom, left]), Color(accent, 0.55)))
	var glint := Line2D.new()
	glint.points = PackedVector2Array([top * 0.62 + right * 0.18, right * 0.55])
	glint.width = 2.0
	glint.default_color = Color(1.0, 1.0, 1.0, 0.85)
	glint.begin_cap_mode = Line2D.LINE_CAP_ROUND
	glint.end_cap_mode = Line2D.LINE_CAP_ROUND
	crystal.add_child(glint)
	return crystal


func _make_rays(count: int, inner: float, outer: float) -> Node2D:
	var rays := Node2D.new()
	rays.name = "Rays"
	for i in count:
		var direction := Vector2.RIGHT.rotated(TAU * float(i) / float(count) + PI / float(count))
		var ray := Line2D.new()
		ray.points = PackedVector2Array([direction * inner, direction * outer])
		ray.width = 3.0
		ray.default_color = Color(success_color.lightened(0.35), 0.9)
		ray.begin_cap_mode = Line2D.LINE_CAP_ROUND
		ray.end_cap_mode = Line2D.LINE_CAP_ROUND
		rays.add_child(ray)
	return rays


func _make_square(scale_factor: float, color: Color) -> Polygon2D:
	return ShapeBuilder.make_polygon(
		ShapeBuilder.rounded_rect(
			Vector2.ONE * size * scale_factor, corner_radius * scale_factor, 7),
		color)


func _start_idle_pulse() -> void:
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_property(_glow_group, "scale", Vector2.ONE * idle_scale, idle_time * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(_glow_group, "scale", Vector2.ONE, idle_time * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if _crystal_tween != null and _crystal_tween.is_valid():
		_crystal_tween.kill()
	_crystal_tween = create_tween().set_loops()
	_crystal_tween.tween_property(_core, "scale", Vector2.ONE * 1.08, crystal_breath_time * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_crystal_tween.tween_property(_core, "scale", Vector2.ONE * 0.94, crystal_breath_time * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _play_ring() -> void:
	if _ring_tween != null and _ring_tween.is_valid():
		_ring_tween.kill()
	_ring.scale = Vector2.ONE
	_ring.modulate.a = 0.85
	_ring_tween = create_tween()
	_ring_tween.set_parallel(true)
	_ring_tween.tween_property(_ring, "scale", Vector2.ONE * ring_scale, ring_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_ring_tween.tween_property(_ring, "modulate:a", 0.0, ring_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_ring_second.scale = Vector2.ONE
	_ring_second.modulate.a = 0.0
	_ring_tween.tween_property(_ring_second, "modulate:a", 0.7, 0.01) \
		.set_delay(second_ring_delay)
	_ring_tween.tween_property(_ring_second, "scale", Vector2.ONE * ring_scale * 1.25,
		ring_time).set_delay(second_ring_delay) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_ring_tween.tween_property(_ring_second, "modulate:a", 0.0, ring_time) \
		.set_delay(second_ring_delay + 0.01).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
