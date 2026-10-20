#!/bin/bash
# CHARACTER-01: WORLD-CORE-02 scripted checks on the 20 km world with the infantry character
# (about 3 minutes). Needs worlds/real_20km (gitignored, copy or rebuild it first).
#   benchmarks/char01/run_large.sh [--shots] [--old-soldier]
cd "$(dirname "$0")/../.."
timeout 600 "../Godot_v4.7.2-stable_win64.exe" --path . --resolution 1600x900 --log-file benchmarks/char01/large_test.log \
  res://scenes/game/world_core_02.tscn -- --large-test --shot-dir=res://docs/character01/godot "$@" > /dev/null 2>&1
echo "exit=$?"
grep -E "^LARGE|SCRIPT ERROR|FATAL" benchmarks/char01/large_test.log | cut -c1-900
