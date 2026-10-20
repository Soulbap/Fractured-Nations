#!/usr/bin/env bash
# WORLD-TERRAIN-01: full, reproducible build of the reference world (worlds/ref_20km).
#
#   tools/terrain_ref/build_ref_world.sh [--assets] [--shots]
#
#   1. geography (Python/numpy via Blender's bundled Python)   ~10 min
#   2. procedural terrain textures                              ~15 s
#   3. --assets: Blender environment assets (GLB + .blend)      ~3 min  (outputs are committed)
#   4. Godot import, GLB -> LOD scenes, vegetation library      ~1 min
#   5. Godot world build (terrain, roads, water, vegetation)    ~5 min
#   6. playability analysis; --shots: top-down + FPS/RTS screenshots
#
# Paths assume the repository sits next to the Godot executables (as on the dev machine);
# override with GODOT=..., GODOT_GUI=..., BLENDER=..., BPY=...
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-../Godot_v4.7.2-stable_win64_console.exe}"
GODOT_GUI="${GODOT_GUI:-../Godot_v4.7.2-stable_win64.exe}"
BLENDER="${BLENDER:-/c/Program Files/Blender Foundation/Blender 5.2/blender.exe}"
BPY="${BPY:-/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe}"
LAYOUT=tools/terrain_ref/layout_ref03.json
SRC=worlds/ref_20km/source
export PYTHONIOENCODING=utf-8

echo "== 1. geography"
"$BPY" tools/terrain_ref/generate.py --layout "$LAYOUT" --out "$SRC"
"$BPY" tools/terrain_ref/check_roads.py "$SRC"
echo "== 2. terrain textures"
"$BPY" tools/terrain_ref/make_terrain_textures.py assets/terrain/textures
"$BPY" tools/blender/env/make_env_textures.py assets/environment/textures
if [[ " $* " == *" --assets "* ]]; then
  echo "== 3. Blender assets"
  "$BLENDER" -b --factory-startup --python tools/blender/env/make_trees.py
  "$BLENDER" -b --factory-startup --python tools/blender/env/make_rocks.py
  "$BLENDER" -b --factory-startup --python tools/blender/env/make_structures.py
fi
echo "== 4. Godot import + asset scenes + library"
"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
"$GODOT" --headless --path . --script res://tools/terrain_ref/import_env_assets.gd
"$GODOT" --headless --path . --script res://tools/terrain_ref/make_nordic_library.gd
echo "== 5. world build"
"$GODOT" --headless --path . --script res://tools/build_world.gd -- --config=res://worlds/ref_20km/world_config.tres
echo "== 6. analysis"
"$BPY" tools/terrain_ref/analyze.py "$SRC" > /dev/null
if [[ " $* " == *" --shots "* ]]; then
  "$GODOT_GUI" --path . --script res://tools/terrain_ref/capture.gd -- --scene=res://scenes/world/ref_20km.tscn \
    --out=res://docs/terrain01/shots --topdown=8x1024 --shots=res://tools/terrain_ref/shots_ref03.json
fi
echo "done"
