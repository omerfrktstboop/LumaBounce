class_name ToggleSwitch
extends Button

## Gercek kayan anahtar (marka rehberi SS18: Aktif=Teal, Pasif=Slate,
## 150-200ms animasyon). Ayarlar ekranindaki eski iki-LumaButton
## "Acik"/"Kapali" ikilisinin yerini alir.
##
## Button'dan turer - projedeki her etkilesimli bilesenle (LumaButton,
## kartlar) ayni basis/dokunma davranisini bedavaya alir; kendi govdesini
## StyleBoxEmpty ile gizleyip UZERINE _draw() ile pil + top cizer.

signal value_changed(value: bool)

@export var value := false:
	set(new_value):
		if value == new_value:
			return
		value = new_value
		if is_node_ready():
			_animate_thumb()

const TRACK_SIZE := Vector2(72.0, 40.0)
const THUMB_MARGIN := 4.0
const ANIM_TIME := 0.16

var _thumb_ratio := 0.0
var _thumb_tween: Tween


func _ready() -> void:
	custom_minimum_size = TRACK_SIZE
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	text = ""
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)
	pressed.connect(_on_pressed)
	_thumb_ratio = 1.0 if value else 0.0
	queue_redraw()


func _on_pressed() -> void:
	value = not value
	value_changed.emit(value)


func _animate_thumb() -> void:
	if _thumb_tween != null and _thumb_tween.is_valid():
		_thumb_tween.kill()
	_thumb_tween = create_tween()
	_thumb_tween.tween_method(
		_set_thumb_ratio, _thumb_ratio, 1.0 if value else 0.0, ANIM_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_thumb_ratio(ratio: float) -> void:
	_thumb_ratio = ratio
	queue_redraw()


func _draw() -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Palette.SURFACE.lerp(Palette.ACCENT_DIM, _thumb_ratio)
	track.set_corner_radius_all(int(TRACK_SIZE.y * 0.5))
	track.anti_aliasing = true
	draw_style_box(track, Rect2(Vector2.ZERO, size))

	var thumb_d := TRACK_SIZE.y - THUMB_MARGIN * 2.0
	var travel := TRACK_SIZE.x - THUMB_MARGIN * 2.0 - thumb_d
	var thumb_x := THUMB_MARGIN + travel * _thumb_ratio
	draw_circle(Vector2(thumb_x + thumb_d * 0.5, size.y * 0.5), thumb_d * 0.5, Palette.TEXT)
