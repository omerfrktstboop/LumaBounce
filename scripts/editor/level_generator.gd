class_name LevelGenerator
extends Node

## Rastgele bolum adaylari uretir ve fizige gore eler.
##
## FIKIR: bugune kadar yerlesimi ben koyuyordum, verifier yarglyordu. Burada
## yon tersine cevrilir - rastgele yerlestirilir, ayni fizik ELER. Uretec
## tasarim yapmaz, ARAMA yapar; begenme kararı hala insanda kalir. Cikti
## "oynanabilir ve toleransli" oldugu dogrulanmis bir kisa listedir.
##
## KADEMELI FILTRE: bir taramanin maliyeti orneklem sayisiyla dogru orantili
## oldugu icin adaylar once cok kaba bir izgaradan gecer (ucuz, %90'i eler),
## yalnizca hayatta kalanlar normal izgarada olculur. Boylece telefonda bile
## dakikalar yerine saniyeler surer.
##
## KARE BLOKLAMAZ: her N simulasyonda bir process_frame beklenir, arayuz
## donmaz ve ilerleme gosterilebilir.

## Bir aday uretilirken hedefe ulasilamazsa bosuna ince taramaya girmesin.
const COARSE_ANGLE_STEP := 6.0
const COARSE_POWER_STEP := 200.0
## Kabul edilen adayin olculdugu izgara. Verifier'in bloklu modda kullandigi
## degerlerle ayni tutulur ki raporlar karsilastirilabilir olsun.
const FINE_ANGLE_STEP := 3.0
const FINE_POWER_STEP := 100.0
## Kaba taramada en az bu kadar isabet yoksa aday ince taramaya alinmaz.
const COARSE_MIN_HITS := 2
## Arayuzun donmamasi icin bu kadar simulasyondan sonra bir kare beklenir.
const SIMS_PER_FRAME := 120

## Bir aday uretildi (kabul veya ret). [param accepted] kabul edildiyse true.
signal candidate_evaluated(tried: int, accepted: int)
## Uretim bitti; [param levels] kabul edilen bolumler.
signal finished(levels: Array[LevelData])
## AI blueprint akisi icin LevelData yaninda kaynak/seed/solver olcumleri.
signal blueprints_finished(candidates: Array[Dictionary])
signal blueprint_progress(tried: int, total: int, accepted: int)

## Zorluk profili. Filtreyi bununla ayarlarsin: kolay bolum genis pencere ve
## az sekme, zor bolum dar pencere ve cok sekme ister.
##
## ESIKLER ELLE YAPILMIS BOLUMLERE GORE KALIBRE EDILDI (3 derece / 100 guc
## izgarasinda olculmustur; baska bir izgarada sayilar degisir):
##   - Bolum 1  (en kolay, 0 sekme)          -> 25 saglam hucre
##   - Bolum 21-25 bloksuz ustalik rotalari  -> 9-12 saglam hucre
##   - 40 rastgele adayin dagilimi           -> 5..58, ortanca ~20
## Referans olmadan bu sayilar anlamsizdir; "30 iyidir" gibi bir sezgi ilk
## denemede bolum 1'in kendisini bile eleyen bir filtre uretmisti.
class Profile extends RefCounted:
	var display_name := "Üretilen"
	var min_robust := 12
	var max_robust := 60
	var min_bounces := 0
	var max_bounces := 3
	var panel_count := Vector2i(1, 2)
	var block_count := Vector2i(0, 1)
	var max_lives := 4
	## Blok varsa bloksuz rota da bulunmali (bkz. verifier tasarim sozlesmesi).
	var require_block_free_route := true

	## Bolum 1 seviyesinde ya da daha rahat: genis pencere, kisa rota.
	static func easy() -> Profile:
		var p := Profile.new()
		p.display_name = "Kolay"
		p.min_robust = 26
		p.max_robust = 200
		p.max_bounces = 1
		p.panel_count = Vector2i(1, 1)
		p.block_count = Vector2i(0, 0)
		p.max_lives = 5
		return p

	## Rastgele dagilimin ortasi: cozulebilir ama dusunmek gerekir.
	static func medium() -> Profile:
		var p := Profile.new()
		p.display_name = "Orta"
		p.min_robust = 14
		p.max_robust = 30
		p.max_bounces = 2
		p.panel_count = Vector2i(1, 2)
		p.block_count = Vector2i(0, 1)
		return p

	## 21-25'in ustalik rotalari bandi: dar ama piksel hassasiyeti degil.
	static func hard() -> Profile:
		var p := Profile.new()
		p.display_name = "Zor"
		p.min_robust = 7
		p.max_robust = 16
		p.min_bounces = 1
		p.max_bounces = 4
		p.panel_count = Vector2i(2, 3)
		p.block_count = Vector2i(1, 2)
		return p

	## Bloklu bolumler ayrica "kirmak rotayi kolaylastirmali" testinden gecer,
	## bu yuzden kabul orani dusuktur ve bant bilerek genis tutulur.
	static func with_blocks() -> Profile:
		var p := Profile.new()
		p.display_name = "Bloklu"
		p.min_robust = 9
		p.max_robust = 32
		p.max_bounces = 3
		p.panel_count = Vector2i(1, 2)
		p.block_count = Vector2i(1, 3)
		return p

var _solver: LevelSolver
var _world: LevelWorld
var _rng := RandomNumberGenerator.new()
var _cancelled := false
var _running := false
## Neden kaci elendi. Bir profil sonuc vermiyorsa hangi kriterin fazla sıkı
## oldugunu soyler - "hicbir sey bulunamadi" tek basina yol gostermez.
var _rejections := {}
var _last_blueprint_records: Array[Dictionary] = []


## Son uretimin eleme dokumu: sebep -> adet.
func get_rejection_summary() -> Dictionary:
	return _rejections.duplicate()


func describe_rejections() -> String:
	if _rejections.is_empty():
		return ""
	var parts := PackedStringArray()
	for reason in _rejections:
		parts.append("%s %d" % [reason, int(_rejections[reason])])
	return ", ".join(parts)


func _reject(reason: String, sims: int) -> Dictionary:
	_rejections[reason] = int(_rejections.get(reason, 0)) + 1
	return {"ok": false, "sims": sims}


func _ready() -> void:
	_solver = LevelSolver.from_scenes()
	_world = LevelWorld.new()
	_world.name = "GeneratorWorld"
	# Uretec dunyasi gorunmez: yalnizca fizik sorgulari icin var.
	_world.visible = false
	add_child(_world)


func is_running() -> bool:
	return _running


func was_cancelled() -> bool:
	return _cancelled


func cancel() -> void:
	_cancelled = true


func get_last_blueprint_records() -> Array[Dictionary]:
	return _last_blueprint_records.duplicate(true)


## [param wanted] kadar bolum bulana ya da [param max_tries] adayi
## tuketene kadar arar.
func generate(profile: Profile, wanted: int, max_tries := 400, seed_value := 0) -> void:
	if _running:
		return
	_running = true
	_cancelled = false
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()

	var accepted: Array[LevelData] = []
	_last_blueprint_records.clear()
	_rejections.clear()
	var tried := 0
	var budget := 0

	while accepted.size() < wanted and tried < max_tries and not _cancelled:
		tried += 1
		var candidate := _random_level(profile)
		_world.build(candidate)
		# Yeni govdelerin fizik uzayina girmesi icin iki kare sart.
		await get_tree().physics_frame
		await get_tree().physics_frame
		_solver.bind_space(_world.get_space(), _world.get_block_rids())

		var verdict := await _evaluate(candidate, profile)
		budget += int(verdict["sims"])
		if bool(verdict["ok"]):
			candidate.display_name = "%s %d" % [profile.display_name, accepted.size() + 1]
			accepted.append(candidate)

		candidate_evaluated.emit(tried, accepted.size())
		if budget > SIMS_PER_FRAME:
			budget = 0
			await get_tree().process_frame

	_world.clear()
	_running = false
	if _cancelled:
		accepted.clear()
	finished.emit(accepted)


## AI mapper'in temiz blueprint'lerini yerelde cesitlendirir ve yine gercek
## LevelSolver fizigiyle eler. Orijinal taslaklar once, sonra varyasyonlar
## round-robin sirayla test edilir; boylece ilk blueprint partiyi tek basina
## doldurmaz.
func generate_from_blueprints(profile: Profile, blueprints: Array, wanted: int,
		variations_per_blueprint: int, seed_value := 0) -> void:
	if _running:
		return
	_running = true
	_cancelled = false
	_rejections.clear()
	_last_blueprint_records.clear()
	var effective_seed := seed_value
	if effective_seed == 0:
		_rng.randomize()
		effective_seed = _rng.randi()
	var candidates := build_blueprint_variations(
		blueprints, clampi(variations_per_blueprint, 0, 30), effective_seed)
	var accepted_levels: Array[LevelData] = []
	var accepted_records: Array[Dictionary] = []
	var tried := 0

	for source in candidates:
		if _cancelled or accepted_levels.size() >= clampi(wanted, 1, 20):
			break
		tried += 1
		var candidate: LevelData = source["level"]
		_world.build(candidate)
		await get_tree().physics_frame
		await get_tree().physics_frame
		_solver.bind_space(_world.get_space(), _world.get_block_rids())
		var verdict := await _evaluate(candidate, profile)
		if bool(verdict["ok"]) and not _cancelled:
			if candidate.display_name.is_empty():
				candidate.display_name = "AI Aday %d" % (accepted_levels.size() + 1)
			accepted_levels.append(candidate)
			var accepted := source.duplicate(true)
			accepted["solver"] = verdict.duplicate(true)
			accepted_records.append(accepted)
		candidate_evaluated.emit(tried, accepted_levels.size())
		blueprint_progress.emit(tried, candidates.size(), accepted_levels.size())
		await get_tree().process_frame

	_world.clear()
	_running = false
	if _cancelled:
		accepted_levels.clear()
		accepted_records.clear()
	_last_blueprint_records.assign(accepted_records)
	blueprints_finished.emit(accepted_records)
	finished.emit(accepted_levels)


## Testler ve coordinator icin saf/deterministik varyasyon adimi. Fizik yoktur.
func build_blueprint_variations(blueprints: Array, variations_per_blueprint: int,
		seed_value: int) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var sources: Array[Dictionary] = []
	for i in blueprints.size():
		var source := _normalize_blueprint(blueprints[i], i)
		if not source.is_empty():
			sources.append(source)
	for source in sources:
		var original := source.duplicate(true)
		original["level"] = (source["level"] as LevelData).duplicate(true)
		original["variation_seed"] = 0
		records.append(original)
	for variation_index in clampi(variations_per_blueprint, 0, 30):
		for source in sources:
			var blueprint_index := int(source["blueprint_index"])
			var variation_seed := seed_value + blueprint_index * 1000003 + (variation_index + 1) * 9176
			var varied := source.duplicate(true)
			varied["level"] = _vary_level(source["level"], variation_seed)
			varied["variation_seed"] = variation_seed
			records.append(varied)
	return records


func _normalize_blueprint(value: Variant, fallback_index: int) -> Dictionary:
	if value is LevelData:
		return {"level": value, "blueprint_index": fallback_index}
	if value is Dictionary and value.get("level", null) is LevelData:
		var source: Dictionary = value.duplicate(true)
		source["blueprint_index"] = int(source.get("blueprint_index", fallback_index))
		return source
	return {}


func _vary_level(source: LevelData, variation_seed: int) -> LevelData:
	var level := source.duplicate(true) as LevelData
	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed
	level.target_position = Vector2(
		clampf(level.target_position.x + rng.randf_range(-25.0, 25.0), 80.0, 640.0),
		clampf(level.target_position.y + rng.randf_range(-25.0, 25.0), 180.0, 560.0))
	for panel in level.panels:
		panel.position = Vector2(
			clampf(panel.position.x + rng.randf_range(-40.0, 40.0), 60.0, 660.0),
			clampf(panel.position.y + rng.randf_range(-40.0, 40.0), 180.0, 1080.0))
		panel.rotation_degrees = clampf(
			panel.rotation_degrees + rng.randf_range(-6.0, 6.0), -80.0, 80.0)
		panel.length = clampf(panel.length + rng.randf_range(-40.0, 40.0), 140.0, 420.0)
	for block in level.breakable_blocks:
		block.position = Vector2(
			clampf(block.position.x + rng.randf_range(-35.0, 35.0), 60.0, 660.0),
			clampf(block.position.y + rng.randf_range(-35.0, 35.0), 180.0, 1080.0))
		block.size.x = clampf(block.size.x + rng.randf_range(-30.0, 30.0), 120.0, 360.0)
	_vary_wall(level.left_wall_segments, rng)
	_vary_wall(level.right_wall_segments, rng)
	return level


func _vary_wall(segments: Array[Vector2], rng: RandomNumberGenerator) -> void:
	if segments.size() != 2:
		return
	var top := clampf(segments[0].y + rng.randf_range(-40.0, 40.0), 120.0, 1064.0)
	var bottom := clampf(segments[1].x + rng.randf_range(-40.0, 40.0), top + 96.0, 1160.0)
	var upper := segments[0]
	var lower := segments[1]
	upper.y = top
	lower.x = bottom
	segments[0] = upper
	segments[1] = lower


# --- Degerlendirme ------------------------------------------------------------

func _evaluate(level: LevelData, profile: Profile) -> Dictionary:
	var play_rect := _world.get_play_rect()
	var spawn := _solver.spawn_position(level.launcher_position)
	var sims := 0

	# 0) Bedava statik kontroller - cogu kotu adayi hic simule etmeden eler.
	if not _static_geometry_ok(level, spawn):
		return _reject("yerlesim", 0)

	var no_blocks: Array[RID] = []

	# 1) Kaba tarama: hicbir isabet yoksa devam etmenin anlami yok.
	var coarse := await _solver.scan_async(spawn, level.target_position, play_rect,
		no_blocks, COARSE_ANGLE_STEP, COARSE_POWER_STEP, SIMS_PER_FRAME,
		Callable(self, "_is_cancelled"))
	sims += int(coarse["total"])
	if bool(coarse.get("cancelled", false)):
		return _reject("iptal", sims)
	if int(coarse["hit_count"]) < COARSE_MIN_HITS:
		return _reject("cozulemez", sims)

	# 2) Ince tarama: bloksuz rotanin gercek penceresi.
	var fine := await _solver.scan_async(spawn, level.target_position, play_rect,
		no_blocks, FINE_ANGLE_STEP, FINE_POWER_STEP, SIMS_PER_FRAME,
		Callable(self, "_is_cancelled"))
	sims += int(fine["total"])
	if bool(fine.get("cancelled", false)):
		return _reject("iptal", sims)
	var analysis := LevelSolver.analyse_robust(fine)
	var route_clusters := LevelSolver.analyse_solution_clusters(fine).size()
	var robust := int(analysis["robust"])
	if robust < profile.min_robust:
		return _reject("pencere-dar", sims)
	if robust > profile.max_robust:
		return _reject("pencere-genis", sims)

	var bounces := int(analysis["bounces"])
	if bounces < profile.min_bounces or bounces > profile.max_bounces:
		return _reject("sekme", sims)

	# 3) Blok varsa: kirmak rotayi GERCEKTEN kolaylastirmali. Kolaylastirmayan
	#    blok bulmacaya hicbir sey katmaz, sadece ekrani doldurur.
	if level.breakable_blocks.is_empty():
		return {
			"ok": true, "sims": sims, "robust": robust, "bounces": bounces,
			"opened_robust": robust, "block_free": true,
			"route_clusters": route_clusters,
		}

	var all_broken := (1 << level.breakable_blocks.size()) - 1
	var opened := await _solver.scan_async(spawn, level.target_position, play_rect,
		_world.rids_for_state(all_broken), FINE_ANGLE_STEP, FINE_POWER_STEP,
		SIMS_PER_FRAME, Callable(self, "_is_cancelled"))
	sims += int(opened["total"])
	if bool(opened.get("cancelled", false)):
		return _reject("iptal", sims)
	var opened_robust := int(LevelSolver.analyse_robust(opened)["robust"])
	if opened_robust <= robust:
		return _reject("blok-katkisiz", sims)

	return {
		"ok": true, "sims": sims, "robust": robust, "bounces": bounces,
		"opened_robust": opened_robust, "block_free": robust > 0,
		"route_clusters": route_clusters,
	}


func _is_cancelled() -> bool:
	return _cancelled


func _static_geometry_ok(level: LevelData, spawn: Vector2) -> bool:
	if level.target_position.y - _solver.target_size * 0.5 < 150.0:
		return false
	if _solver.overlaps_obstacle(level.target_position, _solver.target_size * 0.5):
		return false
	if _solver.overlaps_obstacle(spawn, _solver.radius):
		return false
	if _solver.overlaps_obstacle(level.launcher_position, 60.0):
		return false
	return true


# --- Rastgele yerlesim --------------------------------------------------------

func _random_level(profile: Profile) -> LevelData:
	var level := LevelData.new()
	level.level_id = 1
	level.max_lives = profile.max_lives
	level.launcher_position = Vector2(360.0, 1120.0)
	# Hedef ust yariya, HUD seridinin altina kalacak sekilde.
	level.target_position = Vector2(
		_rng.randf_range(140.0, 580.0), _rng.randf_range(230.0, 480.0))

	var panels: Array[PanelData] = []
	for i in _rng.randi_range(profile.panel_count.x, profile.panel_count.y):
		panels.append(_random_panel())
	level.panels = panels

	var blocks: Array[BreakableBlockData] = []
	for i in _rng.randi_range(profile.block_count.x, profile.block_count.y):
		blocks.append(_random_block())
	level.breakable_blocks = blocks

	# Yildiz esikleri mevcut dengeye uyar; editorde elle degistirilebilir.
	level.three_star_max_shots = 2
	level.two_star_max_shots = mini(4, profile.max_lives)
	level.three_star_max_seconds = 50.0
	level.two_star_max_seconds = 100.0
	return level


func _random_panel() -> PanelData:
	var panel := PanelData.new()
	panel.position = Vector2(
		_rng.randf_range(150.0, 570.0), _rng.randf_range(450.0, 950.0))
	panel.rotation_degrees = _rng.randf_range(-55.0, 55.0)
	panel.length = _rng.randf_range(220.0, 340.0)
	panel.thickness = 26.0
	return panel


func _random_block() -> BreakableBlockData:
	var block := BreakableBlockData.new()
	block.position = Vector2(
		_rng.randf_range(150.0, 570.0), _rng.randf_range(480.0, 900.0))
	block.rotation_degrees = 0.0
	block.size = Vector2(_rng.randf_range(160.0, 300.0), 44.0)
	return block
