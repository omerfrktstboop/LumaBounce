class_name Gameplay
extends Node2D

## Bir bolumu oynatan ekran.
##
## Yerlesim sahnede sabit degildir: firlatici, hedef, paneller, kenar
## segmentleri ve top hakki tamamen [member level_data]'dan kurulur.
## Top fizigi (ball.gd), nisan onizlemesi (launcher.gd) ve carpma/kazanma
## efektleri degismeden korunur.
##
## Ekran baska bir sahne acmaz; yalnizca sinyal yayar, AppRoot karar verir.

signal level_completed(level_id: int, stars: int, seconds: float, shots: int)
signal level_failed(level_id: int, reason: String, shots: int, active_seconds: float)
signal next_level_requested(level_id: int)
signal level_select_requested()
signal menu_requested()
## Tanitim toast'i bir engel turunu ilk kez gosterdiginde yayilir. AppRoot
## dinler ve ProgressStore'a yazar (bkz. app_root.gd - "yazma AppRoot'a
## aittir" kurali, ayni sey level_completed/yildizlar icin de gecerli).
signal obstacle_kind_seen(kind: int)
## Kirilabilir blok mekanigi ilk kez gosterildiginde yayilir - obstacle_kind_seen
## ile ayni yazma kurali (bkz. app_root.gd).
signal block_mechanic_seen()
## KISA IPUCU istendi. Odulu veren AppRoot'tur (ileride odullu reklam
## servisi); Gameplay yalnizca ister ve grant_short_hint() ile sonucu alir.
signal short_hint_requested()
## Retention sayaçlari icin hafif olay. Analytics'e gonderilmez; AppRoot bunu
## DailyStore/AchievementStore'a yazar.
signal bounce_recorded()

@export var completed_title := "BÖLÜM TAMAMLANDI"
@export var failed_title := "BÖLÜM BAŞARISIZ"
@export var failed_subtitle := "HEDEFİ VURAMADIN"
@export var next_level_label := "SONRAKİ BÖLÜM"
@export var level_select_label := "BÖLÜM SEÇİMİ"
@export var retry_label := "TEKRAR OYNA"
@export var restart_label := "TEKRAR BAŞLA"
@export var menu_label := "ANA MENÜ"
@export var out_of_balls_message := "TOP HAKKI BİTTİ"
@export var daily_return_label := "GÜNLÜĞE DÖN"
## Kazanma efekti gorulsun diye sonuc karti kisa bir gecikmeyle acilir.
@export var result_delay := 0.75
## Basarisiz atistan sonra, hala hakki varsa otomatik sifirlama gecikmesi.
@export var auto_reset_delay := 0.35
## Test modunda hedefe isabetten sonra topun geri gelme gecikmesi.
@export var practice_hit_reset_delay := 0.7
@export var message_pop_time := 0.35
@export var level_title_format := "BÖLÜM %d"
## Oyuncu ilk gecerli nisan hareketini yapinca ipucu bu surede solar.
@export var tutorial_fade_time := 0.25

@export_group("Luma Coin Ipucu")
## TAM ROTA: bir bolumun ornek rotasini KALICI acma maliyeti.
@export var hint_cost := 5
## KISA IPUCU: rotanin yalnizca ilk parcasini gosterir. Bedeli odullu reklam
## izlemektir; Luma Coin HARCAMAZ ve kalici unlock SAYILMAZ (her istendiginde
## yeniden kazanilir). Bu alan 0'dan buyuk yapilirsa kisa ipucu da Coin
## isteyen bir secenege donusur - urun karari degisirse tek satir yeter.
@export var short_hint_cost := 2
## Kisa ipucu rotanin en fazla bu kadarini gosterir.
##
## Ust sinir SART: bazi bolumlerde ilk sekme yolun cok ilerisindedir ve
## "ilk sekmeye kadar goster" kurali tek basina rotanin tamamini vermis
## olurdu - o zaman tam rotayi satin almanin anlami kalmazdi.
@export_range(0.15, 0.60, 0.01) var short_hint_max_ratio := 0.40
## Kisa ipucu bundan kisa olmaz. Ilk sekme hemen firlaticinin onunde ise
## birkac pikselik bir cizgi hicbir sey anlatmazdi.
@export_range(0.05, 0.30, 0.01) var short_hint_min_ratio := 0.15

@export_group("Hizli Yeniden Nisan")
## Ucan bir top varken yalnizca firlaticinin bu yaricapindaki dokunuslar
## yeni bir nisan suruklemesi baslatabilir.
@export var reaim_touch_radius := 140.0
## Iptal edilen eski topun kisa gorsel izi. Yeni top beklemeden firlaticida
## gorunur; bu sure yalnizca eski konumdaki gorsel kopyaya uygulanir.
@export_range(0.10, 0.15, 0.01) var manual_cancel_fade_time := 0.12

@export_group("Bolum")
## Panellerin uretildigi sahne (bounce_panel.tscn).
@export var panel_scene: PackedScene
## Eger load_level ile belirli bir bolum yuklenmeden sahne acilirsa (onizleme).
@export var fallback_level_id := 1

@export_group("Nisan Zorlugu")
## 30'dan 40'a ilerlerken kılavuz %95'ten %50'ye iner. Fizik ve impuls aynidir.
@export var preview_reduction_start_level := 30
@export var preview_reduction_end_level := 40
@export_range(0.4, 1.0, 0.01) var preview_ratio_at_start := 0.95
@export_range(0.4, 1.0, 0.01) var preview_ratio_at_end := 0.50

@export_group("Carpma Efekti")
## Kivilcim siddetinin doygunluga ulastigi hiz.
@export var spark_reference_speed := 1600.0
@export var spark_count := 5
@export var spark_length := 24.0

@export_group("Ekran Titresimi")
## Panele carpma titresiminin carpani (gercek deger carpma hizina gore olceklenir).
@export_range(0.0, 1.0, 0.01) var bounce_shake_trauma := 0.4
## Blok kirilmasi sekmenin ustune EKLENEN kucuk bir vurgudur; sekme
## titresimi zaten calistigi icin bilerek dusuk tutulur.
@export_range(0.0, 1.0, 0.01) var block_break_shake_trauma := 0.22
@export_range(0.0, 1.0, 0.01) var target_hit_shake_trauma := 0.75
## Guc bari yeni bir kademeye ilk kez ciktiginda verilen hafif dokunsal tik.
## (Diger titresim sureleri Haptics'te sabittir; bunlar nisan alma hissine ait
## oldugu icin bolum bazinda ayarlanabilir kalir.)
@export var power_step_haptic_msec := 10
@export var max_power_step_haptic_msec := 20
## Bombaya temas, hedef kadar agir olmayan kisa bir tehlike vurgusudur.
@export_range(0.0, 1.0, 0.01) var hazard_shake_trauma := 0.34

## AppRoot tarafindan add_child'dan ONCE atanir.
var level_data: LevelData
## AppRoot tarafindan add_child'dan ONCE atanir; debug build disinda tum
## kayit cagrilari sessizce hicbir sey yapmaz (bkz. PlaytestStats).
var playtest_stats: PlaytestStats
## AppRoot tarafindan add_child'dan ONCE atanir. Buradan YALNIZCA onceki
## yildiz OKUNUR (yeni rekor tespiti icin); yazma islemi AppRoot'a aittir.
var progress: ProgressStore
## AppRoot tarafindan add_child'dan ONCE atanir. Harcama ve kalici ipucu
## kilitleri bu nesnenin tek sorumlulugudur.
var wallet: WalletStore
## AppRoot tarafindan enjekte edilen urun-seviyesi servisler. Gameplay provider,
## SDK sinifi veya reklam birimi kimligi bilmez.
var ad_service: AdService
var analytics: AnalyticsService
## TEST MODU - bolum editorunden "TEST" ile acildiginda AppRoot tarafindan
## acilir. Bolum BITMEZ: hedefe isabet geri bildirimi oynar ama sonuc karti
## acilmaz, haklar tukenmez, ilerleme yazilmaz. Amac bolumu degerlendirmek
## degil, geometriyi istedigin kadar denemek.
var practice_mode := false
## Daily challenge campaign progression'ina yazilmaz ve sonuc kartinin ana
## eylemi sonraki bolum yerine retention ekranina doner.
var daily_mode := false
## Oyuncunun ayarlardan sectigi nisan yardimi. AppRoot tarafindan add_child'dan
## ONCE atanir; ProgressStore'dan okunur, ekran kendi basina ayara bakmaz.
var aim_assist := false

@onready var _arena: Arena = $Arena
@onready var _panels: Node2D = $Panels
@onready var _blocks: BreakableField = $Blocks
@onready var _obstacles: ObstacleField = $Obstacles
@onready var _launcher: Launcher = $Launcher
@onready var _ball: Ball = $Ball
@onready var _target: Target = $Target
@onready var _effects: Node2D = $Effects
@onready var _hint_path: HintPath = $HintPath
@onready var _shake: ScreenShake = $ShakeCamera
@onready var _message: Label = $HUD/SafeArea/Root/Message
@onready var _tutorial: Label = $HUD/SafeArea/Root/TutorialLabel
@onready var _intro_card: MechanicIntroCard = $HUD/MechanicIntroCard
@onready var _level_title: Label = $HUD/SafeArea/Root/LevelHeader/LevelTitle
@onready var _level_subtitle: Label = $HUD/SafeArea/Root/LevelHeader/LevelSubtitle
@onready var _pause_button: LumaIconButton = $HUD/SafeArea/Root/PauseButton
@onready var _pause_card: PauseCard = $HUD/PauseCard
@onready var _hint_button: LumaIconButton = $HUD/SafeArea/Root/HintButton
@onready var _hint_badge: Label = $HUD/SafeArea/Root/HintButton/HintBadge
@onready var _coin_chip: PanelContainer = $HUD/SafeArea/Root/CoinChip
@onready var _coin_value: Label = $HUD/SafeArea/Root/CoinChip/Row/Value
@onready var _hint_status: HBoxContainer = $HUD/SafeArea/Root/HintStatus
@onready var _hint_status_text: Label = $HUD/SafeArea/Root/HintStatus/Text
@onready var _hint_status_glyph: Control = $HUD/SafeArea/Root/HintStatus/Glyph
@onready var _lives_display: LivesDisplay = $HUD/SafeArea/Root/LivesDisplay
@onready var _result_panel: ResultPanel = $HUD/ResultPanel
@onready var _hint_card: HintPurchaseCard = $HUD/HintPurchaseCard

var _message_tween: Tween
var _tutorial_tween: Tween
var _hint_status_tween: Tween
## Ipucu bu denemede zaten solduysa tekrar tetiklenmesin.
var _tutorial_dismissed := false
## Bu bolume GIRISTE (restart'ta degil) gosterilecek, oyuncunun daha once
## hic gormedigi engel turleri - bkz. _apply_level(), reset_shot().
var _pending_obstacle_intro_kinds: Array[int] = []
## Bu bolum ilk kez kirilabilir blok iceriyorsa ve oyuncu mekanigi daha once
## hic gormemisse true - engel turlerinden farkli olarak tek bir bayraktir.
var _pending_block_intro := false
## Su an acik olan kart bir engel mi yoksa blok mekanigi mi - kart kapaninca
## hangi sinyalin yayilacagi buradan bilinir.
var _showing_block_intro := false
## Kart acilmadan onceki firlatici durumu; kapaninca aynen geri verilir.
var _launcher_enabled_before_intro := true
var _launcher_enabled_before_hint := true
var _launcher_enabled_before_pause := true
var _hint_trace := PackedVector2Array()
var _hint_waiting_for_blocks := false
## Kisa ipucu su an verilebilir mi. AppRoot AdService hazirligindan enjekte eder;
## Gameplay NEDENINI bilmez - reklam servisi, abonelik ya da baska bir kosul
## olabilir. Boylece reklam SDK'si eklendiginde bu dosya degismez.
var short_hint_enabled := false
## Kisa ipucu SU ANKI denemede gosterildi mi. Kalici degildir: bolum
## yeniden baslatilinca sifirlanir, cunku kalici olan tek sey satin alinan
## tam rotadir.
var _short_hint_shown := false
var _full_hint_used_this_attempt := false
var _pending_luma_coin_reward := 0
var _max_lives := 5
var _lives_remaining := 0
## Her "gecerli atis denemesi" basladiginda artar (bkz. _respawn_ball).
## Gecikmeli otomatik-sifirlama zamanlayicisi, calistigi anda bu deger
## degismisse (araya manuel "Yeniden Dene" girmisse) kendini iptal eder.
var _shot_token := 0
## Nisan almayi engellemesi gereken HUD ogeleri.
var _input_blockers: Array[Control] = []

# --- Debug/playtest durumu ---------------------------------------------------
#
# Bu alanlar SADECE gozlem icindir (debug paneli okur, oynanis mantigi
# bunlara gore dallanmaz); bu yuzden oynanis kodunun geri kalanindan
# ayri, kendi bolumunde tutulur.

## reset_shot() ilk kez mi (giris) yoksa tekrar mi (restart) cagriliyor.
var _has_started := false
var _shots_this_attempt := 0
var _attempt_active_start_msec := 0
var _attempt_elapsed_seconds := 0.0
## Deneme kronometresi bolume GIRINCE degil, oyuncu ilk topu gercekten nisan
## almaya baslayinca calisir. Bolumu inceleyip yerlesimi okumak yildiz suresini
## yemez. Ipucunun soldugu anla ayni tetik kullanilir (ilk gecerli nisan),
## boylece "sure basladi" ile "artik oynuyorsun" ayni an olur.
var _attempt_timer_running := false
var _level_active_start_msec := 0
var _level_elapsed_seconds := 0.0
var _playtest_timing_paused := false
var _timing_pause_reasons := {}
var _last_shot_power := 0.0
var _last_shot_angle_deg := 0.0
var _last_failure_reason := "-"
## Bolum bittigi ANDA dondurulan sure. Sonuc paneli gecikmeli acildigi ve
## kart ekranda beklerken kronometre calismaya devam ettigi icin, yildiz
## hesabi ve kartta gosterilen deger bu dondurulmus degeri kullanir.
var _final_attempt_seconds := 0.0
var _final_attempt_shots := 0
## Bolum bitti (hedef vuruldu veya haklar tukendi). Kronometre burada durur;
## sonuc karti ekranda beklerken sure ilerlemez.
var _attempt_finished := false
var _attempt_completed := false
var _active_touch_index := -1
var _touch_indices: Array[int] = []
var _suppress_touch_until_release := false
## Ucan top sirasinda firlatici bolgesinden baslayan, henuz minimum surukleme
## esigini gecmedigi icin aktif atisi iptal etmemis nisan hareketi.
var _reaim_pending := false


func _ready() -> void:
	_apply_level()
	_sync_tuning()
	_connect_signals()
	get_viewport().size_changed.connect(_position_shake_camera)
	_position_shake_camera()
	_input_blockers.append(_pause_button)
	_input_blockers.append(_pause_card)
	_input_blockers.append(_hint_button)
	_input_blockers.append(_hint_card)
	_refresh_hint_hud()
	_start_playtest_timing()
	if playtest_stats != null:
		playtest_stats.record_entry(level_data.level_id)
	reset_shot()


func _exit_tree() -> void:
	if playtest_stats == null or level_data == null:
		return
	_flush_playtest_time()
	playtest_stats.add_time_spent(level_data.level_id, _level_elapsed_seconds)


# --- Bolum kurulumu ----------------------------------------------------------

func _apply_level() -> void:
	if level_data == null:
		level_data = LevelLibrary.load_level(fallback_level_id, _arena.get_play_rect())

	var play_rect := _arena.get_play_rect()
	_arena.configure(
		level_data.get_left_segments(play_rect),
		level_data.get_right_segments(play_rect))

	_launcher.position = level_data.launcher_position
	_target.position = level_data.target_position

	# NOT: burada eskiden AppRoot/BackgroundLayer'a ULASILIP gorunurlugu
	# "level_id > 50" ile aciliyordu. Iki sorunu vardi: bir ekran AppRoot'un
	# icine uzaniyordu (projenin "ekranlar yukari dogru bilmez" kuralina
	# aykiri) ve zemin bir RENK degil, ikili bir ac/kapa olarak yonetiliyordu.
	# Zemin artik temanin parcasi ve AppRoot tarafindan kuruluyor
	# (bkz. AppRoot._configure_gameplay).

	_target.scale = Vector2.ONE * level_data.target_scale
	_ball.set_radius(24.0 * level_data.ball_scale)

	_launcher.accent = Palette.ACCENT
	_launcher.accent_core = Palette.ACCENT_CORE
	_launcher._build_base()
	_launcher._build_barrel()
	_launcher._build_power_meter()
	_launcher._build_drag_hint()

	_target.accent = Palette.ACCENT
	_target.core_color = Palette.ACCENT_CORE
	_target._build_visual()

	# Kozmetikler paletten SONRA uygulanir: secili bir deri varsa bant
	# temasini ezer, yoksa hicbir sey degismez ve bugunku gorunum kalir.
	# Yalnizca gorunum alanlarina yazar (bkz. CosmeticApplier).
	CosmeticApplier.apply(wallet, _ball, _launcher, _target)

	_max_lives = maxi(level_data.max_lives, 1)

	_build_panels()
	_obstacles.build(level_data.obstacles)
	_obstacles.reset_motion()
	_apply_level_header()
	_pending_obstacle_intro_kinds = _newly_seen_obstacle_kinds()
	_pending_block_intro = (not level_data.breakable_blocks.is_empty()
		and progress != null and not progress.has_seen_block_mechanic())


## Bu bolumun engelleri arasinda oyuncunun daha once hic gormedigi turler.
## Sira level_data.obstacles sirasiyla aynidir; ayni tur birden fazla
## engelde geçse bile listede bir kez gecer.
func _newly_seen_obstacle_kinds() -> Array[int]:
	var fresh: Array[int] = []
	if progress == null:
		return fresh
	for obstacle in level_data.obstacles:
		if obstacle == null:
			continue
		if not progress.has_seen_obstacle_kind(obstacle.kind) and not fresh.has(obstacle.kind):
			fresh.append(obstacle.kind)
	return fresh


func _build_panels() -> void:
	for child in _panels.get_children():
		_panels.remove_child(child)
		child.queue_free()

	if panel_scene == null:
		push_error("Gameplay: panel_scene atanmamis, paneller olusturulamiyor.")
		return

	for panel_data in level_data.panels:
		if panel_data == null:
			continue
		var panel := panel_scene.instantiate() as BouncePanel
		if panel == null:
			push_error("Gameplay: panel_scene bir BouncePanel degil.")
			return
		panel.position = panel_data.position
		panel.rotation_degrees = panel_data.rotation_degrees
		panel.length = panel_data.length
		panel.thickness = panel_data.thickness
		_panels.add_child(panel)


## Uzun ekranlarda ust tarafta olusan bosluga bolum kimligi ve editorun
## hesapladigi zorluk tier'i gelir; bolum adi HUD'da tekrarlanmaz.
func _apply_level_header() -> void:
	# tr() BICIMLENDIRMEDEN ONCE: Control'un otomatik cevirisi hazir metni
	# arar, yani "BÖLÜM 5" tabloda bulunamaz. Cevrilmesi gereken KALIPTIR.
	_level_title.text = tr(level_title_format) % level_data.level_id
	# Test modu basligi: bolum neden bitmiyor sorusunun yaniti gorunur olsun,
	# yoksa "hedefi vurdum ama bir sey olmadi" bir hata gibi okunur.
	var difficulty_label := level_data.difficulty_label()
	var subtitle := tr(difficulty_label) if not difficulty_label.is_empty() else ""
	if practice_mode:
		subtitle = tr("%s · TEST (bölüm bitmez)") % subtitle if not subtitle.is_empty() \
			else tr("TEST (bölüm bitmez)")
	_level_subtitle.text = subtitle
	_level_subtitle.visible = not subtitle.is_empty()


func _sync_tuning() -> void:
	# Nisan kilavuzu topun gercek yer cekimi/sekme/yaricap/hiz davranisiyla
	# ayni sonucu vermeli, yoksa onizleme ile gercek carpisma ayrisir.
	_launcher.preview_gravity = _ball.gravity
	_launcher.preview_bounciness = _ball.bounciness
	_launcher.preview_ball_radius = _ball.radius
	_launcher.preview_max_speed = _ball.max_speed
	_launcher.set_guide_visibility_ratio(_preview_ratio_for_level(level_data.level_id))
	_ball.play_bounds = _arena.get_play_rect()


func _preview_ratio_for_level(level_id: int) -> float:
	# Nisan yardimi acikken iz her bolumde tam uzunlukta kalir - ayarin
	# tamami budur, baska hicbir sey degismez (zorluk, yildiz, fizik ayni).
	if aim_assist:
		return 1.0
	if level_id < preview_reduction_start_level:
		return 1.0
	var span := maxi(preview_reduction_end_level - preview_reduction_start_level, 1)
	var progress_ratio := clampf(
		float(level_id - preview_reduction_start_level) / float(span), 0.0, 1.0)
	return lerpf(preview_ratio_at_start, preview_ratio_at_end, progress_ratio)


## Kamerayi yatayda oyun alaninin merkezinde, dikeyde alt kenara hizali tutar.
## 720x1280'de eski merkez gorunum korunur; uzun ekranlarda ekstra alan ustte
## acilir ve launcher/HUD ekranin altina yakin kalir.
func _position_shake_camera() -> void:
	var play_rect := _arena.get_play_rect()
	var visible_size := get_viewport_rect().size
	_shake.position = Vector2(
		play_rect.position.x + play_rect.size.x * 0.5,
		play_rect.position.y + play_rect.size.y - visible_size.y * 0.5)


func _connect_signals() -> void:
	_launcher.shot_fired.connect(_on_shot_fired)
	_launcher.aim_cancelled.connect(_on_aim_cancelled)
	_launcher.power_step_crossed.connect(_on_power_step_crossed)
	_ball.bounced.connect(_on_ball_bounced)
	_ball.surface_touched.connect(_on_surface_touched)
	_blocks.block_broken.connect(_on_block_broken)
	_blocks.block_damaged.connect(_on_block_damaged)
	_obstacles.hazard_triggered.connect(_on_hazard_triggered)
	_ball.shot_failed.connect(_on_shot_failed)
	_target.hit.connect(_on_target_hit)
	# Ilk gecerli nisan hareketinde ipucunu sondur.
	_launcher.aim_updated.connect(_on_aim_updated)
	# Tiklama sesini LumaButton'un kendisi calar (HUD butonlari da LumaIconButton).
	# TEKRAR BASLA ve ANA MENU artik ust seritte DEGIL, duraklat kartinin
	# icinde: ikisi de geri alinamaz eylemler ve oynanis sirasinda tek
	# dokunusla erisilebilir olmalari yanlislikla bir denemeyi bitiriyordu.
	_pause_button.pressed.connect(_on_pause_pressed)
	_pause_card.resume_requested.connect(_on_pause_resume)
	_pause_card.restart_requested.connect(_on_pause_restart)
	_pause_card.level_select_requested.connect(level_select_requested.emit)
	_pause_card.menu_requested.connect(menu_requested.emit)
	_hint_button.pressed.connect(_on_hint_pressed)
	_hint_card.purchase_requested.connect(_on_hint_purchase_requested)
	_hint_card.short_hint_requested.connect(_on_short_hint_requested)
	_hint_card.dismissed.connect(_on_hint_card_dismissed)
	_intro_card.dismissed.connect(_on_intro_card_dismissed)
	_result_panel.next_pressed.connect(_on_result_next)
	_result_panel.retry_pressed.connect(_on_result_retry)
	# Gameplay hicbir sahne acmaz; AppRoot mevcut fade gecisiyle karar verir.
	_result_panel.level_select_pressed.connect(level_select_requested.emit)
	_result_panel.menu_pressed.connect(menu_requested.emit)


# --- Oyun dongusu ------------------------------------------------------------

## BOLUM YENIDEN BASLATMA. Haklar dolar, atis sayaci ve kronometre sifirlanir,
## KIRILAN TUM BLOKLAR GERI GELIR. (Karsiti: _respawn_ball, yalnizca ATIS
## sifirlamasidir ve bloklara dokunmaz.)
##
## _has_started, bolume ILK giris ile MANUEL yeniden baslatmayi ayirir:
## giriste ne restart sayaci artar ne de restart sesi calar.
func reset_shot() -> void:
	var is_first_entry := not _has_started
	if _has_started:
		if analytics != null and not practice_mode and level_data != null:
			analytics.track_event(AnalyticsService.RESTART, {
				"level_id": level_data.level_id,
				"world": _analytics_world_key(),
				"shots_bucket": AnalyticsService.shots_bucket(_shots_this_attempt),
				"source": &"manual",
			})
		AudioManager.play_restart()
		if playtest_stats != null:
			playtest_stats.record_restart(level_data.level_id)
	_has_started = true
	_shots_this_attempt = 0
	_reset_attempt_timer()
	_hint_path.hide_path()
	_hint_waiting_for_blocks = false
	_short_hint_shown = false
	_full_hint_used_this_attempt = false
	_pending_luma_coin_reward = 0
	_hide_hint_status()
	# Ipucu yalnizca bolum bastan baslarken geri gelir; basarisiz atistan
	# sonraki otomatik top respawn'inda gelmez.
	_show_tutorial()
	# Tanitim karti ise SADECE gercek ilk giriste acilir - manuel "Tekrar Basla"
	# ayni deneme icinde onu tekrar tekrar gostermemeli
	# (bkz. _pending_obstacle_intro_kinds, _apply_level tarafindan bolum
	# basina bir kez hesaplanir).
	if is_first_entry:
		_show_next_intro_card()

	# Bloklar bilerek _apply_level'da degil BURADA kurulur: paneller ve
	# duvarlar bolumun degismeyen iskeleti, bloklar ise deneme boyunca
	# degisen durumudur. Boylece "bloklar ne zaman geri gelir" sorusunun
	# yaniti tek bir yerdedir ve yanlislikla atis sifirlamasina sizamaz.
	_blocks.build(level_data.breakable_blocks)

	_lives_remaining = _max_lives
	_update_lives_hud()
	_result_panel.hide_result()
	_respawn_ball()


## AppRoot arka plan / geri donus bildirimlerinde cagirir. Oyun agaci
## duraklatildigi icin fizik zaten ilerlemez; burada yalnizca playtest
## kronometresini ve yarim kalmis dokunma durumunu guvenli hale getiririz.
# --- Duraklatma -------------------------------------------------------------

## Oyuncu duraklat tusuna basti mi. AppRoot bunu OKUR: uygulama arka plandan
## geri geldiginde agaci kendiliginden devam ettirmemeli, yoksa elle
## duraklatilmis oyun kartin arkasinda calismaya baslardi.
func is_manually_paused() -> bool:
	return _pause_card != null and _pause_card.is_open()


func _on_pause_pressed() -> void:
	if _attempt_finished or _result_panel.visible or _intro_card.is_open():
		return
	if _hint_card.is_open():
		_hint_card.close()
	_launcher_enabled_before_pause = _launcher.enabled
	_launcher.cancel_aim()
	_launcher.enabled = false
	_pause_card.open()
	# Agaci duraklatmak topu, engelleri ve tweenleri BIRLIKTE durdurur.
	# Kartin kendisi PROCESS_MODE_ALWAYS oldugu icin butonlari calisir kalir.
	get_tree().paused = true
	_set_playtest_timing_pause(&"manual", true)


func _on_pause_resume() -> void:
	_pause_card.close()
	get_tree().paused = false
	_set_playtest_timing_pause(&"manual", false)
	if not _intro_card.is_open() and not _attempt_finished:
		_launcher.enabled = _launcher_enabled_before_pause


## Duraklatmadan TEKRAR BASLA: once agaci serbest birakmak sart, yoksa
## reset_shot'in tweenleri ve fizik adimlari donmus agacta calismaz.
func _on_pause_restart() -> void:
	_pause_card.close()
	get_tree().paused = false
	_set_playtest_timing_pause(&"manual", false)
	reset_shot()


func set_app_paused(paused: bool) -> void:
	_set_playtest_timing_pause(&"application", paused)
	if paused:
		_cancel_pointer_state()


func set_fullscreen_ad_active(active: bool) -> void:
	_set_playtest_timing_pause(&"advertisement", active)


## ATIS SIFIRLAMA. Sadece topu ve hedefi baslangic durumuna dondurur; top
## hakkina ve KIRILMIS BLOKLARA dokunmaz - kirilan blok bolum cozumunun
## ilerlemesidir, yeni top eskisinin actigi yoldan devam eder.
func _respawn_ball() -> void:
	_shot_token += 1
	_reaim_pending = false
	_launcher.cancel_aim()
	_ball.reset_to(_launcher.get_spawn_position())
	_target.reset()
	_obstacles.reset_motion()
	_clear_effects()
	_hide_message()
	_launcher.enabled = true


func _on_shot_fired(impulse: Vector2) -> void:
	# Ayni anda yalnizca bir top aktif olabilir.
	if not _ball.is_ready_to_launch():
		return
	_reaim_pending = false
	_hint_path.hide_path()

	_shots_this_attempt += 1
	_last_shot_power = impulse.length()
	_last_shot_angle_deg = rad_to_deg(Vector2.UP.angle_to(impulse.normalized()))
	if playtest_stats != null:
		playtest_stats.record_shot(level_data.level_id)

	# Guc orani firlaticinin kendi araligindan turetilir; boylece ses
	# ayarlari min/max_power degisirse otomatik uyum saglar.
	AudioManager.play_launch(clampf(
		inverse_lerp(_launcher.min_power, _launcher.max_power, impulse.length()), 0.0, 1.0))

	_ball.launch(impulse)
	_obstacles.start_motion()


func _on_shot_failed(reason: String) -> void:
	_reaim_pending = false
	_last_failure_reason = reason
	if playtest_stats != null:
		playtest_stats.record_failure(level_data.level_id, reason)

	_launcher.enabled = false
	if _consume_life():
		return

	# Bekleme sirasinda oyuncu manuel "Yeniden Dene"ye basarsa _respawn_ball()
	# token'i ilerletir; sure doldugunda token degismisse bu zamanlayici
	# artik gecersizdir ve yeni (manuel baslatilmis) atisi ezmeden iptal olur.
	var token := _shot_token
	await get_tree().create_timer(auto_reset_delay, false).timeout
	if token != _shot_token:
		return
	_respawn_ball()


## Ucan topu, Launcher'in devam eden nisan suruklemesini bozmadan iptal eder.
## Ball.shot_failed yayilmaz; hak ve istatistik burada tam olarak bir kez islenir.
func _cancel_active_shot_for_reaim() -> void:
	if not _reaim_pending or not _launcher.has_valid_aim() or not _ball.is_flying():
		return

	_reaim_pending = false
	_shot_token += 1
	_ball.cancel_and_reset_to(_launcher.get_spawn_position(), manual_cancel_fade_time)
	_ball.set_launcher_tension(
		_launcher.get_power_ratio(), _launcher.get_aim_direction(),
		_launcher.loaded_ball_pullback_distance)
	_obstacles.reset_motion()
	_clear_effects()
	_hide_message()

	_last_failure_reason = "manual_cancel"
	if playtest_stats != null:
		playtest_stats.record_failure(level_data.level_id, "manual_cancel")

	if _consume_life():
		_launcher.cancel_aim()
		_launcher.enabled = false
		return

	# cancel_and_reset_to topu READY yapar. Launcher'in nisan durumu bilerek
	# korunur; ayni parmak hareketi guc/aciyi guncelleyip yeni topu firlatabilir.
	_launcher.enabled = true


## Bir hak harcar. Haklar bittiyse basarisizlik akisini baslatir ve true
## doner; cagiran o noktada durmalidir.
##
## TEST MODUNDA hak harcanmaz: editorden gelen amac bolumu "gecmek" degil
## geometriyi denemektir, ve dorduncu atista basarisizlik karti acilan bir
## test araci ise yaramaz.
func _consume_life() -> bool:
	if practice_mode:
		return false
	_lives_remaining = maxi(_lives_remaining - 1, 0)
	_update_lives_hud()
	if _lives_remaining > 0:
		return false
	_handle_out_of_lives()
	return true


## Son top da bitti. Iki cagiran var (normal iska ve manuel iptal), bu yuzden
## ses + mesaj + sonuc karti tek yerde toplanir.
func _handle_out_of_lives() -> void:
	# Sadece SON hak bitince duyulur; her sıradan iskada agir bir
	# kaybetme sesi calmak yorucu olurdu.
	AudioManager.play_failure()
	_show_message(out_of_balls_message)
	_open_failure_panel()


func _update_lives_hud() -> void:
	_lives_display.set_lives(_lives_remaining, _max_lives)


func _on_target_hit(_body: Node2D) -> void:
	if not _ball.is_flying():
		return
	_reaim_pending = false
	_ball.stop()
	_obstacles.stop_motion()
	_launcher.enabled = false
	# Kazanma anini ikincil vurgu (menekse) ile isaretle.
	SparkBurst.burst(
		_effects, _target.global_position, Vector2.UP, 1.0,
		Palette.ACCENT_ALT, Palette.ACCENT_ALT_CORE, 12, 74.0, 350.0)
	_shake.add_trauma(target_hit_shake_trauma)
	Haptics.target_hit()
	AudioManager.play_target_hit()

	# TEST MODU: isabetin tum geri bildirimi (kivilcim, titresim, ses) oynar
	# ama bolum bitmez - kart acilmaz, ilerleme yazilmaz. Top ve hedef kisa
	# bir gecikmeyle sifirlanir, kaldigin yerden denemeye devam edersin.
	if practice_mode:
		_respawn_after_practice_hit()
		return

	# Sure ve atis burada dondurulur: kart gecikmeli acilir ve ekranda
	# beklerken kronometrenin islemesi yildizi haksiz yere dusururdu.
	_freeze_attempt()
	_attempt_completed = true

	if playtest_stats != null:
		playtest_stats.record_completion(
			level_data.level_id, _final_attempt_shots, _final_attempt_seconds)

	var stars := level_data.calculate_stars(_final_attempt_seconds, _final_attempt_shots)
	# Kaydi AppRoot yazar; "yeni rekor" karari YAZMADAN ONCE alinmali.
	var previous_stars := progress.get_level_stars(level_data.level_id) if progress != null else 0
	var new_record := stars > previous_stars

	level_completed.emit(
		level_data.level_id, stars, _final_attempt_seconds,
		_final_attempt_shots)
	_open_success_panel(stars, new_record)


## Test modunda isabetten sonra. Gecikme hedefin kendi isabet animasyonundan
## (halka ~0.55 sn) biraz uzun, yoksa vurdugunu gormeden top geri gelirdi.
func _respawn_after_practice_hit() -> void:
	var token := _shot_token
	await get_tree().create_timer(practice_hit_reset_delay, false).timeout
	if token != _shot_token or not is_inside_tree():
		return
	# _respawn_ball hedefi de sifirlar, boylece tekrar vurulabilir hale gelir.
	_respawn_ball()


func _open_success_panel(stars: int, new_record: bool) -> void:
	var token := _shot_token
	await get_tree().create_timer(result_delay, false).timeout
	# Bu arada yeniden baslatildiysa karti acma.
	if token != _shot_token or not is_inside_tree():
		return
	var next_text := daily_return_label if daily_mode else (
		next_level_label if _can_advance_to_next() else level_select_label)
	_result_panel.show_success(
		completed_title, next_text, retry_label,
		stars, _final_attempt_seconds, _final_attempt_shots, new_record,
		_pending_luma_coin_reward)
	# target_hit'ten result_delay kadar sonra geldigi icin ust uste binmez.
	AudioManager.play_level_complete()


## Son top da kaybedildi. Yildiz GOSTERILMEZ - bolum tamamlanmadi.
func _open_failure_panel() -> void:
	_freeze_attempt()
	_attempt_completed = false

	var token := _shot_token
	await get_tree().create_timer(result_delay, false).timeout
	if token != _shot_token or not is_inside_tree():
		return
	level_failed.emit(
		level_data.level_id, _last_failure_reason, _final_attempt_shots,
		_final_attempt_seconds)
	_result_panel.show_failure(
		failed_title, failed_subtitle, restart_label,
		_final_attempt_seconds, _final_attempt_shots)


func _on_result_next() -> void:
	if daily_mode:
		menu_requested.emit()
		return
	if _can_advance_to_next():
		next_level_requested.emit(level_data.level_id + 1)
	else:
		level_select_requested.emit()


## Sonraki bolum var mi VE gercekten acik mi. Ikincisi sart: 21. bolumun
## yildiz kapisi henuz dolmamissa "SONRAKI BOLUM" butonu kapiyi delerdi.
## Bu kontrol basari paneli acilirken yapilir; AppRoot o ana kadar
## level_completed sinyalini isleyip yildizi kaydetmis olur, yani kapinin
## bu tamamlamayla acilip acilmadigi da dogru gorunur.
func _can_advance_to_next() -> bool:
	if daily_mode:
		return false
	var next_id := level_data.level_id + 1
	if not LevelLibrary.has_next(level_data.level_id):
		return false
	return progress == null or progress.is_unlocked(next_id)


func has_completed_result() -> bool:
	return _attempt_finished and _attempt_completed


## Hem basaridaki "TEKRAR OYNA" hem basarisizliktaki "TEKRAR BASLA".
## Ayni reset mantigi ikinci kez yazilmaz: reset_shot() zaten haklari,
## atis sayacini, attempt zamanlayicisini, hedefi, topu, ipucunu ve
## retry pulse'ini sifirlar; panel de orada kapanir.
func _on_result_retry() -> void:
	reset_shot()


# --- Carpma geri bildirimi ---------------------------------------------------

## Topun her temasi buraya duser (hiz esigi YOK - bkz. Ball.surface_touched).
## Sekmenin kendisi zaten fizik tarafindan cozuldu; burada yalnizca "bu temas
## ne anlama geliyor" sorusu yanitlanir.
func _on_surface_touched(collider: Object, _at: Vector2, _normal: Vector2) -> void:
	var block := collider as BreakableBlock
	if block == null:
		return
	block.take_hit()


func _on_hazard_triggered(reason: String, at: Vector2) -> void:
	if not _ball.is_flying():
		return
	if reason == "speed_boost":
		var blocks_node = get_node_or_null("Blocks")
		if blocks_node and blocks_node.has_method("shatter_in_radius"):
			blocks_node.shatter_in_radius(at, 180.0)
		SparkBurst.burst(
			_effects, at, Vector2.UP, 1.5,
			Palette.ACCENT_ALT, Palette.ACCENT_ALT_CORE, 24, 100.0, 500.0)
		_shake.add_trauma(0.6)
		Haptics.pulse(power_step_haptic_msec)
		AudioManager.play_target_hit()
		return
		
	if reason == "laser":
		# Bomba kadar olumcul ama gorsel dili farkli: patlama degil, isinin
		# uzerinde ince ve keskin bir kivilcim cizgisi.
		SparkBurst.burst(
			_effects, at, Vector2.UP, 1.4,
			Palette.HAZARD_CORE, Palette.HAZARD, 18, 90.0, 520.0)
		_shake.add_trauma(0.7)
		Haptics.hazard(true)
		_ball.fail_shot(reason)
		return

	if reason == "bomb":
		SparkBurst.burst(
			_effects, at, Vector2.UP, 2.0,
			Palette.HAZARD, Palette.HAZARD_CORE, 30, 150.0, 600.0)
		_shake.add_trauma(0.8)
		Haptics.hazard(true)
		_ball.fail_shot(reason)
		return
		
	SparkBurst.burst(
		_effects, at, Vector2.UP, 0.72,
		Palette.HAZARD, Palette.HAZARD_CORE, 7, 34.0, 230.0)
	_shake.add_trauma(hazard_shake_trauma)
	Haptics.hazard()
	_ball.fail_shot(reason)


func _on_block_damaged(_at: Vector2, _remaining_hits: int, _maximum_hits: int) -> void:
	Haptics.block_damage()


## Gorsel parcalar blogun KENDI icinde cizilir (bkz. BreakableBlock._draw) ve
## temas noktasindaki kivilcimi zaten sekme uretir. Buraya ayri bir partikul
## daha eklemek ayni ani uc kez anlatmak olurdu; burada sadece ses ve kucuk
## bir titresim vardir.
func _on_block_broken(_at: Vector2) -> void:
	# Sekme sesi bu cagriyla bastirilir (bkz. AudioManager.play_block_break),
	# ama sekmenin kivilcimi ve titresimi aynen kalir.
	AudioManager.play_block_break()
	_shake.add_trauma(block_break_shake_trauma)
	if _hint_waiting_for_blocks and _blocks.get_remaining_count() == 0:
		_hint_waiting_for_blocks = false
		_show_unlocked_hint.call_deferred()


func _on_ball_bounced(at: Vector2, normal: Vector2, impact_speed: float) -> void:
	var strength := clampf(impact_speed / spark_reference_speed, 0.3, 1.0)
	SparkBurst.burst(
		_effects, at, normal, strength,
		Palette.ACCENT, Palette.ACCENT_CORE, spark_count, spark_length)
	_shake.add_trauma(strength * bounce_shake_trauma)
	# Titresim de AYNI strength olcegini kullanir: siyirma gibi hafif bir temas
	# ile sert bir carpisma ayni darbeyi verirse geri bildirim anlamsizlasir.
	# Sinyalin kendisi zaten Ball.min_impact_for_feedback ile suzuldugu icin
	# burada ayrica bir esik yok (bkz. ball.gd "bounced").
	Haptics.bounce(strength)
	# Ham impact_speed verilir; katman secimi ve cooldown AudioManager'da.
	AudioManager.play_bounce(impact_speed)
	if not practice_mode:
		bounce_recorded.emit()


func _clear_effects() -> void:
	for child in _effects.get_children():
		_effects.remove_child(child)
		child.queue_free()


# --- Girdi -------------------------------------------------------------------
#
# Hem fare hem dokunma desteklenir. Godot dokunmadan fare olayi da uretebildigi
# icin ayni hareket iki kez gelebilir; launcher tarafi idempotent oldugundan
# bu durum ikinci bir atis yaratmaz.

func _unhandled_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null:
		_handle_touch_input(touch)
		return

	var drag := event as InputEventScreenDrag
	if drag != null:
		_pointer_moved(drag.position)
		return

	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_pointer_pressed(button.position)
			else:
				_pointer_released()
		return

	var motion := event as InputEventMouseMotion
	if motion != null:
		_pointer_moved(motion.position)


func _handle_touch_input(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if not _touch_indices.has(touch.index):
			_touch_indices.append(touch.index)
		if _touch_indices.size() > 1:
			_suppress_touch_until_release = true
			_active_touch_index = -1
			_reaim_pending = false
			_launcher.cancel_aim()
			return
		if _suppress_touch_until_release:
			return
		_active_touch_index = touch.index
		_pointer_pressed(touch.position)
		return

	_touch_indices.erase(touch.index)
	if _suppress_touch_until_release:
		if _touch_indices.is_empty():
			_suppress_touch_until_release = false
		return
	if touch.index != _active_touch_index:
		return
	_active_touch_index = -1
	_pointer_released()


func _cancel_pointer_state() -> void:
	_touch_indices.clear()
	_active_touch_index = -1
	_suppress_touch_until_release = false
	_reaim_pending = false
	_launcher.cancel_aim()


func _pointer_pressed(viewport_position: Vector2) -> void:
	# Dokunma olaylari HUD tarafindan yutulmaz; UI alanlarini elle disla.
	if _result_panel.visible:
		return
	for control in _input_blockers:
		if control.visible and control.get_global_rect().has_point(viewport_position):
			return

	var world_position := _to_world(viewport_position)
	if _ball.is_ready_to_launch():
		_launcher.begin_aim(world_position)
		return
	if not _ball.is_flying():
		return
	if world_position.distance_to(_launcher.global_position) > reaim_touch_radius:
		return

	_launcher.begin_aim(world_position)
	_reaim_pending = _launcher.is_aiming()


func _pointer_moved(viewport_position: Vector2) -> void:
	_launcher.update_aim(_to_world(viewport_position))
	if _reaim_pending and _launcher.has_valid_aim():
		_cancel_active_shot_for_reaim()


func _pointer_released() -> void:
	_reaim_pending = false
	_launcher.release_aim()


func _to_world(viewport_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * viewport_position


# --- HUD ---------------------------------------------------------------------

func _refresh_hint_hud() -> void:
	var available := (
		wallet != null and level_data != null and level_data.has_hint() and not practice_mode)
	_coin_chip.visible = wallet != null and not practice_mode
	_hint_button.visible = available
	if wallet == null:
		return
	# Yalnizca SAYI: "LUMA COIN" kelimesi her karede tekrar etmez, simge
	# zaten neyin sayildigini soyluyor (bkz. GlyphIcon.Glyph.COIN).
	_coin_value.text = str(wallet.balance)
	if not available:
		return
	# Rozet fiyati tasir; acilmis bolumde fiyat yoktur, bu yuzden gizlenir.
	var unlocked := wallet.is_hint_unlocked(level_data.uid())
	_hint_badge.visible = not unlocked
	_hint_badge.text = str(hint_cost)
	_hint_button.disabled = false


func _on_hint_pressed() -> void:
	if wallet == null or level_data == null or not level_data.has_hint() or practice_mode:
		return
	if wallet.is_hint_unlocked(level_data.uid()):
		_show_unlocked_hint()
		return
	# Satin alma kartini acmadan once kayitli aci/gucun bu geometride gercekten
	# hedefe gittigini dogrula. Bozuk/eski ipucu verisi icin Coin kesilmez.
	if _hint_trace.is_empty():
		_hint_trace = _build_hint_trace()
	if _hint_trace.is_empty():
		_show_hint_status(tr("İPUCU HAZIR DEĞİL"))
		return
	if ad_service != null:
		short_hint_enabled = ad_service.is_rewarded_ready(
			MonetizationConfig.PLACEMENT_SHORT_HINT)
	if analytics != null:
		analytics.track_event(AnalyticsService.HINT_OFFER_OPEN, {
			"level_id": level_data.level_id,
			"short_available": short_hint_enabled and not _short_hint_shown,
			"full_unlocked": false,
		})
		if short_hint_enabled and not _short_hint_shown:
			analytics.track_event(AnalyticsService.REWARDED_OFFER, {
				"level_id": level_data.level_id,
				"placement": MonetizationConfig.PLACEMENT_SHORT_HINT,
			})
	_open_hint_card()
	# Kart TEK basina acilir ve iki secenegi birden tasir; hangi secenegin
	# etkin oldugunu kart degil BURASI belirler - urun kurallari (bakiye,
	# ozellik bayragi, bu denemede kisa ipucu kullanildi mi) oyunun bilgisi.
	_hint_card.show_options({
		"full_cost": hint_cost,
		"balance": wallet.balance,
		"can_afford_full": wallet.can_afford(hint_cost),
		"short_cost": short_hint_cost,
		"short_enabled": short_hint_enabled and not _short_hint_shown,
		"short_used": _short_hint_shown,
	})


## KISA IPUCU istendi. Gameplay odulu KENDISI vermez: karari veren AppRoot'tur
## (ileride odullu reklam servisi). Boylece bu dosya hicbir reklam sinifini
## tanimaz - mimari kural.
func _on_short_hint_requested() -> void:
	if not short_hint_enabled or _short_hint_shown:
		return
	_hint_card.close()
	short_hint_requested.emit()


## AppRoot odul kazanildiginda cagirir (reklam izlendi / bayrak acik).
## Kalici DEGILDIR ve Coin harcamaz: yalnizca bu denemede rotanin basi gorunur.
func grant_short_hint() -> void:
	if level_data == null or not level_data.has_hint():
		return
	if _blocks.get_remaining_count() > 0:
		_show_hint_status(tr("ÖNCE BLOKLARI KIR"), 2.8)
		return
	var trace := _build_short_hint_trace()
	if trace.is_empty():
		_show_hint_status(tr("İPUCU HAZIR DEĞİL"))
		return
	_short_hint_shown = true
	if analytics != null:
		analytics.track_event(AnalyticsService.SHORT_HINT_REWARDED_EARNED, {
			"level_id": level_data.level_id,
			"placement": MonetizationConfig.PLACEMENT_SHORT_HINT,
		})
	_hint_path.show_path(trace)
	_show_hint_status(tr("İLK HAMLE"), 2.2)
	_refresh_hint_hud()


func _on_hint_purchase_requested() -> void:
	if wallet == null or level_data == null:
		return
	if not wallet.unlock_hint(level_data.uid(), hint_cost):
		# Savunma amacli: "TAM ROTAYI AC" satiri zaten yalnizca bakiye
		# yetiyorken tiklanabilir. Yine de yarisan bir harcama olursa karti
		# guncel bakiyeyle yeniden cizeriz - Coin kesilmez.
		_hint_card.show_options({
			"full_cost": hint_cost,
			"balance": wallet.balance,
			"can_afford_full": false,
			"short_cost": short_hint_cost,
			"short_enabled": short_hint_enabled and not _short_hint_shown,
			"short_used": _short_hint_shown,
		})
		return
	_refresh_hint_hud()
	_hint_card.close()
	if analytics != null:
		analytics.track_event(AnalyticsService.FULL_HINT_UNLOCK, {
			"level_id": level_data.level_id,
			"cost": hint_cost,
		})
	_show_unlocked_hint()


func _analytics_world_key() -> StringName:
	if level_data == null:
		return &"world_01"
	return StringName("world_%02d" % (LevelWorlds.index_for_level(level_data.level_id) + 1))


## ResultPanel'in SDK'dan bagimsiz completion hook'u. AppRoot policy adayini
## level_completed sinyalinde hesaplar ve kart acilmadan once buraya yazar.
func set_interstitial_candidate(candidate: bool) -> void:
	_result_panel.set_interstitial_candidate(candidate)


func _open_hint_card() -> void:
	if not _hint_card.is_open():
		_launcher_enabled_before_hint = _launcher.enabled
	_launcher.cancel_aim()
	_launcher.enabled = false


func _on_hint_card_dismissed() -> void:
	if not _intro_card.is_open() and not _attempt_finished:
		_launcher.enabled = _launcher_enabled_before_hint


func _show_unlocked_hint() -> void:
	if wallet == null or not wallet.is_hint_unlocked(level_data.uid()):
		return
	if _blocks.get_remaining_count() > 0:
		_hint_waiting_for_blocks = true
		_show_hint_status(tr("ÖNCE BLOKLARI KIR"), 2.8)
		return
	if _hint_trace.is_empty():
		_hint_trace = _build_hint_trace()
	if _hint_trace.is_empty():
		_show_hint_status(tr("İPUCU HAZIR DEĞİL"))
		return
	_hint_waiting_for_blocks = false
	_hint_path.show_path(_hint_trace)
	_full_hint_used_this_attempt = true
	_show_hint_status(tr("ROTAYI TAKİP ET"), 2.2)


func get_retention_snapshot() -> Dictionary:
	return {
		"full_hint_used": _full_hint_used_this_attempt,
	}


func notify_achievement_unlocked(title_key: String, coin_reward: int) -> void:
	if coin_reward > 0:
		_pending_luma_coin_reward += coin_reward
	_show_hint_status(tr("BAŞARI AÇILDI: %s") % tr(title_key), 2.8, coin_reward > 0)


## Offline taramada bulunan tek atisi runtime fizik dunyasinda bir kez oynatir.
## Runtime blok/engel govdeleri sorgudan dislanir: bloklar ipucu sozlesmesine
## gore kirik, hareketli engeller ise LevelSolver'in zaman cizelgesindedir.
func _build_hint_trace() -> PackedVector2Array:
	var empty := PackedVector2Array()
	if level_data == null or not level_data.has_hint():
		return empty
	var solver := LevelSolver.from_scenes()
	var excluded := _blocks.get_body_rids()
	excluded.append_array(_obstacles.get_solver_excluded_rids())
	solver.bind_space(get_world_2d().direct_space_state, {}, level_data.obstacles)
	var direction := Vector2.UP.rotated(deg_to_rad(level_data.hint_angle_degrees))
	var result := solver.simulate(
		_launcher.get_spawn_position(), direction * level_data.hint_power,
		level_data.target_position, _arena.get_play_rect(), excluded, true)
	if not bool(result.get("hit", false)):
		push_warning("Gameplay: %s icin kayitli ipucu hedefe ulasmiyor." % level_data.uid())
		return empty
	return result.get("trace_points", empty) as PackedVector2Array


## KISA IPUCU: tam rotanin yalnizca bas kismi.
##
## Mevcut _build_hint_trace() YENIDEN YAZILMAZ - ayni dogrulanmis rotayi
## uretir, burada sadece KIRPILIR. Boylece kisa ipucu ile tam rota asla
## farkli bir yol gosteremez.
##
## Kesim noktasi: ILK SEKME, ama rotanin short_hint_max_ratio'sunu gecmemek
## ve short_hint_min_ratio'nun altina inmemek kaydiyla. Iki sinir da olculebilir
## bir sebeple var:
##   ust sinir - bazi bolumlerde ilk sekme yolun sonuna yakindir; yalnizca
##               "ilk sekmeye kadar" demek rotanin tamamini vermek olurdu.
##   alt sinir - ilk sekme firlaticinin hemen onundeyse birkac piksellik bir
##               cizgi hicbir yon bilgisi tasimaz.
func _build_short_hint_trace() -> PackedVector2Array:
	var full := _hint_trace
	if full.is_empty():
		full = _build_hint_trace()
	if full.size() < 2:
		return PackedVector2Array()

	# Yay uzunlugu boyunca kumulatif mesafe: kirpma noktalarini SAYIYLA degil
	# UZUNLUKLA secmek gerekiyor, cunku nokta yogunlugu hiza gore degisir.
	var lengths := PackedFloat32Array()
	lengths.resize(full.size())
	lengths[0] = 0.0
	for i in range(1, full.size()):
		lengths[i] = lengths[i - 1] + full[i - 1].distance_to(full[i])
	var total: float = lengths[full.size() - 1]
	if total <= 0.0:
		return PackedVector2Array()

	var min_length := total * short_hint_min_ratio
	var max_length := total * short_hint_max_ratio
	var cut_length := max_length
	var bounce_length := _first_bounce_length(full, lengths)
	if bounce_length > 0.0:
		cut_length = clampf(bounce_length, min_length, max_length)

	var out := PackedVector2Array()
	for i in full.size():
		out.append(full[i])
		if lengths[i] >= cut_length:
			break
	return out if out.size() >= 2 else PackedVector2Array()


## Rotanin ilk KESKIN yon degisimine kadar olan uzunluk; bulunamazsa 0.
##
## Sekme sayaci yerine acidan tespit edilir, cunku _build_hint_trace yalnizca
## noktalari dondurur. Yercekimi altindaki serbest ucus kucuk aci degisimleri
## uretir; gercek bir sekme keskin bir kirilmadir - esik bu ikisini ayirir.
func _first_bounce_length(points: PackedVector2Array, lengths: PackedFloat32Array) -> float:
	const BOUNCE_ANGLE_THRESHOLD := 0.55
	for i in range(1, points.size() - 1):
		var incoming := points[i] - points[i - 1]
		var outgoing := points[i + 1] - points[i]
		if incoming.length() < 0.5 or outgoing.length() < 0.5:
			continue
		if absf(incoming.angle_to(outgoing)) >= BOUNCE_ANGLE_THRESHOLD:
			return lengths[i]
	return 0.0


## AppRoot ilk tamamlama odulunu ayni WalletStore'a yazdiktan sonra cagirir.
func notify_luma_coin_reward(amount: int) -> void:
	if amount <= 0:
		return
	_pending_luma_coin_reward += amount
	_refresh_hint_hud()
	_show_hint_status("+%d" % amount, 2.4, true)


## [param with_coin] true ise metnin yanina jeton simgesi konur.
##
## Neden simge: odul bildirimi "+1 LUMA COIN" yaziyordu ve bolum basliginin
## hemen altinda para biriminin adini tekrarliyordu. Simge hem kisa hem her
## dilde ayni; metin yalnizca sayiyi tasir.
func _show_hint_status(text: String, hold_time := 2.0, with_coin := false) -> void:
	if _hint_status_tween != null and _hint_status_tween.is_valid():
		_hint_status_tween.kill()
	_hint_status_text.text = text
	_hint_status_glyph.visible = with_coin
	_hint_status.modulate.a = 0.0
	_hint_status.show()
	_hint_status_tween = create_tween()
	_hint_status_tween.tween_property(_hint_status, "modulate:a", 1.0, 0.16)
	_hint_status_tween.tween_interval(hold_time)
	_hint_status_tween.tween_property(_hint_status, "modulate:a", 0.0, 0.28)
	_hint_status_tween.tween_callback(_hint_status.hide)


func _hide_hint_status() -> void:
	if _hint_status_tween != null and _hint_status_tween.is_valid():
		_hint_status_tween.kill()
	_hint_status.hide()
	_hint_status.modulate.a = 1.0


func _show_message(text: String) -> void:
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message.text = text
	_message.pivot_offset = _message.size * 0.5
	_message.scale = Vector2(0.72, 0.72)
	_message.modulate.a = 0.0
	_message.show()

	_message_tween = create_tween()
	_message_tween.set_parallel(true)
	_message_tween.tween_property(_message, "scale", Vector2.ONE, message_pop_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_message_tween.tween_property(_message, "modulate:a", 1.0, message_pop_time * 0.7)


## --- Ipucu -------------------------------------------------------------------

func _show_tutorial() -> void:
	if _tutorial_tween != null and _tutorial_tween.is_valid():
		_tutorial_tween.kill()
	_tutorial_dismissed = false
	# Bolum adinda oldugu gibi: anahtar Turkce metnin kendisi (levels.csv).
	_tutorial.text = tr(level_data.tutorial_text) if not level_data.tutorial_text.is_empty() \
		else ""
	_tutorial.modulate.a = 1.0
	_tutorial.visible = not level_data.tutorial_text.is_empty()


## Oyuncu gercekten nisan almaya basladiginda (surukleme min esigi gecince)
## iki sey olur: ipucu yumusakca cekilir ve deneme kronometresi baslar.
## Ayni tetigi paylasmalari kasitli - oyuncu icin "artik oynuyorum" ani budur.
## Ekrana dokunmak degil, gercek bir nisan olusmasi araniyor; boylece
## yanlislikla degen bir parmak sureyi baslatmaz.
func _on_aim_updated(power_ratio: float, direction: Vector2) -> void:
	if _ball.is_ready_to_launch():
		_ball.set_launcher_tension(
			power_ratio, direction, _launcher.loaded_ball_pullback_distance)
	if _launcher.has_valid_aim():
		_hint_path.hide_path()
		_hint_waiting_for_blocks = false
		_hide_hint_status()
		_start_attempt_timer()
		_dismiss_tutorial()


func _on_aim_cancelled() -> void:
	_ball.reset_launcher_tension()


func _on_power_step_crossed(step_index: int, step_count: int) -> void:
	var duration := (
		max_power_step_haptic_msec if step_index >= step_count
		else power_step_haptic_msec)
	Haptics.pulse(duration)


func _dismiss_tutorial() -> void:
	if _tutorial_dismissed or not _tutorial.visible:
		return
	_tutorial_dismissed = true
	if _tutorial_tween != null and _tutorial_tween.is_valid():
		_tutorial_tween.kill()
	_tutorial_tween = create_tween()
	_tutorial_tween.tween_property(_tutorial, "modulate:a", 0.0, tutorial_fade_time)
	_tutorial_tween.tween_callback(_tutorial.hide)


## Yeni bir mekanigi TANITIM KARTI ile gosterir (bkz. MechanicIntroCard).
##
## Kart ipucu etiketinden farkli olarak MODALDIR: kendiliginden solmaz, oyuncu
## "Anladım" diyene kadar durur. Sebep, kartin bir kuralı ogretmesidir - oyuncu
## nisan almaya baslayinca kaybolan bir toast, kurali okumaya firsat vermeden
## kayboluyordu. Kart acikken firlatici kapatilir, boylece arkadan yanlislikla
## atis yapilamaz.
##
## Bir bolum birden fazla yeni sey tanitiyorsa (mevcut kutuphanede olmaz - blok
## bandi 26-40 ile engel bandi 41+ ayrik kumelerdir) sirayla gosterilir: biri
## kapaninca digeri acilir. Blok mekanigi engel kuyrugundan ONCE gelir.
func _show_next_intro_card() -> void:
	if _intro_card.is_open():
		return
	if _pending_block_intro:
		_pending_block_intro = false
		_showing_block_intro = true
		_suspend_launcher_for_intro()
		_intro_card.show_block_mechanic()
		return
	if _pending_obstacle_intro_kinds.is_empty():
		return
	_showing_block_intro = false
	_suspend_launcher_for_intro()
	_intro_card.show_obstacle(_pending_obstacle_intro_kinds[0] as ObstacleData.Kind)


func _suspend_launcher_for_intro() -> void:
	# Ust uste acilan kartlarda ilk kaydedilen deger korunmali; aksi halde
	# ikinci kart "kapali" durumu kaydedip firlaticiyi kalici kapatirdi.
	if not _intro_card.is_open():
		_launcher_enabled_before_intro = _launcher.enabled
	_launcher.enabled = false


## Kart kapandi: gorulen mekanik kalici olarak isaretlenir (AppRoot yazar),
## sonra kuyrukta bekleyen varsa bir sonraki kart acilir.
func _on_intro_card_dismissed() -> void:
	if _showing_block_intro:
		_showing_block_intro = false
		block_mechanic_seen.emit()
	elif not _pending_obstacle_intro_kinds.is_empty():
		obstacle_kind_seen.emit(_pending_obstacle_intro_kinds.pop_front())

	if _pending_block_intro or not _pending_obstacle_intro_kinds.is_empty():
		_show_next_intro_card()
		return
	_launcher.enabled = _launcher_enabled_before_intro


func _hide_message() -> void:
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message.hide()
	_message.scale = Vector2.ONE
	_message.modulate.a = 1.0


# --- Debug -------------------------------------------------------------------
#
# Bu tek metod disinda gameplay.gd, debug panelinin var olup olmadigini
# hic bilmez - panel sadece asagidaki anlik durumu okur.

func get_debug_snapshot() -> Dictionary:
	var stats := {}
	if playtest_stats != null and level_data != null:
		stats = playtest_stats.get_entry_snapshot(level_data.level_id)
	var attempt_seconds := _current_attempt_seconds()
	var projected := 0
	var saved_stars := 0
	var total_stars := 0
	if level_data != null:
		# "Su an bitirsen kac yildiz alirdin" - gercek hesabin aynisi.
		projected = level_data.calculate_stars(attempt_seconds, _shots_this_attempt)
	if progress != null and level_data != null:
		saved_stars = progress.get_level_stars(level_data.level_id)
		total_stars = progress.get_total_stars()

	return {
		"level_id": level_data.level_id if level_data != null else 0,
		"lives_remaining": _lives_remaining,
		"max_lives": _max_lives,
		"ball_speed": _ball.velocity.length(),
		"last_shot_power": _last_shot_power,
		"last_shot_angle_deg": _last_shot_angle_deg,
		"last_failure_reason": _last_failure_reason,
		"blocks_total": _blocks.get_total_count(),
		"blocks_remaining": _blocks.get_remaining_count(),
		"blocks_broken": _blocks.get_broken_count(),
		"attempt_shots": _shots_this_attempt,
		"attempt_seconds": attempt_seconds,
		"attempt_timer_running": _attempt_timer_running,
		"projected_stars": projected,
		"saved_stars": saved_stars,
		"total_stars": total_stars,
		"max_total_stars": progress.get_max_available_stars() if progress != null else 0,
		"luma_coins": wallet.balance if wallet != null else -1,
		"hint_available": level_data.has_hint() if level_data != null else false,
		"hint_unlocked": (
			wallet.is_hint_unlocked(level_data.uid()) if wallet != null and level_data != null
			else false),
		"hint_visible": _hint_path.is_showing(),
		"stats": stats,
	}


# --- Playtest zamanlamasi -----------------------------------------------------

func _start_playtest_timing() -> void:
	var now := Time.get_ticks_msec()
	_level_elapsed_seconds = 0.0
	_attempt_elapsed_seconds = 0.0
	_level_active_start_msec = now
	_attempt_active_start_msec = now
	_timing_pause_reasons.clear()
	_playtest_timing_paused = false


func _reset_attempt_timer() -> void:
	_attempt_elapsed_seconds = 0.0
	_attempt_active_start_msec = Time.get_ticks_msec()
	# Kronometre yeniden KURULUR ama baslatilmaz; oyuncu tekrar nisan alana
	# kadar bekler (bkz. _start_attempt_timer).
	_attempt_timer_running = false
	_final_attempt_seconds = 0.0
	_final_attempt_shots = 0
	_attempt_finished = false
	_attempt_completed = false


## Oyuncu ilk gecerli nisanini yaptigi anda kronometreyi baslatir. Deneme
## boyunca yalnizca bir kez etki eder; sonraki atislarda sure durmaz.
func _start_attempt_timer() -> void:
	if _attempt_timer_running or _attempt_finished:
		return
	_attempt_timer_running = true
	_attempt_active_start_msec = Time.get_ticks_msec()


func _set_playtest_timing_pause(reason: StringName, paused: bool) -> void:
	var was_paused := not _timing_pause_reasons.is_empty()
	if paused:
		_timing_pause_reasons[reason] = true
	else:
		_timing_pause_reasons.erase(reason)
	var is_paused := not _timing_pause_reasons.is_empty()
	if was_paused == is_paused:
		return
	if is_paused:
		_flush_playtest_time()
		_playtest_timing_paused = true
		return
	var now := Time.get_ticks_msec()
	_level_active_start_msec = now
	_attempt_active_start_msec = now
	_playtest_timing_paused = false


func _flush_playtest_time() -> void:
	if _playtest_timing_paused:
		return
	var now := Time.get_ticks_msec()
	# Bolum kronometresi (playtest istatistigi) bolume girildigi andan itibaren
	# isler; deneme kronometresi (yildiz suresi) yalnizca baslatildiysa.
	_level_elapsed_seconds += maxf((now - _level_active_start_msec) / 1000.0, 0.0)
	if _attempt_timer_running:
		_attempt_elapsed_seconds += maxf((now - _attempt_active_start_msec) / 1000.0, 0.0)
	_level_active_start_msec = now
	_attempt_active_start_msec = now


func _current_attempt_seconds() -> float:
	# Bolum bittiyse dondurulmus deger doner; sonuc karti acikken sure islemez.
	if _attempt_finished:
		return _final_attempt_seconds
	# Henuz nisan alinmadi: sure 0'dir, yerlesimi incelemek yildiz yemez.
	if not _attempt_timer_running:
		return _attempt_elapsed_seconds
	var elapsed := _attempt_elapsed_seconds
	if not _playtest_timing_paused:
		elapsed += maxf((Time.get_ticks_msec() - _attempt_active_start_msec) / 1000.0, 0.0)
	return elapsed


## Bolum bittigi anda sure/atis dondurulur. Iki bitis yolu da (hedef ve
## haklarin tukenmesi) buradan gecer, boylece kural tek yerde durur.
func _freeze_attempt() -> void:
	if _attempt_finished:
		return
	_final_attempt_seconds = _current_attempt_seconds()
	_final_attempt_shots = _shots_this_attempt
	_attempt_finished = true
