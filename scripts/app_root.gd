class_name AppRoot
extends Node

const DEBUG_PANEL_SCENE_PATH := "res://scenes/debug_panel.tscn"
const LEVEL_EDITOR_SCENE_PATH := "res://scenes/level_editor.tscn"

## Uygulamanin giris noktasi: splash -> ana menu -> bolum secimi -> oynanis.
##
## MIMARI KURAL: ekranlar birbirini asla instantiate etmez. Her ekran yalnizca
## sinyal yayar, tum gecis ve ilerleme kararlari burada verilir. Ekranlara
## ihtiyac duyduklari veri (bolum, ilerleme, playtest istatistikleri) add_child'dan
## ONCE enjekte edilir, boylece _ready icinde hazir olur.
##
## Ekranlar ScreenHost altina tek tek yuklenir; her gecis kisa bir fade ile
## ortulur. Fade rengi saf siyah degil, paletin en koyu murekkep tonudur.
##
## Uygulama arka plana gecince (odak kaybi / OS duraklatmasi) tum sahne
## agacini duraklatir: bu hem "guvenli duraklama" hem de "topun ani fizik
## sicramasi" sorununu tek mekanizmayla cozer - fizik/animasyon islenmedigi
## icin geri donuste birikmis bir "yakalama" adimi olmaz, kaldigi yerden
## normal bir fizik adimiyla devam eder.

@export var splash_scene: PackedScene
@export var main_menu_scene: PackedScene
@export var level_select_scene: PackedScene
@export var settings_scene: PackedScene
@export var shop_scene: PackedScene
@export var retention_scene: PackedScene
@export var gameplay_scene: PackedScene
@export var fade_time := 0.28
@export var fade_color := Palette.INK_TOP
## Arka katman, arenanin murekkep tonundan bu kadar koyu olur (bkz.
## _apply_background_theme). Ayni tonda olsa derinlik hissi kaybolurdu.
@export_range(0.0, 1.0, 0.01) var background_darken := 0.35

@onready var _host: Node = $ScreenHost
@onready var _fade: ColorRect = $FadeLayer/Fade

var _progress: ProgressStore
var _playtest_stats: PlaytestStats
var _wallet: WalletStore
var _entitlements: EntitlementStore
var _analytics: AnalyticsService
var _ad_policy: AdPolicy
var _ad_service: AdService
var _purchase_service: PurchaseService
var _daily_store: DailyStore
var _achievement_store: AchievementStore
## Bu iki kaynak ana sahnenin bagimliligi degildir. Yalnizca debug template
## calisirken yuklenir; Android Release filtresi dosyalari pakete dahil etmez.
var _debug_panel = null
var _level_editor_scene: PackedScene
## Debug paneli disinda hicbir yerde okunmaz; gercek save'e asla yazilmaz.
var _debug_unlock_all := false
var _current: Node
## Son go_to_level cagrisinda istenen bolum. Debug onceki/sonraki/tekrar
## butonlari icin tutulur.
var _current_level_id := LevelLibrary.FIRST_LEVEL_ID
## Editorden test edilen bolum. Oynanistan cikildiginda editore ayni veriyle
## donebilmek icin tutulur; kaydedilmemis duzenleme kaybolmaz.
var _editor_level: LevelData
## Uretilen veya kaydedilen parti, acik indeks ve metadata. Test sahnesi
## LevelEditor'u yok ettigi icin bu baglam AppRoot'ta yasatilir.
var _editor_batch_context := {}
## Editorde duzenlenen sey bir resmi bolumden geldiyse onun numarasi, yoksa 0.
var _editor_source_level_id := 0
var _busy := false
var _completion_ad_in_progress := false
var _active_daily_challenge := false
var _analytics_session_active := false
var _analytics_session_started_msec := 0


func _ready() -> void:
	# process_mode = ALWAYS (sahnede ayarli): uygulama arka plana alinsa/odagi
	# kaybetse bile bu dugum calismaya devam etmeli ki duraklatma/devam
	# bildirimlerini kacirmasin.
	_progress = ProgressStore.load_from_disk()
	_wallet = WalletStore.load_from_disk()
	_daily_store = DailyStore.load_from_disk()
	_achievement_store = AchievementStore.load_from_disk()
	_setup_monetization()
	_apply_achievement_unlocks(_achievement_store.sync_campaign(_progress), null)
	# Titresim tercihi tek okuma noktasina (Haptics) aktarilir; boylece
	# cagiranlarin ProgressStore'a erisimi olmasi gerekmez (bkz. haptics.gd).
	Haptics.enabled = _progress.haptics_enabled
	# Dil ILK ekrandan once uygulanmali: bir Control'un metni cevrilirken
	# o anki locale okunur, sonradan degistirmek zaten kurulmus etiketleri
	# guncellemez. Kayitli tercih bos ise (oyuncu henuz secmedi) cihaz dili
	# kullanilir ve HICBIR SEY kaydedilmez - bkz. Locale.apply_saved.
	Locale.apply_saved(_progress.language)
	# Sarsinti tercihi de tek kisma noktasina aktarilir (bkz. screen_shake.gd);
	# Haptics ile ayni desen.
	ScreenShake.trauma_scale = _progress.shake_scale
	_playtest_stats = PlaytestStats.load_from_disk()
	_start_analytics_session(&"launch")
	_setup_debug_tools()
	_connect_debug_panel()

	# Ilk ekran bilerek fade'siz acilir: splash'in kendi top-dususu zaten
	# acilis animasyonudur, onune bir fade koymak sekme anini gizlerdi.
	# Fade yalnizca ekranlar ARASI gecislerde kullanilir.
	_fade.color = Color(fade_color, 0.0)
	_fade.visible = false
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_swap_to(splash_scene)


## Gecis sirasinda hicbir girdi alttaki ekrana ulasmasin.
## (Control'lar dokunma olaylarini yutmadigi icin sadece fade'in
## mouse_filter'ina guvenmek yeterli olmaz.)
func _input(_event: InputEvent) -> void:
	if _busy:
		get_viewport().set_input_as_handled()


## Telefonun geri tusu VE uygulama odak/arka plan bildirimleri.
## quit_on_go_back kapali oldugu icin geri tusunda uygulama kendiliginden
## kapanmaz; hiyerarside bir adim geri gideriz.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_handle_go_back()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			_end_analytics_session(&"background")
			_set_application_paused(true)
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			_set_application_paused(false)
			_start_analytics_session(&"foreground")
			if _purchase_service != null:
				_purchase_service.restore_purchases.call_deferred()


func _exit_tree() -> void:
	if _daily_store != null:
		_daily_store.save()
	if _achievement_store != null:
		_achievement_store.save()
	_end_analytics_session(&"exit")
	if _analytics != null:
		_analytics.shutdown()


func _set_application_paused(paused: bool) -> void:
	if get_tree().paused == paused:
		return
	var gameplay := _current as Gameplay
	if gameplay != null:
		gameplay.set_app_paused(paused)
	# ELLE duraklatilmis bir oyun, uygulama on plana dondugunde kendiliginden
	# devam ETMEMELI: oyuncu duraklat kartini hala aciktir ve arkasinda top
	# ucmaya baslardi. Agaci serbest birakma karari yine burada, ama gameplay'in
	# durumuna saygi duyarak.
	get_tree().paused = paused or (gameplay != null and gameplay.is_manually_paused())


# --- Ekran gecisleri ---------------------------------------------------------

func go_to_main_menu() -> void:
	_active_daily_challenge = false
	await _transition(main_menu_scene, _configure_main_menu)


func go_to_level_select() -> void:
	_active_daily_challenge = false
	await _transition(level_select_scene, _configure_level_select)


func go_to_shop() -> void:
	_active_daily_challenge = false
	await _transition(shop_scene, _configure_shop)


func go_to_settings() -> void:
	_active_daily_challenge = false
	await _transition(settings_scene, _configure_settings)


func go_to_retention() -> void:
	_active_daily_challenge = false
	await _transition(retention_scene, _configure_retention)


func go_to_daily_challenge() -> void:
	if not _progress.is_completed(DailyStore.CHALLENGE_UNLOCK_LEVEL):
		return
	_daily_store.refresh_for_date()
	_active_daily_challenge = true
	_current_level_id = _daily_store.challenge_level_id
	await _transition(gameplay_scene, _configure_daily_gameplay,
		_daily_store.challenge_level_id)


func go_to_level(level_id: int) -> void:
	_active_daily_challenge = false
	_current_level_id = LevelLibrary.clamp_id(level_id)
	await _transition(gameplay_scene, _configure_gameplay.bind(_current_level_id),
		_current_level_id)


## [param theme_level] hangi bolumun temasi uygulanacak. 0 = notr taban tema
## (menu, ayarlar, bolum secimi): oyuncu 3. dunyadan menuye dondugunde menu
## mor kalmamali; bolum secim ekrani zaten dunya renklerini VERI olarak tasir.
##
## TEMA NEDEN BURADA UYGULANIYOR: bircok dugum rengini `@export var x :=
## Palette.Y` seklinde alir ve bu baslangic degeri sahne OLUSTURULURKEN
## okunur. Tema instantiate'ten sonra uygulanirsa o dugumler bir onceki
## dunyanin rengiyle kalir - arena duvarlarinin 70. bolumde hala 1. dunyanin
## yuzeyini gostermesinin sebebi buydu. Fade tam kapandiktan SONRA, sahne
## kurulmadan ONCE uygulamak 17 ayri script'i yamamadan hepsini duzeltir;
## ustelik degisim ekran tamamen ortuluyken olur, yani goze carpmaz.
func _transition(scene: PackedScene, configure: Callable, theme_level := 0) -> void:
	if _busy or scene == null:
		return
	_busy = true
	await _fade_to(1.0)
	Palette.apply_theme(PaletteThemes.for_level(theme_level))
	_apply_background_theme()
	_swap_to(scene, configure)
	await _fade_to(0.0)
	_busy = false


func _fade_to(alpha: float) -> void:
	_fade.visible = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, fade_time)
	await tween.finished
	if is_zero_approx(alpha):
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.visible = false


func _swap_to(scene: PackedScene, configure := Callable()) -> void:
	if scene == null:
		push_warning("AppRoot: yuklenecek sahne atanmamis.")
		return

	if _current != null:
		# queue_free tek basina yetmez: dugum kare sonuna kadar agacta kalir
		# ve yeni ekranla birlikte cizilip islenirdi.
		_host.remove_child(_current)
		_current.queue_free()
		_current = null

	var instance := scene.instantiate()
	# Sinyaller ve veri _ready'den once hazir olsun.
	_connect_screen(instance)
	if configure.is_valid():
		configure.call(instance)
	_host.add_child(instance)
	_current = instance

	if _debug_panel != null and is_instance_valid(_debug_panel) and not _debug_panel.is_queued_for_deletion():
		_debug_panel.call("set_active_gameplay", instance as Gameplay)
		# Editorun kendi GERI dugmesi ayni koseyi kullaniyor; orada kose
		# dugmesi gizlenir (uc parmak jesti calismaya devam eder).
		_debug_panel.call("set_toggle_visible", not _is_level_editor(instance))


# --- Ekran kurulumu ----------------------------------------------------------

func _connect_screen(screen: Node) -> void:
	var splash := screen as SplashScreen
	if splash != null:
		splash.finished.connect(go_to_main_menu)
		return

	var menu := screen as MainMenu
	if menu != null:
		menu.play_pressed.connect(go_to_level)
		menu.levels_requested.connect(go_to_level_select)
		menu.settings_requested.connect(go_to_settings)
		menu.shop_requested.connect(go_to_shop)
		return

	var shop := screen as ShopScreen
	if shop != null:
		shop.menu_requested.connect(go_to_main_menu)
		return

	var settings := screen as SettingsScreen
	if settings != null:
		settings.menu_requested.connect(go_to_main_menu)
		return

	var retention := screen as RetentionScreen
	if retention != null:
		retention.menu_requested.connect(go_to_main_menu)
		retention.challenge_requested.connect(go_to_daily_challenge)
		return

	var select := screen as LevelSelect
	if select != null:
		select.level_selected.connect(go_to_level)
		select.menu_requested.connect(go_to_main_menu)
		return

	var gameplay := screen as Gameplay
	if gameplay != null:
		gameplay.level_completed.connect(_on_level_completed)
		gameplay.next_level_requested.connect(_on_next_level_requested)
		gameplay.level_select_requested.connect(_on_gameplay_level_select_requested)
		# Editorden test edildiyse "menu" tusu editore geri doner; yoksa
		# tasarladigin bolumu terk etmek icin tek yol kaydetmek olurdu.
		gameplay.menu_requested.connect(_on_gameplay_menu_requested)
		gameplay.obstacle_kind_seen.connect(_on_obstacle_kind_seen)
		gameplay.block_mechanic_seen.connect(_on_block_mechanic_seen)
		gameplay.short_hint_requested.connect(_on_short_hint_requested.bind(gameplay))
		gameplay.level_failed.connect(_on_level_failed)
		gameplay.bounce_recorded.connect(_on_bounce_recorded.bind(gameplay))
		return

	if _is_level_editor(screen):
		screen.connect("test_requested", _on_editor_test_requested)
		screen.connect("menu_requested", _on_editor_closed)


func _configure_main_menu(screen: Node) -> void:
	var menu := screen as MainMenu
	if menu != null:
		menu.resume_level_id = _progress.get_resume_level_id()
		# Ayni WalletStore/ProgressStore ORNEKLERI: Coin rozeti ve ilerleme
		# ozeti Magaza/Ayarlar'in zaten yaptigi gibi dogrudan okur.
		menu.wallet = _wallet
		menu.progress = _progress


func _configure_level_select(screen: Node) -> void:
	var select := screen as LevelSelect
	if select != null:
		select.progress = _progress
		select.debug_force_unlock = _debug_unlock_all


func _configure_shop(screen: Node) -> void:
	var shop := screen as ShopScreen
	if shop != null:
		# Ayni WalletStore ORNEGI: magazada yapilan satin alma AppRoot'un
		# elindeki cuzdanda da gorunmeli, yoksa sonraki bir save eski
		# bakiyeyi geri yazardi.
		shop.wallet = _wallet
		shop.purchase_service = _purchase_service
		shop.analytics = _analytics
		_analytics.track_event(AnalyticsService.SHOP_OPEN, {
			"balance": _wallet.balance,
		})


func _configure_settings(screen: Node) -> void:
	var shop := screen as ShopScreen
	if shop != null:
		shop.menu_requested.connect(go_to_main_menu)
		return

	var settings := screen as SettingsScreen
	if settings != null:
		# Ayni ProgressStore ORNEGI verilir, kopyasi degil: ekran bir ayari
		# yazdiginda AppRoot'un elindeki nesne de guncel olmali, yoksa bir
		# sonraki save() eski degeri geri yazardi.
		settings.progress = _progress
		settings.ad_service = _ad_service


func _configure_retention(screen: Node) -> void:
	var retention := screen as RetentionScreen
	if retention == null:
		return
	retention.daily_store = _daily_store
	retention.achievement_store = _achievement_store
	retention.wallet = _wallet
	retention.progress = _progress
	retention.analytics = _analytics


func _configure_gameplay(screen: Node, level_id: int) -> void:
	var gameplay := screen as Gameplay
	if gameplay != null:
		# Tema burada DEGIL, _transition icinde uygulanir (sahne kurulmadan
		# once); bkz. oradaki not.
		gameplay.level_data = LevelLibrary.load_level(level_id)
		gameplay.playtest_stats = _playtest_stats
		gameplay.progress = _progress
		gameplay.wallet = _wallet
		gameplay.aim_assist = _progress.aim_assist
		gameplay.ad_service = _ad_service
		gameplay.analytics = _analytics
		gameplay.short_hint_enabled = _ad_service.is_rewarded_ready(
			MonetizationConfig.PLACEMENT_SHORT_HINT)
		_ad_policy.begin_level(LevelData.uid_for(level_id))
		_analytics.track_event(AnalyticsService.LEVEL_START, {
			"level_id": level_id,
			"world": _world_key(level_id),
			"is_bonus": LevelWorlds.is_bonus_id(level_id),
		})
		if _progress.is_completed(DailyStore.QUESTS_UNLOCK_LEVEL) \
			and LevelWorlds.is_bonus_id(level_id):
			_record_completed_quests(_daily_store.record_bonus_attempt())
			_claim_quest_reward(gameplay)


func _configure_daily_gameplay(screen: Node) -> void:
	var gameplay := screen as Gameplay
	if gameplay == null:
		return
	var level_id := _daily_store.challenge_level_id
	gameplay.level_data = LevelLibrary.load_level(level_id)
	gameplay.playtest_stats = _playtest_stats
	gameplay.progress = _progress
	gameplay.wallet = _wallet
	gameplay.aim_assist = _progress.aim_assist
	gameplay.ad_service = _ad_service
	gameplay.analytics = _analytics
	gameplay.daily_mode = true
	gameplay.short_hint_enabled = _ad_service.is_rewarded_ready(
		MonetizationConfig.PLACEMENT_SHORT_HINT)
	_ad_policy.begin_level("daily:%s" % _daily_store.active_date)
	_analytics.track_event(AnalyticsService.LEVEL_START, {
		"level_id": level_id,
		"world": _world_key(level_id),
		"is_bonus": false,
	})


## Servisler AppRoot'a aittir: ekran omru degistiginde provider/policy durumu
## kaybolmaz. Autoload kullanmamak testlerde NoOp yerine Mock enjekte etmeyi ve
## sonraki fazda yalnizca bu composition root'u degistirmeyi kolaylastirir.
func _setup_monetization() -> void:
	_entitlements = EntitlementStore.load_from_disk()
	_analytics = AnalyticsService.new(OS.is_debug_build() and not OS.has_feature("production"))
	var analytics_config := GameAnalyticsConfig.load_from_path()
	var analytics_provider: AnalyticsProvider = NoOpAnalyticsProvider.new()
	if analytics_config.is_ready():
		analytics_provider = GameAnalyticsProvider.new()
	_analytics.configure(analytics_provider, analytics_config)
	_analytics.initialize()
	_ad_policy = AdPolicy.new(
		_entitlements, MonetizationConfig.AD_POLICY_STATE_PATH)
	_ad_service = AdService.new()
	_ad_service.name = "AdService"
	var provider: AdProvider = NoOpAdProvider.new()
	if OS.get_name() == "Android" and Engine.has_singleton(Admob.PLUGIN_SINGLETON_NAME):
		provider = AdmobAdProvider.new()
	_ad_service.configure(provider, _ad_policy, _analytics)
	add_child(_ad_service)
	_ad_service.initialize()

	_purchase_service = PurchaseService.new()
	_purchase_service.name = "PurchaseService"
	var purchase_provider: PurchaseProvider = NoOpPurchaseProvider.new()
	if OS.get_name() == "Android" and Engine.has_singleton(
			GooglePlayBillingProvider.PLUGIN_SINGLETON_NAME):
		purchase_provider = GooglePlayBillingProvider.new()
	_purchase_service.configure(purchase_provider, _entitlements, _analytics)
	add_child(_purchase_service)
	_purchase_service.initialize()


## Oynanisin arkasindaki "derin uzay" katmani temanin murekkep rengini takip
## eder, boylece bant degisimi yalnizca vurgu renginde degil ZEMINDE de
## gorunur - tema degisiminin fark edilmesini saglayan asil sey budur.
##
## Sahnedeki sabit renk yerine Palette'ten okunur ve biraz koyultulur: bu
## katman arenanin ARKASINDA durur, ayni tonda olursa derinlik kaybolur.
func _apply_background_theme() -> void:
	var deep_space := get_node_or_null("BackgroundLayer/DeepSpace") as ColorRect
	if deep_space == null:
		return
	deep_space.color = Palette.INK_TOP.darkened(background_darken)
	var layer := get_node_or_null("BackgroundLayer") as CanvasLayer
	if layer != null:
		layer.visible = true


## Kazanilan yildiz yalnizca oncekinden IYIYSE kaydedilir; eski 3, yeni 1
## ise kayit 3 kalir (bkz. ProgressStore.set_level_stars_if_higher).
## Gameplay yalnizca "kisa ipucu istiyorum" der. Provider sonucu EARNED
## degilse Coin/rota verilmez; unavailable durumda bir frame sonra normal oyun
## devam eder. Gercek SDK adapteri bu fonksiyonun disina sizmaz.
func _on_short_hint_requested(gameplay: Gameplay) -> void:
	if gameplay == null or not is_instance_valid(gameplay):
		return
	if _ad_service == null:
		return
	gameplay.set_fullscreen_ad_active(true)
	var result := int(await _ad_service.show_rewarded(
		MonetizationConfig.PLACEMENT_SHORT_HINT))
	if gameplay == null or not is_instance_valid(gameplay):
		return
	gameplay.set_fullscreen_ad_active(false)
	if result == AdResult.Code.EARNED and gameplay.is_inside_tree():
		gameplay.grant_short_hint()


func _on_level_completed(level_id: int, stars: int, seconds: float,
		shots: int) -> void:
	# Editorden test edilen bolum gercek ilerlemeye YAZILMAZ; henuz oyunun
	# bir parcasi degil ve kaydi kirletmesi anlamsiz olurdu.
	if _editor_level != null:
		return
	var gameplay := _current as Gameplay
	var retention_snapshot := gameplay.get_retention_snapshot() if gameplay != null else {}
	var full_hint_used := bool(retention_snapshot.get("full_hint_used", false))
	if _active_daily_challenge:
		_on_daily_completed(level_id, stars, seconds, shots, full_hint_used,
			gameplay)
		return
	var first_clear := not _progress.is_completed(level_id)
	_analytics.track_event(AnalyticsService.LEVEL_COMPLETE, {
		"level_id": level_id,
		"world": _world_key(level_id),
		"stars": stars,
		"seconds_bucket": AnalyticsService.seconds_bucket(seconds),
		"shots": shots,
		"first_clear": first_clear,
		"is_bonus": LevelWorlds.is_bonus_id(level_id),
	})
	# "Ilk kez 3 yildiz" kaydetmeden ONCE olculmeli; set_level_stars_if_higher
	# calistiktan sonra eski deger kaybolur.
	var first_three_star := stars >= LevelData.NORMAL_MAX_STARS 		and _progress.get_level_stars(level_id) < LevelData.NORMAL_MAX_STARS
	_progress.mark_completed(level_id)
	_progress.set_level_stars_if_higher(level_id, stars)
	if _wallet != null:
		# Kurallar CoinEconomy'de; burasi yalnizca sonucu yazar ve gosterir.
		var reward := CoinEconomy.level_complete_reward(
			level_id, _completed_normal_level_count(), first_clear, first_three_star)
		if reward > 0:
			_wallet.add(reward)
			var rewarded_screen := _current as Gameplay
			if rewarded_screen != null:
				rewarded_screen.notify_luma_coin_reward(reward)

	_ad_policy.register_successful_completion(
		LevelData.uid_for(level_id), not LevelWorlds.is_bonus_id(level_id))
	_record_meta_completion(
		LevelData.uid_for(level_id), stars, shots, full_hint_used, gameplay)


func _on_next_level_requested(level_id: int) -> void:
	if _active_daily_challenge:
		go_to_retention()
		return
	if _completion_ad_in_progress:
		return
	_completion_ad_in_progress = true
	if _ad_service != null:
		await _ad_service.request_interstitial(
			MonetizationConfig.CONTEXT_LEVEL_COMPLETE)
	_completion_ad_in_progress = false
	go_to_level(level_id)


func _completed_normal_level_count() -> int:
	var count := 0
	for level_id in _progress.completed_levels:
		if LevelLibrary.is_valid_id(level_id) and not LevelWorlds.is_bonus_id(level_id):
			count += 1
	return count


## Failure suresi yalnizca Gameplay'in pause/background hariç tuttugu aktif
## deneme suresinden gelir. Reklam sonuc karti acildiktan sonraki dogal
## geciste denenir; provider hazir degilse oyun akisi bekletilmez.
func _on_level_failed(level_id: int, reason: String, shots: int,
		active_seconds: float) -> void:
	if _editor_level != null:
		return
	_analytics.track_event(AnalyticsService.LEVEL_FAIL, {
		"level_id": level_id,
		"world": _world_key(level_id),
		"reason": AnalyticsService.failure_reason(reason),
		"shots_bucket": AnalyticsService.shots_bucket(shots),
		"is_bonus": LevelWorlds.is_bonus_id(level_id),
	})
	var candidate := _ad_policy.register_failed_attempt(
		LevelData.uid_for(level_id), active_seconds,
		not _active_daily_challenge and not LevelWorlds.is_bonus_id(level_id))
	if candidate and _ad_service != null:
		await _ad_service.request_interstitial(MonetizationConfig.CONTEXT_LEVEL_FAIL)


func _on_daily_completed(level_id: int, stars: int, seconds: float, shots: int,
		full_hint_used: bool, gameplay: Gameplay) -> void:
	_analytics.track_event(AnalyticsService.LEVEL_COMPLETE, {
		"level_id": level_id,
		"world": _world_key(level_id),
		"stars": stars,
		"seconds_bucket": AnalyticsService.seconds_bucket(seconds),
		"shots": shots,
		"first_clear": not _daily_store.is_daily_claimed(),
		"is_bonus": false,
	})
	var completion := _daily_store.complete_daily()
	var reward := int(completion.get("reward", 0))
	if reward > 0:
		_wallet.add(reward)
		if gameplay != null:
			gameplay.notify_luma_coin_reward(reward)
		_analytics.track_event(AnalyticsService.DAILY_COMPLETE, {
			"day_index": DailyStore.day_index(_daily_store.active_date),
			"reward": reward,
		})
	if stars >= LevelData.NORMAL_MAX_STARS:
		_analytics.track_event(AnalyticsService.DAILY_THREE_STAR, {
			"day_index": DailyStore.day_index(_daily_store.active_date),
		})
	var milestone := int(completion.get("milestone", 0))
	if milestone > 0:
		_analytics.track_event(AnalyticsService.STREAK_MILESTONE, {
			"streak_bucket": StringName(str(milestone)),
		})
	_record_meta_completion(
		"daily:%s" % _daily_store.active_date, stars, shots, full_hint_used, gameplay)


func _record_meta_completion(completion_key: String, stars: int, shots: int,
		full_hint_used: bool, gameplay: Gameplay) -> void:
	if _progress.is_completed(DailyStore.QUESTS_UNLOCK_LEVEL):
		_record_completed_quests(_daily_store.record_level_completion(
			stars, shots, full_hint_used))
		_claim_quest_reward(gameplay)
	var final_world_start := LevelWorlds.first_level(LevelWorlds.count() - 1)
	var unlocks := _achievement_store.record_completion(
		completion_key, _progress.completed_levels.size(), shots, stars,
		_progress.is_unlocked(final_world_start))
	_apply_achievement_unlocks(unlocks, gameplay)


func _record_completed_quests(quest_ids: PackedStringArray) -> void:
	for quest_id in quest_ids:
		var quest := DailyQuestCatalog.find(quest_id)
		if quest == null:
			continue
		_analytics.track_event(AnalyticsService.QUEST_COMPLETE, {
			"quest_id": quest.id,
			"quest_type": quest.analytics_type,
		})


func _claim_quest_reward(gameplay: Gameplay) -> void:
	var reward := _daily_store.claim_all_quests_reward()
	if reward <= 0:
		return
	_wallet.add(reward)
	if gameplay != null:
		gameplay.notify_luma_coin_reward(reward)
	_analytics.track_event(AnalyticsService.ALL_DAILY_QUESTS_COMPLETE, {
		"day_index": DailyStore.day_index(_daily_store.active_date),
		"reward": reward,
	})


func _on_bounce_recorded(gameplay: Gameplay) -> void:
	if _editor_level != null:
		return
	if _progress.is_completed(DailyStore.QUESTS_UNLOCK_LEVEL):
		_record_completed_quests(_daily_store.record_bounce())
		_claim_quest_reward(gameplay)
	_apply_achievement_unlocks(_achievement_store.record_bounce(), gameplay)


func _apply_achievement_unlocks(unlocks: Array[Dictionary], gameplay: Gameplay) -> void:
	for unlock in unlocks:
		var reward := int(unlock.get("coin_reward", 0))
		if reward > 0 and _wallet != null:
			_wallet.add(reward)
		if gameplay != null and is_instance_valid(gameplay):
			gameplay.notify_achievement_unlocked(
				String(unlock.get("title_key", "")), reward)
		if _analytics != null:
			_analytics.track_event(AnalyticsService.ACHIEVEMENT_UNLOCK, {
				"achievement_id": String(unlock.get("id", "")),
				"reward": reward,
			})


func _world_key(level_id: int) -> StringName:
	return StringName("world_%02d" % (LevelWorlds.index_for_level(level_id) + 1))


func _start_analytics_session(reason: StringName) -> void:
	if _analytics == null or _analytics_session_active:
		return
	_analytics_session_active = true
	_analytics_session_started_msec = Time.get_ticks_msec()
	_analytics.track_event(AnalyticsService.SESSION_START, {
		"game_version": GameVersion.GAME,
		"environment": _analytics.environment(),
		"analytics_provider": _analytics.provider_name(),
		"ad_provider": _ad_service.provider_name() if _ad_service != null else &"none",
		"reason": reason,
	})


func _end_analytics_session(reason: StringName) -> void:
	if _analytics == null or not _analytics_session_active:
		return
	var elapsed := float(Time.get_ticks_msec() - _analytics_session_started_msec) / 1000.0
	_analytics_session_active = false
	_analytics.track_event(AnalyticsService.SESSION_END, {
		"seconds_bucket": AnalyticsService.seconds_bucket(elapsed),
		"reason": reason,
	})


## Editordeki bolum icin de _on_level_completed ile ayni kural: gercek
## ilerlemeye yazilmaz.
func _on_obstacle_kind_seen(kind: int) -> void:
	if _editor_level != null:
		return
	_progress.mark_obstacle_kind_seen(kind)


func _on_block_mechanic_seen() -> void:
	if _editor_level != null:
		return
	_progress.mark_block_mechanic_seen()


func _on_gameplay_menu_requested() -> void:
	if _editor_level != null:
		go_to_editor(_editor_level, _editor_source_level_id)
		return
	if _active_daily_challenge:
		go_to_retention()
		return
	await _show_completion_interstitial_if_needed()
	go_to_main_menu()


func _on_gameplay_level_select_requested() -> void:
	if _active_daily_challenge:
		go_to_retention()
		return
	await _show_completion_interstitial_if_needed()
	go_to_level_select()


func _show_completion_interstitial_if_needed() -> void:
	var gameplay := _current as Gameplay
	if gameplay == null or not gameplay.has_completed_result():
		return
	if _completion_ad_in_progress:
		return
	_completion_ad_in_progress = true
	if _ad_service != null:
		await _ad_service.request_interstitial(
			MonetizationConfig.CONTEXT_LEVEL_COMPLETE)
	_completion_ad_in_progress = false


# --- Bolum editoru (yalnizca debug) -------------------------------------------
#
# Ayri bir "admin" yapisi yok: bu ekrana giden tek yol debug panelidir.
# Panel ve editor sahnesi ana sahneye bagli degildir; yalnizca debug template
# calisirken dinamik yuklenir ve release AAB filtresinden tamamen cikarilir.

## [param source_level_id] 0'dan buyukse duzenlenen sey bir RESMI bolumdur;
## editor bunu kaydederken sidecar'a yazar (bkz. LevelEditor.source_level_id).
func go_to_editor(edit_level: LevelData = null, source_level_id := 0) -> void:
	if not OS.is_debug_build() or OS.has_feature("production"):
		return
	if _level_editor_scene == null:
		_level_editor_scene = load(LEVEL_EDITOR_SCENE_PATH) as PackedScene
	if _level_editor_scene == null:
		push_error("AppRoot: debug level editor sahnesi yuklenemedi.")
		return
	if edit_level == null:
		_editor_batch_context.clear()
	_editor_level = edit_level
	_editor_source_level_id = source_level_id
	await _transition(_level_editor_scene, _configure_editor)


func _configure_editor(screen: Node) -> void:
	if not _is_level_editor(screen):
		return
	screen.set("source_level_id", _editor_source_level_id)
	if not _editor_batch_context.is_empty():
		screen.set("initial_batch_context", _editor_batch_context)
	elif _editor_level != null:
		screen.set("level", _editor_level)


## Editordeki bolumu oynatir. Kopya DEGIL ayni kaynak verilir: test sirasinda
## bolum degismez, ve geri donuldugunde duzenleme aynen durur.
func _on_editor_test_requested(edit_level: LevelData) -> void:
	if _is_level_editor(_current):
		_editor_batch_context = _current.call("get_batch_context")
		_editor_source_level_id = int(_current.get("source_level_id"))
	_editor_level = edit_level
	# Acik kalan debug paneli arenanin ustunu ortup test edilen bolumu
	# gizlerdi. Kose dugmesi durdugu icin tek dokunusla geri acilir.
	if _debug_panel != null and is_instance_valid(_debug_panel):
		_debug_panel.call("hide_panel")
	await _transition(gameplay_scene, _configure_editor_gameplay,
		_editor_level.level_id if _editor_level != null else 0)


func _configure_editor_gameplay(screen: Node) -> void:
	var gameplay := screen as Gameplay
	if gameplay != null:
		# Tema burada DEGIL, _transition icinde uygulanir (sahne kurulmadan
		# once); bkz. oradaki not.
		gameplay.level_data = _editor_level
		gameplay.playtest_stats = _playtest_stats
		gameplay.progress = _progress
		# Bolum bitmez: hedefe isabet geri bildirimi oynar ama sonuc karti
		# acilmaz ve haklar tukenmez (bkz. Gameplay.practice_mode).
		gameplay.practice_mode = true


func _on_editor_closed() -> void:
	_editor_level = null
	_editor_batch_context.clear()
	go_to_main_menu()


# --- Geri tusu ---------------------------------------------------------------

func _handle_go_back() -> void:
	if _busy:
		return

	var splash := _current as SplashScreen
	if splash != null:
		splash.skip()
		return

	if _is_level_editor(_current):
		_on_editor_closed()
		return

	var gameplay := _current as Gameplay
	if gameplay != null:
		# Editorden test ediliyorsa geri tusu de editore doner.
		if _editor_level != null:
			go_to_editor(_editor_level, _editor_source_level_id)
		else:
			go_to_level_select()
		return

	var select := _current as LevelSelect
	if select != null:
		go_to_main_menu()
		return

	# Ana menude geri tusu uygulamadan cikar.
	get_tree().quit()


# --- Debug paneli -------------------------------------------------------------
#
# Panel sadece debug build'de dinamik kurulur. Release export'ta sahne ve script
# pakette bulunmaz; _debug_panel null kalir ve bu baglantilar kurulmaz.

func _setup_debug_tools() -> void:
	if not OS.is_debug_build() or OS.has_feature("production"):
		return
	var panel_scene := load(DEBUG_PANEL_SCENE_PATH) as PackedScene
	if panel_scene == null:
		push_error("AppRoot: debug panel sahnesi yuklenemedi.")
		return
	var debug_layer := CanvasLayer.new()
	debug_layer.name = "DebugLayer"
	debug_layer.layer = 200
	add_child(debug_layer)
	_debug_panel = panel_scene.instantiate()
	debug_layer.add_child(_debug_panel)
	_level_editor_scene = load(LEVEL_EDITOR_SCENE_PATH) as PackedScene


func _is_level_editor(screen: Node) -> bool:
	return (
		OS.is_debug_build()
		and not OS.has_feature("production")
		and screen != null
		and screen.has_signal("test_requested")
		and screen.has_signal("menu_requested")
		and screen.has_method("get_batch_context")
	)

func _connect_debug_panel() -> void:
	if _debug_panel == null or not is_instance_valid(_debug_panel) or _debug_panel.is_queued_for_deletion():
		return
	_debug_panel.connect("previous_level_requested", _on_debug_previous_level)
	_debug_panel.connect("next_level_requested", _on_debug_next_level)
	_debug_panel.connect("restart_level_requested", _on_debug_restart_level)
	_debug_panel.connect("unlock_all_toggled", _on_debug_unlock_all_toggled)
	_debug_panel.connect("reset_stats_requested", _on_debug_reset_stats)
	_debug_panel.connect("editor_requested", _on_debug_editor_requested)


func _on_debug_previous_level() -> void:
	if not (_current is Gameplay):
		return
	if _editor_level != null:
		if _step_editor_batch(-1):
			_transition(gameplay_scene, _configure_editor_gameplay,
				_editor_level.level_id if _editor_level != null else 0)
		return
	go_to_level(_current_level_id - 1)


func _on_debug_next_level() -> void:
	if not (_current is Gameplay):
		return
	if _editor_level != null:
		if _step_editor_batch(1):
			_transition(gameplay_scene, _configure_editor_gameplay,
				_editor_level.level_id if _editor_level != null else 0)
		return
	go_to_level(_current_level_id + 1)


func _step_editor_batch(direction: int) -> bool:
	var raw_levels = _editor_batch_context.get("levels", [])
	if not raw_levels is Array or raw_levels.size() <= 1:
		return false
	var index := wrapi(
		int(_editor_batch_context.get("index", 0)) + direction, 0, raw_levels.size())
	var next_level = raw_levels[index]
	if not next_level is LevelData:
		return false
	_editor_batch_context["index"] = index
	_editor_level = next_level
	return true


func _on_debug_restart_level() -> void:
	var gameplay := _current as Gameplay
	if gameplay != null:
		gameplay.reset_shot()


## Yalnizca oturum-ici bir bayrak degistirir; ProgressStore'a hic dokunmaz,
## bu yuzden gercek save dosyasi kalici olarak etkilenmez.
func _on_debug_unlock_all_toggled(enabled: bool) -> void:
	_debug_unlock_all = enabled
	var select := _current as LevelSelect
	if select != null:
		select.set_debug_force_unlock(enabled)


func _on_debug_reset_stats() -> void:
	if _playtest_stats != null:
		_playtest_stats.reset_all()


func _on_debug_editor_requested() -> void:
	if not OS.is_debug_build() or OS.has_feature("production"):
		return
	if _is_level_editor(_current):
		return

	# OYNANAN RESMI BOLUMU DUZENLE: debug panelini bir bolumun icinde acip
	# "DUZENLE" demek, "su an oynadigim bolumu ac" anlamina gelir - eskiden
	# bos bir editor aciliyordu ve resmi bolume dokunmanin tek yolu .tres'i
	# elle bulmakti.
	#
	# KOPYA verilir: LevelLibrary'nin dondurdugu kaynak onbellege alinabildigi
	# icin dogrudan duzenlemek, o oturumda o bolumu oynayan herkesi etkilerdi.
	var gameplay := _current as Gameplay
	if gameplay != null and gameplay.level_data != null:
		var source_id := gameplay.level_data.level_id
		go_to_editor(gameplay.level_data.duplicate(true) as LevelData, source_id)
		return

	if _editor_level != null:
		go_to_editor(_editor_level, _editor_source_level_id)
		return
	# Bos bolumle acilir; editordeki "AC" ile kayitli bir bolum yuklenebilir.
	go_to_editor()
