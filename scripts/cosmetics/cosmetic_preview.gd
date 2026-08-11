class_name CosmeticPreview
extends Control

## Magaza kartindaki kucuk onizleme. Harici gorsel YOK - her tur kendi
## bilesenini temsil eden basit bir cizimle gosterilir, aynen oyunun geri
## kalaninda oldugu gibi (bkz. ShapeBuilder, GlyphIcon).
##
## Onizleme GERCEK bileseni ornegini kurmaz: bir Ball/Launcher dugumu fizik
## govdesi ve sinyaller getirir, magaza kartinda bunlarin isi yok. Burada
## yalnizca esyanin RENK KIMLIGI gosterilir - oyuncunun karsilastirdigi sey
## zaten renk ve bicim.

@export var item: CosmeticData:
	set(value):
		item = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if item == null:
		return
	var center := size * 0.5
	var unit := minf(size.x, size.y) * 0.5
	if unit <= 0.0:
		return
	match item.kind:
		CosmeticData.Kind.BALL:
			_draw_ball(center, unit)
		CosmeticData.Kind.TRAIL:
			_draw_trail(center, unit)
		CosmeticData.Kind.LAUNCHER:
			_draw_launcher(center, unit)
		CosmeticData.Kind.TARGET_FX:
			_draw_target(center, unit)


func _draw_ball(center: Vector2, unit: float) -> void:
	draw_circle(center, unit * 0.86, Color(item.accent, 0.20))
	draw_circle(center, unit * 0.58, item.accent)
	draw_circle(center, unit * 0.26, item.core)


## Iz: sagdan sola incelen bir kuyruk + ucunda top. Uzunluk ve genislik
## carpanlari GERCEK degerlerdir, yani kart oyundaki farki gosterir.
func _draw_trail(center: Vector2, unit: float) -> void:
	var length := unit * 1.7 * clampf(item.trail_length_scale, 0.5, 1.9) / 1.9
	var width := unit * 0.44 * clampf(item.trail_width_scale, 0.4, 1.4)
	var steps := 9
	for i in steps:
		var t := float(i) / float(steps - 1)
		var at := center + Vector2(lerpf(-length, unit * 0.55, t), 0.0)
		draw_circle(at, lerpf(width * 0.18, width, t), Color(item.accent, lerpf(0.05, 0.55, t)))
	draw_circle(center + Vector2(unit * 0.55, 0.0), width * 0.9, item.accent)
	draw_circle(center + Vector2(unit * 0.55, 0.0), width * 0.4, item.core)


func _draw_launcher(center: Vector2, unit: float) -> void:
	var base := center + Vector2(0.0, unit * 0.44)
	draw_rect(Rect2(base - Vector2(unit * 0.72, unit * 0.20),
		Vector2(unit * 1.44, unit * 0.40)), Palette.SURFACE_EDGE)
	draw_rect(Rect2(center - Vector2(unit * 0.16, unit * 0.72),
		Vector2(unit * 0.32, unit * 1.10)), item.accent)
	draw_circle(center + Vector2(0.0, -unit * 0.66), unit * 0.30, item.core)


func _draw_target(center: Vector2, unit: float) -> void:
	var glow := unit * 0.90 * (item.glow_scale if item.glow_scale > 0.0 else 1.0)
	draw_circle(center, minf(glow, unit), Color(item.accent, 0.16))
	var half := unit * 0.52
	draw_rect(Rect2(center - Vector2(half, half), Vector2(half * 2.0, half * 2.0)),
		item.accent, false, 3.0)
	draw_circle(center, unit * 0.20, item.core)
	# Basari rengi kucuk bir kivilcim olarak: hedef efektinin ikinci rengi
	# yalnizca vurus aninda goruldugu icin kartta ayrica temsil edilmeli.
	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25
		var from := center + Vector2.RIGHT.rotated(angle) * unit * 0.62
		draw_line(from, from + Vector2.RIGHT.rotated(angle) * unit * 0.24,
			item.alt, 2.6, true)
