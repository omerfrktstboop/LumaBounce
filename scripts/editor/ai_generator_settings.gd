class_name AIGeneratorSettings
extends RefCounted

## API anahtari yalnizca acik onayla user:// altinda DUZ METIN saklanir.
## Bu gercek sifreleme degildir; varsayilan davranis anahtari diske yazmaz.

const SETTINGS_PATH := "user://ai_settings.cfg"

var _path: String


func _init(path := SETTINGS_PATH) -> void:
	_path = path


func defaults() -> Dictionary:
	return {
		"model_slug": "",
		"remember_api_key": false,
		"api_key": "",
		"template": "auto",
		"difficulty": "medium",
		"mechanics": PackedStringArray(["panel"]),
		"design_note": "",
		"blueprint_count": 5,
		"variation_count": 12,
		"candidate_count": 10,
	}


func load_values() -> Dictionary:
	var values := defaults()
	var config := ConfigFile.new()
	if config.load(_path) != OK:
		return values
	for key in values:
		if config.has_section_key("generator", key):
			values[key] = config.get_value("generator", key, values[key])
	return _sanitize(values)


func save_values(values: Dictionary, api_key := "") -> Error:
	var safe := _sanitize(values)
	var config := ConfigFile.new()
	for key in safe:
		if key == "api_key":
			continue
		config.set_value("generator", key, safe[key])
	if bool(safe["remember_api_key"]) and not String(api_key).is_empty():
		config.set_value("generator", "api_key", String(api_key))
	return config.save(_path)


func clear_api_key() -> Error:
	var values := load_values()
	values["remember_api_key"] = false
	return save_values(values, "")


func sanitize(values: Dictionary) -> Dictionary:
	return _sanitize(values)


func _sanitize(source: Dictionary) -> Dictionary:
	var safe := defaults()
	var model_slug := String(source.get("model_slug", "")).strip_edges()
	safe["model_slug"] = model_slug.left(160)
	safe["remember_api_key"] = bool(source.get("remember_api_key", false))
	if safe["remember_api_key"]:
		safe["api_key"] = String(source.get("api_key", ""))
	var template_id := String(source.get("template", "auto"))
	safe["template"] = template_id if template_id in AILevelContract.TEMPLATE_IDS else "auto"
	var difficulty := String(source.get("difficulty", "medium"))
	safe["difficulty"] = difficulty if difficulty in AILevelContract.DIFFICULTY_IDS else "medium"
	var mechanics := PackedStringArray()
	for mechanic in source.get("mechanics", []):
		var mechanic_id := String(mechanic)
		if mechanic_id in AILevelContract.MECHANIC_IDS and not mechanics.has(mechanic_id):
			mechanics.append(mechanic_id)
	if mechanics.is_empty():
		mechanics.append("panel")
	safe["mechanics"] = mechanics
	safe["design_note"] = String(source.get("design_note", "")).left(AILevelContract.MAX_DESIGN_NOTE)
	safe["blueprint_count"] = clampi(int(source.get("blueprint_count", 5)), 1, 10)
	safe["variation_count"] = clampi(int(source.get("variation_count", 12)), 1, 30)
	safe["candidate_count"] = clampi(int(source.get("candidate_count", 10)), 1, 20)
	return safe
