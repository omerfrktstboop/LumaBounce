class_name HintPurchaseCard
extends Control

## Ipucu karti: TEK acilista IKI secenek sunar.
##
##   A) KISA IPUCU  - rotanin yalnizca ilk parcasi. Odullu reklam karsiligi;
##                    Luma Coin harcamaz ve kalici acilim SAYILMAZ.
##   B) TAM ROTA    - bolumun ornek atisinin tamami. Luma Coin ile alinir ve
##                    o bolum icin KALICI acilir.
##
## KART KARAR VERMEZ. Hangi secenegin etkin oldugu (bakiye, ozellik bayragi,
## bu denemede kisa ipucu kullanildi mi) Gameplay'in bilgisidir ve
## [method show_options] ile veri olarak gelir. Kartin isi yalnizca sunmak.
## Bu ayrim onemli: aksi halde urun kurallari iki yere dagilirdi.
##
## GORSEL: buyuk gri kapsul YOK. Her secenek koyu lacivert bir satirdir,
## kenari kendi vurgu renginde - kisa ipucu mor (ACCENT_ALT), tam rota cyan
## (ACCENT). Renk secenegi ANLATIR: iki secenek ayni sey degildir.

signal purchase_requested()
signal short_hint_requested()
signal dismissed()

@export var card_corner_radius := 30
@export var pop_time := 0.24
@export var option_corner_radius := 20
@export var option_height := 96.0

@onready var _card: PanelContainer = $CardCenter/Card
@onready var _kicker: Label = $CardCenter/Card/Margin/Rows/Header/Kicker
@onready var _balance_chip: HBoxContainer = $CardCenter/Card/Margin/Rows/Header/BalanceChip
@onready var _title: Label = $CardCenter/Card/Margin/Rows/Title
@onready var _options: VBoxContainer = $CardCenter/Card/Margin/Rows/Options
@onready var _cancel_button: LumaButton = $CardCenter/Card/Margin/Rows/CancelButton

var _pop_tween: Tween
var _balance_value: Label


func _ready() -> void:
	_apply_style()
	_build_balance_chip()
	_cancel_button.pressed.connect(close)
	hide()


## [param config] anahtarlari:
##   full_cost, balance, can_afford_full, short_cost, short_enabled, short_used
func show_options(config: Dictionary) -> void:
	var balance := int(config.get("balance", 0))
	_kicker.text = tr("İPUCU")
	_balance_value.text = str(balance)
	_title.text = tr("Nasıl yardım istersin?")

	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()

	_options.add_child(_make_short_option(config))
	_options.add_child(_make_full_option(config))
	_cancel_button.text = tr("VAZGEÇ")
	_open()


func is_open() -> bool:
	return visible


func close() -> void:
	if not visible:
		return
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	hide()
	modulate.a = 1.0
	_card.scale = Vector2.ONE
	dismissed.emit()


# --- Secenek satirlari --------------------------------------------------------

func _make_short_option(config: Dictionary) -> Button:
	var enabled := bool(config.get("short_enabled", false))
	var used := bool(config.get("short_used", false))
	var cost := int(config.get("short_cost", 0))

	var price := tr("ÜCRETSİZ") if cost <= 0 else tr("%d ◈") % cost
	var note := ""
	if used:
		note = tr("Bu denemede kullanıldı")
	elif not enabled:
		# Ozellik bayragi kapali (odullu reklam henuz yok). Secenek GORUNUR
		# kalir: oyuncu ne gelecegini bilsin, ama calismayan bir dugmeye
		# basip hicbir sey olmamasiyla karsilasmasin.
		note = tr("Yakında")
		price = tr("YAKINDA")

	var row := _make_option_row(
		GlyphIcon.Glyph.HINT, Palette.ACCENT_ALT,
		tr("KISA İPUCU"), tr("Rotanın ilk hamlesini gösterir"), note, price,
		enabled and not used)
	row.name = "ShortOption"
	if enabled and not used:
		row.pressed.connect(short_hint_requested.emit)
	return row


func _make_full_option(config: Dictionary) -> Button:
	var cost := int(config.get("full_cost", 0))
	var affordable := bool(config.get("can_afford_full", false))
	var note := "" if affordable else tr("Bakiye yetersiz")
	var row := _make_option_row(
		GlyphIcon.Glyph.COIN, Palette.COIN,
		tr("TAM ROTAYI AÇ"), tr("Bu bölüm için kalıcı açılır"), note,
		tr("%d ◈") % cost, affordable)
	row.name = "FullOption"
	if affordable:
		row.pressed.connect(purchase_requested.emit)
	return row


## Koyu lacivert govde + secenege ozel vurgu kenari. Tum satir tiklanabilir
## olsun diye Button; icerik mouse_filter IGNORE ile basisi engellemez.
func _make_option_row(glyph: GlyphIcon.Glyph, accent: Color, title: String,
		subtitle: String, note: String, price: String, enabled: bool) -> Button:
	var row := Button.new()
	row.custom_minimum_size = Vector2(0.0, option_height)
	row.focus_mode = Control.FOCUS_NONE
	row.disabled = not enabled
	row.add_theme_stylebox_override("normal", _option_style(accent, 0.16, 2))
	row.add_theme_stylebox_override("hover", _option_style(accent, 0.26, 2))
	row.add_theme_stylebox_override("pressed", _option_style(accent, 0.34, 3))
	row.add_theme_stylebox_override("disabled", _option_style(accent, 0.07, 1))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	row.add_child(margin)

	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 14)
	margin.add_child(line)

	var icon := GlyphIcon.new()
	icon.glyph = glyph
	icon.color = accent if enabled else Color(accent, 0.42)
	icon.stroke_width = 2.6
	icon.custom_minimum_size = Vector2(34.0, 34.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(icon)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_theme_constant_override("separation", 1)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(texts)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 23)
	title_label.add_theme_color_override(
		"font_color", Palette.TEXT if enabled else Color(Palette.TEXT_DIM, 0.7))
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(title_label)

	var subtitle_label := Label.new()
	subtitle_label.text = note if not note.is_empty() else subtitle
	subtitle_label.add_theme_font_size_override("font_size", 16)
	subtitle_label.add_theme_color_override(
		"font_color", accent if not note.is_empty() and enabled else Palette.TEXT_DIM)
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(subtitle_label)

	var price_label := Label.new()
	price_label.name = "Price"
	price_label.text = price
	price_label.add_theme_font_size_override("font_size", 21)
	price_label.add_theme_color_override(
		"font_color", accent if enabled else Color(Palette.TEXT_DIM, 0.6))
	price_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(price_label)

	return row


func _option_style(accent: Color, fill_alpha: float, border: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.INK_MID, 0.92)
	style.border_color = Color(accent, fill_alpha + 0.34)
	style.set_border_width_all(border)
	style.set_corner_radius_all(option_corner_radius)
	style.corner_detail = 10
	style.anti_aliasing = true
	return style


## Baslikta kucuk bir bakiye rozeti: "BAKIYE: 3 LUMA COIN" cumlesi yerine
## simge + sayi. Kelime tekrari HUD'da da kartta da kaldirildi.
func _build_balance_chip() -> void:
	var icon := GlyphIcon.new()
	icon.glyph = GlyphIcon.Glyph.COIN
	icon.color = Palette.COIN
	icon.stroke_width = 2.4
	icon.custom_minimum_size = Vector2(22.0, 22.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_balance_chip.add_child(icon)

	_balance_value = Label.new()
	_balance_value.name = "Value"
	_balance_value.text = "0"
	_balance_value.add_theme_font_size_override("font_size", 21)
	_balance_value.add_theme_color_override("font_color", Palette.COIN_CORE)
	_balance_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_balance_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_balance_chip.add_child(_balance_value)


func _open() -> void:
	show()
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.88, 0.88)
	modulate.a = 0.0
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.set_parallel(true)
	_pop_tween.tween_property(_card, "scale", Vector2.ONE, pop_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(self, "modulate:a", 1.0, pop_time * 0.75)


func _apply_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.SURFACE, 0.98)
	style.border_color = Color(Palette.ACCENT, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(card_corner_radius)
	style.corner_detail = 12
	style.anti_aliasing = true
	_card.add_theme_stylebox_override("panel", style)
	_kicker.add_theme_color_override("font_color", Palette.ACCENT)
	_title.add_theme_color_override("font_color", Palette.TEXT)
