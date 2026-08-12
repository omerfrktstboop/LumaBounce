class_name LumaCard
extends RefCounted

## FAZ 9 paylasilan kart StyleBox ureticisi.
##
## Ev/Magaza/Ayarlar ekranlarindaki kart gorunumunu TEK yerden uretir.
## Oncesinde ayni sekil UC ayri yerde (shop_screen.gd::_card_style,
## pause_card.gd, mechanic_intro_card.gd) farkli yaricap (20/30/18) ve farkli
## zeminle (INK_MID vs SURFACE) tekrar tekrar yaziliyordu.
##
## pause_card.gd ve mechanic_intro_card.gd kapsam disinda birakildi (Faz 9
## yalnizca Ev/Magaza/Ayarlar'i kapsiyor); onlari da bu bilesene tasimak
## ileride yapilabilecek ayri bir temizlik.


## Etkilesimli kart (Button uzerine StyleBoxFlat override). [param selected]
## kenari belirginlestirir - "secili"/"basili" gorunumu icin.
static func style(accent: Color, selected := false, border_width := 2,
		radius := UIMetrics.RADIUS_CARD) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.INK_MID, 0.92)
	box.border_color = Color(accent, 0.85 if selected else 0.24)
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.corner_detail = 10
	box.anti_aliasing = true
	return box


## Sabit (etkilesimsiz) kart zemini - PanelContainer'lar icin (Ayarlar'daki
## bolum kartlari, Ev'deki hero karti).
static func panel_style(radius := UIMetrics.RADIUS_CARD,
		fill := Color(0.0, 0.0, 0.0, 0.0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill if fill.a > 0.0 else Color(Palette.SURFACE, 0.55)
	box.border_color = Color(Palette.SURFACE_EDGE, 0.5)
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.corner_detail = 10
	box.anti_aliasing = true
	return box


## Bolum basligi. shop_screen.gd::_make_section ve settings_screen.gd::
## _add_section neredeyse birebir ayniydi; ikisi de artik burayi kullanir.
static func section_header(title: String) -> Label:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", UIMetrics.FONT_LABEL + 6)
	label.add_theme_color_override("font_color", Palette.ACCENT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size = Vector2(0.0, 30.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return label
