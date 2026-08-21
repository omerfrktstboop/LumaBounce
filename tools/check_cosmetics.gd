extends SceneTree

## GELISTIRME ARACI - oyuna dahil degildir.
##
## Kozmetik magazasinin sozlesmelerini dogrular. En onemlisi sonuncusu:
## KOZMETIK FIZIGE DOKUNMAZ. Bu sozun kod incelemesiyle korunmasi mumkun
## degil - bir gun biri "hizli top derisi" eklemek isteyecek ve tek satirla
## pay-to-win olacak. Burada olculur.
##
## Kullanim:
##   godot --headless --path . --script res://tools/check_cosmetics.gd

const AUDIO_AUTOLOAD := "autoload/AudioManager"
## CosmeticApplier'in ASLA yazmamasi gereken alan adlari.
const PHYSICS_FIELDS := [
	"radius", "gravity", "bounciness", "max_speed", "min_separation_speed",
	"settle_speed", "settle_time", "max_bounces_per_step", "out_of_bounds_margin",
]

var _failures := 0
var _paths: Array[String] = []
var _owned_audio_manager: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_register_audio_manager()
	_test_catalog()
	_test_ownership_and_selection()
	_test_purchase_guards()
	_test_persistence()
	_test_reset_semantics()
	_test_applier_touches_no_physics()
	await _test_gameplay_physics_unchanged()
	await _test_shop_screen()
	for path in _paths:
		_cleanup(path)
	await _unregister_audio_manager()
	# quit() HEMEN DONMEZ - SceneTree'ye istek birakir ve bu fonksiyon
	# calismaya devam eder. return olmadan basarili kosu de FAIL basiyordu.
	if _failures == 0:
		print("PASS cosmetics: catalog, ownership, guards, persistence, physics")
		quit(0)
		return
	push_error("FAIL cosmetics: %d assertion(s)" % _failures)
	quit(1)


func _test_catalog() -> void:
	var items := CosmeticCatalog.all()
	_check(items.size() >= 14, "catalog holds defaults plus purchasable skins")

	var problems: Array[String] = []
	var ids := {}
	for item in items:
		for message in item.validate():
			problems.append(message)
		# Kimlik CAKISMASI kalici sahipligi bozar: iki esya ayni anahtari
		# paylasirsa birini alan digerine de sahip olur.
		if ids.has(item.id):
			problems.append("tekrar eden kimlik: %s" % item.id)
		ids[item.id] = true
	_check(problems.is_empty(), "every cosmetic validates: %s" % str(problems))

	# Her turde TAM BIR varsayilan olmali; yoksa hicbir sey secmemis oyuncu
	# gorunumsuz kalirdi.
	for kind in CosmeticCatalog.KIND_ORDER:
		var defaults := 0
		var purchasable := 0
		for item in CosmeticCatalog.by_kind(kind):
			if item.is_default:
				defaults += 1
			else:
				purchasable += 1
				var band: Vector2i = CosmeticCatalog.PRICE_RANGES[kind]
				_check(item.price >= band.x and item.price <= band.y,
					"%s priced inside its band (%d in %d-%d)" % [
						item.id, item.price, band.x, band.y])
		_check(defaults == 1, "%s has exactly one default" % CosmeticCatalog.kind_label(kind))
		_check(purchasable >= 2, "%s offers at least two skins" % CosmeticCatalog.kind_label(kind))

	# Varsayilan renkleri BUGUNKU gorunumle ayni olmali: magaza acilmasi
	# hicbir sey satin almayan oyuncunun ekranini degistirmemeli.
	var default_ball := CosmeticCatalog.find(CosmeticCatalog.DEFAULT_BALL)
	_check(default_ball.accent.is_equal_approx(Color("34e6d4")),
		"default ball keeps the original accent")


func _test_ownership_and_selection() -> void:
	var wallet := WalletStore.load_from_path(_new_path("own"))
	_check(wallet.owns(CosmeticCatalog.DEFAULT_BALL), "defaults are owned from the start")
	_check(not wallet.owns("ball_violet"), "paid skins start unowned")
	_check(wallet.owned_cosmetic_count() == 0, "defaults are not written to the save")

	# Sahip olunmayan esya SECILEMEZ - aksi halde magazayi atlamanin yolu acilir.
	_check(not wallet.select_cosmetic("ball_violet"), "unowned skin cannot be selected")
	_check(wallet.selected_cosmetic_id(CosmeticData.Kind.BALL) == CosmeticCatalog.DEFAULT_BALL,
		"selection falls back to the default")

	wallet.add(200)
	_check(wallet.purchase_cosmetic("ball_violet"), "affordable skin can be purchased")
	_check(wallet.owns("ball_violet"), "purchase grants ownership")
	_check(wallet.select_cosmetic("ball_violet"), "owned skin can be selected")
	_check(wallet.selected_cosmetic_id(CosmeticData.Kind.BALL) == "ball_violet",
		"selection sticks")
	# Bir turdeki secim DIGER turleri etkilemez.
	_check(wallet.selected_cosmetic_id(CosmeticData.Kind.TRAIL) == CosmeticCatalog.DEFAULT_TRAIL,
		"selecting a ball leaves the trail untouched")


func _test_purchase_guards() -> void:
	var wallet := WalletStore.load_from_path(_new_path("guard"))
	var item := CosmeticCatalog.find("target_singularity")

	# BAKIYE YETERSIZ: hicbir sey degismemeli.
	_check(wallet.balance < item.price, "fixture starts below the price")
	var before := wallet.balance
	_check(not wallet.purchase_cosmetic(item.id), "insufficient balance blocks purchase")
	_check(wallet.balance == before, "failed purchase spends nothing")
	_check(not wallet.owns(item.id), "failed purchase grants nothing")

	# CIFT DOKUNUS: ikinci cagri bakiyeye dokunmamali.
	wallet.add(500)
	var funded := wallet.balance
	_check(wallet.purchase_cosmetic(item.id), "first tap purchases")
	var after_first := wallet.balance
	_check(after_first == funded - item.price, "first tap spends exactly the price")
	_check(not wallet.purchase_cosmetic(item.id), "second tap is rejected")
	_check(wallet.balance == after_first, "double tap never charges twice")

	# Varsayilan esya satin ALINAMAZ (bedava zaten).
	_check(not wallet.purchase_cosmetic(CosmeticCatalog.DEFAULT_BALL),
		"default cosmetics cannot be purchased")
	_check(not wallet.purchase_cosmetic("yok_boyle_bir_sey"),
		"unknown cosmetic id is rejected")


func _test_persistence() -> void:
	var path := _new_path("persist")
	var wallet := WalletStore.load_from_path(path)
	wallet.add(300)
	wallet.purchase_cosmetic("trail_comet")
	wallet.select_cosmetic("trail_comet")
	wallet.purchase_cosmetic("launcher_brass")
	var expected_balance := wallet.balance

	var reloaded := WalletStore.load_from_path(path)
	_check(reloaded.owns("trail_comet"), "ownership survives reload")
	_check(reloaded.owns("launcher_brass"), "second purchase survives reload")
	_check(reloaded.selected_cosmetic_id(CosmeticData.Kind.TRAIL) == "trail_comet",
		"selection survives reload")
	_check(reloaded.balance == expected_balance, "balance survives reload")
	# Satin alinmis ama SECILMEMIS esya varsayilani bozmamali.
	_check(reloaded.selected_cosmetic_id(CosmeticData.Kind.LAUNCHER)
		== CosmeticCatalog.DEFAULT_LAUNCHER,
		"unselected purchase leaves the default active")


## SIFIRLAMA ANLAMI: "ilerlemeyi sifirla" kozmetik sahipligini SILMEZ.
## Kozmetik satin alinmis bir seydir, kazanilmis ilerleme degil.
func _test_reset_semantics() -> void:
	var path := _new_path("reset")
	var wallet := WalletStore.load_from_path(path)
	wallet.add(300)
	wallet.purchase_cosmetic("ball_ember")
	wallet.select_cosmetic("ball_ember")

	var progress := ProgressStore.new()
	progress.highest_unlocked_level = 30
	progress.set_level_stars_if_higher(3, 3)
	progress.reset()

	var reloaded := WalletStore.load_from_path(path)
	_check(reloaded.owns("ball_ember"), "progress reset keeps purchased cosmetics")
	_check(reloaded.selected_cosmetic_id(CosmeticData.Kind.BALL) == "ball_ember",
		"progress reset keeps the selected cosmetic")
	_check(progress.highest_unlocked_level == LevelLibrary.FIRST_LEVEL_ID,
		"progress reset still clears progress")


## CosmeticApplier'in KAYNAK METNI fizik alanlarina yazmamali.
##
## Calisma zamani testi bir derinin bugun fizige dokunmadigini gosterir;
## bu metin testi ise YARIN eklenecek bir derinin dokunamayacagini gosterir,
## cunku uygulama noktasi tektir ve o nokta denetleniyor.
func _test_applier_touches_no_physics() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/cosmetics/cosmetic_applier.gd")
	_check(not source.is_empty(), "applier source is readable")
	var offenders: Array[String] = []
	for field in PHYSICS_FIELDS:
		# Yalnizca ATAMA aranir: yorumda gecmesi serbest, hatta istenir.
		for line in source.split("\n"):
			var text := line.strip_edges()
			if text.begins_with("#") or text.begins_with("##"):
				continue
			if text.contains(".%s =" % field) or text.contains(".%s=" % field):
				offenders.append(field)
				break
	_check(offenders.is_empty(),
		"applier assigns no physics field: %s" % str(offenders))


## FIZIK REGRESYONU: deri secili iken topun fizik alanlari degismemeli.
func _test_gameplay_physics_unchanged() -> void:
	var level := load("res://levels/level_60.tres") as LevelData

	var plain := WalletStore.load_from_path(_new_path("phys_plain"))
	var baseline := await _physics_snapshot(level, plain)

	var skinned := WalletStore.load_from_path(_new_path("phys_skin"))
	skinned.add(1000)
	for id in ["ball_violet", "trail_comet", "launcher_prism", "target_singularity"]:
		skinned.purchase_cosmetic(id)
		skinned.select_cosmetic(id)
	var themed := await _physics_snapshot(level, skinned)

	# applied_accent BILEREK disarida: o, derinin gercekten uygulandigini
	# gosteren kontrol degeridir ve degismek ZORUNDADIR.
	for key in baseline:
		if key == "applied_accent":
			continue
		_check(is_equal_approx(float(baseline[key]), float(themed[key])),
			"skin leaves %s unchanged (%s vs %s)" % [key, baseline[key], themed[key]])
	# Deri GERCEKTEN uygulanmis olmali, yoksa test hicbir sey kanitlamaz.
	_check(themed["applied_accent"] != baseline["applied_accent"],
		"the skin actually changed the ball colour")


func _physics_snapshot(level: LevelData, wallet: WalletStore) -> Dictionary:
	var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	gameplay.set("level_data", level)
	gameplay.set("wallet", wallet)
	root.add_child(gameplay)
	await process_frame
	await physics_frame

	var ball := gameplay.get_node("Ball") as Ball
	var snapshot := {
		"radius": ball.radius,
		"gravity": ball.gravity,
		"bounciness": ball.bounciness,
		"max_speed": ball.max_speed,
		"min_separation_speed": ball.min_separation_speed,
		"settle_speed": ball.settle_speed,
		"settle_time": ball.settle_time,
		"max_bounces_per_step": float(ball.max_bounces_per_step),
		"applied_accent": ball.accent.to_html(false).hash(),
	}
	root.remove_child(gameplay)
	gameplay.queue_free()
	await process_frame
	return snapshot


func _test_shop_screen() -> void:
	var wallet := WalletStore.load_from_path(_new_path("shop"))
	wallet.add(1000)
	var shop := (load("res://scenes/shop_screen.tscn") as PackedScene).instantiate()
	shop.set("wallet", wallet)
	root.add_child(shop)
	await process_frame
	await process_frame

	# Sekme yapisi: varsayilan aktif sekme TOP (KIND_ORDER'in ilki), bu yuzden
	# grid dogrudan ball_* kartlarini gosterir - sekme degistirmeye gerek yok.
	var rows := shop.get_node("SafeArea/Content/Scroll/Rows")
	_check(rows.has_node("CategoryTabs"), "shop shows category tabs")
	var grid := rows.get_node("ProductGrid")
	_check(grid.get_child_count() == CosmeticCatalog.by_kind(CosmeticData.Kind.BALL).size(),
		"shop grid lists exactly the active tab's cosmetics")
	_check(grid.has_node("Card_ball_ember"), "shop shows a purchasable card")

	var card := grid.get_node("Card_ball_ember") as Button
	_check(not card.disabled, "affordable card is pressable")
	var before := wallet.balance
	var price := CosmeticCatalog.find("ball_ember").price
	card.pressed.emit()
	await process_frame
	_check(wallet.balance == before - price, "shop purchase spends exactly the price")
	_check(wallet.owns("ball_ember"), "shop purchase grants ownership")
	_check(wallet.selected_cosmetic_id(CosmeticData.Kind.BALL) == "ball_ember",
		"purchased cosmetic is selected immediately")

	# Satin alinan kart yeniden kuruldu; artik SECILI ve basilamaz olmali.
	var refreshed := rows.get_node("ProductGrid/Card_ball_ember") as Button
	_check(refreshed.disabled, "selected card cannot be pressed again")
	_check(wallet.balance == before - price, "re-render never charges again")

	# Sekme degisimi: baska bir tur secildiginde grid o turun kartlarini
	# gostermeli ve TOP kartlari kaybolmali.
	var tabs := rows.get_node("CategoryTabs")
	tabs.call("_on_option_pressed", 1)
	await process_frame
	var trail_grid := shop.get_node("SafeArea/Content/Scroll/Rows/ProductGrid")
	_check(trail_grid.get_child_count() == CosmeticCatalog.by_kind(CosmeticData.Kind.TRAIL).size(),
		"switching tabs shows the new kind's cosmetics")
	_check(not trail_grid.has_node("Card_ball_ember"),
		"switching tabs hides the previous kind's cards")

	root.remove_child(shop)
	shop.queue_free()
	await process_frame


# --- Yardimcilar --------------------------------------------------------------

func _new_path(tag: String) -> String:
	var path := "user://cosmetic_test_%s.cfg" % tag
	_paths.append(path)
	_cleanup(path)
	return path


func _cleanup(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  OK  %s" % description)
		return
	_failures += 1
	push_error("  X   %s" % description)


func _register_audio_manager() -> void:
	if Engine.has_singleton("AudioManager"):
		return
	var path := String(ProjectSettings.get_setting(AUDIO_AUTOLOAD, "")).trim_prefix("*")
	var script := load(path) as GDScript
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
