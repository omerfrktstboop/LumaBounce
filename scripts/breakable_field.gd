class_name BreakableField
extends Node2D

## Aktif bolumun kirilabilir bloklarini tutan kucuk sorumluluk sinifi.
##
## Var olma nedeni tek bir kural: oyunun IKI farkli sifirlamasi vardir ve
## bloklar bunlarin yalnizca birinden etkilenir.
##
##   ATIS SIFIRLAMA  (top kaybedildi / hizli yeniden nisan ile iptal edildi)
##     -> bu sinifa HIC dokunulmaz, kirilan bloklar kirik kalir.
##        Blok kirmak bolum cozumunun ilerlemesidir; geri alinmaz.
##
##   BOLUM YENIDEN BASLATMA  (TEKRAR BASLA / debug restart / bolume yeniden giris)
##     -> build() yeniden cagrilir, tum bloklar bastan olusturulur.
##
## Kirilan blok kendi kisa efektini oynatip agactan silinir, bu yuzden burada
## bir havuz veya "kirik" listesi tutulmaz - canli cocuklar tek gercektir.

## Bir blok kirildi (aynı blok icin yalnizca bir kez).
signal block_broken(at: Vector2)
signal block_damaged(at: Vector2, remaining_hits: int, maximum_hits: int)

@export var block_scene: PackedScene

## build() ile kurulan blok sayisi; kirilanlar bu sayidan dusulmez.
var _total := 0


## Bolumun bloklarini bastan kurar. Cagrildigi her yer bir BOLUM YENIDEN
## BASLATMA'dir; atis sifirlamasi buraya asla ugramaz.
func build(blocks: Array[BreakableBlockData]) -> void:
	clear()
	if blocks.is_empty():
		return
	if block_scene == null:
		push_error("BreakableField: block_scene atanmamis, bloklar olusturulamiyor.")
		return

	for data in blocks:
		if data == null:
			continue
		var block := block_scene.instantiate() as BreakableBlock
		if block == null:
			push_error("BreakableField: block_scene bir BreakableBlock degil.")
			return
		block.position = data.position
		block.rotation_degrees = data.rotation_degrees
		block.block_size = data.size
		block.hit_points = data.hit_points
		block.broken.connect(_on_block_broken)
		block.damaged.connect(_on_block_damaged)
		add_child(block)
		_total += 1


## remove_child sart: yalnizca queue_free eski bloklari kare sonuna kadar
## fizik dunyasinda birakir ve yeni denemede hayalet carpisma yaratirdi
## (bkz. Arena.rebuild - ayni tuzak).
func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_total = 0


func shatter_in_radius(center: Vector2, radius: float) -> void:
	var r2 := radius * radius
	for child in get_children():
		var block := child as BreakableBlock
		if block != null and not block.is_broken():
			if block.global_position.distance_squared_to(center) <= r2:
				block.shatter()


func get_total_count() -> int:
	return _total


func get_remaining_count() -> int:
	var remaining := 0
	for child in get_children():
		var block := child as BreakableBlock
		if block != null and not block.is_broken():
			remaining += 1
	return remaining


func get_broken_count() -> int:
	return _total - get_remaining_count()


func _on_block_broken(at: Vector2) -> void:
	block_broken.emit(at)


func _on_block_damaged(at: Vector2, remaining_hits: int, maximum_hits: int) -> void:
	block_damaged.emit(at, remaining_hits, maximum_hits)
