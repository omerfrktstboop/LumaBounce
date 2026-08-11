class_name ResultPanel
extends Control

## Bolum sonu karti - hem BASARI hem BASARISIZLIK icin AYNI bilesen.
##
## Iki ayri UI kopyasi yoktur: show_success() ve show_failure() ayni
## dugumleri farkli yapilandirir (yildiz satiri ve "sonraki bolum" butonu
## yalnizca basaride gorunur). Kart CenterContainer icinde oldugu icin
## gizlenen satirlar yer kaplamaz, kart icerige gore kuculur.
##
## Kendi basina karar vermez: metinleri ve butonlarin anlamini cagiran
## (gameplay.gd) belirler. Panel acikken tum ekran girdisini bloklar.

signal next_pressed()
signal retry_pressed()
signal revive_pressed()
## 2 Coin ile devam etme yolu. Reklamdan AYRI sinyal: ikisi farkli bedeller,
## farkli basarisizlik yollari ve farkli izinler tasir.
signal revive_coin_pressed()
signal level_select_pressed()
signal menu_pressed()

@export var scrim_color := Color(Palette.INK_TOP, 0.82)
@export var card_color := Color(Palette.SURFACE, 0.96)
@export var card_border_color := Color(Palette.SURFACE_EDGE, 1.0)
@export var card_corner_radius := 34
@export var pop_time := 0.28

@onready var _scrim: ColorRect = $Scrim
@onready var _card: PanelContainer = $CardCenter/Card
@onready var _title: Label = $CardCenter/Card/Margin/Rows/Title
@onready var _subtitle: Label = $CardCenter/Card/Margin/Rows/Subtitle
@onready var _reward_row: HBoxContainer = $CardCenter/Card/Margin/Rows/RewardRow
@onready var _reward_value: Label = $CardCenter/Card/Margin/Rows/RewardRow/Value
@onready var _reward_glyph: GlyphIcon = $CardCenter/Card/Margin/Rows/RewardRow/Glyph
@onready var _stars: StarRow = $CardCenter/Card/Margin/Rows/Stars
@onready var _stats: HBoxContainer = $CardCenter/Card/Margin/Rows/Stats
@onready var _time_value: Label = $CardCenter/Card/Margin/Rows/Stats/TimeColumn/Value
@onready var _shot_value: Label = $CardCenter/Card/Margin/Rows/Stats/ShotColumn/Value
@onready var _next_button: LumaButton = $CardCenter/Card/Margin/Rows/NextButton
@onready var _revive_button: LumaButton = $CardCenter/Card/Margin/Rows/ReviveButton
@onready var _revive_coin_button: LumaButton = $CardCenter/Card/Margin/Rows/ReviveCoinButton
@onready var _retry_button: LumaButton = $CardCenter/Card/Margin/Rows/RetryButton
@onready var _level_select_button: LumaButton = $CardCenter/Card/Margin/Rows/LevelSelectButton
@onready var _menu_button: LumaButton = $CardCenter/Card/Margin/Rows/MenuButton

var _pop_tween: Tween


func _ready() -> void:
	_scrim.color = scrim_color
	_apply_card_style()
	_reward_value.add_theme_color_override("font_color", Palette.COIN_CORE)
	_reward_glyph.color = Palette.COIN
	_reward_row.hide()
	_next_button.pressed.connect(next_pressed.emit)
	_revive_button.pressed.connect(revive_pressed.emit)
	_revive_coin_button.pressed.connect(revive_coin_pressed.emit)
	_retry_button.pressed.connect(retry_pressed.emit)
	_level_select_button.pressed.connect(level_select_pressed.emit)
	_menu_button.pressed.connect(menu_pressed.emit)
	hide_result()


## Bolum tamamlandi: yildizlar, sure/atis bilgisi ve tam navigasyon.
## [param new_record] true ise yildizlar kisa bir pop ile belirir.
func show_success(title_text: String, next_text: String, retry_text: String,
		stars: int, seconds: float, shots: int, new_record: bool,
		reward_coins := 0) -> void:
	_title.text = title_text
	_subtitle.hide()
	# Odul METIN degil, SAYI + SIMGE: "+1 LUMA COIN" cumlesi her bolum
	# sonunda para biriminin adini tekrarliyordu. Simge zaten neyin
	# kazanildigini soyluyor ve her dilde ayni.
	_reward_row.visible = reward_coins > 0
	_reward_value.text = "+%d" % reward_coins

	_stars.show()
	if new_record:
		_stars.play_reveal(stars)
	else:
		_stars.set_stars(stars)

	_stats.show()
	# tr() BICIMLENDIRMEDEN ONCE: Control'un otomatik cevirisi hazir metni
	# arar, "12.4 sn" tabloda yoktur. Cevrilmesi gereken kaliptir.
	_time_value.text = tr("%.1f sn") % seconds
	_shot_value.text = str(shots)

	_next_button.text = next_text
	_next_button.show()
	_revive_button.hide()
	_revive_coin_button.hide()
	_retry_button.text = retry_text
	_open()


## Top hakki bitti: yildiz YOK (bolum tamamlanmadi), sonraki bolum YOK.
func show_failure(title_text: String, subtitle_text: String, retry_text: String,
		seconds: float, shots: int) -> void:
	_title.text = title_text
	_subtitle.text = subtitle_text
	_subtitle.show()
	_reward_row.hide()

	_stars.hide()

	_stats.show()
	_time_value.text = tr("%.1f sn") % seconds
	_shot_value.text = str(shots)

	_next_button.hide()
	_revive_button.visible = is_revive_offer_eligible()
	_revive_button.disabled = false
	_revive_coin_button.visible = is_revive_coin_offer_eligible()
	_revive_coin_button.disabled = false
	_retry_button.text = retry_text
	_open()


func hide_result() -> void:
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	hide()
	modulate.a = 1.0
	_card.scale = Vector2.ONE


## Faz 2 hook'lari UI cizmez ve reklam baslatmaz. Sonraki faz bu durumlari
## istege bagli buton/akislara baglarken ResultPanel SDK sinifi tanimaz.
func set_revive_offer_eligible(eligible: bool) -> void:
	set_meta(&"revive_offer_eligible", eligible)
	if is_node_ready():
		_revive_button.visible = eligible
		_revive_button.disabled = false


func is_revive_offer_eligible() -> bool:
	return bool(get_meta(&"revive_offer_eligible", false))


## 2 Coin yolu. Fiyat PARAMETREDIR, panelde yazili degil: bedel Gameplay'in
## ayarindan gelir ve denge degisirse burasi degismez.
func set_revive_coin_offer(eligible: bool, cost: int) -> void:
	set_meta(&"revive_coin_offer_eligible", eligible)
	if not is_node_ready():
		return
	_revive_coin_button.visible = eligible
	_revive_coin_button.disabled = false
	_revive_coin_button.text = tr("%d COIN · +1 TOP") % cost


func is_revive_coin_offer_eligible() -> bool:
	return bool(get_meta(&"revive_coin_offer_eligible", false))


func set_revive_offer_busy(busy: bool) -> void:
	if is_node_ready():
		_revive_button.disabled = busy
		# Coin yolu da kilitlenir: reklam yuklenirken Coin harcanmasi, iki
		# ayri yoldan ayni tek topu iki kez odemek olurdu.
		_revive_coin_button.disabled = busy


func set_interstitial_candidate(candidate: bool) -> void:
	set_meta(&"interstitial_candidate", candidate)


func is_interstitial_candidate() -> bool:
	return bool(get_meta(&"interstitial_candidate", false))


func _open() -> void:
	show()
	# Kart icerige gore kuculup buyudugu icin pivot her acilista guncellenir.
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


func _apply_card_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = card_color
	style.border_color = card_border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(card_corner_radius)
	style.corner_detail = 12
	style.anti_aliasing = true
	_card.add_theme_stylebox_override("panel", style)
