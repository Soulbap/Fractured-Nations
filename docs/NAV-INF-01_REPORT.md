# NAV-INF-01 — long-distance infantry movement reliability

Date: 2026-10-23. Branch `develop`, baseline `b70c836` (N1-C1). Godot 4.7.2, world `ref_20km` (not regenerated; terrain edited, manifest re-created).
Scope: bug fixing and stabilisation. No new navigation engine, no vehicle changes, N1-C2 / NAV-PERF-01 not started.

**Honest status of verification.** The product owner asked for a short verification only. What was run is listed in D and E. The NAVINF-01..12
cases were run in parts on the code before the final world edit (all passed); only the repro cases and NAVINF-06 were repeated after it. The visual
(screenshot) run and the wider regressions (N1-A, AI-WAR, squad, logistics) were **not** run. See G.

## A. Root cause

The Centre Bridge march (six soldiers, 180 m before the deck to a goal 220 m after it) failed for several independent reasons. The retry budget was
only one of them.

1. **Far tier: false "blocked everywhere".** Terrain3D's `get_height` returns a value 1-1.5 m off in bands about 1 cm wide beside some heightmap
   vertices. A soldier whose step landed in one was refused in every direction (`_step_blocked`), asked for a local route, got none, and spent
   its budget in 0.6 s. Found at (-95.7, -1277.3) and reproduced on the exact coordinates.
2. **Far tier: planner and walker disagreed.** The local A* (5 m cells, grade between nodes) accepted routes over banks the walker's own test
   refuses (34 % of unchecked plans from the area east of the bluff crossed such ground; the bluff is a real 48 degree face 13 m high). Every replan
   returned the same route.
3. **Retry budgets were per order, not per blockage.** `WorldSim._local_attempts` (3), `SoldierBody._stuck_stage` (one unstick, then the order is
   dropped) and `SquadControl` member recovery (1 per target) never renewed on progress, so a second harmless jam anywhere in a long leg ended
   the order as `BLOCKED`.
4. **Near tier: the road lip.** The Road Generator terrain connector sinks the terrain 0.25 m under every road (`offset = -0.25`). The road mesh
   collider therefore has a 12-25 cm sharp edge; contact normals y 0.3-0.65 match a 0.35 m capsule against a ledge of that height. 121 stuck
   episodes for six soldiers on one 500 m march.
5. **Near tier: slopes.** The navmesh allowed 45 degrees while a `SoldierBody` stood still on 40+ degree faces (floor normals y 0.75). Soldiers were
   routed up banks they could not climb.

## B. Fixes

| Where | Change |
|---|---|
| `world_sim.gd` | confirms a grade refusal with the median of three nearby height samples; retry budget renews after 10 m of progress; shared squad routes are validated for the walker before use; negative cache so squad mates standing together do not repeat a failed full-grid search (12 -> 2 searches); block reasons are meaningful and logged (`local_block_log`); one slope limit `INFANTRY_MAX_GRADE` = tan 38 deg |
| `local_route_planner.gd` | optional `walk_check`: the finished route is walked with the walker's own test; where it fails, the steep cells (and connected ones) are closed and it plans again (max 6); route endpoints use the nearest cell the walker can actually reach |
| `area_navigation.gd` | navmesh slope limit taken from `INFANTRY_MAX_GRADE` |
| `soldier_body.gd` | steps up ledges to 0.35 m; the stuck stage renews after 4 m of progress; the reason names the cause (stuck / navmesh path ends short / no path) |
| `squad_control.gd` | member recovery budget renews after 15 m |
| world, `tools/terrain_ref/flush_roads.gd` | terrain smoothed beside the paved roads (low-pass blended by distance: 0 on the road bed, full from 14 m, fading out at 45 m; nothing within 25 m of a bridge span or culvert) and raised to 3 cm under the road surface where it lay 2-32 cm lower. Backup of the old terrain: `../fractured-nations-backups/2026-10-23_NAV-INF-01_terrain_before_flush_roads`. Manifest re-created. `road_lip_stats.gd` measures the result: road centre 25 cm -> 4 cm above terrain |

Not used: higher retry limits, longer timeouts, wider arrival tolerance, teleporting, relaxed tests.

## C. Before / after (Centre Bridge, six soldiers, same start and goal)

| Case | Before | After |
|---|---|---|
| Bridge + 220 m, far | 5/6 and 4/6 arrived in separate runs (members `BLOCKED`: retry budget exhausted / no local passage) | 6/6, 126 s |
| Bridge + 220 m, near | 2/6 to 4/6 arrived, 121 stuck episodes; 3/6 in one run even after the first fixes | 6/6, 127 s |
| 220 m after the bridge only, far / near | 4/6 / 4-5/6 | 6/6 51 s / 6/6 54 s |
| Bridge, near -> far -> near swap | not measured before | 6/6, no position jump |
| N1C1-01 (infantry reaches the original goal) | only "crossed" was asserted | 6/6 reach the destination |

"Before" numbers come from the instrumented reproduction on `b70c836` before each fix; the full suite was not run on the old code (stopped on request).

## D. Tests (`--nav-inf-test`, `scripts/debug/nav_inf01_selftest.gd`)

Arrival means: member within 25 m of the goal, no order, `ARRIVED`.

| ID | Scenario | Result |
|---|---|---|
| 01 | 250 m open, far + near | PASS 6/6, 62 s each |
| 02 | 1 km varied, far + near | PASS 6/6, 252 s / 238 s |
| 03 | 4 km straight (5.8 km route, 42 waypoints), far | PASS 6/6, 1334 s |
| 04 | Bridge + 220 m, far + near | PASS (also after the world edit) |
| 05 | 1.8 km, several waypoints, far | PASS 6/6, 467 s |
| 06 / 07 / 08 | near->far / far->near / toggling every 25 s | PASS, 0 jumps (06 also after the world edit) |
| 09 | building across the line, squad and single, far + near | PASS; the far squad met it (1 search, +5 s); the single far soldier did not meet it in this geometry |
| 10 | every crossing closed, goal across the river | far: PASS (stops, says why, 2 searches). **Near: soldiers wade the river (3.3 m deep) and arrive**, see G |
| 11 | new order mid-march | PASS far and near (near: 4 members used up their recovery budget before arriving) |
| 12 | save at 40 s, load at 55 s | PASS, restored to the saved place, order and route kept |
| AI ops | MOVE 1.5 km, REINFORCE 1.3 km, ATTACK approach 0.9 km, WITHDRAW | PASS: MOVE completed (394 s, within 8 m), REINFORCE completed, ATTACK reached deployment, WITHDRAW "withdrawal complete" |

## E. Regression

Run once after the world edit: `--navigation-n1c1-test --only n1c1_01,n1c1_02,n1c1_07,n1c1_07n`. 01 PASS (6/6 reach the goal), 02 PASS, 07n PASS,
07 flaky (PASS with 5/6, FAIL with 4/6): two soldiers whose formation slots lie beside the deck, in the river, when the bridge closes are stranded
("no local passage"). The N1-C1 report already recorded 07 as intermittent; not introduced here, not fixed.

Not run: N1-A (`--navigation-n1-test`), N1-B, AI-WAR movement, squad, logistics. Performance was not measured before/after; the walker check adds
about 5 ms to a 30 ms local plan, and an extra search happens only when a route fails it. The 12 -> 2 search reduction in NAVINF-10 is measured.

## F. Visual verification

Not done. Seen only through numbers: no position jumps (max 0.3-2.2 m per frame), no stalls without a reason in the repro cases.

## G. Remaining problems

* Near-tier bodies wade rivers: the navmesh is baked from terrain only, so closed bridges do not stop near squads. Fixing it means excluding water
  from the navmesh and connecting decks to it (touches bridge crossing).
* N1C1-07 "squad on the deck when the bridge closes" is flaky for members outside the deck strip.
* Near squads can still lose a member to a double stuck on a 35-38 degree slope; recovery re-orders it, and NAVINF-11 near showed 4 members spending their budget.
* The terrain edit changed 2.2 M vertices (max 7 m at the steepest banks); bridge and culvert surroundings were left alone. Vegetation was not re-seated,
  so objects on the smoothed strip may float or sink by decimetres.
* The cause of the Terrain3D `get_height` bands was not found, only worked around.
* The FPS-controlled player has no step-up (only AI bodies do).
* Pending: full NAVINF suite and N1-A / AI-WAR / squad regressions on the final world; the visual run; before/after performance.
