extends SceneTree

## GELISTIRME ARACI - oyuna dahil degildir.
##
## 51-150 bandini YENIDEN URETIR ve her bolumu yazmadan once gercek
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
const SIMS_PER_FRAME := 240
const MAX_SIMILARITY := 82.0

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

## Ekranda tekrar eden "Faz N" etiketleri yerine her rotanin ayirt edici bir
## adi vardir. 51, 76, 101 ve 126 okunakli tanitim bolumleridir; diger adlar rota
## fikrini anlatir, yeni mekanik gelince zorlugun sifirlandigini ima etmez.
const BAND_NAMES := {
	51: "Halka Girişi", 52: "Açık Halka", 53: "Eğik Geçiş",
	54: "Kenar Halkası", 55: "Bloklu Halka", 56: "Ters Halka",
	57: "Çifte Sekme", 58: "Çatlak Çember", 59: "Dar Yörünge",
	60: "Halka Koridoru", 61: "Kırık Yörünge", 62: "Kenar Düğümü",
	63: "Çapraz Halka", 64: "Zırhlı Çember", 65: "İki Geçit",
	66: "Ters Koridor", 67: "Halka Anahtarı", 68: "Kırık Yay",
	69: "Duvar Dönüşü", 70: "Dar Çember", 71: "Kilitli Halka",
	72: "Çifte Yörünge", 73: "Zırhlı Geçit", 74: "Son Düğüm",
	75: "Halka Ustalığı", 76: "Mayın Girişi", 77: "Güvenli Açı",
	78: "Mayın Çemberi", 79: "Ters Fitil", 80: "Kenar Mayını",
	81: "Halka ve Fitil", 82: "Dar Güvenlik", 83: "Çifte Tehdit",
	84: "Kırık Rota", 85: "Mayın Yörüngesi", 86: "Zırhlı Mayın",
	87: "Halka Sığınağı", 88: "Çapraz Fitil", 89: "Sessiz Koridor",
	90: "Dar Mayın", 91: "Çifte Mayın", 92: "Kırık Güvenlik",
	93: "Duvar Tuzağı", 94: "Halka Tuzağı", 95: "Üçlü Tehdit",
	96: "Zırhlı Fitil", 97: "Son Güvenli Açı", 98: "Halka ve Mayın",
	99: "Mayın Kilidi", 100: "Mayın Ustalığı",
	101: "Çark Girişi", 102: "Dönen Geçit", 103: "Ters Devir",
	104: "Kenar Çarkı", 105: "Çatlak Rotor", 106: "Mayın Dişlisi",
	107: "Dar Pervane", 108: "Zırhlı Devir", 109: "Mayınlı Çark",
	110: "Çapraz Rotor", 111: "Duvar Dişlisi", 112: "İkili Devir",
	113: "Sıkışık Pervane", 114: "Kırık Rotor", 115: "Derin Devir",
	116: "Sessiz Devir", 117: "Zırhlı Rotor", 118: "Ters Pervane",
	119: "Halka Deviri", 120: "Kilitli Devir", 121: "Dar Rotor",
	122: "Duvar Pervanesi", 123: "Üçlü Dönüş", 124: "Son Devir",
	125: "Çark Ustalığı", 126: "Lazer Girişi", 127: "Sönen Hat",
	128: "Işık Aralığı", 129: "Kesik Işın", 130: "Zırhlı Lazer",
	131: "Çember Işığı", 132: "Mayın ve Işık", 133: "Çatlak Hat",
	134: "Halka Lazer", 135: "Ters Darbe", 136: "Kırık Işın",
	137: "Duvar Işığı", 138: "Çifte Atım", 139: "Dar Zamanlama",
	140: "Dönen Işık", 141: "Kesik Darbe", 142: "Zırhlı Atım",
	143: "Kesişen Işın", 144: "Sessiz Aralık", 145: "Işık Kapanı",
	146: "Keskin Atım", 147: "Sönük Koridor", 148: "Son Işık Kilidi",
	149: "Işın Düğümü", 150: "Lazer Ustalığı",
}

## Iskelet cesitlemesi. Bkz. _jitter_skeleton: yalnizca --distinct modunda
## uygulanir, cunku normal uretim BIRE BIR atamayla zaten farkli iskelet verir.
const JITTER_PANEL_MIN := 26.0
const JITTER_PANEL_MAX := 54.0
const JITTER_ANGLE := 7.0
const JITTER_TARGET := 34.0

var _skeletons: Array[Dictionary] = []
var _from := 51
var _to := 150
## Yalnizca bu bolumler uretilir (--only). Bos ise _from.._to araligi kullanilir.
var _only: Array[int] = []
## --distinct: iskelet her denemede kucuk bir sapmayla kullanilir, boylece
## uretilen bolum kutuphanedeki HICBIR bolumle ayni iskeleti paylasmaz.
var _distinct := false
var _identity_only := false
var _solver: LevelSolver
var _world: LevelWorld
var _rng := RandomNumberGenerator.new()
var _novelty := LevelNoveltyScorer.new()
var _references: Array[Dictionary] = []


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
		elif args[i] == "--identity-only":
			_identity_only = true
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
	if _identity_only:
		for level_id in wanted:
			var level := LevelLibrary.load_level(level_id)
			_apply_identity(level, level_id, _spec_for(level_id))
			var error := ResourceSaver.save(level, "res://levels/level_%d.tres" % level_id)
			if error != OK:
				push_error("kimlik kayit hatasi level %d: %d" % [level_id, error])
				quit(1)
				return
		print("Kimlik/zorluk alanlari yenilendi: %d bolum" % wanted.size())
		quit(0)
		return
	if _distinct:
		print("--distinct: iskeletler sapmayla kullanilacak (tekrar kirma modu)")
	_index_references(wanted)

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


func _index_references(rebuilt_ids: Array[int]) -> void:
	# Yeniden yazilan eski dosyalar kendi adaylarini haksiz yere reddetmesin.
	# 1-50 ile bant tanitimlari (51/76/101/126 parca parca calistirmada) ve ayni
	# calismada kabul edilen yeni bolumler yine referans olarak kalir.
	for level_id in range(LevelLibrary.FIRST_LEVEL_ID, 151):
		if rebuilt_ids.has(level_id):
			continue
		_references.append({
			"name": "Resmi %03d" % level_id,
			"level": LevelLibrary.load_level(level_id),
			"metrics": {},
		})


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
	for choice in 12:
		var skeleton := _skeleton_for(level_id, choice)
		var relaxed := spec.duplicate(true)
		# Blok durum aramasi pahali oldugu icin kapili bolumler tutmayan ek
		# engelleri daha erken birakir; bandin kimlik engeli listenin basinda
		# oldugundan cark/lazer her durumda korunur.
		var has_bricks := int(spec["bricks"]) > 0
		var drop := choice
		var kinds: Array = (spec["kinds"] as Array).duplicate()
		var min_kinds := int(spec.get("min_kinds", 1))
		while drop > 0 and kinds.size() > min_kinds:
			kinds.pop_back()
			drop -= 1
		relaxed["kinds"] = kinds
		var attempt_count := 8
		for attempt in attempt_count:
			var shaped := _jitter_skeleton(skeleton) if _distinct else skeleton
			var level := _level_from_skeleton(shaped, level_id, relaxed)
			if not _layout_is_clear(level):
				continue
			if int(relaxed["bricks"]) > 0 and not _place_bricks(level, relaxed, shaped):
				continue
			if not _place_obstacles(level, relaxed, shaped):
				continue
			if not level.validate().is_empty():
				continue

			var verdict := await _evaluate(level)
			if not bool(verdict["ok"]):
				continue
			var novelty := _novelty.score(level, verdict, _references)
			if float(novelty["similarity"]) > MAX_SIMILARITY:
				continue

			_apply_identity(level, level_id, relaxed)
			var error := ResourceSaver.save(level, "res://levels/level_%d.tres" % level_id)
			if error != OK:
				push_error("kayit hatasi level %d: %d" % [level_id, error])
				return false
			_references.append({
				"name": "Yeni %03d" % level_id,
				"level": level.duplicate(true),
				"metrics": verdict.duplicate(true),
			})
			print("LEVEL %3d ok  iskelet=%-2d%s engel=%d tugla=%d saglam=%d sekme=%d benzerlik=%d" % [
				level_id, int(skeleton["index"]),
				"A" if bool(skeleton["mirrored"]) else " ",
				level.obstacles.size(), level.breakable_blocks.size(),
				int(verdict["robust"]), int(verdict["bounces"]),
				int(novelty["similarity"])])
			return true

	print("LEVEL %3d BASARISIZ - arama basamaklari yetmedi" % level_id)
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
	if level_id in [51, 76, 101, 126] and panels.size() > 1:
		panels.resize(1)
	level.panels = panels
	level.max_lives = 5
	_apply_wall_gaps(level, int(spec.get("wall_mode", 0)), level_id)
	return level


func _layout_is_clear(level: LevelData) -> bool:
	var spawn := _solver.spawn_position(level.launcher_position)
	for panel in level.panels:
		var ends := _panel_endpoints(panel)
		for endpoint in ends:
			if (endpoint.x < 24.0 or endpoint.x > 696.0
					or endpoint.y < 165.0 or endpoint.y > 1060.0):
				return false
		if _circle_hits_panel(level.target_position,
				_solver.target_size * 0.5 + 24.0, panel):
			return false
		if _circle_hits_panel(level.launcher_position, 92.0, panel):
			return false
		if _circle_hits_panel(spawn, _solver.radius + 26.0, panel):
			return false
	for i in level.panels.size():
		for j in range(i + 1, level.panels.size()):
			if _panels_too_close(level.panels[i], level.panels[j]):
				return false
	return true


func _panel_endpoints(panel: PanelData) -> Array[Vector2]:
	var half := Vector2.RIGHT.rotated(deg_to_rad(panel.rotation_degrees)) * panel.length * 0.5
	return [panel.position - half, panel.position + half] as Array[Vector2]


func _panels_too_close(a: PanelData, b: PanelData) -> bool:
	var aa := _panel_endpoints(a)
	var bb := _panel_endpoints(b)
	if Geometry2D.segment_intersects_segment(aa[0], aa[1], bb[0], bb[1]) != null:
		return true
	var clearance := (a.thickness + b.thickness) * 0.5 + 22.0
	for point in aa:
		if point.distance_to(Geometry2D.get_closest_point_to_segment(
				point, bb[0], bb[1])) < clearance:
			return true
	for point in bb:
		if point.distance_to(Geometry2D.get_closest_point_to_segment(
				point, aa[0], aa[1])) < clearance:
			return true
	return false


func _apply_wall_gaps(level: LevelData, mode: int, level_id: int) -> void:
	level.left_wall_segments = [] as Array[Vector2]
	level.right_wall_segments = [] as Array[Vector2]
	if mode == 0:
		return
	var center := _rng.randf_range(560.0, 820.0)
	var half := _rng.randf_range(58.0, 92.0)
	var gap: Array[Vector2] = [
		Vector2(-LevelData.WALL_OVERSHOOT, center - half),
		Vector2(center + half, 1280.0 + LevelData.WALL_OVERSHOOT),
	]
	if mode in [1, 3]:
		level.left_wall_segments = gap.duplicate()
	if mode in [2, 3]:
		var other_center := clampf(center + _rng.randf_range(-145.0, 145.0), 500.0, 860.0)
		var other_half := _rng.randf_range(55.0, 88.0)
		level.right_wall_segments = [
			Vector2(-LevelData.WALL_OVERSHOOT, other_center - other_half),
			Vector2(other_center + other_half, 1280.0 + LevelData.WALL_OVERSHOOT),
		] as Array[Vector2]


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
		skeleton: Dictionary) -> bool:
	var count := int(spec["bricks"])
	var strong := int(spec["strong_bricks"])
	# Tam genislikteki kapinin iki yanindan bedava gecilemez. Satir yuksekligi
	# her adayda degisir ve panel/hedef boslugu fizik kurulmadan once elenir.
	var gap := _rng.randf_range(12.0, 22.0)
	var left := 34.0
	var total_width := 652.0
	var brick_width := (total_width - gap * float(count - 1)) / float(count)
	for _try in 24:
		var row_y := _rng.randf_range(390.0, 720.0)
		var bricks: Array[BreakableBlockData] = []
		var clear := true
		for i in count:
			var brick := BreakableBlockData.new()
			brick.position = Vector2(
				left + brick_width * 0.5 + float(i) * (brick_width + gap),
				row_y + (16.0 if (i + level.level_id) % 2 == 0 else -16.0))
			brick.rotation_degrees = _rng.randf_range(-5.0, 5.0)
			brick.size = Vector2(brick_width, 34.0)
			brick.hit_points = 2 if i < strong else 1
			if not _block_position_is_clear(brick, level):
				clear = false
				break
			bricks.append(brick)
		if clear:
			level.breakable_blocks = bricks
			return true
	return false


func _block_position_is_clear(block: BreakableBlockData, level: LevelData) -> bool:
	if _circle_hits_block(level.target_position, _solver.target_size * 0.5 + 10.0, block):
		return false
	if _circle_hits_block(level.launcher_position, 85.0, block):
		return false
	for panel in level.panels:
		if _oriented_rects_overlap(block.position, block.size * 0.5,
				deg_to_rad(block.rotation_degrees), panel.position,
				Vector2(panel.length, panel.thickness) * 0.5,
				deg_to_rad(panel.rotation_degrees), 10.0):
			return false
	return true


func _circle_hits_block(circle: Vector2, radius: float,
		block: BreakableBlockData) -> bool:
	var local := (circle - block.position).rotated(-deg_to_rad(block.rotation_degrees))
	var half := block.size * 0.5
	var nearest := Vector2(clampf(local.x, -half.x, half.x),
		clampf(local.y, -half.y, half.y))
	return local.distance_squared_to(nearest) < radius * radius


func _oriented_rects_overlap(a_center: Vector2, a_half: Vector2, a_angle: float,
		b_center: Vector2, b_half: Vector2, b_angle: float, padding: float) -> bool:
	var a_x := Vector2.RIGHT.rotated(a_angle)
	var a_y := Vector2.DOWN.rotated(a_angle)
	var b_x := Vector2.RIGHT.rotated(b_angle)
	var b_y := Vector2.DOWN.rotated(b_angle)
	var delta := b_center - a_center
	for axis in [a_x, a_y, b_x, b_y]:
		var a_projection := absf(a_x.dot(axis)) * (a_half.x + padding) \
			+ absf(a_y.dot(axis)) * (a_half.y + padding)
		var b_projection := absf(b_x.dot(axis)) * b_half.x \
			+ absf(b_y.dot(axis)) * b_half.y
		if absf(delta.dot(axis)) >= a_projection + b_projection:
			return false
	return true


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
	if level.level_id in [51, 76, 101, 126] and position.y > 820.0:
		# Tanitim metni ekranin alt-orta bandinda, dunya koordinatinda yaklasik
		# y=930'da cizilir; yeni engeli bu satirin ustunde tut.
		return false
	if position.distance_to(level.target_position) < radius + _solver.target_size * 0.5 + CLEARANCE:
		return false
	if position.distance_to(level.launcher_position) < radius + 70.0 + CLEARANCE:
		return false
	if position.distance_to(spawn) < radius + _solver.radius + CLEARANCE:
		return false
	for panel in level.panels:
		if _circle_hits_panel(position, radius + CLEARANCE, panel):
			return false
	for block in level.breakable_blocks:
		var half := block.size * 0.5 + Vector2.ONE * (radius + CLEARANCE)
		var local := (position - block.position).rotated(-deg_to_rad(block.rotation_degrees))
		if absf(local.x) < half.x and absf(local.y) < half.y:
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
			data.size = Vector2(170.0, 28.0)
			data.inner_radius = lerpf(72.0, 56.0, difficulty)
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

	var band_start := 51
	if level.level_id >= 126:
		band_start = 126
	elif level.level_id >= 101:
		band_start = 101
	elif level.level_id >= 76:
		band_start = 76
	var band_progress := float(level.level_id - band_start) / 24.0
	var intro_levels := [51, 76, 101, 126]
	var max_robust := 64 if level.level_id in intro_levels else roundi(
		lerpf(34.0, 18.0, clampf(band_progress, 0.0, 1.0)))
	var min_robust := 14 if level.level_id in intro_levels else MIN_ROBUST
	if level.breakable_blocks.is_empty():
		var scan := _solver.scan(spawn, level.target_position, play_rect,
			[], ANGLE_STEP, POWER_STEP)
		var analysis := LevelSolver.analyse_robust(scan)
		var robust := int(analysis["robust"])
		var bounces := int(analysis["bounces"]) if int(scan["hit_count"]) > 0 else -1
		result["robust"] = robust
		result["bounces"] = bounces
		var hit_rate := float(scan["hit_count"]) / float(maxi(int(scan["total"]), 1))
		result["hit_rate"] = hit_rate
		result["ok"] = (robust >= min_robust and robust <= max_robust
			and bounces >= 1 and (level.level_id in intro_levels or hit_rate <= 0.075))
	else:
		# Bloklu bolumde yalnizca "hepsi kirilmis" hayali geometriyi olcmek
		# yetmez. Oyuncunun gercek atislarla ulasabildigi blok durumlarini ara;
		# aksi halde kagit ustunde acilan ama oynanista acilamayan kapi uretilir.
		var coarse := await _solver.search_block_states_async(
			spawn, level.target_position, play_rect, 5,
			9.0, 300.0, 32, SIMS_PER_FRAME * 2)
		var free_scan := await _solver.scan_block_state_async(
			spawn, level.target_position, play_rect, 0,
			ANGLE_STEP, POWER_STEP, SIMS_PER_FRAME)
		var free_robust := int(LevelSolver.analyse_robust(free_scan)["robust"])
		if free_robust < MIN_ROBUST:
			var checked := 0
			for solution in coarse["solutions"]:
				var state := int(solution["state"])
				if state == 0:
					continue
				checked += 1
				if checked > 6:
					break
				var opened := await _solver.scan_block_state_async(
					spawn, level.target_position, play_rect, state,
					ANGLE_STEP, POWER_STEP, SIMS_PER_FRAME)
				var opened_analysis := LevelSolver.analyse_robust(opened)
				var opened_robust := int(opened_analysis["robust"])
				var opened_hit_rate := (float(opened["hit_count"])
					/ float(maxi(int(opened["total"]), 1)))
				var opened_bounces := (int(opened_analysis["bounces"])
					if int(opened["hit_count"]) > 0 else -1)
				if (opened_robust >= MIN_ROBUST and opened_robust <= max_robust
						and opened_hit_rate <= 0.08
						and opened_bounces >= 1):
					result["robust"] = opened_robust
					result["bounces"] = opened_bounces
					result["hit_rate"] = opened_hit_rate
					result["shots"] = int(solution["shots"])
					result["ok"] = true
					break

	_world.queue_free()
	_world = null
	await process_frame
	return result


func _apply_identity(level: LevelData, level_id: int, spec: Dictionary) -> void:
	level.level_uid = LevelData.uid_for(level_id)
	level.display_order = level_id
	level.difficulty = (3 if level_id in [51, 76, 101, 126] else
		(5 if level_id in [75, 95, 96, 97, 98, 99, 100, 120, 121, 122,
			123, 124, 125, 145, 146, 147, 148, 149, 150] else 4))
	level.display_name = String(spec["name"])
	level.tutorial_text = ("Metal halkanın açıklığını sekme rotasında kullan."
		if level_id == 51 else ("Mayına değmeden güvenli sekme açısını bul."
		if level_id == 76 else ("Dönen çarkın kolları arasındaki boşluğu zamanla."
		if level_id == 101 else ("Lazer sönükken atışını çizginin ötesine geçir."
		if level_id == 126 else ""))))
	level.max_lives = 5
	level.two_star_max_shots = 5 if int(spec["bricks"]) > 0 else 3
	level.three_star_max_shots = 4 if int(spec["bricks"]) > 0 else 2
	var t := clampf(float(level_id - 51) / 99.0, 0.0, 1.0)
	level.two_star_max_seconds = snappedf(lerpf(75.0, 160.0, t), 0.1)
	level.three_star_max_seconds = snappedf(lerpf(40.0, 85.0, t), 0.1)


## Bolum basina icerik plani: engel karisimi, zorluk ve aralikli tugla kapilari.
func _spec_for(level_id: int) -> Dictionary:
	var difficulty := clampf(float(level_id - 51) / 99.0, 0.0, 1.0)
	var name := String(BAND_NAMES.get(level_id, "Faz %d" % level_id))
	var kinds: Array = []
	var bricks := 0
	var strong := 0
	var wall_mode := 0
	var min_kinds := 1

	if level_id <= 75:
		# 51-75: halka bandi. Yalnizca 51 tanitim kolayligindadir; 52'den
		# itibaren onceki panel, duvar boslugu ve blok dili geri gelir.
		var stage := level_id - 51
		difficulty = lerpf(0.18, 0.92, float(stage) / 24.0)
		kinds = [RING]
		if stage >= 10 and (stage % 2 == 0 or stage >= 20):
			kinds.append(RING)
		if level_id in [55, 58, 61, 64, 67, 70, 73, 75]:
			bricks = 4
			strong = 1 if level_id >= 64 else 0
		if stage > 0:
			wall_mode = 3 if stage in [14, 19, 24] else (stage % 3)
	elif level_id <= 100:
		# 76-100: bomba bandi. 76 bombayi tek basina ve okunakli tanitir;
		# 77'den sonra halka hemen geri doner, blok/duvarlar da aralikli olarak
		# kullanilir. Boylece yeni engel butun oyunu yeniden kolaylastirmaz.
		var stage := level_id - 76
		difficulty = lerpf(0.48, 1.0, float(stage) / 24.0)
		kinds = [BOMB]
		if stage > 0:
			kinds.append(RING)
		if stage >= 15 and (stage % 2 == 1 or stage >= 22):
			kinds.append(BOMB)
		if level_id in [80, 83, 86, 89, 92, 95, 98, 100]:
			bricks = 4
			strong = 1 if level_id >= 86 else 0
		if stage > 0:
			wall_mode = 3 if stage in [14, 19, 24] else (stage % 3)
	elif level_id <= 125:
		# 101-125: donen cark bandi. Yalnizca 101 tek mekanikli tanitimdir;
		# 102'den itibaren halka/mayin, aralikli blok kapilari ve duvar bosluklari
		# geri gelir. Cark ilk tur olarak kalir, gevseme onu asla dusurmez.
		var stage := level_id - 101
		difficulty = lerpf(0.58, 1.0, float(stage) / 24.0)
		kinds = [WHEEL]
		if stage > 0:
			kinds.append(RING if stage % 3 != 2 else BOMB)
		if level_id in [124, 125]:
			kinds.append(BOMB if kinds[1] == RING else RING)
		if level_id in [105, 108, 111, 114, 117, 120, 123, 125]:
			bricks = 1
			strong = 0 if level_id < 114 else 1
		if stage > 0:
			wall_mode = 3 if stage in [14, 19, 24] else (stage % 3)
		if level_id in [102, 104, 105, 106, 107, 109, 110, 111, 112, 119]:
			min_kinds = 2
	else:
		# 126-150: lazer bandi. 126 yalnizca lazeri ogretir; sonrasinda cark,
		# halka ve mayin duzenli doner. Lazer ilk turdur ve her bolumde korunur.
		var stage := level_id - 126
		difficulty = lerpf(0.64, 1.0, float(stage) / 24.0)
		kinds = [LASER]
		var previous := [WHEEL, RING, BOMB]
		if stage > 0:
			kinds.append(previous[(stage - 1) % previous.size()])
		if level_id in [149, 150]:
			kinds.append(LASER)
		if level_id in [130, 133, 136, 139, 142, 145, 148, 150]:
			bricks = 1
			strong = 0 if level_id < 139 else 1
		if stage > 0:
			wall_mode = 3 if stage in [14, 19, 24] else (stage % 3)
		if level_id in [127, 128, 129, 130, 131, 132, 134, 135, 136, 137, 140,
				143, 144, 148]:
			min_kinds = 2

	return {
		"name": name,
		"kinds": kinds,
		"difficulty": difficulty,
		"bricks": bricks,
		"strong_bricks": strong,
		"wall_mode": wall_mode,
		"min_kinds": min_kinds,
	}
