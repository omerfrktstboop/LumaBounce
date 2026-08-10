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
	for path in _paths:
		_cleanup_wallet(path)
	await _unregister_audio_manager()
	if _failures == 0:
		print("PASS hint economy: wallet, permanent unlock, modal and block-gated path")
		quit(0)
	else:
		push_error("FAIL hint economy: %d assertion(s)" % _failures)
		quit(1)


func _test_wallet_contract() -> void:
	var path := _new_wallet_path("contract")
	var wallet := WalletStore.load_from_path(path)
	_check(wallet.balance == 3, "new wallet grants one 3-coin trial")
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
	for level_id in range(1, 156):
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

	var initial: Dictionary = gameplay.call("get_debug_snapshot")
	_check(bool(initial["hint_available"]), "gameplay exposes available hint")
	_check(not bool(initial["hint_unlocked"]), "hint starts locked")
	gameplay.call("_on_hint_pressed")
	_check((gameplay.get_node("HUD/HintPurchaseCard") as Control).visible,
		"first tap opens purchase confirmation")
	_check(wallet.balance == 3, "opening confirmation does not spend")

	gameplay.call("_on_hint_purchase_requested")
	var purchased: Dictionary = gameplay.call("get_debug_snapshot")
	_check(wallet.balance == 0, "confirmation spends configured cost")
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
	_check(wallet.balance == 0, "unlocked hint never charges again after restart")
	_check(not (gameplay.get_node("HUD/HintPurchaseCard") as Control).visible,
		"unlocked hint bypasses purchase modal")

	root.remove_child(gameplay)
	gameplay.queue_free()
	await process_frame


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
