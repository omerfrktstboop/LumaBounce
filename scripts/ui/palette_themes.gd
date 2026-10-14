class_name PaletteThemes
extends RefCounted

## Bolum bandi basina renk temalari (bkz. AppRoot._theme_for_level()).
##
## Sadece VURGU renkleri (ACCENT ailesi) bantlar arasi degisir - zemin/yuzey
## tonlari ve HAZARD (bomba/tehlike) her temada AYNI kalir: "tek vurgu"
## tasarim kurali ile tehlike renginin her zaman ayni anlama gelmesi
## boylece korunur (bkz. palette.gd basligi).
##
## theme_a() bilerek Palette'in ORIJINAL degerleriyle birebir aynidir - 1-50
## bandi gorsel olarak hic degismez.

static func theme_a() -> PaletteTheme:
	return PaletteTheme.new()


## 51-100: turuncu vurgu, KOYU YESIL-TEAL zemin.
##
## Zemin de degisir, yalnizca vurgu degil. Sebep olculdu: yalnizca vurgu
## degistiginde bolum secim ekraninda ve oynanista dunyalar neredeyse ayni
## gorunuyordu - tema degisimi "belli olmuyordu". Turuncu, teal bir zeminde
## en cok one cikan renktir; ayni parlaklikta mavi bir zeminde soluk kalirdi.
static func theme_b() -> PaletteTheme:
	var t := PaletteTheme.new()
	t.INK_TOP = Color("12262a")
	t.INK_MID = Color("173235")
	t.INK_BOTTOM = Color("1b3b3d")
	t.SURFACE = Color("2a4048")
	t.SURFACE_EDGE = Color("395560")
	t.SURFACE_LIGHT = Color("4f7480")
	t.FRAME = Color("314954")
	t.SURFACE_PANEL = Color("3f5560")
	t.ACCENT = Color("ff9d4d")
	t.ACCENT_DIM = Color("c96f28")
	t.ACCENT_CORE = Color("fff3e6")
	t.ACCENT_ALT = Color("ffd166")
	t.ACCENT_ALT_CORE = Color("fffaf0")
	return t


## 101-125: mor vurgu, KOYU INDIGO-MENEKSE zemin.
##
## SURFACE_BLOCK* ailesine BILEREK dokunulmaz: kirilabilir tuglalarin
## dayaniklilik renk kodu (mavi-gri = tek vuruş, bronz = cift vuruş) her
## dunyada AYNI anlama gelmeli. Bu bant tugla iceren tek engel bandidir,
## dolayisiyla tam da burada bozulmamasi onemli.
static func theme_c() -> PaletteTheme:
	var t := PaletteTheme.new()
	t.INK_TOP = Color("1a1530")
	t.INK_MID = Color("221c3f")
	t.INK_BOTTOM = Color("28214a")
	t.SURFACE = Color("322a52")
	t.SURFACE_EDGE = Color("443a6b")
	t.SURFACE_LIGHT = Color("5b4f8c")
	t.FRAME = Color("392f5f")
	t.SURFACE_PANEL = Color("473d66")
	t.ACCENT = Color("c060ff")
	t.ACCENT_DIM = Color("8a3fd1")
	t.ACCENT_CORE = Color("f6ecff")
	t.ACCENT_ALT = Color("4de0c8")
	t.ACCENT_ALT_CORE = Color("e8fffb")
	return t


## 151-200 (PRİZMA): limon yesili vurgu, NOTR GRAFIT zemin.
##
## Onceki uc dunyanin vurgulari (camgobegi, turuncu, mor) ve dunyadan bagimsiz
## HAZARD (pembe-kirmizi) / COIN (altin) disinda kalan tek guclu ton limondur.
## Bu bandin portallari camgobegi giris / turuncu cikis kullanir; vurgu bu
## ikisinden biri olsaydi top ve hedef portallarla karisirdi. Zemin bilerek
## renksizdir ki portal renkleri ve limon vurgu ayni ekranda yarismasin.
## Ikincil vurgu varsayilan menekse: "isabet" her dunyada ayni okunur.
static func theme_d() -> PaletteTheme:
	var t := PaletteTheme.new()
	t.INK_TOP = Color("15191f")
	t.INK_MID = Color("1a2027")
	t.INK_BOTTOM = Color("1f262e")
	t.SURFACE = Color("2a333d")
	t.SURFACE_EDGE = Color("3a4652")
	t.SURFACE_LIGHT = Color("52606e")
	t.FRAME = Color("323c47")
	t.SURFACE_PANEL = Color("434e5a")
	t.ACCENT = Color("b8f05a")
	t.ACCENT_DIM = Color("7fb22e")
	t.ACCENT_CORE = Color("f5ffe6")
	t.ACCENT_ALT = Color("c07dff")
	t.ACCENT_ALT_CORE = Color("f6ecff")
	return t


## Bant sinirlari BURADA DEGIL, LevelWorlds'te tanimlidir. Sebep: ayni sinirlar
## bolum secim ekranindaki sayfalari da belirliyor ve ikisi ayni olmak zorunda -
## oyuncu 51. bolume gectiginde hem oyunun rengi degismeli hem de listede yeni
## sayfaya gecmis olmali.
static func for_level(level_id: int) -> PaletteTheme:
	return LevelWorlds.theme_for_index(LevelWorlds.index_for_level(level_id))
