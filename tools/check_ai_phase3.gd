extends SceneTree

const MANIFEST_PATH := "user://generated_levels/phase3_manifest_test.json"

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_test_novelty()
	_test_quality_and_ranking()
	_test_metadata()
	print("AI ASAMA 3: %d gecti, %d kaldi." % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_novelty() -> void:
	var scorer := LevelNoveltyScorer.new()
	var original := _level(Vector2(170, 280), Vector2(230, 680), 24.0)
	var copy := original.duplicate(true) as LevelData
	var exact := scorer.score(copy, {}, [{"name": "ozgun", "level": original, "metrics": {}}])
	_check("ayni geometri reddediliyor", exact["similarity"] >= 90, true)
	var mirror := _mirror_level(original)
	var mirrored := scorer.score(mirror, {}, [{"name": "ozgun", "level": original, "metrics": {}}])
	_check("yatay ayna benzer", mirrored["similarity"] >= 90, true)
	_check("ayna isareti", mirrored["mirrored_match"], true)
	var different := _level(Vector2(590, 500), Vector2(560, 980), -62.0)
	different.breakable_blocks.append(_block(Vector2(130, 430)))
	var fresh := scorer.score(different, {}, [{"name": "ozgun", "level": original, "metrics": {}}])
	_check("farkli geometri daha yenilikci", fresh["novelty_score"] > exact["novelty_score"], true)


func _test_quality_and_ranking() -> void:
	var coordinator := AILevelGenerationCoordinator.new()
	root.add_child(coordinator)
	var reference := _level(Vector2(160, 260), Vector2(220, 680), 20.0)
	var high := _level(Vector2(560, 460), Vector2(500, 820), -36.0)
	var low := _level(Vector2(300, 320), Vector2(340, 720), 4.0)
	var records: Array[Dictionary] = [
		{"level": low, "solver": {"ok": true, "robust": 8, "bounces": 2, "opened_robust": 8, "block_free": true}},
		{"level": high, "solver": {"ok": true, "robust": 28, "bounces": 2, "opened_robust": 28, "block_free": true}},
		{"level": high.duplicate(true), "solver": {"ok": true, "robust": 28, "bounces": 2, "opened_robust": 28, "block_free": true}},
	]
	var ranked := coordinator.rank_records(records, {"template": "single_bounce"}, [
		{"name": "referans", "level": reference, "metrics": {}},
	])
	_check("batch kopyasi eleniyor", ranked.size(), 2)
	var exact_fill := coordinator.rank_records(records, {"template": "single_bounce"}, [
		{"name": "referans", "level": reference, "metrics": {}},
	], 3)
	_check("tam kopya sayiyi doldurmak icin geri alinmiyor", exact_fill.size(), 2)
	var near := high.duplicate(true) as LevelData
	near.target_position += Vector2(18.0, 12.0)
	near.panels[0].position += Vector2(20.0, -10.0)
	var fill_records := records.slice(0, 2)
	fill_records.append({
		"level": near,
		"solver": {
			"ok": true, "robust": 26, "bounces": 2,
			"opened_robust": 26, "block_free": true,
		},
	})
	var filled := coordinator.rank_records(
		fill_records, {"template": "single_bounce"}, [
			{"name": "referans", "level": reference, "metrics": {}},
		], 3)
	_check("benzer fizik adayi istenen sayiyi dolduruyor", filled.size(), 3)
	var has_fallback := false
	for entry in filled:
		if bool(entry["novelty"].get("similarity_fallback", false)):
			has_fallback = true
	_check("doldurma adayi metadata ile isaretli", has_fallback, true)
	var previous_near := high.duplicate(true) as LevelData
	previous_near.target_position += Vector2(14.0, 10.0)
	var previous_ranked := coordinator.rank_records([{
		"level": previous_near,
		"solver": {
			"ok": true, "robust": 25, "bounces": 2,
			"opened_robust": 25, "block_free": true,
		},
	}], {"template": "single_bounce"}, [{
		"name": "Onceki uretim/01_onceki",
		"level": high,
		"metrics": {},
	}], 1)
	_check("onceki uretime cok yakin aday geri gelmiyor", previous_ranked.size(), 0)
	if not ranked.is_empty():
		_check("yuksek kalite once", ranked[0]["level"], high)
	var quality := LevelQualityScorer.new()
	var neutral_novelty := {"novelty_score": 80, "strong_penalty": false, "reject": false}
	var ordinary := quality.score(high, records[1]["solver"], neutral_novelty, "single_bounce")
	_check("alternatif istemeyen sablon rota puani aliyor", ordinary["breakdown"]["route"], 10)
	var no_two_routes: Array[Dictionary] = [{
		"level": high,
		"solver": {
			"ok": true, "robust": 28, "bounces": 2, "opened_robust": 28,
			"block_free": true, "route_clusters": 1,
		},
	}]
	_check("iki rota sablonu solver kumesi olmadan eleniyor",
		coordinator.rank_records(no_two_routes, {"template": "two_routes"}, []).size(), 0)
	_check("sekme zinciri kisa rota ile eleniyor",
		coordinator.rank_records(no_two_routes, {"template": "ricochet_chain"}, []).size(), 0)
	var corridor_level := high.duplicate(true) as LevelData
	corridor_level.breakable_blocks.append(_block(Vector2(160, 580)))
	var corridor_records: Array[Dictionary] = [{
		"level": corridor_level,
		"solver": {
			"ok": true, "robust": 12, "bounces": 1, "opened_robust": 12,
			"block_free": false, "solution_shots": 3, "broken_state": 1,
		},
	}]
	_check("blok koridoru cok atis metriğiyle kabul ediliyor",
		coordinator.rank_records(
			corridor_records, {"template": "block_corridor"}, []).size(), 1)
	var corridor_quality := quality.score(
		corridor_level, corridor_records[0]["solver"], neutral_novelty, "block_corridor")
	_check("blok koridoru rota puani aliyor", corridor_quality["breakdown"]["route"], 10)
	root.remove_child(coordinator)
	coordinator.free()


func _test_metadata() -> void:
	var store := GenerationMetadataStore.new(MANIFEST_PATH)
	store.clear()
	var names := PackedStringArray(["01_bir", "02_iki"])
	var metadata := [
		{"model_slug": "vendor/model", "quality_score": 88, "resource_path": "res://ignored"},
		{"model_slug": "vendor/model", "quality_score": 72},
	]
	_check("manifest yaziliyor", store.replace(names, metadata), OK)
	_check("metadata ada bagli", store.get_entry("01_bir")["quality_score"], 88)
	_check("izin disi alan sidecar'a girmiyor", store.get_entry("01_bir").has("resource_path"), false)
	var file_text := FileAccess.get_file_as_string(MANIFEST_PATH)
	_check("manifest LevelData tres degil", file_text.contains("LevelData"), false)
	store.clear()
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	file.store_string("broken json")
	file.close()
	_check("bozuk manifest guvenli", store.load_all().is_empty(), true)
	store.clear()


func _level(target: Vector2, panel_position: Vector2, angle: float) -> LevelData:
	var level := LevelData.new()
	level.display_name = "Test"
	level.launcher_position = Vector2(360, 1120)
	level.target_position = target
	var panel := PanelData.new()
	panel.position = panel_position
	panel.rotation_degrees = angle
	panel.length = 260
	panel.thickness = 26
	level.panels = [panel]
	return level


func _block(position: Vector2) -> BreakableBlockData:
	var block := BreakableBlockData.new()
	block.position = position
	block.size = Vector2(180, 44)
	return block


func _mirror_level(source: LevelData) -> LevelData:
	var level := source.duplicate(true) as LevelData
	level.launcher_position.x = 720.0 - level.launcher_position.x
	level.target_position.x = 720.0 - level.target_position.x
	for panel in level.panels:
		panel.position.x = 720.0 - panel.position.x
		panel.rotation_degrees = -panel.rotation_degrees
	for block in level.breakable_blocks:
		block.position.x = 720.0 - block.position.x
	var left := level.left_wall_segments
	level.left_wall_segments = level.right_wall_segments
	level.right_wall_segments = left
	return level


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
		return
	_failed += 1
	print("HATA %s: beklenen %s, gelen %s" % [label, expected, actual])
