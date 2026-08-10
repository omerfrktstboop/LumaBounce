# Repository Guidelines

## Project Structure & Module Organization

LumaBounce is a Godot 4.7 portrait-mobile puzzle game. `scenes/app_root.tscn` owns the screen flow. Keep runtime GDScript in `scripts/`; level models and simulation code belong in `scripts/levels/`, UI components in `scripts/ui/`, and debug editor code in `scripts/editor/`. Scene files live in `scenes/`, level resources follow `levels/level_NNN.tres`, and translations/audio live under `assets/`. Validation and generation utilities are in `tools/`. `tests/` is reserved; active regression suites are tool scripts. Design context belongs in `docs/`.

## Build, Test, and Development Commands

Godot may not be on `PATH`; replace `godot` with the local Godot 4.7 executable when necessary.

- `godot --path .` launches the project locally.
- `godot --headless --path . --quit-after 200` catches boot-time script and scene errors.
- `godot --headless --editor --path . --quit` refreshes imports and global `class_name` registrations.
- `godot --headless --path . --script res://tools/check_blocks_and_gate.gd` runs the main gameplay regression suite.
- `godot --headless --path . --script res://tools/verify_levels.gd -- --level 21` checks level solvability; omit `--level` for the campaign.
- `godot --headless --path . --script res://tools/check_obstacles.gd` validates obstacle behavior and level coverage.
- `godot --headless --path . --export-debug Android builds/lumabounce-debug.apk` creates the configured Android debug export.

## Coding Style & Naming Conventions

Follow Godot/GDScript conventions: tabs for indentation, `snake_case` for files, functions, signals, and variables; `PascalCase` for `class_name` types; and `UPPER_SNAKE_CASE` for constants. Add static types where practical and use `:=` when inference is clear. Match scene and controller names (`main_menu.tscn` / `main_menu.gd`). Keep screen navigation in `AppRoot`; screens emit signals instead of instantiating one another. For localized format strings, translate before interpolation: `tr("BOLUM %d") % id`.

## Testing Guidelines

There is no coverage percentage or external test framework. Every behavior change should receive a focused assertion in the relevant `tools/check_*.gd` suite. Run the boot check plus affected suites before submitting. Level changes must pass `verify_levels.gd`; AI pipeline changes should run `check_ai_phase1.gd` through `check_ai_phase4.gd`. Never run `probe_openrouter_live.gd` unintentionally: it performs a paid network call.

## Commit & Pull Request Guidelines

Recent history uses short, imperative, sentence-case subjects such as `Fix moving obstacles animating during aim phase`. Keep commits focused and avoid committing generated `.godot/`, `builds/`, APK/AAB files, logs, or signing secrets. Pull requests should explain player-visible impact, list validation commands, link relevant issues, and include screenshots or video for UI/gameplay changes. Call out changed levels and localization rows explicitly.
