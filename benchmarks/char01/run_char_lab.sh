#!/bin/bash
# CHARACTER-01 lab runner: imports, then runs the lab in a mode with a timeout.
#   benchmarks/run_char_lab.sh --shots | --checks | "--perf 60" ["--old"]
cd "$(dirname "$0")/../.."
G="../Godot_v4.7.2-stable_win64.exe"
GC="../Godot_v4.7.2-stable_win64_console.exe"
mkdir -p benchmarks/raw
timeout 600 "$GC" --headless --path . --import > benchmarks/raw/char_import.log 2>&1
tag=$(echo "$*" | tr -d ' -')
timeout ${CHAR_TIMEOUT:-300} "$G" --path . --resolution 1600x900 --log-file "benchmarks/raw/char_lab_$tag.log" \
    res://scenes/characters/character_lab.tscn -- "$@"
code=$?
grep -E "^CHAR|SCRIPT ERROR|ERROR: (res|Parse|Failed)" "benchmarks/raw/char_lab_$tag.log" | grep -v "RID allocations" | head -80
exit $code
