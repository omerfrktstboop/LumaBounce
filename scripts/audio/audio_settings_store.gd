class_name AudioSettingsStore
extends RefCounted

## Kalici ses ayarlari: user://audio_settings.cfg.
##
## Dosya yoksa, bozuksa veya beklenmeyen bir tip iceriyorsa sessizce
## varsayilana donulur; oyun hicbir durumda ayar dosyasi yuzunden acilmaz
## olmaz. Ayni savunmaci desen: ProgressStore, PlaytestStats.
##
## Ses ayarlari ILERLEMEDEN AYRI bir dosyada durur ve ProgressStore.reset()
## bunlara dokunmaz - "bastan basla" diyen oyuncunun kistigi sesi geri
## acmak yanlis olurdu.

const SAVE_PATH := "user://audio_settings.cfg"
const SECTION := "audio"
const KEY_MASTER_MUTED := "master_muted"
const KEY_MUSIC_VOLUME := "music_volume"
const KEY_SFX_VOLUME := "sfx_volume"

var master_muted := false
## 0.0..1.0 dogrusal ses seviyesi. Muzik (ortam dongusu) ve efektler AYRI
## tutulur: ortam dongusunu kisip sekme sesini duymak isteyen oyuncu, tek bir
## "ses" kaydiriciyla bunu yapamaz.
var music_volume := 1.0
var sfx_volume := 1.0


static func load_from_disk() -> AudioSettingsStore:
	var store := AudioSettingsStore.new()
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return store

	var raw_muted: Variant = config.get_value(SECTION, KEY_MASTER_MUTED, false)
	if raw_muted is bool:
		store.master_muted = raw_muted
	store.music_volume = _read_volume(config, KEY_MUSIC_VOLUME)
	store.sfx_volume = _read_volume(config, KEY_SFX_VOLUME)
	return store


## Eksik veya bozuk deger tam sese duser: sessiz acilan bir oyun, bozuk ayar
## dosyasini "ses calismiyor" hatasi gibi gosterirdi.
static func _read_volume(config: ConfigFile, key: String) -> float:
	var raw: Variant = config.get_value(SECTION, key, 1.0)
	if raw is float or raw is int:
		return clampf(float(raw), 0.0, 1.0)
	return 1.0


func save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, KEY_MASTER_MUTED, master_muted)
	config.set_value(SECTION, KEY_MUSIC_VOLUME, music_volume)
	config.set_value(SECTION, KEY_SFX_VOLUME, sfx_volume)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("AudioSettingsStore: kayit yazilamadi (hata %d)." % error)
