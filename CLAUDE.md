# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

LumaBounce is a Godot 4.7 portrait-mobile physics bounce-puzzle game (GDScript, GL Compatibility renderer). The player drags back a fixed launcher to fire a ball that bounces off panels/walls/obstacles into a target. 50 hand- and AI-authored levels, no external art/audio assets — everything is drawn procedurally (`ShapeBuilder`, `_draw()`) and synthesized (`tools/generate_sfx.py`).

No README, AGENTS.md, or Cursor/Copilot rule files exist in this repo — this file is the only project-level guidance.

## Commands

There is no traditional build/lint step. The Godot editor executable is not on PATH in this environment — locate the local `Godot_v4.7.1-stable_win64.exe` (or platform equivalent) before running any of the below; substitute `godot` for it here.

**Boot check (catches script/scene errors without playing):**
```
godot --headless --path . --quit-after 200
```

**Re-scan global class_name registrations** (needed after adding a new `class_name` script, since headless `--script` runs won't see it otherwise):
```
godot --headless --editor --path . --quit
```

**Run a dev tool / test suite** (all are `extends SceneTree` scripts under `tools/`, excluded from exported builds via `export_presets.cfg`'s `exclude_filter="tools/*"`):
```
godot --headless --path . --script res://tools/<name>.gd [-- --flag value ...]
```

Tool scripts and what they check:
- `verify_levels.gd` — the core solvability verifier; see Architecture below. Flags: `--level N` (single level), `--free-only` (block-free route only, for fast iteration), `--angle-step`/`--power-step`/`--block-angle-step`/`--block-power-step` (grid resolution).
- `check_blocks_and_gate.gd` — the general regression suite: debug panel, launcher feel, durable/multi-hit block state rules, practice/test mode, `CustomLevelStore` save/load/bulk-clipboard, the local `LevelGenerator`, the full level editor UI, star row rendering, attempt timer, level-select screen, the level-21 star gate, and `_test_library_bounds()` (authoritative check of level-arc structure — see Architecture).
- `check_obstacles.gd` — ring/bomb/wheel/moving-bar geometry, hazard detection, `.tres` round-trip, AI-obstacle mapping, that 41-50 collectively use only ring+bomb, and that 51-100 collectively exercise all four non-speed-boost obstacle kinds.
- `check_ai_phase1.gd` .. `check_ai_phase4.gd` — AI generation pipeline stages: prompt/contract/client plumbing (1), mapper field-clamping + solver variation/rescue logic (2), novelty/quality scoring + coordinator ranking (3), end-to-end editor UI + release-guard assertions (4).
- `probe_openrouter_live.gd` — opt-in **live network** probe against OpenRouter; reads `OPENROUTER_API_KEY`/`OPENROUTER_MODEL`/`OPENROUTER_BLUEPRINT_COUNT` from the process environment, never logs the key. Only run this deliberately — it makes a real paid API call.

**Regenerate synthetic SFX** (deterministic, stdlib-only):
```
py -3 tools/generate_sfx.py     # Windows — plain `python3` falls through to the Store stub
python3 tools/generate_sfx.py   # Linux/macOS
```
New sounds must be appended at the end of the `written` list in `main()` — the RNG is a single stream shared across all sound recipes, so inserting mid-list reshuffles every later sound's samples and rewrites unchanged WAVs.

**Android export**: single preset in `export_presets.cfg`, `arm64-v8a` only, package `com.lumabounce.game`, `gradle_build/use_gradle_build=false`. `permissions/internet=true` is required for the AI generator's OpenRouter calls, but that whole feature is `OS.is_debug_build()`-gated so it's unreachable in a release build regardless.

## Architecture

### Screen flow
`AppRoot` (`scripts/app_root.gd`, the only non-tool autoload-adjacent root; `AudioManager` is the sole real autoload) owns all screen transitions. **Screens never instantiate each other** — each screen only emits signals; AppRoot decides what happens and injects data (`level_data`, `progress`, etc.) into a screen instance *before* `add_child`, so it's ready in `_ready()`. Screens: splash → main menu → level select → gameplay, plus a debug-only level editor reachable only from the debug panel.

### Localization (`scripts/locale.gd`, `assets/i18n/*.csv`)
Source language is **Turkish**; `Locale` is the single exit point for `TranslationServer.set_locale` (same pattern and rationale as `Haptics`). Two CSV tables: `ui.csv` (interface) and `levels.csv` (125 level names + 13 tutorial strings).

**The translation key is the Turkish source string itself**, not a symbolic id. This is a deliberate maintenance trade-off: `LEVEL_042_NAME`-style keys would require touching all 125 `.tres` files and would make them unreadable, and the level generator writes `display_name` itself. With source-as-key, an untranslated string renders as *Turkish*, never blank. Verified safe because all 125 level names are unique.

Godot auto-translates `Control` text, so scene strings and plain `.text = "..."` assignments need no change. **The exception is format strings**: `tr()` must be called *before* `%`, because auto-translation looks up the finished text (`"BÖLÜM 5"`), which is not in the table. Correct form: `tr("BÖLÜM %d") % id`. There are four such sites (level title, result time, practice-mode subtitle).

`check_blocks_and_gate.gd::_test_translation_coverage()` fails if any level name or tutorial string lacks an English row — the guard against adding a level and forgetting its translation.

### Settings (`scripts/settings_screen.gd`)
Rows are built in code, not in the scene, because changing the language must refresh both the labels *and* which option shows as selected — Godot re-translates text by itself but cannot know that a different button is now active. One `_rebuild()` handles both, and adding a setting is a one-line change.

Settings live in **two** stores on purpose: `ProgressStore` `[settings]` (language, haptics, screen shake, aim assist) and `AudioSettingsStore` (mute, music/SFX volume). **Both survive `ProgressStore.reset()`** — erasing progress must not drop the player into a language they cannot read or re-enable vibration they turned off.

`ScreenShake.trauma_scale` is a `static var` for the same reason as `Haptics.enabled`: shake is triggered from six call sites, and scaling at each one guarantees someone eventually misses one and the preference leaks silently.

### Haptics (`scripts/haptics.gd`)
`Haptics` is the **single** exit point for `Input.vibrate_handheld` — nothing else in `scripts/` may call it directly, and `check_blocks_and_gate.gd::_test_haptics_setting()` scans the tree to enforce that. The reason is the on/off setting: with vibration calls scattered across the codebase, one always gets missed and the preference silently leaks. `Haptics.enabled` is a `static var` (same pattern as `Palette`) that `AppRoot` fills from `ProgressStore.haptics_enabled` at startup, so callers need no access to the store.

Durations live as constants in one place so the overall feel can be tuned together. Bounce haptics are **impact-scaled** (`Haptics.bounce(strength)`, sharing the same 0..1 `strength` the sparks and screen-shake use), because a graze and a hard slam feeling identical carries no information. The target hit is deliberately the longest pulse so "you won" is distinguishable from ordinary contact.

**Settings live in their own `[settings]` section** of `user://save.cfg`, separate from `[progress]`: `ProgressStore.reset()` wipes progress but deliberately **keeps** `haptics_enabled`, since that's a player preference, not earned progress.

### Ball trail (`scripts/ball.gd`)
The trail is a `Line2D` in world space (`top_level = true`) whose length and width **track the ball's speed** — a fixed-length trail communicates nothing, while a speed-reactive one is the main carrier of the game's sense of velocity. The raw speed is not used directly: it changes in steps at every bounce, which made the trail visibly jump, so it's exponentially smoothed (`trail_response_speed`, frame-rate independent). `_clear_trail()` resets the smoothed ratio so a new shot doesn't inherit the previous shot's trail state.

This is purely visual: `_update_trail_response()` touches no physics field, so the determinism rule below still holds.

### Mechanic intro card (`scripts/ui/mechanic_intro_card.gd`)
When the player meets a mechanic for the first time, `Gameplay` opens `MechanicIntroCard` — a **modal** card that plays a small looping demonstration of the rule (ball rises, passes through the ring's open centre, then bounces off its rim; brick cracks then shatters). It deliberately replaced an earlier fading toast: a toast that disappeared as soon as the player started aiming gave no time to read a *rule*, and a spinning icon can't express "the centre passes but the rim blocks".

The stage reuses the **real** classes — `LevelObstacle` (in `as_preview` mode) and real `BreakableBlock` instances — so a mechanic's look never drifts from its tutorial. The ball's path is hand-written and deterministic (`_demo_*`), **not** physics: the explanation must look identical every time, independent of frame rate. The block demo shows a 1-hit and a 2-hit brick side by side and respawns the broken one mid-loop, because the thing being taught there is the durability **colour** difference.

"First time" is content-driven, not a hardcoded table: `Gameplay._newly_seen_obstacle_kinds()` diffs the level's obstacle kinds against `ProgressStore.seen_obstacle_kinds`, and `AppRoot` persists the flag when the card is dismissed. While a card is open the launcher is disabled and restored afterwards (`_launcher_enabled_before_intro`). `check_obstacles.gd::_test_mechanic_intro_card()` covers it.

### The physics-verification core: `LevelSolver` + `LevelWorld`
This is the load-bearing abstraction of the whole project. `scripts/levels/level_solver.gd` (`LevelSolver`) is a **single, deliberately non-duplicated** deterministic physics simulator that:
- reads real gameplay constants (gravity, bounciness, launcher power/angle range, ball radius, target size) directly from `ball.tscn`/`launcher.tscn`/`target.tscn` via `from_scenes()` — never hand-copied, so it can't drift from the actual game;
- reproduces `ball.gd`'s exact integration order (gravity → clamp speed → move → bounce → separation-push) and `launcher.gd`'s aim-preview collision method (`cast_motion` + `get_rest_info` swept-circle test);
- simulates breakable-block hit-point persistence and multi-shot state search (`search_block_states_async`, BFS over "which blocks/lives are consumed" bit-states, since a block broken by shot 1 stays broken for shot 2 — state only grows, never resets mid-attempt);
- simulates moving/rotating obstacles analytically per-frame (`ObstacleGeometry.dynamic_shapes`/`hazard_shapes`) rather than as real physics bodies, with `seconds` always measured from **shot start** (frame 0 = phase zero) so every simulated shot sees the same obstacle phase the real game would.

`scripts/levels/level_world.gd` (`LevelWorld`) builds the actual scene-tree bodies (real `bounce_panel.tscn`/`breakable_block.tscn` instances, real obstacle nodes, real arena walls) that `LevelSolver` queries against. **Both the headless `tools/verify_levels.gd` and the in-game level editor/generator use this same `LevelSolver` + `LevelWorld` pair** — this is intentional and must be preserved: a second/duplicated simulation would eventually diverge and produce "passes in the editor, fails in the game" bugs. If you change ball/launcher/panel/block physics, `LevelSolver` picks it up automatically (it reads from the real scenes); if you add a new obstacle kind or LevelData field, both `LevelSolver` and `LevelWorld` need updating together.

"Solvable" is measured, not asserted: a level passes only if a grid scan of aim angle × power finds a **robust** hit — a cell whose 4 grid-neighbor cells also hit (`ROBUST_NEIGHBOURS`), which is the measurable proxy for "doesn't require pixel-perfect aim." `MIN_ROBUST_CELLS = 6` is the acceptance bar in `verify_levels.gd`.

### Level arcs and verification modes (`tools/verify_levels.gd`)
`LevelLibrary.LEVEL_COUNT = 125` (files `res://levels/level_01.tres`..`level_125.tres`). Levels 1-50 are the hand-authored library with strict, enforced mechanical arcs; the verifier dispatches its check strategy by **level content**, not a hardcoded table:
- **1-20**: plain single-shot grid scan (`_check_solvability`), no blocks/obstacles.
- **21-25**: single-shot scan plus `_check_ricochet_chain` — requires a contiguous cluster of 5-10 (`RICOCHET_MIN_BOUNCES`..`RICOCHET_MAX_BOUNCES`, increasing with level) bounces, and rejects any lower-bounce robust shortcut.
- **26**: single mandatory `BreakableBlockData` — teaches the mechanic (the one level where a block is allowed to be a hard gate).
- **27-29** (`BLOCK_OPTIONAL_FIRST/LAST_LEVEL`): must have **both** a block-free "mastery" route and a blocked "safe" route, each independently robust, and the blocked route must have *strictly more* robust cells than the free one (a block that doesn't measurably help is a design failure, not a valid puzzle).
- **30-40**: blocks are mandatory again (rejects if a robust block-free shortcut exists); 30-40 specifically must contain at least one **durable** block (`BreakableBlockData.hit_points >= 2`, cracks then breaks — introduced for this arc).
- **41-50**: obstacles (`ObstacleData`), zero breakable blocks; introduces `METAL_RING` (41) then `BOMB` (42), then combines the two — `ROTATING_WHEEL`/`MOVING_BAR` are deliberately deferred to 51+ so one band doesn't stack every new mechanic at once. No dedicated verifier branch needed since obstacle motion is baked transparently into `LevelSolver`'s per-frame simulation.
- **51-100**: continues the obstacle arc — `ROTATING_WHEEL` gets its own first-sees level (51), `MOVING_BAR` gets its own (56), then 57-100 combine all four kinds (ring/bomb/wheel/bar) with obstacle count and speed/travel/rotation values scaling up toward level 100 (the band's boss). Still zero breakable blocks: `SPEED_BOOST` is deliberately excluded from this band because its real gameplay effect (shattering nearby breakable blocks, `gameplay.gd::_on_hazard_triggered`) is never simulated by `LevelSolver`, so a level relying on it to open a route could never be verified offline. 101-125 are still the original bulk-generated content (mixed obstacles/blocks, not yet solver-tuned) — treat any per-level assumptions about that range as unverified.

`tools/check_blocks_and_gate.gd::_test_library_bounds()` is the authoritative programmatic check of this structure (1-25 & 41-100 have no blocks; 26-40 do; 30-40 have a durable block; 41+ has a non-empty `obstacles` array; 101-125 only get light structural checks) — update it if you change an arc's boundaries.

Star gate: `LevelLibrary.STAR_GATES = {21: 40}` — level 21 requires 40 total stars from levels 1-20 (`ProgressStore.get_stars_before`/`is_unlocked`). Stars are computed from time+shots only (`LevelData.calculate_stars`), never from obstacle/block count.

### Obstacle system (`scripts/levels/obstacle_data.gd`, `obstacle_geometry.gd`, `scripts/obstacle_field.gd`, `scripts/level_obstacle.gd`)
`ObstacleData.Kind`: `METAL_RING`, `BOMB`, `ROTATING_WHEEL`, `MOVING_BAR`. Rings are real static physics bodies: a 24-segment trapezoidal annulus with **4 segments skipped at the top**, i.e. a horseshoe. 20 of 24 segments are solid, so the centre is reachable *only through the ~60° opening at the top* — a ball arriving from below hits the metal body and bounces. (Do not describe this as "centre passable": the hollow centre is real geometry but unreachable from the launcher's direction, and the intro card previously taught the wrong rule because of that phrasing.) Bombs are `Area2D` hazards (`hazard_triggered` signal, failure reason `"bomb"`). Wheels/moving bars are `AnimatableBody2D` (`sync_to_physics = true`) driven by `ObstacleField.start_motion()`/`reset_motion()`, restarting phase at 0 every shot to match the solver's assumption. `LevelData.obstacles: Array[ObstacleData]` is additive and empty by default, so pre-obstacle levels are unaffected.

### Breakable blocks (`scripts/breakable_block.gd`, `breakable_field.gd`)
Collision is removed via `set_deferred` on hit — the ball still sees the block as solid for the rest of that physics frame (it genuinely bounced off it) and it's gone from the next frame on. **Two distinct resets, not to be conflated**: a lost/cancelled shot leaves broken blocks broken (`_respawn_ball`, resets only ball+target); a full level restart rebuilds every block from `LevelData` (`reset_shot` → `BreakableField.build`). Durable blocks (`hit_points > 1`) crack visually before breaking on the final hit.

**Durability is colour-coded**: `hit_points == 1` bricks use the blue-grey `Palette.SURFACE_BLOCK*` family, `hit_points == 2` bricks use the bronze/amber `Palette.SURFACE_BLOCK_STRONG*` family (`BreakableBlock.get_body_color()`/`get_rim_color()`/`get_seam_color()` pick per brick). Colour is deliberately **not** the only signal — `_build_armor_marks()` also draws twin edge notches on durable bricks, so the information survives for colour-blind players. `check_blocks_and_gate.gd::_test_block_tier_colors()` asserts both signals stay distinct. There's no clash with the pink/red `HAZARD` family: bombs only exist in 41+ and breakable blocks only in 26-40, so the two never share a screen.

**Bricks, not slabs**: 26-40 use rows of 60-160px bricks rather than single 350-540px walls. A row's gaps are ~30px — deliberately under the 48px ball diameter — so an *unbroken* row still behaves exactly like the old solid wall (which is what keeps the verifier's route contracts intact), while breaking one brick opens a genuinely passable hole. Note each brick costs one solver state-slot **per hit point** (`LevelWorld._build_blocks`), and `verify_levels.gd`'s BFS caps at `MAX_BLOCK_STATES = 96`, so brick counts are kept to ≤8 per level; a level with many durable bricks takes minutes to verify.

### Editing an official level from the debug panel
Opening the debug panel *while playing* and pressing **DÜZENLE** loads **that level** into the editor (`AppRoot._on_debug_editor_requested` reads `Gameplay.level_data`). It passes a `duplicate(true)` — `LevelLibrary` hands back a shared resource, so editing it in place would mutate the level for everything else in the session — plus the level number via `LevelEditor.source_level_id`.

Saving then records `source_level_id` in a **sidecar JSON** (`user://custom_levels/saved_manifest.json`), never in the `.tres`: a level file describes the level, not where someone edited it from. The saved list shows the origin (`← Bölüm 17`) and the file is named `bolum_17_<ad>` so the provenance survives even if the JSON is lost. `GenerationMetadataStore` serves both buckets; note `replace()` overwrites the whole manifest (correct for a generation batch, which is atomic) while `upsert()` adds one entry (correct for saves, which accumulate one at a time). Covered by `check_blocks_and_gate.gd::_test_edit_official_level()`.

### Level editor & generation (`scripts/editor/*`, debug-build only)
Reached only via the debug panel (which self-deletes from the tree in release builds via `OS.is_debug_build()`), so there is no separate "admin" app — one project, one signing key. `LevelEditor` (`level_editor.gd`) previews with real `LevelWorld` nodes (what you drag is what you'll play), drives `LevelSolver` for on-demand analysis, and manages a two-bucket `CustomLevelStore` (`SAVED` — user-curated, only user-deleted; `GENERATED` — last batch, overwritten by the next generation run; explicitly "keep this" = save it to `SAVED`). Because an exported APK's `res://` is read-only, on-device level authoring lives in `user://` and exports via clipboard text (`CustomLevelStore.copy_to_clipboard`/`bulk_text`, `===== name.tres =====`-separated for multi-level paste-back into the repo); on desktop it can write straight into `res://levels/`.

`LevelGenerator` (`scripts/editor/level_generator.gd`) is the single shared generation engine with two entry points:
- `generate()` — **local, non-AI**: pure-random layout filtered through a `Profile` (easy/medium/hard/with_blocks/ricochet_chain/block_corridor/kinetic) via the same `LevelSolver` scan used by the verifier.
- `generate_from_blueprints()` — **AI-assisted**: takes LLM-proposed geometry (see below), applies deterministic jitter variations (`build_blueprint_variations`, escalating tiers up to `MAX_VARIATION_SCALE=3.0`), can substitute hand-authored "rescue" geometry sourced from real official levels when a profile demands hard-to-hit properties the AI didn't produce, and evaluates every candidate through the *identical* solver filter as the local path.

**AI generation pipeline** (`AILevelGenerationCoordinator` orchestrates): `AILevelPromptBuilder` builds a chat prompt (template/difficulty/mechanics/diversity-seed rules; user free-text notes are explicitly framed as untrusted data, never as instructions) → `OpenRouterClient` posts to OpenRouter with a strict JSON-schema `response_format` (`AILevelContract`, capped at 10 levels/5 panels/4 blocks/4 obstacles per response, `PROMPT_VERSION` tracked) → `AILevelMapper` converts raw JSON into real `LevelData`/`PanelData`/`BreakableBlockData`/`ObstacleData` Resources, clamping every field to safe ranges and **never** trusting AI-provided `level_id`, paths, or scripts → `LevelGenerator.generate_from_blueprints()` filters through real physics → `LevelNoveltyScorer` rejects near-duplicates of official levels / SAVED / prior GENERATED batches (including mirror-image matches) → `LevelQualityScorer` ranks survivors (physics + tolerance + novelty + readability + template fit) → accepted levels go to `CustomLevelStore.replace_generated()`, with AI provenance (model, scores, token usage) written to a separate JSON sidecar (`GenerationMetadataStore`, `user://generated_levels/generated_manifest.json`) so it never contaminates the `.tres` resource itself. All AI code paths are debug-build-gated; `check_ai_phase4.gd` asserts the `OS.is_debug_build()` guards exist verbatim in the relevant scripts.

### Determinism discipline
The whole project is built around reproducible shots: no `randomize()`/global RNG in ball physics, spark bursts, or the solver. Where randomness is needed (audio pitch jitter, level generation), it uses a dedicated `RandomNumberGenerator` instance so it never perturbs gameplay determinism. Keep this invariant when touching ball/launcher/panel/obstacle code — it's what makes `LevelSolver`'s offline verification meaningful at all.
