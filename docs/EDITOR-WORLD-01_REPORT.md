# EDITOR-WORLD-01 — phase 1: see the real world in the editor

Goal: open `scenes/world/ref_20km.tscn` in the Godot editor and see the game world as it
looks at runtime, without starting the game. No world data was regenerated or changed.

## Findings (why the editor looked empty)

1. **Camera under the terrain.** The editor camera starts at y=0; the terrain is 51-1216 m.
   The terrain was there but seen from below.
2. **Four resource scripts without `@tool`** (`VegetationMeshDef`, `VegetationLibrary`,
   `VegetationMask`, `VegetationChunk`). `VegetationStreamer` and `GrassLayer` already run
   in the editor, but called methods on placeholder instances: 400+ errors, no trees,
   houses, rocks or grass.
3. **Editor far plane 4 km**: anything farther is not drawn (grey viewport). The editor
   resets the camera's `far` every frame, so it can only be changed through the editor's
   Z-Far preference (`editors/3d/default_z_far`, read when a viewport is created).

## Changes

- `@tool` on the four vegetation resource scripts. Checked first: none of them (nor the
  streamer/grass nodes) writes files; streamer and grass children are internal nodes
  without `owner`, so nothing is saved into the scene. Resources are read-only data here.
- New editor plugin `tools/editor_viewpoints/` (enabled in `project.godot`): a
  **Viewpoints** menu in the 3D toolbar. Points: overview, all settlements and plateaus
  from the world's `sites.json`. Camera height comes from `Terrain3D.data.get_height`
  (never below the surface); distance is clamped to the editor's far plane. It moves the
  editor camera only and writes nothing. Also raises the Z-Far preference to 30 km (only
  ever raised). Static API for tests: `WorldViewpointsPlugin.goto_named("Haugen")`.
- Not touched: terrain, roads, vegetation chunks, the generated scene, `world_config.tres`,
  the player's spawn, the game camera, the manifest.

## Measurements

| What | Result |
|---|---|
| Editor start to `ref_20km.tscn` open (RTX 3070, warm disk cache) | ~44 s from launch; ~17 s is editor and plugin start-up, scene load about 16-27 s |
| Editor errors after the fix | 0 (was 400+ placeholder errors) |
| Editor frame rate at Sentrum (town, ~3300 draw calls) | 60 fps |
| Editor frame rate at the default camera (under the terrain) | ~19 fps |
| Editor memory after load | ~3 GB static |
| Headless editor open (`--headless --editor`) | not meaningful; the scene did not load, ignored |

No performance changes were made in this phase. The ~19 fps at the default camera is
unexplained (underground view draws terrain and grass from below) and not investigated.

## Visual verification (live editor, MCP screenshots)

- Haugen: houses, barn, road with markings and posts, trees, rocks, grass.
- Sentrum: street grid, houses, trees, hills on the horizon.
- Overview (9 km up): whole terrain, lake, river, fields.
- Flyslette ost: forest block, lake, mountains.

## Runtime

`--integration03-test --only catalog,views` on `world_ref_20km.tscn`: `WI03 PASS`, 0 script
errors. `world_manifest.py verify --ignore-editor-metadata`: OK. `ref_20km.tscn` unchanged
(same mtime and size).

## Known limits / not done

- The menu was tested through the same `viewpoints()`/`move_camera()` functions via a
  temporary hook; the toolbar popup itself was not clicked in this run.
- The editor Z-Far preference applies to viewports created after the change; the first
  session after enabling needs a restart (or View > Settings > Z-Far). Until then the
  overview is automatically moved closer.
- Editing (phase 2) and manual vegetation/building overrides (phase 3) are not started.
- Opening the scene may make the editor re-save resources with defaults trimmed (e.g.
  `assets/vegetation/vegetation_library.tres` once); that file was reverted, harmless.
