class_name AILevelContract
extends RefCounted

## OpenRouter semasi, mapper sinirlari ve UI secenekleri icin tek kaynak.

const PROMPT_VERSION := "1.0"
const MAX_LEVELS := 10
const MAX_PANELS := 5
const MAX_BLOCKS := 4
const MAX_DISPLAY_NAME := 40
const MAX_DESIGN_INTENT := 240
const MAX_DESIGN_NOTE := 1000

const TEMPLATE_IDS := [
	"auto", "tutorial", "single_bounce", "wall_bounce", "zigzag",
	"narrow_passage", "reverse_route", "two_routes", "safe_block_route",
	"block_free_mastery", "multi_shot", "mini_final",
]
const DIFFICULTY_IDS := ["easy", "medium", "hard", "final"]
const MECHANIC_IDS := ["panel", "wall_gap", "breakable_block"]


static func response_schema(requested_count: int) -> Dictionary:
	var point := _object({
		"x": _number(0.0, 720.0),
		"y": _number(0.0, 1280.0),
	}, ["x", "y"])
	var wall_gap := _object({
		"enabled": {"type": "boolean"},
		"top": _number(0.0, 1280.0),
		"bottom": _number(0.0, 1280.0),
	}, ["enabled", "top", "bottom"])
	var panel := _object({
		"x": _number(0.0, 720.0),
		"y": _number(0.0, 1280.0),
		"rotation_degrees": _number(-180.0, 180.0),
		"length": _number(120.0, 480.0),
		"thickness": _number(10.0, 60.0),
	}, ["x", "y", "rotation_degrees", "length", "thickness"])
	var block := _object({
		"x": _number(0.0, 720.0),
		"y": _number(0.0, 1280.0),
		"rotation_degrees": _number(-180.0, 180.0),
		"width": _number(100.0, 360.0),
		"height": _number(20.0, 80.0),
	}, ["x", "y", "rotation_degrees", "width", "height"])
	var expected_solution := _object({
		"estimated_bounces": {"type": "integer", "minimum": 0, "maximum": 12},
		"blocks_required": {"type": "integer", "minimum": 0, "maximum": MAX_BLOCKS},
		"route_description": {"type": "string", "maxLength": 240},
	}, ["estimated_bounces", "blocks_required", "route_description"])
	var level := _object({
		"display_name": {"type": "string", "minLength": 1, "maxLength": MAX_DISPLAY_NAME},
		"design_intent": {"type": "string", "maxLength": MAX_DESIGN_INTENT},
		"launcher": point,
		"target": point,
		"panels": {
			"type": "array", "maxItems": MAX_PANELS, "items": panel,
		},
		"blocks": {
			"type": "array", "maxItems": MAX_BLOCKS, "items": block,
		},
		"left_wall_gap": wall_gap,
		"right_wall_gap": wall_gap,
		"max_lives": {"type": "integer", "minimum": 1, "maximum": 8},
		"expected_solution": expected_solution,
	}, [
		"display_name", "design_intent", "launcher", "target", "panels", "blocks",
		"left_wall_gap", "right_wall_gap", "max_lives", "expected_solution",
	])
	return _object({
		"levels": {
			"type": "array",
			"minItems": 1,
			"maxItems": clampi(requested_count, 1, MAX_LEVELS),
			"items": level,
		},
	}, ["levels"])


static func structured_response_format(requested_count: int) -> Dictionary:
	return {
		"type": "json_schema",
		"json_schema": {
			"name": "lumabounce_level_blueprints",
			"strict": true,
			"schema": response_schema(requested_count),
		},
	}


static func _number(minimum: float, maximum: float) -> Dictionary:
	return {"type": "number", "minimum": minimum, "maximum": maximum}


static func _object(properties: Dictionary, required: Array) -> Dictionary:
	return {
		"type": "object",
		"properties": properties,
		"required": required,
		"additionalProperties": false,
	}
