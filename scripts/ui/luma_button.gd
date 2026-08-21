class_name LumaButton
extends Button

## Projenin ortak buton bileseni.
##
## Tum stiller Palette'ten kod ile uretilir (sahnede StyleBox kopyasi tutulmaz).
## Etkilesim geri bildirimi iki katmanlidir:
##   - basista kucuk bir scale animasyonu
##   - hover/basisda hafif CYAN KENAR vurgusu
## Neon cyan burada bilerek yalnizca kenarda kullanilir; dolgu ve metin mat
## kalir, boylece "tek vurgu" kurali korunur.

enum Emphasis {
	PRIMARY,   ## Ana eylem: duragan halde bile hafif cyan kenar.
	SECONDARY, ## Ikincil eylem: mat kenar, cyan yalnizca etkilesimde.
	## Ekranin TEK birincil eylemi (Ev'deki OYNA). PRIMARY'nin her seyini
	## devralir, uzerine vurgu tonuna dogru kaydirilmis KOYU TEAL bir dolgu
	## ekler.
	##
	## Neden ayri bir seviye: PRIMARY bu projede "ana eylem" degil, fiilen
	## "secili/tamamlanmis" durumu isaretliyor (level_select.gd tamamlanan
	## bolum butonlari ve dunya sekmeleri, segmented_control.gd secili
	## segment). PRIMARY'nin dolgusunu degistirmek bolum secim izgarasindaki
	## onlarca butonu birden boyar ve "tek vurgu" kuralini kirardi.
	CTA,
}

## CTA dolgusunun vurgu tonuna dogru karisim orani. Degerler bilerek dusuk:
## dolgu KOYU teal kalmali, neon/fosforlu olmamali. Hover ve basili hal
## ayni eksende yukari/asagi kayar, boylece etkilesim TON degisimi olarak
## okunur - ayri bir parlama katmani eklemeye gerek kalmaz.
const CTA_FILL_MIX := 0.20
const CTA_FILL_MIX_HOVER := 0.30
const CTA_FILL_MIX_PRESSED := 0.12
## PRIMARY'nin 0.5'inden belirgin ama parlamayacak kadar yukarida.
const CTA_BORDER_ALPHA := 0.62

@export var emphasis: Emphasis = Emphasis.SECONDARY:
	set(value):
		emphasis = value
		if is_node_ready():
			_apply_style()
@export var corner_radius := 30
## true ise kose yaricapi boyuttan hesaplanir (tam yuvarlak ikon butonlari).
@export var circular := false
## Oynanis HUD'undaki ikon butonlari zeminin uzerinde tek baslarina durur ve
## menu butonlarindan daha opak bir dolgu + daha aydinlik bir kenar ister,
## yoksa arenanin uzerinde silik kalirlar. Menu butonlari varsayilanda sessiz.
@export var high_contrast := false
@export var content_margin := Vector2(28.0, 14.0)
## Vurgu rengini bu buton icin DEGISTIRIR. Alfasi 0 iken (varsayilan)
## Palette.ACCENT kullanilir, yani mevcut hicbir buton etkilenmez.
##
## Neden gerekli: bolum secim ekraninda ayni anda UC dunyanin rengi temsil
## ediliyor. Palette global bir static var oldugu icin onu degistirmek tum
## ekrani birden boyar; renk butona veri olarak gecmek zorunda.
@export var accent_override := Color(0.0, 0.0, 0.0, 0.0):
	set(value):
		accent_override = value
		if is_node_ready():
			_apply_style()
## Dolgu rengini bu buton icin degistirir; alfasi 0 iken Palette.SURFACE
## kullanilir. Vurgudan AYRI bir alan, cunku ikisi bagimsiz degisiyor:
## bolum secim sekmelerinin hepsi ayni zeminin uzerinde durur (ayni yuzey)
## ama her biri kendi dunyasinin vurgusunu tasir.
##
## Kenar ve basili haldeki tonlar bundan TURETILIR (lightened/darkened) -
## her ton icin ayri bir alan API'yi sisirir ve tutarsizliga acik birakirdi.
@export var surface_override := Color(0.0, 0.0, 0.0, 0.0):
	set(value):
		surface_override = value
		if is_node_ready():
			_apply_style()

@export_group("Basis Animasyonu")
## Basis geri bildirimi bilerek SIG ve KISA: derin bir ezilme (0.95) buyuk
## bir CTA'da yavas ve yumusak okunuyordu. 0.97 + kisa sureler "tok" bir
## dokunus hissi verir ve tum butonlarda ayni dili korur.
@export_range(0.7, 1.0, 0.01) var press_scale := 0.97
@export var press_time := 0.07
@export var release_time := 0.14

@export_group("Ses")
## Kapatilirsa bu buton tiklama sesi calmaz (or. sesin kendisini bozacak
## ozel durumlar icin). Devre disi butonlar zaten hic ses cikarmaz.
@export var play_click_sound := true

var _scale_tween: Tween
## Stil yeniden uretimini gereksiz tetiklememek icin son uygulanan yaricap.
var _applied_radius := -1


func _ready() -> void:
	resized.connect(_on_resized)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	# "pressed" basari basina TAM BIR KEZ yayilir ve disabled butonlarda hic
	# yayilmaz; tiklama sesi icin dogru kanca budur. LumaIconButton bunu
	# oldugu gibi devralir.
	pressed.connect(_on_pressed_sound)
	pivot_offset = size * 0.5
	_apply_style()


func _on_pressed_sound() -> void:
	if play_click_sound:
		AudioManager.play_ui_click()


func _on_resized() -> void:
	# Olcek animasyonu merkezden olsun.
	pivot_offset = size * 0.5
	# Stil her seferinde yeni StyleBox uretir ve minimum boyut bildirimi
	# tetikler; yalnizca yaricap gercekten degistiyse yeniden kur.
	if _current_radius() != _applied_radius:
		_apply_style()


# --- Stil --------------------------------------------------------------------

func _current_radius() -> int:
	return int(minf(size.x, size.y) * 0.5) if circular else corner_radius


func _apply_style() -> void:
	var radius := _current_radius()
	_applied_radius = radius
	var is_cta := emphasis == Emphasis.CTA
	var is_primary := is_cta or emphasis == Emphasis.PRIMARY

	var solid := is_primary or high_contrast
	var surface := _surface()
	var surface_edge := _surface_edge()
	var accent := _accent()
	var solid_fill := Color(surface, 0.92)
	var normal_bg := solid_fill if solid else Color(surface, 0.5)
	var hover_bg := Color(surface_edge, 0.92) if solid else Color(surface, 0.85)
	var pressed_bg := Color(_pressed_fill(), 1.0)

	var normal_border := Color(surface_edge, 0.9)
	if is_primary:
		normal_border = Color(accent, 0.5)
	elif high_contrast:
		normal_border = Color(_surface_light(), 1.0)

	# CTA: PRIMARY'nin uzerine vurgu tonuna kaydirilmis koyu teal dolgu.
	# Dolgu zeminden (INK_MID) turetilir, SURFACE'tan degil - kartlar ve
	# ikincil butonlar SURFACE ailesinde kaldigi icin hiyerarsi farki
	# boylece TON olarak da okunur, yalnizca parlaklik olarak degil.
	if is_cta:
		normal_bg = Color(_cta_fill(accent, CTA_FILL_MIX), 0.96)
		hover_bg = Color(_cta_fill(accent, CTA_FILL_MIX_HOVER), 0.98)
		pressed_bg = Color(_cta_fill(accent, CTA_FILL_MIX_PRESSED), 1.0)
		normal_border = Color(accent, CTA_BORDER_ALPHA)
	var hover_border := Color(accent, 0.95) if is_primary else Color(accent, 0.55)
	var pressed_border := Color(accent, 1.0) if is_primary else Color(accent, 0.85)

	add_theme_stylebox_override("normal", _make_style(normal_bg, normal_border, 2, radius))
	add_theme_stylebox_override("hover", _make_style(hover_bg, hover_border, 2, radius))
	add_theme_stylebox_override("pressed", _make_style(pressed_bg, pressed_border, 3, radius))
	add_theme_stylebox_override("focus", _make_style(hover_bg, hover_border, 2, radius))
	add_theme_stylebox_override("disabled", _make_style(
		Color(surface, 0.26), Color(surface_edge, 0.4), 2, radius))

	add_theme_color_override("font_color", Palette.TEXT if is_primary else Palette.TEXT_DIM)
	add_theme_color_override("font_hover_color", Palette.TEXT)
	add_theme_color_override("font_pressed_color", Palette.ACCENT_CORE)
	# 0.45 -> 0.52: bolum secim izgarasinda kilitli bolum NUMARALARI okunmuyordu
	# (numara tek basina bilgi tasiyor - "kacinci bolumdeyim"). Artis bilerek
	# kucuk: devre disi hissi kaybolmamali, yalnizca metin secilebilir olmali.
	add_theme_color_override("font_disabled_color", Color(Palette.TEXT_DIM, 0.52))


## accent_override atanmissa o, degilse paletin vurgusu. Alfa 0 "atanmadi"
## demektir - Color'in kendisi null olamadigi icin sentinel gerekiyor.
func _accent() -> Color:
	return accent_override if accent_override.a > 0.0 else Palette.ACCENT


func _surface() -> Color:
	return surface_override if surface_override.a > 0.0 else Palette.SURFACE


## Turetilmis tonlar: override YOKKEN paletin kendi degerleri kullanilir,
## boylece oyundaki mevcut butonlarin gorunumu birebir korunur. Override
## varsa tek bir renkten turetilir - her ton icin ayri alan API'yi sisirirdi.
func _surface_edge() -> Color:
	return surface_override.lightened(0.16) if surface_override.a > 0.0 else Palette.SURFACE_EDGE


func _surface_light() -> Color:
	return surface_override.lightened(0.38) if surface_override.a > 0.0 else Palette.SURFACE_LIGHT


## CTA dolgusu: murekkep zeminden vurgu tonuna dogru kontrollu karisim.
## Taban Palette.INK_MID oldugu icin tema degistiginde (PaletteThemes) dolgu
## da dunyanin vurgusunu kendiliginden takip eder - sabit bir cyan yazmak
## 51+ bandinda turuncu temanin yaninda yanlis renk birakirdi.
func _cta_fill(accent: Color, mix: float) -> Color:
	return Palette.INK_MID.lerp(accent, mix)


func _pressed_fill() -> Color:
	return surface_override.darkened(0.35) if surface_override.a > 0.0 else Palette.INK_MID


func _make_style(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.corner_detail = 12
	style.anti_aliasing = true
	style.content_margin_left = content_margin.x
	style.content_margin_right = content_margin.x
	style.content_margin_top = content_margin.y
	style.content_margin_bottom = content_margin.y
	return style


# --- Basis animasyonu --------------------------------------------------------

func _on_button_down() -> void:
	_start_scale_tween(press_scale, press_time).set_trans(Tween.TRANS_SINE)


func _on_button_up() -> void:
	_start_scale_tween(1.0, release_time).set_trans(Tween.TRANS_BACK)


func _start_scale_tween(target: float, duration: float) -> PropertyTweener:
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	_scale_tween = create_tween()
	return _scale_tween.tween_property(self, "scale", Vector2.ONE * target, duration) \
		.set_ease(Tween.EASE_OUT)
