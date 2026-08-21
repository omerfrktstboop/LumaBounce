class_name MonetizationConfig
extends RefCounted

## SDK bagimsiz monetization urun sozlesmesinin tek sabit kaynagi.
## Provider adapterleri bu placement/context adlarini SDK birimlerine cevirir;
## Gameplay veya AppRoot gercek reklam birimi kimligi bilmez.

const PLACEMENT_SHORT_HINT := &"short_hint"

const PRODUCT_REMOVE_ADS := &"remove_ads"

const CONTEXT_LEVEL_COMPLETE := &"level_complete"
const CONTEXT_LEVEL_FAIL := &"level_fail"

const COMPLETIONS_PER_INTERSTITIAL := 3
const FAILURE_INTERSTITIAL_INTERVAL_SEC := 600.0
const INTERSTITIAL_GLOBAL_COOLDOWN_SEC := 180.0
const AD_POLICY_STATE_PATH := "user://ad_policy_state.cfg"


static func is_rewarded_placement(placement: StringName) -> bool:
	return placement == PLACEMENT_SHORT_HINT
