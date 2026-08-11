class_name Palette
extends RefCounted

## LumaBounce tema paleti. Tum renkler tek yerden yonetilir.
##
## TASARIM KURALI - "tek vurgu":
## Sahnenin buyuk cogunlugu sessizdir (ink zemin + surface yuzeyler).
## Neon vurgu YALNIZCA oyuncunun odaklanmasi gereken uc elemanda kullanilir:
##   1) top   2) nisan kilavuzu   3) hedef
## Ikincil vurgu (menekse) sadece isabet / basari aninda gorunur.
##
## TEMA DEGISIMI: alanlar bilerek 'const' degil 'static var' - AppRoot,
## bolume gore apply_theme() cagirarak hepsini birden degistirir (bkz.
## PaletteThemes, AppRoot._theme_for_level()). Var olan Palette.ACCENT gibi
## okumalar bundan etkilenmez, hicbir cagiran degismek zorunda degil.


# --- Zemin: derin murekkep lacivert (saf siyah degil) ---
static var INK_TOP := Color("17233a")
static var INK_MID := Color("1e2d46")
static var INK_BOTTOM := Color("22324d")

# --- Sessiz yuzeyler: duvar, panel, firlatici ---
static var SURFACE := Color("2b3c5b")
static var SURFACE_EDGE := Color("3a4f76")
static var SURFACE_LIGHT := Color("4d6595")
static var FRAME := Color("31446a")
## Sekme paneli govdesi: SURFACE'tan ~%10 daha acik. Panellerin zeminden
## net ayrismasi icin ayri tutulur (SURFACE duvar/buton/firlaticida da
## kullanildigi icin onu genel olarak aydinlatmak tum arayuzu degistirirdi).
static var SURFACE_PANEL := Color("40506b")

# --- Kirilabilir blok yuzeyi ---
# Panelden AYIRT EDILEBILIR olmali ama neon top/hedefle yarismamali.
# Panel "saglam" hissi verir (acik mat govde, yuvarlak stadyum); blok ise
# "modulup kirilabilir" hissi verir: daha KOYU govde, daha PARLAK ince kenar
# ve merkezdeki dikis cizgisi. Tonlar bilerek cyan/teal DEGIL, mavi-gri.
static var SURFACE_BLOCK := Color("32405c")
static var SURFACE_BLOCK_EDGE := Color("6d86b6")
## Merkezdeki hafif kirilma/segment cizgisi.
static var SURFACE_BLOCK_SEAM := Color("8ba3ce")

# --- Iki darbelik (dayanikli) kirilabilir blok ---
# Tek darbelik tugla MAVI-GRI, iki darbelik tugla BRONZ/AMBER: oyuncu bir
# tuglanin kac temas istedigini SAYMADAN, tek bakista renkten anlamali.
# Ton bilerek mavinin karsi tarafindan secildi (en yuksek ayirt edilebilirlik).
# HAZARD (pembe-kirmizi) ile karisma riski yok: bombalar yalnizca 41+
# bolumlerde, kirilabilir bloklar yalnizca 26-40'ta bulunur - hic yan yana
# gelmezler. Ayrica bomba daire, tugla dikdortgendir.
static var SURFACE_BLOCK_STRONG := Color("5c4630")
static var SURFACE_BLOCK_STRONG_EDGE := Color("d19a5e")
static var SURFACE_BLOCK_STRONG_SEAM := Color("e8bd88")

# --- Birincil vurgu: neon camgobegi / teal (bolum 1-50) ---
static var ACCENT := Color("34e6d4")
static var ACCENT_DIM := Color("1ba99d")
static var ACCENT_CORE := Color("ecfffc")

# --- Ikincil vurgu: yumusak menekse (isabet ve basari) ---
static var ACCENT_ALT := Color("c07dff")
static var ACCENT_ALT_CORE := Color("f6ecff")

# --- Tehlike vurgusu: yalnizca bomba ve temas geri bildirimi. Tema
# degisse de AYNI kalir - "tehlike" her zaman ayni renge cevrilmeli. ---
## PARA BIRIMI. HAZARD ile ayni sebeple dunyadan BAGIMSIZ (temalar bu alani
## ezmez): tehlike her dunyada ayni sey demek zorunda oldugu gibi, para da
## her dunyada ayni sey demek zorunda. Vurgu rengiyle degisseydi 3. dunyada
## mor bir jeton, oradaki vurgu renginin bir parcasi gibi okunurdu.
static var COIN := Color("ffc861")
static var COIN_CORE := Color("fff1d2")

static var HAZARD := Color("ff667d")
static var HAZARD_DARK := Color("63364a")
static var HAZARD_CORE := Color("ffe2e7")

# --- Metin ---
static var TEXT := Color("e9f2ff")
static var TEXT_DIM := Color("93a7c9")


## Butun alanlari verilen temadan tek seferde uygular. Cagrildigi andan
## itibaren her Palette.XXX okuyusu yeni degeri gorur.
static func apply_theme(theme: PaletteTheme) -> void:
	INK_TOP = theme.INK_TOP
	INK_MID = theme.INK_MID
	INK_BOTTOM = theme.INK_BOTTOM

	SURFACE = theme.SURFACE
	SURFACE_EDGE = theme.SURFACE_EDGE
	SURFACE_LIGHT = theme.SURFACE_LIGHT
	FRAME = theme.FRAME
	SURFACE_PANEL = theme.SURFACE_PANEL

	SURFACE_BLOCK = theme.SURFACE_BLOCK
	SURFACE_BLOCK_EDGE = theme.SURFACE_BLOCK_EDGE
	SURFACE_BLOCK_SEAM = theme.SURFACE_BLOCK_SEAM

	SURFACE_BLOCK_STRONG = theme.SURFACE_BLOCK_STRONG
	SURFACE_BLOCK_STRONG_EDGE = theme.SURFACE_BLOCK_STRONG_EDGE
	SURFACE_BLOCK_STRONG_SEAM = theme.SURFACE_BLOCK_STRONG_SEAM

	ACCENT = theme.ACCENT
	ACCENT_DIM = theme.ACCENT_DIM
	ACCENT_CORE = theme.ACCENT_CORE

	ACCENT_ALT = theme.ACCENT_ALT
	ACCENT_ALT_CORE = theme.ACCENT_ALT_CORE

	COIN = theme.COIN
	COIN_CORE = theme.COIN_CORE
	HAZARD = theme.HAZARD
	HAZARD_DARK = theme.HAZARD_DARK
	HAZARD_CORE = theme.HAZARD_CORE

	TEXT = theme.TEXT
	TEXT_DIM = theme.TEXT_DIM
