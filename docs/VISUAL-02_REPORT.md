# VISUAL-02 — World & Environment Overhaul

Branch `develop` (project standard). Markers: **[RUN]** measured in the real game at 1920×1080; **[CODE]** read in the source;
**[NOTE]** judgement. Screenshots in `docs/visual02/` (JPEG). The reference world `ref_20km` is **unchanged**
(`world_manifest.py verify` OK); everything that needs new world files is in a separate **candidate world** that waits for
the product owner's approval (§14).

## 1. Executive summary

The world's flat, repetitive look had three root causes, only one of which was "art":

1. **A data bug made the forest monotone.** The generator wrote its 4-channel maps through OpenImageIO, which treats the 4th
   channel as alpha and *divides RGB by it* when writing PNG. `vegetation.png` keeps wetness in alpha, so the pine and birch
   shares were divided by a small number and saturated: 48 % of the map says "100 % pine". **[RUN]** The planted reference forest
   is **71 % pine, 20 % spruce, 9 % birch** everywhere, whatever the ground. The same bug washed out the procedural forest
   floor, gravel, bog and asphalt textures (height in alpha: albedo up to 3× too bright, 67 % of forest-floor pixels clipped
   to white) and gave every foliage card a bright fringe. **Fixed** in the writers; textures regenerated (identical except the
   corrupted pixels).
2. **The terrain colour map is painted, not composed.** Field parcels are flat colours with straight edges, meadows one green,
   and a forest beyond ~1 km (where tree meshes stop) turns into bare forest-floor texture, so from the tactical camera every
   forest has a hard square edge. **Fixed in the shader** (in memory, no world file changed): a new ground shader softens and
   warps the colour map, adds macro variation, turns parcels into fields with rows / tramlines / mowing bands / furrows, and
   draws distant forest as a mottled canopy.
3. **Vegetation and land use come from a few independent noises.** One forest noise, one clearing noise, trees on a jittered
   6.5 m grid with probability = density. **Rebuilt as a candidate**: one set of environmental parameters (elevation, slope,
   moisture, distance to the river, rockiness, farmland / settlement influence, a few landscape zones) drives forest density,
   stand age (forestry stands, clear-cuts, regrowth), species, ground and colour together; trees are planted in groups and gaps
   with sizes by age.

The settlement buildings and fences were rebuilt in Blender with textures (weatherboard, board-and-batten, pantiles,
corrugated sheet, stone plinth, window and door panels) at **fewer triangles** than before.

What the product owner gets now, without approval: the bug fixes, the ground shader and the new buildings on `ref_20km`.
What needs approval: the candidate world `ref_20km_visual02` (new vegetation, colour and ground maps on the unchanged relief,
roads, settlements and bases).

## 2. Visual baseline and current weaknesses

`--visual02-test --only survey` (scripts/debug/visual02_selftest.gd) places a free camera at 13 fixed points chosen from the
generator's maps across the whole 20 km world (not only the New Game valley), then the tactical camera over a base, first
person and the map. Same lighting every run (no day cycle), HUD hidden for the world views.

| # | View | Place (world x, z) |
|---|---|---|
| 01 | Open meadow, ground | Flyslette øst plateau (7600, −3000) |
| 02 | Dense forest, FPS | west forest (−5850, −1914) |
| 03 | Sparse forest, FPS | south-east (6436, 2520) |
| 04 | Forest edge | east (7275, −1700) |
| 05 | Agricultural area | Øst-sletta (4000, −1150), 25 m |
| 06 / 06b | Small settlement (overview / street) | Skogli (−4150, 50) |
| 07 / 08 | Road through forest / open terrain | Rv2 (4633, −3503), Fv øst (3826, 82) |
| 09 | River | Hovedelva, centre (160, −700) |
| 10 | Mountain foothills | under Nordfjellet (2900, −7600) |
| 11 | Valley | central valley from a ridge (−600, −3200) |
| 12 | Military base, tactical camera | New Game start + 6 structures |
| 13 / 13b | High-altitude RTS / RTS over the start valley | 900 m / 160 m |
| 14 | Ground-level FPS | the player's squad leader |
| 15 | Long-distance landscape | from the NE heights (5900, −5900) |

Baseline findings ([RUN], `docs/visual02/baseline/`):

- **Repeated patterns**: the same pine stand everywhere (bug 1); identical spacing (jittered grid, nearest-neighbour CV 0.435);
  parcels in the same lime / ochre / green palette from the valley floor to the plateaus.
- **Unnatural transitions**: forest → meadow is a wall of trunks; fields end in straight colour lines; the tree ring around the
  camera is visible from the air as a square of trees on a flat dark green.
- **Material weaknesses**: forest floor, gravel and bog washed out (bug 1); meadow texture tinted to a saturated lime; houses,
  barns and sheds flat colours with painted black windows; fences untextured.
- **Vegetation**: grass tufts a different green from the ground under them (a visible ring at 60–70 m); outcrops lying flat on
  steep rock faces showing their undersides; forest interiors very dark.
- **Terrain geometry**: relief good and varied at the large scale (massif, rocky hills, valley, lakes, plateaus); detail is
  smooth; no change needed for this milestone (§3).
- **Empty areas**: plateaus (deliberately open for bases) read as golf courses; large open meadows without anything on them.
- **Landmarks**: the river, Nordfjellet and the lakes are strong; the forests do not differ from each other.

## 3. Terrain analysis

[CODE] `tools/terrain_ref/generate.py`: macro relief from a hand-authored layout (regional slope to the river, hills scaled by a
hilliness field, rocky hills, a NE massif with passes, lake basins, flattened settlements / plateaus), drainage carving
(priority-flood + D8, valleys in proportion to catchment), roads graded by A*, then 1.95 m detail. [RUN] The relief already has
what the brief asks for — broad and narrow valleys, rocky ridges, plateaus, a river with terraces, stream valleys, a massif —
and it is tied to the roads, bridges, settlements, bases, the strategic route grid and the navigation tests. Regenerating the
relief would invalidate all of those for little visual gain: the repetitiveness was in the cover and the materials, not in the
heights. **Decision: relief unchanged** (also in the candidate, which reuses the reference Terrain3D height maps byte for byte).

## 4. Regional variation

Reference: one forest type, one meadow colour, one field palette everywhere.

Candidate (`cover_v2` in `tools/terrain_ref/layout_ref03_visual02.json`) — soft zones plus the environment:

| Region | Where | What it does |
|---|---|---|
| Spruce forestry | SW, NE slope, SE, W | dense spruce, frequent clear-cuts and regrowth stands |
| Pine moors | Vestheia, Nordvest-åsen, Østheia, Søråsen (the rocky hills) | open old pine on dry rock, lichen-light colour, juniper |
| Wetland | round Storvatnet, Tjernet, Langvatnet | birch, bog openings, open wet ground |
| Mountain birch | below Nordfjellet | low birch and pine, open |
| River valley / farmland | valley floor, Øst-sletta, Sør | leys, grain, ploughed parcels; woodlots and tree belts along streams instead of continuous forest |

There are no rectangles: every zone is a noise-warped ellipse with a 0.55–1.25 soft edge, and the environment (moisture,
dryness, elevation) does most of the work. [RUN] Candidate forest: **15 % pine, 66 % spruce, 19 % birch**, by place.

## 5. Vegetation analysis

| | Reference | Candidate |
|---|---|---|
| Trees planted | 5.82 M | 4.47 M + 0.33 M saplings (no collider) |
| Species | pine 71 / spruce 20 / birch 9 % everywhere | pine 15 / spruce 66 / birch 19 %, by site |
| Placement | jittered 6.5 m grid, p = density | 4 m candidates × clumping noise (15–60 m groups and gaps), min. trunk distance by size |
| Sizes | random 0.7–1.3 | by stand age (regrowth 0.42–0.7, mature 0.9–1.2), smaller at edges and on rock |
| Forest edges | wall of trunks | 20–60 m band of thinner, younger trees, more birch |
| Clear-cuts | none | 6.9 % of the forest: grass + slash patches, stumps, saplings, a few seed trees |
| Deadwood | uniform | stumps on clear-cuts, more logs in old stands |
| Outcrops | lying on any slope | none on rock faces > ~30° (the rock texture is the face) |
| NN spacing CV (sample) | 0.435 | 0.451 |

[NOTE] The nearest-neighbour coefficient changed less than expected because the sample (the first cell with ≥ 50 trees per
fourth chunk) lands mostly in closed interior stands where both methods are near their minimum spacing; the group / gap
structure shows at 20–100 m (screenshots 02, 03, 13, 15), not in nearest-neighbour distance.

Gameplay rules kept: every tree that can stop a soldier or a vehicle is one of the six collider species (unchanged
`collider` values, read by `InstanceColliderStreamer` and `StructureManager.blocks_trunk`); saplings are new library entries
22–23 **without** a collider (a 1–2 m spruce or birch is not cover and must not block a vehicle). Road, building and water
clearances are the reference values.

## 6. Terrain material improvements (in the reference world now)

`shaders/world/terrain_visual02.gdshader` = Terrain3D 1.0.2's generated default shader (vertex, normals, texture blending
untouched) + four additions, applied by `GroundLook` (`scripts/world/ground_look.gd`) at game start in memory like
`WorldLook`; `--legacy-ground` keeps the old shader.

1. **Colour map** read through a 2-scale noise warp (±6 texels ≈ 12 m) and a blurred mip, contrast 0.86, saturation 0.80: field
   and forest outlines become irregular and soft.
2. **Open ground** (meadow + field texture weight) gets regional dry / lush (2.6 km), patches (290 m) and clumps (37 m), drier
   on slopes; meadow albedo pulled from lime to a muted green (saturation 0.74, brightness 0.90); dark open ground (where the
   grass tufts draw dwarf shrubs) gets a heath tone so the tuft ring does not end in a light edge.
3. **Field parcels**: the generator paints a parcel one flat colour, so that colour (nearest texel) is the parcel's identity:
   row direction and crop. Grain = straw with fine rows and tramlines (21 m), ley = green with mowing bands (9 m), tilled = soil
   with furrows; rows fade out by pixel footprint (no aliasing from the air). Alpine heath (field over rock) is excluded.
4. **Distant forest**: forest-floor weight becomes a canopy colour beyond 300–1000 m with crowns (8 m), groups (35 m) and stands
   (180 m), tinted by the colour map's species colour. From the tactical camera the forest no longer stops at the tree ring.

Plus rock lichen / weathering. Cost: one 512² noise texture, ~12 extra texture lookups per terrain pixel. The grass tufts
(`shaders/environment/grass_tuft.gdshader`) get the same colour treatment, computed once per tuft in the vertex shader.

Texture fixes (bug 1): `forest_floor`, `gravel`, `bog`, `asphalt` (_alb_ht and _nrm_rgh) regenerated with
`make_terrain_textures.py`; the eight foliage alpha textures with `make_env_textures.py`. Byte-identical to the committed
files wherever alpha was 255.

## 7. Asset improvements (in the reference world now)

| Asset | Before (LOD0 / LOD1 tris, materials) | After |
|---|---|---|
| House (771 settlement records share house / barn / shed) | 502 / 34, 5 flat colours, painted windows | **364 / 76**, 6 textured: weatherboard, pantile roof, stone plinth, trim, window and door panels (windows also on LOD1) |
| Barn | 364 / 34, 7 | **236 / 60**, board-and-batten, corrugated roof, stone ramp walls, timber ramp deck |
| Shed | 166 / 34, 6 | **116 / 44** |
| Skigard fence | 162 / 102, flat | 162 / 102, weathered grey wood with grain along the rails |

`shaders/environment/building.gdshader`: the MultiMesh instance colour (the settlement layer's paints: white, cream, yellow,
red ochre, pale blue) tints only the siding and the door (`tint_strength`), roofs / stone / glass / trim keep their own
colour; barns and sheds are Falu red with a 25 % hint of the instance colour; AO and a little splash dirt from the height above
the ground. Collision is unchanged (library colliders by mesh id). Same footprint, origin and front, so the settlement layer
and the WorldOverrides records apply as before.

## 8. Blender production details

- Textures: `tools/blender/env/make_building_textures.py` (procedural, tileable, 1024², metric tiles: siding 2 m, roof 2 m,
  stone 2 m, wood 1 m; window and door panels UV 0..1).
- Geometry: `tools/blender/env/make_structures.py` — `Builder` (box builder with UVs in texture tiles), `textured_building`
  (same footprints as before), gables wound outward (they were inward), corner boards stop under the eaves.
- Run: `blender -b --factory-startup --python tools/blender/env/make_structures.py -- --only=house,barn,shed,fence`, then
  `Godot --headless --import` and `tools/terrain_ref/import_env_assets.gd -- --only=house,barn,shed,fence` (binds the `Bld_*`
  materials to the building shader by name, table `BUILDING`).
- Inspected: Blender previews `docs/terrain01/blender_previews/{house,barn,shed,fence}_lod0_v*.png`; in game
  `docs/visual02/settlements/` and views 06 / 06b / 12.
- [NOTE] These four env assets come from the WORLD-TERRAIN-01 env pipeline (`tools/blender/env/`), not from
  `build_assets.py`; the `--qa` gate of the military library does not cover them. Checked by eye in Blender and Godot.

## 9. Before / after screenshots

`docs/visual02/`:

| Folder | Content |
|---|---|
| `baseline/` | the 17 survey images before any change |
| `terrain/` | iterations of the ground shader (reference world) |
| `settlements/` | village views with the new buildings |
| `vegetation/` | candidate forest views |
| `final/` | reference world with everything that is in it now (`*_final.jpg`) |
| `candidate/` | candidate world (`*_candidate.jpg`) |
| `comparison/` | per view one sheet: **left baseline · middle reference now · right candidate** |
| `fps/`, `rts/` | the comparison sheets of the first-person and tactical views |

## 10–12. FPS, RTS and high-altitude comparison

- **FPS** (`fps/`): meadow tufts and ground now one colour (no ring); dense forest (02) in the candidate is mixed spruce / birch
  with undergrowth and varied tree sizes instead of a pine colonnade; village street (06b) shows siding, roofs and windows;
  road through forest (07) has birch and shrub at the edge.
- **RTS** (`rts/`): fields read as fields (rows, tramlines, different crops), forest outlines are soft, the start valley is
  less "painted"; base view (12) and 13b: the start valley's parcels are drawn as fields (one of them ploughed soil) — darker and
  browner than the old lime.
- **High altitude** (13, 15): reference now shows canopy instead of bare floor beyond the tree ring, but its forests are still
  one block; the candidate adds clear-cut mosaics, lighter pine moors, birch wetlands and farmed valley floors — the
  regions are recognisable from the air.

## 13. Performance

[RUN] vsync off, 1920×1080, same build, GPU not shared with another Godot run (agreed with the parallel GAMEPLAY-05B session),
frames per second per view (2 s after 5 s of streaming), three runs back to back:

| View | legacy ground | reference now | candidate |
|---|---:|---:|---:|
| 01 meadow | 378 | 366 | 376 |
| 02 dense forest | 127 | 125 | 170 |
| 03 sparse forest | 246 | 238 | 155 |
| 04 forest edge | 167 | 168 | 102 |
| 05 farmland | 320 | 314 | 295 |
| 06 settlement | 290 | 283 | 277 |
| 07 road / forest | 121 | 121 | 175 |
| 09 river | 314 | 297 | 309 |
| 10 foothills | 152 | 146 | 316 |
| 11 valley | 192 | 190 | 265 |
| 12 base (RTS) | 252 | 246 | 249 |
| 13 RTS 900 m | 274 | 258 | 285 |
| 13b RTS valley | 344 | 321 | 313 |
| 14 first person | 251 | 207 | 229 |
| 15 long distance | 143 | 142 | 156 |

- The ground shader costs **1–6 %** in terrain-dominated views (≈ 0.1–0.25 ms per frame).
- First person cost 18 % in that run: the grass tufts did the ground-colour work per pixel. Moved to the vertex shader (per
  tuft) after the measurement; *not re-measured* (the shared GPU was busy) — see §16.
- Candidate: same order of cost overall; forest views differ because the place itself differs (the 02 / 07 cameras now stand in
  mixed stands, 03 / 04 in dense young spruce). Draw calls +5–20 % in forest views (two sapling types, more birch).
- Buildings: fewer triangles than before, one material more per asset (6 vs 5 for the house).

## 14. World-generation recommendations and the candidate world

**Why a regeneration is needed for vegetation**: the trees are stored in 400 manifest-locked chunk files (`worlds/ref_20km/
vegetation/`), the species / density / clear-cut information in `vegetation.png` + the new `stand.png`, the colour and ground
paint in the Terrain3D regions. None of it can be changed in memory without a second vegetation system (forbidden).

**What changes** (`worlds/ref_20km_visual02/`, git-ignored, 1.7 GB): `source/` (vegetation, info, stand, colour, control maps;
roads / sites / water copied from the reference), `terrain/` (the **reference** regions with only the colour maps and the
ground texture ids replaced: pixels whose control value is untouched since generation *and* whose both texture ids are ground
cover — road surfaces, verges, yards, river banks and lake beds keep the reference paint; heights, holes and later edits are
byte-identical), `vegetation/` (new chunks), `worlds/settlements/ref_20km_visual02.{json,overrides.json}` (the same 771
buildings, removals computed against the new chunks), `scenes/world/ref_20km_visual02.tscn` (the reference scene pointing at
the candidate folders: bridges, culverts, water, roads identical) and `scenes/game/world_ref_20km_visual02.tscn`.

**Impact**: relief, roads, bridges, settlements, bases, the route grid (same heights, same cache key `ref_20km`) — unchanged.
Forest cover changes place by place (in the New Game start valley the tree belt west of the start becomes a few scattered
spruce; objectives elsewhere stand in different cover); tree counts −23 %; vehicle cross-country legs meet different trunks.

**Reproduce**:

```bash
BPY="/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe"
"$BPY" tools/terrain_ref/generate.py --layout tools/terrain_ref/layout_ref03_visual02.json --out worlds/ref_20km_visual02/source
cp worlds/ref_20km/source/{roads,sites,water}.json worlds/ref_20km_visual02/source/ && rm worlds/ref_20km_visual02/source/height.r32
../Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/visual02/build_candidate.gd
../Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/settlement_proto/build_overrides.gd -- --world=ref_20km_visual02
```

(~12 + 8 + 1 min). Why the copies: running the unchanged generator today reproduces `color.rgba8` and `water.json` byte for
byte, but not the heights (0.15 % of pixels, up to 7.7 m) nor `roads.json` (124 roads in the reference: later edits and the
settlement layer's road set) — the candidate must take the reference relief and roads, not regenerate them.

**Load it**: `Godot --path . res://scenes/game/world_ref_20km_visual02.tscn` (all game modes, `--scenario=new_game`, tests).

**Adopting it** (needs approval): copy `source/{vegetation,info,stand,color,control}`, `terrain/`, `vegetation/` over the
reference, `ref_20km_visual02.overrides.json` → `ref_20km.overrides.json`, re-create the manifest, then run the navigation and
vehicle suites (`--navigation-n1b-test`, `--ai-war-test --only r_*`) on it — they were not run on the candidate.

Other recommendations: (a) keep `cover_v2` as the cover model of any future world; (b) the colour map should carry no straight
parcel edges at all — the shader now works around them; a generator-side soft parcel edge would let the shader drop its warp;
(c) roads (§16).

## 15. Gameplay compatibility

- Reference world: no navigation input changed (no chunk, height, road or collider). Logs of all survey runs free of errors.
- Buildings: same footprints / colliders. Grass and terrain: visual only.
- Candidate: colliders follow the same species rules; saplings non-blocking; clearances unchanged; vehicle / infantry
  navigation suites **not yet run** on it (§14).
- `scripts/debug/visual02_selftest.gd` (`--visual02-test --only survey|veg_stats [--views=05,13_] [--shots] [--shot-tag=]`).

## 16. Remaining limitations

- Grass-tuft optimisation (§13) not re-measured.
- Forest interiors are very dark (both worlds; worse in the candidate's dense young spruce). An ambient / sky-light lift under
  canopy belongs to a lighting pass, not done here.
- Roads (§7 of the brief) not reworked: verges, ditches and road classes keep the WORLD-TERRAIN-01 paint; river banks still
  show a saw-tooth dirt edge.
- Ground clutter (§6 of the brief) only through the candidate's scatter (stumps, slash, saplings, shrubs on clear-cuts); no new
  prop types (branches, pebbles, tyre tracks).
- Military utility buildings and the checkpoint / depot (white boxes from above) not touched.
- The env-asset pipeline has no QA gate.
- Plateaus stay open meadows (they are the base sites).

## 17. Proposed next visual milestones

1. **Approve / adopt the candidate**, with the navigation suites on it.
2. **Roads and banks**: road-class-specific verges (asphalt edge wear, gravel shoulders, grass in the centre of tracks), ditches
   as ground paint + tufts, river bank material.
3. **Lighting under canopy and backlight** (dark forests, black soldiers against bright grass).
4. **Military structures art pass** (checkpoint, depot, utility buildings) with the building shader.
5. **Ground clutter props** (branches, pebbles, tyre ruts) as contextual scatter.

## 18. Commits

| Commit | Content |
|---|---|
| `4101d0b` | straight alpha in the texture writers; regenerated terrain and foliage textures |
| `0b852ca` | ground shader (`GroundLook`), grass colour match, `--visual02-test` |
| `b6e3337` | textured houses, barns, sheds, fences; building shader |
| `f7e7aa5` | cover model v2, scatter v2, candidate world tooling, generator alpha fix |
| `d4e1a69` | report, README, screenshots |
