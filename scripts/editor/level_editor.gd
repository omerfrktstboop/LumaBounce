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

enum Selection { NONE, PANEL, BLOCK, OBSTACLE, TARGET, LAUNCHER, LEFT_WALL, RIGHT_WALL }

## Ince ayar adimlari. Dokunmatikte surukleme kaba, stepper hassas olsun.
const ANGLE_STEP := 2.0
const SIZE_STEP := 20.0
const WALL_STEP := 20.0
const MIN_PANEL_LENGTH := 120.0
const MAX_PANEL_LENGTH := 560.0
const MIN_BLOCK_WIDTH := 80.0
const MAX_BLOCK_WIDTH := 620.0
const BLOCK_HEIGHT := 44.0
const MIN_BLOCK_THICKNESS := 20.0
const MAX_BLOCK_THICKNESS := 80.0
const TARGET_SCALE_STEP := 0.1
const MIN_TARGET_SCALE := 0.5
const MAX_TARGET_SCALE := 1.5
const MAX_SOLUTION_ROUTES := 10
## Duvar bosluklarinin editordeki varsayilan araligi.
const DEFAULT_GAP := Vector2(420.0, 740.0)
## Alt serit sabit yukseklikte; parti gezinme satiri belirince tam o kadar
## buyur. Sabit en buyuk boyutta birakmak arenadan bosuna yer yerdi.
const PANEL_HEIGHT := 354.0
const PANEL_HEIGHT_WITH_BATCH := 418.0
const PANEL_VIEW_TOP := 92.0
const PANEL_VIEW_BOTTOM_MARGIN := 20.0

## AppRoot tarafindan add_child'dan ONCE atanabilir; bos birakilirsa bos bir
## bolumle baslanir.
var level: LevelData
## Test sahnesinden editore donerken AppRoot tarafindan add_child'dan ONCE
## atanir. Uretilen/kaydedilen parti ve acik indeks boylece kaybolmaz.
var initial_batch_context := {}
## Duzenlenen bolum bir RESMI bolumden geldiyse onun numarasi, yoksa 0.
## AppRoot, debug panelinden "DUZENLE" ile girildiginde oynanan bolumun
## numarasini buraya yazar; KAYDET bunu sidecar'a gecirir, boylece kayitlar
## listesinde "Bölüm 17" etiketi gorunur (bkz. _on_save, _refresh_library_rows).
var source_level_id := 0

@onready var _world: LevelWorld = $World
@onready var _camera: Camera2D = $EditorCamera
@onready var _info: Label = $HUD/SafeArea/Root/BottomPanel/Rows/InfoLabel
@onready var _bottom: PanelContainer = $HUD/SafeArea/Root/BottomPanel
@onready var _batch_row: HBoxContainer = $HUD/SafeArea/Root/BottomPanel/Rows/BatchRow
@onready var _batch_label: Label = $HUD/SafeArea/Root/BottomPanel/Rows/BatchRow/BatchLabel
@onready var _previous_level_button: Button = $HUD/SafeArea/Root/BottomPanel/Rows/BatchRow/PrevLevel
@onready var _next_level_button: Button = $HUD/SafeArea/Root/BottomPanel/Rows/BatchRow/NextLevel
@onready var _modal: Control = $HUD/Modal
@onready var _modal_title: Label = $HUD/Modal/Card/Rows/Title
@onready var _modal_status: Label = $HUD/Modal/Card/Rows/Status
@onready var _modal_tabs: HBoxContainer = $HUD/Modal/Card/Rows/TabRow
@onready var _modal_actions: HBoxContainer = $HUD/Modal/Card/Rows/ActionRow
@onready var _modal_list: VBoxContainer = $HUD/Modal/Card/Rows/Scroll/List
@onready var _solution_overlay: LevelSolutionOverlay = $SolutionOverlay
@onready var _solution_button: Button = $HUD/SafeArea/Root/BottomPanel/Rows/ActionRow/SolutionButton
@onready var _analyse_button: Button = $HUD/SafeArea/Root/BottomPanel/Rows/ActionRow/AnalyseButton
@onready var _rotate_90_button: Button = $HUD/SafeArea/Root/BottomPanel/Rows/TuneRow/Rotate90
@onready var _thickness_button: Button = $HUD/SafeArea/Root/BottomPanel/Rows/TuneRow/ThicknessCycle
@onready var _copy_button: Button = $HUD/SafeArea/Root/BottomPanel/Rows/AddRow/CopyItem
@onready var _collapse_button: Button = $HUD/SafeArea/Root/TopBar/CollapseButton
@onready var _quick_generate_button: Button = $HUD/SafeArea/Root/BottomPanel/Rows/ActionRow/QuickGenerateButton

var _solver: LevelSolver
var _generator: LevelGenerator
var _ai_coordinator: AILevelGenerationCoordinator
var _generation_form: AIGenerationForm
var _metadata_store := GenerationMetadataStore.new()
## Kayitlar kovasinin kendi sidecar'i - uretim manifestinden ayri tutulur,
## cunku uretim partisi her seferinde tamamen ezilir, kayitlar birikir.
var _saved_metadata_store := GenerationMetadataStore.new(
	GenerationMetadataStore.SAVED_MANIFEST_PATH)
var _target_preview: Node2D
var _launcher_preview: Node2D

var _selection := Selection.NONE
var _selected_index := -1
var _dragging := false
var _drag_offset := Vector2.ZERO
var _active_touch := -1
## Uzerinde gezinilen parti (uretim sonucu ya da kitapliktan acilan liste).
## Editorde acik bolum her zaman _batch[_batch_index]'tir; ‹ › ile gezilir.
var _batch: Array[LevelData] = []
var _batch_names := PackedStringArray()
var _batch_index := 0
var _batch_bucket := CustomLevelStore.Bucket.GENERATED
var _batch_metadata: Array[Dictionary] = []
## Kitaplikta acik olan sekme ve isaretli satirlar.
var _library_bucket := CustomLevelStore.Bucket.GENERATED
var _library_names := PackedStringArray()
var _library_selected := {}
var _status_text := ""
var _solution_busy := false
var _analysis_busy := false
var _last_difficulty_result := {}


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	if level == null:
		level = _make_blank_level()

	_solver = LevelSolver.from_scenes()
	_generator = LevelGenerator.new()
	_generator.name = "Generator"
	add_child(_generator)
	_generator.candidate_evaluated.connect(_on_candidate_evaluated)
	_generator.finished.connect(_on_generation_finished)
	_ai_coordinator = AILevelGenerationCoordinator.new()
	_ai_coordinator.name = "AICoordinator"
	add_child(_ai_coordinator)
	_ai_coordinator.status_changed.connect(_on_ai_status_changed)
	_ai_coordinator.completed.connect(_on_ai_generation_completed)
	_ai_coordinator.failed.connect(_on_ai_generation_failed)
	_ai_coordinator.cancelled.connect(_on_ai_generation_cancelled)

	_build_previews()
	_connect_buttons()
	get_viewport().size_changed.connect(_position_camera)
	_position_camera()
	_modal.hide()
	if initial_batch_context.is_empty():
		_rebuild()
	else:
		_restore_batch_context(initial_batch_context)
	_refresh_batch_row()
	_set_panel_visible(_bottom.visible)


## Oynanisla AYNI cerceveleme: yatayda oyun alani ortali, dikeyde alt kenara
## hizali. Editorde gordugun kadraj oyunda gordugun kadrajdir.
func _position_camera() -> void:
	var play_rect := _world.get_play_rect()
	var visible_size := get_viewport_rect().size
	var world_center := play_rect.position + play_rect.size * 0.5
	if not _bottom.visible:
		_camera.zoom = Vector2.ONE
		_camera.position = Vector2(
			world_center.x, play_rect.end.y - visible_size.y * 0.5)
		return
	var panel_height := PANEL_HEIGHT_WITH_BATCH if _batch_row.visible else PANEL_HEIGHT
	var visible_bottom := visible_size.y - panel_height - PANEL_VIEW_BOTTOM_MARGIN
	var available_height := maxf(visible_bottom - PANEL_VIEW_TOP, 120.0)
	var zoom_factor := clampf(available_height / play_rect.size.y, 0.35, 1.0)
	var desired_screen_center := (PANEL_VIEW_TOP + visible_bottom) * 0.5
	_camera.zoom = Vector2.ONE * zoom_factor
	_camera.position = Vector2(
		world_center.x,
		world_center.y + (visible_size.y * 0.5 - desired_screen_center) / zoom_factor)


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
	get_node(rows + "AddRow/AddStrongBlock").pressed.connect(_on_add_block.bind(2))
	_copy_button.pressed.connect(_on_copy_selected)
	get_node(rows + "AddRow/DeleteItem").pressed.connect(_on_delete)
	get_node(rows + "AddRow/CycleWall").pressed.connect(_on_cycle_wall)
	get_node(rows + "ObstacleRow/AddRing").pressed.connect(
		_on_add_obstacle.bind(ObstacleData.Kind.METAL_RING))
	get_node(rows + "ObstacleRow/AddBomb").pressed.connect(
		_on_add_obstacle.bind(ObstacleData.Kind.BOMB))
	get_node(rows + "ObstacleRow/AddWheel").pressed.connect(
		_on_add_obstacle.bind(ObstacleData.Kind.ROTATING_WHEEL))
	get_node(rows + "ObstacleRow/AddMover").pressed.connect(
		_on_add_obstacle.bind(ObstacleData.Kind.MOVING_BAR))
	get_node(rows + "ObstacleRow/AddLaser").pressed.connect(
		_on_add_obstacle.bind(ObstacleData.Kind.PULSE_LASER))

	get_node(rows + "TuneRow/AMinus").pressed.connect(_on_tune.bind(0, -1))
	get_node(rows + "TuneRow/APlus").pressed.connect(_on_tune.bind(0, 1))
	get_node(rows + "TuneRow/BMinus").pressed.connect(_on_tune.bind(1, -1))
	get_node(rows + "TuneRow/BPlus").pressed.connect(_on_tune.bind(1, 1))
	_rotate_90_button.pressed.connect(_on_rotate_90)
	_thickness_button.pressed.connect(_on_cycle_thickness)

	get_node(rows + "ActionRow/TestButton").pressed.connect(_on_test)
	get_node(rows + "ActionRow/AnalyseButton").pressed.connect(_on_analyse)
	get_node(rows + "ActionRow/GenerateButton").pressed.connect(_on_open_generator)
	_quick_generate_button.pressed.connect(_on_quick_generate)
	get_node(rows + "ActionRow/SolutionButton").pressed.connect(_on_solution_pressed)
	get_node(rows + "ActionRow/SaveButton").pressed.connect(_on_save)

	get_node(rows + "BatchRow/PrevLevel").pressed.connect(_on_batch_step.bind(-1))
	get_node(rows + "BatchRow/NextLevel").pressed.connect(_on_batch_step.bind(1))

	$HUD/SafeArea/Root/TopBar/BackButton.pressed.connect(menu_requested.emit)
	$HUD/SafeArea/Root/TopBar/OpenButton.pressed.connect(_on_open_library)
	$HUD/SafeArea/Root/TopBar/CollapseButton.pressed.connect(_on_toggle_panel)
	$HUD/Modal/Card/Rows/CloseButton.pressed.connect(_on_modal_close)

	$HUD/Modal/Card/Rows/TabRow/GeneratedTab.pressed.connect(
		_show_library.bind(CustomLevelStore.Bucket.GENERATED))
	$HUD/Modal/Card/Rows/TabRow/SavedTab.pressed.connect(
		_show_library.bind(CustomLevelStore.Bucket.SAVED))
	$HUD/Modal/Card/Rows/ActionRow/EditSelected.pressed.connect(_on_library_edit)
	$HUD/Modal/Card/Rows/ActionRow/CopySelected.pressed.connect(_on_library_copy)
	$HUD/Modal/Card/Rows/ActionRow/RepoSelected.pressed.connect(_on_library_to_repo)
	$HUD/Modal/Card/Rows/ActionRow/DeleteSelected.pressed.connect(_on_library_delete)


# --- Onizlemeyi veriden kurma -------------------------------------------------

## Yapisal her degisiklikten sonra cagrilir (ekleme, silme, bolum yukleme).
## Surukleme sirasinda cagrilmaz - orada yalnizca ilgili dugum oynatilir.
func _rebuild() -> void:
	_last_difficulty_result.clear()
	_clear_solution()
	_world.build(level)
	_target_preview.position = level.target_position
	_target_preview.scale = Vector2.ONE * level.target_scale
	_launcher_preview.position = level.launcher_position
	_refresh_info()
	queue_redraw()


func _refresh_info() -> void:
	_rotate_90_button.disabled = not _selection_can_rotate()
	_thickness_button.disabled = not _selection_supports_thickness()
	_copy_button.disabled = not _selection_can_copy()
	var lines := PackedStringArray()
	lines.append("%d panel  %d blok  %d engel  |  %d can" % [
		level.panels.size(), level.breakable_blocks.size(),
		level.obstacles.size(), level.max_lives])
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
			return "Blok %d — A: açı %.0f°  B: genişlik %.0f  kalınlık %.0f  can %d" % [
				_selected_index + 1, block.rotation_degrees, block.size.x,
				block.size.y, block.hit_points]
		Selection.OBSTACLE:
			var obstacle := level.obstacles[_selected_index]
			match obstacle.kind:
				ObstacleData.Kind.METAL_RING:
					return "Halka %d - A: dis cap %.0f  B: delik cap %.0f  kalinlik %.0f" % [
						_selected_index + 1, obstacle.size.x, obstacle.inner_radius * 2.0,
						obstacle.outer_radius() - obstacle.inner_radius]
				ObstacleData.Kind.BOMB:
					return "Bomba %d - A: cap %.0f  B: yon %.0f" % [
						_selected_index + 1, obstacle.size.x, obstacle.rotation_degrees]
				ObstacleData.Kind.ROTATING_WHEEL:
					return "Cark %d - A: hiz %.0f  B: cap %.0f  kalinlik %.0f" % [
						_selected_index + 1, obstacle.angular_speed_degrees,
						obstacle.size.x, obstacle.size.y]
				ObstacleData.Kind.MOVING_BAR:
					return "Kayan %d - A: yon %.0f  B: mesafe %.0f  kalinlik %.0f" % [
						_selected_index + 1, obstacle.motion_direction_degrees,
						obstacle.travel_distance, obstacle.size.y]
				ObstacleData.Kind.PULSE_LASER:
					return "Lazer %d - A: dongu %.1fsn  B: boy %.0f  kalinlik %.0f" % [
						_selected_index + 1, obstacle.motion_period, obstacle.size.x,
						obstacle.size.y]
			return obstacle.display_name()
		Selection.TARGET:
			return "Hedef — A: boyut %.0f%%  sürükle: (%.0f, %.0f)" % [
				level.target_scale * 100.0,
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
	_clear_solution()
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

	for i in level.obstacles.size():
		var distance := world.distance_to(level.obstacles[i].position)
		if distance < best_distance:
			best_distance = distance
			best_selection = Selection.OBSTACLE
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
		Selection.PANEL, Selection.BLOCK, Selection.OBSTACLE,
		Selection.TARGET, Selection.LAUNCHER]


func _selected_position() -> Vector2:
	match _selection:
		Selection.PANEL:
			return level.panels[_selected_index].position
		Selection.BLOCK:
			return level.breakable_blocks[_selected_index].position
		Selection.OBSTACLE:
			return level.obstacles[_selected_index].position
		Selection.TARGET:
			return level.target_position
		Selection.LAUNCHER:
			return level.launcher_position
	return Vector2.ZERO


func _set_selected_position(value: Vector2) -> void:
	_last_difficulty_result.clear()
	match _selection:
		Selection.PANEL:
			level.panels[_selected_index].position = value
			var panel := _world.get_panel_node(_selected_index)
			if panel != null:
				panel.position = value
		Selection.BLOCK:
			level.breakable_blocks[_selected_index].position = value
			_world.set_block_position(_selected_index, value)
		Selection.OBSTACLE:
			level.obstacles[_selected_index].position = value
			_world.set_obstacle_position(_selected_index, value)
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


func _on_add_block(hit_points: int = 1) -> void:
	var block := BreakableBlockData.new()
	block.position = _free_spot()
	block.rotation_degrees = 0.0
	block.size = Vector2(220.0, BLOCK_HEIGHT)
	block.hit_points = hit_points
	level.breakable_blocks.append(block)
	_selection = Selection.BLOCK
	_selected_index = level.breakable_blocks.size() - 1
	_status_text = "Güçlendirilmiş blok eklendi." if hit_points == 2 else ""
	_rebuild()


func _on_add_obstacle(kind: ObstacleData.Kind) -> void:
	var obstacle := ObstacleData.new()
	obstacle.kind = kind
	obstacle.position = _free_spot()
	match kind:
		ObstacleData.Kind.METAL_RING:
			obstacle.size = Vector2(150.0, 28.0)
			obstacle.inner_radius = 42.0
		ObstacleData.Kind.BOMB:
			obstacle.size = Vector2(68.0, 68.0)
		ObstacleData.Kind.ROTATING_WHEEL:
			obstacle.size = Vector2(150.0, 24.0)
			obstacle.spoke_count = 6
			obstacle.angular_speed_degrees = 55.0
		ObstacleData.Kind.MOVING_BAR:
			obstacle.size = Vector2(190.0, 34.0)
			obstacle.motion_direction_degrees = 0.0
			obstacle.travel_distance = 100.0
			obstacle.motion_period = 2.8
		ObstacleData.Kind.PULSE_LASER:
			obstacle.size = Vector2(280.0, 14.0)
			obstacle.motion_period = 3.0
			obstacle.pulse_on_ratio = 0.667
	level.obstacles.append(obstacle)
	_selection = Selection.OBSTACLE
	_selected_index = level.obstacles.size() - 1
	_status_text = ""
	_rebuild()


## Yeni ogeler ust uste binmesin diye her ekleyiste biraz kaydirilir.
func _free_spot() -> Vector2:
	var count := level.panels.size() + level.breakable_blocks.size() + level.obstacles.size()
	return Vector2(300.0 + float(count % 3) * 60.0, 700.0 - float(count % 4) * 70.0)


func _on_delete() -> void:
	if _selection == Selection.PANEL:
		level.panels.remove_at(_selected_index)
	elif _selection == Selection.BLOCK:
		level.breakable_blocks.remove_at(_selected_index)
	elif _selection == Selection.OBSTACLE:
		level.obstacles.remove_at(_selected_index)
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
		Selection.OBSTACLE:
			_tune_obstacle(level.obstacles[_selected_index], axis, direction)
		Selection.TARGET:
			if axis != 0:
				return
			level.target_scale = clampf(
				level.target_scale + TARGET_SCALE_STEP * direction,
				MIN_TARGET_SCALE, MAX_TARGET_SCALE)
		Selection.LEFT_WALL, Selection.RIGHT_WALL:
			_tune_wall(axis, direction)
		_:
			return
	_status_text = ""
	_rebuild()


func _selection_can_copy() -> bool:
	match _selection:
		Selection.PANEL:
			return _selected_index >= 0 and _selected_index < level.panels.size()
		Selection.BLOCK:
			return _selected_index >= 0 and _selected_index < level.breakable_blocks.size()
		Selection.OBSTACLE:
			return _selected_index >= 0 and _selected_index < level.obstacles.size()
	return false


func _on_copy_selected() -> void:
	if not _selection_can_copy():
		return
	match _selection:
		Selection.PANEL:
			var panel := level.panels[_selected_index].duplicate(true) as PanelData
			panel.position = _copied_position(panel.position)
			level.panels.append(panel)
			_selected_index = level.panels.size() - 1
		Selection.BLOCK:
			var block := (
				level.breakable_blocks[_selected_index].duplicate(true) as BreakableBlockData)
			block.position = _copied_position(block.position)
			level.breakable_blocks.append(block)
			_selected_index = level.breakable_blocks.size() - 1
		Selection.OBSTACLE:
			var obstacle := level.obstacles[_selected_index].duplicate(true) as ObstacleData
			obstacle.position = _copied_position(obstacle.position)
			level.obstacles.append(obstacle)
			_selected_index = level.obstacles.size() - 1
	_status_text = "Seçili parça kopyalandı."
	_rebuild()


func _copied_position(source: Vector2) -> Vector2:
	var offset := Vector2(32.0, 32.0)
	var copied := source + offset
	if copied.x > 660.0 or copied.y > 1040.0:
		copied = source - offset
	return Vector2(
		clampf(copied.x, 60.0, 660.0),
		clampf(copied.y, 180.0, 1040.0))


func _selection_can_rotate() -> bool:
	match _selection:
		Selection.PANEL:
			return _selected_index >= 0 and _selected_index < level.panels.size()
		Selection.BLOCK:
			return _selected_index >= 0 and _selected_index < level.breakable_blocks.size()
		Selection.OBSTACLE:
			return _selected_index >= 0 and _selected_index < level.obstacles.size()
	return false


func _on_rotate_90() -> void:
	if not _selection_can_rotate():
		return
	match _selection:
		Selection.PANEL:
			var panel := level.panels[_selected_index]
			panel.rotation_degrees = wrapf(panel.rotation_degrees + 90.0, -90.0, 90.0)
		Selection.BLOCK:
			var block := level.breakable_blocks[_selected_index]
			block.rotation_degrees = wrapf(block.rotation_degrees + 90.0, -90.0, 90.0)
		Selection.OBSTACLE:
			var obstacle := level.obstacles[_selected_index]
			obstacle.rotation_degrees = wrapf(
				obstacle.rotation_degrees + 90.0, -180.0, 180.0)
	_status_text = "Seçili parça 90° döndürüldü."
	_rebuild()


func _selection_supports_thickness() -> bool:
	if _selection == Selection.BLOCK:
		return _selected_index >= 0 and _selected_index < level.breakable_blocks.size()
	if _selection != Selection.OBSTACLE or _selected_index < 0 \
			or _selected_index >= level.obstacles.size():
		return false
	return level.obstacles[_selected_index].kind in [
		ObstacleData.Kind.METAL_RING,
		ObstacleData.Kind.ROTATING_WHEEL,
		ObstacleData.Kind.MOVING_BAR,
		ObstacleData.Kind.PULSE_LASER,
	]


func _on_cycle_thickness() -> void:
	if not _selection_supports_thickness():
		return
	if _selection == Selection.BLOCK:
		var block := level.breakable_blocks[_selected_index]
		block.size.y = _next_thickness(
			block.size.y, MIN_BLOCK_THICKNESS, MAX_BLOCK_THICKNESS)
		_status_text = "Blok kalınlığı: %.0f px (5 kademe)" % block.size.y
		_rebuild()
		return
	var obstacle := level.obstacles[_selected_index]
	var thickness := obstacle.size.y
	match obstacle.kind:
		ObstacleData.Kind.METAL_RING:
			var outer := obstacle.outer_radius()
			var current := outer - obstacle.inner_radius
			thickness = _next_thickness(current, 12.0, maxf(outer - 28.0, 12.0))
			obstacle.inner_radius = outer - thickness
		ObstacleData.Kind.ROTATING_WHEEL:
			thickness = _next_thickness(obstacle.size.y, 14.0, 40.0)
			obstacle.size.y = thickness
		ObstacleData.Kind.MOVING_BAR:
			thickness = _next_thickness(obstacle.size.y, 20.0, 72.0)
			obstacle.size.y = thickness
		ObstacleData.Kind.PULSE_LASER:
			thickness = _next_thickness(obstacle.size.y, 8.0, 30.0)
			obstacle.size.y = thickness
	_status_text = "Engel kalınlığı: %.0f px (5 kademe)" % thickness
	_rebuild()


func _next_thickness(current: float, minimum: float, maximum: float) -> float:
	var step := (maximum - minimum) / 4.0
	for index in range(5):
		var candidate := snappedf(minimum + step * index, 1.0)
		if current < candidate - 0.5:
			return candidate
	return minimum


func _tune_obstacle(obstacle: ObstacleData, axis: int, direction: int) -> void:
	match obstacle.kind:
		ObstacleData.Kind.METAL_RING:
			if axis == 0:
				obstacle.size.x = clampf(
					obstacle.size.x + SIZE_STEP * direction, 88.0, 300.0)
				obstacle.inner_radius = minf(
					obstacle.inner_radius, obstacle.outer_radius() - 12.0)
			else:
				obstacle.inner_radius = clampf(
					obstacle.inner_radius + 8.0 * direction,
					28.0, obstacle.outer_radius() - 12.0)
		ObstacleData.Kind.BOMB:
			if axis == 0:
				obstacle.size = Vector2.ONE * clampf(
					obstacle.size.x + 10.0 * direction, 48.0, 140.0)
			else:
				obstacle.rotation_degrees = wrapf(
					obstacle.rotation_degrees + 15.0 * direction, -180.0, 180.0)
		ObstacleData.Kind.ROTATING_WHEEL:
			if axis == 0:
				obstacle.angular_speed_degrees = clampf(
					obstacle.angular_speed_degrees + 10.0 * direction, -180.0, 180.0)
				if absf(obstacle.angular_speed_degrees) < 10.0:
					obstacle.angular_speed_degrees = 10.0 * direction
			else:
				obstacle.size.x = clampf(
					obstacle.size.x + SIZE_STEP * direction, 84.0, 260.0)
		ObstacleData.Kind.MOVING_BAR:
			if axis == 0:
				obstacle.motion_direction_degrees = wrapf(
					obstacle.motion_direction_degrees + 15.0 * direction, -180.0, 180.0)
			else:
				obstacle.travel_distance = clampf(
					obstacle.travel_distance + SIZE_STEP * direction, 20.0, 260.0)
		ObstacleData.Kind.PULSE_LASER:
			# A dongu suresini, B isinin boyunu ayarlar. Acik ORANI kasten
			# ayar kollarinda degil: ondan once ayarlanmasi gereken sey ritim,
			# ve iki kol var. Orani degistirmek gerekirse .tres'ten yapilir.
			if axis == 0:
				obstacle.motion_period = clampf(
					obstacle.motion_period + 0.2 * direction, 1.2, 6.0)
			else:
				obstacle.size.x = clampf(
					obstacle.size.x + SIZE_STEP * direction, 90.0, 460.0)


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
	_set_panel_visible(false)
	test_requested.emit(level)


## Oynanisin fizigiyle olcum. Kisa bir donma olur (birkac bin simulasyon),
## bu yuzden once "olculuyor" yazilir ve bir kare beklenir.
func _on_analyse() -> void:
	if _analysis_busy or _solution_busy:
		return
	_analysis_busy = true
	_analyse_button.disabled = true
	_refresh_batch_row()
	_status_text = "Zorluk skoru hesaplaniyor..."
	_refresh_info()
	await get_tree().process_frame
	await get_tree().physics_frame

	_solver.bind_space(
		_world.get_space(), _world.get_block_rids(), _world.get_obstacles())
	var spawn := _solver.spawn_position(level.launcher_position)
	var play_rect := _world.get_play_rect()
	var none: Array[RID] = []
	var free_scan: Dictionary
	if level.breakable_blocks.is_empty():
		free_scan = await _solver.scan_for_solution_async(
			spawn, level.target_position, play_rect, none,
			LevelGenerator.FINE_ANGLE_STEP, LevelGenerator.FINE_POWER_STEP,
			LevelGenerator.SIMS_PER_FRAME)
	else:
		# Bloklu tasarimlarda ilk durumun kapali olmasi normaldir. Pahali
		# hassas arama, hedef rotasinin acildigi kirik durumda yapilir.
		free_scan = await _solver.scan_async(
			spawn, level.target_position, play_rect, none,
			LevelGenerator.FINE_ANGLE_STEP, LevelGenerator.FINE_POWER_STEP,
			LevelGenerator.SIMS_PER_FRAME)
	var free_analysis := LevelSolver.analyse_robust(free_scan)

	var opened_scan := {}
	var opened_analysis := {}
	if not level.breakable_blocks.is_empty():
		var all_broken := _world.get_all_broken_state()
		opened_scan = await _solver.scan_for_solution_async(
			spawn, level.target_position, play_rect,
			_world.rids_for_state(all_broken),
			LevelGenerator.FINE_ANGLE_STEP, LevelGenerator.FINE_POWER_STEP,
			LevelGenerator.SIMS_PER_FRAME)
		opened_analysis = LevelSolver.analyse_robust(opened_scan)

	_last_difficulty_result = LevelDifficultyScorer.evaluate(
		level, free_scan, free_analysis, opened_scan, opened_analysis)
	_status_text = LevelDifficultyScorer.summary(_last_difficulty_result)
	_analysis_busy = false
	_analyse_button.disabled = false
	_refresh_batch_row()
	_refresh_info()


func _on_solution_pressed() -> void:
	if _solution_busy or _analysis_busy:
		return
	if _solution_overlay.has_routes():
		_solution_overlay.cycle()
		_refresh_solution_state()
		return
	_solution_busy = true
	_solution_button.disabled = true
	_refresh_batch_row()
	_status_text = "Cozum taraniyor..."
	_refresh_info()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_solver.bind_space(
		_world.get_space(), _world.get_block_rids(), _world.get_obstacles())
	var spawn := _solver.spawn_position(level.launcher_position)
	var play_rect := _world.get_play_rect()
	var none: Array[RID] = []
	var free_scan: Dictionary
	if level.breakable_blocks.is_empty():
		free_scan = await _solver.scan_for_solution_async(
			spawn, level.target_position, play_rect, none,
			LevelGenerator.FINE_ANGLE_STEP, LevelGenerator.FINE_POWER_STEP,
			LevelGenerator.SIMS_PER_FRAME)
	else:
		# Bloklu bantta kirilmamis durumun cozum vermemesi tasarimin parcasi;
		# burada pahali hassas taramayi bloklar acildiktan sonraya sakla.
		free_scan = await _solver.scan_async(
			spawn, level.target_position, play_rect, none,
			LevelGenerator.FINE_ANGLE_STEP, LevelGenerator.FINE_POWER_STEP,
			LevelGenerator.SIMS_PER_FRAME)
	var free_analysis := LevelSolver.analyse_robust(free_scan)
	var opened_scan := {}
	var opened_analysis := {}
	var routes: Array[Dictionary] = []
	if level.breakable_blocks.is_empty():
		routes.append_array(_routes_from_scan(
			free_scan, none, "SERBEST", 0, MAX_SOLUTION_ROUTES))
	else:
		# Kapali durumdan en fazla bir rota goster; kalan yerleri bloklar kirik
		# durumdaki farkli cozumlere ayir. Boylece ikinci rota her zaman blok
		# kapisinin ardindaki alternatifi temsil etmeye devam eder.
		routes.append_array(_routes_from_scan(free_scan, none, "BLOKLAR SAGLAM", 0, 1))
		var all_broken := _world.get_all_broken_state()
		var opened_rids := _world.rids_for_state(all_broken)
		opened_scan = await _solver.scan_for_solution_async(
			spawn, level.target_position, play_rect, opened_rids,
			LevelGenerator.FINE_ANGLE_STEP, LevelGenerator.FINE_POWER_STEP,
			LevelGenerator.SIMS_PER_FRAME)
		opened_analysis = LevelSolver.analyse_robust(opened_scan)
		routes.append_array(_routes_from_scan(
			opened_scan, opened_rids, "BLOKLAR KIRIK",
			level.breakable_blocks.size(), MAX_SOLUTION_ROUTES - routes.size()))

	_last_difficulty_result = LevelDifficultyScorer.evaluate(
		level, free_scan, free_analysis, opened_scan, opened_analysis)
	for index in routes.size():
		var route := routes[index]
		var state_label := String(route.get("label", "ROTA"))
		route["label"] = "ROTA %d/%d - %s" % [index + 1, routes.size(), state_label]
		route["difficulty_score"] = int(_last_difficulty_result.get("score", 0))
		route["difficulty_label"] = String(_last_difficulty_result.get("label", ""))
		route["solution_count"] = int(_last_difficulty_result.get("solution_count", 0))

	_solution_overlay.set_routes(routes)
	if not routes.is_empty():
		_solution_overlay.show_main()
	_solution_busy = false
	_solution_button.disabled = false
	_refresh_batch_row()
	if routes.is_empty():
		_status_text = "Saglam veya basarili cozum rotasi bulunamadi."
	_refresh_solution_state()


func _routes_from_scan(scan_result: Dictionary, excluded: Array[RID], label: String,
		prebroken_count: int, max_routes: int) -> Array[Dictionary]:
	var routes: Array[Dictionary] = []
	if max_routes <= 0:
		return routes
	var candidates := LevelSolver.analyse_solution_clusters(scan_result)
	if candidates.is_empty():
		var fallback := _best_hit_candidate(scan_result)
		if not fallback.is_empty():
			candidates.append(fallback)
	var diverse := LevelSolver.solution_candidates(scan_result, max_routes)
	for candidate in diverse:
		var duplicate := false
		for existing in candidates:
			if (is_equal_approx(float(existing["angle"]), float(candidate["angle"]))
					and is_equal_approx(float(existing["power"]), float(candidate["power"]))):
				duplicate = true
				break
		if not duplicate:
			candidates.append(candidate)
	for candidate in candidates:
		if routes.size() >= max_routes:
			break
		var route := _route_from_candidate(
			candidate, scan_result, excluded, label, prebroken_count)
		if not route.is_empty():
			routes.append(route)
	return routes


func _route_from_scan(scan_result: Dictionary, excluded: Array[RID], label: String,
		prebroken_count: int, cluster_index := 0) -> Dictionary:
	var candidates := LevelSolver.solution_candidates(scan_result, cluster_index + 1)
	if candidates.is_empty():
		var fallback := _best_hit_candidate(scan_result)
		if not fallback.is_empty():
			candidates.append(fallback)
	if cluster_index >= candidates.size():
		return {}
	return _route_from_candidate(
		candidates[cluster_index], scan_result, excluded, label, prebroken_count)


func _route_from_candidate(candidate: Dictionary, scan_result: Dictionary,
		excluded: Array[RID], label: String, prebroken_count: int) -> Dictionary:
	var route: Dictionary = candidate.duplicate(true)
	var direction := Vector2.UP.rotated(deg_to_rad(float(route["angle"])))
	var trace := _solver.simulate(
		_solver.spawn_position(level.launcher_position), direction * float(route["power"]),
		level.target_position, _world.get_play_rect(), excluded, true)
	if not bool(trace.get("hit", false)):
		return {}
	route["label"] = label
	route["prebroken_count"] = prebroken_count
	route["trace_points"] = trace.get("trace_points", PackedVector2Array())
	route["collision_points"] = trace.get("collision_points", [])
	route["broken_order"] = trace.get("broken_order", PackedInt32Array())
	route["target_hit_position"] = trace.get("target_hit_position", Vector2.ZERO)
	route["bounces"] = int(trace.get("bounces", route.get("bounces", 0)))
	route["solution_search_passes"] = int(scan_result.get("solution_search_passes", 1))
	route["solution_angle_step"] = float(scan_result.get(
		"solution_angle_step", LevelGenerator.FINE_ANGLE_STEP))
	route["solution_power_step"] = float(scan_result.get(
		"solution_power_step", LevelGenerator.FINE_POWER_STEP))
	return route


## Dort-komsulu "saglam" hucre yoksa ilk isabete atlamak rotanin tolerans
## adasinin kenarini secebilir. Sekiz komsuda en cok isabetle cevrili hucre,
## ozellikle aci/guc dengesi capraz ilerleyen panel-ucu rotalarinda daha iyi
## bir merkezdir.
func _best_hit_candidate(scan_result: Dictionary) -> Dictionary:
	var angles: Array[float] = scan_result["angles"]
	var powers: Array[float] = scan_result["powers"]
	var hits: Array = scan_result["hits"]
	var bounces: Array = scan_result["bounces"]
	var best := {}
	var best_neighbours := -1
	var best_bounces := 999
	var best_edge_distance := -1
	for ai in angles.size():
		for pi in powers.size():
			if not bool(hits[ai][pi]):
				continue
			var neighbours := 0
			for da in range(-1, 2):
				for dp in range(-1, 2):
					if da == 0 and dp == 0:
						continue
					var neighbour_ai := ai + da
					var neighbour_pi := pi + dp
					if (neighbour_ai >= 0 and neighbour_ai < angles.size()
							and neighbour_pi >= 0 and neighbour_pi < powers.size()
							and bool(hits[neighbour_ai][neighbour_pi])):
						neighbours += 1
			var cell_bounces := int(bounces[ai][pi])
			var edge_distance := mini(
				mini(ai, angles.size() - 1 - ai), mini(pi, powers.size() - 1 - pi))
			if neighbours < best_neighbours:
				continue
			if neighbours == best_neighbours and cell_bounces > best_bounces:
				continue
			if (neighbours == best_neighbours and cell_bounces == best_bounces
					and edge_distance <= best_edge_distance):
				continue
			best_neighbours = neighbours
			best_bounces = cell_bounces
			best_edge_distance = edge_distance
			best = {
				"robust": 0, "angle": angles[ai], "power": powers[pi],
				"bounces": best_bounces, "angle_lo": angles[ai],
				"angle_hi": angles[ai], "power_lo": powers[pi], "power_hi": powers[pi],
				"fallback_neighbours": neighbours,
			}
	return best


func _clear_solution() -> void:
	if _solution_overlay != null:
		_solution_overlay.clear()
	if _solution_button != null:
		_solution_button.text = "COZUM"


func _refresh_solution_state() -> void:
	match _solution_overlay.get_mode():
		LevelSolutionOverlay.Mode.MAIN, LevelSolutionOverlay.Mode.ALTERNATIVE:
			_solution_button.text = "ROTA %d/%d" % [
				_solution_overlay.current_index() + 1, _solution_overlay.route_count()]
			_status_text = _solution_overlay.current_info()
		_:
			_solution_button.text = "COZUM"
			if _solution_overlay.has_routes():
				_status_text = "Cozum kapali"
	_refresh_info()


## KAYDET her zaman KAYITLAR kovasina yazar - uretilen bir bolume basmak onu
## "begendim, kalsin" demektir ve bir sonraki uretimin silmesinden kurtarir.
func _on_save() -> void:
	var level_name := _saved_name_for_current()
	var path := CustomLevelStore.save(CustomLevelStore.Bucket.SAVED, level, level_name)
	var copied := CustomLevelStore.copy_to_clipboard(level)
	if path.is_empty():
		_status_text = "Kaydedilemedi."
		_refresh_info()
		return

	# Hangi resmi bolumden turedigi .tres'e DEGIL sidecar JSON'a yazilir:
	# .tres yalnizca bolumun kendisini tanimlar, "bunu nereden duzenledim"
	# bilgisi editorun defteridir (bkz. GenerationMetadataStore basligi).
	var entry := {"saved_at": Time.get_datetime_string_from_system()}
	if source_level_id > 0:
		entry["source_level_id"] = source_level_id
	if not _last_difficulty_result.is_empty():
		entry["difficulty_score"] = int(_last_difficulty_result.get("score", 0))
		entry["difficulty_label"] = String(_last_difficulty_result.get("label", ""))
		entry["solution_count"] = int(_last_difficulty_result.get("solution_count", 0))
		entry["difficulty_breakdown"] = _last_difficulty_result.get("breakdown", {}).duplicate(true)
	_saved_metadata_store.upsert(CustomLevelStore.entry_name_for(level_name), entry)

	var origin := " (bölüm %d)" % source_level_id if source_level_id > 0 else ""
	if copied:
		_status_text = "Kayıtlara alındı%s + panoya kopyalandı: %s" % [origin, level_name]
	else:
		_status_text = "Kayıtlara alındı%s: %s (pano başarısız)" % [origin, level_name]
	_refresh_info()


## Kayit adi. Resmi bir bolum duzenleniyorsa numarasi ONE alinir: kayitlar
## listesinde "zikzak" degil "bolum_17_zikzak" gorunur, yani hangi bolumun
## varyanti oldugu dosya adindan da bellidir (JSON'a ek olarak).
func _saved_name_for_current() -> String:
	var base := level.display_name
	if base.is_empty() or base == "Yeni Bölüm":
		base = "bolum_%s" % Time.get_datetime_string_from_system().replace(":", "")
	if source_level_id > 0:
		return "bolum_%02d_%s" % [source_level_id, base]
	return base


# --- Parti gezinmesi ----------------------------------------------------------
#
# Uretim 10 aday dondurur; hepsini tek tek gercek olcekte gorup begendigini
# kaydetmek gerekir. Onceki surumde listeden birini secmek digerlerini
# atiyordu, yani gozden gecirmek imkansizdi.

func _set_batch(levels: Array[LevelData], names: PackedStringArray,
		bucket: CustomLevelStore.Bucket, metadata: Array[Dictionary] = [],
		start_index := 0) -> void:
	_batch = levels
	_batch_names = names
	_batch_bucket = bucket
	_library_bucket = bucket
	_batch_metadata.assign(metadata)
	_batch_index = clampi(start_index, 0, maxi(_batch.size() - 1, 0))
	_load_batch_entry()


func get_batch_context() -> Dictionary:
	var context := {
		"level": level,
		"panel_visible": _bottom.visible,
		"levels": _batch.duplicate(),
		"names": _batch_names.duplicate(),
		"index": _batch_index,
		"bucket": int(_batch_bucket),
		"metadata": _batch_metadata.duplicate(true),
	}
	return context


func _restore_batch_context(context: Dictionary) -> void:
	var panel_visible := bool(context.get("panel_visible", true))
	var restored_levels: Array[LevelData] = []
	var raw_levels = context.get("levels", [])
	if raw_levels is Array:
		for candidate in raw_levels:
			if candidate is LevelData:
				restored_levels.append(candidate)
	if restored_levels.is_empty():
		var restored_level = context.get("level", null)
		if restored_level is LevelData:
			level = restored_level
		_rebuild()
		_set_panel_visible(panel_visible)
		return

	var restored_names := PackedStringArray(context.get("names", PackedStringArray()))
	while restored_names.size() < restored_levels.size():
		restored_names.append("bolum_%02d" % (restored_names.size() + 1))
	var restored_metadata: Array[Dictionary] = []
	var raw_metadata = context.get("metadata", [])
	if raw_metadata is Array:
		for entry in raw_metadata:
			restored_metadata.append(entry if entry is Dictionary else {})
	_set_batch(
		restored_levels, restored_names,
		int(context.get("bucket", CustomLevelStore.Bucket.GENERATED)),
		restored_metadata, int(context.get("index", 0)))
	_set_panel_visible(panel_visible)


func _on_batch_step(direction: int) -> void:
	if _analysis_busy or _solution_busy:
		return
	if _batch.size() > 1:
		_batch_index = wrapi(_batch_index + direction, 0, _batch.size())
		_load_batch_entry()
		return
	if source_level_id <= 0:
		return
	var wanted := source_level_id + direction
	if not LevelLibrary.is_valid_id(wanted):
		return
	var official := LevelLibrary.load_level(wanted)
	if official == null or official.level_id != wanted:
		_status_text = "Bolum %d yuklenemedi." % wanted
		_refresh_info()
		return
	source_level_id = wanted
	level = official.duplicate(true) as LevelData
	_selection = Selection.NONE
	_selected_index = -1
	_status_text = "Bolum %d acildi." % wanted
	_refresh_batch_row()
	_rebuild()


func _load_batch_entry() -> void:
	if _batch.is_empty():
		_refresh_batch_row()
		return
	level = _batch[_batch_index]
	_selection = Selection.NONE
	_selected_index = -1
	_status_text = ""
	_refresh_batch_row()
	_rebuild()


func _refresh_batch_row() -> void:
	var shows_batch := _batch.size() > 1
	var shows_official := not shows_batch and source_level_id > 0
	_batch_row.visible = shows_batch or shows_official
	_bottom.offset_top = -(PANEL_HEIGHT_WITH_BATCH if _batch_row.visible else PANEL_HEIGHT)
	_previous_level_button.disabled = _analysis_busy or _solution_busy
	_next_level_button.disabled = _analysis_busy or _solution_busy
	if shows_batch:
		_batch_label.text = "%d / %d — %s" % [
			_batch_index + 1, _batch.size(), level.display_name]
		if _batch_index < _batch_metadata.size():
			var meta := _batch_metadata[_batch_index]
			if meta.has("difficulty_score"):
				_batch_label.text += "\nZorluk %d/100  Cozum %d  Sekme %d" % [
					int(meta.get("difficulty_score", 0)),
					int(meta.get("solution_count", 0)),
					int(meta.get("bounce_count", 0))]
			else:
				_batch_label.text += "\nPuan %d  Yenilik %d  Saglam %d  Sekme %d" % [
					int(meta.get("quality_score", 0)), int(meta.get("novelty_score", 0)),
					int(meta.get("robust_cells", 0)), int(meta.get("bounce_count", 0))]
	elif shows_official:
		_batch_label.text = "BOLUM %d / %d - %s" % [
			source_level_id, LevelLibrary.last_level_id(), level.display_name]
		_previous_level_button.disabled = (
			_previous_level_button.disabled
			or source_level_id <= LevelLibrary.FIRST_LEVEL_ID)
		_next_level_button.disabled = (
			_next_level_button.disabled
			or source_level_id >= LevelLibrary.last_level_id())
	_position_camera()


func _on_toggle_panel() -> void:
	_set_panel_visible(not _bottom.visible)


func _set_panel_visible(value: bool) -> void:
	_bottom.visible = value
	_collapse_button.text = "▾" if value else "▴"
	_collapse_button.tooltip_text = (
		"Editör panelini kapat" if value else "Editör panelini aç")
	_position_camera()


# --- Kitaplik ve uretec (modal) -----------------------------------------------
#
# Tek bir modal iki isi gorur: URETILENLER (son arama partisi) ve KAYITLAR
# (bilerek sakladiklarin). Satirlar isaretlenebilir, boylece begendiklerini
# tek tek degil TOPLU kopyalayabilir ya da repoya yazabilirsin.

func _open_modal(title: String, show_tabs: bool, show_actions: bool) -> void:
	_modal_title.text = title
	_modal_status.text = ""
	_modal_tabs.visible = show_tabs
	_modal_actions.visible = show_actions
	_library_selected.clear()
	_clear_modal_list()
	_modal.show()


func _clear_modal_list() -> void:
	_generation_form = null
	for child in _modal_list.get_children():
		_modal_list.remove_child(child)
		child.queue_free()


func _on_modal_close() -> void:
	if _generator.is_running():
		_generator.cancel()
	if _ai_coordinator != null and _ai_coordinator.is_running():
		_ai_coordinator.cancel_generation()
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	DisplayServer.virtual_keyboard_hide()
	_modal.hide()


func _on_open_library() -> void:
	_open_modal("Kitaplık", true, true)
	_show_library(_library_bucket)


func _show_library(bucket: CustomLevelStore.Bucket) -> void:
	_library_bucket = bucket
	_library_selected.clear()
	_modal_tabs.visible = true
	_modal_actions.visible = true
	_clear_modal_list()

	_library_names = CustomLevelStore.list_names(bucket)
	# Her kovanin kendi sidecar'i var: uretilenlerde kalite/AI bilgisi,
	# kayitlarda "hangi resmi bolumden turedi" bilgisi.
	var manifest: Dictionary
	if bucket == CustomLevelStore.Bucket.GENERATED:
		manifest = _metadata_store.load_all()
	else:
		# Silinen kayitlarin girisleri birikmesin.
		_saved_metadata_store.prune(_library_names)
		manifest = _saved_metadata_store.load_all()
	if _library_names.is_empty():
		_modal_status.text = ("Bu partide bölüm yok - ÜRET ile ara."
			if bucket == CustomLevelStore.Bucket.GENERATED else "Henüz kayıt yok.")
		_refresh_library_actions()
		return

	for entry_name in _library_names:
		var button := _make_list_button("", _on_library_toggle.bind(entry_name))
		button.set_meta("entry", entry_name)
		button.set_meta("generation", manifest.get(entry_name, {}))
		_modal_list.add_child(button)
	_refresh_library_rows()


## Satira dokunmak SECER (acmaz). Acmak ayri bir dugmedir; boylece toplu
## secim yaparken yanlislikla bolum degistirilmez.
func _on_library_toggle(entry_name: String) -> void:
	if _library_selected.has(entry_name):
		_library_selected.erase(entry_name)
	else:
		_library_selected[entry_name] = true
	_refresh_library_rows()


func _refresh_library_rows() -> void:
	for child in _modal_list.get_children():
		var button := child as Button
		if button == null or not button.has_meta("entry"):
			continue
		var entry_name := String(button.get_meta("entry"))
		var mark := "[x]" if _library_selected.has(entry_name) else "[  ]"
		button.text = "%s  %s" % [mark, entry_name]
		var generation = button.get_meta("generation", {})
		if generation is Dictionary and generation.has("quality_score"):
			button.text += " - %d/100" % int(generation["quality_score"])
		if generation is Dictionary and generation.has("difficulty_score"):
			button.text += " - Zorluk %d/100 · Çözüm %d" % [
				int(generation["difficulty_score"]), int(generation.get("solution_count", 0))]
		# Resmi bir bolumden turetilmis kayitlar kaynagini gosterir; boylece
		# listede "hangi bolumun varyantiydi bu" sorusu cevapsiz kalmaz.
		if generation is Dictionary and generation.has("source_level_id"):
			button.text += "  ← Bölüm %d" % int(generation["source_level_id"])
		button.emphasis = LumaButton.Emphasis.PRIMARY if _library_selected.has(entry_name) 			else LumaButton.Emphasis.SECONDARY
	_refresh_library_actions()


func _refresh_library_actions() -> void:
	var count := _library_selected.size()
	_modal_actions.get_node("CopySelected").text = "KOPYALA (%d)" % count
	_modal_actions.get_node("DeleteSelected").text = "SİL (%d)" % count
	# Repoya dogrudan yazma yalnizca masaustunde mumkun (res:// salt okunur).
	_modal_actions.get_node("RepoSelected").visible = CustomLevelStore.can_write_to_repo()
	if count == 0 and not _library_names.is_empty():
		_modal_status.text = "%d bölüm — satırlara dokunup seç" % _library_names.size()


func _selected_names() -> PackedStringArray:
	# Liste sirasi korunur; sozluk sirasina guvenilmez.
	var names := PackedStringArray()
	for entry_name in _library_names:
		if _library_selected.has(entry_name):
			names.append(entry_name)
	return names


func _load_selected_levels() -> Array[LevelData]:
	var levels: Array[LevelData] = []
	for entry_name in _selected_names():
		var loaded := CustomLevelStore.load_level(_library_bucket, entry_name)
		if loaded != null:
			levels.append(loaded)
	return levels


## Secilen satir baslangic noktasidir; kovadaki tum gecerli bolumler partiye
## alinir. Boylece tek satira dokunup DUZENLE denince Sonraki/Onceki ile
## diger uretilen veya kaydedilen adaylara gecilebilir.
func _on_library_edit() -> void:
	var selected_names := _selected_names()
	if selected_names.is_empty():
		_modal_status.text = "Önce en az bir bölüm seç."
		return
	var names := PackedStringArray()
	var levels: Array[LevelData] = []
	var metadata: Array[Dictionary] = []
	var manifest := (
		_metadata_store.load_all()
		if _library_bucket == CustomLevelStore.Bucket.GENERATED else {})
	for entry_name in _library_names:
		var loaded := CustomLevelStore.load_level(_library_bucket, entry_name)
		if loaded == null:
			continue
		names.append(entry_name)
		levels.append(loaded)
		if _library_bucket == CustomLevelStore.Bucket.GENERATED:
			metadata.append(manifest.get(entry_name, {}))
	if levels.is_empty():
		_modal_status.text = "Yüklenemedi."
		return
	_modal.hide()
	var start_index := names.find(selected_names[0])
	_set_batch(levels, names, _library_bucket, metadata, maxi(start_index, 0))
	_status_text = "%d bölüm açıldı — ‹ › ile gez" % levels.size()
	_refresh_info()


func _on_library_copy() -> void:
	var names := _selected_names()
	if names.is_empty():
		_modal_status.text = "Önce en az bir bölüm seç."
		return
	var levels := _load_selected_levels()
	if CustomLevelStore.copy_many_to_clipboard(levels, names):
		_modal_status.text = "%d bölüm panoya kopyalandı (ayraç satırlarıyla)" % levels.size()
	else:
		_modal_status.text = "Kopyalanamadı."


func _on_library_to_repo() -> void:
	var levels := _load_selected_levels()
	if levels.is_empty():
		_modal_status.text = "Önce en az bir bölüm seç."
		return
	var written := CustomLevelStore.save_many_to_repo(levels)
	_modal_status.text = "%d bölüm res://levels/ içine yazıldı" % written


func _on_library_delete() -> void:
	var names := _selected_names()
	if names.is_empty():
		_modal_status.text = "Önce en az bir bölüm seç."
		return
	for entry_name in names:
		CustomLevelStore.delete(_library_bucket, entry_name)
	_show_library(_library_bucket)
	_modal_status.text = "%d bölüm silindi" % names.size()


# --- Uretec -------------------------------------------------------------------

func _on_open_generator() -> void:
	if not OS.is_debug_build():
		return
	_open_modal("Bölüm Üret", false, false)
	_modal_status.text = "Yerel veya OpenRouter AI uretim modunu sec."
	_generation_form = AIGenerationForm.new()
	_generation_form.name = "GenerationForm"
	_generation_form.local_generation_requested.connect(_start_generation)
	_generation_form.local_settings_saved.connect(_on_local_settings_saved)
	_generation_form.ai_generation_requested.connect(_start_ai_generation)
	_generation_form.cancel_requested.connect(_cancel_generation)
	_generation_form.validation_failed.connect(_on_ai_generation_failed)
	_generation_form.status_message.connect(_on_ai_status_changed)
	_modal_list.add_child(_generation_form)


func _start_generation(profile_name: String) -> void:
	var profile: LevelGenerator.Profile
	match profile_name:
		"easy":
			profile = LevelGenerator.Profile.easy()
		"hard":
			profile = LevelGenerator.Profile.hard()
		"blocks":
			profile = LevelGenerator.Profile.with_blocks()
		"obstacles":
			profile = LevelGenerator.Profile.kinetic()
		_:
			profile = LevelGenerator.Profile.medium()

	if _generation_form != null:
		_generation_form.set_busy(true)
	_modal_status.text = "Aranıyor..."
	_generator.generate(profile, 10)


func _on_local_settings_saved(settings: Dictionary) -> void:
	var mechanics: PackedStringArray = settings.get(
		"local_mechanics", PackedStringArray(["panel"]))
	_status_text = "Hızlı üretim ayarı: %d-%d skor, %d mekanik" % [
		int(settings.get("local_score_min", 0)),
		int(settings.get("local_score_max", 100)), mechanics.size()]
	_refresh_info()


func _on_quick_generate() -> void:
	if _generator.is_running() or _ai_coordinator.is_running():
		_status_text = "Üretim zaten devam ediyor."
		_refresh_info()
		return
	var settings := AIGeneratorSettings.new().load_values()
	var profile := LevelGenerator.Profile.custom(settings)
	_quick_generate_button.disabled = true
	_status_text = "%d-%d zorluk skorunda bölüm aranıyor..." % [
		profile.min_difficulty_score, profile.max_difficulty_score]
	_refresh_info()
	# Dar skor bantlari daha fazla eleme yapar; tek bir dogrulanmis aday icin
	# standart parti aramasindan genis ama sonlu bir deneme bütçesi kullanilir.
	_generator.generate(profile, 1, 900)


func _start_ai_generation(request: Dictionary) -> void:
	if _generation_form != null:
		_generation_form.set_busy(true)
	_modal_status.text = "AI taslaklari bekleniyor..."
	var error := _ai_coordinator.start(request)
	if error != OK and _generation_form != null:
		_generation_form.set_busy(false)


func _cancel_generation() -> void:
	if _generator.is_running():
		_generator.cancel()
	if _ai_coordinator.is_running():
		_ai_coordinator.cancel_generation()
	_modal_status.text = "Uretim iptal ediliyor..."


func _on_ai_status_changed(message: String) -> void:
	if _modal.visible:
		_modal_status.text = message


func _on_ai_generation_failed(message: String) -> void:
	if _generation_form != null:
		_generation_form.set_busy(false)
	if _modal.visible:
		_modal_status.text = message


func _on_ai_generation_cancelled() -> void:
	if _generation_form != null:
		_generation_form.set_busy(false)
	if _modal.visible:
		_modal_status.text = "Uretim iptal edildi; onceki parti korundu."


func _on_ai_generation_completed(levels: Array[LevelData], names: PackedStringArray,
		metadata: Array[Dictionary]) -> void:
	if _generation_form != null:
		_generation_form.set_busy(false)
	_modal.hide()
	DisplayServer.virtual_keyboard_hide()
	_set_batch(levels, names, CustomLevelStore.Bucket.GENERATED, metadata)
	_status_text = "%d AI bolumu puanlanip kaydedildi - en iyi aday ilk sirada" % levels.size()
	_refresh_info()


func _on_candidate_evaluated(tried: int, accepted: int) -> void:
	if _modal.visible:
		_modal_status.text = "Aranıyor... %d aday denendi, %d bulundu" % [tried, accepted]


## Parti biter bitmez DISKE yazilir. Onceki surumde yalnizca bellekte
## duruyordu ve listeden birini secmek digerlerini yok ediyordu.
func _on_generation_finished(levels: Array[LevelData]) -> void:
	var rejections := _generator.describe_rejections()
	_quick_generate_button.disabled = false
	if _generation_form != null:
		_generation_form.set_busy(false)
	if levels.is_empty():
		var failure_text := ("Uretim iptal edildi; onceki parti korundu."
			if _generator.was_cancelled()
			else "Uygun aday çıkmadı. Eleme: %s" % rejections)
		if _modal.visible:
			_modal_status.text = failure_text
		else:
			_status_text = failure_text
			_refresh_info()
		return

	var names := CustomLevelStore.replace_generated(levels)
	var metadata := _generator.get_last_generation_records()
	_metadata_store.replace(names, metadata)
	_modal.hide()
	_set_batch(levels, names, CustomLevelStore.Bucket.GENERATED, metadata)
	if levels.size() == 1 and not metadata.is_empty() and metadata[0].has("difficulty_score"):
		_status_text = "Bölüm üretildi: ZORLUK %d/100 - %s | çözüm %d" % [
			int(metadata[0].get("difficulty_score", 0)),
			String(metadata[0].get("difficulty_label", "")),
			int(metadata[0].get("solution_count", 0))]
	else:
		_status_text = "%d bölüm üretildi ve kaydedildi — ‹ › ile gez, beğendiğine KAYDET
Eleme: %s" % [levels.size(), rejections]
	_refresh_info()


func _make_list_button(text: String, action: Callable) -> LumaButton:
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
		Selection.OBSTACLE:
			var obstacle := level.obstacles[_selected_index]
			var marker_size := obstacle.size
			if obstacle.kind != ObstacleData.Kind.MOVING_BAR:
				marker_size = Vector2.ONE * obstacle.size.x
			_draw_marker(obstacle.position, marker_size,
				deg_to_rad(obstacle.rotation_degrees), color)
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
