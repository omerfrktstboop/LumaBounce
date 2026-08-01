class_name GenerationMetadataStore
extends RefCounted

## Debug uretim bilgileri LevelData/.tres icine girmez; dosya adiyla eslesen
## ayri bir JSON sidecar'da tutulur.

const MANIFEST_PATH := "user://generated_levels/generated_manifest.json"
const MANIFEST_VERSION := 1

const ALLOWED_FIELDS := [
	"model_slug", "template", "difficulty", "user_design_note",
	"generation_timestamp", "prompt_version", "blueprint_index", "variation_seed",
	"variation_scale", "physics_rescue", "generation_seed",
	"robust_cells", "bounce_count", "opened_robust", "novelty_score", "quality_score",
	"solution_shots", "broken_state",
	"similarity_fallback",
	"most_similar_level", "similarity_reasons", "design_intent", "usage",
]

var _path: String


func _init(path := MANIFEST_PATH) -> void:
	_path = path


func replace(names: PackedStringArray, metadata: Array) -> Error:
	var entries := {}
	for i in mini(names.size(), metadata.size()):
		if metadata[i] is Dictionary:
			entries[names[i]] = _sanitize_entry(metadata[i])
	var payload := {
		"version": MANIFEST_VERSION,
		"entries": entries,
	}
	var base_dir := _path.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		var dir_error := DirAccess.make_dir_recursive_absolute(base_dir)
		if dir_error != OK:
			return dir_error
	var temp_path := _path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(_path))


func load_all() -> Dictionary:
	if not FileAccess.file_exists(_path):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(_path)) != OK:
		return {}
	if not parser.data is Dictionary or not parser.data.get("entries", null) is Dictionary:
		return {}
	return parser.data["entries"].duplicate(true)


func get_entry(level_name: String) -> Dictionary:
	var entries := load_all()
	var entry = entries.get(level_name, {})
	return entry.duplicate(true) if entry is Dictionary else {}


func clear() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


func _sanitize_entry(source: Dictionary) -> Dictionary:
	var safe := {}
	for key in ALLOWED_FIELDS:
		if not source.has(key):
			continue
		var value = source[key]
		if value is String:
			safe[key] = String(value).left(1000)
		elif value is int or value is float or value is bool:
			safe[key] = value
		elif value is Array or value is PackedStringArray or value is Dictionary:
			# Bu alanlar yalnizca yerel skor/usage verisidir; JSON serilestirme
			# resource veya Callable calistiramaz.
			safe[key] = value
	return safe
