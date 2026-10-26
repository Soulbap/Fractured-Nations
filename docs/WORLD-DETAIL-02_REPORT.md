# WORLD-DETAIL-02 — Physical cover, environmental detail and battlefield density

Branch `feature/world-detail-02` (worktree `../fractured-nations-world-detail-02`, from `develop` @ `0fac37c`), not merged.

`ref_20km` gets **7 187 man-made and natural detail objects** in a new read-only layer: garden walls and fences at the plots,
firewood against the houses, round bales and yard goods at the farms, builder's and container yards in the town and the works,
transformer kiosks, road depots and guardrails along the roads, sandbag / HESCO checkpoints on the roads into objectives, and
bales and rock piles on the last 200 m into every settlement. The solid ones are cover through the existing systems; nothing is a
new cover, collision or streaming system. On request during the milestone, **every sandbag asset was rebuilt** (pillow bags laid
tight, from reference photographs) and **the road culverts were rebuilt and re-seated** into the road fill.

## 1. Assets

**New civilian kit** (`tools/blender/asset_production/fam_props_civil.py`, static library pipeline, QA gate passed, previews
`docs/world_detail02/blender/`): 12 models.

| Asset | Size (m) | Collider |
|---|---|---|
| round_bales_white / _green: four wrapped silage bales in a row | 5.1 × 1.3 × 1.25 | box |
| firewood_stack: split wood between posts under a sheet | 3.4 × 1.0 × 1.4 | box |
| garden_wall_concrete / _stone: plot walls | 6.0 × 0.35-0.45 × 0.85-0.9 | box |
| picket_fence: white stakittgjerde section | 4.0 × 0.1 × 1.0 | none (drawn only) |
| concrete_blocks: 1.6 × 0.8 × 0.8 m interlocking blocks, two high | 4.8 × 0.8 × 1.65 | 2 boxes |
| concrete_pipes: three 1000 mm pipes on chocks (hollow, whole) | 2.3 × 2.0 × 1.95 | 2 boxes |
| skip_green / _yellow: open lift skip with waste | 3.6 × 2.3 × 1.5 | box |
| transformer_kiosk: nettstasjon | 3.0 × 2.5 × 2.45 | box |
| material_stack: pallet stacks, cement sacks, bulk bag | 4.0 × 1.7 × 1.3 | 4 boxes |

New materials: `Wrap_White`, `Wrap_Green` (bale film). Reference photos: Wikimedia Commons (free licences) for bales,
firewood, garden walls, kiosks, pallets, picket fences, skips and sandbags; downloaded to `benchmarks/raw/wd02_refs*` (study
material, not committed).

**Reused** (existing library, unchanged): jersey barrier, HESCO 5-cell line, sandbag wall 2 m (tan / green), T-wall, ISO 20 ft
containers (rust / blue civilian; OD / tan military), guardrail 4 m, chain-link fence, yard goods (IBC tank, drum pallet,
supply pallet, crate), log barricade; from WORLD-COVER-01 the rock group, boulder and timber stack.

**Vegetation library ids 31-49** (`assets/environment/nordic_library.tres`, 19 ids, 29 variants) are written by
`tools/world_detail/make_detail_library.py` from the asset sidecars: an id's box is the union of its variants' collision boxes,
several or off-centre boxes become per-variant `parts`. The same script writes `assets/environment/detail_kit.json`
(footprints, solid or drawn only) for the layer. All box radii stay under 3.3 m (LineOfFire's bucket reach).

### 1.1 Sandbags (rebuilt)

The old bags were scaled spheres with gaps. Now one shared geometry, `tools/blender/sandbag_geo.py`: a filled bag is a pillow
(0.60 × 0.32 × 0.14 m, flat where it presses on its neighbours, blunt sewn end, one folded flap), laid tight in running bond,
each course pressed 2 cm into the one below; walls, rings (circular positions) and roof layers come from the same layouts
(`ap_kit.sandbag / bag_wall / bag_ring / bag_layer`). Rebuilt with it (QA: no new findings against the baseline):

sandbag_wall_2m, sandbag_wall_low_2m, sandbag_wall_green_2m, sandbag_single, sandbag_fighting_position, earth_berm,
dfp_sandbag_ring, mg_nest, fighting_position, mg_emplacement, range_firing_point, guard_booth, guard_tower_steel,
bunker_fighting (static library) and **guard_tower** (WORLD-BASE-01 structures, `tools/blender/structures/make_buildings.py`).
Collision boxes are unchanged; StructureDef sizes moved by ≤ 5 cm. Previews `docs/world_detail02/sandbags/`.
LOD0 is heavier than before (a 2 m wall 10 k triangles, the largest positions 30-41 k); LOD1 uses coarse bags, LOD2 blocks.

### 1.2 Culverts (rebuilt and re-seated)

The VISUAL-02 culvert was a pipe in a free-standing stone headwall, placed 2.5 m off the road on the terrain as it was before
the settlement layer, road shoulders and relief changed it — so it stood up beside the road like a block.

- **Model** `tools/blender/env/make_culvert_v2.py`: a corrugated steel pipe (0.8 m bore) whose mouth stands 0.75 m out of the
  foot of the fill (a terrain cannot have a hole), slightly mitred, a stone apron from the moss-rock scans; 4.5 m of pipe run back
  under the fill.
- **Placement** `CulvertSeat` (`scripts/world/culvert_seat.gd`), in memory at game start after the terrain layers (scene and
  manifest untouched): each end moves to the toe of the embankment on the final terrain (stopping on the bank at a stream and
  before another road at a junction), faces away from the road, and the buried pipe dips (≤ 16°) until the ground covers it under
  the road. **87 of 422** ends have a real fill to lie in and are shown; 319 on roads at grade and 16 at junctions are hidden
  (the product owner agreed to drop placements that make no sense). `--legacy-culverts` gives the old placement.

## 2. Placement (`DetailLayer`, `worlds/detail/ref_20km.detail.json`)

A read-only WorldOverrides layer like the cover layer, loaded after it (`--no-world-detail` off). Built in the running game in
46 s, deterministic (hashes of building / cell / road positions):

`--scenario=dev --no-world-detail --build-detail-layer [--area=x,z,r]`

| Rule | Where | Placed |
|---|---|---|
| plot boundary: two 6 m garden walls with a gate gap, or picket fence, between house and road | every house near a road (town 50 %/25 %, village 40/30, hamlet 30/30, farm 15/20) | 251 walls, 521 fence sections |
| firewood stack along a long wall | 30-50 % of houses | 223 |
| skip / pallets of a renovation | town and village houses, a few elsewhere | 32 / 29 |
| farm: 1-2 bale rows 8-22 m off the barn away from the road; goods, pallets, firewood / timber, block bin, a container | barns | 102 rows, 82 others |
| settlement approaches (0.85 R to R + 200 m, 30 m cells): bales on fields, rock groups / boulders, timber | open ground round every settlement (not forest, not wet) | 234 / 346 / 55 |
| yards: container rows (some stacked), block walls, pipes, skips, goods, chain-link | the works (Verket, 9), the town (7), villages (1) | 112 objects |
| transformer kiosk beside a road | 1 + 1 per 200 m of radius per settlement | 30 |
| road works depot (pipes, blocks, pallets, skip) 14-22 m off a main road | ~45 % of every 2.5 km | 60 |
| guardrail (drawn only) | meshed main roads where the ground falls 1.5 m within 6 m and 4 m within 11 m of the edge, bridge approaches | 5 065 sections |
| checkpoint: sandbag walls across both shoulders, HESCO / jersey barrier along them, T-walls, sometimes a military container | 70-110 m out on roads into 9 bridge / village / town objectives | 45 |

Never: within ~2.5 m of the road mesh edge (all footprint corners checked), within 40 m of a bridge (guardrails excepted), in
water, on ground rising > 0.6 m under the footprint, over trees / rocks / structures / buildings (probes every 1.5 m along the
footprint, building rectangles), closer than 1.2 m to another object, on objective centres (40 m), base areas (+30 m) or base
sites (220 m). Rejections in the full build: slope 371, building 187, road 145, gap 94, area 37, occupied 19, bridge 1.

Military objects appear only at checkpoints on roads into objectives; civilian countryside gets no barriers. Large open fields
stay open (approach objects are sparse: about one per six 30 m cells).

## 3. Functional cover — existing systems only

| System | What it does with the new objects |
|---|---|
| VegetationStreamer / WorldOverrides | draws them as instanced multimeshes with the assets' 3 LODs (`extra_layers`) |
| LineOfFire | box solids stop bullets and sight (fences, guardrails, chain-link: no solid) |
| InstanceColliderStreamer | box shapes near the observer (physics, vehicles) |
| StructureManager / AreaNavigation | clearance circles and navmesh rectangles: soldiers walk round, vehicles plan round |
| CombatBrain.cover_spots | `_box_candidates` puts posts behind them; used by reactions, DEFEND / firing posts, bounds and the GAMEPLAY-02 placement once integrated |

No combat, AI, UI or input code was changed.

## 4. Checks (`--scenario=dev --world-detail-test [--shots]`, all PASS)

| Check | Result |
|---|---|
| r_loaded | 7 187 of 7 187 layer records in the streamer's overrides |
| r_roads | 1 579 solid objects: 0 at a road surface, 0 on a bridge deck |
| b_ballistic | crouched shots from four sides stopped by every solid kind (4-8 of 8; the misses pass beside the ends), the cover test protects behind all of them; picket fence and guardrail stop none |
| c_cover | cover posts at a garden wall (5 box + 8 terrain), a bale row (5) and a container (2) |
| v_culverts | 87 shown, 0 on a road, 0 facing the road |
| screenshots | `docs/world_detail02/wd_*_eye.jpg` / `_rts.jpg`: plot wall, plot fence, farm bales, firewood, skip, container yard, kiosk, guardrail, checkpoint, approach rocks, two culverts |

No combat suites, performance runs or long simulations were run (milestone scope). The layer adds 1.1 MB of JSON; the cover
layer's measurement (32 k records, +0.19 s at start) puts this one's load cost well under a tenth of a second.

## 5. Integration notes (shared files)

- `scripts/game/core_demo.gd`: `--build-detail-layer`, `--world-detail-test`, `CulvertSeat.apply` after the terrain relief.
- `scripts/vegetation/vegetation_streamer.gd`: the layer in `extra_layers`. `scripts/world/terrain_relief.gd`: the layer in the
  relief builder's exclusions (one line).
- `assets/environment/nordic_library.tres`: ids 31-49 appended (regenerate with `make_detail_library.py`, idempotent).
- Asset pipeline: `ap_materials.py` (2 materials), `build_assets.py` (module registration), `ap_kit.py` (sandbag helpers),
  `fam_props.py` / `fam_props_tactical.py` / `fam_modules.py` / `fam_buildings.py` (sandbags), `structures/make_buildings.py`.
- Rebuilt GLBs / sidecars / defs of the 15 sandbag assets and `assets/structures/guard_tower.glb`; new `culvert.glb` / scene /
  meshes.
- Pre-existing fix: `assets/environment/materials/wood_end_grain.tres` (used by the committed timber stack meshes) was never
  committed in WORLD-COVER-01; it is now.
- The worktree links `worlds/ref_20km/{source,terrain,vegetation,water}` and `assets/environment/source` to the main checkout
  (junctions) and holds copies of the other git-ignored world files; the manifest is untouched.
- CLAUDE.md asks for work on `develop` without new worktrees; this branch / worktree follows the milestone brief (parallel work).

## 6. Known limitations

- Guardrails and fences have no collider: they neither stop bullets nor block walking (deliberate; thin boards / rails).
- The library's house collider is a 4 m sphere, not the house's box; firewood stands 1.1 m off the wall to clear it.
- Box solids are boxes: a bale row, pipe stack or block wall stops bullets over its whole box (gaps between round bales included).
- 335 culvert ends are hidden (no fill or a junction): those crossings have no visible culvert.
- Sandbag-heavy positions are 30-41 k triangles at LOD0 (within 40 m only).
- Industrial yards are few (14 main + their extras): the works and the town have little free flat ground between buildings
  and roads.
- Not measured in combat: how much the new cover changes assaults is AI-COMBAT-02's job.
