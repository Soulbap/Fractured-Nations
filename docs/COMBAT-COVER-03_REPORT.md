# COMBAT-COVER-03 — Company of Heroes-style cover, ballistic integrity, tactical infantry

Base: `develop` @ `2a61ece` (AI-COMBAT-02). Date: 2026-10-26.
Check: `--scenario=dev --cover03-test [--shots] [--only a_building,b_terrain,c_corner,d_click,e_direction,f_drag,g_fight,q_perf]`
(results `benchmarks/raw/cover03_test.json`, shots `docs/combat_cover03/`, run `--fullscreen` for 1920x1080).

## 1. Root causes: shooting through buildings and terrain

| Problem | Cause (measured) |
|---|---|
| Rounds and sight through buildings | The settlement houses, barns and sheds (vegetation library ids 16-18, 771 buildings in `ref_20km`) had a **sphere** collider: radius 4 m round an 8 x 11.5 m house, 5 m round a 10.5 x 20.5 m barn, centred 1.2 m above the origin. LineOfFire, the near-tier physics (InstanceColliderStreamer), the navmesh obstacles and the cover search all used that sphere. Of 387 chest-height lines crossing a house's footprint, **84 (22 %) passed** - through the ends and corners, and over 5 m high everywhere. |
| FPS player hits enemies through the wall beside him | The same spheres, plus: the possessed soldier's round left the **camera**, not the weapon. A camera beside a wall sees (and fired) past it. |
| AI fires into walls, hillsides and the ground | Fire missions (squad suppression at a *reported* position) were fired without checking the line: a house or a crest between the soldier and the report took the rounds. Aimed fire checked sight (eye to target), so it was mostly consistent - except the aim error, which put rounds into the ground in front of prone / crouched soldiers (12 % of an enemy squad's rounds landed within 30 m of the shooter in one run). |
| Big solids missed by long lines | LineOfFire files a solid in the 16 m bucket of its centre and tests a line against buckets within `REACH` (5 m); anything wider than that (a barn) could be missed. |

Not causes: collision layers, terrain height queries (LineOfFire and the physics ray stop at the same wall to 0.1 m), the projectile
spawn (shots are traced, not spawned) and the friendly-fire check (it existed and works).

## 2. Ballistics and firing validation

- **Buildings are box solids** (`assets/environment/nordic_library.tres`): walls to the eaves and a narrower box to the ridge, the barn's
  earth ramp, all from the meshes (`tools/cover03/measure_buildings.gd`), and a new `VegetationMeshDef.box_base` (-0.55 m) so the
  solid reaches the foundation on sloping ground. Every reader goes through `boxes_of`, so LineOfFire, physics, navmesh, vehicle
  clearance and cover spots changed together; no asset or world file was rebuilt (manifest untouched). Now **387 of 387** lines stop.
- **LineOfFire** files a box wider than `REACH` in every bucket it touches (`copy_of` lets listing readers skip the copies; a
  construction clearing forgets the neighbour cells too). A vegetation hit now reports its solid type (`solid`: trunk / rock / box /
  light box).
- **Muzzle shots** (`CombatSim.muzzle_shot`, used by the possessed soldier's rifle and launcher): the crosshair point is the first thing
  the view line meets; the round leaves the first-person weapon's `ATT_Muzzle` towards it. A barrel pushed through a wall fires
  into that wall. Test: standing 25 m from the house, the round stops at 24.1 m (the wall); pressed against the wall, at 0.02 m.
- **AI line-of-fire discipline** (`CombatBrain._lof`): before a shot, the weapon's line to the aim point must be free (aimed fire:
  up to 1.5 m short of the target - his own cover; area fire: 6 m - the cover round a report is what suppression hits). Blocked:
  the other aim point (head / torso), then standing up over the cover, else no round is fired (`lof_holds`). Three blocked attempts
  within 5 s send the soldier to a firing position (`lof_stuck` -> `_start_search(need_fire)`, with two sidesteps either side first);
  a soldier who is fighting is not "calm" and does not walk back behind the wall (`_fighting`). While his target stays blocked, any
  other enemy he sees may replace it. The aim error never puts the round into the ground within 30 m when the ideal line clears it
  (`ground_saves`).

## 3. Cover design (Company of Heroes reference)

Documented CoH behaviour used as reference: heavy (green) cover such as stone walls, sandbags, buildings and wrecks, light (yellow)
cover such as wooden fences, bushes and craters, negative (red) cover on roads/water; cover is directional - it must be between the unit
and the enemy, so flanking defeats it; soldiers spread out and use cover near the point they are sent to ([CoH2 glossary](https://www.coh2.org/guides/5732/company-of-heroes-2-basic-concepts-and-glossary),
[Giant Bomb](https://www.giantbomb.com/company-of-heroes/3030-18930/), [Prima CoH2 guide](https://primagames.com/eguides/company-of-heroes-2-eguide/essentials)).
Not found in sources (our own design): a per-soldier placement preview, and how CoH3 snaps squads to cover.

What we took: three readable levels, directional judgement, snapping, spreading. What we did not: abstract damage modifiers or
"negative cover" - here protection is the geometry itself (a wall stops the round), and the levels only *describe* it.

## 4. Directional cover (`CoverEval`)

`scripts/combat/cover_eval.gd`, one instance `CombatBrain.cover_eval`; `CombatBrain._evaluate_spot` is now a wrapper, so the soldiers'
own cover reactions, the squad tactics' posts (SquadPositions / SquadTactics) and the player's preview use the same answer.

- **Level** against a believed threat (never a hidden soldier's true position): HEAVY when a hard solid (structure, terrain bank,
  rock, box) stops the crouched torso line *and both shoulder lines*; LIGHT for a trunk, light cover (`VegetationMeshDef.cover_class` 1:
  round bales, pallets, yard goods), the edge of a solid (one shoulder free - a corner), cover that works only prone, or foliage that
  conceals without protecting; NONE; UNKNOWN without a threat.
- **Fire** separately: CLEAR / BLOCKED along the eye line (up to 90 m), from the standing eye behind cover taller than a crouched eye.
- Several threats (`judge_all`): the worst protection, the best fire. The threats come from IntelSim contacts and the squad's
  assessed threat (`SquadPositions.threats_for`), up to three at least 35 degrees apart.
- `e_direction`: behind the house - front **heavy / fire blocked**, side **exposed**, rear **exposed**; behind a 0.85 m garden wall -
  front **heavy**, side and rear **exposed**.

## 5. Automatic placement and snapping

- **Spots** along every lee face of a box solid or a structure's collision box every 1.3-1.4 m, plus corner positions of tall solids
  (just past each end of the lee face, and along the side faces near it): `CoverEval.box_spots`. Spots inside another solid are
  dropped. Structures used to give one spot behind their middle.
- **Single right-click** within `cover_snap()` (3-8 m, growing with the zoom) of a wall, building, sandbags, a rock or a log:
  `SquadPositions.cover_line_near` finds the face on the click's side (clicked on the solid: the side towards the squad), lays a line
  along it as long as the squad needs, and the squad is placed there. In the open it stays the ordinary move. While squads are
  selected, the same plan is shown under the cursor (every 150 ms when it moved), and the click gives exactly that plan.
- **Right-drag**: unchanged interaction; `placement` now pairs soldiers and spots best-first over the whole squad (heavy before light,
  a line of fire, near the soldier's place on the line, snap by zoom), sends the rest to cover farther out (overflow, close to the
  line: cohesion), never two within 1.3 m, never onto a spot another soldier stands on.
- **Preview** (`GameHUD._draw_places`): a dot per soldier - green heavy, yellow light, red exposed (white outline when no threat is
  known: "FRONT ASSUMED") - and a tick towards the threat: white = line of fire, red stub = none. Tag: "4 HEAVY · 2 LIGHT · 1 OPEN".
- **Player authority**: places are player orders (`SquadState.placed`). Found and fixed on the way: a placed squad facing a
  *reported* (unseen) enemy chose its own SUPPRESS and moved to new posts (placed share 0.13 in the fight check); it now suppresses
  from the places it was given, does not regroup off them, and keeps the placement when the suppression ends.

## 6. AI cover usage

- Cover scores (`_cover_score`): heavy +1.5 (+2.5 suppressed), a suppressed soldier values protection over a line of fire, an
  unprotected firing spot -3.
- Corners: a soldier behind the house with no line moves to a corner and fires; he stays there while fighting (`c_corner`: one move of
  5 m, first round past the house after 5 s, 60 rounds, none into the house).
- Low cover: stands to fire over cover his crouched eye cannot clear (`_stand_for_line`, held 6 s against bobbing).
- Flank and post searches read the new judgement through `_evaluate_spot` / `cover_spots` (no new planner).
- Cost: one judgement ~0.27 ms (it follows the eye line 90 m); the per-frame search budget counts it double (`eval_cost`).

## 7. Results (ref_20km, a settlement house at (4302, -1995) with 14 detail objects within 40 m)

| Check | Result |
|---|---|
| a_building | 387/387 lines through the house stop (old sphere: 303/387); LineOfFire and the physics ray stop at 25.5 m; AI 10 s weapons-free: 0 rounds, 0 hits; FPS 25 m: round stops at the wall; pressed to the wall: stops at 0.02 m |
| b_terrain | crest 41 m between two soldiers, 12 s fire mission: **0 rounds into the hillside**, 15 held shots |
| c_corner | 1 firing-position move (5 m to the corner), first clear round at 5 s, 60 rounds, 0 into the house |
| d_click | preview 8/8 = order 8/8; 7 heavy + 1 light; min spacing 1.48 m; none inside a solid; all arrive within 1.1 m |
| e_direction | see §4 |
| f_drag | 26 m drag past the house: 6 behind the house, 1 behind concrete blocks, 1 at yard goods (7 heavy, 1 light), max 6.8 m off the line, no stacking |
| g_fight | placed squad vs 8 enemies 105 m out, 60 s: places kept **100 %** (before the fix 13 %), 0 rounds into own cover, 0 into the ground in front |
| q_perf | click plan 4.1 ms, drag plan 4.9 ms (both at most every 150 ms), one judgement 0.27 ms |

Change-impact checks: `--controls-test --only d_drag` PASS, `--combat01-test --only f_gunplay` PASS, `--ai-combat02-test --only p_placed`
PASS (550 rounds, places kept), `--world-cover-test --only b_ballistic` PASS, `--world-detail-test --only b_ballistic,c_cover` PASS.
`--ai-combat02-test --only b_firefight`: its site picker tried only the nearest cover object, which (run alone) had no sight line in any of its 12
directions (0 rounds; the unchanged code failed identically, A/B run). Fixed after the milestone (`_firefight_site`: the
nearest of 40 open cover objects with a mutual sight line over dry, gentle ground): PASS, 800 rounds, 1 stalemate break, 1 reposition.

Screenshots (`docs/combat_cover03/`): `d_click_preview.png` (single-click preview behind the house), `d_click_arrived.png`,
`f_drag_preview.png`, `f_drag_arrived.png`, `c_corner.png`, `g_fight.png`, `a_fps_against_wall.png`.

## 8. Known limitations

- No Blender or asset changes were needed: the house meshes were right, their collision data was wrong. Houses stay solid (windows are
  textures, nobody enters a house).
- No leaning: corner fighting is a position just past the corner, so the soldier there is exposed to the threat he fires at (LIGHT
  only when the angle leaves a shoulder behind the wall).
- Behind a building the preview honestly shows "0 can fire"; the player chooses corners by dragging past the ends.
- Fire is judged against the believed threat point; a crest near the enemy may still block once there.
- Weapon spread (not aim error) can still drop a round short; facing / animation were not reworked.
