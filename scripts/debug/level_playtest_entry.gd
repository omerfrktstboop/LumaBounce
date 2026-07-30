class_name LevelPlaytestEntry
extends RefCounted

## Tek bir bolume ait yerel playtest sayaclari.
##
## Salt veri: hicbir dosya IO veya oyun mantigi burada olmaz, bkz. PlaytestStats.

var entries := 0
var completions := 0
var total_shots := 0
var failed_shots := 0
var restarts := 0
var out_of_bounds_failures := 0
var settled_failures := 0
var manual_cancels := 0
var total_time_seconds := 0.0
## Hicbir tamamlanma yoksa -1 (henuz bilgi yok anlaminda).
var min_shots_to_complete := -1
var total_completion_seconds := 0.0


func average_completion_seconds() -> float:
	return total_completion_seconds / float(completions) if completions > 0 else 0.0


func record_completion(shots_used: int, elapsed_seconds: float) -> void:
	completions += 1
	total_completion_seconds += elapsed_seconds
	if min_shots_to_complete < 0 or shots_used < min_shots_to_complete:
		min_shots_to_complete = shots_used


func record_failure(reason: String) -> void:
	failed_shots += 1
	match reason:
		"out_of_bounds":
			out_of_bounds_failures += 1
		"settled":
			settled_failures += 1
		"manual_cancel":
			manual_cancels += 1


func to_dictionary() -> Dictionary:
	return {
		"entries": entries,
		"completions": completions,
		"total_shots": total_shots,
		"failed_shots": failed_shots,
		"restarts": restarts,
		"total_time_seconds": total_time_seconds,
		"min_shots_to_complete": min_shots_to_complete,
		"average_completion_seconds": average_completion_seconds(),
		"out_of_bounds_failures": out_of_bounds_failures,
		"settled_failures": settled_failures,
		"manual_cancels": manual_cancels,
	}


func load_from(config: ConfigFile, section: String) -> void:
	entries = config.get_value(section, "entries", 0)
	completions = config.get_value(section, "completions", 0)
	total_shots = config.get_value(section, "total_shots", 0)
	failed_shots = config.get_value(section, "failed_shots", 0)
	restarts = config.get_value(section, "restarts", 0)
	out_of_bounds_failures = config.get_value(section, "out_of_bounds_failures", 0)
	settled_failures = config.get_value(section, "settled_failures", 0)
	manual_cancels = config.get_value(section, "manual_cancels", 0)
	total_time_seconds = config.get_value(section, "total_time_seconds", 0.0)
	min_shots_to_complete = config.get_value(section, "min_shots_to_complete", -1)
	var raw_total_completion: Variant = config.get_value(section, "total_completion_seconds", null)
	if raw_total_completion is int or raw_total_completion is float:
		total_completion_seconds = float(raw_total_completion)
	else:
		var average_completion: Variant = config.get_value(section, "average_completion_seconds", 0.0)
		if average_completion is int or average_completion is float:
			total_completion_seconds = float(average_completion) * float(completions)


func save_to(config: ConfigFile, section: String) -> void:
	config.set_value(section, "entries", entries)
	config.set_value(section, "completions", completions)
	config.set_value(section, "total_shots", total_shots)
	config.set_value(section, "failed_shots", failed_shots)
	config.set_value(section, "restarts", restarts)
	config.set_value(section, "out_of_bounds_failures", out_of_bounds_failures)
	config.set_value(section, "settled_failures", settled_failures)
	config.set_value(section, "manual_cancels", manual_cancels)
	config.set_value(section, "total_time_seconds", total_time_seconds)
	config.set_value(section, "min_shots_to_complete", min_shots_to_complete)
	config.set_value(section, "average_completion_seconds", average_completion_seconds())
	config.set_value(section, "total_completion_seconds", total_completion_seconds)
