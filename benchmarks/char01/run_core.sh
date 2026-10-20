#!/bin/bash
# CHARACTER-01: WORLD-CORE-01 scripted FPS/RTS checks with the infantry character (about 2 min).
#   benchmarks/char01/run_core.sh [--shots] [--old-soldier]
cd "$(dirname "$0")/../.."
timeout 400 "../Godot_v4.7.2-stable_win64.exe" --path . --resolution 1600x900 --log-file benchmarks/char01/core_test.log \
  res://scenes/game/core_demo.tscn -- --core-test --shot-dir=res://docs/character01/godot "$@" > /dev/null 2>&1
echo "exit=$?"
grep -E "^CORE|SCRIPT ERROR|FATAL|ERROR: res" benchmarks/char01/core_test.log | cut -c1-700
