# Monetization Architecture

`AppRoot` is the composition root for `EntitlementStore`, `AnalyticsService`, `AdPolicy`, and `AdService`. Android uses `AdmobAdProvider`; desktop/editor builds safely fall back to `NoOpAdProvider`. Gameplay sees only product-level placement names and never imports a Google SDK class. The normalized analytics contract, provider quarantine, privacy filter, and dashboards are documented in `docs/ANALYTICS.md`.

## Runtime contract

- `show_rewarded(short_hint)` grants the first route move only after `earned`.
- `request_interstitial(level_complete)` runs at the result transition after every third successful normal-level completion.
- `request_interstitial(level_fail)` becomes eligible after 600 seconds of active failed-attempt playtime on the same normal level and runs only at a failure result transition.
- Completion and failure candidates share a 180-second global cooldown. Unloaded/failed ads never block gameplay and keep the candidate for a later natural transition.
- The completion counter survives sessions in `user://ad_policy_state.cfg`; failure playtime is session-only and resets on success or level change.
- `remove_ads` disables interstitials but keeps voluntary rewarded offers.
- Missing or unloaded ads return immediately without blocking play.

## AdMob and consent

The vendored `godot-sdk-integrations/godot-admob` v7.0 plugin lives under `addons/AdmobPlugin` and `addons/GMPShared`. `LumaAdmobConfig` is the only source for application/ad-unit IDs. The `production` export feature selects live IDs; debug APKs always use Google's demo rewarded and interstitial IDs.

UMP consent information is refreshed on every Android launch before Mobile Ads initialization. A required form is loaded and shown first. If consent has no usable current or cached state, the adapter fails closed and requests no production ads. For affected users, Settings exposes **Privacy options** so choices can be reopened. UMP propagates the selected personalization state to Google Mobile Ads.

No consent value is written to `ProgressStore`; UMP owns its storage, so the save schema is unchanged.

## Google Play Billing

The official `GodotGooglePlayBilling` 3.3.0 plugin is vendored under
`addons/GodotGooglePlayBilling` and exports Google Play Billing Library 9.1.0.
V1 exposes only the one-time, non-consumable Play product `remove_ads`; coin
packs and subscriptions are deliberately out of scope.

`PurchaseService` queries Play for the localized price, restores owned purchases
at launch and resume, rejects `PENDING` purchases, grants the entitlement only
for `PURCHASED`, and then acknowledges an unacknowledged purchase. A successful
authoritative restore with no owned `remove_ads` purchase revokes a stale local
cache; an offline/failed query keeps the last cache so paid users are not
temporarily penalized. Purchase tokens never enter analytics or `ProgressStore`.

The implementation is client-side for V1. It is suitable for the simple
`remove_ads` entitlement, but future consumable coin products require backend
purchase verification and an authoritative server balance.

## Verification

```powershell
godot --headless --path . --script res://tools/check_monetization_phase2.gd
godot --headless --path . --script res://tools/check_billing_phase7.gd
godot --headless --path . --script res://tools/check_analytics_phase10.gd
godot --headless --path . --script res://tools/check_release_readiness.gd
```

Before a production upload, verify the consent form, rewarded hint cancellation/failure/earned result, both interstitial paths and their shared cooldown, privacy-options entry point, purchase, pending purchase, acknowledgment, and restore on a physical Android license-test device. Do not click production ads during development.
