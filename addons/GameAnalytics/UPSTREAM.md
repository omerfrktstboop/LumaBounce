# Upstream

- Source: https://github.com/GameAnalytics/GA-SDK-GODOT
- Tag: `3.1.0`
- Commit: `305e2d791689d99ee5f13a86a1fc1355059a5c60`
- Android Maven dependency: `com.gameanalytics.sdk:gameanalytics-android:7.0.1`
- Retrieved: 2026-08-11

The official Godot Asset Library marks 3.1.0 as unstable. Its Windows binary
also prevents LumaBounce's Godot 4.7.1 headless checks from starting. The Android
descriptor is therefore stored as `GameAnalytics.gdextension.disabled`, and the
editor export plugin is not enabled in `project.godot`. Keep the provider feature
flag off until an upgraded SDK passes the Phase 10 and Android device checks.
