class_name GameAnalyticsProvider
extends AnalyticsProvider

## Resmi GameAnalytics singleton'ini normalize AnalyticsService eventlerine
## uyarlar. Bu dosya disinda hicbir runtime kodu SDK class adini bilmez.

const PLUGIN_SINGLETON_NAME := "GameAnalytics"
const PROGRESSION_EVENTS := {
	AnalyticsService.LEVEL_START: "start",
	AnalyticsService.LEVEL_COMPLETE: "complete",
	AnalyticsService.LEVEL_FAIL: "fail",
}

var _api: Object
var _ready := false


func _init(api_override: Object = null) -> void:
	_api = api_override


func provider_name() -> StringName:
	return &"gameanalytics" if _ready else &"gameanalytics_unavailable"


func initialize(config: GameAnalyticsConfig) -> bool:
	if config == null or not config.is_ready():
		return false
	if _api == null:
		if not Engine.has_singleton(PLUGIN_SINGLETON_NAME):
			return false
		_api = Engine.get_singleton(PLUGIN_SINGLETON_NAME)
	if not _has_required_api():
		return false
	# Random SDK kimligi kullanilir; e-posta, reklam kimligi veya oyun save ID'si
	# analytics kimligi olarak verilmez.
	_api.call("useRandomizedId", true)
	_api.call("configureBuild", "%s-%s" % [GameVersion.GAME, config.environment])
	_api.call("setEnabledErrorReporting", false)
	_api.call("setEnabledEventSubmission", config.collection_enabled)
	_api.call("init", config.game_key, config.secret_key)
	_ready = true
	return true


func send_event(event_name: StringName, properties: Dictionary) -> bool:
	if not _ready or _api == null:
		return false
	var options := {"fields": JSON.stringify(properties)}
	if PROGRESSION_EVENTS.has(event_name):
		var level_id := int(properties.get("level_id", 0))
		var world := String(properties.get("world", "world_01"))
		var level := "level_%03d" % maxi(level_id, 0)
		var phase := "bonus" if bool(properties.get("is_bonus", false)) else "normal"
		_api.call("addProgressionEvent", PROGRESSION_EVENTS[event_name],
			world, level, phase, options)
		return true
	_api.call("addDesignEvent", String(event_name).replace("_", ":"), options)
	return true


func set_collection_enabled(enabled: bool) -> void:
	if _api != null and _api.has_method(&"setEnabledEventSubmission"):
		_api.call("setEnabledEventSubmission", enabled)


func shutdown() -> void:
	_ready = false


func _has_required_api() -> bool:
	for method in [
		&"useRandomizedId", &"configureBuild", &"setEnabledErrorReporting",
		&"setEnabledEventSubmission", &"init", &"addProgressionEvent",
		&"addDesignEvent",
	]:
		if not _api.has_method(method):
			return false
	return true
