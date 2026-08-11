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
	_test_hint_coverage()
	await _test_gameplay_purchase_flow()
	await _test_short_hint()
	await _test_broken_hint_never_charges()
	await _test_hud_fits_tall_aspect()
	await _test_pause_card()
	for path in _paths:
		_cleanup_wallet(path)
	await _unregister_audio_manager()
	if _failures == 0:
		print("PASS hint economy: wallet, unlock, two-option card, short hint, HUD, pause")
		quit(0)
	else:
		push_error("FAIL hint economy: %d assertion(s)" % _failures)
		quit(1)


func _test_wallet_contract() -> void:
	var path := _new_wallet_path("contract")
	var wallet := WalletStore.load_from_path(path)
	_check(wallet.balance == CoinEconomy.STARTING_COINS,
		"new wallet grants the configured starting balance")
	_check(not wallet.unlock_hint("", 3), "empty level uid is rejected")
	_check(wallet.unlock_hint("level_041", 3), "affordable hint unlock succeeds")
	_check(wallet.balance == 0 and wallet.spent_total == 3, "unlock spends exactly once")
	_check(wallet.unlock_hint("level_041", 3), "repeated unlock is idempotent")
	_check(wallet.balance == 0 and wallet.spent_total == 3, "repeated unlock costs nothing")
	_check(not wallet.unlock_hint("level_042", 3), "insufficient balance cannot unlock")

	var reloaded := WalletStore.load_from_path(path)
	_check(reloaded.is_hint_unlocked("level_041"), "hint unlock survives reload")
	_check(reloaded.balance == 0, "spent balance survives reload")
	reloaded.add(1)
	_check(reloaded.balance == 1 and reloaded.earned_total == 1, "coin rewards are recorded")


func _test_hint_coverage() -> void:
	var missing: Array[int] = []
	# 1-150 ana kampanya, 151-155 bonus bolumlerdir.
	for level_id in range(LevelLibrary.FIRST_LEVEL_ID, LevelLibrary.last_level_id() + 1):
		var level := load(LevelLibrary.level_path(level_id)) as LevelData
		if level == null or not level.has_hint():
			missing.append(level_id)
	_check(missing.is_empty(), "all 150 campaign and 5 bonus levels have hint shots")
	if not missing.is_empty():
		push_error("Missing hint levels: %s" % str(missing))


func _test_gameplay_purchase_flow() -> void:
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

	# Tam ipucu baslangic bakiyesinden PAHALI (bilerek: yeni oyuncu once
	# kazanmali). Test fiyati oyundan okur ve cuzdani ona gore fonlar.
	var cost := int(gameplay.get("hint_cost"))
	wallet.add(cost)
	var funded := wallet.balance
	_check(funded >= cost, "wallet funded for one full-route unlock")

	var initial: Dictionary = gameplay.call("get_debug_snapshot")
	_check(bool(initial["hint_available"]), "gameplay exposes available hint")
	_check(not bool(initial["hint_unlocked"]), "hint starts locked")
	gameplay.call("_on_hint_pressed")
	_check((gameplay.get_node("HUD/HintPurchaseCard") as Control).visible,
		"first tap opens purchase confirmation")
	_check(wallet.balance == funded, "opening confirmation does not spend")

	gameplay.call("_on_hint_purchase_requested")
	var purchased: Dictionary = gameplay.call("get_debug_snapshot")
	_check(wallet.balance == funded - cost, "confirmation spends exactly the cost")
	_check(bool(purchased["hint_unlocked"]), "purchase permanently unlocks level hint")
	_check(not bool(purchased["hint_visible"]), "block level waits before drawing final route")

	var blocks := gameplay.get_node("Blocks") as BreakableField
	blocks.shatter_in_radius(Vector2(360.0, 640.0), 2000.0)
	await process_frame
	await physics_frame
	await process_frame
	var revealed: Dictionary = gameplay.call("get_debug_snapshot")
	_check(bool(revealed["hint_visible"]),
		"route appears after all blocks are broken")

	gameplay.call("reset_shot")
	gameplay.call("_on_hint_pressed")
	_check(wallet.balance == funded - cost,
		"unlocked hint never charges again after restart")
	_check(not (gameplay.get_node("HUD/HintPurchaseCard") as Control).visible,
		"unlocked hint bypasses purchase modal")

	root.remove_child(gameplay)
	gameplay.queue_free()
	await process_frame


## KISA IPUCU: bedava, kalici DEGIL, rotanin yalnizca bir parcasi.
##
## Bu testin asil isi iki sozlesmeyi korumak: kisa ipucu Coin harcamamali ve
## tam rotanin yerine gecmemeli. Ikisi de urun kararidir; kod onlari sessizce
## kaybederse kimse fark etmez.
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

	# Tam rota baslangic bakiyesinden pahali; "yeterli bakiye varken" iddiasi
	# anlamli olsun diye cuzdan once fonlanir.
	wallet.add(int(gameplay.get("hint_cost")))

	# Ozellik bayragi KAPALI: secenek gorunur ama pasif olmali.
	gameplay.set("short_hint_enabled", false)
	gameplay.call("_on_hint_pressed")
	_check(card.visible, "hint tap opens the single two-option card")
	var options := card.get_node("CardCenter/Card/Margin/Rows/Options")
	_check(options.get_child_count() == 2, "card offers exactly two options")
	_check(options.has_node("ShortOption"), "short option row exists")
	_check(options.has_node("FullOption"), "full route row exists")
	_check((options.get_node("ShortOption") as Button).disabled,
		"short hint is disabled while the rewarded flag is off")
	_check(not (options.get_node("FullOption") as Button).disabled,
		"full route stays purchasable with enough balance")
	gameplay.call("_on_short_hint_requested")
	var short_before := wallet.balance
	_check(wallet.balance == short_before, "disabled short hint spends nothing")
	_check(not bool(gameplay.call("get_debug_snapshot")["hint_visible"]),
		"disabled short hint draws no route")
	card.call("close")

	# Bayrak ACIK: secenek etkinlesir ve odul verilince kisa rota cizilir.
	gameplay.set("short_hint_enabled", true)
	gameplay.call("_on_hint_pressed")
	_check(not (options.get_node("ShortOption") as Button).disabled,
		"short hint enables when the rewarded flag is on")
	gameplay.call("grant_short_hint")
	var granted: Dictionary = gameplay.call("get_debug_snapshot")
	_check(bool(granted["hint_visible"]), "granted short hint draws a route")
	_check(wallet.balance == short_before,
		"rewarded short hint never spends Luma Coin")
	_check(not bool(granted["hint_unlocked"]),
		"short hint is not a permanent unlock")

	# Kisa rota TAM rotadan gercekten kisa olmali - yoksa tam rotayi satin
	# almanin bir anlami kalmaz.
	var full: PackedVector2Array = gameplay.call("_build_hint_trace")
	var short_trace: PackedVector2Array = gameplay.call("_build_short_hint_trace")
	_check(short_trace.size() >= 2, "short trace has drawable geometry")
	_check(_arc_length(short_trace) < _arc_length(full) * 0.65,
		"short trace stays well below the full route length")
	_check(short_trace[0].is_equal_approx(full[0]),
		"short trace starts at the same launch point")

	# Ayni denemede ikinci kez verilmez.
	gameplay.call("_on_hint_pressed")
	_check((options.get_node("ShortOption") as Button).disabled,
		"short hint cannot be claimed twice in one attempt")
	card.call("close")

	root.remove_child(gameplay)
	gameplay.queue_free()
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
