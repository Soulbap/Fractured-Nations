# WORLD-COVER-01 — Natural terrain cover, asset creation and tactical AI integration

Branch `develop`. The world `ref_20km` gets 32 067 natural cover objects, and the AI uses them through its existing cover search. Nothing is a separate cover AI, navigation or world:

- **What is new:** large boulders, rock groups, rock ridges, thick fallen logs, wind-thrown root plates, dry stone field walls and timber stacks.
- **How they are placed:** a deterministic, read-only layer over the unchanged generated world (chunks and manifest untouched). `--no-natural-cover` gives the world as it was.
- **How they are used:** the objects are solid for bullets, physics, vehicles and the navmesh, and the existing AI cover search finds positions behind them.

## 1. Existing systems inspected and reused

| System | What it does for cover | Use here |
|---|---|---|
| Vegetation library / chunks / `VegetationStreamer` | instanced meshes with LODs and variants per library id | 7 new ids (24-30), drawn like the forest |
| `WorldOverrides` (settlement layer) | read-only "added" records over the chunks | a second layer: `extra_layers` |
| `LineOfFire` | shots and sight against trunk capsules / rock spheres from the vegetation | a third solid type: the turned box |
| `InstanceColliderStreamer`, `StructureManager.blocks_trunk`, `AreaNavigation` | physics near the camera, vehicle and soldier clearance, local navmesh | box shapes, circles along the axis, turned rectangles |
| `CombatBrain.cover_spots` / `_evaluate_spot` / `_cover_score` | the one cover search for reactions, DEFEND posts, firing posts, bound legs (`SquadPositions.find_posts`) | candidates behind boxes, extra spots at big boulders, reachable spot distance |
| `Concealment` (grass) | delays noticing | unchanged: concealment stays vegetation, protection comes from solids |
| Scan prop pipeline (`make_props_v3.py`, `import_env_assets.gd`) | Poly Haven CC0 scans to game meshes | reused for every asset |
| QOL-01 behaviour modes | how cautious a squad is | unchanged; they act on more cover |

## 2. Assets created

`tools/blender/env/make_cover_v1.py` builds every asset on the WORLD-VISUALS-01 scan pipeline: scans decimated per piece, scaled, sunk into the soil, LOD0 / LOD1. The `.blend` sources are in `assets/environment/blender/`, GLBs in `assets/environment/glb/`, Godot scenes / meshes in `assets/environment/scenes|meshes/`, and previews / iteration sheets in `docs/world_cover01/blender/`. Every variant was checked against its collider (`_cover_v1_report.json`: all inside).

| id | Asset | Variants | Size above ground | Collider | Tris LOD0 / LOD1 |
|---|---|---|---|---|---|
| 24 | cover_boulder: large mossy granite blocks | 3 | 1.3-1.45 m, up to 3 m long | sphere r 1.15 | 2 200 / 260 |
| 25 | cover_rockgroup: 3 blocks touching | 3 | 0.7-0.9 m (partial cover) | box 2.7 × 0.85 × 1.56 m | 2 400 / 300 |
| 26 | cover_ridge: low bedrock ridge | 2 | about 1.1 m, 5.3 m long | box 5.5 × 1.1 × 3.8 m | 2 600 / 320 |
| 27 | cover_log: thick fallen spruce | 2 | 0.6-0.7 m, 6.6-7.4 m long | box 7.4 × 0.68 × 0.76 m | 2 000 / 260 |
| 28 | cover_rootplate: wind-thrown spruce | 2 | 2.3-2.5 m plate, 6-6.5 m trunk | box round the plate | 6 500 / 900 |
| 29 | stone_wall: dry stone field wall | 2 | 0.85 m, 5.9 m long | box 6.0 × 0.85 × 0.96 m | 8 000-9 400 / 2 400 |
| 30 | timber_stack: stacked logs at a track | 2 | 0.9-1.15 m, 4.2 m long | box 4.3 × 1.15 × 1.76 m | 640 / 300 |

**Visual iteration** (sheets in `docs/world_cover01/blender/_sheet1-9.jpg`):

- **Boulders:** the first versions scaled by footprint and came out too low; one scan was reddish, foreign blocks. They are now scaled by height from the world's own mossy granite sets.
- **Rock groups and ridges:** first scattered slabs with gaps, which a box collider would have turned into false bullet stops. They now touch.
- **Stone wall:** the joined wall decimated at once lost its stones, and dozens of duplicate materials came through. It is now built from a palette of closed rock scans, decimated once each, with one material.
- **Root plate:** a stood-up root scan read as a thin twisted sheet. It is now a ragged soil disc (dirt scan) with crooked roots, stones in the soil and the trunk running down from the plate.
- **Timber:** the cut ends came out white in the game; the importer now gives them a weathered wood colour.

Seen in the game (`docs/world_cover01/kind_*_side.jpg` / `_rts.jpg`), the objects sit on the ground, read at their scale from a soldier's eye and from the tactical camera, and are not visibly repeated.

## 3. Placement (`CoverLayer`, `worlds/cover/ref_20km.cover.json`)

**How it is built:** inside the running game, so it sees the terrain soldiers walk on (settlement heights and road shoulders applied), the road network, water, bridges, objectives and bases:

`--scenario=dev --no-natural-cover --build-cover-layer [--area=x,z,r]`

The build is deterministic per 25 m cell (a hash of the cell) and takes 53 s for the whole map. Result: 32 067 objects, 6.7 MB.

| Ground (the world's own maps) | What may lie there |
|---|---|
| dense forest (vegetation.png density > 0.55) | logs, root plates, rock groups, a few boulders (more on rocky ground) |
| open woodland (0.2-0.55) | boulders, logs, rock groups, a few root plates |
| meadow / open | rare boulders and rock groups: open ground stays open |
| rocky ground (info.png rockiness > 0.45) | ridges, boulders, rock groups |
| field edges (the field map drops off within 25 m) | dry stone walls along the edge |
| forest roads | timber stacks 12 m from the road edge, parallel, about every 250 m (sometimes) |

| Kind | Placed |
|---|---|
| boulders | 8 432 |
| rock groups | 10 278 |
| logs | 5 400 |
| root plates | 3 737 |
| walls | 4 098 |
| timber stacks | 84 |
| ridges | 38 |

**Never placed:**

- on roads or within 9 m + the object's size of them, near bridges (60 m) or in or within 10 m of water;
- inside settlements, on objective centres (60 m), base areas (radius + 40 m) or base sites (260 m);
- on slopes over about 35° or where the footprint rises more than 0.7-1.1 m;
- over an existing tree, rock or structure, or within 8 m of another cover object.

**Rejection counts** from the last build:

| Reason | Count |
|---|---|
| slope | 27 683 |
| occupied | 22 998 |
| road | 1 673 |
| gap | 493 |
| water | 81 |
| area | 45 |
| bridge | 4 |

Objects sit on the lowest ground under their footprint (embedded, not floating). Checked over all 32 067: 0 within reach of a road surface, 0 within 40 m of a bridge.

**Representative test area first:** a 700 m disc round the CombatScenario site (-5400, -8860) with forest, meadow, a road and slopes. It got 136 objects, which were validated before the whole map was built.

**Not done: earth formations** (depressions, berms, ditches, folds). They would be terrain edits like the settlement layer's in-memory heights. Every one of them changes the strategic grid, the navmesh, the road shoulders and the terrain collision, and in this world the risk around roads, bridges and sites is real. The ridges (rock) and the existing terrain-rise candidates of the cover search are the terrain-like cover this milestone has. Earth formations are a follow-up (§14).

## 4. Cover vs concealment

| Object | Stops bullets (LineOfFire) | Concealment |
|---|---|---|
| boulder, ridge, root plate | yes (sphere / box) | its own bulk |
| thick log, wall, timber stack | yes to their height (prone and crouched; a standing soldier shows above) | low |
| rock group | partial (0.7-0.9 m: prone, low crouch) | low |
| trees (unchanged) | trunk capsules only | foliage layers count for sight, not for bullets |
| bushes, grass (unchanged) | no | noticing delay (`Concealment`) |

Measured (`b_ballistic`): three objects of each kind, 8 directions, a level shooter 40 m away, target 2-3 m behind the object.

| Kind | Stopped at standing / crouched / prone height (of 24) |
|---|---|
| root plate | 10 / 10 / 10 |
| boulder | 0 / 8 / 12 |
| ridge | 1 / 8 / 9 |
| log | 6 / 6 / 11 |
| wall | 0 / 6 / 14 |
| rock group | 2 / 2 / 6 |

- **Reading:** low objects protect the low postures. A standing soldier shows above all but the root plate.
- **Why not more:** where the line misses, the shot passes beside the object at that heading; terrain blocked the rest.
- **Directional protection:** a spot behind a boulder is protected against the threat on the far side in 18 of 24 probes, and against a threat on the near side in 10. Those 10 are where something else covers, such as forest trunks or terrain. For root plates it is 24 against 10.

## 5. AI cover selection

No new cover engine. `CombatBrain.cover_spots` is the one search, used by a threatened soldier's cover reaction, DEFEND / REPOSITION posts (`_judged_posts`), firing posts (SUPPRESS), bound and assault legs and fall-back lines.

- **Box solids:** `_box_candidates` puts spots along the long side away from the threat every 1.4 m, so several soldiers fit behind one wall or log (occupancy goes through the existing `_reject` / taken-spot list). When the threat lies along the object's length, the spot is behind the far end.
- **Big boulders** (r ≥ 1 m): two more spots to either side behind them, so two soldiers do not share one rock's centre line.
- **Scoring:** boxes score like rocks (above trees, below structures). The existing preference for a spot the soldier can fire from (`_evaluate_spot.can_fire`: the eye clears the cover towards the threat) stays: a soldier picks a firing spot over full cover when both protect.

**Reachable spots (a bug found by the tests).** Spots lay 0.55 m behind a solid, but the local navmesh keeps agents `tree_margin` + agent radius ≈ 0.95 m off every vegetation solid. Soldiers stopped about a metre short, often out of the cover's shadow. In `e_modes` that made squads end *less* protected with natural cover than without (2 of 6 against 6 of 6). Two changes:

- **`COVER_GAP` 1.0 m:** spots now lie 1.0 m behind the surface (a 0.85 m wall still hides a crouched soldier from a level shooter at that distance).
- **Precise arrival at posts:** a walk to a post (`UnitState.post_pos`, already saved) arrives with the reaction tolerance (0.7 m body, 0.5 m abstract) instead of 1.3 / 1.0 m.

After both, the same scenario ends 6 / 5 / 5 protected.

**QOL-01 behaviour modes, unchanged:** SAFE reacts with a smaller radius and time, COMBAT and compromised STEALTH with larger ones, and the cover reactions choose among the new spots like the old ones. STEALTH's concealment remains grass and routes through woods; it does not treat a bush as protection.

## 6. Directional protection and firing

- **Directional by construction:** cover is judged against the believed threat. A candidate is placed on the far side of the object from the threat, and `_evaluate_spot` traces from the crouched torso towards the threat's eye. A defence that sees the threat move re-judges its posts (REPOSITION).
- **Two directions (`d_two_threats`)**, a squad defending at a stone wall with enemy teams east and north:

  | | Soldiers left | Protected vs east / north | Protected from at least one |
  |---|---|---|---|
  | With natural cover | 6 | 3 / 3 | 5 |
  | Without | 6 | 0 / 1 | 1 |

- **Firing from cover:** the posts prefer spots with a line of fire (eye over the cover); muzzle and line checks stay CombatSim's (a shot that would hit the own cover is stopped there, as before).

## 7. Tactical movement

- **Road crossing (`c_road`):** a COMBAT squad crossed a road 140 m from an enemy in 20.6 s with natural cover, 20.5 s without; nobody blocked.
- **Bounding between cover (`z_fight`):** a squad given BOUND moves 63 m by bounds; legs end at cover posts from the same search. Screenshot `fight_bound_rts.jpg`.
- **Attacks still make progress:** `--ai-squad-test d_assault` with the cover layer reached the objective (18 m off, defenders all down in 60 s).
- **Short moves:** the QOL-01.1 finding stands. A plain move ends in formation slots; cover is taken when the squad defends or reacts. With the reachable spots, the posts a halted squad takes are now really in cover (§5).

## 8. Before / after combat comparisons

Same place, same set-up, one run each; "before" is `--no-natural-cover`. The AI factions' soldiers within 2.5 km are removed first (they had joined the scenarios), and fights face a direction with a clear sight line.

| Scenario | With natural cover | Without |
|---|---|---|
| A open ground, 8 v 8, 45 s: shots | 470 | 126 |
| A: share of samples protected against the known threat | 0.11 | 0.00 |
| A: samples in cover (IN_COVER) | 544 | 0 |
| A: shots stopped by cover objects / vegetation | 7 / 75 | 0 / 15 |
| A: soldiers left | 7 / 5 | 8 / 8 |
| B forest, 8 v 8 (three runs each) | 0.07 protected, 47-48 shots | 0.07 protected, 47 shots |
| D two threats: protected from one | 5 of 6 | 1 of 6 |
| E move past a reported enemy, protected at the end (AWARE / COMBAT / STEALTH) | 6/6, 0/3, 6/6 | 6/6, 0/6, 1/6 |

**Reading:**

- **A:** on open ground soldiers now have something to fight from. Exposure falls, and the fight is fought instead of stood out; nobody became invulnerable (5 and 7 of 8 left).
- **B:** the forest place has no layer object in play and the forest is cover already; three runs each give the same result. An earlier single run that looked worse with cover was noise (identical repeats).
- **E:** COMBAT halted under fire both times (the scenario's reported contact) and lost soldiers. It is not a cover result.

Numbers: `benchmarks/raw/world_cover_test_after.json`, `_before.json` (git-ignored, from the runs above).

## 9. Screenshots (`docs/world_cover01/`)

- `kind_<kind>_side.jpg` / `_rts.jpg`: boulder, rock group, ridge, log, root plate, wall, timber stack from eye height and from the tactical camera.
- `open_fight.jpg`, `forest_fight.jpg`, `two_threats.jpg`, `road_crossing.jpg`: the scenarios.
- `fight_cover_rts.jpg`: soldiers in the open-ground fight at the cover objects.
- `fight_bound_rts.jpg`: a squad bounding.
- `blender/`: previews of every variant and the iteration sheets.

A first-person shot through a soldier in cover was planned (`z_fight`). In the final run the picked soldier was not at a layer object at the moment of the shot, so it was not taken.

## 10. Performance

| Measure (test area, vsync 60 Hz) | With layer | Without |
|---|---|---|
| frame median, RTS / eye height | 16.7 / 16.6 ms | 16.7 / 16.7 ms |
| frame p95, RTS / eye height | 18.6 / 18.7 ms | 18.7 / 19.0 ms |
| overrides layers load at start | 261 ms (32 067 records) | 72 ms |
| layer JSON parse | 128 ms (6.7 MB) | – |

- **Rendering:** objects are instanced multimeshes with two LODs and the library's ranges (rocks 550-900 m, logs 400 m).
- **Physics:** only within the collider streamer's radius.
- **Bullets and cover search:** the same 16 m buckets as trunks. Boxes add three floats per solid to the bucket and one AABB test.
- **Cover candidates:** at most 14 per search, as before.
- **Build:** the generator takes 53 s for the whole map (tool only).

## 11. Navigation and vehicle access

- **Vehicles (`n_vehicles`):** APC cross-country plans from the test area's open place to eight points 350 m round it: 8 of 8 with cover (3 284 m in total) and without (3 098 m). The legs go round the new solids (+6 % length), and planning stays within the router's usual cost (worst 224 ms vs 230 ms).
- **Roads and bridges:** 0 of 32 067 objects on or beside a road surface, 0 near a bridge.
- **Infantry:** the navmesh gets the boxes as turned rectangles. No soldier blocked in any scenario, and `--ai-squad-test d_assault` / `f_withdraw` and `--combat03-test p_posts,d_open` pass. The latter two were run without the layer, to separate the AI code change from the terrain.

## 12. Tests

| Run | Result |
|---|---|
| `--world-cover-test --shots` (v_kinds, b_ballistic, a_open, b_forest, c_road, d_two_threats, e_modes, n_vehicles, q_perf, z_fight) | PASS |
| the same with `--no-natural-cover` (scenarios, vehicles, perf) | PASS |
| `--no-natural-cover --ai-squad-test --only a_engagement,d_assault,f_withdraw` | PASS (cover-spot and post-arrival code) |
| `--no-natural-cover --combat03-test --only p_posts,d_open` | PASS |
| `--ai-squad-test --only d_assault` (with the layer) | assault reached its objective |
| `--ai-squad-test --only c_flank` | FAIL with and without the layer, identical message: "no safe flank: straight approach (exposure 93 % against 100 %)". The same refusal as the known K(flank) failure; not caused by this milestone. |
| `--qol011-test --only c_views` | PASS; exits cleanly with and without the layer |

**Observed, not resolved:** `--ai-squad-test` runs end with a segmentation fault at quit (exit 139), after they have written their results. This happens with and without the cover layer. The QOL tests exit cleanly. Whether it predates this milestone could not be checked without a second copy of the project.

## 13. Known limitations

- **Earth formations:** none (§3).
- **Box colliders are boxes:** a wall's ragged top or a rock group's gaps are not modelled (the group is 0.85 m everywhere along its box). The root plate's collider covers the plate, not the lying trunk.
- **Soldiers stand on the ground under cover objects' footprint** like on any ground; prone soldiers can lie right behind a log.
- **Tall meadow grass** hides the lowest objects (rock groups, logs) from a distance. That is their honest look.
- **Few rocky-ground objects:** only 38 ridges and 84 timber stacks (little ground passes the rockiness and road-forest rules).
- **Load time:** the layer adds about 0.19 s at start.
- **First-person screenshot:** not taken in the final run (§9).
- **Segfault at quit:** in `--ai-squad-test`, unclear origin (§12).

## 14. Recommended follow-ups

- **Earth formations** (shallow ditches beside forest roads, berms at field edges) as an in-memory terrain layer like the settlement layer, with the strategic grid, navmesh and road shoulders rebuilt from it.
- **End-of-move cover** for COMBAT / STEALTH moves now that cover is reachable (QOL-01.1 §4). Measure again with the layer before shipping.
- **Per-variant colliders** (several boxes per id) for rock groups and root plates with their trunks.
- **More rocky-ground features** where the rockiness map is high but slopes were rejected (bedrock steps).
- **The `--ai-squad-test` quit crash.**
