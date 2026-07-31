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
## Kullanim:
##   godot --headless --path . --script res://tools/verify_levels.gd
##   godot --headless --path . --script res://tools/verify_levels.gd -- --angle-step 1 --power-step 25

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

var _angle_step := 2.0
var _power_step := 50.0

var _world: Node2D
var _arena: Arena
var _space: PhysicsDirectSpaceState2D
var _ball_shape: CircleShape2D

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


func _run() -> void:
	await physics_frame
	_read_real_constants()

	print("LumaBounce bolum dogrulayici")
	print("  yaricap=%.0f  yercekimi=%.0f  sekme=%.2f  guc=%.0f..%.0f  aci=+-%.0f" % [
		_radius, _gravity, _bounciness, _min_power, _max_power, _max_angle])
	print("  izgara: aci adimi %.2f deg, guc adimi %.0f" % [_angle_step, _power_step])
	print("")

	var failures := 0
	for level_id in range(LevelLibrary.FIRST_LEVEL_ID, LevelLibrary.last_level_id() + 1):
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

	_space = _world.get_world_2d().direct_space_state


func _teardown_world() -> void:
	if _world != null:
		_world.queue_free()
		_world = null
		_arena = null


# --- Dogrulama ----------------------------------------------------------------

func _verify_level(level: LevelData) -> bool:
	_build_world(level)
	# Yeni gövdelerin fizik uzayina girmesi icin iki kare bekle.
	await physics_frame
	await physics_frame

	var ok := true
	print("--- Bolum %d: %s ---" % [level.level_id, level.display_name])

	ok = _check_static_geometry(level) and ok
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


## Aci x guc izgarasini tarar; isabetleri ve "saglam" (komsulari da isabet
## eden) hucreleri raporlar.
func _check_solvability(level: LevelData) -> bool:
	var spawn := level.launcher_position + Vector2.UP * _spawn_offset
	var angles: Array[float] = []
	var powers: Array[float] = []
	var angle := -_max_angle
	while angle <= _max_angle + 0.001:
		angles.append(angle)
		angle += _angle_step
	var power := _min_power
	while power <= _max_power + 0.001:
		powers.append(power)
		power += _power_step

	var hits: Array = []          # [ai][pi] -> bool
	var bounce_counts: Array = [] # [ai][pi] -> int (isabet etmeyenler -1)
	var hit_count := 0
	var min_bounces := 999
	var reasons := {"settled": 0, "oob": 0, "timeout": 0}

	for ai in angles.size():
		var row := []
		var bounce_row := []
		row.resize(powers.size())
		bounce_row.resize(powers.size())
		for pi in powers.size():
			var direction := Vector2.UP.rotated(deg_to_rad(angles[ai]))
			var result := _simulate(spawn, direction * powers[pi], level)
			var did_hit: bool = result["hit"]
			row[pi] = did_hit
			bounce_row[pi] = int(result["bounces"]) if did_hit else -1
			if did_hit:
				hit_count += 1
				min_bounces = mini(min_bounces, int(result["bounces"]))
			else:
				var reason: String = result["reason"]
				reasons[reason] = int(reasons.get(reason, 0)) + 1
		hits.append(row)
		bounce_counts.append(bounce_row)

	var total := angles.size() * powers.size()
	print("  ornek: %d  isabet: %d (%%%.1f)  en az sekme: %s" % [
		total, hit_count, 100.0 * float(hit_count) / float(total),
		str(min_bounces) if hit_count > 0 else "-"])
	print("  basarisiz: ekran disi=%d, durdu=%d, zaman asimi=%d" % [
		reasons["oob"], reasons["settled"], reasons["timeout"]])

	if hit_count == 0:
		print("  HATA: hicbir atis hedefe ulasmiyor - bolum cozulemez.")
		return false

	return _report_robust_window(angles, powers, hits, bounce_counts)


## Cevresi de isabet eden hucreler = piksel hassasiyeti gerektirmeyen cozum.
## Ornek olarak EN AZ sekmeyle biten saglam hucre secilir; bu, oyuncunun
## bulmasi beklenen "ana rota"dir. Cok sekmeli saglam hucreler genelde
## topun ortalikta dolasip sansla hedefe girdigi rotalardir.
func _report_robust_window(angles: Array[float], powers: Array[float],
		hits: Array, bounce_counts: Array) -> bool:
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

	if robust == 0:
		print("  UYARI: saglam cozum yok - her isabet tek bir dar aci/guce bagli.")
		return false

	var spread := PackedStringArray()
	var keys := by_bounces.keys()
	keys.sort()
	for key in keys:
		spread.append("%d sekme x%d" % [key, by_bounces[key]])

	print("  saglam hucre: %d  ana rota: aci %.1f deg, guc %.0f, %d sekme" % [
		robust, best_angle, best_power, best_bounces])
	print("  saglam aralik: aci %.1f..%.1f deg, guc %.0f..%.0f" % [
		angle_lo, angle_hi, power_lo, power_hi])
	print("  sekme dagilimi: %s" % ", ".join(spread))
	return true


# --- Simulasyon (ball.gd ile ayni sira) ---------------------------------------

func _simulate(start: Vector2, impulse: Vector2, level: LevelData) -> Dictionary:
	var play_rect := _arena.get_play_rect()
	var bounds := play_rect.grow(_oob_margin)
	var target_half := _target_size * 0.5

	var pos := start
	var vel: Vector2 = impulse.limit_length(_max_speed)
	var dt := 1.0 / PHYSICS_FPS
	var bounces := 0
	var settle_timer := 0.0

	for frame in MAX_FRAMES:
		vel.y += _gravity * dt
		vel = vel.limit_length(_max_speed)
		var motion := vel * dt

		for _step in MAX_SUBSTEPS:
			var hit := _cast(pos, motion)
			if hit.is_empty():
				pos += motion
				break

			var normal: Vector2 = hit["normal"]
			var fraction: float = hit["fraction"]
			pos = pos + motion * fraction + normal * CONTACT_EPSILON
			bounces += 1

			vel = vel.bounce(normal) * _bounciness
			var along := vel.dot(normal)
			if along < _min_separation:
				vel += normal * (_min_separation - along)
			motion = (motion * (1.0 - fraction)).bounce(normal) * _bounciness

		# Hedef algilamasi Area2D gibi kare sonunda yapilir.
		if _circle_hits_target(pos, level.target_position, target_half):
			return {"hit": true, "bounces": bounces}

		if vel.length() < _settle_speed:
			settle_timer += dt
			if settle_timer >= _settle_time:
				return {"hit": false, "reason": "settled", "bounces": bounces}
		else:
			settle_timer = 0.0

		if not bounds.has_point(pos):
			return {"hit": false, "reason": "oob", "bounces": bounces}

	return {"hit": false, "reason": "timeout", "bounces": bounces}


## launcher.gd'nin nisan onizlemesiyle ayni iki adimli yontem:
## cast_motion ilk temas oranini, get_rest_info o noktadaki normali verir.
func _cast(from: Vector2, motion: Vector2) -> Dictionary:
	if motion.is_zero_approx():
		return {}

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _ball_shape
	params.collision_mask = OBSTACLE_LAYER
	params.transform = Transform2D(0.0, from)
	params.motion = motion

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
	}


func _circle_hits_target(center: Vector2, target: Vector2, half: float) -> bool:
	var closest := Vector2(
		clampf(center.x, target.x - half, target.x + half),
		clampf(center.y, target.y - half, target.y + half))
	return center.distance_to(closest) <= _radius
