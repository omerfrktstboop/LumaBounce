class_name BreakableBlockData
extends Resource

## Tek bir kirilabilir blogun veri tanimi.
##
## breakable_block.tscn ornegi bu degerlerle kurulur; gorsel ve kirilma
## davranisi BreakableBlock'a aittir, burada yalnizca yerlesim tutulur.
## PanelData ile ayni sozlesme: veri saf yerlesim ve dayaniklilik ayaridir,
## davranis BreakableBlock'ta kalir.

@export var position := Vector2.ZERO
@export var rotation_degrees := 0.0
@export var size := Vector2(160.0, 44.0)
## 1 normal tugla, 2 ilk darbede catlayip ikinci temasta kirilan kilit tugla.
@export_range(1, 2, 1) var hit_points := 1


## Sorun bulunmazsa bos dizi doner.
func validate(index: int) -> PackedStringArray:
	var problems := PackedStringArray()
	if size.x <= 0.0 or size.y <= 0.0:
		problems.append("blok %d: size pozitif olmali (%s)" % [index, size])
	if hit_points < 1 or hit_points > 2:
		problems.append("blok %d: hit_points 1-2 araliginda olmali (%d)" % [
			index, hit_points])
	return problems
