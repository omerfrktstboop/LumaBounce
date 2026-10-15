class_name LumaAdmobConfig
extends RefCounted

const TEST_ANDROID_APP_ID := "ca-app-pub-3940256099942544~3347511713"
const TEST_REWARDED := "ca-app-pub-3940256099942544/5224354917"
const TEST_INTERSTITIAL := "ca-app-pub-3940256099942544/1033173712"
const LIVE_ANDROID_APP_ID := "ca-app-pub-4666663369729289~4144593249"
const LIVE_REWARDED := "ca-app-pub-4666663369729289/3826129122"
const LIVE_INTERSTITIAL := "ca-app-pub-4666663369729289/7804902588"


static func production_ads_enabled() -> bool:
	return OS.has_feature("production") and not OS.is_debug_build()


static func rewarded_unit_id(placement: StringName) -> String:
	match placement:
		# Iki odullu yer ayni AdMob odullu birimini kullanir; ayri birim acmak
		# yalnizca raporlamayi bolerdi, odul yine oyun icinde ayrilir.
		MonetizationConfig.PLACEMENT_FULL_HINT, MonetizationConfig.PLACEMENT_COIN_BONUS:
			return LIVE_REWARDED if production_ads_enabled() else TEST_REWARDED
		_:
			return ""


static func interstitial_unit_id() -> String:
	return LIVE_INTERSTITIAL if production_ads_enabled() else TEST_INTERSTITIAL
