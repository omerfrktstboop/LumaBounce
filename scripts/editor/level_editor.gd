class_name LevelEditor
extends Node2D

## Oyun ici bolum editoru - YALNIZCA debug build'de erisilir.
##
## Ayri bir "admin APK" yok: ekran debug panelinden acilir, o panel de
## release export'ta kendini agactan siler (bkz. debug_panel.gd). Tek proje,
## tek imzalama, tek surum takibi.
##
## Onizleme gercek sahnelerden kurulur (LevelWorld), yani editorde gordugun
## panel/blok oynarken carptigin panelin AYNISIDIR. Analiz de oynanisin
## fizigini kullanan LevelSolver ile yapilir; "editorde gecti, oyunda gecmedi"
## durumu bu yuzden olusamaz.
##
## KAYIT: export edilmis APK'da res:// salt okunurdur, bu yuzden tasarlanan
## bolum user:// altina yazilir ve metni panoya kopyalanabilir - repoya
## tasimanin en az surtunmeli yolu bu. Masaustunde dogrudan res://levels/
## icine de yazilabilir (bkz. CustomLevelStore).

signal test_requested(level: LevelData)
signal menu_requested()

enum Selection { NONE, PANEL, BLOCK, TARGET, LAUNCHER, LEFT_WALL, RIGHT_WALL }

## Ince ayar adimlari. Dokunmatikte surukleme kaba, stepper hassas olsun.
const ANGLE_STEP := 2.0
const SIZE_STEP := 20.0
const WALL_STEP := 20.0
const MIN_PANEL_LENGTH := 120.0
const MAX_PANEL_LENGTH := 560.0
const MIN_BLOCK_WIDTH := 80.0
const MAX_BLOCK_WIDTH := 620.0
const BLOCK_HEIGHT := 44.0
## Duvar bosluklarinin editordeki varsayilan araligi.
const DEFAULT_GAP := Vector2(420.0, 740.0)

## AppRoot tarafindan add_child'dan ONCE atanabilir; bos birakilirsa bos bir
## bolumle baslanir.
var level: LevelData

@onready var _world: LevelWorld = $World
@onready var _camera: Camera2D = $EditorCamera
@onready var _info: Label = $HUD/SafeArea/Root/BottomPanel/Rows/InfoLabel
@onready var _bottom: PanelContainer = $HUD/SafeArea/Root/BottomPanel
@onready var _modal: Control = $HUD/Modal
@onready var _modal_title: Label = $HUD/Modal/Card/Rows/Title
@onready var _modal_status: Label = $HUD/Modal/Card/Rows/Status
@onready var _modal_list: VBoxContainer = $HUD/Modal/Card/Rows/Scroll/List

var _solver: LevelSolver
var _generator: LevelGenerator
var _target_preview: Node2D
var _launcher_preview: Node2D

var _selection := Selection.NONE
var _selected_index := -1
var _dragging := false
var _drag_offset := Vector2.ZERO
var _active_touch := -1
## Uretecin son sonuclari; listeden secilince editore yuklenir.
var _generated: Array[LevelData] = []
var _status_text := ""


func _ready() -> void:
	if level == null:
		level = _make_blank_level()

	_solver = LevelSolver.from_scenes()
	_generator = LevelGenerator.new()
	_generator.name = "Generator"
	add_child(_generator)
	_generator.candidate_evaluated.connect(_on_candidate_evaluated)
	_generator.finished.connect(_on_generation_finished)

	_build_previews()
	_connect_buttons()
	get_viewport().size_changed.connect(_position_camera)
	_position_camera()
	_modal.hide()
	_rebuild()


## Oynanisla AYNI cerceveleme: yatayda oyun alani ortali, dikeyde alt kenara
## hizali. Editorde gordugun kadraj oyunda gordugun kadrajdir.
func _position_camera() -> void:
	var play_rect := _world.get_play_rect()
	var visible_size := get_viewport_rect().size
	_camera.position = Vector2(
		play_rect.position.x + play_rect.size.x * 0.5,
		play_rect.position.y + play_rect.size.y - visible_size.y * 0.5)


func _build_previews() -> void:
	# Gercek sahneler kullanilir; hedefin Area2D'si "ball" grubunda cisim
	# olmadigi icin editorde hicbir sey tetiklemez.
	_target_preview = (load("res://scenes/target.tscn") as PackedScene).instantiate()
	_target_preview.z_index = 2
	add_child(_target_preview)

	_launcher_preview = (load("res://scenes/launcher.tscn") as PackedScene).instantiate()
	_launcher_preview.z_index = 4
	add_child(_launcher_preview)


func _connect_buttons() -> void:
	var rows := "HUD/SafeArea/Root/BottomPanel/Rows/"
	get_node(rows + "AddRow/AddPanel").pressed.connect(_on_add_panel)
	get_node(rows + "AddRow/AddBlock").pressed.connect(_on_add_block)
	get_node(rows + "AddRow/DeleteItem").pressed.connect(_on_delete)
	get_node(rows + "AddRow/CycleWall").pressed.connect(_on_cycle_wall)

	get_node(rows + "TuneRow/AMinus").pressed.connect(_on_tune.bind(0, -1))
	get_node(rows + "TuneRow/APlus").pressed.connect(_on_tune.bind(0, 1))
	get_node(rows + "TuneRow/BMinus").pressed.connect(_on_tune.bind(1, -1))
	get_node(rows + "TuneRow/BPlus").pressed.connect(_on_tune.bind(1, 1))

	get_node(rows + "ActionRow/TestButton").pressed.connect(_on_test)
	get_node(rows + "ActionRow/AnalyseButton").pressed.connect(_on_analyse)
	get_node(rows + "ActionRow/GenerateButton").pressed.connect(_on_open_generator)
	get_node(rows + "ActionRow/SaveButton").pressed.connect(_on_save)

	$HUD/SafeArea/Root/TopBar/BackButton.pressed.connect(menu_requested.emit)
	$HUD/SafeArea/Root/TopBar/OpenButton.pressed.connect(_on_open_saved)
	$HUD/SafeArea/Root/TopBar/CollapseButton.pressed.connect(_on_toggle_panel)
	$HUD/Modal/Card/Rows/CloseButton.pressed.connect(_on_modal_close)


# --- Onizlemeyi veriden kurma -------------------------------------------------

## Yapisal her degisiklikten sonra cagrilir (ekleme, silme, bolum yukleme).
## Surukleme sirasinda cagrilmaz - orada yalnizca ilgili dugum oynatilir.
func _rebuild() -> void:
	_world.build(level)
	_target_preview.position = level.target_position
	_launcher_preview.position = level.launcher_position
	_refresh_info()
	queue_redraw()


func _refresh_info() -> void:
	var lines := PackedStringArray()
	lines.append("%d panel  %d blok  |  %d can" % [
		level.panels.size(), level.breakable_blocks.size(), level.max_lives])
	lines.append(_selection_text())
	if not _status_text.is_empty():
		lines.append(_status_text)
	_info.text = "\n".join(lines)


## Stepper'lar secime gore anlam degistirir; ne yaptiklari burada yazili
## olmazsa dort isimsiz dugmeye donerler.
func _selection_text() -> String:
	match _selection:
		Selection.PANEL:
			var panel := level.panels[_selected_index]
			return "Panel %d — A: açı %.0f°   B: uzunluk %.0f" % [
				_selected_index + 1, panel.rotation_degrees, panel.length]
		Selection.BLOCK:
			var block := level.breakable_blocks[_selected_index]
			return "Blok %d — A: açı %.0f°   B: genişlik %.0f" % [
				_selected_index + 1, block.rotation_degrees, block.size.x]
		Selection.TARGET:
			return "Hedef — sürükleyerek taşı (%.0f, %.0f)" % [
				level.target_position.x, level.target_position.y]
		Selection.LAUNCHER:
			return "Fırlatıcı — sürükleyerek taşı (%.0f, %.0f)" % [
				level.launcher_position.x, level.launcher_position.y]
		Selection.LEFT_WALL, Selection.RIGHT_WALL:
			var gap := _wall_gap(_selection)
			var side := "Sol" if _selection == Selection.LEFT_WALL else "Sağ"
			if gap == Vector2.ZERO:
				return "%s kenar kapalı — Kenar ile aç" % side
			return "%s kenar boşluğu — A: üst %.0f   B: alt %.0f" % [side, gap.x, gap.y]
		_:
			return "Bir öğeye dokun ya da yeni ekle"


# --- Girdi --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _modal.visible:
		return

	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed and _active_touch < 0:
			_active_touch = touch.index
			_pointer_down(touch.position)
		elif not touch.pressed and touch.index == _active_touch:
			_active_touch = -1
			_dragging = false
		return

	var drag := event as InputEventScreenDrag
	if drag != null and drag.index == _active_touch:
		_pointer_move(drag.position)
		return

	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_pointer_down(button.position)
		else:
			_dragging = false
		return

	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_pointer_move(motion.position)


func _pointer_down(viewport_position: Vector2) -> void:
	if _bottom.visible and _bottom.get_global_rect().has_point(viewport_position):
		return
	var world := _to_world(viewport_position)
	_select_at(world)
	if _selection != Selection.NONE and _selection_is_movable():
		_dragging = true
		_drag_offset = _selected_position() - world
	_refresh_info()
	queue_redraw()


func _pointer_move(viewport_position: Vector2) -> void:
	if not _dragging or not _selection_is_movable():
		return
	var target := _to_world(viewport_position) + _drag_offset
	# Oyun alani disina tasarim yapilamaz.
	var rect := _world.get_play_rect()
	target.x = clampf(target.x, rect.position.x, rect.end.x)
	target.y = clampf(target.y, rect.position.y, rect.end.y)
	_set_selected_position(target)
	_refresh_info()
	queue_redraw()


func _to_world(viewport_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * viewport_position


## En yakin ogeyi secer. Kucuk ogelerin buyuk olanlarin altinda kaybolmamasi
## icin mesafeye gore siralanir, ust uste binenlerde en yakini kazanir.
func _select_at(world: Vector2) -> void:
	var best_distance := 90.0
	var best_selection := Selection.NONE
	var best_index := -1

	for i in level.panels.size():
		var distance := world.distance_to(level.panels[i].position)
		if distance < best_distance:
			best_distance = distance
			best_selection = Selection.PANEL
			best_index = i

	for i in level.breakable_blocks.size():
		var distance := world.distance_to(level.breakable_blocks[i].position)
		if distance < best_distance:
			best_distance = distance
			best_selection = Selection.BLOCK
			best_index = i

	var target_distance := world.distance_to(level.target_position)
	if target_distance < best_distance:
		best_distance = target_distance
		best_selection = Selection.TARGET
		best_index = -1

	var launcher_distance := world.distance_to(level.launcher_position)
	if launcher_distance < best_distance:
		best_selection = Selection.LAUNCHER
		best_index = -1

	_selection = best_selection
	_selected_index = best_index


func _selection_is_movable() -> bool:
	return _selection in [
		Selection.PANEL, Selection.BLOCK, Selection.TARGET, Selection.LAUNCHER]


func _selected_position() -> Vector2:
	match _selection:
		Selection.PANEL:
			return level.panels[_selected_index].position
		Selection.BLOCK:
			return level.breakable_blocks[_selected_index].position
		Selection.TARGET:
			return level.target_position
		Selection.LAUNCHER:
			return level.launcher_position
	return Vector2.ZERO


func _set_selected_position(value: Vector2) -> void:
	match _selection:
		Selection.PANEL:
			level.panels[_selected_index].position = value
			var panel := _world.get_panel_node(_selected_index)
			if panel != null:
				panel.position = value
		Selection.BLOCK:
			level.breakable_blocks[_selected_index].position = value
			var block := _world.get_block_node(_selected_index)
			if block != null:
				block.position = value
		Selection.TARGET:
			level.target_position = value
			_target_preview.position = value
		Selection.LAUNCHER:
			level.launcher_position = value
			_launcher_preview.position = value


# --- Araclar ------------------------------------------------------------------

func _on_add_panel() -> void:
	var panel := PanelData.new()
	panel.position = _free_spot()
	panel.rotation_degrees = 0.0
	panel.length = 280.0
	panel.thickness = 26.0
	level.panels.append(panel)
	_selection = Selection.PANEL
	_selected_index = level.panels.size() - 1
	_status_text = ""
	_rebuild()


func _on_add_block() -> void:
	var block := BreakableBlockData.new()
	block.position = _free_spot()
	block.rotation_degrees = 0.0
	block.size = Vector2(220.0, BLOCK_HEIGHT)
	level.breakable_blocks.append(block)
	_selection = Selection.BLOCK
	_selected_index = level.breakable_blocks.size() - 1
	_status_text = ""
	_rebuild()


## Yeni ogeler ust uste binmesin diye her ekleyiste biraz kaydirilir.
func _free_spot() -> Vector2:
	var count := level.panels.size() + level.breakable_blocks.size()
	return Vector2(300.0 + float(count % 3) * 60.0, 700.0 - float(count % 4) * 70.0)


func _on_delete() -> void:
	if _selection == Selection.PANEL:
		level.panels.remove_at(_selected_index)
	elif _selection == Selection.BLOCK:
		level.breakable_blocks.remove_at(_selected_index)
	else:
		return
	_selection = Selection.NONE
	_selected_index = -1
	_status_text = ""
	_rebuild()


## Kenar bosluklari ayri bir ekran istemesin diye secim dongusune katilir:
## dokun -> sol kenar, tekrar dokun -> sag kenar, tekrar -> secimi birak.
func _on_cycle_wall() -> void:
	match _selection:
		Selection.LEFT_WALL:
			_selection = Selection.RIGHT_WALL
		Selection.RIGHT_WALL:
			_selection = Selection.NONE
		_:
			_selection = Selection.LEFT_WALL
	_selected_index = -1
	_refresh_info()
	queue_redraw()


func _on_tune(axis: int, direction: int) -> void:
	match _selection:
		Selection.PANEL:
			var panel := level.panels[_selected_index]
			if axis == 0:
				panel.rotation_degrees = wrapf(
					panel.rotation_degrees + ANGLE_STEP * direction, -90.0, 90.0)
			else:
				panel.length = clampf(
					panel.length + SIZE_STEP * direction, MIN_PANEL_LENGTH, MAX_PANEL_LENGTH)
		Selection.BLOCK:
			var block := level.breakable_blocks[_selected_index]
			if axis == 0:
				block.rotation_degrees = wrapf(
					block.rotation_degrees + ANGLE_STEP * direction, -90.0, 90.0)
			else:
				block.size.x = clampf(
					block.size.x + SIZE_STEP * direction, MIN_BLOCK_WIDTH, MAX_BLOCK_WIDTH)
		Selection.LEFT_WALL, Selection.RIGHT_WALL:
			_tune_wall(axis, direction)
		_:
			return
	_status_text = ""
	_rebuild()


func _tune_wall(axis: int, direction: int) -> void:
	var gap := _wall_gap(_selection)
	if gap == Vector2.ZERO:
		gap = DEFAULT_GAP
	if axis == 0:
		gap.x = clampf(gap.x + WALL_STEP * direction, 0.0, gap.y - WALL_STEP)
	else:
		gap.y = clampf(gap.y + WALL_STEP * direction, gap.x + WALL_STEP, 1280.0)
	_set_wall_gap(_selection, gap)


## Segment dizisini editorde tek bir "bosluk" olarak modelleriz: bugune kadar
## tasarlanan her bolum kenar basina en fazla bir aciklik kullaniyor ve iki
## sayi ile dusunmek dizi duzenlemekten cok daha kolay.
func _wall_gap(side: int) -> Vector2:
	var segments := level.left_wall_segments if side == Selection.LEFT_WALL \
		else level.right_wall_segments
	if segments.size() < 2:
		return Vector2.ZERO
	return Vector2(segments[0].y, segments[1].x)


func _set_wall_gap(side: int, gap: Vector2) -> void:
	var segments: Array[Vector2] = [
		Vector2(-320.0, gap.x),
		Vector2(gap.y, 1440.0),
	]
	if side == Selection.LEFT_WALL:
		level.left_wall_segments = segments
	else:
		level.right_wall_segments = segments


# --- Eylemler -----------------------------------------------------------------

func _on_test() -> void:
	test_requested.emit(level)


## Oynanisin fizigiyle olcum. Kisa bir donma olur (birkac bin simulasyon),
## bu yuzden once "olculuyor" yazilir ve bir kare beklenir.
func _on_analyse() -> void:
	_status_text = "Ölçülüyor..."
	_refresh_info()
	await get_tree().process_frame
	await get_tree().physics_frame

	_solver.bind_space(_world.get_space(), _world.get_block_rids())
	var spawn := _solver.spawn_position(level.launcher_position)
	var play_rect := _world.get_play_rect()
	var none: Array[RID] = []

	var free_scan := _solver.scan(spawn, level.target_position, play_rect,
		none, LevelGenerator.FINE_ANGLE_STEP, LevelGenerator.FINE_POWER_STEP)
	var free_robust := int(LevelSolver.analyse_robust(free_scan)["robust"])
	var free_bounces := int(LevelSolver.analyse_robust(free_scan)["bounces"])

	if level.breakable_blocks.is_empty():
		_status_text = "Bloksuz: %d isabet, %d sağlam hücre, %d sekme" % [
			int(free_scan["hit_count"]), free_robust, free_bounces]
		_refresh_info()
		return

	var all_broken := (1 << level.breakable_blocks.size()) - 1
	var open_scan := _solver.scan(spawn, level.target_position, play_rect,
		_world.rids_for_state(all_broken),
		LevelGenerator.FINE_ANGLE_STEP, LevelGenerator.FINE_POWER_STEP)
	var open_robust := int(LevelSolver.analyse_robust(open_scan)["robust"])
	_status_text = "Bloksuz %d sağlam | Bloklar kırık %d sağlam%s" % [
		free_robust, open_robust,
		"" if open_robust > free_robust else "  (blok kolaylaştırmıyor!)"]
	_refresh_info()


func _on_save() -> void:
	var level_name := "bolum_%s" % Time.get_datetime_string_from_system().replace(":", "")
	var path := CustomLevelStore.save(level, level_name)
	var copied := CustomLevelStore.copy_to_clipboard(level)
	if path.is_empty():
		_status_text = "Kaydedilemedi."
	elif copied:
		_status_text = "Kaydedildi + panoya kopyalandı: %s" % level_name
	else:
		_status_text = "Kaydedildi: %s (pano başarısız)" % level_name
	_refresh_info()


func _on_toggle_panel() -> void:
	_bottom.visible = not _bottom.visible


# --- Modal (kayitlar / uretec) ------------------------------------------------

func _open_modal(title: String) -> void:
	_modal_title.text = title
	_modal_status.text = ""
	for child in _modal_list.get_children():
		_modal_list.remove_child(child)
		child.queue_free()
	_modal.show()


func _on_modal_close() -> void:
	if _generator.is_running():
		_generator.cancel()
	_modal.hide()


func _on_open_saved() -> void:
	_open_modal("Kayıtlı Bölümler")
	var names := CustomLevelStore.list_names()
	if names.is_empty():
		_modal_status.text = "Henüz kayıt yok."
		return
	for saved_name in names:
		_modal_list.add_child(_make_list_button(saved_name, _on_load_saved.bind(saved_name)))


func _on_load_saved(saved_name: String) -> void:
	var loaded := CustomLevelStore.load_level(saved_name)
	if loaded == null:
		_modal_status.text = "Yüklenemedi: %s" % saved_name
		return
	level = loaded
	_selection = Selection.NONE
	_selected_index = -1
	_status_text = "Yüklendi: %s" % saved_name
	_modal.hide()
	_rebuild()


func _on_open_generator() -> void:
	_open_modal("Bölüm Üret")
	_modal_status.text = "Bir profil seç; 10 aday aranacak."
	_modal_list.add_child(_make_list_button("Kolay", _start_generation.bind("easy")))
	_modal_list.add_child(_make_list_button("Orta", _start_generation.bind("medium")))
	_modal_list.add_child(_make_list_button("Zor", _start_generation.bind("hard")))
	_modal_list.add_child(_make_list_button("Bloklu", _start_generation.bind("blocks")))


func _start_generation(profile_name: String) -> void:
	var profile: LevelGenerator.Profile
	match profile_name:
		"easy":
			profile = LevelGenerator.Profile.easy()
		"hard":
			profile = LevelGenerator.Profile.hard()
		"blocks":
			profile = LevelGenerator.Profile.with_blocks()
		_:
			profile = LevelGenerator.Profile.medium()

	for child in _modal_list.get_children():
		_modal_list.remove_child(child)
		child.queue_free()
	_modal_status.text = "Aranıyor..."
	_generated.clear()
	_generator.generate(profile, 10)


func _on_candidate_evaluated(tried: int, accepted: int) -> void:
	if _modal.visible:
		_modal_status.text = "Aranıyor... %d aday denendi, %d bulundu" % [tried, accepted]


func _on_generation_finished(levels: Array[LevelData]) -> void:
	_generated = levels
	if not _modal.visible:
		return
	# Eleme dokumu gosterilir: "hiçbir şey bulunamadı" tek basina yol
	# gostermez, hangi olcutun fazla siki oldugunu bilmek gerekir.
	var rejections := _generator.describe_rejections()
	if levels.is_empty():
		_modal_status.text = "Uygun aday çıkmadı.\nEleme: %s" % rejections
		return
	_modal_status.text = "%d bölüm bulundu — düzenlemek için dokun\nEleme: %s" % [
		levels.size(), rejections]
	for i in levels.size():
		_modal_list.add_child(_make_list_button(levels[i].display_name, _load_generated.bind(i)))


func _load_generated(index: int) -> void:
	if index < 0 or index >= _generated.size():
		return
	level = _generated[index]
	_selection = Selection.NONE
	_selected_index = -1
	_status_text = "Üretilen bölüm yüklendi — düzenleyip kaydet"
	_modal.hide()
	_rebuild()


func _make_list_button(text: String, action: Callable) -> Button:
	var button := LumaButton.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 64.0)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(action)
	return button


# --- Secim vurgusu ------------------------------------------------------------

## Secili ogenin etrafina ince bir cerceve. Panel ve bloklarin kendi gorseli
## zaten var; burada yalnizca "hangisi secili" bilgisi cizilir.
func _draw() -> void:
	if _selection == Selection.NONE:
		return

	var color := Palette.ACCENT
	match _selection:
		Selection.PANEL:
			var panel := level.panels[_selected_index]
			_draw_marker(panel.position, Vector2(panel.length, panel.thickness),
				deg_to_rad(panel.rotation_degrees), color)
		Selection.BLOCK:
			var block := level.breakable_blocks[_selected_index]
			_draw_marker(block.position, block.size,
				deg_to_rad(block.rotation_degrees), color)
		Selection.TARGET:
			_draw_marker(level.target_position, Vector2.ONE * _solver.target_size, 0.0, color)
		Selection.LAUNCHER:
			_draw_marker(level.launcher_position, Vector2(150.0, 74.0), 0.0, color)
		Selection.LEFT_WALL, Selection.RIGHT_WALL:
			_draw_wall_gap()


func _draw_marker(at: Vector2, size: Vector2, rotation: float, color: Color) -> void:
	var half := size * 0.5 + Vector2(10.0, 10.0)
	draw_set_transform(at, rotation, Vector2.ONE)
	draw_rect(Rect2(-half, half * 2.0), Color(color, 0.85), false, 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Bosluk gorunmez bir seydir - kenarda hicbir sey YOKTUR. Secildiginde
## nerede oldugunu gostermek icin araligi isaretleriz.
func _draw_wall_gap() -> void:
	var gap := _wall_gap(_selection)
	if gap == Vector2.ZERO:
		return
	var rect := _world.get_play_rect()
	var x := rect.position.x + 7.0 if _selection == Selection.LEFT_WALL else rect.end.x - 7.0
	draw_line(Vector2(x, gap.x), Vector2(x, gap.y), Color(Palette.ACCENT_ALT, 0.9), 6.0)


func _make_blank_level() -> LevelData:
	var blank := LevelData.new()
	blank.level_id = 1
	blank.display_name = "Yeni Bölüm"
	blank.launcher_position = Vector2(360.0, 1120.0)
	blank.target_position = Vector2(360.0, 320.0)
	blank.max_lives = 4
	return blank
