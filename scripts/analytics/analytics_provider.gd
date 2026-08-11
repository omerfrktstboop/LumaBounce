class_name AnalyticsProvider
extends RefCounted

## AnalyticsService'in arkasindaki SDK adaptoru. Oyun kodu yalnızca normalize
## event adlarini bilir; provider singleton'i bu sinirin disina cikamaz.


func provider_name() -> StringName:
	return &"none"


func initialize(_config: GameAnalyticsConfig) -> bool:
	return false


func send_event(_event_name: StringName, _properties: Dictionary) -> bool:
	return false


func set_collection_enabled(_enabled: bool) -> void:
	pass


func shutdown() -> void:
	pass
