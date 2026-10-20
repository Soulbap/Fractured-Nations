# UNIT-01A — Squad control and tactical orders

Branch `feature/unit-01a` (worktree `fractured-nations-unit01a`) is based on
`feature/world-integration-01` (b816565). It has not been merged into `main`, and no other
worktree was changed. The generated `ref_20km` world data was copied into the worktree from
the integration worktree; it is git-ignored, and the build command in the README still
produces it.

All results below come from scripted runs in the actual game: Godot 4.7.2, Vulkan,
RTX 3070, 1600×900, on the 20 km reference world. **Nobody has play-tested this by hand
yet.** Section 9 lists what should be tried by hand.

## Summary

- **Squads.** Squads are persistent records in `WorldState`, with an id, name, faction,
  members, leader, order and formation. The soldiers stay independent units.
- **Test squads.** Three squads are set up for testing:
  - Alpha: 8 North soldiers at site A;
  - Bravo: 4 North soldiers at site A;
  - Sierra: 4 South soldiers at site B.
- **Orders.** The four orders are Move (line or column), Hold, Follow and Regroup.
- **One authority, existing execution.** A squad order becomes one ordinary move order
  per soldier, to its own formation slot. Physical bodies (navmesh plus avoidance) and the
  abstract tier carry these out with the code they already had. There is no second unit
  simulation and no new pathfinding.
- **RTS controls.**
  - Selection: Ctrl+click or the squad panel selects a squad; a plain click still selects
    one soldier.
  - Squad orders: RMB moves, H holds, F + click follows, G regroups, V switches line /
    column, [ ] changes spacing.
  - Feedback: name tags over squad leaders and slot markers in the view.
- **Persistence.** Squads and their orders survive:
  - FPS possession of one member (the others are not touched);
  - camera jumps of 12 km (the squad keeps walking in the abstract tier);
  - save and load.
- **Camera.** The RTS camera zooms 5–200 m and starts at 80 m. Below 40 m it is kept in
  front of walls, trees and terrain.
- **Bug fixes from the testing:**
  - Shift-add selection, which was already broken before this task;
  - soldiers that walked in place forever are now reported as blocked;
  - Follow orders shuffled behind an idle leader.
- **Test results.** The new squad test passes. The WORLD-CORE-02, WORLD-BASE-01 and
  WORLD-INTEGRATION-01 tests were rerun on this branch (section 6).

## 1. Architecture and integration

| Part | Role |
|---|---|
| `SquadState` (`scripts/core/squad_state.gd`) | Plain data for one squad: id, name, faction, `members` (unit ids), `leader_id`, `order` (None / Move / Hold / Follow / Regroup), target and facing, follow target (unit or squad), `formation` (Line / Column), `spacing`, `detached` members, and progress (`status`, `blocked`). |
| `WorldState.squads` | The only authority for squads. It is part of the world snapshot, next to the units and construction. API: `add_squad`, `squad_of`, `set_leader`, `detach`, `issue_individual_moves`, and `apply_snapshot` (load in place). Removing a unit removes it from its squad. |
| `SquadControl` (`scripts/core/squad_control.gd`, owned by `WorldSim`) | Turns squad orders into per-unit move orders through formation slots. Runs twice per second, not per frame, to track progress; Follow targets are re-checked once per second. |
| `RTSController` | Squad selection and the order keys. Orders always go to `WorldState` / `SquadControl`, never to bodies. |
| `SquadPanel`, `GameHUD` overlay | A compact list (name, faction, size, formation, order and progress) and the in-view feedback. Display only. |
| `SoldierBody` | Unchanged navmesh walking, plus stuck handling (section 4). |
| `WorldSim` | Calls `SquadControl.update`. After a load it moves bodies to their restored records, and it removes bodies whose units are gone. |

**Why this design.** Squads add no simulation of their own. A squad order is translated
once into per-unit move orders: `UnitState.order` and `order_target`, the same fields the
RTS and the abstract tier already use. Everything that was already true for those orders
therefore holds for squads too:
- possession suspends the order without losing it;
- bodies use the navmesh and RVO avoidance;
- abstract units walk in straight lines and stop or slide at walls (WORLD-INTEGRATION-01);
- detailed ↔ abstract transitions keep the record.

The squad record only says who belongs together, what they were told, and how far they
have come.

**Spawn layout.**
- Site A now has 12 North soldiers instead of 10, organised as Alpha (8) and Bravo (4). The
  WC-02 test expectations were updated to 28 soldiers.
- At site B, four South soldiers form Sierra. The other four keep their individual
  300 m start order, which the WC-02 abstract-tier check uses.
- Site C stays unorganised, as an example of plain unit control.
- Bravo's start order is now a squad move.

## 2. Controls (RTS)

| Input | Effect |
|---|---|
| Click soldier | Selects that soldier, as before |
| Ctrl+click soldier | Selects the soldier's whole squad (Shift adds) |
| Squad panel row (left) | Selects that squad; Shift+click adds |
| Drag box, Shift+click, Ctrl+A | As before. A squad counts as selected when all its members are |
| RMB | **Move.** Selected squads walk to the point in formation, facing the direction of travel. Several squads stand side by side with a 5 m gap. Other selected soldiers get individual orders next to them, which detaches them from their squad's order until its next order |
| H | **Hold.** Squads stop and stay; individual soldiers stop |
| F, then LMB on a soldier | **Follow** that soldier, or its squad if it has one (tracked through the squad's leader). Esc cancels |
| G / Shift+G | **Regroup** on the leader (the leader stays put) / at the cursor |
| V | Line ↔ column for the selected squads (also re-shapes a running Move or Regroup) |
| [ / ] | Spacing −/+ 0.5 m (1.5–10 m, default 3 m) |
| P, Enter, double-click, Tab | Possession, as before. The possessed soldier's squad keeps its order |
| F5 / F9 | Save / load: construction (`construction.json`) **plus units and squads** (`world.json`, same folder) |
| Wheel | Zoom 5–200 m, starts at 80 m |

**Feedback in the view:**
- A ring on each selected soldier, as before.
- A name tag with the current order over each selected squad's leader, with a yellow
  leader dot.
- While moving, a dot on each soldier's formation slot and a thin line to it.
- The HUD lists the selected squads, the key help and short confirmations ("Following
  Alpha", "Formation: Column").
- In FPS, the HUD shows the possessed soldier's squad and its order.

## 3. Squad state and persistence

| Situation | How | Measured |
|---|---|---|
| FPS ↔ RTS | Orders live in the records; switching changes only `player_controlled` | — |
| Possession of a member mid-move | The possessed soldier's order is suspended (not lost); the others are untouched | 7 of 7 others kept the same target and arrived. The possessed soldier moved 0.06 m without input in 5 s, kept its target, and arrived after Tab |
| Detailed ↔ abstract | Per-unit orders carry over between tiers | 12 km camera jump: all 8 abstract while away, minimum 1.5 m apart, squad record unchanged, 8 bodies back on return, then arrived |
| Save / load | `WorldState.save_file` / `load_file` (`var_to_str`, keeps Vector3 values exact) with F5 / F9. Load writes into the existing records, so bodies and proxies stay attached, and moves bodies to the loaded positions | 11.6 KB `world.json`. After changing order, formation, follow target and leader, F9 restored all three squads byte-identical (JSON of every record), positions within 0.15 m. The interrupted Move then resumed and finished |
| Formation, spacing, leader, detached members, follow target | All fields of `SquadState` | Included in the identical-after-load check |

Construction keeps its own JSON file from WORLD-BASE-01. `world.json` holds units and
squads. Both are written and read by the same F5 / F9.

## 4. Formation and navigation behaviour

**Slots:**
- **Line:** across the facing direction, leader in the middle, then alternating right and
  left.
- **Column:** single file behind the leader.
- **Facing:** the direction from the squad's centre to the target.

**Assignment:**
- The leader takes slot 0.
- The others are matched to slots by their order across (line) or along (column) the
  facing, so paths cross little.
- A slot that falls in water or inside a structure moves to the nearest free spot within
  6 m.

**Slots are preferences.** Each soldier walks to its slot with its own navmesh path and RVO
avoidance, so it can step aside for others and go around walls. Arrival tolerance is
1.3 m, as before. No path is recomputed per frame:
- a squad order sets each soldier's target once;
- Follow re-checks once per second and re-issues only when a slot has moved more than 4 m;
- slots are placed 1 s ahead of a walking target, and do not move while the target
  stands.

**Blocked movement is reported.**
- **Unreachable slot:** if the navmesh path ends more than 3 m from the slot, the soldier
  ends its order as BLOCKED. This is the existing logic.
- **Stuck in place (new):** a soldier that walks but gains less than 0.8 m in 3 s first
  re-queries its path. It then ignores crowd avoidance for 1.5 s, because two agents can
  hold each other in a gap. If it is still stuck after another 3 s, it ends as BLOCKED.
  Before this, one soldier in a test walked in place for 70 s without being reported.
- **Squad status:** the squad reports "moving", "in position" or "N blocked" (panel and
  `SquadState.blocked`).

**Measured** (test area: open meadow at (-1107, -7885); base: a 40×40 m HESCO square with
a 6-cell south entrance and a barracks, on open ground at (-1412, -8343)):

| Check | Result |
|---|---|
| 8 soldiers, line, 70 m | done in 16.6 s; 8/8 arrived; 8 distinct slots; final minimum spacing 2.31 m; closest approach while walking 0.89 m (two 0.35 m capsules touch at 0.7 m) |
| Same, column | done in 17.0 s; 8/8; minimum spacing 2.5 m |
| Two squads pass head-on (Alpha 8 east, Sierra 4 west) | both done in 17.1 s; closest soldier pair between the squads 0.9 m (passing, not stuck) |
| Around a structure: from 40 m north of the HESCO base to its inside (entrance on the south side) | done in 27.5 s; 8/8 inside; 0 frames inside a wall; minimum spacing 2.75 m |
| Hold | drift 0.00 m over 3 s, no orders left |
| Follow (Bravo follows Alpha, Alpha walks 80 m) | Bravo 4/4 behind Alpha's leader, within 9.9 m; final spacing 2.8 m. While Alpha walks: 0.87 orders per soldier per second. Settling: 4 orders in 6 s. While Alpha stands: 0 |
| Regroup (7 soldiers individually sent 25 m away, then G) | the 7 detached rejoin; spread 23.9 → 13.0 m (an 8-man line at 3 m is ±12 m); done in 9.7 s |
| Unreachable target (squad ordered into a closed HESCO square) | 4/4 reported BLOCKED in 8.9 s, status PARTIAL, panel "4 blocked", nobody inside the wall |

Screenshots show a slot that cannot be kept, such as the line overlapping a barracks
inside the base. It is moved to free ground nearby instead of making the squad fail.

## 5. RTS camera

| Setting | Value |
|---|---|
| `zoom_min` / `zoom_max` / `zoom_default` | 5 / 200 / 80 m (exported, configurable) |
| Pitch | 28° at 5 m to 65° at 200 m, log scale as before |
| Ground clearance | 1.2 m at 5 m, rising to 3 m by 40 m |
| Obstacles | below 40 m, one ray per frame from the focus point (1.6 m up) to the camera keeps the camera 0.4 m in front of the first static obstacle (structures, tree colliders, terrain). Soldiers and vehicles are ignored |

**Measured:**
- The wheel reached exactly 5.00 and 200.00 m.
- At 5 m next to the base wall the camera was 2.45 m above the ground and not inside the
  structure.
- Panning at 5 m works (2.7 m in 0.6 s).
- A soldier can still be clicked at 200 m.
- The FPS camera is unchanged.

## 6. Test results

| Suite | Result |
|---|---|
| `bash benchmarks/unit01a/run_test.sh squad --shots` (new, about 7 min) | **PASS**, 0 failures (`benchmarks/unit01a/unit_test.json`, log alongside) |
| WORLD-CORE-02 `large` (28 soldiers now; abstract orders, 8 km possession jumps, N cycling, tier transitions) | **PASS** |
| WORLD-BASE-01 `base` (construction; zoom check now 5 / 200 m) | **PASS** |
| WORLD-INTEGRATION-01 `integration` (5 environments, clearing, groundwork, save/load) | **PASS** |

The three earlier suites ran unchanged, except for:
- the expected soldier count (26 → 28);
- the zoom limits (15 / 300 → 5 / 200 m).

Their JSON results are in `benchmarks/unit01a/`. They ran without `--shots`, so the
committed WB-01 / WC-02 / WI-01 screenshots were not overwritten.

**Bugs found by the test and fixed:**
- **`RTSController.select()` cleared the list it was given.** `Array(selected)` returns the
  same array, not a copy, so every "add to selection" (Shift+click, Shift+drag) ended with
  an empty selection. This was already the case before UNIT-01A. `select()` now copies its
  input.
- **A soldier could walk in place indefinitely.** The stuck handling in section 4 fixes
  this.
- **Follow re-issued orders while the followed leader stood still**, because the leader's
  idle turning moved the slots. A standing target now keeps the last walking direction.

## 7. Performance

Same machine and resolution as WORLD-INTEGRATION-01. Frame times are CPU ms, average /
p99 / worst.

| Measurement | WORLD-INTEGRATION-01 | UNIT-01A |
|---|---|---|
| RTS, 150 m over the open base | 1.90 / 2.22 / 2.24 | — |
| RTS, 80 m, three squads (16 soldiers) walking | — | 2.19 / 3.10 / 3.16 |
| RTS, 15 m over a base | 2.16 / 2.66 / 2.69 | 1.99 / 2.30 / 2.48 |
| RTS, 300 m → now 200 m (the maximum) | 2.13 / 2.59 / 2.71 (300 m) | 1.94 / 2.91 / 3.00 (200 m) |
| FPS inside a base / inside a squad (16 bodies near) | 1.97 / 2.39 / 2.57 | 2.42 / 3.52 / 3.55 |
| Squad Move order for 8 soldiers (slots, assignment, 8 orders) | — | 0.086 ms |
| `SquadControl.update` (all squads, one tick) | — | 0.014 ms |
| Long camera jump, worst frame | 399–413 ms | 395–408 ms (unchanged: Terrain3D collision rebuild, see the WI-01 report) |

The squad layer costs well under 0.1 ms. Frame times with three squads walking are in the
same range as the integration build. The higher FPS figure has more soldier bodies in
view: 16 walking soldiers versus 2 in the WI-01 base scene.

## 8. Screenshots (`docs/unit01a/`)

| Required | File |
|---|---|
| Squad selection | `u01a_squad_selection.jpg` (Alpha + Bravo selected through Ctrl+click and the panel; tags, rings, panel) |
| Line formation | `u01a_line_formation.jpg` (slots and paths while moving), `u01a_line_formation_done.jpg` |
| Column formation | `u01a_column_formation.jpg`, `u01a_column_formation_done.jpg` |
| Movement around obstacles | `u01a_around_base.jpg` (Alpha going around the HESCO base to the south entrance; slot markers inside) |
| Also | `u01a_squads_passing.jpg`, `u01a_follow.jpg`, `u01a_regroup.jpg`, `u01a_blocked_box.jpg`, `u01a_fps_possessed_in_squad.jpg`, `u01a_after_possession.jpg`, `u01a_after_jump.jpg`, `u01a_after_load.jpg`, `u01a_zoom_5m.jpg`, `u01a_zoom_200m.jpg` |

## 9. Known limitations

- **Abstract tier.** Far from the camera, squad members walk straight to their slots and
  stop or slide at walls. They do not look for gates (the WORLD-INTEGRATION-01
  limitation). When the camera comes near, they get bodies and real paths.
- **Formation while walking.** Slots apply at the destination. On the way, each soldier
  takes its own path, so a line is not kept while walking and soldiers can bunch briefly
  (closest approach about 0.7–0.9 m). There is no formation-keeping march yet.
- **Follow cadence.** Follow sends about one new target per soldier per second while the
  followed unit walks. Follow is for squads only; individual soldiers cannot be given a
  Follow order.
- **Squad editing.** Squads are created in code (`WorldState.add_squad`). There is no UI
  to form, split or merge squads, or to change the leader (`set_leader` exists).
- **Line width.** Line formation centres on the leader; a very wide line (8 × 10 m) can
  get slots moved off water or structures.
- **Save scope.** `world.json` restores units and squads by id. A save from a world with
  different unit ids (another spawn layout) adds or removes units to match.
- **Two save files.** Construction and units are saved separately but with the same key.
- **Panel.** The panel lists all squads of both factions, because test control of every
  faction is still on (`command_any_faction`).
- **Long jumps** still hitch about 0.4 s (WORLD-INTEGRATION-01, Terrain3D collision).

## 10. Needs manual playtesting

- **Feel of the controls:** selecting squads with Ctrl+click and the panel, F + click,
  G / Shift+G, V and [ ] in normal play. Are the keys and feedback clear?
- **Watching a squad walk:** is the loose movement (no formation on the way) acceptable,
  and is 3 m spacing right?
- **Formation on terrain:** line and column on slopes, in forest and through gates of your
  own bases.
- **Following from first person:** possess a soldier, give another squad a Follow on it
  from RTS, then walk around in FPS.
- **Possession inside a squad:** possess a squad member during a Move, walk somewhere else,
  Tab back, and check that it rejoins its slot.
- **Long sessions:** F5, quit the game, start again, F9.
- **Camera:** the 5 m zoom near buildings and trees, and whether 80 m is a good start
  height.
