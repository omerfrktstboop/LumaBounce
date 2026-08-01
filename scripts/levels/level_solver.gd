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
	var angles := build_angles(angle_step)
	var powers := build_powers(power_step)

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
			var result := simulate(
				spawn, direction * powers[pi], target_position, play_rect, excluded)
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


# --- Simulasyon (ball.gd ile ayni sira) ---------------------------------------

## [param excluded] atisin BASINDA zaten kirik olan bloklar. Atis sirasinda
## kirilanlar sonuca "broken" bit maskesi olarak doner.
func simulate(start: Vector2, impulse: Vector2, target_position: Vector2,
		play_rect: Rect2, excluded: Array[RID]) -> Dictionary:
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

	for _frame in MAX_FRAMES:
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
			pos = pos + motion * fraction + normal * CONTACT_EPSILON
			bounces += 1

			var rid: RID = hit["rid"]
			if _block_index.has(rid):
				broken |= 1 << int(_block_index[rid])
				if not broke_this_frame.has(rid):
					broke_this_frame.append(rid)

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

		# Hedef algilamasi Area2D gibi kare sonunda yapilir.
		if _circle_hits_target(pos, target_position, target_half):
			return {"hit": true, "bounces": bounces, "broken": broken}

		if vel.length() < settle_speed:
			settle_timer += dt
			if settle_timer >= settle_time:
				return {"hit": false, "reason": "settled", "bounces": bounces, "broken": broken}
		else:
			settle_timer = 0.0

		if not bounds.has_point(pos):
			return {"hit": false, "reason": "oob", "bounces": bounces, "broken": broken}

	return {"hit": false, "reason": "timeout", "bounces": bounces, "broken": broken}


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
