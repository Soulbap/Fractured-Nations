# FRACTURED NATIONS

Modern military sandbox in Godot 4. One large, continuous 3D world shared by the FPS,
RTS and 2D-map views.

Current state: **WORLD-SANDBOX-01** — the first playable persistent war. Three factions
(North = you, South = aggressive AI, East = defensive AI) fight for twelve strategic objectives
(bases, towns, river bridges, villages) across the whole 20 x 20 km world. Forces march along
planned routes (roads and bridges, never through lakes, the river or cliffs), capture ground by
driving defenders out, reinforce, recover and run out of reserves. You command your faction on a
strategic map (M), in the tactical view and in first person - the same soldiers in the same
world, which keeps fighting wherever you are and is saved with F5. See
[docs/WORLD-SANDBOX-01_REPORT.md](docs/WORLD-SANDBOX-01_REPORT.md).

Before that, **COMBAT-02** — larger and smarter infantry fights: 100 v 100 and several
battles kilometres apart run at about 3.3 ms average frame time; soldiers who come under fire
work out roughly where it comes from and take nearby cover (HESCO, buildings, rocks, trees,
terrain) and fight from it, within what their squad order allows (Hold keeps its area, Move and
Follow only pause briefly, Hold Fire takes cover without firing; a player order always wins);
see [docs/COMBAT-02_REPORT.md](docs/COMBAT-02_REPORT.md).

Before that, **COMBAT-01b** — soldiers fight on their own: they see enemies (field of
view, terrain, trees, foliage, structures), pick and keep a target, aim with human error,
fire, reload and take casualties through the same rifle and combat authority as the player,
while squad orders, Hold Fire / Weapons Free, possession and save/load keep working; see
[docs/COMBAT-01B_REPORT.md](docs/COMBAT-01B_REPORT.md).

Before that, **COMBAT-01a** — the first rifle: possess a soldier, aim, fire (semi / auto),
reload and kill; hits and cover are resolved from world data, so they work at any range and
with or without the camera nearby; see [docs/COMBAT-01A_REPORT.md](docs/COMBAT-01A_REPORT.md).

Before that, **UNIT-01A** — squads with tactical orders (move in line or column, hold, follow,
regroup) on top of the soldiers, persistent through FPS possession, the abstract tier and
save/load; see [docs/UNIT-01A_REPORT.md](docs/UNIT-01A_REPORT.md).

Before that, **WORLD-INTEGRATION-01** — the construction system and the FPS/RTS game run on
the reference world `ref_20km`, which is now the main scene (see
[docs/WORLD-INTEGRATION-01_REPORT.md](docs/WORLD-INTEGRATION-01_REPORT.md) and
[docs/WORLD-TERRAIN-01_REPORT.md](docs/WORLD-TERRAIN-01_REPORT.md)), on top of
**WORLD-BASE-01** freeform military base construction (RTS construction mode,
drag-to-build HESCO / fences / barriers, Blender-made construction set, persistent and saved)
on the **WORLD-CORE-02** 20 km world simulation, the WORLD-CORE-01 FPS/RTS control, the
WORLD-TECH-02 vegetation foundation and the WORLD-TECH-01 world-technology prototype. See
[docs/WORLD-BASE-01_REPORT.md](docs/WORLD-BASE-01_REPORT.md),
[docs/WORLD-CORE-02_REPORT.md](docs/WORLD-CORE-02_REPORT.md),
[docs/WORLD-CORE-01_REPORT.md](docs/WORLD-CORE-01_REPORT.md),
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

**The main scene is `scenes/game/world_ref_20km.tscn`, which needs the generated reference
world.** On a fresh checkout build it first (about 14 minutes, ~2.4 GB of git-ignored data under
`worlds/ref_20km/` and `scenes/world/ref_20km.tscn`; Blender 5.x must be installed because the
generator runs in Blender's Python):

```bash
bash tools/terrain_ref/build_ref_world.sh
```

Then press **F5**. The war starts at once: you are North (blue), in the tactical view over
your HQ; South (orange, aggressive) and East (green, defensive) are AI factions that plan and
launch their own operations. Press **M** for the strategic map. The first start builds the
strategic route grid (about 1 s) and caches it in `user://strategic/`. The scripted tests of
earlier milestones (`--squad-test`, `--combat-test` ...) still use their own fixed two-faction
layout. The small `scenes/game/core_demo.tscn` (2 km world, no build needed) still runs on its
own with that layout.

| Key | Strategic map (M) |
|---|---|
| M / Esc | Open / close the map (from first person the game switches to the tactical view first) |
| Wheel, middle-drag or WASD, Home | Zoom, pan, whole map |
| LMB, LMB-drag, Shift | Select your squads (or an objective), box select, add |
| RMB | Order the selected squads: on an enemy or neutral objective = **attack**, on your own = **reinforce**, on open ground = **move** (all as operations with planned routes) |
| Buttons | Attack / Defend / Reinforce the selected objective, Cancel op, View |
| G, "Go" in the operation list | Jump the tactical camera there (closes the map) |
| , and . | Time compression 1 / 2 / 4 / 8 x (first person always runs at 1 x) |

The map shows territory (each objective's area in its owner's colour), objectives with capture
progress and a blinking ring while contested, your squads (NATO symbols with strength), enemy
forces your soldiers have seen (diamonds; they fade when not seen for a while), your operations
with their routes, and the war log. A direct RTS order (move, hold, follow, regroup) takes a
squad out of its operation: your command always wins.

| Key | First person (possessing a soldier) |
|---|---|
| Mouse | Look (click to capture, Esc to release) |
| W A S D / Shift / Space | Move / sprint / jump |
| LMB (hold in auto) / RMB | Fire / aim (narrower view) |
| R / V | Reload / semi or automatic fire |
| **Tab** | Switch to the tactical camera (the soldier returns to the simulation) |
| F | Debug fly / noclip |
| F3 | Performance overlay |
| M | Strategic map (WORLD-SANDBOX-01 war) |
| F4 | AI combat debug overlay (both views): state, target, why a soldier is not firing; COMBAT-02: tactical state, threat direction (orange), chosen cover (green ring), reaction path (dashed), "AI reaction" vs "order", cover reasons |

| Key | Tactical (RTS) |
|---|---|
| W A S D (Shift faster) | Pan |
| Q / E, middle-mouse drag | Rotate |
| Mouse wheel | Zoom (5–200 m, starts at 80 m; `RTSCamera.zoom_min` / `zoom_max` / `zoom_default`) |
| **B** | Construction mode (see below) |
| Left click / drag box, Shift+click | Select soldiers and vehicles / add to selection, Ctrl+A all soldiers |
| Ctrl+click, squad panel (left) | Select a soldier's whole squad; Shift adds more squads. Rows show order, progress, living + fallen, engaging / under fire / in cover; the list scrolls when it would reach the HUD text |
| Right click | Move: selected squads walk in formation to the point (side by side if several); other selected soldiers get individual orders and leave their squad's order until its next one |
| H | Hold: selected squads stop and stay; other selected soldiers stop |
| F, then click a soldier | Selected squads follow that soldier, or its squad (its leader) |
| G / Shift+G | Regroup selected squads on their leader / at the cursor |
| V, [ and ] | Line or column formation, spacing −/+ 0.5 m (1.5–10 m) |
| Y, FREE / HOLD in the squad panel | Rules of engagement of the selected squads: Weapons Free (default, soldiers engage on their own) / Hold Fire (they track but do not shoot) |
| P, Enter or double-click | Possess the selected soldier (first person) |
| **Tab** | Return to the soldier you last controlled |

F5 / F9 also save and load units and squads (`user://saves/<world>/world.json`, next to the
construction file).

### Construction (WORLD-BASE-01, RTS)

| Key | Construction mode |
|---|---|
| B | Enter / leave; pick a type in the panel (top right) |
| Mouse, LMB | Building preview (green / red with reason), click builds |
| R, Shift+R, Ctrl+wheel | Rotate 15° |
| LMB on lines | Start, then one click per corner; click the start again to close a perimeter |
| Enter, RMB, double-click | Finish the line; Backspace removes the last corner |
| Shift / Ctrl (held) | 15° direction steps / no snapping |
| X | Delete tool: click removes a building or one line module, Shift+click a whole line |
| C | Vegetation clearing on (default) / off: trees, shrubs and debris inside new footprints are cut (saved with the base); off, trees block placement. Rocks and settlement buildings always block |
| Esc | Cancel line → tool → leave |
| F5 / F9 | Save / load construction (`user://saves/<world>/construction.json`) |

Assets are generated in Blender by `tools/blender/structures/*.py` (sources in
`assets/structures/blender/`). Scripted checks on the reference world (from the repository
root, after the world build): `bash benchmarks/wi01/run_test.sh integration --shots`
(construction in five terrain types, clearing, navigation, persistence, performance),
`... base` (the WORLD-BASE-01 checks) and `... large` (the WORLD-CORE-02 checks). The newest
runner, `bash benchmarks/sandbox01/run_test.sh <kind>`, also takes `sandbox` (WORLD-SANDBOX-01
war scenarios, `--only a,b`), `combat-tactics` (COMBAT-02
reactions and cover), `combat-scale` (COMBAT-02 16 / 50 / 100 v N, two battles), `combat-ai`
(COMBAT-01b AI firefights), `combat` (COMBAT-01a) and `squad` (UNIT-01A).

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

## Reference world (WORLD-TERRAIN-01)

`worlds/ref_20km` is a 20 × 20 km northern-European world built from the geographic
reference map (`docs/terrain01/reference_map_03.png`) with Nordic trees, rocks, buildings
and road furniture from the project's Blender pipeline. See
[docs/WORLD-TERRAIN-01_REPORT.md](docs/WORLD-TERRAIN-01_REPORT.md).

Generated data (~2.4 GB) is not committed. Build it once (about 14 minutes; `--assets` also
regenerates the Blender assets, whose outputs are committed):

```bash
bash tools/terrain_ref/build_ref_world.sh
```

`--shots` adds the top-down mosaic and the FPS/RTS screenshots. Then run
`scenes/game/world_ref_20km.tscn` (the WORLD-CORE-02 FPS/RTS game on the new world) or
open `scenes/world/ref_20km.tscn` in the editor. The geography is edited in
`tools/terrain_ref/layout_ref03.json` (river, lakes, zones, settlements, plateaus, road
waypoints, seed); `tools/terrain_ref/generate.py` turns it into heightmap, control,
colour, vegetation and road data that `ReferenceWorldBuilder` imports.

## Repository layout

```
addons/          third-party editor plugins (Terrain3D, Road Generator, Godot AI)
assets/          textures, placeholder vegetation, rock models
scenes/          world and player scenes
scripts/world/   WorldConfig, terrain generator, WorldBuilder, collider streaming
scripts/vegetation/  VegetationChunk data, VegetationStreamer, GrassLayer, exclusion mask
shaders/vegetation/  GPU grass placement and blade shaders
shaders/environment/ foliage, bark, rock and grass-tuft shaders (WORLD-TERRAIN-01 assets)
shaders/world/       river and lake water
tools/terrain_ref/   reference-world generator (Python), build/capture/analysis tools
tools/blender/env/   Blender generators for the Nordic environment assets
assets/environment/  environment GLBs, .blend sources, textures, LOD scenes, vegetation library
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
- WORLD-TERRAIN-01 environment assets (trees, shrubs, rocks, deadwood, bridges, buildings,
  road furniture) and their bark/foliage/ground textures are generated by the project's own
  scripts (`tools/blender/env/`, `tools/terrain_ref/make_terrain_textures.py`); photographic
  references were only viewed (`docs/terrain01/REFERENCES.md`), nothing was copied.
