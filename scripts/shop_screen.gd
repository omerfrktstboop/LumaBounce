class_name ShopScreen
extends Control

## Luma Coin magazasi: kozmetik satin alma ve secme.
##
## Diger ekranlarla ayni kural: KENDISI hicbir sahne acmaz, yalnizca sinyal
## yayar; cuzdan AppRoot tarafindan add_child'dan ONCE enjekte edilir.
##
## Kartlar kod ile uretilir (ayarlar ekranindaki desen): satin alma ya da
## secim sonrasi hem fiyat/durum etiketi hem SECILI isareti degisir; tek bir
## _rebuild ikisini de tutarli tutar.
##
## FIYAT BURADA YAZILI DEGIL - CosmeticData'dan okunur. Denge degisikligi
## katalogda yapilir ve bu dosya hic degismez.

signal menu_requested()

## AppRoot tarafindan add_child'dan ONCE atanir.
var wallet: WalletStore
var purchase_service: PurchaseService

const CARD_HEIGHT := 96.0
const PREVIEW_SIZE := 56.0

@onready var _rows: VBoxContainer = $SafeArea/Content/Scroll/Rows
@onready var _balance_value: Label = $SafeArea/Content/BalanceChip/Row/Value
@onready var _back_button: LumaButton = $SafeArea/Content/BackButton

var _flash_tween: Tween
var _iap_message := ""


func _ready() -> void:
	if wallet == null:
		wallet = WalletStore.load_from_disk()
	_back_button.pressed.connect(menu_requested.emit)
	if purchase_service != null:
		purchase_service.state_changed.connect(_on_purchase_state_changed)
	_rebuild()


func _rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()

	_balance_value.text = str(wallet.balance)
	if purchase_service != null:
		_rows.add_child(_make_section(tr("PREMİUM")))
		_rows.add_child(_make_remove_ads_card())
		_rows.add_child(_make_restore_purchases_button())
	for kind in CosmeticCatalog.KIND_ORDER:
		_rows.add_child(_make_section(CosmeticCatalog.kind_label(kind)))
		for item in CosmeticCatalog.by_kind(kind):
			_rows.add_child(_make_card(item))


func _make_section(title: String) -> Label:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 21)
	label.add_theme_color_override("font_color", Palette.ACCENT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size = Vector2(0.0, 44.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return label


## Kart uc durumdan birini gosterir:
##   satin alinabilir -> fiyat
##   sahip ama secili degil -> "SAHİP" (dokununca secilir)
##   secili -> "SEÇİLİ" (dokunulamaz, zaten aktif)
func _make_card(item: CosmeticData) -> Button:
	var owned := wallet.owns(item.id)
	var selected := wallet.selected_cosmetic_id(item.kind) == item.id
	var affordable := owned or wallet.can_afford(item.price)

	var card := Button.new()
	card.name = "Card_%s" % item.id
	card.custom_minimum_size = Vector2(0.0, CARD_HEIGHT)
	card.focus_mode = Control.FOCUS_NONE
	card.disabled = selected or (not owned and not affordable)
	var accent := item.accent
	card.add_theme_stylebox_override("normal", _card_style(accent, selected, 2))
	card.add_theme_stylebox_override("hover", _card_style(accent, true, 2))
	card.add_theme_stylebox_override("pressed", _card_style(accent, true, 3))
	card.add_theme_stylebox_override("disabled", _card_style(accent, selected, 2))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	card.add_child(margin)

	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 14)
	margin.add_child(line)

	var preview := CosmeticPreview.new()
	preview.name = "Preview"
	preview.item = item
	preview.custom_minimum_size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(preview)

	var name_label := Label.new()
	name_label.text = item.display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.add_theme_font_size_override("font_size", 23)
	name_label.add_theme_color_override("font_color", Palette.TEXT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name_label)

	line.add_child(_make_status(item, owned, selected, affordable))

	if selected:
		pass
	elif owned:
		card.pressed.connect(_on_select_pressed.bind(item))
	elif affordable:
		card.pressed.connect(_on_purchase_pressed.bind(item))
	return card


func _make_remove_ads_card() -> Button:
	var active := purchase_service.is_remove_ads_active()
	var ready := purchase_service.is_product_ready(MonetizationConfig.PRODUCT_REMOVE_ADS)
	var busy := purchase_service.is_busy()

	var card := Button.new()
	card.name = "RemoveAdsCard"
	card.custom_minimum_size = Vector2(0.0, 112.0)
	card.focus_mode = Control.FOCUS_NONE
	card.disabled = active or busy or not ready
	card.add_theme_stylebox_override("normal", _card_style(Palette.ACCENT, active, 2))
	card.add_theme_stylebox_override("hover", _card_style(Palette.ACCENT, true, 2))
	card.add_theme_stylebox_override("pressed", _card_style(Palette.ACCENT, true, 3))
	card.add_theme_stylebox_override("disabled", _card_style(Palette.ACCENT, active, 2))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)

	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 14)
	margin.add_child(line)

	var icon := GlyphIcon.new()
	icon.glyph = GlyphIcon.Glyph.CHECK if active else GlyphIcon.Glyph.LOCK
	icon.color = Palette.ACCENT
	icon.stroke_width = 3.0
	icon.custom_minimum_size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(icon)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_theme_constant_override("separation", 3)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(texts)

	var title := Label.new()
	title.text = tr("REKLAMLARI KALDIR")
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Palette.TEXT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(title)

	var description := Label.new()
	description.text = tr("Geçiş reklamlarını kalıcı olarak kapatır")
	description.add_theme_font_size_override("font_size", 16)
	description.add_theme_color_override("font_color", Palette.TEXT_DIM)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(description)

	var status := Label.new()
	status.text = _remove_ads_status(active, ready, busy)
	status.add_theme_font_size_override("font_size", 19)
	status.add_theme_color_override(
		"font_color", Palette.ACCENT if active else Palette.COIN)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(status)

	if not card.disabled:
		card.pressed.connect(_on_remove_ads_pressed)
	return card


func _remove_ads_status(active: bool, ready: bool, busy: bool) -> String:
	if active:
		return tr("AKTİF")
	if busy:
		return tr("İŞLENİYOR...")
	if not _iap_message.is_empty():
		return tr(_iap_message)
	if ready:
		var price := purchase_service.formatted_price(MonetizationConfig.PRODUCT_REMOVE_ADS)
		return price if not price.is_empty() else tr("SATIN AL")
	return tr("PLAY STORE'A BAĞLANILIYOR")


func _make_restore_purchases_button() -> Button:
	var button := LumaButton.new()
	button.name = "RestorePurchasesButton"
	button.text = tr("SATIN ALMALARI GERİ YÜKLE")
	button.corner_radius = 18
	button.custom_minimum_size = Vector2(0.0, 52.0)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = purchase_service.is_busy() or not purchase_service.is_available()
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(_on_restore_purchases_pressed)
	return button


func _make_status(item: CosmeticData, owned: bool, selected: bool,
		affordable: bool) -> Control:
	var box := HBoxContainer.new()
	box.name = "Status"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.name = "Label"
	label.add_theme_font_size_override("font_size", 20)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	if selected:
		label.text = tr("SEÇİLİ")
		label.add_theme_color_override("font_color", item.accent)
	elif owned:
		label.text = tr("SAHİP")
		label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	else:
		label.text = str(item.price)
		label.add_theme_color_override(
			"font_color", Palette.COIN if affordable else Color(Palette.TEXT_DIM, 0.65))
		var coin := GlyphIcon.new()
		coin.glyph = GlyphIcon.Glyph.COIN
		coin.color = Palette.COIN if affordable else Color(Palette.TEXT_DIM, 0.65)
		coin.stroke_width = 2.4
		coin.custom_minimum_size = Vector2(24.0, 24.0)
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(label)
		box.add_child(coin)
		return box

	box.add_child(label)
	return box


func _card_style(accent: Color, strong: bool, border: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.INK_MID, 0.92)
	style.border_color = Color(accent, 0.8 if strong else 0.28)
	style.set_border_width_all(border)
	style.set_corner_radius_all(20)
	style.corner_detail = 10
	style.anti_aliasing = true
	return style


# --- Islemler -----------------------------------------------------------------

func _on_remove_ads_pressed() -> void:
	if purchase_service == null:
		return
	_iap_message = ""
	_rebuild()
	var result := int(await purchase_service.purchase_remove_ads())
	match result:
		PurchaseResult.Code.PURCHASED, PurchaseResult.Code.RESTORED, \
				PurchaseResult.Code.ALREADY_OWNED:
			_iap_message = "REKLAMLAR KALDIRILDI"
		PurchaseResult.Code.PENDING:
			_iap_message = "ÖDEME BEKLEMEDE"
		PurchaseResult.Code.CANCELLED:
			_iap_message = ""
		PurchaseResult.Code.UNAVAILABLE:
			_iap_message = "PLAY STORE'A BAĞLANILAMADI"
		_:
			_iap_message = "SATIN ALMA TAMAMLANAMADI"
	_rebuild()


func _on_restore_purchases_pressed() -> void:
	if purchase_service == null:
		return
	_iap_message = "İŞLENİYOR..."
	_rebuild()
	var success := bool(await purchase_service.restore_purchases())
	if not success:
		_iap_message = "PLAY STORE'A BAĞLANILAMADI"
	elif purchase_service.is_remove_ads_active():
		_iap_message = "SATIN ALMA GERİ YÜKLENDİ"
	else:
		_iap_message = "AKTİF SATIN ALMA BULUNAMADI"
	_rebuild()


func _on_purchase_state_changed() -> void:
	if is_inside_tree():
		_rebuild()

## Satin alma CIFT DUSMEZ: WalletStore.purchase_cosmetic sahip olunan esyada
## false doner ve bakiyeye dokunmaz. Kart da satin alindiktan hemen sonra
## yeniden kurulur, yani ikinci dokunus artik "sec" yoluna gider.
func _on_purchase_pressed(item: CosmeticData) -> void:
	if not wallet.purchase_cosmetic(item.id):
		return
	# Satin alinan esya hemen secilir: oyuncu aldigi seyi ayrica secmek
	# zorunda kalmamali.
	wallet.select_cosmetic(item.id)
	Haptics.target_hit()
	AudioManager.play_level_complete()
	_rebuild()
	_flash(item.id)


func _on_select_pressed(item: CosmeticData) -> void:
	if not wallet.select_cosmetic(item.id):
		return
	Haptics.pulse(18)
	_rebuild()
	_flash(item.id)


## Satin alma/secim sonrasi kisa bir parlama: islemin GERCEKLESTIGI
## gorulmeli, yoksa dokunusun ise yarayip yaramadigi belirsiz kalir.
func _flash(cosmetic_id: String) -> void:
	var card := _rows.get_node_or_null("Card_%s" % cosmetic_id) as Control
	if card == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	card.modulate = Color(1.6, 1.6, 1.6)
	_flash_tween = create_tween()
	_flash_tween.tween_property(card, "modulate", Color.WHITE, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
