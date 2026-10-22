# Static asset standard (ASSET-PRODUCTION-01)

Rules for buildings, base modules, props, road assets and vehicles in `assets/military/`,
so new assets share materials, LODs and conventions and drop into any scene or into the
construction system as data. Infantry follows `docs/CHARACTER_STANDARD.md` instead.
Background and measurements: `docs/ASSET-PRODUCTION-01_REPORT.md`.

## 1. Space, scale, origin

| Rule | Value |
|---|---|
| Units | 1 Blender unit = 1 m |
| Axes | Blender Z up, asset **front faces +Y** (= Godot −Z). glTF export maps axes; nothing is rotated on import |
| Origin | On the ground (z = 0) at the footprint centre |
| Foundation | Anything that must meet uneven terrain has a skirt / pad below z = 0 (`Asset.skirt`). `foundation_depth` in the metadata; StructureDef `max_ground_gap` ≈ 2 × skirt depth |
| Linear modules | Run along X with `SNAP_W` / `SNAP_E` markers at the ends (HESCO 1.06 m cells, 3.0 m fences / barriers, 1.52 m T-walls, 4 m MOUT walls, 4 m guardrail, 10 m road sections along Y with `SNAP_S` / `SNAP_N`) |
| Placement | Free: no grid, no mandatory road or neighbour. Expansion points are optional markers |

## 2. GLB contents

```
<id>_LOD0   (first mesh: StructureCatalog.mesh_of takes the first MeshInstance3D)
<id>_LOD1
<id>_LOD2
COL_<n>-convcolonly   collision boxes -> StaticBody3D + convex shape on import
IP_* / ATT_* / SNAP_* / VEH_* / WHEEL_* / SUSP_* / DOOR_* / SEAT_* / CARGO_* / TOW_* / WEAPON_*   empties -> Node3D markers
```

A JSON sidecar `<id>.json` next to the GLB holds: display name, category, description,
bounds, size above ground, footprint, foundation depth, triangles and surfaces per LOD,
materials, LOD ranges, Godot-space collision AABBs, markers (name, position, yaw, note)
and StructureDef hints. `assets/military/catalog.json` lists every asset.

Markers: `IP_*` interaction points (a unit stands there; the marker's +Y / Godot −Z
faces the thing it interacts with), `ATT_*` attachment points for expansions,
`SNAP_*` alignment points for modules, `VEH_*` vehicle positions, `WHEEL_*` wheel
centres, `SUSP_*` suspension top mounts, `DOOR_*` / `SEAT_*` / `CARGO_*` vehicle points.

## 3. Authored LODs

Primitives are added to the LOD levels they belong to (`lods=` on every `Asset`
primitive): small details LOD0 only, medium parts LOD0+1, simplified stand-ins LOD1/2
only (e.g. a container's LOD2 is one box with a painted door decal). Distant levels
drop parts instead of melting boxes by decimation; Godot's automatic mesh LODs stay on
for LOD0.

| Family | LOD0 | LOD1 | LOD2 (end) |
|---|---|---|---|
| building | 0–70 m | 70–280 m | 280–2000 m |
| module | 0–60 m | 60–240 m | 240–1600 m |
| prop | 0–35 m | 35–120 m | 120–600 m (small items 20 / 60 / 160 m) |
| road | 0–60 m | 60–250 m | 250–1500 m |
| vehicle | 0–40 m | 40–160 m | 160–1500 m |

The import script sets these visibility ranges, with one hysteresis margin per
boundary (3 % of the distance, ≥ 1 m) shared by both LODs, so there is never a band
where neither is visible.

## 4. Materials and textures

* **One shared library** (`tools/blender/asset_production/ap_materials.py` → 51
  `assets/military/materials/*.tres`). GLBs carry material names only; the import script
  (`tools/asset_lab/ap_post_import.gd`) replaces each surface with the library material
  of the same name. Never embed images in a GLB.
* **Greyscale bases tinted per material** (paint, canvas, galvanized steel): one texture,
  many colours.
* **World-scale box UVs**: one UV unit = the material's tile in metres (paint 3 m,
  containers 2.24 m = 8 ribs, roof sheet 2.432 m = 32 ribs, concrete 3 m, CMU 1.6 m,
  asphalt / dirt 4 m, gravel 2 m, canvas 2 m, timber 1.2 m, HESCO 0.608 m).
* **Kit_Palette**: small flat-coloured parts (hardware, glass, lamps, rubber, plastics,
  small painted parts) are folded into one material at build time (UV = swatch centre in
  a 256 px palette with albedo, roughness/metal and emission). A building's small parts
  cost one surface.
* **LOD material merging**: on LOD1 materials under 1.5 % of the area, on LOD2 under 8 %,
  merge into the dominant material.
* **Signs atlas** (`signs.png`, 2048 px, 8 × 8 cells, rendered by `ap_signs.py`): road,
  military and hazard signs, range targets, building plates, decals. `Asset.sign` /
  `Frame.sign` map an outline onto a cell.
* **Vertex colours** (`Col`): baked ground dirt / contact darkening, multiplied into the
  albedo by every library material.
* Textures: procedural, tileable PNG (`ap_textures.py`), 1024 px for large surfaces,
  512 px for others, VRAM compressed + mipmaps (palette: lossless, no mipmaps), normal
  maps OpenGL / +Y up with `compress/normal_map=1`.
* Alpha: wire mesh / chain-link alpha **blend** + double-sided (fades to a haze at
  distance instead of vanishing); camouflage net alpha **scissor** + double-sided.

## 5. Budgets (guidance)

| Kind | LOD0 tris | Surfaces LOD0 |
|---|---|---|
| Building | 1.5–5 k | ≤ 7 |
| Module | 0.2–6 k | ≤ 6 |
| Prop | 50–2 k (sandbag walls 3.6–5.8 k) | ≤ 4 |
| Vehicle | 4–5 k | ≤ 6 |

## 6. Build, import, validate

```
blender -b --factory-startup --python tools/blender/asset_production/build_assets.py -- --export [--family F] [--only ID,..] [--previews DIR] [--lods] [--textures]
    [--qa] [--qa-strict] [--qa-baseline benchmarks/asset01/qa_baseline.json] [--qa-sheets DIR] [--qa-report P]
benchmarks/asset01/run_lab.sh --validate            # every catalogued asset; exit 1 on failures
benchmarks/asset01/run_lab.sh --shots [filter]      # Godot 2 x 2 sheets -> docs/asset01/godot/
benchmarks/asset01/run_lab.sh --lod [filter]        # the three LODs at their real distances
REIMPORT=1 benchmarks/asset01/run_lab.sh ...        # after changing ap_post_import.gd
```

A new asset is a builder function returning an `ap_lib.Asset` in one of the `fam_*.py`
modules, registered in its `BUILDERS` dict. The validator checks: LOD0/1/2 present and
LOD0 first, triangle counts never rising, contiguous LOD ranges, every surface a library
material, vertex colours present, bounds equal to the Blender metadata (orientation),
no floating, collision shape count and marker positions.

### Blender-side QA gate (BLENDER-SKILLS-01)

`--qa` runs the `blender-asset-qa` and `blender-game-optimization` scripts of the
project-scoped agent skills (`.claude/skills/`, MIT, EL4CTEO/blender-skills) on LOD0 of
every built asset through `tools/blender/asset_production/ap_qa.py`: closed parts with
inward normals, coplanar overlapping faces (z-fighting), detached parts, degenerate faces,
duplicate vertices, unapplied scale, plus triangle / material / texture budgets. These are
the defects the Godot validator cannot see. Library tolerances live in `ap_qa.CHECK` (eps
2 mm, contact 3 cm, UV check off: box projection and palette point UVs are by design); a
builder may set `asset.qa = {...}` to override them for one asset.

* With `--export`, the verdict is written into the sidecar (`"qa"`) next to the other numbers.
* `benchmarks/asset01/qa_baseline.json` is the recorded state of the library (the known
  backlog). `--qa-strict --qa-baseline <it>` fails the build only on findings that are new
  against it; `--qa-strict` alone fails on any finding. After fixing a backlog item, rerun with
  `--qa-report benchmarks/asset01/qa_baseline.json` to re-record.
* `--qa-sheets DIR` renders a random-colour-per-part Workbench sheet per asset (detached
  parts stand out) for a look before the Godot screenshots.

Generic skills and our conventions: `.claude/skills/fn-blender-pipeline/SKILL.md`.
