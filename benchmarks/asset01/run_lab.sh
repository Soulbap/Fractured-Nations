#!/bin/bash
# ASSET-PRODUCTION-01 lab runner: re-imports, then runs the asset lab in one mode.
#   benchmarks/asset01/run_lab.sh --shots [filter] | --validate [filter] | --lod [filter] | ...
# Set NOIMPORT=1 to skip the import step, REIMPORT=1 to force the library GLBs to re-import.
cd "$(dirname "$0")/../.."
G="../Godot_v4.7.2-stable_win64.exe"
GC="../Godot_v4.7.2-stable_win64_console.exe"
mkdir -p benchmarks/raw
# REIMPORT=1 forces the library GLBs to re-import (after changing ap_post_import.gd).
if [ -n "$REIMPORT" ]; then
  for f in assets/military/*/*.glb; do rm -f .godot/imported/$(basename "$f")-*; done
fi
if [ -z "$NOIMPORT" ]; then
  timeout 900 "$GC" --headless --path . --import > benchmarks/raw/ap_import.log 2>&1
  grep -E "ERROR|SCRIPT ERROR" benchmarks/raw/ap_import.log | grep -v "RID allocations" | head -20
fi
tag=$(echo "$1" | tr -d ' -')
timeout ${AP_TIMEOUT:-600} "$G" --path . --resolution ${AP_RES:-1600x900} --log-file "benchmarks/raw/ap_lab_$tag.log" \
    res://scenes/asset_lab/asset_lab.tscn -- "$@"
code=$?
grep -E "^AP|SCRIPT ERROR|ERROR: (res|Parse|Failed)" "benchmarks/raw/ap_lab_$tag.log" | grep -v "RID allocations" | head -120
exit $code
