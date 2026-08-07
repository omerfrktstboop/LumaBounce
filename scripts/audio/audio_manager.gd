extends Node

## Merkezi ses yoneticisi (Autoload: AudioManager).
##
## NOT: bu script bilerek `class_name` TASIMAZ - autoload adiyla ayni global
## isim iki kez tanimlanamaz. Her yerden dogrudan `AudioManager.play_*()`
## seklinde cagrilir.
##
## Sahneler kendi AudioStreamPlayer'larini olusturmaz; burada iki havuz vardir:
##   - SFX havuzu (8 player, "SFX" bus)  -> sik sekmeler icin
##   - UI  havuzu (3 player, "UI"  bus)  -> kisa arayuz tiklamalari icin
## Havuzdaki tum player'lar mesgulse en eskisi geri donusturulur (round-robin),
## boylece ses hicbir zaman "yutulmaz" ama sinirsiz da cogalmaz.
##
## Eksik ses dosyasi oyunu ASLA cokertmez: yukleme sirasinda uyarilir, ilgili
## calma cagrisi sessizce hicbir sey yapmaz.

signal mute_changed(muted: bool)

const MASTER_BUS := "Master"
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const UI_BUS := "UI"

const SFX_POOL_SIZE := 8
const UI_POOL_SIZE := 3

## Ardisik mikro carpismalarda ses yigilmasini onler.
const BOUNCE_COOLDOWN_MSEC := 35

## Pitch cesitliligi bilerek cok kucuk tutulur: mekanik tekrar hissini kirar,
## sesin kimligini degistirmez. Oynanis fizigine hicbir etkisi yoktur (bkz. _rng).
const PITCH_VARIATION := 0.04

## Sekme siddeti esikleri (px/s). ball.gd'nin impact_speed degeriyle karsilastirilir.
const BOUNCE_MEDIUM_MIN_SPEED := 700.0
const BOUNCE_HARD_MIN_SPEED := 1500.0
## Ses/pitch rampasinin taban ve doygunluk hizlari.
const BOUNCE_QUIET_SPEED := 250.0
const BOUNCE_LOUD_SPEED := 2000.0

const SFX_DIR := "res://assets/audio/sfx/"
const SOUND_FILES := {
	"ui_click": "ui_click.wav",
	"launch": "launch.wav",
	"bounce_soft": "bounce_soft.wav",
	"bounce_medium": "bounce_medium.wav",
	"bounce_hard": "bounce_hard.wav",
	"block_break": "block_break.wav",
	"target_hit": "target_hit.wav",
	"level_complete": "level_complete.wav",
	"failure": "failure.wav",
	"restart": "restart.wav",
	"splash_bounce": "splash_bounce.wav",
	"logo_reveal": "logo_reveal.wav",
}

var _streams: Dictionary = {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _ui_pool: Array[AudioStreamPlayer] = []
var _sfx_cursor := 0
var _ui_cursor := 0
var _settings: AudioSettingsStore
var _last_bounce_msec := -BOUNCE_COOLDOWN_MSEC
var _last_played := "-"
## Ses icin AYRI bir RNG: global rastgele diziyi hic tuketmez, boylece
## deterministik top hareketi ve kivilcim yerlesimi etkilenmez.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Uygulama arka plana alininca sahne agaci duraklatilir; ses sistemi
	# bu durumda da bildirim alip sesleri durdurabilmeli.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()

	_ensure_buses()
	_ensure_master_limiter()
	# Mute, HERHANGI bir ses calmadan once uygulanmali (splash dahil).
	_settings = AudioSettingsStore.load_from_disk()
	_apply_mute()
	_apply_volumes()

	_build_pools()
	_load_streams()


## Uygulama arka plana alindiginda kisa SFX'leri kes. Geri gelindiginde
## hicbir sey yeniden baslatilmaz; fizik ve oyun zamanlamasina dokunulmaz.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		stop_transient_sounds()


# --- Oynanis sesleri ----------------------------------------------------------

func play_launch(power_ratio: float) -> void:
	# Dusuk ve maksimum guc arasindaki fark bilerek kucuk: 4.5 dB ve %8 pitch.
	var t := clampf(power_ratio, 0.0, 1.0)
	_play_sfx("launch", lerpf(-6.0, -1.5, t), lerpf(0.98, 1.06, t))


func play_bounce(impact_speed: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_bounce_msec < BOUNCE_COOLDOWN_MSEC:
		return
	_last_bounce_msec = now

	var key := "bounce_soft"
	if impact_speed >= BOUNCE_HARD_MIN_SPEED:
		key = "bounce_hard"
	elif impact_speed >= BOUNCE_MEDIUM_MIN_SPEED:
		key = "bounce_medium"

	var t := clampf(
		inverse_lerp(BOUNCE_QUIET_SPEED, BOUNCE_LOUD_SPEED, impact_speed), 0.0, 1.0)
	_play_sfx(key, lerpf(-10.0, 0.0, t), lerpf(0.97, 1.05, t))


## Kirilabilir blok kirildi. Ayni temasta top zaten sekiyor, yani hemen
## ardindan play_bounce() de cagrilacak; iki ses ust uste yigilip cirkin bir
## tepe yapmasin diye burada SEKME COOLDOWN'U damgalanir. Boylece o temasin
## sekme sesi mevcut mekanizma tarafindan yutulur ve kirilma one cikar -
## sekmenin gorsel kivilcimi ve ekran titresimi ise aynen kalir.
func play_block_break() -> void:
	_last_bounce_msec = Time.get_ticks_msec()
	_play_sfx("block_break", -3.0)


func play_target_hit() -> void:
	_play_sfx("target_hit", 0.0)


## Sonuc paneli acilirken. target_hit'ten ~0.75 sn sonra geldigi icin
## ust uste binmez; yine de biraz kisik calinir.
func play_level_complete() -> void:
	_play_sfx("level_complete", -2.0)


func play_failure() -> void:
	_play_sfx("failure", -3.0)


func play_restart() -> void:
	_play_sfx("restart", -4.0)


# --- Acilis ekrani ------------------------------------------------------------

func play_splash_bounce() -> void:
	_play_sfx("splash_bounce", -2.0)


func play_logo_reveal() -> void:
	_play_sfx("logo_reveal", -4.0)


# --- Arayuz -------------------------------------------------------------------

func play_ui_click() -> void:
	_play_ui("ui_click", -2.0)


# --- Sessize alma -------------------------------------------------------------

func is_muted() -> bool:
	return _settings != null and _settings.master_muted


func set_muted(muted: bool) -> void:
	if _settings == null or _settings.master_muted == muted:
		return
	_settings.master_muted = muted
	_apply_mute()
	_settings.save()
	mute_changed.emit(muted)


func toggle_muted() -> void:
	set_muted(not is_muted())


# --- Ses seviyeleri -----------------------------------------------------------
#
# Kaydiricilar 0..1 DOGRUSAL calisir; kulak logaritmik duydugu icin bus'a
# desibel yazilir. 0.0 tam sessizdir - linear_to_db(0) sonsuz negatiftir,
# o yuzden ayrica ele alinir, yoksa bus gecersiz bir degerle susar.

const MIN_VOLUME_DB := -60.0


func get_music_volume() -> float:
	return _settings.music_volume if _settings != null else 1.0


func get_sfx_volume() -> float:
	return _settings.sfx_volume if _settings != null else 1.0


func set_music_volume(value: float) -> void:
	if _settings == null:
		return
	var wanted := clampf(value, 0.0, 1.0)
	if is_equal_approx(_settings.music_volume, wanted):
		return
	_settings.music_volume = wanted
	_apply_volumes()
	_settings.save()


func set_sfx_volume(value: float) -> void:
	if _settings == null:
		return
	var wanted := clampf(value, 0.0, 1.0)
	if is_equal_approx(_settings.sfx_volume, wanted):
		return
	_settings.sfx_volume = wanted
	_apply_volumes()
	_settings.save()


func _apply_volumes() -> void:
	if _settings == null:
		return
	# Arayuz sesleri SFX kaydiricisini takip eder: oyuncu "efektleri kis"
	# dediginde tik seslerinin tam sesle kalmasi tutarsiz olurdu.
	_set_bus_linear(MUSIC_BUS, _settings.music_volume)
	_set_bus_linear(SFX_BUS, _settings.sfx_volume)
	_set_bus_linear(UI_BUS, _settings.sfx_volume)


func _set_bus_linear(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(
		index, MIN_VOLUME_DB if linear <= 0.0 else linear_to_db(linear))


func stop_transient_sounds() -> void:
	for player in _sfx_pool:
		player.stop()
	for player in _ui_pool:
		player.stop()


# --- Debug --------------------------------------------------------------------

func get_active_sfx_count() -> int:
	var count := 0
	for player in _sfx_pool:
		if player.playing:
			count += 1
	return count


func get_last_played_sound() -> String:
	return _last_played


func get_debug_snapshot() -> Dictionary:
	return {
		"muted": is_muted(),
		"active_sfx": get_active_sfx_count(),
		"sfx_pool_size": _sfx_pool.size(),
		"last_sound": _last_played,
	}


# --- Ic isleyis ---------------------------------------------------------------

func _play_sfx(key: String, volume_db: float, pitch := 1.0) -> void:
	_play_on(_acquire_sfx(), key, volume_db, pitch)


func _play_ui(key: String, volume_db: float, pitch := 1.0) -> void:
	_play_on(_acquire_ui(), key, volume_db, pitch)


func _play_on(player: AudioStreamPlayer, key: String, volume_db: float, pitch: float) -> void:
	if player == null:
		return
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		# Dosya eksik/bozuk: _load_streams zaten uyardi, oyun sessizce devam eder.
		return
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = maxf(pitch * _pitch_jitter(), 0.01)
	player.play()
	_last_played = key


func _pitch_jitter() -> float:
	return 1.0 + _rng.randf_range(-PITCH_VARIATION, PITCH_VARIATION)


func _acquire_sfx() -> AudioStreamPlayer:
	for player in _sfx_pool:
		if not player.playing:
			return player
	if _sfx_pool.is_empty():
		return null
	var recycled := _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_pool.size()
	return recycled


func _acquire_ui() -> AudioStreamPlayer:
	for player in _ui_pool:
		if not player.playing:
			return player
	if _ui_pool.is_empty():
		return null
	var recycled := _ui_pool[_ui_cursor]
	_ui_cursor = (_ui_cursor + 1) % _ui_pool.size()
	return recycled


func _build_pools() -> void:
	_sfx_pool = _make_pool("SfxPlayer", SFX_POOL_SIZE, SFX_BUS)
	_ui_pool = _make_pool("UiPlayer", UI_POOL_SIZE, UI_BUS)


func _make_pool(prefix: String, size: int, bus: String) -> Array[AudioStreamPlayer]:
	var pool: Array[AudioStreamPlayer] = []
	for i in size:
		var player := AudioStreamPlayer.new()
		player.name = "%s%d" % [prefix, i]
		player.bus = bus
		add_child(player)
		pool.append(player)
	return pool


func _load_streams() -> void:
	for key in SOUND_FILES:
		var path: String = SFX_DIR + String(SOUND_FILES[key])
		if not ResourceLoader.exists(path):
			push_warning("AudioManager: ses dosyasi bulunamadi -> %s" % path)
			continue
		var stream := load(path) as AudioStream
		if stream == null:
			push_warning("AudioManager: %s bir AudioStream degil." % path)
			continue
		_streams[key] = stream


## Bus duzeni yuklenemezse (dosya eksik/bozuk) sesin tamamen kaybolmamasi icin
## eksik bus'lari calisma zamaninda olusturur.
func _ensure_buses() -> void:
	_ensure_bus(MUSIC_BUS, -12.0)
	_ensure_bus(SFX_BUS, -5.0)
	_ensure_bus(UI_BUS, -8.0)


func _ensure_bus(bus_name: String, volume_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	push_warning("AudioManager: '%s' bus'i yok, calisma zamaninda olusturuldu." % bus_name)
	var index := AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_volume_db(index, volume_db)
	AudioServer.set_bus_send(index, MASTER_BUS)


## Limiter normalde default_bus_layout.tres icinde gelir. Layout yuklenemezse
## (dosya eksik veya efekt sinifi bu Godot surumunde yoksa) Master efektsiz
## kalir; birkac ses ust uste bindiginde clipping olmasin diye eksikse
## calisma zamaninda eklenir.
func _ensure_master_limiter() -> void:
	var index := AudioServer.get_bus_index(MASTER_BUS)
	if index < 0 or AudioServer.get_bus_effect_count(index) > 0:
		return
	var effect := _make_limiter()
	if effect != null:
		AudioServer.add_bus_effect(index, effect)


func _make_limiter() -> AudioEffect:
	# Godot 4.4+ HardLimiter'i onerir; daha eski surumlerde Limiter kullanilir.
	for class_name_candidate in ["AudioEffectHardLimiter", "AudioEffectLimiter"]:
		if ClassDB.class_exists(class_name_candidate):
			return ClassDB.instantiate(class_name_candidate) as AudioEffect
	push_warning("AudioManager: limiter efekti bulunamadi, Master limitersiz calisiyor.")
	return null


func _apply_mute() -> void:
	var index := AudioServer.get_bus_index(MASTER_BUS)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, is_muted())
