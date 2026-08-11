class_name InkBackground
extends TextureRect

## Uygulama genelinde kullanilan sakin murekkep-lacivert gradient zemin.
##
## arena.gd'deki oyun ici zeminin UI karsiligi: ayni Palette degerleri,
## ayni sakin gecis. Leke, desen veya doku YOK - tek isi kontrast saglayip
## neon vurgulu ogelerin one cikmasina izin vermek.
## Kucuk bir gradient dokusu uretilip Control'un rect'ine gerilir; boylece
## her ekran orani ve cozunurlukte tek satir kod degisikligi olmadan calisir.

@export var ink_top := Palette.INK_TOP
@export var ink_mid := Palette.INK_MID
@export var ink_bottom := Palette.INK_BOTTOM
@export_range(0.0, 1.0, 0.01) var mid_offset := 0.55
## _ready'de renkleri Palette'ten TAZELER.
##
## Neden gerekli: yukaridaki baslangic degerleri sahne OLUSTURULURKEN
## okunuyor, oysa AppRoot temayi ondan sonra uyguluyor (bkz. _swap_to:
## instantiate -> configure -> add_child). Tazelenmezse zemin bir onceki
## dunyanin murekkebiyle kalirdi - 51+ bolumlerde tema degistigi halde arka
## planin lacivert kalmasinin sebebi tam olarak buydu.
##
## Kendi rengini veren ekranlar (bolum secim sayfalari) bunu kapatmaz;
## apply_ink zaten _ready'den SONRA cagrildigi icin son sozu o soyler.
@export var follow_palette := true


func _ready() -> void:
	if follow_palette:
		ink_top = Palette.INK_TOP
		ink_mid = Palette.INK_MID
		ink_bottom = Palette.INK_BOTTOM
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture = _build_texture()


## Zemini calisma zamaninda degistirir (bolum secim ekranindaki dunya
## sayfalari). Renkler @export oldugu icin atamak yetmez - doku _ready'de bir
## kez uretiliyor, bu yuzden yeniden kurulmasi gerekir.
func apply_ink(top: Color, mid: Color, bottom: Color) -> void:
	ink_top = top
	ink_mid = mid
	ink_bottom = bottom
	texture = _build_texture()


func _build_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, ink_top)
	gradient.set_color(1, ink_bottom)
	gradient.add_point(mid_offset, ink_mid)

	# Dar ama uzun bir doku yeterli: dogrusal filtreleme ile puruzsuz gerilir.
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.width = 8
	gradient_texture.height = 256
	gradient_texture.fill_from = Vector2(0.0, 0.0)
	gradient_texture.fill_to = Vector2(0.0, 1.0)
	return gradient_texture
