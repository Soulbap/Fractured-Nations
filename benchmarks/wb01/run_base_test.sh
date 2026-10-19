#!/bin/bash
# WORLD-BASE-01: scripted construction checks on the real 20 km world (about 3 minutes).
#   benchmarks/wb01/run_base_test.sh [--shots]
# Stops the game early when a script fails to compile (the test would never start).
P="/c/Users/Hafnor/Desktop/Game Dev/fractured-nations"
cd "$P"
LOG=benchmarks/wb01/base_test.log
rm -f "$LOG"
timeout 480 "../Godot_v4.7.2-stable_win64.exe" --path . --resolution 1600x900 --log-file "$LOG" \
  res://scenes/game/world_core_02.tscn -- --base-test "$@" > /dev/null 2>&1 &
PID=$!
for i in $(seq 1 90); do
  sleep 1
  if grep -qE "Parse Error|Compile Error|Failed to load script" "$LOG" 2>/dev/null; then
    echo "compile error, stopping"; kill $PID 2>/dev/null; taskkill //F //IM Godot_v4.7.2-stable_win64.exe > /dev/null 2>&1; break
  fi
  grep -q "^BASE base_site" "$LOG" 2>/dev/null && break
  kill -0 $PID 2>/dev/null || break
done
wait $PID
echo "exit=$?"
grep -E "^BASE|SCRIPT ERROR|FATAL" "$LOG" | cut -c1-1200
