#!/bin/bash
# WORLD-INTEGRATION-01: scripted checks on the reference world (run from the repository root
# of the checkout to test; needs the built world, see tools/terrain_ref/build_ref_world.sh).
#   bash benchmarks/wi01/run_test.sh integration [--shots]   construction on ref_20km (~6 min)
#   bash benchmarks/wi01/run_test.sh base [--shots]          the WORLD-BASE-01 test on ref_20km (~4 min)
#   bash benchmarks/wi01/run_test.sh large [--shots]         the WORLD-CORE-02 test on ref_20km (~2 min)
# Godot is expected next to the repository (../Godot_v4.7.2-stable_win64.exe) or in $GODOT.
# Only the process started here is stopped on a timeout; other Godot instances are left alone.
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-../Godot_v4.7.2-stable_win64.exe}"
KIND="${1:-integration}"
shift
LOG="benchmarks/wi01/${KIND}_test.log"
rm -f "$LOG"
timeout 1000 "$GODOT" --path . --resolution 1600x900 --log-file "$LOG" \
  res://scenes/game/world_ref_20km.tscn -- "--${KIND}-test" "$@" > /dev/null 2>&1 &
PID=$!
# A script that fails to parse leaves the game running without the test: stop this run.
while kill -0 $PID 2>/dev/null; do
  if grep -q "Parse Error" "$LOG" 2>/dev/null; then
    echo "parse error, stopping"; kill $PID 2>/dev/null; break
  fi
  sleep 2
done
wait $PID
echo "exit=$?"
grep -E "^(WI01|BASE|LARGE) |SCRIPT ERROR|Parse Error|FATAL" "$LOG" | cut -c1-1500
