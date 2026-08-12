class_name UIMetrics
extends RefCounted

## FAZ 9 tasarim token sistemi: bosluk, kose yaricapi ve yazi boyutu.
##
## Oncesinde bu degerler her ekranda ayri ayri sabit yazilirdi (ornegin
## magaza urun adi 23px, ayarlar satir etiketi 26px - kavramsal olarak ayni
## seviyedeki iki metin bile uyusmuyordu). Bu dosya Palette'in yaninda ikinci
## bir "static var" sinifi degil - degerler zaman icinde temaya gore
## degismiyor, bu yuzden sabit ('const') kalabilirler.
##
## Olcek, oyunun mevcut 720 birim genislikli referans cozunurlugune gore
## kalibre edilmistir (ekranlardaki bugunku font boyutlariyla ayni buyukluk
## mertebesinde) - marka rehberinin onerdigi 32-36px gibi degerler farkli bir
## taban birime gore yazilmisti ve burada birebir kullanilirsa mevcut metnin
## yariya yakin kuculmesine (gorsel gerilemeye) yol acardi.

# --- Bosluk (marka rehberi SS10 ile ayni 4px tabanli olcek) ---
const SPACE_XS := 4
const SPACE_SM := 8
const SPACE_MD := 12
const SPACE_LG := 16
const SPACE_XL := 20
const SPACE_XXL := 24
const SPACE_XXXL := 32
const SPACE_HUGE := 40
const SPACE_MASSIVE := 48

const CARD_PADDING := 20
const COMPONENT_GAP := 16
const SECTION_GAP := 28

# --- Kose yaricapi ---
const RADIUS_SM := 12
const RADIUS_MD := 16
const RADIUS_CARD := 20
const RADIUS_LARGE_CARD := 24
const RADIUS_CTA := 28
const RADIUS_PILL := 999

# --- Yazi olcegi ---
const FONT_DISPLAY := 40    ## Sayfa basligi (MAĞAZA, AYARLAR)
const FONT_HERO := 34       ## Buyuk vurgu metni
const FONT_TITLE := 27      ## Belirgin bolum/kart metni
const FONT_CARD_TITLE := 22 ## Urun/navigasyon karti adi
const FONT_BODY := 18       ## Satir etiketi, standart govde metni
const FONT_SUPPORTING := 15 ## Ipucu/aciklama metni
const FONT_LABEL := 13      ## Kucuk durum/etiket metni

## 720x1280 referans tuvalinde yaklasik 45 ekran pikseline denk gelen
## dokunma hedefi. 48 referans birimi telefonda 30 piksele kadar kuculuyor
## ve ozellikle baslik ikonlari ile magaza sekmelerini zor dokunulur yapiyordu.
const MIN_TOUCH := 72
