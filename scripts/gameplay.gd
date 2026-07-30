extends Node2D

## Prototip oyun dongusunun orkestratoru.
##
## Sorumlulugu: girdiyi firlaticiya iletmek, sinyalleri baglamak, carpma/kazanma
## efektlerini tetiklemek ve "nisan al -> firlat -> sektir -> hedefi vur ->
## yeniden dene" dongusunu surdurmek.
## Fizik ball.gd'de, nisan hesabi launcher.gd'de, hedef efektleri target.gd'de.

@export var success_message := "HEDEF VURULDU!"
## Hak bittiginde gosterilen sade mesaj (ayni Label/animasyon, farkli metin).
@export var out_of_balls_message := "TOP HAKKI BİTTİ"
## Basarisiz atistan sonra, hala hakki varsa otomatik sifirlama gecikmesi.
@export var auto_reset_delay := 0.35
@export var message_pop_time := 0.35
@export var retry_pulse_time := 0.4

@export_group("Top Hakki")
## Bolume ait sinirli top hakki. Hak biterse otomatik sifirlama durur;
## oyuncu "Yeniden Dene" ile bolumu tam olarak (haklar dahil) yeniden baslatir.
@export var max_lives := 5

@export_group("Carpma Efekti")
## Kivilcim siddetinin doygunluga ulastigi hiz.
@export var spark_reference_speed := 1600.0
@export var spark_count := 5
@export var spark_length := 24.0

@onready var _arena: Arena = $Arena
@onready var _launcher: Launcher = $Launcher
@onready var _ball: Ball = $Ball
@onready var _target: Target = $Target
@onready var _effects: Node2D = $Effects
@onready var _message: Label = $HUD/Root/Message
@onready var _retry_button: Button = $HUD/Root/RetryButton
@onready var _lives_display: LivesDisplay = $HUD/Root/LivesDisplay

var _message_tween: Tween
var _retry_pulse_tween: Tween
var _lives_remaining := 0
## Her "gecerli atis denemesi" basladiginda artar (bkz. _respawn_ball).
## Gecikmeli otomatik-sifirlama zamanlayicisi, calistigi anda bu deger
## degismisse (araya manuel "Yeniden Dene" girmisse) kendini iptal eder.
var _shot_token := 0


func _ready() -> void:
	_sync_tuning()
	_connect_signals()
	reset_shot()


func _sync_tuning() -> void:
	# Nisan kilavuzu topun gercek yer cekimi/sekme/yaricap/hiz davranisiyla
	# ayni sonucu vermeli, yoksa onizleme ile gercek carpisma ayrisir.
	_launcher.preview_gravity = _ball.gravity
	_launcher.preview_bounciness = _ball.bounciness
	_launcher.preview_ball_radius = _ball.radius
	_launcher.preview_max_speed = _ball.max_speed
	_ball.play_bounds = _arena.get_play_rect()


func _connect_signals() -> void:
	_launcher.shot_fired.connect(_on_shot_fired)
	_ball.bounced.connect(_on_ball_bounced)
	_ball.shot_failed.connect(_on_shot_failed)
	_target.hit.connect(_on_target_hit)
	_retry_button.pressed.connect(reset_shot)


# --- Oyun dongusu ------------------------------------------------------------

## Bolumu tam olarak yeniden baslatir: haklar dolar, top ve hedef sifirlanir.
## Bekleyen bir otomatik-sifirlama zamanlayicisi varsa _respawn_ball() token'i
## ilerleterek onu gecersiz kilar (bkz. _on_shot_failed).
func reset_shot() -> void:
	_lives_remaining = max_lives
	_update_lives_hud()
	_respawn_ball()


## Sadece topu ve hedefi baslangic durumuna dondurur; top hakkina dokunmaz.
## Basarisiz bir atistan sonra, hak varsa bu cagrilir.
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
	_ball.launch(impulse)


func _on_shot_failed(_reason: String) -> void:
	_launcher.enabled = false
	_lives_remaining = maxi(_lives_remaining - 1, 0)
	_update_lives_hud()
	if _lives_remaining <= 0:
		_show_out_of_balls()
		return

	# Bekleme sirasinda oyuncu manuel "Yeniden Dene"ye basarsa _respawn_ball()
	# token'i ilerletir; sure doldugunda token degismisse bu zamanlayici
	# artik geçersizdir ve yeni (manuel baslatilmis) atisi ezmeden iptal olur.
	var token := _shot_token
	await get_tree().create_timer(auto_reset_delay).timeout
	if token != _shot_token:
		return
	_respawn_ball()


func _update_lives_hud() -> void:
	_lives_display.set_lives(_lives_remaining, max_lives)


func _on_target_hit(_body: Node2D) -> void:
	_ball.stop()
	_launcher.enabled = false
	_show_message(success_message)
	# Kazanma anini ikincil vurgu (menekse) ile isaretle.
	SparkBurst.burst(
		_effects, _target.global_position, Vector2.UP, 1.0,
		Palette.ACCENT_ALT, Palette.ACCENT_ALT_CORE, 12, 74.0, 350.0)


## Son top hakki da bitince: sade bir mesaj + "Yeniden Dene" butonuna kisa
## bir vurgu animasyonu. Baska renk/gorsel eklenmez, mevcut sistem yeniden kullanilir.
func _show_out_of_balls() -> void:
	_show_message(out_of_balls_message)
	_pulse_retry_button()


# --- Carpma geri bildirimi ---------------------------------------------------

func _on_ball_bounced(at: Vector2, normal: Vector2, impact_speed: float) -> void:
	var strength := clampf(impact_speed / spark_reference_speed, 0.3, 1.0)
	SparkBurst.burst(
		_effects, at, normal, strength,
		Palette.ACCENT, Palette.ACCENT_CORE, spark_count, spark_length)


func _clear_effects() -> void:
	for child in _effects.get_children():
		child.queue_free()


# --- Girdi -------------------------------------------------------------------
#
# Hem fare hem dokunma desteklenir. Godot dokunmadan fare olayi da uretebildigi
# icin ayni hareket iki kez gelebilir; launcher tarafi idempotent oldugundan
# bu durum ikinci bir atis yaratmaz.

func _unhandled_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_pointer_pressed(touch.position)
		else:
			_pointer_released()
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


func _pointer_pressed(viewport_position: Vector2) -> void:
	# Dokunma olaylari HUD tarafindan yutulmaz; butonun uzerini elle disla.
	if _retry_button.visible and _retry_button.get_global_rect().has_point(viewport_position):
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
