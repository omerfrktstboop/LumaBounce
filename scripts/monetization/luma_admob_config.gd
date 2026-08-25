class_name LumaAdmobConfig
extends RefCounted

## Kapali test donemi boyunca debug ve release paketlerinin ikisi de Google'in
## resmi demo kimliklerini kullanir. 14 gunluk test bittiginde asagidaki gercek
## kimlikleri yeniden etkinlestirip production secimini geri acin.
## const ANDROID_APP_ID := "ca-app-pub-4666663369729289~4144593249"
## const REWARDED_FULL_HINT := "ca-app-pub-4666663369729289/3826129122"
## const INTERSTITIAL_LEVEL_TRANSITION := "ca-app-pub-4666663369729289/7804902588"

const TEST_ANDROID_APP_ID := "ca-app-pub-3940256099942544~3347511713"
const TEST_REWARDED := "ca-app-pub-3940256099942544/5224354917"
const TEST_INTERSTITIAL := "ca-app-pub-3940256099942544/1033173712"
const ANDROID_APP_ID := TEST_ANDROID_APP_ID


static func production_ads_enabled() -> bool:
	# Kapali test bittiginde su satiri geri acin:
	# return OS.has_feature("production") and not OS.is_debug_build()
	return false


static func rewarded_unit_id(placement: StringName) -> String:
	match placement:
		MonetizationConfig.PLACEMENT_FULL_HINT:
			return TEST_REWARDED
		_:
			return ""


static func interstitial_unit_id() -> String:
	return TEST_INTERSTITIAL
