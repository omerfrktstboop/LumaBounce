class_name BreakableBlockData
extends Resource

## Tek bir kirilabilir blogun veri tanimi.
##
## breakable_block.tscn ornegi bu degerlerle kurulur; gorsel ve kirilma
## davranisi BreakableBlock'a aittir, burada yalnizca yerlesim tutulur.
## PanelData ile ayni sozlesme: veri saf yerlesimdir, davranis tasimaz.
##
## Bilerek dayaniklilik/HP alani YOKTUR - ilk surumde her blok TEK vurusta
## kirilir (bkz. BreakableBlock).

@export var position := Vector2.ZERO
@export var rotation_degrees := 0.0
@export var size := Vector2(160.0, 44.0)


## Sorun bulunmazsa bos dizi doner.
func validate(index: int) -> PackedStringArray:
	var problems := PackedStringArray()
	if size.x <= 0.0 or size.y <= 0.0:
		problems.append("blok %d: size pozitif olmali (%s)" % [index, size])
	return problems
