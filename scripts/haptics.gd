class_name Haptics
extends RefCounted

## Dokunsal geri bildirimin TEK cikis noktasi.
##
## NEDEN AYRI BIR SINIF: Input.vibrate_handheld() cagrilari oyunun her yerine
## dagilirsa "titresimi kapat" ayari eklemek imkansizlasir - biri mutlaka
## atlanir. Burasi tek suzgectir; hicbir yerde dogrudan vibrate_handheld
## cagrilmaz (tools/check_blocks_and_gate.gd bunu test eder).
##
## STATIC VAR: Palette ile ayni desen. AppRoot, ProgressStore'daki tercihi
## oyun acilirken buraya aktarir; boylece cagiranlarin ayardan haberi olmasi
## veya ProgressStore'a erisimi olmasi gerekmez.
##
## SURE OLCEGI: degerler kisa ve "tok" tutulur. Mobilde 100 ms'nin uzeri
## titresim oyuncuya geri bildirim degil ariza hissi verir; bu yuzden en uzun
## darbe (hedef) bile HIT_TARGET_MSEC ile sinirlidir.

## Tek tek olaylarin sureleri - hepsi tek yerde ki toplam his ayarlanabilsin.
const HIT_TARGET_MSEC := 90
const HIT_HAZARD_MSEC := 34
const HIT_BLOCK_MSEC := 12
## Sekme darbesi carpma siddetine gore bu araliga olceklenir (bkz. bounce()).
const BOUNCE_MIN_MSEC := 6
const BOUNCE_MAX_MSEC := 26
## Guvenlik tavani: hicbir cagri bunun uzerine cikamaz.
const MAX_MSEC := 120

## AppRoot tarafindan ProgressStore.haptics_enabled'dan atanir.
static var enabled := true


## Ham darbe. [param msec] 0 veya altiysa hicbir sey yapilmaz.
static func pulse(msec: int) -> void:
	if not enabled or msec <= 0:
		return
	Input.vibrate_handheld(mini(msec, MAX_MSEC))


## Sekme: darbe suresi carpma SIDDETIYLE orantilidir. Hafif bir siyirma ile
## sert bir carpismanin ayni hissi vermesi, geri bildirimi anlamsizlastirirdi.
## [param strength] 0..1 (gameplay.gd'de kivilcim/sarsinti ile ayni olcek).
static func bounce(strength: float) -> void:
	var ratio := clampf(strength, 0.0, 1.0)
	pulse(int(round(lerpf(float(BOUNCE_MIN_MSEC), float(BOUNCE_MAX_MSEC), ratio))))


## Hedef vurusu: bilerek en uzun darbe - "kazandin" ani digerlerinden
## AYIRT EDILEBILIR olmali.
static func target_hit() -> void:
	pulse(HIT_TARGET_MSEC)


## Bomba/hizlandirici gibi atisi bitiren temaslar.
static func hazard(fatal: bool = false) -> void:
	pulse(HIT_HAZARD_MSEC * (2 if fatal else 1))


## Kirilabilir tugla hasari - en hafif darbe, cunku bir atista birden cok kez
## olabilir.
static func block_damage() -> void:
	pulse(HIT_BLOCK_MSEC)
