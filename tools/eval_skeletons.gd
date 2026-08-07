extends SceneTree

## GELISTIRME ARACI - oyuna dahil degildir.
##
## 51-125 bandi icin PANEL ISKELETI kutuphanesi ARAR ve bulduklarini kopyala-
## yapistir edilebilir bicimde basar. Amac cesitlilik: bant iki sablonun
## tekrari yerine birbirinden ayrisan onlarca iskelete dagitilmali
## (bkz. tools/find_duplicate_levels.py raporu).
##
## NEDEN ARAMA, ELLE TASARIM DEGIL: elle yazilan 24 adayin 19'u elendi ve
## cogunun kusuru aynidir - panel hic ISE YARAMIYOR, top hedefe dogrudan
## parabolle gidiyor (sekme = 0). "Panelin gercekten rota kurdugu" bir
## yerlesimi gozle kestirmek zor; olcup elemek kolay. Bu, projenin
## LevelGenerator'daki "uretec tasarim yapmaz, ARAMA yapar" ilkesinin
## iskeletlere uygulanmasidir.
##
## Iskelet = firlatici + hedef + paneller. Engel/blok YOKTUR: once iskeletin
## kendisi olculur, mekanikler sonra uzerine kurulur. Boylece bir bolum
## cozulemez ciktiginda sucun iskelette mi mekanikte mi oldugu bellidir.
##
## Kullanim:
##   godot --headless --path . --script res://tools/eval_skeletons.gd
##   godot --headless --path . --script res://tools/eval_skeletons.gd -- --wanted 32 --seed 20260806

## Uzerine engel eklenecegi icin iskeletin kendisi RAHAT olmali: engel
## pencereyi daraltacagindan esik verifier'in MIN_ROBUST_CELLS'inden (6) yuksek.
const MIN_ROBUST := 16
## Cok genis pencere = bolum zaten bedava; engel eklense de kolay kalir.
const MAX_ROBUST := 90
## Panel gercekten rota kurmali. 0 sekme, panelin dekor oldugu anlamina gelir.
const MIN_BOUNCES := 1

var _wanted := 32
var _seed := 20260806
var _max_tries := 900
var _angle_step := 2.0
var _power_step := 50.0

var _solver: LevelSolver
var _world: LevelWorld
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--wanted" and i + 1 < args.size():
			_wanted = maxi(int(args[i + 1]), 1)
		elif args[i] == "--seed" and i + 1 < args.size():
			_seed = int(args[i + 1])
		elif args[i] == "--max-tries" and i + 1 < args.size():
			_max_tries = maxi(int(args[i + 1]), 1)
	_run.call_deferred()


func _run() -> void:
	await physics_frame
	_solver = LevelSolver.from_scenes()
	_rng.seed = _seed

	var accepted: Array[Dictionary] = []
	var tried := 0
	var rejected := {"sekme": 0, "dar": 0, "genis": 0, "benzer": 0}

	while accepted.size() < _wanted and tried < _max_tries:
		tried += 1
		var candidate := _random_skeleton()
		var level := _level_from(candidate)

		_world = LevelWorld.new()
		root.add_child(_world)
		_world.build(level)
		_solver.bind_space(
			_world.get_space(), _world.get_block_rids(), _world.get_obstacles())
		await physics_frame
		await physics_frame

		var scan := _solver.scan(
			_solver.spawn_position(level.launcher_position),
			level.target_position, _world.get_play_rect(),
			[], _angle_step, _power_step)
		var analysis := LevelSolver.analyse_robust(scan)
		var robust := int(analysis["robust"])
		var bounces := int(analysis["bounces"]) if int(scan["hit_count"]) > 0 else -1

		_world.queue_free()
		_world = null
		await process_frame

		if bounces < MIN_BOUNCES:
			rejected["sekme"] += 1
			continue
		if robust < MIN_ROBUST:
			rejected["dar"] += 1
			continue
		if robust > MAX_ROBUST:
			rejected["genis"] += 1
			continue
		if _too_similar(candidate, accepted):
			rejected["benzer"] += 1
			continue

		candidate["robust"] = robust
		candidate["bounces"] = bounces
		accepted.append(candidate)

	_print_library(accepted, tried, rejected)
	quit(0)


## Iki iskelet "ayni tasarim" hissi vermemeli: hedefleri ve panel agirlik
## merkezleri yeterince ayrismali. Yalnizca sayisal esik - amac kutuphanenin
## tekrar uretmemesi (bkz. find_duplicate_levels.py "ayni iskelet" raporu).
func _too_similar(candidate: Dictionary, accepted: Array[Dictionary]) -> bool:
	var target: Vector2 = candidate["target"]
	var centroid := _centroid(candidate)
	for other in accepted:
		var other_target: Vector2 = other["target"]
		if other["panels"].size() != candidate["panels"].size():
			continue
		if target.distance_to(other_target) < 110.0 \
				and centroid.distance_to(_centroid(other)) < 110.0:
			return true
	return false


func _centroid(candidate: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	for raw in (candidate["panels"] as Array):
		sum += (raw as Array)[0] as Vector2
	return sum / maxf(float(candidate["panels"].size()), 1.0)


func _random_skeleton() -> Dictionary:
	var panel_count := _rng.randi_range(1, 3)
	var panels: Array = []
	for i in panel_count:
		# Paneller dikey olarak katmanlanir: ust uste yiginlari onler ve
		# "merdiven" hissi veren yerlesimleri olasi kilar.
		var band_top := 460.0 + float(i) * 30.0
		var band_bottom := 980.0 - float(panel_count - 1 - i) * 150.0
		panels.append([
			Vector2(_rng.randf_range(150.0, 570.0),
				_rng.randf_range(band_top, maxf(band_bottom, band_top + 60.0))),
			_rng.randf_range(-52.0, 52.0),
			_rng.randf_range(240.0, 420.0),
		])
	return {
		"target": Vector2(_rng.randf_range(140.0, 580.0), _rng.randf_range(230.0, 470.0)),
		"panels": panels,
	}


func _level_from(candidate: Dictionary) -> LevelData:
	var level := LevelData.new()
	level.level_id = 1
	level.launcher_position = Vector2(360.0, 1120.0)
	level.target_position = candidate["target"]
	var panels: Array[PanelData] = []
	for raw in (candidate["panels"] as Array):
		var spec: Array = raw
		var panel := PanelData.new()
		panel.position = spec[0]
		panel.rotation_degrees = float(spec[1])
		panel.length = float(spec[2])
		panel.thickness = 26.0
		panels.append(panel)
	level.panels = panels
	level.max_lives = 5
	return level


## Python ureticisine dogrudan yapistirilabilecek bicimde basar.
func _print_library(accepted: Array[Dictionary], tried: int,
		rejected: Dictionary) -> void:
	print("# denendi=%d kabul=%d eleme: sekme=%d dar=%d genis=%d benzer=%d" % [
		tried, accepted.size(), int(rejected["sekme"]), int(rejected["dar"]),
		int(rejected["genis"]), int(rejected["benzer"])])
	print("SKELETONS = [")
	for entry in accepted:
		var target: Vector2 = entry["target"]
		var parts := PackedStringArray()
		for raw in (entry["panels"] as Array):
			var spec: Array = raw
			var position: Vector2 = spec[0]
			parts.append("(%.0f, %.0f, %.1f, %.0f)" % [
				position.x, position.y, float(spec[1]), float(spec[2])])
		print("    # saglam=%d sekme=%d" % [int(entry["robust"]), int(entry["bounces"])])
		print("    {\"target\": (%.0f, %.0f), \"panels\": [%s]}," % [
			target.x, target.y, ", ".join(parts)])
	print("]")
