# BASE-01 — Player base construction, first playable version

Branch `feature/base-01` (from `develop` @ `551039c`). The player opens construction mode in the RTS view, places a
**Command Post** anywhere suitable, which establishes a base of their faction with a 150 m area, and builds
**Barracks**, **Supply Depot**, **Vehicle Parking** and **Guard Post** inside it. Everything happens in the normal game
scene (`world_ref_20km`, the three-faction war), is physical (collision, navmesh, vehicle blocking), shows in FPS, RTS
and on the strategic map, and is saved with F5 / F9.

## 1. What already existed and was reused

The mapping found most of the machinery in place; BASE-01 adds the base rules on top of it, no parallel system.

| Need | Existing system (reused as is) |
|---|---|
| Build mode, preview, rotation, valid / invalid with reason, LMB build, RMB / Esc cancel | `ConstructionController` (WORLD-BASE-01), B in RTS |
| Terrain fit, slope / water / overlap / tree checks | `StructureManager.check_building` |
| Collision, navmesh carving, vehicle blocking | `StructureManager` cells + `nav_obstacles` + `blocks_point` (read by `VehicleRouter` / `VehicleSim` / `WorldSim`) |
| Vegetation under the footprint | `clearings_for` (cleared trees saved with the construction file) |
| Bases and facilities | `ConstructionState.bases`, `StructureState.base_id`, `FacilityDefs`, `BaseSim` (LOGISTICS-01) |
| Stores, start stockpile | `Inventory`, `LogisticsSim` (first player supply depot receives `START_STOCK`) |
| Save / load | `ConstructionState.to_dict / from_dict` (F5 / F9, `user://saves/ref_20km/construction.json`) |
| 2D map | `StrategicMap._draw_logistics_layer` (base ring, facility letters) |
| Models | `command_post` (WORLD-BASE-01 set), `barracks_block`, `supply_depot`, `vehicle_parking_pad`, `guard_tower_steel` (ASSET-PRODUCTION-01 library) — no new Blender models were needed |

What was missing: a command post did not establish anything (it was not a facility); bases were proximity groups
whose anchor drifted with their facilities, without an area; no rule tied buildings to a base; no road / bridge check;
no base menu; no view of a base area; no capacity / parking / guard properties.

**Terrain:** the brief asks not to change Terrain3D heights. The existing groundwork (WORLD-INTEGRATION-01, a project
rule in CLAUDE.md: "building must work on uneven terrain") levels the ground under a building *in memory only*,
up to 2.5 m cut / fill; terrain files are never written and removing a building restores the ground. BASE-01 keeps
it (the world manifest verifies unchanged). Steeper ground (> 20°) is refused. `StructureManager.level_ground = false`
switches the groundwork off if the product owner wants plain "flat or refused" placement.

## 2. How build mode works

- **B** in the RTS view opens construction mode (the camera keeps panning, rotating, zooming). The panel (top right)
  starts with **BASE**: Command Post / Barracks / Supply Depot / Vehicle Parking / Guard Post, each with its function
  ("establishes a base", "+32 soldier capacity", "base stores", "6 vehicle bays", "defensive position") and a status line.
  Until the player has a base only the Command Post can be chosen. The full catalog stays below as "All structures"
  (folded).
- Choosing a building shows a transparent preview at the cursor: green = can build, red = cannot; the HUD gives the
  reason. **R / Shift+R / Ctrl+wheel** rotate in 15° steps, **LMB** builds, **RMB / Esc** cancel.
- While the mode is open, the player's base areas are drawn as dashed rings on the ground (brighter for the base the
  cursor is in); with the Command Post selected, a green / red ring shows the area it would open.
- Reasons the player sees (examples from the test): `no base: place a command post first`, `too steep (40° > 20°)`,
  `too close to a road (Rv1 vest-sørøst)`, `outside the base area`, `blocked by command post`,
  `too close to North base 1 (one command post per base)`, plus the existing `water`, `blocked by <tree / building>`,
  `too uneven to level ...`.

Rules (`BaseSim.placement_rule`, `StructureManager.road_conflict`, applied by `ConstructionController` for the player):

| Building | Rule |
|---|---|
| Command Post | not inside / next to one of the faction's bases (anchor distance < its area + 75 m); not inside or within 150 m of another faction's base area; not inside an objective held by another faction |
| Other base facilities | inside one of the faction's base areas |
| All base facilities | footprint 1.5 m clear of every road surface (world and built roads), not on / next to a bridge deck |
| Walls, fences, roads, props | unchanged (free, as before) |

## 3. The buildings

| Menu entry | Type (model) | Facility data (`FacilityDefs`) |
|---|---|---|
| Command Post | `command_post` (20 ft shelter, antenna) | kind `hq`, `founds` a base, area 150 m, 8 beds, 2 000 store |
| Barracks | `barracks_block` (24 x 7 m, 32 beds) | kind `barracks` (recruiting as before), 32 beds |
| Supply Depot | `supply_depot` (warehouse with loading dock) | kind `supply`, 60 000 store; the first one gets the starting stockpile |
| Vehicle Parking | `vehicle_parking_pad` (24 x 14 m, six bays) | kind `parking`, 6 slots at the asset's bay markers (`FacilityDefs.parking_spot`) |
| Guard Post | `guard_tower_steel` (steel watchtower) | kind `guard`; positions via `BaseSim.guard_posts` |

`BaseSim` adds `capacity(bid)` (beds), `parking_spots / free_parking_spot`, `guard_posts`, and its `summary` carries
radius, capacity, parking and guard-post counts. The map shows the facilities as H, B, S, P and G.

Asset fix: the parking pad's `sink` was 0.15 m for a slab whose top is 0.08 m above its origin, so the groundwork buried
it (only the cleared grass showed). Now 0.04 (`.tres`, `.json` and the pipeline source `fam_modules.py`; geometry
unchanged, no re-export needed).

## 4. How bases are registered

`ConstructionState.bases[id] = {id, name, faction, anchor, radius, founder}`. Placing a Command Post
(`FacilityDefs.founds_base`) where the faction has no base makes `BaseSim._on_added` create one: unique id, the
player's faction (`WarState.player_faction`), anchor = the command post, radius 150 m, founder = the command post's
structure id; the war log says "North base 1 established (area 150 m)". Facilities placed later join the base whose
area contains them (`StructureState.base_id`). An established base's anchor never moves (proximity groups of
LOGISTICS-01, radius 0, still follow their facilities). Removing the command post keeps the base and its area while
other facilities remain (`founder` = -1); removing the last facility removes the base.

For WarSim / operations: owner (`faction`), position (`anchor`, `radius`), facilities (`BaseSim.facilities_of`,
`summary`), soldiers and vehicles near it (`summary.soldiers / vehicles`) are all read from this one record. Several
bases per faction are supported by the data (`bases_of`); BASE-01 only demonstrates one.

## 5. Save / load

No new save format: the base and its buildings are part of `ConstructionState.to_dict` (format 3; `radius` and
`founder` are new optional keys, older files load with 0 / -1). F5 writes `construction.json` and `world.json`, F9
loads both. Saved per base: id, faction, anchor, area, founder; per building: type, position, yaw, faction, base id,
inventory, facility state. The test compares the player's structures and bases before save and after clear + load:
identical.

## 6. Targeted tests

New scenario `--base01-test [--shots] [--only collision,infantry,vehicle,persist,far,views]` in the normal game scene
(`scripts/debug/base01_selftest.gd`), through the real input (B, panel, cursor, R, LMB). The base is always built; `--only`
picks the later checks (vehicle-only run: 25 s; everything with screenshots: 81 s, a third of it the squad's 400 m walk at 4x time). Last full run:
**PASS** (`benchmarks/raw/base01_test.json`).

| # | Check | Result |
|---|---|---|
| 1 | Menu: only Command Post available without a base | yes |
| 2 | Refused: barracks without base / steep (40°) / on Rv1 | `no base ...` / `too steep` / `too close to a road` |
| 3 | Command Post rotated 45° (R x3) establishes "North base 1" (faction North, r 150 m, founder = CP) | yes |
| 4 | Barracks (rotated 90°), depot, parking, two guard posts inside the area; outside / overlap / second CP refused | all placed, all three refused |
| 5 | Facility data: 40 beds, 6 bays, 2 guard posts, depot got 4000 / 6000 / 9000 starting stock | yes |
| 6 | Collision: ray hits and blocking footprint for CP, barracks, depot, guard post; parking pad walkable | yes |
| 7 | Infantry: nearest squad (406 m away) ordered to a point behind the barracks: arrives (98 s sim), route and soldiers never inside a building, squad stays put 80 s afterwards | yes |
| 8 | Vehicle: truck in bay 1, next free bay differs; vehicle route to the far side of the barracks (128 m) has no point in a building | yes |
| 9 | Save -> clear -> load: player's base identical | yes |
| 10 | 6 km away and back: nothing drawn far away, 6 instances and collision back | yes |
| 11 | FPS (a soldier 30 m from the command post) and strategic map show the base | yes |

Regression (change-impact: shared `BaseSim` / `FacilityDefs` / `ConstructionState`, the parking pad and guard tower
used by older scenarios, AI start bases):

- `--integration03-test --only base,persist`: PASS.
- `--ai-war-test --only a_init`: PASS (AI start bases unchanged).
- `--logistics-test --only bases,persist_logistics`: 4 failed checks (`a facility has no owner or base`, `recruiting
  without supplies was allowed` (reserves run out first), `repair` (damage not applied), `persist` (fuel 199.5 ->
  199.49)). **The same four fail on `develop` without BASE-01** (baseline run with develop's files), so they are
  older and not caused by this milestone; left for a logistics follow-up.
- `python tools/terrain_ref/world_manifest.py verify --ignore-editor-metadata`: OK (535 files, 0 changed).

Older scenarios build facilities freely, without a command post; `LargeWorldSelfTest` switches the new player rules off
for them (`ConstructionController.base_rules = false`); `Base01SelfTest` switches them on.

**Observation:** in the first two runs the squad ended against the barracks' west wall ("stuck: no progress after an
unstick attempt") instead of walking round it. In those runs the test watched the squad for 180 s because its arrival
check was too strict. After the arrival check was fixed and route / navmesh diagnostics were added, six runs in a row
(with and without screenshots, plus 80 s of watching after arrival) showed the squad going round the building and
staying put. The navmesh paths had no point inside a building, and neither did the squad route. Not reproduced, so the
cause is unknown. It may be timing: an asynchronous navmesh re-centre while the squad comes in. Worth watching in play.

## 7. Screenshots (`docs/base_01/`)

| File | Shows |
|---|---|
| `base01_menu.jpg` | Build mode, base menu without a base (only Command Post enabled) |
| `base01_preview_command_post.jpg` | Command Post preview (green), its area ring |
| `base01_preview_invalid_road.jpg` / `base01_preview_invalid_outside.jpg` | Red previews with reason (road / outside the base area) |
| `base01_base_rts.jpg` / `base01_base_rts_areas.jpg` | The finished base from the RTS camera, without / with build mode (area ring) |
| `base01_base_units.jpg` | Ground level: the squad in front of the barracks |
| `base01_parking.jpg` | Vehicle parking with a truck in bay 1 |
| `base01_base_ground_fps.jpg` | First person next to the base |
| `base01_map.jpg` | Strategic map: base area and facilities H B S P G |

## 8. Known limitations

- The base area is a fixed circle (150 m); no expansion, no territory.
- Construction is free and instant for the player (the AI's cost / build-time table `AiBases.BUILD_COST` is not
  switched on for the player).
- Capacity (beds) is a property shown to the player; recruiting does not check it yet.
- Guard posts and parking bays are data (`guard_posts`, `free_parking_spot`): no automatic manning or parking order yet;
  vehicles are simply driven near the depot / pad as before.
- The enemy AI does not target the player's base: player bases are no `ObjectiveState`, so nothing captures them yet
  (`BaseSim.capture_base` exists).
- Groundwork levels the terrain in memory (see 1).
- The panel uses the existing construction-panel style (dark, thin border); the HUD's developer lines (units, detail)
  are still shown in RTS.
- A short `--only` run once crashed the engine on exit (0xC0000005) after its PASS line had been written. The other
  runs exited normally. This looks like the known shutdown issue with pending terrain / navmesh work, not BASE-01 code.

## 9. Branch and commits

Branch `feature/base-01` from `develop` (`551039c`), not merged, not pushed:

- `3cfb0b5` feat(base): BASE-01 player base construction
- report, README and screenshots (this commit)
