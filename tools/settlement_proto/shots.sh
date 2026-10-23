#!/usr/bin/env bash
# WORLD-SETTLEMENT-02: before/after screenshots of the settlement layer (GUI binary, a few minutes each).
#   tools/settlement_proto/shots.sh [before|after|both] [shots json]
set -e
GODOT_GUI="${GODOT_GUI:-../Godot_v4.7.2-stable_win64.exe}"
OUT=res://docs/world_settlement02
SHOTS="${2:-res://tools/settlement_proto/shots_ws02.json}"
what="${1:-both}"
mkdir -p docs/world_settlement02
if [ "$what" != after ]; then
  "$GODOT_GUI" --path . --resolution 1600x900 --log-file docs/world_settlement02/before.log --script res://tools/terrain_ref/capture.gd -- \
    --shots=$SHOTS --out=$OUT/before --no-settlements
fi
if [ "$what" != before ]; then
  "$GODOT_GUI" --path . --resolution 1600x900 --log-file docs/world_settlement02/after.log --script res://tools/terrain_ref/capture.gd -- \
    --shots=$SHOTS --out=$OUT/after
fi
