# ROAD-QUALITY-01 — Main road terrain integration and infantry traversability

Branch `develop`, not pushed. World: the adopted `ref_20km` (VISUAL-02 cover, `02d573c`); **no world file was changed** — the fix is
in `RoadShoulders`, which shapes the terrain beside the roads in memory at game start (manifest untouched). Markers: **[RUN]**
measured in the real game; **[CODE]** read in the source; **[NOTE]** judgement. The plan this follows is
[ROAD-QUALITY-01_PLAN.md](ROAD-QUALITY-01_PLAN.md) (its numbers were an offline model; everything below is measured in Godot).

## 1. Summary

The main roads' mesh (Road Generator) is not the road the terrain was fitted to. The mesh is 2 m wider on each side (its gutter),
stands 0.2 m above RoadNetwork's line, leaves the line in bends, and junctions are separate meshes. The terrain was eased to the
line, so the mesh edge hung over the ground — on embankments, beside junction surfaces and where two roads run side by side
up to 1–4 m. `RoadShoulders` now measures the road **collider** with rays and fits the terrain to it.

| Survey, 7 143 cross-sections every 20 m (14 423 edges) [RUN] | no shoulders | before (05B) | after |
|---|---|---|---|
| lip at the edge, median / p90 / p99 | 0.15 / 0.22 / 0.43 m | 0.02 / 0.11 / 0.27 m | 0.00 / 0.09 / 0.14 m |
| largest lip | 3.20 m | 4.09 m | 0.37 m (a culvert channel, kept) |
| edges higher than a step (0.35 m) | 234 | 88 | 1 |
| edges over 0.5 m / over 1 m | 110 / 49 | 55 / 26 | 0 / 0 |

| Near-tier soldiers at 16 fixed sites [RUN] | before (05B) | after |
|---|---|---|
| single soldier: cross both ways, road → shoulder, shoulder → road (64 legs) | 40 clean, 6 natural, 18 fail | 60 clean, 3 natural, 1 fail (a 3 s pause, §7) |
| squad of 6 across (8 legs) | 2 clean, 6 fail | 5 clean, 2 natural, 1 fail (§7) |
| along the road and along the verge (12 legs) | 11 clean, 1 fail | 11 clean, 1 natural (bridge, §7) |
| ledge hops / stuck stages, all legs | 22 / 32 | 1 / 2 (all at natural banks or not at the road, §7) |

The before run is the committed GAMEPLAY-05B `road_shoulders.gd` on the same world, sites and test code. One difference in the
criterion: it counted squad member recoveries globally (any squad), the after run counts only the leg's own soldiers becoming
BLOCKED; 2 of the 18 "before" crossing failures (both at navinf_04) failed on that count alone, the other 16 on a ledge hop, a stuck
stage, a stall over 2 s or not arriving. The before run was not repeated with the new criterion (not needed for the comparison).

"Clean" = arrived **without any stuck handling**: no ledge hop, no stuck stage, no BLOCKED state, no stall longer than 2 s on the way.
"Natural" = the leg's start or goal lies across a bank steeper than the infantry limit (tan 50°), in water, or beside a bridge deck;
those are reported, not counted as road defects.

## 2. Root causes [CODE] [RUN]

1. **The road mesh is wider and higher than the line the terrain was fitted to.** `ReferenceWorldBuilder._add_rp3` places every
   RoadPoint 0.2 m above the roads.json profile; Road Generator's default `gutter_profile` (2.0 m, −0.5 m, unchanged in the scene)
   adds a 2 m strip beyond each shoulder that falls 0.5 m. The collider is a one-sided trimesh (`create_trimesh_collision`) whose
   outer edge is free: wherever the ground is lower, a capsule meets a vertical lip. Survey: the collider ends median **2.0 m**
   beyond `RoadNetwork.width / 2`. GAMEPLAY-04A eased the terrain to the line; GAMEPLAY-05B modelled the gutter with constants
   (2.0 m, 0.28 m), which removed most lips on straight roads (88 left of 234).
2. **The 1.95 m terrain grid sags under the edge on embankments.** Heights live on vertices; between two vertices the ground is
   a straight line. With the ramp starting at the edge and falling steeply, the vertex 1–2 m beyond the edge sits low and the line
   from the last vertex under the gutter passes below the edge (the navinf_04 verge, the Rv2 fills north-east: 0.3–0.5 m).
3. **Junction surfaces were not fitted at all.** `RoadIntersection` meshes are wider than the arms; 56 of 195 radial sections had
   a lip over 0.35 m (Elvetun, Sentrum, Østby, Moen: up to 2 m).
4. **Two roads close together fought over the same vertices.** The first road written won; where two roads at different heights
   run 15 m apart (Fv sentrum–sør / Rv1 at (−385, 1760)) the terrain between them took the lower road's ramp and left the
   higher road's edge 4 m in the air (a vertical earth wall in the screenshots).
5. **Culverts.** At culverts the stream channel beside the road is natural; the fix keeps it (lips 0.2–0.37 m there are channel
   banks, not road edges).
6. **The route grid cache ignored the shoulders.** `StrategicRoutes` cached its grid as `..._shoulders.bin` whatever the easing
   was, so a change of the shoulders (05B included) reused a grid built on the old terrain. The name now carries the shoulder
   signature.

## 3. The fix (`scripts/world/road_shoulders.gd`)

- **Meshed roads are fitted to their collider.** Every 2 m along the centre line (71 649 stations) rays find the collider's edge on
  both sides and its height (`_edge`; a junction surface is followed to its far edge). Every terrain vertex near the road is tested
  with one ray: under the collider it lies just below the surface — 0.28 m under the carriageway as before, tapering to 0.04 m at
  the edge — so the edge meets the ground.
- **A short landing beyond the edge.** Where the ramp to the original terrain would start steeper than 0.35, the ground falls at
  0.35 for the first 3 m, then the GAMEPLAY-04A ramp continues (band 7–14 m, unchanged). 2 854 vertices; no flat strips: the
  landing is a 19° fall, only where the bank beyond is steep. `SHOULDER_MAX_M` stays 14 m — the 22 m band of the plan was not
  needed (§6).
- **Between two roads** a vertex takes both roads' heights and the ground runs straight from one edge to the other; within 3 m of
  the higher road's edge its landing is kept, so that edge never hangs (the lower edge is covered by the bank). Where the two
  edges are close and far apart in height the bank is steep — a natural obstacle (§6).
- **Priorities:** under a road surface beats beside it; a meshed road beats a track; tracks, local roads and settlement streets keep
  the GAMEPLAY-04A rule (05B's fake gutter no longer applies to roads without a mesh).
- **Bridges** decks are left alone, their approaches only raised; **culvert** channels within 8 m are kept.
- **Vegetation and grass.** The ground under the surface is now just below the asphalt, so plants and the GPU grass there grew
  through it (junction surfaces were never in the grass mask, which is painted from RoadNetwork's widths). Plants on vertices at
  least 1 m inside an edge are put 1.5 m under the ground (`fix_chunk`), and those texels are added to the grass exclusion mask in
  memory (`mask_grass`, before StructureManager copies the mask). Nearer the edge the verge keeps its plants and grass.
- **Cache:** the heights (and the under-road flags) are cached per signature in `user://terrain/` — the signature covers the rules,
  `CACHE_VERSION`, the road set and every road mesh's bounds; the route grid cache name includes it.
- Removed: the `--shoulders-g04` comparison switch (PERFORMANCE-01 prep, unused elsewhere; the old easing no longer exists in this
  form). Before / after comparisons were made by running the committed GAMEPLAY-05B `road_shoulders.gd`.

Other files: `RoadNetwork.Road` gains `mesh` and `culverts` (from roads.json); `CoreDemo._start_sandbox` passes the `Roads` node,
paints the grass mask and names the route grid cache; `--gameplay04-test a_shoulders` counts the plants kept under the asphalt
separately.

## 4. Problem locations (before → after) [RUN]

Largest lip within the place, survey every 20 m:

| Road | Place (x, z) | Before | After |
|---|---|---|---|
| Fv sentrum–sør / Rv1 (two roads 15 m apart) | (−385.6, 1759.6) | 4.09 m, earth wall under the upper road | 0.15 m; steep bank between the roads (natural) |
| Junction Elvetun | (−3008, −7487) | 2.05 m | 0.14 m |
| Junction Rv1 / Fv sentrum–sør | (−397.9, 1704.2) | 1.94 m | 0.13 m |
| Fv vest–lia (gully under the road) | (−5123.5, 1614.2) | 1.99 m | 0.09 m |
| Fv sentrum–vest junction | (−2463.9, −1226.6) | 1.56 m | 0.07 m |
| Junction Østby | (3252, 1899) | 1.53 m | 0.30 m |
| Junction Sentrum | (−900, −1800) | 1.37 m | 0.14 m |
| Junction Moen | (−1478, 7096) | 1.18 m | 0.16 m |
| Rv2 nord–øst embankment (14–21 m fill) | (−250 … −900, −6480 … −7150) | 0.48 m | 0.21 m; the fill itself 50–63° (natural) |
| navinf_04 verge (Centre Bridge route) | (−150.7, −1317.3) | 0.25 m | 0.18 m |
| Fv sentrum–vest culvert | (−8648.0, −1824.7) | 2.05 m | 0.37 m (stream channel kept) |

During the work, an intermediate version lifted Rv1 / Fv sør–tverr (7570, 6033), two parallel roads, to 0.64–0.90 m (each vertex
went to its nearer road); the edge-to-edge rule (§3) fixed it (after: 0.08 m).

By category (after): straight 7 975 edges, max 0.19 m; curves 5 861, max 0.23 m; junction arms 102, max 0.30 m; junction radial
sections 195, max 0.16 m; bridge approaches 28, max 0.14 m; culverts 262, max 0.37 m (one over 0.35 m).

## 5. Collision, navigation and the step height [CODE] [RUN]

- **Rendered road = collider.** The collider is the mesh itself (trimesh of the visible surface); the survey measures the collider,
  and the terrain now meets it. Under the carriageway the terrain stays 0.28 m below (the gap the survey reports, median 0.28 m) so
  distant terrain LODs never show through the asphalt; a soldier promoted onto a road is placed 0.3 m above the terrain, above the
  surface.
- **Navmesh vs body: `agent_max_climb` 0.5 m vs `SoldierBody.step_height` 0.35 m.** The navmesh (`AreaNavigation`) is baked from
  the terrain, tree trunks and parked vehicles only — it never contains a road edge, a wall or a kerb. On a continuous heightfield
  Recast's climb is the height between neighbouring 0.5 m voxels, i.e. a slope limit: 0.5 m per 0.5 m cell ≈ 45°, next to the
  infantry limit of 50° (`agent_max_slope`). The value cannot be 0.35: `cell_height` is 0.25 m and Recast rounds the climb down to
  whole cells, so it would become **0.25 m, cutting every slope over ~27° out of the navmesh** (most road banks, much of the world)
  — or `cell_height` would have to shrink (finer bake, more cost) and still cut slopes over 35°. **Not changed.** The mismatch only
  matters for discontinuities the navmesh does not see, and those are removed at their source (this milestone). Documented in
  `_rq_nav_climb` (`--road-quality-test --only nav_climb`).
- **Navmesh height error.** The bake uses `detail_sample_max_error = 1.0`; a path point can lie up to ~0.7 m below the road
  surface (measured at Fv øst nord–sør, (3571, 460)). Closer than 15 m to the goal `SoldierBody` then waits for a better path (the
  GAMEPLAY-04A rule) — the one remaining 3 s pause (§7). A finer `detail_sample_max_error` is a global navmesh change and was left
  alone; recommended as a follow-up.
- **No global value changed:** step height, hop height, floor angle, navmesh parameters and collision layers are as they were.

## 6. Visual quality, natural obstacles [RUN]

Screenshots at 1920×1080, the same frames before and after, in [docs/road_quality01/](road_quality01/) (`rq_<site>_before.jpg` /
`rq_<site>_after.jpg`): navinf04_verge, fvs_parallel, vestlia_gully, rv2_fill, rv1_curve, junction_rv1, junction_sentrum_v,
junction_elvetun.

- Junctions (Elvetun, Rv1, Sentrum-vest): the thick hanging edge of the junction surface is gone; grass meets the asphalt.
- Embankments (navinf_04, Rv2): the verge reaches the road edge with its grass; the fill below is unchanged.
- Two roads side by side (fvs_parallel): the earth wall under the upper road is replaced by a steep rocky bank between the roads.
- No flat strips: the landing is a 19° fall beside steep banks only; the ramp band is unchanged (7–14 m). VISUAL-02's ground
  shader, colour maps and vegetation are untouched (the shoulders change heights only; plants are moved, never removed).

**Natural, non-traversable banks** (steeper than tan 50° within 3–15 m of the edge), 50 cells of 100 m — reported, not fixed:
the Rv2 nord–øst fills (−280 … −1730, −6690 … −7060; 14–21 m high, 50–63°), Fv sentrum–øst (−125, −1274; 13.7 m, 67°) and
(−452, −1624), Fv sentrum–vest by Sentrum (−1304, −2129 and −1268, −2113: 11–12 m, 74–75°), Fv øst nord–sør (3009, 2162), Fv
nord–sentrum (−1584, −4377; −898, −2288…−2308), Fv vest–lia (−4060, 58), Rv2 (−5647, −9972). The full list is in
`benchmarks/raw/road_quality_test_after.json` (`survey.steep_natural`). Laying these back would need a band of up to 22 m or more
and change the landscape; per the brief they stay as obstacles. The plan's 22 m option was not used.

## 7. Remaining difficult locations

| Site | What | Cause |
|---|---|---|
| Fv øst nord–sør (3571, 460), crossing towards +z | arrives, but stands 3.1 s on the road on the way | navmesh height error (§5): a path point ~0.5 m under the soldier, < 15 m from the goal; not an edge (lip 0.11 m). Before the fix this site passed — the new terrain changed the navmesh polygons |
| Elvetun squad, one member | gives up one stuck stage 4 m from its start (−3022, −7472), recovers, arrives | settlement ground at the spawn point, before and after alike; not at the road |
| Rv1 bridge approach, along the verge (1096, 4484) → (1141, 4524) | never arrives | the goal lies beside the bridge deck above the river bank; the soldier misses the bridge and walks in circles below it (as the product owner observed). A bridge navigation case, not a road edge. **Fixed in BRIDGE-NAV-01** ([report](BRIDGE-NAV-01_REPORT.md)) |
| navinf_04 verge, squad of 6 | 4 of 6 arrive; two take a long detour (100 m) and one gives up there | the far side is a 52° slope (natural); formation slots on it are partly unreachable |
| Fv sentrum–sør / Rv1 parallel roads | steep bank between the roads | 4.7 m height difference across ~3 m between the edges: natural obstacle |
| Culverts (8 km of culvert zones) | lips 0.2–0.37 m | stream channel kept beside the road |

## 8. Vehicles [RUN]

| Test | Result | What it covers |
|---|---|---|
| `--ai-war-test --only r_offroad,r_lanes` | PASS (lanes: 99 % on own right, 4.0 m separation; off-road legs as before) | trucks / APCs on and off the roads beside the changed verges |
| `--navigation-n1c1-test` (all 13) | 13 / 13 PASS | bridges open / closed, infantry and vehicles on decks and approaches (approaches now raised) |
| `--navigation-n1b-test` (all 10) | 8 PASS; n1b_03 ERROR, n1b_07 FAIL | vehicle clearance, soft links, convoys, audit routes |

n1b_03 stops in its setup ("base lacks fuel point or supply depot": the dev scenario's base composition) and n1b_07 finds no isolated
road to test (0 listed: its precondition is missing, it reports FAIL rather than a hollow pass). Neither reads the terrain beside the
roads; they were not re-run against the GAMEPLAY-05B shoulders [NOTE]. Vehicle routing (`VehicleRouter` over `RoadNetwork`) is
unchanged; the road collider vehicles drive on is unchanged; only the ground beside it moved (by centimetres to decimetres, up to
the landing beside steep fills).

## 9. Performance [RUN]

| | before (05B) | after |
|---|---|---|
| `RoadShoulders.apply`, first start (computes, then caches) | 11.2 s (GAMEPLAY-04 figure) | 29–32 s (≈2.1 M rays, 71 649 stations) |
| `RoadShoulders.apply` from the cache | 0.88 s | 0.82–0.95 s |
| vertices written | 2.05 M | 1.69 M |
| `fix_chunk` per vegetation chunk (25 chunks round navinf_04) | — | mean 1.87 ms, p95 6.6 ms, max 7.5 ms |
| of which new in ROAD-QUALITY-01 (under-road lookup) | — | 0.31 ms per chunk |
| frame time | — | no per-frame code added (heights and the grass mask are set once at start) |

The first-start cost is paid once per road set and rule version (cache in `user://terrain/`); every later start reads the cache.

## 10. Tests

New: `--road-quality-test` (`scripts/debug/road_quality_selftest.gd`), results `benchmarks/raw/road_quality_test_<tag>.json`:
- `survey` — collider edge, lip, near grade, bank, gap under the carriageway; worst places per 100 m cell; natural steep banks.
- `cross`, `squads`, `along` — near-tier soldiers through the ordinary move order at 16 fixed sites (`SITES`); stall, hops, stuck
  stages and BLOCKED per leg; natural legs separated. `--sites=a,b` to pick sites.
- `shots` — the before / after frames (`--shot-tag`, `--at=x:z:side` for any place); `probe` — cross-section profiles, the
  station edge and the navmesh path at a site; `perf` — `fix_chunk` cost; `nav_climb` — navmesh climb / slope vs the body.

Regression runs (chosen because the terrain beside the roads, vegetation on it and the route grid changed):

| Run | Result |
|---|---|
| `--road-quality-test --only survey` (before / after / no shoulders) | after: max lip 0.37 m, 1 edge over 0.35 m (§1) |
| `--road-quality-test --only cross,squads,along` (before / after) | §1 |
| `--road-quality-test --only perf,nav_climb` | §5, §9 |
| `--nav-inf-test --only navinf_04` (the reported verge; known flaky near tier) | PASS — near 6/6, far 6/6, 0 ledge hops |
| `--scenario=new_game --gameplay04-test --only a_shoulders,a_road` | PASS — 0 plants off the ground (21 007 checked, 107 kept under the asphalt); 8/8 soldiers across the road at the New Game start, 0 hops, 0 stuck stages |
| `--ai-war-test --only r_offroad,r_lanes` | PASS |
| `--navigation-n1c1-test` | 13/13 PASS |
| `--navigation-n1b-test` | 8/10 (§8) |
| `tools/check_scripts.gd` | 179 scripts, 0 failed |

No full suite was run (shared systems touched: terrain heights beside roads, vegetation pass, route grid cache name — covered above).

## 11. Commits

| Commit | Content |
|---|---|
| `19c5515` | RoadShoulders fitted to the road collider, grass mask, route grid cache name, `RoadNetwork.Road.mesh/culverts`, `--road-quality-test`, a_shoulders check |
| (this commit) | report, README, CLAUDE.md, plan, before / after screenshots |

Not pushed. `main` untouched.

## 12. Recommendations

- Navmesh height precision (`AreaNavigation` `detail_sample_max_error` 1.0 → ~0.25–0.5, with a bake-cost measurement) or let a
  soldier near its goal walk straight when the path point lies under it — the last road pause (§7) and similar ones elsewhere.
- Bridges: soldiers sent to a point beside a deck should be routed over the deck, not to the river bank below it.
- If the steep fills should become passable in places, add ramps/paths as world features (data), rather than widening the band.
- The road mesh's gutter could be narrowed in the generator (`gutter_profile`) at the next world rebuild; that needs a candidate
  world and approval and is not required after this fix.
