class_name Locale
extends RefCounted

## Dil secimi icin TEK cikis noktasi.
##
## Haptics ile ayni desen: dilin nasil uygulandigini bilen tek yer burasi,
## boylece "bir yerde TranslationServer.set_locale unutuldu" hatasi olusamaz.
## AppRoot acilista [method apply_saved] ile kaydedilen dili uygular; ayarlar
## ekrani [method apply] cagirir.
##
## KAYNAK DIL TURKCE. Ceviri tablolarinin anahtari Turkce metnin KENDISIDIR
## (bkz. assets/i18n/*.csv), cunku boylece 125 bolum dosyasinin hicbirine
## dokunmadan ceviri eklenebiliyor ve cevirisi olmayan bir metin ekranda bos
## degil, Turkce gorunuyor.

## Desteklenen diller. Sira ayarlar ekranindaki sirayla aynidir.
const SUPPORTED: Array[String] = ["tr", "en"]
const DEFAULT := "tr"

## Dilin KENDI dilindeki adi - ayarlar ekraninda "English" yazar, "Ingilizce"
## degil. Dil secen oyuncu genellikle mevcut dili okuyamiyordur.
const DISPLAY_NAMES := {
	"tr": "Türkçe",
	"en": "English",
}


static func is_supported(code: String) -> bool:
	return SUPPORTED.has(code)


static func display_name(code: String) -> String:
	return String(DISPLAY_NAMES.get(code, code))


## Kaydedilmis/serbest bir kodu desteklenen bir dile indirger.
## Bos veya taninmayan deger sistem diline, o da desteklenmiyorsa DEFAULT'a duser.
static func normalize(code: String) -> String:
	var clean := code.strip_edges().to_lower()
	if is_supported(clean):
		return clean
	# "en_US" gibi bolge ekli kodlar da kabul edilir.
	var language := clean.split("_")[0] if clean.contains("_") else clean
	if is_supported(language):
		return language
	return DEFAULT


## Oyuncu henuz secim yapmadiginda kullanilacak dil: cihazin dili destekleniyorsa
## o, degilse Turkce. Boylece Ingilizce bir telefonda oyun Ingilizce acilir.
static func system_default() -> String:
	return normalize(OS.get_locale_language())


## Dili uygular. Cagiran kaydetmekle ilgilenmez - kayit ProgressStore'un isidir.
static func apply(code: String) -> String:
	var resolved := normalize(code)
	TranslationServer.set_locale(resolved)
	return resolved


## Kayitli tercihi uygular; tercih bos ise (henuz secilmemis) sistem dilini
## kullanir ama HICBIR SEY KAYDETMEZ - oyuncu bilincli bir secim yapana kadar
## cihaz dilini takip etmesi dogru davranistir.
static func apply_saved(saved: String) -> String:
	var wanted := saved.strip_edges()
	return apply(wanted if is_supported(wanted) else system_default())


static func current() -> String:
	return normalize(TranslationServer.get_locale())
