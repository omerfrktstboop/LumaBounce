class_name WalletStore
extends RefCounted

## Oyuncunun ALTIN bakiyesi: user://wallet.cfg.
##
## NEDEN AYRI DOSYA: altin ileride SATIN ALINABILIR olacak. Gercek parayla
## alinmis bir bakiyenin, "ilerlemeyi sifirla" ya da bir kayit bozulmasi
## yuzunden silinmesi kabul edilemez. ProgressStore'dan ayri tutmak bu iki
## riski birden kaldirir: reset() bu dosyaya dokunmaz ve ilerleme dosyasi
## bozulsa bile bakiye yerinde kalir.
##
## SU AN SATIN ALMA YOK. Burada yalnizca bakiye, harcama ve kazanma vardir;
## magaza/faturalandirma eklendiginde tek yapilacak sey [method add] cagiran
## bir odeme dogrulayicisi yazmaktir. Bakiyeyi degistiren baska hicbir yol
## olmamali - tek giris noktasi bu sinif.
##
## GUVENLIK NOTU: bu dosya CIHAZDA duruyor ve kurcalanabilir. Sunucu tarafli
## dogrulama olmadan altin "guvenli" degildir; bu kabul edilmis bir tercih,
## cunku altin yalnizca IPUCU aciyor - rekabetci bir sey degil. Gercek para
## akisi eklendiginde bakiyenin sunucuda tutulmasi gerekir.

const SAVE_PATH := "user://wallet.cfg"
const SECTION := "wallet"
const KEY_BALANCE := "gold"
const KEY_SPENT := "gold_spent_total"
const KEY_EARNED := "gold_earned_total"

## Yeni oyuncuya verilen baslangic altini. Ipucu sistemini bir kez BEDAVA
## denemesi icin: hic denemeden "para ister" diyen bir ozellik reddedilir.
const STARTING_GOLD := 3

var balance := STARTING_GOLD
## Toplamlar yalnizca raporlama/analiz icin tutulur; oynanisi etkilemez.
var spent_total := 0
var earned_total := 0


static func load_from_disk() -> WalletStore:
	var store := WalletStore.new()
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		# Dosya yok: ilk calistirma. Baslangic altini verilir ve HEMEN yazilir,
		# yoksa oyuncu her acilista yeniden 3 altin alirdi.
		store.save()
		return store
	store.balance = _read_int(config, KEY_BALANCE, STARTING_GOLD)
	store.spent_total = _read_int(config, KEY_SPENT, 0)
	store.earned_total = _read_int(config, KEY_EARNED, 0)
	return store


static func _read_int(config: ConfigFile, key: String, fallback: int) -> int:
	var raw: Variant = config.get_value(SECTION, key, fallback)
	if raw is int or raw is float:
		return maxi(int(raw), 0)
	return fallback


func save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, KEY_BALANCE, balance)
	config.set_value(SECTION, KEY_SPENT, spent_total)
	config.set_value(SECTION, KEY_EARNED, earned_total)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("WalletStore: bakiye yazilamadi (hata %d)." % error)


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


## Altin ekler (odul, satin alma, telafi). Tek giris noktasi burasi.
func add(amount: int) -> void:
	if amount <= 0:
		return
	balance += amount
	earned_total += amount
	save()
