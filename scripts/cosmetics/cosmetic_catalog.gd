class_name CosmeticCatalog
extends RefCounted

## Magazadaki tum kozmetiklerin TEK kaynagi.
##
## Fiyatlar burada durur, arayuzde degil: magaza karti fiyati esyadan okur,
## dolayisiyla denge degisikligi tek dosyada olur.
##
## Renkler paletten TUREMEZ, sabit yazilir. Sebep olculebilir: Palette bolum
## bandina gore degisiyor (bkz. PaletteThemes) - kozmetikler paletten okusaydi
## oyuncunun satin aldigi "Buz Mavisi" top 2. dunyada turuncuya donerdi.
## Bir kozmetigin kimligi dunyaya gore degisemez.
##
## Her tur icin BIR varsayilan vardir ve o varsayilanin renkleri BILEREK
## paletin baslangic degerleriyle aynidir: hicbir sey secmemis oyuncunun
## gorduğu sey bugunku oyunla birebir aynidir.

const DEFAULT_BALL := "ball_default"
const DEFAULT_TRAIL := "trail_default"
const DEFAULT_LAUNCHER := "launcher_default"
const DEFAULT_TARGET := "target_default"

## Tur -> varsayilan esya kimligi.
const DEFAULT_IDS := {
	CosmeticData.Kind.BALL: DEFAULT_BALL,
	CosmeticData.Kind.TRAIL: DEFAULT_TRAIL,
	CosmeticData.Kind.LAUNCHER: DEFAULT_LAUNCHER,
	CosmeticData.Kind.TARGET_FX: DEFAULT_TARGET,
}

## Turlerin magazada gorunme sirasi.
const KIND_ORDER: Array[CosmeticData.Kind] = [
	CosmeticData.Kind.BALL,
	CosmeticData.Kind.TRAIL,
	CosmeticData.Kind.LAUNCHER,
	CosmeticData.Kind.TARGET_FX,
]

const KIND_LABELS := {
	CosmeticData.Kind.BALL: "TOP",
	CosmeticData.Kind.TRAIL: "İZ",
	CosmeticData.Kind.LAUNCHER: "FIRLATICI",
	CosmeticData.Kind.TARGET_FX: "HEDEF EFEKTİ",
}

## Fiyat bantlari - yeni esya eklerken bu araliklarin disina cikilmamali,
## yoksa magazanin ekonomisi bir kalemle bozulur. check_cosmetics.gd dogrular.
const PRICE_RANGES := {
	CosmeticData.Kind.BALL: Vector2i(30, 100),
	CosmeticData.Kind.TRAIL: Vector2i(50, 120),
	CosmeticData.Kind.LAUNCHER: Vector2i(80, 150),
	CosmeticData.Kind.TARGET_FX: Vector2i(120, 220),
}

static var _cache: Array[CosmeticData] = []


static func all() -> Array[CosmeticData]:
	if _cache.is_empty():
		_cache = _build()
	return _cache


static func by_kind(kind: CosmeticData.Kind) -> Array[CosmeticData]:
	var out: Array[CosmeticData] = []
	for item in all():
		if item.kind == kind:
			out.append(item)
	return out


static func find(id: String) -> CosmeticData:
	for item in all():
		if item.id == id:
			return item
	return null


static func default_id(kind: CosmeticData.Kind) -> String:
	return String(DEFAULT_IDS.get(kind, DEFAULT_BALL))


static func kind_label(kind: CosmeticData.Kind) -> String:
	return String(KIND_LABELS.get(kind, ""))


static func _make(id: String, kind: CosmeticData.Kind, name: String, price: int,
		accent: Color, core: Color, alt := Color(0, 0, 0, 0)) -> CosmeticData:
	var item := CosmeticData.new()
	item.id = id
	item.kind = kind
	item.display_name = name
	item.price = price
	item.is_default = price <= 0
	item.accent = accent
	item.core = core
	item.alt = alt if alt.a > 0.0 else core
	return item


static func _build() -> Array[CosmeticData]:
	var items: Array[CosmeticData] = []

	# --- TOP (30-100) ---
	# Varsayilan = bugunku cyan top; hicbir sey secmeyen oyuncu icin degisiklik yok.
	items.append(_make(DEFAULT_BALL, CosmeticData.Kind.BALL,
		"Luma", 0, Color("34e6d4"), Color("ecfffc")))
	items.append(_make("ball_ember", CosmeticData.Kind.BALL,
		"Kor", 40, Color("ff8a3d"), Color("fff0e0")))
	items.append(_make("ball_frost", CosmeticData.Kind.BALL,
		"Ayaz", 65, Color("7ad7ff"), Color("eaf9ff")))
	items.append(_make("ball_violet", CosmeticData.Kind.BALL,
		"Menekşe", 95, Color("c060ff"), Color("f6ecff")))

	# --- IZ (50-120) ---
	items.append(_make(DEFAULT_TRAIL, CosmeticData.Kind.TRAIL,
		"İnce İz", 0, Color("34e6d4"), Color("ecfffc")))
	var comet := _make("trail_comet", CosmeticData.Kind.TRAIL,
		"Kuyruklu Yıldız", 60, Color("ffd166"), Color("fffaf0"))
	comet.trail_length_scale = 1.6
	comet.trail_width_scale = 1.15
	items.append(comet)
	var ion := _make("trail_ion", CosmeticData.Kind.TRAIL,
		"İyon", 85, Color("4de0c8"), Color("e8fffb"))
	ion.trail_length_scale = 1.35
	ion.trail_width_scale = 0.9
	items.append(ion)
	var thread := _make("trail_thread", CosmeticData.Kind.TRAIL,
		"İpek", 115, Color("ff9d4d"), Color("fff3e6"))
	thread.trail_length_scale = 1.2
	thread.trail_width_scale = 0.6
	items.append(thread)

	# --- FIRLATICI (80-150) ---
	items.append(_make(DEFAULT_LAUNCHER, CosmeticData.Kind.LAUNCHER,
		"Standart", 0, Color("34e6d4"), Color("ecfffc")))
	items.append(_make("launcher_brass", CosmeticData.Kind.LAUNCHER,
		"Pirinç", 100, Color("ffc861"), Color("fff1d2")))
	items.append(_make("launcher_prism", CosmeticData.Kind.LAUNCHER,
		"Prizma", 145, Color("c060ff"), Color("f6ecff")))

	# --- HEDEF EFEKTI (120-220) ---
	items.append(_make(DEFAULT_TARGET, CosmeticData.Kind.TARGET_FX,
		"Sade Vuruş", 0, Color("34e6d4"), Color("ecfffc"), Color("c07dff")))
	var nova := _make("target_nova", CosmeticData.Kind.TARGET_FX,
		"Nova", 160, Color("ff667d"), Color("ffe2e7"), Color("ffd166"))
	nova.glow_scale = 2.1
	items.append(nova)
	var singularity := _make("target_singularity", CosmeticData.Kind.TARGET_FX,
		"Tekillik", 215, Color("9a6cff"), Color("f1e9ff"), Color("4de0c8"))
	singularity.glow_scale = 2.4
	items.append(singularity)

	return items
