class_name WalletStore
extends RefCounted

## Oyuncunun LUMA COIN bakiyesi ve kalici ipucu kilitleri: user://wallet.cfg.
##
## NEDEN AYRI DOSYA: Luma Coin ileride SATIN ALINABILIR olacak. Gercek parayla
## alinmis bir bakiyenin, "ilerlemeyi sifirla" ya da bir kayit bozulmasi
## yuzunden silinmesi kabul edilemez. ProgressStore'dan ayri tutmak bu iki
## riski birden kaldirir: reset() bu dosyaya dokunmaz ve ilerleme dosyasi
## bozulsa bile bakiye yerinde kalir.
##
## SU AN SATIN ALMA YOK. Burada bakiye, harcama, kazanma ve acilan ipuclari vardir;
## magaza/faturalandirma eklendiginde tek yapilacak sey [method add] cagiran
## bir odeme dogrulayicisi yazmaktir. Bakiyeyi degistiren baska hicbir yol
## olmamali - tek giris noktasi bu sinif.
##
## GUVENLIK NOTU: bu dosya CIHAZDA duruyor ve kurcalanabilir. Sunucu tarafli
## dogrulama olmadan Luma Coin "guvenli" degildir; bu kabul edilmis bir tercih,
## cunku Luma Coin yalnizca IPUCU aciyor - rekabetci bir sey degil. Gercek para
## akisi eklendiginde bakiyenin sunucuda tutulmasi gerekir.

const SAVE_PATH := "user://wallet.cfg"
const SECTION := "wallet"
const KEY_BALANCE := "gold"
const KEY_SPENT := "gold_spent_total"
const KEY_EARNED := "gold_earned_total"
const KEY_HINT_UNLOCKS := "hint_unlocks"
const KEY_OWNED_COSMETICS := "owned_cosmetics"
const KEY_SELECTED_COSMETICS := "selected_cosmetics"
const KEY_SCHEMA := "wallet_schema"

## Cuzdan dosyasinin yapisi. 2: kozmetik sahipligi ve secimi eklendi.
## v1 -> v2 icin VERI DONUSUMU GEREKMEZ; eksik anahtarlar savunmaci okunur ve
## oyuncu yalnizca varsayilan kozmetiklere sahip sayilir. Numara yine de artti
## cunku surumun anlami "bu dosyayi hangi alan kumesini bilen surum yazdi".
const SCHEMA_VERSION := 2

## Yeni oyuncuya verilen baslangic bakiyesi. Ipucu sistemini bir kez BEDAVA
## denemesi icin: hic denemeden "para ister" diyen bir ozellik reddedilir.
const STARTING_LUMA_COINS := 3

var balance := STARTING_LUMA_COINS
## Toplamlar yalnizca raporlama/analiz icin tutulur; oynanisi etkilemez.
var spent_total := 0
var earned_total := 0
## Anahtar LevelData.uid() degeridir. Dictionary kullanimi tekrar acmayi
## idempotent yapar; diske sirali PackedStringArray olarak yazilir.
## Satin alinmis kozmetik kimlikleri (varsayilanlar burada TUTULMAZ: onlar
## zaten herkeste acik, kayda yazmak dosyayi sisirirdi).
var _owned_cosmetics: Dictionary = {}
## Tur kimligi ("ball") -> secili kozmetik kimligi.
var _selected_cosmetics: Dictionary = {}
var _hint_unlocks: Dictionary = {}
var _save_path := SAVE_PATH


static func load_from_disk() -> WalletStore:
	return load_from_path(SAVE_PATH)


## Testler gercek oyuncu cuzdanina dokunmadan ayni kod yolunu kullanabilsin.
static func load_from_path(path: String) -> WalletStore:
	var store := WalletStore.new()
	store._save_path = path
	var config := ConfigFile.new()
	if config.load(path) != OK:
		# Dosya yok: ilk calistirma. Baslangic bakiyesi verilir ve HEMEN yazilir,
		# yoksa oyuncu her acilista yeniden 3 Coin alirdi.
		store.save()
		return store
	store.balance = _read_int(config, KEY_BALANCE, STARTING_LUMA_COINS)
	store.spent_total = _read_int(config, KEY_SPENT, 0)
	store.earned_total = _read_int(config, KEY_EARNED, 0)
	store._load_hint_unlocks(config)
	store._load_cosmetics(config)
	return store


static func _read_int(config: ConfigFile, key: String, fallback: int) -> int:
	var raw: Variant = config.get_value(SECTION, key, fallback)
	if raw is int or raw is float:
		return maxi(int(raw), 0)
	return fallback


func save() -> Error:
	var config := ConfigFile.new()
	config.set_value(SECTION, KEY_BALANCE, balance)
	config.set_value(SECTION, KEY_SPENT, spent_total)
	config.set_value(SECTION, KEY_EARNED, earned_total)
	var unlocks := PackedStringArray(_hint_unlocks.keys())
	unlocks.sort()
	config.set_value(SECTION, KEY_HINT_UNLOCKS, unlocks)
	config.set_value(SECTION, KEY_SCHEMA, SCHEMA_VERSION)
	var owned := PackedStringArray(_owned_cosmetics.keys())
	owned.sort()
	config.set_value(SECTION, KEY_OWNED_COSMETICS, owned)
	config.set_value(SECTION, KEY_SELECTED_COSMETICS, _selected_cosmetics)
	var error := config.save(_save_path)
	if error != OK:
		push_warning("WalletStore: bakiye yazilamadi (hata %d)." % error)
	return error


func can_afford(amount: int) -> bool:
	return amount >= 0 and balance >= amount


## Harcar ve true doner. Bakiye YETMIYORSA hicbir sey yapmaz ve false doner -
## cagiran once can_afford sormak zorunda degil, ama sonuca BAKMAK zorunda.
func spend(amount: int) -> bool:
	if amount <= 0 or not can_afford(amount):
		return false
	balance -= amount
	spent_total += amount
	save()
	return true


func is_hint_unlocked(level_uid: String) -> bool:
	return _hint_unlocks.has(level_uid.strip_edges())


## Harcama ve kilit acma TEK save icinde yapilir. Ayni bolum ikinci kez
## acilirsa true doner ama bakiyeye dokunmaz; boylece cift dokunus ucret kesmez.
func unlock_hint(level_uid: String, cost: int) -> bool:
	var clean_uid := level_uid.strip_edges()
	if clean_uid.is_empty():
		return false
	if is_hint_unlocked(clean_uid):
		return true
	if cost <= 0 or not can_afford(cost):
		return false

	var previous_balance := balance
	var previous_spent := spent_total
	balance -= cost
	spent_total += cost
	_hint_unlocks[clean_uid] = true
	if save() == OK:
		return true

	# Yazma basarisizsa calisan oturum da diskte olmayan bir satin almayi
	# basarili sanmasin; bellek durumunu geri al.
	balance = previous_balance
	spent_total = previous_spent
	_hint_unlocks.erase(clean_uid)
	return false


## Luma Coin ekler (odul, satin alma, telafi). Tek giris noktasi burasi.
func add(amount: int) -> void:
	if amount <= 0:
		return
	balance += amount
	earned_total += amount
	save()


# --- Kozmetikler --------------------------------------------------------------
#
# SIFIRLAMA ANLAMI - bilerek: "ilerlemeyi sifirla" kozmetik sahipligini
# SILMEZ. Cuzdan ProgressStore'dan AYRI bir dosyadir ve ProgressStore.reset()
# ona hic dokunmaz. Gerekce: kozmetik SATIN ALINMIS bir seydir, kazanilmis bir
# ilerleme degil. Bolumlerini sifirlayan oyuncunun 215 Coin'e aldigi hedef
# efektini de kaybetmesi, sifirlamayi cezaya cevirirdi. Bugun Coin yalnizca
# oyun ici kazanildigi icin bu tercih; ileride GERCEK PARAYLA Coin satilirsa
# bu davranis zorunluluk haline gelir ve bakiyenin sunucuda tutulmasi gerekir
# (bkz. dosya basligindaki guvenlik notu).

func owns(cosmetic_id: String) -> bool:
	var item := CosmeticCatalog.find(cosmetic_id)
	if item == null:
		return false
	# Varsayilanlar herkeste aciktir ve kayda yazilmaz.
	return item.is_default or _owned_cosmetics.has(cosmetic_id)


## Satin alir. Basarisizsa HICBIR SEY degismez ve false doner.
##
## Ayni esyaya ikinci kez odeme YOK: cift dokunus, yavas arayuz ya da
## yarisan bir sinyal ikinci kez cagirsa bile bakiye tek kez duser.
func purchase_cosmetic(cosmetic_id: String) -> bool:
	var item := CosmeticCatalog.find(cosmetic_id)
	if item == null or item.is_default:
		return false
	if owns(cosmetic_id):
		return false
	if not spend(item.price):
		return false
	_owned_cosmetics[cosmetic_id] = true
	save()
	return true


## Sahip olunmayan bir esya SECILEMEZ; aksi halde magazayi atlayip bedava
## kullanmanin yolu acilirdi.
func select_cosmetic(cosmetic_id: String) -> bool:
	var item := CosmeticCatalog.find(cosmetic_id)
	if item == null or not owns(cosmetic_id):
		return false
	if String(_selected_cosmetics.get(item.kind_id(), "")) == cosmetic_id:
		return false
	_selected_cosmetics[item.kind_id()] = cosmetic_id
	save()
	return true


## Bir tur icin secili esya. Secim yoksa ya da kayittaki kimlik artik
## katalogda yoksa VARSAYILANA duser - eski bir kayit oyunu gorunumsuz
## birakmamali.
func selected_cosmetic(kind: CosmeticData.Kind) -> CosmeticData:
	var stored := String(_selected_cosmetics.get(
		String(CosmeticData.KIND_IDS.get(kind, "")), ""))
	if not stored.is_empty() and owns(stored):
		var item := CosmeticCatalog.find(stored)
		if item != null and item.kind == kind:
			return item
	return CosmeticCatalog.find(CosmeticCatalog.default_id(kind))


func selected_cosmetic_id(kind: CosmeticData.Kind) -> String:
	var item := selected_cosmetic(kind)
	return item.id if item != null else ""


func owned_cosmetic_count() -> int:
	return _owned_cosmetics.size()


func _load_cosmetics(config: ConfigFile) -> void:
	var raw_owned: Variant = config.get_value(SECTION, KEY_OWNED_COSMETICS, PackedStringArray())
	if raw_owned is PackedStringArray or raw_owned is Array:
		for value in raw_owned:
			var id := String(value)
			# Katalogdan KALKMIS bir kimlik sessizce atilir: eski bir surumde
			# alinmis ama artik var olmayan esya, oyunu bozmamali.
			if CosmeticCatalog.find(id) != null:
				_owned_cosmetics[id] = true
	var raw_selected: Variant = config.get_value(SECTION, KEY_SELECTED_COSMETICS, {})
	if raw_selected is Dictionary:
		for key in raw_selected:
			_selected_cosmetics[String(key)] = String(raw_selected[key])


func _load_hint_unlocks(config: ConfigFile) -> void:
	_hint_unlocks.clear()
	var raw: Variant = config.get_value(SECTION, KEY_HINT_UNLOCKS, PackedStringArray())
	if not (raw is PackedStringArray or raw is Array):
		return
	for value in raw:
		var clean := String(value).strip_edges()
		if not clean.is_empty():
			_hint_unlocks[clean] = true
