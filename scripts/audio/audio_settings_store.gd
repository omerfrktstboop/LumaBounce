class_name AudioSettingsStore
extends RefCounted

## Kalici ses ayarlari: user://audio_settings.cfg.
##
## Su an yalnizca master_muted saklanir. Dosya yoksa, bozuksa veya
## beklenmeyen bir tip iceriyorsa sessizce varsayilana (sesli) donulur;
## oyun hicbir durumda ayar dosyasi yuzunden acilmaz olmaz.
## Ayni savunmaci desen: ProgressStore, PlaytestStats.

const SAVE_PATH := "user://audio_settings.cfg"
const SECTION := "audio"
const KEY_MASTER_MUTED := "master_muted"

var master_muted := false


static func load_from_disk() -> AudioSettingsStore:
	var store := AudioSettingsStore.new()
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return store

	var raw_muted: Variant = config.get_value(SECTION, KEY_MASTER_MUTED, false)
	if raw_muted is bool:
		store.master_muted = raw_muted
	return store


func save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, KEY_MASTER_MUTED, master_muted)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("AudioSettingsStore: kayit yazilamadi (hata %d)." % error)
