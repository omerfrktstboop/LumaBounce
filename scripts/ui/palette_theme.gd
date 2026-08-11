class_name PaletteTheme
extends Resource

## Palette icin degistirilebilir renk seti - bkz. Palette.apply_theme().
## Alan adlari Palette'in static var listesiyle BIREBIR ayni olmali; yeni
## bir tema eklerken oradaki alan listesini buraya da yansitin.

@export var INK_TOP := Color("17233a")
@export var INK_MID := Color("1e2d46")
@export var INK_BOTTOM := Color("22324d")

@export var SURFACE := Color("2b3c5b")
@export var SURFACE_EDGE := Color("3a4f76")
@export var SURFACE_LIGHT := Color("4d6595")
@export var FRAME := Color("31446a")
@export var SURFACE_PANEL := Color("40506b")

@export var SURFACE_BLOCK := Color("32405c")
@export var SURFACE_BLOCK_EDGE := Color("6d86b6")
@export var SURFACE_BLOCK_SEAM := Color("8ba3ce")

@export var SURFACE_BLOCK_STRONG := Color("5c4630")
@export var SURFACE_BLOCK_STRONG_EDGE := Color("d19a5e")
@export var SURFACE_BLOCK_STRONG_SEAM := Color("e8bd88")

@export var ACCENT := Color("34e6d4")
@export var ACCENT_DIM := Color("1ba99d")
@export var ACCENT_CORE := Color("ecfffc")

@export var ACCENT_ALT := Color("c07dff")
@export var ACCENT_ALT_CORE := Color("f6ecff")

## Para birimi - hicbir tema bunu EZMEZ (bkz. palette.gd).
@export var COIN := Color("ffc861")
@export var COIN_CORE := Color("fff1d2")

@export var HAZARD := Color("ff667d")
@export var HAZARD_DARK := Color("63364a")
@export var HAZARD_CORE := Color("ffe2e7")

@export var TEXT := Color("e9f2ff")
@export var TEXT_DIM := Color("93a7c9")
