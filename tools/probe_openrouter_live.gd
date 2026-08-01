extends SceneTree

## Istege bagli canli OpenRouter probi. Anahtari yalnizca process environment'tan
## okur ve yanit icerigini/log header'larini yazdirmaz.

const PROBE_LIMIT_MS := 210000

var _finished := false
var _exit_code := 1
var _started_ms := 0
var _document := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var api_key := OS.get_environment("OPENROUTER_API_KEY")
	var model := OS.get_environment("OPENROUTER_MODEL")
	var requested_count := clampi(
		int(OS.get_environment("OPENROUTER_BLUEPRINT_COUNT")), 1, AILevelContract.MAX_LEVELS)
	if api_key.is_empty() or model.is_empty():
		print("LIVE PROBE: OPENROUTER_API_KEY ve OPENROUTER_MODEL gerekli.")
		quit(2)
		return

	var client := OpenRouterClient.new()
	root.add_child(client)
	client.status_changed.connect(func(message: String) -> void:
		print("LIVE STATUS: %s" % message))
	client.completed.connect(func(document: Dictionary, usage: Dictionary) -> void:
		_document = document.duplicate(true)
		var levels = document.get("levels", [])
		var level_count: int = levels.size() if levels is Array else 0
		print("LIVE OK: %.2f sn, %d taslak, prompt=%d, completion=%d" % [
			_elapsed_seconds(), level_count,
			int(usage.get("prompt_tokens", 0)), int(usage.get("completion_tokens", 0)),
		])
		_exit_code = 0
		_finished = true)
	client.failed.connect(func(message: String, status_code: int) -> void:
		print("LIVE FAIL: %.2f sn, HTTP=%d, %s" % [
			_elapsed_seconds(), status_code, message])
		_finished = true)

	_started_ms = Time.get_ticks_msec()
	var error := client.request_blueprints(api_key, model, {
		"template": "auto",
		"difficulty": "medium",
		"mechanics": PackedStringArray(["panel"]),
		"design_note": "Okunabilir, adil ve farkli bir rota.",
	}, requested_count)
	api_key = ""
	if error != OK and not _finished:
		print("LIVE FAIL: istek baslatma kodu %d" % error)
		_finished = true

	while not _finished and Time.get_ticks_msec() - _started_ms < PROBE_LIMIT_MS:
		await process_frame
	if not _finished:
		client.cancel_request()
		print("LIVE FAIL: prob ust zaman sinirina ulasti.")
	if _exit_code == 0 and OS.get_environment("OPENROUTER_VALIDATE_PIPELINE") == "1":
		_exit_code = await _validate_pipeline(_document)
	quit(_exit_code)


func _elapsed_seconds() -> float:
	return float(Time.get_ticks_msec() - _started_ms) / 1000.0


func _validate_pipeline(document: Dictionary) -> int:
	var mapped := AILevelMapper.new().map_document(document)
	if not bool(mapped.get("ok", false)):
		print("PIPELINE FAIL: AILevelMapper belgeyi reddetti.")
		return 1
	var blueprints: Array = mapped.get("blueprints", [])
	print("PIPELINE MAP: %d taslak geometriye donusturuldu." % blueprints.size())
	var generator := LevelGenerator.new()
	root.add_child(generator)
	var records: Array[Dictionary] = []
	generator.blueprints_finished.connect(func(items: Array[Dictionary]) -> void:
		records.assign(items))
	generator.generate_from_blueprints(
		LevelGenerator.Profile.medium(), blueprints, 10, 6, 731)
	while generator.is_running():
		await process_frame
	print("PIPELINE SOLVER: %d fizik filtresinden gecen aday." % records.size())
	print("PIPELINE RET: %s" % generator.describe_rejections())
	root.remove_child(generator)
	generator.free()
	return 0 if not records.is_empty() else 1
