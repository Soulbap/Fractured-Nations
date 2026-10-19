#!/bin/bash
# WORLD-CORE-02: scripted checks on the real 20 km world (about 3 minutes).
#   benchmarks/wc02/run_large_test.sh [--shots]
P="/c/Users/Hafnor/Desktop/Game Dev/fractured-nations"
cd "$P"
timeout 600 "../Godot_v4.7.2-stable_win64.exe" --path . --resolution 1600x900 --log-file benchmarks/wc02/large_test.log \
  res://scenes/game/world_core_02.tscn -- --large-test "$@" > /dev/null 2>&1
echo "exit=$?"
grep -E "^LARGE|SCRIPT ERROR|FATAL" benchmarks/wc02/large_test.log | cut -c1-900
