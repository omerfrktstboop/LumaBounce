extends SceneTree

const AUDIO_AUTOLOAD := "autoload/AudioManager"

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await physics_frame
	_register_audio_manager()
	await _test_mobile_form()
	await _test_cancelled_local_batch()
	await _test_solution_overlay(2, false)
	await _test_solution_overlay(22, true)
	_test_release_guards()
	print("AI ASAMA 4: %d gecti, %d kaldi." % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _register_audio_manager() -> void:
	if Engine.has_singleton("AudioManager"):
		return
	var path := String(ProjectSettings.get_setting(AUDIO_AUTOLOAD, "")).trim_prefix("*")
	var script := load(path) as GDScript
	var node := script.new() as Node
	node.name = "AudioManager"
	root.add_child(node)
	Engine.register_singleton("AudioManager", node)


func _test_mobile_form() -> void:
	var editor: Node = (load("res://scenes/level_editor.tscn") as PackedScene).instantiate()
	editor.level = LevelLibrary.load_level(1)
	root.add_child(editor)
	await process_frame
	editor.call("_on_open_generator")
	await process_frame
	var form := editor.get_node("HUD/Modal/Card/Rows/Scroll/List/GenerationForm") as Control
	_check("iki modlu form aciliyor", form != null, true)
	if form != null:
		_check("yerel mod varsayilan", form.get_node("LocalPage").visible, true)
		form.call("set_busy", true)
		_check("yerel uretimde iptal gorunur", form.get_node("LocalPage/CancelLocal").visible, true)
		form.call("set_busy", false)
		form.call("show_ai_mode")
		var ai_page := form.get_node("AIPage") as Control
		_check("OpenRouter modu gorunuyor", ai_page.visible, true)
		_check("API key maskeli", (ai_page.get_node("APIKey") as LineEdit).secret, true)
		_check("model elle yazilabilir", ai_page.has_node("ModelSlug"), true)
		_check("API key yapistirma dugmesi", ai_page.has_node("PasteAPIKey"), true)
		_check("API key kopyalama dugmesi yok",
			ai_page.find_child("CopyAPIKey", true, false) != null, false)
		_check("model pano dugmeleri", ai_page.find_child("PasteModel", true, false) != null
			and ai_page.find_child("CopyModel", true, false) != null, true)
		_check("tasarim notu pano dugmeleri",
			ai_page.find_child("PasteDesignNote", true, false) != null
			and ai_page.find_child("CopyDesignNote", true, false) != null, true)
		form.call("_apply_paste", "api_key", "  sk-or-test\r\n")
		_check("API key panodan temiz tek satir alinir",
			(ai_page.get_node("APIKey") as LineEdit).text, "sk-or-test")
		form.call("_apply_paste", "model", "  provider/model\n")
		_check("model panodan temiz tek satir alinir",
			(ai_page.get_node("ModelSlug") as LineEdit).text, "provider/model")
		(ai_page.get_node("DesignNote") as TextEdit).clear()
		form.call("_apply_paste", "design_note", "mobil pano notu")
		_check("tasarim notu panodan alinir",
			(ai_page.get_node("DesignNote") as TextEdit).text, "mobil pano notu")
		_check("form ScrollContainer icinde", form.get_parent().get_parent() is ScrollContainer, true)
		var request: Dictionary = form.call("get_request")
		_check("aday siniri 1-20", int(request["candidate_count"]) in range(1, 21), true)
		_check("blueprint siniri 1-10", int(request["blueprint_count"]) in range(1, 11), true)
		_check("varyasyon siniri 1-30", int(request["variation_count"]) in range(1, 31), true)
		form.call("set_busy", true)
		_check("istek surerken ikinci uretim disabled",
			(ai_page.get_node("GenerateAI") as Button).disabled, true)
		_check("istek surerken pano islemleri disabled",
			(ai_page.get_node("PasteAPIKey") as Button).disabled, true)
		_check("istek surerken iptal gorunur", ai_page.get_node("Cancel").visible, true)
		form.call("set_busy", false)
	editor.call("_on_modal_close")
	root.remove_child(editor)
	editor.free()


func _test_cancelled_local_batch() -> void:
	var generator := LevelGenerator.new()
	root.add_child(generator)
	await process_frame
	var produced: Array[LevelData] = []
	generator.finished.connect(func(levels: Array[LevelData]) -> void: produced.assign(levels))
	generator.generate(LevelGenerator.Profile.easy(), 10, 120, 12345)
	await process_frame
	generator.cancel()
	while generator.is_running():
		await process_frame
	_check("iptal edilen yerel parti kayda verilmez", produced.is_empty(), true)
	root.remove_child(generator)
	generator.free()


func _test_solution_overlay(level_id: int, expect_alternative: bool) -> void:
	var editor: Node = (load("res://scenes/level_editor.tscn") as PackedScene).instantiate()
	editor.level = LevelLibrary.load_level(level_id)
	root.add_child(editor)
	await physics_frame
	await physics_frame
	editor.call("_on_solution_pressed")
	var frames := 0
	while bool(editor.get("_solution_busy")) and frames < 300:
		frames += 1
		await process_frame
	var overlay := editor.get_node("SolutionOverlay") as Node2D
	_check("bolum %d solver rotasi" % level_id, overlay.call("has_routes"), true)
	var routes: Array = overlay.get("_routes")
	if not routes.is_empty():
		var route: Dictionary = routes[0]
		var trace: PackedVector2Array = route.get("trace_points", PackedVector2Array())
		_check("bolum %d trace noktasi" % level_id, trace.size() > 2, true)
		_check("bolum %d hedef hit noktasi" % level_id,
			route.get("target_hit_position", Vector2.ZERO) != Vector2.ZERO, true)
		if level_id == 2:
			var collisions: Array = route.get("collision_points", [])
			_check("trace gercek carpisma noktasi iceriyor", collisions.size() > 0, true)
	if expect_alternative:
		_check("bloklu bolumde free/open rota", overlay.call("has_alternative"), true)
		if routes.size() > 1:
			_check("ikinci rota bloklar kirik", int(routes[1].get("prebroken_count", 0)) > 0, true)
	var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	_check("overlay gameplay sahnesine tasmiyor", gameplay.has_node("SolutionOverlay"), false)
	gameplay.free()
	root.remove_child(editor)
	editor.free()


func _test_release_guards() -> void:
	var editor_source := FileAccess.get_file_as_string("res://scripts/editor/level_editor.gd")
	var root_source := FileAccess.get_file_as_string("res://scripts/app_root.gd")
	var client_source := FileAccess.get_file_as_string("res://scripts/editor/openrouter_client.gd")
	_check("LevelEditor release guard", editor_source.contains("if not OS.is_debug_build()"), true)
	_check("AppRoot editor release guard", root_source.contains("func go_to_editor")
		and root_source.contains("if not OS.is_debug_build()"), true)
	_check("OpenRouter release guard", client_source.contains("if not OS.is_debug_build()"), true)


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
		return
	_failed += 1
	print("HATA %s: beklenen %s, gelen %s" % [label, expected, actual])
