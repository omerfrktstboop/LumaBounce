class_name PauseCard
extends Control

## DURAKLAT karti: oyunu durdurur ve cikis yollarini tek yerde toplar.
##
## NEDEN VAR: ust seritte "ana menu" ve "tekrar basla" ayri ayri duruyordu.
## Ikisi de GERI ALINAMAZ eylemlerdi (bolumu terk et / atisi sifirla) ve
## oynanis sirasinda tek dokunusla erisilebiliyorlardi - yanlislikla basmak
## bir denemeyi bitiriyordu. Simdi ikisi de duraklatmanin arkasinda.
##
## Kart KARAR VERMEZ, yalnizca secenekleri sunar ve sinyal yayar; oyunun
## gercekten durdurulmasi ve navigasyon Gameplay/AppRoot'un isidir.
##
## process_mode = ALWAYS: agac duraklatildiginda bile bu kartin butonlari
## calismali, yoksa oyuncu duraklattigi oyundan cikamazdi.

signal resume_requested()
signal restart_requested()
signal level_select_requested()
signal menu_requested()

@export var card_corner_radius := 30
@export var pop_time := 0.22
@export var row_height := 78.0
@export var row_corner_radius := 20

@onready var _card: PanelContainer = $CardCenter/Card
@onready var _title: Label = $CardCenter/Card/Margin/Rows/Title
@onready var _actions: VBoxContainer = $CardCenter/Card/Margin/Rows/Actions

var _pop_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_style()
	hide()


func open() -> void:
	if visible:
		return
	_title.text = tr("DURAKLATILDI")
	_build_actions()
	show()
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.9, 0.9)
	modulate.a = 0.0
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.set_parallel(true)
	_pop_tween.tween_property(_card, "scale", Vector2.ONE, pop_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(self, "modulate:a", 1.0, pop_time * 0.75)


func close() -> void:
	if not visible:
		return
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	hide()
	modulate.a = 1.0
	_card.scale = Vector2.ONE


func is_open() -> bool:
	return visible


func _build_actions() -> void:
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()

	# DEVAM ET vurgulu ve en ustte: duraklatan oyuncunun en cok istedigi sey
	# geri donmektir; cikis yollari onun altinda ve daha sessiz durur.
	_actions.add_child(_make_row("ResumeButton", tr("DEVAM ET"),
		Palette.ACCENT, true, resume_requested))
	_actions.add_child(_make_row("RestartButton", tr("TEKRAR BAŞLA"),
		Palette.ACCENT_ALT, false, restart_requested))
	_actions.add_child(_make_row("LevelSelectButton", tr("BÖLÜM SEÇİMİ"),
		Palette.TEXT_DIM, false, level_select_requested))
	_actions.add_child(_make_row("MenuButton", tr("ANA MENÜ"),
		Palette.TEXT_DIM, false, menu_requested))


func _make_row(node_name: String, text: String, accent: Color, primary: bool,
		target: Signal) -> Button:
	var row := Button.new()
	row.name = node_name
	row.text = text
	row.custom_minimum_size = Vector2(0.0, row_height)
	row.focus_mode = Control.FOCUS_NONE
	row.add_theme_font_size_override("font_size", 24)
	row.add_theme_color_override("font_color", Palette.TEXT if primary else Palette.TEXT_DIM)
	row.add_theme_color_override("font_hover_color", Palette.TEXT)
	row.add_theme_stylebox_override("normal", _row_style(accent, primary, 2))
	row.add_theme_stylebox_override("hover", _row_style(accent, true, 2))
	row.add_theme_stylebox_override("pressed", _row_style(accent, true, 3))
	row.pressed.connect(target.emit)
	return row


func _row_style(accent: Color, strong: bool, border: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.INK_MID, 0.94 if strong else 0.82)
	style.border_color = Color(accent, 0.75 if strong else 0.3)
	style.set_border_width_all(border)
	style.set_corner_radius_all(row_corner_radius)
	style.corner_detail = 10
	style.anti_aliasing = true
	return style


func _apply_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.SURFACE, 0.98)
	style.border_color = Color(Palette.ACCENT, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(card_corner_radius)
	style.corner_detail = 12
	style.anti_aliasing = true
	_card.add_theme_stylebox_override("panel", style)
	_title.add_theme_color_override("font_color", Palette.TEXT)
