#!/bin/bash
# WORLD-SANDBOX-01 / COMBAT-02 / COMBAT-01B / COMBAT-01A / UNIT-01A / WORLD-INTEGRATION-01: scripted checks on the reference world (run from the repository root
# of the checkout to test; needs the built world, see tools/terrain_ref/build_ref_world.sh).
#   bash benchmarks/sandbox01/run_test.sh sandbox [--shots] [--only a,b] [--minutes N]  WORLD-SANDBOX-01 war scenarios
#   bash benchmarks/sandbox01/run_test.sh combat-tactics [--shots]  COMBAT-02 tactical reactions, cover, orders, persistence
#   bash benchmarks/sandbox01/run_test.sh combat-scale [--shots]    COMBAT-02 16/50/100 v N and two battles (--scale-only N)
#   bash benchmarks/sandbox01/run_test.sh combat-ai [--shots]     COMBAT-01b AI perception and firefights (~15 min)
#   bash benchmarks/sandbox01/run_test.sh squad --follow-repeat N  only the UNIT-01A Follow check, N times
#   bash benchmarks/sandbox01/run_test.sh combat [--shots]        COMBAT-01a combat core and FPS rifle (~5 min)
#   bash benchmarks/sandbox01/run_test.sh squad [--shots]         UNIT-01A squads and orders (~6 min)
#   bash benchmarks/sandbox01/run_test.sh integration [--shots]   construction on ref_20km (~8 min)
#   bash benchmarks/sandbox01/run_test.sh base [--shots]          the WORLD-BASE-01 test on ref_20km (~4 min)
#   bash benchmarks/sandbox01/run_test.sh large [--shots]         the WORLD-CORE-02 test on ref_20km (~2 min)
# Godot is expected next to the repository (../Godot_v4.7.2-stable_win64.exe) or in $GODOT.
# Only the process started here is stopped on a timeout; other Godot instances are left alone.
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-../Godot_v4.7.2-stable_win64.exe}"
KIND="${1:-integration}"
shift
LOG="benchmarks/sandbox01/${KIND}_test.log"
rm -f "$LOG"
timeout 7200 "$GODOT" --path . --resolution 1600x900 --log-file "$LOG" \
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
grep -E "^(SANDBOX|SCALE|TAC|AI|COMBAT|UNIT|WI01|BASE|LARGE) |SCRIPT ERROR|Parse Error|FATAL" "$LOG" | cut -c1-1500
