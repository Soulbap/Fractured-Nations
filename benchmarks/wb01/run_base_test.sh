#!/bin/bash
# WORLD-BASE-01: scripted construction checks on the real 20 km world (about 3 minutes).
#   benchmarks/wb01/run_base_test.sh [--shots]
P="/c/Users/Hafnor/Desktop/Game Dev/fractured-nations"
cd "$P"
timeout 600 "../Godot_v4.7.2-stable_win64.exe" --path . --resolution 1600x900 --log-file benchmarks/wb01/base_test.log \
  res://scenes/game/world_core_02.tscn -- --base-test "$@" > /dev/null 2>&1
echo "exit=$?"
grep -E "^BASE|SCRIPT ERROR|FATAL|ERROR" benchmarks/wb01/base_test.log | cut -c1-1200
