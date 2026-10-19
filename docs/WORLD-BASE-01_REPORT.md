# WORLD-BASE-01 — Freeform Military Base Construction

**Branch:** `feature/world-base-01` (from `feature/world-core-02`, not merged into `main`)
**Engine:** Godot 4.7.2, Forward+, Vulkan, Terrain3D 1.0.2, Jolt. Blender 5.2.2 LTS (MCP). **Machine:** i7-12700F, RTX 3070, 16 GB, 1600 × 900, VSync off.
Status tags: **[VERIFIED]** executed in Godot by `scripts/debug/base_selftest.gd` on the real 20 × 20 km world; **[INSPECTED]** looked at in renders/screenshots; **[NOT VERIFIED]** not tested.

## 1. Summary

The RTS view has a construction mode (**B**). Anywhere suitable in the 20 km world the player can place four building types, a guard tower and a fence gate, and draw HESCO walls (two sizes), chain-link fences and concrete barriers as straight lines or multi-point perimeters. Lines are built from fixed-size modules and are never stretched. They snap to compatible structures and follow the terrain without deforming. Blocked sections are shown red and left out, and single modules can be deleted.

Structures are plain records in `WorldState.construction`. They are drawn as MultiMesh instances by 128 m cell, get collision only near the observer, cut into the navmesh and clear the grass. They persist across 7.6 km trips and save to JSON (F5/F9).

The ten assets were built with Blender Python scripts from real-world references and rendered from several angles. They were then imported into Godot and corrected there over several rounds; the details are in section 5.

The scripted run on the 20 km world passes **[VERIFIED]** (`benchmarks/wb01/base_test.json`, 0 failures). The WORLD-CORE-02 20 km test also still passes (`benchmarks/wb01/wc02_regression.log`).

## 2. What was implemented

| File | Role |
|---|---|
| `scripts/construction/structure_def.gd` | `StructureDef` (Resource): size, collision boxes, stair ramps, layout (SPAN / CENTERED), terrain fit (LEVEL / STEP / PITCH / SHEAR), slope and ground-gap limits, snap group and points, nav blocking |
| `scripts/construction/structure_catalog.gd` | The 10 types with real dimensions; loads GLB meshes (with import LODs), sets material modes (alpha blend for wire mesh, scissor for camo net, double-sided sheets, vertex-colour dirt) |
| `scripts/construction/structure_state.gd`, `construction_state.gd` | Records (`StructureState`: id, type, position/yaw or line points + removed module indices) and registry with signals, JSON save/load. Part of `WorldState` (`world.construction`, included in `snapshot()/restore()`) |
| `scripts/construction/modular_line.gd` | **One reusable modular layout for every linear type**: whole-module segment snapping, angle snapping, SPAN and CENTERED layouts, even spacing on snapped ends (≤ 15 % deviation) |
| `scripts/construction/structure_manager.gd` | Terrain fitting, placement checks, 128 m cell index, MultiMesh rendering near the camera, collision cells near the observer, ray picking, snap points, nav obstacles, grass clearing |
| `scripts/construction/construction_controller.gd` | Construction mode input, previews (green/red ghost, per-module colours, corner markers, snap ring), place/draw/delete, F5/F9 |
| `scripts/ui/construction_panel.gd` | Categorised menu built from the catalog (tooltips with descriptions) |
| `scripts/core/detail_manager.gd`, `scripts/world/area_navigation.gd` | Structures carve the navmesh; structure changes trigger a debounced **async** rebake of the same area (terrain faces cached) |
| `scripts/rts/rts_camera.gd` | `zoom_min = 15`, `zoom_max = 300` (exported); the 3000 m override in `world_core_02.tscn` removed |
| `scripts/game/core_demo.gd`, `scripts/ui/game_hud.gd`, `scenes/game/*.tscn` | Wiring (both the 20 km and the 2 km scene), HUD lines |
| `tools/blender/fn_structures_lib.py`, `tools/blender/structures/*.py` | Procedural tileable textures (numpy), world-scale box UVs, ground-dirt vertex colours, preview renders |
| `tools/preview_structures.gd` | Renders the **imported** assets in Godot (sun, sky, ground) from four angles |
| `scripts/debug/base_selftest.gd`, `benchmarks/wb01/run_base_test.sh` | Scripted 20 km checks (about 3 min) |

### Design points
- **Records, not nodes.** Structures exist only as `StructureState` records. Instance transforms are derived from them once and cached on the record (not saved). A distant base costs 14 records and a few hundred transforms: no nodes, no collision, no draw calls **[VERIFIED: 0 visible cells, 0 collision cells at 7.8 km]**.
- **Rendering:** one `MultiMeshInstance3D` per (128 m cell, type) within 1.8 km of the camera, `visibility_range_end` per type. The finished test base is 364 instances in 16 MultiMeshes.
- **Collision:** one `StaticBody3D` per cell within 260 m of the observer (possessed soldier or RTS focus, as in DetailManager). Box shapes come from the defs. Fences are sheared visually but get an orthonormal box. The guard tower stairs are a walkable convex wedge.
- **Navigation:** ground-touching boxes of blocking types become projected obstructions with a 0.3 m margin (without it, the 0.75 m navmesh raster let paths clip HESCO corners and a soldier got stuck). Gates and stairs stay walkable; roofs are ignored. Changes rebake the current area 0.4 s after the last edit, on a worker thread. The old navmesh stays in use until the new one is ready.
- **Grass:** footprints plus 1 m are painted into the in-memory grass exclusion mask, and closed perimeters clear their whole interior. Removing a structure restores the original texels. Nothing is written to `worlds/*/vegetation/mask.res`.
- **No framework:** about 2.1 k lines of GDScript in `scripts/construction/` and the panel. There is no streaming system; only per-cell node toggling.

## 3. Controls (RTS)

| Key / mouse | Action |
|---|---|
| **B** | Enter / leave construction mode (unit selection and orders pause, camera keeps working) |
| Panel (top right) | Choose a type (Buildings / Defences), Delete, Save, Load, Close |
| Buildings: move mouse | Transparent preview, green = can build, red + HUD reason (too steep, uneven ground, blocked by …, tree, soldier/vehicle in the way, outside the map, water) |
| **R** / **Shift+R** / **Ctrl+wheel** | Rotate 15° |
| **LMB** | Build (the tool stays active for the next one) |
| Lines: **LMB** | First click = start, every further click = a corner (multi-point perimeter) |
| **Enter**, **RMB**, double-click | Finish the line (the dangling segment to the cursor is dropped) |
| Click on the line's start | Closes the perimeter and finishes |
| **Backspace** | Remove the last corner |
| **Shift** (held) | Direction snaps to 15° steps relative to the previous segment |
| **Ctrl** (held) | No snapping to other structures |
| **X** / Delete | Delete tool: hover highlights red, click removes a building or **one line module**, Shift+click removes the whole line |
| **Esc** | Cancel line → clear tool → leave construction mode |
| **F5 / F9** | Save / load construction (`user://saves/<world>/construction.json`); also works outside construction mode |
| Gate | Moving it near a fence end snaps a post onto it and aligns it with the fence; fences snap their start/end onto gate posts |

Command line: `--load-construction` loads the save at start.

## 4. Construction data

```json
{"format": 1, "next_id": 19, "structures": [
  {"id": 1, "type": "command_post", "faction": 0, "position": [-5514.647, 39.297, 5741.352], "yaw": 0.0},
  {"id": 2, "type": "barracks", "faction": 0, "position": [-5530.647, 39.507, 5759.352], "yaw": 1.5708},
  {"id": 10, "type": "hesco", "faction": 0, "points": [[x, y, z], ...5 corners], "removed": [164, 165, 166, 167, 168]}]}
```
Stable ids, type, faction, position/yaw (buildings) or corner points plus removed module indices (lines). The test base is 2.6 KB. Module transforms are recomputed from the terrain on load: the largest difference after save → clear → load was 0.7 mm **[VERIFIED]**.

Validation and fitting rules:
- **Buildings** sample the terrain on a ≤ 2 m grid over their footprint (from the collision boxes, so off-centre stairs count). They fit a plane for the slope, limit the height range (`max_ground_gap`), and sit at the highest point. Every model has a foundation skirt (block piers, jacks, concrete pad, legs) that reaches below the ground by more than the allowed gap, so there is never a visible gap underneath.
- **Line modules** are checked one by one: HESCO cells **step** (level, set to the local mean height, buried skirt), concrete barriers **pitch** with the slope, and fence panels are **sheared** so posts stay vertical. Each module is checked for slope, cross-slope gap, outside map, water and overlap. Overlap covers other structures (same connection group may touch), tree trunks from the vegetation chunks, and soldiers and vehicles from their records.
- Odd modules are 0.4 % taller and thicker, so faces that touch at corners never z-fight. Fence end posts are 2 % thinner than start posts for the same reason.
- No map currently has water bodies. `water_level` exists (default off), and terrain holes or areas outside the terrain are rejected.

## 5. Assets — references, Blender iterations, Godot corrections

Process for every asset: reference photos → Python script (`tools/blender/structures/`) → Blender EEVEE renders (perspective, back, low/close and orthographic top, `assets/structures/previews/*.jpg`) → look and fix → GLB export → Godot import → Godot renders (`godot_*_{front,back,close,top}.jpg` via `tools/preview_structures.gd`) → in-game FPS/RTS screenshots → fix in Blender and re-export. Editable `.blend` files are in `assets/structures/blender/` and generated textures in `assets/structures/textures/`.

| Asset | Size (m) | Tris | Key reference features modelled |
|---|---|---|---|
| `command_post` | 6.06 × 2.44 shelter + 2.05 m extension | 3 864 | Expandable 20 ft ISO shelter: corrugated olive walls, ISO corner castings, levelling jacks, folding extension with seal, 2 ECU A/C units, steps, telescopic mast with whips, dish and guy wires, garnished camo net on poles, cable reel, power box |
| `barracks` | 6.06 × 2.44 × 2.59 (CHU) | 3 800 | Tan accommodation container on block piers, door with canopy and lamp, barred windows, split A/C on bracket, pipe cover, electrical box and cable, roof vent, steps |
| `supply_storage` | 10 × 14 × 5.2 (K-span) | 5 444 | Half-elliptic corrugated arch with seams every 0.6 m as geometry, concrete pad and curbs, corrugated end walls, roll-up door with slats and drum, personnel door, sign, pallets with crates |
| `vehicle_shelter` | 8.2 × 12.2 × 5.5 | 1 208 | Steel frame every 2.44 m, olive fabric walls and gable roof, open front with rolled-up door, seams, tie-downs and stakes, bench and tool chest inside |
| `guard_tower` | 3.4 × 3.4, deck 4 m, roof 6.6 m | 5 162 | Timber legs on footings, two levels of X-bracing, joists and plywood deck, 1.1 m plywood parapet with two sandbag courses, roof posts, corrugated sloped roof, searchlight, 42° stairs with handrails (walkable) |
| `hesco` / `hesco_tall` | 1.06 cell × 1.37 / 2.13 × 2.21 (MIL1/MIL7-type) | 424 each | Welded 76 mm mesh (alpha), tan geotextile liner with slight pillowing, sand fill below the rim, coil hinges at corners, top rim wire |
| `fence` | 3.0 × 2.4 panel | 1 334 | Galvanized posts, top rail, tension wire, 50 mm chain-link (alpha), Y-arm outriggers with 3 barbed strands per side and a concertina coil |
| `fence_gate` | 4.2 m opening | 716 | Terminal posts with Y-arms, two welded tube leaves with chain-link infill, diagonal brace, hinges, drop rod; leaves open (the gate is passable) |
| `concrete_barrier` | 3.0 × 0.61 × 0.81 | 236 | F-shape/Jersey profile (toe, 55° and 84° faces), forklift slots (boolean), connection loops, lifting eyes |

All assets have LODs generated on import (`meshes/generate_lods=true`), box collision from `StructureCatalog`, dirt baked into vertex colours toward the ground, and tileable textures of 512–1024 px (painted steel with fading and rain streaks, corrugation normal maps, concrete, fabric weave, timber grain, sandbag, weld mesh, chain-link, camo net).

### Iteration log (what looked wrong and what changed)
1. **HESCO v1** (Blender): corner coils too thick and bright → thinner and darker; ground dirt (vertex colour) added; previews now render with a ground plane.
2. **HESCO in Godot**: liner too dark and blotchy, previews lit from behind → lighter liner, previews lit from the front. Thin wires **disappeared at distance** (alpha scissor loses sub-pixel wires in the mipmaps) → wire mesh and chain-link switched to alpha blending, so they fade to a grey haze like real mesh. The grid is also printed faintly into the liner so it still reads at 100+ m.
3. **HESCO in game** looked grey and desaturated (blended wire layer over the tan) → warmer liner, lighter grid print, darker wire colour.
4. **Buildings v1**: procedural paint looked like camouflage or rust blotches; corrugation normals invisible → paint rewritten (broad fading, vertical rain streaks, soft dirt patches, chips); normal maps with a real slope; texture tiles enlarged from about 1 m to 2–3 m to hide repetition (container ribs kept at 0.28 m pitch).
5. **K-span**: double ribbing (geometry seams plus a normal map projected across the curve) → arch uses geometry only; end walls tan corrugated instead of galvanized.
6. **Command post v1** was a plain olive box → added the camo net. **v2 net cut through the walls** (user feedback "den ser ikke riktig ut") → net rebuilt as a canopy that is never lower than the roof over the footprint and drops to poles outside, with spreader poles; shorter mast. **v3** net was opaque and busy and hid the shelter → more open garnish (about half holes), muted colours, larger patches.
7. **Vehicle shelter in game** rendered black from the front and inside (single-sided fabric) → fabric, end walls, camo net, liner and mesh are double-sided; lighter fabric.
8. **Concertina** too sparse (9 loops per 3 m) → 17 loops; less shiny wire.
9. In-game: **grass grew through floors and hid the HESCO walls** in first person → grass clearing (section 2).

### Reference sources (viewed in the browser, not copied or stored)
- HESCO: [Commons search "hesco barrier"](https://commons.wikimedia.org/w/index.php?search=hesco+barrier&title=Special:MediaSearch&type=image), especially [591st Engineer Company places concertina wire on HESCO](https://commons.wikimedia.org/wiki/File:591st_Engineer_Company_places_Concertina_Wire_on_top_of_HESCO_barriers_at_NDA_2.png); [Bing "HESCO barrier wall close up FOB"](https://www.bing.com/images/search?q=HESCO+barrier+wall+close+up+FOB); [marines.mil FOB Robinson](https://www.marines.mil/Photos/igphoto/253311); dimensions: [MSF catalogue MIL10](https://unicat.msf.org/cat/product/71108), [Task & Purpose (MIL1/MIL7)](https://taskandpurpose.com/news/how-much-sand-to-fill-hesco-tower/)
- CHU / barracks: [Wikipedia: Containerized housing unit](https://en.wikipedia.org/wiki/Containerized_housing_unit), [DMG Global CHU dimensions](https://dmgglobal.com/temporary-housing-solutions/), [Commons: USAG Wiesbaden CHUs](https://commons.wikimedia.org/wiki/File:USAG_Wiesbaden_containerized_housing_units_provide_Soldier_billeting_solutions_(7612935).jpg), [Commons: Risalah CHU yard](https://commons.wikimedia.org/wiki/File:Cyclone_Company_pushes_Neighborhood_Advisory_Councils_to_forefront_of_day-to-day_operations_in_Risalah_DVIDS125729.jpg), [Bing "containerized housing unit CHU military camp"](https://www.bing.com/images/search?q=containerized+housing+unit+CHU+military+camp)
- Command post: [RUAG command post containers](https://www.ruag.ch/en/our-competences/land-systems/containersysteme/command-control-container-systems), [Airbus mobile command post flyer](https://www.defence-solutions.airbus.com/sites/g/files/jlcbta231/files/2025-03/mobile_command_post_flyer.pdf), [Losberger De Boer TOC](https://www.losbergerdeboer.com/uk/solutions/rapid-deployment-space/command-post-tactical-operations-centres/), [Bing "military expandable container command post shelter antenna"](https://www.bing.com/images/search?q=military+expandable+container+command+post+shelter+antenna)
- Guard tower: [Commons: Seabees NMCB 1 guard tower](https://commons.wikimedia.org/wiki/File:US_Navy_070625-N-7367K-003_Seabees_attached_to_Naval_Mobile_Construction_Battalion_(NMCB)_1,_construct_a_guard_tower_that_will_overlook_the_battalion%27s_forward_operating_base_(FOB).jpg), [Commons: FOB Mizan guard tower](https://commons.wikimedia.org/wiki/File:Flickr_-_The_U.S._Army_-_Manning_the_guard_tower_at_Forward_Operating_Base_Mizan.jpg), [Bing "FOB guard tower wooden sandbags Afghanistan"](https://www.bing.com/images/search?q=FOB+guard+tower+wooden+sandbags+Afghanistan), [2nd MLG Camp Dwyer tower](https://www.2ndmlg.marines.mil/Media-Room/Photos/igphoto/2000709056/)
- Vehicle shelter: [Bing "army vehicle maintenance tent shelter"](https://www.bing.com/images/search?q=army+vehicle+maintenance+tent+shelter) (NIXUS, HTS TENTIQ, Weatherhaven), [Big Top maintenance shelters](https://bigtopusa.com/maintenance-shelters), [Edwards AFB clamshell shelter](https://www.edwards.af.mil/News/Photos/igphoto/2003511965/)
- Supply storage: [Bing "K-span building military FOB supply storage"](https://www.bing.com/images/search?q=K-span+building+military+FOB+supply+storage)
- Fence and gate: [Bing "military base perimeter chain link fence gate concertina"](https://www.bing.com/images/search?q=military+base+perimeter+chain+link+fence+gate+concertina)
- Concrete barrier: [Wikipedia: Jersey barrier](https://en.wikipedia.org/wiki/Jersey_barrier), [Wikipedia: Bremer wall](https://en.wikipedia.org/wiki/Bremer_wall), [Bing "concrete jersey barrier military checkpoint"](https://www.bing.com/images/search?q=concrete+jersey+barrier+military+checkpoint)

## 6. Validation (real 20 km world, real input actions, about 3 min) **[VERIFIED]**

Base site found automatically 260 m from site A (flattest 100 m square with few trees).

| Check | Result |
|---|---|
| RTS zoom limits (wheel) | stops at exactly 15.0 m and 300.0 m; both exported properties |
| Construction mode | B: panel visible, unit selection inactive |
| Buildings on flat ground | command post, 3 barracks, supply storage, 2 guard towers, vehicle shelter built by cursor + click |
| Rotation | R × 6 → barracks yaw 90.0° |
| Overlap | second command post on the first refused ("blocked by command post") |
| Moderate slope | command post built on 3.2° ground 120 m away |
| Steep slope | 14.5° spot refused: "too steep (15° > 7°)" |
| Cancel | Esc clears the tool, nothing built |
| Delete | X + click on a barracks removes it (hover highlight found it) |
| HESCO perimeter | 4 corners + click on the start: closed loop, 264 cells, 279.9 m; joints 1 mm, corner cells face to face (0.5 mm) |
| Single module removal | 5 cells in the south wall removed one by one; the line still exists |
| Multi-point concrete chicane | 5 modules on 3 points, exact joints |
| Fence → gate → fence | gate snapped onto the fence end (0.000 m), the second fence snapped onto the far gate post (0.000 m) |
| Long straight line | 150 m fence = 50 exact 3 m modules |
| Blocked sections | HESCO line through the command post: 7 of 51 modules red in the preview, left out when built, 44 built |
| Navmesh | 375 structure obstructions; path from inside to outside goes through the gap (31.4 m vs 27.0 m straight), never through a wall |
| Soldier around the wall | ordered from inside to outside: arrived in 6.7 s, 1.3 m off target, 0 frames inside a HESCO cell |
| FPS collision | ray hits the HESCO wall, barracks roof and tower stairs; the possessed soldier walking into the wall for 3 s stops 0.89 m from its centre line |
| Travel 7.8 km and back (keys 2, 1) | away: 0 visible cells, 0 collision cells, 14 records; back: records and all 364 transforms identical, everything redrawn |
| Save / clear / load (F5, F9) | 2.6 KB JSON; cleared to 0; restored records identical, transforms within 0.7 mm; navmesh carving restored |
| WORLD-CORE-02 regression | `LARGE PASS []` |

## 7. Performance

| Item | Result |
|---|---|
| FPS inside the base | 1.48 ms avg, p99 2.13 ms, 399 draw calls |
| RTS over the base at 150 / 300 m | 1.87 / 1.88 ms avg, p99 2.51 / 2.60 ms; 391 / 305 draw calls |
| Base cost | 14 structures, 364 instances in 16 MultiMeshes, 392 collision shapes in 4 cells |
| One placement, camera at rest | worst frame 29 ms: cell rebuild 27 ms, grass mask 5 ms, navmesh 4 ms on the main thread + about 100 ms on a worker |
| Line preview while drawing (51 modules) | about 9 ms per frame while the cursor moves (was 62 ms before the distance reject and result caching); 0 when it rests |
| Distant base | records only (no nodes) |

`physics_ms` from Godot's monitor reads 40–55 ms in these runs, which cannot be true at 1.5–2.6 ms frame times. WORLD-CORE-02 saw the same; not investigated.

## 8. Screenshots (`docs/screenshots/base01_*.jpg`)

RTS: `rts_base_overview`, `rts_base_close`, `rts_vehicle_yard`, `rts_base_after_reload`, `hesco_corner_rts`. Construction: `preview_line_blocked` (live HESCO preview, blocked part red, menu), `preview_invalid_steep` (red building ghost), `delete_highlight`. First person: `fps_inside_base`, `fps_gate_opening`, `fps_hesco_corner_closeup`, `fps_fence_gate`, `fps_guard_tower`, `fps_vehicle_shelter`, `fps_supply_storage`. Asset renders: `assets/structures/previews/` (Blender `*_persp/back/top`, Godot `godot_*`).

## 9. Limitations

- **Not played by a human**: everything was checked by script and by looking at screenshots. Placement feel (rotation step, snap radius = 2.5 % of zoom) still needs a playtest.
- Grass clearing works on the 5 m mask texels of the 20 km world, so cleared strips are 5–7 m wide (looks like a cleared perimeter) and edges are soft.
- The scene's sun is in the south, so fronts that face north (the vehicle shelter's open side) are in shade.
- Only blocking checks for trees; trees and rocks are not removed under or around structures. Boulders next to a base are not cleared either.
- Abstract-tier (bodiless) soldiers still walk straight lines through structures, the same limitation as for trees in WORLD-CORE-02.
- No water bodies exist on the maps, so the water check (`water_level`) is unexercised.
- Gates are always open; there are no doors or interiors (buildings are solid boxes; the vehicle shelter and tower deck are enterable).
- Moving the camera far enough to re-centre the detail area still does WORLD-CORE-02's synchronous bake plus collision rebuild (about 0.2–0.6 s), as before.
- A closed perimeter clears grass with a per-texel polygon test; a very large loop (km-scale) would take a few hundred ms once.
- No undo for placement (deletion is the undo); no faction ownership rules yet (faction field stored, always 0).
- Godot extracts the GLB-embedded textures next to each GLB (`assets/structures/<asset>_*.png`), duplicating shared textures per asset (8.6 MB in total).

## 10. Next steps

1. Playtest the controls; consider hotkeys for types and a snap-to-grid toggle for buildings.
2. Remove or hide trees, rocks and bushes under footprints (vegetation override per cell) instead of only refusing placement.
3. A gravel or compound ground decal for cleared areas; finer grass mask near bases.
4. Doors and interiors for the CHU and command post; a closed variant of the gate.
5. Faction ownership, resources and builders (out of scope here).

## 11. Running

```bash
benchmarks/wb01/run_base_test.sh --shots      # 20 km construction checks + screenshots (~3 min)
Godot_v4.7.2-stable_win64.exe --path . --resolution 1400x900 --script res://tools/preview_structures.gd   # Godot asset renders
```
In Blender (MCP or the Python console): `exec(open(r"<repo>/tools/blender/structures/make_buildings.py").read())` (also `make_hesco.py`, `make_fence_barriers.py`; globals `ONLY=[...]`, `EXPORT`, `PREVIEW_DIR`). Blender writes PNG previews; the committed ones were converted to JPG.
