extends SceneTree

const AUDIO_AUTOLOAD := "autoload/AudioManager"

var _passed := 0
var _failed := 0
var _owned_audio_manager: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_register_audio_manager()
	_test_data_and_geometry()
	await _test_world_and_solver()
	await _test_gameplay_bomb()
	_test_laser_pulse()
	await _test_gameplay_laser()
	await _test_real_obstacle_motion()
	await _test_mechanic_intro_card()
	_test_resource_roundtrip()
	_test_ai_mapping()
	_test_generation_contract()
	_test_official_obstacle_levels()
	await _unregister_audio_manager()
	print("ENGEL TESTI: %d gecti, %d kaldi." % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_data_and_geometry() -> void:
	var ring := _ring(Vector2(360.0, 600.0))
	_check("halka verisi gecerli", ring.validate(0).is_empty(), true)
	var ring_shapes := ObstacleGeometry.all_shapes([ring], 0.0)
	_check("halka merkezi bos", ObstacleGeometry.overlaps_circle(
		Vector2(360.0, 600.0), 20.0, ring_shapes), false)
	_check("halka cemberi kati", ObstacleGeometry.overlaps_circle(
		Vector2(430.0, 600.0), 20.0, ring_shapes), true)

	var mover := _mover(Vector2(360.0, 600.0))
	var start_shapes := ObstacleGeometry.dynamic_shapes([mover], 0.0)
	var later_shapes := ObstacleGeometry.dynamic_shapes([mover], mover.motion_period * 0.25)
	_check("kayan engel zamanla tasiniyor",
		(start_shapes[0]["center"] as Vector2).distance_to(later_shapes[0]["center"]) > 80.0,
		true)

	var bomb := _bomb(Vector2(360.0, 600.0))
	var hazard := ObstacleGeometry.cast_circle(
		Vector2(360.0, 760.0), Vector2(0.0, -260.0), 24.0,
		ObstacleGeometry.hazard_shapes([bomb]))
	_check("bomba supurme testi", String(hazard.get("hazard_reason", "")), "bomb")


## LevelSolver'in analitik hareket matematigini _test_data_and_geometry() zaten
## dogruluyor, ama bu ObstacleField/LevelObstacle'in GERCEK oyun govdesini
## (AnimatableBody2D + gercek _physics_process tik'leri) hic calistirmiyor. Bu
## test o bosluu kapatiyor: gercek dugumleri kurup gercek fizik karesi
## bekleyerek MotionRoot'un konumunun/donusunun GERCEKTEN degistigini olcuyor -
## "donen cark/kayan bariyer hareket etmiyor" turu bir regresyon artik burada
## sessizce gecemez.
func _test_real_obstacle_motion() -> void:
	var holder := Node2D.new()
	get_root().add_child(holder)

	var bar := _mover(Vector2(300.0, 500.0))
	var wheel := _wheel(Vector2(500.0, 500.0))
	var field := ObstacleField.new()
	holder.add_child(field)
	field.build([bar, wheel])
	field.start_motion()
	await physics_frame

	var bar_node: LevelObstacle = field.get_obstacle_node(0)
	var wheel_node: LevelObstacle = field.get_obstacle_node(1)
	var bar_root: Node2D = bar_node.get_node("MotionRoot")
	var wheel_root: Node2D = wheel_node.get_node("MotionRoot")
	var bar_start := bar_root.position
	var wheel_start := wheel_root.rotation

	for i in 30:
		await physics_frame

	_check("gercek kayan bariyer govdesi zamanla hareket ediyor",
		bar_root.position.distance_to(bar_start) > 20.0, true)
	_check("gercek donen cark govdesi zamanla donuyor",
		not is_equal_approx(wheel_root.rotation, wheel_start), true)

	holder.queue_free()
	await process_frame


## Tanitim karti bir KURALI ogretir, bu yuzden kendiliginden kaybolmamali ve
## her mekanik icin gercekten bir gosterim kurmali. Kart bozulursa oyuncu yeni
## bir engelle hicbir aciklama gormeden karsilasir - sessizce kaybolan bir
## regresyon oldugu icin burada acikca olculur.
## NOT - kart neden TIPSIZ yukleniyor: kartin "Anladım" butonu LumaButton'dir,
## LumaButton ise AudioManager'a bakar. `--script` ile ozel bir ana dongu
## calistirildiginda Godot autoload'lari kurmaz; bu dosya MechanicIntroCard
## tipini STATIK olarak anarsa zincir derleme zamaninda AudioManager'a takilir
## ve kart bos bir Button ile yuklenir. Bu yuzden sahne yalnizca calisma
## zamaninda, tipsiz bir Node olarak alinir (ayni gerekce icin bkz.
## check_blocks_and_gate.gd dosya basi).
func _test_mechanic_intro_card() -> void:
	var card: Node = (
		load("res://scenes/mechanic_intro_card.tscn") as PackedScene).instantiate()
	get_root().add_child(card)
	await process_frame

	_check("kart baslangicta kapali", card.call("is_open"), false)

	var stage: Node2D = card.get_node(
		"CardCenter/Card/Margin/Rows/StageFrame/StageViewport/SubViewport/StageRoot")

	# Her engel turu icin: kart acilmali, baslik/aciklama dolmali ve sahnede
	# gercek bir gosterim (engel + top) kurulmali.
	for kind in [ObstacleData.Kind.METAL_RING, ObstacleData.Kind.BOMB,
			ObstacleData.Kind.ROTATING_WHEEL, ObstacleData.Kind.MOVING_BAR]:
		card.call("show_obstacle", kind)
		await process_frame
		var title: Label = card.get_node("CardCenter/Card/Margin/Rows/Title")
		var description: Label = card.get_node("CardCenter/Card/Margin/Rows/Description")
		_check("engel %d karti aciliyor" % kind, card.call("is_open"), true)
		_check("engel %d karti baslik gosteriyor" % kind, title.text.is_empty(), false)
		_check("engel %d karti aciklama gosteriyor" % kind, description.text.is_empty(), false)
		_check("engel %d gosteriminde gercek engel var" % kind,
			_find_child_of_type(stage, "LevelObstacle") != null, true)
		_check("engel %d gosteriminde top var" % kind,
			stage.get_node_or_null("DemoBall") != null, true)

	# Kart MODAL: nisan almak onu kapatmamali, yalnizca close()/buton kapatir.
	var dismiss_count := [0]
	card.dismissed.connect(func() -> void: dismiss_count[0] += 1)
	card.call("close")
	await process_frame
	_check("kart kapaniyor", card.call("is_open"), false)
	_check("kapaninca dismissed yayiliyor", dismiss_count[0], 1)
	_check("kapali kartta gosterim temizleniyor", stage.get_child_count(), 0)
	card.call("close")
	_check("ikinci close() tekrar sinyal yaymiyor", dismiss_count[0], 1)

	# Tugla gosterimi: iki dayaniklilik seviyesi YAN YANA olmali - renk farki
	# ancak boyle ogretilebilir (bkz. Palette.SURFACE_BLOCK_STRONG).
	card.call("show_block_mechanic")
	await process_frame
	var tiers := {}
	for child in stage.get_children():
		var brick := child as BreakableBlock
		if brick != null:
			tiers[brick.hit_points] = true
	_check("tugla gosteriminde tek darbelik tugla var", tiers.has(1), true)
	_check("tugla gosteriminde iki darbelik tugla var", tiers.has(2), true)

	card.queue_free()
	await process_frame


func _find_child_of_type(parent: Node, type_name: String) -> Node:
	for child in parent.get_children():
		if child.is_class(type_name) or child.get_script() != null \
				and child.get_script().get_global_name() == type_name:
			return child
	return null


func _test_world_and_solver() -> void:
	var holder := Node2D.new()
	get_root().add_child(holder)
	var world := LevelWorld.new()
	holder.add_child(world)
	var level := LevelData.new()
	level.obstacles = [_ring(Vector2(360.0, 600.0)), _wheel(Vector2(220.0, 760.0))]
	world.build(level)
	await physics_frame
	await physics_frame
	var solver := LevelSolver.from_scenes()
	solver.bind_space(world.get_space(), world.get_block_rids(), world.get_obstacles())
	_check("solver halka merkezini bos goruyor",
		solver.overlaps_obstacle(Vector2(360.0, 600.0), 20.0), false)
	_check("solver halka kenarini kati goruyor",
		solver.overlaps_obstacle(Vector2(430.0, 600.0), 20.0), true)
	holder.queue_free()
	await process_frame


func _test_gameplay_bomb() -> void:
	var level := LevelData.new()
	level.level_id = 1
	level.launcher_position = Vector2(360.0, 1120.0)
	level.target_position = Vector2(120.0, 260.0)
	level.max_lives = 5
	level.obstacles = [_bomb(Vector2(360.0, 930.0))]
	var gameplay: Node = (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	gameplay.level_data = level
	get_root().add_child(gameplay)
	await process_frame
	gameplay.call("_on_shot_fired", Vector2.UP * 1100.0)
	for _frame in 30:
		await physics_frame
		var frame_snapshot: Dictionary = gameplay.call("get_debug_snapshot")
		if String(frame_snapshot["last_failure_reason"]) == "bomb":
			break
	var snapshot: Dictionary = gameplay.call("get_debug_snapshot")
	_check("gameplay bomba nedeni", String(snapshot["last_failure_reason"]), "bomb")
	_check("bomba tek hak dusuruyor", int(snapshot["lives_remaining"]), 4)
	gameplay.queue_free()
	await process_frame


## Lazerin ZAMANLAMA sozlesmesi. Bu testin asil isi, oyunun ve solver'in
## isini AYNI anda acik saymasini korumak: kaysalar "editorde gecti, oyunda
## carpti" olurdu ve bir daha kimse fark etmezdi.
func _test_laser_pulse() -> void:
	var laser := ObstacleData.new()
	laser.kind = ObstacleData.Kind.PULSE_LASER
	laser.position = Vector2(360.0, 620.0)
	laser.size = Vector2(300.0, 16.0)
	laser.motion_period = 3.0
	laser.pulse_on_ratio = 0.667

	_check("lazer dogrulamadan geciyor", laser.validate(0).size(), 0)
	_check("t=0 isin acik", laser.laser_is_active(0.0), true)
	_check("t=1.9 isin acik", laser.laser_is_active(1.9), true)
	_check("t=2.1 isin kapali", laser.laser_is_active(2.1), false)
	_check("t=2.9 isin kapali", laser.laser_is_active(2.9), false)
	_check("t=3.1 dongu bastan basliyor", laser.laser_is_active(3.1), true)

	# Faz kaydirmasi olmasa ayni bolumdeki iki lazer birlikte yanip sonerdi;
	# o zaman ikisi tek bir kalin lazerden farksiz olurdu.
	var shifted := ObstacleData.new()
	shifted.kind = ObstacleData.Kind.PULSE_LASER
	shifted.motion_period = 3.0
	shifted.pulse_on_ratio = 0.667
	shifted.phase_degrees = 180.0
	_check("faz kaydirilmis lazer farkli durumda",
		shifted.laser_is_active(2.1) != laser.laser_is_active(2.1), true)

	# Tehlike sekli YALNIZCA acikken uretilmeli - solver bunu okuyor.
	var arr: Array[ObstacleData] = [laser]
	_check("acikken tehlike sekli var",
		ObstacleGeometry.hazard_shapes(arr, 0.5).size(), 1)
	_check("kapaliyken tehlike sekli yok",
		ObstacleGeometry.hazard_shapes(arr, 2.5).size(), 0)
	_check("tehlike sebebi laser", String(
		ObstacleGeometry.hazard_shapes(arr, 0.5)[0]["hazard_reason"]), "laser")
	# Isin bir DUVAR degil: cark/bariyer gibi kati sekiller listesine girmemeli,
	# yoksa top sonuk isinden sekerdi.
	_check("isin kati sekil uretmiyor",
		ObstacleGeometry.dynamic_shapes(arr, 0.5).size(), 0)

	# Surekli acik bir lazer zamanlama bulmacasi degil duvardir.
	var always_on := ObstacleData.new()
	always_on.kind = ObstacleData.Kind.PULSE_LASER
	always_on.size = Vector2(300.0, 16.0)
	always_on.pulse_on_ratio = 0.95
	_check("surekli acik lazer dogrulamadan KALIYOR",
		always_on.validate(0).size() > 0, true)


## Gercek oynanista isin ACIKKEN oldurur, SONUKKEN oldurmez.
##
## Iki atis ayni geometride yapilir; tek fark isinin o andaki durumudur.
func _test_gameplay_laser() -> void:
	for expect_hit in [true, false]:
		var level := LevelData.new()
		level.level_id = 1
		level.launcher_position = Vector2(360.0, 1120.0)
		level.target_position = Vector2(120.0, 260.0)
		level.max_lives = 5
		var laser := ObstacleData.new()
		laser.kind = ObstacleData.Kind.PULSE_LASER
		laser.position = Vector2(360.0, 930.0)
		laser.size = Vector2(420.0, 18.0)
		laser.motion_period = 4.0
		laser.pulse_on_ratio = 0.5
		# phase 180 => atis basinda isin SONUK; 0 => acik.
		laser.phase_degrees = 0.0 if expect_hit else 180.0
		level.obstacles = [laser] as Array[ObstacleData]

		var gameplay: Node = (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
		gameplay.level_data = level
		get_root().add_child(gameplay)
		await process_frame
		gameplay.call("_on_shot_fired", Vector2.UP * 1100.0)
		for _frame in 24:
			await physics_frame
			var snap: Dictionary = gameplay.call("get_debug_snapshot")
			if String(snap["last_failure_reason"]) == "laser":
				break
		var snapshot: Dictionary = gameplay.call("get_debug_snapshot")
		var label := "isin ACIKKEN" if expect_hit else "isin SONUKKEN"
		_check("%s top vuruluyor mu" % label,
			String(snapshot["last_failure_reason"]) == "laser", expect_hit)
		gameplay.queue_free()
		await process_frame


func _register_audio_manager() -> void:
	if Engine.has_singleton("AudioManager"):
		return
	var path := String(ProjectSettings.get_setting(AUDIO_AUTOLOAD, "")).trim_prefix("*")
	var script := load(path) as GDScript
	if script == null:
		push_error("AudioManager yuklenemedi: %s" % path)
		return
	var node := script.new() as Node
	node.name = "AudioManager"
	root.add_child(node)
	Engine.register_singleton("AudioManager", node)
	_owned_audio_manager = node


func _unregister_audio_manager() -> void:
	if _owned_audio_manager == null:
		return
	_owned_audio_manager.call("stop_transient_sounds")
	await create_timer(0.1).timeout
	Engine.unregister_singleton("AudioManager")
	root.remove_child(_owned_audio_manager)
	_owned_audio_manager.free()
	_owned_audio_manager = null


func _test_resource_roundtrip() -> void:
	var path := "user://obstacle_roundtrip_test.tres"
	var level := LevelData.new()
	level.obstacles = [
		_ring(Vector2(200.0, 500.0)), _bomb(Vector2(500.0, 500.0)),
		_wheel(Vector2(240.0, 760.0)), _mover(Vector2(480.0, 760.0)),
	]
	_check("engel kaydi", ResourceSaver.save(level, path), OK)
	var loaded := ResourceLoader.load(path, "LevelData", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	_check("dort engel geri yuklendi", loaded.obstacles.size(), 4)
	_check("hareket suresi korundu", loaded.obstacles[3].motion_period, 2.8)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# Lazerin zamanlama alanlari da diske gidip geri gelmeli: biri kaybolursa
	# bolum kaydedildikten sonra baska bir ritimle oynanir ve dogrulama yalan
	# soyler.
	var laser_level := LevelData.new()
	var laser := ObstacleData.new()
	laser.kind = ObstacleData.Kind.PULSE_LASER
	laser.position = Vector2(300.0, 600.0)
	laser.size = Vector2(280.0, 15.0)
	laser.motion_period = 2.4
	laser.pulse_on_ratio = 0.42
	laser.phase_degrees = 137.0
	laser_level.obstacles = [laser] as Array[ObstacleData]
	_check("lazer kaydi", ResourceSaver.save(laser_level, path), OK)
	var laser_back := ResourceLoader.load(
		path, "LevelData", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	_check("lazer turu korundu", laser_back.obstacles[0].kind,
		ObstacleData.Kind.PULSE_LASER)
	_check("lazer dongusu korundu", laser_back.obstacles[0].motion_period, 2.4)
	_check("lazer acik orani korundu", laser_back.obstacles[0].pulse_on_ratio, 0.42)
	_check("lazer fazi korundu", laser_back.obstacles[0].phase_degrees, 137.0)
	_check("geri yuklenen lazer ayni ritmi veriyor",
		laser_back.obstacles[0].laser_is_active(1.1), laser.laser_is_active(1.1))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_ai_mapping() -> void:
	var raw := {
		"display_name": "Engel AI",
		"launcher": {"x": 360, "y": 1120},
		"target": {"x": 420, "y": 300},
		"panels": [], "blocks": [],
		"obstacles": [{
			"kind": "moving_bar", "x": 360, "y": 650,
			"rotation_degrees": 0, "width": 180, "height": 34,
			"inner_radius": 40, "spoke_count": 6, "speed_degrees": 55,
			"motion_direction_degrees": 90, "travel_distance": 100,
			"motion_period": 3.2, "phase_degrees": 0,
		}],
		"left_wall_gap": {"enabled": false, "top": 420, "bottom": 720},
		"right_wall_gap": {"enabled": false, "top": 420, "bottom": 720},
		"max_lives": 5,
		"expected_solution": {
			"estimated_bounces": 2, "blocks_required": 0,
			"route_description": "Kayan bariyeri gec",
		},
	}
	var mapped := AILevelMapper.new().map_blueprint(raw)
	_check("AI engel taslagi map edildi", bool(mapped["ok"]), true)
	var level: LevelData = mapped["blueprint"]["level"]
	_check("AI kayan engel turu", level.obstacles[0].kind, ObstacleData.Kind.MOVING_BAR)
	_check("AI hareket mesafesi", level.obstacles[0].travel_distance, 100.0)


func _test_generation_contract() -> void:
	var schema := AILevelContract.response_schema(2)
	var level_properties: Dictionary = schema["properties"]["levels"]["items"]["properties"]
	_check("AI semasinda engel dizisi", level_properties.has("obstacles"), true)
	_check("AI semasi dort engel turu", level_properties["obstacles"]["items"]
		["properties"]["kind"]["enum"].size(), 4)
	var kinetic := AIGeneratorSettings.new().sanitize({
		"template": "kinetic_course", "mechanics": PackedStringArray(),
	})
	_check("hareketli parkur carki zorunlu tutuyor",
		kinetic["mechanics"].has("rotating_wheel"), true)
	_check("hareketli parkur kayan engeli zorunlu tutuyor",
		kinetic["mechanics"].has("moving_bar"), true)
	var messages := AILevelPromptBuilder.build_messages({
		"template": "kinetic_course", "difficulty": "hard",
		"mechanics": PackedStringArray(["rotating_wheel", "moving_bar"]),
	}, 2)
	_check("AI promptu halka deligini acikliyor",
		String(messages[0]["content"]).contains("inner_radius"), true)
	var profile := LevelGenerator.Profile.kinetic()
	_check("yerel engelli profil engel uretiyor", profile.obstacle_count.y > 0, true)


## 41-50 bilerek yalnizca halka + bomba kullanir: cark ve kayan bariyer
## tanitimi 51-100 bandina yayildi (51=cark ilk-gorulme, 56=kayan bariyer
## ilk-gorulme, sonra tum turlerin kombinasyonlari 100'e kadar zorlasir).
## Hizlandirici (SPEED_BOOST) 51-100'e BILEREK dahil edilmedi: gercek
## mekanigi (yakindaki bloklari kirma, gameplay.gd _on_hazard_triggered)
## LevelSolver'da hic simule edilmiyor, yani onu rota acan bir eleman olarak
## kullanan bir bolum offline dogrulanamaz - bloksuz engel bandi olarak
## kalmasi bu korlugu bastan onler. Ileride bloklu bir bantla eslenirse
## buraya eklenebilir.
func _test_official_obstacle_levels() -> void:
	var kinds_41_50 := {}
	for level_id in range(41, 51):
		var level := LevelLibrary.load_level(level_id)
		for obstacle in level.obstacles:
			kinds_41_50[obstacle.kind] = true
	_check("41-50 halka kullaniyor", kinds_41_50.has(ObstacleData.Kind.METAL_RING), true)
	_check("41-50 bomba kullaniyor", kinds_41_50.has(ObstacleData.Kind.BOMB), true)
	_check("41-50 sadece halka+bomba kullaniyor (cark/kayan bariyer 51-100'e ertelendi)",
		kinds_41_50.size(), 2)

	var kinds_51_100 := {}
	var blocks_51_100 := 0
	for level_id in range(51, 101):
		var level := LevelLibrary.load_level(level_id)
		blocks_51_100 += level.breakable_blocks.size()
		for obstacle in level.obstacles:
			kinds_51_100[obstacle.kind] = true
	_check("51-100 halka kullaniyor", kinds_51_100.has(ObstacleData.Kind.METAL_RING), true)
	_check("51-100 bomba kullaniyor", kinds_51_100.has(ObstacleData.Kind.BOMB), true)
	_check("51-100 cark kullaniyor", kinds_51_100.has(ObstacleData.Kind.ROTATING_WHEEL), true)
	_check("51-100 kayan bariyer kullaniyor", kinds_51_100.has(ObstacleData.Kind.MOVING_BAR), true)
	_check("51-100 hizlandirici kullanmiyor (solver korlugu, bkz. yukaridaki not)",
		kinds_51_100.has(ObstacleData.Kind.SPEED_BOOST), false)
	_check("51-100 bloksuz engel bandi", blocks_51_100, 0)
	_check("51 donen carkin ilk-gorulme anidir",
		LevelLibrary.load_level(51).obstacles[0].kind, ObstacleData.Kind.ROTATING_WHEEL)

	# 126-150 LAZER BANDI: bandin kimligi yanip sonen isindir, dolayisiyla
	# HER bolumde en az bir lazer olmali. 126 lazerin ilk-gorulme anidir ve
	# YALNIZCA lazer icerir: tanitim karti bir bolumdeki yeni turleri gosterir,
	# baska bir engel olsa oyuncu ayni anda iki kural ogrenmek zorunda kalirdi.
	var laser_free: Array[int] = []
	for level_id in range(126, LevelLibrary.last_level_id() + 1):
		var level := LevelLibrary.load_level(level_id)
		var has_laser := false
		for obstacle in level.obstacles:
			if obstacle.kind == ObstacleData.Kind.PULSE_LASER:
				has_laser = true
		if not has_laser:
			laser_free.append(level_id)
	_check("126+ her bolumde lazer var", laser_free, [] as Array[int])

	var first := LevelLibrary.load_level(126)
	var first_kinds := {}
	for obstacle in first.obstacles:
		first_kinds[obstacle.kind] = true
	_check("126 yalnizca lazer icerir", first_kinds.size(), 1)
	_check("126 lazerin ilk-gorulme anidir",
		first_kinds.has(ObstacleData.Kind.PULSE_LASER), true)
	# 125'e kadar lazer GORULMEMELI, yoksa 126'nin tanitim karti hic acilmaz.
	var early_laser: Array[int] = []
	for level_id in range(1, 126):
		for obstacle in LevelLibrary.load_level(level_id).obstacles:
			if obstacle.kind == ObstacleData.Kind.PULSE_LASER:
				early_laser.append(level_id)
				break
	_check("1-125 lazer icermiyor", early_laser, [] as Array[int])


func _ring(at: Vector2) -> ObstacleData:
	var data := ObstacleData.new()
	data.kind = ObstacleData.Kind.METAL_RING
	data.position = at
	data.size = Vector2(160.0, 28.0)
	data.inner_radius = 52.0
	return data


func _bomb(at: Vector2) -> ObstacleData:
	var data := ObstacleData.new()
	data.kind = ObstacleData.Kind.BOMB
	data.position = at
	data.size = Vector2.ONE * 68.0
	return data


func _wheel(at: Vector2) -> ObstacleData:
	var data := ObstacleData.new()
	data.kind = ObstacleData.Kind.ROTATING_WHEEL
	data.position = at
	data.size = Vector2(150.0, 24.0)
	data.spoke_count = 6
	data.angular_speed_degrees = 55.0
	return data


func _mover(at: Vector2) -> ObstacleData:
	var data := ObstacleData.new()
	data.kind = ObstacleData.Kind.MOVING_BAR
	data.position = at
	data.size = Vector2(180.0, 34.0)
	data.motion_direction_degrees = 0.0
	data.travel_distance = 100.0
	data.motion_period = 2.8
	return data


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
		return
	_failed += 1
	push_error("%s: beklenen=%s gercek=%s" % [label, expected, actual])
