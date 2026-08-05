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

signal level_completed(level_id: int, stars: int)
signal next_level_requested(level_id: int)
signal level_select_requested()
signal menu_requested()

@export var completed_title := "BÖLÜM TAMAMLANDI"
@export var failed_title := "BÖLÜM BAŞARISIZ"
@export var failed_subtitle := "HEDEFİ VURAMADIN"
@export var next_level_label := "SONRAKİ BÖLÜM"
@export var level_select_label := "BÖLÜM SEÇİMİ"
@export var retry_label := "TEKRAR OYNA"
@export var restart_label := "TEKRAR BAŞLA"
@export var menu_label := "ANA MENÜ"
@export var out_of_balls_message := "TOP HAKKI BİTTİ"
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
## Veri atanmamissa (or. sahne dogrudan calistirilirsa) kullanilacak bolum.
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
## Hedefe vurulunca (destekleyen cihazlarda) kisa bir titresim; Android/iOS
## disinda ve destegi olmayan cihazlarda Godot bunu sessizce yok sayar.
@export var target_hit_haptic_msec := 80
## Guc bari yeni bir kademeye ilk kez ciktiginda verilen hafif dokunsal tik.
@export var power_step_haptic_msec := 10
@export var max_power_step_haptic_msec := 20
## Iki canli tuglanin ilk catlamasinda verilen kisa dokunsal onay.
@export var block_damage_haptic_msec := 12
## Bombaya temas, hedef kadar agir olmayan kisa bir tehlike vurgusudur.
@export_range(0.0, 1.0, 0.01) var hazard_shake_trauma := 0.34
@export var hazard_haptic_msec := 34

## AppRoot tarafindan add_child'dan ONCE atanir.
var level_data: LevelData
## AppRoot tarafindan add_child'dan ONCE atanir; debug build disinda tum
## kayit cagrilari sessizce hicbir sey yapmaz (bkz. PlaytestStats).
var playtest_stats: PlaytestStats
## AppRoot tarafindan add_child'dan ONCE atanir. Buradan YALNIZCA onceki
## yildiz OKUNUR (yeni rekor tespiti icin); yazma islemi AppRoot'a aittir.
var progress: ProgressStore
## TEST MODU - bolum editorunden "TEST" ile acildiginda AppRoot tarafindan
## acilir. Bolum BITMEZ: hedefe isabet geri bildirimi oynar ama sonuc karti
## acilmaz, haklar tukenmez, ilerleme yazilmaz. Amac bolumu degerlendirmek
## degil, geometriyi istedigin kadar denemek.
var practice_mode := false

@onready var _arena: Arena = $Arena
@onready var _panels: Node2D = $Panels
@onready var _blocks: BreakableField = $Blocks
@onready var _obstacles: ObstacleField = $Obstacles
@onready var _launcher: Launcher = $Launcher
@onready var _ball: Ball = $Ball
@onready var _target: Target = $Target
@onready var _effects: Node2D = $Effects
@onready var _shake: ScreenShake = $ShakeCamera
@onready var _message: Label = $HUD/SafeArea/Root/Message
@onready var _tutorial: Label = $HUD/SafeArea/Root/TutorialLabel
@onready var _level_title: Label = $HUD/SafeArea/Root/LevelHeader/LevelTitle
@onready var _level_subtitle: Label = $HUD/SafeArea/Root/LevelHeader/LevelSubtitle
@onready var _retry_button: Button = $HUD/SafeArea/Root/RetryButton
@onready var _home_button: Button = $HUD/SafeArea/Root/HomeButton
@onready var _lives_display: LivesDisplay = $HUD/SafeArea/Root/LivesDisplay
@onready var _result_panel: ResultPanel = $HUD/ResultPanel

var _message_tween: Tween
var _tutorial_tween: Tween
## Ipucu bu denemede zaten solduysa tekrar tetiklenmesin.
var _tutorial_dismissed := false
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
	_input_blockers.append(_retry_button)
	_input_blockers.append(_home_button)
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
	if level_data.level_id > 50:
		var theme_scale := 0.8
		if "target_scale" in level_data:
			_target.scale = Vector2.ONE * float(level_data.get("target_scale"))
		else:
			_target.scale = Vector2.ONE * theme_scale
			
		if "ball_scale" in level_data:
			_ball.set_radius(24.0 * float(level_data.get("ball_scale")))
		else:
			_ball.set_radius(24.0 * theme_scale)
			
		var new_accent = Color("ff633a") # Orange/Red
		var new_core = Color("ffebd6")
		
		_launcher.accent = new_accent
		_launcher.accent_core = new_core
		_launcher._build_base()
		_launcher._build_barrel()
		_launcher._build_power_meter()
		_launcher._build_drag_hint()
		
		_target.accent = new_accent
		_target.core_color = new_core
		_target._build_visual()
	else:
		if "target_scale" in level_data:
			_target.scale = Vector2.ONE * float(level_data.get("target_scale"))
		else:
			_target.scale = Vector2.ONE
			
		if "ball_scale" in level_data:
			_ball.set_radius(24.0 * float(level_data.get("ball_scale")))
		else:
			_ball.set_radius(24.0)
			
		_launcher.accent = Palette.ACCENT
		_launcher.accent_core = Palette.ACCENT_CORE
		_launcher._build_base()
		_launcher._build_barrel()
		_launcher._build_power_meter()
		_launcher._build_drag_hint()
		
		_target.accent = Palette.ACCENT
		_target.core_color = Palette.ACCENT_CORE
		_target._build_visual()

	_max_lives = maxi(level_data.max_lives, 1)

	_build_panels()
	_obstacles.build(level_data.obstacles)
	_obstacles.start_motion()
	_apply_level_header()


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


## Uzun ekranlarda ust tarafta olusan bosluga bolum kimligi. Metin gercek
## LevelData'dan gelir; home ve restart butonlarinin arasinda, safe area icinde.
func _apply_level_header() -> void:
	_level_title.text = level_title_format % level_data.level_id
	# Test modu basligi: bolum neden bitmiyor sorusunun yaniti gorunur olsun,
	# yoksa "hedefi vurdum ama bir sey olmadi" bir hata gibi okunur.
	var subtitle := level_data.display_name
	if practice_mode:
		subtitle = "%s · TEST (bölüm bitmez)" % subtitle if not subtitle.is_empty() \
			else "TEST (bölüm bitmez)"
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
	_retry_button.pressed.connect(reset_shot)
	_home_button.pressed.connect(menu_requested.emit)
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
	if _has_started:
		AudioManager.play_restart()
		if playtest_stats != null:
			playtest_stats.record_restart(level_data.level_id)
	_has_started = true
	_shots_this_attempt = 0
	_reset_attempt_timer()
	# Ipucu yalnizca bolum bastan baslarken geri gelir; basarisiz atistan
	# sonraki otomatik top respawn'inda gelmez.
	_show_tutorial()

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
func set_app_paused(paused: bool) -> void:
	_set_playtest_timing_paused(paused)
	if paused:
		_cancel_pointer_state()


## ATIS SIFIRLAMA. Sadece topu ve hedefi baslangic durumuna dondurur; top
## hakkina ve KIRILMIS BLOKLARA dokunmaz - kirilan blok bolum cozumunun
## ilerlemesidir, yeni top eskisinin actigi yoldan devam eder.
func _respawn_ball() -> void:
	_shot_token += 1
	_reaim_pending = false
	_launcher.cancel_aim()
	_ball.reset_to(_launcher.get_spawn_position())
	_target.reset()
	_clear_effects()
	_hide_message()
	_launcher.enabled = true


func _on_shot_fired(impulse: Vector2) -> void:
	# Ayni anda yalnizca bir top aktif olabilir.
	if not _ball.is_ready_to_launch():
		return
	_reaim_pending = false

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
	Input.vibrate_handheld(target_hit_haptic_msec)
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

	if playtest_stats != null:
		playtest_stats.record_completion(
			level_data.level_id, _final_attempt_shots, _final_attempt_seconds)

	var stars := level_data.calculate_stars(_final_attempt_seconds, _final_attempt_shots)
	# Kaydi AppRoot yazar; "yeni rekor" karari YAZMADAN ONCE alinmali.
	var previous_stars := progress.get_level_stars(level_data.level_id) if progress != null else 0
	var new_record := stars > previous_stars

	level_completed.emit(level_data.level_id, stars)
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
	var next_text := next_level_label if _can_advance_to_next() else level_select_label
	_result_panel.show_success(
		completed_title, next_text, retry_label,
		stars, _final_attempt_seconds, _final_attempt_shots, new_record)
	# target_hit'ten result_delay kadar sonra geldigi icin ust uste binmez.
	AudioManager.play_level_complete()


## Son top da kaybedildi. Yildiz GOSTERILMEZ - bolum tamamlanmadi.
func _open_failure_panel() -> void:
	_freeze_attempt()

	var token := _shot_token
	await get_tree().create_timer(result_delay, false).timeout
	if token != _shot_token or not is_inside_tree():
		return
	_result_panel.show_failure(
		failed_title, failed_subtitle, restart_label,
		_final_attempt_seconds, _final_attempt_shots)


func _on_result_next() -> void:
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
	var next_id := level_data.level_id + 1
	if not LevelLibrary.has_next(level_data.level_id):
		return false
	return progress == null or progress.is_unlocked(next_id)


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
		if power_step_haptic_msec > 0:
			Input.vibrate_handheld(power_step_haptic_msec)
		AudioManager.play_target_hit()
		return
		
	if reason == "bomb":
		SparkBurst.burst(
			_effects, at, Vector2.UP, 2.0,
			Palette.HAZARD, Palette.HAZARD_CORE, 30, 150.0, 600.0)
		_shake.add_trauma(0.8)
		if hazard_haptic_msec > 0:
			Input.vibrate_handheld(hazard_haptic_msec * 2)
		_ball.fail_shot(reason)
		return
		
	SparkBurst.burst(
		_effects, at, Vector2.UP, 0.72,
		Palette.HAZARD, Palette.HAZARD_CORE, 7, 34.0, 230.0)
	_shake.add_trauma(hazard_shake_trauma)
	if hazard_haptic_msec > 0:
		Input.vibrate_handheld(hazard_haptic_msec)
	_ball.fail_shot(reason)


func _on_block_damaged(_at: Vector2, _remaining_hits: int, _maximum_hits: int) -> void:
	if block_damage_haptic_msec > 0:
		Input.vibrate_handheld(block_damage_haptic_msec)


## Gorsel parcalar blogun KENDI icinde cizilir (bkz. BreakableBlock._draw) ve
## temas noktasindaki kivilcimi zaten sekme uretir. Buraya ayri bir partikul
## daha eklemek ayni ani uc kez anlatmak olurdu; burada sadece ses ve kucuk
## bir titresim vardir.
func _on_block_broken(_at: Vector2) -> void:
	# Sekme sesi bu cagriyla bastirilir (bkz. AudioManager.play_block_break),
	# ama sekmenin kivilcimi ve titresimi aynen kalir.
	AudioManager.play_block_break()
	_shake.add_trauma(block_break_shake_trauma)


func _on_ball_bounced(at: Vector2, normal: Vector2, impact_speed: float) -> void:
	var strength := clampf(impact_speed / spark_reference_speed, 0.3, 1.0)
	SparkBurst.burst(
		_effects, at, normal, strength,
		Palette.ACCENT, Palette.ACCENT_CORE, spark_count, spark_length)
	_shake.add_trauma(strength * bounce_shake_trauma)
	# Ham impact_speed verilir; katman secimi ve cooldown AudioManager'da.
	AudioManager.play_bounce(impact_speed)


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
	_tutorial.text = level_data.tutorial_text
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
		_start_attempt_timer()
		_dismiss_tutorial()


func _on_aim_cancelled() -> void:
	_ball.reset_launcher_tension()


func _on_power_step_crossed(step_index: int, step_count: int) -> void:
	var duration := (
		max_power_step_haptic_msec if step_index >= step_count
		else power_step_haptic_msec)
	if duration > 0:
		Input.vibrate_handheld(duration)


func _dismiss_tutorial() -> void:
	if _tutorial_dismissed or not _tutorial.visible:
		return
	_tutorial_dismissed = true
	if _tutorial_tween != null and _tutorial_tween.is_valid():
		_tutorial_tween.kill()
	_tutorial_tween = create_tween()
	_tutorial_tween.tween_property(_tutorial, "modulate:a", 0.0, tutorial_fade_time)
	_tutorial_tween.tween_callback(_tutorial.hide)


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
		"stats": stats,
	}


# --- Playtest zamanlamasi -----------------------------------------------------

func _start_playtest_timing() -> void:
	var now := Time.get_ticks_msec()
	_level_elapsed_seconds = 0.0
	_attempt_elapsed_seconds = 0.0
	_level_active_start_msec = now
	_attempt_active_start_msec = now
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


## Oyuncu ilk gecerli nisanini yaptigi anda kronometreyi baslatir. Deneme
## boyunca yalnizca bir kez etki eder; sonraki atislarda sure durmaz.
func _start_attempt_timer() -> void:
	if _attempt_timer_running or _attempt_finished:
		return
	_attempt_timer_running = true
	_attempt_active_start_msec = Time.get_ticks_msec()


func _set_playtest_timing_paused(paused: bool) -> void:
	if paused == _playtest_timing_paused:
		return
	if paused:
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
