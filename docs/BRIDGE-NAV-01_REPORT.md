# BRIDGE-NAV-01 — near-tier infantry beside a bridge deck

**Branch:** `develop` · **World:** `ref_20km` (unchanged, manifest untouched) · **Date:** 2026-10-25

## 1. The case

ROAD-QUALITY-01 §7 left one leg that never arrived: a soldier ordered along the verge of the Rv1 bridge approach, from
(1096, 4484) to (1141, 4524), "misses the bridge and walks in circles below it" (the product owner saw the same in play).
Repro: `--road-quality-test --only along --sites=bridge_appr_rv1`, leg `along_shoulder` (45 s, 0/1 arrived, ended at
(1131, 80.7, 4524) — 6 m below the deck).

## 2. What the ground there is

`bridge_r0_s0` (Rv1, 98 m) does not start over the river: its first 40+ m lie on an earth fill that the generated world
(Terrain3D regions) carries under the deck — the source relief (`height.r32`) has the valley floor at 75–81 m there, the game
terrain stands at deck height (86–87 m) for ±9 m round the centre line (RoadShoulders changes it by < 0.8 m). Beside the deck the
fill drops 6–9 m at 70–78°. The order's point, 1.5 m beyond the road edge, lies on that face: 3.9 m beyond the deck edge and
2 m below it.

## 3. Why the soldier looped — three causes, each fixed where it arises

| # | Cause (measured) | Fix |
|---|---|---|
| 1 | **The slot stayed on the bank face.** `SquadControl._free_ground` only moved slots off water and structures. The navmesh's nearest point to a goal on the face is the bare lip, so every path ended on the lip. | Beside a deck (`DECK_SIDE_M` = 6 m), a slot on ground nobody stands on — wet, blocked, or steeper than `WorldSim.INFANTRY_MAX_GRADE` (`_steep`, central differences over 1 m) — goes onto the open deck (`RoadNetwork.onto_deck`), before the ring search. The order means the bridge. |
| 2 | **The terrain collision was triangulated along the other diagonal.** `TerrainCollisionStreamer` builds Jolt `HeightMapShape3D` chunks, which split each 1.95 m cell (x1,z0)–(x0,z1); Terrain3D's mesh and the navmesh source faces split it (x0,z0)–(x1,z1). Over 9 760 samples round the site the physics matched the other diagonal to 0.0001 m and lay up to 1.95 m below the navmesh surface at the lip — the edge the navmesh walked along was not there physically, the body slid down the face. | Each chunk shape is turned 90° about Y with its data re-indexed (a proper rotation, no negative scale), so its fixed diagonal is Terrain3D's. After: physics equals the Terrain3D triangles (worst 0.00007 m). This applies to all near-tier terrain collision; on smooth ground it moves the surface by centimetres. |
| 3 | **A waypoint 1.4 m above a hollow was never reached.** `NavigationAgent3D` reaches a waypoint within `path_desired_distance` (1 m) in 3D. A portal point on a long navmesh edge across the concave toe of the approach embankment lay 1.4 m above the ground; the soldier walked under it, turned back, and flip-flopped on the spot (the 3 s stall at (1120, 4510) in ROAD-QUALITY-01's runs; with 1+2 fixed it became a stuck stage). | `SoldierBody._ground_waypoint`: a waypoint also counts as reached on the ground (flat distance ≤ `path_desired_distance`), remembered until the agent moves on or the path changes; the last point is never skipped. `_next_distinct_dir` starts there too. No stuck-recovery change. |

Each fix alone was not enough (1 alone: the soldier still slid off the lip of the climb; 1+3 without 2: 2 of 2 runs still loop
below; 1+2 without 3: stuck stage at the hollow).

`StrategicRoutes` and `RoadNetwork.bridge_at` are not involved: the order is 60 m, a straight squad move (no strategic route);
bridge cells and deck data were correct. The navmesh itself (terrain-only, `AreaNavigation`) was not changed.

## 4. Results

| Test | Before | After |
|---|---|---|
| `--road-quality-test --only along --sites=bridge_appr_rv1` along_shoulder | never arrives (NATURAL) | **PASS**, arrives on the deck slot (1144.3, 87.5, 4519.9) in 14.5 s, no stall / hop / stuck |
| `--road-quality-test --only along` (12 legs, all sites) | 11 PASS, 1 natural | **12 PASS** |
| `--road-quality-test --only squads` (8 legs) | 5 PASS, 2 natural, 1 FAIL (Elvetun) | **6 PASS**, 2 natural (navinf_04 52° far side), 0 FAIL |
| `--road-quality-test --only cross` (64 legs) | 60 PASS, 3 natural, 1 FAIL (fvon 3.1 s pause) | 60 PASS, 2 natural, **2 FAIL**: rv1_curve shoulder_to_road, culvert_west cross_- (both arrive; one ledge hop each) — see §5 |
| `--navigation-n1c1-test` (13) | 13 PASS | **13 PASS** |
| `--nav-inf-test` (12) | — | 10 PASS; navinf_05 FAIL = known precondition ("strategic route has fewer than 3 waypoints", VISUAL-02 §14); navinf_12 FAIL once (1 of 6 near-tier soldiers stuck at a vertical obstacle), **PASS** 6/6 on re-run — flaky, like navinf_04 |

Results: `benchmarks/raw/road_quality_test_bridgenav.json`.

## 5. Open points

- **Two road-edge crossings need one ledge hop** (rv1_curve shoulder_to_road, culvert_west cross_-; reproducible). Isolated: the
  culvert hop comes from the collision rotation alone; rv1_curve only with rotation and waypoint rule together. Cause: ROAD-QUALITY-01
  fitted and surveyed the road edges against `Terrain3DData.get_height`, which is neither triangulation (it differs from the
  Terrain3D triangles by up to 1.8 m at sharp edges); the soldiers walked on the old diagonal, now on Terrain3D's. The survey and
  `RoadShoulders` should measure the triangle surface and re-fit (bump `CACHE_VERSION`). Not done here (outside this case).
- **Navmesh clearance at drop-offs**: navmesh polygons still reach a bank lip with ~0 m clearance (agent_radius 0.5, contour error
  1.3 voxels); with physics now matching the navmesh this no longer drops soldiers off at this site, but a path hugging a lip is
  still tight.
- Terrain3D's own collision (used where the streamer is not) was not checked for the same diagonal mismatch.

## 6. Files

- `scripts/core/squad_control.gd` — `_free_ground` deck rule, `_steep`, `DECK_SIDE_M`.
- `scripts/world/terrain_collision_streamer.gd` — chunk rotation / data order.
- `scripts/units/soldier_body.gd` — `_ground_waypoint`, `_next_distinct_dir` start index.
- `scripts/debug/road_quality_selftest.gd` — a single soldier is judged at the slot its order resolved to (`slot` in each row).
