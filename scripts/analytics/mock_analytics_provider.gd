class_name MockAnalyticsProvider
extends AnalyticsProvider

## Faz 10 testlerinin network kullanmadan provider sonucunu yonetebilmesi icin.

var initialize_result := true
var next_send_result := true
var received: Array[Dictionary] = []
var initialize_calls := 0


func provider_name() -> StringName:
	return &"mock"


func initialize(_config: GameAnalyticsConfig) -> bool:
	initialize_calls += 1
	return initialize_result


func send_event(event_name: StringName, properties: Dictionary) -> bool:
	received.append({
		"name": event_name,
		"properties": properties.duplicate(true),
	})
	var result := next_send_result
	next_send_result = true
	return result
