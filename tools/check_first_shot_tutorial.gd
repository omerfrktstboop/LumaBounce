extends SceneTree

## Focused onboarding regression, no real saves, SDK requests or level edits.
class MemoryProgress extends ProgressStore:
	var writes = 0
	func save() -> void:
		writes += 1

var _failed = 0
var _passed = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_migration()
	await _test_input_and_retry()
	await _test_skip_and_existing_player()
	await _test_replay()
	_check("all test sections executed", _passed + _failed >= 51)
	print("FIRST SHOT: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed else 0)


func _test_migration() -> void:
	var progress = MemoryProgress.new()
	_check("new player needs tutorial", progress.needs_first_shot_tutorial())
	var old = MemoryProgress.new()
	old._read(ConfigFile.new())
	_check("existing save is not forced through tutorial", not old.needs_first_shot_tutorial())
	var pending = ConfigFile.new()
	pending.set_value(ProgressStore.SECTION_SETTINGS, ProgressStore.KEY_FIRST_SHOT_TUTORIAL, 0)
	old._read(pending)
	_check("explicit incomplete tutorial resumes", old.needs_first_shot_tutorial())
	old.finish_first_shot_tutorial()
	old.finish_first_shot_tutorial()
	_check("completion writes once", old.writes == 1)
	_check("completion stored at current version",
		old.first_shot_tutorial_version == ProgressStore.FIRST_SHOT_TUTORIAL_VERSION)
	old.reset()
	_check("progress reset preserves tutorial preference", not old.needs_first_shot_tutorial())
	progress.completed_levels.append(1)
	_check("completed level avoids forced tutorial", not progress.needs_first_shot_tutorial())
	var future = ConfigFile.new()
	future.set_value(ProgressStore.SECTION_SETTINGS, ProgressStore.KEY_FIRST_SHOT_TUTORIAL, 5)
	old._read(future)
	old.finish_first_shot_tutorial()
	_check("future tutorial version is preserved", old.first_shot_tutorial_version == 5)


func _game(progress: ProgressStore, replay = false):
	var game = (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	game.level_data = LevelLibrary.load_level(1)
	game.progress = progress
	game.tutorial_replay = replay
	game.practice_mode = replay
	root.add_child(game)
	return game


func _touch(game: Node, pressed: bool, at: Vector2, index = 0) -> void:
	var event = InputEventScreenTouch.new()
	event.position = at
	event.pressed = pressed
	event.index = index
	game._unhandled_input(event)


func _drag(game: Node, at: Vector2) -> void:
	var event = InputEventScreenDrag.new()
	event.position = at
	game._unhandled_input(event)


func _test_input_and_retry() -> void:
	var progress = MemoryProgress.new()
	var game = _game(progress)
	var app = load("res://scripts/app_root.gd").new()
	app.set("_progress", progress)
	game.first_shot_tutorial_finished.connect(app._on_first_shot_tutorial_finished.bind(game))
	await process_frame
	var tutorial = game.get_node("HUD/SafeArea/Root/FirstShotTutorial")
	var launcher = game.get_node("Launcher") as Launcher
	var at = game.get_canvas_transform() * launcher.get_spawn_position()
	_check("fresh first level shows tutorial", tutorial.is_active())
	_check("whole entry suppresses engagement", game.suppress_engagement_prompts())
	_check("hint purchases unavailable during tutorial", (game.get_node(
		"HUD/SafeArea/Root/HintButton") as BaseButton).disabled)
	game._pointer_pressed(Vector2(10, 10))
	_check("touch outside ball does not begin", not launcher.is_aiming())
	_touch(game, true, at)
	_check("touch advances to drag", tutorial.step == tutorial.Step.DRAG)
	_drag(game, at + Vector2(0, 8))
	_check("tiny drag does not advance", tutorial.step == tutorial.Step.DRAG)
	_touch(game, false, at + Vector2(0, 8))
	_check("invalid release returns to touch", tutorial.step == tutorial.Step.TOUCH)
	_touch(game, true, at)
	_drag(game, at + Vector2(0, 50))
	_check("valid aim teaches power", tutorial.step == tutorial.Step.POWER)
	_touch(game, true, at, 1)
	_check("second touch cancels aim", tutorial.step == tutorial.Step.TOUCH)
	_touch(game, false, at, 1)
	_touch(game, false, at)
	_touch(game, true, at)
	_drag(game, at + Vector2(0, 50))
	_touch(game, false, at + Vector2(0, 50))
	_check("early release can fly without completing", tutorial.step == tutorial.Step.FLIGHT)
	var lives: int = game.get("_lives_remaining")
	game._on_shot_failed("test_miss")
	_check("incomplete tutorial does not exhaust lives", int(game.get("_lives_remaining")) == lives)
	game.reset_shot()
	_check("retry returns to touch", tutorial.step == tutorial.Step.TOUCH)
	_touch(game, true, at)
	_drag(game, at + Vector2(0, 50))
	_drag(game, at + Vector2(0, 90))
	_check("power adjustment reaches release", tutorial.step == tutorial.Step.RELEASE)
	_touch(game, false, at + Vector2(0, 90))
	_check("actual release completes", not tutorial.is_active())
	_check("actual release still fires ball", (game.get_node("Ball") as Ball).is_flying())
	_check("AppRoot persists completion once", progress.writes == 1)
	_check("first result remains ad-free", game.suppress_engagement_prompts())
	_check("touch state cleaned", (game.get("_touch_indices") as Array).is_empty())
	game.queue_free()
	app.free()
	await process_frame
	await create_timer(0.4).timeout


func _test_skip_and_existing_player() -> void:
	var progress = MemoryProgress.new()
	var game = _game(progress)
	await process_frame
	var tutorial = game.get_node("HUD/SafeArea/Root/FirstShotTutorial")
	var launcher = game.get_node("Launcher") as Launcher
	var at = game.get_canvas_transform() * launcher.get_spawn_position()
	var mouse = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = at
	game._unhandled_input(mouse)
	_check("mouse also starts tutorial gesture", tutorial.step == tutorial.Step.DRAG)
	game.set_app_paused(true)
	_check("background cancels gesture", tutorial.step == tutorial.Step.TOUCH)
	game.set_app_paused(false)
	game._unhandled_input(mouse)
	tutorial.finish(true)
	_check("skip clears active aim", not launcher.is_aiming())
	_check("skip restores hint button", not (game.get_node(
		"HUD/SafeArea/Root/HintButton") as BaseButton).disabled)
	game.queue_free()
	await process_frame
	progress.first_shot_tutorial_version = 1
	game = _game(progress)
	_check("existing player sees no forced tutorial", not game.is_first_shot_tutorial_active())
	_check("normal entry allows ad policy", not game.suppress_engagement_prompts())
	game.queue_free()
	await process_frame


func _test_replay() -> void:
	var app = load("res://scripts/app_root.gd").new()
	var progress = MemoryProgress.new()
	progress.completed_levels.assign([1, 2, 3])
	progress.highest_unlocked_level = 4
	progress.level_stars = {1: 3, 2: 2, 3: 1}
	progress.first_shot_tutorial_version = 1
	app.set("_progress", progress)
	var game = (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	app._configure_tutorial(game)
	root.add_child(game)
	await process_frame
	_check("settings replay forces tutorial", game.is_first_shot_tutorial_active())
	_check("replay uses practice mode", game.practice_mode and game.tutorial_replay)
	_check("replay has player-facing header", (game.get_node(
		"HUD/SafeArea/Root/LevelHeader/LevelTitle") as Label).text == tr("HOW_TO_PLAY"))
	_check("replay has no wallet, analytics or ad service",
		game.wallet == null and game.analytics == null and game.ad_service == null)
	app._on_bounce_recorded(game)
	_check("replay does not write progress", progress.writes == 0)
	_check("replay preserves stars", progress.level_stars == {1: 3, 2: 2, 3: 1})
	_check("replay preserves unlocked level", progress.highest_unlocked_level == 4)
	var tutorial = game.get_node("HUD/SafeArea/Root/FirstShotTutorial")
	var launcher = game.get_node("Launcher")
	var at = game.get_canvas_transform() * launcher.get_spawn_position()
	game._pointer_pressed(at)
	game._pointer_moved(at + Vector2(0, 50))
	game._on_tutorial_viewport_resized()
	_check("rotation cancels old aim", not launcher.is_aiming())
	_check("rotation resets gesture step", tutorial.step == tutorial.Step.TOUCH)
	for language in ["tr", "en", "es", "pt_BR", "de", "fr"]:
		TranslationServer.set_locale(language)
		tutorial.start()
		tutorial.aim_started()
		tutorial.aim_updated(true, 0.3)
		await process_frame
		await process_frame
		var card: PanelContainer = tutorial.get("_card")
		_check("card fits safe width " + language, card.size.x <= tutorial.size.x + 1)
		var body: Label = tutorial.get("_body")
		_check("translated power text " + language, not body.text.begins_with("FIRST_SHOT_"))
		_check("replay header follows locale " + language, (game.get_node(
			"HUD/SafeArea/Root/LevelHeader/LevelTitle") as Label).text == tr("HOW_TO_PLAY"))
	game.queue_free()
	app.free()
	await process_frame


func _check(label: String, passed: bool) -> void:
	if passed:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: " + label)
