#!/bin/bash
# WORLD-TERRAIN-01 targeted checks on the reference world (worlds/ref_20km), same fast-suite
# method as WORLD-TECH-02 (benchmarks/wt02_suite/run_wt02.sh) so the numbers are comparable:
#   - station benchmark (tools/bench_world.gd: FPS centre on the main road, FPS far corner,
#     RTS 150 m, RTS 600 m, strategic; jump test; FPS<->RTS switch test), Vulkan,
#     scenarios full / trees / roads, wrapped by tools/measure_run.ps1 (OS memory counters)
#   - vegetation checks (tools/test_vegetation.gd: mask, clearance, determinism, streaming)
#   - FPS self-test (WorldDiagnostics --fps-test: landing, walking, slopes, tree collision)
# About 5 minutes.   benchmarks/terrain01/run_terrain01.sh <out_dir>  (STEPS=bench|vegtest|fps)
P="$(cd "$(dirname "$0")/../.." && pwd)"
GUI="$P/../Godot_v4.7.2-stable_win64.exe"
GUIW=$(cygpath -w "$GUI")
OUT="$1"; mkdir -p "$OUT"; OUTW=$(cygpath -w "$OUT")
SCENE=res://scenes/world/ref_20km.tscn
STEPS="${STEPS:-bench vegtest fps}"
cd "$P"
log() { echo "$(date +%H:%M:%S) $*" >> "$OUT/summary.txt"; }
if [[ " $STEPS " == *" bench "* ]]; then
  tag=ref_20km_full
  log "== bench $tag"
  mem=$(powershell -NoProfile -ExecutionPolicy Bypass -File tools/measure_run.ps1 -Exe "$GUIW" \
    -ArgLine "--path . --resolution 1600x900 --rendering-driver vulkan --log-file \"$OUTW\\$tag.log\" --script res://tools/bench_world.gd -- --scene=$SCENE --tag=$tag --scenarios=full,trees,roads --shots" \
    -Out "$OUTW\\$tag.mem.json" -TimeoutSec 600 | tr -d '\r')
  log "MEM $mem"
  log "errors: script=$(grep -c 'SCRIPT ERROR' "$OUT/$tag.log") shader=$(grep -c 'SHADER ERROR' "$OUT/$tag.log") fatal=$(grep -c 'FATAL' "$OUT/$tag.log")"
  grep -E "^BENCH [a-z]|SCRIPT ERROR|SHADER ERROR|FATAL" "$OUT/$tag.log" | grep -v "stage" | cut -c1-1500 >> "$OUT/summary.txt"
fi
if [[ " $STEPS " == *" vegtest "* ]]; then
  log "== vegtest ref_20km"
  timeout 600 "$GUI" --path . --resolution 1600x900 --log-file "$(cygpath -w "$OUT/vegtest_ref_20km.log")" --script res://tools/test_vegetation.gd -- --scene=$SCENE --tag=ref_20km --shots > /dev/null 2>&1
  log "rc=$?"
  grep -E "VEGTEST|SCRIPT ERROR|SHADER ERROR" "$OUT/vegtest_ref_20km.log" | cut -c1-1500 >> "$OUT/summary.txt"
fi
if [[ " $STEPS " == *" fps "* ]]; then
  tag=ref_20km_fps
  log "== fps-test"
  mem=$(powershell -NoProfile -ExecutionPolicy Bypass -File tools/measure_run.ps1 -Exe "$GUIW" \
    -ArgLine "--path . --resolution 1600x900 --log-file \"$OUTW\\$tag.log\" $SCENE -- --fps-test" \
    -Out "$OUTW\\$tag.mem.json" -TimeoutSec 600 | tr -d '\r')
  log "MEM $mem"
  grep -E "DIAG fps-test|SCRIPT ERROR|FATAL|Program crashed" "$OUT/$tag.log" | cut -c1-2500 >> "$OUT/summary.txt"
fi
cat "$OUT/summary.txt"
