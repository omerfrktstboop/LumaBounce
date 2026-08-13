class_name RetentionScreen
extends Control

## FAZ 9 meta-game ekrani. Challenge/gorev/achievement verisini kendisi
## sahiplenmez; AppRoot'un enjekte ettigi store'lari yalnizca okur ve sinyal yayar.

signal menu_requested()
signal challenge_requested()

var daily_store: DailyStore
var achievement_store: AchievementStore
var wallet: WalletStore
var progress: ProgressStore
var analytics: AnalyticsService

@onready var _back_button: LumaIconButton = $SafeArea/Content/Header/BackButton
@onready var _coin_chip: CoinChip = $SafeArea/Content/Header/CoinChip
@onready var _rows: VBoxContainer = $SafeArea/Content/Scroll/Rows


func _ready() -> void:
	if daily_store == null:
		daily_store = DailyStore.load_from_disk()
	if achievement_store == null:
		achievement_store = AchievementStore.load_from_disk()
	if wallet == null:
		wallet = WalletStore.load_from_disk()
	if progress == null:
		progress = ProgressStore.load_from_disk()
	daily_store.refresh_for_date()
	_coin_chip.bind(wallet)
	_back_button.pressed.connect(menu_requested.emit)
	_rebuild()
	if analytics != null:
		analytics.track_event(AnalyticsService.DAILY_OPEN, {
			"day_index": DailyStore.day_index(daily_store.active_date),
			"streak_bucket": _streak_bucket(daily_store.current_streak),
		})


func _rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_rows.add_child(_build_challenge_card())
	_rows.add_child(_build_streak_card())
	_rows.add_child(_build_quests_card())
	_rows.add_child(_build_achievements_card())


func _build_challenge_card() -> PanelContainer:
	var body := _card_body("GÜNLÜK CHALLENGE", Palette.ACCENT)
	var level := LevelLibrary.load_level(daily_store.challenge_level_id)
	var title := _label(tr("Günün bölümü: %s") % tr(level.display_name),
		UIMetrics.FONT_TITLE, Palette.TEXT)
	body.add_child(title)
	body.add_child(_label(daily_store.active_date, UIMetrics.FONT_LABEL, Palette.TEXT_DIM))

	var unlocked := progress.is_completed(DailyStore.CHALLENGE_UNLOCK_LEVEL)
	var claimed := daily_store.is_daily_claimed()
	var state_text := ""
	if not unlocked:
		state_text = tr("10. bölümü tamamlayınca açılır")
	elif claimed:
		state_text = tr("Bugünün ödülü alındı")
	else:
		state_text = tr("Tamamla ve +%d Luma Coin kazan") % DailyStore.DAILY_REWARD
	body.add_child(_label(state_text, UIMetrics.FONT_BODY, Palette.COIN if unlocked else Palette.TEXT_DIM))

	var button := LumaButton.new()
	button.name = "PlayDailyButton"
	button.custom_minimum_size = Vector2(0.0, UIMetrics.MIN_TOUCH)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.emphasis = LumaButton.Emphasis.PRIMARY
	button.add_theme_font_size_override("font_size", UIMetrics.FONT_BODY + 4)
	button.text = tr("TEKRAR OYNA") if claimed else tr("CHALLENGE'I OYNA")
	button.disabled = not unlocked
	button.pressed.connect(challenge_requested.emit)
	body.add_child(button)
	return body.get_parent().get_parent() as PanelContainer


func _build_streak_card() -> PanelContainer:
	var body := _card_body("STREAK", Palette.COIN)
	body.add_child(_label(
		tr("%d günlük seri · En iyi %d") % [daily_store.current_streak, daily_store.best_streak],
		UIMetrics.FONT_TITLE, Palette.TEXT))
	var milestones := HBoxContainer.new()
	milestones.add_theme_constant_override("separation", UIMetrics.SPACE_MD)
	for target in [3, 7, 14]:
		var reached: bool = daily_store.current_streak >= target
		var chip := Label.new()
		chip.text = tr("%d GÜN") % target
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.custom_minimum_size = Vector2(0.0, 54.0)
		chip.add_theme_font_size_override("font_size", UIMetrics.FONT_BODY)
		chip.add_theme_color_override("font_color", Palette.COIN_CORE if reached else Palette.TEXT_DIM)
		chip.add_theme_stylebox_override("normal", _pill_style(
			Palette.COIN if reached else Palette.SURFACE_EDGE, reached))
		milestones.add_child(chip)
	body.add_child(milestones)
	body.add_child(_label(tr("Seri günlük challenge tamamlayınca ilerler"),
		UIMetrics.FONT_SUPPORTING, Palette.TEXT_MUTED))
	return body.get_parent().get_parent() as PanelContainer


func _build_quests_card() -> PanelContainer:
	var body := _card_body("GÜNLÜK GÖREVLER", Palette.ACCENT_ALT)
	if not progress.is_completed(DailyStore.QUESTS_UNLOCK_LEVEL):
		body.add_child(_label(tr("8. bölümü tamamlayınca üç günlük görev açılır"),
			UIMetrics.FONT_BODY, Palette.TEXT_DIM))
		return body.get_parent().get_parent() as PanelContainer

	for quest_id in daily_store.quest_ids:
		var quest := DailyQuestCatalog.find(quest_id)
		if quest != null:
			body.add_child(_quest_row(quest))
	var reward_label := _label("", UIMetrics.FONT_BODY, Palette.COIN)
	if daily_store.is_all_quests_claimed():
		reward_label.text = tr("Üç görev ödülü alındı")
	elif daily_store.all_quests_complete():
		reward_label.text = tr("Tüm görevler tamamlandı · +%d Luma Coin") % DailyStore.ALL_QUESTS_REWARD
	else:
		reward_label.text = tr("Üçünü tamamla · +%d Luma Coin") % DailyStore.ALL_QUESTS_REWARD
	body.add_child(reward_label)
	return body.get_parent().get_parent() as PanelContainer


func _quest_row(quest: DailyQuestData) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 62.0)
	row.add_theme_constant_override("separation", UIMetrics.SPACE_MD)
	var check := GlyphIcon.new()
	check.glyph = GlyphIcon.Glyph.CHECK if daily_store.quest_is_complete(quest.id) \
		else GlyphIcon.Glyph.COIN
	check.color = Palette.ACCENT if daily_store.quest_is_complete(quest.id) else Palette.TEXT_DIM
	check.custom_minimum_size = Vector2(36.0, 36.0)
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(check)
	var text := _label(tr(quest.title_key), UIMetrics.FONT_BODY, Palette.TEXT)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(text)
	var value := daily_store.quest_progress_for(quest.id)
	row.add_child(_label("%d/%d" % [value, quest.target], UIMetrics.FONT_BODY,
		Palette.ACCENT if value >= quest.target else Palette.TEXT_DIM))
	return row


func _build_achievements_card() -> PanelContainer:
	var body := _card_body("BAŞARILAR", Palette.INFO)
	body.add_child(_label(tr("%d / %d başarı açıldı") % [
		achievement_store.unlocked_count(), AchievementCatalog.all().size()],
		UIMetrics.FONT_BODY, Palette.TEXT_DIM))
	for achievement in AchievementCatalog.all():
		var unlocked := achievement_store.is_unlocked(achievement.id)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var title_line := HBoxContainer.new()
		var title := _label(tr(achievement.title_key), UIMetrics.FONT_BODY,
			Palette.ACCENT if unlocked else Palette.TEXT)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_line.add_child(title)
		var progress_value := achievement_store.progress_for(achievement)
		var status := tr("AÇILDI") if unlocked else "%d/%d" % [progress_value, achievement.target]
		title_line.add_child(_label(status, UIMetrics.FONT_LABEL,
			Palette.ACCENT if unlocked else Palette.TEXT_DIM))
		row.add_child(title_line)
		row.add_child(_label(tr(achievement.description_key), UIMetrics.FONT_SUPPORTING,
			Palette.TEXT_MUTED))
		body.add_child(row)
	return body.get_parent().get_parent() as PanelContainer


## PanelContainer'i dondurmek yerine body dondurulur; cagiran kolayca cocuk
## ekler, en sonda body.get_parent() ile karti alir.
func _card_body(title: String, accent: Color) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", LumaCard.panel_style())
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, UIMetrics.CARD_PADDING)
	card.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", UIMetrics.SPACE_MD)
	margin.add_child(body)
	var header := _label(tr(title), UIMetrics.FONT_LABEL + 6, accent)
	body.add_child(header)
	return body


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _pill_style(accent: Color, active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent, 0.22 if active else 0.10)
	style.border_color = Color(accent, 0.75 if active else 0.30)
	style.set_border_width_all(1)
	style.set_corner_radius_all(UIMetrics.RADIUS_PILL)
	return style


func _streak_bucket(streak: int) -> StringName:
	if streak >= 14:
		return &"14_plus"
	if streak >= 7:
		return &"7_13"
	if streak >= 3:
		return &"3_6"
	return StringName(str(maxi(streak, 0)))
