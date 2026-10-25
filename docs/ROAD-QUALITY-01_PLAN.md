# ROAD-QUALITY-01 — survey and plan (before any change)

Status: investigation only. Nothing in the game, the world files or the tests has been changed. Not committed. The final
milestone report will be `docs/ROAD-QUALITY-01_REPORT.md`; this file is its starting point.

Markers: **[CODE]** read in the source; **[OFFLINE]** measured by a model built from `roads.json` + `height.r32` (outside
Godot; must be confirmed in the game, plan step 1); **[05B]** measured in the game by the GAMEPLAY-05B session.

World check: `world_manifest.py verify --ignore-editor-metadata` → `VERIFY ref_20km OK: 536 files checked, 0 missing,
0 changed, 0 extra` (2026-10-25).

## 1. Scope

The main roads are the 10 roads with a Road Generator mesh in `roads.json` (2 primary, 8 secondary), 137.6 km of mesh in
total (143 km of polyline), 4 bridges and 10 junctions. Local roads, tracks and settlement streets have no mesh (terrain
paint only).

## 2. Root causes

1. **The road mesh is not the road RoadShoulders fits the terrain to** [CODE].
   - `ReferenceWorldBuilder._add_rp3` places every RoadPoint 0.2 m above the roads.json height.
   - Road Generator's default `gutter_profile` (2.0 m, −0.5 m), left unchanged in the scene, adds a 2 m strip outside each
     shoulder that falls 0.5 m. It is a one-sided trimesh (`create_trimesh_collision`) with a free outer edge: wherever the
     terrain is lower than that edge, the capsule meets a vertical lip.
   - At build time `Terrain3DRoadConnector` fitted the terrain to this mesh. GAMEPLAY-04A's `RoadShoulders` then
     overwrites it at game start against the `RoadNetwork` polyline and width, which has no gutter and sits 0.2 m lower.
   - GAMEPLAY-05B's uncommitted change models the gutter with constants (2.0 m, 0.28 m).
2. **The terrain grid cannot hold the edge (main cause after 05B)** [OFFLINE]. The vertex spacing is 1.953 m and the gutter
   is 2 m wide. Where the ramp beyond the edge falls steeply (embankments), the straight line between the last gutter vertex
   and the first ramp vertex sags below the mesh edge.
3. **The mesh is laterally offset from the polyline on curves and near bridges** [OFFLINE]. The mesh is a Bézier through a
   simplified polyline (0.8 m / 0.25 m tolerance, handles 0.35 × d). Offset: median 0.06 m, p99 0.45 m, max 1.48 m, so the
   terrain is fitted beside the real edge. Vertical offset is small (p99 ±0.03 m, min −0.33 m).
4. **Steep roadside banks** [OFFLINE]. The ramp band is capped at `SHOULDER_MAX_M` = 14 m, so 12–19 m cuts and embankments
   become 45–54°. Seven areas are steeper than `INFANTRY_MAX_GRADE` (50°).
5. **Bridge approaches** [CODE]. `RoadShoulders` skips segments within 15 m of a span end. There the connector's
   mesh-fitted terrain meets the eased terrain, which is about 0.28 m lower under the gutter: a likely step along the road
   edge. The mesh offset is also largest at pinned bridge ends (0.8–1.26 m).
6. **Junctions** [CODE]. The `RoadIntersection` meshes (at +0.2 m, 14 m trimmed arms) are not part of the shoulder fit.
   Not measured; needs the in-game survey.
7. **05B side effect** [CODE]. `MESH_EDGE_M` / `MESH_EDGE_DROP_M` apply to every world road, including tracks, local roads
   and streets that have no mesh, which adds a needless 2 m cross-fall strip there. `RoadNetwork.Road` has no `mesh` flag.
8. **Navigation sees none of it** [CODE]. `AreaNavigation` bakes the terrain only, with `agent_max_climb` 0.5 m, while
   `SoldierBody.step_height` is 0.35 m. Road lips are invisible to the navmesh. This resolves itself once the terrain meets
   the mesh edge; no global change is proposed.

## 3. Measurements [OFFLINE]

68 822 cross-sections every 2 m. The gutter-edge lip was sampled every 4 m on both sides, on terrain made of the 1.953 m
vertex grid as `RoadShoulders` (05B version) eases it. "Lip" means mesh edge minus terrain.

| | median | p90 | p99 | max |
|---|---|---|---|---|
| lip, continuous profile (no grid) | 0.06 | 0.08 | 0.15 | 0.52 |
| lip, vertex-sampled (what collision sees) | 0.02 | 0.32 | 0.75 | 1.18 |
| lip on embankment sides (drop > 2 m) | 0.14 | 0.49 | – | 1.14 |
| roadside ramp grade | 0.24 | 0.48 | 0.84 | 1.36 (54°) |

- Vertex-sampled lip above 0.35 m (the step height): 8.4 % of edge points. Above 0.5 m: 3.7 %.
- 529 cells of 100 m have at least one edge point with a lip above 0.3 m.
- Cross-check against [05B] in the game (30 secondary-road sections after its fix): p90 0.32 m, the same as this model.
  The model's worst area is the navinf_04 verge that 05B found in the game.

## 4. Problem locations (x, z)

| Road | Area | Finding |
|---|---|---|
| Fv sentrum–øst | (−90…−285, −1240…−1480) | lip 1.07–1.18 m, 12–16 m embankment, 48–49° (navinf_04, Centre Bridge route) |
| Rv2 nord–øst | (−200…−1730, −6690…−7060) | 14–19 m embankment, 45–54°, lip ~1.1 m |
| Fv nord–sentrum | (−1770…−2310, −4230…−4560) | lip 1.03–1.09 m |
| Fv sentrum–sør | (−1500…−1600, 8720…8920) | lip 1.04–1.13 m, ~5 m embankment |
| Cuts over 40° | Fv nord–sentrum (−1133, −3667) 46°; Fv sentrum–vest (−6400, −557) 41–43°; Rv2 (−5528, −9985) 49° | steep banks |
| Mesh offset from the polyline | Fv sør–tverr (55, 7386) 1.48 m, (4735, 6536) 1.10 m; Rv2 (2158, −5464) 1.01 m; bridge ends Fv sør–tverr (700–711, 7297–7300) 1.2–1.26 m and Rv1 (1099–1121, 4463–4495) 0.8–1.1 m | terrain fitted beside the real edge |
| Junctions (10), bridge approaches (4) | – | not modelled offline; in-game survey |

## 5. Plan

0. **Wait for GAMEPLAY-05B to commit.** It owns the uncommitted changes in `road_shoulders.gd` and `soldier_body.gd`.
1. **In-game survey** (`--road-quality-test --only survey`). Every 20 m on both sides of all 10 main roads, including
   junctions and bridge approaches, rays measure the road collider against the terrain: lip at the mesh edge and slope 0–6 m
   beyond it. Output: a JSON list of locations with severity. This gives the before and after measurement and generalises
   05B's `n_roads` (30 sections).
2. **Crossing test** (`--only cross`).
   - About 24 sites taken from the survey: straight, curve, junction, slope / embankment, bridge approach, worst lips.
   - One near-tier soldier crosses both ways and walks road → shoulder and shoulder → road.
   - A 6-soldier squad at 4 hard sites.
   - Records arrived / stuck, stuck time, ledge hops and final position.
   - The baseline must fail at the lips; otherwise the test proves nothing.
   - Success after the fix means arriving with no ledge hop needed (the hop is a fallback, not the fix).
3. **Fix in `RoadShoulders`.** Runtime and memory only; no world files, no manifest change.
   - a. For mesh roads, take the centreline, height, width and gutter from the generated road segments' curves (the real
     mesh) instead of the polyline and 05B's constants. This removes the curve offset. `RoadNetwork` stays the only road
     data; this is terrain fitting to the visible geometry.
   - b. Grid-safe edge. Terrain vertices up to one vertex spacing beyond the mesh edge are held at edge height (≈ 2 m
     landing) before the ramp starts, and the edge is buried 3–5 cm. Target: terrain at the mesh edge between −0.05 and
     +0.10 m.
   - c. The gutter treatment applies to mesh roads only. Tracks, local roads and streets go back to the 04A profile.
   - d. Lay steep banks back to at most ~40–45°, with a band up to ~22 m only where the drop is large (~17 areas). Nothing
     else in the landscape changes.
   - e. Bridge approaches: fit to the mesh without cutting into the abutment (raise only), so there is no seam.
   - f. The same edge rule on the junction meshes' outer edges.
   - The cache signature includes the new parameters; the vegetation re-grounding is unchanged.
4. **No global changes** to step height, collision or stuck recovery. The navmesh stays terrain-based (the terrain then
   matches the road).
5. **Validation.**
   - Survey before / after. Targets: p99 ≤ 0.15 m, max ≤ 0.30 m.
   - The crossing test.
   - `--nav-inf-test navinf_04` near tier, 3 runs (known flaky).
   - Vehicles: `--navigation-n1b-test`, `--ai-war-test --only r_offroad,r_lanes`.
   - Bridges: `--navigation-n1c1-test`.
   - GAMEPLAY-04 shoulders: `--gameplay04-test --only a_shoulders,a_road`.
   - Performance: `RoadShoulders` compute time (now 11.2 s on the first run, 0.67 s from the cache) and frame time.
   - 1920×1080 before / after screenshots of 6 sites, and a short real-game run with soldiers along and across the sites.
6. **Report** `docs/ROAD-QUALITY-01_REPORT.md`, README, one line in CLAUDE.md. One commit per phase on `develop`, no push.

**Alternative, not first choice:** a smaller gutter in the road mesh itself. That means rebuilding `scenes/world/ref_20km.tscn`,
which is locked by the manifest, so it needs a candidate world and the product owner's approval. Only if the runtime fix is
not enough.

## 6. Survey scripts

Kept outside the project (session scratchpad; run with Blender's Python, which has numpy): `road_survey.py`
(the mesh centreline rebuilt like `ReferenceWorldBuilder`, compared with the polyline) and `road_survey2.py`
(vertex-sampled lip, steep banks, hotspots). They become the in-game survey of step 1 and are not needed after it.
