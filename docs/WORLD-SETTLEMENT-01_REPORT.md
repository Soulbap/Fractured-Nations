# WORLD-SETTLEMENT-01 — Haugen prototype (organic settlement)

Branch `exp/world-settlement-01` (not merged, not pushed). The canonical world is untouched
(`world_manifest.py verify --ignore-editor-metadata`: OK, 535 files, 0 changed).

**Run it:** add `--settlement-proto=haugen` after `--` (game or `tools/terrain_ref/capture.gd`), e.g.

```
Godot_v4.7.2-stable_win64.exe --path . res://scenes/game/world_ref_20km.tscn -- --settlement-proto=haugen
```

Without the flag nothing changes. Screenshots: `tools/settlement_proto/shots.sh [before|after|both]`.

## How the old pattern was made and removed

- `tools/terrain_ref/generate.py::_settlement_streets` gives every settlement a circle (`radius_km` in
  `layout_ref03.json`): towns get a 95 m street grid clipped to the circle, villages two straight "gate"
  streets. The generator also paints a round mown-grass patch with a pale colour-map tint, and
  `ReferenceWorldBuilder._plan_props` drops buildings at random inside the circle (one per 1 500 / 3 000 m²,
  9–40 m from a road, long side to the road), plus garden trees inside the circle.
- Note: the attached screenshot (95 m grid, ~600 buildings) is **Sentrum**; Haugen was the village variant
  (160 m circle, two streets, ~26 buildings). The disc, the straight streets and the even spread were the
  same problem at small scale.
- Removed in the prototype: streets `Haugen gate 1/2` (their roads.json slot stays empty so road keys and
  bridge ids do not shift), the 26 buildings and mailboxes in the circle, ~80 % of the circle's garden trees,
  and the disc itself (its texture and tint are refilled from the surrounding fields, see below).
- Kept: terrain/heights, Fv nord-sentrum, Lv haugen, bridges, rivers, forest, the `Haugen` site in
  `sites.json` and the sandbox objective (same position and radius), WarSim, navigation code, streaming.

## New Haugen

Hand-made (`tools/settlement_proto/design_haugen.py`), laid on the 5 m contours from
`tools/settlement_proto/look.py`; no generator, no grid, no circle:

- **Haugvegen** (narrow asphalt, 280 m) leaves the Fv's west arm where both lie at ground level, climbs the
  west side of the bowl along the contours and ends at the upper houses; **Bakkeli** a short dead end down
  into the bowl. The village centre is the junction: a shop-sized building and a few houses.
- **Farm roads** (gravel, dead ends): Nordre Haugen through the forest to the north fields, Austre Haugen /
  Haugen øvre east over the fields, Vestre Haugen under the wooded ridge, and **Sagvegen** to a small
  sawmill/workshop yard on Lv haugen south of the junction.
- **33 buildings** (existing house/barn/shed models): centre 6, Haugvegen/Bakkeli 9, sawmill 3, roadside
  houses 4, four farms 11. Varying setbacks (15–24 m) and yaw offsets; every building checked for slope
  and road clearance by the design script. Trees, rocks and logs under new buildings and roads are removed.
- **Ground:** the disc is refilled per vertex from the nearest of 16 field samples just outside it (wavy
  Voronoi parcels), so the surrounding fields run into the village; mown grass only as gardens round the
  buildings. Roads get asphalt/gravel with worn verges and no particle grass.

Roads follow the terrain (no grading; max grade 7–11 % on all roads except a 13 m ramp off the Fv at the
start of Haugvegen, 18 %, and the first metres of Sagvegen off Lv haugen, 14 %, where those roads sit on
their graded profile).

## Implementation (small, prototype-only)

| File | Change |
|---|---|
| `scripts/world/settlement_proto.gd` (new) | `--settlement-proto` flag, road patch, in-memory ground paint (Terrain3D control + colour map, grass mask; never saved) |
| `scripts/world/road_network.gd` | `load_world` applies the patch; roads without points are skipped |
| `scripts/vegetation/vegetation_streamer.gd` | prototype overrides file when the flag is set |
| `scripts/vegetation/world_overrides.gd` | `added` records may carry a `color` (house tints) |
| `scripts/game/core_demo.gd` | ground paint + own strategic grid cache (`user://strategic/ref_20km_grid_haugen.bin`) |
| `tools/terrain_ref/capture.gd` | ground paint when the flag is set |
| `scripts/debug/nav_perf_bc_selftest.gd` | `b_settlement` check (only with `--only b_settlement`) |
| `tools/settlement_proto/` (new) | `design_haugen.py`, `build_overrides.gd`, `look.py`, `shots_haugen.json`, `shots.sh` |
| `worlds/settlement_proto/` (new) | `haugen.json` (roads, buildings), `haugen.overrides.json` (canonical overrides + removals + 33 buildings) |

Buildings use the EDITOR-WORLD-02 override records (baseline-bound removals, added instances), so they
stream, collide and show in the editor tooling like other overrides. RoadTerrain3DConnector is not involved.

## Checks

- Visual (capture.gd, same 5 cameras before/after): `docs/world_settlement01/before|after/`
  `1_top`, `2_oblique_se`, `3_oblique_n`, `4_ground_haugvegen`, `5_ground_fv_east`.
- Navigation, `--nav-perf-bc-test --only b_settlement --settlement-proto=haugen` (game scene): **PASS**.
  Old streets gone, 6 new roads in `RoadNetwork`; four trips that start on yards only the new roads reach
  (upper Haugvegen → Fv SE 0.95 km, Fv SE → Nordre Haugen 1.18 km, Haugen øvre → Sentrum 3.17 km,
  Vestre Haugen → Lv haugen south 0.46 km): truck routes planned with `RoadAudit` check clean (no water,
  structure, closed deck or steep step), infantry routes 0 bad legs, worst 10 m grade 8 %.
- Canonical world: manifest verify OK.

## Limitations

- Prototype only: the world's `roads.json`, terrain files and canonical overrides are not changed. Moving it
  into the canonical world means writing the roads into roads.json (or keeping the patch), baking the paint
  into the Terrain3D regions and merging the override records.
- Roads are painted, not graded: on the short ramps off the Fv/Lv the surface follows the existing
  embankment. The old streets' small cut/fill under the meadow is still in the heightmap.
- The prototype overrides file copies the 3 records of the (untracked) canonical
  `worlds/ref_20km.overrides.json`; re-run `build_overrides.gd` if that file changes.
- Faint lines of no particle grass remain where the old streets were (grass mask not cleared there).
