class_name CosmeticData
extends Resource

## Tek bir kozmetik esya: top derisi, iz, firlatici derisi ya da hedef efekti.
##
## TEMEL KURAL - PAY-TO-WIN DEGIL: bu kaynak yalnizca GORUNUM alanlari tasir.
## Yaricap, ziplama katsayisi, yercekimi, hiz gibi hicbir fizik alani burada
## YOKTUR ve olmamalidir. Ball/Launcher/Target sinifi zaten alanlarini
## "Fizik" ve "Gorunum" gruplarina ayirmis durumda; kozmetik yalnizca ikinci
## gruba dokunur. check_cosmetics.gd bunu olcerek dogrular.
##
## FIYAT BURADA, ARAYUZDE DEGIL: magaza karti fiyati bu kaynaktan okur.
## Fiyat dengesi degistiginde tek yer degisir ve hicbir ekran guncellenmez.

enum Kind {
	BALL,
	TRAIL,
	LAUNCHER,
	TARGET_FX,
}

const KIND_IDS := {
	Kind.BALL: "ball",
	Kind.TRAIL: "trail",
	Kind.LAUNCHER: "launcher",
	Kind.TARGET_FX: "target_fx",
}

## Kalici kimlik. Kayit dosyasina BU yazilir; adi veya fiyati degisse bile
## oyuncunun sahipligi bozulmaz. Asla yeniden kullanilmamali.
@export var id := ""
@export var kind: Kind = Kind.BALL
@export var display_name := ""
## Luma Coin cinsinden fiyat. 0 = baslangicta sahip olunan varsayilan.
@export var price := 0
## Varsayilan esya her oyuncuda acik gelir ve satin alinamaz.
@export var is_default := false

@export_group("Görünüm")
@export var accent := Palette.ACCENT
@export var core := Palette.ACCENT_CORE
## Ikincil renk: iz gradyaninin ucu, hedefin basari parlamasi gibi.
@export var alt := Palette.ACCENT_ALT
## Parlama yaricap carpani. 0 = bilesenin kendi varsayilanini koru.
@export var glow_scale := 0.0
## IZ icin: uzunluk ve genislik carpanlari. Ikisi de GORSELDIR - iz fizige
## hicbir sekilde katilmaz (bkz. ball.gd, _update_trail_response).
@export var trail_length_scale := 1.0
@export var trail_width_scale := 1.0


func kind_id() -> String:
	return String(KIND_IDS.get(kind, "ball"))


## Varsayilanlar bedava ve satin alinamaz; digerleri fiyatli olmak ZORUNDA.
## Fiyatsiz bir magaza esyasi sessizce bedava dagitilirdi.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id.strip_edges().is_empty():
		problems.append("kozmetik kimligi bos olamaz")
	if display_name.strip_edges().is_empty():
		problems.append("%s: gorunen ad bos" % id)
	if is_default and price != 0:
		problems.append("%s: varsayilan esya ucretsiz olmali (%d)" % [id, price])
	if not is_default and price <= 0:
		problems.append("%s: satin alinabilir esyanin fiyati olmali" % id)
	if glow_scale < 0.0:
		problems.append("%s: parlama carpani negatif olamaz" % id)
	if trail_length_scale <= 0.0 or trail_width_scale <= 0.0:
		problems.append("%s: iz carpanlari pozitif olmali" % id)
	return problems
