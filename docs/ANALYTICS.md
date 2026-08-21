# Analytics Architecture

`AppRoot` owns `AnalyticsService` and injects it into gameplay, ads, billing, and
the shop. These consumers only emit product events; no GameAnalytics class or SDK
identifier is allowed outside `scripts/analytics/`. Events are queued and sent
with `call_deferred`, so provider latency or failure never blocks a frame.

## Provider status

The evaluated provider is the official GameAnalytics Godot SDK 3.1.0 (upstream
commit `305e2d791689d99ee5f13a86a1fc1355059a5c60`, Android SDK 7.0.1). It requires
Godot 4.5+, but the publisher marks it unstable and its Windows binary fails the
Godot 4.7.1 headless workflow. The native descriptor is therefore quarantined as
`addons/GameAnalytics/GameAnalytics.gdextension.disabled`; production currently
falls back to `NoOpAnalyticsProvider` without delaying play. Do not switch to
Firebase automatically.

When a compatible official release is available, replace the pinned addon,
restore its active `.gdextension`, enable `addons/GameAnalytics/plugin.cfg`, and
run every check below plus an internal Android dashboard test. Copy
`gameanalytics.example.cfg` to ignored `gameanalytics.cfg` and set:

```ini
[analytics]
enabled=true
environment="staging"
game_key="..."
secret_key="..."
collection_enabled=true
```

Debug builds reject `environment="production"`. Use a separate GameAnalytics
game for staging; the build dimension is also suffixed with `-staging` or
`-production`.

## Event contract

| Area | Normalized events | Bounded fields |
|---|---|---|
| Session | `session_start`, `session_end` | build/environment/provider, duration bucket, reason |
| Level | `level_start`, `level_complete`, `level_fail`, `restart` | level, world, bonus, stars, seconds/shots buckets, first clear, fail reason |
| Hint/rewarded | `hint_offer_open`, `short_hint_rewarded_earned`, `full_hint_unlock`, `rewarded_offer`, `rewarded_click`, `rewarded_result` | level, placement, provider, result, Coin cost |
| Interstitial | `interstitial_candidate`, `interstitial_shown`, `interstitial_failed` | context, provider, bounded reason |
| Commerce | `remove_ads_purchase_result`, `shop_open`, `cosmetic_purchase`, `cosmetic_select` | product/cosmetic, action/result, kind, price/balance |
| Daily hooks | `daily_open`, `daily_complete`, `quest_complete`, `streak_milestone` | day, reward, quest enum, streak bucket |

Daily/quest events are contract-only because the repository has no daily system;
they must be emitted only when that feature exists.

## Privacy and consent

`AnalyticsService` drops unknown fields and accepts only booleans, finite numbers,
and 64-character tokens from an event-specific allowlist. Never send purchase
tokens, email, advertising ID, save IDs, raw device identifiers, stack traces, or
free-form errors. GameAnalytics is configured for a randomized SDK identifier and
SDK error reporting is disabled.

Analytics collection consent is independent from AdMob UMP. A future consent UI
must call `set_collection_enabled()` separately; no consent value is currently
persisted and the save schema remains unchanged.

## First dashboards

1. Onboarding: `session_start -> level_start -> first_clear level_complete`.
2. Level health: starts versus completes, fails, restarts, time and shot buckets.
3. Rewarded: offer -> click -> result -> earned, split by placement.
4. Interstitial: candidate -> shown/failed, with show and failure rates.
5. Store: shop open -> cosmetic purchase/select and remove-ads result.

Validate staging events on a Play internal-test build, including app background /
resume, offline provider failure, cancelled rewarded, first clear, and
purchase restore. Production dashboards must never contain debug build events.

```powershell
godot --headless --path . --script res://tools/check_analytics_phase10.gd
godot --headless --path . --script res://tools/check_monetization_phase2.gd
godot --headless --path . --script res://tools/check_billing_phase7.gd
```
