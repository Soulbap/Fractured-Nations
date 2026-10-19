# FRACTURED NATIONS

Modern military sandbox in Godot 4. One large, continuous 3D world shared by the FPS,
RTS and 2D-map views.

Current state: **WORLD-TECH-01** world-technology prototype (terrain, roads,
vegetation, FPS exploration, scalability measurements). See
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

Press **F5** or run `scenes/world/test_2km.tscn`, which is the main scene.

| Key | Action |
|---|---|
| Mouse | Look (click to capture, Esc to release) |
| W A S D | Move |
| Shift | Sprint (boost while flying) |
| Space | Jump (up while flying) |
| F | Toggle debug fly / noclip |
| Ctrl | Down while flying |
| F3 | Performance overlay |

## Editing the world

Open `scenes/world/test_2km.tscn` in the editor.

- **Terrain:** select `Terrain3D` and use the Terrain3D toolbar to sculpt, paint
  textures and paint instanced vegetation. Save the scene to write the region files in
  `worlds/test_2km/terrain/`.
- **Roads:** select a `RoadPoint` under `Roads/RoadManager/RoadNetwork` and move it, or
  use the Road Generator toolbar to add roads and intersections.
  `Roads/Terrain3DRoadConnector` flattens the terrain under the roads.
- **Regeneration:** the `WorldBuilder` node has inspector buttons to regenerate the
  terrain, rebuild the roads or rescatter vegetation from its `WorldConfig`. These
  overwrite hand edits in that layer. A copy of the terrain data is written to
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

## Repository layout

```
addons/          third-party editor plugins (Terrain3D, Road Generator, Godot AI)
assets/          textures, placeholder vegetation, rock models
scenes/          world and player scenes
scripts/world/   WorldConfig, terrain generator, WorldBuilder, collider streaming
scripts/player/  FPS controller
scripts/debug/   diagnostics overlay, benchmark, FPS self-test
tools/           build, tiling, benchmark and editor-probe tools
worlds/<name>/   per-world config, Terrain3D assets/material and region data
benchmarks/      committed benchmark evidence (raw/ is git-ignored)
docs/            reports and screenshots
```

## Third-party asset licenses

- Terrain3D, Godot Road Generator: MIT (see each addon's LICENSE).
- Ground and rock textures and the rock models come from the Terrain3D demo. They are
  ambientCG CC0 (`assets/terrain/textures/asset_licenses.txt`).
- Trees, bushes, the grass card and the dirt texture are procedurally generated
  placeholders (`tools/make_vegetation_assets.gd`).
