# Monetization Architecture

FAZ 2 keeps gameplay independent from AdMob, Play Billing, and analytics SDKs. `AppRoot` is the composition root: it owns one `EntitlementStore`, `AnalyticsService`, `AdPolicy`, and `AdService` for the application session, then injects only product-level services into `Gameplay`. This avoids global autoload state and lets headless tests replace the provider deterministically.

## Runtime contract

- `AdService.initialize()` initializes the configured provider.
- `is_rewarded_ready(placement)` reports a voluntary offer without waiting.
- `show_rewarded(placement)` returns `earned`, `closed_without_reward`, `failed`, or `unavailable`.
- `is_interstitial_ready()` includes provider readiness and the no-ads entitlement.
- `maybe_show_interstitial(context, candidate)` applies policy and returns immediately when blocked or unavailable.
- `EntitlementStore` caches `remove_ads` separately in `user://entitlements.cfg`; it does not change `ProgressStore` or the save schema.
- `AnalyticsService` accepts only normalized product events. It logs locally in debug builds and performs no network calls.

`ResultPanel` currently stores only `revive_offer_eligible` and `interstitial_candidate` hooks. It does not render an ad button or start an ad. Failure and retry contexts can never pass `AdPolicy` v1.

## Provider adapter seam

`NoOpAdProvider` is the current runtime provider; `tools/mocks/mock_ad_provider.gd` is test-only. In the next phase, add an adapter such as `scripts/monetization/providers/admob_ad_provider.gd` implementing `AdProvider`, and select it only in `AppRoot._setup_monetization()`. Keep plugin classes, ad unit IDs, and callbacks inside that adapter. A future Billing adapter should verify purchases and call `EntitlementStore.update_remove_ads()`; Gameplay and MainMenu must remain unchanged.

Run the focused suite with:

```powershell
godot --headless --path . --script res://tools/check_monetization_phase2.gd
```
