# WORLD-COVER-01.1 — Terrain microrelief, tactical cover positions and collision refinement

Branch `develop`, after WORLD-COVER-01. Four things changed:

1. **Terrain microrelief.** `ref_20km` gets 13 773 small natural terrain features: shallow hollows, swells, low earth folds, field-edge banks and 112 km of roadside drainage ditches. They are a deterministic layer added to the terrain in memory at start; the world's files and manifest are untouched, and `--no-terrain-relief` gives the old ground.
2. **Cover on the terrain.** Soldiers find spots in hollows and behind folds. They lie down where only that protects, and stand to fire over cover taller than their crouched eye.
3. **Cover at the end of a move.** A COMBAT or STEALTH squad ordered near a believed enemy ends its move in cover round the ordered point.
4. **Fitted colliders.** Rock groups, ridges, logs, root plates and walls have colliders fitted per variant.

**Two side findings:**

- **Quit crash fixed.** The segmentation fault at quit, which WORLD-COVER-01 left open, is found and fixed: a navmesh bake was still running on a worker thread at shutdown.
- **Stale test fixed.** The `--combat01-test p_ai_posture` failure was a test still checking against the pre-QOL-01.1 top speed.

## 1. Existing systems inspected and reused

| System | Reused for |
|---|---|
| `SettlementLayer.apply_terrain`, `RoadShoulders.apply` (in-memory height layers before the route grid) | the same mechanism for the relief: written after both, before `StrategicRoutes.setup`, `TerrainCollisionStreamer`, `AreaNavigation`, LineOfFire |
| `RoadShoulders.fix_chunk` (vegetation back on eased ground) | `TerrainRelief.fix_chunk` moves instances with the ground; runs first in `VegetationStreamer._store_chunk` |
| StrategicRoutes grid cache keyed by the terrain layers | key extended with the relief file's hash |
| `CombatBrain.cover_spots` (one cover search: reactions, DEFEND posts, `SquadPositions.find_posts`) | relief candidates from the feature list; the terrain-rise sampling (threshold 0.9 → 0.55 m) |
| `CombatBrain._evaluate_spot`, `_choose_posture` | "low" spots (prone protects), standing to fire over tall cover |
| `SquadPositions.find_posts`, `exposure` | end-of-move positions (COMBAT firing posts, STEALTH least-seen posts) |
| `SquadTactics._step`, QOL-01 behaviour modes and their threat belief | `_settle` once per player move order |
| WORLD-COVER-01 box solids (`VegetationMeshDef.box`) and their four readers | `VegetationMeshDef.parts` / `boxes_of`: one place every reader asks |
| `CoverLayer` builder pattern (in-game, `--area`, deterministic per cell) | `TerrainRelief` builder |

**Not created:** no second terrain system, cover engine, pathfinding or order queue.

## 2. Terrain implementation

**Data:** `worlds/relief/ref_20km.relief.json` (2 MB). It is a list of features with their parameters, editable and kept in git:

- **hollow / swell:** centre, two radii, yaw, depth (negative = swell), rim, irregular outline harmonics.
- **fold / step:** centre, yaw, half length, curved crest (bend), front and back half widths, height.
- **ditch / bank:** a polyline, half width, depth or height, end taper.

**At start, `TerrainRelief.apply`:**

1. Evaluates every feature at the 1.953 m terrain vertices its box covers. Overlapping features add up.
2. Adds the result to `Terrain3DData` heights, after `SettlementLayer.apply_terrain` and `RoadShoulders.apply` (`CoreDemo._start_sandbox`).
3. Calls `update_maps` once.

The evaluated heights are cached per file hash in `user://terrain/` (zstd). The first start on a machine takes 7.3 s; every later start 0.8 s for 810 115 vertices.

**Whole dependency chain checked** (`r_survey`, one feature of each kind):

| Reader | How it sees the relief | Measured |
|---|---|---|
| rendered terrain (Terrain3D mesh, normals in the shader) | the edited height map | screenshots §10 |
| terrain collision (`TerrainCollisionStreamer`, streamed later) | built from the same data | collision − data 0.00-0.03 m at every kind's deepest / highest point |
| navmesh (`AreaNavigation`, terrain faces from Terrain3D) | the same data | navmesh 0.3-0.8 m from the point (agent / cell rounding, as elsewhere) |
| LineOfFire, abstract tier, cover search | `Terrain3DData.get_height` | — |
| strategic route grid | rebuilt once for the new key (1.24 s), then cached | — |
| generated vegetation | moved by the feature's height at its position | 0 plants floating, 0 buried at every surveyed feature |
| cover-layer objects, settlement buildings, the user's added objects | the ground under them is never changed (builder pass, §4) | `r_global`: 32 838 objects checked, 0 on changed ground |

**Saves:** unchanged. The relief is derived from a file and nothing is saved.

**Resolution:** at 1.95 m vertex spacing a feature narrower than ~6 m cannot be drawn (a 2 m ditch would be one vertex row: a notch). Every feature is therefore broad and smooth:

| Kind | Size |
|---|---|
| hollows | radius at least what keeps the slope under the limit (≈ 4.5-9.5 m) |
| folds | 8-11 m half width |
| ditches | ≈ 2.6-3.1 m half width |

Narrow trenches and sharp steps were not attempted.

**Gradient budget:** a feature may add at most 0.28 rise per metre on ground of at most 0.12. That is 0.40, the truck's `max_grade`. The builder rejects anything steeper.

## 3. Types of microrelief

| Kind | What it is | Size | Count |
|---|---|---|---|
| hollow | shallow natural low point, irregular outline (two low harmonics), sometimes a slight rim | 0.55-1.0 m deep | 7 767 |
| swell | low rise (uneven ground: 2-4 swells and shallow hollows together) | 0.28-0.45 m | 2 066 (plus the hollows of the groups) |
| fold | low earth ridge: curved crest, level middle, tapered ends, crest height varying along it | 1.1-1.5 m high, 24-44 m long | 1 690 |
| step | rocky-ground fold, steeper towards one side | 1.0-1.4 m | 2 |
| bank | low earth bank along a field edge, just outside the field | 0.55-0.75 m, 24-48 m long | 350 |
| ditch | roadside drainage just beyond the road shoulder band, runs of 40-140 m with gaps, tapered ends | 0.45-0.65 m deep | 1 898 runs, 112 km |

**Not modelled:** general noise over all ground (it would change millions of vertices). Uneven ground is the swell groups.

## 4. Placement rules

**Builder:** `--scenario=dev --no-terrain-relief --build-terrain-relief [--area=x,z,r]`, in the running game, 36 s for the whole map. It is deterministic per 40 m cell and uses the world's own maps.

| Ground | Features (chance per cell) |
|---|---|
| dense forest (vegetation.png > 0.55) | hollow 9 %, fold 5 %, uneven 4 % |
| open woodland (0.2-0.55) | hollow 9 %, fold 8 %, uneven 5 % |
| meadow / open | hollow 6 %, fold 6 %, uneven 3 % (open ground stays mostly open) |
| rocky (info.png > 0.45) | step 12 %, hollow 5 % |
| fields (info.png field > 0.45) | nothing in the field; a bank at its edge (22 % where the field map drops off within 25 m) |
| wet (> 0.55), settled (> 0.2) | nothing |
| local roads, tracks, secondary and primary roads outside settlements | ditches on either side |

**Placement guards for scattered features:**

- outside objectives (70 m), bases (reach + 50 m), settlements (radius + 30 m) and base sites (270 m);
- beyond road width / 2 + 18 m + the feature's reach, and outside the road shoulder band (the bitmap of the vertices `RoadShoulders` eased);
- 80 m from bridges, clear of water (15 m round), of cover objects and added buildings (their footprint + 3 m), and of each other (4 m);
- on ground whose height range over the feature stays within its gradient budget.

**Placement guards for ditches** (per 4 m station):

- the ditch lies one ditch-width beyond the outermost shoulder vertex;
- it stops 6 segments from bridges and 2 from culverts, where another road comes within its own band + 16 m, near exclusions, where its bottom would be under water, and where the ground across it is steeper than 0.15.

**Last pass:** any feature that would change the ground under an object (its centre and four points at its reach, cover layer + settlement layer + user overrides) is dropped.

**Rejections in the last build:**

| Reason | Count |
|---|---|
| slope | 21 423 |
| gap | 10 137 |
| cover / buildings | 9 794 |
| road | 1 707 |
| water | 176 |
| area | 167 |
| bridge | 1 |

`r_global` (whole map): 0 features near a road, 0 near a bridge, 0 of 32 838 objects on changed ground.

**Test area first:** the 700 m disc round the CombatScenario site (-5400, -8860), with open ground, woodland, a road with ditches, cover objects and folds. It got 47-48 features and was validated (§5-§12) before the whole map was built. The first iteration's hollows (0.5-0.85 m) and folds (0.8-1.15 m) proved too shallow in the ballistic tests (§6), so they were made deeper and higher before expansion.

## 5. Terrain and navigation integration

- **Vehicles (`f_road`):** APC and truck cross-country plans across the road at the nearest ditch, three crossings each way: 6 of 6 for both. The steepest grade on their routes is 0.34 (truck limit 0.40).
- **Infantry:** squads crossed the ditched road in 16 s with no halt in two of the three full runs. In the third they halted once under the enemy's fire (QOL-01 interruption) and regrouped 13 m from the goal. No soldier was ever blocked in any scenario (`blocked` 0).
- **Road edges:** `--road-quality-test --only survey` passes unchanged (the relief stays out of the shoulder band).
- **Route grid:** rebuilt for the new terrain (cache key includes the relief hash).
- **Navmesh:** follows the terrain; soldiers reached posts in hollows and behind folds (§7).

## 6. Ballistic protection tests

All shots are LineOfFire traces with units at the soldier's real hit volumes, aimed at torso and head. Shooters are 40 m off with the eye 1.5 m above their own ground ("level") or 5 m ("high").

**Hollows (`b_hollow`)** — three deepest near the site, 8 directions, hits of 16:

| Hollow (depth) | Standing | Crouched | Prone |
|---|---|---|---|
| 0.67 m | 14 / 14 | 11 / 11 | 3 / 6 |
| 0.85 m | 12 / 12 | 10 / 11 | 6 / 6 |
| 0.83 m | 8 / 8 | 7 / 8 | 2 / 3 |

(level / high)

- **Prone:** lying in a hollow halves to quarters the hits.
- **Standing / crouched:** largely exposed.
- **What the remaining prone hits are:** the head (0.40 m up) over the rim from the downhill side. The test area lies on a slope, so from some directions the shooter stands lower than the rim.
- **The brain's verdict:** "protected", and "low" where only lying down helps.

**Folds (`c_ridge`)** — the back of three folds, at 0.55 and 0.75 of the back width from the crest. The shooter is across the fold and ±29° (hits of 6, level):

| Fold | Spot | Standing | Crouched | Prone | Can fire over it |
|---|---|---|---|---|---|
| 1.38 m | 6.2 m behind | 4 | 4 | 3 | stand, crouch, prone |
| 1.38 m | 8.5 m behind | 6 | 5 | 2 | all |
| 1.27 m | 6.6 m behind | 6 | 6 | 0 | stand, crouch (prone: crest in the way at 2.8 m) |
| 1.27 m | 9.0 m behind | 4 | 3 | 0 | stand, crouch |
| 1.13 m (in trees) | 5.9 / 8.1 m | 4 / 2 | 3 / 2 | 1 / 0 | a trunk 2-5 m in front blocks |

**Reading:**

- **Lying down:** a soldier on the back of a fold is protected lying down.
- **Firing:** crouched or standing he can fire over it; his head shows, as it should.
- **Prone and firing:** prone at the foot of the slope he cannot fire (the eye line meets the crest). The AI's verdict follows this: "can_fire" false there, "low" true.
- **The 1.38 m fold:** it protects prone less (3 / 2 of 6) because from the ±29° shooters the line passes along the fold's tapered end.

**Two-way checks:** muzzle clear in every posture where firing was possible. Never "firing into the ground": the eye line was blocked by the crest only for prone soldiers at the foot, and the AI does not choose those spots to fire from.

## 7. COMBAT / STEALTH end-of-move cover

`SquadTactics._settle` runs once per player move order, when the squad has arrived (status done, no route, not interrupted). Conditions:

- a believed threat within reach of the ordered point: COMBAT 350 m, AWARE 150 m (contact close), STEALTH 450 m; SAFE never;
- never on HOLD, FOLLOW, a tactic, a garrison or AI squads (their moves belong to WarSim).

**How it picks positions:**

1. It asks `SquadPositions.find_posts` (→ `CombatBrain.cover_spots`, including the relief candidates) for positions within 18 m of the ordered point.
2. **COMBAT / AWARE:** firing posts that protect.
3. **STEALTH:** posts least seen from the threat (`exposure` ≤ 0.34) or protecting, least seen first.
4. Each position goes to the nearest soldier (short walks, no crossing). Soldiers walk there by ordinary moves to a post (precise arrival).
5. **No good position:** the order ends as before.

**Order and player authority:**

- **Oscillation:** none; one evaluation per order target.
- **Status:** the squad's order stays its MOVE, which reads "Arrived" when the soldiers are there.
- **Overrides:** any new order or HOLD replaces it.
- **Off switch:** `--no-end-cover`.

**On arrival, two posture rules** (in `_choose_posture`, derived, never saved):

- **Low cover:** a soldier whose spot protects only lying down goes prone, if he is in cover, under fire or not shooting at a seen target. The threat is his own, or else his squad's belief.
- **Standing to fire:** a soldier fighting a target he sees, whose crouched eye line meets cover within 4 m while the standing one is clear, stands to fire over it.

**Results** (`d_combat_move`, `e_stealth_move`): the place is an open spot with relief 75 m from the start; the enemy is reported 230 m from it (beyond QOL-01's 220 m contact range that would interrupt the move).

| | Protected at the end (in the posture held) | Farthest soldier from the ordered point | Time | Order |
|---|---|---|---|---|
| COMBAT | 5-6 of 6 (4-5 prone) | 17 m | 33-42 s | Arrived |
| STEALTH | 4-5 of 6 | 18 m | 43-45 s | Arrived |

Path length is 74-78 m against 77-78 m straight: no detours.

**Before the change:** in the first runs (positions not yet settled, or the threat inside the interrupt range), the same squads ended with 0-2 of 6 protected.

## 8. Collision refinements

**Measuring:** `tools/world_cover/measure_cover_colliders.gd` rasterises each variant's LOD0 mesh into a 0.1 m height map. It walks along the long axis in 0.2 m slices; a slice's top is its 85th-percentile height. It joins similar slices into at most four boxes per variant, which it writes into `VegetationMeshDef.parts` with `--write`.

**Using it:** every reader of box solids goes through `VegetationMeshDef.boxes_of(xf)`, the parts of the instance's variant (the same position hash the streamer draws by):

- LineOfFire buckets (and so the cover search);
- `InstanceColliderStreamer` (one BoxShape3D per box);
- `StructureManager` (vehicle clearance circles);
- `AreaNavigation` (one turned rectangle per box).

`--single-box-colliders` gives the old single box.

**Measured** per variant:

- **Covered:** the share of the mesh's solid cells (≥ 0.3 m) inside a box up to their height.
- **Phantom:** the share of box footprint where the mesh is under half the box height, i.e. bullets stopped by nothing visible.

| Kind (variant) | Single box: covered / phantom | Fitted: covered / phantom | Boxes |
|---|---|---|---|
| rock group 0 / 1 / 2 | 1.00 / 0.68, 1.00 / 0.70, 1.00 / 0.60 | 0.99 / 0.43, 0.94 / 0.38, 0.98 / 0.28 | 2, 1, 3 |
| ridge 0 / 1 | 1.00 / 0.62, 1.00 / 0.65 | 0.99 / 0.43, 0.99 / 0.30 | 3, 4 |
| log 0 / 1 | 1.00 / 0.46, 1.00 / 0.57 | 0.97 / 0.25, 0.98 / 0.31 | 1, 1 |
| root plate 0 / 1 | **0.28** / 0.40, **0.31** / 0.43 | 1.00 / 0.37, 0.99 / 0.42 | 2, 3 |
| wall 0 / 1 | 1.00 / 0.48, 1.00 / 0.50 | 0.99 / 0.19, 0.94 / 0.26 | 1, 4 |
| timber stack | kept as one box (the fit trimmed the stack's protruding log ends: 0.74 covered) | | |

**What changed:**

- **Rock groups:** rock group variant 1 is 0.49 m tall where its box was 0.85 m. Its gaps and low parts no longer stop bullets in the air.
- **Logs:** the shorter log (6.6 m) no longer has a 0.4 m invisible extension at each end.
- **Root plates:** the lying trunk now protects. A prone soldier beside it, shot at from across it, is protected in 6 of 12 probes (`k_colliders`; before: the trunk was not modelled).
- **Remaining phantom hits:** across the objects at the old box top − 0.08 m, 0-3 of 30 shots per kind are still stopped, by the tallest parts of the objects.

**Cover candidates** come from the fitted boxes (one bucket record per box). Spots stay `COVER_GAP` (1.0 m) behind the surface, the WORLD-COVER-01 rule that keeps them reachable. Box candidates still require a box of at least 0.45 m height and 0.3 m half length, so the small end pieces of a rock group give none.

## 9. Before / after gameplay measurements

Full before/after series were not run (at the product owner's request). The comparisons are:

- **End-of-move cover (§7):** 0-2 of 6 protected before, 5-6 of 6 after.
- **Colliders (§8):** single box against fitted, per variant.
- **Same soldier in FPS / RTS (§10):** the relief position checked in each posture.
- **Open-ground fight (`a_open`, 8 v 8, 45 s, posture-aware exposure):** these numbers vary a lot between runs with the same set-up (WORLD-COVER-01 showed the same noise).

| Run | Protected share | Samples on relief features |
|---|---|---|
| final | 0.51 | 13 % |
| earlier | 0.32 | 6 % |
| earlier | 0.50 | 6 % |
| earlier | 0.61 | — |

In every run, 0 soldiers were blocked.
- **Two threats (`g_two_threats`, a squad defending at a fold, enemies across it and to the side):** 2 protected against the threat across, 1 against the side, 3 of 8 against at least one. A fold protects in one direction, as it should; the side threat looks along it.

## 10. FPS and RTS screenshots (`docs/world_cover01_1/`, 1920×1080, real game)

**Relief:**

- `relief_<kind>_side.jpg` / `_rts.jpg`: hollow, swell, fold, step, ditch, bank at eye height and from the tactical camera.
- `hollow_prone_side.jpg`: a soldier prone in a hollow.

**Movement and fights:**

- `combat_move_end_rts.jpg`, `stealth_move_end_rts.jpg`: squads in their end-of-move positions (prone at the forest edge and the relief).
- `two_threats_fold.jpg`, `open_relief_fight.jpg`, `road_crossing.jpg`.

**Same-soldier check (`v_same`, the mandatory one).** The AI puts a squad into DEFEND posts at a fold on open ground. The enemy is placed where it sees a standing man at the place (so the fold, not a hill beyond, decides). One soldier the AI put in terrain cover is then:

1. shown from the RTS camera, selected: `same_relief_rts_before.jpg`;
2. possessed (0.00 m moved, posture kept);
3. checked in first person standing, crouched and prone: `same_relief_fps_stand/crouch/prone.jpg`;
4. shown again from the RTS camera: `same_relief_rts_after.jpg`, still 0.00 m from where he was.

**Final run, soldier N163-x behind a 1.38 m fold, enemy 136-150 m off:**

| Posture | Hit by the threat (of 2) | Can fire | Muzzle clear | Feet − ground | Inside a solid |
|---|---|---|---|---|---|
| standing | 2 | yes, hits the enemy | yes | 0.00 m | no |
| crouched | 2 (head and torso over the crest at this spot) | yes, hits the enemy | yes | 0.00 m | no |
| prone (the AI's choice) | 0 | yes, hits the enemy | yes | 0.00 m | no |

In the run before it, at a spot 3 m further back, the same check gave:

- **prone:** 0 hits, cannot fire (the crest is 3.9 m in front);
- **crouched:** 1 hit (head), can fire;
- **standing:** 2 hits, can fire.

That is the reverse-slope behaviour wanted.

**Same check at a boulder on open ground** (`same_object_*`):

| Posture | Hit (of 2) | Can fire | Note |
|---|---|---|---|
| standing | 2 | yes | |
| crouched | 1 | yes | |
| prone | 0 | no | the boulder 0.4 m in front: correctly obstructed muzzle; prone behind a 1.3 m boulder cannot shoot |

This led to the standing-to-fire rule (§7).

**Other checks:** the possessed camera is 0.02 m from the posture's eye height in all postures. No soldier floated or stood inside a solid.

**Iterations the checks forced:**

1. Hollows and folds were deepened and widened (§4).
2. Fold cover spots were moved from 0.33 / 0.5 to 0.55 / 0.75 of the back width.
3. The standing-to-fire rule was added.
4. The relief pick now requires the terrain itself to be the blocker. A first pick was protected by a tree trunk 7 m away instead of the fold.

**Seen and not fixed:** in `same_relief_fps_crouch` / `_prone` a squad-mate lying on the front slope of the fold, a few metres ahead, shows an odd prone pose: legs raised, weapon pointing up. It looks like the prone clip and aim layer on a slope. This milestone did not investigate it; see §14.

## 11. Performance

| Measure | Value |
|---|---|
| frame time at the relief, RTS / eye height (vsync 60 Hz) | median 16.6 / 16.6 ms, p95 18.4 / 18.3 ms (WORLD-COVER-01: 16.6-16.7 / 18.6-18.7) |
| relief apply at start | 0.85 s cached (810 115 vertices); 7.3 s the first start per file and machine |
| route grid | 1.24 s rebuild once for the new key, then 0.07 s cached |
| post search with relief candidates (`find_posts`, 8 posts) | 1.7 ms per search (one per squad decision or end of move, never per frame) |
| posture rules | at most two traces per soldier every 2-4 s, only for soldiers in cover or fighting |
| colliders | one bucket record / BoxShape3D per box: at most four per object, only for ids 25-29 near the camera |

The relief adds no physics bodies; the terrain collision chunks are the same, only their heights differ.

## 12. Road and vehicle access

- **Distance from roads and bridges:** no feature's extreme point lies within road width / 2 + 12 m of a road (ditches excepted, which lie beyond their own road's shoulder band), and none is near a bridge.
- **Road edges:** `--road-quality-test --only survey` passes.
- **Vehicles:** APC and truck cross a ditched road 6 of 6 each; max grade 0.34.
- **Infantry:** crosses in 16 s, 0 blocked.
- **Bridges:** decks and approaches are untouched (80 m exclusion; ditches stop 6 segments short).

**Regression runs** (change impact):

| Run | Result |
|---|---|
| `--ai-squad-test --only a_engagement,d_assault,f_withdraw` | PASS |
| `--combat03-test --only p_posts,d_open` | PASS |
| `--qol01-test --only i_interrupt,b_modes` | PASS |
| `--qol011-test --only m_modes,i_multi,f_stealth` | PASS |
| `--world-cover-test --only b_ballistic,n_vehicles,e_modes` | PASS |
| `--road-quality-test --only survey` | PASS |
| `--combat01-test --only p_ai_posture,t_withdraw,p_posture` | `p_ai_posture` failed, see below; PASS after the test fix |
| `--world-cover11-test` (all 12 checks, final run, full map) | PASS |

**`p_ai_posture`:** it flagged a standing soldier sprinting to his post at 6.2 m/s (QOL-01.1 SPRINT). The check still used the pre-QOL-01.1 top speed (4.5 m/s) for standing. It failed identically with every WORLD-COVER-01.1 switch off. The check now holds crouched / prone soldiers to `Posture.MAX_SPEED` (1.6 / 0.81 m/s, stricter than before) and standing ones to sprint speed; it passes.

## 13. Known limitations

**Relief, shape and protection:**

- Features under ~6 m across cannot be drawn by the 1.95 m terrain grid: no foxhole-sized hollows, no narrow ditches, no sharp steps.
- Hollows of 0.55-1.0 m protect a prone soldier partly (head over the rim from lower ground). Crouched or standing they protect little.
- Folds protect in one direction. From along the fold, or past its tapered ends, they do not.

**Relief, placement and visibility:**

- Only 2 rocky steps: little rocky ground passes the slope and gradient rules.
- Uneven ground is swell groups, not a general ground noise.
- The relief is not painted: hollows and folds read by shading and the vegetation on them, and tall grass hides the shallow ones from a distance.

**Relief, costs:**

- The first start with a new relief file on a machine evaluates it (7.3 s); later starts read the cache.
- A road-shoulder rule change (`RoadShoulders.CACHE_VERSION`) does not re-place ditches: they were placed against the band of the build.

**AI and assets:**

- End-of-move cover is for the player's squads. AI factions' squads move under WarSim and keep their formation slots.
- The timber stack keeps its single box.
- `c_flank` still fails as before ("no safe flank"), unrelated.
- The squad-mate prone pose on a slope (§10).

## 14. Deferred improvements

**Natural follow-ups of this milestone:**

- **Prone pose and aim on slopes:** the squad-mate in `same_relief_fps_*`. Check the prone clip / aim IK against the ground normal.
- **Ground paint for the relief:** a damp darker tint in hollows and ditch bottoms, so the relief reads from the RTS camera.
- **End-of-move cover for AI squads:** OpCoordination's stages could use the same `_settle` at their objectives.
- **Re-placing ditches** when the road shoulder rules change.

**Larger items:**

- **Higher-resolution terrain** (or a local detail mesh) would allow foxhole-sized hollows and narrow ditches.

**Done in this milestone:**

- **Quit crash:** found and fixed. A navmesh bake (`AreaNavigation`, worker thread or NavigationServer async) still running when the engine shut down crashed the process after quit. It came in tests that built structures (`--ai-squad-test` b_suppress / c_flank: `QUIT_DIAG nav_pending=1`); `a_engagement`, which builds nothing, exited cleanly. It was independent of every WORLD-COVER switch and of `shutdown_cleanup`'s collider freeing. `AreaNavigation.drain()` (called from `CoreDemo.shutdown_cleanup`, also on window close / pre-delete) now waits for the running bakes. Both scenarios exit with code 0.
