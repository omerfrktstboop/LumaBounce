class_name NoOpAnalyticsProvider
extends AnalyticsProvider

## SDK kapali, eksik veya basarisiz oldugunda sessiz ve hizli geri donus.


func provider_name() -> StringName:
	return &"no_op"


func initialize(_config: GameAnalyticsConfig) -> bool:
	return true


func send_event(_event_name: StringName, _properties: Dictionary) -> bool:
	return true
