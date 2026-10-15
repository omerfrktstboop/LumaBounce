class_name WorldMotif
extends Control

## Her dunyanin arka plan motifi: zemin gradyaninin USTUNDE, oyun alaninin
## ALTINDA cok soluk bir desen.
##   Dunya 1: yildiz alani (yavasca yanip sonen noktalar)
##   Dunya 2: ufuk izgarasi (asagi akan perspektif zemin)
##   Dunya 3: aurora (suzulen iki-uc isik seridi)
##   Dunya 4: prizma kirintilari (yavas donen renkli kesikler)
## Amac dunyalari birbirinden ayirmak ve sahneye derinlik katmak. Alfa bilerek
## cok dusuk: "tek vurgu" kurali - top, nisan ve hedef her zaman one cikmali.
##
## Hafif parallax: [member parallax_source] (top) ekranda ilerledikce desen ters
## yone birkac piksel kayar; yakin katmanlar (buyuk yildiz, buyuk kirinti) daha
## cok kayar. Yalnizca cizim: fizik, carpisma ve atis determinizmi etkilenmez;
## yerlesim kendi RandomNumberGenerator'u ile sabit tohumdan uretilir.

enum Motif { STARS, GRID, AURORA, PRISM }

const STAR_COUNT := 64
const SHARD_COUNT := 13

@export var motif := Motif.STARS
## Topun ekran merkezinden her piksel uzakligi icin desen kaymasi (ters yon).
@export var parallax_strength := 0.02
## Desenin genel opaklik carpani (ayar yuzeyi; 0 kapatir).
@export_range(0.0, 2.0, 0.05) var intensity := 1.0

var parallax_source: Node2D

var _accent := Palette.ACCENT
var _accent_alt := Palette.ACCENT_ALT
var _time := 0.0
var _offset := Vector2.ZERO
## [konum (0..1), yaricap, faz, hiz]
var _stars: Array[Array] = []
## [konum (0..1), boyut, aci, donus hizi, renk, kenar sayisi]
var _shards: Array[Array] = []


static func motif_for_world(index: int) -> Motif:
	match index:
		1:
			return Motif.GRID
		2:
			return Motif.AURORA
		3:
			return Motif.PRISM
		_:
			return Motif.STARS


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Tema AppRoot tarafindan sahne kurulduktan SONRA uygulanir (bkz.
	# InkBackground.follow_palette); renkler burada tazelenir.
	_accent = Palette.ACCENT
	_accent_alt = Palette.ACCENT_ALT
	_build_layout()


func _process(delta: float) -> void:
	_time += delta
	var wanted := Vector2.ZERO
	if parallax_source != null and is_instance_valid(parallax_source):
		wanted = -(parallax_source.global_position - size * 0.5) * parallax_strength
	_offset = _offset.lerp(wanted, 1.0 - exp(-3.0 * delta))
	queue_redraw()


func _build_layout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7151 + int(motif) * 97
	_stars.clear()
	for i in STAR_COUNT:
		_stars.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(1.0, 2.8),
			rng.randf_range(0.0, TAU), rng.randf_range(0.35, 1.1)])
	_shards.clear()
	for i in SHARD_COUNT:
		var hue := fposmod(float(i) / float(SHARD_COUNT) + rng.randf_range(-0.04, 0.04), 1.0)
		_shards.append([Vector2(rng.randf(), rng.randf_range(0.05, 0.9)),
			rng.randf_range(16.0, 48.0), rng.randf_range(0.0, TAU),
			rng.randf_range(-0.12, 0.12), Color.from_hsv(hue, 0.45, 1.0),
			3 if i % 3 == 0 else 4])


func _draw() -> void:
	if intensity <= 0.0:
		return
	match motif:
		Motif.STARS:
			_draw_stars()
		Motif.GRID:
			_draw_grid()
		Motif.AURORA:
			_draw_aurora()
		Motif.PRISM:
			_draw_prism()


func _draw_stars() -> void:
	for star in _stars:
		var radius: float = star[1]
		var twinkle := 0.5 + 0.5 * sin(_time * float(star[3]) + float(star[2]))
		var alpha := (0.10 + 0.26 * twinkle) * intensity
		# Buyuk yildiz "yakin": parallax'ta daha cok kayar.
		var pos: Vector2 = star[0]
		var at := pos * size + _offset * (radius / 2.8)
		draw_circle(at, radius, Color(Palette.TEXT, alpha))
		if radius > 2.0:
			draw_circle(at, radius * 3.0, Color(_accent, alpha * 0.18))


func _draw_grid() -> void:
	var horizon := size.y * 0.58 + _offset.y * 0.3
	var center_x := size.x * 0.5 + _offset.x * 0.3
	var line := Color(_accent, 0.10 * intensity)
	# Ufukta keskin bir cizgi YOK, yalnizca yumusak bir isik bandi: tam
	# genislikte net bir yatay cizgi oyun alaninda bariyer/lazer gibi okunurdu.
	for band in 4:
		var h := 10.0 + 12.0 * float(band)
		draw_rect(Rect2(0.0, horizon - h, size.x, h * 2.0), Color(_accent, 0.012 * intensity))
	# Kacis noktasina yakinsayan dikey cizgiler.
	for i in range(-9, 10):
		var bottom_x := center_x + float(i) * size.x * 0.16
		draw_line(Vector2(center_x + float(i) * 18.0, horizon), Vector2(bottom_x, size.y), line, 1.2)
	# Asagi akan yatay cizgiler (perspektif: ufka yaklastikca sik).
	var depth := size.y - horizon
	var scroll := fposmod(_time * 0.12, 1.0)
	for i in 9:
		var t := (float(i) + scroll) / 9.0
		var y := horizon + depth * t * t
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(_accent, 0.10 * intensity * t), 1.2)


func _draw_aurora() -> void:
	var colors: Array[Color] = [_accent, _accent_alt, _accent.lerp(_accent_alt, 0.5)]
	for k in 3:
		var base_y := size.y * (0.16 + 0.11 * float(k)) + _offset.y * (0.5 + 0.25 * float(k))
		var top := PackedVector2Array()
		var bottom := PackedVector2Array()
		var x := -40.0
		while x <= size.x + 40.0:
			var px := x + _offset.x * (0.5 + 0.25 * float(k))
			var wave := sin(x * 0.006 + _time * 0.22 + float(k) * 1.7) * 46.0 \
				+ sin(x * 0.014 - _time * 0.15 + float(k)) * 18.0
			var thickness := 70.0 + 40.0 * sin(x * 0.009 + _time * 0.18 + float(k) * 2.3)
			top.append(Vector2(px, base_y + wave))
			bottom.append(Vector2(px, base_y + wave + thickness))
			x += 36.0
		bottom.reverse()
		var ribbon := top + bottom
		draw_colored_polygon(ribbon, Color(colors[k], 0.06 * intensity))
		draw_polyline(top, Color(colors[k], 0.09 * intensity), 1.5, true)


func _draw_prism() -> void:
	for shard in _shards:
		var shard_size: float = shard[1]
		var angle: float = float(shard[2]) + _time * float(shard[3])
		var pos: Vector2 = shard[0]
		var at := pos * size + _offset * (shard_size / 48.0)
		var sides: int = shard[5]
		var points := PackedVector2Array()
		for s in sides:
			var a := angle + TAU * float(s) / float(sides)
			# Dortgenler ince eskenar dortgen (kristal kesigi), ucgenler duzgun.
			var r := shard_size * (1.0 if sides == 3 or s % 2 == 0 else 0.45)
			points.append(at + Vector2(cos(a), sin(a)) * r)
		var color: Color = shard[4]
		draw_colored_polygon(points, Color(color, 0.03 * intensity))
		var loop := points.duplicate()
		loop.append(points[0])
		draw_polyline(loop, Color(color, 0.09 * intensity), 1.2, true)
