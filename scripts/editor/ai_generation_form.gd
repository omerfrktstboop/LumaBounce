class_name AIGenerationForm
extends VBoxContainer

## Mobil debug editor icindeki iki modlu uretim formu. Ag/network isi yapmaz;
## yalnizca dogrulanmis kullanici secimlerini sinyal olarak coordinator'a verir.

signal local_generation_requested(profile_name: String)
signal local_settings_saved(settings: Dictionary)
signal ai_generation_requested(request: Dictionary)
signal cancel_requested
signal validation_failed(message: String)
signal status_message(message: String)

const TEMPLATE_OPTIONS := [
	["Otomatik", "auto"], ["Ogretici", "tutorial"],
	["Tek Sekme", "single_bounce"], ["Duvar Sekmesi", "wall_bounce"],
	["Zikzak", "zigzag"], ["Dar Gecit", "narrow_passage"],
	["Ters Rota", "reverse_route"], ["Iki Alternatif Rota", "two_routes"],
	["Bloklu Guvenli Rota", "safe_block_route"],
	["Bloksuz Ustalik Rotasi", "block_free_mastery"],
	["Cok Atisli Ilerleme", "multi_shot"],
	["Sekme Zinciri", "ricochet_chain"], ["Blok Koridoru", "block_corridor"],
	["Hareketli Parkur", "kinetic_course"],
	["Mini Final", "mini_final"],
]
const DIFFICULTY_OPTIONS := [
	["Kolay", "easy"], ["Orta", "medium"], ["Zor", "hard"], ["Final", "final"],
]

var _settings := AIGeneratorSettings.new()
var _local_page: VBoxContainer
var _ai_page: VBoxContainer
var _local_mode_button: LumaButton
var _ai_mode_button: LumaButton
var _api_key: LineEdit
var _model: LineEdit
var _remember: CheckBox
var _template: OptionButton
var _difficulty: OptionButton
var _mechanics := {}
var _design_note: TextEdit
var _candidate_count: SpinBox
var _blueprint_count: SpinBox
var _variation_count: SpinBox
var _generate_button: LumaButton
var _cancel_button: LumaButton
var _local_cancel_button: LumaButton
var _local_mechanics := {}
var _local_score_min: SpinBox
var _local_score_max: SpinBox
var _interactive: Array[Control] = []
var _busy := false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	_build_mode_row()
	_build_local_page()
	_build_ai_page()
	_load_settings()
	_show_ai(false)


func set_busy(value: bool) -> void:
	_busy = value
	for control in _interactive:
		if not is_instance_valid(control):
			continue
		if control is BaseButton:
			(control as BaseButton).disabled = value
		elif control is LineEdit:
			(control as LineEdit).editable = not value
		elif control is TextEdit:
			(control as TextEdit).editable = not value
		elif control is SpinBox:
			(control as SpinBox).editable = not value
	_cancel_button.visible = value
	_cancel_button.disabled = false
	_local_cancel_button.visible = value
	_local_cancel_button.disabled = false


func is_busy() -> bool:
	return _busy


func show_ai_mode() -> void:
	_show_ai(true)


func _build_mode_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_local_mode_button = _button("YEREL", _show_ai.bind(false), true)
	_ai_mode_button = _button("OPENROUTER AI", _show_ai.bind(true), true)
	_local_mode_button.name = "LocalMode"
	_ai_mode_button.name = "OpenRouterMode"
	row.add_child(_local_mode_button)
	row.add_child(_ai_mode_button)
	_interactive.append_array([_local_mode_button, _ai_mode_button])


func _build_local_page() -> void:
	_local_page = VBoxContainer.new()
	_local_page.name = "LocalPage"
	_local_page.add_theme_constant_override("separation", 10)
	add_child(_local_page)
	var hint := _label("Mevcut fizik filtreli yerel uretim")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_local_page.add_child(hint)
	var preset_grid := GridContainer.new()
	preset_grid.name = "PresetGrid"
	preset_grid.columns = 2
	preset_grid.add_theme_constant_override("h_separation", 8)
	preset_grid.add_theme_constant_override("v_separation", 8)
	_local_page.add_child(preset_grid)
	for option in [
			["Kolay", "easy"], ["Orta", "medium"], ["Zor", "hard"],
			["Bloklu", "blocks"], ["Engelli", "obstacles"]]:
		var button := _button(option[0], local_generation_requested.emit.bind(option[1]), true)
		preset_grid.add_child(button)
		_interactive.append(button)

	_local_page.add_child(_field_label("KAYITLI HIZLI ÜRET AYARI"))
	var mechanics_grid := GridContainer.new()
	mechanics_grid.name = "LocalMechanics"
	mechanics_grid.columns = 2
	mechanics_grid.add_theme_constant_override("h_separation", 8)
	mechanics_grid.add_theme_constant_override("v_separation", 4)
	_local_page.add_child(mechanics_grid)
	for definition in [
			["Panel", "panel"], ["Duvar boşluğu", "wall_gap"],
			["Kırılabilir blok", "breakable_block"], ["Metal halka", "metal_ring"],
			["Bomba", "bomb"], ["Dönen çark", "rotating_wheel"],
			["Kayan engel", "moving_bar"], ["Lazer", "pulse_laser"]]:
		var check := CheckBox.new()
		check.name = "Local_%s" % definition[1]
		check.text = definition[0]
		check.custom_minimum_size = Vector2(0, 52)
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mechanics_grid.add_child(check)
		_local_mechanics[definition[1]] = check
		_interactive.append(check)

	_local_score_min = _spin_field_on(
		_local_page, "MİNİMUM ZORLUK SKORU", 0, 100, 20)
	_local_score_min.name = "LocalScoreMin"
	_local_score_max = _spin_field_on(
		_local_page, "MAKSİMUM ZORLUK SKORU", 0, 100, 60)
	_local_score_max.name = "LocalScoreMax"
	var save_local := _button("AYARI KAYDET", _on_save_local_settings)
	save_local.name = "SaveLocalSettings"
	save_local.emphasis = LumaButton.Emphasis.PRIMARY
	_local_page.add_child(save_local)
	_interactive.append(save_local)
	_local_cancel_button = _button("IPTAL", cancel_requested.emit)
	_local_cancel_button.name = "CancelLocal"
	_local_cancel_button.visible = false
	_local_page.add_child(_local_cancel_button)


func _build_ai_page() -> void:
	_ai_page = VBoxContainer.new()
	_ai_page.name = "AIPage"
	_ai_page.add_theme_constant_override("separation", 10)
	add_child(_ai_page)

	_ai_page.add_child(_field_label("API KEY"))
	_api_key = LineEdit.new()
	_api_key.name = "APIKey"
	_api_key.secret = true
	_api_key.placeholder_text = "sk-or-..."
	_prepare_text_input(_api_key)
	_ai_page.add_child(_api_key)
	var paste_api_key := _button("YAPISTIR", _paste_from_clipboard.bind("api_key"), true)
	paste_api_key.name = "PasteAPIKey"
	_ai_page.add_child(paste_api_key)
	_interactive.append(paste_api_key)

	var remember_row := HBoxContainer.new()
	remember_row.add_theme_constant_override("separation", 8)
	_ai_page.add_child(remember_row)
	_remember = CheckBox.new()
	_remember.name = "RememberKey"
	_remember.text = "BU CIHAZDA HATIRLA"
	_remember.custom_minimum_size = Vector2(0, 56)
	_remember.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remember_row.add_child(_remember)
	var clear_button := _button("ANAHTARI TEMIZLE", _on_clear_key)
	clear_button.custom_minimum_size.x = 210
	remember_row.add_child(clear_button)
	_interactive.append_array([_remember, clear_button])

	_ai_page.add_child(_field_label("MODEL"))
	_model = LineEdit.new()
	_model.name = "ModelSlug"
	_model.placeholder_text = "provider/model-slug"
	_prepare_text_input(_model)
	_ai_page.add_child(_model)
	var model_actions := HBoxContainer.new()
	model_actions.add_theme_constant_override("separation", 8)
	_ai_page.add_child(model_actions)
	var paste_model := _button("YAPISTIR", _paste_from_clipboard.bind("model"), true)
	paste_model.name = "PasteModel"
	model_actions.add_child(paste_model)
	var copy_model := _button("KOPYALA", _copy_to_clipboard.bind("model"), true)
	copy_model.name = "CopyModel"
	model_actions.add_child(copy_model)
	_interactive.append_array([paste_model, copy_model])

	_template = _option_field("SABLON", TEMPLATE_OPTIONS)
	_difficulty = _option_field("ZORLUK", DIFFICULTY_OPTIONS)

	_ai_page.add_child(_field_label("MEKANIKLER"))
	var mechanics_row := GridContainer.new()
	mechanics_row.columns = 2
	mechanics_row.add_theme_constant_override("separation", 6)
	_ai_page.add_child(mechanics_row)
	for definition in [
			["Panel", "panel"], ["Duvar boslugu", "wall_gap"],
			["Kirilabilir blok", "breakable_block"], ["Metal halka", "metal_ring"],
			["Bomba", "bomb"], ["Donen cark", "rotating_wheel"],
			["Kayan engel", "moving_bar"]]:
		var check := CheckBox.new()
		check.text = definition[0]
		check.custom_minimum_size = Vector2(0, 54)
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mechanics_row.add_child(check)
		_mechanics[definition[1]] = check
		_interactive.append(check)
	_template.item_selected.connect(_on_template_selected)

	_ai_page.add_child(_field_label("TASARIM NOTU"))
	_design_note = TextEdit.new()
	_design_note.name = "DesignNote"
	_design_note.custom_minimum_size = Vector2(0, 126)
	_design_note.placeholder_text = "Rota, blok katkisi ve okunabilirlik hedefini yaz."
	_design_note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_ai_page.add_child(_design_note)
	_watch_focus(_design_note)
	_interactive.append(_design_note)
	var note_actions := HBoxContainer.new()
	note_actions.add_theme_constant_override("separation", 8)
	_ai_page.add_child(note_actions)
	var paste_note := _button("YAPISTIR", _paste_from_clipboard.bind("design_note"), true)
	paste_note.name = "PasteDesignNote"
	note_actions.add_child(paste_note)
	var copy_note := _button("KOPYALA", _copy_to_clipboard.bind("design_note"), true)
	copy_note.name = "CopyDesignNote"
	note_actions.add_child(copy_note)
	_interactive.append_array([paste_note, copy_note])

	_candidate_count = _spin_field("ISTENEN ADAY", 1, 20, 10)
	_blueprint_count = _spin_field("AI TASLAK SAYISI", 1, 10, 5)
	_variation_count = _spin_field("TASLAK BASINA VARYASYON", 1, 30, 12)

	_generate_button = _button("AI ILE URET", _on_generate_ai)
	_generate_button.name = "GenerateAI"
	_generate_button.emphasis = LumaButton.Emphasis.PRIMARY
	_ai_page.add_child(_generate_button)
	_interactive.append(_generate_button)
	_cancel_button = _button("IPTAL", cancel_requested.emit)
	_cancel_button.name = "Cancel"
	_cancel_button.visible = false
	_ai_page.add_child(_cancel_button)


func _option_field(title: String, options: Array) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_ai_page.add_child(row)
	var title_label := _field_label(title)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(300, 58)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for definition in options:
		option.add_item(definition[0])
		option.set_item_metadata(option.item_count - 1, definition[1])
	row.add_child(option)
	_interactive.append(option)
	return option


func _spin_field(title: String, minimum: float, maximum: float, initial: float) -> SpinBox:
	return _spin_field_on(_ai_page, title, minimum, maximum, initial)


func _spin_field_on(parent: Control, title: String, minimum: float,
		maximum: float, initial: float) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var title_label := _field_label(title)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value = initial
	spin.custom_minimum_size = Vector2(180, 58)
	row.add_child(spin)
	_watch_focus(spin.get_line_edit())
	_interactive.append(spin)
	return spin


func _prepare_text_input(input: LineEdit) -> void:
	input.custom_minimum_size = Vector2(0, 58)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_theme_font_size_override("font_size", 21)
	_watch_focus(input)
	_interactive.append(input)


func _button(caption: String, action: Callable, expand := false) -> LumaButton:
	var button := LumaButton.new()
	button.text = caption
	button.custom_minimum_size = Vector2(0, 58)
	button.corner_radius = 14
	button.content_margin = Vector2(8, 6)
	button.add_theme_font_size_override("font_size", 20)
	if expand:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	return button


func _label(caption: String) -> Label:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	label.add_theme_font_size_override("font_size", 19)
	return label


func _field_label(caption: String) -> Label:
	var label := _label(caption)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _show_ai(enabled: bool) -> void:
	if _busy:
		return
	_local_page.visible = not enabled
	_ai_page.visible = enabled
	_local_mode_button.emphasis = (
		LumaButton.Emphasis.SECONDARY if enabled else LumaButton.Emphasis.PRIMARY)
	_ai_mode_button.emphasis = (
		LumaButton.Emphasis.PRIMARY if enabled else LumaButton.Emphasis.SECONDARY)


func _load_settings() -> void:
	var values := _settings.load_values()
	for mechanic_id in _local_mechanics:
		(_local_mechanics[mechanic_id] as CheckBox).button_pressed = (
			values["local_mechanics"].has(mechanic_id))
	_local_score_min.value = int(values["local_score_min"])
	_local_score_max.value = int(values["local_score_max"])
	_model.text = String(values["model_slug"])
	_remember.button_pressed = bool(values["remember_api_key"])
	_api_key.text = String(values["api_key"]) if _remember.button_pressed else ""
	_select_metadata(_template, String(values["template"]))
	_select_metadata(_difficulty, String(values["difficulty"]))
	for mechanic_id in _mechanics:
		(_mechanics[mechanic_id] as CheckBox).button_pressed = values["mechanics"].has(mechanic_id)
	_apply_template_requirements()
	_design_note.text = String(values["design_note"])
	_candidate_count.value = int(values["candidate_count"])
	_blueprint_count.value = int(values["blueprint_count"])
	_variation_count.value = int(values["variation_count"])


func _on_generate_ai() -> void:
	var request := get_request()
	if String(request["api_key"]).strip_edges().is_empty():
		validation_failed.emit("API anahtari gerekli.")
		return
	if String(request["model_slug"]).strip_edges().is_empty():
		validation_failed.emit("Model slug'i gerekli.")
		return
	_settings.save_values(request, String(request["api_key"]))
	ai_generation_requested.emit(request)


func get_local_settings() -> Dictionary:
	var mechanics := PackedStringArray()
	for mechanic_id in _local_mechanics:
		if (_local_mechanics[mechanic_id] as CheckBox).button_pressed:
			mechanics.append(mechanic_id)
	if mechanics.is_empty():
		mechanics.append("panel")
	var score_min := roundi(_local_score_min.value)
	var score_max := roundi(_local_score_max.value)
	if score_min > score_max:
		var swap := score_min
		score_min = score_max
		score_max = swap
		_local_score_min.value = score_min
		_local_score_max.value = score_max
	return {
		"local_mechanics": mechanics,
		"local_score_min": score_min,
		"local_score_max": score_max,
	}


func _on_save_local_settings() -> void:
	var local_settings := get_local_settings()
	var values := _settings.load_values()
	for key in local_settings:
		values[key] = local_settings[key]
	var error := _settings.save_values(values, String(values.get("api_key", "")))
	if error != OK:
		validation_failed.emit("Yerel üretim ayarı kaydedilemedi: %s" % error_string(error))
		return
	local_settings_saved.emit(local_settings)
	status_message.emit("Hızlı üretim ayarı kaydedildi.")


func _on_template_selected(_index: int) -> void:
	_apply_template_requirements()


func _apply_template_requirements() -> void:
	if _template == null or _mechanics.is_empty():
		return
	var template_id := String(_template.get_item_metadata(_template.selected))
	if template_id == "ricochet_chain":
		(_mechanics["panel"] as CheckBox).button_pressed = true
	elif template_id == "block_corridor":
		(_mechanics["breakable_block"] as CheckBox).button_pressed = true
	elif template_id == "kinetic_course":
		(_mechanics["rotating_wheel"] as CheckBox).button_pressed = true
		(_mechanics["moving_bar"] as CheckBox).button_pressed = true


func get_request() -> Dictionary:
	_apply_template_requirements()
	var mechanics := PackedStringArray()
	for mechanic_id in _mechanics:
		if (_mechanics[mechanic_id] as CheckBox).button_pressed:
			mechanics.append(mechanic_id)
	if mechanics.is_empty():
		mechanics.append("panel")
	return {
		"api_key": _api_key.text,
		"model_slug": _model.text.strip_edges(),
		"remember_api_key": _remember.button_pressed,
		"template": String(_template.get_item_metadata(_template.selected)),
		"difficulty": String(_difficulty.get_item_metadata(_difficulty.selected)),
		"mechanics": mechanics,
		"design_note": _design_note.text.left(AILevelContract.MAX_DESIGN_NOTE),
		"candidate_count": roundi(_candidate_count.value),
		"blueprint_count": roundi(_blueprint_count.value),
		"variation_count": roundi(_variation_count.value),
	}


func _on_clear_key() -> void:
	_api_key.clear()
	_remember.button_pressed = false
	_settings.clear_api_key()
	status_message.emit("Kayitli API anahtari temizlendi.")


func _paste_from_clipboard(target: String) -> void:
	_apply_paste(target, DisplayServer.clipboard_get())


func _apply_paste(target: String, clipboard_text: String) -> void:
	if clipboard_text.is_empty():
		status_message.emit("Pano bos.")
		return
	match target:
		"api_key":
			var api_key := _single_line_clipboard_text(clipboard_text)
			if api_key.is_empty():
				status_message.emit("Panoda gecerli bir API anahtari yok.")
				return
			_api_key.text = api_key
			_api_key.caret_column = api_key.length()
			_api_key.grab_focus()
			status_message.emit("API anahtari panodan yapistirildi.")
		"model":
			var model_slug := _single_line_clipboard_text(clipboard_text)
			if model_slug.is_empty():
				status_message.emit("Panoda gecerli bir model slug'i yok.")
				return
			_model.text = model_slug
			_model.caret_column = model_slug.length()
			_model.grab_focus()
			status_message.emit("Model slug'i panodan yapistirildi.")
		"design_note":
			_design_note.insert_text_at_caret(clipboard_text)
			if _design_note.text.length() > AILevelContract.MAX_DESIGN_NOTE:
				_design_note.text = _design_note.text.left(AILevelContract.MAX_DESIGN_NOTE)
			_design_note.grab_focus()
			status_message.emit("Tasarim notu panodan yapistirildi.")


func _copy_to_clipboard(target: String) -> void:
	var clipboard_text := ""
	var description := ""
	match target:
		"model":
			clipboard_text = _model.text
			description = "Model slug'i"
		"design_note":
			clipboard_text = _design_note.text
			description = "Tasarim notu"
	if clipboard_text.is_empty():
		status_message.emit("Kopyalanacak metin yok.")
		return
	DisplayServer.clipboard_set(clipboard_text)
	status_message.emit("%s panoya kopyalandi." % description)


func _single_line_clipboard_text(value: String) -> String:
	return value.replace("\r", "").replace("\n", "").strip_edges()


func _select_metadata(option: OptionButton, wanted: String) -> void:
	for i in option.item_count:
		if String(option.get_item_metadata(i)) == wanted:
			option.select(i)
			return


func _watch_focus(control: Control) -> void:
	control.focus_entered.connect(_ensure_visible.bind(control))


func _ensure_visible(control: Control) -> void:
	await get_tree().process_frame
	var ancestor := get_parent()
	while ancestor != null:
		var scroll := ancestor as ScrollContainer
		if scroll != null:
			scroll.ensure_control_visible(control)
			return
		ancestor = ancestor.get_parent()
