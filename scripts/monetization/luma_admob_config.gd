class_name LumaAdmobConfig
extends RefCounted

## AdMob kimlikleri gizli anahtar degildir; uygulama paketinden zaten okunur.
## Tek kaynakta tutulmalari debug build'in yanlislikla canli reklam istemesini
## engeller. Production kimlikleri yalnizca `production` export feature'inda
## secilir; Android Debug her zaman Google'in resmi demo birimlerini kullanir.

const ANDROID_APP_ID := "ca-app-pub-4666663369729289~4144593249"

const REWARDED_EXTRA_BALL := "ca-app-pub-4666663369729289/9720473697"
const REWARDED_SHORT_HINT := "ca-app-pub-4666663369729289/3826129122"
const INTERSTITIAL_LEVEL_TRANSITION := "ca-app-pub-4666663369729289/7804902588"

const TEST_REWARDED := "ca-app-pub-3940256099942544/5224354917"
const TEST_INTERSTITIAL := "ca-app-pub-3940256099942544/1033173712"


static func production_ads_enabled() -> bool:
	return OS.has_feature("production") and not OS.is_debug_build()


static func rewarded_unit_id(placement: StringName) -> String:
	if not production_ads_enabled():
		return TEST_REWARDED
	match placement:
		MonetizationConfig.PLACEMENT_SHORT_HINT:
			return REWARDED_SHORT_HINT
		MonetizationConfig.PLACEMENT_REVIVE:
			return REWARDED_EXTRA_BALL
		_:
			return ""


static func interstitial_unit_id() -> String:
	return INTERSTITIAL_LEVEL_TRANSITION if production_ads_enabled() else TEST_INTERSTITIAL
