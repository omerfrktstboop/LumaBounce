class_name LegalLinks
extends RefCounted

## Oyunun disariya actigi YASAL BAGLANTILARIN tek kaynagi.
##
## Sebep Haptics/Locale ile ayni: URL'yi cagri yerine gomdugumuz anda ayni
## adres iki-uc yerde kopyalanir ve politika adresi degistiginde biri mutlaka
## eski adreste kalir. Magaza yayin sartlarinin bagli oldugu bir baglantida
## bunun bedeli yuksek - tek cikis noktasi bu yuzden var.
##
## OS.shell_open cagrisi da burada toplanir: adres disaridan (ornegin ileride
## bir uzak yapilandirmadan) gelse bile scheme dogrulamasi tek yerde kalir.

const PRIVACY_POLICY_URL := "https://policy.lumabounce-privacy.workers.dev/"


## Yalnizca https adresleri acilir. `javascript:`/`file:` gibi semalar bir
## kullanici arayuzu dugmesinden asla acilmamali; kontrol tek yerde durdugu
## icin yeni bir baglanti eklemek bu korumayi otomatik devralir.
static func is_openable(url: String) -> bool:
	return url.begins_with("https://")


## Basarili ise true. Cagiranlar sonucu yok sayabilir - masaustu/mobilde
## tarayici acilamamasi oyunun akisini bozmamali.
static func open(url: String) -> bool:
	if not is_openable(url):
		push_warning("LegalLinks: guvenli olmayan adres yok sayildi: %s" % url)
		return false
	OS.shell_open(url)
	return true


static func open_privacy_policy() -> bool:
	return open(PRIVACY_POLICY_URL)
