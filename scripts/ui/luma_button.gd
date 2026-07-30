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
	PRIMARY,   ## Ana eylem (OYNA): duragan halde bile hafif cyan kenar.
	SECONDARY, ## Ikincil eylem: mat kenar, cyan yalnizca etkilesimde.
}

@export var emphasis: Emphasis = Emphasis.SECONDARY:
	set(value):
		emphasis = value
		if is_node_ready():
			_apply_style()
@export var corner_radius := 30
## true ise kose yaricapi boyuttan hesaplanir (tam yuvarlak ikon butonlari).
@export var circular := false
@export var content_margin := Vector2(28.0, 14.0)

@export_group("Basis Animasyonu")
@export_range(0.7, 1.0, 0.01) var press_scale := 0.95
@export var press_time := 0.09
@export var release_time := 0.22

var _scale_tween: Tween
## Stil yeniden uretimini gereksiz tetiklememek icin son uygulanan yaricap.
var _applied_radius := -1


func _ready() -> void:
	resized.connect(_on_resized)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	pivot_offset = size * 0.5
	_apply_style()


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
	var is_primary := emphasis == Emphasis.PRIMARY

	var normal_bg := Color(Palette.SURFACE, 0.92) if is_primary else Color(Palette.SURFACE, 0.5)
	var hover_bg := Color(Palette.SURFACE_EDGE, 0.92) if is_primary else Color(Palette.SURFACE, 0.85)
	var pressed_bg := Color(Palette.INK_MID, 1.0)

	var normal_border := Color(Palette.ACCENT, 0.5) if is_primary else Color(Palette.SURFACE_EDGE, 0.9)
	var hover_border := Color(Palette.ACCENT, 0.95) if is_primary else Color(Palette.ACCENT, 0.55)
	var pressed_border := Color(Palette.ACCENT, 1.0) if is_primary else Color(Palette.ACCENT, 0.85)

	add_theme_stylebox_override("normal", _make_style(normal_bg, normal_border, 2, radius))
	add_theme_stylebox_override("hover", _make_style(hover_bg, hover_border, 2, radius))
	add_theme_stylebox_override("pressed", _make_style(pressed_bg, pressed_border, 3, radius))
	add_theme_stylebox_override("focus", _make_style(hover_bg, hover_border, 2, radius))
	add_theme_stylebox_override("disabled", _make_style(
		Color(Palette.SURFACE, 0.26), Color(Palette.SURFACE_EDGE, 0.4), 2, radius))

	add_theme_color_override("font_color", Palette.TEXT if is_primary else Palette.TEXT_DIM)
	add_theme_color_override("font_hover_color", Palette.TEXT)
	add_theme_color_override("font_pressed_color", Palette.ACCENT_CORE)
	add_theme_color_override("font_disabled_color", Color(Palette.TEXT_DIM, 0.45))


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
