extends SceneTree

## GELISTIRME ARACI - oyuna dahil degildir.
##
## 51-125 bandini YENIDEN URETIR ve her bolumu yazmadan once gercek
## LevelSolver ile dogrular.
##
## NEDEN VAR: bu bant daha once iki panel sablonunun (ve aynasinin) tekrariyla
## uretilmisti; find_duplicate_levels.py 57 bolumun ayni iskeleti paylastigini
## gosterdi. Burada her bolume KUTUPHANEDEN farkli bir iskelet atanir ve
## engeller o iskelete gore ARANIR - sabit "slot" tablosu yoktur, cunku sabit
## slotlar tam da tekrari ureten seydi.
##
## TASARIM ILKESI (LevelGenerator ile ayni): bu arac tasarim YAPMAZ, ARAMA
## yapar. Engel yerlesimi rastgele denenir, ayni fizik ELER. Kabul olcutu
## verifier'inkiyle uyumludur, boylece "uretecte gecti ama verifier'da kaldi"
## durumu olusmaz.
##
## Kullanim:
##   godot --headless --path . --script res://tools/generate_band_51_125.gd
##   godot --headless --path . --script res://tools/generate_band_51_125.gd -- --from 51 --to 60

const RING := ObstacleData.Kind.METAL_RING
const BOMB := ObstacleData.Kind.BOMB
const WHEEL := ObstacleData.Kind.ROTATING_WHEEL
const BAR := ObstacleData.Kind.MOVING_BAR
const LASER := ObstacleData.Kind.PULSE_LASER

## Kabul bandi. Alt sinir verifier'in MIN_ROBUST_CELLS'i (6) ile ayni; ustu
## "zaten bedava" bolumleri eler.
const MIN_ROBUST := 6
const MAX_ROBUST := 44
const ANGLE_STEP := 3.0
const POWER_STEP := 100.0
## Engelin hedefe/firlaticiya/panele en yakin durabilecegi mesafe payi.
const CLEARANCE := 26.0

## eval_skeletons.gd ile ARANMIS ve her biri gercek LevelSolver ile dogrulanmis
## panel iskeletleri (hepsi >=1 sekme gerektirir, saglam hucre 16-88 bandinda).
## Elle yazilmadilar; yorumdaki olcumler icin bkz. eval_skeletons.gd ciktisi.
## Her giris ayrica x-aynasiyla kullanilir -> 64 varyant.
const SKELETONS := [
	{"target": Vector2(576, 419), "panels": [[Vector2(476, 855), -28.8, 371]]},
	{"target": Vector2(203, 376), "panels": [[Vector2(438, 810), 2.8, 376]]},
	{"target": Vector2(279, 236), "panels": [[Vector2(166, 477), 41.7, 325], [Vector2(303, 817), -50.3, 270], [Vector2(201, 668), 29.6, 392]]},
	{"target": Vector2(510, 256), "panels": [[Vector2(364, 610), 29.1, 304], [Vector2(548, 621), -28.8, 250], [Vector2(418, 606), -39.3, 304]]},
	{"target": Vector2(324, 456), "panels": [[Vector2(549, 563), 23.3, 350], [Vector2(431, 519), 33.6, 292], [Vector2(318, 705), 36.5, 342]]},
	{"target": Vector2(273, 330), "panels": [[Vector2(372, 812), -30.7, 245], [Vector2(229, 523), -6.9, 369]]},
	{"target": Vector2(237, 339), "panels": [[Vector2(188, 602), -39.3, 339], [Vector2(376, 567), 2.8, 252], [Vector2(221, 851), 38.4, 266]]},
	{"target": Vector2(398, 310), "panels": [[Vector2(505, 612), 18.5, 403]]},
	{"target": Vector2(412, 355), "panels": [[Vector2(327, 820), 26.7, 286]]},
	{"target": Vector2(296, 255), "panels": [[Vector2(304, 701), -26.0, 400], [Vector2(170, 941), 21.3, 327]]},
	{"target": Vector2(296, 275), "panels": [[Vector2(558, 546), -5.3, 322], [Vector2(474, 750), -2.9, 351], [Vector2(410, 657), 25.2, 244]]},
	{"target": Vector2(393, 276), "panels": [[Vector2(447, 820), 3.8, 271]]},
	{"target": Vector2(241, 409), "panels": [[Vector2(193, 853), -11.9, 311]]},
	{"target": Vector2(148, 370), "panels": [[Vector2(287, 799), 37.3, 354], [Vector2(483, 921), 7.9, 352]]},
	{"target": Vector2(371, 374), "panels": [[Vector2(280, 512), -22.8, 404]]},
	{"target": Vector2(517, 264), "panels": [[Vector2(402, 651), -32.2, 313], [Vector2(294, 663), 1.5, 370]]},
	{"target": Vector2(178, 445), "panels": [[Vector2(181, 504), 14.2, 412]]},
	{"target": Vector2(518, 421), "panels": [[Vector2(440, 557), -40.7, 401], [Vector2(439, 769), -34.0, 344], [Vector2(451, 812), 44.7, 408]]},
	{"target": Vector2(285, 404), "panels": [[Vector2(567, 707), -42.6, 349], [Vector2(276, 596), 36.7, 339]]},
	{"target": Vector2(229, 233), "panels": [[Vector2(351, 660), 43.0, 327]]},
	{"target": Vector2(370, 238), "panels": [[Vector2(489, 689), -17.7, 259], [Vector2(462, 492), 6.4, 413]]},
	{"target": Vector2(412, 446), "panels": [[Vector2(222, 505), 31.7, 330], [Vector2(386, 779), 49.0, 322], [Vector2(220, 569), -40.2, 395]]},
	{"target": Vector2(432, 394), "panels": [[Vector2(300, 662), 24.7, 403]]},
	{"target": Vector2(450, 389), "panels": [[Vector2(516, 533), -26.4, 326], [Vector2(481, 501), 22.8, 399], [Vector2(372, 723), 29.1, 318]]},
	{"target": Vector2(368, 355), "panels": [[Vector2(332, 684), -49.1, 269], [Vector2(326, 879), -42.0, 294]]},
	{"target": Vector2(299, 443), "panels": [[Vector2(313, 624), 1.9, 291], [Vector2(304, 737), 18.9, 241], [Vector2(191, 897), 7.9, 264]]},
	{"target": Vector2(574, 325), "panels": [[Vector2(213, 542), -41.7, 342], [Vector2(368, 521), 50.6, 318]]},
	{"target": Vector2(559, 302), "panels": [[Vector2(376, 543), 15.2, 322]]},
	{"target": Vector2(576, 432), "panels": [[Vector2(481, 638), 1.1, 245], [Vector2(308, 761), 43.2, 273]]},
	{"target": Vector2(153, 393), "panels": [[Vector2(351, 736), 12.9, 359]]},
	{"target": Vector2(512, 235), "panels": [[Vector2(565, 601), 26.8, 309]]},
	{"target": Vector2(363, 315), "panels": [[Vector2(334, 550), -38.1, 250], [Vector2(275, 651), 15.9, 279], [Vector2(176, 665), -19.3, 329]]},
	{"target": Vector2(454, 370), "panels": [[Vector2(432, 601), -47.4, 275], [Vector2(175, 617), 11.7, 267]]},
	{"target": Vector2(576, 257), "panels": [[Vector2(404, 679), -51.6, 367]]},
	{"target": Vector2(299, 269), "panels": [[Vector2(250, 576), 41.6, 360]]},
	{"target": Vector2(170, 291), "panels": [[Vector2(207, 525), -51.1, 255]]},
	{"target": Vector2(469, 276), "panels": [[Vector2(255, 483), -2.0, 399]]},
	{"target": Vector2(570, 381), "panels": [[Vector2(472, 637), 24.0, 404]]},
	{"target": Vector2(214, 327), "panels": [[Vector2(236, 522), 31.1, 272], [Vector2(185, 668), 23.7, 311]]},
	{"target": Vector2(422, 267), "panels": [[Vector2(206, 812), 23.6, 384]]},
	{"target": Vector2(530, 448), "panels": [[Vector2(566, 787), 20.2, 332]]},
	{"target": Vector2(347, 394), "panels": [[Vector2(494, 782), -15.9, 357]]},
]

## Iskelet cesitlemesi. Bkz. _jitter_skeleton: yalnizca --distinct modunda
## uygulanir, cunku normal uretim BIRE BIR atamayla zaten farkli iskelet verir.
const JITTER_PANEL_MIN := 26.0
const JITTER_PANEL_MAX := 54.0
const JITTER_ANGLE := 7.0
const JITTER_TARGET := 34.0

var _skeletons: Array[Dictionary] = []
var _from := 51
var _to := 125
## Yalnizca bu bolumler uretilir (--only). Bos ise _from.._to araligi kullanilir.
var _only: Array[int] = []
## --distinct: iskelet her denemede kucuk bir sapmayla kullanilir, boylece
## uretilen bolum kutuphanedeki HICBIR bolumle ayni iskeleti paylasmaz.
var _distinct := false
var _solver: LevelSolver
var _world: LevelWorld
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--from" and i + 1 < args.size():
			_from = int(args[i + 1])
		elif args[i] == "--to" and i + 1 < args.size():
			_to = int(args[i + 1])
		elif args[i] == "--only" and i + 1 < args.size():
			for piece in args[i + 1].split(",", false):
				var clean := piece.strip_edges()
				if clean.is_valid_int():
					_only.append(int(clean))
		elif args[i] == "--distinct":
			_distinct = true
	_run.call_deferred()


func _run() -> void:
	await physics_frame
	_solver = LevelSolver.from_scenes()
	_skeletons.assign(SKELETONS)
	print("iskelet kutuphanesi: %d giris (aynalarla %d varyant)" % [
		_skeletons.size(), _skeletons.size() * 2])

	var wanted: Array[int] = _only.duplicate()
	if wanted.is_empty():
		for level_id in range(_from, _to + 1):
			wanted.append(level_id)
	if _distinct:
		print("--distinct: iskeletler sapmayla kullanilacak (tekrar kirma modu)")

	var ok := 0
	var failed: Array[int] = []
	for level_id in wanted:
		if await _build_level(level_id):
			ok += 1
		else:
			failed.append(level_id)

	print("")
	print("OZET uretildi=%d basarisiz=%d" % [ok, failed.size()])
	if not failed.is_empty():
		print("basarisiz bolumler: %s" % str(failed))
	quit(0 if failed.is_empty() else 1)


## Bir bolumu uretir. Atanan iskelet tutmazsa SIRAYLA BASKA ISKELETLERE gecer.
##
## Neden: her iskeletin kendi "bosluk butcesi" var. Dar bir iskelete (or.
## kutuphanenin en dar girisi, saglam=16) uc engel sigdirmak imkansiz olabilir;
## tek iskelete kilitlenip 240 kez denemek hem dakikalar suruyor hem de bolumu
## bos birakiyordu. Alternatif iskelete gecmek bunu hem hizlandirir hem kurtarir.
func _build_level(level_id: int) -> bool:
	var spec := _spec_for(level_id)
	# Her bolum icin sabit tohum: ayni girdi ayni bolumu uretir (determinizm).
	_rng.seed = 770000 + level_id * 7919

	# Kademeli GEVSEME: her tur once iskelet degisir, iki turda bir de engel
	# sayisi bir azalir. Sebep, olculen davranis: dar bir iskelete dort engel
	# sigdirmak cogu zaman imkansiz ve arama bunu ancak yuzlerce denemeden
	# sonra "anliyor". Bir engel eksiltmek bolumu kurtarir; bos birakmaktan
	# ya da dakikalarca aramaktan iyidir. En az bir engel her zaman kalir.
	for choice in 6:
		var skeleton := _skeleton_for(level_id, choice)
		var relaxed := spec.duplicate(true)
		var drop := choice / 2
		var kinds: Array = (spec["kinds"] as Array).duplicate()
		while drop > 0 and kinds.size() > 1:
			kinds.pop_back()
			drop -= 1
		relaxed["kinds"] = kinds
		for attempt in 60:
			var shaped := _jitter_skeleton(skeleton) if _distinct else skeleton
			var level := _level_from_skeleton(shaped, level_id, relaxed)
			if not _place_obstacles(level, relaxed, shaped):
				continue
			if int(relaxed["bricks"]) > 0:
				_place_bricks(level, relaxed, shaped)
			if not level.validate().is_empty():
				continue

			var verdict := await _evaluate(level)
			if not bool(verdict["ok"]):
				continue

			_apply_identity(level, level_id, relaxed)
			var error := ResourceSaver.save(level, "res://levels/level_%d.tres" % level_id)
			if error != OK:
				push_error("kayit hatasi level %d: %d" % [level_id, error])
				return false
			print("LEVEL %3d ok  iskelet=%-2d%s engel=%d tugla=%d saglam=%d sekme=%d" % [
				level_id, int(skeleton["index"]),
				"A" if bool(skeleton["mirrored"]) else " ",
				level.obstacles.size(), level.breakable_blocks.size(),
				int(verdict["robust"]), int(verdict["bounces"])])
			return true

	print("LEVEL %3d BASARISIZ - 6 iskelet x 60 deneme yetmedi" % level_id)
	return false


## Iskeleti bolume atar. Ayna varyanti kutuphaneyi iki katina cikarir; carpim
## adimlari (7 ve 11) ardisik bolumlerin ayni iskeleti almasini engeller.
## [param choice] 0 ilk tercihtir; tutmazsa cagiran artirarak baska iskelet
## ister (bkz. _build_level).
func _skeleton_for(level_id: int, choice: int = 0) -> Dictionary:
	var count := _skeletons.size()
	# BIRE BIR ATAMA: kutuphane 42 iskelet x 2 ayna = 84 varyant sunar, bant ise
	# 75 bolum. 17 ile carpim (obek(17, 84) = 1) 0..83 uzerinde bir permutasyon
	# uretir, dolayisiyla ilk 75 deger BIRBIRINDEN FARKLIDIR - hicbir iki bolum
	# ayni iskeleti paylasmaz. Onceki "(level_id * 7) % count" formulu bunu
	# garanti etmiyordu ve 44 bolum ikiser ikiser eslesiyordu
	# (bkz. find_duplicate_levels.py raporu).
	var variants := count * 2
	var variant := ((level_id - 51) * 17 + choice * 29) % variants
	var index := variant % count
	var mirrored := variant >= count
	var source: Dictionary = _skeletons[index]
	var target: Vector2 = source["target"]
	var panels: Array = []
	for raw in (source["panels"] as Array):
		var spec: Array = raw
		var position: Vector2 = spec[0]
		if mirrored:
			panels.append([Vector2(720.0 - position.x, position.y),
				-float(spec[1]), float(spec[2])])
		else:
			panels.append([position, float(spec[1]), float(spec[2])])
	return {
		"index": index,
		"mirrored": mirrored,
		"target": Vector2(720.0 - target.x, target.y) if mirrored else target,
		"panels": panels,
	}


## Iskeleti kucuk ama GORULEBILIR bir sapmayla cesitler (--distinct modu).
##
## NEDEN VAR: bire bir atama yalnizca ILK tercih tuttugunda tekrarsizligi
## garanti eder. Iskelet dar geldiginde _build_level bir sonraki tercihe
## geciyor ve o tercih baska bir bolumun ilk tercihiyle ayni varyanta
## dusebiliyor - find_duplicate_levels.py'nin "ayni iskelet" gruplari tam
## olarak bunlardi. Sapma, ayni varyanti kullanan iki bolumu yine de farkli
## kilar; ayrica 51-125 bandinin bir bolumu elle yazilmis 1-50 bandindaki bir
## bolumle ayni panel yerlesimine sahip oldugunda da ayni ise yarar.
##
## Sapma _rng'den cekilir, yani her deneme farkli bir sapma dener ve tumu
## bolum tohumundan turedigi icin calisma yine TEKRARLANABILIRDIR. Kotu bir
## sapma zaten validate()/solver elemesinden gecemez; bir sonraki deneme
## baskasini dener. Kaydirma yonu isaretce rastgele, buyuklugu ise en az
## JITTER_PANEL_MIN'dir - "1 piksel oynattim, artik farkli" sahte cozumunu
## engellemek icin.
func _jitter_skeleton(skeleton: Dictionary) -> Dictionary:
	var target: Vector2 = skeleton["target"]
	var moved_target := Vector2(
		clampf(target.x + _rng.randf_range(-JITTER_TARGET, JITTER_TARGET), 120.0, 600.0),
		clampf(target.y + _rng.randf_range(-JITTER_TARGET, JITTER_TARGET), 220.0, 470.0))

	var panels: Array = []
	for raw in (skeleton["panels"] as Array):
		var spec: Array = raw
		var position: Vector2 = spec[0]
		panels.append([
			Vector2(
				clampf(position.x + _signed_jitter(), 140.0, 580.0),
				clampf(position.y + _signed_jitter(), 470.0, 960.0)),
			clampf(float(spec[1]) + _rng.randf_range(-JITTER_ANGLE, JITTER_ANGLE), -55.0, 55.0),
			float(spec[2]),
		])

	return {
		"index": skeleton["index"],
		"mirrored": skeleton["mirrored"],
		"target": moved_target,
		"panels": panels,
	}


## En az JITTER_PANEL_MIN, en cok JITTER_PANEL_MAX buyuklugunde; yonu rastgele.
func _signed_jitter() -> float:
	var amount := _rng.randf_range(JITTER_PANEL_MIN, JITTER_PANEL_MAX)
	return amount if _rng.randf() < 0.5 else -amount


func _level_from_skeleton(skeleton: Dictionary, level_id: int,
		spec: Dictionary) -> LevelData:
	var level := LevelData.new()
	level.level_id = level_id
	level.launcher_position = Vector2(360.0, 1120.0)
	level.target_position = skeleton["target"]
	var panels: Array[PanelData] = []
	for raw in (skeleton["panels"] as Array):
		var panel_spec: Array = raw
		var panel := PanelData.new()
		panel.position = panel_spec[0]
		panel.rotation_degrees = float(panel_spec[1])
		panel.length = float(panel_spec[2])
		panel.thickness = 26.0
		panels.append(panel)
	level.panels = panels
	level.max_lives = 5
	return level


## Istenen TUM turler yerlestirilebildiyse true.
##
## Eskiden yer bulunamayan engel sessizce ATLANIYORDU ve cagiran bunu
## ogrenemiyordu; sonuc, spec'i iki engel diyen ama tek engelle kaydedilen
## bolumlerdi (or. 134 lazersiz kaldi ve bandin kimligini kirdi - test
## yakaladi). Engel sayisini AZALTMAK kasitli bir karardir ve gevseme
## merdiveninde yapilir (bkz. _build_level); tesadufen olmamali.
func _place_obstacles(level: LevelData, spec: Dictionary,
		skeleton: Dictionary) -> bool:
	var kinds: Array = spec["kinds"]
	var placed: Array[ObstacleData] = []
	for kind in kinds:
		var data := _make_obstacle(int(kind), float(spec["difficulty"]))
		var seated := false
		for _try in 40:
			data.position = Vector2(
				_rng.randf_range(110.0, 610.0), _rng.randf_range(330.0, 960.0))
			if _position_is_clear(data.position, _obstacle_radius(data), level, placed):
				placed.append(data)
				seated = true
				break
		if not seated:
			return false
	level.obstacles = placed
	return true


func _place_bricks(level: LevelData, spec: Dictionary,
		skeleton: Dictionary) -> void:
	var count := int(spec["bricks"])
	var strong := int(spec["strong_bricks"])
	var bricks: Array[BreakableBlockData] = []
	# Tuglalar tek bir sirada: dagitilmis tek tuglalar "kume" hissi vermiyor.
	var row_y := _rng.randf_range(430.0, 700.0)
	var brick_width := 104.0
	var gap := 30.0
	var total := count * brick_width + float(count - 1) * gap
	var left := _rng.randf_range(120.0, maxf(600.0 - total, 130.0))
	for i in count:
		var brick := BreakableBlockData.new()
		brick.position = Vector2(left + brick_width * 0.5 + float(i) * (brick_width + gap), row_y)
		brick.size = Vector2(brick_width, 34.0)
		brick.hit_points = 2 if i < strong else 1
		bricks.append(brick)
	level.breakable_blocks = bricks


func _obstacle_radius(data: ObstacleData) -> float:
	if data.kind == BAR:
		return data.size.length() * 0.5 + data.travel_distance
	if data.kind == LASER:
		# Isin uzun ve ince: yaricap olarak yarim boyu kullanmak onu bir daire
		# gibi ele alir ve gereginden cok yer ayirir, ama guvenli taraftadir.
		return data.size.x * 0.5
	return data.outer_radius()


## Engel; hedefi, firlaticiyi, topun dogdugu noktayi veya bir paneli
## kapatmamali - aksi halde bolum daha ilk karede cozulemez olur.
func _position_is_clear(position: Vector2, radius: float, level: LevelData,
		placed: Array[ObstacleData]) -> bool:
	var spawn := _solver.spawn_position(level.launcher_position)
	if position.distance_to(level.target_position) < radius + _solver.target_size * 0.5 + CLEARANCE:
		return false
	if position.distance_to(level.launcher_position) < radius + 70.0 + CLEARANCE:
		return false
	if position.distance_to(spawn) < radius + _solver.radius + CLEARANCE:
		return false
	for panel in level.panels:
		if _circle_hits_panel(position, radius + CLEARANCE, panel):
			return false
	for other in placed:
		if position.distance_to(other.position) < radius + _obstacle_radius(other) + 24.0:
			return false
	return true


func _circle_hits_panel(circle: Vector2, radius: float, panel: PanelData) -> bool:
	var local := (circle - panel.position).rotated(-deg_to_rad(panel.rotation_degrees))
	var half := Vector2(panel.length, panel.thickness) * 0.5
	var nearest := Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
	return local.distance_squared_to(nearest) < radius * radius


func _make_obstacle(kind: int, difficulty: float) -> ObstacleData:
	var data := ObstacleData.new()
	data.kind = kind as ObstacleData.Kind
	data.rotation_degrees = 0.0
	match kind:
		RING:
			data.size = Vector2(180.0, 28.0)
			data.inner_radius = lerpf(76.0, 58.0, difficulty)
			# Halkanin gecirgen deligi topun geldigi yone (asagi) baksin.
			data.rotation_degrees = 180.0
		BOMB:
			var radius := lerpf(30.0, 44.0, difficulty)
			data.size = Vector2(radius * 2.0, radius * 2.0)
		WHEEL:
			data.size = Vector2(120.0, 20.0)
			data.spoke_count = 5
			data.angular_speed_degrees = lerpf(45.0, 120.0, difficulty) \
				* (1.0 if _rng.randf() < 0.5 else -1.0)
		BAR:
			data.size = Vector2(130.0, 26.0)
			data.motion_direction_degrees = 0.0
			data.travel_distance = lerpf(70.0, 140.0, difficulty)
			data.motion_period = lerpf(3.2, 1.9, difficulty)
		LASER:
			# Isin YATAY: dikey bir isin firlaticidan cikan yolu boydan boya
			# kesmez, sadece bir seridi kapatir; zamanlama bulmacasi olmaz.
			data.size = Vector2(lerpf(200.0, 330.0, difficulty), 14.0)
			data.rotation_degrees = 0.0
			# Zorluk arttikca dongu KISALIR (pencere daralir) ama acik orani
			# 0.6'yi gecmez: surekli acik bir isin zamanlama degil duvardir.
			data.motion_period = lerpf(3.4, 2.2, difficulty)
			data.pulse_on_ratio = lerpf(0.45, 0.60, difficulty)
			# Ayni bolumdeki iki lazer sirayla yansin.
			data.phase_degrees = _rng.randf_range(0.0, 360.0)
	return data


## verify_levels.gd::_check_static_geometry ile AYNI kontroller, ayni cagriyla.
##
## NEDEN SONRADAN EKLENDI: _position_is_clear yalnizca ENGELIN panele/hedefe
## uzakligina bakiyordu; HEDEFIN panele gomulup gomulmedigini hicbir yerde
## kontrol etmiyordum. Sonuc, iskeletin kendisinden ya da --distinct
## sapmasindan gelen yedi bozuk bolumdu (52, 71, 72, 89, 94, 113, 114):
## hepsi rahat cozulebiliyordu ama hedef panelin govdesinin icindeydi.
func _static_geometry_ok(level: LevelData, spawn: Vector2) -> bool:
	if _solver.overlaps_obstacle(level.target_position, _solver.target_size * 0.5):
		return false
	if _solver.overlaps_obstacle(spawn, _solver.radius):
		return false
	if _solver.overlaps_obstacle(level.launcher_position, 60.0):
		return false
	return level.target_position.y - _solver.target_size * 0.5 >= 150.0


## Bloksuz bolumler tek atisla, bloklular cok atisli durum aramasiyla olculur -
## verifier ile ayni ayrim (bkz. verify_levels.gd).
func _evaluate(level: LevelData) -> Dictionary:
	_world = LevelWorld.new()
	root.add_child(_world)
	_world.build(level)
	_solver.bind_space(_world.get_space(), _world.get_block_rids(), _world.get_obstacles())
	await physics_frame
	await physics_frame

	var spawn := _solver.spawn_position(level.launcher_position)
	var play_rect := _world.get_play_rect()
	var result := {"ok": false, "robust": 0, "bounces": -1}

	if not _static_geometry_ok(level, spawn):
		# Statik yerlesim bozuksa tarama yapmanin anlami yok: bolum cozulebilir
		# olsa bile hedefi panelin govdesine gomulmus halde cikar.
		_world.queue_free()
		_world = null
		await process_frame
		return result

	if level.breakable_blocks.is_empty():
		var scan := _solver.scan(spawn, level.target_position, play_rect,
			[], ANGLE_STEP, POWER_STEP)
		var analysis := LevelSolver.analyse_robust(scan)
		var robust := int(analysis["robust"])
		var bounces := int(analysis["bounces"]) if int(scan["hit_count"]) > 0 else -1
		result["robust"] = robust
		result["bounces"] = bounces
		result["ok"] = robust >= MIN_ROBUST and robust <= MAX_ROBUST and bounces >= 1
	else:
		# Bloklu bolumde "kirmadan saglam kestirme" olmamali; kirilmis durumda
		# ise rahat bir rota bulunmali (26-40 bandiyla ayni sozlesme).
		var free_scan := _solver.scan(spawn, level.target_position, play_rect,
			[], ANGLE_STEP, POWER_STEP)
		var free_robust := int(LevelSolver.analyse_robust(free_scan)["robust"])
		var opened := _solver.scan(spawn, level.target_position, play_rect,
			_world.rids_for_state(_world.get_all_broken_state()), ANGLE_STEP, POWER_STEP)
		var opened_analysis := LevelSolver.analyse_robust(opened)
		var opened_robust := int(opened_analysis["robust"])
		result["robust"] = opened_robust
		result["bounces"] = int(opened_analysis["bounces"]) if int(opened["hit_count"]) > 0 else -1
		result["ok"] = (free_robust < MIN_ROBUST
			and opened_robust >= MIN_ROBUST and opened_robust <= MAX_ROBUST)

	_world.queue_free()
	_world = null
	await process_frame
	return result


func _apply_identity(level: LevelData, level_id: int, spec: Dictionary) -> void:
	level.display_name = String(spec["name"])
	level.max_lives = 5
	level.two_star_max_shots = 3
	level.three_star_max_shots = 2
	var t := clampf(float(level_id - 51) / 99.0, 0.0, 1.0)
	level.two_star_max_seconds = snappedf(lerpf(75.0, 160.0, t), 0.1)
	level.three_star_max_seconds = snappedf(lerpf(40.0, 85.0, t), 0.1)


## Bolum basina icerik plani: engel karisimi, zorluk ve (101+) tugla sayisi.
func _spec_for(level_id: int) -> Dictionary:
	var difficulty := clampf(float(level_id - 51) / 99.0, 0.0, 1.0)
	var name := "Faz %d" % level_id
	var kinds: Array = []
	var bricks := 0
	var strong := 0

	if level_id == 51:
		name = "Dönen Çark"
		kinds = [WHEEL]
	elif level_id == 56:
		name = "Kayan Bariyer"
		kinds = [BAR]
	elif level_id == 100:
		name = "Son Faz"
		kinds = [RING, BOMB, WHEEL, BAR]
	elif level_id == 126:
		# LAZERIN ILK GORULDUGU BOLUM: yalnizca lazer. Tanitim karti bir
		# bolumdeki YENI turleri gosterir; burada baska engel olsaydi oyuncu
		# ayni anda iki kural ogrenmek zorunda kalirdi.
		name = "Lazer Hattı"
		kinds = [LASER]
	elif level_id == 150:
		name = "Son Işık"
		kinds = [LASER, RING, WHEEL, LASER]
		bricks = 4
		strong = 3
	elif level_id == 125:
		name = "Final"
		kinds = [RING, BOMB, WHEEL, BAR]
		bricks = 4
		strong = 3
	elif level_id < 56:
		kinds = [WHEEL, [RING, BOMB][level_id % 2]]
	elif level_id < 60:
		kinds = [BAR, [RING, BOMB, WHEEL][level_id % 3]]
	elif level_id <= 100:
		# 60-100: tum turler, sayi kademeli artar.
		var pool := [RING, BOMB, WHEEL, BAR]
		var count := 2 if level_id < 72 else (3 if level_id < 90 else 4)
		for i in count:
			kinds.append(pool[(level_id + i) % 4])
	elif level_id > 125:
		# 126-150 LAZER BANDI: yanip sonen isin, once tek basina ogretilir
		# (126), sonra diger turlerle birlikte kullanilir. Her bolumde EN AZ
		# BIR lazer vardir - bandin kimligi odur.
		var pool3 := [RING, WHEEL, BAR, BOMB]
		kinds = [LASER]
		if level_id >= 130:
			kinds.append(pool3[level_id % 4])
		if level_id >= 140:
			kinds.append(LASER)
		bricks = 0 if level_id < 135 else 2
		strong = 0 if level_id < 145 else 1
	else:
		# 101-125 FINAL BANDI: engeller + kucuk bir tugla kumesi bir arada.
		# Tugla sayisi bilerek dusuk (2-4): LevelWorld her cana bir durum yuvasi
		# ayirdigi icin kalabalik kumeler dogrulamayi dakikalara cikariyor.
		var pool2 := [RING, BOMB, WHEEL, BAR]
		var count2 := 2 if level_id < 113 else 3
		for i in count2:
			kinds.append(pool2[(level_id + i) % 4])
		bricks = 2 if level_id < 110 else (3 if level_id < 120 else 4)
		strong = 1 if level_id < 115 else 2

	return {
		"name": name,
		"kinds": kinds,
		"difficulty": difficulty,
		"bricks": bricks,
		"strong_bricks": strong,
	}
