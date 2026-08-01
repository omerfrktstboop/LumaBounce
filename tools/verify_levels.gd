extends SceneTree

## GELISTIRME ARACI - oyuna dahil degildir, calisma zamaninda hic yuklenmez.
##
## Her bolum icin aci x guc izgarasini tarar ve hedefe ulasan atislari raporlar.
## Amac "bu bolum cozulebilir mi" sorusunu el hesabiyla degil, GERCEK fizikle
## yanitlamak.
##
## Sadakat notlari:
##   - Tum sabitler (yercekimi, sekme katsayisi, guc araligi, yaricap...)
##     gercek ball.tscn / launcher.tscn / target.tscn ornekleri olusturulup
##     export'lari OKUNARAK alinir; elle kopyalanmaz, dolayisiyla sapma olmaz.
##   - Duvarlar ve paneller gercek Arena ve bounce_panel.tscn dugumleridir.
##   - Carpisma testi launcher.gd'nin nisan onizlemesiyle ayni yontemi kullanir:
##     cast_motion + get_rest_info (CircleShape2D supurmesi).
##   - Entegrasyon sirasi ball.gd ile birebir aynidir:
##     yercekimi -> hiz sinirlama -> move_and_collide -> sekme -> ayrilma itmesi.
##
## Tek fark: move_and_collide'in safe_margin depenetrasyonu birebir taklit
## edilmez (temas sonrasi normal yonunde kucuk sabit bir itme kullanilir).
## Bu yuzden sonuclar "cok yakin yaklasim"dir, bit-bit ayni degildir.
##
## IKI MOD:
##   1) Bloksuz bolumler (1-20) - tek atislik izgara taramasi. Davranis
##      kirilabilir bloklar eklenmeden onceki haliyle birebir aynidir.
##   2) Kirilabilir blogu olan bolumler (21+) - COK ATISLI durum arayisi.
##      Tek atislik model burada yanlis cevap verirdi: bir atisin kirdigi
##      blok sonraki atisin geometrisini kalicі olarak degistirir. Bu yuzden
##      "hangi bloklar kirik" durumlari uzerinde genislik-oncelikli arama
##      yapilir ve hedefe EN AZ kac atista ulasilabildigi bulunur.
##
## Kullanim:
##   godot --headless --path . --script res://tools/verify_levels.gd
##   godot --headless --path . --script res://tools/verify_levels.gd -- --angle-step 1 --power-step 25
##   godot --headless --path . --script res://tools/verify_levels.gd -- --level 21
##   godot --headless --path . --script res://tools/verify_levels.gd -- --block-angle-step 2 --block-power-step 50

const OBSTACLE_LAYER := 1
const PHYSICS_FPS := 60.0
## Bir atisin izlenecegi en fazla fizik karesi (~7 sn).
const MAX_FRAMES := 420
## Tek karede cozulecek en fazla carpisma (ball.gd max_bounces_per_step).
const MAX_SUBSTEPS := 6
## Temas sonrasi ayni yuzeyi tekrar yakalamamak icin normal yonunde itme.
const CONTACT_EPSILON := 0.05
## Bir hucrenin "saglam" sayilmasi icin 4 komsusunun da isabet etmesi gerekir.
## Bu, "piksel hassasiyeti gerektirmesin" kuralinin olculebilir karsiligi.
const ROBUST_NEIGHBOURS := 4
## Cok atisli aramada ziyaret edilecek en fazla "kirik blok" durumu.
## Kombinasyon sayisi 2^blok oldugu icin ust sinir sart.
const MAX_BLOCK_STATES := 48
## Cok atisli modda bir rotanin "rahat" sayilmasi icin gereken saglam hucre
## sayisi. Tek bir saglam hucre, kaba izgarada yalnizca ~3 derece x 100 guc
## demektir - teknik olarak "komsulari da isabet ediyor" ama oyuncu icin hala
## tek bir noktayi tutturmak. Bloklu bolumlerde bu esigin altinda kalan bir
## rota kabul edilmez; daha derin (daha cok blok kirilmis) durumlar aranir.
const MIN_ROBUST_CELLS := 6
## TASARIM SOZLESMESI: bu bolumden itibaren kirilabilir blok ZORUNLU OLAMAZ.
## Her bolumun hicbir blok kirmadan gecilebilen bir rotasi olmali, yoksa blok
## bir bulmaca parcasi degil anahtar/kapi olur ve oyun brick-breaker'a kayar.
## 21 disaridadir: mekanigi ogreten tek bolum oldugu icin orada blok kirmak
## zorunlu olabilir. Ileride eklenecek bolumler bu esigin ustunde kalir.
const BLOCK_OPTIONAL_FROM_LEVEL := 22

var _angle_step := 2.0
var _power_step := 50.0
## Cok atisli mod her durum icin bastan tarama yaptigi icin bilerek daha
## kaba baslar; --block-*-step ile sikilastirilabilir.
var _block_angle_step := 3.0
var _block_power_step := 100.0
## -1: tum bolumler. Tek bir bolumu hizlica denemek icin --level N.
var _only_level := -1
## Yalnizca "hicbir blok kirilmamis" durumunu tarar. Bloksuz rotayi ayarlarken
## tum durum agacini beklemeye gerek yok - tasarim dongusunu kisaltir.
var _free_only := false

var _world: Node2D
var _arena: Arena
var _space: PhysicsDirectSpaceState2D
var _ball_shape: CircleShape2D
## Kirilabilir blok govdesinin RID'i -> LevelData.breakable_blocks indeksi.
## Simulasyon bir blogu "kirdiginda" onu gercekten silmez; RID'i o atisin
## haric tutma listesine ekler, boylece sonraki temaslarda gorunmez olur.
var _block_index: Dictionary = {}
var _block_count := 0

# Gercek sahnelerden okunan fizik sabitleri.
var _radius := 24.0
var _gravity := 1500.0
var _bounciness := 0.94
var _min_separation := 60.0
var _max_speed := 3000.0
var _settle_speed := 80.0
var _settle_time := 0.85
var _oob_margin := 240.0
var _min_power := 900.0
var _max_power := 2300.0
var _max_angle := 78.0
var _spawn_offset := 70.0
var _target_size := 92.0


func _initialize() -> void:
	_parse_args()
	_run.call_deferred()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--angle-step" and i + 1 < args.size():
			_angle_step = maxf(float(args[i + 1]), 0.25)
		elif args[i] == "--power-step" and i + 1 < args.size():
			_power_step = maxf(float(args[i + 1]), 5.0)
		elif args[i] == "--block-angle-step" and i + 1 < args.size():
			_block_angle_step = maxf(float(args[i + 1]), 0.25)
		elif args[i] == "--block-power-step" and i + 1 < args.size():
			_block_power_step = maxf(float(args[i + 1]), 5.0)
		elif args[i] == "--level" and i + 1 < args.size():
			_only_level = int(args[i + 1])
		elif args[i] == "--free-only":
			_free_only = true


func _run() -> void:
	await physics_frame
	_read_real_constants()

	print("LumaBounce bolum dogrulayici")
	print("  yaricap=%.0f  yercekimi=%.0f  sekme=%.2f  guc=%.0f..%.0f  aci=+-%.0f" % [
		_radius, _gravity, _bounciness, _min_power, _max_power, _max_angle])
	print("  izgara: aci adimi %.2f deg, guc adimi %.0f" % [_angle_step, _power_step])
	print("  blok izgarasi: aci adimi %.2f deg, guc adimi %.0f" % [
		_block_angle_step, _block_power_step])
	print("")

	var failures := 0
	for level_id in range(LevelLibrary.FIRST_LEVEL_ID, LevelLibrary.last_level_id() + 1):
		if _only_level > 0 and level_id != _only_level:
			continue
		var level := LevelLibrary.load_level(level_id)
		var passed: bool = await _verify_level(level)
		if not passed:
			failures += 1
		_teardown_world()

	print("")
	if failures == 0:
		print("SONUC: tum bolumler gecti.")
	else:
		print("SONUC: %d bolum uyari uretti." % failures)
	quit(0 if failures == 0 else 1)


## Sabitleri gercek sahnelerden oku - elle kopyalanan deger sapma yaratir.
func _read_real_constants() -> void:
	var ball := (load("res://scenes/ball.tscn") as PackedScene).instantiate() as Ball
	var launcher := (load("res://scenes/launcher.tscn") as PackedScene).instantiate() as Launcher
	var target := (load("res://scenes/target.tscn") as PackedScene).instantiate() as Target
	root.add_child(ball)
	root.add_child(launcher)
	root.add_child(target)

	_radius = ball.radius
	_gravity = ball.gravity
	_bounciness = ball.bounciness
	_min_separation = ball.min_separation_speed
	_max_speed = ball.max_speed
	_settle_speed = ball.settle_speed
	_settle_time = ball.settle_time
	_oob_margin = ball.out_of_bounds_margin
	_min_power = launcher.min_power
	_max_power = launcher.max_power
	_max_angle = launcher.max_aim_angle_deg
	_spawn_offset = launcher.ball_spawn_offset
	_target_size = target.size

	ball.queue_free()
	launcher.queue_free()
	target.queue_free()

	_ball_shape = CircleShape2D.new()
	_ball_shape.radius = _radius


# --- Dunya kurulumu -----------------------------------------------------------

func _build_world(level: LevelData) -> void:
	_world = Node2D.new()
	root.add_child(_world)

	_arena = Arena.new()
	_world.add_child(_arena)
	var play_rect := _arena.get_play_rect()
	_arena.configure(level.get_left_segments(play_rect), level.get_right_segments(play_rect))

	var panel_scene := load("res://scenes/bounce_panel.tscn") as PackedScene
	for panel_data in level.panels:
		if panel_data == null:
			continue
		var panel := panel_scene.instantiate() as BouncePanel
		panel.position = panel_data.position
		panel.rotation_degrees = panel_data.rotation_degrees
		panel.length = panel_data.length
		panel.thickness = panel_data.thickness
		_world.add_child(panel)

	_build_blocks(level)
	_space = _world.get_world_2d().direct_space_state


## Bloklar gercek breakable_block.tscn ornekleridir; boylece carpisma
## dikdortgeni ve donusu oyundakiyle birebir aynidir.
func _build_blocks(level: LevelData) -> void:
	_block_index.clear()
	_block_count = 0

	var block_scene := load("res://scenes/breakable_block.tscn") as PackedScene
	for i in level.breakable_blocks.size():
		var data := level.breakable_blocks[i]
		if data == null:
			continue
		var block := block_scene.instantiate() as BreakableBlock
		block.position = data.position
		block.rotation_degrees = data.rotation_degrees
		block.block_size = data.size
		_world.add_child(block)
		# Indeks .tres sirasidir; raporlarda "blok 2" dosyadaki 2. blok demektir.
		_block_index[block.get_rid()] = i
		_block_count += 1


func _teardown_world() -> void:
	if _world != null:
		_world.queue_free()
		_world = null
		_arena = null
	_block_index.clear()
	_block_count = 0


# --- Dogrulama ----------------------------------------------------------------

func _verify_level(level: LevelData) -> bool:
	_build_world(level)
	# Yeni gövdelerin fizik uzayina girmesi icin iki kare bekle.
	await physics_frame
	await physics_frame

	var ok := true
	print("--- Bolum %d: %s ---" % [level.level_id, level.display_name])

	ok = _check_static_geometry(level) and ok
	if _block_count > 0:
		ok = _check_multi_shot_solvability(level) and ok
	else:
		ok = _check_solvability(level) and ok
	return ok


## Statik yerlesim hatalari: hedef/firlatici bir panelin icinde mi, panel
## uclari hedefe/firlaticiya biniyor mu.
func _check_static_geometry(level: LevelData) -> bool:
	var ok := true
	var spawn := level.launcher_position + Vector2.UP * _spawn_offset

	if _overlaps_obstacle(level.target_position, _target_size * 0.5):
		print("  HATA: hedef bir panelin/duvarin collision alani icinde.")
		ok = false
	if _overlaps_obstacle(spawn, _radius):
		print("  HATA: topun dogdugu nokta bir panelle cakisiyor.")
		ok = false
	if _overlaps_obstacle(level.launcher_position, 60.0):
		print("  HATA: firlatici govdesi bir panelle cakisiyor.")
		ok = false

	# Hedefin HUD'un arkasina dusmemesi: ust serit ~76 px + safe area payi.
	if level.target_position.y - _target_size * 0.5 < 150.0:
		print("  UYARI: hedef ust HUD seridine cok yakin (y=%.0f)." % level.target_position.y)
		ok = false
	return ok


func _overlaps_obstacle(at: Vector2, probe_radius: float) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = probe_radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.collision_mask = OBSTACLE_LAYER
	params.transform = Transform2D(0.0, at)
	return not _space.intersect_shape(params, 1).is_empty()


## Tek atislik dogrulama (bloksuz bolumler). Aci x guc izgarasini tarar;
## isabetleri ve "saglam" (komsulari da isabet eden) hucreleri raporlar.
func _check_solvability(level: LevelData) -> bool:
	var spawn := level.launcher_position + Vector2.UP * _spawn_offset
	var scan := _scan_grid(spawn, level, [], _angle_step, _power_step)
	_print_scan_summary(scan)

	if int(scan["hit_count"]) == 0:
		print("  HATA: hicbir atis hedefe ulasmiyor - bolum cozulemez.")
		return false

	return _report_robust_window(scan)


## Verilen "kirik blok" durumundan tum aci x guc izgarasini tarar.
## [param excluded] o durumda ARTIK OLMAYAN bloklarin RID'leridir.
func _scan_grid(spawn: Vector2, level: LevelData, excluded: Array[RID],
		angle_step: float, power_step: float) -> Dictionary:
	var angles: Array[float] = []
	var powers: Array[float] = []
	var angle := -_max_angle
	while angle <= _max_angle + 0.001:
		angles.append(angle)
		angle += angle_step
	var power := _min_power
	while power <= _max_power + 0.001:
		powers.append(power)
		power += power_step

	var hits: Array = []          # [ai][pi] -> bool
	var bounce_counts: Array = [] # [ai][pi] -> int (isabet etmeyenler -1)
	var hit_count := 0
	var min_bounces := 999
	var reasons := {"settled": 0, "oob": 0, "timeout": 0}
	## Bu taramada ulasilabilen yeni kirik-blok kombinasyonlari:
	## maske -> onu ureten temsili atis metni.
	var reached: Dictionary = {}

	for ai in angles.size():
		var row := []
		var bounce_row := []
		row.resize(powers.size())
		bounce_row.resize(powers.size())
		for pi in powers.size():
			var direction := Vector2.UP.rotated(deg_to_rad(angles[ai]))
			var result := _simulate(spawn, direction * powers[pi], level, excluded)
			var did_hit: bool = result["hit"]
			row[pi] = did_hit
			bounce_row[pi] = int(result["bounces"]) if did_hit else -1
			if did_hit:
				hit_count += 1
				min_bounces = mini(min_bounces, int(result["bounces"]))
			else:
				var reason: String = result["reason"]
				reasons[reason] = int(reasons.get(reason, 0)) + 1

			var broken := int(result["broken"])
			if broken != 0 and not reached.has(broken):
				reached[broken] = "aci %.1f deg, guc %.0f" % [angles[ai], powers[pi]]
		hits.append(row)
		bounce_counts.append(bounce_row)

	return {
		"angles": angles,
		"powers": powers,
		"hits": hits,
		"bounces": bounce_counts,
		"total": angles.size() * powers.size(),
		"hit_count": hit_count,
		"min_bounces": min_bounces,
		"reasons": reasons,
		"reached": reached,
	}


func _print_scan_summary(scan: Dictionary) -> void:
	var total := int(scan["total"])
	var hit_count := int(scan["hit_count"])
	var reasons: Dictionary = scan["reasons"]
	print("  ornek: %d  isabet: %d (%%%.1f)  en az sekme: %s" % [
		total, hit_count, 100.0 * float(hit_count) / float(maxi(total, 1)),
		str(int(scan["min_bounces"])) if hit_count > 0 else "-"])
	print("  basarisiz: ekran disi=%d, durdu=%d, zaman asimi=%d" % [
		int(reasons["oob"]), int(reasons["settled"]), int(reasons["timeout"])])


# --- Cok atisli dogrulama (kirilabilir bloklu bolumler) -----------------------
#
# Neden ayri bir mod: tek atislik model "bu bolum cozulebilir mi" sorusuna
# bloklu bir bolumde YANLIS cevap verir. Ilk atis hicbir zaman hedefe
# ulasamayabilir ama bir blogu kirip ikinci atisin yolunu acabilir - tek
# atisli tarama bunu "cozulemez" diye raporlardi.
#
# Durum = hangi bloklarin kirik oldugu (bit maskesi). Baslangic durumu 0'dir.
# Her durumda tum izgara taranir; isabet varsa bolum o kadar atista cozulur,
# yoksa taramanin urettigi yeni kirik-blok kombinasyonlari siraya eklenir.
# Blogun kirilmasi KALICIDIR (oyunda da atis sifirlamasi bloklari geri
# getirmez), bu yuzden durumlar yalnizca buyur.

func _check_multi_shot_solvability(level: LevelData) -> bool:
	var spawn := level.launcher_position + Vector2.UP * _spawn_offset
	var max_shots := 1 if _free_only else maxi(level.max_lives, 1)
	print("  kirilabilir blok: %d   en fazla atis: %d" % [_block_count, max_shots])

	var frontier: Array[int] = [0]
	var seen := {0: true}
	var states_visited := 0
	## Butun derinlikler taranir - ilk bulunan cozumde durmayiz. Sig bir
	## cozumun penceresi cok dar olabilir; o zaman "daha cok blok kirilmis"
	## bir durumda rahat bir rota var mi diye bakmak gerekir.
	var solutions: Array[Dictionary] = []

	for depth in max_shots:
		var next_frontier: Array[int] = []

		for state in frontier:
			if states_visited >= MAX_BLOCK_STATES:
				break
			states_visited += 1

			var scan := _scan_grid(
				spawn, level, _rids_for_state(state), _block_angle_step, _block_power_step)
			if int(scan["hit_count"]) > 0:
				solutions.append({
					"shots": depth + 1,
					"state": state,
					"scan": scan,
					"analysis": _analyse_robust(scan),
				})

			var reached: Dictionary = scan["reached"]
			for raw_mask in reached:
				var mask := state | int(raw_mask)
				if mask == state or seen.has(mask):
					continue
				seen[mask] = true
				next_frontier.append(mask)

		if next_frontier.is_empty() or states_visited >= MAX_BLOCK_STATES:
			break
		frontier = next_frontier

	if solutions.is_empty():
		print("  HATA: %d durum tarandi, hicbir atis dizisi hedefe ulasmiyor." % states_visited)
		return false

	return _report_solutions(level, solutions, states_visited)


## Bulunan tum rotalari listeler, sonra tasarim sozlesmesini uygular.
##
## BLOKSUZ ROTA hep durum 0'dir, yani tanimi geregi TEK ATISLIK bir cozumdur:
## her atis firlaticidan ayni geometriyle baslar, dolayisiyla "blok kirmadan
## 2 top" ile "blok kirmadan 1 top" ayni pencereyi paylasir - ikincisi sadece
## bir kez iskalamis halidir.
func _report_solutions(level: LevelData, solutions: Array[Dictionary],
		states_visited: int) -> bool:
	print("  %d durum tarandi, %d rota hedefe ulasiyor:" % [states_visited, solutions.size()])
	for entry in solutions:
		print("    %d atis  kirilan blok: %-10s isabet: %-5d saglam hucre: %d" % [
			int(entry["shots"]), _describe_state(int(entry["state"])),
			int((entry["scan"] as Dictionary)["hit_count"]), _robust_of(entry)])

	var free_route := _pick_route(solutions, true)
	var block_route := _pick_route(solutions, false)

	if _free_only:
		# Tasarim dongusu modu: yalnizca bloksuz rota olculur.
		return _report_route("BLOKSUZ USTALIK ROTASI (tek atis)", free_route)

	if level.level_id < BLOCK_OPTIONAL_FROM_LEVEL:
		# Ogretici bolum: blok kirmak zorunlu olabilir, tek bir rahat rota yeter.
		var main := block_route
		if not free_route.is_empty() and _robust_of(free_route) >= MIN_ROBUST_CELLS:
			main = free_route
		return _report_route("ANA ROTA", main)

	var ok := _report_route("BLOKSUZ USTALIK ROTASI (tek atis)", free_route)
	ok = _report_route("BLOKLU GUVENLI ROTA", block_route) and ok
	if not ok:
		return false

	# Blok kirmak rotayi gercekten kolaylastirmali; kolaylastirmiyorsa blok
	# bulmacaya hicbir sey katmiyor demektir.
	var free_robust := _robust_of(free_route)
	var block_robust := _robust_of(block_route)
	print("  KARSILASTIRMA: bloksuz %d saglam hucre, bloklu %d saglam hucre" % [
		free_robust, block_robust])
	if block_robust <= free_robust:
		print("  UYARI: blok kirmak rotayi kolaylastirmiyor - blok bulmacaya katki vermiyor.")
		return false
	return true


## [param block_free] true ise yalnizca hicbir blogun kirilmadigi durum (0).
## Esigi gecen rotalar oncelikli; hicbiri gecmiyorsa en iyisi raporlanir ki
## tasarimin ne kadar yaklastigi gorunsun.
func _pick_route(solutions: Array[Dictionary], block_free: bool) -> Dictionary:
	var best: Dictionary = {}
	for entry in solutions:
		if (int(entry["state"]) == 0) != block_free:
			continue
		if best.is_empty() or _is_better_route(entry, best):
			best = entry
	return best


func _is_better_route(a: Dictionary, b: Dictionary) -> bool:
	var a_ok := _robust_of(a) >= MIN_ROBUST_CELLS
	var b_ok := _robust_of(b) >= MIN_ROBUST_CELLS
	if a_ok != b_ok:
		return a_ok
	if int(a["shots"]) != int(b["shots"]):
		return int(a["shots"]) < int(b["shots"])
	return _robust_of(a) > _robust_of(b)


func _robust_of(entry: Dictionary) -> int:
	return int((entry["analysis"] as Dictionary)["robust"])


func _report_route(label: String, route: Dictionary) -> bool:
	if route.is_empty():
		print("  HATA: %s yok - hedefe hic ulasilamiyor." % label)
		return false
	print("  %s -> %d atis, kirilan blok: %s" % [
		label, int(route["shots"]), _describe_state(int(route["state"]))])
	_print_scan_summary(route["scan"])
	if _robust_of(route) < MIN_ROBUST_CELLS:
		print("  UYARI: %s %d saglam hucre esigini gecmiyor (%d) - cozum var ama dar." % [
			label, MIN_ROBUST_CELLS, _robust_of(route)])
		return false
	_print_robust(route["analysis"])
	return true


## Durumdaki kirik bloklarin RID'leri - simulasyon bunlari yok sayar.
func _rids_for_state(state: int) -> Array[RID]:
	var rids: Array[RID] = []
	if state == 0:
		return rids
	for rid in _block_index:
		if state & (1 << int(_block_index[rid])) != 0:
			rids.append(rid)
	return rids


func _describe_state(state: int) -> String:
	if state == 0:
		return "yok"
	var parts := PackedStringArray()
	for i in 32:
		if state & (1 << i) != 0:
			parts.append(str(i))
	return ", ".join(parts)


## Cevresi de isabet eden hucreler = piksel hassasiyeti gerektirmeyen cozum.
## Ornek olarak EN AZ sekmeyle biten saglam hucre secilir; bu, oyuncunun
## bulmasi beklenen "ana rota"dir. Cok sekmeli saglam hucreler genelde
## topun ortalikta dolasip sansla hedefe girdigi rotalardir.
func _report_robust_window(scan: Dictionary) -> bool:
	var analysis := _analyse_robust(scan)
	if int(analysis["robust"]) == 0:
		print("  UYARI: saglam cozum yok - her isabet tek bir dar aci/guce bagli.")
		return false
	_print_robust(analysis)
	return true


func _analyse_robust(scan: Dictionary) -> Dictionary:
	var angles: Array[float] = scan["angles"]
	var powers: Array[float] = scan["powers"]
	var hits: Array = scan["hits"]
	var bounce_counts: Array = scan["bounces"]

	var robust := 0
	var best_angle := 0.0
	var best_power := 0.0
	var best_bounces := 9999
	var angle_lo := 999.0
	var angle_hi := -999.0
	var power_lo := 99999.0
	var power_hi := -99999.0
	## Ana rotanin kac sekme icerdigini gormek icin dagilim.
	var by_bounces := {}

	for ai in range(1, angles.size() - 1):
		for pi in range(1, powers.size() - 1):
			if not hits[ai][pi]:
				continue
			var neighbours := 0
			if hits[ai - 1][pi]:
				neighbours += 1
			if hits[ai + 1][pi]:
				neighbours += 1
			if hits[ai][pi - 1]:
				neighbours += 1
			if hits[ai][pi + 1]:
				neighbours += 1
			if neighbours < ROBUST_NEIGHBOURS:
				continue

			robust += 1
			var cell_bounces: int = bounce_counts[ai][pi]
			by_bounces[cell_bounces] = int(by_bounces.get(cell_bounces, 0)) + 1
			if cell_bounces < best_bounces:
				best_bounces = cell_bounces
				best_angle = angles[ai]
				best_power = powers[pi]
			angle_lo = minf(angle_lo, angles[ai])
			angle_hi = maxf(angle_hi, angles[ai])
			power_lo = minf(power_lo, powers[pi])
			power_hi = maxf(power_hi, powers[pi])

	return {
		"robust": robust,
		"angle": best_angle,
		"power": best_power,
		"bounces": best_bounces,
		"angle_lo": angle_lo,
		"angle_hi": angle_hi,
		"power_lo": power_lo,
		"power_hi": power_hi,
		"by_bounces": by_bounces,
	}


func _print_robust(analysis: Dictionary) -> void:
	var by_bounces: Dictionary = analysis["by_bounces"]
	var spread := PackedStringArray()
	var keys := by_bounces.keys()
	keys.sort()
	for key in keys:
		spread.append("%d sekme x%d" % [key, by_bounces[key]])

	print("  saglam hucre: %d  en kisa rota: aci %.1f deg, guc %.0f, %d sekme" % [
		int(analysis["robust"]), float(analysis["angle"]),
		float(analysis["power"]), int(analysis["bounces"])])
	print("  saglam aralik: aci %.1f..%.1f deg, guc %.0f..%.0f" % [
		float(analysis["angle_lo"]), float(analysis["angle_hi"]),
		float(analysis["power_lo"]), float(analysis["power_hi"])])
	print("  sekme dagilimi: %s" % ", ".join(spread))


# --- Simulasyon (ball.gd ile ayni sira) ---------------------------------------

## [param excluded] atisin BASINDA zaten kirik olan bloklar. Atis sirasinda
## kirilanlar sonuca "broken" bit maskesi olarak doner.
func _simulate(start: Vector2, impulse: Vector2, level: LevelData,
		excluded: Array[RID]) -> Dictionary:
	var play_rect := _arena.get_play_rect()
	var bounds := play_rect.grow(_oob_margin)
	var target_half := _target_size * 0.5

	var pos := start
	var vel: Vector2 = impulse.limit_length(_max_speed)
	var dt := 1.0 / PHYSICS_FPS
	var bounces := 0
	var settle_timer := 0.0
	var broken := 0
	var ignored := excluded.duplicate()
	var broke_this_frame: Array[RID] = []

	for frame in MAX_FRAMES:
		vel.y += _gravity * dt
		vel = vel.limit_length(_max_speed)
		var motion := vel * dt
		broke_this_frame.clear()

		for _step in MAX_SUBSTEPS:
			var hit := _cast(pos, motion, ignored)
			if hit.is_empty():
				pos += motion
				break

			var normal: Vector2 = hit["normal"]
			var fraction: float = hit["fraction"]
			pos = pos + motion * fraction + normal * CONTACT_EPSILON
			bounces += 1

			var rid: RID = hit["rid"]
			if _block_index.has(rid):
				broken |= 1 << int(_block_index[rid])
				if not broke_this_frame.has(rid):
					broke_this_frame.append(rid)

			vel = vel.bounce(normal) * _bounciness
			var along := vel.dot(normal)
			if along < _min_separation:
				vel += normal * (_min_separation - along)
			motion = (motion * (1.0 - fraction)).bounce(normal) * _bounciness

		# Blok, oyundakiyle AYNI anda seffaflasir: BreakableBlock carpismasini
		# set_deferred ile kaldirir, yani top o karenin geri kalaninda blogu
		# hala kati gorur ve ancak sonraki kareden itibaren icinden gecer.
		for rid in broke_this_frame:
			if not ignored.has(rid):
				ignored.append(rid)

		# Hedef algilamasi Area2D gibi kare sonunda yapilir.
		if _circle_hits_target(pos, level.target_position, target_half):
			return {"hit": true, "bounces": bounces, "broken": broken}

		if vel.length() < _settle_speed:
			settle_timer += dt
			if settle_timer >= _settle_time:
				return {"hit": false, "reason": "settled", "bounces": bounces, "broken": broken}
		else:
			settle_timer = 0.0

		if not bounds.has_point(pos):
			return {"hit": false, "reason": "oob", "bounces": bounces, "broken": broken}

	return {"hit": false, "reason": "timeout", "bounces": bounces, "broken": broken}


## launcher.gd'nin nisan onizlemesiyle ayni iki adimli yontem:
## cast_motion ilk temas oranini, get_rest_info o noktadaki normali verir.
func _cast(from: Vector2, motion: Vector2, ignored: Array[RID]) -> Dictionary:
	if motion.is_zero_approx():
		return {}

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _ball_shape
	params.collision_mask = OBSTACLE_LAYER
	params.transform = Transform2D(0.0, from)
	params.motion = motion
	# Kirilmis bloklar gercekten silinmez, sadece sorgudan dislanir; boylece
	# her durum icin dunyayi yeniden kurmaya (ve fizik karesi beklemeye)
	# gerek kalmaz.
	params.exclude = ignored

	var fractions := _space.cast_motion(params)
	if fractions.is_empty() or fractions[0] >= 1.0:
		return {}

	var safe_fraction: float = fractions[0]
	var unsafe_fraction: float = fractions[1]
	params.transform = Transform2D(0.0, from + motion * unsafe_fraction)
	params.motion = Vector2.ZERO
	var rest := _space.get_rest_info(params)
	if rest.is_empty():
		return {}

	return {
		"normal": (rest["normal"] as Vector2).normalized(),
		"fraction": safe_fraction,
		"rid": rest["rid"] as RID,
	}


func _circle_hits_target(center: Vector2, target: Vector2, half: float) -> bool:
	var closest := Vector2(
		clampf(center.x, target.x - half, target.x + half),
		clampf(center.y, target.y - half, target.y + half))
	return center.distance_to(closest) <= _radius
