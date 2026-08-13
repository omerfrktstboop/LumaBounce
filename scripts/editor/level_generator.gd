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
## AI varyasyonlari ayni kucuk komsuluga yigilirsa kotu bir blueprint'in 10+
## kopyasi da ayni nedenle elenir. Dortlu kademeler ince -> orta -> genis
## arama yapar; filtre esikleri degismez.
const VARIATION_TIER_SIZE := 4
const MAX_VARIATION_SCALE := 3.0
const ANCHOR_CLEARANCE := 14.0

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
##   - Standart zor tek-sekme iskeletleri    -> 7-16 saglam hucre
##   - 40 rastgele adayin dagilimi           -> 5..58, ortanca ~20
## Referans olmadan bu sayilar anlamsizdir; "30 iyidir" gibi bir sezgi ilk
## denemede bolum 1'in kendisini bile eleyen bir filtre uretmisti.
class Profile extends RefCounted:
	var evaluation_mode := "standard"
	var display_name := "Üretilen"
	var min_robust := 12
	var max_robust := 60
	var min_bounces := 0
	var max_bounces := 3
	var panel_count := Vector2i(1, 2)
	var block_count := Vector2i(0, 1)
	var wall_gap_count := Vector2i(0, 0)
	var obstacle_count := Vector2i(0, 0)
	var obstacle_kinds: Array[int] = []
	var include_each_obstacle_kind := false
	var max_lives := 4
	var target_y_range := Vector2(235.0, 345.0)
	var enforce_difficulty_score := false
	var min_difficulty_score := 0
	var max_difficulty_score := 100
	## Blok varsa bloksuz rota da bulunmali (bkz. verifier tasarim sozlesmesi).
	var require_block_free_route := true
	var min_solution_shots := 1
	var max_solution_shots := 1

	## Bolum 1 seviyesinde ya da daha rahat: genis pencere, kisa rota.
	static func easy() -> Profile:
		var p := Profile.new()
		p.display_name = "Kolay"
		# Bolumler yeniden numaralandiginca bu esik oyunun KENDI en kolay
		# bolumunden siki hale gelmisti: bolum 1 ayni izgarada 16 saglam
		# hucre olcuyor, esik ise 26'ydi. Referanssiz secilen esik, uretecin
		# resmi tasarim standardini reddetmesi demek.
		p.min_robust = 14
		p.max_robust = 200
		p.max_bounces = 1
		p.panel_count = Vector2i(1, 1)
		p.block_count = Vector2i(0, 0)
		p.max_lives = 5
		p.target_y_range = Vector2(340.0, 460.0)
		return p

	## Rastgele dagilimin ortasi: cozulebilir ama dusunmek gerekir.
	static func medium() -> Profile:
		var p := Profile.new()
		p.display_name = "Orta"
		p.min_robust = 14
		p.max_robust = 30
		# min_bounces varsayilani 0'di, yani duz atisla gecilen bir bolum de
		# "Orta" sayilabiliyordu. En az bir sekme artik zorunlu.
		p.min_bounces = 1
		p.max_bounces = 2
		p.panel_count = Vector2i(1, 2)
		p.block_count = Vector2i(0, 1)
		p.target_y_range = Vector2(235.0, 345.0)
		return p

	## Standart zor aday bandi: dar ama piksel hassasiyeti degil.
	static func hard() -> Profile:
		var p := Profile.new()
		p.display_name = "Zor"
		# min_bounces, analyse_robust()'un EN AZ sekmeli saglam hucresine
		# bakar; yani "en kolay saglam rota bile en az bu kadar sekme
		# istesin" demektir ve dolayli olarak kestirmeleri de eler.
		# Eskiden 1'di: bu yalnizca 0 sekmeli duz atisi disliyordu, tek
		# sekmeli bir rota "zor" sayiliyordu. Olcum (90 rastgele aday):
		# 0 sekme x18, 1 sekme x50, 2 sekme x8, 3 sekme x2, 5 sekme x1.
		# Yani "zor" adaylarin %76'si aslinda 0-1 sekmeydi.
		p.min_bounces = 2
		p.max_bounces = 6
		# Sekme sayisi arttikca isabet penceresi daralir (ayni olcumde
		# ortalama saglam hucre: 0 sekme->22, 1->10, 2->3, 3->1). Eski 7
		# alt siniri 2+ sekmeli hicbir adayin gecemeyecegi bir esikti, bu
		# yuzden profil pratikte yalnizca tek sekmeli bolum uretebiliyordu.
		# 2, ortalamanin (3) altinda kalarak jitter'a pay birakir; 1 olsaydi
		# tek hucrelik, yani piksel hassasiyetli rotalar da gecerdi.
		p.min_robust = 2
		p.max_robust = 24
		p.panel_count = Vector2i(2, 3)
		p.block_count = Vector2i(1, 2)
		p.target_y_range = Vector2(225.0, 320.0)
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
		p.target_y_range = Vector2(245.0, 360.0)
		return p

	## Uzun sekmelerde kucuk nisan farklari hizla buyur. Bu profil, gercek
	## izgara cozumunu ve saglam kisa yol bulunmamasini ayri olcer.
	static func ricochet_chain() -> Profile:
		var p := Profile.new()
		p.display_name = "Sekme Zinciri"
		p.evaluation_mode = "ricochet_chain"
		p.min_robust = 1
		p.max_robust = 12
		p.min_bounces = 5
		p.max_bounces = 10
		p.panel_count = Vector2i(2, 4)
		p.block_count = Vector2i(0, 0)
		p.max_lives = 5
		p.target_y_range = Vector2(220.0, 500.0)
		return p

	## Hedef, en az bir blogun kalici kirilmasindan sonra 2-4 atista acilir.
	static func block_corridor() -> Profile:
		var p := Profile.new()
		p.display_name = "Blok Koridoru"
		p.evaluation_mode = "block_corridor"
		p.min_robust = 6
		p.max_robust = 80
		p.panel_count = Vector2i(0, 2)
		p.block_count = Vector2i(2, 4)
		p.max_lives = 5
		p.target_y_range = Vector2(230.0, 420.0)
		p.require_block_free_route = false
		p.min_solution_shots = 2
		p.max_solution_shots = 4
		return p

	## 41+ mekanikleri: solver hareketi her atista ayni fazdan baslatir.
	static func kinetic() -> Profile:
		var p := Profile.new()
		p.display_name = "Engelli"
		p.min_robust = 4
		p.max_robust = 34
		p.min_bounces = 0
		p.max_bounces = 5
		p.panel_count = Vector2i(1, 2)
		p.block_count = Vector2i(0, 0)
		p.obstacle_count = Vector2i(1, 3)
		p.obstacle_kinds = [
			ObstacleData.Kind.METAL_RING, ObstacleData.Kind.BOMB,
			ObstacleData.Kind.ROTATING_WHEEL, ObstacleData.Kind.MOVING_BAR,
		]
		p.max_lives = 5
		p.target_y_range = Vector2(225.0, 390.0)
		return p

	## Editordeki kayitli hizli uretim ayarini fizik profilinde somutlastirir.
	## Secilen engel turleri yalnizca izin listesi degil, adayda en az birer
	## kez bulunmasi gereken mekaniklerdir. Son kabulü 0-100 zorluk skoru yapar.
	static func custom(settings: Dictionary) -> Profile:
		var p := Profile.new()
		var mechanics := PackedStringArray(
			settings.get("local_mechanics", PackedStringArray(["panel"])))
		if mechanics.is_empty():
			mechanics.append("panel")
		p.min_difficulty_score = clampi(int(settings.get("local_score_min", 20)), 0, 100)
		p.max_difficulty_score = clampi(int(settings.get("local_score_max", 60)), 0, 100)
		if p.min_difficulty_score > p.max_difficulty_score:
			var swap := p.min_difficulty_score
			p.min_difficulty_score = p.max_difficulty_score
			p.max_difficulty_score = swap
		p.display_name = "Özel %d-%d" % [
			p.min_difficulty_score, p.max_difficulty_score]
		p.enforce_difficulty_score = true
		p.min_robust = 1
		p.max_robust = 10000
		p.min_bounces = 0
		p.max_bounces = 12
		p.max_lives = 5
		p.target_y_range = Vector2(220.0, 480.0)
		p.panel_count = Vector2i(1, 3) if mechanics.has("panel") else Vector2i.ZERO
		p.block_count = (
			Vector2i(1, 3) if mechanics.has("breakable_block") else Vector2i.ZERO)
		p.wall_gap_count = Vector2i(1, 2) if mechanics.has("wall_gap") else Vector2i.ZERO
		var obstacle_ids := [
			["metal_ring", ObstacleData.Kind.METAL_RING],
			["bomb", ObstacleData.Kind.BOMB],
			["rotating_wheel", ObstacleData.Kind.ROTATING_WHEEL],
			["moving_bar", ObstacleData.Kind.MOVING_BAR],
			["pulse_laser", ObstacleData.Kind.PULSE_LASER],
		]
		for definition in obstacle_ids:
			if mechanics.has(definition[0]):
				p.obstacle_kinds.append(int(definition[1]))
		if not p.obstacle_kinds.is_empty():
			p.include_each_obstacle_kind = true
			p.obstacle_count = Vector2i(
				p.obstacle_kinds.size(), mini(p.obstacle_kinds.size() + 1, 6))
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
var _last_generation_records: Array[Dictionary] = []


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


func get_last_generation_records() -> Array[Dictionary]:
	return _last_generation_records.duplicate(true)


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
	_last_generation_records.clear()
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
		_solver.bind_space(
			_world.get_space(), _world.get_block_rids(), _world.get_obstacles())

		var verdict := await _evaluate(candidate, profile)
		budget += int(verdict["sims"])
		if bool(verdict["ok"]):
			_apply_verdict_difficulty(candidate, verdict)
			candidate.display_name = "%s %d" % [profile.display_name, accepted.size() + 1]
			accepted.append(candidate)
			_last_generation_records.append(_metadata_from_verdict(verdict))

		candidate_evaluated.emit(tried, accepted.size())
		if budget > SIMS_PER_FRAME:
			budget = 0
			await get_tree().process_frame

	_world.clear()
	_running = false
	if _cancelled:
		accepted.clear()
		_last_generation_records.clear()
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
	_last_generation_records.clear()
	var effective_seed := seed_value
	if effective_seed == 0:
		_rng.randomize()
		effective_seed = _rng.randi()
	var candidates := build_blueprint_variations(
		blueprints, clampi(variations_per_blueprint, 0, 30), effective_seed, profile)
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
		_solver.bind_space(
			_world.get_space(), _world.get_block_rids(), _world.get_obstacles())
		var verdict := await _evaluate(candidate, profile)
		if bool(verdict["ok"]) and not _cancelled:
			_apply_verdict_difficulty(candidate, verdict)
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
		seed_value: int, profile: Profile = null) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var sources: Array[Dictionary] = []
	for i in blueprints.size():
		var source := _normalize_blueprint(blueprints[i], i)
		if not source.is_empty():
			sources.append(source)
	for source in sources:
		var original := source.duplicate(true)
		var original_level := (source["level"] as LevelData).duplicate(true)
		_repair_anchor_clearance(
			original_level, seed_value + int(source["blueprint_index"]) * 1000003)
		original["level"] = original_level
		original["variation_seed"] = 0
		original["variation_scale"] = 0.0
		records.append(original)
	for variation_index in clampi(variations_per_blueprint, 0, 30):
		for source in sources:
			var blueprint_index := int(source["blueprint_index"])
			var variation_seed := seed_value + blueprint_index * 1000003 + (variation_index + 1) * 9176
			var variation_scale := _variation_scale(variation_index)
			var varied := source.duplicate(true)
			varied["level"] = _vary_level(
				source["level"], variation_seed, variation_scale, profile)
			varied["variation_seed"] = variation_seed
			varied["variation_scale"] = variation_scale
			varied["physics_rescue"] = (
				variation_scale >= MAX_VARIATION_SCALE and profile != null
				and (profile.min_bounces > 0 or profile.evaluation_mode != "standard"))
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


func _variation_scale(variation_index: int) -> float:
	return minf(
		1.0 + floorf(float(variation_index) / float(VARIATION_TIER_SIZE)),
		MAX_VARIATION_SCALE)


func _vary_level(source: LevelData, variation_seed: int, scale: float,
		profile: Profile) -> LevelData:
	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed
	if scale >= MAX_VARIATION_SCALE and profile != null:
		var rescued: LevelData = null
		match profile.evaluation_mode:
			"ricochet_chain":
				rescued = _build_ricochet_rescue_level(source, rng)
			"block_corridor":
				rescued = _build_block_corridor_rescue_level(source, rng)
			_:
				if profile.min_bounces > 0:
					rescued = _build_hard_rescue_level(source, rng)
		if rescued != null:
			_repair_anchor_clearance(rescued, variation_seed + 48611)
			return rescued

	var level := source.duplicate(true) as LevelData
	level.target_position = Vector2(
		clampf(level.target_position.x + rng.randf_range(-25.0, 25.0) * scale, 80.0, 640.0),
		clampf(level.target_position.y + rng.randf_range(-25.0, 25.0) * scale, 180.0, 560.0))
	for panel in level.panels:
		panel.position = Vector2(
			clampf(panel.position.x + rng.randf_range(-40.0, 40.0) * scale, 60.0, 660.0),
			clampf(panel.position.y + rng.randf_range(-40.0, 40.0) * scale, 180.0, 1080.0))
		panel.rotation_degrees = clampf(
			panel.rotation_degrees + rng.randf_range(-6.0, 6.0) * scale, -80.0, 80.0)
		panel.length = clampf(
			panel.length + rng.randf_range(-40.0, 40.0) * scale, 140.0, 420.0)
	for block in level.breakable_blocks:
		block.position = Vector2(
			clampf(block.position.x + rng.randf_range(-35.0, 35.0) * scale, 60.0, 660.0),
			clampf(block.position.y + rng.randf_range(-35.0, 35.0) * scale, 180.0, 1080.0))
		block.size.x = clampf(
			block.size.x + rng.randf_range(-30.0, 30.0) * scale, 120.0, 360.0)
	for obstacle in level.obstacles:
		obstacle.position = Vector2(
			clampf(obstacle.position.x + rng.randf_range(-32.0, 32.0) * scale, 70.0, 650.0),
			clampf(obstacle.position.y + rng.randf_range(-32.0, 32.0) * scale, 180.0, 1060.0))
		obstacle.rotation_degrees = wrapf(
			obstacle.rotation_degrees + rng.randf_range(-8.0, 8.0) * scale,
			-180.0, 180.0)
		obstacle.phase_degrees = wrapf(
			obstacle.phase_degrees + rng.randf_range(-18.0, 18.0) * scale,
			-180.0, 180.0)
	_vary_wall(level.left_wall_segments, rng, scale)
	_vary_wall(level.right_wall_segments, rng, scale)
	if scale >= MAX_VARIATION_SCALE and profile != null:
		# Son kademe, AI'nin ayni fizik kusurunu tasiyan yakin kopyalarina
		# takilmak yerine zorluk icin kalibre edilmis hedef bandini tarar.
		level.target_position = Vector2(
			rng.randf_range(145.0, 575.0),
			rng.randf_range(profile.target_y_range.x, profile.target_y_range.y))
	_repair_anchor_clearance(level, variation_seed + 48611)
	return level


func _build_ricochet_rescue_level(source: LevelData,
		rng: RandomNumberGenerator) -> LevelData:
	var seeds := [
		{
			"target": Vector2(111.5912, 237.2848),
			"panels": [
				[Vector2(557.6433, 538.7047), -31.2, 308.9],
				[Vector2(309.9937, 791.0869), -17.2, 299.9],
			],
		},
		{
			"target": Vector2(597.2757, 398.7138),
			"panels": [
				[Vector2(258.1210, 725.6567), 19.2, 255.9],
				[Vector2(534.3357, 538.9850), 32.6, 326.3],
			],
		},
		{
			"target": Vector2(491.1871, 483.0049),
			"panels": [
				[Vector2(486.3035, 854.7031), 6.7, 254.2],
				[Vector2(145.9453, 694.3622), -3.0, 255.7],
			],
		},
		{
			"target": Vector2(371.0254, 471.0891),
			"panels": [
				[Vector2(242.1640, 846.6019), -3.4, 265.8],
				[Vector2(527.7546, 743.9351), 41.2, 255.4],
			],
		},
	]
	var layout_seed: Dictionary = seeds[rng.randi_range(0, seeds.size() - 1)]
	var level := LevelData.new()
	level.launcher_position = Vector2(360.0, 1120.0)
	var base_target: Vector2 = layout_seed["target"]
	level.target_position = Vector2(
		clampf(base_target.x + rng.randf_range(-24.0, 24.0), 90.0, 630.0),
		clampf(base_target.y + rng.randf_range(-16.0, 16.0), 190.0, 520.0))
	var panels: Array[PanelData] = []
	for definition in layout_seed["panels"]:
		var panel := PanelData.new()
		var base_position: Vector2 = definition[0]
		panel.position = Vector2(
			clampf(base_position.x + rng.randf_range(-18.0, 18.0), 100.0, 620.0),
			clampf(base_position.y + rng.randf_range(-14.0, 14.0), 440.0, 940.0))
		panel.rotation_degrees = clampf(
			float(definition[1]) + rng.randf_range(-2.5, 2.5), -55.0, 55.0)
		panel.length = clampf(
			float(definition[2]) + rng.randf_range(-16.0, 16.0), 220.0, 360.0)
		panel.thickness = 26.0
		panels.append(panel)
	level.panels = panels
	_copy_generated_identity(level, source)
	if rng.randf() < 0.5:
		_mirror_level(level)
	return level


func _build_block_corridor_rescue_level(source: LevelData,
		rng: RandomNumberGenerator) -> LevelData:
	var level := LevelLibrary.load_level(26).duplicate(true) as LevelData
	_copy_generated_identity(level, source)
	level.max_lives = maxi(source.max_lives, 3)
	var lower_gate := BreakableBlockData.new()
	lower_gate.position = Vector2(
		360.0 + rng.randf_range(-24.0, 24.0), rng.randf_range(750.0, 820.0))
	lower_gate.size = Vector2(rng.randf_range(480.0, 580.0), 46.0)
	level.breakable_blocks.append(lower_gate)
	var x_shift := rng.randf_range(-28.0, 28.0)
	level.launcher_position.x += x_shift
	level.target_position = Vector2(
		clampf(level.target_position.x + x_shift + rng.randf_range(-16.0, 16.0), 120.0, 600.0),
		clampf(level.target_position.y + rng.randf_range(-10.0, 10.0), 210.0, 420.0))
	for block in level.breakable_blocks:
		block.position.x = clampf(
			block.position.x + x_shift + rng.randf_range(-12.0, 12.0), 80.0, 640.0)
		block.position.y = clampf(
			block.position.y + rng.randf_range(-14.0, 14.0), 400.0, 940.0)
		block.size.x = clampf(
			block.size.x + rng.randf_range(-24.0, 24.0), 140.0, 600.0)
	if rng.randf() < 0.5:
		_mirror_level(level)
	return level


func _copy_generated_identity(level: LevelData, source: LevelData) -> void:
	level.level_id = source.level_id
	level.display_name = source.display_name
	level.max_lives = source.max_lives
	level.tutorial_text = source.tutorial_text
	level.two_star_max_seconds = source.two_star_max_seconds
	level.two_star_max_shots = source.two_star_max_shots
	level.three_star_max_seconds = source.three_star_max_seconds
	level.three_star_max_shots = source.three_star_max_shots


func _mirror_level(level: LevelData) -> void:
	level.launcher_position.x = 720.0 - level.launcher_position.x
	level.target_position.x = 720.0 - level.target_position.x
	for panel in level.panels:
		panel.position.x = 720.0 - panel.position.x
		panel.rotation_degrees = -panel.rotation_degrees
	for block in level.breakable_blocks:
		block.position.x = 720.0 - block.position.x
		block.rotation_degrees = -block.rotation_degrees
	for obstacle in level.obstacles:
		obstacle.position.x = 720.0 - obstacle.position.x
		obstacle.rotation_degrees = -obstacle.rotation_degrees
		obstacle.motion_direction_degrees = wrapf(
			180.0 - obstacle.motion_direction_degrees, -180.0, 180.0)
		obstacle.angular_speed_degrees = -obstacle.angular_speed_degrees
	var left_segments := level.left_wall_segments.duplicate()
	level.left_wall_segments = level.right_wall_segments.duplicate()
	level.right_wall_segments = left_segments


## Zor kurtarma iskeletleri. RESMI BOLUM KOPYASI DEGIL, bilerek: hard profili
## 2+ sekme isteyince kopyalanabilecek tek resmi bloksuz bolum 14 kaliyordu
## (1-13 tek sekmeli, 15-24'un klasik saglam hucresi 0, 25 tek hucreli) ve tek
## kaynaktan turetilen her kurtarma novelty tarafindan "resmi bolum kopyasi"
## diye eleniyordu. Bu yuzden geometriler ricochet kurtarmasindaki gibi
## sabittir; hepsi yerel uretecin hard profilinden HASAT EDILIP ayni solver
## taramasindan gecirilmistir (3 derece/100 guc; olculen sekme/saglam hucre
## degerleri yorumlarda).
const HARD_RESCUE_SEEDS := [
	# 3 sekme, 5 saglam hucre
	{"target": Vector2(323.6, 265.8),
		"panels": [[Vector2(492.6, 680.9), 10.2, 339.5], [Vector2(231.8, 919.0), 32.6, 293.1]]},
	# 2 sekme, 13 saglam hucre - en genis pencere, jitter payi en yuksek
	{"target": Vector2(354.2, 296.7),
		"panels": [[Vector2(378.7, 687.1), -51.6, 290.4], [Vector2(531.4, 891.6), -32.3, 323.7],
			[Vector2(157.4, 484.2), -31.4, 286.9]]},
	# 2 sekme, 8 saglam hucre
	{"target": Vector2(233.0, 350.7),
		"panels": [[Vector2(242.2, 743.4), -12.3, 255.6], [Vector2(386.0, 464.3), -51.9, 234.0],
			[Vector2(353.1, 730.9), -33.6, 242.0]]},
	# 2 sekme, 4 saglam hucre
	{"target": Vector2(486.2, 397.4),
		"panels": [[Vector2(262.8, 748.4), -37.4, 261.0], [Vector2(559.6, 466.9), -45.2, 271.6],
			[Vector2(467.4, 884.8), 44.1, 315.5]]},
]

## NEDEN BLOKLU KURTARMA TOHUMU YOK: bloklu geometri 2+ sekmede yapisal
## olarak kirilgandir. Hasat edilmis bloklu iskeletler (olculen: 4/3/2/2 sekme,
## 3-4 saglam hucre) kurtarmanin aynalama+kaydirmasindan sonra olculdugunde
## ikisi saglam hucreyi tamamen kaybediyor, ikisi de TEK SEKMEYE dusuyordu:
## blok birkac piksel kayinca rotayi kapatmayi birakiyor ve kestirme aciliyor.
## Blok jitter'ini yarilamak da bu sonucu degistirmedi.
##
## Kurtarma zaten son care: yalnizca en yuksek varyasyon kademesinde, orijinal
## geometri ve daha yumusak varyasyonlar elendikten sonra devreye girer. Orada
## secenek "bloksuz saglam bir zor bolum" ile "hic aday yok" arasindadir, bu
## yuzden blok birakilir. Zor profilinin zorlugu zaten sekme zincirinden gelir,
## bloktan degil; blok isteyen tasarim icin block_corridor sablonu var.


func _level_from_rescue_seed(seed_entry: Dictionary) -> LevelData:
	var level := LevelData.new()
	level.launcher_position = Vector2(360.0, 1120.0)
	level.target_position = seed_entry["target"]

	var panels: Array[PanelData] = []
	for raw in (seed_entry["panels"] as Array):
		var spec: Array = raw
		var panel := PanelData.new()
		panel.position = spec[0]
		panel.rotation_degrees = float(spec[1])
		panel.length = float(spec[2])
		panel.thickness = 26.0
		panels.append(panel)
	level.panels = panels

	var blocks: Array[BreakableBlockData] = []
	for raw in (seed_entry.get("blocks", []) as Array):
		var spec: Array = raw
		var block := BreakableBlockData.new()
		block.position = spec[0]
		block.size = Vector2(float(spec[1]), 44.0)
		blocks.append(block)
	level.breakable_blocks = blocks
	return level


func _build_hard_rescue_level(source: LevelData,
		rng: RandomNumberGenerator) -> LevelData:
	# Kaynakta blok olsa da kurtarma bloksuz iskelet uretir (bkz. yukaridaki not).
	var seed_entry: Dictionary = HARD_RESCUE_SEEDS[
		rng.randi_range(0, HARD_RESCUE_SEEDS.size() - 1)]
	var level := _level_from_rescue_seed(seed_entry)

	# Kaynak taslagin urun kimligi korunur; yalnizca son kademe geometrisi
	# solver'dan gecen bir fizik iskeletinden turetilir.
	level.level_id = source.level_id
	level.display_name = source.display_name
	level.max_lives = source.max_lives
	level.tutorial_text = source.tutorial_text
	level.two_star_max_seconds = source.two_star_max_seconds
	level.two_star_max_shots = source.two_star_max_shots
	level.three_star_max_seconds = source.three_star_max_seconds
	level.three_star_max_shots = source.three_star_max_shots

	var mirrored := rng.randf() < 0.5
	if mirrored:
		level.target_position.x = 720.0 - level.target_position.x
		for panel in level.panels:
			panel.position.x = 720.0 - panel.position.x
			panel.rotation_degrees = -panel.rotation_degrees
		for block in level.breakable_blocks:
			block.position.x = 720.0 - block.position.x
		var left_segments := level.left_wall_segments.duplicate()
		level.left_wall_segments = level.right_wall_segments.duplicate()
		level.right_wall_segments = left_segments

	var shift_direction := -1.0 if rng.randf() < 0.5 else 1.0
	var x_shift := shift_direction * rng.randf_range(8.0, 20.0)
	level.launcher_position.x = clampf(
		level.launcher_position.x + rng.randf_range(-8.0, 8.0), 330.0, 390.0)
	level.target_position = Vector2(
		clampf(level.target_position.x + x_shift + rng.randf_range(-10.0, 10.0), 120.0, 600.0),
		clampf(level.target_position.y + rng.randf_range(-8.0, 10.0), 210.0, 340.0))
	for panel in level.panels:
		panel.position = Vector2(
			clampf(panel.position.x + x_shift + rng.randf_range(-10.0, 10.0), 70.0, 650.0),
			clampf(panel.position.y + rng.randf_range(-10.0, 10.0), 360.0, 940.0))
		panel.rotation_degrees = clampf(
			panel.rotation_degrees + rng.randf_range(-2.0, 2.0), -80.0, 80.0)
		panel.length = clampf(panel.length + rng.randf_range(-12.0, 12.0), 180.0, 520.0)
	if level.panels.size() < 2:
		# Resmi iskeletin birebir kopyasi olmasin; ana cozumden uzaktaki kisa
		# ikinci yuzey alternatif denemeleri toplar ve cesitlilik puanina girer.
		var side := -1.0 if level.target_position.x >= 360.0 else 1.0
		var route_shaper := PanelData.new()
		route_shaper.position = Vector2(360.0 + side * rng.randf_range(205.0, 235.0),
			rng.randf_range(900.0, 960.0))
		route_shaper.rotation_degrees = side * rng.randf_range(16.0, 28.0)
		route_shaper.length = rng.randf_range(170.0, 205.0)
		route_shaper.thickness = 26.0
		level.panels.append(route_shaper)
	# Blok oynatmasi bilerek panelinkinden DAR. Eski tohumlar resmi 27-29
	# bolumleriydi ve genis pencereleri +-18/+-24'luk sapmayi tasiyabiliyordu;
	# yeni tohumlar profil esiginde dogrulanmis geometriler oldugu icin ayni
	# sapma onlari dogrudan "pencere-dar"a dusuruyor. Blok rotayi kapatan
	# eleman oldugundan en hassas parca da odur.
	for block in level.breakable_blocks:
		block.position = Vector2(
			clampf(block.position.x + x_shift * 0.5 + rng.randf_range(-8.0, 8.0), 80.0, 640.0),
			clampf(block.position.y + rng.randf_range(-8.0, 8.0), 400.0, 940.0))
		block.size.x = clampf(
			block.size.x + rng.randf_range(-12.0, 12.0), 120.0, 560.0)
	# Kurtarma iskeletleri artik resmi bolumlerden kopyalanmadigi icin kendi
	# duvar bosluklari yok; kaynak taslakta varsa onlari devralir ve oynatiriz.
	if source.left_wall_segments.size() == 2:
		level.left_wall_segments = source.left_wall_segments.duplicate()
		_vary_wall(level.left_wall_segments, rng, 0.35)
	if source.right_wall_segments.size() == 2:
		level.right_wall_segments = source.right_wall_segments.duplicate()
		_vary_wall(level.right_wall_segments, rng, 0.35)
	return level


func _vary_wall(segments: Array[Vector2], rng: RandomNumberGenerator, scale: float) -> void:
	if segments.size() != 2:
		return
	var top := clampf(
		segments[0].y + rng.randf_range(-40.0, 40.0) * scale, 120.0, 1064.0)
	var bottom := clampf(
		segments[1].x + rng.randf_range(-40.0, 40.0) * scale, top + 96.0, 1160.0)
	var upper := segments[0]
	var lower := segments[1]
	upper.y = top
	lower.x = bottom
	segments[0] = upper
	segments[1] = lower


func _repair_anchor_clearance(level: LevelData, repair_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = repair_seed
	var occupied: Array[Dictionary] = []
	for panel in level.panels:
		var size := Vector2(panel.length, panel.thickness)
		panel.position = _clear_obstacle_position(
			panel.position, size, panel.rotation_degrees, level, occupied,
			Rect2(130.0, 460.0, 460.0, 470.0), rng)
		occupied.append({"position": panel.position, "radius": panel.length * 0.32})
	for block in level.breakable_blocks:
		block.position = _clear_obstacle_position(
			block.position, block.size, block.rotation_degrees, level, occupied,
			Rect2(140.0, 420.0, 440.0, 480.0), rng)
		occupied.append({"position": block.position, "radius": block.size.x * 0.32})
	for obstacle in level.obstacles:
		var obstacle_size := obstacle.size
		if obstacle.kind != ObstacleData.Kind.MOVING_BAR:
			obstacle_size = Vector2.ONE * obstacle.size.x
		obstacle.position = _clear_obstacle_position(
			obstacle.position, obstacle_size, obstacle.rotation_degrees, level, occupied,
			Rect2(100.0, 300.0, 520.0, 650.0), rng)
		occupied.append({"position": obstacle.position, "radius": obstacle_size.length() * 0.32})


func _clear_obstacle_position(initial: Vector2, size: Vector2, rotation_degrees: float,
		level: LevelData, occupied: Array[Dictionary], bounds: Rect2,
		rng: RandomNumberGenerator) -> Vector2:
	if _obstacle_position_is_clear(
			initial, size, rotation_degrees, level, occupied):
		return initial
	for _attempt in 16:
		var candidate := Vector2(
			rng.randf_range(bounds.position.x, bounds.end.x),
			rng.randf_range(bounds.position.y, bounds.end.y))
		if _obstacle_position_is_clear(
				candidate, size, rotation_degrees, level, occupied):
			return candidate
	return initial


func _obstacle_position_is_clear(position: Vector2, size: Vector2,
		rotation_degrees: float, level: LevelData,
		occupied: Array[Dictionary]) -> bool:
	var spawn := (
		_solver.spawn_position(level.launcher_position)
		if _solver != null else level.launcher_position + Vector2.UP * 70.0)
	var target_radius := (_solver.target_size * 0.5 if _solver != null else 46.0)
	var ball_radius := (_solver.radius if _solver != null else 24.0)
	if _circle_overlaps_rotated_rect(
			level.target_position, target_radius + ANCHOR_CLEARANCE,
			position, size, rotation_degrees):
		return false
	if _circle_overlaps_rotated_rect(
			level.launcher_position, 60.0 + ANCHOR_CLEARANCE,
			position, size, rotation_degrees):
		return false
	if _circle_overlaps_rotated_rect(
			spawn, ball_radius + ANCHOR_CLEARANCE,
			position, size, rotation_degrees):
		return false
	var radius := maxf(size.x, size.y) * 0.32
	for other in occupied:
		var minimum_distance := minf(
			radius + float(other.get("radius", 0.0)) + 20.0, 180.0)
		var other_position: Vector2 = other.get("position", Vector2.ZERO)
		if position.distance_to(other_position) < minimum_distance:
			return false
	return true


func _circle_overlaps_rotated_rect(circle: Vector2, radius: float,
		rect_position: Vector2, rect_size: Vector2, rotation_degrees: float) -> bool:
	var local_circle := (circle - rect_position).rotated(-deg_to_rad(rotation_degrees))
	var half := rect_size * 0.5
	var nearest := Vector2(
		clampf(local_circle.x, -half.x, half.x),
		clampf(local_circle.y, -half.y, half.y))
	return local_circle.distance_squared_to(nearest) < radius * radius


# --- Degerlendirme ------------------------------------------------------------

func _evaluate(level: LevelData, profile: Profile) -> Dictionary:
	var play_rect := _world.get_play_rect()
	var spawn := _solver.spawn_position(level.launcher_position)
	var sims := 0

	# 0) Bedava statik kontroller - cogu kotu adayi hic simule etmeden eler.
	if not _static_geometry_ok(level, spawn):
		return _reject("yerlesim", 0)
	match profile.evaluation_mode:
		"ricochet_chain":
			return await _evaluate_ricochet(level, profile, play_rect, spawn)
		"block_corridor":
			return await _evaluate_block_corridor(level, profile, play_rect, spawn)

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
		var block_free_difficulty := LevelDifficultyScorer.evaluate(level, fine, analysis)
		if not _difficulty_score_matches(profile, block_free_difficulty):
			return _reject("skor-araligi", sims)
		return _standard_verdict(
			{
			"ok": true, "sims": sims, "robust": robust, "bounces": bounces,
			"opened_robust": robust, "block_free": true,
			"route_clusters": route_clusters,
			}, block_free_difficulty)

	var all_broken := _world.get_all_broken_state()
	var opened := await _solver.scan_async(spawn, level.target_position, play_rect,
		_world.rids_for_state(all_broken), FINE_ANGLE_STEP, FINE_POWER_STEP,
		SIMS_PER_FRAME, Callable(self, "_is_cancelled"))
	sims += int(opened["total"])
	if bool(opened.get("cancelled", false)):
		return _reject("iptal", sims)
	var opened_analysis := LevelSolver.analyse_robust(opened)
	var opened_robust := int(opened_analysis["robust"])
	if opened_robust <= robust:
		return _reject("blok-katkisiz", sims)
	var difficulty := LevelDifficultyScorer.evaluate(
		level, fine, analysis, opened, opened_analysis)
	if not _difficulty_score_matches(profile, difficulty):
		return _reject("skor-araligi", sims)

	return _standard_verdict({
		"ok": true, "sims": sims, "robust": robust, "bounces": bounces,
		"opened_robust": opened_robust, "block_free": robust > 0,
		"route_clusters": route_clusters,
	}, difficulty)


func _difficulty_score_matches(profile: Profile, difficulty: Dictionary) -> bool:
	if not profile.enforce_difficulty_score:
		return true
	var score := int(difficulty.get("score", 100))
	return score >= profile.min_difficulty_score and score <= profile.max_difficulty_score


func _standard_verdict(verdict: Dictionary, difficulty: Dictionary) -> Dictionary:
	verdict["difficulty_score"] = int(difficulty.get("score", 100))
	verdict["difficulty_label"] = String(difficulty.get("label", "COZUMSUZ"))
	verdict["difficulty_tier"] = int(difficulty.get("tier", 5))
	verdict["difficulty_breakdown"] = difficulty.get("breakdown", {}).duplicate(true)
	verdict["solution_count"] = int(difficulty.get("solution_count", 0))
	return verdict


func _apply_verdict_difficulty(level: LevelData, verdict: Dictionary) -> void:
	if verdict.has("difficulty_tier"):
		level.difficulty = clampi(int(verdict["difficulty_tier"]), 0, 5)


func _metadata_from_verdict(verdict: Dictionary) -> Dictionary:
	var metadata := {
		"robust_cells": int(verdict.get("robust", 0)),
		"bounce_count": int(verdict.get("bounces", 0)),
		"opened_robust": int(verdict.get("opened_robust", 0)),
	}
	if verdict.has("difficulty_score"):
		metadata["difficulty_score"] = int(verdict["difficulty_score"])
		metadata["difficulty_label"] = String(verdict.get("difficulty_label", ""))
		metadata["difficulty_breakdown"] = (
			verdict.get("difficulty_breakdown", {}).duplicate(true))
		metadata["solution_count"] = int(verdict.get("solution_count", 0))
	return metadata


func _evaluate_ricochet(_level: LevelData, profile: Profile,
		play_rect: Rect2, spawn: Vector2) -> Dictionary:
	var fine := await _solver.scan_async(
		spawn, _level.target_position, play_rect, [], FINE_ANGLE_STEP,
		FINE_POWER_STEP, SIMS_PER_FRAME, Callable(self, "_is_cancelled"))
	var sims := int(fine["total"])
	if bool(fine.get("cancelled", false)):
		return _reject("iptal", sims)
	var band := LevelSolver.analyse_bounce_band(
		fine, profile.min_bounces, profile.max_bounces)
	var robust := int(band["largest_cluster"])
	if robust < profile.min_robust:
		return _reject("zincir-yok", sims)
	if robust > profile.max_robust:
		return _reject("pencere-genis", sims)
	var ordinary := LevelSolver.analyse_robust(fine)
	# Tek bir saglam kisa-yol hucresi, ozellikle guc izgarasinin sinirinda,
	# oyuncuya tekrar edilebilir bir kestirme sunmaz. En az iki saglam hucre
	# uzun sekme zincirini gecersiz kilacak bir pencereyi kanitlar.
	if (int(ordinary["robust"]) >= 2
			and int(ordinary["bounces"]) < profile.min_bounces):
		return _reject("kisa-yol", sims)
	var clusters: Array = band["clusters"]
	var best: Dictionary = clusters[0]
	return {
		"ok": true, "sims": sims, "robust": robust,
		"bounces": int(best["bounces"]), "opened_robust": robust,
		"block_free": _level.breakable_blocks.is_empty(),
		"route_clusters": clusters.size(),
		"shortcut_robust": int(ordinary["robust"]),
	}


func _evaluate_block_corridor(level: LevelData, profile: Profile,
		play_rect: Rect2, spawn: Vector2) -> Dictionary:
	if level.breakable_blocks.size() < 2:
		return _reject("blok-yok", 0)
	var max_shots := mini(profile.max_solution_shots, maxi(level.max_lives, 1))
	if max_shots < profile.min_solution_shots:
		return _reject("hak-yetersiz", 0)
	var search := await _solver.search_block_states_async(
		spawn, level.target_position, play_rect, max_shots,
		FINE_ANGLE_STEP, FINE_POWER_STEP, 32, SIMS_PER_FRAME,
		Callable(self, "_is_cancelled"))
	var sims := int(search["sims"])
	if bool(search.get("cancelled", false)):
		return _reject("iptal", sims)
	var best: Dictionary = {}
	for solution in search["solutions"]:
		var solution_analysis: Dictionary = solution["analysis"]
		var solution_robust := int(solution_analysis["robust"])
		var shots := int(solution["shots"])
		var state := int(solution["state"])
		if state == 0 and solution_robust >= profile.min_robust:
			return _reject("blok-kestirmesi", sims)
		if (state == 0 or shots < profile.min_solution_shots
				or shots > profile.max_solution_shots
				or solution_robust < profile.min_robust
				or solution_robust > profile.max_robust):
			continue
		if (best.is_empty() or solution_robust > int(best["analysis"]["robust"])
				or (solution_robust == int(best["analysis"]["robust"])
					and shots < int(best["shots"]))):
			best = solution
	if best.is_empty():
		return _reject("blok-koridoru", sims)
	var analysis: Dictionary = best["analysis"]
	var scan: Dictionary = best["scan"]
	var robust := int(analysis["robust"])
	return {
		"ok": true, "sims": sims, "robust": robust,
		"bounces": int(analysis["bounces"]), "opened_robust": robust,
		"block_free": false,
		"route_clusters": LevelSolver.analyse_solution_clusters(scan).size(),
		"solution_shots": int(best["shots"]),
		"broken_state": int(best["state"]),
		"states_visited": int(search["states_visited"]),
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
		_rng.randf_range(140.0, 580.0),
		_rng.randf_range(profile.target_y_range.x, profile.target_y_range.y))

	var panels: Array[PanelData] = []
	for i in _rng.randi_range(profile.panel_count.x, profile.panel_count.y):
		panels.append(_random_panel())
	level.panels = panels

	var blocks: Array[BreakableBlockData] = []
	for i in _rng.randi_range(profile.block_count.x, profile.block_count.y):
		blocks.append(_random_block())
	level.breakable_blocks = blocks

	var wall_count := _rng.randi_range(profile.wall_gap_count.x, profile.wall_gap_count.y)
	if wall_count > 0:
		var first_on_left := _rng.randf() < 0.5
		if first_on_left:
			level.left_wall_segments = _random_wall_gap()
		else:
			level.right_wall_segments = _random_wall_gap()
		if wall_count > 1:
			if first_on_left:
				level.right_wall_segments = _random_wall_gap()
			else:
				level.left_wall_segments = _random_wall_gap()

	var obstacles: Array[ObstacleData] = []
	if not profile.obstacle_kinds.is_empty():
		var wanted_obstacles := _rng.randi_range(
			profile.obstacle_count.x, profile.obstacle_count.y)
		if profile.include_each_obstacle_kind:
			for kind in profile.obstacle_kinds:
				var single_kind: Array[int] = [kind]
				obstacles.append(_random_obstacle(single_kind))
		while obstacles.size() < wanted_obstacles:
			obstacles.append(_random_obstacle(profile.obstacle_kinds))
	level.obstacles = obstacles

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


func _random_wall_gap() -> Array[Vector2]:
	var top := _rng.randf_range(360.0, 700.0)
	var bottom := _rng.randf_range(top + 180.0, minf(top + 420.0, 1080.0))
	return [Vector2(-320.0, top), Vector2(bottom, 1440.0)]


func _random_obstacle(kinds: Array[int]) -> ObstacleData:
	var obstacle := ObstacleData.new()
	obstacle.kind = kinds[_rng.randi_range(0, kinds.size() - 1)] as ObstacleData.Kind
	obstacle.position = Vector2(
		_rng.randf_range(130.0, 590.0), _rng.randf_range(360.0, 920.0))
	obstacle.rotation_degrees = _rng.randf_range(-55.0, 55.0)
	match obstacle.kind:
		ObstacleData.Kind.METAL_RING:
			obstacle.size = Vector2(_rng.randf_range(120.0, 200.0), 28.0)
			obstacle.inner_radius = clampf(
				_rng.randf_range(34.0, 58.0), 28.0, obstacle.outer_radius() - 12.0)
		ObstacleData.Kind.BOMB:
			obstacle.size = Vector2.ONE * _rng.randf_range(56.0, 88.0)
		ObstacleData.Kind.ROTATING_WHEEL:
			obstacle.size = Vector2(_rng.randf_range(110.0, 190.0), _rng.randf_range(18.0, 30.0))
			obstacle.spoke_count = _rng.randi_range(4, 7)
			obstacle.angular_speed_degrees = _rng.randf_range(35.0, 90.0) * (
				-1.0 if _rng.randf() < 0.5 else 1.0)
		ObstacleData.Kind.MOVING_BAR:
			obstacle.size = Vector2(_rng.randf_range(130.0, 240.0), _rng.randf_range(28.0, 44.0))
			obstacle.motion_direction_degrees = _rng.randf_range(-90.0, 90.0)
			obstacle.travel_distance = _rng.randf_range(60.0, 150.0)
			obstacle.motion_period = _rng.randf_range(2.2, 4.2)
			obstacle.phase_degrees = _rng.randf_range(-90.0, 90.0)
		ObstacleData.Kind.PULSE_LASER:
			obstacle.size = Vector2(
				_rng.randf_range(140.0, 300.0), _rng.randf_range(10.0, 22.0))
			obstacle.motion_period = _rng.randf_range(1.8, 4.2)
			obstacle.phase_degrees = _rng.randf_range(-180.0, 180.0)
			obstacle.pulse_on_ratio = _rng.randf_range(0.35, 0.72)
	return obstacle
