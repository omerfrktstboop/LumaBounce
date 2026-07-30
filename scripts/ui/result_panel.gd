class_name ResultPanel
extends Control

## Bolum tamamlaninca acilan sade sonuc karti.
##
## Kendi basina karar vermez: hangi metinlerin gosterilecegini ve butonlarin
## ne anlama geldigini cagiran (gameplay.gd) belirler.

signal next_pressed()
signal retry_pressed()
signal menu_pressed()

@export var scrim_color := Color(Palette.INK_TOP, 0.82)
@export var card_color := Color(Palette.SURFACE, 0.96)
@export var card_border_color := Color(Palette.SURFACE_EDGE, 1.0)
@export var card_corner_radius := 34
@export var pop_time := 0.28

@onready var _scrim: ColorRect = $Scrim
@onready var _card: PanelContainer = $Card
@onready var _title: Label = $Card/Margin/Rows/Title
@onready var _next_button: LumaButton = $Card/Margin/Rows/NextButton
@onready var _retry_button: LumaButton = $Card/Margin/Rows/RetryButton
@onready var _menu_button: LumaButton = $Card/Margin/Rows/MenuButton

var _pop_tween: Tween


func _ready() -> void:
	_scrim.color = scrim_color
	_apply_card_style()
	_next_button.pressed.connect(next_pressed.emit)
	_retry_button.pressed.connect(retry_pressed.emit)
	_menu_button.pressed.connect(menu_pressed.emit)
	hide_result()


func show_result(title_text: String, next_text: String) -> void:
	_title.text = title_text
	_next_button.text = next_text

	show()
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.86, 0.86)
	modulate.a = 0.0

	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.set_parallel(true)
	_pop_tween.tween_property(_card, "scale", Vector2.ONE, pop_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(self, "modulate:a", 1.0, pop_time * 0.7)


func hide_result() -> void:
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	hide()
	modulate.a = 1.0
	_card.scale = Vector2.ONE


func _apply_card_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = card_color
	style.border_color = card_border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(card_corner_radius)
	style.corner_detail = 12
	style.anti_aliasing = true
	_card.add_theme_stylebox_override("panel", style)
