# FRACTURED NATIONS

Modern military sandbox in Godot 4. One large, continuous 3D world shared by the FPS,
RTS and 2D-map views.

Current state: **WORLD-CORE-01** persistent world with FPS/RTS control (soldiers, vehicles,
orders, possession) on top of the WORLD-TECH-02 vegetation foundation and the WORLD-TECH-01
world-technology prototype. See [docs/WORLD-CORE-01_REPORT.md](docs/WORLD-CORE-01_REPORT.md),
[docs/WORLD-TECH-02_REPORT.md](docs/WORLD-TECH-02_REPORT.md) and
[docs/WORLD-TECH-01_REPORT.md](docs/WORLD-TECH-01_REPORT.md).

## Requirements

| Dependency | Version | Notes |
|---|---|---|
| Godot | **4.7.2-stable** (standard, not .NET) | Forward+ renderer, **Vulkan** (D3D12 only as automatic fallback) |
| Physics | Jolt (built into Godot 4.7) | Set in Project Settings → Physics → 3D |
| Terrain3D | 1.0.2-stable (MIT) | Bundled in `addons/terrain_3d` (Windows + Linux x86_64 binaries) |
| Godot Road Generator | 0.9.5 (MIT) | Bundled in `addons/road-generator` |
| Godot AI | 4.3.0 | Editor MCP addon used during development, optional |

All addons are committed to the repository. Nothing has to be installed separately.

## Opening the project

1. Clone the repository and check out the branch you want (`main` is the stable baseline,
   `feature/world-tech-01` has the prototype).
2. Open `project.godot` with Godot 4.7.2. The first import takes about a minute.
3. If the editor shows errors about Terrain3D on first open, restart the editor once.
   GDExtensions load at startup.

## Running the prototype

Press **F5** or run `scenes/game/core_demo.tscn`, which is the main scene. You start in
first person as a North soldier on the base pad of the 2 km world; two factions (North, blue
rings / olive uniforms; South, orange rings / khaki uniforms) with 8 soldiers and one transport
vehicle each share the world. A South patrol and two North soldiers already have move orders.

| Key | First person (possessing a soldier) |
|---|---|
| Mouse | Look (click to capture, Esc to release) |
| W A S D / Shift / Space | Move / sprint / jump |
| **Tab** | Switch to the tactical camera (the soldier returns to the simulation) |
| F | Debug fly / noclip |
| F3 | Performance overlay |

| Key | Tactical (RTS) |
|---|---|
| W A S D (Shift faster) | Pan |
| Q / E, middle-mouse drag | Rotate |
| Mouse wheel | Zoom (12–700 m) |
| Left click / drag box, Shift+click | Select soldiers and vehicles / add to selection, Ctrl+A all soldiers |
| Right click | Move order for the selected soldiers (grid formation at the clicked point) |
| H | Halt the selected soldiers |
| P, Enter or double-click | Possess the selected soldier (first person) |
| **Tab** | Return to the soldier you last controlled |

The world exploration scene `scenes/world/test_2km.tscn` still runs on its own with the
WORLD-TECH-01 free-roaming controller.

## Editing the world

Open `scenes/world/test_2km.tscn` in the editor.

- **Terrain:** select `Terrain3D` and use the Terrain3D toolbar to sculpt and paint
  textures. Save the scene to write the region files in `worlds/test_2km/terrain/`.
- **Vegetation:** trees, bushes and rocks live in `worlds/<name>/vegetation/veg_<x>_<z>.res`
  (1024 m chunks of 128 m cells) and are streamed around the camera by the `Vegetation`
  node (`VegetationStreamer`, also in the editor viewport). Grass is camera-local GPU
  particles (`Grass` node, `GrassLayer`) masked by `worlds/<name>/vegetation/mask.res`
  (roads, base pads). You can still paint trees with Terrain3D's instancer brush; the
  `WorldBuilder` button **Bake painted instances into cells** moves them into the chunk
  files (otherwise they stay as Terrain3D MultiMeshes for the whole map).
- **Roads:** select a `RoadPoint` under `Roads/RoadManager/RoadNetwork` and move it, or
  use the Road Generator toolbar to add roads and intersections.
  `Roads/Terrain3DRoadConnector` flattens the terrain under the roads.
- **Regeneration:** the `WorldBuilder` node has inspector buttons to regenerate the
  terrain, rebuild the roads or rescatter vegetation (chunks, grass mask and the forest
  tint baked into the Terrain3D color map) from its `WorldConfig`. These overwrite hand
  edits in that layer. A copy of the terrain data is written to
  `worlds/<name>/terrain_backup/` first.

### Building a world from the command line

```bash
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/build_world.gd -- --config=res://worlds/test_2km/world_config.tres
```

A new size from defaults (written to `worlds/<name>/` and `scenes/world/<name>.tscn`):

```bash
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/build_world.gd -- --name=scale_4km --size=4096
```

Options: `--spacing=<m>`, `--region=<256|512|1024|2048>`, `--grass-extent=<m>`,
`--veg-extent=<m>`, `--no-roads`, `--no-vegetation`, `--no-scene`.
Scale-test worlds (`worlds/scale_*`) are git-ignored.

Rebuild only the vegetation of an existing world (chunks, mask, forest tint; adds the
`Vegetation` and `Grass` nodes if the scene lacks them):

```bash
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/rebuild_vegetation.gd -- --scene=res://scenes/world/test_2km.tscn --veg-extent=0
```

### Measurements (fast workflow, routine use)

One process per map, fixed FPS, RTS and strategic camera stations, and layer scenarios. Runs
abort automatically on render errors or memory pressure. Results go to
`benchmarks/raw/bench_<tag>.json`.

```bash
Godot_v4.7.2-stable_win64.exe --path . --resolution 1600x900 --log-file bench.log --script res://tools/bench_world.gd -- --scene=res://scenes/world/test_2km.tscn --tag=my_run
```

Use the GUI executable with `--log-file`. The console wrapper throttles the process when
there is heavy error output. Add `--rendering-driver d3d12` to compare backends.
`tools/measure_run.ps1` wraps a run and records peak RAM and GPU memory from Windows counters.

Synthetic stress-test maps (mirror-tiled from the 2 km world, **not** representative
terrain):

```bash
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/tile_world.gd -- --name=tile_8km --regions=8 --veg=trees
```

Optional longer regression benchmark (camera routes) and the scripted FPS controller test:

```bash
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 res://scenes/world/test_2km.tscn -- --benchmark
```

```bash
Godot_v4.7.2-stable_win64_console.exe --path . res://scenes/world/test_2km.tscn -- --fps-test
```

Also `--screenshots` (writes `docs/screenshots/`) and `--quit-after-load`.

WORLD-CORE-01 scripted checks (spawn, orders during FPS, Tab switching, click/box selection,
right-click orders, 12 perspective switches, arrival, suspended orders, the bodiless unit tier,
frame times; about 90 s, writes `benchmarks/raw/core_test.json` and `docs/screenshots/core01_*.png`):

```bash
Godot_v4.7.2-stable_win64.exe --path . --resolution 1600x900 --log-file core.log res://scenes/game/core_demo.tscn -- --core-test --shots
Godot_v4.7.2-stable_win64.exe --path . --resolution 1600x900 --log-file wc02.log res://scenes/game/world_core_02.tscn -- --large-test --shots   # WORLD-CORE-02, real 20 km world; keys 1/2/3 sites, N next soldier
```

Targeted vegetation checks (mask, tree clearance, determinism, streamer activation,
camera jumps and FPS/RTS switching, grass altitude cutoff, colliders; about 20 s):

```bash
Godot_v4.7.2-stable_win64.exe --path . --resolution 1600x900 --log-file vegtest.log --script res://tools/test_vegetation.gd -- --scene=res://scenes/world/test_2km.tscn --shots
```

`benchmarks/wt02_suite/run_wt02.sh <out_dir>` runs the whole WORLD-TECH-02 validation.

## Repository layout

```
addons/          third-party editor plugins (Terrain3D, Road Generator, Godot AI)
assets/          textures, placeholder vegetation, rock models
scenes/          world and player scenes
scripts/world/   WorldConfig, terrain generator, WorldBuilder, collider streaming
scripts/vegetation/  VegetationChunk data, VegetationStreamer, GrassLayer, exclusion mask
shaders/vegetation/  GPU grass placement and blade shaders
scripts/player/  FPS controller
scripts/core/    UnitState, WorldState, WorldSim (authoritative simulation), GameController (possession)
scripts/units/   SoldierBody, VehicleBody, faction visuals
scripts/rts/     tactical camera and selection/orders
scripts/game/    CoreDemo: the playable scene wiring and spawning
scripts/ui/      HUD
scripts/debug/   diagnostics overlay, benchmark, FPS self-test, WORLD-CORE-01 self-test
tools/           build, tiling, benchmark and editor-probe tools; tools/blender/ asset generators
assets/units/    soldier and vehicle glTF models (+ blender/ sources, ignored by Godot)
worlds/<name>/   per-world config, Terrain3D assets/material, region data, vegetation chunks
benchmarks/      committed benchmark evidence (raw/ is git-ignored)
docs/            reports and screenshots
```

## Third-party asset licenses

- Terrain3D, Godot Road Generator: MIT (see each addon's LICENSE).
- Ground and rock textures and the rock models come from the Terrain3D demo. They are
  ambientCG CC0 (`assets/terrain/textures/asset_licenses.txt`).
- Trees, bushes, the grass card and the dirt texture are procedurally generated
  placeholders (`tools/make_vegetation_assets.gd`).
- The soldier and transport vehicle models are generated in Blender by the project's own
  scripts (`tools/blender/`), no third-party content.
- The GPU grass shaders derive from Terrain3D's `extras/particle_example` (MIT).
