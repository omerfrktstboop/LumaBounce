extends SceneTree

## Luma Coin / ipucu regresyonu. Gercek user://wallet.cfg dosyasina dokunmaz;
## her kosuda benzersiz gecici cuzdanlar kullanir.

var _failures := 0
var _paths: Array[String] = []
var _owned_audio_manager: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_register_audio_manager()
	_test_wallet_contract()
	await _test_hint_coverage()
	await _test_full_hint_reward_flow()
	await _test_short_hint()
	await _test_broken_hint_never_charges()
	await _test_hud_fits_tall_aspect()
	await _test_pause_card()
	for path in _paths:
		_cleanup_wallet(path)
	await _unregister_audio_manager()
	if _failures == 0:
		print("PASS hint economy: 150 valid routes, persistent display, retry entitlement, wallet, HUD, pause")
		quit(0)
	else:
		push_error("FAIL hint economy: %d assertion(s)" % _failures)
		quit(1)


func _test_wallet_contract() -> void:
	var path := _new_wallet_path("contract")
	var wallet := WalletStore.load_from_path(path)
	_check(wallet.balance == CoinEconomy.STARTING_COINS,
		"new wallet grants the configured starting balance")
	_check(not wallet.grant_hint_unlock(""), "empty level uid is rejected")
	_check(wallet.grant_hint_unlock("level_041"), "rewarded hint unlock succeeds")
	_check(wallet.balance == CoinEconomy.STARTING_COINS,
		"rewarded hint unlock spends no Coin")
	_check(wallet.grant_hint_unlock("level_041"), "repeated unlock is idempotent")
	_check(wallet.balance == CoinEconomy.STARTING_COINS,
		"repeated rewarded unlock still costs nothing")

	var reloaded := WalletStore.load_from_path(path)
	_check(reloaded.is_hint_unlocked("level_041"), "hint unlock survives reload")
	_check(reloaded.balance == CoinEconomy.STARTING_COINS,
		"rewarded unlock leaves persisted balance unchanged")
	reloaded.add(1)
	_check(reloaded.balance == CoinEconomy.STARTING_COINS + 1
		and reloaded.earned_total == 1, "coin rewards are recorded")


func _test_hint_coverage() -> void:
	var missing: Array[int] = []
	var invalid: Array[int] = []
	var solver := LevelSolver.from_scenes()
	# Yalnizca aci/guc alaninin dolu olmasi yetmez. Kayitli atisi gercek
	# LevelWorld ve LevelSolver ile oynatip rotanin cizilebilir oldugunu denetle.
	for level_id in range(LevelLibrary.FIRST_LEVEL_ID, LevelLibrary.last_level_id() + 1):
		var level := load(LevelLibrary.level_path(level_id)) as LevelData
		if level == null or not level.has_hint():
			missing.append(level_id)
			continue
		var world := LevelWorld.new()
		root.add_child(world)
		world.build(level)
		await physics_frame
		await physics_frame
		solver.bind_space(world.get_space(), world.get_block_rids(), world.get_obstacles())
		var excluded := world.rids_for_state(world.get_all_broken_state())
		var direction := Vector2.UP.rotated(deg_to_rad(level.hint_angle_degrees))
		var result := solver.simulate(
			solver.spawn_position(level.launcher_position), direction * level.hint_power,
			level.target_position, world.get_play_rect(), excluded, true)
		if not bool(result.get("hit", false)) \
				or (result.get("trace_points", PackedVector2Array()) as PackedVector2Array).size() < 2:
			invalid.append(level_id)
		root.remove_child(world)
		world.queue_free()
		await process_frame
	_check(missing.is_empty(), "all 150 campaign levels have hint shots")
	_check(invalid.is_empty(), "all 150 campaign hint shots reach the target")
	if not missing.is_empty():
		push_error("Missing hint levels: %s" % str(missing))
	if not invalid.is_empty():
		push_error("Invalid hint levels: %s" % str(invalid))


func _test_full_hint_reward_flow() -> void:
	var path := _new_wallet_path("gameplay")
	var wallet := WalletStore.load_from_path(path)
	var level := load("res://levels/level_41.tres") as LevelData
	_check(level != null and level.has_hint(), "fixture level has an offline hint")
	if level == null or not level.has_hint():
		return

	# Gameplay tipi burada bilerek statik olarak anilmaz: --script autoload'lari
	# kurmadigi icin AudioManager once yukarida elle kaydedilmelidir.
	var scene := load("res://scenes/gameplay.tscn") as PackedScene
	_check(scene != null, "gameplay scene loads after AudioManager registration")
	if scene == null:
		return
	var gameplay := scene.instantiate()
	_check(gameplay != null, "gameplay scene instantiates")
	if gameplay == null:
		return
	gameplay.set("level_data", level)
	gameplay.set("wallet", wallet)
	root.add_child(gameplay)
	await process_frame
	await physics_frame
	await physics_frame

	var initial_balance := wallet.balance
	gameplay.set("full_hint_enabled", true)

	var initial: Dictionary = gameplay.call("get_debug_snapshot")
	_check(bool(initial["hint_available"]), "gameplay exposes available hint")
	_check(not bool(initial["hint_unlocked"]), "hint starts locked")
	gameplay.call("_on_hint_pressed")
	_check((gameplay.get_node("HUD/HintPurchaseCard") as Control).visible,
		"first tap opens purchase confirmation")
	_check(wallet.balance == initial_balance, "opening hint choices does not spend")
	var options := gameplay.get_node("HUD/HintPurchaseCard/CardCenter/Card/Margin/Rows/Options")
	_check(not (options.get_node("FullOption") as Button).disabled,
		"full route is available when rewarded ad is ready")

	gameplay.call("_on_full_hint_requested")
	gameplay.call("grant_full_hint")
	var rewarded: Dictionary = gameplay.call("get_debug_snapshot")
	_check(wallet.balance == initial_balance, "rewarded full route spends no Coin")
	_check(bool(rewarded["hint_unlocked"]), "reward permanently unlocks level hint")
	_check(not bool(rewarded["hint_visible"]), "block level waits before drawing final route")

	var blocks := gameplay.get_node("Blocks") as BreakableField
	blocks.shatter_in_radius(Vector2(360.0, 640.0), 2000.0)
	await process_frame
	await physics_frame
	await process_frame
	var revealed: Dictionary = gameplay.call("get_debug_snapshot")
	_check(bool(revealed["hint_visible"]),
		"route appears after all blocks are broken")
	gameplay.call("_on_shot_fired", Vector2(0.0, -1800.0))
	_check(bool(gameplay.call("get_debug_snapshot")["hint_visible"]),
		"full route remains visible while the ball is flying")

	gameplay.call("reset_shot")
	gameplay.call("_on_hint_pressed")
	_check(wallet.balance == initial_balance,
		"unlocked rewarded hint never charges after restart")
	_check(not (gameplay.get_node("HUD/HintPurchaseCard") as Control).visible,
		"unlocked hint bypasses purchase modal")

	root.remove_child(gameplay)
	gameplay.queue_free()
	await process_frame


## KISA IPUCU: Coin ile bir kez alinir, bolum oturumunda yeniden denemelerde
## korunur ve rotanin yalnizca bir parcasi olarak kalir.
##
## Bu testin asil isi uc sozlesmeyi korumak: kisa ipucu tam fiyatini harcar,
## reklam istemez ve tam rotanin yerine gecmez.
func _test_short_hint() -> void:
	var path := _new_wallet_path("shorthint")
	var wallet := WalletStore.load_from_path(path)
	# Bloksuz VE kayitli ipucusu calisma aninda gercekten hedefe ulasan bir
	# bolum secilir: kisa ipucu blok bekleme yoluna girmemeli ve fixture'in
	# kendisi bozuk olmamali.
	var level := load("res://levels/level_60.tres") as LevelData
	_check(level != null and level.has_hint(), "short-hint fixture has an offline hint")
	if level == null or not level.has_hint():
		return

	var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	gameplay.set("level_data", level)
	gameplay.set("wallet", wallet)
	root.add_child(gameplay)
	await process_frame
	await physics_frame
	await physics_frame

	var card := gameplay.get_node("HUD/HintPurchaseCard") as Control

	var short_cost := int(gameplay.get("short_hint_cost"))
	var balance_before := wallet.balance
	gameplay.set("full_hint_enabled", false)
	gameplay.call("_on_hint_pressed")
	_check(card.visible, "hint tap opens the single two-option card")
	var options := card.get_node("CardCenter/Card/Margin/Rows/Options")
	_check(options.get_child_count() == 2, "card offers exactly two options")
	_check(options.has_node("ShortOption"), "short option row exists")
	_check(options.has_node("FullOption"), "full route row exists")
	_check(not (options.get_node("ShortOption") as Button).disabled,
		"short hint is available with enough Coin")
	_check((options.get_node("FullOption") as Button).disabled,
		"full route is disabled while rewarded ad is unavailable")
	gameplay.call("_on_short_hint_requested")
	var granted: Dictionary = gameplay.call("get_debug_snapshot")
	_check(bool(granted["hint_visible"]), "purchased short hint draws a route")
	_check(wallet.balance == balance_before - short_cost,
		"short hint spends exactly its Coin cost")
	_check(not bool(granted["hint_unlocked"]),
		"short hint is not a permanent unlock")
	_check(bool(granted["short_hint_unlocked"]),
		"short hint records a level-session entitlement")

	# Kisa rota TAM rotadan gercekten kisa olmali - yoksa tam rotayi satin
	# almanin bir anlami kalmaz.
	var full: PackedVector2Array = gameplay.call("_build_hint_trace")
	var short_trace: PackedVector2Array = gameplay.call("_build_short_hint_trace")
	_check(short_trace.size() >= 2, "short trace has drawable geometry")
	_check(_arc_length(short_trace) < _arc_length(full) * 0.65,
		"short trace stays well below the full route length")
	_check(short_trace[0].is_equal_approx(full[0]),
		"short trace starts at the same launch point")

	# Ustteki ipucu simgesi rotayi kapatir; tekrar dokunmak Coin harcamadan acar.
	var paid_balance := wallet.balance
	gameplay.call("_on_hint_pressed")
	_check(not bool(gameplay.call("get_debug_snapshot")["hint_visible"]),
		"top hint icon hides the visible route")
	gameplay.call("_on_hint_pressed")
	_check(bool(gameplay.call("get_debug_snapshot")["hint_visible"]),
		"second icon tap reopens the paid short route")
	_check(wallet.balance == paid_balance and not card.visible,
		"reopening a short route neither charges Coin nor opens an offer")

	# Atis baslayinca cizgi arka planda kalir; bolum tamamlaninca kapanir.
	gameplay.call("_on_shot_fired", Vector2(0.0, -1800.0))
	_check(bool(gameplay.call("get_debug_snapshot")["hint_visible"]),
		"short route remains visible while the ball is flying")
	gameplay.call("_on_target_hit", null)
	_check(not bool(gameplay.call("get_debug_snapshot")["hint_visible"]),
		"route hides when the level is completed")

	# Yeniden deneme rotayi kapatir ama odenmis hakki korur. Bakiye artik
	# yetersiz olsa bile simge ayni ipucunu ucretsiz acar.
	gameplay.call("reset_shot")
	_check(not bool(gameplay.call("get_debug_snapshot")["hint_visible"]),
		"restart begins with the route hidden")
	gameplay.call("_on_hint_pressed")
	_check(bool(gameplay.call("get_debug_snapshot")["hint_visible"]),
		"restart reopens the paid short route for free")
	_check(wallet.balance == paid_balance and not card.visible,
		"restart never repeats the Coin/ad offer for that short route")

	# Son top hakki bittiginde rota kapanir. Sonuc kartindan tekrar baslatinca
	# ayni oturum hakki bir kez daha ucretsiz kullanilir.
	gameplay.set("_lives_remaining", 1)
	gameplay.call("_consume_life")
	_check(not bool(gameplay.call("get_debug_snapshot")["hint_visible"]),
		"route hides as soon as all ball rights are exhausted")
	gameplay.call("_on_hint_pressed")
	_check(not bool(gameplay.call("get_debug_snapshot")["hint_visible"]),
		"hint cannot reopen before the out-of-balls result is retried")
	gameplay.call("reset_shot")
	gameplay.call("_on_hint_pressed")
	_check(bool(gameplay.call("get_debug_snapshot")["hint_visible"]),
		"after out-of-balls retry the same short hint opens for free")
	_check(wallet.balance == paid_balance and not card.visible,
		"out-of-balls retry preserves the paid entitlement")

	root.remove_child(gameplay)
	gameplay.queue_free()
	await process_frame

	# Bolum ekranindan cikmak kisa ipucu oturum hakkini bitirir. Yeni Gameplay
	# orneginde bakiye yetmiyorsa Coin kesilmez ve reklam yonlendirmesi gorunur.
	var insufficient_gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	insufficient_gameplay.set("level_data", level)
	insufficient_gameplay.set("wallet", wallet)
	root.add_child(insufficient_gameplay)
	await process_frame
	await physics_frame
	await physics_frame
	var insufficient_balance := wallet.balance
	_check(insufficient_balance < short_cost,
		"fixture balance is insufficient in a new level session")
	insufficient_gameplay.call("_on_hint_pressed")
	insufficient_gameplay.call("_on_short_hint_requested")
	_check(wallet.balance == insufficient_balance,
		"insufficient short hint spends nothing")
	_check(not bool(insufficient_gameplay.call("get_debug_snapshot")["hint_visible"]),
		"insufficient short hint draws no route")
	var status := insufficient_gameplay.get_node("HUD/SafeArea/Root/HintStatus/Text") as Label
	_check(status.text == tr("COIN YOK · REKLAM İZLE"),
		"insufficient Coin shows the watch-ad guidance")
	root.remove_child(insufficient_gameplay)
	insufficient_gameplay.queue_free()
	await process_frame


## BOZUK IPUCU VERISI COIN KESMEZ.
##
## Kayitli aci/guc eski bir geometriye aitse rota hedefe ulasmaz. O durumda
## kart hic acilmamali ve bakiyeye dokunulmamali - oyuncu calismayan bir sey
## icin odememeli.
func _test_broken_hint_never_charges() -> void:
	var path := _new_wallet_path("brokenhint")
	var wallet := WalletStore.load_from_path(path)
	var level := (load("res://levels/level_60.tres") as LevelData).duplicate(true) as LevelData
	# Hedefe asla ulasmayan bir atis: guc gecerli ama aci tamamen ters.
	level.hint_angle_degrees = 179.0
	level.hint_power = 400.0

	var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	gameplay.set("level_data", level)
	gameplay.set("wallet", wallet)
	root.add_child(gameplay)
	await process_frame
	await physics_frame
	await physics_frame

	gameplay.call("_on_hint_pressed")
	_check(not (gameplay.get_node("HUD/HintPurchaseCard") as Control).visible,
		"broken hint data never opens the purchase card")
	_check(wallet.balance == CoinEconomy.STARTING_COINS,
		"broken hint data never charges Luma Coin")
	_check(not wallet.is_hint_unlocked(level.uid()),
		"broken hint data never marks the level unlocked")

	root.remove_child(gameplay)
	gameplay.queue_free()
	await process_frame


## HUD 720x1280 ve 1080x2400 gibi farkli oranlarda guvenli alanda kalmali.
##
## Jeton rozeti ile ipucu dugmesi ust seritte KARSI koselerde durur; dar bir
## ekranda ust uste binerlerse ikisi de okunmaz hale gelir.
func _test_hud_fits_tall_aspect() -> void:
	var level := load("res://levels/level_60.tres") as LevelData
	for size in [Vector2i(720, 1280), Vector2i(1080, 2400)]:
		var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
		gameplay.set("level_data", level)
		gameplay.set("wallet", WalletStore.load_from_path(_new_wallet_path("hud")))
		root.add_child(gameplay)
		# Test ortaminda pencere boyutu degistirilemedigi icin HUD kokunun
		# boyutu dogrudan zorlanir; yerlesim anchor tabanli oldugu icin sonuc
		# gercek cihazdakiyle ayni olur.
		var hud_root := gameplay.get_node("HUD/SafeArea/Root") as Control
		hud_root.size = Vector2(size)
		await process_frame
		await process_frame

		var chip := gameplay.get_node("HUD/SafeArea/Root/CoinChip") as Control
		var button := gameplay.get_node("HUD/SafeArea/Root/HintButton") as Control
		var label := "%dx%d" % [size.x, size.y]
		_check(chip.get_rect().position.x >= 0.0, "%s: coin chip stays inside" % label)
		_check(button.get_rect().end.x <= hud_root.size.x + 1.0,
			"%s: hint button stays inside" % label)
		# Jeton rozeti ile ipucu dugmesi artik AYNI KOSEDE ama farkli
		# satirlarda. Dogru degismez x araliklarinin ayrikligi degil,
		# DIKDORTGENLERIN kesismemesidir.
		_check(not chip.get_rect().intersects(button.get_rect()),
			"%s: coin chip and hint button never overlap" % label)
		var pause := gameplay.get_node("HUD/SafeArea/Root/PauseButton") as Control
		_check(not pause.get_rect().intersects(button.get_rect()),
			"%s: hint and pause buttons never overlap" % label)
		_check(button.get_rect().end.x <= pause.get_rect().position.x,
			"%s: hint button sits left of pause" % label)
		# Jeton SOLDA, kontrol butonlari SAGDA: iki grup birbirine karismamali.
		_check(chip.get_rect().end.x < button.get_rect().position.x,
			"%s: coin chip stays on the left of the controls" % label)
		_check(chip.get_rect().position.x < hud_root.size.x * 0.5,
			"%s: coin chip sits in the left half" % label)
		_check(button.size.x >= 80.0 and pause.size.x >= 80.0,
			"%s: control buttons are at least 80px" % label)
		_check(pause.get_rect().end.x <= hud_root.size.x + 1.0,
			"%s: pause button stays inside" % label)
		# Fiyat rozeti dugmenin KENARINDAN TASMAMALI: sag kenarda duran bir
		# dugmede tasan rozet guvenli alanin disina cikar ve centikli
		# cihazlarda kirpilir.
		var badge := button.get_node("HintBadge") as Control
		_check(badge.get_rect().end.x <= button.size.x + 0.5,
			"%s: price badge stays inside the hint button" % label)

		root.remove_child(gameplay)
		gameplay.queue_free()
		await process_frame


## DURAKLAT karti: oyunu gercekten durdurmali ve cikis yollarini tasimali.
##
## Asil korunan sozlesme: "tekrar basla" ve "ana menu" ust seritten kaldirilip
## buraya alindi cunku ikisi de geri alinamaz. Kart bunlari kaybederse oyuncu
## bolumden cikamaz hale gelir.
func _test_pause_card() -> void:
	var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	gameplay.set("level_data", load("res://levels/level_60.tres"))
	gameplay.set("wallet", WalletStore.load_from_path(_new_wallet_path("pause")))
	root.add_child(gameplay)
	await process_frame
	await physics_frame

	var root_hud := gameplay.get_node("HUD/SafeArea/Root")
	# Eski tek-dokunusluk tehlikeli butonlar ust seritte KALMAMALI.
	_check(not root_hud.has_node("HomeButton"), "home button left the top bar")
	_check(not root_hud.has_node("RetryButton"), "retry button left the top bar")
	_check(root_hud.has_node("PauseButton"), "pause button replaces them")

	var card := gameplay.get_node("HUD/PauseCard") as Control
	_check(not card.visible, "pause card starts closed")
	_check(not bool(gameplay.call("is_manually_paused")), "game starts unpaused")

	gameplay.call("_on_pause_pressed")
	_check(card.visible, "pause button opens the card")
	_check(bool(gameplay.call("is_manually_paused")), "pause card marks the game paused")
	_check(gameplay.get_tree().paused, "pause card actually pauses the tree")
	# Kart duraklatilmis agacta bile islenebilmeli, yoksa butonlari olu kalir.
	_check(card.process_mode == Node.PROCESS_MODE_ALWAYS,
		"pause card keeps processing while the tree is paused")

	var actions := card.get_node("CardCenter/Card/Margin/Rows/Actions")
	for expected in ["ResumeButton", "RestartButton", "LevelSelectButton", "MenuButton"]:
		_check(actions.has_node(expected), "pause card offers %s" % expected)

	gameplay.call("_on_pause_resume")
	_check(not card.visible, "resume closes the card")
	_check(not gameplay.get_tree().paused, "resume unpauses the tree")
	_check(not bool(gameplay.call("is_manually_paused")), "resume clears the paused flag")

	# TEKRAR BASLA agaci serbest birakmali, yoksa reset_shot donmus agacta
	# calisir ve bolum bir daha baslamaz.
	gameplay.call("_on_pause_pressed")
	gameplay.call("_on_pause_restart")
	_check(not gameplay.get_tree().paused, "restart from pause unpauses the tree")
	_check(not card.visible, "restart from pause closes the card")

	gameplay.get_tree().paused = false
	root.remove_child(gameplay)
	gameplay.queue_free()
	await process_frame


static func _arc_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


func _register_audio_manager() -> void:
	if Engine.has_singleton("AudioManager"):
		return
	var path := String(ProjectSettings.get_setting("autoload/AudioManager", "")).trim_prefix("*")
	var script := load(path) as GDScript
	_check(script != null, "AudioManager autoload script exists")
	if script == null:
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


func _new_wallet_path(label: String) -> String:
	var path := "user://lumabounce_hint_test_%s_%d.cfg" % [label, Time.get_ticks_usec()]
	_paths.append(path)
	return path


func _cleanup_wallet(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	var filename := absolute.get_file()
	if not filename.begins_with("lumabounce_hint_test_") or not filename.ends_with(".cfg"):
		push_error("Refusing to remove unexpected test path: %s" % absolute)
		_failures += 1
		return
	if FileAccess.file_exists(path):
		var error := DirAccess.remove_absolute(absolute)
		_check(error == OK, "temporary wallet removed")


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  OK  %s" % description)
		return
	_failures += 1
	push_error("  X   %s" % description)
