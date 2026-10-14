class_name FirstShotTutorial
extends Control

## Non-modal guidance: the launcher owns input and physics. No timer advances
## these steps. Gameplay forwards actual aim/shot events.
signal finished(skipped: bool)

enum Step { TOUCH, DRAG, POWER, RELEASE, FLIGHT, DONE }
const POWER_CHANGE := 0.12

var step: Step = Step.DONE
var _initial_power := 0.0
var _card: PanelContainer
var _heading: Label
var _body: Label
var _skip: Button
var _ball_position := Vector2.ZERO
var _pointer_position := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", LumaCard.panel_style(24,
		Color(Palette.INK_MID, 0.97)))
	add_child(_card)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_card.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	_heading = Label.new()
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.add_theme_font_size_override("font_size", 23)
	_heading.add_theme_color_override("font_color", Palette.ACCENT)
	_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_heading)
	_skip = LumaButton.new()
	_skip.custom_minimum_size = Vector2(130, 58)
	_skip.add_theme_font_size_override("font_size", 23)
	_skip.pressed.connect(func() -> void: finish(true))
	row.add_child(_skip)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 26)
	_body.add_theme_color_override("font_color", Palette.TEXT)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_body)
	resized.connect(_layout)
	_refresh()


func start() -> void:
	step = Step.TOUCH
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()


func is_active() -> bool:
	return step != Step.DONE


func aim_started() -> void:
	if is_active():
		step = Step.DRAG
		_refresh()


func aim_updated(valid: bool, power_ratio: float) -> void:
	if step == Step.DRAG and valid:
		_initial_power = power_ratio
		step = Step.POWER
	elif step == Step.POWER and valid and absf(power_ratio - _initial_power) >= POWER_CHANGE:
		step = Step.RELEASE
	_refresh()


func aim_cancelled() -> void:
	if is_active() and step != Step.FLIGHT:
		step = Step.TOUCH
		_refresh()


func shot_fired() -> void:
	if step == Step.RELEASE:
		finish(false)
	elif is_active():
		step = Step.FLIGHT
		_refresh()


func ball_ready() -> void:
	if step == Step.FLIGHT:
		step = Step.TOUCH
		_refresh()


func finish(skipped: bool) -> void:
	if not is_active():
		return
	step = Step.DONE
	_refresh()
	finished.emit(skipped)


func blocks_pointer(at: Vector2) -> bool:
	return is_active() and visible and _card.get_global_rect().has_point(at)


func set_markers(ball: Vector2, pointer: Vector2) -> void:
	_ball_position = ball - global_position
	_pointer_position = pointer - global_position
	queue_redraw()


func _refresh() -> void:
	visible = is_active()
	if _body == null:
		return
	_heading.text = tr("İLK ATIŞ · %d/4") % mini(int(step) + 1, 4)
	_skip.text = tr("FIRST_SHOT_SKIP")
	var keys := ["FIRST_SHOT_TOUCH", "FIRST_SHOT_DRAG", "FIRST_SHOT_POWER",
		"FIRST_SHOT_RELEASE", "FIRST_SHOT_FLIGHT", ""]
	_body.text = tr(keys[step]) if is_active() else ""
	_layout.call_deferred()
	queue_redraw()


func _layout() -> void:
	if _card == null:
		return
	var width := minf(size.x, 620.0)
	_card.size = Vector2(width, 0)
	_card.position = Vector2((size.x - width) * 0.5,
		maxf(135.0, size.y - 250.0 - _card.size.y))


func _draw() -> void:
	if not is_active() or step == Step.FLIGHT:
		return
	# Static, high-contrast shape cue also works with reduced motion / sound off.
	var center := _ball_position if step == Step.TOUCH else _pointer_position
	draw_arc(center, 43.0, 0, TAU, 48, Palette.TEXT, 3.0, true)
	if step in [Step.DRAG, Step.POWER]:
		var end := center + Vector2(0, 95)
		draw_line(center + Vector2(0, 48), end, Palette.ACCENT, 4.0, true)
		draw_line(end, end + Vector2(-12, -16), Palette.ACCENT, 4.0, true)
		draw_line(end, end + Vector2(12, -16), Palette.ACCENT, 4.0, true)
