class_name LevelSolver
extends RefCounted

## Bir bolumun GERCEKTEN cozulebilir olup olmadigini fizikle olcen cekirdek.
##
## Bu sinif iki yerden kullanilir ve bilerek TEK kopya halinde durur:
##   - tools/verify_levels.gd (headless dogrulama araci)
##   - oyun ici bolum editoru ve uretec
## Fizik burada bir kez yazildigi icin arac ile editorun sonuclari ayrisamaz;
## kopyalanmis bir simulasyon er ya da gec kayar ve "araca gore gecti, oyunda
## gecmiyor" durumunu uretirdi.
##
## Sadakat notlari:
##   - Tum sabitler gercek ball.tscn / launcher.tscn / target.tscn ornekleri
##     olusturulup export'lari OKUNARAK alinir; elle kopyalanmaz.
##   - Carpisma testi launcher.gd'nin nisan onizlemesiyle ayni yontemi
##     kullanir: cast_motion + get_rest_info (CircleShape2D supurmesi).
##   - Entegrasyon sirasi ball.gd ile birebir aynidir:
##     yercekimi -> hiz sinirlama -> hareket -> sekme -> ayrilma itmesi.
##
## Tek fark: move_and_collide'in safe_margin depenetrasyonu birebir taklit
## edilmez (temas sonrasi normal yonunde kucuk sabit bir itme kullanilir).
## Bu yuzden sonuclar "cok yakin yaklasim"dir, bit-bit ayni degildir.

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

# Gercek sahnelerden okunan fizik sabitleri.
var radius := 24.0
var gravity := 1500.0
var bounciness := 0.94
var min_separation := 60.0
var max_speed := 3000.0
var settle_speed := 80.0
var settle_time := 0.85
var oob_margin := 240.0
var min_power := 900.0
var max_power := 2300.0
var max_angle := 78.0
var spawn_offset := 70.0
var target_size := 92.0

var _space: PhysicsDirectSpaceState2D
var _ball_shape: CircleShape2D
## Kirilabilir blok govdesinin RID'i -> LevelData.breakable_blocks indeksi.
var _block_index: Dictionary = {}


## Sabitleri gercek sahnelerden okur. Dugumler agaca EKLENMEZ - export
## degerleri instantiate() aninda uygulanir, _ready() calistirmaya gerek yok.
static func from_scenes() -> LevelSolver:
	var solver := LevelSolver.new()

	var ball := (load("res://scenes/ball.tscn") as PackedScene).instantiate() as Ball
	solver.radius = ball.radius
	solver.gravity = ball.gravity
	solver.bounciness = ball.bounciness
	solver.min_separation = ball.min_separation_speed
	solver.max_speed = ball.max_speed
	solver.settle_speed = ball.settle_speed
	solver.settle_time = ball.settle_time
	solver.oob_margin = ball.out_of_bounds_margin
	ball.free()

	var launcher := (load("res://scenes/launcher.tscn") as PackedScene).instantiate() as Launcher
	solver.min_power = launcher.min_power
	solver.max_power = launcher.max_power
	solver.max_angle = launcher.max_aim_angle_deg
	solver.spawn_offset = launcher.ball_spawn_offset
	launcher.free()

	var target := (load("res://scenes/target.tscn") as PackedScene).instantiate() as Target
	solver.target_size = target.size
	target.free()

	solver._ball_shape = CircleShape2D.new()
	solver._ball_shape.radius = solver.radius
	return solver


## Hangi fizik uzayinda calisilacagi ve o uzaydaki kirilabilir bloklarin
## kimligi. [param block_rids] bos verilebilir (bloksuz bolum).
func bind_space(space: PhysicsDirectSpaceState2D, block_rids: Dictionary = {}) -> void:
	_space = space
	_block_index = block_rids


func spawn_position(launcher_position: Vector2) -> Vector2:
	return launcher_position + Vector2.UP * spawn_offset


# --- Izgara -------------------------------------------------------------------

func build_angles(step: float) -> Array[float]:
	var angles: Array[float] = []
	var angle := -max_angle
	while angle <= max_angle + 0.001:
		angles.append(angle)
		angle += maxf(step, 0.25)
	return angles


func build_powers(step: float) -> Array[float]:
	var powers: Array[float] = []
	var power := min_power
	while power <= max_power + 0.001:
		powers.append(power)
		power += maxf(step, 5.0)
	return powers


# --- Tarama -------------------------------------------------------------------

## Verilen "kirik blok" durumundan tum aci x guc izgarasini tarar.
## [param excluded] o durumda ARTIK OLMAYAN bloklarin RID'leridir.
func scan(spawn: Vector2, target_position: Vector2, play_rect: Rect2,
		excluded: Array[RID], angle_step: float, power_step: float) -> Dictionary:
	var state := _create_scan_state(angle_step, power_step)
	for ai in state["angles"].size():
		for pi in state["powers"].size():
			_scan_cell(state, ai, pi, spawn, target_position, play_rect, excluded)
	return state


## scan() ile ayni sonucu ayni simulate() cekirdeginden uretir, fakat uzun
## izgarayi karelere boler. AI generator bunu kullanir; verifier'in senkron
## scan() sozlesmesi degismez.
func scan_async(spawn: Vector2, target_position: Vector2, play_rect: Rect2,
		excluded: Array[RID], angle_step: float, power_step: float,
		sims_per_frame := 120, cancel_check := Callable()) -> Dictionary:
	var state := _create_scan_state(angle_step, power_step)
	var frame_budget := 0
	for ai in state["angles"].size():
		for pi in state["powers"].size():
			if cancel_check.is_valid() and bool(cancel_check.call()):
				state["cancelled"] = true
				return state
			_scan_cell(state, ai, pi, spawn, target_position, play_rect, excluded)
			frame_budget += 1
			if frame_budget >= maxi(sims_per_frame, 1):
				frame_budget = 0
				var tree := Engine.get_main_loop() as SceneTree
				if tree != null:
					await tree.process_frame
	state["cancelled"] = false
	return state


func _create_scan_state(angle_step: float, power_step: float) -> Dictionary:
	var angles := build_angles(angle_step)
	var powers := build_powers(power_step)
	var hits: Array = []
	var bounce_counts: Array = []
	for _ai in angles.size():
		var row := []
		var bounce_row := []
		row.resize(powers.size())
		bounce_row.resize(powers.size())
		hits.append(row)
		bounce_counts.append(bounce_row)
	return {
		"angles": angles,
		"powers": powers,
		"hits": hits,
		"bounces": bounce_counts,
		"total": angles.size() * powers.size(),
		"hit_count": 0,
		"min_bounces": 999,
		"reasons": {"settled": 0, "oob": 0, "timeout": 0},
		"reached": {},
	}


func _scan_cell(state: Dictionary, ai: int, pi: int, spawn: Vector2,
		target_position: Vector2, play_rect: Rect2, excluded: Array[RID]) -> void:
	var angles: Array[float] = state["angles"]
	var powers: Array[float] = state["powers"]
	var direction := Vector2.UP.rotated(deg_to_rad(angles[ai]))
	var result := simulate(spawn, direction * powers[pi], target_position, play_rect, excluded)
	var did_hit: bool = result["hit"]
	state["hits"][ai][pi] = did_hit
	state["bounces"][ai][pi] = int(result["bounces"]) if did_hit else -1
	if did_hit:
		state["hit_count"] = int(state["hit_count"]) + 1
		state["min_bounces"] = mini(int(state["min_bounces"]), int(result["bounces"]))
	else:
		var reason: String = result["reason"]
		state["reasons"][reason] = int(state["reasons"].get(reason, 0)) + 1
	var broken := int(result["broken"])
	if broken != 0 and not state["reached"].has(broken):
		state["reached"][broken] = "aci %.1f deg, guc %.0f" % [angles[ai], powers[pi]]


## Cevresi de isabet eden hucreler = piksel hassasiyeti gerektirmeyen cozum.
## Ornek olarak EN AZ sekmeyle biten saglam hucre secilir; bu, oyuncunun
## bulmasi beklenen "ana rota"dir. Cok sekmeli saglam hucreler genelde
## topun ortalikta dolasip sansla hedefe girdigi rotalardir.
static func analyse_robust(scan_result: Dictionary) -> Dictionary:
	var angles: Array[float] = scan_result["angles"]
	var powers: Array[float] = scan_result["powers"]
	var hits: Array = scan_result["hits"]
	var bounce_counts: Array = scan_result["bounces"]

	var robust := 0
	var best_angle := 0.0
	var best_power := 0.0
	var best_bounces := 9999
	var angle_lo := 999.0
	var angle_hi := -999.0
	var power_lo := 99999.0
	var power_hi := -99999.0
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


## Saglam hucreleri 4-komsu baglantili rota kumelerine ayirir. Overlay ve
## "iki alternatif rota" degerlendirmesi ayni tarama sonucunu kullanir.
static func analyse_solution_clusters(scan_result: Dictionary) -> Array[Dictionary]:
	var angles: Array[float] = scan_result["angles"]
	var powers: Array[float] = scan_result["powers"]
	var hits: Array = scan_result["hits"]
	var bounce_counts: Array = scan_result["bounces"]
	var robust_map: Array = []
	for _ai in angles.size():
		var robust_row := []
		robust_row.resize(powers.size())
		robust_row.fill(false)
		robust_map.append(robust_row)
	for ai in range(1, angles.size() - 1):
		for pi in range(1, powers.size() - 1):
			robust_map[ai][pi] = _is_robust_cell(hits, ai, pi)

	var clusters: Array[Dictionary] = []
	var visited := {}
	var neighbour_offsets: Array[Vector2i] = [
		Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for ai in angles.size():
		for pi in powers.size():
			var start_key := ai * powers.size() + pi
			if not robust_map[ai][pi] or visited.has(start_key):
				continue
			var queue: Array[Vector2i] = [Vector2i(ai, pi)]
			visited[start_key] = true
			var cells: Array[Vector2i] = []
			while not queue.is_empty():
				var cell: Vector2i = queue.pop_front()
				cells.append(cell)
				for offset in neighbour_offsets:
					var neighbour: Vector2i = cell + offset
					if (neighbour.x < 0 or neighbour.x >= angles.size()
							or neighbour.y < 0 or neighbour.y >= powers.size()):
						continue
					var neighbour_key: int = neighbour.x * powers.size() + neighbour.y
					if robust_map[neighbour.x][neighbour.y] and not visited.has(neighbour_key):
						visited[neighbour_key] = true
						queue.append(neighbour)
			clusters.append(_describe_cluster(cells, angles, powers, bounce_counts))
	clusters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["robust"]) != int(b["robust"]):
			return int(a["robust"]) > int(b["robust"])
		return int(a["bounces"]) < int(b["bounces"]))
	return clusters


static func _is_robust_cell(hits: Array, ai: int, pi: int) -> bool:
	return (hits[ai][pi] and hits[ai - 1][pi] and hits[ai + 1][pi]
		and hits[ai][pi - 1] and hits[ai][pi + 1])


static func _describe_cluster(cells: Array[Vector2i], angles: Array[float],
		powers: Array[float], bounce_counts: Array) -> Dictionary:
	var best := cells[0]
	var best_bounces := int(bounce_counts[best.x][best.y])
	var angle_lo := INF
	var angle_hi := -INF
	var power_lo := INF
	var power_hi := -INF
	for cell in cells:
		var cell_bounces := int(bounce_counts[cell.x][cell.y])
		if cell_bounces < best_bounces:
			best = cell
			best_bounces = cell_bounces
		angle_lo = minf(angle_lo, angles[cell.x])
		angle_hi = maxf(angle_hi, angles[cell.x])
		power_lo = minf(power_lo, powers[cell.y])
		power_hi = maxf(power_hi, powers[cell.y])
	return {
		"robust": cells.size(),
		"angle": angles[best.x],
		"power": powers[best.y],
		"bounces": best_bounces,
		"angle_lo": angle_lo,
		"angle_hi": angle_hi,
		"power_lo": power_lo,
		"power_hi": power_hi,
	}


# --- Simulasyon (ball.gd ile ayni sira) ---------------------------------------

## [param excluded] atisin BASINDA zaten kirik olan bloklar. Atis sirasinda
## kirilanlar sonuca "broken" bit maskesi olarak doner.
func simulate(start: Vector2, impulse: Vector2, target_position: Vector2,
		play_rect: Rect2, excluded: Array[RID], capture_trace := false) -> Dictionary:
	var bounds := play_rect.grow(oob_margin)
	var target_half := target_size * 0.5

	var pos := start
	var vel: Vector2 = impulse.limit_length(max_speed)
	var dt := 1.0 / PHYSICS_FPS
	var bounces := 0
	var settle_timer := 0.0
	var broken := 0
	var ignored := excluded.duplicate()
	var broke_this_frame: Array[RID] = []
	var trace_points := PackedVector2Array()
	var collision_points: Array[Dictionary] = []
	var broken_order := PackedInt32Array()
	if capture_trace:
		trace_points.append(pos)

	for frame_index in MAX_FRAMES:
		vel.y += gravity * dt
		vel = vel.limit_length(max_speed)
		var motion := vel * dt
		broke_this_frame.clear()

		for _step in MAX_SUBSTEPS:
			var hit := cast(pos, motion, ignored)
			if hit.is_empty():
				pos += motion
				break

			var normal: Vector2 = hit["normal"]
			var fraction: float = hit["fraction"]
			var collision_position := pos + motion * fraction
			pos = pos + motion * fraction + normal * CONTACT_EPSILON
			bounces += 1

			var rid: RID = hit["rid"]
			var block_index := -1
			if _block_index.has(rid):
				block_index = int(_block_index[rid])
				broken |= 1 << block_index
				if capture_trace and not broken_order.has(block_index):
					broken_order.append(block_index)
				if not broke_this_frame.has(rid):
					broke_this_frame.append(rid)
			if capture_trace:
				trace_points.append(collision_position)
				collision_points.append({
					"position": collision_position,
					"normal": normal,
					"block_index": block_index,
				})

			vel = vel.bounce(normal) * bounciness
			var along := vel.dot(normal)
			if along < min_separation:
				vel += normal * (min_separation - along)
			motion = (motion * (1.0 - fraction)).bounce(normal) * bounciness

		# Blok, oyundakiyle AYNI anda seffaflasir: BreakableBlock carpismasini
		# set_deferred ile kaldirir, yani top o karenin geri kalaninda blogu
		# hala kati gorur ve ancak sonraki kareden itibaren icinden gecer.
		for rid in broke_this_frame:
			if not ignored.has(rid):
				ignored.append(rid)
		if capture_trace and frame_index % 3 == 0:
			trace_points.append(pos)

		# Hedef algilamasi Area2D gibi kare sonunda yapilir.
		if _circle_hits_target(pos, target_position, target_half):
			return _simulation_result(true, "", bounces, broken, pos,
				trace_points, collision_points, broken_order, capture_trace)

		if vel.length() < settle_speed:
			settle_timer += dt
			if settle_timer >= settle_time:
				return _simulation_result(false, "settled", bounces, broken, pos,
					trace_points, collision_points, broken_order, capture_trace)
		else:
			settle_timer = 0.0

		if not bounds.has_point(pos):
			return _simulation_result(false, "oob", bounces, broken, pos,
				trace_points, collision_points, broken_order, capture_trace)

	return _simulation_result(false, "timeout", bounces, broken, pos,
		trace_points, collision_points, broken_order, capture_trace)


func _simulation_result(hit: bool, reason: String, bounces: int, broken: int,
		end_position: Vector2, trace_points: PackedVector2Array,
		collision_points: Array[Dictionary], broken_order: PackedInt32Array,
		capture_trace: bool) -> Dictionary:
	var result := {"hit": hit, "bounces": bounces, "broken": broken}
	if not hit:
		result["reason"] = reason
	if capture_trace:
		if trace_points.is_empty() or trace_points[-1].distance_to(end_position) > 0.5:
			trace_points.append(end_position)
		result["trace_points"] = trace_points
		result["collision_points"] = collision_points
		result["broken_order"] = broken_order
		result["target_hit_position"] = end_position if hit else Vector2.ZERO
	return result


## launcher.gd'nin nisan onizlemesiyle ayni iki adimli yontem:
## cast_motion ilk temas oranini, get_rest_info o noktadaki normali verir.
func cast(from: Vector2, motion: Vector2, ignored: Array[RID]) -> Dictionary:
	if motion.is_zero_approx():
		return {}

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _ball_shape
	params.collision_mask = OBSTACLE_LAYER
	params.transform = Transform2D(0.0, from)
	params.motion = motion
	# Kirilmis bloklar gercekten silinmez, sadece sorgudan dislanir; boylece
	# her durum icin dunyayi yeniden kurmaya gerek kalmaz.
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


## Verilen noktada engel var mi (hedef/firlatici panele gomulmus mu testi).
func overlaps_obstacle(at: Vector2, probe_radius: float) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = probe_radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.collision_mask = OBSTACLE_LAYER
	params.transform = Transform2D(0.0, at)
	return not _space.intersect_shape(params, 1).is_empty()


func _circle_hits_target(center: Vector2, target: Vector2, half: float) -> bool:
	var closest := Vector2(
		clampf(center.x, target.x - half, target.x + half),
		clampf(center.y, target.y - half, target.y + half))
	return center.distance_to(closest) <= radius
