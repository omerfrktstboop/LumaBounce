class_name NavigationCard
extends Button

## Ev ekranindaki "Bolumler"/"Magaza" kartlari: IconTile + baslik + aciklama +
## durum metni + ok (marka rehberi SS15 hiyerarsisi: Icon -> Title ->
## Supporting -> Action). LumaCard.style() ile ayni kart dilini paylasir.
##
## Tiklama VAR OLAN Button.pressed sinyali uzerinden yayilir; ozel bir sinyal
## eklemeye gerek yok, main_menu.gd zaten dogrudan .pressed.connect() kullaniyor.

@export var glyph: GlyphIcon.Glyph = GlyphIcon.Glyph.HOME
@export var title_text := "":
	set(value):
		title_text = value
		if _title != null:
			_title.text = value
@export var supporting_text := "":
	set(value):
		supporting_text = value
		if _supporting != null:
			_supporting.text = value
@export var status_text := "":
	set(value):
		status_text = value
		if _status != null:
			_status.text = value
			_status.visible = not value.is_empty()
## Alfasi 0 iken Palette.ACCENT kullanilir.
@export var accent := Color(0.0, 0.0, 0.0, 0.0)

var _title: Label
var _supporting: Label
var _status: Label


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0.0, 100.0)
	text = ""
	var live_accent := accent if accent.a > 0.0 else Palette.ACCENT
	add_theme_stylebox_override("normal", LumaCard.style(live_accent, false, 1))
	add_theme_stylebox_override("hover", LumaCard.style(live_accent, true, 1))
	add_theme_stylebox_override("pressed", LumaCard.style(live_accent, true, 2))
	add_theme_stylebox_override("focus", LumaCard.style(live_accent, false, 1))

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, UIMetrics.SPACE_LG)
	add_child(margin)

	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", UIMetrics.SPACE_LG)
	margin.add_child(line)

	var tile := IconTile.new()
	tile.glyph = glyph
	tile.icon_color = live_accent
	tile.tile_accent = live_accent
	tile.tile_size = 56.0
	tile.icon_inset = 14.0
	line.add_child(tile)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_theme_constant_override("separation", 3)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(texts)

	_title = Label.new()
	_title.text = title_text
	_title.add_theme_font_size_override("font_size", UIMetrics.FONT_CARD_TITLE + 2)
	_title.add_theme_color_override("font_color", Palette.TEXT)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(_title)

	_supporting = Label.new()
	_supporting.text = supporting_text
	_supporting.add_theme_font_size_override("font_size", UIMetrics.FONT_SUPPORTING + 1)
	_supporting.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	_supporting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_supporting.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(_supporting)

	var trailing := VBoxContainer.new()
	trailing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trailing.add_theme_constant_override("separation", 4)
	trailing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(trailing)

	_status = Label.new()
	_status.text = status_text
	_status.visible = not status_text.is_empty()
	_status.add_theme_font_size_override("font_size", UIMetrics.FONT_LABEL)
	_status.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trailing.add_child(_status)

	var chevron_slot := CenterContainer.new()
	chevron_slot.size_flags_horizontal = Control.SIZE_SHRINK_END
	chevron_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trailing.add_child(chevron_slot)

	var chevron := GlyphIcon.new()
	chevron.glyph = GlyphIcon.Glyph.CHEVRON_RIGHT
	chevron.color = Palette.TEXT_DIM
	chevron.custom_minimum_size = Vector2(24.0, 24.0)
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chevron_slot.add_child(chevron)
