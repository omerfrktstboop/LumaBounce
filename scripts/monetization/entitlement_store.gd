class_name EntitlementStore
extends RefCounted

## Billing adapterinden gelecek haklarin yerel cache'i. Su anda tek urun
## remove_ads ve varsayilani false. ProgressStore semasina bilerek eklenmez.

const CACHE_PATH := "user://entitlements.cfg"
const CACHE_SCHEMA := 1

var remove_ads := false
var verified_at_unix := 0.0

var _path := CACHE_PATH


func _init(path := CACHE_PATH) -> void:
	_path = path


static func load_from_disk() -> EntitlementStore:
	return load_from_path(CACHE_PATH)


static func load_from_path(path: String) -> EntitlementStore:
	var store := EntitlementStore.new(path)
	var config := ConfigFile.new()
	var error := config.load(path)
	if error == ERR_FILE_NOT_FOUND:
		return store
	if error != OK:
		push_warning("EntitlementStore: cache okunamadi; remove_ads=false kullaniliyor.")
		return store
	if int(config.get_value("meta", "schema", 0)) != CACHE_SCHEMA:
		push_warning("EntitlementStore: bilinmeyen cache semasi; varsayilan haklar kullaniliyor.")
		return store
	store.remove_ads = bool(config.get_value("entitlements", "remove_ads", false))
	store.verified_at_unix = maxf(
		float(config.get_value("meta", "verified_at_unix", 0.0)), 0.0)
	return store


func update_remove_ads(active: bool, verified_at := 0.0) -> bool:
	remove_ads = active
	verified_at_unix = maxf(verified_at, 0.0)
	return save_cache()


func save_cache() -> bool:
	var config := ConfigFile.new()
	config.set_value("meta", "schema", CACHE_SCHEMA)
	config.set_value("meta", "verified_at_unix", verified_at_unix)
	config.set_value("entitlements", "remove_ads", remove_ads)
	var error := config.save(_path)
	if error != OK:
		push_warning("EntitlementStore: cache yazilamadi (%s)." % error_string(error))
		return false
	return true


func snapshot() -> Dictionary:
	return {
		"remove_ads": remove_ads,
		"verified_at_unix": verified_at_unix,
	}
