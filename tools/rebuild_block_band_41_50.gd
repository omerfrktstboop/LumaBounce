extends SceneTree

## 41-50 arasini, 26-40'ta ogrenilen kirilabilir bloklari temel panel ve
## duvar-boslugu oyunuyla birlestiren on benzersiz ustalik bolumu olarak kurar.
##
## Adaylar gercek LevelWorld + LevelSolver ile elenir. Kabul edilen bir bolum:
## - blok kirmadan rahat bir kestirmeye sahip olamaz,
## - en az bir blok durumu gercek atislarla erisildikten sonra 6+ saglam hucre
##   vermelidir,
## - kendinden onceki resmi bolumlere %75'ten fazla benzeyemez,
## - gec banda geldikce daha dar cozum ve daha uzun atis zinciri ister.
##
## Kullanim:
##   godot --headless --path . --script res://tools/rebuild_block_band_41_50.gd
##   godot --headless --path . --script res://tools/rebuild_block_band_41_50.gd -- --only 41,42

const FIRST_LEVEL := 41
const LAST_LEVEL := 50
const ATTEMPTS_PER_LEVEL := 500
const ANGLE_STEP := 3.0
const POWER_STEP := 100.0
const MIN_ROBUST := 6
const MAX_STATES := 96
const SIMS_PER_FRAME := 240
# Benzerlik puaninda 75 "guclu ceza", 90 "kesin ret" esigidir. Resmi bant
# uretiminde ikisinin ortasinda daha sert bir 82 kapisi kullanilir; 74 kapisi
# ayni mekanigi (blok koridoru) kullanan fiziksel olarak farkli tum adaylari
# da reddedip aramayi kilitliyordu.
const MAX_SIMILARITY := 82.0

const NAMES := {
	41: "Kenar Anahtarı",
	42: "Çifte Koridor",
	43: "Kırık Zikzak",
	44: "Ters Kilit",
	45: "Dar Geçit",
	46: "Yankı Duvarı",
	47: "Çapraz Hasar",
	48: "İkili Açılım",
	49: "Son Koridor",
	50: "Blok Ustalığı",
}

var _only: Array[int] = []
var _solver: LevelSolver
var _world: LevelWorld
var _novelty := LevelNoveltyScorer.new()
var _references: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_parse_args()
	_run.call_deferred()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--only" and i + 1 < args.size():
			for piece in args[i + 1].split(",", false):
				var clean := piece.strip_edges()
				if clean.is_valid_int():
					_only.append(int(clean))


func _run() -> void:
	await physics_frame
	_solver = LevelSolver.from_scenes()
	_world = LevelWorld.new()
	root.add_child(_world)

	var ids: Array[int] = _only.duplicate()
	if ids.is_empty():
		for level_id in range(FIRST_LEVEL, LAST_LEVEL + 1):
			ids.append(level_id)
	_index_references(ids)

	var failed: Array[int] = []
	for level_id in ids:
		if level_id < FIRST_LEVEL or level_id > LAST_LEVEL:
			push_error("Bu arac yalnizca 41-50 araligini yazar: %d" % level_id)
			failed.append(level_id)
			continue
		if not await _build_level(level_id):
			failed.append(level_id)

	_world.clear()
	root.remove_child(_world)
	_world.queue_free()
	print("")
	print("OZET basarili=%d basarisiz=%d" % [ids.size() - failed.size(), failed.size()])
	if not failed.is_empty():
		print("basarisiz bolumler: %s" % str(failed))
	quit(0 if failed.is_empty() else 1)


func _index_references(rebuilt_ids: Array[int]) -> void:
	# Parca parca calistirmada daha once uretilen 41-50 bolumleri de referans
	# kalir; ayni komutta yeniden yazilacak eski dosyalar ise adaylari haksiz
	# yere kendi eski halleriyle karsilastirmasin diye dislanir.
	for level_id in range(LevelLibrary.FIRST_LEVEL_ID, LAST_LEVEL + 1):
		if rebuilt_ids.has(level_id):
			continue
		_references.append({
			"name": "Resmi %02d" % level_id,
			"level": LevelLibrary.load_level(level_id),
			"metrics": {},
		})


func _build_level(level_id: int) -> bool:
	_rng.seed = 4100000 + level_id * 104729
	var rejects := {
		"validate": 0, "clearance": 0, "free": 0, "early": 0,
		"route": 0, "bounce": 0, "wide": 0, "similar": 0,
	}
	for attempt in ATTEMPTS_PER_LEVEL:
		if attempt > 0 and attempt % 25 == 0:
			print("LEVEL %2d ilerleme deneme=%d ret=%s" % [
				level_id, attempt, str(rejects)])
		var level := _candidate(level_id)
		if not level.validate().is_empty():
			rejects["validate"] += 1
			continue
		if not _layout_is_clear(level):
			rejects["clearance"] += 1
			continue

		var verdict := await _evaluate(level, level_id)
		if not bool(verdict["ok"]):
			var reason := String(verdict["reason"])
			rejects[reason] = int(rejects.get(reason, 0)) + 1
			continue

		var novelty := _novelty.score(level, verdict, _references)
		if float(novelty["similarity"]) > MAX_SIMILARITY:
			rejects["similar"] += 1
			continue

		level.hint_angle_degrees = float(verdict["angle"])
		level.hint_power = float(verdict["power"])
		level.three_star_max_shots = int(verdict["shots"])
		level.two_star_max_shots = mini(level.max_lives, int(verdict["shots"]) + 1)
		var error := ResourceSaver.save(level, "res://levels/level_%d.tres" % level_id)
		if error != OK:
			push_error("Bolum %d kaydedilemedi: %d" % [level_id, error])
			return false
		_references.append({
			"name": "Yeni %02d" % level_id,
			"level": level.duplicate(true),
			"metrics": verdict.duplicate(true),
		})
		print("LEVEL %2d ok deneme=%d saglam=%d sekme=%d atis=%d benzerlik=%d" % [
			level_id, attempt + 1, int(verdict["robust"]), int(verdict["bounces"]),
			int(verdict["shots"]), int(novelty["similarity"])])
		return true

	print("LEVEL %2d BASARISIZ ret=%s" % [level_id, str(rejects)])
	return false


func _candidate(level_id: int) -> LevelData:
	# Ilk kabul edilen bolum bir sonraki icin fizik tohumu olur. Her adayda
	# hedef, blok deseni, duvar boslugu ve panel geometrisi ciddi bicimde
	# degistigi icin bu bir kopyalama degil; aramayi cozumlu bir komsuluktan
	# baslatan evrimsel bir adimdir. Novelty filtresi benzer kalanlari eler.
	var level := (LevelLibrary.load_level(level_id - 1).duplicate(true) as LevelData
		if level_id > FIRST_LEVEL else LevelData.new())
	var stage := level_id - FIRST_LEVEL
	var family := stage % 5
	if level_id > FIRST_LEVEL and stage % 2 == 1:
		_mirror_geometry(level)
	level.level_uid = LevelData.uid_for(level_id)
	level.display_order = level_id
	level.level_id = level_id
	level.display_name = String(NAMES[level_id])
	level.difficulty = 3 if level_id <= 44 else (4 if level_id < 50 else 5)
	level.launcher_position = Vector2(
		clampf(level.launcher_position.x + _rng.randf_range(-42.0, 42.0), 300.0, 420.0),
		1120.0)
	if level_id == FIRST_LEVEL:
		level.target_position = Vector2(
			170.0 + _rng.randf_range(-32.0, 32.0), _rng.randf_range(220.0, 315.0))
	else:
		# Onceki cozumlu rotanin hedef komsulugunda kal; buyuk hedef sicrama
		# panelleri anlamsizlastirip yuzlerce pahali solver reddi uretiyordu.
		# Ayna, panel sayisi, blok dalgasi ve duvar tarafi zaten bolum kimligini
		# degistiriyor; burada yalnizca fizik komsulugu korunur.
		level.target_position = Vector2(
			clampf(level.target_position.x + _rng.randf_range(-58.0, 58.0), 120.0, 600.0),
			clampf(level.target_position.y + _rng.randf_range(-38.0, 38.0), 210.0, 330.0))
		if stage == 7:
			level.target_position = Vector2(
				clampf(level.target_position.x + _rng.randf_range(-80.0, 80.0), 120.0, 600.0),
				clampf(level.target_position.y + _rng.randf_range(-45.0, 45.0), 210.0, 330.0))
	level.target_scale = 1.0
	level.ball_scale = 1.0
	level.max_lives = 5
	level.tutorial_text = ""
	level.two_star_max_seconds = 105.0 + float(stage) * 3.0
	level.three_star_max_seconds = 58.0 + float(stage) * 2.0
	level.obstacles = [] as Array[ObstacleData]

	if level_id >= 47:
		level.panels = _vary_late_panels(
			level.panels, stage, level.target_position.x)
		level.breakable_blocks = _vary_late_blocks(
			level.breakable_blocks, stage, level.target_position)
	else:
		level.panels = _vary_panels(level.panels, stage, level.target_position.x)
		level.breakable_blocks = _make_blocks(stage, family, level.target_position)
	_apply_wall_gaps(level, stage)
	return level


func _mirror_geometry(level: LevelData) -> void:
	level.launcher_position.x = 720.0 - level.launcher_position.x
	level.target_position.x = 720.0 - level.target_position.x
	for panel in level.panels:
		panel.position.x = 720.0 - panel.position.x
		panel.rotation_degrees = -panel.rotation_degrees
	for block in level.breakable_blocks:
		block.position.x = 720.0 - block.position.x
		block.rotation_degrees = -block.rotation_degrees
	var left := level.left_wall_segments.duplicate()
	level.left_wall_segments = level.right_wall_segments.duplicate()
	level.right_wall_segments = left


func _vary_panels(source: Array[PanelData], stage: int,
		target_x: float) -> Array[PanelData]:
	var panels: Array[PanelData] = []
	for raw in source:
		var panel := raw.duplicate(true) as PanelData
		panel.position = Vector2(
			clampf(panel.position.x + _rng.randf_range(-95.0, 95.0), 115.0, 605.0),
			clampf(panel.position.y + _rng.randf_range(-75.0, 75.0), 500.0, 965.0))
		panel.rotation_degrees = clampf(
			panel.rotation_degrees + _rng.randf_range(-14.0, 14.0), -58.0, 58.0)
		panel.length = clampf(
			panel.length + _rng.randf_range(-50.0, 50.0), 175.0, 325.0)
		panel.thickness = 26.0
		panels.append(panel)
	var wanted := 3 if stage in [1, 2, 4, 8, 9] else 2
	while panels.size() > wanted:
		panels.remove_at(panels.size() - 1)
	if panels.size() < wanted:
		var fresh := _make_panels(stage, target_x)
		for panel in fresh:
			if panels.size() >= wanted:
				break
			panels.append(panel)
	return panels


func _make_panels(stage: int, target_x: float) -> Array[PanelData]:
	var panels: Array[PanelData] = []
	var target_side := -1.0 if target_x > 360.0 else 1.0
	var lower := PanelData.new()
	lower.position = Vector2(
		360.0 + target_side * _rng.randf_range(135.0, 225.0),
		_rng.randf_range(820.0, 950.0))
	lower.rotation_degrees = target_side * _rng.randf_range(18.0, 43.0)
	lower.length = _rng.randf_range(215.0, 310.0)
	lower.thickness = 26.0
	panels.append(lower)

	var upper := PanelData.new()
	upper.position = Vector2(
		360.0 - target_side * _rng.randf_range(120.0, 215.0),
		_rng.randf_range(610.0, 760.0))
	upper.rotation_degrees = -target_side * _rng.randf_range(16.0, 40.0)
	upper.length = _rng.randf_range(205.0, 300.0)
	upper.thickness = 26.0
	panels.append(upper)

	if stage in [2, 4, 6, 8, 9]:
		var middle := PanelData.new()
		middle.position = Vector2(
			_rng.randf_range(190.0, 530.0), _rng.randf_range(500.0, 600.0))
		middle.rotation_degrees = _rng.randf_range(-32.0, 32.0)
		middle.length = _rng.randf_range(165.0, 235.0)
		middle.thickness = 26.0
		panels.append(middle)
	return panels


func _vary_late_panels(source: Array[PanelData], stage: int,
		target_x: float) -> Array[PanelData]:
	# Son dort bolum onceki cozumlu sekme koridorunu korur. Kucuk konum
	# degisimleri oynanisi tazeler; 47 ve 49'a eklenen orta panel ise yeni
	# bir karar noktasi yaratip ayna-kopya benzerligini kirar.
	var panels: Array[PanelData] = []
	for raw in source:
		var panel := raw.duplicate(true) as PanelData
		panel.position = Vector2(
			clampf(panel.position.x + _rng.randf_range(-32.0, 32.0), 115.0, 605.0),
			clampf(panel.position.y + _rng.randf_range(-28.0, 28.0), 500.0, 965.0))
		panel.rotation_degrees = clampf(
			panel.rotation_degrees + _rng.randf_range(-7.0, 7.0), -58.0, 58.0)
		panel.length = clampf(
			panel.length + _rng.randf_range(-25.0, 25.0), 175.0, 325.0)
		panel.thickness = 26.0
		panels.append(panel)
	var wanted := 3 if stage in [6, 8] else (4 if stage == 7 else 2)
	while panels.size() > wanted:
		panels.remove_at(panels.size() - 1)
	if panels.size() < wanted:
		var middle := PanelData.new()
		var target_side := -1.0 if target_x > 360.0 else 1.0
		if panels.size() == 3:
			# 48'in dorduncu paneli mevcut orta ve alt bantlarin arasinda,
			# yatayda da orta panelin karsi tarafinda durur.
			var third_x := panels[2].position.x
			middle.position = Vector2(
				180.0 if third_x > 360.0 else 540.0,
				_rng.randf_range(785.0, 820.0))
		else:
			middle.position = Vector2(
				360.0 + target_side * _rng.randf_range(90.0, 180.0),
				_rng.randf_range(625.0, 730.0))
		middle.rotation_degrees = target_side * _rng.randf_range(18.0, 38.0)
		middle.length = _rng.randf_range(180.0, 235.0)
		middle.thickness = 26.0
		panels.append(middle)
	return panels


func _vary_late_blocks(source: Array[BreakableBlockData], stage: int,
		target: Vector2) -> Array[BreakableBlockData]:
	# Cozumlu blok kapisini yeniden kurmak yerine evrimlestir. Dayanikli blok
	# sirasi her bolumde kayar; son iki bolumdeki besinci anahtar blok onceki
	# tum blok bilgisini birlikte kullanmayi gerektirir.
	var blocks: Array[BreakableBlockData] = []
	for i in source.size():
		var block := source[i].duplicate(true) as BreakableBlockData
		block.position = Vector2(
			clampf(block.position.x + _rng.randf_range(-18.0, 18.0), 90.0, 630.0),
			clampf(block.position.y + _rng.randf_range(-14.0, 14.0), 385.0, 610.0))
		block.rotation_degrees = clampf(
			block.rotation_degrees + _rng.randf_range(-4.0, 4.0), -18.0, 18.0)
		block.hit_points = 2 if i == stage % maxi(source.size(), 1) else 1
		blocks.append(block)
	while blocks.size() > 4:
		blocks.remove_at(blocks.size() - 1)
	if stage >= 8:
		var key := BreakableBlockData.new()
		var target_side := -1.0 if target.x > 360.0 else 1.0
		key.position = Vector2(
			clampf(target.x + target_side * _rng.randf_range(190.0, 260.0), 105.0, 615.0),
			clampf(target.y + _rng.randf_range(270.0, 330.0), 500.0, 660.0))
		key.rotation_degrees = target_side * _rng.randf_range(12.0, 24.0)
		key.size = Vector2(_rng.randf_range(115.0, 155.0), 34.0)
		key.hit_points = 2 if stage == 9 else 1
		blocks.append(key)
	return blocks


func _make_blocks(stage: int, family: int, target: Vector2) -> Array[BreakableBlockData]:
	var blocks: Array[BreakableBlockData] = []
	var count := 3 if stage == 0 else 4
	var row_y := target.y + _rng.randf_range(165.0, 235.0)
	var gap := _rng.randf_range(24.0, 38.0)
	var width := (540.0 - gap * float(count - 1)) / float(count)
	var left := 90.0
	for i in count:
		var block := BreakableBlockData.new()
		var wave := 0.0
		if family == 1:
			wave = (-34.0 if i % 2 == 0 else 34.0)
		elif family == 2:
			wave = (float(i) - float(count - 1) * 0.5) * 24.0
		elif family == 3:
			wave = (28.0 if i in [0, count - 1] else -24.0)
		elif family == 4:
			wave = sin(float(i) * PI / maxf(float(count - 1), 1.0)) * 48.0
		block.position = Vector2(
			left + width * 0.5 + float(i) * (width + gap), row_y + wave)
		block.rotation_degrees = _rng.randf_range(-7.0, 7.0) if family != 0 else 0.0
		block.size = Vector2(width, 34.0)
		var durable_target := stage / 3
		block.hit_points = 2 if i <= durable_target and stage >= 3 else 1
		blocks.append(block)

	if family in [2, 4] and stage >= 4:
		var key := BreakableBlockData.new()
		key.position = Vector2(
			clampf(target.x + _rng.randf_range(-150.0, 150.0), 120.0, 600.0),
			row_y + _rng.randf_range(95.0, 145.0))
		key.rotation_degrees = _rng.randf_range(-28.0, 28.0)
		key.size = Vector2(_rng.randf_range(120.0, 175.0), 34.0)
		key.hit_points = 1
		blocks.append(key)
	return blocks


func _apply_wall_gaps(level: LevelData, stage: int) -> void:
	# Onceki bolumun bosluklarini tasima; her duvar deseni bu bolumun kendi
	# kimligidir. Bos dizi o tarafta kesintisiz arena duvari demektir.
	level.left_wall_segments = [] as Array[Vector2]
	level.right_wall_segments = [] as Array[Vector2]
	var center := _rng.randf_range(600.0, 790.0)
	var half := _rng.randf_range(65.0, 105.0)
	var segments: Array[Vector2] = [
		Vector2(-320.0, center - half), Vector2(center + half, 1600.0)]
	if stage % 2 == 0:
		level.left_wall_segments = segments.duplicate()
	else:
		level.right_wall_segments = segments.duplicate()
	if stage in [4, 8, 9]:
		var other_center := _rng.randf_range(500.0, 720.0)
		var other_half := _rng.randf_range(55.0, 90.0)
		var other: Array[Vector2] = [
			Vector2(-320.0, other_center - other_half),
			Vector2(other_center + other_half, 1600.0)]
		if stage % 2 == 0:
			level.right_wall_segments = other
		else:
			level.left_wall_segments = other


func _layout_is_clear(level: LevelData) -> bool:
	for panel in level.panels:
		if panel.position.distance_to(level.target_position) < 125.0:
			return false
		if panel.position.distance_to(level.launcher_position) < 145.0:
			return false
	for block in level.breakable_blocks:
		if block.position.distance_to(level.target_position) < 105.0:
			return false
		if block.position.distance_to(level.launcher_position) < 150.0:
			return false
	for i in level.panels.size():
		for j in range(i + 1, level.panels.size()):
			if level.panels[i].position.distance_to(level.panels[j].position) < 145.0:
				return false
	for panel in level.panels:
		for block in level.breakable_blocks:
			if panel.position.distance_to(block.position) < 105.0:
				return false
	return true


func _evaluate(level: LevelData, level_id: int) -> Dictionary:
	_world.build(level)
	await physics_frame
	await physics_frame
	_solver.bind_space(_world.get_space(), _world.get_block_rids(), _world.get_obstacles())
	var spawn := _solver.spawn_position(level.launcher_position)
	if (_solver.overlaps_obstacle(level.target_position, _solver.target_size * 0.5)
			or _solver.overlaps_obstacle(spawn, _solver.radius)
			or _solver.overlaps_obstacle(level.launcher_position, 60.0)):
		return {"ok": false, "reason": "clearance"}

	var min_shots := 2
	var max_shots := 3 if level_id <= 44 else 4
	var max_robust := 18 if level_id <= 44 else (13 if level_id < 50 else 10)
	var min_bounces := 1
	# Ucuz on tarama: hicbir bloklu duruma ulasmayan aday 3/100'luk tam
	# durum agacina girmesin. Bu yalnizca arama optimizasyonudur; kabul karari
	# her zaman asagidaki ince taramadan gelir.
	var coarse := await _solver.search_block_states_async(
		spawn, level.target_position, _world.get_play_rect(), max_shots,
		9.0, 300.0, 8, SIMS_PER_FRAME * 2)
	var coarse_route := false
	for solution in coarse["solutions"]:
		if int(solution["state"]) != 0 and int(solution["shots"]) >= min_shots:
			coarse_route = true
			break
	if not coarse_route:
		return {"ok": false, "reason": "route"}
	var free_scan := await _solver.scan_block_state_async(
		spawn, level.target_position, _world.get_play_rect(), 0,
		ANGLE_STEP, POWER_STEP, SIMS_PER_FRAME)
	var free_analysis := LevelSolver.analyse_robust(free_scan)
	if int(free_analysis["robust"]) >= MIN_ROBUST:
		return {"ok": false, "reason": "free"}
	var fine_states := 0
	for coarse_solution in coarse["solutions"]:
		var shots := int(coarse_solution["shots"])
		var state := int(coarse_solution["state"])
		if state == 0 or shots < min_shots or shots > max_shots:
			continue
		fine_states += 1
		if fine_states > 4:
			break
		var fine_scan := await _solver.scan_block_state_async(
			spawn, level.target_position, _world.get_play_rect(), state,
			ANGLE_STEP, POWER_STEP, SIMS_PER_FRAME)
		var analysis := LevelSolver.analyse_robust(fine_scan)
		var robust := int(analysis["robust"])
		if robust < MIN_ROBUST or robust > max_robust:
			continue
		if int(analysis["bounces"]) < min_bounces:
			continue
		return {
			"ok": true,
			"robust": robust,
			"bounces": int(analysis["bounces"]),
			"shots": shots,
			"state": state,
			"angle": float(analysis["angle"]),
			"power": float(analysis["power"]),
		}
	return {"ok": false, "reason": "route"}
