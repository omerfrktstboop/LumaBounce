class_name PanelData
extends Resource

## Tek bir sekme panelinin veri tanimi.
##
## bounce_panel.tscn ornegi bu degerlerle kurulur; gorsel ve fizik
## davranisi BouncePanel'e aittir, burada yalnizca yerlesim tutulur.

@export var position := Vector2.ZERO
@export var rotation_degrees := 0.0
@export var length := 220.0
@export var thickness := 24.0


## Sorun bulunmazsa bos dizi doner.
func validate(index: int) -> PackedStringArray:
	var problems := PackedStringArray()
	if length <= 0.0:
		problems.append("panel %d: length pozitif olmali (%s)" % [index, length])
	if thickness <= 0.0:
		problems.append("panel %d: thickness pozitif olmali (%s)" % [index, thickness])
	return problems
