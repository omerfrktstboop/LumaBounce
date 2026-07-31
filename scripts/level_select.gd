class_name LevelSelect
extends Control

## Bolum secim ekrani.
##
## Butonlar LevelLibrary'deki bolum sayisindan uretilir; ilerleme durumu
## AppRoot tarafindan [member progress] ile enjekte edilir. Ekran hicbir
## sahneyi kendisi acmaz, yalnizca sinyal yayar.

signal level_selected(level_id: int)
signal menu_requested()

## 10 bolum iki sutuna sigacak boyut: 5 satir x 132 + 4 x 20 bosluk = 740 px,
## 720x1280 referans ekranda kaydirmaya gerek kalmadan sigar. Daha kisa
## ekranlarda GridScroll devreye girer.
@export var button_size := Vector2(132.0, 132.0)
@export var button_font_size := 40
@export var columns := 2
@export var check_size := 24.0
## Kaydirma bittikten sonra bu sure boyunca bolum secimi yok sayilir; parmak
## kaydirirken butonun uzerinde birakildiginda yanlislikla bolum acilmasin.
@export var scroll_guard_msec := 220

## AppRoot tarafindan add_child'dan ONCE atanir.
var progress: ProgressStore
## Yalnizca debug paneli tarafindan kullanilir. true iken gercek save
## dosyasina HICBIR SEKILDE dokunmadan tum bolumleri secilebilir gosterir.
var debug_force_unlock := false

@onready var _scroll: ScrollContainer = $SafeArea/Content/GridScroll
@onready var _grid: GridContainer = $SafeArea/Content/GridScroll/GridHolder/Grid
@onready var _back_button: LumaButton = $SafeArea/Content/BackButton

var _last_scroll_msec := -100000


func _ready() -> void:
	if progress == null:
		progress = ProgressStore.load_from_disk()
	_grid.columns = columns
	_build_buttons()
	_back_button.pressed.connect(menu_requested.emit)
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)


func _on_scrolled(_value: float) -> void:
	_last_scroll_msec = Time.get_ticks_msec()


## Debug panelinden calisma zamaninda cagrilir; ekran zaten acikken
## butonlarin kilit durumunu aninda yeniler. Baslangic enjeksiyonu icin
## debug_force_unlock alanini dogrudan atamak yeterlidir (bkz. AppRoot).
func set_debug_force_unlock(enabled: bool) -> void:
	debug_force_unlock = enabled
	if is_node_ready():
		_build_buttons()


func _build_buttons() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

	for level_id in range(LevelLibrary.FIRST_LEVEL_ID, LevelLibrary.last_level_id() + 1):
		_grid.add_child(_make_level_button(level_id))


func _make_level_button(level_id: int) -> LumaButton:
	var unlocked := progress.is_unlocked(level_id) or debug_force_unlock
	var completed := progress.is_completed(level_id)

	var button := LumaButton.new()
	button.name = "Level%02d" % level_id
	button.text = str(level_id)
	button.custom_minimum_size = button_size
	button.corner_radius = 28
	button.content_margin = Vector2(10.0, 10.0)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not unlocked
	# Tamamlanan bolum, birincil vurgu (hafif cyan kenar) ile isaretlenir.
	button.emphasis = LumaButton.Emphasis.PRIMARY if completed else LumaButton.Emphasis.SECONDARY
	button.add_theme_font_size_override("font_size", button_font_size)
	button.pressed.connect(_on_level_pressed.bind(level_id))

	if completed:
		button.add_child(_make_check_mark())

	return button


## "Tamamlandi" isareti: kucuk, sade bir onay imi.
func _make_check_mark() -> GlyphIcon:
	var check := GlyphIcon.new()
	check.name = "CompletedMark"
	check.glyph = GlyphIcon.Glyph.CHECK
	check.color = Palette.ACCENT
	check.stroke_width = 3.0
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	check.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	check.offset_left = -(check_size + 16.0)
	check.offset_top = 16.0
	check.offset_right = -16.0
	check.offset_bottom = 16.0 + check_size
	return check


func _on_level_pressed(level_id: int) -> void:
	# Kaydirma jesti butonun uzerinde bitmis olabilir; hemen ardindan gelen
	# basisi bolum acma niyeti saymayiz.
	if Time.get_ticks_msec() - _last_scroll_msec < scroll_guard_msec:
		return
	if not progress.is_unlocked(level_id) and not debug_force_unlock:
		return
	level_selected.emit(level_id)
