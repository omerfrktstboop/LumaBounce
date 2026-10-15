extends SceneTree

## GELISTIRME ARACI - oyuna dahil degildir.
##
## Her bolum icin bir IPUCU ATISI hesaplar (aci + guc) ve bolum dosyasina
## yazar.
##
## NEDEN CEVRIMDISI: ipucu, solver'in izgara taramasindan gelir - binlerce
## simulasyon. Bunu oyuncu "ipucu" tusuna bastiginda yapmak telefonu
## saniyelerce dondururdu. Burada bir kez hesaplanip .tres'e yazilir; oyun
## calisma aninda yalnizca TEK bir atis simule edip yolunu cizer.
##
## HANGI ATIS SECILIR: LevelSolver.analyse_robust'in "best" hucresi, yani
## saglam (dort komsusu da isabet eden) hucreler arasinda EN AZ SEKMEYLE
## gidenin acisi/gucu. Saglam hucre yok ama isabet varsa, cevresinde en cok
## isabet olan gercek hucre yedek rota secilir. Ipucu ekranda tam yolu cizdigi
## icin bu az sayidaki hassas bolumde de kullanilabilir kalir.
##
## TUGLALI BOLUMLERDE TAM COZUM: eskiden tarama tuglalar KIRILMIS halde
## yapilir ve ipucu yalnizca son atisi bilirdi; oyun tugla kaldikca "once
## bloklari kir" deyip hangi tuglanin nasil kirilacagini gostermezdi. Simdi
## dogrulayicinin durum aramasiyla (durum = kirilmis katman maskesi) en kisa
## kirma zinciri bulunur: her adimin acisi/gucu ve vurdugu tuglalar
## LevelData.hint_break_* dizilerine, hedef durumdan son atis
## hint_angle_degrees/hint_power'a yazilir. Oyun hedef tuglasi saglam olan ilk
## adimi gosterir (bkz. Gameplay._current_hint_step).
##
## Kullanim:
##   godot --headless --path . --script res://tools/compute_hints.gd
##   godot --headless --path . --script res://tools/compute_hints.gd -- --only 42,126
##   godot --headless --path . --script res://tools/compute_hints.gd -- --from 1 --to 50

const ANGLE_STEP := 2.0
const POWER_STEP := 50.0
## Kirma zinciri aramasinin izgarasi - dogrulayicinin blok izgarasiyla ayni.
const PLAN_ANGLE_STEP := 3.0
const PLAN_POWER_STEP := 100.0
## Kaba izgara zincir bulamazsa kullanilan ince izgara (dogrulayicinin tek
## atis izgarasi).
const PLAN_FINE_ANGLE_STEP := 2.0
const PLAN_FINE_POWER_STEP := 50.0
## Son atis haric en fazla bu kadar kirma atisi: max_lives 5'tir.
const PLAN_MAX_BREAKS := 4
## verify_levels.gd'nin MAX_BLOCK_STATES'i ile ayni ust sinir.
const PLAN_MAX_STATES := 96
## Arama, son atisinda en az bu kadar saglam hucre olan ilk (en az kirma
## gerektiren) derinlikte durur. Daha derine inmek ipucunu uzatir.
const PLAN_GOAL_ROBUST := 6

var _from := 1
var _to := 0
var _only: Array[int] = []
var _solver: LevelSolver
var _world: LevelWorld


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
	_run.call_deferred()


func _run() -> void:
	await physics_frame
	_solver = LevelSolver.from_scenes()

	var wanted: Array[int] = _only.duplicate()
	if wanted.is_empty():
		var last := _to if _to > 0 else LevelLibrary.last_level_id()
		for level_id in range(_from, last + 1):
			wanted.append(level_id)

	var written := 0
	var skipped: Array[int] = []
	for level_id in wanted:
		if await _compute(level_id):
			written += 1
		else:
			skipped.append(level_id)

	print("")
	print("OZET yazilan=%d ipucusuz=%d" % [written, skipped.size()])
	if not skipped.is_empty():
		print("ipucu bulunamayan bolumler: %s" % str(skipped))
	# Yayina giren kampanyada ipucusuz bolum kabul edilmez. Arac CI/yerel
	# kontrolde eksigi sessizce gecmesin diye basarisiz cikis kodu verir.
	quit(0 if skipped.is_empty() else 1)


func _compute(level_id: int) -> bool:
	var path := LevelLibrary.level_path(level_id)
	var level := load(path) as LevelData
	if level == null:
		push_warning("compute_hints: %s yuklenemedi." % path)
		return false

	_world = LevelWorld.new()
	root.add_child(_world)
	_world.build(level)
	_solver.apply_level_scale(level)
	_solver.bind_space(_world.get_space(), _world.get_block_rids(), _world.get_obstacles())
	await physics_frame
	await physics_frame

	var spawn := _solver.spawn_position(level.launcher_position)
	var play_rect := _world.get_play_rect()
	# Tuglali bolumde once kirma zinciri aranir; son atis zincirin vardigi
	# durumdan (kalan tuglalar KATI) taranir. Zincir bulunamazsa eski davranis:
	# tum tuglalar kirik halde son atis, kirma adimi yok.
	var excluded: Array[RID] = []
	var plan := {}
	if not level.breakable_blocks.is_empty():
		plan = await _plan_block_solution(level, spawn, play_rect,
			PLAN_ANGLE_STEP, PLAN_POWER_STEP)
		if plan.is_empty():
			# Dar bolumde (or. 149) kaba izgara zinciri kacirabilir; ince
			# izgarayla bir kez daha dene. Bulunamazsa son atis tum tuglalar
			# kirik halde hesaplanir ve kirma adimi yazilmaz.
			print("LEVEL %3d kaba izgarada zincir yok, ince izgara deneniyor" % level_id)
			plan = await _plan_block_solution(level, spawn, play_rect,
				PLAN_FINE_ANGLE_STEP, PLAN_FINE_POWER_STEP)
		var goal_state: int = int(plan["goal_state"]) if not plan.is_empty() \
			else _world.get_all_broken_state()
		excluded = _world.rids_for_state(goal_state)
	# Kaba izgara hizlidir; hic isabet yoksa LevelSolver ayni fizik cekirdeginde
	# 1 derece/50 ve 0.5 derece/25 araliklarina iner. Boylece elle cozulebilen
	# dar bir rota yalnizca iki derecelik orneklerin arasinda kaldi diye ipucu
	# eksik birakilmaz.
	var scan := await _solver.scan_for_solution_async(
		spawn, level.target_position, play_rect, excluded,
		ANGLE_STEP, POWER_STEP, 240)
	var analysis := LevelSolver.analyse_robust(scan)

	root.remove_child(_world)
	_world.queue_free()
	_world = null
	await process_frame

	var selected := _select_hint(scan, analysis)
	if selected.is_empty():
		print("LEVEL %3d ipucu yok (hedefe ulasan hucre bulunamadi)" % level_id)
		return false

	var angle := float(selected["angle"])
	var power := float(selected["power"])
	var break_angles: PackedFloat32Array = plan.get("angles", PackedFloat32Array())
	var break_powers: PackedFloat32Array = plan.get("powers", PackedFloat32Array())
	var break_targets: PackedInt32Array = plan.get("targets", PackedInt32Array())
	if is_equal_approx(level.hint_angle_degrees, angle) \
			and is_equal_approx(level.hint_power, power) \
			and level.hint_break_angles == break_angles \
			and level.hint_break_powers == break_powers \
			and level.hint_break_targets == break_targets:
		print("LEVEL %3d ipucu zaten guncel (aci %.1f, guc %.0f, kirma %d)" % [
			level_id, angle, power, break_angles.size()])
		return true

	level.hint_angle_degrees = angle
	level.hint_power = power
	level.hint_break_angles = break_angles
	level.hint_break_powers = break_powers
	level.hint_break_targets = break_targets
	var error := ResourceSaver.save(level, path)
	if error != OK:
		push_error("compute_hints: %s yazilamadi (%d)" % [path, error])
		return false
	var chain := ""
	for i in break_angles.size():
		chain += " [kir %d: aci %.0f guc %.0f]" % [i + 1, break_angles[i], break_powers[i]]
	print("LEVEL %3d ipucu: aci %.1f deg, guc %.0f  (saglam %d, komsu %d, sekme %d)%s" % [
		level_id, angle, power, int(analysis["robust"]), int(selected["neighbours"]),
		int(selected["bounces"]), chain])
	return true


## Kirma zinciri: genislik oncelikli arama, durum = LevelWorld'un kirilmis
## katman maskesi (dayanikli tuglanin her cani ayri katmandir). Her durum icin
## her hucrenin hangi katmanlari kirdigi ve hedefe ulasip ulasmadigi olculur.
## Ust durum isaretcileri saklanir ki hedef durumdan geriye dogru atis zinciri
## cikarilabilsin (LevelSolver.search_block_states_async bunu saklamaz).
## Donus: {goal_state, angles, powers, targets, robust}; cozum yoksa {}.
func _plan_block_solution(level: LevelData, spawn: Vector2, play_rect: Rect2,
		angle_step: float, power_step: float) -> Dictionary:
	# Katman -> tugla sirasi. LevelWorld._build_blocks ile ayni siralama: her
	# tuglanin her cani icin bir katman, bos kayitlar atlanir.
	var slot_block: Array[int] = []
	for i in level.breakable_blocks.size():
		var data := level.breakable_blocks[i]
		if data == null:
			continue
		for _hit in data.hit_points:
			slot_block.append(i)

	var parents := {0: {}}
	var frontier: Array[int] = [0]
	var visited := 0
	var best_state := -1
	var best_robust := -1
	var best_depth := 999
	for depth in PLAN_MAX_BREAKS + 1:
		var next_frontier: Array[int] = []
		var good_found := false
		for state in frontier:
			if visited >= PLAN_MAX_STATES:
				break
			visited += 1
			var grid := await _scan_state(state, spawn, level.target_position, play_rect,
				angle_step, power_step)
			if int(grid["hit_count"]) > 0:
				var robust := int(LevelSolver.analyse_robust(grid)["robust"])
				if robust > best_robust or (robust == best_robust and depth < best_depth):
					best_state = state
					best_robust = robust
					best_depth = depth
				good_found = good_found or robust >= PLAN_GOAL_ROBUST
			if depth >= PLAN_MAX_BREAKS:
				continue
			var options := _break_options(grid, state)
			for next_state in options:
				if parents.has(next_state):
					continue
				parents[next_state] = {
					"parent": state,
					"angle": float(options[next_state].x),
					"power": float(options[next_state].y),
				}
				next_frontier.append(next_state)
		if good_found or next_frontier.is_empty() or visited >= PLAN_MAX_STATES:
			break
		frontier = next_frontier
	if best_state < 0:
		# Hedef rotasi bu izgarada hicbir durumda gorunmedi (cok dar bolum, or.
		# 149: rota ancak 0.5 derecelik aramada cikiyor). Tugla kirmak genis bir
		# hedeftir; ulasilabilen EN COK kirilmis duruma (tercihen hepsi) giden
		# zincir alinir, son atisi cagiran hassas aramayla o durumdan bulur.
		var most_broken := -1
		for reachable in parents:
			if most_broken < 0 or _popcount(int(reachable)) > _popcount(most_broken):
				most_broken = int(reachable)
		if most_broken <= 0:
			return {}
		best_state = most_broken

	var angles := PackedFloat32Array()
	var powers := PackedFloat32Array()
	var targets := PackedInt32Array()
	var state := best_state
	while state != 0:
		var link: Dictionary = parents[state]
		var parent := int(link["parent"])
		var new_slots := state & ~parent
		var target_mask := 0
		for slot in slot_block.size():
			if new_slots & (1 << slot) != 0:
				target_mask |= 1 << slot_block[slot]
		angles.insert(0, float(link["angle"]))
		powers.insert(0, float(link["power"]))
		targets.insert(0, target_mask)
		state = parent
	return {
		"goal_state": best_state, "angles": angles, "powers": powers,
		"targets": targets, "robust": best_robust,
	}


func _popcount(mask: int) -> int:
	var count := 0
	while mask != 0:
		count += mask & 1
		mask >>= 1
	return count


## Bir durumun izgara taramasi: her hucre icin isabet, sekme ve o atista
## kirilan katmanlar. LevelSolver.analyse_robust ile ayni sozluk bicimi.
func _scan_state(state: int, spawn: Vector2, target: Vector2, play_rect: Rect2,
		angle_step: float, power_step: float) -> Dictionary:
	var angles := _solver.build_angles(angle_step)
	var powers := _solver.build_powers(power_step)
	var excluded := _world.rids_for_state(state)
	var hits: Array = []
	var bounces: Array = []
	var masks: Array = []
	var hit_count := 0
	var sims := 0
	for ai in angles.size():
		var hit_row := []
		var bounce_row := []
		var mask_row := []
		var direction := Vector2.UP.rotated(deg_to_rad(angles[ai]))
		for pi in powers.size():
			var result := _solver.simulate(spawn, direction * powers[pi], target,
				play_rect, excluded)
			var hit := bool(result["hit"])
			hit_row.append(hit)
			bounce_row.append(int(result["bounces"]) if hit else -1)
			mask_row.append(int(result["broken"]))
			if hit:
				hit_count += 1
			sims += 1
			if sims % 240 == 0:
				await process_frame
		hits.append(hit_row)
		bounces.append(bounce_row)
		masks.append(mask_row)
	return {
		"angles": angles, "powers": powers, "hits": hits, "bounces": bounces,
		"masks": masks, "hit_count": hit_count, "total": angles.size() * powers.size(),
	}


## Bu durumdan ulasilabilen her yeni durum icin en SAGLAM kirma atisi:
## ayni yeni duruma goturen dort komsusu en fazla olan hucre (oyuncu ipucu
## rotasini birkac derece kacirsa da ayni tuglayi kirsin). Esitlikte izgara
## merkezine yakin hucre. Donus: {yeni_durum: Vector2(aci, guc)}.
func _break_options(grid: Dictionary, state: int) -> Dictionary:
	var angles: Array[float] = grid["angles"]
	var powers: Array[float] = grid["powers"]
	var masks: Array = grid["masks"]
	var best := {}
	var best_score := {}
	for ai in angles.size():
		for pi in powers.size():
			var next_state := state | int(masks[ai][pi])
			if next_state == state:
				continue
			var neighbours := 0
			for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var na: int = ai + offset.x
				var np: int = pi + offset.y
				if na >= 0 and na < angles.size() and np >= 0 and np < powers.size() \
						and (state | int(masks[na][np])) == next_state:
					neighbours += 1
			var centre := absf(float(ai) - angles.size() * 0.5) \
				+ absf(float(pi) - powers.size() * 0.5)
			var score := float(neighbours) * 1000.0 - centre
			if not best_score.has(next_state) or score > float(best_score[next_state]):
				best_score[next_state] = score
				best[next_state] = Vector2(angles[ai], powers[pi])
	return best


func _select_hint(scan: Dictionary, analysis: Dictionary) -> Dictionary:
	if int(analysis["robust"]) > 0:
		return {
			"angle": float(analysis["angle"]),
			"power": float(analysis["power"]),
			"bounces": int(analysis["bounces"]),
			"neighbours": 4,
		}

	var angles: Array[float] = scan["angles"]
	var powers: Array[float] = scan["powers"]
	var hits: Array = scan["hits"]
	var bounces: Array = scan["bounces"]
	var best := {}
	var best_neighbours := -1
	var best_bounces := 9999
	var best_edge_distance := -1
	for ai in angles.size():
		for pi in powers.size():
			if not bool(hits[ai][pi]):
				continue
			var neighbours := 0
			for da in range(-1, 2):
				for dp in range(-1, 2):
					if da == 0 and dp == 0:
						continue
					var neighbour_ai := ai + da
					var neighbour_pi := pi + dp
					if neighbour_ai >= 0 and neighbour_ai < angles.size() \
							and neighbour_pi >= 0 and neighbour_pi < powers.size() \
							and bool(hits[neighbour_ai][neighbour_pi]):
						neighbours += 1
			var cell_bounces := int(bounces[ai][pi])
			var edge_distance := mini(
				mini(ai, angles.size() - 1 - ai), mini(pi, powers.size() - 1 - pi))
			if neighbours < best_neighbours:
				continue
			if neighbours == best_neighbours and cell_bounces > best_bounces:
				continue
			if neighbours == best_neighbours and cell_bounces == best_bounces \
					and edge_distance <= best_edge_distance:
				continue
			best_neighbours = neighbours
			best_bounces = cell_bounces
			best_edge_distance = edge_distance
			best = {
				"angle": angles[ai],
				"power": powers[pi],
				"bounces": cell_bounces,
				"neighbours": neighbours,
			}
	return best
