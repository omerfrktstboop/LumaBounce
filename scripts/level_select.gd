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
@export var button_size := Vector2(100.0, 100.0)
@export var button_font_size := 32
@export var columns := 4
@export var check_size := 24.0
@export var lock_size := 24.0
## Buton icindeki mini yildiz satiri.
@export var button_star_radius := 8.5
@export var button_star_spacing := 5.0
## Yildiz kapisi yuzunden kilitli butondaki "34 / 40" bilgisi.
@export var gate_font_size := 18
@export var gate_star_radius := 7.0
## Kilitli bolumlerde yildizlar tamamen gizlenmez, kisilir - grid'in
## dikey ritmi bozulmasin ve "burada da yildiz var" bilgisi kalsin.
@export_range(0.0, 1.0, 0.05) var locked_star_alpha := 0.25
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
@onready var _star_total: Label = $SafeArea/Content/StarTotal
@onready var _back_button: LumaButton = $SafeArea/Content/BackButton

var _last_scroll_msec := -100000


func _ready() -> void:
	if progress == null:
		progress = ProgressStore.load_from_disk()
	_grid.columns = columns
	_build_buttons()
	_refresh_star_total()
	_back_button.pressed.connect(menu_requested.emit)
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)
	_animate_buttons_entry()

func _animate_buttons_entry() -> void:
	for i in range(_grid.get_child_count()):
		var btn = _grid.get_child(i)
		btn.modulate.a = 0.0
		var tw = create_tween()
		tw.tween_property(btn, "modulate:a", 1.0, 0.4).set_delay(i * 0.015).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Ustte sade toplam: "34 / 150". Yeni panel acilmaz, mevcut baslik
## seridinin altina tek satir eklenir.
func _refresh_star_total() -> void:
	_star_total.text = "%d / %d" % [progress.get_total_stars(), progress.get_max_available_stars()]


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
	if not unlocked:
		button.add_child(_make_lock_mark())

	# Yildiz kapisi yuzunden kilitliyse alt satirda yildizlar yerine kapinin
	# durumu gosterilir: o yildiz satiri zaten 0 gosterecekti, oysa oyuncunun
	# ihtiyaci olan bilgi "daha kac yildiz gerekiyor".
	var gate := progress.get_star_gate_progress(level_id)
	if not unlocked and gate.y > 0:
		button.add_child(_make_gate_row(gate))
	else:
		button.add_child(_make_button_stars(level_id, unlocked))

	return button


## Butonun alt kenarinda mini yildiz satiri. Kilitliyken kisilir.
func _make_button_stars(level_id: int, unlocked: bool) -> StarRow:
	var stars := StarRow.new()
	stars.name = "Stars"
	stars.star_radius = button_star_radius
	stars.spacing = button_star_spacing
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked:
		stars.modulate.a = locked_star_alpha
	stars.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	stars.offset_left = 0.0
	stars.offset_top = -(button_star_radius * 2.0 + 16.0)
	stars.offset_right = 0.0
	stars.offset_bottom = -8.0
	# set_stars sadece dolu sayisini ayarlar; StarRow._ready henuz calismadigi
	# icin deger saklanir ve ilk cizimde uygulanir.
	stars.set_stars(progress.get_level_stars(level_id))
	return stars


## "34 / 40 *" satiri. Yildiz karakteri metin olarak yazilmaz - projede hicbir
## yerde harici font/asset varsayimi yok, bu yuzden yildiz yine prosedurel
## StarRow ile cizilir (tek yildiz, dolu).
func _make_gate_row(gate: Vector2i) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "StarGate"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)
	row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_left = 0.0
	row.offset_top = -(float(gate_font_size) + 16.0)
	row.offset_right = 0.0
	row.offset_bottom = -8.0

	var label := Label.new()
	label.text = "%d / %d" % [gate.x, gate.y]
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", gate_font_size)
	label.add_theme_color_override("font_color", Palette.ACCENT_DIM)
	row.add_child(label)

	var star := StarRow.new()
	star.star_count = 1
	star.star_radius = gate_star_radius
	star.spacing = 0.0
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star.set_stars(1)
	row.add_child(star)

	return row


## Kilitli bolum isareti. Butonun solgunlugu tek basina "neden basamiyorum"
## sorusunu yanitlamiyordu.
func _make_lock_mark() -> GlyphIcon:
	var lock := GlyphIcon.new()
	lock.name = "LockMark"
	lock.glyph = GlyphIcon.Glyph.LOCK
	lock.color = Color(Palette.TEXT_DIM, 0.75)
	lock.stroke_width = 2.6
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	lock.offset_left = -(lock_size + 16.0)
	lock.offset_top = 16.0
	lock.offset_right = -16.0
	lock.offset_bottom = 16.0 + lock_size
	return lock


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
