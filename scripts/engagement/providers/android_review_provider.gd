class_name AndroidReviewProvider
extends ReviewProvider

const PLUGIN_SINGLETON_NAME := "LumaReviewPlugin"

var _plugin: Object
var _busy := false


func provider_name() -> StringName:
	return &"google_play"


func initialize() -> bool:
	if OS.get_name() != "Android" or not Engine.has_singleton(PLUGIN_SINGLETON_NAME):
		return false
	_plugin = Engine.get_singleton(PLUGIN_SINGLETON_NAME)
	if _plugin == null or not _plugin.has_signal("review_flow_finished"):
		_plugin = null
		return false
	_plugin.connect("review_flow_finished", _on_review_flow_finished)
	return true


func is_available() -> bool:
	return _plugin != null and not _busy


func is_busy() -> bool:
	return _busy


func request_review() -> bool:
	if not is_available() or not _plugin.has_method("requestReview"):
		return false
	_busy = bool(_plugin.call("requestReview"))
	return _busy


func _on_review_flow_finished(completed: bool) -> void:
	if not _busy:
		return
	_busy = false
	review_finished.emit(completed)
