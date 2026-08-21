class_name SparkBurst
extends Node2D

## Kisa, kontrollu carpisma kivilcimi. Kendi kendini siler.
##
## Yonleri deterministik olarak (normal etrafinda esit araliklarla) secer;
## rastgelelik yoktur, boylece ayni atis ayni gorseli uretir.

## Temas geri bildirimi bilerek KISA: 0.26 sn'de kivilcimlar topun kendisinden
## daha uzun sure ekranda kaliyordu ve hizli sekmelerde birbirine binerek
## gorusu bulandiriyordu. 0.18 sn "tok" bir temas birakip hemen cekiliyor.
const LIFETIME := 0.18

var _normal := Vector2.UP
var _strength := 1.0
var _color := Palette.ACCENT
var _core_color := Palette.ACCENT_CORE
var _count := 5
var _length := 24.0
var _spread := 64.0

var _progress := 0.0:
	set(value):
		_progress = value
		queue_redraw()


## Verilen noktada bir kivilcim patlamasi olusturur.
static func burst(
		parent: Node,
		at: Vector2,
		normal: Vector2,
		strength: float,
		color: Color = Palette.ACCENT,
		core_color: Color = Palette.ACCENT_CORE,
		count: int = 5,
		length: float = 24.0,
		spread_deg: float = 64.0) -> void:
	var node := SparkBurst.new()
	node.name = "SparkBurst"
	node.position = at
	node._normal = normal if not normal.is_zero_approx() else Vector2.UP
	node._strength = clampf(strength, 0.3, 1.0)
	node._color = color
	node._core_color = core_color
	node._count = maxi(count, 2)
	node._length = length
	node._spread = spread_deg
	parent.add_child(node)
	node._play()


func _play() -> void:
	var tween := create_tween()
	tween.tween_property(self, "_progress", 1.0, LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(queue_free)


func _draw() -> void:
	var fade := 1.0 - _progress
	var alpha := fade * fade * _strength
	if alpha <= 0.01:
		return

	var reach := _length * _strength
	var base_angle := _normal.angle()
	var spread := deg_to_rad(_spread)
	var inner := reach * (0.20 + 0.80 * _progress)
	var outer := inner + reach * 0.5 * fade
	var line_color := Color(_color, alpha * 0.9)
	var line_width := 1.6 + 1.6 * _strength

	for i in _count:
		var offset := (float(i) / float(_count - 1)) * 2.0 - 1.0
		var direction := Vector2.RIGHT.rotated(base_angle + offset * spread * 0.5)
		draw_line(direction * inner, direction * outer, line_color, line_width, true)

	# Carpma anindaki kisa parlama.
	draw_circle(Vector2.ZERO, reach * 0.32 * fade, Color(_core_color, alpha * 0.5))

	# Ince temas halkasi: kivilcim cizgileri "hangi yone" savruldugunu
	# anlatir, halka ise "tam nerede" degdigini tek okunakli sekille verir.
	# Tek draw_arc oldugu icin maliyeti ihmal edilebilir; kalinlik ve alfa
	# bilerek dusuk tutulur - amac vurgu eklemek degil, temasi netlestirmek.
	var ring_alpha := alpha * 0.40
	if ring_alpha > 0.01:
		draw_arc(Vector2.ZERO, reach * (0.35 + 0.95 * _progress), 0.0, TAU, 20,
			Color(_core_color, ring_alpha), 1.4, true)
