class_name HintPurchaseCard
extends Control

## Luma Coin harcamasi geri alinamadigi icin tek dokunusta gerceklesmez.
## Bu modal maliyeti ve mevcut bakiyeyi gosterir; harcama kararini Gameplay,
## kalici yazmayi WalletStore yapar.

signal purchase_requested()
signal dismissed()

@export var card_corner_radius := 30
@export var pop_time := 0.24

@onready var _card: PanelContainer = $CardCenter/Card
@onready var _kicker: Label = $CardCenter/Card/Margin/Rows/Kicker
@onready var _title: Label = $CardCenter/Card/Margin/Rows/Title
@onready var _description: Label = $CardCenter/Card/Margin/Rows/Description
@onready var _balance: Label = $CardCenter/Card/Margin/Rows/Balance
@onready var _cancel_button: LumaButton = $CardCenter/Card/Margin/Rows/Buttons/CancelButton
@onready var _confirm_button: LumaButton = $CardCenter/Card/Margin/Rows/Buttons/ConfirmButton

var _pop_tween: Tween


func _ready() -> void:
	_apply_style()
	_cancel_button.pressed.connect(close)
	_confirm_button.pressed.connect(purchase_requested.emit)
	hide()


func show_purchase(cost: int, current_balance: int) -> void:
	_kicker.text = tr("LUMA COIN")
	_title.text = tr("Ä°PUCUYU AÃ‡")
	_description.text = tr("Bu bÃ¶lÃ¼mÃ¼n Ã¶rnek atÄ±ÅŸ rotasÄ±nÄ± gÃ¶sterir. Ä°pucu bu bÃ¶lÃ¼m iÃ§in kalÄ±cÄ± aÃ§Ä±lÄ±r.")
	_balance.text = tr("BAKÄ°YE: %d LUMA COIN") % current_balance
	_confirm_button.text = tr("%d LUMA COIN Ä°LE AÃ‡") % cost
	_confirm_button.disabled = false
	_confirm_button.show()
	_cancel_button.text = tr("VAZGEÃ‡")
	_open()


func show_insufficient(current_balance: int) -> void:
	_kicker.text = tr("LUMA COIN")
	_title.text = tr("BAKÄ°YE YETERSÄ°Z")
	_description.text = tr("Yeni bÃ¶lÃ¼mleri ilk kez tamamlayarak Luma Coin kazanabilirsin.")
	_balance.text = tr("BAKÄ°YE: %d LUMA COIN") % current_balance
	_confirm_button.hide()
	_cancel_button.text = tr("KAPAT")
	_open()


func is_open() -> bool:
	return visible


func close() -> void:
	if not visible:
		return
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	hide()
	modulate.a = 1.0
	_card.scale = Vector2.ONE
	dismissed.emit()


func _open() -> void:
	show()
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.88, 0.88)
	modulate.a = 0.0
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.set_parallel(true)
	_pop_tween.tween_property(_card, "scale", Vector2.ONE, pop_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(self, "modulate:a", 1.0, pop_time * 0.75)


func _apply_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.SURFACE, 0.98)
	style.border_color = Color(Palette.ACCENT, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(card_corner_radius)
	style.corner_detail = 12
	style.anti_aliasing = true
	_card.add_theme_stylebox_override("panel", style)
	_kicker.add_theme_color_override("font_color", Palette.ACCENT)
	_title.add_theme_color_override("font_color", Palette.TEXT)
	_description.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_balance.add_theme_color_override("font_color", Palette.ACCENT_CORE)
