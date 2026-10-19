#!/bin/bash
# WORLD-TECH-02 validation: targeted vegetation tests, station benchmark (same stations
# and scenarios structure as the WORLD-TECH-01 fast suite, so numbers are comparable),
# FPS self-test with streamed colliders. Every benchmark run is wrapped by
# tools/measure_run.ps1 (wall time, exit code, peak RAM, peak GPU memory from OS counters).
#   benchmarks/wt02_suite/run_wt02.sh <out_dir>        (STEPS=vegtest|bench|fps to run a part)
P="/c/Users/Hafnor/Desktop/Game Dev/fractured-nations"
GUIW='C:\Users\Hafnor\Desktop\Game Dev\Godot_v4.7.2-stable_win64.exe'
GUI="/c/Users/Hafnor/Desktop/Game Dev/Godot_v4.7.2-stable_win64.exe"
OUT="$1"; mkdir -p "$OUT"; OUTW=$(cygpath -w "$OUT")
cd "$P"
log() { echo "$(date +%H:%M:%S) $*" >> "$OUT/summary.txt"; }
run() { # tag driver scene scenarios [extra script args]
  local tag=$1 drv=$2 scene=$3 sc=$4; shift 4
  log "== $tag driver=$drv [$sc] $*"
  rm -f "$OUT/$tag.log"
  local mem=$(powershell -NoProfile -ExecutionPolicy Bypass -File tools/measure_run.ps1 -Exe "$GUIW" \
    -ArgLine "--path . --resolution 1600x900 --rendering-driver $drv --log-file \"$OUTW\\$tag.log\" --script res://tools/bench_world.gd -- --scene=$scene --tag=$tag --scenarios=$sc $*" \
    -Out "$OUTW\\$tag.mem.json" -TimeoutSec 420 | tr -d '\r')
  log "MEM $mem"
  log "errors: descriptor=$(grep -c 'descriptor heap' "$OUT/$tag.log" 2>/dev/null) script=$(grep -c 'SCRIPT ERROR' "$OUT/$tag.log" 2>/dev/null) shader=$(grep -c 'SHADER ERROR' "$OUT/$tag.log" 2>/dev/null) fatal=$(grep -c 'FATAL' "$OUT/$tag.log" 2>/dev/null)"
  grep -E "^BENCH [a-z]|SCRIPT ERROR|SHADER ERROR|FATAL" "$OUT/$tag.log" | grep -v "stage" | cut -c1-1500 >> "$OUT/summary.txt"
}
vegtest() { # tag scene
  local tag=$1 scene=$2
  log "== vegtest $tag"
  rm -f "$OUT/vegtest_$tag.log"
  timeout 420 "$GUI" --path . --resolution 1600x900 --log-file "$(cygpath -w "$OUT/vegtest_$tag.log")" --script res://tools/test_vegetation.gd -- --scene=$scene --tag=$tag --shots > /dev/null 2>&1
  log "rc=$?"
  grep -E "VEGTEST|SCRIPT ERROR|SHADER ERROR" "$OUT/vegtest_$tag.log" | cut -c1-1500 >> "$OUT/summary.txt"
}
fpstest() { # tag scene
  local tag=$1 scene=$2
  log "== $tag fps-test"
  rm -f "$OUT/$tag.log"
  local mem=$(powershell -NoProfile -ExecutionPolicy Bypass -File tools/measure_run.ps1 -Exe "$GUIW" \
    -ArgLine "--path . --resolution 1600x900 --log-file \"$OUTW\\$tag.log\" $scene -- --fps-test" \
    -Out "$OUTW\\$tag.mem.json" -TimeoutSec 420 | tr -d '\r')
  log "MEM $mem"
  grep -E "DIAG fps-test|SCRIPT ERROR|FATAL|Program crashed" "$OUT/$tag.log" | cut -c1-2500 >> "$OUT/summary.txt"
}
STEPS=${STEPS:-all}
[ "$STEPS" = all ] && : > "$OUT/summary.txt"
SC=full,trees,grass,roads,terrain
if [ "$STEPS" = all ] || [ "$STEPS" = vegtest ]; then
vegtest test_2km res://scenes/world/test_2km.tscn
vegtest real_20km res://scenes/world/real_20km.tscn
fi
if [ "$STEPS" = all ] || [ "$STEPS" = bench ]; then
run v2_vulkan_real_2km vulkan res://scenes/world/test_2km.tscn $SC --shots
run v2_vulkan_real_20km vulkan res://scenes/world/real_20km.tscn $SC --shots
# D3D12 fallback sanity: the per-MultiMesh cost that broke D3D12 in WORLD-TECH-01 no longer scales with the map.
run v2_d3d12_real_20km d3d12 res://scenes/world/real_20km.tscn full
fi
if [ "$STEPS" = all ] || [ "$STEPS" = fps ]; then
fpstest v2_fps_real_2km res://scenes/world/test_2km.tscn
fpstest v2_fps_real_20km res://scenes/world/real_20km.tscn
fi
log ALL_DONE
