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
##
## DENGE (Ekim 2026): eski tabloda 200 bolumun tamami ~100 Coin ediyordu, magaza
## ise 1080 Coin'di - 50 bolum oynayan biri hicbir sey alamiyordu. Simdi her
## ilk bitiris ve her ilk 3 yildiz +1, her 10. bolum ayrica +3: kampanya
## 260-460 Coin, magaza 660 Coin. Odullu reklam gunde 25 Coin'e kadar ekler.
const STARTING_COINS := 3
## Normal bir bolumun ILK bitirisi.
const FIRST_CLEAR_REWARD := 1
## Normal bir bolumde ILK KEZ 3 yildiz. Ilk bitirise bagli degildir: oyuncu
## once 1 yildizla gecip sonra donup 3 yildiz yapabilir.
const THREE_STAR_REWARD := 1
## Her N. bolumun (10, 20, 30...) ilk bitirisinde ek, hissedilir bir odul.
const MILESTONE_STEP := 10
const MILESTONE_CLEAR_REWARD := 3
## Bonus bolumun ilk kez bitirilmesi.
const BONUS_FIRST_CLEAR_REWARD := 3
## Gunluk giris ve gunluk gorevlerin tamami.
const DAILY_LOGIN_REWARD := 2
const DAILY_QUESTS_COMPLETE_REWARD := 2
## Magazadaki odullu reklam basina ve gunluk tavan.
const REWARDED_BONUS_REWARD := 5
const REWARDED_BONUS_DAILY_CAP := 5


## Bir bolum tamamlandiginda kazanilan Coin.
##
## [param completed_normal_count] bu bolum de sayilmis halde, tamamlanmis
## NORMAL (bonus olmayan) bolum sayisi.
## [param first_clear] bu bolum ilk kez mi bitirildi.
## [param first_three_star] bu bolumde ilk kez mi 3 yildiz alindi.
##
## Tum kosullar BIRLIKTE degerlendirilir: 10. bolumu ilk kez 3 yildizla
## bitiren oyuncu ilk bitiris, 3 yildiz ve kilometre tasi odulunun hepsini alir.
## Odullerin hepsi "ILK" kosuluna baglidir; ayni bolumu tekrar oynayarak
## Coin basilamaz.
##
## [param completed_normal_count] imza uyumu icin korunur; kurallar artik
## bolum numarasina bakar.
static func level_complete_reward(level_id: int, _completed_normal_count: int,
		first_clear: bool, first_three_star: bool) -> int:
	var total := 0
	if LevelWorlds.is_bonus_id(level_id):
		return BONUS_FIRST_CLEAR_REWARD if first_clear else 0
	if first_clear:
		total += FIRST_CLEAR_REWARD
		if level_id % MILESTONE_STEP == 0:
			total += MILESTONE_CLEAR_REWARD
	if first_three_star:
		total += THREE_STAR_REWARD
	return total


## Bugun kac odullu bonus daha alinabilir.
static func rewarded_bonus_remaining(claimed_today: int) -> int:
	return maxi(REWARDED_BONUS_DAILY_CAP - maxi(claimed_today, 0), 0)


static func can_claim_rewarded_bonus(claimed_today: int) -> bool:
	return rewarded_bonus_remaining(claimed_today) > 0
