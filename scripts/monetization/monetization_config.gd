class_name MonetizationConfig
extends RefCounted

## SDK bagimsiz monetization urun sozlesmesinin tek sabit kaynagi.
## Provider adapterleri bu placement/context adlarini SDK birimlerine cevirir;
## Gameplay veya AppRoot gercek reklam birimi kimligi bilmez.

const PLACEMENT_FULL_HINT := &"full_hint"
## Magazadaki "reklam izle, Coin kazan" karti. Istege bagli bir oduldur;
## remove_ads satin alan oyuncuya da acik kalir (yalnizca gecis reklamlari kapanir).
const PLACEMENT_COIN_BONUS := &"coin_bonus"

const PRODUCT_REMOVE_ADS := &"remove_ads"

const CONTEXT_LEVEL_COMPLETE := &"level_complete"
const CONTEXT_LEVEL_FAIL := &"level_fail"

const COMPLETIONS_PER_INTERSTITIAL := 5
## Yeni oyuncu ilk N normal bolumu hic ara reklam gormeden oynar (takilma
## reklami dahil). Ilk reklam N. bolumun ardindan, sonrasi her
## COMPLETIONS_PER_INTERSTITIAL bolumde bir. Gerekce: ilk bolumler kisa;
## sayac 1. bolumden baslayinca ilk reklam oyunun ilk 3-4 dakikasina,
## oyuncu henuz baglanmadan denk geliyordu.
const FIRST_INTERSTITIAL_AFTER_LEVELS := 10
const FAILURE_INTERSTITIAL_INTERVAL_SEC := 600.0
const INTERSTITIAL_GLOBAL_COOLDOWN_SEC := 180.0
const AD_POLICY_STATE_PATH := "user://ad_policy_state.cfg"


static func is_rewarded_placement(placement: StringName) -> bool:
	return placement in [PLACEMENT_FULL_HINT, PLACEMENT_COIN_BONUS]
