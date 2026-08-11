class_name FeatureFlags
extends RefCounted

## Henuz tamamlanmamis ozelliklerin TEK acma/kapama noktasi.
##
## NEDEN VAR: yarim bir ozelligi koda serpistirip "su an calismiyor" yorumu
## birakmak, o ozelligin ne zaman yayina hazir oldugunu belirsiz birakir.
## Bayrak tek yerde durur; ozellik hazir oldugunda burada true yapilir ve
## baska hicbir yeri degistirmek gerekmez.
##
## KULLANIM KURALI: bayragi OKUYAN yer, ozelligi SUNAN yer degildir.
## AppRoot bayragi okur ve ekranlara enjekte eder; Gameplay yalnizca
## "kisa ipucu su an verilebilir mi" bilgisini alir, NEDENINI bilmez.
## Boylece reklam SDK'si eklendiginde Gameplay'e dokunulmaz.


## ODULLU REKLAMLA KISA IPUCU.
##
## false: kart acildiginda "KISA IPUCU" secenegi GORUNUR ama pasiftir ve
##        "yakinda" notu tasir. Oyuncu ozelligin var oldugunu bilir, ama
##        calismayan bir dugmeye basip hicbir sey olmamasiyla karsilasmaz.
## true : secenek etkinlesir. Reklam servisi baglanana kadar odul dogrudan
##        verilir (bkz. AppRoot._on_short_hint_requested).
##
## Bu fazda reklam SDK'si YOK, bu yuzden varsayilan false.
const REWARDED_SHORT_HINT := false


static func rewarded_short_hint_enabled() -> bool:
	return REWARDED_SHORT_HINT
