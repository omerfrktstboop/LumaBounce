extends SceneTree

## GELISTIRME ARACI - oyuna dahil degildir, calisma zamaninda hic yuklenmez.
##
## Her bolum icin aci x guc izgarasini tarar ve hedefe ulasan atislari raporlar.
## Amac "bu bolum cozulebilir mi" sorusunu el hesabiyla degil, GERCEK fizikle
## yanitlamak.
##
## Fizigin tamami LevelSolver'dadir; bu dosya yalnizca DUNYAYI KURAR ve
## SONUCU RAPORLAR. Oyun ici editor/uretec de ayni solver'i kullandigi icin
## iki taraf asla farkli cevap veremez.
##
## IKI MOD:
##   1) Bloksuz bolumler (1-20) - tek atislik izgara taramasi.
##   2) Kirilabilir blogu olan bolumler (21+) - COK ATISLI durum arayisi.
##      Tek atislik model burada yanlis cevap verirdi: bir atisin kirdigi
##      blok sonraki atisin geometrisini kalici olarak degistirir.
##
## Kullanim:
##   godot --headless --path . --script res://tools/verify_levels.gd
##   godot --headless --path . --script res://tools/verify_levels.gd -- --angle-step 1 --power-step 25
##   godot --headless --path . --script res://tools/verify_levels.gd -- --level 21
##   godot --headless --path . --script res://tools/verify_levels.gd -- --level 22 --free-only

## Cok atisli aramada ziyaret edilecek en fazla "kirik blok" durumu.
## Kombinasyon sayisi 2^blok oldugu icin ust sinir sart.
const MAX_BLOCK_STATES := 48
## Cok atisli modda bir rotanin "rahat" sayilmasi icin gereken saglam hucre
## sayisi. Tek bir saglam hucre, kaba izgarada yalnizca ~3 derece x 100 guc
## demektir - teknik olarak "komsulari da isabet ediyor" ama oyuncu icin hala
## tek bir noktayi tutturmak.
const MIN_ROBUST_CELLS := 6
## TASARIM SOZLESMESI: bu bolumden itibaren kirilabilir blok ZORUNLU OLAMAZ.
## Her bolumun hicbir blok kirmadan gecilebilen bir rotasi olmali, yoksa blok
## bir bulmaca parcasi degil anahtar/kapi olur ve oyun brick-breaker'a kayar.
## 21 disaridadir: mekanigi ogreten tek bolum oldugu icin orada blok kirmak
## zorunlu olabilir.
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

var _solver: LevelSolver
var _world: LevelWorld


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
	_solver = LevelSolver.from_scenes()

	print("LumaBounce bolum dogrulayici")
	print("  yaricap=%.0f  yercekimi=%.0f  sekme=%.2f  guc=%.0f..%.0f  aci=+-%.0f" % [
		_solver.radius, _solver.gravity, _solver.bounciness,
		_solver.min_power, _solver.max_power, _solver.max_angle])
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


# --- Dunya kurulumu -----------------------------------------------------------

func _build_world(level: LevelData) -> void:
	_world = LevelWorld.new()
	root.add_child(_world)
	_world.build(level)
	_solver.bind_space(_world.get_space(), _world.get_block_rids())


func _teardown_world() -> void:
	if _world != null:
		_world.queue_free()
		_world = null


# --- Dogrulama ----------------------------------------------------------------

func _verify_level(level: LevelData) -> bool:
	_build_world(level)
	# Yeni gövdelerin fizik uzayina girmesi icin iki kare bekle.
	await physics_frame
	await physics_frame

	var ok := true
	print("--- Bolum %d: %s ---" % [level.level_id, level.display_name])

	ok = _check_static_geometry(level) and ok
	if _world.get_block_count() > 0:
		ok = _check_multi_shot_solvability(level) and ok
	else:
		ok = _check_solvability(level) and ok
	return ok


## Statik yerlesim hatalari: hedef/firlatici bir panelin icinde mi, panel
## uclari hedefe/firlaticiya biniyor mu.
func _check_static_geometry(level: LevelData) -> bool:
	var ok := true
	var spawn := _solver.spawn_position(level.launcher_position)

	if _solver.overlaps_obstacle(level.target_position, _solver.target_size * 0.5):
		print("  HATA: hedef bir panelin/duvarin collision alani icinde.")
		ok = false
	if _solver.overlaps_obstacle(spawn, _solver.radius):
		print("  HATA: topun dogdugu nokta bir panelle cakisiyor.")
		ok = false
	if _solver.overlaps_obstacle(level.launcher_position, 60.0):
		print("  HATA: firlatici govdesi bir panelle cakisiyor.")
		ok = false

	# Hedefin HUD'un arkasina dusmemesi: ust serit ~76 px + safe area payi.
	if level.target_position.y - _solver.target_size * 0.5 < 150.0:
		print("  UYARI: hedef ust HUD seridine cok yakin (y=%.0f)." % level.target_position.y)
		ok = false
	return ok


## Tek atislik dogrulama (bloksuz bolumler).
func _check_solvability(level: LevelData) -> bool:
	var scan := _scan(level, [], _angle_step, _power_step)
	_print_scan_summary(scan)

	if int(scan["hit_count"]) == 0:
		print("  HATA: hicbir atis hedefe ulasmiyor - bolum cozulemez.")
		return false

	var analysis := LevelSolver.analyse_robust(scan)
	if int(analysis["robust"]) == 0:
		print("  UYARI: saglam cozum yok - her isabet tek bir dar aci/guce bagli.")
		return false
	_print_robust(analysis)
	return true


func _scan(level: LevelData, excluded: Array[RID],
		angle_step: float, power_step: float) -> Dictionary:
	return _solver.scan(
		_solver.spawn_position(level.launcher_position),
		level.target_position,
		_world.get_play_rect(),
		excluded, angle_step, power_step)


func _print_scan_summary(scan: Dictionary) -> void:
	var total := int(scan["total"])
	var hit_count := int(scan["hit_count"])
	var reasons: Dictionary = scan["reasons"]
	print("  ornek: %d  isabet: %d (%%%.1f)  en az sekme: %s" % [
		total, hit_count, 100.0 * float(hit_count) / float(maxi(total, 1)),
		str(int(scan["min_bounces"])) if hit_count > 0 else "-"])
	print("  basarisiz: ekran disi=%d, durdu=%d, zaman asimi=%d" % [
		int(reasons["oob"]), int(reasons["settled"]), int(reasons["timeout"])])


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


# --- Cok atisli dogrulama (kirilabilir bloklu bolumler) -----------------------
#
# Neden ayri bir mod: tek atislik model "bu bolum cozulebilir mi" sorusuna
# bloklu bir bolumde YANLIS cevap verir. Ilk atis hicbir zaman hedefe
# ulasamayabilir ama bir blogu kirip ikinci atisin yolunu acabilir.
#
# Durum = hangi bloklarin kirik oldugu (bit maskesi). Blogun kirilmasi
# KALICIDIR (oyunda da atis sifirlamasi bloklari geri getirmez), bu yuzden
# durumlar yalnizca buyur.

func _check_multi_shot_solvability(level: LevelData) -> bool:
	var max_shots := 1 if _free_only else maxi(level.max_lives, 1)
	print("  kirilabilir blok: %d   en fazla atis: %d" % [_world.get_block_count(), max_shots])

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

			var scan := _scan(
				level, _world.rids_for_state(state), _block_angle_step, _block_power_step)
			if int(scan["hit_count"]) > 0:
				solutions.append({
					"shots": depth + 1,
					"state": state,
					"scan": scan,
					"analysis": LevelSolver.analyse_robust(scan),
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
## 2 top" ile "blok kirmadan 1 top" ayni pencereyi paylasir.
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


func _describe_state(state: int) -> String:
	if state == 0:
		return "yok"
	var parts := PackedStringArray()
	for i in 32:
		if state & (1 << i) != 0:
			parts.append(str(i))
	return ", ".join(parts)
