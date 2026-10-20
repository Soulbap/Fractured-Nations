# WORLD-INTEGRATION-03 — Unified world, military assets and faction integration

Branch `feature/world-integration-03` (worktree `../fractured-nations-integration03`), the new
development baseline. Not merged into `main`. The source branches and their worktrees are
untouched.

Status tags: **[VERIFIED]** checked by `--integration03-test` or another scripted run in the
real game; **[INSPECTED]** looked at in Godot screenshots; **[NOT VERIFIED]** not tested.

## 1. Integration summary

### Sources and merge

| Branch | Head | Base | What it brought |
|---|---|---|---|
| `feature/unified-sandbox` | 6418b12 | — | INTEGRATION-02 baseline |
| `feature/world-playtest-01` | 87634df | 6418b12 | 94 files: river / lake / bridge geometry, audited road network, `RoadNetwork`, built roads and yards, routed Move orders, bridge traversal, map camera wedge, middle-mouse teleport and tilt, 16 x time compression, regenerated world |
| `feature/asset-production-01` | 7d28da7 (4 commits) | 6418b12 | 835 files: 96 static assets with LODs, collision and markers, 33 `StructureDef` resources, three faction loadouts (19 pieces), CHARACTER-01 re-export with the hip fix, 51 shared materials, asset lab and validator |

Both branches were confirmed to start at 6418b12 (`git merge-base`). Merge strategy: two
ordinary merges into a branch created from `feature/unified-sandbox` —
`ad74c9c` (playtest) then `61badcc` (assets). The only file touched by both branches is
`README.md` (merged cleanly); **no conflicts**. Uncommitted work found in the other worktrees
(an editor re-save of `.tres` / `.import` files and three screenshots in
`../fractured-nations-unified`, a `project.godot` main-scene change in the main checkout) was
left where it was.

The generated world is git-ignored (`worlds/ref_20km/*`, `scenes/world/ref_20km.tscn`,
2.3 GB). It was copied from `../fractured-nations-playtest01` (the WORLD-PLAYTEST-01 data:
124 world roads, 302.1 km, the "after" audit state) together with the `.godot/imported`
caches of both source worktrees, after which `--headless --import` took 37 s instead of a full
re-import. **The world in this worktree is the WORLD-PLAYTEST-01 world [VERIFIED]**: the game
reports `roads_world 124, road_km 302.1`, the strategic route grid was accepted from the
`user://` cache because its fingerprint matches this source data (a rebuilt world would have
invalidated it, WORLD-PLAYTEST-01 §3).

Reproducible copy procedure for a new worktree:

```bash
robocopy ../fractured-nations-playtest01/worlds/ref_20km worlds/ref_20km /E /XF world_config.tres
copy ../fractured-nations-playtest01/scenes/world/ref_20km.tscn scenes/world/
robocopy ../fractured-nations-playtest01/.godot .godot /E /XD editor      # optional import cache
Godot_console.exe --headless --path . --import
```
(or rebuild with `tools/terrain_ref/build_ref_world.sh`, about 14 min).

### Gameplay changes on top of the merge

| File | Change |
|---|---|
| `scripts/construction/structure_def.gd` | `walkable` flag (no collision body, no nav obstacle; footprint kept for placement checks); `bounds()` falls back to `size` when nothing is solid |
| `scripts/construction/structure_catalog.gd` | six menu categories; loads every `StructureDef` under `assets/military/defs/` and `assets/military/defs/props/` after the code-built set; asset categories folded into menu categories; props and road dressing drawn to 700 m |
| `scripts/ui/construction_panel.gd` | collapsible categories (one open, count in the header), scroll area for long categories |
| `scripts/core/world_state.gd` | `FACTION_LOADOUTS` table and `faction_loadout()` |
| `scripts/characters/infantry_loadout.gd` | `default_for(unit_id, faction)` returns the faction's family when configured |
| `scripts/units/soldier_body.gd`, `scripts/units/unit_proxy.gd` | pass the unit's faction to `default_for` (three call sites) |
| `scripts/characters/infantry_materials.gd` | `FACTION_CAMO` = the three family camouflages (shared `Camo_M23` pieces and legacy loadouts match their faction) |
| `scripts/core/world_sim.gd` | abstract-tier sliding fix (§4.3): the next step is tested as well as the 1 m look-ahead; a unit inside a footprint backs out instead of walking through |
| `assets/military/defs/{obstacle_crawl,obstacle_tires,vehicle_parking_pad}.tres` | `walkable = true` (and the pad sunk 0.15 m) |
| `assets/military/defs/props/*.tres` (26, new) | prop StructureDefs written by `tools/asset_production/make_prop_defs.py` (new) |
| `scripts/debug/integration03_selftest.gd` (new), `scripts/game/core_demo.gd` | `--integration03-test` scenarios A–G |
| `CLAUDE.md`, `README.md`, `.gitignore` | baseline branch, catalog / faction-table principles, test command; root `*.log` ignored |

No new managers, no compatibility layers, no per-faction character implementation, no second
road system, no vehicle framework.

## 2. Architecture

### Data ownership (unchanged)

| Data | Owner | Representations |
|---|---|---|
| Units (identity, faction, position, health, orders, **loadout id**) | `WorldState.units` → `UnitState` | `SoldierBody` (near), `UnitProxy` (far), `Viewmodel` (FPS) |
| Faction identity North / South / East | `WorldState.FACTION_NAMES`, `WarState.FactionState` | — |
| Faction → equipment family | `WorldState.FACTION_LOADOUTS` + `InfantryMaterials.FACTION_CAMO` | read only by `InfantryLoadout.default_for()` / material lookup |
| Structures | `WorldState.construction` → `ConstructionState` / `StructureState` (type id + transform / points) | `StructureManager`: MultiMesh per cell, collision bodies, groundwork pads, grass clearing, nav obstacles, blocking grid |
| Structure types | `StructureCatalog` (code set + `.tres` resources) | `StructureDef` |
| Roads | `WorldState.roads` → `RoadNetwork` | `StrategicRoutes` grid, construction snapping, grading |
| Terrain | Terrain3D under `worlds/ref_20km/` (never written by the game) | groundwork edits heights in memory |

### How the new assets are registered

* **Buildings and modules (33)** come in as the `StructureDef` resources the asset pipeline
  wrote (`assets/military/defs/*.tres`). `StructureCatalog._load_resource_defs()` loads every
  `.tres` in the two def folders after the code-built WORLD-BASE-01 set; a resource whose id
  the code set already has is skipped. Nothing else is needed: `StructureManager`,
  `ModularLine`, `ConstructionController` and the construction save already read only
  `StructureDef` fields.
* **Props (26 of 51)** have no pipeline-written defs because what is worth a menu entry, how a
  line of them behaves (module length, how it sits on a slope, what it snaps to) and where it
  goes in the menu are gameplay decisions. `tools/asset_production/make_prop_defs.py` holds that
  table and writes `assets/military/defs/props/<id>.tres` from the sidecar numbers (size,
  Godot-space collision boxes, SNAP markers). It needs no Blender. Left out on purpose: colour
  variants, duplicates of the WORLD-BASE-01 set (HESCO cells, chain-link fence / gate, F-shape
  barrier), small decor (jerrycans, cans, single sandbags, cones), road surface sections
  (painted roads are the road system), `bridge_small` and `road_culvert` (need terrain cuts the
  player construction does not do).
* **Meshes** go through the unchanged `StructureCatalog.mesh_of()`: the first `MeshInstance3D`
  of the GLB (`<id>_LOD0`, first by the asset validator) with Godot's automatic LODs, drawn as
  MultiMesh per 128 m cell like the WORLD-BASE-01 assets. The library's shared materials
  (vertex-colour dirt, alpha chain-link / HESCO mesh / camo net) come with the import script.
* **Menu categories.** Asset categories ("Ammunition", "Fuel", "Checkpoint", "Shelter", ...)
  are folded into six by `StructureCatalog.MENU_CATEGORY`: Buildings 11, Training 15,
  Logistics 11, Defences 18, Infrastructure 14, Roads 5 — 74 types **[VERIFIED]** (`catalog`
  check: all nine buildings, 24 modules, every library mesh loads, walkable types have no
  collision).
* **Loadouts.** `assets/characters/infantry/loadouts/{NATO,RU,CN}_rifleman.tres` are found by
  `InfantryLoadout.by_id()`; no registration.
* **Vehicles** are not registered anywhere: a drivable vehicle will be a `UnitState` of kind
  VEHICLE in the next milestone, and a temporary structure entry would have ended up in
  `construction.json` saves. The integration test instantiates the GLBs to validate them (§4.6).

### Faction loadout configuration

`WorldState.FACTION_LOADOUTS = ["NATO_rifleman", "RU_rifleman", "CN_rifleman"]` (index =
faction id: North, South, East) and `InfantryMaterials.FACTION_CAMO = ["Camo_NATO",
"Camo_EMR", "Camo_Type21"]`. `InfantryLoadout.default_for(unit_id, faction)` returns the
family when the table has one and the resource exists, else the old A/B pattern. The three
places that fill an empty `UnitState.loadout` (`SoldierBody._use_infantry_character`,
`SoldierBody._set_viewmodel`, `UnitProxy.bind`) pass the unit's faction. From then on the
record is the truth: promotion, possession, the far proxy and save/load read `UnitState.loadout`
exactly as before. Reinforcements go through `WarSim.spawn_squad → WorldState.add_unit` with an
empty loadout and pick up the family the same way. Nothing in `WarSim`, `CombatSim`,
`CombatBrain`, diplomacy or objectives reads the table.

### Structures, roads, terrain, navigation

* Placement validation, groundwork pads, grass clearing, collision bodies, navmesh carving and
  the abstract blocking grid all read `StructureDef.get_collision_boxes()` and
  `blocks_navigation`; the library defs plug in with one addition — `walkable` for the three
  modules that intentionally have no collision (low-crawl wire, tyre run, parking pad; also used
  for the camouflage net, signs and delineators). Before, an empty `collision_boxes` meant "one
  box of `size`", which would have made a 0.2 m parking pad a solid block.
* The boom barrier's arm (0.9 m up, 6 m long) is not a collision box: soldiers duck under it,
  vehicles will stop at its `VEH_Stop` marker later.
* Roads: `RoadNetwork` is unchanged and authoritative. The road-kit surface meshes are not
  placed (painted roads would get a floating duplicate). Guardrails and delineators are props.
* Navigation after construction is the WORLD-BASE-01 / PLAYTEST-01 path: `area_changed` →
  debounced navmesh rebake for bodies, `_rebuild_block_grid()` for the abstract tier.

### Remaining architectural risks

* Old saves keep "A_standard" / "B_heavy" loadouts (valid; now drawn in the faction's
  camouflage through `FACTION_CAMO`). No migration.
* Large buildings use their LOD0 mesh in the MultiMesh at every distance (like the WORLD-BASE-01
  set). Sandbag walls / fighting positions are 3.6–6.3 k triangles at LOD0; measured cost in
  §4.7, no change needed yet.
* `StructureCatalog` loads the defs at first use (one-off ~0.3 s for 59 resources with their
  GLBs on demand); fine for now, worth a preload if the catalog grows much.
* The strategic map does not draw player-built structures or roads (it never did).

## 3. Gameplay

### What the player can do now

* Play the three-faction war on the corrected 20 km world; order squads anywhere, long moves
  follow roads and bridges; build roads and yards.
* See NATO, Russian and Chinese infantry fighting for North, South and East; possess any North
  soldier and fight with the HK416-class carbine and its optic.
* Build a military base from the library: 11 buildings, 15 training installations, 11
  logistics installations, 18 defensive types (lines and positions), 14 infrastructure props,
  5 road / yard types — freely placed (no grid, no road or adjacency requirement, no tiers),
  graded into uneven ground, grass and trees cleared, collision and navigation updated, saved
  with F5 / loaded with F9.

### Construction catalog (B, categories fold / unfold)

| Category | Types |
|---|---|
| Buildings (11) | Headquarters, Barracks, Supply Depot, Vehicle Depot, Medical Station, Communications Station, Training Facility; WORLD-BASE-01 field set: Command post (ISO shelter), Barracks module (CHU), Supply storage (K-span), Vehicle shelter |
| Training (15) | Shooting range: firing point, target line, backstop, control tower; shoot house (CQB); MOUT walls (door, window); obstacle course: balance logs, low crawl, monkey bars, cargo net, tyre run, climbing wall; vehicle ramp 30 %; vehicle parking pad |
| Logistics (11) | Ammunition storage bunker, container storage area, fuel bladder in bund, vehicle fuel point, repair bay; containers 20 ft / 40 ft; fuel tank 10 000 l; supply / ammunition / drum pallets |
| Defences (18) | Guard Tower (steel), Bunker / Fighting Position, fighting position (sandbags), MG nest, guard checkpoint; WORLD-BASE-01: guard tower (timber), HESCO (two sizes), chain-link fence, fence gate, concrete barrier; new lines: T-wall, sandbag wall (two heights), water-filled barrier, temporary mesh fence; boom barrier, guard booth |
| Infrastructure (14) | Communications tower 24 m, telescopic radio mast, generator 60 kW, light pole, mobile light tower, frame tents 6 x 4.5 and 10 x 6, camouflage net canopy, field toilet, checkpoint / restricted-area / stop signs, guardrail (line), delineator post |
| Roads (5) | Dirt track, gravel road, asphalt road (curves); gravel yard, asphalt yard (polygons) |

Lines (T-wall, sandbag walls, water barriers, mesh fence, guardrail) use the existing
drag-to-build line tool with per-type slope behaviour (T-walls step, sandbags and guardrails
pitch, mesh fence shears). The existing HESCO / fence / gate / barrier placement is unchanged.

### Soldier faction mapping (provisional)

| Faction | Family | Loadout |
|---|---|---|
| North (player) | NATO | `NATO_rifleman` |
| South | Russian | `RU_rifleman` |
| East | Chinese | `CN_rifleman` |

### Facility types ready for gameplay

HQ, Barracks, Supply Depot and Vehicle Depot are distinct `StructureDef` ids with their
`IP_*` / `VEH_*` / `ATT_*` markers in the imported scenes (`fn_asset` metadata). They have no
mechanics yet — no production, recruitment, repair or logistics was faked. Expansions are
free-standing installations; the association module → base is a future field on
`StructureState` (owner / parent id), which the records already have room for (`faction`).

### Known unfinished mechanics

Vehicles do not drive; buildings do nothing; training, repair and supply are not simulated;
the boom barrier does not stop anything; bridges and culverts cannot be built by the player.

## 4. Validation

Change-impact testing only. New: `--integration03-test` (`scripts/debug/integration03_selftest.gd`,
extends the playtest / sandbox test chain; results in `benchmarks/raw/integration03_test.json`,
screenshots `docs/integration03/wi03_*.jpg`).

### 4.1 Catalog [VERIFIED]

74 types, six categories all populated, nine buildings and 24 modules present, every library
mesh loads (no placeholder boxes), the eight walkable types have no collision and keep a footprint.

### 4.2 Scenario A — faction infantry [VERIFIED]

* Sandbox garrisons at every HQ wear their faction's family: North 24 / 24 bodies NATO,
  South 32 / 32 RU, East 24 / 24 CN; all 40 records of each faction carry the family or are
  still unset (abstract, never represented yet).
* Three squads side by side: 18 / 18 bodies with every piece attached (`CharacterIntegrationCheck`),
  120 / 120 far proxies with a loadout mesh; walking at 4.5 m/s, 18 / 18 animate with their
  velocity; possession of a North soldier gives the `NATO_rifleman` viewmodel, ADS through the
  optic, shots fired; demotion 2.5 km away and promotion back: 18 / 18 return with the same kit.
* Screenshots: `wi03_01_nato_north_hq`, `02_ru_south_hq`, `03_cn_east_hq`,
  `04_three_families_rts_30m`, `05_three_families_walking`, `06_fps_nato_hip`,
  `06b_fps_nato_ads`, `06c_fps_nato_firing` [INSPECTED]: three distinct silhouettes (NATO
  packs and tan furniture, RU full-wrap armour and AK-12-class rifle, CN digital camouflage),
  no missing materials, weapons in both hands, optics aligned.

### 4.3 Scenario B — base construction [VERIFIED]

Site search (open, dry, no world road under the perimeter, no boulders, a road within 1.2 km)
found (-7423, -7734), 450 m from the North HQ. Built in one go through the real tool: HQ, two
Barracks, Supply Depot, Vehicle Depot, two steel guard towers, generator, two 20 ft containers,
10 x 6 tent, light tower, parking pad, fence gate, HESCO on three sides (open polyline),
chain-link on the fourth snapped to the gate posts, a T-wall behind the HQ, a sandbag
position, a 720 m² gravel yard (graded to 3.4 %), and a 203 m gravel road from the gate
to the world road *Lv nordvik* (10 % max grade, 0.23 m cut, junction step 0.03 m, 11 / 11
route-grid cells marked as road). 45 structure records.

* Groundwork: the terrain under the corners of HQ, barracks, depots and tower is within
  0.01 m of the pad. 495 navmesh obstacles, 691 collision shapes in 5 streamed cells; the HQ
  blocks the abstract grid, the gate opening and the parking pad do not; the pad has 0
  collision boxes.
* Screenshots `wi03_07_base_rts_overview`, `08_base_rts_hq_close`, `08b_base_rts_motorpool`,
  `09_base_road_to_network`, `10_map_base_area`, `15_construction_menu` [INSPECTED]: buildings
  sit on level pads with no floating or sunken edges, correct scale against soldiers and
  vehicles, materials and dirt vertex colours present, the road meets the world road with a
  painted junction.

Found and fixed on the way: the first site straddled a world road (the test's site search
ignored roads; placement near roads is correctly refused by the groundwork rule) and the
second had boulders under the gate and the yard (placement correctly refused; the search now
checks the whole perimeter). The road tool builds immediately when the last click lands on a
road — the test now detects that.

### 4.4 Scenario C — navigation through the base [VERIFIED]

| March | Tier | Arrived | Inside a blocking footprint | Longest stall |
|---|---|---|---|---|
| From outside, in through the gate | bodies (navmesh) | 8 / 8 | 0 of 12 144 samples | 0.5 s |
| Across the base past the HQ | bodies | 8 / 8 | 0 of 2 976 | 0.2 s |
| From the north, round the HESCO wall, in through the gate | abstract | 8 / 8 | 0 of 23 072 | 0.2 s |

**Defect found and fixed:** in the abstract tier (camera far away) a squad sliding at 45°
along the HESCO wall crept into the wall's footprint a few centimetres per tick — the 1 m
look-ahead test passed while the unit's own next position did not — and the "already inside a
footprint: let it walk out" rule then let it walk straight through (first run: 1 326 of 24 952
samples inside walls, 5 %). `WorldSim._free_direction` now tests the next step as well and
backs a unit out of a footprint instead of through it. After the fix: 0 samples.

### 4.5 Scenario D — long-distance operations

`long_route` = the WORLD-PLAYTEST-01 river crossing (`nav_river`) run in this build: an RTS
Move order across the river from the North HQ area, bodies (camera close) and abstract
(camera far) **[VERIFIED]**:

| Tier | Bridge used | Route waypoints / skips | Arrived | Wading / water cells / impassable samples | Longest stall |
|---|---|---|---|---|---|
| bodies | 2 936 m away | 59 / 0 | 6 / 6 | 0 / 0 / 0 of 34 884 | 0.2 s |
| abstract | 2 126 m away | 46 / 0 | 6 / 6 | 0 / 0 / 0 of 6 078 | 0.2 s |

The corrected route planner, road preference and bridge decks work unchanged in the merged
build with the new soldiers (the abstract squad ran at 14.8 x compressed time).

### 4.6 Vehicle prototypes [VERIFIED]

Instantiated on the base yard from `assets/military/vehicles/*.glb`:

| | Size in Godot (W x H x D) | vs asset metadata | Markers | LOD ranges | Lowest point vs ground |
|---|---|---|---|---|---|
| Truck 6x6 | 3.31 x 3.64 x 8.67 m | 0 / +0.04 / 0 m | WHEEL 6, SUSP 6, DOOR 2, SEAT 3, CARGO 2, TOW 1 | 0–40 / 40–160 / 160–1500 m | -0.04 m |
| APC 8x8 | 3.27 x 4.84 x 7.99 m | 0 / +0.04 / 0 m | WHEEL 8, SUSP 8, DOOR 3, SEAT 11, WEAPON 1, TOW 1 | 0–40 / 40–160 / 160–1500 m | -0.04 m |

`fn_asset` metadata present (import script ran), library materials bound (Paint_Green,
Kit_Palette, Canvas_OD, Signs). Screenshots `wi03_13_vehicles_on_yard`, `13b_vehicles_close`
[INSPECTED]: right scale next to the depot, fence and soldiers, resting on the gravel.

Asset changes needed before a functional vehicle: none for a first drivable prototype —
the wheels are part of the body mesh, so the separate `wheel_truck` / `wheel_apc` assets must
replace them at the `WHEEL_*` markers (radius / width in the sidecars) and the body mesh's
own wheels should be dropped in the next Blender export. Interiors are absent (doors / seats
are markers).

### 4.7 Scenario E — view transitions [VERIFIED]

The sandbox `map_rts_fps` sequence in this build (an attack operation watched on the strategic
map, "View" jump to the squad, possession of one of its soldiers, firing, Tab back, map
again): possessed with the operation kept, 2 player shots, back on the map, 144 units and 18
squads before and after, 0 duplicate shot counters, record consistency 0 problems. Jump cost:
one 39.5 ms frame on the map → RTS jump, then 2.5 ms average. Across the whole sequence
**no soldier changed loadout or faction** (120 soldiers compared; 24 reinforcements arrived
meanwhile). Camera jumps base → East HQ → base afterwards: 144 / 144 units, consistency 0.
Screenshots `wi03_08_rts_active_operation`, `09_fps_same_operation`,
`12_rts_structures_and_soldiers`, `14_fps_in_base` [INSPECTED].

### 4.8 Scenario F — save / load of the combined state [VERIFIED]

F5 with the base built and the war running, then the live state wrecked on purpose (all 45
structure records cleared, every soldier's loadout blanked), F9:

* Construction: 45 / 45 records back, 0 differences in type, position (0.1 m), yaw, points,
  removed modules and instance count; the manager rebuilt 1 046 instances, 691 collision
  shapes, 2 surfaces (the road and the yard with their grading).
* Soldiers: every loadout and faction back (part of the same signature).
* War (the sandbox `persist` check with the AI running): 4 active operations at the save, 54
  of 209 signature keys changed before the load, **0 differences after it**, the war continues,
  record consistency 0 problems.

### 4.9 Scenario G — representative performance [VERIFIED]

1600 x 900, Forward+, RTX 3070 / i7-12700F, vsync off, the war running (282 soldiers in the
world, 24 bodies near the camera unless stated). "dc" = draw calls, "prims" = primitives per
frame. Measured in `--integration03-test --only perf` after the base of §4.3 was built.

| Situation | avg / p99 / max (ms) | dc | prims | Comparable baseline (avg / p99 / max) |
|---|---|---|---|---|
| RTS over the new base, 120 m | 2.33 / 4.2 / 11.4 | 535 | 1.32 M | — (new; RTS at HQ INTEGRATION-02: 1.99 / 3.9 / 7.2) |
| RTS over the new base, 45 m | 3.15 / 4.8 / 11.4 | 530 | 1.81 M | — |
| First person inside the base | 4.07 / 6.3 / 12.4 | 1 278 | 2.16 M | — (asset-lab sample base alone: 1.1–1.4 ms, 216–609 dc) |
| Strategic map (base in the world) | 1.88 / 3.5 / 10.3 | 204 | 8 k | map overview INTEGRATION-02 / 01B: 1.8 / 2.21 |
| RTS at the North HQ | 2.41 / 6.1 / 11.9 | | | INTEGRATION-02: 1.99 / 3.9 / 7.2 |
| War far away, 0 bodies | 2.44 / 4.0 / 11.0 | | | INTEGRATION-02: 2.44 / 5.0 / 7.4 |
| War far away at 8 x (8.0 x reached) | 3.60 / 10.6 / 13.5 | | | WORLD-PLAYTEST-01: 8.0 x reached; INTEGRATION-02: 22.1, 2.9 x |
| 50 v 50 battle, RTS (80 bodies, three families) | 6.54 / 14.6 / 77.7 (one frame over 33 ms) | | | INTEGRATION-02: 9.65 / 19.2 / 21.6 |
| 50 v 50 battle, first person (40 bodies) | 7.75 / 14.7 / 16.7 | | | INTEGRATION-02: 7.18 / 13.6 / 40.4 |

* Static memory 1.98–2.0 GB, video memory 1.78 GB with the base, the war and the vegetation
  loaded (the asset library's 25 MB of textures and 51 materials are a small part of it).
* No regression against the INTEGRATION-02 numbers for the same scenarios; the 50 v 50 RTS
  case is faster (the WORLD-PLAYTEST-01 blocking grid and distance LOD settings carry over),
  with one 78 ms frame during the battle (a navmesh re-centre or a promotion burst, not seen in
  the FPS case). The new base costs about 1.5–2 ms in first person at 1 278 draw calls, which
  is the LOD0 meshes of 45 structures plus 24 soldiers; the asset-lab figure for a base alone
  (1.1–1.4 ms) is not the same workload and is not compared directly.
* Construction and demolition: grading and painting the 203 m road and levelling the base
  pads ran inside the construction scenario without a frame over 33 ms in the RTS measurements
  that followed (the manager's deferred work is budgeted per frame, WORLD-BASE-01).

### 4.10 Regression of the shared systems changed [VERIFIED]

Change-impact runs only (no full suite; the integration scenarios above already covered the
cross-system paths):

| Changed | Test | Result |
|---|---|---|
| `WorldSim._free_direction` (abstract sliding) | `--playtest-test --only nav_base` (HESCO wall with a gap, bodies and abstract) | PASS: 6 / 6 round the wall in both tiers, 0 impassable samples |
| `WorldSim._free_direction` | `--sandbox-test --only navigation` (13.5 km operation march across the map, abstract) | PASS: completed, river crossed at a bridge, 0 water / impassable samples of 21 392, 127 waypoints, 0 skips |
| `StructureCatalog` / `StructureDef` | `--playtest-test --only roads` (built roads and yards, save / load, removal) | PASS: 15 / 15 grid cells, snapped asphalt road, yard, river road refused, ground restored |
| `StructureCatalog` / `StructureDef` | `--base-test` (WORLD-BASE-01 construction set on its own layout) | PASS |
| Loadout defaults, `FACTION_CAMO` | `--sandbox-test --only characters` | PASS: 8 / 8 bodies animate at 4.4–4.5 m/s, possession with viewmodel and 2 shots, 8 / 8 same kit after demotion / promotion, 0 loadouts lost through save / load |

Total test time this milestone: about 45 minutes of Godot runs, no run longer than 12 minutes.
The internal plan written before the changes is `docs/integration03/INTEGRATION_PLAN.md`.

## 5. Known limitations

* Strategic map does not show player-built structures or roads.
* Buildings have no interiors; doors are visual; the Run clip limitation of CHARACTER-01 stands.
* No bridge / culvert construction; the road-kit surface meshes and bridge prototype are not used.
* Old saves keep their legacy loadouts.
* Vehicles are static props in the world (test only), not units.
* The construction menu lists 74 types; names and grouping were chosen for a first pass and
  can be tuned.

## 6. Next milestone readiness

| Foundation | State |
|---|---|
| Drivable vehicles | GLBs validated in the world with wheel / suspension markers; `UnitState` kind VEHICLE and `VehicleBody` exist from WORLD-CORE; roads are in `RoadNetwork` with widths and grades per class |
| Infantry transport | `SEAT_*` / `DOOR_*` markers on both vehicles; squads and orders exist |
| Convoys | `StrategicRoutes` prefers roads (built roads included), column formation on the march |
| Physical supply logistics | Supply Depot / Vehicle Depot / fuel point / container yard are placeable with `VEH_*` dock and `IP_*` dispenser markers |
| Functional facilities | HQ / Barracks / Supply / Vehicle Depot distinct ids, markers, `faction` on every record |
| Modular expansions | free-standing installations; parent / owner association is a record field away |

## 7. Running

```bash
Godot_v4.7.2-stable_win64.exe --path . --resolution 1600x900 --log-file wi03.log res://scenes/game/world_ref_20km.tscn -- --integration03-test --shots [--only catalog,factions,base,base_nav,long_route,views,persist,vehicles,perf]
python tools/asset_production/make_prop_defs.py     # regenerate the prop StructureDefs
```
