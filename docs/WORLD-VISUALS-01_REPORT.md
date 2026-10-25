# WORLD-VISUALS-01 — Scandinavian environment visual overhaul

Branch `develop`. Markers: **[RUN]** measured / inspected in the real game at 1920×1080; **[CODE]** read in the source;
**[NOTE]** judgement. Screenshots in `docs/world_visuals01/` (`before/`, `after/`, `comparison/`, `blender/`, `cards/`,
`surfaces/`). The world `ref_20km` is **unchanged** (`world_manifest.py verify` OK): every change is in the asset library,
shaders and the in-memory look applied at game start. (Report name follows the project convention `docs/<MILESTONE>_REPORT.md`.)

## Summary

**Verified in the game [RUN]:** the environment of `ref_20km` is rebuilt from the ground up without touching the world's
data. 24 tree variants (Norway spruce, Scots pine, birch, saplings) built in Blender from CC0 scanned sprigs and bark, each
library tree id drawing several variants chosen per instance, with a mid LOD and per-id impostor atlases; 30 rock, stump,
log, bush and fern variants; eight ground plants chosen by soil and forest type; scanned ground textures at a real scale
(moss-and-needle forest floor, lichen granite, sphagnum bog, heath, gravel); gravel road verges; darker Nordic water; a
lighting pass (AgX, limited eye adaptation, sky light) that turns the near-black forest interiors into readable woodland.
Survey of 20 fixed views before / after (`docs/world_visuals01/comparison/`), FPS measured in three runs.

**Unchanged by design:** heights, roads, bridges, water, settlements, bases, vegetation placement, colliders and
navigation inputs (`world_manifest.py verify` OK). Navigation, sight-line and grass-concealment checks pass; a new streamer
check proves every stored instance is drawn exactly once with its variant.

**Not done / limits:** vegetation placement was not regenerated (needs approval; §11); 5 of 12 grass/heather targets;
the 900 m RTS view is still hazy; dense forest views cost 5-20 % more frame time (75-136 FPS on the RTX 3070); EW02's slow
override cases c2-c4 were not completed (c1 passes).

## 1. Existing systems inspected (audit)

| System | Owner / files | Finding | Decision |
|---|---|---|---|
| Terrain material | Terrain3D 1.0.2, `worlds/ref_20km/terrain_assets.tres` (8 textures), `GroundLook` + `shaders/world/terrain_visual02.gdshader` | Two ambientCG scans (meadow = field = Ground037, rock = Rock023) and four procedural textures; stretched to 9-16 m per tile (uv 0.06-0.18); the colour map multiplies everything | **Replace the 8 textures in memory** (GroundLook), keep the shader; scans at 2.5-3 m per tile |
| Trees, bushes, rocks | `VegetationStreamer` (1024 m chunks, 128 m cells, one MultiMesh per cell and mesh id), `nordic_library.tres` (23 ids), `tools/blender/env/make_trees.py`, `make_rocks.py` | One mesh per id (two per species), sparse "lollipop" pines with a hard bark-colour band, spruce as a few flat sprays, birch as dense round blobs; impostors per id; two LODs | **Keep ids, colliders and chunk data**; replace the meshes; add **variants per id** and a **mid LOD** to the streamer |
| Placement | `worlds/ref_20km/vegetation/` (400 manifest-locked chunks, cover model v2 of VISUAL-02, adopted the same day) | Already ecological: species by site, stands, clear-cuts, edges, 549k ferns, 467k shrubs, 436k junipers, 260k stumps, 211k logs, 96k stone clusters, 62k boulders, 330k saplings ([RUN] `--visual02-test --only veg_stats`) | **Not regenerated** (CLAUDE.md: no world regeneration without approval; navigation tests depend on it). Distribution work is in the ground cover and the variants |
| Ground cover | `GrassLayer` (GPU particles from the Terrain3D maps), `grass_particles.gdshader`, `grass_tuft.gdshader` | One grass tuft and one dwarf-shrub texture | **Extend** the same layer: 8 plants chosen per particle by ground |
| Lighting | `WorldLook` (GAMEPLAY-05): ACES, SSAO 1.6, fog 1.6e-4, sun 1.15 | Forest interiors near black; green tints saturated | **Extend** WorldLook (AgX, limited eye adaptation, sky light, softer SSAO) |
| Water | `shaders/world/water.gdshader`, `assets/environment/water/*.tres` | Saturated blue paint | Re-tint, shallow transparency |
| Roads | Road Generator meshes, `RoadShoulders`, grass mask (`VegetationMask`) | Grass ran straight to the asphalt | Gravel verge in the ground shader from the existing road mask |
| Collision / navigation | `InstanceColliderStreamer`, `StructureManager.blocks_trunk`, `LineOfFire` read **library collider values by mesh id** through `get_cell_instances` | Independent of the meshes drawn | Unchanged by design; variants keep each id's trunk radius / footprint |

## 2. References

`docs/world_visuals01/REFERENCES.md`: Norwegian forest types (SNL), Norway spruce crown architecture, Scots pine bark and
crown, mountain / multi-stem birch, Arma Reforger environment observations, forest rendering practice. Source assets: CC0
scans from Poly Haven (downloads approved by the product owner during the task), fetched by
`tools/blender/env/fetch_polyhaven.py` into the git-ignored `assets/environment/source/polyhaven/` (licence / author record
`sources.json`).

## 3. Assets created

All built by scripts (reproducible from seeds and the CC0 sources), inspected in Blender previews
(`docs/world_visuals01/blender/<asset>_pv_v0/1.png`, ground level and from above) and in the game.

| Family | Library id(s) | Variants | LOD0 / mid / far triangles | Builder |
|---|---|---:|---|---|
| Norway spruce (narrow, broad, forest-grown with dead lower stem, open-grown to the ground, drooping comb, leaning) | 3 | 6 | 10-14k / 1.1-2.2k / 8 (impostor atlas) | `make_trees_v3.py` |
| Young spruce | 4 | 3 | 4.5-4.9k / 0.4-0.5k / 8 | `make_trees_v3.py` |
| Spruce saplings (no collider) | 22 | 2 | 2.7-3.3k / 0.3k / 8 | `make_trees_v3.py` |
| Scots pine, middle-aged rounded crown | 1 | 3 | 5.6-7.7k / 2.2-3.0k / 8 | `make_trees_v3.py` |
| Scots pine, old flat crown on a long clear stem | 2 | 3 | 5.2-7.9k / 3.2-4.8k / 8 | `make_trees_v3.py` |
| Birch, single stem, weeping twigs | 5 | 3 | 1.8-1.9k / 1.3-1.5k / 8 | `make_trees_v3.py` |
| Birch, multi-stem | 6 | 2 | 2.4-3.6k / 1.6-2.5k / 8 | `make_trees_v3.py` |
| Birch saplings (no collider) | 23 | 2 | 1.3-2.0k / 0.9-1.3k / 8 | `make_trees_v3.py` |
| Juniper (columnar, spreading, tall) | 7 | 3 | card bushes | `make_trees_v3.py` |
| Shrubs (sallow, rowan, birch scrub, mixed, low scrub) | 8 | 5 | card bushes | `make_trees_v3.py` |
| Ferns (arching frond strips) | 15 | 4 | 48-80 / 24-40 | `make_trees_v3.py` |
| Large granite blocks | 9 | 3 | 1.8k / 0.22k | `make_props_v3.py` (rock_moss_set_01/02 scans) |
| Medium blocks | 10 | 3 | 1.4k / 0.18k | `make_props_v3.py` |
| Bedrock slabs / outcrops | 12 | 3 | 2.4k / 0.3k | `make_props_v3.py` |
| Small stone clusters | 11 | 12 | 0.9k / 0.12-0.18k | `make_props_v3.py` (rock_moss_set_02, rock_07, rock_09, stone_01) |
| Stumps | 14 | 3 | 1.5k / 0.2k | `make_props_v3.py` (tree_stump_01/02) |
| Fallen trunks and a slash pile | 13 | 3 | 1.6k / 0.2-0.9k | `make_props_v3.py` (dead_tree_trunk/_02, dry_branches) |
| Ground plants (meadow grass, grass with flowers, wavy hair-grass, heather, bilberry, lingonberry, fern, sedge with cotton grass) | grass layer | 8 | particle cards | `make_cards_v3.py` |

**63 placed 3D variants + 8 ground plant types = 71** against the brief's 74 targets. By family: spruce 6 (target 6),
pine 6 (6), birch 5 (5), young trees 7 (5), bushes 8 (8), small rocks 12 (12), large rocks 6 + 3 outcrops (6), stumps and
deadwood 6 (6), grass and heather 5 (12: **under target**), ferns and small plants 4 fern meshes + bilberry, lingonberry and
fern particles (8). [NOTE] Grass types were kept to what the ground rules can place meaningfully; more grass tiles would
only add near-identical cards.

Card atlases (`make_cards_v3.py`, `docs/world_visuals01/cards/`): `spruce3` (four branch sprays composited from ~20 scanned
fir sprigs each, re-graded to Norway spruce green), `pine3` (four branch ends with 7-9 Scots pine needle tufts), `birch3`
(four hanging twig curtains with serrated leaves), `bush3`, `fern3` (pinnate fronds), `ground3` (eight side-view plants).
Each card has a normal map from its sprig orientations and colour bled into the transparent area (no dark mip fringes).

Tree construction (`make_trees_v3.py`): species skeletons from the references - spruce whorls of 5-7 branches that sag and
turn up, 2-3 cards per 1.1 m of branch and hanging branchlet cards; pine with a self-pruned clear stem, ascending limbs and
upturned tufts; birch with ascending limbs, twig curtains and a dark fissured base sleeve. Trunk base radius per id is the
old one, so `InstanceColliderStreamer`, `StructureManager.blocks_trunk` and `LineOfFire` (which read the library's collider
values by id, not the mesh) stay correct for every variant. **Mid LOD**: the same tree with 35 % of its foliage cards
(enlarged ×1.45 about their centres so the crown keeps its cover), without dead twigs and thin branches - generated from
LOD0, so the silhouette does not jump at the switch. **Far LOD**: one impostor mesh per id (three crossed cards + a top card)
drawn by `impostor_v3.gdshader`, which takes the variant's tile of a 3 × 2 atlas (side and top renders of every variant) and
its size from the instance.

Rocks / deadwood (`make_props_v3.py`): scan meshes decimated to budget, scaled to the **old asset's size** (read from the
committed GLB of the previous version, so boulders stay inside their collider spheres), sunk 5-45 % into the ground, one
shared 1K texture set per scan. In the game `scan_prop.gdshader` grades the scanned sandstone to grey granite / gneiss and
adds moss on faces turned to the sky and pale crustose lichen.

## 4. Materials

| Surface | Before | After |
|---|---|---|
| Meadow | Ground037 at 9 m per tile, lime tint | leafy_grass scan, 2.9 m per tile, calibrated tint |
| Field / heath | Ground037 (same as meadow) | sparse_grass scan graded to dry heath |
| Forest floor | procedural brown with green blobs | **composite**: feather-moss carpet (rocky_terrain_02, olive grade) + humus with drawn spruce needle litter (mud_forest), mixed by a tileable two-scale mask with height blending |
| Rock | Rock023 (grey layered slate), 16 m per tile | mossy_rock scan (granite / gneiss with lichen), 6 m per tile |
| Dirt | procedural smear | forest_ground_04 (soil with small stones) |
| Gravel | procedural flat | rocky_trail (grey gravel) |
| Bog | procedural olive blotches | **composite**: sphagnum (graded yellow-green / red-brown) with wet dark peat hollows (low roughness) |
| Bark | procedural blobs; pine split hard at 42 % of the height | pine_bark scan: grey plates below, orange flakes above, **blended by height with an irregular tongue edge** (`bark.gdshader`); spruce: the same plates at half size, greyed; birch base: bark_brown_02 dark grey |

All terrain textures are 2048² (Terrain3D needs equal sizes), albedo + height and normal + roughness packed as Terrain3D
expects, made by `make_surfaces_v3.py`. They replace the world's textures **in memory** in `GroundLook` (a freshly loaded
copy of `terrain_assets.tres` with the new files; Terrain3D's `free_editor_textures` has to be off, otherwise it reloads the
asset file on any change and drops the new textures - this keeps the sources in RAM, ~90 MB). Tints are calibrated so each
surface keeps about the mean colour of the old one under the world's colour map. `--legacy-ground` keeps the old set.

Road verges (`terrain_visual02.gdshader`): the grass layer's road mask (`VegetationMask`, 2 m texels) becomes a gravel / dirt
shoulder of 1-2 m beyond the asphalt with a noisy edge; the shader follows later mask changes through the new
`GrassLayer.mask_applied` signal.

Water (`water.gdshader`, `water_*.tres`): dark, slightly humic fresh water (brown shallows, dark teal depth), shallow water
more transparent (bottom visible near the bank), colour by view angle.

## 5. Vegetation and ground cover

- **Variants per id** (`VegetationMeshDef.variants`, `VegetationStreamer._split_variants`): each stored instance draws one
  variant chosen by an integer hash of its position (stable across runs and machines). Chunk data, ids, instance indices and
  `WorldOverrides` records are untouched (overrides bind to the hash of the chunk *file*).
- **Three LOD levels** for trees (`VegetationMeshDef.mid_range`, `lod_at`): near (full) to 20-40 m, mid to 45-110 m,
  impostor beyond; near and mid cast shadows.
- **Ground cover** (`grass_particles.gdshader`, `plant_types`): each particle picks one of the eight plants from the terrain
  texture under it - bog: sedge / cotton grass; forest floor or forest tint: bilberry carpet, lingonberry / heather /
  hair-grass on dry patches, ferns in moist patches; dark heath: heather, hair-grass, lingonberry; rock and gravel:
  hair-grass and heather; meadow: grass with flower patches and hair-grass on the dry side (SNL forest types). Placement,
  density and height are unchanged, so `Concealment` (which mirrors them) is unaffected.

## 6. Lighting and atmosphere (`WorldLook._nordic_light`)

AgX tonemapping instead of ACES (greens no longer neon, highlights roll off), limited eye adaptation
(`CameraAttributesPractical`, sensitivity 95-165: shade brightens up to ~1.7×, open sunlit land stays about where it was),
sky light energy 1.25, SSAO 1.15 / power 1.2 (was 1.6 / 1.4 and blackened every foliage card), glow only above HDR 1.3,
haze 1.2e-4 (was 1.6e-4; the adapted view from 900 m was milky), sun 1.2 with a slightly larger disc. Foliage card AO
raised (minimum 0.6 instead of 0.45). The ground shader's distant canopy starts at 150 m (was 300 m): the scanned litter
floor showed brown between tree tops from above. `--legacy-look` keeps GAMEPLAY-05's light.

## 7. Water, shorelines and roads

- Water [RUN, views 09 / 18]: lakes and the river read as dark Nordic fresh water instead of saturated blue; shallows show
  the bottom near the bank. No new effect, no cost change.
- Shores: the bank vegetation is now the ground-cover mix (sedge / hair-grass / bilberry by the soil) instead of one dwarf
  shrub; [NOTE] the generated colour map's saw-tooth dirt band along the river (VISUAL-02 §16) is still visible.
- Roads [RUN, views 07 / 08 / 12]: a narrow worn gravel / dirt shoulder now separates the asphalt from the grass; road
  geometry, `RoadNetwork` and `RoadShoulders` untouched.

## 8. Before / after

Fixed views of `--visual02-test --only survey` (VISUAL-02's 15 views + two new ones: 17 rocky pine hillside on Vestheia,
18 lakeshore at Langvatnet), 1920×1080, same light, HUD hidden for the world views. `docs/world_visuals01/before/`,
`after/`, side by side in `comparison/<view>.jpg`. Brief's seven views: dense forest (02), open grassland (01), forest road
(07), rocky hillside (17), lakeshore / river (18 / 09), elevated RTS (13b, 12, 13 at 900 m), ground-level FPS (14).

[RUN] What changed, judged on the screenshots:
- **Forest interiors (02, 03, 04)**: from near-black to readable; spruce now dense cones with hanging branchlets, birch with
  weeping twig curtains, Scots pine with an orange upper stem; a forest floor of moss and needle litter with bilberry,
  lingonberry, ferns and hair-grass instead of one repeated dwarf shrub on brown.
- **Rocky hillside (17)**: grey lichen-covered granite instead of a smooth shiny slate; old pine with orange upper bark.
- **Open land (01, 14)**: grass ground at a real scale (no 9 m stretch), the grass ring edge matched; trees at the field
  edge are recognisably spruce / birch / pine.
- **Roads (07, 08)**: gravel shoulders; roadside trees of mixed species and sizes.
- **Water (09, 18)**: darker, natural fresh water.
- **Distance (15, 11)**: impostors carry the variant shapes; forests read as stands of individual conifers.
- **RTS (12, 13b, 13)**: fields and forest edges as before; from 900 m the view is still hazy and the forest inside the tree
  ring looks speckled (impostor tops over the litter floor) - see §11.

## 9. Performance

[RUN] vsync off, 1920×1080, RTX 3070, frames per second 2 s after 5 s of streaming per view. "Before" is one run at the
start of the task (on the then-current `develop`, the other session's game was possibly running at the same time - several
before values, e.g. 01 and 07, are far below VISUAL-02's measurements of the same views); "after" two runs of the final
build (a third run of the same assets: within 1-3 % except 04 at 89); "no variants" = the final build with `--veg-no-variants` (every instance draws variant 0).

| View | before | after (run 1 / run 2) | no variants | draw calls before → after | primitives before → after |
|---|---:|---:|---:|---:|---:|
| 01 meadow | 158 | 315 / 317 | 315 | 392 → 479 | 0.93 M → 0.97 M |
| 02 dense forest | 141 | 136 / 134 | 131 | 4041 → 4562 | 1.84 M → 2.75 M |
| 03 sparse forest (mixed stand) | 154 | 118 / 122 | 115 | 1523 → 2153 | 1.35 M → 2.18 M |
| 04 forest edge (dense spruce) | 92 | 78 / 88 | 82 | 2701 → 3258 | 1.80 M → 2.67 M |
| 05 farmland | 278 | 269 / 268 | 270 | 1263 → 1270 | 1.05 M → 1.07 M |
| 06 settlement | 207 | 241 / 249 | 253 | 2487 → 2571 | 1.55 M → 1.54 M |
| 06b village street | 253 | 278 / 278 | 271 | 2676 → 2760 | 1.69 M → 1.82 M |
| 07 road through forest | 66 | 185 / 184 | 167 | 1267 → 1829 | 1.47 M → 2.11 M |
| 08 road, open | 189 | 292 / 294 | 299 | 2531 → 2655 | 1.34 M → 1.32 M |
| 09 river | 300 | 276 / 278 | 276 | 1480 → 1540 | 1.10 M → 1.13 M |
| 10 foothills | 313 | 289 / 286 | 283 | 1099 → 1255 | 1.19 M → 1.22 M |
| 11 valley | 273 | 266 / 270 | 272 | 2891 → 2923 | 1.21 M → 1.22 M |
| 12 base, tactical camera | 183 | 232 / 232 | 230 | - | - |
| 13 RTS 900 m | 283 | 253 / 253 | 255 | 319 → 323 | 0.68 M → 0.69 M |
| 13b RTS over the start valley | 255 | 265 / 266 | 266 | - | - |
| 14 first person | 164 | 192 / 194 | 197 | - | - |
| 15 long distance | 154 | 203 / 205 | 208 | 3856 → 4006 | 1.49 M → 1.54 M |
| 17 rocky hillside | 223 | 208 / 207 | 203 | 1174 → 1684 | 1.42 M → 1.70 M |
| 18 lakeshore | 277 | 248 / 247 | 223 | 1145 → 1170 | 1.11 M → 1.19 M |

[NOTE] Forest views cost more GPU work: about +50 % primitives (denser, real crowns; the full LOD within 20-40 m is
10-14k triangles per mature spruce) and +10-40 % draw calls (variants split a near / mid cell into one MultiMesh per
variant). The frame rate stays above 75 FPS in the worst view (04, dense young spruce), 118-136 in the other forest views.
Variants themselves cost nothing measurable (no-variants is within the run-to-run spread). The mid LOD was what made it fit:
before it, the same views ran at 68 (04) and 110 (03) FPS with the full tree up to 65-80 m. Open land, settlements, RTS
and the map are unchanged within noise. Memory: the 2048² terrain sources stay in RAM (~90 MB, `free_editor_textures`
off); the new textures are VRAM-compressed (BPTC).

## 10. Navigation, collision and gameplay validation

| Check | Result |
|---|---|
| World data | `world_manifest.py verify --ignore-editor-metadata`: **OK**, 536 files, 0 changed |
| Colliders / navigation inputs | [CODE] unchanged: ids, instance data and library `collider` values are the same; `get_cell_instances`, `InstanceColliderStreamer`, `StructureManager.blocks_trunk`, `LineOfFire` untouched; trunk base radii of every variant = the id's old radius; rocks scaled to the old asset's size; saplings, ferns, bushes, stones stay collider-less as before |
| Streamer draws exactly the stored instances | [RUN] new check `--visual02-test --only wv_streamer`: **PASS** - 2927 active cells with variants (66 near, 37 mid, 2824 far), 95 039 instances, drawn = stored per cell, variant 0 in the cell's own MultiMesh, far impostor codes = the hash's variant |
| Vegetation overrides / editor layer | [RUN] `--ew02-test` c1 (revision model, warm lookups, reload hash, instance at the moved site): **PASS** (twice). c2-c4/b6 not completed: the test's own reset erases override records one at a time and re-indexes the ~1700-record settlement layer for each (O(n²)); c2 needed > 25 min headless and was stopped. Instrumented: every `_go` (streaming, settling, nav bake) finished in < 1 s, the time is in the test's record reset - not related to this change |
| Sight lines and grass concealment | [RUN] `--combat01-test --only g_grass,v_detect`: **PASS** - v_detect 32 / 32 pairs visible at 120 m (no foliage blocker change), g_grass: grass height 0.2-0.3 m at the dense spot, prone noticed after 1.83 s vs 0.5 s on bare ground (the ground-plant change did not alter what conceals) |
| Infantry navigation | [RUN] `--nav-inf-test --only navinf_01,navinf_02`: **PASS** (6 / 6 arrived each, no stuck bodies, no failures) |
| Scripts | `tools/check_scripts.gd`: 188 scripts, 0 failed |
| Errors | no SCRIPT / SHADER errors in any survey run |

## 11. Known limitations and remaining issues

- **Placement unchanged.** Distribution was improved through the ground cover, variants and LODs, not by moving trees: the
  stored cover (VISUAL-02's ecological model, adopted on 2026-10-25) is manifest-locked and the navigation suites depend
  on it. Changing where trees stand needs a world rebuild with the product owner's approval and the navigation / vehicle
  suites afterwards.
- **Grass and heather: 5 of 12 target types** (§3). Bilberry / lingonberry / heather / fern particles are cards, not meshes.
- **900 m RTS view** stays hazy, and inside the tree ring the forest looks speckled from above (top impostors over the
  litter floor; the canopy colour starts at 150 m from the camera, which at that height is under the camera).
- **Birch base sleeve** has a visible upper edge at close range (separate geometry, not a shader blend).
- **Forest cost** +5-20 % frame time in dense forest views (§9). A shadow-distance or card-count budget per quality level
  would be the next lever if lower-end GPUs matter.
- **River banks**: the colour map's saw-tooth dirt edge remains (generator paint).
- **EW02 c2-c4** not completed (test runtime, §10).
- Old WORLD-TERRAIN-01 textures / materials that no asset references any more are still in `assets/environment/` (not
  deleted while another session works in the same tree).

## 12. Reproduce

```bash
python tools/blender/env/fetch_polyhaven.py                      # CC0 sources (git-ignored)
python tools/blender/env/make_surfaces_v3.py                     # terrain, bark, rock textures
python tools/blender/env/make_cards_v3.py                        # foliage / plant card atlases
"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/env/make_trees_v3.py
"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/env/make_props_v3.py
../Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
../Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/terrain_ref/import_env_assets.gd -- --only=<assets>
```

`make_props_v3.py` reads the previous assets' sizes from `assets/environment/source/old_glb/` (taken out of git with
`git show 55f7da7:assets/environment/glb/<asset>.glb`). Survey: `--scenario=new_game --visual02-test --shots --only
survey,wv_streamer --shot-dir=res://docs/world_visuals01/after --shot-tag=after`; comparisons `--legacy-ground`,
`--legacy-look`, `--veg-no-variants`.
