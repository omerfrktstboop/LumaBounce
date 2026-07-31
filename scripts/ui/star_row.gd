class_name StarRow
extends Control

## Prosedurel 1-3 yildiz gostergesi.
##
## Harici asset yok; yildizlar _draw() ile cizilir. Renk mevcut gorsel dile
## uyar: dolu yildiz cyan vurgu, bos yildiz mat surface tonu. Bilerek altin/
## sari kullanilmaz - "tek vurgu" kuralinda cyan zaten basari rengidir.

@export var star_count := 3:
	set(value):
		star_count = maxi(value, 1)
		_refresh_minimum_size()
		queue_redraw()
@export var star_radius := 17.0:
	set(value):
		star_radius = maxf(value, 4.0)
		_refresh_minimum_size()
		queue_redraw()
@export var spacing := 12.0:
	set(value):
		spacing = maxf(value, 0.0)
		_refresh_minimum_size()
		queue_redraw()

@export_group("Renkler")
@export var filled_color := Palette.ACCENT
@export var filled_core_color := Palette.ACCENT_CORE
@export var empty_color := Color(Palette.SURFACE_LIGHT, 0.35)
@export var outline_color := Color(Palette.SURFACE_EDGE, 0.9)
@export var outline_width := 2.0

@export_group("Animasyon")
@export var pop_time := 0.26
@export var pop_stagger := 0.10
@export var pop_scale := 1.35

## Kac yildiz dolu.
var _filled := 0
## Her yildizin anlik olcegi; reveal animasyonu bunlari oynatir.
var _scales: PackedFloat32Array = PackedFloat32Array()
var _reveal_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_minimum_size()


## Yildizlari animasyonsuz gosterir (bolum secim ekrani, tekrar acilan panel).
func set_stars(filled: int) -> void:
	_kill_reveal()
	_filled = clampi(filled, 0, star_count)
	_reset_scales(1.0)
	queue_redraw()


## Yeni kisisel rekorda kisa, sirali bir pop. Abartili partikul yok - sadece
## her yildiz sirayla bir kez buyuyup yerine oturur.
func play_reveal(filled: int) -> void:
	_kill_reveal()
	_filled = clampi(filled, 0, star_count)
	if _filled <= 0:
		_reset_scales(1.0)
		queue_redraw()
		return

	_reset_scales(1.0)
	for i in _filled:
		_scales[i] = 0.0
	queue_redraw()

	_reveal_tween = create_tween()
	_reveal_tween.set_parallel(true)
	for i in _filled:
		var index := i
		var start := float(index) * pop_stagger
		_reveal_tween.tween_method(
				_set_star_scale.bind(index), 0.0, pop_scale, pop_time * 0.55) \
			.set_delay(start).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_reveal_tween.tween_method(
				_set_star_scale.bind(index), pop_scale, 1.0, pop_time * 0.45) \
			.set_delay(start + pop_time * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _set_star_scale(index: int, value: float) -> void:
	if index < 0 or index >= _scales.size():
		return
	_scales[index] = value
	queue_redraw()


func _reset_scales(value: float) -> void:
	_scales.resize(star_count)
	for i in star_count:
		_scales[i] = value


func _kill_reveal() -> void:
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()


func _refresh_minimum_size() -> void:
	var width := star_count * star_radius * 2.0 + maxi(star_count - 1, 0) * spacing
	custom_minimum_size = Vector2(width, star_radius * 2.0 + 4.0)


func _draw() -> void:
	if _scales.size() != star_count:
		_reset_scales(1.0)

	var step := star_radius * 2.0 + spacing
	var total := star_count * star_radius * 2.0 + maxi(star_count - 1, 0) * spacing
	var start_x := (size.x - total) * 0.5 + star_radius
	var center_y := size.y * 0.5

	for i in star_count:
		var center := Vector2(start_x + step * float(i), center_y)
		var scale_factor: float = _scales[i]
		if scale_factor <= 0.001:
			# Henuz belirmemis dolu yildizin yerini bos yildiz tutar.
			_draw_star(center, star_radius, empty_color, true)
			continue
		if i < _filled:
			_draw_star(center, star_radius * scale_factor, filled_color, false)
			_draw_star(center, star_radius * scale_factor * 0.42, filled_core_color, false)
		else:
			_draw_star(center, star_radius, empty_color, true)


## Bes koseli yildiz: dis ve ic yaricap arasinda donusumlu 10 nokta.
func _draw_star(center: Vector2, radius: float, color: Color, outlined: bool) -> void:
	var points := PackedVector2Array()
	var inner := radius * 0.45
	for i in 10:
		var angle := -PI * 0.5 + PI * float(i) / 5.0
		var r := radius if i % 2 == 0 else inner
		points.append(center + Vector2(cos(angle), sin(angle)) * r)

	draw_colored_polygon(points, color)
	if outlined:
		var loop := points.duplicate()
		loop.append(points[0])
		draw_polyline(loop, outline_color, outline_width, true)
