#!/bin/bash
# Validation matrix: identical scenes/scenarios on D3D12 and Vulkan, every run wrapped
# by tools/measure_run.ps1 (wall time, exit code, peak RAM, peak GPU memory from OS).
P="/c/Users/Hafnor/Desktop/Game Dev/fractured-nations"
G="/c/Users/Hafnor/Desktop/Game Dev/Godot_v4.7.2-stable_win64_console.exe"
GUIW='C:\Users\Hafnor\Desktop\Game Dev\Godot_v4.7.2-stable_win64.exe'
OUT="$1"; OUTW=$(cygpath -w "$OUT")
cd "$P"
log() { echo "$(date +%H:%M:%S) $*" >> "$OUT/summary.txt"; }
run() { # tag driver scene scenarios [extra script args]
  local tag=$1 drv=$2 scene=$3 sc=$4; shift 4
  log "== $tag driver=$drv [$sc] $*"
  rm -f "$OUT/$tag.log"
  local mem=$(powershell -NoProfile -ExecutionPolicy Bypass -File tools/measure_run.ps1 -Exe "$GUIW" \
    -ArgLine "--path . --resolution 1600x900 --rendering-driver $drv --log-file \"$OUTW\$tag.log\" --script res://tools/bench_world.gd -- --scene=$scene --tag=$tag --scenarios=$sc $*" \
    -Out "$OUTW\$tag.mem.json" -TimeoutSec 420 | tr -d '\r')
  log "MEM $mem"
  log "descriptor_errors=$(grep -c 'descriptor heap' "$OUT/$tag.log" 2>/dev/null) fatal=$(grep -c 'FATAL' "$OUT/$tag.log" 2>/dev/null) crashed=$(grep -c 'Program crashed' "$OUT/$tag.log" 2>/dev/null)"
  grep -E "^BENCH [a-z]|SCRIPT ERROR|FATAL" "$OUT/$tag.log" | cut -c1-900 >> "$OUT/summary.txt"
  if [ $(wc -c < "$OUT/$tag.log") -gt 20000000 ]; then grep -vE "Uniforms were never supplied|driver_uniform_set|descriptor heap|max_resource_descriptors" "$OUT/$tag.log" > "$OUT/$tag.tmp"; mv "$OUT/$tag.tmp" "$OUT/$tag.log"; fi
}
fpstest() { # tag driver scene
  local tag=$1 drv=$2 scene=$3
  log "== $tag driver=$drv fps-test"
  rm -f "$OUT/$tag.log"
  local mem=$(powershell -NoProfile -ExecutionPolicy Bypass -File tools/measure_run.ps1 -Exe "$GUIW" \
    -ArgLine "--path . --resolution 1600x900 --rendering-driver $drv --log-file \"$OUTW\$tag.log\" $scene -- --fps-test" \
    -Out "$OUTW\$tag.mem.json" -TimeoutSec 420 | tr -d '\r')
  log "MEM $mem"
  grep -E "DIAG fps-test|SCRIPT ERROR|FATAL|Program crashed" "$OUT/$tag.log" | cut -c1-2500 >> "$OUT/summary.txt"
  log "leak_warnings_at_exit=$(grep -ciE 'leaked|still in use' "$OUT/$tag.log")"
}
while ! grep -q ALL_DONE "$OUT/../fast/summary.txt" 2>/dev/null; do sleep 15; done
: > "$OUT/summary.txt"
SC=full,particles,roads,terrain
# Bracket test for the D3D12 subresource limit (19x19 = 361 regions, 3971 subresources).
log "== build tile_19km"
timeout 900 "$G" --headless --path . --script res://tools/tile_world.gd -- --name=tile_19km --regions=19 --veg=none > "$OUT/tile_19km_build.log" 2>&1
grep "TILE tile" "$OUT/tile_19km_build.log" >> "$OUT/summary.txt"
run d3d12_tile_19km d3d12 res://scenes/world/tile_19km.tscn terrain
# Equivalent D3D12 vs Vulkan matrix.
for drv in vulkan d3d12; do
  run ${drv}_real_2km $drv res://scenes/world/test_2km.tscn $SC
  run ${drv}_tile_4km $drv res://scenes/world/tile_4km.tscn full,roads,terrain
  run ${drv}_tile_15km $drv res://scenes/world/tile_15km.tscn $SC
  run ${drv}_tile_20km $drv res://scenes/world/tile_20km.tscn $SC
  run ${drv}_real_20km $drv res://scenes/world/real_20km.tscn $SC
done
# Navigation on the 20 km maps (FPS controller, real terrain collision), clean exit.
fpstest vulkan_fps_real_20km vulkan res://scenes/world/real_20km.tscn
fpstest vulkan_fps_tile_20km vulkan res://scenes/world/tile_20km.tscn
# Screenshots on Vulkan at 20 km.
run vulkan_real_20km_shots vulkan res://scenes/world/real_20km.tscn full --shots
run vulkan_tile_20km_shots vulkan res://scenes/world/tile_20km.tscn full --shots
log ALL_DONE
