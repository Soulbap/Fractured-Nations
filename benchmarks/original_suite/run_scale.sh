#!/bin/bash
# Scalability suite: build + load timing + benchmark per world size.
P="/c/Users/Hafnor/Desktop/Game Dev/fractured-nations"
G="/c/Users/Hafnor/Desktop/Game Dev/Godot_v4.7.2-stable_win64_console.exe"
OUT="$1"
cd "$P"
F='leaked|^\s+at: |PagedAllocator|still in use|Leaked instance|godot_ai|instance_reset_physics|GDScript backtrace|^\s+\[[0-9]+\]'
measure() { # name scene
  local name=$1 scene=$2
  echo "== $name load" >> "$OUT/summary.txt"
  local t0=$(date +%s%3N)
  timeout 600 "$G" --path . --resolution 1600x900 "$scene" -- --quit-after-load > "$OUT/${name}_load.log" 2>&1
  local t1=$(date +%s%3N)
  echo "wall_ms_launch_to_exit=$((t1-t0))" >> "$OUT/summary.txt"
  grep -E "DIAG load" "$OUT/${name}_load.log" >> "$OUT/summary.txt"
  echo "== $name benchmark" >> "$OUT/summary.txt"
  timeout 900 "$G" --path . --resolution 1600x900 "$scene" -- --benchmark > "$OUT/${name}_bench.log" 2>&1
  grep -E "DIAG (benchmark|result)" "$OUT/${name}_bench.log" >> "$OUT/summary.txt"
  grep -vE "$F" "$OUT/${name}_bench.log" | grep -E "ERROR|WARNING" | sort | uniq -c | sort -rn | head -5 >> "$OUT/summary.txt"
  echo "== $name editor open" >> "$OUT/summary.txt"
  t0=$(date +%s%3N)
  timeout 600 "$G" --editor --path . "$scene" --quit-after 600 > "$OUT/${name}_editor.log" 2>&1
  t1=$(date +%s%3N)
  echo "editor_wall_ms_600_frames=$((t1-t0)) rc=$?" >> "$OUT/summary.txt"
}
build() { # name size extra
  local name=$1; shift
  echo "== $name build" >> "$OUT/summary.txt"
  local t0=$(date +%s%3N)
  timeout 3600 "$G" --headless --path . --script res://tools/build_world.gd -- --name=$name "$@" > "$OUT/${name}_build.log" 2>&1
  local t1=$(date +%s%3N)
  echo "build_wall_ms=$((t1-t0))" >> "$OUT/summary.txt"
  grep -E "^(BUILD|WorldBuilder)" "$OUT/${name}_build.log" >> "$OUT/summary.txt"
  grep -E "SCRIPT ERROR" "$OUT/${name}_build.log" | head -3 >> "$OUT/summary.txt"
  du -sh "worlds/$name/terrain" >> "$OUT/summary.txt"
}
: > "$OUT/summary.txt"
measure test_2km res://scenes/world/test_2km.tscn
build scale_4km --size=4096
measure scale_4km res://scenes/world/scale_4km.tscn
build scale_8km --size=8192 --grass-extent=2048
measure scale_8km res://scenes/world/scale_8km.tscn
echo ALL_DONE >> "$OUT/summary.txt"
