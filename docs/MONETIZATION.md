# Monetization Architecture

`AppRoot` is the composition root for `EntitlementStore`, `AnalyticsService`, `AdPolicy`, and `AdService`. Android uses `AdmobAdProvider`; desktop/editor builds safely fall back to `NoOpAdProvider`. Gameplay sees only product-level placement names and never imports a Google SDK class.

## Runtime contract

- `show_rewarded(short_hint)` grants the first route move only after `earned`.
- `show_rewarded(revive)` grants one extra ball once per failed attempt. Closing or failing the ad grants nothing.
- `maybe_show_interstitial(level_complete)` runs only when the player requests the next level and only after `AdPolicy` accepts the completion candidate.
- The first five normal completions are protected; later candidates follow the every-four, 180-second fullscreen cooldown, and 120-second rewarded suppression rules.
- `remove_ads` disables interstitials but keeps voluntary rewarded offers.
- Missing or unloaded ads return immediately without blocking play.

## AdMob and consent

The vendored `godot-sdk-integrations/godot-admob` v7.0 plugin lives under `addons/AdmobPlugin` and `addons/GMPShared`. `LumaAdmobConfig` is the only source for application/ad-unit IDs. The `production` export feature selects live IDs; debug APKs always use Google's demo rewarded and interstitial IDs.

UMP consent information is refreshed on every Android launch before Mobile Ads initialization. A required form is loaded and shown first. If consent has no usable current or cached state, the adapter fails closed and requests no production ads. For affected users, Settings exposes **Privacy options** so choices can be reopened. UMP propagates the selected personalization state to Google Mobile Ads.

No consent value is written to `ProgressStore`; UMP owns its storage, so the save schema is unchanged.

## Verification

```powershell
godot --headless --path . --script res://tools/check_monetization_phase2.gd
godot --headless --path . --script res://tools/check_release_readiness.gd
```

Before a production upload, verify the consent form, rewarded cancellation/failure, earned extra ball/hint, interstitial cadence, and privacy-options entry point on a physical Android test device. Do not click production ads during development.
