class_name SettingsScreen
extends Control

## Ayarlar ekrani.
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
## AYAR NEREDE SAKLANIR - iki ayri yer, bilerek:
##   ProgressStore [settings] -> dil, titresim, sarsinti, nisan yardimi
##   AudioSettingsStore       -> sessize alma, muzik/efekt seviyesi
## Ikisi de ProgressStore.reset() tarafindan KORUNUR; ilerleme silmek oyuncu
## tercihlerini silmez.

signal menu_requested()
## Dil degisti - AppRoot'un acik olan diger ekranlari (ana menu) yeniden
## kurmasi icin. Ekran kendi basina baska bir ekrani tazeleyemez.
signal language_changed(code: String)

## AppRoot tarafindan add_child'dan ONCE atanir.
var progress: ProgressStore

## Ekran sarsintisi secenekleri. Tamamen kaldirmak yerine olceklenir: sarsinti
## oyunun geri bildiriminin parcasi, ama hareket duyarliligi olan oyuncu icin
## kapatilabilir olmali.
const SHAKE_CHOICES := [
	{"label": "Kapalı", "value": 0.0},
	{"label": "Az", "value": 0.5},
	{"label": "Normal", "value": 1.0},
]

const ROW_HEIGHT := 64.0
const SECTION_TOP_MARGIN := 18

@onready var _rows: VBoxContainer = $SafeArea/Content/Scroll/Rows
@onready var _back_button: Button = $SafeArea/Content/BackButton
@onready var _confirm_layer: Control = $ConfirmLayer
@onready var _confirm_button: Button = $ConfirmLayer/Card/Margin/Rows/Buttons/ConfirmButton
@onready var _cancel_button: Button = $ConfirmLayer/Card/Margin/Rows/Buttons/CancelButton


func _ready() -> void:
	if progress == null:
		progress = ProgressStore.load_from_disk()
	_back_button.pressed.connect(menu_requested.emit)
	_confirm_button.pressed.connect(_on_reset_confirmed)
	_cancel_button.pressed.connect(_hide_confirm)
	_rebuild()


# --- Satirlarin kurulmasi -----------------------------------------------------

func _rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()

	_add_section("Genel")
	_add_choice_row("Dil", _language_labels(), _language_index(), _on_language_chosen)

	_add_section("Sesler")
	_add_toggle_row("Ses", not AudioManager.is_muted(), _on_sound_toggled)
	_add_slider_row("Müzik", AudioManager.get_music_volume(), AudioManager.set_music_volume)
	_add_slider_row("Efektler", AudioManager.get_sfx_volume(), AudioManager.set_sfx_volume)

	_add_section("Oynanış")
	_add_toggle_row("Titreşim", progress.haptics_enabled, _on_haptics_toggled,
		"Sekme ve çarpmalarda titreşim")
	_add_choice_row("Ekran sarsıntısı", _shake_labels(), _shake_index(), _on_shake_chosen)
	_add_toggle_row("Nişan yardımı", progress.aim_assist, _on_aim_assist_toggled,
		"Nişan izi uzun bölümlerde de tam görünür")
	_add_action_row("Öğreticileri tekrar göster", _on_forget_mechanics)
	_add_action_row("İlerlemeyi sıfırla", _show_confirm)

	_add_section("Sürüm")
	_add_info_row(GameVersion.describe())


func _add_section(title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Palette.ACCENT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _rows.get_child_count() > 0:
		label.add_theme_constant_override("line_spacing", SECTION_TOP_MARGIN)
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0.0, SECTION_TOP_MARGIN)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rows.add_child(spacer)
	_rows.add_child(label)


## Etiket solda, denetim sagda. Aciklama metni (varsa) etiketin altinda kucuk
## ve sonuk durur - bir ayarin NE YAPTIGI, adindan her zaman anlasilmaz.
func _add_row(label_text: String, control: Control, hint := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	row.add_theme_constant_override("separation", 16)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_theme_constant_override("separation", 2)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Palette.TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(label)

	if not hint.is_empty():
		var hint_label := Label.new()
		hint_label.text = hint
		hint_label.add_theme_font_size_override("font_size", 17)
		hint_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texts.add_child(hint_label)

	row.add_child(texts)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	_rows.add_child(row)
	return row


func _add_toggle_row(label_text: String, value: bool, handler: Callable,
		hint := "") -> void:
	var button := _make_button("Açık" if value else "Kapalı", value)
	button.custom_minimum_size = Vector2(150.0, 52.0)
	button.pressed.connect(func() -> void:
		handler.call(not value)
		_rebuild())
	_add_row(label_text, button, hint)


## Iki-uc secenekli ayar (dil, sarsinti). Secili olan vurgulu gorunur;
## acik/kapali anahtarindan farkli olarak burada TUM secenekler gorunmelidir,
## cunku oyuncu neyin arasindan sectigini bilmeli.
func _add_choice_row(label_text: String, labels: Array, selected: int,
		handler: Callable, hint := "") -> void:
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation", 8)
	for i in labels.size():
		var index := i
		var button := _make_button(String(labels[i]), i == selected)
		button.custom_minimum_size = Vector2(104.0, 52.0)
		button.pressed.connect(func() -> void:
			handler.call(index)
			_rebuild())
		group.add_child(button)
	_add_row(label_text, group, hint)


func _add_slider_row(label_text: String, value: float, handler: Callable) -> void:
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(240.0, 52.0)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	# Kaydirici surukledigi surece SESI ANINDA degistirir: oyuncu sonucu
	# duymadan seviye secemez. Kalici yazim AudioManager'in isi.
	slider.value_changed.connect(func(new_value: float) -> void:
		handler.call(new_value))
	_add_row(label_text, slider)


func _add_action_row(label_text: String, handler: Callable) -> void:
	var button := _make_button(label_text, false)
	button.custom_minimum_size = Vector2(0.0, 60.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(handler)
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	row.add_child(button)
	_rows.add_child(row)


func _add_info_row(value: String) -> void:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Surum numarasi CEVRILMEZ: "1.0.0 (icerik 1...)" her dilde ayni olmali,
	# ayrica ceviri tablosunda olmadigi icin bosuna arama yapilmasin.
	label.set_message_translation(false)
	_rows.add_child(label)


func _make_button(text: String, active: bool) -> Button:
	var button := LumaButton.new()
	button.text = text
	button.emphasis = LumaButton.Emphasis.PRIMARY if active else LumaButton.Emphasis.SECONDARY
	button.corner_radius = 18
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 22)
	return button


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


func _on_forget_mechanics() -> void:
	progress.forget_seen_mechanics()
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
