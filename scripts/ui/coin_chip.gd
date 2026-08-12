class_name CoinChip
extends Button

## Paylasilan Coin bakiye rozeti (pill).
##
## Oncesinde gameplay HUD'undaki CoinChip ile magazadaki BalanceChip birbirinin
## neredeyse birebir kopyasi iki ayri sahne agaciydi, renkleri Palette.COIN'i
## OKUMUYOR, ona denk gelen sabit Color(...) degerleri tekrar yaziyordu (bir
## .tscn sub_resource calisma zamaninda static var okuyamaz). Bu bilesen
## Ev'de (yeni) ve Magaza basliginda (BalanceChip'in yerine) kullanilir.
##
## Gameplay HUD'undaki CoinChip bu bilesene TASINMADI - kapsam disinda (Faz 9
## yalnizca Ev/Magaza/Ayarlar'i kapsiyor) ve o dugum yolu ipucu-ekonomisi
## testleriyle es baglidir; ayri bir temizlik olarak birakildi.
##
## [member tappable] true ise (Ev ekraninda) dokununca kendi "pressed"
## sinyalini yayar - cagiran bunu VAR OLAN shop_requested sinyaline baglar,
## yeni bir AppRoot kancasi gerekmez.

@export var tappable := false

var wallet: WalletStore

var _value: Label
var _row: HBoxContainer
## Button.get_minimum_size() bilerek kucuk metin/ikondan hesaplanir ve elle
## eklenen COCUK dugumleri (Row) HESABA KATMAZ - Button bir Container degildir.
## CoinChip yan yana baska kardeşlerle bir HBoxContainer icinde durdugunda
## (Ev/Magaza basligi) bu, ebeveynin CoinChip'e gercek icerikten cok daha dar
## bir alan ayirmasina ve Row'un komsu dugumlerin uzerine taşmasina yol acar.
##
## custom_minimum_size DOGRUDAN ATANIR - _get_minimum_size() override'i
## denendi ve GridContainer/HBoxContainer tarafindan guvenilir sekilde
## okunmadigi gorüldu (bkz. product_card.gd'deki ayni donus). Bakiye basamak
## sayisi degisebildigi icin bu deger refresh()'te YENIDEN hesaplanir.
const _PAD := Vector2(44.0, 28.0)


func _ready() -> void:
	flat = true
	text = ""
	focus_mode = Control.FOCUS_CLICK if tappable else Control.FOCUS_NONE
	if not tappable:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	else:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.INK_MID, 0.74)
	style.border_color = Color(Palette.COIN, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(UIMetrics.RADIUS_PILL)
	style.corner_detail = 8
	style.anti_aliasing = true
	style.content_margin_left = 18.0
	style.content_margin_right = 20.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	# Rozet HER durumda ayni gorunmeli: bu bir eylem butonu degil, bir
	# bilgi rozetidir (magazadaki hali hic tiklanamaz).
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, style)

	custom_minimum_size = Vector2(0.0, UIMetrics.MIN_TOUCH)

	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", UIMetrics.SPACE_SM)
	_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_row)

	var glyph := GlyphIcon.new()
	glyph.name = "Glyph"
	glyph.glyph = GlyphIcon.Glyph.COIN
	glyph.color = Palette.COIN
	glyph.stroke_width = 2.6
	glyph.custom_minimum_size = Vector2(26.0, 26.0)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(glyph)

	_value = Label.new()
	_value.name = "Value"
	_value.add_theme_font_size_override("font_size", UIMetrics.FONT_BODY + 6)
	_value.add_theme_color_override("font_color", Palette.COIN_CORE)
	_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_value)

	if wallet != null:
		refresh()


func bind(new_wallet: WalletStore) -> void:
	wallet = new_wallet
	refresh()


func refresh() -> void:
	if wallet == null or _value == null:
		return
	_value.text = str(wallet.balance)
	var content_size := _row.get_combined_minimum_size() + _PAD
	custom_minimum_size = Vector2(content_size.x, maxf(UIMetrics.MIN_TOUCH, content_size.y))
