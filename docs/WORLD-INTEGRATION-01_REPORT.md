# WORLD-INTEGRATION-01 — construction and FPS/RTS on the reference world

Branch `feature/world-integration-01` (worktree `fractured-nations-integration01`) joins
`feature/world-terrain-01` (the 20 × 20 km reference world `ref_20km`) and
`feature/world-base-01` (freeform base construction). `ref_20km` is now the main scene.
Nothing was merged into `main`, and the other worktrees were not touched.

Everything below was measured in the actual Godot 4.7.2 game (Vulkan, RTX 3070, 1600×900)
by scripted runs. **Nobody has play-tested this build by hand yet.** Section 11 lists what
a person should check.

## Summary

- **Construction works on the reference world.** Buildings, HESCO, fences, gates,
  corners, snapping, closed perimeters and validation were tested in five automatically
  found terrain types: open meadow, forest clearing, gentle slope, next to a road, and
  inside a village. All three test suites pass on `ref_20km`: the new integration test,
  the WORLD-BASE-01 test and the WORLD-CORE-02 test.
- **Building on uneven ground (groundwork, added after user feedback).** Buildings now
  level the terrain under them into a pad that blends into the surroundings:
  - the limits are up to 20° average slope and 2.5 m cut/fill;
  - the WB-01 rules (5–7°, 0.5–0.9 m) refused most of this rolling map;
  - collision, navmesh and nearby lines follow the new ground;
  - removing the building restores the ground.
- **Vegetation clearing.** Placement cuts trees, shrubs and debris inside the new
  footprint (C toggles it; on by default). The clearing persists through streaming and
  save/load, and is filtered out of rendering, colliders and navigation.
- **Navigation.**
  - Abstract soldiers no longer walk through walls.
  - Gate posts are carved into the navmesh.
  - The navmesh margin was widened after a soldier got stuck on a corner.
  - The navmesh re-centre after camera moves is now asynchronous.
- **Water.** Buildings and lines are refused in the river and lakes; that check did
  nothing before.
- **Performance is unchanged where it was already measured:** the WT-01 station bench
  is within noise of its baseline. Placement and removal hitches match WB-01. Long jumps
  still cost ~0.4 s, now mostly Terrain3D's collision rebuild (section 8).

## 1. Git strategy and conflicts

| Step | What |
|---|---|
| Base | New worktree `../fractured-nations-integration01`, branch `feature/world-integration-01` from `feature/world-base-01` (a541eee). Common ancestor with the terrain branch: ba5a952 (WORLD-CORE-02). |
| Merge | `git merge feature/world-terrain-01` → merge commit 9b98597. |
| Textual conflicts | **`.gitignore`**: both sides added blocks (base: `__pycache__/`; terrain: `/worlds/ref_*/*`, generated ref scenes, logs, full-res mosaics). Kept both. **`README.md`**: merged automatically; the run section was later rewritten for the new main scene. |
| Semantic conflict 1 | `scenes/game/world_ref_20km.tscn` (terrain branch) was a copy of the *old* `world_core_02.tscn`, without the `Structures` / `Construction` nodes and with a 3000 m zoom limit. Regenerated from the base branch's `world_core_02.tscn`; only the world path and root name differ. This keeps the 15–300 m RTS zoom. |
| Semantic conflict 2 | The reference world scene had a node named `Structures` (bridges, culverts), the same name as the game's `StructureManager` node. Renamed to `RoadStructures` in `ReferenceWorldBuilder` and `probe_perf.gd`; this takes effect when the world is built. |
| Not merged | `main`, `feature/character-01` and the original worktree (`fractured-nations`, which has uncommitted `project.godot` and untracked docs) were not touched. |

## 2. Changes

| File | Change |
|---|---|
| `project.godot` | `run/main_scene = res://scenes/game/world_ref_20km.tscn` |
| `scenes/game/world_ref_20km.tscn` | Regenerated (see section 1) |
| `scripts/vegetation/vegetation_streamer.gd` | `set_clearings()`: oriented rectangles per 128 m cell. Activation and `get_cell_instances` skip the cleared instances. Chunk files are never changed. Signal `clearings_changed` |
| `scripts/world/instance_collider_streamer.gd` | Drops its index when clearings change, so tree colliders disappear with the trees |
| `scripts/construction/construction_state.gd` | `clearings` records, saved in the construction JSON (format 2; format-1 files still load). Fixed an aliasing bug where `to_dict()` returned the live array, so `clear()` emptied snapshots |
| `scripts/construction/structure_manager.gd` | Vegetation clearing (clearable ids; rocks and settlement buildings always block); water index from the world's `Water` meshes; `blocks_point()` for the abstract tier; gate posts carved into the navmesh; `nav_margin` 0.3 → 0.5 m; groundwork (section 4). Fixed `_trees_in` caching empty cells when called before the first placement check |
| `scripts/construction/construction_controller.gd` | C toggles clearing; HUD shows clearing state and groundwork depth; placements record their clearings |
| `scripts/core/world_sim.gd` | Abstract step tests the next step against structure footprints: straight, else slide 45°/90° along the wall, else stop (BLOCKED) |
| `scripts/core/detail_manager.gd` | Re-centring the navmesh area after camera or observer drift bakes on a worker thread. New bodies wait until the area is ready; possession stays synchronous. Collision timing recorded |
| `scripts/world/area_navigation.gd` | Bake serial (an older async result never replaces a newer bake); `terrain_changed()` patches the cached terrain faces in place after groundwork |
| `scripts/game/core_demo.gd` | Wires water, abstract blocking and terrain edits → navigation; `--integration-test` |
| `scripts/debug/integration_selftest.gd` | New: the WORLD-INTEGRATION-01 checks (section 6) |
| `scripts/debug/base_selftest.gd` | Site search skips water and the map edge; the "steep is refused" check looks above the new 20° limit |
| `benchmarks/wi01/run_test.sh` | Runs the integration, base or large test on `ref_20km`; stops its own process on a parse error and never kills other Godot instances |
| `README.md` | Main scene, build-first instructions, C key, test commands |

No Blender assets were regenerated or changed; the existing WB-01 and WT-01 assets are
used as they are. No shaders, textures, forest, grass, shrub, settlement or terrain
generation changes.

## 3. Main scene, startup and world generation

**Main scene:** `scenes/game/world_ref_20km.tscn` (F5 in the editor). You start in first
person as a North soldier at site A (Nordvest-moen). Keys 1 / 2 / 3 jump between the three
sites, Tab switches to RTS, B opens construction.

**Fresh checkout.** The world data (~2.4 GB) is generated and git-ignored. Build it once:

```bash
git clone <repo> && cd fractured-nations && git checkout feature/world-integration-01
bash tools/terrain_ref/build_ref_world.sh
```

- **Godot:** `Godot_v4.7.2-stable_win64(_console).exe` next to the repository folder.
- **Blender:** 5.x installed at the default path; the generator uses Blender's bundled
  Python with numpy and OpenImageIO.
- **Validation:** I ran exactly this command in the new worktree with no prior world data.
  It finished in **806 s (13.4 min)** with exit code 0 and created:
  - `worlds/ref_20km/{source,terrain,vegetation,water}`;
  - `scenes/world/ref_20km.tscn`;
  - 114 road containers and 4,500 RoadPoints;
  - 5 bridges and 404 culvert ends.
- **Side effect:** the build re-saves the committed `assets/environment/scenes/*.tscn`. The
  only difference is Godot's new random `unique_id` values (no content change). I
  reverted them; `git checkout -- assets/environment/scenes` does the same after a build.

## 4. Base building on the new terrain

### Five environments, found by measuring the map

`IntegrationSelfTest` measures the map around site A. Nothing is predefined; it uses
heights, slopes, vegetation, roads from `roads.json`, settlements from `sites.json` and
water.

| Environment | Spot | Ground | Built | Result |
|---|---|---|---|---|
| Open meadow | (-1107, -7885) | 0.1°, 0.5 m over 40 m, no trees within 60 m | HESCO perimeter 90×70 m (302 cells) with a 6-cell entrance; command post, 3 barracks, supply storage, vehicle shelter, 2 towers, concrete chicane | all placed, joints ≤ 1.5 mm |
| Forest clearing | (-7241, -8080) | 1.3°, 42 trees within 30 m | Clearing off: barracks on a pine **refused** ("blocked by a tree (pine a; C turns clearing on)"). Clearing on: command post, barracks (on the pine), tower, 30×30 m fence with a snapped gate and a closing fence | 42 clearings, 0 trunks left in footprints, 17 → 5 clearable plants in the base square (the rest of the square keeps its trees) |
| Gentle slope | (-7218, -7114) | 5.9°, 5.7 m over 40 m | Barracks, 50 m HESCO L, 21 m fence | HESCO 0.07–0.09 m into the ground, worst module gap 0.08 m |
| Near a road | (-8444, -7209) | 20 m from the road, 57 trees within 30 m | Barracks, 48 m fence | built, trees in the footprint cleared |
| Inside a settlement | Nordvik (-5020, -8635) | 140 m inside the village radius, 2 houses within 60 m | Barracks, 48 m fence | built; houses keep blocking placement (never cleared) |
| Water | river at (-1892, -9368) | terrain 3.2 m below the surface | barracks | refused: "water" |

### Groundwork (building on uneven ground)

After the first runs the user pointed out: *"Men det må gå an å bygge på terreng som
ikke er flatt også."* The WB-01 limits (command post / barracks 7° and 0.7 m, storage 5°
and 0.9 m) refused most of this map's rolling, hummocky ground. The WB-01 test's own site
next to site A was refused for its corner towers ("uneven ground 1.0–1.5 m") and vehicle
shelter ("too steep 10°").

**How it works.**
- **Pad height.** A building's pad height is halfway between the lowest and highest ground
  under its footprint, so cut and fill are equal.
- **Placement limits:**
  - average slope ≤ 20° (`level_max_slope_deg`);
  - cut/fill ≤ 2.5 m (`level_max_depth`);
  - cut/fill ≤ 0.3 m where the 4 m blend zone touches a road, because road meshes follow
    the original terrain.
- **Terrain edit.** The terrain inside the footprint is set to the pad height. Within 4 m
  around it, a smoothstep blend returns to the original ground. Neighbouring pads mix
  with weights⁴, so they hardly pull on each other's edges.
- **Collision.** Terrain3D only rebuilds collision for the whole 200 m radius (~0.4 s). So
  only the 3–4 heightfield shapes under the pad are re-read from the edited heights,
  through `PhysicsServer3D`. A read-back on untouched ground reproduces Terrain3D's own
  shapes exactly (0.000 m difference), which confirms the layout.
- **Navigation.** The cached navmesh terrain faces are patched in place. The patched
  faces match freshly generated ones exactly (0.000 m).
- **Lines** (fences, HESCO) in the blend zone are re-fitted to the new ground.
- **Vegetation.** Trees in the blend zone block placement when clearing is off and are
  cut when it is on. Undergrowth there is always removed so nothing floats.
- **Persistence.** Pads are derived from the building records (position, yaw, type), so
  saving needs no extra data. Terrain files are never written. Removing a building
  restores the original heights from an in-memory copy.

**Measured** on a 10.8° slope that the old rule refused (1.3 m uneven > 0.7 m):

| Check | Result |
|---|---|
| Barracks placed with groundwork | yes, 0.65 m cut/fill |
| Terrain under the footprint vs pad height | 0.021 m |
| Collision in the blend zone vs terrain (8 rays) | 0.03 m |
| Fence through the blend zone after re-fit | 0.00 m gap |
| Navmesh face patch vs fresh Terrain3D faces | 0.000 m |
| Removal restores the ground | 0.000 m |
| Save → clear → load | ground restored to 0.000 m (0.56 m difference while cleared) |
| Cost | 3–7 ms for ~36 vertices and 4 shapes |

With groundwork, the WORLD-BASE-01 test passes **at its original site next to site A**
(3 m height range over 100 m), including both corner towers and the vehicle shelter.
Steep ground is still refused, e.g. "too steep (40° > 20°)".

### Construction features (WB-01 test on `ref_20km`, PASS)

- **Zoom limits:** 15 / 300 m reached with the mouse wheel.
- **Basic tools:** construction mode on B, rotation with R, overlap refusal, Esc cancel,
  X delete.
- **HESCO perimeter:** 280 m closed by clicking the start, joint error 1 mm, corner gap
  0.5 mm.
- **Line editing:** five single cells removed to make a gate gap; the concrete chicane;
  blocked sections shown and left out.
- **Fences:** fence → gate → fence snapping (0.000 m); 150 m fence = 50 exact modules.
- **Navigation:** 374 structure obstructions carved; a soldier walks around the wall
  through the gap, never inside the HESCO.
- **FPS collision:** HESCO ray, barracks roof and tower stairs all hit. Walking into the
  wall stops 0.89 m from its centre line.
- **Persistence:** an 11.9 km trip and back leaves records and transforms identical;
  save/load is identical (0.7 mm).

## 5. Vegetation and construction

- **What blocks placement.** Tree trunks (pine, spruce, birch), boulders, outcrops and the
  settlement houses, barns and sheds all have colliders in the Nordic library.
  - Before this work, all of them reported "blocked by a tree".
  - Now the message names the object.
  - Only plants and small debris (ids 1–8, 11, 13–15) can be cleared. Rocks and settlement
    buildings always block, so settlements are never demolished.
- **Clearing scope.** Only the footprint of the structure being placed, plus 1 m (4 m for
  buildings, the groundwork zone), is cleared. Entering construction mode clears nothing,
  and there is no area or forestry tool.
- **How it is stored.** Clearing records are game state in `WorldState.construction`
  (`clearings`, saved in JSON). The vegetation chunk files are not modified.
- **What applies the filter.** The streamer filters rendering, `get_cell_instances` (tree
  colliders, navmesh tree obstructions, placement checks) and re-activates only the
  affected cells.
- **Grass** inside footprints still uses WB-01's in-memory mask paint, so no grass grows
  through floors.
- **Persistence was measured:**
  - after a 22.9 km trip, the forest chunk was unloaded and streamed back;
  - drawn vegetation instances in the base cells were 416 before and 416 after;
  - trunks inside footprints were 0 before and 0 after;
  - save → clear → load took the base square from 5 to 17 (trees back) to 5.
- **Appearance:** forest floor, grass, shrubs and their shaders are unchanged. The WT-01
  station bench and vegetation test give the same numbers as their baseline (section 8).

## 6. Navigation and persistence

| Check | Result |
|---|---|
| Soldier from inside the forest base out through the fence gate (straight 35 m) | arrives in 9.5 s, path 44.3 m through the gate, 0 frames inside a fence |
| Soldier out of the open HESCO base (straight 36.7 m) | arrives in 11.5 s, path 53.2 m through the entrance, 0 frames inside the wall |
| FPS soldier walks into HESCO | stops 0.88 m from the wall centre line |
| Abstract soldier ordered straight through the north wall (camera 12 km away) | never inside the wall; held at it and sliding along it after 25 s |
| Abstract soldier ordered through the entrance | passes and arrives |
| 22.9 km trip and back | structure records and transforms identical; nodes released while away, rebuilt on return |
| Save (F5) / clear / load (F9) | 60 KB JSON, 459 clearings, records identical, transforms within 1.1 mm, clearings and groundwork restored |

**Bugs found and fixed** (all reproduced first):

- **Soldier stuck on a command post corner** after the navmesh area re-centred. The 0.75 m
  navmesh raster plus a 0.3 m obstacle margin left about 0.3 m worst-case clearance,
  less than the 0.35 m soldier capsule. The margin is now 0.5 m.
- **Gate posts were not carved into the navmesh.** Gates are `blocks_navigation = false`,
  so paths could run into the solid posts. Their collision boxes, which are only the
  posts, are now carved, and the 4 m opening stays walkable.
- **Abstract soldiers walked straight through structures.** They now check structure
  footprints through a cell lookup and slide along walls. This is not a path search, so
  an abstract unit does not find a gate by itself. When it comes near the camera it gets
  a body and a real navmesh path.

## 7. Visual checks

| Check | Result | Screenshot |
|---|---|---|
| Buildings on uneven ground | On a pad, no floating corners or buried sides; the blend zone looks like ground preparation | `wi01_groundwork_slope_rts.jpg` |
| Grass/shrubs through floors | None (footprint grass mask + cleared undergrowth) | `wi01_fps_inside_open_base.jpg`, `wi01_forest_clearing_base_rts.jpg` |
| HESCO and fences follow terrain | HESCO 0.07–0.09 m into the ground on 5.9°, fence ends ≤ 0.1 m | `wi01_env_slope_rts.jpg`, `wi01_fps_hesco_corner.jpg` |
| Gate alignment | Gate post on the fence end at 0.000 m, closing fence snapped to the far post | `wi01_forest_gate_rts.jpg` |
| Blending with environment | Uses WB-01 assets unchanged; chain-link reads well against the forest; the HESCO colour is lighter than the farmland it stands on in the open base (not changed: asset redesign is out of scope) | `wi01_open_base_rts.jpg`, `wi01_rts_same_base.jpg` |
| Bridge and road alignment | Not changed by this task. The WT-01 bridge and road shots and their measurements still apply, because the world build is identical apart from the node rename. Construction cannot touch a road's ground by more than 0.3 m | `docs/terrain01/` |

Required screenshots (`docs/integration01/`):

| Required | File |
|---|---|
| Small base in a forest clearing | `wi01_forest_clearing_base_rts.jpg`, `wi01_forest_gate_rts.jpg` |
| Larger base on open terrain | `wi01_open_base_rts.jpg` |
| HESCO and fences on uneven terrain | `wi01_env_slope_rts.jpg`, `wi01_groundwork_slope_rts.jpg`, `wi01_fps_hesco_corner.jpg` |
| FPS inside a base | `wi01_fps_inside_open_base.jpg`, `wi01_fps_base_entrance.jpg` |
| RTS view of the same base | `wi01_rts_same_base.jpg` (and `wi01_open_base_rts.jpg`) |
| Soldier navigating around barriers | `wi01_soldier_around_hesco.jpg`, `wi01_soldier_around_barrier.jpg` |
| Also | `wi01_env_road_rts.jpg`, `wi01_env_settlement_rts.jpg`, `wi01_fps_dense_forest.jpg`, `wi01_forest_base_after_trip.jpg` |

## 8. Performance

All frame times are CPU frame time (ms), average / p99 / worst, at 1600×900 with vsync off.
Raw data is in `benchmarks/wi01/`.

**Same method as WT-01** (`benchmarks/terrain01/run_terrain01.sh`, world scene without
the game):

| Station | WT-01 baseline | WI-01 | |
|---|---|---|---|
| FPS centre | 9.6 / 10.1 | 9.8 / 12.2 | p99 slightly higher, single run |
| FPS far corner | 8.6 / 9.2 | 8.6 / 9.4 | = |
| RTS 150 m | 2.5 / 2.8 | 2.5 / 2.7 | = |
| RTS 600 m | 2.9 / 3.2 | 2.9 / 3.2 | = |
| Strategic | 3.5 / 4.4 | 3.4 / 3.9 | = |
| Camera jump, worst frame | 22.9 | 23.4 | = |
| FPS↔RTS switch, worst frame | 26.2 | 25.7 | = |
| VRAM / peak RAM | 1606 MB / 2.5 GB | 1606 MB / 2.47 GB | = |
| Vegetation test, FPS walk test | PASS | PASS | = |

**In the game** (integration test; WB-01 numbers were on `real_20km`):

| Measurement | WB-01 baseline | WI-01 on `ref_20km` |
|---|---|---|
| FPS in dense forest (71 trees within 30 m) | — | 9.42 / 10.08 / 10.39 |
| FPS inside a base | 1.48 / 2.13 | 1.97 / 2.39 / 2.57 (open base); 2.32 / 2.60 (WB-01 test base) |
| RTS 15 m / 150 m / 300 m (avg / p99) | – / 1.87 / 1.88 | 2.16 / 2.66, 1.90 / 2.22, 2.13 / 2.59 |
| Placement, worst frame | 29 ms | 31.9 ms (cells 21 ms, grass 4.3 ms, groundwork 7.4 ms; navmesh bake 141 ms on a worker) |
| Removal, worst frame | — | 25.3 ms |
| Groundwork alone | — | 3–7 ms |
| Soldier navigating around barriers | — | worst physics-frame wait 19–31 ms during the walks (body promotion, path query) |
| Vegetation streaming after construction | — | worst cell activation 3.6 ms after return (filtered cells) |
| WT-01 vegetation jump test | first frame 41.1 ms | 40.7 ms |

**Long jumps in the game.** These are still the slowest frames:

| Jump | Before | After |
|---|---|---|
| RTS 800 m camera jump | 818 ms | 409–417 ms |
| 22.9 km trip, each way | — | 399–413 ms |

The remaining frame splits as follows:
- **~400 ms Terrain3D collision rebuild** around the new area (`collision.update(true)`).
  This is the same cost as before, and is also part of WORLD-CORE-02's 620–660 ms
  possession jumps.
- **~120 ms navmesh source collection.** Terrain faces and 2,000–4,500 tree obstructions
  in a forest are gathered on the main thread.

The bake itself now runs on a worker. Making the collision rebuild incremental is not
possible through Terrain3D 1.0.2's API (it only has `update(rebuild)`). That would be the
next step (section 10).

Not every physics value in the tables is meaningful. `physics_ms` is a single-sample
engine monitor, and it occasionally shows 9–20 ms in one RTS row while that row's frame
p99 stays at 2.3–2.5 ms. It reflects the one sampled frame, not a sustained cost.

## 9. Test commands

```bash
bash tools/terrain_ref/build_ref_world.sh                # once, ~14 min
bash benchmarks/wi01/run_test.sh integration --shots     # ~8 min, docs/integration01/wi01_*.jpg
bash benchmarks/wi01/run_test.sh base                    # WORLD-BASE-01 checks on ref_20km, ~4 min
bash benchmarks/wi01/run_test.sh large                   # WORLD-CORE-02 checks on ref_20km, ~2 min
STEPS="bench vegtest fps" bash benchmarks/terrain01/run_terrain01.sh <out_dir>   # WT-01 method
```

The base and large tests are run without `--shots`, because their shot names would
overwrite the committed WB-01 / WC-02 screenshots.

Final results:
- WI01 PASS (0 failures);
- BASE PASS;
- LARGE PASS;
- WT-01 vegetation test PASS;
- FPS self-test unchanged.

## 10. Known limitations

- **Long jumps hitch about 0.4 s.** Most of it is Terrain3D's full collision rebuild; see
  section 8. Possible fix: a smaller collision radius in RTS, or time-sliced collision in
  a later Terrain3D version.
- **Abstract units do not path-find.** Far from the camera, they are stopped at walls and
  slide along them, but they do not look for a gate. A unit ordered into a closed base
  can circle the wall until it is near the camera, where it gets a real path. A proper
  fix needs a coarse path layer for the abstract tier, which is out of scope.
- **Groundwork limits.**
  - Up to 20° and 2.5 m cut/fill.
  - The pad is plain terrain: no foundation, retaining wall or dirt texture.
  - Its edges are terrain-textured, so a 2 m cut looks like a smooth bank.
  - Next to roads it only allows 0.3 m.
  - Vegetation outside the cleared zone is not adjusted to the new ground.
- **Clearing scope.** Clearing removes vegetation only inside footprints plus margin.
  Trees between buildings in a forest base stay. There is no area-clearing tool, by
  design.
- **Navmesh margin.** The 0.5 m margin makes paths keep a little more distance from
  walls. Gaps narrower than about 2.6 m between structures are no longer walkable for
  bodies.
- **Grass mask paint** for footprints is still WB-01's in-memory mask; it is rebuilt from
  the records after load.
- **HESCO colour** is lighter than the farmland in the open-base shot. It is unchanged,
  because asset redesign was out of scope.

## 11. Needs manual testing by the user

Nothing below has been verified by a person:

- Placing buildings by hand on slopes. Check how the groundwork looks up close from FPS,
  especially at 1.5–2.5 m cut/fill, and whether 20° / 2.5 m feel right.
- Walking in FPS over freshly levelled ground and blend banks. Collision was measured, but
  the feel was not.
- The C toggle and HUD text during normal play; whether clearing ON by default is what you
  want.
- Building a whole base in thick forest and on a hillside, then reloading with F9 in a new
  session (restart the game, B, F9).
- Ordering soldiers into and out of bases through gates from RTS, including groups.
- The ~0.4 s hitch on long jumps: is it acceptable for now?
- Possessing a soldier inside a levelled base right after loading a save.
