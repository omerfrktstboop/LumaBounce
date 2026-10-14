class_name ReviewProvider
extends Node

## Platform review API adapters expose only this small surface to the game.
## Completion means the platform flow returned; it never means a rating was
## submitted because Google Play intentionally does not reveal that result.

@warning_ignore("unused_signal")
signal review_finished(completed: bool)


func provider_name() -> StringName:
	return &"base"


func initialize() -> bool:
	return false


func is_available() -> bool:
	return false


func is_busy() -> bool:
	return false


func request_review() -> bool:
	return false
