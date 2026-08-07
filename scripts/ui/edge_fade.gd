class_name EdgeFade
extends Control

## Kaydirilan bir listenin ust/alt kenarindaki SERT KIRPMAYI yumusatir.
##
## Neden var: bolum listesi basligin altindan gecerken satirlar ortadan
## ikiye bolunuyordu ve "buraya kadar" hissi vermek yerine bozuk gorunuyordu.
##
## Shader kullanilmaz - proje genelinde oldugu gibi prosedurel cizim:
## draw_polygon kose basina renk kabul ettigi icin dikey bir gradyan tek
## cagriyla cizilebiliyor.

## Solma rengi. Zeminle AYNI olmali, yoksa gecis bir seritmis gibi okunur.
@export var color := Palette.INK_TOP:
	set(value):
		color = value
		queue_redraw()
## true: ustte opak baslar, asagi dogru seffaflasir (basligin altina giren
## icerik icin). false: tersi.
@export var opaque_at_top := true:
	set(value):
		opaque_at_top = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var solid := Color(color, 1.0)
	var clear := Color(color, 0.0)
	var top := solid if opaque_at_top else clear
	var bottom := clear if opaque_at_top else solid
	draw_polygon(
		PackedVector2Array([
			Vector2.ZERO, Vector2(size.x, 0.0),
			Vector2(size.x, size.y), Vector2(0.0, size.y),
		]),
		PackedColorArray([top, top, bottom, bottom]))
