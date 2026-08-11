class_name GlyphIcon
extends Control

## Prosedurel UI ikonlari. Harici asset yok; hepsi Control'un boyutuna gore
## _draw() ile cizilir.

enum Glyph {
	SOUND_ON,
	SOUND_OFF,
	SETTINGS,
	HOME,
	CHECK,
	RESTART,
	LOCK,
	COIN,
	HINT,
	PAUSE,
}

@export var glyph: Glyph = Glyph.SETTINGS:
	set(value):
		glyph = value
		queue_redraw()
@export var color := Palette.TEXT_DIM:
	set(value):
		color = value
		queue_redraw()
@export var stroke_width := 2.8


func _draw() -> void:
	var center := size * 0.5
	var unit := minf(size.x, size.y) * 0.5
	if unit <= 0.0:
		return

	match glyph:
		Glyph.SOUND_ON:
			_draw_speaker(center, unit, true)
		Glyph.SOUND_OFF:
			_draw_speaker(center, unit, false)
		Glyph.SETTINGS:
			_draw_gear(center, unit)
		Glyph.HOME:
			_draw_home(center, unit)
		Glyph.RESTART:
			_draw_restart(center, unit)
		Glyph.CHECK:
			_draw_check(center, unit)
		Glyph.LOCK:
			_draw_lock(center, unit)
		Glyph.COIN:
			_draw_coin(center, unit)
		Glyph.HINT:
			_draw_hint(center, unit)
		Glyph.PAUSE:
			_draw_pause(center, unit)


func _draw_speaker(center: Vector2, unit: float, sound_on: bool) -> void:
	var body := PackedVector2Array([
		center + Vector2(-unit * 0.78, -unit * 0.26),
		center + Vector2(-unit * 0.34, -unit * 0.26),
		center + Vector2(unit * 0.06, -unit * 0.68),
		center + Vector2(unit * 0.06, unit * 0.68),
		center + Vector2(-unit * 0.34, unit * 0.26),
		center + Vector2(-unit * 0.78, unit * 0.26),
	])
	draw_colored_polygon(body, color)

	if sound_on:
		var arc_center := center + Vector2(unit * 0.1, 0.0)
		draw_arc(arc_center, unit * 0.44, -PI * 0.42, PI * 0.42, 16, color, stroke_width, true)
		draw_arc(arc_center, unit * 0.74, -PI * 0.40, PI * 0.40, 20, color, stroke_width, true)
		return

	# Kapali: kucuk bir carpi.
	var a := center + Vector2(unit * 0.34, -unit * 0.30)
	var b := center + Vector2(unit * 0.82, unit * 0.30)
	draw_line(a, b, color, stroke_width, true)
	draw_line(Vector2(a.x, b.y), Vector2(b.x, a.y), color, stroke_width, true)


## Luma Coin: madeni para halkasi + icinde "L" monogrami.
##
## Neden monogram: onceki hali ic ice iki halkaydi ve JETON degil "hedef/kayit"
## simgesi gibi okunuyordu - ustelik oyunun hedefi ve topu da ic ice
## dairelerden olustugu icin HUD'da onlarla karisiyordu. Monogram hem para
## oldugunu hem HANGI para oldugunu bir bakista soyluyor.
func _draw_coin(center: Vector2, unit: float) -> void:
	draw_arc(center, unit * 0.84, 0.0, TAU, 32, color, stroke_width, true)
	# "L": dikey govde + saga kisa taban.
	var top := center + Vector2(-unit * 0.16, -unit * 0.40)
	var bottom := center + Vector2(-unit * 0.16, unit * 0.34)
	draw_line(top, bottom, color, stroke_width * 1.15, true)
	draw_line(bottom, bottom + Vector2(unit * 0.44, 0.0), color, stroke_width * 1.15, true)


## Duraklat: iki dikey cubuk. Ucgen "oynat" simgesiyle karismasin diye
## bilerek kalin ve kisa - kucuk boyutta ince cubuklar tek bir cizgi gibi
## okunuyordu.
func _draw_pause(center: Vector2, unit: float) -> void:
	var bar := Vector2(unit * 0.30, unit * 1.30)
	var gap := unit * 0.26
	for side in [-1.0, 1.0]:
		var at := center + Vector2((gap + bar.x * 0.5) * side, 0.0)
		draw_rect(Rect2(at - bar * 0.5, bar), color)


## Ipucu: ampul govdesi + taban cizgileri. Yolu degil FIKRI temsil eder;
## rota zaten HintPath ile arenada cizilir.
func _draw_hint(center: Vector2, unit: float) -> void:
	var bulb := center + Vector2(0.0, -unit * 0.18)
	draw_arc(bulb, unit * 0.52, PI * 0.08, PI * 0.92 + PI, 26, color, stroke_width, true)
	# Ampulun boynu: govdenin iki ucundan tabana inen kisa cizgiler.
	var left := bulb + Vector2(-unit * 0.30, unit * 0.42)
	var right := bulb + Vector2(unit * 0.30, unit * 0.42)
	draw_line(left, left + Vector2(0.0, unit * 0.20), color, stroke_width, true)
	draw_line(right, right + Vector2(0.0, unit * 0.20), color, stroke_width, true)
	# Iki taban cizgisi (vida disi).
	for i in 2:
		var y := unit * (0.62 + float(i) * 0.24)
		draw_line(bulb + Vector2(-unit * 0.28, y), bulb + Vector2(unit * 0.28, y),
			color, stroke_width * 0.9, true)


func _draw_home(center: Vector2, unit: float) -> void:
	# Cati: tek parca ucgen.
	var roof := PackedVector2Array([
		center + Vector2(0.0, -unit * 0.78),
		center + Vector2(unit * 0.84, -unit * 0.02),
		center + Vector2(-unit * 0.84, -unit * 0.02),
	])
	draw_colored_polygon(roof, color)

	# Govde: ince konturlu kutu.
	var half := unit * 0.5
	var top := -unit * 0.02
	var bottom := unit * 0.72
	var box := PackedVector2Array([
		center + Vector2(-half, top),
		center + Vector2(half, top),
		center + Vector2(half, bottom),
		center + Vector2(-half, bottom),
		center + Vector2(-half, top),
	])
	draw_polyline(box, color, stroke_width, true)


## Donen tek ok: "yeniden baslat". HUD'daki home ve restart butonlarinin ayni
## ikon ve stil kaynagini paylasmasi icin buraya tasindi - boylece ikisi
## tanim geregi ayni gorsel agirliga sahip.
func _draw_restart(center: Vector2, unit: float) -> void:
	var radius := unit * 0.62
	var start_rad := deg_to_rad(-35.0)
	var end_rad := deg_to_rad(225.0)
	draw_arc(center, radius, start_rad, end_rad, 24, color, stroke_width, true)

	# Yayin bittigi noktada, tesetten (tangent) yonlu kucuk bir ok ucu.
	var arrow := unit * 0.28
	var tip := center + Vector2(cos(end_rad), sin(end_rad)) * radius
	var tangent := Vector2(-sin(end_rad), cos(end_rad))
	var outward := Vector2(cos(end_rad), sin(end_rad))
	draw_polygon(PackedVector2Array([
		tip + tangent * arrow - outward * arrow * 0.35,
		tip - tangent * arrow - outward * arrow * 0.35,
		tip + outward * arrow * 0.85,
	]), PackedColorArray([color]))


func _draw_check(center: Vector2, unit: float) -> void:
	var points := PackedVector2Array([
		center + Vector2(-unit * 0.62, unit * 0.02),
		center + Vector2(-unit * 0.16, unit * 0.48),
		center + Vector2(unit * 0.64, -unit * 0.46),
	])
	draw_polyline(points, color, stroke_width, true)


## Kilit: dolu govde + uzerinde yarim halka aski. Bolum secim ekranindaki
## kilitli butonlar bunu kullanir; "kapali" bilgisi yalnizca solgunlukla
## degil, bir isaretle de verilsin.
func _draw_lock(center: Vector2, unit: float) -> void:
	var body_top := center.y - unit * 0.22
	draw_arc(
		Vector2(center.x, body_top), unit * 0.40, PI, TAU, 16, color, stroke_width, true)
	draw_rect(
		Rect2(Vector2(center.x - unit * 0.62, body_top), Vector2(unit * 1.24, unit * 0.84)),
		color)


func _draw_gear(center: Vector2, unit: float) -> void:
	var ring_radius := unit * 0.46
	draw_arc(center, ring_radius, 0.0, TAU, 28, color, stroke_width, true)

	var teeth := 8
	for i in teeth:
		var angle := TAU * float(i) / float(teeth)
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(
			center + direction * (ring_radius + stroke_width * 0.5),
			center + direction * (unit * 0.88),
			color, stroke_width, true)
