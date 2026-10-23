# WORLD-SETTLEMENT-02 — Organic settlements for all of ref_20km (+ NAV-FINAL-01)

Branch `exp/world-settlement-01` (continues the Haugen prototype, `47612b2`), commits listed at the end. Not merged, not pushed.

## Result

All 26 generated settlements are replaced. The round settlement discs, the 91 generated streets (the 95 m grid of Sentrum and
Østby, the straight "gate" streets of the villages), the ~2 300 random buildings and the scattered garden trees are gone. In their place:
**107 new local roads (28.8 km) and 771 buildings**, laid out from the terrain and the main roads, plus an access road to Flyslette øst.

It runs in the normal game (no flag) and in `capture.gd`; `-- --no-settlements` shows the old world. The canonical world files are
not changed (`world_manifest.py verify --ignore-editor-metadata`: OK, 535 files, 0 changed).

| Place | Type | New roads | Buildings | Design |
|---|---|---|---|---|
| Sentrum | C town | 22 | 271 | dense centre along the four Fv arms at the junction, three through streets, nine side roads (some with branches), housing clusters of different density, two yards (industry/warehouses), farms on tracks, open fields between the quarters |
| Østby | B | 12 | 108 | centre at the Fv junction, five residential roads with clusters, farms, a yard |
| Ødegård, Elvetun, Strand, Moen | B | 4-9 | 27-44 | small centre on the Fv, 3 residential roads, 2 farms, a yard (Ødegård, Strand) |
| Verket | industrial | 4 | 20 | two yard roads with barns/sheds (works), one residential road, a farm |
| Haugen | A (hand-made, approved WS-01) | 6 | 33 | unchanged prototype |
| Nordvik, Bruvoll, Vestli, Åsbygda, Kvernes, Nordre, Fjellfoten, Lia, Sørli, Skogli, Sletta, Østmark, Østre, Bakken | A village | 1-4 | 7-22 | a few houses at the junction, one or two village roads, farm tracks with tun (house, barn, shed) |
| Elvebakken, Sørhaug, Grensen, Vestvatn | D hamlet | 0-1 | 3-9 | farm cluster / houses along the road / small sawmill yard |
| Flyslette øst | access road | 1 | – | 1.09 km from Lv fjellvatn, A* on an 8 m grid, max grade 9 % (no terrain work beyond the road corridor) |

Screenshots (before/after, same cameras): `docs/world_settlement02/before|after/` — `Sentrum_1top/2oblique/3ground`,
`Ostby_*`, `Odegard_*`, `Verket_*`, `Nordvik_*`, `Sletta_*`, `Fjellfoten_*`, `Lia_*`, `Strand_*`, `Bruvoll_*`, `Flyslette_road`;
movement: `docs/world_settlement02/movement/`.

## How it is built (small, reuses Haugen)

* `tools/settlement_proto/design_settlements.py` — not a generator framework: per place a short plan (type and counts); roads start on
  a vertex of an existing road and are walked out in 6 m steps towards the flattest dry ground and away from other roads (dead ends,
  farm tracks, yard roads); buildings in clusters with gaps along them, farms as a tun at the end of a track; each building is checked
  for slope, water, road clearance and overlap.
* `tools/settlement_proto/paint_settlements.py` — ground and heights, the Haugen rules for every place: the old disc (the generator's
  own settlement mask, soft dithered edge) is refilled from the ground just outside it; the old streets get the ground right beside
  them; gardens round the houses; road surfaces. Heights: the old streets' cut/fill corridors (up to 15 m in Sentrum) are smoothed back
  into the terrain, the small-scale relief the generator left out of the flattened discs is put back, and every new road is graded
  like the generator's own roads (grade-limited profile pinned on the road it leaves, narrow cut/fill corridor; steep dead-end tails cut).
* `tools/settlement_proto/build_overrides.gd` — the buildings and removals as a world-overrides **layer**.
* Runtime `scripts/world/settlement_layer.gd`: roads into the one `RoadNetwork` (removed streets keep their slot: road keys and bridge
  ids do not move); heights and paint into Terrain3DData in memory at game start (1.5 s, never saved); grass mask.
* `WorldOverrides`: optional read-only layer under the user's own file; user records win on the same id, saving writes only the
  user's records, erasing a layer record saves it as removed. Checked with the real file: user 3 records + layer 11 537 → merged
  11 540, all user records intact, the saved file equals the user's (`tools/settlement_proto/check_overrides_layer.gd`).
* Old generation off for future rebuilds: `layout_ref03.json` `"settlement_layer": true` → `generate.py` skips the street grids,
  `ReferenceWorldBuilder` skips the random settlement buildings (not run: a rebuild was not needed).
* Fix found on the way: `VegetationStreamer._cell_distance` read an empty buffer when overrides removed every instance of a mesh in
  a cell (script errors, no crash).

## Navigation Final Validation

All in the normal game scene (settlement layer on), with the existing diagnostics (`--nav-perf-bc-test`, `RoadAudit`):

| Check | Run | Result |
|---|---|---|
| Road network | `--only b_settlement` | **PASS** — 0 generated streets left (the 17 disconnected village-street components are gone with them), 107 new roads, every one starts on another road (0 unlinked), none steeper than 16 % over 24 m, 4 bridges traversable, objectives Sentrum/Østby/Verket/Elvetun/Haugen/Ødegård present |
| Reachability | same | **0 unreachable settlements**: a truck plans a clean route (no water, structure or closed deck) from a new road end in every one of the 25 other places to Sentrum (3.4-17.8 km), infantry gets a feasible route from all 26; Flyslette øst reachable by truck over its new access road |
| Infantry, near | `b_settlement_move` | **PASS** — squad of 6 across Sentrum (660 m, bodies + navmesh round the new houses): 6/6 arrived in 191 s, 0 stalls, 0 inside buildings, 2 member recoveries |
| Infantry, long | same | **PASS** — squad of 6 Østby -> Sentrum (abstract tier, 1 426 s): 6/6 arrived, 0 stalls, 0 jumps, 19 local recoveries / 3 repairs (normal) |
| Vehicles | same | **PASS** — truck from the main road into Østby to the end of a new village road (79 s), then out and over the river bridge (`bridge_r4_s0`) to the end of a new street in Sentrum (460 s): both arrived (1 m), 0 stops, 0 jumps, 0 recoveries/replans, never inside a building footprint. Screenshots `movement/navperf_ws02_truck_*`, `movement/navinf_ws02_sentrum_*` |
| Bridges | `b_settlement` + truck leg | **PASS** — 4/4 traversable, truck crossed one |
| RouteService | `--only c_vehicle,c_pending` | **PASS** — pending -> route -> moving for squads and vehicles, newer order wins, Hold/halt drop the pending answer, operation waits for its routes, a convoy forms from the leader's route |
| Convoy hand-back (NAV-PERF-01B+C open item) | `--logistics-test --only convoy`, before and after | Cause as documented: the leader counted a player-driven truck, and one just handed back and still waiting for its new route, as a straggler and gave it up after 60 s, so it then drove alone. **Fixed** (`VehicleConvoy.speed_limit`: such members are not waited for nor given up; they catch up once they drive). Reproduction after the fix: takeover check passes (resumed order, still in the convoy), all three arrive in column order at the dock (0 / 16 / 31 m). The failure is intermittent, so one run cannot prove it gone. The scenario's remaining failed check, "supplies not conserved", is identical before and after the fix (pre-existing baseline failure, not navigation) |

Remaining navigation notes: the AreaNavigation navmesh bake prints Godot's known "agent_height/max_climb rounded to cell height"
warnings (also on the baseline); the near march shows the usual couple of member recoveries. Nothing stops normal movement.

**Navigation foundation: COMPLETE — maintenance only.**

## Remaining issues

* The generator also flattened each place to a plane and cleared a **round opening in the forest** round it (1–1.9 × radius). The plane
  is softened (relief put back), but the round forest edges are still visible from the air at some villages (e.g. Nordvik). Changing
  them means adding/removing forest (vegetation overrides) — not done.
* Parcels inside the old discs are copied from the ground just outside; from the air some show as wide wedges (Verket, partly reduced).
* Buildings are the three existing models (house, barn, shed); a centre/shop/industry reads only through size, colour and grouping.
* The editor shows the layer's buildings (overrides) but not its ground paint, heights and roads (those are applied at game start).
* Making it part of the world files themselves (baking paint/heights into the Terrain3D regions, writing roads.json) is possible but
  rewrites canonical data; not done (plan: bake from the same files, re-create the manifest, after approval).

## Git

`exp/world-settlement-01`: `47612b2` (WS-01 Haugen prototype), `a4feeb7` (WS-02 settlement layer), and the commit with the
navigation checks, the convoy fix and this report. Not merged into `develop`, not pushed.
