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

## Her girisin ilk bolumu, adi ve BONUS bolumleri.
##
## Bonus bolumler numara sirasinin DISINDA durur (151+): boylece bir dunyaya
## normal bolum eklemek bonus numaralarini kaydirmaz ve kayitlar bozulmaz.
## Her dunyanin sonunda iki tane vardir; ikincisi birincisinden zordur.
const WORLDS := [
	{"name": "BAŞLANGIÇ", "first": 1, "bonus": [151, 152]},
	{"name": "KİNETİK", "first": 51, "bonus": [153, 154]},
	{"name": "FİNAL", "first": 101, "bonus": [155, 156]},
]

## Ilk bonus bolumun numarasi. Bundan kucuk her numara NORMAL bolumdur ve
## dunyalarin normal araliklari bu sinira gore hesaplanir.
const FIRST_BONUS_ID := 151

## Bonus bolumun acilmasi icin KENDI DUNYASINDAN gereken yildiz orani.
## Ikinci bonus birincisinden daha yuksek bir esik ister.
const BONUS_GATE_RATIOS := [0.80, 0.90]


static func count() -> int:
	return WORLDS.size()


static func first_level(index: int) -> int:
	var safe := clampi(index, 0, count() - 1)
	return int(WORLDS[safe]["first"])


## Dunyanin son NORMAL bolumu. Bonus bolumler bu araligin disindadir
## (bkz. bonus_ids): son dunyada da sinir FIRST_BONUS_ID'dir, kutuphanenin
## sonu degil - aksi halde bonuslar normal izgaraya karisirdi.
static func last_level(index: int) -> int:
	var safe := clampi(index, 0, count() - 1)
	var library_end := mini(LevelLibrary.last_level_id(), FIRST_BONUS_ID - 1)
	if safe >= count() - 1:
		return library_end
	return mini(first_level(safe + 1) - 1, library_end)


## Dunyanin bonus bolum numaralari (varsa).
static func bonus_ids(index: int) -> Array[int]:
	var out: Array[int] = []
	var safe := clampi(index, 0, count() - 1)
	for raw in (WORLDS[safe].get("bonus", []) as Array):
		var id := int(raw)
		if LevelLibrary.is_valid_id(id):
			out.append(id)
	return out


static func is_bonus_id(level_id: int) -> bool:
	for i in count():
		if bonus_ids(i).has(level_id):
			return true
	return false


## Bonus bolumun ait oldugu dunya; bonus degilse -1.
static func world_of_bonus(level_id: int) -> int:
	for i in count():
		if bonus_ids(i).has(level_id):
			return i
	return -1


## Bir dunyanin NORMAL bolumlerinden toplanabilecek azami yildiz. Bonus
## bolumler bu sayiya girmez: kendileri odul, esik degil.
static func world_star_capacity(index: int) -> int:
	return level_count(index) * LevelData.NORMAL_MAX_STARS


## Bonus bolumun acilmasi icin kendi dunyasindan gereken yildiz.
## Bonus degilse 0.
static func bonus_required_stars(level_id: int) -> int:
	var world := world_of_bonus(level_id)
	if world < 0:
		return 0
	var slot := bonus_ids(world).find(level_id)
	if slot < 0:
		return 0
	var ratio: float = BONUS_GATE_RATIOS[mini(slot, BONUS_GATE_RATIOS.size() - 1)]
	return int(round(float(world_star_capacity(world)) * ratio))


static func level_count(index: int) -> int:
	return maxi(last_level(index) - first_level(index) + 1, 0)


static func display_name(index: int) -> String:
	var safe := clampi(index, 0, count() - 1)
	return String(WORLDS[safe]["name"])


## Bolum numarasi -> dunya indeksi. Bonus bolumler ait olduklari dunyayi
## dondurur (numaralari 151+ oldugu icin sira karsilastirmasi yanlis sonuc
## verirdi). Gecersiz numara ilk dunyaya duser.
static func index_for_level(level_id: int) -> int:
	var bonus_world := world_of_bonus(level_id)
	if bonus_world >= 0:
		return bonus_world
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
