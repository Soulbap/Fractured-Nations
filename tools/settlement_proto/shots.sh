#!/usr/bin/env bash
# WORLD-SETTLEMENT-01: before/after screenshots of the Haugen prototype (GUI binary, ~2 min each).
#   tools/settlement_proto/shots.sh [before|after|both]
set -e
GODOT_GUI="${GODOT_GUI:-../Godot_v4.7.2-stable_win64.exe}"
OUT=res://docs/world_settlement01
what="${1:-both}"
if [ "$what" != after ]; then
  "$GODOT_GUI" --path . --resolution 1600x900 --log-file docs/world_settlement01/before.log --script res://tools/terrain_ref/capture.gd -- \
    --shots=res://tools/settlement_proto/shots_haugen.json --out=$OUT/before
fi
if [ "$what" != before ]; then
  "$GODOT_GUI" --path . --resolution 1600x900 --log-file docs/world_settlement01/after.log --script res://tools/terrain_ref/capture.gd -- \
    --shots=res://tools/settlement_proto/shots_haugen.json --out=$OUT/after --settlement-proto=haugen
fi
