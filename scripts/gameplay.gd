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

signal level_completed(level_id: int)
signal next_level_requested(level_id: int)
signal level_select_requested()
signal menu_requested()

@export var completed_title := "BÖLÜM TAMAMLANDI"
@export var next_level_label := "SONRAKİ BÖLÜM"
@export var level_select_label := "BÖLÜM SEÇİMİ"
@export var retry_label := "TEKRAR DENE"
@export var menu_label := "ANA MENÜ"
@export var out_of_balls_message := "TOP HAKKI BİTTİ"
## Kazanma efekti gorulsun diye sonuc karti kisa bir gecikmeyle acilir.
@export var result_delay := 0.75
## Basarisiz atistan sonra, hala hakki varsa otomatik sifirlama gecikmesi.
@export var auto_reset_delay := 0.35
@export var message_pop_time := 0.35
@export var retry_pulse_time := 0.4

@export_group("Bolum")
## Panellerin uretildigi sahne (bounce_panel.tscn).
@export var panel_scene: PackedScene
## Veri atanmamissa (or. sahne dogrudan calistirilirsa) kullanilacak bolum.
@export var fallback_level_id := 1

@export_group("Carpma Efekti")
## Kivilcim siddetinin doygunluga ulastigi hiz.
@export var spark_reference_speed := 1600.0
@export var spark_count := 5
@export var spark_length := 24.0

@export_group("Ekran Titresimi")
## Panele carpma titresiminin carpani (gercek deger carpma hizina gore olceklenir).
@export_range(0.0, 1.0, 0.01) var bounce_shake_trauma := 0.4
@export_range(0.0, 1.0, 0.01) var target_hit_shake_trauma := 0.75
## Hedefe vurulunca (destekleyen cihazlarda) kisa bir titresim; Android/iOS
## disinda ve destegi olmayan cihazlarda Godot bunu sessizce yok sayar.
@export var target_hit_haptic_msec := 80

## AppRoot tarafindan add_child'dan ONCE atanir.
var level_data: LevelData
## AppRoot tarafindan add_child'dan ONCE atanir; debug build disinda tum
## kayit cagrilari sessizce hicbir sey yapmaz (bkz. PlaytestStats).
var playtest_stats: PlaytestStats

@onready var _arena: Arena = $Arena
@onready var _panels: Node2D = $Panels
@onready var _launcher: Launcher = $Launcher
@onready var _ball: Ball = $Ball
@onready var _target: Target = $Target
@onready var _effects: Node2D = $Effects
@onready var _shake: ScreenShake = $ShakeCamera
@onready var _message: Label = $HUD/SafeArea/Root/Message
@onready var _tutorial: Label = $HUD/SafeArea/Root/TutorialLabel
@onready var _retry_button: Button = $HUD/SafeArea/Root/RetryButton
@onready var _home_button: Button = $HUD/SafeArea/Root/HomeButton
@onready var _lives_display: LivesDisplay = $HUD/SafeArea/Root/LivesDisplay
@onready var _result_panel: ResultPanel = $HUD/ResultPanel

var _message_tween: Tween
var _retry_pulse_tween: Tween
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
var _level_active_start_msec := 0
var _level_elapsed_seconds := 0.0
var _playtest_timing_paused := false
var _last_shot_power := 0.0
var _last_shot_angle_deg := 0.0
var _last_failure_reason := "-"
var _active_touch_index := -1
var _touch_indices: Array[int] = []
var _suppress_touch_until_release := false


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
	_max_lives = maxi(level_data.max_lives, 1)

	_build_panels()
	_apply_tutorial()


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


func _apply_tutorial() -> void:
	_tutorial.text = level_data.tutorial_text
	_tutorial.visible = not level_data.tutorial_text.is_empty()


func _sync_tuning() -> void:
	# Nisan kilavuzu topun gercek yer cekimi/sekme/yaricap/hiz davranisiyla
	# ayni sonucu vermeli, yoksa onizleme ile gercek carpisma ayrisir.
	_launcher.preview_gravity = _ball.gravity
	_launcher.preview_bounciness = _ball.bounciness
	_launcher.preview_ball_radius = _ball.radius
	_launcher.preview_max_speed = _ball.max_speed
	_ball.play_bounds = _arena.get_play_rect()


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
	_ball.bounced.connect(_on_ball_bounced)
	_ball.shot_failed.connect(_on_shot_failed)
	_target.hit.connect(_on_target_hit)
	_retry_button.pressed.connect(reset_shot)
	_home_button.pressed.connect(menu_requested.emit)
	_result_panel.next_pressed.connect(_on_result_next)
	_result_panel.retry_pressed.connect(_on_result_retry)
	_result_panel.menu_pressed.connect(menu_requested.emit)


# --- Oyun dongusu ------------------------------------------------------------

## Bolumu bastan baslatir: haklar dolar, top ve hedef sifirlanir.
func reset_shot() -> void:
	if _has_started and playtest_stats != null:
		playtest_stats.record_restart(level_data.level_id)
	_has_started = true
	_shots_this_attempt = 0
	_reset_attempt_timer()

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


## Sadece topu ve hedefi baslangic durumuna dondurur; top hakkina dokunmaz.
func _respawn_ball() -> void:
	_shot_token += 1
	_stop_retry_pulse()
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

	_shots_this_attempt += 1
	_last_shot_power = impulse.length()
	_last_shot_angle_deg = rad_to_deg(Vector2.UP.angle_to(impulse.normalized()))
	if playtest_stats != null:
		playtest_stats.record_shot(level_data.level_id)

	_ball.launch(impulse)


func _on_shot_failed(reason: String) -> void:
	_last_failure_reason = reason
	if playtest_stats != null:
		playtest_stats.record_failure(level_data.level_id, reason)

	_launcher.enabled = false
	_lives_remaining = maxi(_lives_remaining - 1, 0)
	_update_lives_hud()
	if _lives_remaining <= 0:
		_show_message(out_of_balls_message)
		_pulse_retry_button()
		return

	# Bekleme sirasinda oyuncu manuel "Yeniden Dene"ye basarsa _respawn_ball()
	# token'i ilerletir; sure doldugunda token degismisse bu zamanlayici
	# artik gecersizdir ve yeni (manuel baslatilmis) atisi ezmeden iptal olur.
	var token := _shot_token
	await get_tree().create_timer(auto_reset_delay, false).timeout
	if token != _shot_token:
		return
	_respawn_ball()


func _update_lives_hud() -> void:
	_lives_display.set_lives(_lives_remaining, _max_lives)


func _on_target_hit(_body: Node2D) -> void:
	_ball.stop()
	_launcher.enabled = false
	# Kazanma anini ikincil vurgu (menekse) ile isaretle.
	SparkBurst.burst(
		_effects, _target.global_position, Vector2.UP, 1.0,
		Palette.ACCENT_ALT, Palette.ACCENT_ALT_CORE, 12, 74.0, 350.0)
	_shake.add_trauma(target_hit_shake_trauma)
	Input.vibrate_handheld(target_hit_haptic_msec)

	if playtest_stats != null:
		var elapsed := _current_attempt_seconds()
		playtest_stats.record_completion(level_data.level_id, _shots_this_attempt, elapsed)

	level_completed.emit(level_data.level_id)
	_open_result_panel()


func _open_result_panel() -> void:
	var token := _shot_token
	await get_tree().create_timer(result_delay, false).timeout
	# Bu arada yeniden baslatildiysa karti acma.
	if token != _shot_token or not is_inside_tree():
		return
	var next_text := next_level_label if LevelLibrary.has_next(level_data.level_id) else level_select_label
	_result_panel.show_result(completed_title, next_text)


func _on_result_next() -> void:
	if LevelLibrary.has_next(level_data.level_id):
		next_level_requested.emit(level_data.level_id + 1)
	else:
		level_select_requested.emit()


func _on_result_retry() -> void:
	_result_panel.hide_result()
	reset_shot()


# --- Carpma geri bildirimi ---------------------------------------------------

func _on_ball_bounced(at: Vector2, normal: Vector2, impact_speed: float) -> void:
	var strength := clampf(impact_speed / spark_reference_speed, 0.3, 1.0)
	SparkBurst.burst(
		_effects, at, normal, strength,
		Palette.ACCENT, Palette.ACCENT_CORE, spark_count, spark_length)
	_shake.add_trauma(strength * bounce_shake_trauma)


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
	_launcher.cancel_aim()


func _pointer_pressed(viewport_position: Vector2) -> void:
	# Dokunma olaylari HUD tarafindan yutulmaz; UI alanlarini elle disla.
	if _result_panel.visible:
		return
	for control in _input_blockers:
		if control.visible and control.get_global_rect().has_point(viewport_position):
			return
	if not _ball.is_ready_to_launch():
		return
	_launcher.begin_aim(_to_world(viewport_position))


func _pointer_moved(viewport_position: Vector2) -> void:
	_launcher.update_aim(_to_world(viewport_position))


func _pointer_released() -> void:
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


func _hide_message() -> void:
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message.hide()
	_message.scale = Vector2.ONE
	_message.modulate.a = 1.0


## Dikkat cekmek icin butonu bir kez buyutup geri getirir. Renk degismez -
## tek vurgu kuralina (neon sadece top/hedef/nisan cizgisinde) dokunulmaz.
func _pulse_retry_button() -> void:
	_stop_retry_pulse()
	_retry_button.pivot_offset = _retry_button.size * 0.5
	_retry_pulse_tween = create_tween()
	_retry_pulse_tween.tween_property(_retry_button, "scale", Vector2.ONE * 1.22, retry_pulse_time * 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_retry_pulse_tween.tween_property(_retry_button, "scale", Vector2.ONE, retry_pulse_time * 0.65) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _stop_retry_pulse() -> void:
	if _retry_pulse_tween != null and _retry_pulse_tween.is_valid():
		_retry_pulse_tween.kill()
	_retry_button.scale = Vector2.ONE


# --- Debug -------------------------------------------------------------------
#
# Bu tek metod disinda gameplay.gd, debug panelinin var olup olmadigini
# hic bilmez - panel sadece asagidaki anlik durumu okur.

func get_debug_snapshot() -> Dictionary:
	var stats := {}
	if playtest_stats != null and level_data != null:
		stats = playtest_stats.get_entry_snapshot(level_data.level_id)
	return {
		"level_id": level_data.level_id if level_data != null else 0,
		"lives_remaining": _lives_remaining,
		"max_lives": _max_lives,
		"ball_speed": _ball.velocity.length(),
		"last_shot_power": _last_shot_power,
		"last_shot_angle_deg": _last_shot_angle_deg,
		"last_failure_reason": _last_failure_reason,
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
	_level_elapsed_seconds += maxf((now - _level_active_start_msec) / 1000.0, 0.0)
	_attempt_elapsed_seconds += maxf((now - _attempt_active_start_msec) / 1000.0, 0.0)
	_level_active_start_msec = now
	_attempt_active_start_msec = now


func _current_attempt_seconds() -> float:
	var elapsed := _attempt_elapsed_seconds
	if not _playtest_timing_paused:
		elapsed += maxf((Time.get_ticks_msec() - _attempt_active_start_msec) / 1000.0, 0.0)
	return elapsed
