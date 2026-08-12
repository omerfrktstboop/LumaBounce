class_name SegmentedControl
extends HBoxContainer

## Paylasilan sekme/secim denetimi (marka rehberi SS20). Magaza'nin kategori
## sekmeleri VE Ayarlar'in dil/sarsinti secim satirlari ayni bilesenden
## kurulur - oncesinde settings_screen.gd::_add_choice_row bu deseni kendi
## icinde tekrar uretiyordu.
##
## [method setup] her cagrildiginda onceki dugumleri atip yeniden kurar -
## cagiranlarin (Ayarlar'in _rebuild'i, Magaza'nin _rebuild'i) zaten
## uyguladigi "tam yeniden kurulum" desenine uyar.

signal value_changed(index: int)

var _buttons: Array[Button] = []
var _selected := 0


func setup(labels: Array, selected_index := 0, accent := Color(0.0, 0.0, 0.0, 0.0)) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	_selected = clampi(selected_index, 0, maxi(labels.size() - 1, 0))
	var live_accent := accent if accent.a > 0.0 else Palette.ACCENT
	add_theme_constant_override("separation", UIMetrics.SPACE_SM)

	for i in labels.size():
		var index := i
		var button := LumaButton.new()
		button.text = String(labels[i])
		button.emphasis = (
			LumaButton.Emphasis.PRIMARY if i == _selected else LumaButton.Emphasis.SECONDARY)
		button.accent_override = live_accent
		button.corner_radius = UIMetrics.RADIUS_MD
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0.0, UIMetrics.MIN_TOUCH)
		button.add_theme_font_size_override("font_size", UIMetrics.FONT_BODY + 1)
		button.pressed.connect(_on_option_pressed.bind(index))
		add_child(button)
		_buttons.append(button)


func selected() -> int:
	return _selected


func _on_option_pressed(index: int) -> void:
	if index == _selected:
		return
	_selected = index
	for i in _buttons.size():
		_buttons[i].emphasis = (
			LumaButton.Emphasis.PRIMARY if i == index else LumaButton.Emphasis.SECONDARY)
	value_changed.emit(index)
