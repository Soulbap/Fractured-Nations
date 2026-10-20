# WORLD-PLAYTEST-01 — Terrain, roads, navigation and camera controls

Branch `feature/world-playtest-01` (from `feature/unified-sandbox` 6418b12), worktree
`../fractured-nations-playtest01`. Not merged into `main` or into the unified baseline.

The first manual playtest found a river in a canyon of vertical walls, bridges that did not
look right, poor AI movement, no way to build roads, missing camera orientation on the
strategic map and fast-forward that did not reach the requested speed. Every item below was
first reproduced (measurement or screenshot), then fixed at its cause, then re-measured in the
real game on the rebuilt 20 km world.

## 1. River and terrain

### Root causes (measured, `tools/terrain_ref/generate.py`)

| Problem | Cause |
|---|---|
| River 27 m below the land between vertical, repetitive rock walls (north half) | The macro relief clamped the valley floor to *water level + 25 m* for ~1 km on both sides, while the full-resolution pass only cut the channel plus 9 m of bank. The regional "north rise" (+110 m) lifts the land above the river, so the clamp produced a flat terrace at +27 m and a vertical cut down to the water along 9 km. Rock texture (slope > 27°) painted the cut, hence the repeating stripes. |
| Steps of 5–10 m at the bank (south half) | The bank zone only *raised* terrain outside the channel, never lowered it. |
| **Every bridge stood on an earth dam that blocked the river** | Ordering bug in the world build: `ReferenceWorldBuilder.flatten_roads()` restored the river channel under the bridges immediately, but the Road Generator terrain connector only *queues* its flattening and runs it in the next physics frame, filling the channel up to the deck again. |
| Lake shores 66–89° walls | Lake beds were cut with `min(h, bottom)`; land above the water level dropped straight to the bed. |
| One local road ended in the middle of a bridge (10 m "bridge") | Layout: *Lv nordre* started on Rv2's waypoint in the river. |

### Changes

* Valley profile: a floodplain (40–320 m wide, varied by noise and terrain character) a little
  above the water, then valley sides at a bounded grade (7–24 %, steeper in rocky ground),
  applied as a smooth cap that grows with distance (`valley_params`, `smin`); re-applied after
  settlements are flattened. Full resolution: bank width varies (6–16 m), the land beyond the
  bank is capped at a bounded grade and blends out over 150 m; a wet dirt/gravel bank shelf is
  painted between water and meadow.
* Lakes: the same bounded-grade cap around the shore.
* Bridge channels restored *after* the connector has flattened (build waits for it).
* Bridge abutments: only the channel and its banks stay open under a bridge; the rest of a
  span gets an embankment up to the deck. Bridge decks now follow the road's slope between
  their ends (a level deck at the higher end floated 5.5 m above the road at the lower end of
  Fv sentrum-øst and looked like a separate road beside it — found by the product owner during
  this milestone).
* `tools/terrain_ref/rebuild_structures.gd` re-places bridges and culverts without a full build.

### Measurements (`docs/playtest01/audit_*.json`)

| | Before | After |
|---|---|---|
| Land 50 / 100 / 200 m from the river (median, above water) | 26.7 / 26.7 / 27.5 m | 2.2 / 2.2 / 5.9 m |
| River cross-sections with a bank steeper than 35° | 109 of 118 (85°, vertical) | 29 of 118 (≤ 36°, the 2–3 m bank ramp) |
| Bridges whose channel is filled (dam) | 4 of 4 (terrain 11–32 m above the water) | 0 of 4 |
| River samples where terrain reaches the water surface | 4 runs (at the dams) | 0 of 929 |
| Deck height above water | 11.9–33.4 m (decks on the +27 m terrace) | 8.3–12.4 m |

Screenshots `docs/playtest01/before/*.jpg` vs `docs/playtest01/after/*.jpg` (same viewpoints,
`tools/terrain_ref/shots_playtest01.json`): `river_north_along`, `river_north_aerial`,
`bridge_rv2` (dam → open channel), `bridge_rv1`, `lake_storvatnet_e`; bridge ends:
`after/endjoin_*.jpg`, `after/bridge_*_abutment.jpg`.

## 2. Road network audit

Two audits, both repeatable after every world build:

* `tools/terrain_ref/audit_roads.py` (source data): water crossings without a bridge, bridge
  ends/clearance/span, connectivity of road ends, height steps at junctions, grade over 20 m and
  curve radius per class (vehicle limits), carriageway width, terrain fit of painted roads.
* `tools/terrain_ref/audit_world.gd` (the built world as the game loads it): river and lake
  water vs terrain, bridge channels, terrain vs road surface (buried / floating), and the
  strategic route grid: every road sample is a road cell, a route between the banks of each
  bridge uses the bridge.

### Root causes found and fixed (generator)

* Path smoothing pinned every waypoint and left clustered points round bends → 10 m radius
  kinks; the grade clamp used the *mean* point spacing → 25–45 % grades on 3 m segments.
  Now: only junction waypoints are pinned, uniform resampling, curve relaxation to a minimum
  radius per class (60 / 45 / 28 / 18 m), the first road through a junction may round its
  curve there and later roads meet it, per-segment grade clamp.
* A* detours out to an off-route waypoint and back (Rv2 ran 100 m out and back on itself,
  leaving a 2 m step): spur removal.
* Town streets graded one by one met at crossings with steps of up to 12.5 m: streets now
  sample one shared smoothed street surface, are pinned where they cross earlier streets and
  roads, grade-limited, and stop where the hillside gets steeper than 15 %. Village streets were
  non-deterministic (Python's randomised `hash`); now seeded with CRC32.

| | Before | After |
|---|---|---|
| Roads / length | 127 / 310.9 km | 124 / 302.1 km (shorter: no spurs, trimmed hillside streets) |
| Audit errors (water, bridge, fit > 2 m) | 16 | **0** |
| Audit warnings (grade, curve, junction step) | 81 | 8 (curves of 14–43 m at 4 town junctions, one 12 % stretch, 1.8 m street step) |
| Bridges | 5 (one 10 m bridge ending mid-river) | 4, all continue on both banks |
| Built world: road samples buried / floating | 125 / 72 of 15 926 | 10 / 47 of 15 144 (at junction centres where intersection meshes meet) |
| Route grid: road samples not marked as road | 0 | 0 |
| Strategic route across each bridge uses the bridge | 5 / 5 | 4 / 4 |

Widths for vehicles: primary 7 m + shoulders, secondary 6 m, local 4.5 m (one lane), track
3.6 m, streets 5.5 m: one truck / AFV (2.5–3.6 m) per lane; tracks and local roads are single
lane by design (the audit reports them as info).

## 3. Player-built roads and paved areas

**One road network** (`scripts/world/road_network.gd`, `WorldState.roads`): the world roads
from `roads.json` plus every built road. Built roads and yards are ordinary construction
records (`StructureState` with a `StructureDef.Surface` type), so selection, deletion,
save/load (`construction.json`) and clearing reuse the construction system; there is no second
road system.

* `RoadNetwork` — world roads, built roads (from the construction records), spatial index,
  `nearest()` for snapping (road ends and junctions win), bridge decks, spline and grading
  shared with construction. Signals `changed(rect)`.
* `StrategicRoutes` — marks road cells from the network (world roads in the cached grid; built
  roads added / removed incrementally when the network changes). The grid cache now has a
  fingerprint of the world data (a rebuilt world used to reuse the old grid).
* `StructureManager` — grades roads and yards into the terrain with the existing groundwork
  (original heights kept, collision patched, navmesh faces updated, never written to disk) and
  paints them into the Terrain3D control map with the world's own gravel / dirt / asphalt
  textures (originals restored on removal); clears grass and trees. `_relevel` now only
  visits the vertices near pads and surfaces (a long road's bounding box would be ~500 000
  vertices).
* `ConstructionController` — road tool and area tool in the existing construction mode.

### Usage (construction mode, B → "Roads")

| Type | Width | Max grade | Route cost |
|---|---|---|---|
| Dirt track | 4.0 m | 16 % | 0.6 |
| Gravel road | 5.5 m | 12 % | 0.5 |
| Asphalt road | 7.0 m | 9 % | 0.45 |
| Gravel yard / Asphalt yard | polygon (≤ 40 000 m²) | 6 / 5 % plane | not a road |

* Road: LMB adds control points, the road is a centripetal Catmull-Rom curve through them.
  Drag a point with LMB to reshape. Ends snap to existing roads, road ends and junctions
  (snap ring, Ctrl disables); clicking onto a road with two or more points builds it, as do
  Enter / RMB / double-click. Backspace removes the last point. The preview shows the graded
  road green, failing sections red, with length, steepest grade and cut / fill.
* Refused with a reason: water ("roads cannot cross rivers or lakes; use a bridge"), outside
  the map, more than 3 m cut / fill, curves tighter than 9 m radius, blocking structures
  (walls, buildings; gates are fine), rocks / settlement buildings, trees when clearing is off.
  Units are not obstacles. Roads work inside and outside bases.
* Yard: click corners, click the first corner / Enter closes; graded to one plane (cut = fill),
  paved, grass and trees cleared. Yards are not part of the road network.
* X deletes a whole road or yard; F5 / F9 save and load with the base. Buildings never need
  roads: a road only makes travel on it cheaper for route planning (and later for vehicles).

### Validation (`--playtest-test --only roads`, PASS)

A curved gravel road (3 control points, 299 m, snapped to the world road *Lv nordvik*, steepest
12 %, cut / fill ≤ 1.2 m): terrain within 0.03 m of the profile, painted gravel along its whole
length, 15 / 15 grid cells marked as road, junction step to the world road 0.03 m, no tree
trunk left on either built road. An asphalt
road snapped to its end (step 0.00 m). A 1 446 m² gravel yard (4.2 % plane): not a road cell.
A dirt track across the river: refused (water). Strategic route along the new roads: 21 / 21
leg samples on a road. Save → clear → load: same surfaces, network and heights; removal restores
the ground exactly. Grading + painting a 300 m road: 8.5 ms (597 vertices levelled, 465
painted). Screenshots `docs/playtest01/pt01_roads_built.jpg`, `pt01_roads_built_close.jpg`.

## 4. AI pathfinding

### Reproduced (before the fix, `--playtest-test --only nav_river,nav_long,nav_base`)

* **Move order across the river (RTS right click), 2–3 km from the nearest bridge**: the squad
  walked straight through the river — 1 420 samples in river cells with the camera close
  (bodies) and 1 219 in the abstract tier; 0 route waypoints.
* 2.5 km move over hills: arrived, straight line, no water on that line.
* HESCO wall with a gap between squad and goal: bodies (navmesh) and the abstract tier
  (sliding along structures) both got round it — local obstacle navigation worked.

### Causes

* A player / RTS **Move** order never used the strategic route planner (only the war's
  operations did). Bodies whose target lies beyond the local navmesh area walk straight at it;
  the abstract tier walks straight lines. Nothing on that line knows about water or cliffs.
* A squad marching in line formation over a bridge put its outer soldiers beside the deck.
* The abstract tier took the terrain height under a bridge (the river bed).
* Abstract movement tested every module of a 128 m structure cell per step (see 7).

### Changes (no new navigation manager)

* `SquadControl.order_move` — a Move farther than 150 m, or one whose straight line crosses
  water or ground the grid rules out, follows a `StrategicRoutes` route (the same planner as the
  operations): column formation on the march, the ordered formation again on the last leg.
  A stalled leg is re-planned from the squad's position (up to 3 times) before a waypoint is
  skipped (route recovery). Short clear moves are unchanged.
* `RoadNetwork.deck_height` / `onto_deck` — the abstract tier and formation slots stand on the
  bridge deck, and soldiers beside a deck over the river close up onto it.
* Roads are preferred through the grid weights (built roads included); off-road movement keeps
  the slope cost and impassable slopes.

### Verified (after, PASS)

| Scenario | Result |
|---|---|
| River crossing, camera close (bodies) | via the bridge 2.9 km away, 59 waypoints, 6 / 6 arrived on the far bank, **0** wading samples (water > 0.5 m above the feet), longest stall 0.2 s |
| River crossing, abstract tier | via the bridge 2.1 km away, 46 waypoints, 6 / 6, **0** wading |
| 2.5 km over hills (abstract) | 33 waypoints, 6 / 6, no water, no impassable cells |
| HESCO wall with a gap (bodies / abstract) | 6 / 6 round the wall in both tiers |

## 5–6. Strategic map camera, middle mouse

* The strategic map draws the tactical camera at its real position with a faint wedge of its
  horizontal field of view in the direction it looks, plus a small cross on its focus; it
  redraws with the map (every 0.1 s), so it follows moves and turns. Screenshots
  `pt01_map_camera_wedge.jpg`, `pt01_map_camera_rotated.jpg`.
* Middle mouse on the map: drag pans (unchanged); a press that moves less than 5 px is a click
  and moves the tactical camera there (heading, tilt and zoom kept, so its height above the
  ground; RTSCamera keeps it above terrain and in front of structures). The map stays open.
  Test: focus lands exactly on the clicked point, the map does not move, camera 109 m above the
  ground; a 60 px drag pans 60 px and does not move the camera.
* RTS view: middle-drag horizontal = rotate (unchanged), vertical = tilt, clamped to 8–84°
  below the horizon on top of the zoom-dependent pitch.

## 7. Time compression

The fixed 1/60 s step is unchanged (k x runs k times as many normal steps). Measured with the
war running, player settings, 6 s per speed (`--only timescale`), same conditions before and
after (120–144 units, 24–32 bodies). Two baseline runs are shown because the RTS numbers vary
with what the soldiers near the camera do:

| Requested | RTS before (run 1 / run 2) | RTS after | Map before (run 1 / run 2) | Map after |
|---|---|---|---|---|
| 2 x | 1.7 / 1.6 | **2.0** | 2.0 / 2.0 | **2.0** |
| 4 x | 2.4 / 2.1 | **4.0** | 4.0 / 4.0 | **4.0** |
| 8 x | 7.5 / 6.5 | **8.0** | 8.0 / 7.2 | **8.0** |
| 16 x (new level) | 11.5 / 10.0 | 11.1 | 9.4 / 7.6 | 9.4 |

Causes and fixes:

* **Abstract movement inside bases cost 6–7 ms per tick** (every HESCO module of a 128 m cell
  tested per step): blocking footprints now sit in an 8 m grid built once per change — same
  boxes, same answers, 0.2–0.4 ms per tick. This was why 2 x and 4 x fell short.
* The player's setting allowed at most 16 steps per frame: now adapted to a 50 ms frame budget
  (8 … 4k steps); the view stays above ~20 fps.
* The 3D world is not rendered while the strategic map covers the screen.

Limit: a tick costs ~1.4 ms with the war running (CombatBrain perception ~0.5 ms of it, which
scales with simulated time and is not cut, Jolt and bodies most of the rest), so this machine
tops out at ~10–11 x; 16 x is offered and the HUD shows the speed reached.

## 8. Testing

Change-impact testing only (no full suite):

* New: `--playtest-test` (`scripts/debug/playtest_selftest.gd`): `nav_river`, `nav_long`,
  `nav_base`, `roads`, `camera`, `timescale` — all PASS (results in
  `benchmarks/raw/playtest_test.json`).
* Audits: `audit_roads.py` 0 errors, `audit_world.gd` (see section 2).
* Regression for the shared systems changed (no full suite):
  * `--base-test` (structure index, groundwork rewrite): PASS.
  * `--integration-test` (construction on the reference world): PASS after one test change.
    Its "open meadow" site search had found the flat, tree-free 27 m river terrace — the bug
    this milestone removed — and found nothing within 6 km afterwards. The meadow criterion now
    accepts a gentle slope (≤ 4° over 20 m) and up to four trees within 70 m; site found at
    (-6962, -7540), 1.4°, no trees within 60 m. `--search-only` prints why candidates fail.
  * `--squad-test` (Move orders now route over 150 m): PASS (same site search).
  * `--sandbox-test --only routes,navigation,map_ui,persist,warp_fidelity`: PASS (operations'
    river march via a bridge, 0 water samples; save / load; map UI; 24 x fixed-step fidelity).
* Exit: a test that changes structures or roads now waits for the debounced navmesh rebake
  before quitting (a bake still on a worker thread crashed the engine on exit).

## Known limitations

* Players cannot build bridges; built roads stop at water.
* A built road through dense forest clears trunks from the road and 3 m beside it (test: 0
  trunks on the built roads); crowns of the trees beside can still overhang the road.
* Road paint follows the 2 m terrain vertex grid (soft edges), like the world's unpaved roads.
  Built roads have no lane-marked mesh; asphalt roads are painted asphalt.
* Edit an existing road by deleting and redrawing it (control points can be dragged only while
  drawing).
* Yards overlapping a building: the building's pad wins under its footprint.
* 8 curve / grade warnings remain at town junctions (audit); junction centres of paved roads
  show small terrain mismatches under the intersection meshes.
* 16 x is CPU-bound at ~10–11 x with the full war.
* The river centre line north of Sentrum is long and straight (layout); the valley is natural,
  the course could meander more in a later layout pass.
* Storvatnet reports 76 "dry" inner samples: its islands.
