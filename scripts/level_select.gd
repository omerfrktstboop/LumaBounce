class_name LevelSelect
extends Control

## Bolum secim ekrani - DUNYA SAYFALARI.
##
## Ekran hicbir sahneyi kendisi acmaz, yalnizca sinyal yayar; ilerleme
## AppRoot tarafindan add_child'dan ONCE enjekte edilir.
##
## NEDEN SAYFALI: onceki hali 125 butonu tek bir kesintisiz akista
## gosteriyordu. Yapi yoktu (53. bolum 8. bolumden ayirt edilemiyordu) ve
## oyunun her 50 bolumde degisen TEMASI bu ekranda hic gorunmuyordu -
## PaletteThemes yalnizca oynanis kurulurken uygulaniyordu, dolayisiyla
## 8. ve 80. bolum butonu birebir aynidi. Simdi her dunya kendi sayfasi ve
## kendi rengi: sekmeler, butonlar, yildizlar ve zemin o dunyanin vurgusunu
## tasir.
##
## RENK NASIL TASINIR: Palette global bir static var'dir; onu degistirmek tum
## ekrani birden boyar ve ustelik sekme cubugunda uc dunya AYNI ANDA temsil
## edilir. Bu yuzden renk butona/yildiza VERI olarak gecirilir
## (LumaButton.accent_override, StarRow.filled_color).
##
## Bant sinirlari burada tanimli DEGIL: tek kaynak LevelWorlds. Oyunun
## temasiyla listenin sayfalari ayni sinirlari kullanmak zorunda.

signal level_selected(level_id: int)
signal menu_requested()

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
## Kaydirma bittikten sonra bu sure boyunca bolum secimi yok sayilir; parmak
## kaydirirken butonun uzerinde birakildiginda yanlislikla bolum acilmasin.
@export var scroll_guard_msec := 220

@export_group("Sayfa gecisi")
## Sayfa kayma animasyonu. Yon degisimin yonunu takip eder, boylece "sagdaki
## dunyaya gectim" hissi olusur.
@export var page_slide_time := 0.26
## Yatay surukleme bu mesafeyi gecerse dunya degisir.
@export var swipe_threshold := 70.0
## Yatay hareket dikeyin bu kati kadar baskin olmali. Aksi halde oyuncu
## listeyi kaydirmak istiyordur; dikey kaydirma her zaman onceliklidir.
@export var swipe_dominance := 1.4

@export_group("Giris animasyonu")
## Butonlarin belirmesi arasindaki TOPLAM kayma. Bolum SAYISINA gore
## sikistirilir, boylece bir dunyada 50 de olsa 100 de olsa acilis ayni surer.
@export var entry_stagger_total := 0.55
@export var entry_stagger_max := 0.015
@export var entry_fade_time := 0.34

## AppRoot tarafindan add_child'dan ONCE atanir.
var progress: ProgressStore
## Yalnizca debug paneli tarafindan kullanilir. true iken gercek save
## dosyasina HICBIR SEKILDE dokunmadan tum bolumleri secilebilir gosterir.
var debug_force_unlock := false

@onready var _background: InkBackground = $Background
@onready var _tabs: HBoxContainer = $SafeArea/Content/Tabs
@onready var _world_stars: Label = $SafeArea/Content/WorldStars
@onready var _page_clip: Control = $SafeArea/Content/PageClip
@onready var _scroll: ScrollContainer = $SafeArea/Content/PageClip/GridScroll
@onready var _grid: GridContainer = $SafeArea/Content/PageClip/GridScroll/GridHolder/Grid
@onready var _top_fade: Control = $SafeArea/Content/PageClip/TopFade
@onready var _bottom_fade: Control = $SafeArea/Content/PageClip/BottomFade
@onready var _back_button: LumaButton = $SafeArea/Content/BackButton

var _world := 0
var _last_scroll_msec := -100000
var _slide_tween: Tween
## Yatay surukleme takibi (bkz. _input). -1 = surukleme yok.
var _drag_start := Vector2.ZERO
var _drag_active := false
var _drag_consumed := false


func _ready() -> void:
	if progress == null:
		progress = ProgressStore.load_from_disk()
	_grid.columns = columns
	_back_button.pressed.connect(menu_requested.emit)
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)

	# Oyuncunun kaldigi bolumun dunyasi acilir; 125 bolumde her seferinde
	# en ustten baslayip elle kaydirmak yorucu.
	_world = LevelWorlds.index_for_level(progress.get_resume_level_id())
	_build_tabs()
	_show_world(_world, 0)


# --- Dunya sayfalari ----------------------------------------------------------

func _build_tabs() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()

	for i in LevelWorlds.count():
		var index := i
		var tab := LumaButton.new()
		tab.name = "Tab%d" % index
		tab.text = LevelWorlds.display_name(index)
		tab.custom_minimum_size = Vector2(0.0, 52.0)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.corner_radius = 16
		tab.content_margin = Vector2(8.0, 8.0)
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override("font_size", 19)
		# Sekme, TEMSIL ETTIGI dunyanin rengini tasir - secili olmasa bile.
		# Boylece oyuncu daha dokunmadan "ileride baska bir renk var" bilgisini
		# alir; tema degisimi bir surpriz degil, bir vaat olur.
		tab.accent_override = LevelWorlds.accent_for_index(index)
		tab.pressed.connect(_on_tab_pressed.bind(index))
		_tabs.add_child(tab)
	_refresh_tab_states()


## Sekmenin VURGUSU kendi dunyasinindir ama YUZEYI acik sayfanindir: uc
## sekme de ayni zeminin uzerinde durur, farkli dolgular kolaj gibi gorunurdu.
func _refresh_tab_states() -> void:
	var surface := LevelWorlds.theme_for_index(_world).SURFACE
	for i in _tabs.get_child_count():
		var tab := _tabs.get_child(i) as LumaButton
		if tab != null:
			tab.surface_override = surface
			tab.emphasis = (LumaButton.Emphasis.PRIMARY if i == _world
				else LumaButton.Emphasis.SECONDARY)


func _on_tab_pressed(index: int) -> void:
	if index == _world:
		return
	_show_world(index, signi(index - _world))


## [param direction] kayma yonu: +1 sagdaki dunyaya, -1 soldakine, 0 animasyonsuz.
func _show_world(index: int, direction: int) -> void:
	_world = clampi(index, 0, LevelWorlds.count() - 1)
	_refresh_tab_states()
	_apply_world_colors()
	_build_buttons()
	_refresh_world_stars()
	_scroll_to_current_level()

	if direction == 0:
		_animate_buttons_entry()
		return
	_slide_page(direction)


## Yeni sayfa, gelinen yonun tersinden kayarak girer.
func _slide_page(direction: int) -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	var offset := _page_clip.size.x * float(direction)
	_scroll.position.x = offset
	_slide_tween = create_tween()
	_slide_tween.tween_property(_scroll, "position:x", 0.0, page_slide_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Sekmeler, zemin ve yildizlar disinda BUTONLARIN rengi _make_level_button
## icinde verilir; burada ekranin geri kalani boyanir.
func _apply_world_colors() -> void:
	var world_theme := LevelWorlds.theme_for_index(_world)
	_world_stars.add_theme_color_override("font_color", world_theme.ACCENT)
	# Zemin de dunyaya gore degisir, yalnizca vurgu degil: sadece vurgu
	# degistiginde sayfalar neredeyse ayni gorunuyordu. Renkler temanin
	# KENDI murekkep tonlaridir, uzerine atilmis bir tint degil - boylece
	# liste, o dunyanin oynanisiyla ayni zemini gosterir.
	_background.apply_ink(world_theme.INK_TOP, world_theme.INK_MID, world_theme.INK_BOTTOM)
	# Solma serifleri zeminle AYNI tonu kullanmali, yoksa gecis bir bant
	# gibi okunur.
	# GERI dugmesi de sayfanin yuzeyini alir, yoksa yeni zeminin uzerinde
	# eski dunyanin lacivert dolgusuyla yapistirilmis gorunur.
	_back_button.surface_override = world_theme.SURFACE
	_top_fade.set("color", world_theme.INK_TOP)
	_bottom_fade.set("color", world_theme.INK_BOTTOM)


func _refresh_world_stars() -> void:
	var earned := 0
	for level_id in range(LevelWorlds.first_level(_world), LevelWorlds.last_level(_world) + 1):
		earned += progress.get_level_stars(level_id)
	var possible := LevelWorlds.level_count(_world) * ProgressStore.MAX_STARS_PER_LEVEL
	_world_stars.text = "%d / %d" % [earned, possible]


func _build_buttons() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

	for level_id in range(LevelWorlds.first_level(_world), LevelWorlds.last_level(_world) + 1):
		_grid.add_child(_make_level_button(level_id))


## Oyuncunun kaldigi bolum bu sayfadaysa, o satir gorunur olacak sekilde
## kaydirilir. Baska bir dunyadaysa sayfa bastan baslar.
func _scroll_to_current_level() -> void:
	var resume := progress.get_resume_level_id()
	if LevelWorlds.index_for_level(resume) != _world:
		_scroll.scroll_vertical = 0
		return
	var offset := resume - LevelWorlds.first_level(_world)
	var row := int(float(offset) / float(maxi(columns, 1)))
	var row_height := button_size.y + 20.0
	# Bir satir yukarida birak: hedef satirin ustunde baglam kalsin, ekranin
	# en ust kenarina yapismis bir buton "liste burada basliyor" gibi okunur.
	var target := maxf(float(row - 1) * row_height, 0.0)
	# Grid henuz yerlesmedigi icin dogrudan atamak calismaz; bir kare beklenir.
	# Signal baglantisi, ekran bu arada silinirse otomatik olarak kopar ve
	# serbest birakilmis instance icinde coroutine resume edilmeye calisilmaz.
	get_tree().process_frame.connect(_apply_scroll.bind(target), CONNECT_ONE_SHOT)


func _apply_scroll(target: float) -> void:
	if not is_inside_tree():
		return
	_scroll.scroll_vertical = int(target)


func _animate_buttons_entry() -> void:
	var count := _grid.get_child_count()
	if count <= 0:
		return
	var step := minf(entry_stagger_max, entry_stagger_total / float(count))
	for i in count:
		var button := _grid.get_child(i) as Control
		button.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(button, "modulate:a", 1.0, entry_fade_time) \
			.set_delay(float(i) * step) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# --- Kaydirma ve jest ---------------------------------------------------------

func _on_scrolled(_value: float) -> void:
	_last_scroll_msec = Time.get_ticks_msec()


## Yatay surukleme dunya degistirir. _input kullanilir cunku ScrollContainer
## surukleme olaylarini kendi icin tuketiyor; _input GUI'den ONCE cagrilir.
##
## DIKEY KAYDIRMA HER ZAMAN ONCELIKLI: yalnizca yatay hareket dikeyden
## belirgin olcude (swipe_dominance) baskin oldugunda dunya degisir. Aksi
## halde listeyi kaydirmaya calisan oyuncu istemeden sayfa degistirirdi.
func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_begin_drag(touch.position)
		else:
			_end_drag()
		return

	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_begin_drag(button.position)
		else:
			_end_drag()
		return

	var drag := event as InputEventScreenDrag
	if drag != null:
		_update_drag(drag.position)
		return

	var motion := event as InputEventMouseMotion
	if motion != null and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_update_drag(motion.position)


func _begin_drag(pointer_position: Vector2) -> void:
	_drag_active = _page_clip.get_global_rect().has_point(pointer_position)
	_drag_start = pointer_position
	_drag_consumed = false


func _update_drag(pointer_position: Vector2) -> void:
	if not _drag_active or _drag_consumed:
		return
	var delta := pointer_position - _drag_start
	if absf(delta.x) < swipe_threshold:
		return
	if absf(delta.x) < absf(delta.y) * swipe_dominance:
		return
	var direction := signi(int(-delta.x))
	var wanted := _world + direction
	_drag_consumed = true
	# Kaydirma korumasi: jest bir butonun uzerinde bitse bile bolum acilmasin.
	_last_scroll_msec = Time.get_ticks_msec()
	if wanted < 0 or wanted >= LevelWorlds.count():
		return
	_show_world(wanted, direction)


func _end_drag() -> void:
	_drag_active = false


# --- Butonlar -----------------------------------------------------------------

## Debug panelinden calisma zamaninda cagrilir.
func set_debug_force_unlock(enabled: bool) -> void:
	debug_force_unlock = enabled
	if is_node_ready():
		_build_buttons()
		_refresh_world_stars()


func _make_level_button(level_id: int) -> LumaButton:
	var unlocked := progress.is_unlocked(level_id) or debug_force_unlock
	var completed := progress.is_completed(level_id)
	var accent := LevelWorlds.accent_for_index(_world)

	var button := LumaButton.new()
	button.name = "Level%02d" % level_id
	button.text = str(level_id)
	button.custom_minimum_size = button_size
	button.corner_radius = 28
	button.content_margin = Vector2(10.0, 10.0)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not unlocked
	button.accent_override = accent
	button.surface_override = LevelWorlds.theme_for_index(_world).SURFACE
	# Tamamlanan bolum, birincil vurgu (dunyanin renginde kenar) ile isaretlenir.
	button.emphasis = LumaButton.Emphasis.PRIMARY if completed else LumaButton.Emphasis.SECONDARY
	button.add_theme_font_size_override("font_size", button_font_size)
	button.pressed.connect(_on_level_pressed.bind(level_id))

	if completed:
		button.add_child(_make_check_mark(accent))
	if not unlocked:
		button.add_child(_make_lock_mark())

	# Yildiz kapisi yuzunden kilitliyse kapinin durumu gosterilir: oyuncunun
	# ihtiyaci olan bilgi "daha kac yildiz gerekiyor".
	#
	# Kilitli ve kapisi olmayan bolumde ALT SATIR HIC CIZILMEZ: orada yildiz
	# satiri her zaman 0/3 gosteriyordu, yani yer kapliyor ama bilgi
	# tasimiyordu. Kilit simgesi "buraya henuz gelmedin"i zaten soyluyor.
	var gate := progress.get_star_gate_progress(level_id)
	if not unlocked:
		if gate.y > 0:
			button.add_child(_make_gate_row(gate, accent))
	else:
		button.add_child(_make_button_stars(level_id, accent))

	return button


## Butonun alt kenarinda mini yildiz satiri (yalnizca acik bolumlerde).
func _make_button_stars(level_id: int, accent: Color) -> StarRow:
	var stars := StarRow.new()
	stars.name = "Stars"
	stars.star_radius = button_star_radius
	stars.spacing = button_star_spacing
	stars.filled_color = accent
	stars.filled_core_color = LevelWorlds.accent_core_for_index(_world)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	stars.offset_left = 0.0
	stars.offset_top = -(button_star_radius * 2.0 + 16.0)
	stars.offset_right = 0.0
	stars.offset_bottom = -8.0
	stars.set_stars(progress.get_level_stars(level_id))
	return stars


## "34 / 40 *" satiri. Yildiz karakteri metin olarak yazilmaz - projede hicbir
## yerde harici font/asset varsayimi yok, bu yuzden yildiz prosedurel StarRow
## ile cizilir.
func _make_gate_row(gate: Vector2i, accent: Color) -> HBoxContainer:
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
	label.add_theme_color_override("font_color", LevelWorlds.accent_dim_for_index(_world))
	row.add_child(label)

	var star := StarRow.new()
	star.star_count = 1
	star.star_radius = gate_star_radius
	star.spacing = 0.0
	star.filled_color = accent
	star.filled_core_color = LevelWorlds.accent_core_for_index(_world)
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


## "Tamamlandi" isareti: kucuk, sade bir onay imi - dunyanin renginde.
func _make_check_mark(accent: Color) -> GlyphIcon:
	var check := GlyphIcon.new()
	check.name = "CompletedMark"
	check.glyph = GlyphIcon.Glyph.CHECK
	check.color = accent
	check.stroke_width = 3.0
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	check.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	check.offset_left = -(check_size + 16.0)
	check.offset_top = 16.0
	check.offset_right = -16.0
	check.offset_bottom = 16.0 + check_size
	return check


func _on_level_pressed(level_id: int) -> void:
	# Kaydirma/kaydirma jesti butonun uzerinde bitmis olabilir; hemen ardindan
	# gelen basisi bolum acma niyeti saymayiz.
	if Time.get_ticks_msec() - _last_scroll_msec < scroll_guard_msec:
		return
	if not progress.is_unlocked(level_id) and not debug_force_unlock:
		return
	level_selected.emit(level_id)
