class_name SettingsScreen
extends Control

## Ayarlar ekrani (FAZ 9 yeniden tasarimi).
##
## Diger ekranlarla ayni kural: KENDISI hicbir sahne acmaz, yalnizca sinyal
## yayar; ilerleme verisi AppRoot tarafindan add_child'dan ONCE enjekte edilir.
##
## Satirlar kod ile uretilir (bkz. _rebuild), sahnede degil. Sebep tek bir
## somut ihtiyac: dil degistiginde etiketlerin degil, SECILI SECENEGIN de
## tazelenmesi gerekiyor - "Açık/Kapalı" metnini Godot kendisi cevirir ama
## hangi dugmenin secili gorundugunu bilemez. Tek bir _rebuild ikisini de
## halleder ve yeni bir ayar eklemek bir satirlik is olur.
##
## Bolumler artik ayri KARTLAR halinde gruplanir (_begin_card ile acilir,
## sonraki _add_*_row cagrilari o kartin GOVDESINE eklenir). Row-builder
## fonksiyonlarinin IMZALARI ve TUM _on_* isleyici adlari degismedi -
## check_blocks_and_gate.gd::_test_settings_screen bunlari dogrudan
## screen.call(...) ile cagirir.
##
## AYAR NEREDE SAKLANIR - iki ayri yer, bilerek:
##   ProgressStore [settings] -> dil, titresim, sarsinti, nisan yardimi
##   AudioSettingsStore       -> sessize alma, muzik/efekt seviyesi
## Ikisi de ProgressStore.reset() tarafindan KORUNUR; ilerleme silmek oyuncu
## tercihlerini silmez.

signal menu_requested()
signal tutorial_requested()
signal rate_requested()
signal feedback_requested()
## Dil degisti - AppRoot'un acik olan diger ekranlari (ana menu) yeniden
## kurmasi icin. Ekran kendi basina baska bir ekrani tazeleyemez.
signal language_changed(code: String)

## AppRoot tarafindan add_child'dan ONCE atanir.
var progress: ProgressStore
var ad_service: AdService

## Ekran sarsintisi secenekleri. Tamamen kaldirmak yerine olceklenir: sarsinti
## oyunun geri bildiriminin parcasi, ama hareket duyarliligi olan oyuncu icin
## kapatilabilir olmali.
const SHAKE_CHOICES := [
	{"label": "Kapalı", "value": 0.0},
	{"label": "Az", "value": 0.5},
	{"label": "Normal", "value": 1.0},
]

const ROW_HEIGHT := 76.0

## Bir kaydirma hareketi dugmenin uzerinde bittiginde Button ayni release'i
## tiklama sanmasin. LevelSelect ile ayni kisa koruma araligini kullanir.
@export var scroll_guard_msec := 220

@onready var _rows: VBoxContainer = $SafeArea/Content/Scroll/Rows
@onready var _scroll: ScrollContainer = $SafeArea/Content/Scroll
@onready var _back_button: Button = $SafeArea/Content/BackButton
@onready var _header_back_button: Button = $SafeArea/Content/Header/HeaderBackButton
@onready var _confirm_layer: Control = $ConfirmLayer
@onready var _confirm_button: Button = $ConfirmLayer/Card/Margin/Rows/Buttons/ConfirmButton
@onready var _cancel_button: Button = $ConfirmLayer/Card/Margin/Rows/Buttons/CancelButton

## _rebuild() sirasinda "su an hangi kartin icine ekleniyoruz" durumu.
## _begin_card() acar, satir eklemeleri buraya gider.
var _current_card_body: VBoxContainer
var _link_status: Label
var _link_status_tween: Tween
var _last_scroll_msec := -100000


func _ready() -> void:
	if progress == null:
		progress = ProgressStore.load_from_disk()
	_back_button.pressed.connect(menu_requested.emit)
	_header_back_button.pressed.connect(menu_requested.emit)
	_confirm_button.pressed.connect(_on_reset_confirmed)
	_cancel_button.pressed.connect(_hide_confirm)
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)
	if ad_service != null:
		ad_service.privacy_options_availability_changed.connect(
			_on_privacy_options_availability_changed)
	_rebuild()


# --- Satirlarin kurulmasi -----------------------------------------------------

func _rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_current_card_body = null

	_begin_card("Genel")
	_add_dropdown_row("Dil", _language_labels(), _language_index(), _on_language_chosen)

	_begin_card("Sesler")
	_add_toggle_row("Ses", not AudioManager.is_muted(), _on_sound_toggled)
	_add_slider_row("Müzik", AudioManager.get_music_volume(), AudioManager.set_music_volume)
	_add_slider_row("Efektler", AudioManager.get_sfx_volume(), AudioManager.set_sfx_volume)

	_begin_card("Oynanış")
	_add_toggle_row("Titreşim", progress.haptics_enabled, _on_haptics_toggled,
		"Sekme ve çarpmalarda titreşim")
	_add_choice_row("Ekran sarsıntısı", _shake_labels(), _shake_index(), _on_shake_chosen)
	_add_toggle_row("Nişan yardımı", progress.aim_assist, _on_aim_assist_toggled,
		"Nişan izi uzun bölümlerde de tam görünür")
	_add_action_row(tr("HOW_TO_PLAY"), tutorial_requested.emit, GlyphIcon.Glyph.INFO,
		64.0, "TutorialReplayIcon")
	_add_divider()
	_add_action_row("İlerlemeyi sıfırla", _show_confirm, GlyphIcon.Glyph.RESTART,
		64.0, "ProgressResetIcon")

	_begin_card(tr("SUPPORT"))
	_add_action_row(tr("RATE_GAME"), rate_requested.emit, GlyphIcon.Glyph.CHECK,
		64.0, "RateGameIcon")
	_add_action_row(tr("SEND_FEEDBACK"), feedback_requested.emit, GlyphIcon.Glyph.INFO,
		64.0, "SendFeedbackIcon")
	_add_link_status()

	# Gizlilik politikasi HER ZAMAN gorunur ve reklam SDK'sindan BAGIMSIZDIR:
	# magaza yayin sarti, reklamlari kaldiran oyuncu icin de gecerli. Gizlilik
	# SECENEKLERI (UMP formu) ise yalnizca saglayici gerekli gordugunde
	# eklenir, bu yuzden kart artik kosulsuz acilir.
	_begin_card("Gizlilik")
	_add_action_row("Gizlilik politikası", _on_privacy_policy_pressed,
		GlyphIcon.Glyph.INFO)
	if ad_service != null and ad_service.is_privacy_options_available():
		_add_action_row("Gizlilik seçenekleri", _on_privacy_options_pressed,
			GlyphIcon.Glyph.LOCK)

	_add_info_row(GameVersion.describe())


func _add_link_status() -> void:
	_link_status = Label.new()
	_link_status.name = "ExternalLinkStatus"
	_link_status.visible = false
	_link_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_link_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_link_status.add_theme_font_size_override("font_size", UIMetrics.FONT_SUPPORTING)
	_link_status.add_theme_color_override("font_color", Palette.HAZARD_CORE)
	_link_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_current_card_body.add_child(_link_status)


func show_external_link_error() -> void:
	if _link_status == null or not is_instance_valid(_link_status):
		return
	if _link_status_tween != null and _link_status_tween.is_valid():
		_link_status_tween.kill()
	_link_status.text = tr("EXTERNAL_LINK_FAILED")
	_link_status.modulate.a = 1.0
	_link_status.show()
	_link_status_tween = create_tween()
	_link_status_tween.tween_interval(3.5)
	_link_status_tween.tween_property(_link_status, "modulate:a", 0.0, 0.35)
	_link_status_tween.tween_callback(_link_status.hide)


## Yeni bir kart PANELI acar; sonraki _add_*_row cagrilari bu kartin
## govdesine eklenir. Kartlar arasi bosluk marka rehberinin "buyuk section
## bosluk" kuralini yansitir (bkz. UIMetrics.SPACE_XXL).
func _begin_card(title: String) -> void:
	if _rows.get_child_count() > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0.0, UIMetrics.SPACE_LG)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rows.add_child(spacer)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", LumaCard.panel_style())
	_rows.add_child(card)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, UIMetrics.CARD_PADDING)
	card.add_child(margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", UIMetrics.SPACE_SM)
	margin.add_child(body)
	body.add_child(LumaCard.section_header(title))

	_current_card_body = body


func _add_divider() -> void:
	var line := ColorRect.new()
	line.color = Color(Palette.SURFACE_EDGE, 0.4)
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_current_card_body.add_child(line)


## Etiket solda, denetim sagda. Aciklama metni (varsa) etiketin altinda kucuk
## ve sonuk durur - bir ayarin NE YAPTIGI, adindan her zaman anlasilmaz.
func _add_row(label_text: String, control: Control, hint := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	row.add_theme_constant_override("separation", UIMetrics.SPACE_LG)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_theme_constant_override("separation", 2)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", UIMetrics.FONT_BODY + 2)
	label.add_theme_color_override("font_color", Palette.TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(label)

	if not hint.is_empty():
		var hint_label := Label.new()
		hint_label.text = hint
		hint_label.add_theme_font_size_override("font_size", UIMetrics.FONT_SUPPORTING)
		hint_label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texts.add_child(hint_label)

	row.add_child(texts)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	_current_card_body.add_child(row)
	return row


func _add_toggle_row(label_text: String, value: bool, handler: Callable,
		hint := "") -> void:
	var toggle := ToggleSwitch.new()
	toggle.value = value
	_enable_parent_touch_scroll(toggle)
	toggle.value_changed.connect(func(new_value: bool) -> void:
		if _scroll_guard_active():
			_rebuild()
			return
		handler.call(new_value)
		_rebuild())
	_add_row(label_text, toggle, hint)


## Dil gibi uzun etiketli ve tek secimli ayarlar acilir liste kullanir. Boylece
## satir iki-uc ayri dugmeyle dolmaz ve yeni diller eklendiginde tasma olmaz.
func _add_dropdown_row(label_text: String, labels: Array, selected: int,
		handler: Callable, hint := "") -> void:
	var dropdown := LumaDropdown.new()
	dropdown.name = "LanguageDropdown"
	dropdown.setup(labels, selected)
	_enable_parent_touch_scroll(dropdown)
	dropdown.item_selected.connect(func(index: int) -> void:
		handler.call(index)
		_rebuild())
	_add_row(label_text, dropdown, hint)


## Iki-uc secenekli kisa ayar (ornegin sarsinti). Secili olan vurgulu gorunur;
## acik/kapali anahtarindan farkli olarak burada TUM secenekler gorunmelidir,
## cunku oyuncu neyin arasindan sectigini bilmeli.
func _add_choice_row(label_text: String, labels: Array, selected: int,
		handler: Callable, hint := "") -> void:
	var control := SegmentedControl.new()
	control.setup(labels, selected)
	_enable_parent_touch_scroll(control)
	control.value_changed.connect(func(index: int) -> void:
		if _scroll_guard_active():
			_rebuild()
			return
		handler.call(index)
		_rebuild())
	_add_row(label_text, control, hint)


func _add_slider_row(label_text: String, value: float, handler: Callable) -> void:
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(196.0, UIMetrics.MIN_TOUCH)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	_style_slider(slider)
	# Kaydirici surukledigi surece SESI ANINDA degistirir: oyuncu sonucu
	# duymadan seviye secemez. Kalici yazim AudioManager'in isi.
	slider.value_changed.connect(func(new_value: float) -> void:
		handler.call(new_value))
	_add_row(label_text, slider)


func _style_slider(slider: HSlider) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.ACCENT
	fill.content_margin_top = 6.0
	fill.content_margin_bottom = 6.0
	fill.set_corner_radius_all(6)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(Palette.SURFACE, 0.9)
	track.content_margin_top = 6.0
	track.content_margin_bottom = 6.0
	track.set_corner_radius_all(6)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.add_theme_stylebox_override("slider", track)


func _add_action_row(label_text: String, handler: Callable,
		glyph := GlyphIcon.Glyph.SETTINGS, tile_width := 0.0,
		tile_name := "") -> void:
	var row := Button.new()
	row.text = ""
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	_enable_parent_touch_scroll(row)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		row.add_theme_stylebox_override(state, empty)
	row.pressed.connect(func() -> void:
		if _scroll_guard_active():
			return
		handler.call())

	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", UIMetrics.SPACE_LG)
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_child(line)

	var tile := IconTile.new()
	tile.glyph = glyph
	tile.tile_size = 44.0
	tile.tile_width = tile_width
	tile.icon_inset = 10.0
	if not tile_name.is_empty():
		tile.name = tile_name
	line.add_child(tile)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", UIMetrics.FONT_BODY + 2)
	label.add_theme_color_override("font_color", Palette.TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(label)

	var chevron := GlyphIcon.new()
	chevron.glyph = GlyphIcon.Glyph.CHEVRON_RIGHT
	chevron.color = Palette.TEXT_DIM
	chevron.custom_minimum_size = Vector2(18.0, 18.0)
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(chevron)

	_current_card_body.add_child(row)


## ScrollContainer, STOP kullanan bir alt kontrolden baslayan dokunmatik
## suruklemeyi goremez. Ayar dugmelerini PASS yapmak hem normal tiklamayi
## korur hem de dikey hareketi ustteki ScrollContainer'a ulastirir.
func _enable_parent_touch_scroll(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_PASS
	for child in control.get_children():
		var child_control := child as Control
		if child_control != null:
			_enable_parent_touch_scroll(child_control)


func _on_scrolled(_value: float) -> void:
	_last_scroll_msec = Time.get_ticks_msec()


func _scroll_guard_active() -> bool:
	return Time.get_ticks_msec() - _last_scroll_msec < scroll_guard_msec


## Surum satiri kendi kucuk, basliksiz kartinda durur (diger kartlar gibi bir
## SECTION baslikligina ihtiyaci yok - tek satirlik pasif bilgi).
func _add_info_row(value: String) -> void:
	if _rows.get_child_count() > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0.0, UIMetrics.SPACE_LG)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rows.add_child(spacer)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", LumaCard.panel_style())
	_rows.add_child(card)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, UIMetrics.SPACE_LG)
	card.add_child(margin)

	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", UIMetrics.SPACE_LG)
	margin.add_child(line)

	var tile := IconTile.new()
	tile.glyph = GlyphIcon.Glyph.INFO
	tile.tile_size = 36.0
	tile.icon_inset = 8.0
	tile.icon_color = Palette.TEXT_DIM
	line.add_child(tile)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 2)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(texts)

	var title := Label.new()
	title.text = tr("Sürüm")
	title.add_theme_font_size_override("font_size", UIMetrics.FONT_BODY)
	title.add_theme_color_override("font_color", Palette.TEXT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(title)

	var version_label := Label.new()
	version_label.text = value
	version_label.add_theme_font_size_override("font_size", UIMetrics.FONT_SUPPORTING)
	version_label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	# Surum numarasi CEVRILMEZ: "1.0.0 (icerik 1...)" her dilde ayni olmali,
	# ayrica ceviri tablosunda olmadigi icin bosuna arama yapilmasin.
	version_label.set_message_translation(false)
	texts.add_child(version_label)
	version_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


# --- Secenek durumlari --------------------------------------------------------

func _language_labels() -> Array:
	var labels: Array = []
	for code in Locale.SUPPORTED:
		labels.append(Locale.display_name(code))
	return labels


## Kaydedilmis tercih bos ise (oyuncu henuz secmedi) o an GECERLI dil secili
## gorunur - ekranda hicbir secenegin isaretli olmamasi kafa karistirir.
func _language_index() -> int:
	var current := Locale.current() if progress.language.is_empty() else progress.language
	return maxi(0, Locale.SUPPORTED.find(current))


func _shake_labels() -> Array:
	var labels: Array = []
	for choice in SHAKE_CHOICES:
		labels.append(String(choice["label"]))
	return labels


func _shake_index() -> int:
	var best := 0
	var best_distance := INF
	for i in SHAKE_CHOICES.size():
		var distance := absf(float(SHAKE_CHOICES[i]["value"]) - progress.shake_scale)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


# --- Islemler -----------------------------------------------------------------

func _on_language_chosen(index: int) -> void:
	if index < 0 or index >= Locale.SUPPORTED.size():
		return
	var code := String(Locale.SUPPORTED[index])
	Locale.apply(code)
	progress.set_language(code)
	language_changed.emit(code)


func _on_sound_toggled(enabled: bool) -> void:
	AudioManager.set_muted(not enabled)


func _on_haptics_toggled(enabled: bool) -> void:
	if progress.set_haptics_enabled(enabled):
		# Tek okuma noktasi Haptics.enabled (bkz. haptics.gd) - burada
		# guncellenmezse ayar yalnizca yeniden baslatmada etkili olurdu.
		Haptics.enabled = enabled
	if enabled:
		# Acildiginda bir kez titret: oyuncu neyi actigini HISSETSIN.
		Haptics.target_hit()


func _on_shake_chosen(index: int) -> void:
	if index < 0 or index >= SHAKE_CHOICES.size():
		return
	if progress.set_shake_scale(float(SHAKE_CHOICES[index]["value"])):
		# Tek kisma noktasi ScreenShake.trauma_scale; burada guncellenmezse
		# ayar yalnizca yeniden baslatmada etkili olurdu.
		ScreenShake.trauma_scale = progress.shake_scale


func _on_aim_assist_toggled(enabled: bool) -> void:
	progress.set_aim_assist(enabled)


## Metin oyunun icinde degil, tarayicida acilir: politika metni magaza
## listelemesiyle AYNI adresten gelmeli, yoksa uygulama guncellemeden
## gecmedigi surece ikisi birbirinden ayrilir.
func _on_privacy_policy_pressed() -> void:
	LegalLinks.open_privacy_policy()


func _on_privacy_options_availability_changed(_available: bool) -> void:
	_rebuild()


func _on_privacy_options_pressed() -> void:
	if ad_service == null:
		return
	await ad_service.show_privacy_options()
	_rebuild()


# --- Ilerlemeyi sifirlama -----------------------------------------------------
#
# Geri alinamaz bir islem tek dokunusla olmamali; onay katmani bu yuzden var.

func _show_confirm() -> void:
	_confirm_layer.visible = true


func _hide_confirm() -> void:
	_confirm_layer.visible = false


func _on_reset_confirmed() -> void:
	progress.reset()
	_hide_confirm()
	_rebuild()
