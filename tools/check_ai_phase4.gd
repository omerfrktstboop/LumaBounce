extends SceneTree

const AUDIO_AUTOLOAD := "autoload/AudioManager"
const EDITOR_SELECTION_PANEL := 1
const EDITOR_SELECTION_BLOCK := 2
const EDITOR_SELECTION_OBSTACLE := 3
const EDITOR_SELECTION_TARGET := 4

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await physics_frame
	_register_audio_manager()
	_test_difficulty_scorer()
	_test_local_generation_settings()
	await _test_mobile_form()
	await _test_cancelled_local_batch()
	await _test_custom_local_generation()
	await _test_editor_score_and_official_navigation()
	await _test_solution_overlay(2, false)
	await _test_solution_overlay(19, false, true)
	await _test_solution_overlay(27, true)
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
		var local_page := form.get_node("LocalPage") as Control
		_check("yerel mekanik secimi var", local_page.has_node("LocalMechanics"), true)
		_check("yerel minimum skor alani var",
			local_page.find_child("LocalScoreMin", true, false) != null, true)
		_check("yerel maksimum skor alani var",
			local_page.find_child("LocalScoreMax", true, false) != null, true)
		_check("yerel ayar kaydet dugmesi var",
			local_page.has_node("SaveLocalSettings"), true)
		var local_mechanics: Dictionary = form.get("_local_mechanics")
		for mechanic_id in local_mechanics:
			(local_mechanics[mechanic_id] as CheckBox).button_pressed = false
		(local_mechanics["metal_ring"] as CheckBox).button_pressed = true
		(local_mechanics["pulse_laser"] as CheckBox).button_pressed = true
		(form.get("_local_score_min") as SpinBox).value = 72
		(form.get("_local_score_max") as SpinBox).value = 48
		var local_settings: Dictionary = form.call("get_local_settings")
		_check("ters girilen yerel skor araligi duzeltilir",
			Vector2i(local_settings["local_score_min"], local_settings["local_score_max"]),
			Vector2i(48, 72))
		_check("yerel engel secimleri korunur",
			local_settings["local_mechanics"].has("metal_ring")
			and local_settings["local_mechanics"].has("pulse_laser"), true)
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
		var form_script := form as Control
		var template := form_script.get("_template") as OptionButton
		var mechanics: Dictionary = form_script.get("_mechanics")
		for option_index in template.item_count:
			if String(template.get_item_metadata(option_index)) == "block_corridor":
				template.select(option_index)
				form_script.call("_on_template_selected", option_index)
				break
		_check("blok koridoru secimi blogu etkinlestiriyor",
			(mechanics["breakable_block"] as CheckBox).button_pressed, true)
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


func _test_custom_local_generation() -> void:
	var generator := LevelGenerator.new()
	root.add_child(generator)
	await process_frame
	var produced: Array[LevelData] = []
	generator.finished.connect(func(levels: Array[LevelData]) -> void:
		produced.assign(levels))
	var profile := LevelGenerator.Profile.custom({
		"local_mechanics": PackedStringArray(["panel"]),
		"local_score_min": 0,
		"local_score_max": 100,
	})
	generator.generate(profile, 1, 200, 24680)
	var frames := 0
	while generator.is_running() and frames < 1200:
		frames += 1
		await process_frame
	var metadata := generator.get_last_generation_records()
	_check("ozel yerel profil gercek fizikte bolum uretir", produced.size(), 1)
	_check("ozel yerel uretim skor metadatasi tasir",
		metadata.size() == 1 and metadata[0].has("difficulty_score"), true)
	if not metadata.is_empty():
		_check("ozel yerel uretim skoru 0-100 araliginda",
			int(metadata[0].get("difficulty_score", -1)) in range(0, 101), true)
	root.remove_child(generator)
	generator.free()


func _test_difficulty_scorer() -> void:
	var easy_level := LevelData.new()
	var easy := LevelDifficultyScorer.evaluate(
		easy_level,
		{"hit_count": 120, "total": 1000, "min_bounces": 0},
		{"robust": 24, "bounces": 0})

	var hard_level := LevelData.new()
	for i in 4:
		var panel := PanelData.new()
		panel.position = Vector2(140.0 + 120.0 * i, 700.0 - 80.0 * i)
		hard_level.panels.append(panel)
	var hard := LevelDifficultyScorer.evaluate(
		hard_level,
		{"hit_count": 2, "total": 1000, "min_bounces": 6},
		{"robust": 0, "bounces": 9999})
	_check("dar ve sekmeli rota daha zor", int(hard["score"]) > int(easy["score"]), true)
	_check("kolay skor etiketi", easy["label"], "KOLAY")
	_check("zor skor 1-5 etiketi", int(hard["tier"]) >= 3, true)

	var gated := LevelDifficultyScorer.evaluate(
		hard_level,
		{"hit_count": 0, "total": 1000, "min_bounces": 0},
		{"robust": 0, "bounces": 9999},
		{"hit_count": 12, "total": 1000, "min_bounces": 3},
		{"robust": 0, "bounces": 9999})
	_check("bloklar kirik rota algilaniyor", gated["route_state"], "opened")
	_check("kapali rota zorluk ekliyor", int(gated["breakdown"]["block_gate"]), 10)

	var impossible := LevelDifficultyScorer.evaluate(
		easy_level,
		{"hit_count": 0, "total": 1000}, {"robust": 0})
	_check("cozumsuz tasarim 100", impossible["score"], 100)
	_check("cozumsuz tasarim etiketi", impossible["label"], "COZUMSUZ")

	var single_solution := LevelDifficultyScorer.evaluate(
		easy_level, {"hit_count": 1, "total": 1000, "min_bounces": 0},
		{"robust": 0, "bounces": 0})
	var ten_solutions := LevelDifficultyScorer.evaluate(
		easy_level, {"hit_count": 10, "total": 1000, "min_bounces": 0},
		{"robust": 0, "bounces": 0})
	_check("tek cozum cesitlilik cezasi aliyor",
		single_solution["breakdown"]["solution_variety"], 10)
	_check("on cozum cesitlilik cezasini kaldiriyor",
		ten_solutions["breakdown"]["solution_variety"], 0)
	_check("on cozum tek cozumden daha kolay puanlaniyor",
		int(ten_solutions["score"]) < int(single_solution["score"]), true)
	_check("skor ozetinde cozum sayisi yaziyor",
		LevelDifficultyScorer.summary(ten_solutions).contains("cozum 10"), true)


func _test_editor_score_and_official_navigation() -> void:
	var editor: Node = (load("res://scenes/level_editor.tscn") as PackedScene).instantiate()
	var first := LevelLibrary.load_level(1).duplicate(true) as LevelData
	first.display_name = "Test Official Navigation"
	if first.panels.is_empty():
		var test_panel := PanelData.new()
		test_panel.position = Vector2(360.0, 720.0)
		first.panels.append(test_panel)
	var test_block := BreakableBlockData.new()
	test_block.position = Vector2(120.0, 560.0)
	first.breakable_blocks.append(test_block)
	var test_obstacle := ObstacleData.new()
	test_obstacle.kind = ObstacleData.Kind.MOVING_BAR
	test_obstacle.position = Vector2(600.0, 560.0)
	first.obstacles.append(test_obstacle)
	editor.level = first
	editor.source_level_id = 1
	root.add_child(editor)
	await physics_frame
	await physics_frame
	var bottom_panel := editor.get_node("HUD/SafeArea/Root/BottomPanel") as Control
	var editor_camera := editor.get_node("EditorCamera") as Camera2D
	var collapse := editor.get_node("HUD/SafeArea/Root/TopBar/CollapseButton") as Button
	_check("editor paneli acikken arena kuculur", editor_camera.zoom.x < 1.0, true)
	editor.call("_set_panel_visible", false)
	_check("editor paneli kapaninca oyun olcegine doner", editor_camera.zoom, Vector2.ONE)
	_check("kapali panel ust sekmeden acilabilir", collapse.text, "▴")
	var closed_context: Dictionary = editor.call("get_batch_context")
	_check("test donusu icin kapali panel durumu saklanir",
		bool(closed_context.get("panel_visible", true)), false)
	editor.call("_set_panel_visible", true)
	editor.call("_restore_batch_context", closed_context)
	_check("testten donuste editor paneli kapali kalir", bottom_panel.visible, false)
	editor.call("_set_panel_visible", true)
	_check("ust sekme editor panelini geri acar", bottom_panel.visible, true)
	_check("hizli uretim dugmesi var", editor.get_node(
		"HUD/SafeArea/Root/BottomPanel/Rows/ActionRow/QuickGenerateButton") != null, true)
	var test_emitted := [false]
	editor.test_requested.connect(func(_tested_level: LevelData) -> void:
		test_emitted[0] = true)
	editor.call("_on_test")
	_check("TEST editor panelini kapatir", bottom_panel.visible, false)
	_check("TEST bolumu oynanisa yollar", test_emitted[0], true)
	editor.call("_set_panel_visible", true)

	var row := editor.get_node("HUD/SafeArea/Root/BottomPanel/Rows/BatchRow") as Control
	var previous := row.get_node("PrevLevel") as Button
	var next := row.get_node("NextLevel") as Button
	var label := row.get_node("BatchLabel") as Label
	_check("resmi bolum ok satiri gorunur", row.visible, true)
	_check("resmi bolum numarasi gorunur", label.text.begins_with("BOLUM 1 /"), true)
	_check("ilk bolumde onceki kapali", previous.disabled, true)
	_check("ilk bolumde sonraki acik", next.disabled, false)

	var rotate := editor.get_node(
		"HUD/SafeArea/Root/BottomPanel/Rows/TuneRow/Rotate90") as Button
	var thickness := editor.get_node(
		"HUD/SafeArea/Root/BottomPanel/Rows/TuneRow/ThicknessCycle") as Button
	var add_strong := editor.get_node(
		"HUD/SafeArea/Root/BottomPanel/Rows/AddRow/AddStrongBlock") as Button
	var copy_item := editor.get_node(
		"HUD/SafeArea/Root/BottomPanel/Rows/AddRow/CopyItem") as Button
	_check("90 derece dondurme dugmesi var", rotate != null, true)
	_check("engel kalinlik dugmesi var", thickness != null, true)
	_check("guclendirilmis blok dugmesi var", add_strong != null, true)
	_check("secili parcayi kopyalama dugmesi var", copy_item != null, true)
	editor.set("_selection", EDITOR_SELECTION_PANEL)
	editor.set("_selected_index", 0)
	editor.call("_refresh_info")
	var panel_angle := first.panels[0].rotation_degrees
	rotate.pressed.emit()
	_check("panel tek dokunusta 90 derece donuyor",
		fposmod(first.panels[0].rotation_degrees - panel_angle, 180.0), 90.0)
	editor.set("_selection", EDITOR_SELECTION_BLOCK)
	editor.set("_selected_index", 0)
	editor.call("_refresh_info")
	rotate.pressed.emit()
	_check("blok tek dokunusta 90 derece donuyor",
		fposmod(first.breakable_blocks[0].rotation_degrees, 180.0), 90.0)
	var old_block_thickness := first.breakable_blocks[0].size.y
	thickness.pressed.emit()
	_check("blok kalinligi dugmeyle degisiyor",
		first.breakable_blocks[0].size.y != old_block_thickness, true)
	var thickness_levels := {}
	var thickness_value := 20.0
	for _index in range(5):
		thickness_levels[thickness_value] = true
		thickness_value = float(editor.call(
			"_next_thickness", thickness_value, 20.0, 80.0))
	_check("kalinlik bes farkli kademe kullaniyor", thickness_levels.size(), 5)
	_check("besinci kademeden sonra inceye donuyor", thickness_value, 20.0)
	var block_count := first.breakable_blocks.size()
	add_strong.pressed.emit()
	_check("guclendirilmis blok ekleniyor", first.breakable_blocks.size(), block_count + 1)
	_check("guclendirilmis blok iki canli",
		first.breakable_blocks[-1].hit_points, 2)
	editor.set("_selection", EDITOR_SELECTION_OBSTACLE)
	editor.set("_selected_index", 0)
	editor.call("_refresh_info")
	var obstacle_count := first.obstacles.size()
	var original_obstacle := first.obstacles[0]
	copy_item.pressed.emit()
	_check("secili engel kopyalaniyor", first.obstacles.size(), obstacle_count + 1)
	var copied_obstacle := first.obstacles[-1]
	_check("engel kopyasi tur ve boyutu koruyor",
		copied_obstacle.kind == original_obstacle.kind
		and copied_obstacle.size == original_obstacle.size, true)
	_check("engel kopyasi gorunur bir miktar kaydiriliyor",
		copied_obstacle.position != original_obstacle.position, true)
	editor.set("_selected_index", 0)
	editor.call("_refresh_info")
	rotate.pressed.emit()
	_check("engel tek dokunusta 90 derece donuyor",
		fposmod(first.obstacles[0].rotation_degrees, 360.0), 90.0)
	var old_thickness := first.obstacles[0].size.y
	thickness.pressed.emit()
	_check("engel kalinligi tek dugmeyle degisiyor",
		first.obstacles[0].size.y != old_thickness, true)
	_check("kayan engel kalinligi gecerli aralikta",
		first.obstacles[0].size.y >= 20.0 and first.obstacles[0].size.y <= 72.0, true)
	editor.set("_selection", EDITOR_SELECTION_TARGET)
	editor.call("_refresh_info")
	_check("hedef seciminde dondurme kapali", rotate.disabled, true)
	_check("hedef seciminde kalinlik kapali", thickness.disabled, true)
	_check("hedef seciminde kopyalama kapali", copy_item.disabled, true)
	var target_scale_before := first.target_scale
	var target_smaller := editor.get_node(
		"HUD/SafeArea/Root/BottomPanel/Rows/TuneRow/AMinus") as Button
	target_smaller.pressed.emit()
	_check("hedef A eksi ile kuculuyor",
		is_equal_approx(first.target_scale, maxf(target_scale_before - 0.1, 0.5)), true)
	var target_preview := editor.get("_target_preview") as Node2D
	_check("hedef onizleme olcegi veriyi izliyor",
		is_equal_approx(target_preview.scale.x, first.target_scale), true)
	for _index in range(20):
		target_smaller.pressed.emit()
	_check("hedef minimum boyutta sinirlaniyor", first.target_scale, 0.5)
	first.target_scale = target_scale_before
	editor.call("_rebuild")

	editor.call("_on_analyse")
	var frames := 0
	while bool(editor.get("_analysis_busy")) and frames < 600:
		frames += 1
		await process_frame
	var result: Dictionary = editor.get("_last_difficulty_result")
	_check("editor zorluk skoru hesaplandi", not result.is_empty(), true)
	_check("editor zorluk skoru aralikta", int(result.get("score", -1)) in range(0, 101), true)
	_check("editor skor metni gorunur", String(editor.get("_status_text")).begins_with("ZORLUK"), true)

	var expected_name := CustomLevelStore.entry_name_for(editor.call("_saved_name_for_current"))
	CustomLevelStore.delete(CustomLevelStore.Bucket.SAVED, expected_name)
	editor.call("_on_save")
	await process_frame
	var saved_meta := GenerationMetadataStore.new(
		GenerationMetadataStore.SAVED_MANIFEST_PATH).get_entry(expected_name)
	_check("kayitta zorluk skoru sakli", int(saved_meta.get("difficulty_score", -1)),
		int(result.get("score", -2)))
	_check("kayitta cozum sayisi sakli", int(saved_meta.get("solution_count", -1)),
		int(result.get("solution_count", -2)))

	editor.call("_on_batch_step", 1)
	await process_frame
	_check("okla ikinci resmi bolume geciliyor", editor.source_level_id, 2)
	_check("ikinci resmi bolum yuklendi", editor.level.level_id, 2)
	editor.call("_on_batch_step", -1)
	await process_frame
	_check("okla ilk resmi bolume donuluyor", editor.source_level_id, 1)

	CustomLevelStore.delete(CustomLevelStore.Bucket.SAVED, expected_name)
	var saved_store := GenerationMetadataStore.new(GenerationMetadataStore.SAVED_MANIFEST_PATH)
	saved_store.prune(CustomLevelStore.list_names(CustomLevelStore.Bucket.SAVED))
	root.remove_child(editor)
	editor.free()


func _test_local_generation_settings() -> void:
	var temp_path := "user://test_ai_local_settings.cfg"
	var settings := AIGeneratorSettings.new(temp_path)
	var safe := settings.sanitize({
		"local_mechanics": PackedStringArray([
			"wall_gap", "breakable_block", "metal_ring", "pulse_laser", "gecersiz"]),
		"local_score_min": 88,
		"local_score_max": 42,
	})
	_check("yerel ayar bilinmeyen mekanigi eler",
		safe["local_mechanics"].has("gecersiz"), false)
	_check("yerel ayar skor sinirini siralar",
		Vector2i(safe["local_score_min"], safe["local_score_max"]), Vector2i(42, 88))
	_check("yerel ayar diske kaydedilir", settings.save_values(safe), OK)
	var loaded := settings.load_values()
	_check("yerel skor araligi diskten geri yuklenir",
		Vector2i(loaded["local_score_min"], loaded["local_score_max"]), Vector2i(42, 88))
	_check("yerel mekanikler diskten geri yuklenir",
		loaded["local_mechanics"].has("pulse_laser"), true)
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	var profile := LevelGenerator.Profile.custom(safe)
	_check("ozel profil skor filtresini acar", profile.enforce_difficulty_score, true)
	_check("ozel profil paneli secilmediyse eklemez", profile.panel_count, Vector2i.ZERO)
	_check("ozel profil duvar boslugu ekler", profile.wall_gap_count.x > 0, true)
	_check("ozel profil secilen engellerin hepsini zorunlu tutar",
		profile.include_each_obstacle_kind and profile.obstacle_kinds.size() == 2, true)
	var generator := LevelGenerator.new()
	var generated: LevelData = generator.call("_random_level", profile)
	_check("ozel aday kirilabilir blok icerir", generated.breakable_blocks.size() > 0, true)
	_check("ozel aday duvar boslugu icerir",
		generated.left_wall_segments.size() == 2
		or generated.right_wall_segments.size() == 2, true)
	var generated_kinds: Array[int] = []
	for obstacle in generated.obstacles:
		if not generated_kinds.has(obstacle.kind):
			generated_kinds.append(obstacle.kind)
	_check("ozel aday halka ve lazeri birlikte icerir",
		generated_kinds.has(ObstacleData.Kind.METAL_RING)
		and generated_kinds.has(ObstacleData.Kind.PULSE_LASER), true)
	_check("skor filtresi bant icini kabul eder",
		generator.call("_difficulty_score_matches", profile, {"score": 60}), true)
	_check("skor filtresi bant disini eler",
		generator.call("_difficulty_score_matches", profile, {"score": 90}), false)
	generator.free()


func _test_solution_overlay(level_id: int, expect_alternative: bool,
		expect_refined := false) -> void:
	var editor: Node = (load("res://scenes/level_editor.tscn") as PackedScene).instantiate()
	var tested_level := LevelLibrary.load_level(level_id)
	editor.level = tested_level
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
	_check("bolum %d en fazla on rota" % level_id, routes.size() <= 10, true)
	if not routes.is_empty():
		var route: Dictionary = routes[0]
		_check("bolum %d rota skorunu tasiyor" % level_id,
			route.has("difficulty_score"), true)
		_check("bolum %d rota cozum sayisini tasiyor" % level_id,
			int(route.get("solution_count", 0)) > 0, true)
		var trace: PackedVector2Array = route.get("trace_points", PackedVector2Array())
		_check("bolum %d trace noktasi" % level_id, trace.size() > 2, true)
		_check("bolum %d hedef hit noktasi" % level_id,
			route.get("target_hit_position", Vector2.ZERO) != Vector2.ZERO, true)
		if expect_refined:
			_check("bolum %d panel ucu hassas tarama" % level_id,
				int(route.get("solution_search_passes", 1)) > 1, true)
			_check("bolum %d hassas tarama aci adimi" % level_id,
				float(route.get("solution_angle_step", 3.0)) <= 1.0, true)
			_check("bolum %d hassas rota komsu destegi" % level_id,
				int(route.get("fallback_neighbours", 0)) > 0, true)
			_check("bolum %d rota panel ucuna temas ediyor" % level_id,
				_route_has_panel_end_contact(
					tested_level, route.get("collision_points", [])), true)
		if level_id == 2:
			var collisions: Array = route.get("collision_points", [])
			_check("trace gercek carpisma noktasi iceriyor", collisions.size() > 0, true)
	if expect_alternative:
		_check("bloklu bolumde free/open rota", overlay.call("has_alternative"), true)
		if routes.size() > 1:
			_check("ikinci rota bloklar kirik", int(routes[1].get("prebroken_count", 0)) > 0, true)
	if level_id == 2:
		_check("genis bolum birden fazla cozum gosteriyor", routes.size() > 1, true)
		for expected_index in range(1, routes.size()):
			editor.call("_on_solution_pressed")
			_check("cozum dugmesi rota %d gecisi" % (expected_index + 1),
				overlay.call("current_index"), expected_index)
	var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	_check("overlay gameplay sahnesine tasmiyor", gameplay.has_node("SolutionOverlay"), false)
	gameplay.free()
	root.remove_child(editor)
	editor.free()


func _route_has_panel_end_contact(level: LevelData, collisions: Array) -> bool:
	for collision in collisions:
		var hit_position: Vector2 = collision.get("position", Vector2.ZERO)
		for panel in level.panels:
			var local := (hit_position - panel.position).rotated(
				-deg_to_rad(panel.rotation_degrees))
			var cap_offset := maxf((panel.length - panel.thickness) * 0.5, 0.0)
			for side in [-1.0, 1.0]:
				# Carpisma noktasi topun merkezidir; 55 px, panel yaricapi ile
				# 24 px top yaricapini ve kucuk fizik toleransini kapsar.
				if local.distance_to(Vector2(cap_offset * side, 0.0)) <= 55.0:
					return true
	return false


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
