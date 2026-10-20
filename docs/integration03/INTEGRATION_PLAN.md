# WORLD-INTEGRATION-03 — internal integration plan

Working notes written before the gameplay changes; the final state is in
`docs/WORLD-INTEGRATION-03_REPORT.md`.

## Sources

| Branch | Head | Base | Scope |
|---|---|---|---|
| `feature/unified-sandbox` | 6418b12 | — | INTEGRATION-02 baseline (worktree `../fractured-nations-unified`) |
| `feature/world-playtest-01` | 87634df | 6418b12 | 94 files: terrain / river / bridge fixes, RoadNetwork, built roads and yards, SquadControl routing, camera, time compression, regenerated world (git-ignored) |
| `feature/asset-production-01` | 7d28da7 (4 commits) | 6418b12 | 835 files: 96 static assets + 33 StructureDef `.tres`, 3 faction loadouts, re-exported CHARACTER-01 (hip fix), asset lab; one gameplay script (`infantry_materials.gd`, 6 data rows) |

File overlap between the two branches: `README.md` only (merged automatically). Both merges
(`ad74c9c`, `61badcc`) are no-conflict merges, so the integration work is semantic, not textual.

Uncommitted work found and left alone: the main worktree (`feature/world-base-01`) has a
`project.godot` main-scene change and two untracked docs; `../fractured-nations-unified` has
Godot 4.7 editor re-saves (uid injection) of `.tres` / `.import` files and three untracked
screenshots. Neither is part of the milestone branches.

## Data ownership (unchanged)

| Data | Owner | Representations |
|---|---|---|
| Units (identity, faction, position, health, orders, **loadout id**) | `WorldState.units` → `UnitState` | `SoldierBody` (near), `UnitProxy` (far), `Viewmodel` (FPS) read the record |
| Faction identity (North / South / East) | `WorldState.FACTION_NAMES/COLORS`, `WarState.FactionState` | — |
| Faction → equipment family | **new** `WorldState.FACTION_LOADOUTS` (+ `InfantryMaterials.FACTION_CAMO`) | consumed only by `InfantryLoadout.default_for()` |
| Structures (type id, transform / points, removed modules) | `WorldState.construction` → `ConstructionState` / `StructureState` | `StructureManager` derives MultiMesh, collision, pads, grass clearing, nav obstacles |
| Structure types | `StructureCatalog` (code-built WORLD-BASE-01 set + surfaces) **+ `assets/military/defs/*.tres`** | `StructureDef` resources |
| Roads | `WorldState.roads` → `RoadNetwork` (world `roads.json` + built roads) | `StrategicRoutes` grid, construction snapping, grading |
| Terrain | Terrain3D data under `worlds/ref_20km/` (git-ignored, copied from playtest01) | `StructureManager` groundwork edits heights in memory only |
| War | `WarState` / `WarSim`, `StrategicRoutes` (cache fingerprinted by world source data) | map, HUD |

No new managers. No per-faction character implementations. No second road system.

## Where new assets are registered

* **Buildings and modules (33):** `StructureCatalog._build()` loads every `StructureDef`
  `.tres` under `assets/military/defs/` after the code-built set. Asset categories
  ("Ammunition", "Fuel", "Checkpoint", ...) are mapped onto the six UI categories in the
  catalog (gameplay decides grouping; asset data stays as authored).
* **Props (51 → curated subset):** generated `StructureDef` `.tres` under
  `assets/military/defs/props/` by `tools/asset_production/make_prop_defs.py` from the JSON
  sidecars (size, collision boxes, SNAP markers) plus a curated table (linear / layout / fit /
  connect group / category). Only distinct, useful objects get an entry; colour variants and
  small decor (jerrycans, cones, single sandbags) do not.
* **Meshes:** `StructureCatalog.mesh_of()` takes the first `MeshInstance3D` of the GLB
  (`<id>_LOD0`, guaranteed first by the asset validator) — same path as the WORLD-BASE-01
  assets; MultiMesh rendering per cell is unchanged.
* **Loadouts:** `assets/characters/infantry/loadouts/{NATO,RU,CN}_rifleman.tres` are found
  by `InfantryLoadout.by_id()` with no registration.
* **Vehicles:** validated as scene instances by the integration self-test (dimensions, markers,
  ground contact, screenshots). Not registered as structures or units — a drivable vehicle is a
  `UnitState` of kind VEHICLE in the next milestone, and a temporary structure entry would end
  up in `construction.json` saves.

## Faction loadout assignment

`InfantryLoadout.default_for(unit_id, faction)` returns `WorldState.faction_loadout(faction)`
when the faction has a configured family, else the old A/B pattern. The three existing call
sites (`SoldierBody._use_infantry_character`, `SoldierBody._set_viewmodel`, `UnitProxy`) pass
the unit's faction. The result is stored in `UnitState.loadout` the first time a representation
needs it and from then on is the record's truth (save/load, promotion, possession unchanged).
Reinforcements go through `WarSim.spawn_squad → WorldState.add_unit` with an empty loadout,
so they pick up the faction family the same way. `InfantryMaterials.FACTION_CAMO` gets the
three family camouflages so shared CHARACTER-01 pieces (pack, belt) and the legacy loadouts
match their faction.

## Structures, roads, terrain and navigation

* Placement, groundwork, grass clearing, collision bodies, navmesh carving and the abstract
  blocking grid all read `StructureDef.get_collision_boxes()` / `blocks_navigation` — new defs
  plug in without code changes **except**: three modules (low-crawl wire, tyre run, parking pad)
  intentionally have no collision; today an empty `collision_boxes` means "one box of `size`",
  which would make them solid walls. New `StructureDef.walkable` flag: no collision body, no
  nav obstacle, footprint still used for overlap and terrain checks.
* Roads: no change to `RoadNetwork`; the road-kit surface meshes (`road_*_10m`) are **not**
  used (painted roads are authoritative; duplicate meshes would float or z-fight). Guardrails,
  delineators and signs are placeable props. `bridge_small` and `road_culvert` need terrain
  cuts the bridge system does not do for player structures — not registered.
* Navigation after construction: `StructureManager.area_changed → DetailManager.structures_changed`
  (debounced navmesh rebake) and `_rebuild_block_grid()` — unchanged.

## APIs that must keep working

`StructureCatalog.all/get_def/in_category/mesh_of`, `StructureDef` fields used by
`StructureManager`/`ModularLine`/`ConstructionController`, `InfantryLoadout.by_id`,
`UnitState.loadout` persistence (`to_dict/from_dict`, `apply_snapshot`), `ConstructionState`
JSON (type ids only), `StrategicRoutes` grid cache fingerprint, every `--*-test` entry point.

## Risks

1. Loadout defaults changing for *existing* saves: old saves keep "A_standard"/"B_heavy" — valid
   loadouts, now shown in the faction's camouflage through `FACTION_CAMO`. No migration.
2. Construction menu size: 10 + 5 + 33 + ~20 entries. The panel gets collapsible categories
   (one open at a time) instead of a redesign.
3. Large buildings on uneven ground: `max_ground_gap` 0.4–1.0 m in the asset defs with 20–30 m
   footprints; the groundwork pad handles it, but placement may be refused on steep ground —
   that is correct behaviour, to be checked in the base scenario.
4. Performance: sandbag walls / fighting positions are 3.6–6.3 k triangles at LOD0 and the
   catalog only uses LOD0 meshes in MultiMesh; measure, use LOD1 as the catalog mesh if needed.
5. Vehicles: wheels are part of the body mesh; `WHEEL_*` markers exist for the next milestone.
