class_name MonetizationConfig
extends RefCounted

## SDK bagimsiz monetization urun sozlesmesinin tek sabit kaynagi.
## Provider adapterleri bu placement/context adlarini SDK birimlerine cevirir;
## Gameplay veya AppRoot gercek reklam birimi kimligi bilmez.

const PLACEMENT_SHORT_HINT := &"short_hint"
const PLACEMENT_REVIVE := &"revive"

const PRODUCT_REMOVE_ADS := &"remove_ads"

const CONTEXT_LEVEL_COMPLETE := &"level_complete"
const CONTEXT_LEVEL_FAIL := &"level_fail"
const CONTEXT_RETRY := &"retry"

const NORMAL_COMPLETIONS_WITHOUT_INTERSTITIAL := 5
const INTERSTITIAL_COMPLETION_INTERVAL := 4
const INTERSTITIAL_COOLDOWN_SECONDS := 180.0
const REWARDED_SUPPRESSION_SECONDS := 120.0


static func is_rewarded_placement(placement: StringName) -> bool:
	return placement in [PLACEMENT_SHORT_HINT, PLACEMENT_REVIVE]
