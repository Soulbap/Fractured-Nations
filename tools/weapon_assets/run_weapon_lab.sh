#!/bin/bash
# WEAPON-ASSETS-01 lab runner: re-imports, then validates or photographs the weapon pack in Godot.
#   tools/weapon_assets/run_weapon_lab.sh --validate [ids] | --shots [ids] | --showcase
# NOIMPORT=1 skips the import step; REIMPORT=1 forces the weapon GLBs to re-import.
cd "$(dirname "$0")/../.."
G="../Godot_v4.7.2-stable_win64.exe"
GC="../Godot_v4.7.2-stable_win64_console.exe"
mkdir -p benchmarks/raw benchmarks/weapon_assets01
if [ -n "$REIMPORT" ]; then
  for f in assets/weapons/*/*/*.glb; do rm -f .godot/imported/$(basename "$f")-*; done
fi
if [ -z "$NOIMPORT" ]; then
  timeout 900 "$GC" --headless --path . --import > benchmarks/raw/wl_import.log 2>&1
  grep -E "ERROR|SCRIPT ERROR" benchmarks/raw/wl_import.log | grep -v "RID allocations\|Pages in use\|resources still in use" | head -20
fi
tag=$(echo "$1" | tr -d ' -')
timeout ${WL_TIMEOUT:-600} "$G" --path . --fullscreen --log-file "benchmarks/raw/wl_$tag.log" \
    res://tools/weapon_assets/weapon_lab.tscn -- "$@"
code=$?
grep -E "^WL|SCRIPT ERROR|ERROR: (res|Parse|Failed)" "benchmarks/raw/wl_$tag.log" | head -120
exit $code
