class_name ProductCard
extends Button

## Magaza urun karti: dikey duzen (onizleme ustte, isim, fiyat/durum altta),
## 2 sutunlu GridContainer'a sigacak sekilde. shop_screen.gd::_make_card'in
## eski yatay-satir halinin yerini alir; satin alma/secim MANTIGI degismedi
## (WalletStore cagrilari hala shop_screen.gd::_on_purchase_pressed/
## _on_select_pressed icinde), yalnizca gorunum.
##
## [method configure] bir kart ORNEGI icin YALNIZCA BIR KEZ cagrilir - shop
## ekrani her degisiklikte (satin alma, sekme degisimi) TUM kartlari yeniden
## kurar (mevcut _rebuild deseniyle ayni), bu yuzden burada onceki
## baglantilari sokme ihtiyaci yok.

signal purchase_requested(item: CosmeticData)
signal select_requested(item: CosmeticData)

## Urunun KENDISI kartin ana bilgisidir; 92 birimde kozmetikler kartin
## icinde kaybolup adlarindan ayirt edilemiyordu. CosmeticPreview her seyi
## min(size)/2 uzerinden olcekledigi icin tek sabit dort turu de (top, iz,
## firlatici, efekt) ayni bounding box mantiginda birlikte buyutur.
const PREVIEW_SIZE := 108.0
const CARD_WIDTH := 180.0
## Onizleme +16 birim buyudu; kartin da ~ayni kadar buyumesi gerekiyor,
## yoksa ad/fiyat satirlari sikisir. Genislik DEGISMEDI - 2 sutunlu izgara
## duzeni genislige bagli, yukseklige degil.
const CARD_HEIGHT := 240.0


func configure(item: CosmeticData, owned: bool, selected: bool, affordable: bool) -> void:
	name = "Card_%s" % item.id
	focus_mode = Control.FOCUS_NONE
	# custom_minimum_size KULLANILIR, _get_minimum_size() override'i DEGIL:
	# ProductCard 2 sutunlu bir GridContainer'da durur ve GridContainer
	# hucre boyutunu buradan okur. shop_screen.gd::_make_remove_ads_card
	# gibi eski Button+manuel-cocuk kartlari her zaman custom_minimum_size
	# kullanmisti; ayni desen burada da guvenilir sonuc verdi.
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text = ""
	disabled = selected or (not owned and not affordable)

	var accent := item.accent
	add_theme_stylebox_override("normal", LumaCard.style(accent, selected, 2))
	add_theme_stylebox_override("hover", LumaCard.style(accent, true, 2))
	add_theme_stylebox_override("pressed", LumaCard.style(accent, true, 3))
	add_theme_stylebox_override("disabled", LumaCard.style(accent, selected, 2))

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, UIMetrics.SPACE_MD)
	add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", UIMetrics.SPACE_SM)
	margin.add_child(column)

	var preview_row := CenterContainer.new()
	preview_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(preview_row)
	var preview := CosmeticPreview.new()
	preview.item = item
	preview.custom_minimum_size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_row.add_child(preview)

	var name_label := Label.new()
	name_label.text = item.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", UIMetrics.FONT_CARD_TITLE + 2)
	name_label.add_theme_color_override("font_color", Palette.TEXT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	column.add_child(_make_status_row(item, owned, selected, affordable))

	if selected:
		var badge := GlyphIcon.new()
		badge.name = "SelectedBadge"
		badge.glyph = GlyphIcon.Glyph.CHECK
		badge.color = accent
		badge.stroke_width = 3.0
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -30.0
		badge.offset_top = 10.0
		badge.offset_right = -10.0
		badge.offset_bottom = 30.0
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(badge)
	elif owned:
		pressed.connect(select_requested.emit.bind(item))
	elif affordable:
		pressed.connect(purchase_requested.emit.bind(item))


func _make_status_row(item: CosmeticData, owned: bool, selected: bool,
		affordable: bool) -> Control:
	var box := HBoxContainer.new()
	box.name = "Status"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", UIMetrics.FONT_SUPPORTING + 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if selected:
		label.text = tr("SEÇİLİ")
		label.add_theme_color_override("font_color", item.accent)
		box.add_child(label)
		return box
	if owned:
		label.text = tr("SAHİP")
		label.add_theme_color_override("font_color", Palette.TEXT_DIM)
		box.add_child(label)
		return box

	label.text = str(item.price)
	var tone := Palette.COIN if affordable else Color(Palette.TEXT_DIM, 0.65)
	label.add_theme_color_override("font_color", tone)
	var coin := GlyphIcon.new()
	coin.glyph = GlyphIcon.Glyph.COIN
	coin.color = tone
	coin.stroke_width = 2.4
	coin.custom_minimum_size = Vector2(22.0, 22.0)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	box.add_child(coin)
	return box
