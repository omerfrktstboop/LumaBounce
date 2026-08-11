class_name CoinEconomy
extends RefCounted

## Luma Coin KAZANMA kurallarinin tek yeri.
##
## NEDEN AYRI SINIF: kurallar daha once AppRoot'un icine gomuluydu ("her ilk
## bitiriste +1"). Denge degistikce o satirin etrafindaki kosullar buyuyecek
## ve ekonomi navigasyon kodunun icine dagilacakti. Burasi saf hesap yapar:
## girdi ilerleme durumu, cikti kac Coin. Yazma isi cagirana (AppRoot) aittir.
##
## HARCAMA (sink) tarafi bilerek burada DEGIL: harcamalar kendi ozelliklerinin
## icinde durur (ipucu maliyeti Gameplay'de, kozmetik fiyati CosmeticData'da),
## cunku her birinin baglami farkli. Burasi yalnizca KAZANC.

## --- Kazanc tablosu ---
## Bir kural eklerken karsiligini SORMALI: oyuncu bunu nasil tetikler?
## Tetikleyicisi olmayan bir kural, olmayan bir gelirdir.
const STARTING_COINS := 3
## Her N YENI normal bolum tamamlandiginda verilen odul.
const NORMAL_LEVEL_STEP := 5
const NORMAL_LEVEL_REWARD := 2
## Her N. bolumde (10, 20, 30...) ILK KEZ 3 yildiz alindiginda.
const MILESTONE_STEP := 10
const MILESTONE_THREE_STAR_REWARD := 1
## Bonus bolumun ilk kez bitirilmesi.
const BONUS_FIRST_CLEAR_REWARD := 3
## Gunluk giris ve gunluk gorevlerin tamami.
const DAILY_LOGIN_REWARD := 2
const DAILY_QUESTS_COMPLETE_REWARD := 2
## Odullu reklam basina ve gunluk tavan.
const REWARDED_BONUS_REWARD := 1
const REWARDED_BONUS_DAILY_CAP := 3


## Bir bolum tamamlandiginda kazanilan Coin.
##
## [param completed_normal_count] bu bolum de sayilmis halde, tamamlanmis
## NORMAL (bonus olmayan) bolum sayisi.
## [param first_clear] bu bolum ilk kez mi bitirildi.
## [param first_three_star] bu bolumde ilk kez mi 3 yildiz alindi.
##
## Tum kosullar BIRLIKTE degerlendirilir: 10. bolumu ilk kez 3 yildizla
## bitiren oyuncu hem esik odulunu hem kilometre tasi odulunu alir.
static func level_complete_reward(level_id: int, completed_normal_count: int,
		first_clear: bool, first_three_star: bool) -> int:
	var total := 0
	var is_bonus := LevelWorlds.is_bonus_id(level_id)

	if first_clear:
		if is_bonus:
			total += BONUS_FIRST_CLEAR_REWARD
		elif completed_normal_count > 0 and completed_normal_count % NORMAL_LEVEL_STEP == 0:
			# Her bolum degil, her BESINCI bolum: kucuk ve surekli bir damla
			# yerine hissedilir bir odul. Yalnizca ILK bitiriste sayilir,
			# yoksa ayni bolumu tekrar oynayarak Coin basilirdi.
			total += NORMAL_LEVEL_REWARD

	# Kilometre tasi bolumleri (10, 20, ...) ilk 3 yildizda ayrica oduldur -
	# bu odul ilk bitirise BAGLI DEGILDIR: oyuncu bolumu once 1 yildizla
	# gecip sonra donup 3 yildiz yapabilir.
	if first_three_star and not is_bonus and level_id % MILESTONE_STEP == 0:
		total += MILESTONE_THREE_STAR_REWARD
	return total


## Bugun kac odullu bonus daha alinabilir.
static func rewarded_bonus_remaining(claimed_today: int) -> int:
	return maxi(REWARDED_BONUS_DAILY_CAP - maxi(claimed_today, 0), 0)


static func can_claim_rewarded_bonus(claimed_today: int) -> bool:
	return rewarded_bonus_remaining(claimed_today) > 0
