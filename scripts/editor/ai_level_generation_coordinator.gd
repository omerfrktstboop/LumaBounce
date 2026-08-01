class_name AILevelGenerationCoordinator
extends Node

## Tek OpenRouter batch istegini mapper -> yerel varyasyon -> LevelSolver ->
## novelty -> quality -> GENERATED + sidecar zincirine baglar.

signal status_changed(message: String)
signal progress_changed(tried: int, total: int, accepted: int)
signal completed(levels: Array[LevelData], names: PackedStringArray, metadata: Array[Dictionary])
signal failed(message: String)
signal cancelled

var _client: OpenRouterClient
var _generator: LevelGenerator
var _mapper := AILevelMapper.new()
var _novelty := LevelNoveltyScorer.new()
var _quality := LevelQualityScorer.new()
var _metadata_store := GenerationMetadataStore.new()
var _running := false
var _cancel_requested := false
var _request := {}
var _usage := {}


func _ready() -> void:
	_client = OpenRouterClient.new()
	_client.name = "OpenRouterClient"
	add_child(_client)
	_generator = LevelGenerator.new()
	_generator.name = "AIGenerator"
	add_child(_generator)
	_client.status_changed.connect(status_changed.emit)
	_client.completed.connect(_on_blueprints_received)
	_client.failed.connect(_on_client_failed)
	_client.cancelled.connect(_on_cancelled)
	_generator.blueprint_progress.connect(_on_generator_progress)
	_generator.blueprints_finished.connect(_on_physics_finished)


func is_running() -> bool:
	return _running


func start(request: Dictionary) -> Error:
	if not OS.is_debug_build():
		failed.emit("AI uretimi yalnizca debug surumunde kullanilabilir.")
		return ERR_UNAUTHORIZED
	if _running:
		return ERR_BUSY
	_request = _sanitize_request(request)
	_cancel_requested = false
	_running = true
	_usage = {}
	var options := {
		"template": _request["template"],
		"difficulty": _request["difficulty"],
		"mechanics": _request["mechanics"],
		"design_note": _request["design_note"],
	}
	var error := _client.request_blueprints(
		String(request.get("api_key", "")), String(_request["model_slug"]),
		options, int(_request["blueprint_count"]))
	if error != OK and _running:
		_running = false
	return error


func cancel_generation() -> void:
	if not _running:
		return
	_cancel_requested = true
	_client.cancel_request()
	_generator.cancel()
	# Generator kendi dongusunu guvenli noktada kapatir; HTTP asamasinda ise
	# client sinyali hemen tamamlar.
	if not _generator.is_running() and _running:
		_on_cancelled()


func rank_records(records: Array[Dictionary], request: Dictionary,
		references: Array) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	var batch_references: Array[Dictionary] = []
	for record in records:
		if not record.get("level", null) is LevelData:
			continue
		var level: LevelData = record["level"]
		var solver: Dictionary = record.get("solver", {})
		if not bool(solver.get("ok", false)):
			continue
		if (String(request.get("template", "auto")) == "two_routes"
				and int(solver.get("route_clusters", 0)) < 2):
			continue
		var comparison := references.duplicate()
		comparison.append_array(batch_references)
		var novelty := _novelty.score(level, solver, comparison)
		if bool(novelty["reject"]):
			continue
		var quality := _quality.score(level, solver, novelty, String(request.get("template", "auto")))
		var ranked_record := record.duplicate(true)
		ranked_record["novelty"] = novelty
		ranked_record["quality"] = quality
		ranked.append(ranked_record)
		batch_references.append({
			"name": "Ayni batch %d" % ranked.size(),
			"level": level,
			"metrics": solver,
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var qa := int(a["quality"]["quality_score"])
		var qb := int(b["quality"]["quality_score"])
		if qa != qb:
			return qa > qb
		return int(a["novelty"]["novelty_score"]) > int(b["novelty"]["novelty_score"]))
	return ranked


func _on_blueprints_received(document: Dictionary, usage: Dictionary) -> void:
	if _cancel_requested:
		_on_cancelled()
		return
	_usage = usage.duplicate(true)
	var mapped := _mapper.map_document(document)
	if not bool(mapped["ok"]):
		_finish_failed("AI taslaklari gecerli bolum geometrisine donusturulemedi.")
		return
	var blueprints: Array = mapped["blueprints"]
	status_changed.emit("%d taslak alindi. Varyasyonlar olusturuluyor..." % blueprints.size())
	var wanted := int(_request["candidate_count"])
	var physics_pool := mini(20, maxi(wanted, wanted * 2))
	_generator.generate_from_blueprints(
		_profile_for(_request), blueprints, physics_pool,
		int(_request["variation_count"]), int(_request["seed"]))


func _on_generator_progress(tried: int, total: int, accepted: int) -> void:
	status_changed.emit("%d / %d aday test edildi. %d uygun." % [tried, total, accepted])
	progress_changed.emit(tried, total, accepted)


func _on_physics_finished(records: Array[Dictionary]) -> void:
	if _cancel_requested:
		_on_cancelled()
		return
	if records.is_empty():
		_finish_failed("LevelSolver filtrelerinden gecen aday bulunamadi.")
		return
	status_changed.emit("Yenilik ve kalite puanlari hesaplaniyor...")
	var ranked := rank_records(records, _request, _novelty.default_references())
	var wanted := int(_request["candidate_count"])
	if ranked.size() > wanted:
		ranked.resize(wanted)
	if ranked.is_empty():
		_finish_failed("Adaylar mevcut bolumlere cok benzedigi icin elendi.")
		return
	var levels: Array[LevelData] = []
	var metadata: Array[Dictionary] = []
	for record in ranked:
		levels.append(record["level"])
		metadata.append(_build_metadata(record))
	var names := CustomLevelStore.replace_generated(levels)
	if names.size() != levels.size():
		_finish_failed("Uretilen bolumler yerel depoya yazilamadi.")
		return
	if _metadata_store.replace(names, metadata) != OK:
		_finish_failed("Uretim metadata dosyasi yazilamadi.")
		return
	_running = false
	completed.emit(levels, names, metadata)


func _build_metadata(record: Dictionary) -> Dictionary:
	var solver: Dictionary = record["solver"]
	var novelty: Dictionary = record["novelty"]
	var quality: Dictionary = record["quality"]
	return {
		"model_slug": _request["model_slug"],
		"template": _request["template"],
		"difficulty": _request["difficulty"],
		"user_design_note": _request["design_note"],
		"generation_timestamp": Time.get_datetime_string_from_system(true),
		"prompt_version": AILevelContract.PROMPT_VERSION,
		"blueprint_index": int(record.get("blueprint_index", 0)),
		"variation_seed": int(record.get("variation_seed", 0)),
		"robust_cells": int(solver.get("robust", 0)),
		"bounce_count": int(solver.get("bounces", 0)),
		"opened_robust": int(solver.get("opened_robust", 0)),
		"novelty_score": int(novelty["novelty_score"]),
		"quality_score": int(quality["quality_score"]),
		"most_similar_level": String(novelty["most_similar_level"]),
		"similarity_reasons": novelty["similarity_reasons"],
		"design_intent": String(record.get("design_intent", "")),
		"usage": _usage,
	}


func _profile_for(request: Dictionary) -> LevelGenerator.Profile:
	match String(request["difficulty"]):
		"easy":
			return LevelGenerator.Profile.easy()
		"hard", "final":
			return LevelGenerator.Profile.hard()
		_:
			return LevelGenerator.Profile.medium()


func _sanitize_request(source: Dictionary) -> Dictionary:
	var settings := AIGeneratorSettings.new()
	var safe := settings.defaults()
	for key in safe:
		if source.has(key):
			safe[key] = source[key]
	# Ayar yoneticisinin ayni sinirlari tek yerde uygulamasini kullan.
	safe = settings.sanitize(safe)
	safe["seed"] = int(source.get("seed", 0))
	return safe


func _on_client_failed(message: String, _status_code: int) -> void:
	_finish_failed(message)


func _finish_failed(message: String) -> void:
	_running = false
	failed.emit(message)


func _on_cancelled() -> void:
	if not _running:
		return
	_running = false
	cancelled.emit()
