extends SceneTree

## GELISTIRME ARACI - oyuna dahil degildir, calisma zamaninda hic yuklenmez.
##
## Kirilabilir blok durum kurallarini ve 21. bolumun yildiz kapisini gercek
## sahne/kaynaklar uzerinde kosturur. El ile oynayarak dogrulanmasi zor olan
## sey burada olculur: hangi sifirlamanin bloklari geri getirdigi ve kapinin
## hangi kosullarda acildigi.
##
## NOT - neden Gameplay tipi hic yazilmiyor: `--script` ile ozel bir ana dongu
## calistirildiginda Godot autoload'lari kurmaz, bu yuzden AudioManager global
## adi yoktur ve ona bagli olan gameplay.gd DERLENEMEZ. Bu dosya Gameplay'i
## statik olarak anarsa kendi derlenmesi de o zincire takilir ve testler
## sessizce atlanir. Bu yuzden AudioManager once elle kaydedilir ve oynanis
## sahnesi yalnizca calisma zamaninda, tipsiz bir Node olarak yuklenir.
##
## Kayit dosyasina dokunur, bu yuzden baslarken var olan save yedeklenir ve
## bitiste aynen geri yazilir - gercek ilerleme kaybolmaz.
##
## Kullanim:
##   godot --headless --path . --script res://tools/check_blocks_and_gate.gd

const SAVE_PATH := "user://save.cfg"
const BACKUP_PATH := "user://save.cfg.verifybak"
const AUDIO_AUTOLOAD := "autoload/AudioManager"

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await physics_frame
	_backup_save()
	_register_audio_manager()

	await _test_block_state_rules()
	await _test_custom_level_store()
	await _test_generator()
	await _test_editor()
	await _test_star_row()
	await _test_attempt_timer()
	await _test_level_select()
	_test_star_gate()
	_test_library_bounds()

	_restore_save()
	print("")
	print("SONUC: %d gecti, %d kaldi." % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


## Autoload'i elle kur; yoksa oynanis sahnesi hic yuklenemez (bkz. dosya basi).
func _register_audio_manager() -> void:
	if Engine.has_singleton("AudioManager"):
		return
	var path := String(ProjectSettings.get_setting(AUDIO_AUTOLOAD, "")).trim_prefix("*")
	var script := load(path) as GDScript
	if script == null:
		push_error("check_blocks_and_gate: AudioManager script'i bulunamadi (%s)." % path)
		return
	var node := script.new() as Node
	node.name = "AudioManager"
	root.add_child(node)
	Engine.register_singleton("AudioManager", node)


# --- Kirilabilir blok durum kurallari -----------------------------------------

func _test_block_state_rules() -> void:
	print("--- Kirilabilir blok durumu (bolum 21) ---")

	# Tipsiz: Gameplay adini anmadan yuklenir (bkz. dosya basindaki not).
	var gameplay: Node = (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	if gameplay == null:
		_fail("oynanis sahnesi yuklenemedi")
		return
	gameplay.level_data = LevelLibrary.load_level(21)
	root.add_child(gameplay)
	await physics_frame

	var field := gameplay.get_node("Blocks") as BreakableField
	_check("bolume girince tum bloklar var", field.get_remaining_count(), field.get_total_count())
	_check("bolumde 1 blok var", field.get_total_count(), 1)

	var block := _first_block(field)
	block.shatter()
	_check("kirilan blok kalanlardan dusuyor", field.get_remaining_count(), 0)
	_check("kirik blok sayaci artiyor", field.get_broken_count(), 1)

	# Ayni blogu tekrar kirmak hicbir sey yapmamali (ayni atista ikinci temas).
	block.shatter()
	_check("ikinci shatter idempotent", field.get_broken_count(), 1)
	# Carpisma set_deferred ile kaldirilir; bir kare sonra gecerli olmali.
	await physics_frame
	_check("kirik blogun collision katmani sifir", block.collision_layer, 0)
	_check("kirik blogun sekli devre disi",
		(block.get_node("Shape") as CollisionShape2D).disabled, true)

	# ATIS SIFIRLAMA: top kaybedildi -> bloklar kirik KALMALI.
	var ball := gameplay.get_node("Ball") as Ball
	ball.shot_failed.emit("out_of_bounds")
	await create_timer(float(gameplay.auto_reset_delay) + 0.25).timeout
	_check("atis sifirlamasi kirik blogu geri getirmiyor", field.get_remaining_count(), 0)

	# BOLUM YENIDEN BASLATMA: her sey basa doner.
	gameplay.reset_shot()
	await physics_frame
	_check("bolum yeniden baslatinca bloklar geri geliyor",
		field.get_remaining_count(), field.get_total_count())
	_check("yeniden baslatinca kirik sayaci sifir", field.get_broken_count(), 0)
	_check("geri gelen blogun collision'i acik", _first_block(field).collision_layer, 1)

	# Blok kirmak atis sayacini ETKILEMEMELI (yildiz hesabi yalnizca sure+top).
	var snapshot: Dictionary = gameplay.get_debug_snapshot()
	var shots_before := int(snapshot["attempt_shots"])
	_first_block(field).shatter()
	await physics_frame
	var after: Dictionary = gameplay.get_debug_snapshot()
	_check("blok kirmak atis sayisini artirmiyor", int(after["attempt_shots"]), shots_before)
	_check("debug anlik goruntusunde blok sayaclari var", int(after["blocks_total"]), 1)

	# Efekt bitince kirik blok agactan silinmeli - kalinti birakmamali.
	await create_timer(0.4).timeout
	_check("kirik blok node'u temizleniyor", field.get_child_count(), 0)

	root.remove_child(gameplay)
	gameplay.free()


func _first_block(field: BreakableField) -> BreakableBlock:
	for child in field.get_children():
		var block := child as BreakableBlock
		if block != null and not block.is_broken():
			return block
	return null


# --- Editor kayit katmani -------------------------------------------------------
#
# Telefonda tasarlanan bolumun repoya donebilmesi bu iki seye baglidir:
# kaydin geri YUKLENEBILMESI ve panoya konan metnin gecerli bir .tres olmasi.
# Ikisi de sessizce bozulabilecek seyler.

func _test_custom_level_store() -> void:
	print("")
	print("--- Editor kayit katmani ---")

	var level := LevelData.new()
	level.level_id = 7
	level.display_name = "Test Bölümü"
	level.launcher_position = Vector2(360, 1120)
	level.target_position = Vector2(280, 340)
	level.max_lives = 3

	var panel := PanelData.new()
	panel.position = Vector2(400, 700)
	panel.rotation_degrees = -22.0
	panel.length = 260.0
	level.panels = [panel]

	var block := BreakableBlockData.new()
	block.position = Vector2(250, 560)
	block.size = Vector2(200, 44)
	level.breakable_blocks = [block]

	var saved := CustomLevelStore.Bucket.SAVED
	var path := CustomLevelStore.save(saved, level, "Sınama Bölümü 1")
	_check("kaydedildi", not path.is_empty(), true)
	_check("dosya adi temizlendi", path.get_file(), "sinama_bolumu_1.tres")
	_check("kayit listede gorunuyor",
		CustomLevelStore.list_names(saved).has("sinama_bolumu_1"), true)

	var loaded := CustomLevelStore.load_level(saved, "sinama_bolumu_1")
	_check("geri yuklendi", loaded != null, true)
	if loaded != null:
		_check("panel korundu", loaded.panels.size(), 1)
		_check("blok korundu", loaded.breakable_blocks.size(), 1)
		_check("panel acisi korundu", loaded.panels[0].rotation_degrees, -22.0)
		_check("blok boyutu korundu", loaded.breakable_blocks[0].size, Vector2(200, 44))
		_check("hedef korundu", loaded.target_position, Vector2(280, 340))
		_check("yuklenen bolum dogrulamadan geciyor", loaded.validate().size(), 0)

	# Panoya konan metin, repoya yapistirilabilecek gecerli bir .tres olmali.
	var text := CustomLevelStore.to_text(level)
	_check("metin uretildi", not text.is_empty(), true)
	_check("metin LevelData kaynagi", text.contains("script_class=\"LevelData\""), true)
	_check("alt kaynaklar gomulu", text.contains("[sub_resource"), true)
	_check("blok verisi metinde", text.contains("breakable_block_data.gd"), true)

	# Toplu kopyalama: her bolum ayrac satiriyla baslamali ki yapistirilan
	# blok tekrar dosyalara bolunebilsin.
	var second := level.duplicate(true) as LevelData
	second.display_name = "İkinci"
	var bulk := CustomLevelStore.bulk_text([level, second],
		PackedStringArray(["birinci", "ikinci"]))
	_check("toplu metin iki bolum iceriyor", bulk.count("[gd_resource"), 2)
	_check("toplu metin ayrac tasiyor", bulk.contains("===== birinci.tres ====="), true)
	_check("ikinci ayrac da var", bulk.contains("===== ikinci.tres ====="), true)

	# URETILENLER kovasi AYRI olmali ve yeni parti eskisini silmeli.
	var generated := CustomLevelStore.Bucket.GENERATED
	CustomLevelStore.replace_generated([level, second])
	_check("parti diske yazildi", CustomLevelStore.list_names(generated).size(), 2)
	_check("parti kayitlar kovasina karismadi",
		CustomLevelStore.list_names(saved).size(), 1)
	CustomLevelStore.replace_generated([level])
	_check("yeni parti eskisini siliyor", CustomLevelStore.list_names(generated).size(), 1)

	for leftover in CustomLevelStore.list_names(generated):
		CustomLevelStore.delete(generated, leftover)
	CustomLevelStore.delete(saved, "sinama_bolumu_1")
	_check("silindi", CustomLevelStore.list_names(saved).has("sinama_bolumu_1"), false)


# --- Uretec ----------------------------------------------------------------------
#
# Uretecin isi "oynanabilir aday bulmak". Kabul ettigi her bolum kendi
# profilini SAGLAMALI - yoksa eleme islevini yitirir ve sadece rastgele
# yerlesim uretir.

func _test_generator() -> void:
	print("")
	print("--- Bolum ureteci ---")

	var generator := LevelGenerator.new()
	root.add_child(generator)
	await process_frame

	var profile := LevelGenerator.Profile.easy()
	# assign() SART: GDScript lambda'lari degeri KOPYALAYARAK yakalar, bu
	# yuzden lambda icinde `produced = levels` yazmak yalnizca lambda'nin
	# kendi kopyasini degistirir ve disaridaki dizi bos kalir. Diziyi yerinde
	# doldurmak gerekir.
	var produced: Array[LevelData] = []
	generator.finished.connect(func(levels: Array[LevelData]) -> void: produced.assign(levels))
	# Sabit tohum: sonuc tekrarlanabilir olsun, test rastgele dalgalanmasin.
	generator.generate(profile, 2, 120, 20240517)
	while generator.is_running():
		await process_frame

	_check("uretec aday buldu", produced.size() > 0, true)
	_check("eleme dokumu tutuluyor", generator.describe_rejections().is_empty(), false)

	# Kabul edilen her bolum profili saglamali ve gecerli olmali.
	var solver := LevelSolver.from_scenes()
	var world := LevelWorld.new()
	root.add_child(world)
	for level in produced:
		_check("uretilen bolum dogrulamadan geciyor", level.validate().size(), 0)
		world.build(level)
		await physics_frame
		await physics_frame
		solver.bind_space(world.get_space(), world.get_block_rids())
		var none: Array[RID] = []
		var scan := solver.scan(
			solver.spawn_position(level.launcher_position), level.target_position,
			world.get_play_rect(), none,
			LevelGenerator.FINE_ANGLE_STEP, LevelGenerator.FINE_POWER_STEP)
		var robust := int(LevelSolver.analyse_robust(scan)["robust"])
		_check("uretilen bolum profili sagliyor (%d >= %d saglam hucre)" % [
			robust, profile.min_robust], robust >= profile.min_robust, true)

	root.remove_child(world)
	world.free()
	root.remove_child(generator)
	generator.free()


# --- Editor ekrani ----------------------------------------------------------------

func _test_editor() -> void:
	print("")
	print("--- Bolum editoru ---")

	# Tipsiz: LevelEditor adini anmadan yuklenir (bkz. dosya basindaki not).
	var editor: Node = (load("res://scenes/level_editor.tscn") as PackedScene).instantiate()
	if editor == null:
		_fail("editor sahnesi yuklenemedi")
		return
	root.add_child(editor)
	await process_frame

	_check("bos bolumle aciliyor", editor.level != null, true)
	var world := editor.get_node("World") as LevelWorld
	_check("onizleme dunyasi kuruldu", world.get_child_count() > 0, true)

	# Ekle -> onizlemede gercek govde belirmeli.
	editor.call("_on_add_panel")
	await process_frame
	_check("panel eklendi", editor.level.panels.size(), 1)
	_check("panel onizlemede", world.get_panel_node(0) != null, true)

	editor.call("_on_add_block")
	await process_frame
	_check("blok eklendi", editor.level.breakable_blocks.size(), 1)
	_check("blok onizlemede", world.get_block_node(0) != null, true)
	_check("blok RID'i kayitli", world.get_block_count(), 1)

	# Stepper'lar secili ogeyi degistirmeli.
	var width_before: float = editor.level.breakable_blocks[0].size.x
	editor.call("_on_tune", 1, 1)
	_check("B+ blok genisligini artiriyor",
		editor.level.breakable_blocks[0].size.x > width_before, true)

	# Sil -> hem veriden hem onizlemeden.
	editor.call("_on_delete")
	await process_frame
	_check("blok silindi", editor.level.breakable_blocks.size(), 0)
	_check("blok onizlemeden kalkti", world.get_block_count(), 0)

	# PARTI GEZINMESI: bir bolumu acmak digerlerini KAYBETMEMELI. Onceki
	# surumde uretilen 10 adaydan birini secmek geri kalanini yok ediyordu.
	var batch: Array[LevelData] = []
	for i in 3:
		var entry := LevelData.new()
		entry.display_name = "Parti %d" % (i + 1)
		entry.launcher_position = Vector2(360, 1120)
		entry.target_position = Vector2(200.0 + 80.0 * float(i), 320)
		batch.append(entry)
	editor.call("_set_batch", batch, PackedStringArray(["a", "b", "c"]),
		CustomLevelStore.Bucket.GENERATED)
	await process_frame

	_check("parti ilk bolumu acti", editor.level.display_name, "Parti 1")
	_check("gezinme satiri gorunur", editor.get_node(
		"HUD/SafeArea/Root/BottomPanel/Rows/BatchRow").visible, true)

	editor.call("_on_batch_step", 1)
	await process_frame
	_check("sonraki bolume gecti", editor.level.display_name, "Parti 2")
	_check("parti hala 3 bolum", editor.get("_batch").size(), 3)

	editor.call("_on_batch_step", -1)
	editor.call("_on_batch_step", -1)
	await process_frame
	_check("basa sarma calisiyor", editor.level.display_name, "Parti 3")
	_check("gezindikten sonra parti bozulmadi", editor.get("_batch").size(), 3)

	root.remove_child(editor)
	editor.free()


# --- Yildiz satiri -------------------------------------------------------------
#
# Yildiz SAYISI dogru olsa bile yanlis CIZILEBILIR: reveal animasyonu her
# yildizin olcegini ayri oynatir ve olcek 0'da kalirsa o yildiz dolu sayilsa
# bile bos cizilir. Kod okumakla fark edilmez, bu yuzden cizim kosulunun
# kendisi test edilir.

func _test_star_row() -> void:
	print("")
	print("--- Yildiz satiri ---")

	var row := StarRow.new()
	root.add_child(row)
	await process_frame

	for count in [0, 1, 2, 3]:
		row.set_stars(count)
		_check("set_stars(%d) -> %d dolu cizilir" % [count, count], _visible_filled(row), count)

	for count in [1, 2, 3]:
		row.play_reveal(count)
		await create_timer(0.8).timeout
		_check("play_reveal(%d) bitince %d dolu cizilir" % [count, count],
			_visible_filled(row), count)

	root.remove_child(row)
	row.free()


## StarRow._draw()'in "bu yildiz dolu cizilir" kosulunun aynisi.
func _visible_filled(row: StarRow) -> int:
	var filled := int(row.get("_filled"))
	var scales: PackedFloat32Array = row.get("_scales")
	var count := 0
	for i in scales.size():
		if i < filled and scales[i] > 0.001:
			count += 1
	return count


# --- Deneme kronometresi -------------------------------------------------------
#
# Sure, bolume GIRINCE degil ilk gecerli nisanda baslamali. Bunu oynayarak
# fark etmek zor (ekranda kronometre yok, yalnizca yildiza yansir), bu yuzden
# dogrudan olculur.

func _test_attempt_timer() -> void:
	print("")
	print("--- Deneme kronometresi ---")

	var gameplay: Node = (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	gameplay.level_data = LevelLibrary.load_level(1)
	root.add_child(gameplay)
	await physics_frame

	_check("bolume girince kronometre kapali",
		bool((gameplay.get_debug_snapshot() as Dictionary)["attempt_timer_running"]), false)

	# Bolumu incelemek sureyi yememeli.
	await create_timer(0.6).timeout
	_check("nisan alinmadan sure islemiyor",
		float((gameplay.get_debug_snapshot() as Dictionary)["attempt_seconds"]), 0.0)

	# Gecerli bir nisan: min_drag_distance esigini gecen bir surukleme.
	var launcher := gameplay.get_node("Launcher") as Launcher
	var origin := launcher.get_spawn_position()
	launcher.begin_aim(origin)
	launcher.update_aim(origin + Vector2(0.0, launcher.min_drag_distance + 40.0))
	_check("gecerli nisan olustu", launcher.has_valid_aim(), true)
	_check("gecerli nisan kronometreyi baslatiyor",
		bool((gameplay.get_debug_snapshot() as Dictionary)["attempt_timer_running"]), true)

	await create_timer(0.5).timeout
	var running := float((gameplay.get_debug_snapshot() as Dictionary)["attempt_seconds"])
	_check("nisandan sonra sure isliyor", running > 0.3, true)

	# Bolum yeniden baslarsa kronometre yeniden BEKLEMEYE gecmeli.
	gameplay.reset_shot()
	await physics_frame
	var after: Dictionary = gameplay.get_debug_snapshot()
	_check("yeniden baslatinca kronometre tekrar kapali",
		bool(after["attempt_timer_running"]), false)
	_check("yeniden baslatinca sure sifir", float(after["attempt_seconds"]), 0.0)

	root.remove_child(gameplay)
	gameplay.free()


# --- Bolum secim ekrani --------------------------------------------------------
#
# Kilitli-kapili buton yeni bir gorunum uretiyor (kilit isareti + "20 / 40"
# satiri). Bu kod yalnizca 21. bolum kilitliyken calistigi icin normal
# oynanista fark edilmesi zor; burada dogrudan olculur.

func _test_level_select() -> void:
	print("")
	print("--- Bolum secim ekrani ---")

	var store := ProgressStore.new()
	store.highest_unlocked_level = 21
	for id in range(1, 21):
		store.completed_levels.append(id)
		store.level_stars[id] = 1

	# Tipsiz: LevelSelect adini anmadan yuklenir (bkz. dosya basindaki not).
	var select: Node = (load("res://scenes/level_select.tscn") as PackedScene).instantiate()
	select.progress = store
	root.add_child(select)
	await process_frame

	var grid := select.get_node("SafeArea/Content/GridScroll/GridHolder/Grid") as GridContainer
	_check("25 bolum butonu uretiliyor", grid.get_child_count(), 25)

	var unlocked := grid.get_node("Level20") as Button
	_check("bolum 20 acik", unlocked.disabled, false)
	_check("acik butonda kilit isareti yok", unlocked.has_node("LockMark"), false)
	_check("acik butonda yildiz satiri var", unlocked.has_node("Stars"), true)

	var gated := grid.get_node("Level21") as Button
	_check("bolum 21 kilitli", gated.disabled, true)
	_check("kilitli butonda kilit isareti var", gated.has_node("LockMark"), true)
	_check("kapili butonda yildiz satiri yerine kapi bilgisi var",
		gated.has_node("StarGate"), true)
	var gate_label := gated.get_node("StarGate").get_child(0) as Label
	_check("kapi bilgisi 20 / 40 gosteriyor", gate_label.text, "20 / 40")

	# 22-25 yildiz kapisi TASIMAZ; sirali ilerleme yuzunden kilitlidirler,
	# bu yuzden kapi satiri degil normal (kisilmis) yildiz satiri gosterirler.
	var plain := grid.get_node("Level22") as Button
	_check("bolum 22 kilitli", plain.disabled, true)
	_check("kapisiz kilitli bolumde kapi satiri yok", plain.has_node("StarGate"), false)
	_check("kapisiz kilitli bolumde yildiz satiri var", plain.has_node("Stars"), true)

	var total := select.get_node("SafeArea/Content/StarTotal") as Label
	_check("toplam yildiz sayaci 20 / 75", total.text, "20 / 75")

	root.remove_child(select)
	select.free()


# --- 21. bolumun yildiz kapisi ------------------------------------------------

func _test_star_gate() -> void:
	print("")
	print("--- Bolum 21 yildiz kapisi ---")

	# 20. bolum bitmis ama yildiz yetersiz -> kilitli.
	var store := ProgressStore.new()
	store.highest_unlocked_level = 21
	for id in range(1, 21):
		store.completed_levels.append(id)
		store.level_stars[id] = 1
	_check("20 bolumden 20 yildiz", store.get_stars_before(21), 20)
	_check("<40 yildizla 21 kilitli", store.is_unlocked(21), false)
	_check("kapi ilerlemesi (20, 40)", store.get_star_gate_progress(21), Vector2i(20, 40))
	_check("kilitliyken OYNA 20'yi acar", store.get_resume_level_id(), 20)

	# 40'a yakin yildiz var ama 20. bolum bitmemis -> yine kilitli.
	var early := ProgressStore.new()
	early.highest_unlocked_level = 15
	for id in range(1, 15):
		early.level_stars[id] = 3
	_check("14 bolumden 42 yildiz", early.get_stars_before(21), 42)
	_check("20 bitmeden 42 yildizla bile 21 kilitli", early.is_unlocked(21), false)

	# 20. bolum bitmis VE 40 yildiz -> acilir.
	var ready := ProgressStore.new()
	ready.highest_unlocked_level = 21
	for id in range(1, 21):
		ready.completed_levels.append(id)
		ready.level_stars[id] = 2
	_check("20 bolumden 40 yildiz", ready.get_stars_before(21), 40)
	_check("20 bitti + 40 yildiz -> 21 acik", ready.is_unlocked(21), true)
	_check("acikken OYNA 21'i acar", ready.get_resume_level_id(), 21)

	# Kapinin ARKASINDAKI yildizlar kapiya sayilmaz.
	var behind := ProgressStore.new()
	behind.highest_unlocked_level = 21
	for id in range(1, 21):
		behind.completed_levels.append(id)
		behind.level_stars[id] = 1
	for id in range(21, 26):
		behind.level_stars[id] = 3
	_check("21-25 yildizlari genel toplama giriyor", behind.get_total_stars(), 35)
	_check("21-25 yildizlari kapiya SAYILMIYOR", behind.get_stars_before(21), 20)
	_check("kapi hala kapali", behind.is_unlocked(21), false)

	# Yildiz kaydi yalnizca IYILESIRSE yazilir (eski kayitlar korunur).
	var record := ProgressStore.new()
	record.highest_unlocked_level = 25
	_check("ilk 21 yildizi kaydediliyor", record.set_level_stars_if_higher(21, 2), true)
	_check("daha dusuk sonuc kaydi ezmiyor", record.set_level_stars_if_higher(21, 1), false)
	_check("kayitli deger korunuyor", record.get_level_stars(21), 2)
	_check("daha iyi sonuc kaydediliyor", record.set_level_stars_if_higher(21, 3), true)
	_check("yeni rekor yaziliyor", record.get_level_stars(21), 3)


func _test_library_bounds() -> void:
	print("")
	print("--- LevelLibrary sinirlari ---")
	_check("LEVEL_COUNT", LevelLibrary.LEVEL_COUNT, 25)
	_check("has_next(20)", LevelLibrary.has_next(20), true)
	_check("has_next(24)", LevelLibrary.has_next(24), true)
	_check("has_next(25)", LevelLibrary.has_next(25), false)
	_check("azami yildiz", ProgressStore.new().get_max_available_stars(), 75)

	# 21-25 gercekten yuklenip dogrulamadan geciyor mu.
	for id in range(21, 26):
		var level := LevelLibrary.load_level(id)
		_check("bolum %d yukleniyor" % id, level.level_id, id)
		_check("bolum %d dogrulamadan geciyor" % id, level.validate().size(), 0)
		_check("bolum %d blok iceriyor" % id, level.breakable_blocks.size() > 0, true)
		_check("bolum %d: 3-yildiz atis <= max_lives" % id,
			level.three_star_max_shots <= level.max_lives, true)
		_check("bolum %d: 2-yildiz atis <= max_lives" % id,
			level.two_star_max_shots <= level.max_lives, true)


# --- Yardimcilar ---------------------------------------------------------------

func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
		print("  OK    %s" % label)
		return
	_failed += 1
	print("  HATA  %s -> beklenen %s, gelen %s" % [label, expected, actual])


func _fail(label: String) -> void:
	_failed += 1
	print("  HATA  %s" % label)


func _backup_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data := FileAccess.get_file_as_bytes(SAVE_PATH)
	var file := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
	if file != null:
		file.store_buffer(data)
		file.close()


func _restore_save() -> void:
	if not FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		return
	var data := FileAccess.get_file_as_bytes(BACKUP_PATH)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_buffer(data)
		file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
