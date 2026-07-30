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


## [param amount] 0..1 araliginda eklenecek sarsinti siddeti.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)
