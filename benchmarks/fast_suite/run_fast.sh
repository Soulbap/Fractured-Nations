#!/bin/bash
# Fast benchmark workflow: station benchmark, one process per map/config.
# Uses the GUI executable with --log-file: piping 30k+ errors per frame through the
# console wrapper throttled earlier runs to ~120 KB/s of output.
P="/c/Users/Hafnor/Desktop/Game Dev/fractured-nations"
G="/c/Users/Hafnor/Desktop/Game Dev/Godot_v4.7.2-stable_win64_console.exe"
GUI="/c/Users/Hafnor/Desktop/Game Dev/Godot_v4.7.2-stable_win64.exe"
OUT="$1"
cd "$P"
log() { echo "$(date +%H:%M:%S) $*" >> "$OUT/summary.txt"; }
bench() { # tag scene scenarios [godot args...] ; BENCH_EXTRA = extra script args
  local tag=$1 scene=$2 sc=$3; shift 3
  log "== bench $tag [$sc] $* $BENCH_EXTRA"
  local L="$OUT/bench_$tag.log"; rm -f "$L"
  local t0=$(date +%s)
  timeout 420 "$GUI" --path . --resolution 1600x900 --log-file "$(cygpath -w "$L")" "$@" --script res://tools/bench_world.gd -- --scene=$scene --tag=$tag --scenarios=$sc $BENCH_EXTRA > /dev/null 2>&1
  local rc=$?
  log "rc=$rc wall=$(( $(date +%s)-t0 ))s descriptor_errors=$(grep -c 'descriptor heap' "$L") device_lost=$(grep -ciE 'device (lost|removed|hung)|DXGI_ERROR' "$L") log_mb=$(( $(wc -c < "$L") / 1048576 ))"
  grep -E "^BENCH [a-z]|SCRIPT ERROR" "$L" | grep -v "stage" | cut -c1-900 >> "$OUT/summary.txt"
  # Keep logs small: errors are counted above, raw spam is not needed.
  if [ $(wc -c < "$L") -gt 20000000 ]; then grep -vE "Uniforms were never supplied|driver_uniform_set|descriptor heap|max_resource_descriptors" "$L" > "$L.tmp"; mv "$L.tmp" "$L"; fi
}
: > "$OUT/summary.txt"
bench tile_4km_trees res://scenes/world/tile_4km_trees.tscn trees,roads,terrain
BENCH_EXTRA="--max-lod=0" bench tile_4km_trees_lod0 res://scenes/world/tile_4km_trees.tscn trees,particles
bench tile_8km res://scenes/world/tile_8km.tscn full,roads,terrain
BENCH_EXTRA="--max-lod=0" bench tile_8km_lod0 res://scenes/world/tile_8km.tscn full
BENCH_EXTRA="--shots" bench tile_15km res://scenes/world/tile_15km.tscn full,particles,roads,terrain
BENCH_EXTRA="--shots" bench tile_20km res://scenes/world/tile_20km.tscn full,particles,roads,terrain
# B: larger D3D12 descriptor heap (temporary override.cfg) and Vulkan.
printf '[rendering]\nrendering_device/d3d12/max_resource_descriptors=262144\n' > override.cfg
bench tile_4km_heap262k res://scenes/world/tile_4km.tscn full
bench tile_4km_trees_heap262k res://scenes/world/tile_4km_trees.tscn trees
rm -f override.cfg
bench tile_4km_vulkan res://scenes/world/tile_4km.tscn full --rendering-driver vulkan
bench tile_4km_trees_vulkan res://scenes/world/tile_4km_trees.tscn trees --rendering-driver vulkan
bench real_2km_vulkan res://scenes/world/test_2km.tscn full,roads --rendering-driver vulkan
# Realistic-terrain validation at 20 km (full generator pipeline, 2 m spacing).
log "== build real_20km"
t0=$(date +%s)
timeout 1800 "$G" --headless --path . --script res://tools/build_world.gd -- --name=real_20km --size=20480 --spacing=2 --region=1024 --veg-extent=2048 --grass-extent=2048 > "$OUT/build_real_20km.log" 2>&1
log "rc=$? wall=$(( $(date +%s)-t0 ))s"
grep -E "^(BUILD|WorldBuilder)|SCRIPT ERROR" "$OUT/build_real_20km.log" >> "$OUT/summary.txt"
du -sh worlds/real_20km/terrain >> "$OUT/summary.txt"
BENCH_EXTRA="--shots" bench real_20km res://scenes/world/real_20km.tscn full,particles,roads,terrain
log ALL_DONE
