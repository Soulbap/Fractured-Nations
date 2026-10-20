# ASSET-PRODUCTION-01 — Military bases, faction infantry and modular environment assets

**Branch:** `feature/asset-production-01` (worktree `../fractured-nations-asset01`, based on `feature/unified-sandbox` @ 6418b12; not merged).
**Tools:** Blender 5.2.2 LTS (background, scripted), Godot 4.7.2 (Forward+, Vulkan). **Machine:** i7-12700F, RTX 3070, 1600 × 900.
Status tags: **[VERIFIED]** checked by a script in Godot; **[INSPECTED]** looked at in Blender renders / Godot screenshots; **[NOT VERIFIED]** not tested.

## 1. Summary

A reusable asset library, built entirely from Python scripts and validated in Godot:

| Family | Count | Where |
|---|---|---|
| Faction infantry (NATO, Russian, Chinese) | 19 new pieces, 3 loadouts, 4 new camo/colour materials + 2 polymers | `assets/characters/infantry/factions/`, `.../loadouts/{NATO,RU,CN}_rifleman.tres` |
| Main base buildings | 9 (all requested) | `assets/military/buildings/` |
| Base expansion modules | 24 | `assets/military/modules/` |
| Infrastructure and props | 51 | `assets/military/props/` |
| Road kit (surfaces + dressing) | 8 + 3 surface materials | `assets/military/roads/` |
| Vehicle prototypes (optional) | truck 6x6, APC 8x8 + 2 wheel assets | `assets/military/vehicles/` |

* All 96 static assets pass the Godot validator (LOD chain, ranges, shared materials, bounds/orientation, collision, markers, vertex colours) **[VERIFIED]**, `benchmarks/asset01/validate.json`, 0 errors.
* The three faction loadouts use the unchanged CHARACTER-01 skeleton (60 bones) and all 19 clips, with every piece attached, every material in the library, weapon mounts and the support grip at the standard positions **[VERIFIED]**, `benchmarks/asset01/factions.json`, 0 errors. The first-person sight line passes through all three new optics **[INSPECTED]**.
* A sample base of 203 instances renders at **1.0–1.4 ms** per frame in FPS and RTS views (216–609 draw calls), nine such bases at 0.8–1.1 ms **[VERIFIED]**, `benchmarks/asset01/showcase.json`.
* 120 animated faction soldiers cost the same as 120 CHARACTER-01 soldiers (12.3 vs 13.4 ms close, 9.9 vs 10.7 mid, 4.2 vs 4.1 RTS) **[VERIFIED]**, `benchmarks/asset01/charperf_120.json`.
* **Hip fix (user feedback during the milestone, "hoftene ser helt grusomme ut"):** the squeezed hips came from the shared CHARACTER-01 body: automatic weights let the thigh bones drive the waist (88 % at belt height), so the waist collapsed whenever the legs flexed. Fixed in the shared pipeline and re-exported; CHARACTER-01's own checks still pass (section 6).

## 2. Approach and pipeline

Everything is regenerated from scripts in background Blender (never the user's open scene) and inspected twice: Blender renders, then real Godot imports and screenshots.

| Part | Files |
|---|---|
| Static builder: geometry tagged per LOD level, collision boxes, markers, world-scale box UVs, ground-dirt vertex colours, LOD material merging, palette folding, GLB + JSON export, StructureDef data | `tools/blender/asset_production/ap_lib.py` |
| Architectural kit (wall frames, doors, windows, roller doors, AC units, roofs, steps, masts, dishes) | `ap_kit.py` |
| Shared material library (Blender preview materials and Godot `.tres` from one table, palette) | `ap_materials.py` |
| Tileable textures (numpy): paint, container ribs, roof sheet, galvanized, concrete, CMU, asphalt, gravel, dirt, canvas, wood, HESCO liner/mesh, chain-link, camo net, rubber | `ap_textures.py` |
| Sign atlas (road, military, hazard, range targets, plates, decals) rendered from shapes and text | `ap_signs.py` |
| Families | `fam_buildings.py`, `fam_modules.py`, `fam_props.py`, `fam_props_logistics.py`, `fam_roads.py`, `fam_vehicles.py` |
| Entry point | `build_assets.py` (`--family`, `--only`, `--export`, `--previews`, `--lods`, `--textures`) |
| Faction infantry on the CHARACTER-01 modules | `characters/build_factions.py`, `fac_textures.py`, `fac_gear.py`, `fac_weapons.py` |
| Godot import script: library materials by name, LOD visibility ranges, `fn_asset` metadata | `tools/asset_lab/ap_post_import.gd` |
| Asset lab: `--validate`, `--shots`, `--lod`, `--factions`, `--charperf N`, `--showcase` | `tools/asset_lab/asset_lab.gd`, `scenes/asset_lab/asset_lab.tscn`, `benchmarks/asset01/run_lab.sh` |

The full standard for new static assets is in **`docs/ASSET_STANDARD.md`** (axes, GLB contents, markers, LODs, materials, budgets, validation).

### Iteration log (what looked wrong and what changed)
1. **Pipeline:** first GLB exported no vertex colours (exporter `ACTIVE` mode) → named colour layer export. Sign atlas: hazard stripes bled into neighbour cells (z-order per canvas, no clipping) → global z and polygon clipping; range silhouettes looked like bottles → round head, short neck, sloped shoulders.
2. **Godot:** LOD1 and LOD2 never appeared between ranges because LOD0's end margin and LOD1's begin margin differed (a band where neither was visible) → one hysteresis margin per boundary.
3. **Draw calls:** buildings had 14–15 surfaces at LOD0 and 5–7 at LOD2 → small flat-coloured parts folded into one palette material, minor materials merged on LOD1/2: now 4–7 / 4–5. The palette first rendered white (Godot's emission operator ADDs the emission colour) → black emission colour + emission texture.
4. **Buildings:** dock canopy cut through the dock-door housings, HQ dish platform sank into the roof, dirt texture tiled visibly from the air → canopy raised, platform put on the roof slope, tile-scale contrast removed.
5. **Props:** HESCO "pillow" panels read as posters → removed; sandbags looked like hexagonal logs → cushion-shaped (flattened ellipsoid) bags.
6. **Modules / vehicles:** ammunition magazine mound had a stray back face and inverted normals → one loft with explicit orientation; APC nose was a broken polygon → sloped glacis loft.
7. **Faction infantry:** RU and CN rifles lost their mount nodes (Blender suffixed duplicate empty names `ATT_Optic.001`) → fresh exact-name empties per export; a texture crash went unnoticed because Blender exits 0 on Python exceptions → build scripts now exit 1; CN camouflage did not read as digital → 4.7 mm pixels, more contrast; CN helmet flare increased (PASGT-style skirt); RU armour too bulky at the bottom → slimmer shell, shorter.
8. **Hips (user feedback):** see section 6.

## 3. Asset inventory, dimensions and triangle counts

Size = above-ground bounding box (width X × depth Y × height Z in Blender axes, front = +Y). "Surfaces" = draw surfaces per LOD. Full per-asset data in the JSON sidecars and `assets/military/catalog.json`; StructureDef resources for all buildings and modules in `assets/military/defs/` (33).

#### Buildings (9)

| Asset | Name | Size above ground W x D x H (m) | Tris LOD0 / 1 / 2 | Surfaces LOD0 / 1 / 2 | Markers | Collision boxes |
|---|---|---|---|---|---|---|
| `barracks_block` | Barracks | 27.70 x 9.52 x 4.62 | 4384 / 1180 / 136 | 6 / 4 / 4 | 6 | 4 |
| `bunker_fighting` | Bunker / Fighting Position | 6.40 x 6.50 x 2.10 | 4764 / 212 / 144 | 5 / 5 / 5 | 4 | 1 |
| `comms_station` | Communications Station | 19.05 x 15.71 x 21.00 | 1954 / 506 / 118 | 6 / 5 / 4 | 3 | 3 |
| `guard_tower_steel` | Guard Tower | 4.95 x 4.94 x 8.80 | 2788 / 824 / 212 | 4 / 4 / 3 | 3 | 2 |
| `hq_building` | Headquarters | 17.23 x 14.36 x 11.20 | 4334 / 1056 / 156 | 7 / 7 / 5 | 7 | 3 |
| `medical_station` | Medical Station | 10.79 x 19.52 x 3.33 | 1652 / 282 / 142 | 7 / 6 / 5 | 5 | 3 |
| `supply_depot` | Supply Depot | 20.70 x 18.08 x 7.37 | 2948 / 1004 / 120 | 7 / 5 / 5 | 8 | 2 |
| `training_facility` | Training Facility | 21.05 x 9.47 x 4.29 | 1880 / 616 / 124 | 7 / 5 / 5 | 4 | 3 |
| `vehicle_depot` | Vehicle Depot | 30.30 x 22.42 x 9.47 | 3620 / 922 / 130 | 6 / 5 / 4 | 10 | 2 |

#### Base expansion modules (24)

| Asset | Name | Size above ground W x D x H (m) | Tris LOD0 / 1 / 2 | Surfaces LOD0 / 1 / 2 | Markers | Collision boxes |
|---|---|---|---|---|---|---|
| `ammo_magazine` | Ammunition storage bunker | 15.09 x 20.60 x 9.00 | 230 / 142 / 82 | 5 / 5 / 3 | 2 | 2 |
| `checkpoint_station` | Guard checkpoint | 12.00 x 20.00 x 5.60 | 444 / 444 / 248 | 5 / 5 / 3 | 7 | 7 |
| `comms_tower` | Communications tower 24 m | 19.75 x 22.77 x 27.50 | 1764 / 348 / 32 | 2 / 2 / 2 | 1 | 1 |
| `container_yard` | Container storage area | 28.20 x 16.20 x 8.00 | 934 / 246 / 150 | 8 / 8 / 4 | 8 | 7 |
| `dfp_sandbag_ring` | Fighting position (sandbags) | 3.20 x 2.80 x 0.98 | 4764 / 40 / 40 | 2 / 2 / 2 | 3 | 1 |
| `fuel_bladder_berm` | Fuel bladder in bund | 15.80 x 12.92 x 1.60 | 780 / 296 / 138 | 3 / 3 / 3 | 2 | 3 |
| `fuel_point` | Vehicle fuel point | 14.00 x 10.00 x 5.60 | 344 / 236 / 84 | 4 / 4 / 3 | 2 | 4 |
| `mg_nest` | MG position with overhead cover | 3.40 x 3.20 x 1.79 | 6252 / 108 / 60 | 3 / 3 / 2 | 2 | 4 |
| `mout_wall_door` | MOUT wall (door) | 4.04 x 0.26 x 2.68 | 48 / 48 / 36 | 2 / 2 / 1 | 2 | 1 |
| `mout_wall_window` | MOUT wall (window) | 4.04 x 0.26 x 2.68 | 72 / 72 / 48 | 2 / 2 / 1 | 2 | 1 |
| `obstacle_balance` | Obstacle: balance logs | 2.59 x 5.00 x 1.10 | 216 / 168 / 60 | 2 / 2 / 1 | 0 | 1 |
| `obstacle_crawl` | Obstacle: low crawl wire | 3.20 x 8.20 x 0.50 | 744 / 732 / 12 | 2 / 2 / 1 | 0 | 0 |
| `obstacle_monkey_bars` | Obstacle: monkey bars | 0.88 x 4.08 x 2.30 | 428 / 120 / 80 | 1 / 1 / 1 | 0 | 1 |
| `obstacle_net` | Obstacle: cargo net A-frame | 3.20 x 3.77 x 4.59 | 572 / 104 / 104 | 2 / 2 / 2 | 0 | 1 |
| `obstacle_tires` | Obstacle: tyre run | 1.74 x 6.36 x 0.23 | 1536 / 704 / 320 | 2 / 2 / 1 | 0 | 0 |
| `obstacle_wall` | Obstacle: climbing wall | 3.05 x 0.68 x 2.40 | 144 / 120 / 120 | 2 / 2 / 2 | 1 | 1 |
| `range_backstop` | Range backstop berm | 20.02 x 8.00 x 4.00 | 156 / 156 / 36 | 2 / 2 / 1 | 0 | 1 |
| `range_firing_point` | Range firing point (6 lanes) | 16.64 x 5.52 x 7.00 | 1516 / 332 / 200 | 7 / 7 / 4 | 8 | 7 |
| `range_target_line` | Range target line (6 lanes) | 16.90 x 2.40 x 1.90 | 332 / 260 / 96 | 5 / 5 / 3 | 6 | 1 |
| `range_tower` | Range control tower | 3.73 x 3.16 x 5.93 | 364 / 364 / 180 | 2 / 2 / 2 | 2 | 1 |
| `repair_bay` | Vehicle repair bay (open) | 11.04 x 15.00 x 7.42 | 428 / 404 / 140 | 4 / 4 / 3 | 3 | 9 |
| `shoot_house` | Shoot house (CQB) | 12.60 x 9.60 x 3.10 | 396 / 276 / 228 | 4 / 3 / 2 | 6 | 18 |
| `vehicle_parking_pad` | Vehicle parking pad | 24.10 x 14.00 x 0.20 | 180 / 108 / 12 | 3 / 2 / 1 | 6 | 0 |
| `vehicle_ramp` | Vehicle incline ramp (30 %) | 4.40 x 17.00 x 2.35 | 34 / 34 / 22 | 2 / 2 / 1 | 2 | 1 |

#### Infrastructure and props (51)

| Asset | Name | Size above ground W x D x H (m) | Tris LOD0 / 1 / 2 | Surfaces LOD0 / 1 / 2 | Markers | Collision boxes |
|---|---|---|---|---|---|---|
| `ammo_box_wood` | Ammunition box (wooden) | 0.67 x 0.31 x 0.26 | 138 / 12 / 12 | 3 / 1 / 1 | 0 | 1 |
| `ammo_can` | Ammunition can | 0.31 x 0.16 x 0.20 | 112 / 24 / 12 | 2 / 1 / 1 | 0 | 1 |
| `ammo_pallet` | Ammunition pallet | 1.20 x 0.81 x 0.66 | 962 / 110 / 24 | 5 / 3 / 2 | 0 | 1 |
| `boom_barrier` | Boom barrier 6 m | 6.80 x 0.80 x 1.20 | 708 / 264 / 36 | 2 / 2 / 2 | 2 | 2 |
| `camo_net_canopy` | Camouflage net canopy | 10.01 x 10.01 x 3.24 | 260 / 228 / 128 | 3 / 2 / 1 | 1 | 0 |
| `chainlink_fence` | Chain-link fence 3 m | 3.07 x 0.62 x 2.81 | 282 / 62 / 42 | 2 / 2 / 2 | 2 | 1 |
| `chainlink_gate` | Chain-link gate 4 m (closed) | 4.23 x 0.62 x 3.11 | 492 / 204 / 44 | 2 / 2 / 2 | 3 | 1 |
| `crate_large` | Wooden crate (large) | 1.21 x 0.81 x 0.91 | 110 / 36 / 36 | 4 / 2 / 2 | 0 | 1 |
| `drum_pallet` | Fuel drums on pallet | 1.22 x 1.22 x 1.02 | 926 / 158 / 92 | 4 / 4 / 3 | 0 | 1 |
| `field_toilet` | Field toilet | 1.12 x 1.14 x 2.65 | 152 / 112 / 24 | 1 / 1 / 1 | 1 | 1 |
| `fuel_drum` | Fuel drum 200 l | 0.60 x 0.60 x 0.90 | 516 / 132 / 28 | 2 / 1 / 1 | 0 | 1 |
| `fuel_drum_red` | Fuel drum 200 l (red) | 0.60 x 0.60 x 0.90 | 516 / 132 / 28 | 1 / 1 / 1 | 0 | 1 |
| `fuel_tank_skid` | Fuel tank 10 000 l | 4.62 x 2.20 x 3.05 | 800 / 182 / 40 | 3 / 3 / 2 | 2 | 1 |
| `generator_60kw` | Generator 60 kW | 2.70 x 1.15 x 2.13 | 262 / 96 / 24 | 3 / 3 / 2 | 1 | 1 |
| `generator_60kw_tan` | Generator 60 kW (tan) | 2.70 x 1.15 x 2.13 | 262 / 96 / 24 | 3 / 3 / 2 | 1 | 1 |
| `guard_booth` | Guard booth | 2.00 x 2.08 x 2.68 | 296 / 132 / 36 | 3 / 3 / 2 | 2 | 1 |
| `hesco_mil1_1` | HESCO cell 1.37 m | 1.08 x 1.08 x 1.37 | 140 / 36 / 24 | 4 / 3 / 2 | 2 | 1 |
| `hesco_mil1_5` | HESCO wall 5.3 m (1.37 m) | 5.32 x 1.08 x 1.37 | 348 / 36 / 24 | 4 / 3 / 2 | 2 | 1 |
| `hesco_mil7_2` | HESCO wall 4.3 m (2.21 m) | 4.28 x 2.15 x 2.21 | 192 / 36 / 24 | 4 / 3 / 2 | 2 | 1 |
| `ibc_tank` | IBC water tank 1000 l | 1.22 x 1.09 x 1.17 | 384 / 56 / 24 | 1 / 1 / 1 | 0 | 1 |
| `iso_container_20_blue` | 20 ft container (blue) | 2.44 x 6.12 x 2.59 | 1864 / 240 / 14 | 2 / 2 / 2 | 2 | 1 |
| `iso_container_20_od` | 20 ft container (olive) | 2.44 x 6.12 x 2.59 | 1864 / 240 / 14 | 3 / 3 / 2 | 2 | 1 |
| `iso_container_20_rust` | 20 ft container (red) | 2.44 x 6.12 x 2.59 | 1864 / 240 / 14 | 2 / 2 / 2 | 2 | 1 |
| `iso_container_20_tan` | 20 ft container (tan) | 2.44 x 6.12 x 2.59 | 1864 / 240 / 14 | 3 / 3 / 2 | 2 | 1 |
| `iso_container_40_od` | 40 ft container (olive) | 2.44 x 12.26 x 2.59 | 1816 / 240 / 14 | 3 / 3 / 2 | 2 | 1 |
| `iso_container_40_tan` | 40 ft container (tan) | 2.44 x 12.26 x 2.59 | 1816 / 240 / 14 | 3 / 3 / 2 | 2 | 1 |
| `jerrycan` | Jerrycan 20 l | 0.34 x 0.18 x 0.48 | 168 / 12 / 12 | 2 / 1 / 1 | 0 | 1 |
| `jersey_barrier` | Concrete barrier (F-shape) | 3.00 x 0.62 x 0.89 | 164 / 28 / 28 | 2 / 1 / 1 | 2 | 1 |
| `light_pole` | Light pole 8 m | 0.50 x 1.88 x 8.13 | 180 / 116 / 40 | 2 / 2 / 2 | 0 | 1 |
| `light_tower` | Mobile light tower | 4.11 x 2.38 x 9.34 | 516 / 324 / 72 | 1 / 1 / 1 | 0 | 2 |
| `mesh_fence_temporary` | Temporary fence panel | 4.11 x 0.20 x 2.10 | 170 / 170 / 26 | 3 / 3 / 2 | 2 | 1 |
| `pallet_euro` | EUR pallet | 1.20 x 0.80 x 0.14 | 240 / 12 / 12 | 2 / 1 / 1 | 0 | 1 |
| `radio_mast` | Telescopic radio mast 12 m | 11.51 x 10.00 x 14.35 | 504 / 252 / 60 | 3 / 3 / 1 | 0 | 1 |
| `sandbag_single` | Sandbag | 0.66 x 0.32 x 0.13 | 136 / 44 / 12 | 1 / 1 / 1 | 0 | 1 |
| `sandbag_wall_2m` | Sandbag wall 2 m (1.0 m) | 2.06 x 0.67 x 0.98 | 5760 / 352 / 12 | 1 / 1 / 1 | 2 | 1 |
| `sandbag_wall_green_2m` | Sandbag wall 2 m (green) | 2.06 x 0.67 x 0.98 | 5760 / 352 / 12 | 1 / 1 / 1 | 2 | 1 |
| `sandbag_wall_low_2m` | Sandbag wall 2 m (0.6 m) | 2.05 x 0.67 x 0.62 | 3600 / 220 / 12 | 1 / 1 / 1 | 2 | 1 |
| `sign_checkpoint` | Checkpoint sign | 1.40 x 0.07 x 2.55 | 64 / 32 / 32 | 2 / 2 / 2 | 0 | 1 |
| `sign_no_entry` | No entry sign | 0.60 x 0.07 x 2.50 | 144 / 112 / 112 | 2 / 2 / 2 | 0 | 1 |
| `sign_restricted` | Restricted area sign | 1.20 x 0.07 x 2.50 | 64 / 32 / 32 | 2 / 2 / 2 | 0 | 1 |
| `sign_speed_15` | Speed limit 15 | 0.60 x 0.07 x 2.50 | 144 / 112 / 112 | 2 / 2 / 2 | 0 | 1 |
| `sign_speed_30` | Speed limit 30 | 0.60 x 0.07 x 2.50 | 144 / 112 / 112 | 2 / 2 / 2 | 0 | 1 |
| `sign_stop` | Stop sign | 0.69 x 0.07 x 2.55 | 80 / 48 / 48 | 2 / 2 / 2 | 0 | 1 |
| `sign_warning` | Danger sign | 0.85 x 0.07 x 2.60 | 60 / 28 / 28 | 2 / 2 / 2 | 0 | 1 |
| `sign_yield` | Give way sign | 0.86 x 0.07 x 2.55 | 60 / 28 / 28 | 2 / 2 / 2 | 0 | 1 |
| `supply_pallet` | Supply pallet | 1.20 x 0.82 x 1.05 | 732 / 72 / 24 | 4 / 2 / 2 | 1 | 1 |
| `t_wall` | T-wall blast wall | 1.52 x 1.23 x 3.77 | 164 / 28 / 28 | 2 / 1 / 1 | 2 | 2 |
| `tent_frame_10x6` | Frame tent 10 x 6 m | 8.63 x 10.44 x 3.18 | 488 / 64 / 40 | 2 / 2 / 1 | 2 | 1 |
| `tent_frame_6x4` | Frame tent 6 x 4.5 m | 7.13 x 6.44 x 2.84 | 488 / 64 / 40 | 3 / 2 / 1 | 2 | 1 |
| `traffic_cone` | Traffic cone | 0.38 x 0.38 x 0.75 | 200 / 36 / 32 | 1 / 1 / 1 | 0 | 1 |
| `water_barrier` | Water-filled barrier | 2.09 x 0.50 x 1.03 | 148 / 80 / 28 | 1 / 1 / 1 | 2 | 1 |

#### Road kit (8)

| Asset | Name | Size above ground W x D x H (m) | Tris LOD0 / 1 / 2 | Surfaces LOD0 / 1 / 2 | Markers | Collision boxes |
|---|---|---|---|---|---|---|
| `bridge_small` | Small road bridge 12 m | 8.10 x 19.20 x 1.30 | 432 / 432 / 168 | 4 / 4 / 2 | 2 | 3 |
| `guardrail_4m` | Guardrail 4 m | 4.05 x 0.29 x 0.80 | 72 / 72 / 48 | 1 / 1 / 1 | 2 | 1 |
| `guardrail_end` | Guardrail end terminal | 4.05 x 1.09 x 0.80 | 264 / 264 / 228 | 1 / 1 / 1 | 1 | 1 |
| `road_asphalt_10m` | Asphalt road section 10 m | 13.00 x 10.00 x 0.15 | 56 / 56 / 20 | 4 / 4 / 3 | 2 | 1 |
| `road_culvert` | Culvert with headwalls | 3.43 x 12.00 x 1.20 | 304 / 172 / 140 | 2 / 2 / 1 | 0 | 2 |
| `road_delineator` | Delineator post | 0.10 x 0.15 x 1.00 | 68 / 24 / 12 | 1 / 1 / 1 | 0 | 1 |
| `road_dirt_10m` | Dirt track section 10 m | 3.50 x 10.00 x 0.05 | 34 / 22 / 22 | 2 / 1 / 1 | 2 | 1 |
| `road_gravel_10m` | Gravel road section 10 m | 8.50 x 10.00 x 0.11 | 32 / 16 / 16 | 3 / 2 / 2 | 2 | 1 |

#### Vehicle prototypes (4)

| Asset | Name | Size above ground W x D x H (m) | Tris LOD0 / 1 / 2 | Surfaces LOD0 / 1 / 2 | Markers | Collision boxes |
|---|---|---|---|---|---|---|
| `apc_8x8` | Wheeled APC 8x8 | 3.27 x 7.99 x 4.80 | 4944 / 936 / 300 | 2 / 2 / 2 | 32 | 2 |
| `truck_6x6` | Logistics truck 6x6 | 3.31 x 8.67 x 3.60 | 4104 / 902 / 274 | 4 / 3 / 3 | 20 | 2 |
| `wheel_apc` | APC wheel | 0.48 x 1.30 x 1.24 | 496 / 72 / 28 | 2 / 2 / 1 | 1 | 0 |
| `wheel_truck` | Truck wheel 14.00R20 | 0.48 x 1.35 x 1.29 | 496 / 72 / 28 | 2 / 2 / 1 | 1 | 0 |

Total assets: 96; validation errors: 0

### Faction infantry pieces

| Piece | Tris LOD0 / 1 / 2 | Materials | GLB KB |
|---|---|---|---|
| `cn_helmet` | 5240 / 1572 / 340 | Camo_Type21, Polymer_Black, Strap_Black | 261 |
| `cn_jacket` | 10044 / 3012 / 652 | Camo_Type21, Patch | 766 |
| `cn_pack` | 4164 / 1248 / 270 | Camo_Type21, Strap_Black | 202 |
| `cn_trousers` | 8000 / 2400 / 520 | Camo_Type21 | 565 |
| `cn_vest` | 6476 / 1942 / 416 | Camo_Type21, Polymer_Black | 545 |
| `cn_optic` | 512 / 200 / 60 | Lens, Metal_Black | 52 |
| `cn_rifle` | 4772 / 1430 / 233 | Metal_Black, Metal_Worn, Polymer_Black, Polymer_OD | 489 |
| `nato_helmet` | 5814 / 1744 / 376 | Camo_NATO, Polymer_Black, Polymer_Tan, Strap_Black | 299 |
| `nato_jacket` | 10044 / 3012 / 652 | Camo_NATO, Fabric_Coyote, Patch | 794 |
| `nato_trousers` | 8000 / 2400 / 520 | Camo_NATO | 565 |
| `nato_vest` | 7108 / 2132 / 459 | Camo_NATO, Polymer_Black, Rubber_Black | 547 |
| `nato_optic` | 720 / 216 / 57 | Lens, Metal_Black, Polymer_Black | 70 |
| `nato_rifle` | 4948 / 1484 / 238 | Metal_Black, Metal_Worn, Polymer_Black, Polymer_Tan | 504 |
| `ru_armor` | 8508 / 2552 / 546 | Camo_EMR, Polymer_Black, Rubber_Black | 642 |
| `ru_helmet` | 4864 / 1458 / 315 | Camo_EMR, Lens_Tinted, Rubber_Black, Strap_Black | 252 |
| `ru_jacket` | 10044 / 3012 / 652 | Camo_EMR, Patch | 766 |
| `ru_trousers` | 10368 / 3110 / 672 | Camo_EMR, Polymer_Black, Strap_Black | 801 |
| `ru_optic` | 352 / 200 / 60 | Lens, Metal_Black | 71 |
| `ru_rifle` | 4440 / 1332 / 213 | Metal_Black, Metal_Worn, Polymer_Black, Polymer_Plum | 447 |

| Loadout | Pieces (faction + shared CHARACTER-01) | Tris LOD0 / 1 / 2 | Surfaces (unmerged LOD0) |
|---|---|---|---|
| `NATO_rifleman` | nato_jacket, nato_trousers, nato_helmet, nato_vest, nato_rifle, nato_optic + boots, gloves, eyepro, belt_standard, pack_assault, foregrip, laser | 59 950 / 18 218 / 3 906 | 34 |
| `RU_rifleman` | ru_jacket, ru_trousers (external knee pads), ru_helmet (goggles), ru_armor (6B45-class + 6Sh117-class pouches), ru_rifle, ru_optic + boots, gloves | 51 516 / 15 546 / 3 296 | 24 |
| `CN_rifleman` | cn_jacket, cn_trousers, cn_helmet (PASGT-lineage skirt, rails), cn_vest, cn_pack, cn_rifle, cn_optic + boots, gloves, foregrip | 52 296 / 15 834 / 3 389 | 23 |
| reference `A_standard` | CHARACTER-01 | 61 235 / 18 501 / 3 904 | |

At runtime CHARACTER-01's `InfantryLodMerge` merges LOD1/LOD2 per loadout (LOD2 = one surface) and builds the far proxy, unchanged.

**Distinct silhouettes, not recolours** **[INSPECTED]** (`docs/asset01/godot/factions_lineup_*.jpg`, `faction_*_close*.jpg`, `docs/asset01/characters/*`):
* **NATO:** mid-cut ballistic helmet with multi-terrain cover, NVG shroud, ARC rails, tan electronic ear defenders, IR strobe; slim plate carrier (triple shingle, radio, IFAK, grenades); combat shirt with plain coyote torso; assault pack; HK416A5-class carbine (slim M-LOK handguard, tan furniture, ribbed magazine) with a 1-4x scope, IR laser, fore grip.
* **Russian:** 6B47-class rounded helmet with digital cover, camo band and goggles on the brow; 6B45-class full-wrap armour with high collar, shoulder protectors, groin flap; 6Sh117-class pouches with four AK magazines across the belly; external hard knee pads; no pack; AK-12-class rifle (railed dust cover, long railed handguard, front-sight gas block, long brake, side-folding stock, plum magazine) with a square-window reflex sight.
* **Chinese:** PASGT-lineage helmet (flared skirt) with Type 21 cover and rails; Type 19-class carrier with a wide four-magazine panel and admin panel; flat square hydration pack; QBZ-191-class rifle (blocky upper, flared magwell, OD furniture, birdcage) with a 3x prism sight and fore grip.
* Camouflage: original patterns in the spirit of MultiCam/MTP (NATO), EMR digital (RU, 4.7 mm pixels), Type 21 "star-sky" digital (CN, 4.7 mm pixels with specks).

## 4. Materials, textures, atlases

* **51 shared materials** (`assets/military/materials/*.tres`) from one table (`ap_materials.py`); GLBs carry names only and the import script swaps in the library material. Typical building: 6–7 surfaces at LOD0, 4–5 at LOD2.
* **31 textures, 25 MB on disk** (`assets/military/textures/`): 1024 px tileables for large surfaces (paint, container ribs, roof sheet, concrete, CMU, asphalt, gravel, dirt, canvas), 512 px for the rest, 2048 px sign atlas, 256 px palette (albedo / ORM / emission). VRAM compressed + mipmaps, normal maps flagged (`.import` files written by the build); palette lossless without mipmaps. Godot reported 142 MB texture memory with the sample base and 15 soldiers loaded (`showcase.json`).
* World-scale box UVs (tile per material), vertex-colour ground dirt, greyscale bases tinted per material, palette for small parts, sign atlas for signs, plates, targets, container doors, dials, grilles. Details: `docs/ASSET_STANDARD.md` §4.
* Infantry: 6 new library entries in `InfantryMaterials.TABLE` (`Camo_NATO`, `Camo_EMR`, `Camo_Type21`, `Fabric_Coyote`, `Polymer_Tan`, `Polymer_Plum`) and three 1024 px camouflage textures in `assets/characters/infantry/textures/`. Faction camouflage is fixed per family; `Camo_M23` faction swapping is untouched.

## 5. LODs

Authored per asset (detail parts dropped, stand-ins added: e.g. the container's LOD2 is one box with the door decal), ranges per family (building 0–70 / 70–280 / 280–2000 m, module 0–60 / 60–240 / 240–1600 m, prop 0–35 / 35–120 / 120–600 m, road 0–60 / 60–250 / 250–1500 m, vehicle 0–40 / 40–160 / 160–1500 m; small props 20 / 60 / 160 m), set as visibility ranges by the import script with a shared hysteresis margin per boundary. Godot's automatic mesh LODs stay enabled on LOD0. LOD switch screenshots at the real distances: `docs/asset01/godot/*_lodrange.jpg` (all buildings, truck, APC, HESCO, container yard) **[INSPECTED]** (each LOD shown in its band). Infantry LODs follow CHARACTER-01 (`_LOD0/1/2`, 30 % / 6.5 % collapse, runtime merge).

## 6. Character rig and weapon compatibility; the hip fix

### Rig and animation
* No new rig, clips or animation framework. Faction pieces are built by the CHARACTER-01 modules (`char_body`, `char_uniform`, `char_gear`, `char_lib.transfer_weights`, `char_export`) against the same skeleton and weight reference; skinned pieces bind by bone name, rigid pieces ride on `ATT_Head` / `ATT_Back`, weapons on `ATT_Weapon`, accessories on weapon mounts.
* Godot checks per loadout **[VERIFIED]**: 60 bones = CHARACTER-01, 19 clips, every piece attached, no material outside the library, mounts `ATT_Optic` / `ATT_Muzzle` / `ATT_Underbarrel` / `GRIP_Support` present.

### Weapons
* All three rifles keep the weapon-space contract (`docs/CHARACTER_STANDARD.md` §3): grip origin, bore at z = 0.074, `GRIP_Support` at (0, 0.165, 0.074) with the standard hand frame (so the shared clips keep both hands on every rifle; Idle-pose renders `docs/asset01/characters/idle_*`), `ATT_Optic` at z = 0.114 **[VERIFIED]** for all three.
* Optics put their axis 0.058 m above the mount and use `Metal_Black` for the housing and `Lens` for glass, so `Viewmodel` cuts the bore and the ADS sight line runs through the optic **[INSPECTED]** (`faction_*_fps_ads.jpg`). Shared foregrip and laser mount on the new rails.
* Muzzle mounts per rifle (NATO 0.560, RU 0.588, CN 0.557 m) feed `InfantryCharacter.muzzle()` for flashes/tracers.

### Hip fix (shared CHARACTER-01 body)
User feedback: the hips looked squeezed and unnatural. Diagnosis by measurement, not by eye:
1. **Weights.** Automatic body weights gave the thigh bones up to 88 % influence at belt height (z = 1.00 m), 57 % at 1.05, 27 % at 1.10 (`tools/blender/character/diag_weights.py`). Every hip flexion (Idle stance, walking) dragged the belly and jacket hem down and forward: waist collapse, hem flap. New `char_lib.limit_leg_weights` fades thigh influence out between 0.80 and 1.00 m (lower at the midline so the crotch does not bulge) and gives it to `Hips`; jackets get their own fade (0.74–0.98 m) so the hem follows the pelvis, partly pushed by the thighs. Applied in `build_infantry.py` and `build_factions.py`. Leg influence above 1.00 m: 0.
2. **Proportions.** Clothed half-widths before: waist 0.17 m vs hips/thighs 0.20 m with a dip at the hip crease (ratio 1.19, jodhpur silhouette). Now: chest/waist 0.18–0.19, hips 0.20 (jacket over the trochanters), thighs tapering 0.19 → 0.17 (ratio 1.07) (`measure_silhouette.py`). Changes: wider lower chest and waist, a trochanter mass at the hip joints, slimmer thighs that start inside the hip mass, cargo pockets on the leg instead of standing out, a straight jacket hem wrapped over the trouser tops.
3. Before/after in the Idle pose: `docs/asset01/characters/hips/hips_before_after.jpg` (also `v3_Run_F_side.jpg` for running); posed Godot views `docs/asset01/godot/faction_*_hips_{front,side}.jpg` **[INSPECTED]**.
4. CHARACTER-01 was re-exported (rig, body regions, uniform, gear, weapons, LODs; clips regenerated identically: `animation_meta.json` unchanged apart from line endings). CHARACTER-01's own lab checks pass **[VERIFIED]** (`benchmarks/asset01/char01_checks_after_hip_fix.txt`: shared rig, piece swap, hands on the weapon within 0.2–3 mm, foot-slide figures as before, LOD/material counts, proxy).

## 7. Godot import validation

`benchmarks/asset01/run_lab.sh --validate` (about 1 min) checks every catalogued asset **[VERIFIED, 96/96, 0 errors]**: `<id>_LOD0/1/2` present and LOD0 first (StructureCatalog uses the first mesh), triangles never rising and LOD2 < LOD0, visibility ranges contiguous, every surface a library material, vertex colours on every surface, LOD0 bounds equal to the Blender metadata (catches axis / orientation errors), nothing floating, collision shape count = metadata, every marker present at its Blender position, `fn_asset` metadata present (import script ran). Godot screenshots of every asset: `docs/asset01/godot/<id>.jpg` (front 3/4, back 3/4, eye level, top); Blender renders: `docs/asset01/blender/<id>.jpg`.

## 8. Performance

| Test | Result |
|---|---|
| Sample base (203 instances: 9 buildings, 24 modules, props, 18 road sections, about 100 HESCO sections, 4 vehicles, 15 animated soldiers), FPS views | 1.07–1.43 ms avg (p-worst 2.1–3.4 ms), 216–609 draw calls, 51–234 k triangles |
| Same base, RTS overview / core | 1.03 / 1.08 ms, 374 / 365 draw calls |
| Strategic view from 600 m | 1.38 ms, 120 draw calls |
| Nine bases 400 m apart (1.8 k static instances), strategic / RTS inside | 1.08 / 1.14 ms, 307 / 773 draw calls |
| 120 animated soldiers, faction loadouts vs CHARACTER-01 loadouts (close / mid / RTS) | 12.33 / 9.89 / 4.15 ms vs 13.35 / 10.72 / 4.12 ms; draw calls 2152 / 718 / 271 vs 2383 / 796 / 271 |

Assets are plain scene instances here (no MultiMesh); the construction system's MultiMesh rendering (WORLD-BASE-01) would reduce draw calls further for repeated pieces. GPU time reported by Godot's viewport timer (0.4–0.6 ms for the base) looked low and was not cross-checked. The 120-soldier cost is the shared CHARACTER-01 system's (skinning + animation, ~3 ms animation), not specific to the new loadouts.

## 9. Integration (gameplay-side work; nothing here was changed in gameplay code)

1. **Construction:** register `assets/military/defs/*.tres` (`StructureDef` data: size, collision AABBs, ramps for the vehicle incline, slope / ground-gap limits, nav blocking) in `StructureCatalog` (today code-built), e.g. by loading every `.tres` in that folder. Meshes come through `mesh_of()` unchanged (LOD0 is the first mesh; its automatic LODs work with MultiMesh). Use LOD2 as a far MultiMesh if wanted.
2. **Free placement as scenes:** instance the GLB; collision (`COL_*` convex boxes), LOD ranges and markers come with it. Read `get_meta("fn_asset")` for footprint and markers.
3. **Markers** are the integration points: `IP_*` (door / dock / dispenser / firing lane / observer positions), `VEH_*` (truck dock, bay, refuel, parking), `ATT_*` (expansion / annex / antenna / generator positions), `SNAP_*` (module ends for lines), vehicle `WHEEL_*`, `SUSP_*`, `DOOR_*`, `SEAT_*`, `CARGO_*`, `TOW_*`, `WEAPON_*`. Semantics: `docs/ASSET_STANDARD.md` §2.
4. **Faction loadouts:** `InfantryLoadout.by_id("NATO_rifleman" | "RU_rifleman" | "CN_rifleman")`. Soldiers currently get `A_standard` / `B_heavy` from `InfantryLoadout.default_for(unit_id)`; mapping WorldState factions to families (e.g. via `UnitState.loadout` at spawn) is a gameplay decision.
5. **Roads:** the road generator keeps ownership. Recommended: `Asphalt.tres` (4 m tile), `Gravel.tres` (2 m), `Dirt.tres` (4 m), `Paint_RoadWhite/Yellow.tres` for markings; cross-sections in `fam_roads.py` (asphalt 7.0 m + 1.0 m shoulders + 2.0 m / 0.5 m ditches, 2.5 % crossfall; gravel 5.5 m + 1.5 m ditches, 3 % crown; dirt 3.5 m with ruts at 1.9 m track). Ditches, culverts and the bridge gap need terrain cuts / Terrain3D holes (they sit below z = 0). Guardrail 4 m modules + terminal, delineators, culvert with headwalls, 12 m bridge are dressing assets.
6. **Vehicles:** visual prototypes. For driving: replace the wheels in the body mesh by `wheel_truck` / `wheel_apc` at `WHEEL_*` markers (radius / width in the sidecar metadata), suspension at `SUSP_*`.
7. **Character changes to integrate:** the re-exported CHARACTER-01 assets (hip fix), the six new `InfantryMaterials.TABLE` rows, three loadouts. No API changes.

## 10. Files touched outside the new asset directories

| File | Why |
|---|---|
| `scripts/characters/infantry_materials.gd` | 6 new rows in the material table (data only) |
| `tools/blender/character/char_body.py`, `char_uniform.py`, `char_lib.py`, `build_infantry.py` | hip fix (proportions, `limit_leg_weights`, jacket fade); new diagnostics `diag_weights.py`, `measure_silhouette.py`, `preview_hips.py` |
| `assets/characters/infantry/{rig,parts,weapons}/*.glb`, `blender/infantry.blend`, `build_log.json` | CHARACTER-01 re-exported with the hip fix |
| `assets/characters/infantry/loadouts/{NATO,RU,CN}_rifleman.tres` | new loadouts (must live in this folder for `InfantryLoadout.by_id`) |

No changes to WorldState / WorldSim, navigation, combat, the soldier controller, construction, roads or the strategic map, and nothing in WORLD-PLAYTEST-01's areas.

## 11. Testing (change-impact policy)

Run during this milestone: the asset lab modes for the new assets (`--validate` all, `--shots` all, `--lod`, `--factions`, `--charperf 120`, `--showcase`) and, because shared CHARACTER-01 assets changed, CHARACTER-01's own `run_char_lab.sh --checks` (PASS). Not run: the sandbox/world regression suites (`--sandbox-test`), because no gameplay code changed and the worktree has no generated 20 km world; the in-world look of the faction soldiers and buildings on real terrain is **[NOT VERIFIED]**.

## 12. Limitations

* Not seen by a human in play: everything was checked by script and screenshots. Proportions of the hip fix were verified by measurement and renders; a playtest on real terrain is the real test.
* All buildings are solid (no interiors; doors are visual). The vehicle depot's roller doors and the supply depot's dock doors are closed.
* Ditches, culvert openings and the bridge gap need terrain cuts; on flat ground they are hidden.
* Single shared head and skin tone for every soldier (CHARACTER-01). No faction-specific boots/gloves.
* Vehicle prototypes: wheels part of the body mesh, no interiors, simple tread blocks.
* Sandbag walls / fighting positions are triangle-heavy at LOD0 (3.6–6.3 k) because every bag is modelled; LOD1 drops to 40–350.
* LOD2 of large buildings loses door / dock details (no decals yet).
* HESCO and chain-link mesh read as plain grey walls beyond ~60 m (alpha mesh fades by design).
* Godot GPU timer values were not cross-checked.
* Textures are procedural (no photo sources); signs use generic designs, no real insignia.

## 13. Running

```bash
# Blender (background)
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/asset_production/build_assets.py -- --export --previews docs/asset01/blender
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/asset_production/characters/build_factions.py -- --export --previews docs/asset01/characters
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/character/build_infantry.py -- --export
# Godot asset lab
benchmarks/asset01/run_lab.sh --validate
benchmarks/asset01/run_lab.sh --shots [ids | family:building]
benchmarks/asset01/run_lab.sh --factions
benchmarks/asset01/run_lab.sh --charperf 120
benchmarks/asset01/run_lab.sh --showcase
```

Screenshots: `docs/asset01/godot/` (assets, LOD ranges, factions, showcase), `docs/asset01/blender/` (Blender sheets and LOD strips), `docs/asset01/characters/` (faction A-pose / Idle sheets and close-ups, hip before/after).
