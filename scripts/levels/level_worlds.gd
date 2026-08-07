class_name LevelWorlds
extends RefCounted

## Bolum BANTLARI: hangi bolumler hangi dunyaya ait, adi ne, rengi ne.
##
## NEDEN AYRI BIR SINIF: bant sinirlari iki ayri yerde kullaniliyor - oynanis
## temasi (PaletteThemes.for_level) ve bolum secim ekranindaki sayfalar. Bu
## ikisi ayni sey olmak ZORUNDA: oyuncu 51. bolume gectiginde hem oyunun
## rengi degismeli hem de bolum listesinde yeni bir sayfaya gecmis olmali.
## Iki yerde ayri tanimlanirsa kaciniz kayar ve kimse fark etmez.
##
## SON DUNYA acik uclu: son bolum numarasi LevelLibrary'den okunur, sabit
## degildir. Boylece LEVEL_COUNT buyudugunde yeni bolumler kendiliginden son
## dunyaya girer ve burada hicbir sey degistirmek gerekmez.

## Her girisin ilk bolumu. Ad ve tema sirayla eslesir.
const WORLDS := [
	{"name": "BAŞLANGIÇ", "first": 1},
	{"name": "KİNETİK", "first": 51},
	{"name": "FİNAL", "first": 101},
]


static func count() -> int:
	return WORLDS.size()


static func first_level(index: int) -> int:
	var safe := clampi(index, 0, count() - 1)
	return int(WORLDS[safe]["first"])


## Bir sonraki dunyanin baslangicindan bir eksik; son dunyada kutuphanenin
## son bolumu.
static func last_level(index: int) -> int:
	var safe := clampi(index, 0, count() - 1)
	if safe >= count() - 1:
		return LevelLibrary.last_level_id()
	return mini(first_level(safe + 1) - 1, LevelLibrary.last_level_id())


static func level_count(index: int) -> int:
	return maxi(last_level(index) - first_level(index) + 1, 0)


static func display_name(index: int) -> String:
	var safe := clampi(index, 0, count() - 1)
	return String(WORLDS[safe]["name"])


## Bolum numarasi -> dunya indeksi. Gecersiz numara ilk dunyaya duser.
static func index_for_level(level_id: int) -> int:
	var found := 0
	for i in count():
		if level_id >= first_level(i):
			found = i
	return found


static func theme_for_index(index: int) -> PaletteTheme:
	match clampi(index, 0, count() - 1):
		0:
			return PaletteThemes.theme_a()
		1:
			return PaletteThemes.theme_b()
	return PaletteThemes.theme_c()


## Dunyanin vurgu rengi. Bolum secim ekrani butonlari ve sekmeleri bununla
## boyar - Palette'i global olarak degistirmeden, cunku o an ekranda uc dunya
## birden temsil ediliyor.
static func accent_for_index(index: int) -> Color:
	return theme_for_index(index).ACCENT


static func accent_dim_for_index(index: int) -> Color:
	return theme_for_index(index).ACCENT_DIM


static func accent_core_for_index(index: int) -> Color:
	return theme_for_index(index).ACCENT_CORE
