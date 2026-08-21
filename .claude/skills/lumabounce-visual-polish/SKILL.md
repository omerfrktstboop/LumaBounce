---
name: lumabounce-visual-polish
description: >
  LumaBounce-specific rules for any visual, UI, layout, animation or polish work:
  editing .tscn scenes, Control/Container layout, responsive mobile UI, safe area,
  Tween and micro-interactions, gameplay juice/impact feedback, particles, Line2D /
  Polygon2D procedural visuals, and controlled shader use. Encodes the project's
  existing design system (Palette, PaletteThemes, UIMetrics, LumaButton, LumaCard,
  InkBackground), the physics fields that visual work must never touch, and the
  inspect -> edit -> run -> verify loop driven through the godot-mcp-toolkit MCP
  server. Use whenever a task touches how LumaBounce looks, feels, animates or
  lays out on screen.
---

# LumaBounce Visual Polish

Project-local skill. It does **not** replace the generic Godot skills — it tells you
which of them to use and what LumaBounce-specific constraints override their generic
advice. Generic Godot advice loses to this file.

Read `CLAUDE.md` (architecture) and `AGENTS.md` (contributor rules) first. They are
authoritative for anything not covered here.

---

## 1. Design system first — never invent a second one

Before any visual change, read the component that already solves the problem. LumaBounce
has a mature design system; hardcoding a new `Color(...)`, `StyleBoxFlat` or font size is
a regression, not a feature.

| Need | Use | File |
| --- | --- | --- |
| Any colour | `Palette` (`static var`, theme-swapped at runtime) | `scripts/palette.gd` |
| Per-world accent colours | `PaletteThemes` / `PaletteTheme` | `scripts/ui/palette_themes.gd` |
| Spacing, radius, font size, touch target | `UIMetrics` (`const` tokens) | `scripts/ui/ui_metrics.gd` |
| Button | `LumaButton` (`Emphasis.PRIMARY` / `SECONDARY`) | `scripts/ui/luma_button.gd` |
| Icon button | `LumaIconButton` | `scripts/ui/luma_icon_button.gd` |
| Card surface | `LumaCard` (static style builder) | `scripts/ui/luma_card.gd` |
| Screen background | `InkBackground` | `scripts/ui/ink_background.gd` |
| Notch / gesture-bar insets | `SafeAreaMargin` | `scripts/ui/safe_area_margin.gd` |
| Coin balance display | `CoinChip` | `scripts/ui/coin_chip.gd` |
| Nav / product / segmented / toggle / dropdown | `NavigationCard`, `ProductCard`, `SegmentedControl`, `ToggleSwitch`, `LumaDropdown` | `scripts/ui/` |
| Star row, icons, edge fade, glow orb/square | `StarRow`, `GlyphIcon`, `EdgeFade`, `NeonOrb`, `NeonSquare` | `scripts/ui/` |

### Rules that follow from the system

- **Never read `Palette` into a `.tscn` sub-resource.** `.tscn` files cannot read a
  runtime `static var`, so a literal colour baked into a scene silently desyncs the
  moment a theme swaps. Build styles in code (`_apply_style()` pattern) — that is
  exactly why `LumaButton` does.
- **Cosmetic catalog colours are the deliberate exception**: `CosmeticCatalog` uses
  literal colours on purpose, because a purchased identity must not change per world.
  Do not "fix" those into `Palette` reads.
- **Respect the "single accent" rule** (`scripts/palette.gd` header). Neon accent belongs
  to only three things: the ball, the aim guide, and the target. Secondary accent
  (`ACCENT_ALT`, violet) appears only on hit/success. Everything else stays quiet ink and
  surface tones. `HAZARD` and `COIN` are world-independent — never theme them.
- **`Button` subclasses with script-added children must set `custom_minimum_size`
  explicitly.** A `_get_minimum_size()` override is not reliably honoured by
  `HBoxContainer`/`GridContainer` and has already caused real overlap and collapse bugs
  (`CoinChip`, `ProductCard`). This is settled — do not retry the override.

### Design language

Minimal, premium, deep navy ground, controlled cyan accent, world-specific accents from
`PaletteThemes`. No neon spam, glow stays restrained. Idle screens are calm; when action
happens the feedback is short and strong, then returns to calm.

---

## 2. Physics protection — the hard boundary

Visual polish must be provably physics-neutral. The offline solver
(`LevelSolver` + `LevelWorld`) verifies all 125 levels against the *real* scene values,
so changing any of the below silently invalidates level solvability and star balance.

**Never change while doing visual work:**

- gravity, impulse / launch power, bounciness, speed clamps
- `CollisionShape2D` / collision polygon extents, ball radius
- level coordinates, launcher position, target position, panel positions/angles
- star thresholds (`LevelData.calculate_stars`) and time/shot targets
- any geometry inside `levels/level_*.tres`

Cosmetics are already held to this rule by `CosmeticApplier` — it is the single place
skins are applied, and `tools/check_cosmetics.gd` both measures ball physics before/after
a skin **and** scans the applier's source for assignments to physics field names. If your
visual change needs to touch anything on that list, it is not a visual change: stop and
say so.

**Determinism:** no `randomize()` and no global RNG in ball physics, spark bursts, or the
solver. If a visual effect needs randomness, give it its own `RandomNumberGenerator`
instance — the ball trail (`scripts/ball.gd`) is the reference for a purely visual,
physics-neutral effect.

---

## 3. Mobile first

Target is a portrait phone, 720x1280 reference units, GL Compatibility renderer, 60 FPS.

- No expensive fullscreen shaders. No blur spam. No unnecessary particles.
- Never shrink a touch target below `UIMetrics.MIN_TOUCH` (72 reference units — it maps
  to roughly 45 real pixels; 48 units would collapse to ~30px and was already rejected).
- Never remove or bypass `SafeAreaMargin`. Insets are ratio-converted from window pixels
  to the 720x1280 canvas — do not reimplement that math inline.
- Everything is drawn procedurally (`ShapeBuilder`, `_draw()`, `Line2D`, `Polygon2D`).
  There are no external art assets — do not introduce any.
- Shaders are allowed but must be justified, small, and mobile-safe. Prefer a `Tween`,
  a `_draw()` change, or a `Line2D`/`Polygon2D` treatment first.
- **Headless size forcing:** in tests use `set_deferred("size", ...)`, never a direct
  `.size =` write. A full-rect anchored screen root reverts a direct assignment on the
  next layout pass, and `DisplayServer.window_set_size()` is unreliable headless.

---

## 4. Godot MCP workflow — evidence, not assumption

The project runs the **`godot-mcp-toolkit`** MCP server (`addons/godot_mcp_toolkit`,
NPGameDev, editor port 6550). It is already configured in `.mcp.json` and enabled.
Do **not** install another Godot MCP server, and do not follow any skill's instruction to
connect a `godot-ai-bridge` — this project does not use one.

> The bundled `godot-interactive` / `godot-live-edit` skills are written for a *different*
> MCP server and name tools `godot_editor_*` / `godot_runtime_*`. Their **workflow
> discipline is correct and worth following**; their **tool names do not exist here**.
> Translate with the table below.

| `godot-interactive` says | Use here |
| --- | --- |
| `godot_connection_status` / `godot_editor_get_project_info` | `project_get_settings` (also the liveness probe) |
| `godot_editor_get_scene_tree` | `scene_get_tree` |
| `godot_list_scene_nodes` | `scene_query` |
| `godot_read_script` | `script_read` |
| `godot_validate_script` | `script_check` |
| `godot_editor_save_scene` | `editor_save_scene` |
| `godot_editor_refresh_filesystem` | `extensions_refresh` |
| `godot_editor_run_scene` | `game_start` / `game_stop` |
| `godot_editor_get_errors` / `get_output` / `get_log_file` | `editor_get_console` |
| `godot_runtime_*` (input, screenshot, state) | `input_simulate`, `runtime_screenshot`, `runtime_get_script_vars` |
| `godot_help` | `discover_tools` |

All are prefixed `mcp__godot-mcp-toolkit__`.

Extra tools with no `godot-interactive` equivalent, useful for this skill's work:
`control_set_layout` (anchors/offsets/presets — the fastest way to fix responsive
layout), `node_set_property`, `node_get_property_list`, `scene_spatial_map`,
`signal_list` / `signal_manage`, and `discover_tools` for on-demand groups
(`theme`, `particles`, `animation_authoring`, `editor_advanced`, `debugger`).

### The loop

1. **Inspect first.** `scene_get_tree` / `scene_query` for structure, `script_read` for
   behaviour. Prefer `scene_query` over dumping a whole `.tscn`.
2. **Read the design system** (section 1) before choosing colours, sizes or components.
3. **Smallest meaningful change.** Keep node names and paths stable — several are
   load-bearing for tests (e.g. the gameplay HUD `CoinChip` path is relied on by the
   hint-economy suite).
4. **Sync.** External file edit while the editor is open -> `extensions_refresh`.
   Live scene edit you intend to keep -> `editor_save_scene`.
5. **Validate.** `script_check` on touched scripts.
6. **Run and observe.** `game_start`, then `runtime_screenshot` and `editor_get_console`.
   Use `input_simulate` to reach the state you changed. `game_stop` when done.
7. **Iterate** on what you actually observed.
8. **Test.** Run the affected `tools/check_*.gd` suite plus the boot check.

**Do not report a visual task complete on written code alone.** A visual change is done
when you have looked at it — a screenshot, or a runtime property read that proves the
new state. If the editor bridge is unavailable, say so plainly and fall back to file
work plus the headless boot check; never invent runtime results.

### Verification commands

Godot is not on `PATH`; substitute the local Godot 4.7 executable (see `AGENTS.md`).

```
godot --headless --path . --quit-after 200                              # boot check
godot --headless --path . --script res://tools/check_blocks_and_gate.gd # UI/layout/gate suite
godot --headless --path . --script res://tools/check_cosmetics.gd       # cosmetics stay physics-free
godot --headless --path . --script res://tools/check_obstacles.gd       # obstacle + intro card
godot --headless --path . --script res://tools/check_hint_economy.gd    # HUD fit
```

Never run `tools/probe_openrouter_live.gd` — it makes a real paid API call.

---

## 5. Animation and juice

- Use `create_tween()` for micro-interactions; `LumaButton` already does press-scale plus
  a cyan edge highlight. Match that vocabulary rather than inventing a new one.
- Impact feedback is **layered and impact-scaled**, not binary. The same 0..1 `strength`
  drives sparks, `ScreenShake`, and `Haptics.bounce(strength)` — a graze and a hard slam
  must not feel identical.
- `ScreenShake.trauma_scale` is a `static var` on purpose (six call sites; scaling at each
  one guarantees the preference eventually leaks). Same reasoning as `Haptics.enabled`.
- **`Haptics` is the single exit point for `Input.vibrate_handheld`.** Nothing else in
  `scripts/` may call it — `check_blocks_and_gate.gd::_test_haptics_setting()` scans the
  tree and will fail you.
- Tutorial/demo animations must be **hand-written and deterministic**, never physics-
  driven (`MechanicIntroCard._demo_*`). An explanation has to look identical every time,
  independent of frame rate.
- Free a `Tween` or guard with `is_instance_valid()` when the node can leave the tree
  mid-animation, especially across `AppRoot` screen transitions.

---

## 6. Scene and screen structure

- **Screens never instantiate each other.** A screen emits a signal; `AppRoot` decides
  and injects data before `add_child`. Do not add a cross-screen `instantiate()` to make
  a transition prettier.
- Settings rows are built in code, not in the scene, because a language change must
  refresh both labels and which option reads as selected. One `_rebuild()` handles both.
- Localisation: source language is Turkish and **the Turkish source string is the
  translation key**. Godot auto-translates `Control` text, so plain `.text = "..."` is
  fine. The exception is format strings — call `tr()` *before* `%`:
  `tr("BÖLÜM %d") % id`. Any new user-visible string needs an English row in
  `assets/i18n/ui.csv` or `levels.csv`, or the coverage test fails.

---

## 7. Product rule — Daily / retention UI stays off

The daily-challenge and retention system exists in code (`scripts/retention/`,
`scripts/retention_screen.gd`, `DailyStore`) but is **deliberately unreachable in the
shipping UI**: the main menu exposes only OYNA, BÖLÜMLER, MAĞAZA and settings, and
`AppRoot.go_to_retention()` is only reachable once `_active_daily_challenge` is already
true — which nothing in the UI sets.

**While doing visual polish, do not:**

- add a Daily / GÜNLÜK button or card to the main menu or anywhere else
- wire up `go_to_daily_challenge()` from any UI element
- re-activate the retention screen or surface achievements as an entry point

This is a launch product decision, not an oversight or a bug to fix. If a task seems to
require it, ask first.

---

## 8. Which skill to reach for

Use the exact invocation names below — they are verified as registered.

| Task | Skill |
| --- | --- |
| Control nodes, anchors, containers, Theme, focus, responsive layout | `godot:godot-ui-control` |
| Tween, AnimationPlayer, AnimationTree, UI transitions | `godot:godot-animation` |
| `.tscn` format, node hierarchy, reusable/composed scenes | `godot:godot-nodes-scenes` |
| Typed GDScript, lifecycle, patterns | `godot:godot-gdscript` |
| Signals, groups, decoupling | `godot:godot-signals-groups` |
| `Resource` / `.tres` patterns | `godot:godot-resources` |
| Shaders (only after cheaper options are ruled out) | `godot:godot-shaders` |
| Collision layers/masks, `Area2D` overlap, raycasts | `godot:godot-physics` |
| Audio buses, SFX/music routing | `godot:godot-audio` |
| Export presets, headless/CI builds | `godot:godot-export` |
| Live editor inspect -> run -> verify discipline | `godot-claude-skills:godot-interactive` (**translate tool names, section 4**) |
| Engine/task routing when unsure | `router:router` |

### Not invocable — do not route to these

`godot-scene-design`, `godot-code-gen`, `godot-shader` and `godot-live-edit` ship in the
`godot-claude-skills` package **without YAML frontmatter**, so Claude Code does not
register them and the Skill tool cannot call them. Only `godot-interactive` from that
package is usable.

This costs nothing in practice — every domain they covered has a registered equivalent in
the table above (`godot-nodes-scenes`, `godot-gdscript`, `godot-shaders`). `godot-live-edit`
was already superseded by section 4 anyway: it targets an AI bridge LumaBounce does not run.

If you ever need their raw text, read the file directly rather than invoking a skill:
`~/.claude/plugins/cache/godot-claude-skills/godot-claude-skills/<version>/skills/<name>/SKILL.md`
