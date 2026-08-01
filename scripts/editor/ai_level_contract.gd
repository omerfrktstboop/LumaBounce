class_name AILevelContract
extends RefCounted

## OpenRouter semasi, mapper sinirlari ve UI secenekleri icin tek kaynak.

const PROMPT_VERSION := "1.5"
const MAX_LEVELS := 10
const MAX_PANELS := 5
const MAX_BLOCKS := 4
const MAX_DISPLAY_NAME := 40
const MAX_DESIGN_INTENT := 240
const MAX_DESIGN_NOTE := 1000

const TEMPLATE_IDS := [
	"auto", "tutorial", "single_bounce", "wall_bounce", "zigzag",
	"narrow_passage", "reverse_route", "two_routes", "safe_block_route",
	"block_free_mastery", "multi_shot", "ricochet_chain", "block_corridor",
	"mini_final",
]
const DIFFICULTY_IDS := ["easy", "medium", "hard", "final"]
const MECHANIC_IDS := ["panel", "wall_gap", "breakable_block"]


static func response_schema(requested_count: int) -> Dictionary:
	var launcher := _object({
		"x": _number(320.0, 400.0),
		"y": _number(1080.0, 1140.0),
	}, ["x", "y"])
	var target := _object({
		"x": _number(140.0, 580.0),
		"y": _number(230.0, 480.0),
	}, ["x", "y"])
	var wall_gap := _object({
		"enabled": {"type": "boolean"},
		"top": _number(180.0, 860.0),
		"bottom": _number(420.0, 1080.0),
	}, ["enabled", "top", "bottom"])
	var panel := _object({
		"x": _number(130.0, 590.0),
		"y": _number(460.0, 930.0),
		"rotation_degrees": _number(-55.0, 55.0),
		"length": _number(220.0, 340.0),
		"thickness": _number(20.0, 32.0),
	}, ["x", "y", "rotation_degrees", "length", "thickness"])
	var block := _object({
		"x": _number(140.0, 580.0),
		"y": _number(420.0, 900.0),
		"rotation_degrees": _number(-55.0, 55.0),
		"width": _number(120.0, 280.0),
		"height": _number(36.0, 52.0),
	}, ["x", "y", "rotation_degrees", "width", "height"])
	var expected_solution := _object({
		"estimated_bounces": {"type": "integer", "minimum": 0, "maximum": 12},
		"blocks_required": {"type": "integer", "minimum": 0, "maximum": MAX_BLOCKS},
		"route_description": {"type": "string", "maxLength": 240},
	}, ["estimated_bounces", "blocks_required", "route_description"])
	var level := _object({
		"display_name": {"type": "string", "minLength": 1, "maxLength": MAX_DISPLAY_NAME},
		"design_intent": {"type": "string", "maxLength": MAX_DESIGN_INTENT},
		"launcher": launcher,
		"target": target,
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
			"minItems": clampi(requested_count, 1, MAX_LEVELS),
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
