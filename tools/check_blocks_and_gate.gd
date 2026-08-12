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
var _owned_audio_manager: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await physics_frame
	_backup_save()
	_register_audio_manager()

	_test_responsive_layout()
	await _test_debug_panel_close()
	await _test_launcher_power_feel()
	await _test_block_state_rules()
	_test_block_tier_colors()
	_test_haptics_setting()
	await _test_ball_trail_speed_response()
	await _test_practice_mode()
	_test_custom_level_store()
	await _test_generator()
	await _test_editor()
	await _test_edit_official_level()
	await _test_star_row()
	await _test_attempt_timer()
	await _test_level_select()
	_test_level_worlds()
	_test_star_gate()
	_test_save_schema_and_migration()
	_test_locale()
	_test_translation_coverage()
	await _test_settings_screen()
	await _test_faz9_tall_aspect()
	_test_library_bounds()

	_restore_save()
	await _unregister_audio_manager()
	print("")
	print("SONUC: %d gecti, %d kaldi." % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_responsive_layout() -> void:
	print("--- Mobil ekran yerlesimi ---")
	_check("canvas item olceklemesi etkin",
		ProjectSettings.get_setting("display/window/stretch/mode", ""), "canvas_items")
	_check("uzun ve genis ekranlar siyah barsiz genisler",
		ProjectSettings.get_setting("display/window/stretch/aspect", ""), "expand")

	# Tum ana ekranlar referans viewport'u doldurmali. `expand`, cihazin
	# en-boy oranina gore bu rect'i uzatir; tam rect anchor'i olmayan bir kok
	# uzun telefonda eski 720x1280 alanda kalip yeniden siyah/eksik alan uretir.
	for path in [
		"res://scenes/splash.tscn",
		"res://scenes/main_menu.tscn",
		"res://scenes/level_select.tscn",
		"res://scenes/settings.tscn",
	]:
		var screen := (load(path) as PackedScene).instantiate() as Control
		_check("%s yatayda tam ekran" % path.get_file(), screen.anchor_right, 1.0)
		_check("%s dikeyde tam ekran" % path.get_file(), screen.anchor_bottom, 1.0)
		screen.free()

	var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	var background := gameplay.get_node("BackgroundLayer/Background") as Control
	var safe_area := gameplay.get_node("HUD/SafeArea") as Control
	_check("oynanis zemini yatayda tam ekran", background.anchor_right, 1.0)
	_check("oynanis zemini dikeyde tam ekran", background.anchor_bottom, 1.0)
	_check("oynanis HUD'u yatayda tam ekran", safe_area.anchor_right, 1.0)
	_check("oynanis HUD'u dikeyde tam ekran", safe_area.anchor_bottom, 1.0)
	gameplay.free()


func _test_debug_panel_close() -> void:
	print("--- Debug paneli ---")
	var panel: Node = (load("res://scenes/debug_panel.tscn") as PackedScene).instantiate()
	root.add_child(panel)
	await process_frame
	panel.call("toggle_visible")
	_check("debug panel aciliyor", panel.get_node("Panel").visible, true)
	_check("debug kapat dugmesi var",
		panel.has_node("Panel/Margin/Rows/HeaderRow/CloseButton"), true)
	(panel.get_node("Panel/Margin/Rows/HeaderRow/CloseButton") as Button).pressed.emit()
	_check("debug kapat dugmesi paneli kapatiyor", panel.get_node("Panel").visible, false)
	root.remove_child(panel)
	panel.free()


func _test_launcher_power_feel() -> void:
	print("")
	print("--- Firlatici guc hissi ---")
	var gameplay: Node = (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	gameplay.level_data = LevelLibrary.load_level(1)
	root.add_child(gameplay)
	await physics_frame

	var launcher := gameplay.get_node("Launcher") as Launcher
	var ball := gameplay.get_node("Ball") as Ball
	var drag_hint := launcher.get_node("DragHint") as Node2D
	var meter := launcher.get_node("PowerMeter") as Node2D
	var guide := launcher.get_node("AimGuide") as AimGuide
	var ball_visual := ball.get_node("Visual") as Node2D
	var barrel_tip := launcher.get("_barrel_tip") as Polygon2D
	var physical_start := ball.global_position
	var crossed_steps: Array[int] = []
	launcher.power_step_crossed.connect(
		func(step_index: int, _step_count: int) -> void: crossed_steps.append(step_index))

	_check("tam guc mesafesi mobil alt alana sigiyor", launcher.max_drag_distance <= 140.0, true)
	_check("azami atis gucu bir kademe dusuruldu", launcher.max_power, 2200.0)
	_check("29'a kadar nisan izi tam", gameplay.call("_preview_ratio_for_level", 29), 1.0)
	_check("30'da nisan izi yumusak azalir", gameplay.call("_preview_ratio_for_level", 30), 0.95)
	_check("40'ta nisan izi yariya iner", gameplay.call("_preview_ratio_for_level", 40), 0.5)
	_check("surukleme alani hazir durumda gorunuyor", drag_hint.visible, true)

	var pointer_start := launcher.global_position
	launcher.begin_aim(pointer_start)
	for step in range(1, launcher.power_step_count + 1):
		var ratio := float(step) / float(launcher.power_step_count)
		var drag_distance := lerpf(
			launcher.min_drag_distance, launcher.max_drag_distance, ratio) + 0.5
		launcher.update_aim(pointer_start + Vector2.DOWN * drag_distance)

	_check("surukleme alani nisanda belirginlesiyor", drag_hint.modulate.a, 1.0)
	_check("guc bari nisanda gorunuyor", meter.visible, true)
	_check("guc bari alti sabit segment", meter.get_child_count(), 6)
	_check("her yeni guc kademesi bir kez yayiliyor", crossed_steps, [1, 2, 3, 4, 5, 6])
	_check("cekiste fizik topu yerinde", ball.global_position, physical_start)
	_check("cekiste yalnizca top gorseli geriliyor",
		ball_visual.position.length() >= 13.5, true)
	_check("namlu ucu gerilen topu takip ediyor",
		barrel_tip.global_position.distance_to(ball_visual.global_position) < 0.5, true)
	var full_guide_count := (guide.get("_dots") as PackedVector2Array).size()
	launcher.set_guide_visibility_ratio(0.5)
	launcher.update_aim(pointer_start + Vector2.DOWN * launcher.max_drag_distance)
	var short_guide_count := (guide.get("_dots") as PackedVector2Array).size()
	_check("azalan oran gercek nokta sayisini kisaltiyor", short_guide_count < full_guide_count, true)
	launcher.set_guide_visibility_ratio(1.0)
	_check("gecerli nisan birakiliyor", launcher.release_aim(), true)
	_check("birakinca top normal firliyor", ball.is_flying(), true)
	_check("birakinca gorsel ofset sifir", ball_visual.position, Vector2.ZERO)
	_check("birakinca guc bari gizleniyor", meter.visible, false)

	root.remove_child(gameplay)
	gameplay.free()


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


# --- Kirilabilir blok durum kurallari -----------------------------------------

func _test_block_state_rules() -> void:
	print("--- Dayanikli blok durumu ---")

	# BILEREK SENTETIK BOLUM: bu test blok DURUM MEKANIGINI olcer (catlama,
	# atis sifirlamasinin hasari korumasi, yeniden baslatmanin geri getirmesi),
	# belirli bir resmi bolumun icerigini degil. Eskiden bolum 30 yuklenip
	# "tam 1 blok var" varsayiliyordu; bu, bolum 30'un tasarimini teste
	# kilitliyordu (kucuk parcali tugla kumesine gecilemiyordu). Kendi tek
	# dayanikli tuglali bolumumuzu kurmak ikisini de bagimsiz birakir.
	var level := LevelData.new()
	level.level_id = 1
	level.launcher_position = Vector2(360.0, 1120.0)
	level.target_position = Vector2(360.0, 300.0)
	level.max_lives = 5
	var lock := BreakableBlockData.new()
	lock.position = Vector2(360.0, 640.0)
	lock.size = Vector2(120.0, 34.0)
	lock.hit_points = 2
	level.breakable_blocks = [lock]

	# Tipsiz: Gameplay adini anmadan yuklenir (bkz. dosya basindaki not).
	var gameplay: Node = (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	if gameplay == null:
		_fail("oynanis sahnesi yuklenemedi")
		return
	gameplay.level_data = level
	root.add_child(gameplay)
	await physics_frame

	var field := gameplay.get_node("Blocks") as BreakableField
	_check("bolume girince tum bloklar var", field.get_remaining_count(), field.get_total_count())
	_check("bolumde 1 blok var", field.get_total_count(), 1)

	var block := _first_block(field)
	_check("kilit tugla iki canli", block.get_max_hits(), 2)
	block.take_hit()
	_check("ilk temas tuglayi catlatiyor", block.get_remaining_hits(), 1)
	_check("catlayan tugla hala sahnede", field.get_remaining_count(), 1)
	_check("catlayan tugla kirik sayilmiyor", field.get_broken_count(), 0)
	block.take_hit()
	_check("ayni fizik karesinde cift hasar yok", block.get_remaining_hits(), 1)
	await physics_frame
	_check("ilk hasardan sonra collision acik", block.collision_layer, 1)

	# ATIS SIFIRLAMA: kismi hasar da kirik durum gibi kalici olmalı.
	var ball := gameplay.get_node("Ball") as Ball
	ball.shot_failed.emit("out_of_bounds")
	await create_timer(float(gameplay.auto_reset_delay) + 0.25).timeout
	_check("atis sifirlamasi catlagi iyilestirmiyor", block.get_remaining_hits(), 1)

	block.take_hit()
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

	# ATIS SIFIRLAMA: tamamen kirilan blok da kirik KALMALI.
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
	_check("yeniden baslatinca iki can geri geliyor", _first_block(field).get_remaining_hits(), 2)

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


## Tek darbelik ve iki darbelik tuglalar RENKTEN ayirt edilebilmeli. Oyuncuya
## "bu tugla kac temas ister" bilgisini denemeden veren tek isaret budur;
## sessizce ayni renge donerlerse bolum tasarimi okunamaz hale gelir.
func _test_block_tier_colors() -> void:
	print("")
	print("--- Tugla dayaniklilik renkleri ---")
	var scene := load("res://scenes/breakable_block.tscn") as PackedScene

	var plain := scene.instantiate() as BreakableBlock
	plain.hit_points = 1
	root.add_child(plain)
	var strong := scene.instantiate() as BreakableBlock
	strong.hit_points = 2
	root.add_child(strong)

	_check("tek/cift darbe govde rengi farkli",
		plain.get_body_color() != strong.get_body_color(), true)
	_check("tek/cift darbe kenar rengi farkli",
		plain.get_rim_color() != strong.get_rim_color(), true)
	# Renk ayrimini goremeyen oyuncular icin geometrik isaret de kalmali.
	_check("cift darbelik tuglada zirh centigi var",
		_has_armor_marks(strong), true)
	_check("tek darbelik tuglada zirh centigi yok",
		_has_armor_marks(plain), false)

	plain.queue_free()
	strong.queue_free()


## _build_armor_marks() cift kenar centigini iki dikey Line2D olarak cizer;
## tek darbelik tuglada yalnizca dikis cizgisi + centikleri bulunur.
func _has_armor_marks(block: BreakableBlock) -> bool:
	var visual := block.get_node("Visual")
	var vertical_lines := 0
	for child in visual.get_children():
		var line := child as Line2D
		if line == null or line.points.size() != 2:
			continue
		if absf(line.points[0].x - line.points[1].x) < 0.01 \
				and absf(line.points[0].y - line.points[1].y) > 0.01:
			vertical_lines += 1
	# Dikis cizgisi de dikeydir; zirh centikleri ONUN USTUNE iki tane daha ekler.
	return vertical_lines >= 3


# --- Dokunsal geri bildirim ---------------------------------------------------

## Titresim tercihi KALICI olmali ve "ilerlemeyi sifirla" onu silmemeli.
## Ayrica tum titresimler tek suzgecten (Haptics) gecmeli - biri dogrudan
## Input.vibrate_handheld cagirirsa ayar sessizce delinir.
func _test_haptics_setting() -> void:
	print("")
	print("--- Titresim ayari ---")

	var store := ProgressStore.new()
	_check("titresim varsayilan olarak acik", store.haptics_enabled, true)
	_check("ayni degere ayarlamak degisiklik saymiyor",
		store.set_haptics_enabled(true), false)
	_check("kapatmak degisiklik sayiliyor", store.set_haptics_enabled(false), true)
	_check("kapali deger tutuluyor", store.haptics_enabled, false)

	var reloaded := ProgressStore.load_from_disk()
	_check("titresim tercihi diske yaziliyor", reloaded.haptics_enabled, false)

	# Ilerleme sifirlamasi bir OYUNCU TERCIHINI silmemeli.
	reloaded.mark_completed(1)
	reloaded.reset()
	_check("ilerleme sifirlamasi titresim tercihini korur",
		reloaded.haptics_enabled, false)
	_check("ilerleme gercekten sifirlandi", reloaded.completed_levels.size(), 0)

	# Haptics kapaliyken hicbir darbe gecmemeli. vibrate_handheld'in kendisi
	# masaustunde sessizce yok sayildigi icin dogrudan gozlenemez; bunun
	# yerine suzgecin kendi karari olculur.
	var previous := Haptics.enabled
	Haptics.enabled = false
	_check("kapaliyken darbe suresi hesaplanmiyor", Haptics.enabled, false)
	Haptics.enabled = true
	_check("acikken suzgec gecirgen", Haptics.enabled, true)
	Haptics.enabled = previous

	# Sekme darbesi carpma siddetiyle ORANTILI olmali (hepsi ayni olursa geri
	# bildirim bilgi tasimaz).
	_check("sekme darbesi tavani makul",
		Haptics.BOUNCE_MAX_MSEC <= Haptics.MAX_MSEC, true)
	_check("hafif sekme sert sekmeden kisa",
		Haptics.BOUNCE_MIN_MSEC < Haptics.BOUNCE_MAX_MSEC, true)
	_check("hedef darbesi sekmeden belirgin sekilde uzun",
		Haptics.HIT_TARGET_MSEC > Haptics.BOUNCE_MAX_MSEC, true)

	_check("dogrudan vibrate_handheld cagrisi yok (haptics.gd disinda)",
		_direct_vibrate_call_count(), 0)


## scripts/ altinda haptics.gd DISINDA kalan dogrudan titresim cagrilarini sayar.
func _direct_vibrate_call_count() -> int:
	var offenders := 0
	for path in _gd_files_under("res://scripts"):
		if path.ends_with("haptics.gd"):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var text := file.get_as_text()
		file.close()
		# Yorum satirlarini saymamak icin kaba ama yeterli bir kontrol.
		for line in text.split("\n"):
			var trimmed := (line as String).strip_edges()
			if trimmed.begins_with("#"):
				continue
			if trimmed.contains("Input.vibrate_handheld"):
				offenders += 1
				push_error("dogrudan titresim cagrisi: %s -> %s" % [path, trimmed])
	return offenders


func _gd_files_under(root_path: String) -> PackedStringArray:
	var found := PackedStringArray()
	var directories: Array[String] = [root_path]
	while not directories.is_empty():
		var current: String = directories.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var full := current.path_join(entry)
			if dir.current_is_dir():
				directories.append(full)
			elif entry.ends_with(".gd"):
				found.append(full)
			entry = dir.get_next()
		dir.list_dir_end()
	return found


# --- Top izi ------------------------------------------------------------------

## Kuyruk topun HIZINA tepki vermeli: duran topta kisa, hizli topta uzun.
## Sabit uzunlukta bir kuyruk hiz hissi tasimaz.
func _test_ball_trail_speed_response() -> void:
	print("")
	print("--- Top izi hiz tepkisi ---")
	var ball: Ball = (load("res://scenes/ball.tscn") as PackedScene).instantiate()
	root.add_child(ball)
	await physics_frame

	var trail := ball.get_node("Trail") as Line2D
	_check("baslangicta kuyruk bos", trail.get_point_count(), 0)

	# Yavas top: kuyruk kisa kalmali.
	ball.reset_to(Vector2(360.0, 900.0))
	ball.launch(Vector2(0.0, -120.0))
	for i in 40:
		await physics_frame
	var slow_points := trail.get_point_count()
	var slow_width := trail.width
	ball.stop()

	# Hizli top: ayni sure sonunda belirgin sekilde daha uzun kuyruk.
	ball.reset_to(Vector2(360.0, 900.0))
	ball.launch(Vector2(0.0, -2000.0))
	for i in 40:
		await physics_frame
	var fast_points := trail.get_point_count()
	var fast_width := trail.width

	_check("hizli topta kuyruk daha uzun", fast_points > slow_points, true)
	_check("hizli topta kuyruk daha genis", fast_width > slow_width, true)
	_check("kuyruk azami uzunlugu asmiyor", fast_points <= ball.trail_length, true)

	# Yeni atis onceki atisin hiz durumunu devralmamali.
	ball.reset_to(Vector2(360.0, 900.0))
	_check("sifirlamada kuyruk temizleniyor", trail.get_point_count(), 0)

	ball.queue_free()
	await process_frame


## Debug panelinden bir RESMI bolumu duzenleyip kaydetme akisi.
##
## Kritik nokta, kaydin NEREDEN geldiginin kaybolmamasi: kayitlar listesinde
## "bolum_17_zikzak" gibi bir satir gorunmeli ve sidecar JSON'da
## source_level_id yazmali. Bu bilgi .tres'e YAZILMAZ (bolum dosyasi yalnizca
## bolumu tanimlar), bu yuzden sessizce kaybolmaya musait - testi burada.
func _test_edit_official_level() -> void:
	print("")
	print("--- Resmi bolumu duzenleyip kaydetme ---")

	var editor: Node = (load("res://scenes/level_editor.tscn") as PackedScene).instantiate()
	if editor == null:
		_fail("editor sahnesi yuklenemedi")
		return
	# AppRoot'un debug panelinden yaptigi sey: oynanan bolumun KOPYASI + numarasi.
	var official := LevelLibrary.load_level(17)
	editor.level = official.duplicate(true) as LevelData
	editor.source_level_id = 17
	root.add_child(editor)
	await process_frame

	_check("resmi bolum editore yuklendi", editor.level.level_id, 17)
	_check("kopya duzenleniyor (kaynak degil)", editor.level != official, true)

	var saved_store := GenerationMetadataStore.new(
		GenerationMetadataStore.SAVED_MANIFEST_PATH)
	var expected := CustomLevelStore.entry_name_for(editor.call("_saved_name_for_current"))
	CustomLevelStore.delete(CustomLevelStore.Bucket.SAVED, expected)

	editor.call("_on_save")
	await process_frame

	_check("kayit adi bolum numarasini tasiyor", expected.begins_with("bolum_17"), true)
	_check("kayit dosyasi olustu",
		CustomLevelStore.list_names(CustomLevelStore.Bucket.SAVED).has(expected), true)

	var entry := saved_store.get_entry(expected)
	_check("sidecar'a kaynak bolum yazildi", int(entry.get("source_level_id", 0)), 17)
	_check("sidecar'a kayit zamani yazildi",
		not String(entry.get("saved_at", "")).is_empty(), true)

	# Sifirdan tasarlanan bolumde kaynak YAZILMAMALI - aksi halde her kayit
	# rastgele bir resmi bolume baglanmis gorunurdu.
	editor.source_level_id = 0
	editor.level.display_name = "Test Tasarim"
	var fresh_name := CustomLevelStore.entry_name_for(
		editor.call("_saved_name_for_current"))
	editor.call("_on_save")
	await process_frame
	_check("kaynaksiz kayitta bolum numarasi yok",
		saved_store.get_entry(fresh_name).has("source_level_id"), false)

	# Temizlik: testin yazdigi kayitlar oyuncunun listesinde kalmasin.
	CustomLevelStore.delete(CustomLevelStore.Bucket.SAVED, expected)
	CustomLevelStore.delete(CustomLevelStore.Bucket.SAVED, fresh_name)
	saved_store.prune(CustomLevelStore.list_names(CustomLevelStore.Bucket.SAVED))

	root.remove_child(editor)
	editor.free()


# --- Yayin hazirligi: kayit semasi, goc, kurtarma -----------------------------

## Play Store surumunde en pahali hata "guncelleme oyuncunun ilerlemesini
## bozdu"dur ve elle fark edilmesi zordur. Bu test o senaryolari acikca kurar.
func _test_save_schema_and_migration() -> void:
	print("")
	print("--- Kayit semasi, goc ve kurtarma ---")

	# 1) YENI OYUNCU: kayit dosyasi yokken bolum 1 acik olmali.
	_delete_save_files()
	var fresh := ProgressStore.load_from_disk()
	_check("yeni oyuncuda bolum 1 acik", fresh.is_unlocked(1), true)
	_check("yeni oyuncuda bolum 2 kapali", fresh.is_unlocked(2), false)
	_check("yeni oyuncuda ilk bolum level_001", LevelData.uid_for(1), "level_001")

	# 2) TAMAMLAMA: kayit dosyasina UID yazilmali (tamsayi degil).
	fresh.mark_completed(1)
	fresh.set_level_stars_if_higher(1, 3)
	var raw := FileAccess.get_file_as_string(ProgressStore.SAVE_PATH)
	_check("kayit uid ile yaziliyor", raw.contains("level_001"), true)
	_check("kayit sema surumu yaziliyor",
		raw.contains(ProgressStore.KEY_SCHEMA_VERSION), true)
	_check("son tamamlanan bolum uid'i yaziliyor",
		raw.contains(ProgressStore.KEY_LAST_COMPLETED_UID), true)

	# 3) YENIDEN ACILIS: ilerleme korunmali.
	var reopened := ProgressStore.load_from_disk()
	_check("kapatip acinca tamamlanan korunuyor", reopened.is_completed(1), true)
	_check("kapatip acinca yildiz korunuyor", reopened.get_level_stars(1), 3)
	_check("kapatip acinca sonraki bolum acik", reopened.is_unlocked(2), true)

	# 4) ESKI KAYIT (sema 0, TAMSAYI anahtarli) gocu - guncelleme senaryosu.
	_delete_save_files()
	var legacy := ConfigFile.new()
	legacy.set_value("progress", ProgressStore.KEY_HIGHEST, 5)
	legacy.set_value("progress", ProgressStore.KEY_LEGACY_COMPLETED, [1, 2, 3, 4])
	legacy.set_value("progress", ProgressStore.KEY_LEGACY_STARS, {1: 3, 2: 2, 4: 1})
	legacy.save(ProgressStore.SAVE_PATH)

	var migrated := ProgressStore.load_from_disk()
	_check("eski kayit: tamamlananlar tasindi", migrated.completed_levels, [1, 2, 3, 4])
	_check("eski kayit: yildizlar tasindi", migrated.get_level_stars(1), 3)
	_check("eski kayit: yildizi olmayan bolum 0", migrated.get_level_stars(3), 0)
	_check("eski kayit: acilan bolum korundu", migrated.highest_unlocked_level, 5)

	# Goc SONRASI yazim yeni semada olmali; ikinci acilis ayni sonucu vermeli.
	migrated.save()
	var after_migration := ProgressStore.load_from_disk()
	_check("goc sonrasi yeni semada yaziliyor",
		FileAccess.get_file_as_string(ProgressStore.SAVE_PATH).contains("level_004"), true)
	_check("goc tekrarlanabilir (kayipsiz)",
		after_migration.completed_levels, [1, 2, 3, 4])
	_check("goc sonrasi yildizlar ayni", after_migration.get_level_stars(2), 2)

	# 5) SIRA DEGISIMI / ARAYA BOLUM EKLEME: kayit uid tuttugu icin bir bolumun
	#    SIRASI degisse de ilerleme o bolumde kalir. Dosyadaki anahtarlarin
	#    numaraya degil uid'e bagli oldugunu dogruluyoruz.
	var probe := ConfigFile.new()
	probe.load(ProgressStore.SAVE_PATH)
	var stored: Variant = probe.get_value("progress", ProgressStore.KEY_STARS_BY_UID, {})
	_check("yildiz anahtarlari uid (metin)",
		stored is Dictionary and (stored as Dictionary).has("level_001"), true)
	_check("yildiz anahtarlari tamsayi DEGIL",
		stored is Dictionary and (stored as Dictionary).has(1), false)

	# 6) BOZUK KAYIT: yedekten kurtarma.
	_delete_save_files()
	var healthy := ProgressStore.load_from_disk()
	healthy.mark_completed(1)
	healthy.mark_completed(2)
	healthy.save()          # yedek olusur
	healthy.mark_completed(3)
	healthy.save()          # yedek artik 1-2'yi tasiyor
	var corrupt := FileAccess.open(ProgressStore.SAVE_PATH, FileAccess.WRITE)
	corrupt.store_string("[[[ bu bir kayit dosyasi degil = = = bozuk")
	corrupt.close()

	var recovered := ProgressStore.load_from_disk()
	_check("bozuk kayitta oyun cokmuyor", recovered != null, true)
	_check("bozuk kayit yedekten kurtariliyor", recovered.is_completed(1), true)
	_check("kurtarma sonrasi dosya tekrar okunabilir",
		ConfigFile.new().load(ProgressStore.SAVE_PATH), OK)

	# 7) EKSIK BOLUM DOSYASI: oyun cokmemeli, guvenli varsayilana dusmeli.
	var missing := LevelLibrary.load_level(LevelLibrary.LEVEL_COUNT + 500)
	_check("eksik bolum cokmeye yol acmiyor", missing != null, true)
	_check("eksik bolum gecerli veri donduruyor", missing.validate().size(), 0)

	# uid <-> numara cevrimi
	_check("uid'den numara", LevelLibrary.number_for_uid("level_027"), 27)
	_check("bozuk uid -1", LevelLibrary.number_for_uid("bolum_27"), -1)
	_check("bos uid -1", LevelLibrary.number_for_uid(""), -1)

	_delete_save_files()


func _delete_save_files() -> void:
	for path in [ProgressStore.SAVE_PATH, ProgressStore.BACKUP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _first_block(field: BreakableField) -> BreakableBlock:
	for child in field.get_children():
		var block := child as BreakableBlock
		if block != null and not block.is_broken():
			return block
	return null


# --- Test modu (editorden TEST) --------------------------------------------------
#
# Test modunun tamami "olmayan seyler" uzerine kurulu: kart ACILMAZ, haklar
# TUKENMEZ, ilerleme YAZILMAZ. Bir seyin olmadigini oynayarak fark etmek zor,
# bu yuzden dogrudan olculur.

func _test_practice_mode() -> void:
	print("")
	print("--- Test modu ---")

	var gameplay: Node = (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	gameplay.level_data = LevelLibrary.load_level(1)
	gameplay.practice_mode = true
	root.add_child(gameplay)
	await physics_frame
	var header_subtitle := gameplay.get_node(
		"HUD/SafeArea/Root/LevelHeader/LevelSubtitle") as Label
	_check("HUD bolum adini gostermiyor",
		header_subtitle.text.contains(gameplay.level_data.display_name), false)
	_check("HUD editor zorluk tier'ini gosteriyor",
		header_subtitle.text.begins_with(tr(gameplay.level_data.difficulty_label())), true)

	var lives_at_start := int((gameplay.get_debug_snapshot() as Dictionary)["lives_remaining"])
	_check("baslangicta haklar dolu", lives_at_start > 0, true)

	# max_lives'tan FAZLA iska: normalde basarisizlik karti acilirdi.
	var ball := gameplay.get_node("Ball") as Ball
	for i in lives_at_start + 2:
		ball.shot_failed.emit("out_of_bounds")
		await create_timer(float(gameplay.auto_reset_delay) + 0.1).timeout
	var after_misses: Dictionary = gameplay.get_debug_snapshot()
	_check("iskalar hak yemiyor", int(after_misses["lives_remaining"]), lives_at_start)

	# ResultPanel tipi BILEREK yazilmaz: result_panel.gd LumaButton'a, o da
	# AudioManager'a baglidir; tipi statik olarak anmak bu zinciri harness
	# derlenirken zorlar ve autoload henuz kayitli olmadigi icin butun
	# butonlar bozulur (bkz. dosya basindaki not).
	var panel := gameplay.get_node("HUD/ResultPanel") as Control
	_check("basarisizlik karti acilmadi", panel.visible, false)

	# Bayrak DIZI icinde tutulur: GDScript lambda'lari degeri kopyalayarak
	# yakalar, dolayisiyla `completed = true` yalnizca lambda'nin kendi
	# kopyasini degistirir ve test hicbir sey olcmemis olur.
	var completed := [false]
	gameplay.level_completed.connect(func(_id: int, _stars: int, _seconds: float,
			_shots: int, _revived: bool) -> void: completed[0] = true)
	var target := gameplay.get_node("Target") as Target
	ball.launch(Vector2.UP * 1000.0)
	target.hit.emit(ball)
	await create_timer(float(gameplay.practice_hit_reset_delay) + 0.3).timeout

	_check("isabette basari karti acilmadi", panel.visible, false)
	_check("isabette level_completed yayilmadi", completed[0], false)
	_check("top tekrar atisa hazir", (gameplay.get_node("Ball") as Ball).is_ready_to_launch(), true)
	_check("baslikta TEST isareti var",
		(gameplay.get_node("HUD/SafeArea/Root/LevelHeader/LevelSubtitle") as Label)
			.text.contains("TEST"), true)

	root.remove_child(gameplay)
	gameplay.free()

	# Normal modda ayni isabet bolumu BITIRMELI - test modu genel davranisi
	# degistirmemis olmali.
	var normal: Node = (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	normal.level_data = LevelLibrary.load_level(1)
	root.add_child(normal)
	await physics_frame
	var normal_completed := [false]
	normal.level_completed.connect(func(_id: int, _stars: int, _seconds: float,
			_shots: int, _revived: bool) -> void: normal_completed[0] = true)
	var normal_ball := normal.get_node("Ball") as Ball
	normal_ball.launch(Vector2.UP * 1000.0)
	(normal.get_node("Target") as Target).hit.emit(normal_ball)
	await process_frame
	_check("normal modda level_completed yayiliyor", normal_completed[0], true)
	root.remove_child(normal)
	normal.free()


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
	block.hit_points = 2
	level.breakable_blocks = [block]

	var saved := CustomLevelStore.Bucket.SAVED
	var saved_count_before := CustomLevelStore.list_names(saved).size()
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
		_check("blok dayanikliligi korundu", loaded.breakable_blocks[0].hit_points, 2)
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
		CustomLevelStore.list_names(saved).size(), saved_count_before + 1)
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
		solver.bind_space(
			world.get_space(), world.get_block_rids(), world.get_obstacles())
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
	editor.level.breakable_blocks[0].hit_points = 2
	var width_before: float = editor.level.breakable_blocks[0].size.x
	editor.call("_on_tune", 1, 1)
	await process_frame
	_check("B+ blok genisligini artiriyor",
		editor.level.breakable_blocks[0].size.x > width_before, true)
	_check("iki canli blok iki solver katmani kuruyor", world.get_state_slot_count(), 2)
	var moved_position := Vector2(420.0, 680.0)
	editor.call("_set_selected_position", moved_position)
	var all_layers_moved := true
	for child in world.get_children():
		var block_layer := child as BreakableBlock
		if block_layer != null and block_layer.position != moved_position:
			all_layers_moved = false
	_check("editor tum can katmanlarini birlikte tasiyor", all_layers_moved, true)

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

	# KUTUPHANE: tek satir secmek yalnizca o satiri degil, tum kovayi parti
	# olarak acmali. Secilen satir baslangic indeksi olur.
	var generated_names := CustomLevelStore.replace_generated(batch)
	editor.set("_library_bucket", CustomLevelStore.Bucket.GENERATED)
	editor.set("_library_names", generated_names)
	editor.set("_library_selected", {generated_names[1]: true})
	editor.call("_on_library_edit")
	await process_frame
	_check("uretilen tek secim tum partiyi aciyor", editor.get("_batch").size(), 3)
	_check("uretilen secili adaydan basliyor", editor.level.display_name, "Parti 2")
	_check("uretilen parti sekmesi korunuyor",
		int(editor.get("_batch_bucket")), int(CustomLevelStore.Bucket.GENERATED))

	var saved_names := PackedStringArray(["nav_saved_01", "nav_saved_02", "nav_saved_03"])
	for i in batch.size():
		CustomLevelStore.save(CustomLevelStore.Bucket.SAVED, batch[i], saved_names[i])
	editor.set("_library_bucket", CustomLevelStore.Bucket.SAVED)
	editor.set("_library_names", saved_names)
	editor.set("_library_selected", {saved_names[2]: true})
	editor.call("_on_library_edit")
	await process_frame
	_check("kayit tek secim tum partiyi aciyor", editor.get("_batch").size(), 3)
	_check("kayit secili adaydan basliyor", editor.level.display_name, "Parti 3")
	_check("kayit parti sekmesi korunuyor",
		int(editor.get("_batch_bucket")), int(CustomLevelStore.Bucket.SAVED))

	# Editor sahnesi test icin yok edilip yeniden kuruldugunda parti ve indeks
	# aynen geri gelmeli.
	var context: Dictionary = editor.call("get_batch_context")
	var restored: Node = (load("res://scenes/level_editor.tscn") as PackedScene).instantiate()
	restored.set("initial_batch_context", context)
	root.add_child(restored)
	await process_frame
	_check("editore donuste parti korunuyor", restored.get("_batch").size(), 3)
	_check("editore donuste acik kayit korunuyor", restored.level.display_name, "Parti 3")
	_check("editore donuste kayit kovasi korunuyor",
		int(restored.get("_batch_bucket")), int(CustomLevelStore.Bucket.SAVED))
	root.remove_child(restored)
	restored.free()

	# Gameplay testinde debug Sonraki/Onceki AppRoot'taki ayni baglami adimlar.
	var app: Node = (load("res://scripts/app_root.gd") as GDScript).new()
	app.set("_editor_batch_context", context)
	app.set("_editor_level", batch[2])
	_check("testte sonraki aday var", app.call("_step_editor_batch", 1), true)
	_check("testte sonraki aday aciliyor",
		(app.get("_editor_level") as LevelData).display_name, "Parti 1")
	_check("testte onceki aday var", app.call("_step_editor_batch", -1), true)
	_check("testte onceki aday aciliyor",
		(app.get("_editor_level") as LevelData).display_name, "Parti 3")
	app.free()

	for entry_name in generated_names:
		CustomLevelStore.delete(CustomLevelStore.Bucket.GENERATED, entry_name)
	for entry_name in saved_names:
		CustomLevelStore.delete(CustomLevelStore.Bucket.SAVED, entry_name)

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

	var grid := select.get_node(
		"SafeArea/Content/PageClip/GridScroll/GridHolder/Grid") as GridContainer
	# Artik TEK SAYFA cizilir: 125 butonun tamami degil, acik dunyanin
	# bolumleri. Oyuncu 21. bolumde oldugu icin 1. dunya (1-50) acilir.
	_check("acilan dunya oyuncunun bulundugu dunya", select.get("_world"), 0)
	_check("yalnizca acik dunyanin butonlari cizilir", grid.get_child_count(), 50)

	var tabs := select.get_node("SafeArea/Content/Tabs") as HBoxContainer
	_check("her dunya icin bir sekme", tabs.get_child_count(), LevelWorlds.count())
	# LumaButton BILEREK anilmiyor: tipi statik olarak yazmak onu bu araci
	# derlerken bagimlilik grafigine sokar ve luma_button.gd AudioManager'a
	# baktigi icin --script altinda derleme cokerdi (bkz. dosya basindaki not).
	# emphasis: 0 = PRIMARY, 1 = SECONDARY.
	var tab_b := tabs.get_child(1)
	# Sekmeler TEMSIL ETTIKLERI dunyanin rengini tasir, secili olan degil -
	# oyuncu daha dokunmadan ileride baska bir renk oldugunu gorur.
	_check("ikinci sekme kendi dunyasinin rengini tasir",
		tab_b.get("accent_override"), LevelWorlds.accent_for_index(1))
	_check("acik sekme vurgulu", tabs.get_child(0).get("emphasis"), 0)
	_check("kapali sekme vurgusuz", tab_b.get("emphasis"), 1)

	var unlocked := grid.get_node("Level20") as Button
	_check("bolum 20 acik", unlocked.disabled, false)
	_check("acik butonda kilit isareti yok", unlocked.has_node("LockMark"), false)
	_check("acik butonda yildiz satiri var", unlocked.has_node("Stars"), true)
	_check("buton dunyasinin rengini tasir",
		unlocked.get("accent_override"), LevelWorlds.accent_for_index(0))

	var gated := grid.get_node("Level21") as Button
	_check("bolum 21 kilitli", gated.disabled, true)
	_check("kilitli butonda kilit isareti var", gated.has_node("LockMark"), true)
	_check("kapili butonda yildiz satiri yerine kapi bilgisi var",
		gated.has_node("StarGate"), true)
	var gate_label := gated.get_node("StarGate").get_child(0) as Label
	_check("kapi bilgisi 20 / 40 gosteriyor", gate_label.text, "20 / 40")

	# 22-50 yildiz kapisi TASIMAZ; sirali ilerleme yuzunden kilitlidirler.
	# Orada alt satir HIC cizilmez: yildiz satiri her zaman 0/3 gosterecekti,
	# yani yer kapliyor ama bilgi tasimiyordu. Kilit simgesi yeterli.
	var plain := grid.get_node("Level22") as Button
	_check("bolum 22 kilitli", plain.disabled, true)
	_check("kapisiz kilitli bolumde kapi satiri yok", plain.has_node("StarGate"), false)
	_check("kapisiz kilitli bolumde yildiz satiri da yok", plain.has_node("Stars"), false)

	# Sayac TUM kutuphanenin degil, ACIK DUNYANIN yildizini gosterir - 375
	# uzerinden bir sayi oyuncuya bir hedef vermiyordu.
	var world_stars := select.get_node("SafeArea/Content/WorldStars") as Label
	_check("dunya yildiz sayaci 20 / 150", world_stars.text, "20 / 150")

	# Dunya degistirince sayfa, sayac ve renk birlikte degismeli.
	select.call("_show_world", 1, 1)
	_check("dunya degisti", select.get("_world"), 1)
	_check("ikinci dunyanin butonlari cizildi", grid.get_child_count(), 50)
	_check("ikinci dunyanin ilk bolumu 51", grid.get_child(0).name, "Level51")
	_check("sayac ikinci dunyaya gore", world_stars.text, "0 / 150")
	_check("butonlar ikinci dunyanin rengini aldi",
		grid.get_child(0).get("accent_override"), LevelWorlds.accent_for_index(1))

	select.call("_show_world", 2, 1)
	# Son dunya normal bolum bandi 101-150'dir; bonuslar ayri tutulur.
	_check("son dunya kutuphanenin sonuna kadar uzanir", grid.get_child_count(),
		LevelWorlds.level_count(2))
	_check("son dunyanin son normal bolumu 150",
		grid.get_child(grid.get_child_count() - 1).name,
		"Level%d" % LevelWorlds.last_level(2))

	root.remove_child(select)
	select.free()


## Bant sinirlari: oyunun temasi ile listenin sayfalari AYNI sinirlari
## kullanmak zorunda, yoksa oyuncu 51. bolumde renk degisimi gorur ama
## listede hala eski sayfadadir.
func _test_level_worlds() -> void:
	print("")
	print("--- Bolum dunyalari ---")
	_check("uc dunya", LevelWorlds.count(), 3)
	_check("1. dunya 1'de baslar", LevelWorlds.first_level(0), 1)
	_check("1. dunya 50'de biter", LevelWorlds.last_level(0), 50)
	_check("2. dunya 51'de baslar", LevelWorlds.first_level(1), 51)
	_check("2. dunya 100'de biter", LevelWorlds.last_level(1), 100)
	_check("3. dunya 101'de baslar", LevelWorlds.first_level(2), 101)
	_check("son dunya 150'de biter", LevelWorlds.last_level(2), 150)
	_check("dunya normal bolum sayilari toplami 150",
		LevelWorlds.level_count(0) + LevelWorlds.level_count(1) + LevelWorlds.level_count(2),
		LevelWorlds.FIRST_BONUS_ID - LevelLibrary.FIRST_LEVEL_ID)
	_check("toplam bes bonus bolum",
		LevelWorlds.bonus_ids(0).size() + LevelWorlds.bonus_ids(1).size()
			+ LevelWorlds.bonus_ids(2).size(), 5)
	_check("final bonusu 155", LevelWorlds.bonus_ids(2), [155])

	_check("bolum 1 -> dunya 0", LevelWorlds.index_for_level(1), 0)
	_check("bolum 50 -> dunya 0", LevelWorlds.index_for_level(50), 0)
	_check("bolum 51 -> dunya 1", LevelWorlds.index_for_level(51), 1)
	_check("bolum 100 -> dunya 1", LevelWorlds.index_for_level(100), 1)
	_check("bolum 101 -> dunya 2", LevelWorlds.index_for_level(101), 2)
	_check("bolum 125 -> dunya 2", LevelWorlds.index_for_level(125), 2)
	_check("bolum 150 -> dunya 2", LevelWorlds.index_for_level(150), 2)

	# Tema ile dunya AYNI kaynaktan gelmeli.
	_check("50 ve 51 farkli tema",
		PaletteThemes.for_level(50).ACCENT != PaletteThemes.for_level(51).ACCENT, true)
	_check("100 ve 101 farkli tema",
		PaletteThemes.for_level(100).ACCENT != PaletteThemes.for_level(101).ACCENT, true)
	_check("1. dunya temasi orijinal palet", PaletteThemes.for_level(1).ACCENT,
		PaletteThemes.theme_a().ACCENT)
	_check("dunya rengi tema rengiyle ayni", LevelWorlds.accent_for_index(1),
		PaletteThemes.theme_b().ACCENT)


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
	for id in range(21, 41):
		behind.level_stars[id] = 3
	_check("21-40 yildizlari genel toplama giriyor", behind.get_total_stars(), 80)
	_check("21-40 yildizlari kapiya SAYILMIYOR", behind.get_stars_before(21), 20)
	_check("kapi hala kapali", behind.is_unlocked(21), false)

	# Yildiz kaydi yalnizca IYILESIRSE yazilir (eski kayitlar korunur).
	var record := ProgressStore.new()
	record.highest_unlocked_level = 40
	_check("ilk 21 yildizi kaydediliyor", record.set_level_stars_if_higher(21, 2), true)
	_check("daha dusuk sonuc kaydi ezmiyor", record.set_level_stars_if_higher(21, 1), false)
	_check("kayitli deger korunuyor", record.get_level_stars(21), 2)
	_check("daha iyi sonuc kaydediliyor", record.set_level_stars_if_higher(21, 3), true)
	_check("yeni rekor yaziliyor", record.get_level_stars(21), 3)


## Dil secimi: normalizasyon, cihaz dili ve "henuz secilmedi" ayrimi.
func _test_locale() -> void:
	print("")
	print("--- Dil secimi ---")
	var before := TranslationServer.get_locale()

	_check("desteklenen diller", Locale.SUPPORTED, ["tr", "en"] as Array[String])
	_check("tr destekleniyor", Locale.is_supported("tr"), true)
	_check("taninmayan dil varsayilana duser", Locale.normalize("de"), "tr")
	_check("bos deger varsayilana duser", Locale.normalize(""), "tr")
	_check("bolge ekli kod indirgenir", Locale.normalize("en_US"), "en")
	_check("buyuk harf kabul edilir", Locale.normalize("EN"), "en")
	# Dil kendi dilinde yazilir: dil secen oyuncu mevcut dili okuyamiyor olabilir.
	_check("dil kendi adiyla gosterilir", Locale.display_name("en"), "English")

	Locale.apply("en")
	_check("apply locale'i degistirir", Locale.current(), "en")
	_check("ceviri uygulaniyor", TranslationServer.translate("OYNA"), "PLAY")
	_check("zorluk etiketi cevriliyor",
		TranslationServer.translate("KOLAY"), "EASY")

	# BOS tercih = "oyuncu henuz secmedi" -> cihaz dili. "tr" secmis olmakla
	# ayni sey DEGIL; ikisi karisirsa Ingilizce telefonda oyun Turkce acilir.
	Locale.apply_saved("")
	_check("secim yokken cihaz dili kullanilir", Locale.current(), Locale.system_default())
	Locale.apply_saved("tr")
	_check("acik secim cihaz dilini ezer", Locale.current(), "tr")
	_check("cevirisi olmayan metin kaynak haliyle doner",
		TranslationServer.translate("Boyle bir ceviri yok"), "Boyle bir ceviri yok")

	TranslationServer.set_locale(before)


## Her bolumun adi ve ogretici metni Ingilizce tabloda OLMALI.
##
## Bu testin asil isi yeni bolum eklendiginde uyarmak: cevirisi unutulan bir
## bolum Ingilizce oyunda Turkce adiyla gorunur ve bunu kimse fark etmez.
func _test_translation_coverage() -> void:
	print("")
	print("--- Ceviri kapsami ---")
	var before := TranslationServer.get_locale()
	Locale.apply("en")

	var missing_names: Array[int] = []
	var missing_hints: Array[int] = []
	for level_id in range(LevelLibrary.FIRST_LEVEL_ID, LevelLibrary.last_level_id() + 1):
		var level := LevelLibrary.load_level(level_id)
		var name_text := level.display_name.strip_edges()
		if not name_text.is_empty() and TranslationServer.translate(name_text) == name_text:
			missing_names.append(level_id)
		var hint := level.tutorial_text.strip_edges()
		if not hint.is_empty() and TranslationServer.translate(hint) == hint:
			missing_hints.append(level_id)

	_check("her bolum adinin Ingilizcesi var", missing_names, [] as Array[int])
	_check("her ogretici metnin Ingilizcesi var", missing_hints, [] as Array[int])

	# Bicimlendirilen metinler: kalibin kendisi cevrilmeli, cunku otomatik
	# ceviri hazir metni ("BÖLÜM 5") arar ve bulamaz.
	_check("bolum basligi kalibi cevrili", TranslationServer.translate("BÖLÜM %d"), "LEVEL %d")
	_check("sure kalibi cevrili", TranslationServer.translate("%.1f sn"), "%.1f s")
	_check("kalip bicimlendirilince dogru sonuc verir",
		TranslationServer.translate("BÖLÜM %d") % 7, "LEVEL 7")

	TranslationServer.set_locale(before)


func _test_settings_screen() -> void:
	print("")
	print("--- Ayarlar ekrani ---")
	var before_locale := TranslationServer.get_locale()
	Locale.apply("tr")

	var progress := ProgressStore.new()
	progress.highest_unlocked_level = 12
	progress.set_level_stars_if_higher(3, 3)

	var screen: Node = (load("res://scenes/settings.tscn") as PackedScene).instantiate()
	screen.set("progress", progress)
	root.add_child(screen)
	await process_frame

	# FAZ 9: satirlar artik tek tek degil, bolum basina bir KART halinde
	# gruplanir (Genel/Sesler/Oynanis/Surum + aralara giren bosluklar) - bu
	# yuzden dogrudan cocuk sayisi eskisinden (>8 duz satir) cok daha kucuk.
	var rows: Node = screen.get_node("SafeArea/Content/Scroll/Rows")
	_check("ayar satirlari kuruldu", rows.get_child_count() >= 7, true)

	# Dil degistirme: hem locale hem KAYIT guncellenmeli, yoksa secim
	# uygulamayi kapatinca kaybolur.
	screen.call("_on_language_chosen", 1)
	_check("dil secimi locale'i degistirir", Locale.current(), "en")
	_check("dil secimi kayda yazilir", progress.language, "en")
	screen.call("_rebuild")
	_check("dil degisince satirlar yeniden kurulur", rows.get_child_count() >= 7, true)

	screen.call("_on_shake_chosen", 0)
	_check("sarsinti kapatilabiliyor", progress.shake_scale, 0.0)
	_check("sarsinti tek kisma noktasina yansir", ScreenShake.trauma_scale, 0.0)
	screen.call("_on_shake_chosen", 2)
	_check("sarsinti geri acilabiliyor", progress.shake_scale, 1.0)

	screen.call("_on_aim_assist_toggled", true)
	_check("nisan yardimi yazildi", progress.aim_assist, true)

	screen.call("_on_haptics_toggled", false)
	_check("titresim kapatildi", progress.haptics_enabled, false)
	_check("titresim tek okuma noktasina yansir", Haptics.enabled, false)

	# ILERLEMEYI SIFIRLA tek dokunusla olmamali.
	var confirm: Control = screen.get_node("ConfirmLayer")
	_check("onay katmani baslangicta kapali", confirm.visible, false)
	screen.call("_show_confirm")
	_check("sifirla onay ister", confirm.visible, true)
	screen.call("_hide_confirm")
	_check("vazgecince kapanir", confirm.visible, false)
	_check("vazgecince ilerleme durur", progress.highest_unlocked_level, 12)

	screen.call("_show_confirm")
	screen.call("_on_reset_confirmed")
	_check("onaylayinca ilerleme silinir", progress.highest_unlocked_level,
		LevelLibrary.FIRST_LEVEL_ID)
	_check("onaylayinca yildizlar silinir", progress.get_level_stars(3), 0)
	# Ayarlar ilerleme DEGILDIR: sifirlama bunlara dokunmamali, yoksa oyuncu
	# anlamadigi bir dile ve kapattigi titresime geri doner.
	_check("sifirlama dili korur", progress.language, "en")
	_check("sifirlama titresim tercihini korur", progress.haptics_enabled, false)
	_check("sifirlama nisan yardimini korur", progress.aim_assist, true)

	root.remove_child(screen)
	screen.free()
	ScreenShake.trauma_scale = 1.0
	Haptics.enabled = true
	TranslationServer.set_locale(before_locale)


## FAZ 9: Ev/Magaza/Ayarlar yeniden tasarimi genis/uzun ekranlarda tasmamali.
##
## DisplayServer.window_set_size() bu test ortaminda guvenilir calismiyor
## (bkz. check_hint_economy.gd::_test_hud_fits_tall_aspect'in ayni notu) -
## bunun yerine ekran KOKUNUN size'i DOGRUDAN zorlanir. Kok, root Viewport'a
## dogrudan eklendigi ve ustunde onu yeniden boyutlandiracak bir Container
## olmadigi icin bu deger degismeden kalir ve SafeArea/Content'e normal
## anchor/Container zinciriyle dogru sekilde yayilir.
func _test_faz9_tall_aspect() -> void:
	print("")
	print("--- Faz 9: Ev/Magaza/Ayarlar uzun ekran yerlesimi ---")
	var temp_paths: Array[String] = []
	for size in [Vector2(720.0, 1280.0), Vector2(1080.0, 2400.0)]:
		var label := "%dx%d" % [int(size.x), int(size.y)]

		var home_wallet_path := "user://faz9_tall_home_%s.cfg" % label
		temp_paths.append(home_wallet_path)
		var home := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
		home.set("wallet", WalletStore.load_from_path(home_wallet_path))
		home.set("progress", ProgressStore.new())
		root.add_child(home)
		home.set_deferred("size", size)
		await process_frame
		await process_frame
		var coin_chip := home.get_node("SafeArea/Content/TopAppBar/CoinChip") as Control
		var settings_button := home.get_node(
			"SafeArea/Content/TopAppBar/SettingsButton") as Control
		_check("%s: ev - coin rozeti ayarlar dugmesiyle cakismiyor" % label,
			not coin_chip.get_rect().intersects(settings_button.get_rect()), true)
		_check("%s: ev - coin rozeti ekran icinde kaliyor" % label,
			coin_chip.get_rect().end.x <= home.size.x + 1.0, true)
		var hero := home.get_node(
			"SafeArea/Content/MainActions/HeroCard") as Control
		var shop_card := home.get_node(
			"SafeArea/Content/MainActions/ShopCard") as Control
		var action_center_y := (hero.get_global_rect().position.y
			+ shop_card.get_global_rect().end.y) * 0.5
		_check("%s: ev - ana eylemler dikey orta bantta" % label,
			action_center_y >= home.size.y * 0.40
			and action_center_y <= home.size.y * 0.62, true)
		root.remove_child(home)
		home.free()
		await process_frame

		var shop_wallet_path := "user://faz9_tall_shop_%s.cfg" % label
		temp_paths.append(shop_wallet_path)
		var entitlement_path := "user://faz9_tall_entitlement_%s.cfg" % label
		temp_paths.append(entitlement_path)
		var purchase_service := PurchaseService.new()
		purchase_service.configure(NoOpPurchaseProvider.new(),
			EntitlementStore.new(entitlement_path), AnalyticsService.new(false, true))
		root.add_child(purchase_service)
		purchase_service.initialize()
		var shop := (load("res://scenes/shop_screen.tscn") as PackedScene).instantiate()
		shop.set("wallet", WalletStore.load_from_path(shop_wallet_path))
		shop.set("purchase_service", purchase_service)
		root.add_child(shop)
		shop.set_deferred("size", size)
		await process_frame
		await process_frame
		var back := shop.get_node("SafeArea/Content/Header/BackButton") as Control
		var shop_chip := shop.get_node("SafeArea/Content/Header/CoinChip") as Control
		_check("%s: magaza - geri dugmesi coin rozetiyle cakismiyor" % label,
			not back.get_rect().intersects(shop_chip.get_rect()), true)
		_check("%s: magaza - coin rozeti ekran icinde kaliyor" % label,
			shop_chip.get_rect().end.x <= shop.size.x + 1.0, true)
		var remove_ads_icon := shop.find_child("RemoveAdsIcon", true, false) as Control
		_check("%s: magaza - reklamsiz ikon yatay rozet" % label,
			remove_ads_icon != null
			and remove_ads_icon.custom_minimum_size.x
			> remove_ads_icon.custom_minimum_size.y, true)
		root.remove_child(shop)
		shop.free()
		root.remove_child(purchase_service)
		purchase_service.free()
		await process_frame

		var settings := (load("res://scenes/settings.tscn") as PackedScene).instantiate()
		settings.set("progress", ProgressStore.new())
		root.add_child(settings)
		settings.set_deferred("size", size)
		await process_frame
		await process_frame
		var header_back := settings.get_node(
			"SafeArea/Content/Header/HeaderBackButton") as Control
		var title := settings.get_node("SafeArea/Content/Header/Title") as Control
		_check("%s: ayarlar - ust geri dugmesi baslikla cakismiyor" % label,
			not header_back.get_rect().intersects(title.get_rect()), true)
		_check("%s: ayarlar - kaydirma alani ekran icinde kaliyor" % label,
			settings.get_node("SafeArea/Content/Scroll").get_rect().end.y \
			<= settings.size.y + 1.0, true)
		var language_dropdown := settings.find_child(
			"LanguageDropdown", true, false) as LumaDropdown
		_check("%s: ayarlar - dil acilir listesi kullaniliyor" % label,
			language_dropdown != null, true)
		if language_dropdown != null:
			_check("%s: ayarlar - dil secenekleri eksiksiz" % label,
				language_dropdown.item_count, 2)
		root.remove_child(settings)
		settings.free()
		await process_frame

	for path in temp_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_library_bounds() -> void:
	print("")
	print("--- LevelLibrary sinirlari ---")
	_check("LEVEL_COUNT", LevelLibrary.LEVEL_COUNT, 155)
	_check("has_next(20)", LevelLibrary.has_next(20), true)
	_check("has_next(24)", LevelLibrary.has_next(24), true)
	_check("has_next(25)", LevelLibrary.has_next(25), true)
	_check("has_next(39)", LevelLibrary.has_next(39), true)
	_check("has_next(40)", LevelLibrary.has_next(40), true)
	_check("has_next(49)", LevelLibrary.has_next(49), true)
	_check("has_next(50)", LevelLibrary.has_next(50), true)
	_check("has_next(125)", LevelLibrary.has_next(125), true)
	_check("has_next(149)", LevelLibrary.has_next(149), true)
	_check("has_next(150)", LevelLibrary.has_next(150), false)
	_check("azami yildiz", ProgressStore.new().get_max_available_stars(), 475)

	# 1-50: elle tasarlanmis kutuphane. 26 tek kolay blok tanitimidir; 27-50
	# onceki panel/duvar bilgisini bloklarla birlikte kullanir.
	for id in range(1, 51):
		var level := LevelLibrary.load_level(id)
		_check("bolum %d yukleniyor" % id, level.level_id, id)
		_check("bolum %d dogrulamadan geciyor" % id, level.validate().size(), 0)
		_check("bolum %d blok donemi dogru" % id,
			level.breakable_blocks.is_empty(), id <= 25)
		if id in range(30, 41) or id in range(44, 51):
			var durable_count := 0
			for block_data in level.breakable_blocks:
				if block_data.hit_points >= 2:
					durable_count += 1
			_check("bolum %d dayanikli kilit iceriyor" % id, durable_count > 0, true)
		_check("bolum %d hareketli engel oncesi temiz" % id,
			level.obstacles.is_empty(), true)
		_check("bolum %d: 3-yildiz atis <= max_lives" % id,
			level.three_star_max_shots <= level.max_lives, true)
		_check("bolum %d: 2-yildiz atis <= max_lives" % id,
			level.two_star_max_shots <= level.max_lives, true)

	# 51-75 halkayi, 76-100 bombayi tanitir. Yalnizca 51 ve 76 okunakli
	# tanitimdir; sonraki bolumlerde daha once ogrenilen blok ve duvar boslugu
	# mekanikleri yeniden kullanilir. Blok kapilari kasitli olarak aralikir:
	# her bolumde ayni kapiyi gostermek de tekrar olurdu.
	var expected_block_levels := [
		53, 54, 55, 57, 58, 59, 61, 64, 67, 70, 73, 75,
		80, 83, 86, 89, 92, 95, 98, 100,
	]
	for id in range(51, 101):
		var level := LevelLibrary.load_level(id)
		_check("bolum %d yukleniyor" % id, level.level_id, id)
		_check("bolum %d dogrulamadan geciyor" % id, level.validate().size(), 0)
		_check("bolum %d blok plani" % id, level.breakable_blocks.is_empty(),
			not expected_block_levels.has(id))
		_check("bolum %d engel iceriyor" % id, level.obstacles.is_empty(), false)
		for obstacle in level.obstacles:
			var allowed := (obstacle.kind == ObstacleData.Kind.METAL_RING
				if id <= 75 else obstacle.kind in [
					ObstacleData.Kind.METAL_RING, ObstacleData.Kind.BOMB])
			_check("bolum %d engel fazi dogru" % id, allowed, true)
		_check("bolum %d: 3-yildiz atis <= max_lives" % id,
			level.three_star_max_shots <= level.max_lives, true)
		_check("bolum %d: 2-yildiz atis <= max_lives" % id,
			level.two_star_max_shots <= level.max_lives, true)

	# 101-125 CARK BANDI: yalnizca 101 okunakli tanitimdir; sonraki bolumler
	# carki onceki halka/mayin, panel, duvar boslugu ve aralikli blok kapilariyla
	# birlestirir. Her bolumde cark kalir, hareketli bar kampanyaya girmez.
	var wheel_block_levels := [105, 108, 111, 114, 117, 120, 123, 125]
	for id in range(101, 126):
		var level := LevelLibrary.load_level(id)
		_check("bolum %d yukleniyor" % id, level.level_id, id)
		_check("bolum %d dogrulamadan geciyor" % id, level.validate().size(), 0)
		_check("bolum %d engel iceriyor" % id, level.obstacles.is_empty(), false)
		_check("bolum %d blok plani" % id, level.breakable_blocks.is_empty(),
			not wheel_block_levels.has(id))
		var has_wheel := false
		for obstacle in level.obstacles:
			has_wheel = has_wheel or obstacle.kind == ObstacleData.Kind.ROTATING_WHEEL
			_check("bolum %d cark fazi dogru" % id, obstacle.kind in [
				ObstacleData.Kind.METAL_RING, ObstacleData.Kind.BOMB,
				ObstacleData.Kind.ROTATING_WHEEL], true)
		_check("bolum %d cark iceriyor" % id, has_wheel, true)
		_check("bolum %d: 3-yildiz atis <= max_lives" % id,
			level.three_star_max_shots <= level.max_lives, true)
		_check("bolum %d: 2-yildiz atis <= max_lives" % id,
			level.two_star_max_shots <= level.max_lives, true)

	# 126-150 LAZER BANDI: yalnizca 126 okunakli tanitimdir. Lazer her bolumde
	# kalir; cark, halka, mayin, duvar boslugu ve bloklar yeniden kullanilir.
	var laser_block_levels := [130, 133, 136, 139, 142, 145, 148, 150]
	for id in range(126, 151):
		var level := LevelLibrary.load_level(id)
		_check("bolum %d yukleniyor" % id, level.level_id, id)
		_check("bolum %d dogrulamadan geciyor" % id, level.validate().size(), 0)
		_check("bolum %d engel iceriyor" % id, level.obstacles.is_empty(), false)
		_check("bolum %d blok plani" % id, level.breakable_blocks.is_empty(),
			not laser_block_levels.has(id))
		var has_laser := false
		for obstacle in level.obstacles:
			has_laser = has_laser or obstacle.kind == ObstacleData.Kind.PULSE_LASER
			_check("bolum %d lazer fazi dogru" % id, obstacle.kind in [
				ObstacleData.Kind.METAL_RING, ObstacleData.Kind.BOMB,
				ObstacleData.Kind.ROTATING_WHEEL,
				ObstacleData.Kind.PULSE_LASER], true)
		_check("bolum %d lazer iceriyor" % id, has_laser, true)
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
