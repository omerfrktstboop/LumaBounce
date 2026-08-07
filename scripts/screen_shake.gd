class_name ScreenShake
extends Camera2D

## Kontrollu, kisa ekran titresimi.
##
## Klasik "trauma" modeli kullanilir: add_trauma() ile 0..1 araliginda bir
## sarsinti puani eklenir, her karede decay ile azalir ve ofset trauma^2 ile
## olceklenir (yumusak baslayip hizli sonlanan bir his verir). max_offset
## kucuk tutuldugu surece "yogun kamera sarsintisi" olusmaz.
##
## Bu kamera SADECE oyun dunyasini (Node2D agacini) sarsar; HUD ayri bir
## CanvasLayer'da oldugu icin hic etkilenmez.

@export var max_offset := 14.0
@export var decay_per_second := 3.2

## Oyuncunun ayarlardan sectigi sarsinti carpani (0.0 = kapali, 1.0 = normal).
##
## Haptics.enabled ile AYNI desen ve ayni sebep: sarsinti alti ayri yerden
## tetikleniyor (sekme, blok kirma, hedef, tehlike...). Ayari her cagri
## yerinde carpmaya kalkarsak biri mutlaka unutulur ve tercih sessizce
## sizar. Tek kisma noktasi burasi; AppRoot ProgressStore'dan doldurur.
static var trauma_scale := 1.0

var _trauma := 0.0


func _ready() -> void:
	make_current()


func _process(delta: float) -> void:
	if _trauma <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return

	_trauma = maxf(_trauma - decay_per_second * delta, 0.0)
	var amount := _trauma * _trauma
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * max_offset * amount


## [param amount] 0..1 araliginda eklenecek sarsinti siddeti. Oyuncunun
## ayari burada uygulanir, cagiran yerlerde degil (bkz. trauma_scale).
func add_trauma(amount: float) -> void:
	if trauma_scale <= 0.0:
		return
	_trauma = clampf(_trauma + amount * trauma_scale, 0.0, 1.0)
