extends SceneTree

## GELISTIRME ARACI - oyuna dahil degildir.
##
## Belirtilen bolumlerin PANEL ISKELETINI cesitler; engelleri, tuglalari,
## yildiz esiklerini ve adini OLDUGU GIBI BIRAKIR.
##
## NEDEN VAR: find_duplicate_levels.py "ayni iskelet" gruplari buluyordu -
## ayni firlatici + ayni hedef + ayni panel yerlesimi. En buyuk grup 41-50
## bandindaydi (14, 42, 43, 44, 46, 48, 50 ayni yerlesim), cunku o bant sabit
## bir slot sablonu uzerine kurulmustu. generate_band_51_125.gd o bandi
## uretemez: check_obstacles.gd 41-50'nin YALNIZCA halka+bomba kullanmasini
## sart kosuyor ve bunlar mekanigi ilk tanitan elle yazilmis bolumler. Bu arac
## mekanigi korur, yalnizca gorsel/geometrik tekrari kirar.
##
## GARANTI: bir bolum ancak yeni iskeleti KUTUPHANEDEKI HICBIR bolumle
## eslesmiyorsa ve gercek LevelSolver taramasi saglam bir rota buluyorsa
## kaydedilir. "Bir piksel oynattim, artik farkli" kabul edilmez: sapmanin
## alt siniri JITTER_MIN'dir.
##
## Kullanim:
##   godot --headless --path . --script res://tools/diversify_skeletons.gd -- --only 14,42,43

## Izgara verify_levels.gd'nin VARSAYILANIYLA AYNI (2 derece / 50 guc).
## Bu onemli: saglam hucre sayisi izgara sikligiyla dogru orantili oldugundan
## "saglam >= 6" ancak ayni izgarada ayni anlama gelir. Daha kaba bir izgarada
## (3/100) ayni sayi ~3 kat agir bir baraj demektir - ilk surumde bolum 42'nin
## 400 denemesinin 396'si bu yuzden eleniyordu.
const ANGLE_STEP := 2.0
const POWER_STEP := 50.0
## Verifier'in mutlak alt siniri; bunun altina hicbir kosulda inilmez.
const MIN_ROBUST := 6
## Kabul bandi ORIJINAL bolume gore belirlenir (bkz. _diversify): amac zorlugu
## yeniden ayarlamak degil, ayni zorlugu farkli bir yerlesimle vermek. Sabit
## bir ust sinir bunu ifade edemez - bant bolumden bolume degisir.
const BAND_LOW := 0.6
const BAND_HIGH := 1.6
## Engel; hedefi, firlaticiyi veya bir paneli kapatmamali.
const CLEARANCE := 26.0

const JITTER_MIN := 26.0
const JITTER_MAX := 58.0
const JITTER_ANGLE := 8.0
const JITTER_TARGET := 34.0
## Engeller de kaydirilir. OLCULEN sebep: yalnizca panelleri oynatinca
## bolum 42'de 400 denemenin 396'si "saglam hucre < 6" ile eleniyordu -
## engeller yerinde kalinca dar bombali koridor kapaniyor ve rota
## saglamligini kaybediyor. Turu (halka/bomba) degismez, cunku 41-50 bandinin
## sozlesmesi odur; yalnizca konum aramaya acilir. Alt sinir YOK: engelin
## yerinde kalmasi mesru bir sonuctur, panelin kalmasi degil.
const OBSTACLE_JITTER := 80.0
## Duvar boslugunun kayabilecegi en buyuk mesafe (bkz. _jitter_walls).
const WALL_JITTER := 150.0
const OBSTACLE_X := Vector2(110.0, 610.0)
const OBSTACLE_Y := Vector2(330.0, 960.0)
## Deneme sayisi ve tohum kaydirmasi --attempts / --seed ile degistirilebilir.
## Arama deterministik oldugundan ayni komutu tekrarlamak ayni sonucu verir;
## tutmayan bir bolum icin ARAMA ALANINI degistirmek gerekir, komutu degil.
const DEFAULT_ATTEMPTS := 400

## Panel ve hedefin kalabilecegi alan (LevelData.DEFAULT_PLAY_RECT icinde,
## kenarlardan pay birakilmis hali).
const PANEL_X := Vector2(140.0, 580.0)
const PANEL_Y := Vector2(430.0, 980.0)
const TARGET_X := Vector2(120.0, 600.0)
const TARGET_Y := Vector2(210.0, 480.0)

var _only: Array[int] = []
var _attempts := DEFAULT_ATTEMPTS
var _seed_offset := 0
## Sapma buyutec carpani (--spread). 1.0 varsayilan; buyuk deger aramayi
## orijinalin yakin cevresinden cikarir. Bolum 19 gibi taban skoru cok dusuk
## bolumlerde gerekli oldu: kucuk sapmalar bozuk yerlesimin etrafinda dolasip
## duruyordu.
var _spread := 1.0
var _solver: LevelSolver
var _world: LevelWorld
var _rng := RandomNumberGenerator.new()
## iskelet imzasi -> onu kullanan bolum numarasi. Cakismayi bu tablo engeller.
var _taken: Dictionary = {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--only" and i + 1 < args.size():
			for piece in args[i + 1].split(",", false):
				var clean := piece.strip_edges()
				if clean.is_valid_int():
					_only.append(int(clean))
		elif args[i] == "--attempts" and i + 1 < args.size():
			_attempts = maxi(1, int(args[i + 1]))
		elif args[i] == "--seed" and i + 1 < args.size():
			_seed_offset = int(args[i + 1])
		elif args[i] == "--spread" and i + 1 < args.size():
			_spread = maxf(1.0, float(args[i + 1]))
	_run.call_deferred()


func _run() -> void:
	if _only.is_empty():
		print("--only ile bolum listesi verilmeli.")
		quit(1)
		return

	await physics_frame
	_solver = LevelSolver.from_scenes()
	_index_existing_skeletons()

	var ok := 0
	var failed: Array[int] = []
	for level_id in _only:
		if await _diversify(level_id):
			ok += 1
		else:
			failed.append(level_id)

	print("")
	print("OZET degistirildi=%d basarisiz=%d" % [ok, failed.size()])
	if not failed.is_empty():
		print("basarisiz bolumler: %s" % str(failed))
	quit(0 if failed.is_empty() else 1)


## Kutuphanedeki TUM bolumlerin iskeletini tablolar. Degistirilecek bolumler
## kendi eski imzalarini bilerek birakir: amac zaten o imzadan kacinmak.
func _index_existing_skeletons() -> void:
	for level_id in range(LevelLibrary.FIRST_LEVEL_ID, LevelLibrary.last_level_id() + 1):
		if _only.has(level_id):
			continue
		var level := LevelLibrary.load_level(level_id)
		_taken[_skeleton_key(level)] = level_id
	print("iskelet tablosu: %d bolum kayitli" % _taken.size())


## Bir bolumun "iskeleti": firlatici + hedef + paneller. find_duplicate_levels.py
## ile AYNI tanim - araclar ayni seyi olcmezse rapor yaniltici olur.
func _skeleton_key(level: LevelData) -> String:
	var parts: Array[String] = [
		"L%.1f,%.1f" % [level.launcher_position.x, level.launcher_position.y],
		"T%.1f,%.1f" % [level.target_position.x, level.target_position.y],
	]
	var panels: Array[String] = []
	for panel in level.panels:
		panels.append("P%.1f,%.1f,%.1f,%.1f,%.1f" % [
			panel.position.x, panel.position.y, panel.rotation_degrees,
			panel.length, panel.thickness])
	panels.sort()
	parts.append_array(panels)
	return "|".join(parts)


func _diversify(level_id: int) -> bool:
	var original := LevelLibrary.load_level(level_id)
	# Sabit tohum: ayni girdi ayni sonucu verir (projenin determinizm kurali).
	_rng.seed = 880000 + level_id * 7919 + _seed_offset * 104729

	# Kabul bandinin capasi: bolumun BUGUNKU skoru. Elle ayarlanmis bir bolumun
	# skorunu sabit bir sayiyla kiyaslamak yaniltir - 42 zaten dar bir bolum,
	# 14 ise genis. Her bolum kendi olcusuyle degerlendirilir.
	var base := await _evaluate_raw(original)
	var base_robust := int(base["robust"])
	# Alt sinir HER ZAMAN verifier'in barajidir. Taban bunun altindaysa
	# (bolum bugun piksel hassasiyetinde nisan istiyorsa) bant tabanin
	# etrafina kurulmaz - o zaman "mevcut halini koru" demek kusuru korumak
	# olurdu. Ust sinir da alt sinirla birlikte yukselir, yoksa bant
	# [6, 2] gibi imkansiz bir aralik olur.
	var low := maxi(MIN_ROBUST, int(round(float(base_robust) * BAND_LOW)))
	var high := maxi(int(round(float(base_robust) * BAND_HIGH)),
		int(round(float(low) * BAND_HIGH)))
	print("LEVEL %3d taban saglam=%d -> kabul bandi [%d, %d]%s" % [
		level_id, base_robust, low, high,
		"  (taban baraj altinda - bolum ayrica DUZELTILIYOR)"
			if base_robust < MIN_ROBUST else ""])

	# Ret sebepleri sayilir: bir bolum tutmazsa "neden" tahmin edilmesin.
	var rejects := {"validate": 0, "taken": 0, "clearance": 0, "geometry": 0,
		"low": 0, "high": 0, "nohit": 0}

	for attempt in _attempts:
		var level := original.duplicate(true) as LevelData
		_jitter(level)
		if not level.validate().is_empty():
			rejects["validate"] += 1
			continue
		if _skeleton_key(level) in _taken:
			rejects["taken"] += 1
			continue
		if not _obstacles_are_clear(level):
			rejects["clearance"] += 1
			continue

		var verdict := await _evaluate_raw(level)
		if not bool(verdict["geometry"]):
			rejects["geometry"] += 1
			continue
		var robust := int(verdict["robust"])
		if int(verdict["bounces"]) < 1:
			rejects["nohit"] += 1
			continue
		if robust < low:
			rejects["low"] += 1
			continue
		if robust > high:
			rejects["high"] += 1
			continue

		var error := ResourceSaver.save(level, "res://levels/level_%d.tres" % level_id)
		if error != OK:
			push_error("kayit hatasi level %d: %d" % [level_id, error])
			return false
		_taken[_skeleton_key(level)] = level_id
		print("LEVEL %3d cesitlendi  deneme=%d saglam=%d sekme=%d" % [
			level_id, attempt + 1, int(verdict["robust"]), int(verdict["bounces"])])
		return true

	print("LEVEL %3d BASARISIZ - %d deneme yetmedi  ret: %s" % [
		level_id, _attempts, str(rejects)])
	return false


## Panelleri, hedefi ve engelleri kaydirir. Tuglalar YERINDE kalir (26-40
## bandinin rota sozlesmesi tugla dizilimine bagli) ve engel TURLERI degismez:
## bu arac mekanigi degil, yerlesimi cesitler.
func _jitter(level: LevelData) -> void:
	level.target_position = Vector2(
		clampf(level.target_position.x + _rng.randf_range(-JITTER_TARGET * _spread, JITTER_TARGET * _spread),
			TARGET_X.x, TARGET_X.y),
		clampf(level.target_position.y + _rng.randf_range(-JITTER_TARGET * _spread, JITTER_TARGET * _spread),
			TARGET_Y.x, TARGET_Y.y))
	for panel in level.panels:
		panel.position = Vector2(
			clampf(panel.position.x + _signed_jitter(), PANEL_X.x, PANEL_X.y),
			clampf(panel.position.y + _signed_jitter(), PANEL_Y.x, PANEL_Y.y))
		panel.rotation_degrees = clampf(
			panel.rotation_degrees + _rng.randf_range(-JITTER_ANGLE * _spread, JITTER_ANGLE * _spread), -55.0, 55.0)
	_jitter_walls(level.left_wall_segments)
	_jitter_walls(level.right_wall_segments)
	for obstacle in level.obstacles:
		obstacle.position = Vector2(
			clampf(obstacle.position.x + _rng.randf_range(-OBSTACLE_JITTER, OBSTACLE_JITTER),
				OBSTACLE_X.x, OBSTACLE_X.y),
			clampf(obstacle.position.y + _rng.randf_range(-OBSTACLE_JITTER, OBSTACLE_JITTER),
				OBSTACLE_Y.x, OBSTACLE_Y.y))


## Duvardaki BOSLUGU kaydirir; boslugun BOYU korunur.
##
## OLCULEN sebep: bolum 19'da yalnizca panelleri oynatmak yetmedi - 1200
## denemenin 1114'u baraj altinda kaldi. O bolumde rota sol duvardaki
## bosluktan gecmek zorunda; bosluk sabit kalinca paneller nereye giderse
## gitsin koridor kapaniyordu. Bosluk da yerlesimin parcasidir, dolayisiyla
## aramaya aittir - ama boyu degismez, cunku boslugun genisligi bolumun
## zorluk kimligidir.
func _jitter_walls(segments: Array[Vector2]) -> void:
	if segments.size() < 2:
		return
	var shift := _rng.randf_range(-WALL_JITTER, WALL_JITTER)
	for i in segments.size() - 1:
		# segments[i] = (bas, son) seklinde DOLU aralik; ardisik ikisinin
		# arasi bosluktur. Iki ucu ayni miktarda kaydirmak boyu korur.
		segments[i] = Vector2(segments[i].x, segments[i].y + shift)
		segments[i + 1] = Vector2(segments[i + 1].x + shift, segments[i + 1].y)


## En az JITTER_MIN buyuklugunde; yonu rastgele. Alt sinir bilerek var:
## bir kac piksellik kayma imzayi degistirir ama oyuncu icin ayni bolumdur.
func _signed_jitter() -> float:
	var amount := _rng.randf_range(JITTER_MIN, JITTER_MAX * _spread)
	return amount if _rng.randf() < 0.5 else -amount


## Paneller kaydiktan sonra bir engel hedefin/firlaticinin/panelin uzerine
## binmis olabilir; o bolum ilk karede cozulemez hale gelir.
func _obstacles_are_clear(level: LevelData) -> bool:
	var spawn := _solver.spawn_position(level.launcher_position)
	for obstacle in level.obstacles:
		var radius := obstacle.size.length() * 0.5 + obstacle.travel_distance \
			if obstacle.kind == ObstacleData.Kind.MOVING_BAR else obstacle.outer_radius()
		if obstacle.position.distance_to(level.target_position) \
				< radius + _solver.target_size * 0.5 + CLEARANCE:
			return false
		if obstacle.position.distance_to(spawn) < radius + _solver.radius + CLEARANCE:
			return false
		for panel in level.panels:
			if _distance_to_panel(obstacle.position, panel) < radius + CLEARANCE:
				return false
	return true


func _distance_to_panel(point: Vector2, panel: PanelData) -> float:
	var axis := Vector2.RIGHT.rotated(deg_to_rad(panel.rotation_degrees))
	var half := panel.length * 0.5
	var offset := point - panel.position
	var along := clampf(offset.dot(axis), -half, half)
	return point.distance_to(panel.position + axis * along) - panel.thickness * 0.5


## verify_levels.gd::_check_static_geometry ile AYNI kontroller, ayni cagriyla
## (LevelSolver.overlaps_obstacle). Kendi geometri hesabimi yazmiyorum: iki
## arac ayni seyi olcmezse "burada gecti, verifier'da kaldi" durumu dogar -
## nitekim jeneratorde tam bu eksikti ve hedefi panelin GOVDESINE gomulmus
## yedi bolum uretti (52, 71, 72, 89, 94, 113, 114).
func _static_geometry_ok(level: LevelData, spawn: Vector2) -> bool:
	if _solver.overlaps_obstacle(level.target_position, _solver.target_size * 0.5):
		return false
	if _solver.overlaps_obstacle(spawn, _solver.radius):
		return false
	if _solver.overlaps_obstacle(level.launcher_position, 60.0):
		return false
	# Hedef ust HUD seridinin arkasina dusmemeli (verifier ile ayni esik).
	return level.target_position.y - _solver.target_size * 0.5 >= 150.0


## Bolumu tarar ve OLCUMU dondurur; kabul karari cagirana aittir (bkz.
## _diversify), cunku baraj bolumun kendi taban skoruna gore belirlenir.
func _evaluate_raw(level: LevelData) -> Dictionary:
	_world = LevelWorld.new()
	root.add_child(_world)
	_world.build(level)
	_solver.bind_space(_world.get_space(), _world.get_block_rids(), _world.get_obstacles())
	await physics_frame
	await physics_frame

	var spawn := _solver.spawn_position(level.launcher_position)
	var play_rect := _world.get_play_rect()
	var result := {"robust": 0, "bounces": -1, "geometry": _static_geometry_ok(level, spawn)}
	if bool(result["geometry"]):
		var scan := _solver.scan(spawn, level.target_position, play_rect,
			[], ANGLE_STEP, POWER_STEP)
		var analysis := LevelSolver.analyse_robust(scan)
		result["robust"] = int(analysis["robust"])
		result["bounces"] = int(analysis["bounces"]) if int(scan["hit_count"]) > 0 else -1

	root.remove_child(_world)
	_world.queue_free()
	_world = null
	return result
