class_name ShopScreen
extends Control

## Luma Coin magazasi: kozmetik satin alma ve secme (FAZ 9 yeniden tasarimi).
##
## Diger ekranlarla ayni kural: KENDISI hicbir sahne acmaz, yalnizca sinyal
## yayar; cuzdan AppRoot tarafindan add_child'dan ONCE enjekte edilir.
##
## Kartlar kod ile uretilir (ayarlar ekranindaki desen): satin alma ya da
## secim sonrasi hem fiyat/durum etiketi hem SEÇİLİ isareti degisir; tek bir
## _rebuild ikisini de tutarli tutar. Sekme (tur) degisimi de ayni tam
## yeniden kurulumu kullanir - _active_kind_index durumu korunur.
##
## FIYAT BURADA YAZILI DEGIL - CosmeticData'dan okunur. Denge degisikligi
## katalogda yapilir ve bu dosya hic degismez.

signal menu_requested()

## AppRoot tarafindan add_child'dan ONCE atanir.
var wallet: WalletStore
var purchase_service: PurchaseService
var analytics: AnalyticsService

## Sekme etiketleri kisa tutulur (720px genislikte 4 sekme sigmali). Tam
## isimler CosmeticCatalog.kind_label()'da kalir, baska yerlerde kullanilir.
const KIND_TAB_LABELS := {
	CosmeticData.Kind.BALL: "TOP",
	CosmeticData.Kind.TRAIL: "İZ",
	CosmeticData.Kind.LAUNCHER: "FIRLATICI",
	CosmeticData.Kind.TARGET_FX: "EFEKT",
}

@onready var _rows: VBoxContainer = $SafeArea/Content/Scroll/Rows
@onready var _balance_chip: CoinChip = $SafeArea/Content/Header/CoinChip
@onready var _back_button: LumaIconButton = $SafeArea/Content/Header/BackButton

var _active_kind_index := 0
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

	_balance_chip.bind(wallet)
	if purchase_service != null:
		_rows.add_child(LumaCard.section_header(tr("PREMİUM")))
		_rows.add_child(_make_remove_ads_card())
		_rows.add_child(_make_restore_purchases_button())

	var tabs := SegmentedControl.new()
	tabs.name = "CategoryTabs"
	var labels: Array = []
	for kind in CosmeticCatalog.KIND_ORDER:
		labels.append(tr(String(KIND_TAB_LABELS.get(kind, CosmeticCatalog.kind_label(kind)))))
	tabs.setup(labels, _active_kind_index)
	tabs.value_changed.connect(_on_category_changed)
	_rows.add_child(tabs)

	var grid := GridContainer.new()
	grid.name = "ProductGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UIMetrics.SPACE_MD)
	grid.add_theme_constant_override("v_separation", UIMetrics.SPACE_MD)
	_rows.add_child(grid)

	var active_kind: CosmeticData.Kind = CosmeticCatalog.KIND_ORDER[_active_kind_index]
	for item in CosmeticCatalog.by_kind(active_kind):
		grid.add_child(_make_card(item))


func _on_category_changed(index: int) -> void:
	_active_kind_index = index
	_rebuild()


## Kart uc durumdan birini gosterir:
##   satin alinabilir -> fiyat
##   sahip ama secili degil -> "SAHİP" (dokununca secilir)
##   secili -> "SEÇİLİ" (dokunulamaz, zaten aktif)
func _make_card(item: CosmeticData) -> ProductCard:
	var owned := wallet.owns(item.id)
	var selected := wallet.selected_cosmetic_id(item.kind) == item.id
	var affordable := owned or wallet.can_afford(item.price)

	var card := ProductCard.new()
	card.configure(item, owned, selected, affordable)
	card.purchase_requested.connect(_on_purchase_pressed)
	card.select_requested.connect(_on_select_pressed)
	return card


func _make_remove_ads_card() -> Button:
	var active := purchase_service.is_remove_ads_active()
	var is_ready := purchase_service.is_product_ready(MonetizationConfig.PRODUCT_REMOVE_ADS)
	var busy := purchase_service.is_busy()

	var card := Button.new()
	card.name = "RemoveAdsCard"
	card.custom_minimum_size = Vector2(0.0, 156.0)
	card.focus_mode = Control.FOCUS_NONE
	card.disabled = active or busy or not is_ready
	card.text = ""
	card.add_theme_stylebox_override("normal", LumaCard.style(Palette.ACCENT, active, 2))
	card.add_theme_stylebox_override("hover", LumaCard.style(Palette.ACCENT, true, 2))
	card.add_theme_stylebox_override("pressed", LumaCard.style(Palette.ACCENT, true, 3))
	card.add_theme_stylebox_override("disabled", LumaCard.style(Palette.ACCENT, active, 2))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", UIMetrics.CARD_PADDING)
	margin.add_theme_constant_override("margin_right", UIMetrics.CARD_PADDING)
	margin.add_theme_constant_override("margin_top", UIMetrics.SPACE_LG)
	margin.add_theme_constant_override("margin_bottom", UIMetrics.SPACE_LG)
	card.add_child(margin)

	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", UIMetrics.SPACE_LG)
	margin.add_child(line)

	var tile := IconTile.new()
	tile.name = "RemoveAdsIcon"
	tile.glyph = GlyphIcon.Glyph.CHECK if active else GlyphIcon.Glyph.LOCK
	tile.icon_color = Palette.ACCENT
	tile.tile_accent = Palette.ACCENT
	tile.tile_size = 64.0
	tile.tile_width = 88.0
	tile.icon_inset = 16.0
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(tile)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_theme_constant_override("separation", 3)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(texts)

	var title := Label.new()
	title.text = tr("REKLAMLARI KALDIR")
	title.add_theme_font_size_override("font_size", UIMetrics.FONT_CARD_TITLE + 3)
	title.add_theme_color_override("font_color", Palette.TEXT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(title)

	var description := Label.new()
	description.text = tr("Geçiş reklamlarını kalıcı olarak kapatır")
	description.add_theme_font_size_override("font_size", UIMetrics.FONT_SUPPORTING + 1)
	description.add_theme_color_override("font_color", Palette.TEXT_DIM)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(description)

	var status := Label.new()
	status.text = _remove_ads_status(active, is_ready, busy)
	status.add_theme_font_size_override("font_size", UIMetrics.FONT_SUPPORTING + 3)
	status.add_theme_color_override(
		"font_color", Palette.ACCENT if active else Palette.COIN)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(status)

	if not card.disabled:
		card.pressed.connect(_on_remove_ads_pressed)
	return card


func _remove_ads_status(active: bool, is_ready: bool, busy: bool) -> String:
	if active:
		return tr("AKTİF")
	if busy:
		return tr("İŞLENİYOR...")
	if not _iap_message.is_empty():
		return tr(_iap_message)
	if is_ready:
		var price := purchase_service.formatted_price(MonetizationConfig.PRODUCT_REMOVE_ADS)
		return price if not price.is_empty() else tr("SATIN AL")
	return tr("PLAY STORE'A BAĞLANILIYOR")


func _make_restore_purchases_button() -> Button:
	var button := LumaButton.new()
	button.name = "RestorePurchasesButton"
	button.text = tr("SATIN ALMALARI GERİ YÜKLE")
	button.corner_radius = UIMetrics.RADIUS_MD
	button.custom_minimum_size = Vector2(0.0, UIMetrics.MIN_TOUCH)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = purchase_service.is_busy() or not purchase_service.is_available()
	button.add_theme_font_size_override("font_size", UIMetrics.FONT_BODY)
	button.pressed.connect(_on_restore_purchases_pressed)
	return button


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
	var selected := wallet.select_cosmetic(item.id)
	if analytics != null:
		analytics.track_event(AnalyticsService.COSMETIC_PURCHASE, {
			"cosmetic_id": item.id,
			"kind": item.kind,
			"price": item.price,
		})
		if selected:
			analytics.track_event(AnalyticsService.COSMETIC_SELECT, {
				"cosmetic_id": item.id,
				"kind": item.kind,
			})
	Haptics.target_hit()
	AudioManager.play_level_complete()
	_rebuild()
	_flash(item.id)


func _on_select_pressed(item: CosmeticData) -> void:
	if not wallet.select_cosmetic(item.id):
		return
	if analytics != null:
		analytics.track_event(AnalyticsService.COSMETIC_SELECT, {
			"cosmetic_id": item.id,
			"kind": item.kind,
		})
	Haptics.pulse(18)
	_rebuild()
	_flash(item.id)


## Satin alma/secim sonrasi kisa bir parlama: islemin GERCEKLESTIGI
## gorulmeli, yoksa dokunusun ise yarayip yaramadigi belirsiz kalir.
func _flash(cosmetic_id: String) -> void:
	var grid := _rows.get_node_or_null("ProductGrid")
	if grid == null:
		return
	var card := grid.get_node_or_null("Card_%s" % cosmetic_id) as Control
	if card == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	card.modulate = Color(1.6, 1.6, 1.6)
	_flash_tween = create_tween()
	_flash_tween.tween_property(card, "modulate", Color.WHITE, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
