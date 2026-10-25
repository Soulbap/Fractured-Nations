#!/bin/bash
# VEHICLE-ASSETS-01 lab runner: re-imports, then validates or photographs the vehicle pack in Godot.
#   tools/vehicle_assets/run_vehicle_lab.sh --validate [ids] | --shots [ids]
# NOIMPORT=1 skips the import step; REIMPORT=1 forces the vehicle GLBs to re-import.
cd "$(dirname "$0")/../.."
G="../Godot_v4.7.2-stable_win64.exe"
GC="../Godot_v4.7.2-stable_win64_console.exe"
mkdir -p benchmarks/raw benchmarks/vehicle_assets01
if [ -n "$REIMPORT" ]; then
  for f in assets/military/vehicles/*/*.glb; do rm -f .godot/imported/$(basename "$f")-*; done
fi
if [ -z "$NOIMPORT" ]; then
  timeout 900 "$GC" --headless --path . --import > benchmarks/raw/vl_import.log 2>&1
  grep -E "ERROR|SCRIPT ERROR" benchmarks/raw/vl_import.log | grep -v "RID allocations\|Pages in use\|resources still in use" | head -20
fi
tag=$(echo "$1" | tr -d ' -')
timeout ${VL_TIMEOUT:-600} "$G" --path . --fullscreen --log-file "benchmarks/raw/vl_$tag.log" \
    res://tools/vehicle_assets/vehicle_lab.tscn -- "$@"
code=$?
grep -E "^VL|SCRIPT ERROR|ERROR: (res|Parse|Failed)" "benchmarks/raw/vl_$tag.log" | head -120
exit $code
