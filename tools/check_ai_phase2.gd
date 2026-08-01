extends SceneTree

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_test_mapper()
	_test_bounce_band_analysis()
	await _test_variations_and_solver()
	print("AI ASAMA 2: %d gecti, %d kaldi." % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_mapper() -> void:
	var mapper := AILevelMapper.new()
	var valid := _raw_level()
	valid["level_id"] = 999
	valid["launcher"] = {"x": -500, "y": 9999}
	valid["target"] = {"x": 9999, "y": -500}
	valid["panels"][0]["thickness"] = 999
	valid["blocks"][0]["height"] = 999
	valid["script"] = "res://do_not_load.gd"
	var mapped := mapper.map_document({"levels": [valid]})
	_check("gecerli belge mapleniyor", mapped["ok"], true)
	var blueprint: Dictionary = mapped["blueprints"][0]
	var level: LevelData = blueprint["level"]
	_check("AI level_id yok sayiliyor", level.level_id, 1)
	_check("launcher guvenli alana clamp", level.launcher_position, Vector2(100, 1180))
	_check("target guvenli alana clamp", level.target_position, Vector2(640, 180))
	_check("panel kalinligi standart", level.panels[0].thickness, AILevelMapper.PANEL_THICKNESS)
	_check("blok yuksekligi standart", level.breakable_blocks[0].size.y, AILevelMapper.BLOCK_HEIGHT)
	_check("beklenmeyen path alani tasinmiyor", blueprint.has("script"), false)
	var missing := _raw_level()
	missing.erase("target")
	_check("eksik target reddediliyor", mapper.map_document({"levels": [missing]})["ok"], false)
	var non_finite := _raw_level()
	non_finite["target"]["x"] = INF
	_check("INF reddediliyor", mapper.map_document({"levels": [non_finite]})["ok"], false)
	var crowded := _raw_level()
	for _i in AILevelContract.MAX_PANELS:
		crowded["panels"].append(crowded["panels"][0].duplicate(true))
	_check("fazla panel reddediliyor", mapper.map_document({"levels": [crowded]})["ok"], false)


func _test_bounce_band_analysis() -> void:
	var angles: Array[float] = [-3.0, 0.0, 3.0]
	var powers: Array[float] = [1000.0, 1100.0, 1200.0]
	var scan := {
		"angles": angles,
		"powers": powers,
		"hits": [
			[false, false, false],
			[true, true, false],
			[false, true, true],
		],
		"bounces": [
			[-1, -1, -1],
			[2, 6, -1],
			[-1, 6, 7],
		],
	}
	var band := LevelSolver.analyse_bounce_band(scan, 5, 10)
	_check("sekme bandi bitisik hucreleri kumeliyor", band["largest_cluster"], 3)
	_check("sekme bandi kisa yolu ayri sayiyor", band["largest_shortcut"], 1)


func _test_variations_and_solver() -> void:
	var generator := LevelGenerator.new()
	root.add_child(generator)
	await process_frame
	var original := LevelLibrary.load_level(4)
	var blueprint := {"level": original, "blueprint_index": 2, "design_intent": "test"}
	var first := generator.build_blueprint_variations([blueprint], 2, 4242)
	var second := generator.build_blueprint_variations([blueprint], 2, 4242)
	_check("orijinal blueprint dahil", first.size(), 3)
	_check("orijinal ilk sirada", (first[0]["level"] as LevelData).target_position, original.target_position)
	_check("orijinal seed sifir", first[0]["variation_seed"], 0)
	_check("ayni seed hedefi tekrarliyor",
		(first[1]["level"] as LevelData).target_position,
		(second[1]["level"] as LevelData).target_position)
	_check("ayni seed paneli tekrarliyor",
		(first[1]["level"] as LevelData).panels[0].position,
		(second[1]["level"] as LevelData).panels[0].position)
	_check("varyasyon seed kayitli", int(first[1]["variation_seed"]) != 0, true)
	var tiered := generator.build_blueprint_variations([blueprint], 12, 4242)
	_check("ilk varyasyon ince arama", float(tiered[1]["variation_scale"]), 1.0)
	_check("orta varyasyon orta arama", float(tiered[5]["variation_scale"]), 2.0)
	_check("son varyasyon genis arama", float(tiered[9]["variation_scale"]), 3.0)
	var guided := generator.build_blueprint_variations(
		[blueprint], 12, 4242, LevelGenerator.Profile.medium())
	var guided_target: Vector2 = (guided[9]["level"] as LevelData).target_position
	_check("genis arama hedefi orta profil bandinda",
		guided_target.y >= 235.0 and guided_target.y <= 345.0, true)
	var hard_guided := generator.build_blueprint_variations(
		[blueprint], 12, 7331, LevelGenerator.Profile.hard())
	_check("zor son kademe fizik kurtarma olarak isaretli",
		bool(hard_guided[9]["physics_rescue"]), true)
	_check("zor kurtarma AI taslagindan farkli",
		(hard_guided[9]["level"] as LevelData).panels[0].position
		!= original.panels[0].position, true)
	var rescue_signatures := {}
	for diversity_seed in [7331, 17731, 27731, 37731]:
		var diversity_batch := generator.build_blueprint_variations(
			[blueprint], 12, diversity_seed, LevelGenerator.Profile.hard())
		var rescue_level := diversity_batch[9]["level"] as LevelData
		var first_panel: PanelData = rescue_level.panels[0]
		var signature := "%d:%d:%d:%d:%d" % [
			roundi(rescue_level.target_position.x), roundi(rescue_level.target_position.y),
			roundi(first_panel.position.x), roundi(first_panel.position.y),
			roundi(first_panel.rotation_degrees),
		]
		rescue_signatures[signature] = true
	_check("dort uretim seed'i en az uc farkli kurtarma geometrisi veriyor",
		rescue_signatures.size() >= 3, true)
	var hard_sources: Array = []
	for hard_index in range(9, 13):
		hard_sources.append(hard_guided[hard_index])
	var hard_records: Array[Dictionary] = []
	generator.blueprints_finished.connect(
		func(items: Array[Dictionary]) -> void: hard_records.assign(items),
		CONNECT_ONE_SHOT)
	generator.generate_from_blueprints(
		LevelGenerator.Profile.hard(), hard_sources, 4, 0, 7331)
	while generator.is_running():
		await process_frame
	if hard_records.is_empty():
		print("ZOR KURTARMA RET: %s" % generator.describe_rejections())
	_check("zor kurtarmadan solver adayi cikiyor", hard_records.is_empty(), false)
	var novel_hard := 0
	var novelty_scorer := LevelNoveltyScorer.new()
	var references := novelty_scorer.default_references()
	for hard_record in hard_records:
		var hard_novelty := novelty_scorer.score(
			hard_record["level"], hard_record["solver"], references)
		if not bool(hard_novelty["reject"]):
			novel_hard += 1
	_check("zor kurtarma resmi bolum kopyasi degil", novel_hard > 0, true)
	var block_source := original.duplicate(true) as LevelData
	var hard_block := BreakableBlockData.new()
	hard_block.position = Vector2(360.0, 650.0)
	hard_block.size = Vector2(300.0, 44.0)
	block_source.breakable_blocks = [hard_block]
	var block_guided := generator.build_blueprint_variations(
		[{"level": block_source, "blueprint_index": 3}], 12, 9182,
		LevelGenerator.Profile.hard())
	var block_sources: Array = []
	for block_index in range(9, 13):
		block_sources.append(block_guided[block_index])
	var block_records: Array[Dictionary] = []
	generator.blueprints_finished.connect(
		func(items: Array[Dictionary]) -> void: block_records.assign(items),
		CONNECT_ONE_SHOT)
	generator.generate_from_blueprints(
		LevelGenerator.Profile.hard(), block_sources, 4, 0, 9182)
	while generator.is_running():
		await process_frame
	if block_records.is_empty():
		print("BLOKLU ZOR KURTARMA RET: %s" % generator.describe_rejections())
	_check("bloklu zor kurtarmadan solver adayi cikiyor", block_records.is_empty(), false)
	var ricochet_guided := generator.build_blueprint_variations(
		[blueprint], 12, 20260801, LevelGenerator.Profile.ricochet_chain())
	var ricochet_sources: Array = []
	for ricochet_index in range(9, 13):
		ricochet_sources.append(ricochet_guided[ricochet_index])
	var ricochet_records: Array[Dictionary] = []
	generator.blueprints_finished.connect(
		func(items: Array[Dictionary]) -> void: ricochet_records.assign(items),
		CONNECT_ONE_SHOT)
	generator.generate_from_blueprints(
		LevelGenerator.Profile.ricochet_chain(), ricochet_sources, 4, 0, 20260801)
	while generator.is_running():
		await process_frame
	if ricochet_records.is_empty():
		print("SEKME ZINCIRI RET: %s" % generator.describe_rejections())
	_check("sekme zinciri kurtarmadan solver adayi cikiyor",
		ricochet_records.is_empty(), false)
	for record in ricochet_records:
		_check("sekme zinciri 5-10 sekme bandinda",
			int(record["solver"]["bounces"]) in range(5, 11), true)
	var corridor_guided := generator.build_blueprint_variations(
		[blueprint], 12, 20260802, LevelGenerator.Profile.block_corridor())
	var corridor_sources: Array = []
	for corridor_index in range(9, 13):
		corridor_sources.append(corridor_guided[corridor_index])
	var corridor_records: Array[Dictionary] = []
	generator.blueprints_finished.connect(
		func(items: Array[Dictionary]) -> void: corridor_records.assign(items),
		CONNECT_ONE_SHOT)
	generator.generate_from_blueprints(
		LevelGenerator.Profile.block_corridor(), corridor_sources, 4, 0, 20260802)
	while generator.is_running():
		await process_frame
	if corridor_records.is_empty():
		print("BLOK KORIDORU RET: %s" % generator.describe_rejections())
	_check("blok koridoru kurtarmadan solver adayi cikiyor",
		corridor_records.is_empty(), false)
	for record in corridor_records:
		_check("blok koridoru en az iki tugla kullaniyor",
			(record["level"] as LevelData).breakable_blocks.size() >= 2, true)
		_check("blok koridoru cok atisli",
			int(record["solver"]["solution_shots"]) in range(2, 5), true)
		_check("blok koridoru kirik durum gerektiriyor",
			int(record["solver"]["broken_state"]) != 0, true)
	var crowded_level := original.duplicate(true) as LevelData
	var crowded_panel := PanelData.new()
	crowded_panel.position = crowded_level.target_position
	crowded_panel.length = 320.0
	crowded_panel.thickness = 26.0
	crowded_level.panels = [crowded_panel]
	var repaired := generator.build_blueprint_variations(
		[{"level": crowded_level, "blueprint_index": 0}], 0, 991)
	var repaired_level: LevelData = repaired[0]["level"]
	_check("hedefle cakisan AI paneli onariliyor",
		repaired_level.panels[0].position != repaired_level.target_position, true)

	var produced: Array[LevelData] = []
	var records: Array[Dictionary] = []
	generator.finished.connect(func(levels: Array[LevelData]) -> void: produced.assign(levels))
	generator.blueprints_finished.connect(func(items: Array[Dictionary]) -> void: records.assign(items))
	var observed_frames := 0
	var physics_blueprint := {
		"level": LevelLibrary.load_level(1),
		"blueprint_index": 0,
		"design_intent": "fizik kontrolu",
	}
	generator.generate_from_blueprints(
		LevelGenerator.Profile.medium(), [physics_blueprint], 1, 0, 99)
	while generator.is_running():
		observed_frames += 1
		await process_frame
	_check("solver'dan gecen orijinal kabul", produced.size(), 1)
	_check("solver olcumleri kayitli", records[0]["solver"].has("robust"), true)
	_check("tarama karelere yayiliyor", observed_frames > 2, true)
	root.remove_child(generator)
	generator.free()


func _raw_level() -> Dictionary:
	return {
		"display_name": "Guvenli Taslak",
		"design_intent": "iki rota",
		"launcher": {"x": 360, "y": 1120},
		"target": {"x": 260, "y": 320},
		"panels": [{
			"x": 360, "y": 700, "rotation_degrees": 20,
			"length": 260, "thickness": 26,
		}],
		"blocks": [{
			"x": 480, "y": 580, "rotation_degrees": 0,
			"width": 180, "height": 44,
		}],
		"left_wall_gap": {"enabled": false, "top": 0, "bottom": 0},
		"right_wall_gap": {"enabled": true, "top": 480, "bottom": 720},
		"max_lives": 4,
		"expected_solution": {
			"estimated_bounces": 2, "blocks_required": 0,
			"route_description": "panel ve duvar",
		},
	}


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
		return
	_failed += 1
	print("HATA %s: beklenen %s, gelen %s" % [label, expected, actual])
