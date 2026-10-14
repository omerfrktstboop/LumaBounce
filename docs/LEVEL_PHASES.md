# LumaBounce Level Phase Rules

Normal levels are deliberately split into 25-level bands. Each band keeps previously introduced mechanics available and introduces at most one new mechanic family.

| Levels | New mechanic | Allowed special mechanics |
|---|---|---|
| 1-25 | Core bounce / wall-gap play | Panels and wall gaps only |
| 26-50 | Breakable blocks | Previous + breakable blocks |
| 51-75 | Metal ring | Previous + metal ring |
| 76-100 | Bomb | Previous + bomb |
| 101-125 | Rotating wheel | Previous + rotating wheel |
| 126-150 | Pulse laser | Previous + pulse laser |
| 151-175 | Portal | Previous + portal |
| 176-200 | None (mastery) | Everything above; lasers and durable bricks return |

Note: the shipped 126-150 content diverges from the table — it mostly uses moving bars, with lasers in only 8 levels. The regression suites record this as known failures; those levels are intentionally left unchanged.

## World 4: PRİZMA (151-200)

151-200 form the fourth world (`LevelWorlds`), with its own palette (`PaletteThemes.theme_d`, graphite ground + lime accent) and a 300-star gate at 151 (two thirds of 1-150, the same ratio as every world transition).

| Step | 151-175 Portal | 176-200 Mastery |
|---|---|---|
| 1 | 151-155 introduction: one portal pair, nothing else | 176-180 two alternating lasers + portal timing |
| 2 | 156-160 portal + panels / wall gaps (portal as shortcut) | 181-185 durable-brick corridors return |
| 3 | 161-165 portal + ring / bomb (a bomb guards an exit) | 186-190 laser + bricks + wheel |
| 4 | 166-170 portal + wheel / bar timing, turning exits | 191-195 two portal pairs + timing |
| 5 | 171-175 two portal pairs, band finale | 196-200 finale run, 200 = campaign finale |

### Portal rules

- One-way: blue entry (arrowheads pointing in) to orange exit (arrowheads pointing out).
- The ball leaves the exit **centre** with the same speed; direction is kept unless the exit turns it by 90 or 180 degrees (shown by a turn arrow in the exit).
- Teleport triggers when the ball's centre enters 75% of the ring radius; skimming the rim does not teleport.
- At most 4 teleports per shot; afterwards the portals dim for that shot.
- Portals never collide. The aim guide stops at an entry: working out where the ball comes out is the puzzle.
- Validation: ring radius 36-64, entry-exit distance at least 220, exit inside the play area, turn in {0, 90, -90, 180}.

### Acceptance

Every 151-200 level must pass `verify_levels.gd` with at least 6 robust cells (at least 10 for the 151-155 introduction), then a manual playtest. A level that can only be solved with a route the designer already knows is not accepted.

## Difficulty curve

Each 25-level band is split into five 5-level steps:

1. introduction,
2. basic route,
3. combination,
4. tighter route,
5. band finale.

A new mechanic starts with a readable introduction but never resets the whole game to tutorial difficulty. Older mechanics return gradually as the band advances.

## Placement rules

- No panel, block, obstacle, target or launcher should visually overlap another gameplay object.
- The target and launcher keep explicit clearance zones.
- A portal exit needs free space around it: the ball must never appear inside a panel, block or obstacle.
- Late-game levels combine mechanics, but layouts stay readable; difficulty should come from route/timing rather than object clutter.
- Speed boosts are not used in the normal campaign: their block-shattering effect is not simulated by `LevelSolver`, so a route relying on it cannot be verified.
- There are no bonus level resources; `LevelWorlds.FIRST_BONUS_ID` is reserved at 201.

Any future level generator or manual edit should preserve these phase gates and placement clearances.
