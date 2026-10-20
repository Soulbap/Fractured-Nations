# WORLD-SANDBOX-01B — War simulation reliability and gameplay readiness

Branch `feature/world-sandbox-01b`, based on `feature/world-sandbox-01` (c003e1c), in its own
worktree (`fractured-nations-sandbox01b`). No other worktree was changed and nothing was
merged into `main`.

All results come from scripted runs of the real game: Godot 4.7.2, Jolt, Vulkan, RTX 3070,
1600×900, `ref_20km`, vsync off. The screenshots in `docs/sandbox01b/` are captures of the
running game, not mockups.

**Nobody has play-tested this by hand.** The automated runs show that the mechanics work and
what they cost. They cannot say whether the war is fun, readable at a glance or well paced.
§9 lists what the first manual session should judge.

## Summary

| Area | Before (01) | After (01B) |
|---|---|---|
| Accelerated test step | `time_scale` only: steps up to 0.4–0.53 s | Same fixed 1/60 s steps as normal play; the speed actually reached is measured and reported |
| A 90 s fight, shots at 1× vs accelerated 24× | 382 vs 205 (−46 %) | 382 vs 313 (fixed steps) |
| Squad markers | Moved into a row beside objectives (not at their real position) | Always at the real position; overlapping markers become one group marker at the group's real centre |
| Zoom | Instant, 0.03–1.5 px/m | Smooth, towards the cursor, whole map down to 2 px/m; three levels of detail |
| Operation feedback | One-line list entry | Selectable on the map or in the list: squads, strength, phase, march progress, measured arrival estimate, outcome |
| Order buttons | Attack / Defend / Reinforce could not be used by clicking (selecting an objective cleared the squads); Move did nothing | Clicking an objective with squads selected makes it their target; buttons without a target wait for a click |
| HUD in normal play | 8 lines of controls and counters, frame-time overlay on | Faction badge, 2 lines; F1 all controls, F3 counters + frame-time overlay |
| 8× time compression, war far away | Frames up to 440 ms, 5.6× reached (measured now; same code as 01) | Frames ≤ 118 ms, 6.7× reached, shown as "8x (reached 6.7x)" |
| AI, 30 sim-min | South attacked East's fortified HQ with 16 soldiers; 4 South ops (2 completed) | No HQ attacks below the estimated garrison; 7 South ops (5 completed); both AIs move reserves to the front |

Every targeted check passed in its final run (§6). Map, RTS and 50 v 50 frame times are at the
level of the old code measured under the same conditions (§7).

## 1. Accelerated simulation testing

**Problem.** The test helper `_warp` (and the autonomous war loop and the 8× performance
case) raised `Engine.time_scale` alone. Godot then stretches every physics step: up to
0.4–0.53 s per step at 24–32×. The in-game compression already kept 1/60 s steps, so the two
ran different simulations.

**Fix.**
- **One implementation.** The new `scripts/core/time_compression.gd` (`TimeCompression`) is
  now the single implementation. `CoreDemo.apply_time_scale` (the player's `,` / `.` keys)
  and every test path call it:
  - `apply(k, max_steps)` sets `physics_ticks_per_second = 60·k` together with
    `time_scale = k`, so the step stays k / (60·k) = 1/60 s;
  - `reset()` returns to 1×;
  - `_warp` resets in every case.
- **Measured speed.** `_warp` measures the speed actually reached (simulated seconds per real
  second) and the largest step. It records every accelerated stretch in the results
  (`warps`), and its real-time safety limit grows so that at least 6× is allowed.
- **Old behaviour kept for comparison.** The old coarse behaviour remains only as an explicit
  `coarse` option of the comparison check.

**Comparison** (`warp_fidelity`, `benchmarks/sandbox01b/fidelity_and_war.log`):
- Two North squads and two South squads advance towards each other on open ground, with the
  camera far away, as in the accelerated scenarios.
- Each mode runs 90 simulated seconds with the same random seed.
- Fights are not deterministic (timing, random spread), so the check compares magnitudes, not
  exact values.

| Mode | Largest step | Speed reached | First shot | Shots N / S | Hits | Left N / S |
|---|---|---|---|---|---|---|
| 1× (reference) | 0.0167 s | 1.0× | 20.6 s | 206 / 176 | 79 | 0 / 6 |
| 8× fixed step | 0.0167 s | 7.5× | 20.5 s | 150 / 175 | 72 | 0 / 10 |
| 24× fixed step | 0.0167 s | **8.5×** | 20.5 s | 158 / 155 | 87 | 2 / 2 |
| 24× old (`time_scale` only) | **0.4 s** | 23.9× | 21.2 s | 145 / **60** | 68 | **11** / 2 |

- **Fixed-step runs:** they stay in the range of the 1× fight: both sides fire 150–206 shots
  and one side is (nearly) wiped out.
- **Old method:** with stretched steps South fired only a third of its shots, and North kept
  11 of 16 soldiers.
- **Requested vs reached:** requesting 24× does not give 24×. This machine reaches about
  8.5–13× depending on how much fighting there is (8.5× with the fight above, 12–13× in the
  quiet abstract war of §4).

**Consequence for earlier results.** The scenario results of WORLD-SANDBOX-01 were obtained
with the coarse steps; their mechanics conclusions stand, but their combat details were
coarser than play. The scenarios now run with fixed steps; those not rerun here (§6) will be
slower in real time (about 8–13× instead of 12–32×).

## 2. Strategic map readability

Reworked inside the existing `scripts/ui/strategic_map.gd`. It uses the same renderer (one
`_draw`) and the same API, with no new rendering system.

**Geographic accuracy.**
- **No offsets.** Every squad marker is drawn at the squad's real position, the centre of its
  living soldiers. The WORLD-SANDBOX-01 row of markers beside objectives (`squad_marker_pos`)
  moved markers by up to 100 px and is gone.
- **Grouping on screen.** Squads whose markers would overlap at the current zoom (30 / 24 /
  16 px by level) are drawn as one group marker at the mean of their real positions:
  - stacked frames with "3 sq · 24";
  - the check measured 0.0 m between the group marker and the real centre of its squads.
- **Splitting.** Zooming in splits groups as soon as their real separation allows. The check
  shows four squads 70–140 m apart: two markers at 0.06 px/m, three at 0.25, four at 0.9.
- **Presentation only.** Grouping never touches unit positions, formations, navigation or any
  state.
- **Real-position selection and orders.** Box selection uses the squads' real positions, and
  right-click orders use the clicked world point. Clicking a group selects all of its squads;
  double-clicking zooms in until they separate.

**Zoom and levels of detail.**
- **Smooth zoom.** The wheel (and trackpad pinch) zoom animates towards the cursor. The world
  point under the cursor moved 2.7 m over a ×2.5 zoom.
- **Range.** From the whole 20 km map down to 2 px/m (a 56 m HQ perimeter is about 110 px wide).
  Pan and zoom use real time, so they no longer speed up with time compression.
- **Strategic level (whole map):**
  - compact markers;
  - squads standing in an objective show as a garrison badge on that objective, with a short
    leader line, so the objective symbol stays visible.
- **Operational level (a few km):** individual squad symbols with names, routes and labels.
- **Close level (a base):**
  - the capture zone;
  - from 1 px/m, every soldier as a dot under its squad's marker.

**Readability.**
- **Territory:**
  - nearest-objective cells at 256² instead of 160², built once (an ownership change only
    recolours);
  - borders stronger, fill lighter;
  - linear filtering;
  - opacity fades from 0.75 on the overview to 0.3 close in, so the terrain stays
    recognisable.
- **Objective states:**
  - **CONTESTED** (blinking ring and tag);
  - **THREATENED** (red warning triangle and tag: enemies seen within 600 m of one of your
    objectives);
  - the capture arc gets a dark track behind it.
  - The capture zone is only drawn once it is larger than the symbol.
- **Labels:** objective names, group labels, operation labels and markers reserve their screen
  rectangles. Each label takes the first free place: below, then right, then left, then above.
  - Objective names and group labels always show.
  - A single squad's label is left out at the whole-map level when there is no room; its name
    is in the panel and appears when zoomed in.
- **Routes:**
  - the remaining route of every squad, as an even dashed line with a dark outline;
  - an arrowhead at the end and the staging point of an attack;
  - colours by type (attack red, reinforce green, defend faction colour, move white);
  - the selected operation is drawn stronger and the others fade.
  - Operation labels are boxed, stacked when several share a target, and clickable.
- **Panel order:**
  1. "You command NORTH";
  2. war time and speed;
  3. the factions;
  4. the selection;
  5. the order buttons with a context hint;
  6. the operations list, including ended ones;
  7. the war log.
- **Help:** H shows a short controls box on the map; the hint line says so.

Before and after (same 1600×900 view size):

| Before (01) | After (01B) |
|---|---|
| `docs/sandbox01/s01_11_map_after_autonomous_war.jpg`: markers moved into rows beside HQ / Elvetun, covering names | `docs/sandbox01b/s01b_01_full_map.jpg`: garrison badges "3 sq · 24", "5 sq · 40", objective symbols free |
| `docs/sandbox01/s01_10_multiple_operations.jpg`: routes as broken long dashes, labels over objective names | `docs/sandbox01b/s01b_03_selected_operation.jpg`: continuous dashed route, boxed label, operation details in the panel |
| `docs/sandbox01/s01_03_force_markers.jpg`: blocky territory edges at zoom | `docs/sandbox01b/s01b_04b_contested_objective_operational.jpg`: smooth borders, CONTESTED tag |
| `docs/sandbox01/s01_08_rts_active_operation.jpg`: 8-line HUD plus frame-time overlay | `docs/sandbox01b/s01b_08_tactical_start_hud.jpg`: faction badge, 2-line HUD |

The required screenshots (`docs/sandbox01b/`):

| # | Required | File |
|---|---|---|
| 1 | Full strategic map | `s01b_01_full_map.jpg` |
| 2 | A selected squad | `s01b_02_selected_squad.jpg` |
| 3 | A selected operation with route and status | `s01b_03_selected_operation.jpg` |
| 4 | A contested objective | `s01b_04_contested_objective.jpg` (close), `s01b_04b_contested_objective_operational.jpg` |
| 5 | Several nearby friendly squads | `s01b_05_nearby_squads_strategic.jpg` |
| 6 | The same at other zoom levels | `s01b_06_nearby_squads_operational.jpg`, `s01b_06_nearby_squads_close.jpg` |
| – | Map help (H) | `s01b_07_map_help.jpg` |
| – | Tactical start, F1 controls, first person | `s01b_08_tactical_start_hud.jpg`, `s01b_09_tactical_f1_controls.jpg`, `s01b_10_first_person_hud.jpg` |
| – | Map → RTS → FPS with the new HUD | `s01b_06_objective_under_attack.jpg`, `s01b_08_rts_active_operation.jpg`, `s01b_09_fps_same_operation.jpg` |

The screenshots were inspected; the problems they showed were fixed and captured again:
- the header upper-cased the colour markup;
- garrison-badge labels sat on the objective symbol;
- group labels collided;
- the war log was cut off;
- soldier dots made the marker noisy at 0.9 px/m.

## 3. Operation feedback and orders

- **Selecting an operation:** click its label on the map or its row in the list. The panel shows:
  - the type and target, and whether the player or the AI ordered it;
  - the phase, for how long, and what it means ("marching to the staging point", "assaulting
    the objective", "holding while it is captured");
  - the squads with their strength, and the strength of the whole operation with losses;
  - the march progress (km left of total, %);
  - the target's owner, contested state and capture progress.
- **Arrival estimate.** It is shown only when it can be trusted. `WarSim` measures each
  operation's remaining route length every second and smooths the rate over about a minute
  (`march_info`, presentation only, not saved). An estimate ("arrival in about 15 min",
  rounded up to the minute) appears only:
  - while the operation is marching;
  - after 20 s of measurement;
  - at a rate of at least 0.4 m/s.

  Otherwise the panel says "estimating …" or "unknown (in contact / halted or slowed)". In
  the check, 3.6 of 4.2 km remained at 4.19 m/s: "about 15 min".
- **Ended operations.** They stay in the list for five minutes, greyed, with the outcome and
  its reason (for example "FAILED: too many losses (5 of 16 left)"), duration and losses.
- **Orders.**
  - Clicking an objective while squads are selected keeps the squads and makes the objective
    their target. Attack / Defend / Reinforce then order it.
  - Without a target the buttons wait for a click on an objective; Move waits for a click on
    the ground. Right-click or Esc cancels.
  - Right-click orders work as before.
  - In WORLD-SANDBOX-01, selecting an objective cleared the squad selection, so the
    Attack / Defend / Reinforce buttons could only be used with Shift, and Move did nothing.
- **A new operation becomes visible at once.** The map selects nothing else, and the order
  shows in the list and on the map.
- **Player orders still override operations.** The check gives a direct RTS order to one squad
  of the player's attack (`rts._player_takes`). The squad leaves the operation and the
  operation keeps the other squad.

## 4. Strategic AI review

**Evidence.**
- **Before the changes:** a 40-minute autonomous war from WORLD-SANDBOX-01, kept in the
  session record, and a 30-minute run with the fixed-step warp. Both use the same start, with
  the player's faction passive.
- **After the changes:** the same 30-minute run (`fidelity_and_war.log`).

| Problem found | Evidence | Change |
|---|---|---|
| Attacks against impossible targets | South sent 16 soldiers against East's HQ: fortified, 2 garrison squads, receiving every reserve squad. An unseen garrison was estimated as `value × 4` for every objective | An unseen HQ is assumed to hold at least 24 soldiers. An aggressive AI then needs 29 soldiers, a defensive one 48 |
| Excessive idle time | After the reserves arrived both AIs had 9 squads (72 soldiers); attacks took only the minimum (2 squads), so 40–56 soldiers stood at the HQ. East's last decision was "1 attacks running" for most of the run | New profile value `attack_commit`: an attack takes at least this share of the free soldiers (aggressive 0.6, defensive 0.5) |
| Attacks and reinforcements starting 6–8 km away | Free squads stand at the HQ; South's first attack on Sentrum marched 28 minutes, East's attack still had 2.9 km left after 26 minutes | Forward deployment: free squads idling at the HQ move to the held objective nearest the enemy (aggressive up to 4 squads there, defensive 2). At most two per decision, only when that objective is more than 1.5 km from the HQ |

**Results, 30 simulated minutes from the same start:**

| | Before | After |
|---|---|---|
| South operations started / completed | 4 / 2 | 7 / 5 |
| East operations started / completed | 1 / 0 | 2 / 1 |
| Attacks on an HQ | 1 (16 soldiers vs East HQ) | 0 |
| Largest attack | 16 | 24 |
| Forward deployments | – | South 3 squads to Verket, East 1 to Østby |
| Captures | South Bridge (17.7 min), Sentrum (29.5 min) | South Bridge (20.2 min), Sentrum (29.5 min) |
| Stuck reroutes | 0 | 0 |

**Checked and not changed (no evidence of a problem):**
- **Expansion speed:** two captures in 30 minutes, not unrealistically fast.
- **Capture loops:** none.
- **Stale operations:** squads leave operations that ended (all-squads-lost, captured, lost
  objective), and a reinforcement that finds its objective taken turns into a counter-attack.
  None was seen.
- **Late reinforcements:** they are limited by march distance, which the forward deployment
  shortens; no new rule was added.
- **Profiles stay distinct:** aggressive attacks with smaller margins, more often and with
  more squads forward; defensive keeps two HQ squads and garrisons and attacks only with
  double strength.

## 5. Playtest readiness

- **Start.** The sandbox starts in the tactical view over North HQ. A badge at the top reads
  **YOU ARE NORTH** in the faction colour, and the war log opens with "The war begins: North
  (you) …".
- **HUD.** It has two lines by default:
  - "TACTICAL M strategic map · LMB select · RMB move · P take over a soldier · Tab first
    person · F1 all controls";
  - "WAR objectives North 3 / South 2 / East 3 · your operations 1 · speed 1x (, .) · F5 save
    · F9 load".

  F1 shows every control; F3 shows the unit, body and structure counters together with the
  frame-time overlay, which is now hidden at start. F4 is the AI debug view, as before.
  Save / load messages show for 4 s.
- **Map controls** are discoverable through the "H map controls" hint, the help box and the
  context hint under the order buttons.
- **Time compression** shows the speed actually reached when the machine falls short, for
  example "8x (reached 6.7x)", on the map and in the HUD. First person stays at 1×.
- **Steps per frame.** The player's compression now allows at most 16 physics steps per frame
  (was 64). With the war running far away at 8×, 64 steps gave frames of 300–440 ms (2–4 fps)
  and 5.6×. 16 steps give a worst frame of 118 ms and p99 55 ms, at 6.7×.
- **Transitions.** Map → RTS → FPS → map works with the new map and HUD (§6). Possession,
  shots, unit and squad counts and operation membership are all kept.

## 6. Targeted test results

Runner: `bash benchmarks/sandbox01b/run_test.sh sandbox [--shots] --only <checks>`. New checks:
`warp_fidelity`, `map_ui`, `hud`. Logs are in `benchmarks/sandbox01b/`.

| Check | Why it was run | Result |
|---|---|---|
| `warp_fidelity` (new) | `_warp` changed | **PASS**: fixed steps stay at 1/60 s; outcome table in §1 |
| `war` (30 min, development check) | AI changes, evidence before and after | Ran; results in §4 |
| `map_ui` (new) | Map rewrite | **PASS**: grouping at real centre (0.0 m), group click selects 5/5, zoom anchor 2.7 m, double-click zoom ×3, objective as target, Attack button, operation details and march, player override, contested Sentrum |
| `hud` (new) | HUD changes | **PASS**: badge "YOU ARE NORTH", 2 lines by default (5 with F1, 4 with F3, 4 in first person) |
| `timescale` | TimeCompression defaults changed | **PASS**: step 0.0167 s at 8×, 480 ticks/s, 6.1× reached at the HQ, reset to 1× / 60 |
| `map_fps` | Map selection / go-to code and HUD changed | **PASS**: units 144 = 144, squads 18 = 18, operation kept, 2 player shots, no duplicate shot counters |
| `perf` | Map rendering, HUD and time compression changed | §7 |

**Not rerun, with the reason:**
- **Scenarios 1–3 and 5–7 of WORLD-SANDBOX-01** (routes, offensive, reinforcement, navigation
  march, save / load, extended war): their code paths are unchanged. Routes, operation
  logic, capture and persistence were not touched.
  - The AI changes are inactive there, because those scenarios pause the AI.
  - The only change to their execution is the fixed-step warp, which `warp_fidelity` covers.
- **Save / load:** the new `march` table is runtime-only and cleared on load. The two new
  profile values are resources, not save data.
- **`transitions`:** the code it measures (DetailManager, the terrain collision streamer,
  threaded navmesh) was not changed.
- **Older suites** (integration, large, combat, squad): no shared code changed. TimeCompression
  is used only by the sandbox, and the HUD change is limited to the war.
- **No full-suite run.** None of the changes is a cross-system change that would justify one.

## 7. Performance

All measured in the same scenario sequence (`map_fps` then `perf`). For the "01 code" column
the WORLD-SANDBOX-01 code ran from its own worktree under the same conditions, with the log in
the session scratchpad and no file in that worktree changed (`baseline_01_code_perf.log`). The
01 report's own numbers are given for reference; they came from a different sequence.

| Situation | 01 report p99 | 01 code, same run: avg / p99 / max | **01B: avg / p99 / max** |
|---|---|---|---|
| Strategic map overview | 3.8 | 2.4 / 7.7 / 12.8 | **2.21 / 7.3 / 12.1** |
| RTS at HQ | 5.9 | 1.91 / 6.1 / 9.6 | **2.0 / 7.2 / 12.4** |
| War far away | 4.0 | 2.48 / 5.3 / 8.0 | **2.77 / 7.9 / 9.9** |
| 50 v 50, RTS | 7.7 | 2.12 / 6.6 / 13.0 | **2.18 / 7.3 / 10.4** |
| 50 v 50, FPS | 8.5 | 2.78 / 6.6 / 11.1 | **2.82 / 7.2 / 9.9** |
| War far away at 8× | 11.9 (stretched steps) | 2.8 / 8.6 / 11.4 (stretched steps, test only) | **4.94 / 55.1 / 117.8 at 1/60 s steps, 6.7× reached** |

- **No frame over 33 ms at 1×.** The `war_update` average is 42–59 µs.
- **The 8× row is not a regression.** The old row was measured with stretched steps, which
  cost less per simulated second but simulate worse. With correct steps the CPU does 6.7 times
  the work of 1×.
- **A regression found and fixed during this milestone:**
  - **Map redrawn every frame:** the map's per-frame pan clamp assigned `view_center`, which
    now redraws.
  - **HUD badge restyled every 30 frames.**
  - **Effect:** together they gave map avg 4.9 ms, p99 12.9 ms, and raised p99 everywhere
    (`hud_mapfps_perf.log`).
  - **Fix:** the clamp assigns only when it changes; the badge is styled once; RichText
    panels are only re-set when their text changes.
- **Remaining differences:** p99 of RTS at HQ and war far away is 1–2.5 ms above the old code
  in this single run. avg and max are similar, and the map, where the changes are, is slightly
  faster. Run-to-run variation of this size was also seen with the old code (war far away p99
  4.0 in its report vs 5.3 here). This is noted, not proven to be noise; see §8.
- **Map → RTS jump** in `map_fps`: worst frame 29.3 ms in one run, and 50.3 ms (2 frames over
  33 ms) in another. WORLD-SANDBOX-01 measured 47.5 ms. The transition code is unchanged.
- **Distant possession** was not re-measured (its code is unchanged).

## 8. Known remaining issues

- **Long marches.** At about 4.2 m/s, 6–8 km routes still take 25–30 minutes. Forward
  deployment shortens later attacks but not the first wave. Vehicles are planned for a later
  milestone.
- **Speed reached at high compression** is bounded by the CPU: about 6–8× at the 8× setting,
  and 8–13× when tests request 24×. Long accelerated scenarios now take longer in real time.
- **Small p99 differences** (RTS at HQ, war far away) of 1–2.5 ms from a single run each. A
  few repeated runs would tell whether this is noise.
- **Close-zoom background.** The map background is the world's macro preview, so it looks
  blocky beyond about 0.5 px/m. Squads and dots stay exact.
- **Squads at one point.** Squads of different factions standing at the same spot (a contested
  objective) are drawn on top of each other at close zoom, because they really are there.
- **Arrival estimates** assume the measured march rate continues. Fights, rerouting or a
  stalled leg change it, and the estimate then disappears or updates.
- **Hidden labels.** A single squad's label is hidden on the whole-map view when there is no
  room. Its name shows in the panel or when zoomed in.
- **Not re-measured:** the transitions check and save / load of the full war (code paths
  unchanged; see §6).

## 9. Manual playtest checklist

1. Start (F5 in the editor): is the faction obvious (badge, blue markers, "You command NORTH")?
2. Press M. Can you tell within a few seconds which territory is whose, where your squads are,
   which operations run, and which objectives are contested or threatened?
3. Zoom from the whole map to a base and back with the wheel. Is it smooth? Does it zoom
   where the cursor points? Do groups split and merge predictably?
4. Select one squad, a group (click), several (box, Shift), then an objective as target; try
   Attack, Defend, Reinforce, Move and right-click orders.
5. Select an operation (label or list). Is the information enough to know what it is doing?
   Does the arrival estimate match what happens?
6. Give a direct order in the tactical view to a squad in an operation. Does it obey you and
   leave the operation?
7. Map → G (RTS) → P (first person) → Tab → M. Any stalls or lost state?
8. Use `,` and `.` at different places. Does the "reached" speed match the feel? Is the screen
   responsive enough at 8×?
9. Save with F5 in the middle of operations, play on, then load with F9. Is the war as it was?
10. Let the AI play for 20–30 minutes (with compression). Are South and East recognisably
    different? Is anything absurd: attacks that cannot work, idle armies, squads stuck in
    useless operations?
11. HUD: are the two default lines enough? Are F1, F3 and F4 easy to find?

## 10. Recommended next steps

1. **Run the manual session above** before tuning AI numbers further. The profiles now act;
   whether they feel right needs a player.
2. **Shorten marches:** vehicles or transport on the road network would make operations
   minutes instead of half-hours; the route grid already prefers roads.
3. **A few repeated perf runs** of `perf` to settle the p99 question for RTS at HQ and war
   far away.
4. **Rerun the WORLD-SANDBOX-01 scenarios** with fixed-step warps once, ideally in the next
   milestone that touches operations or combat, so their combat numbers come from play-like
   steps.
5. **Optional:** a higher-resolution map background for the close level.

## 11. Files

**New:**
- `scripts/core/time_compression.gd`;
- `benchmarks/sandbox01b/` (runner and logs);
- `docs/sandbox01b/` (screenshots);
- this report.

**Changed:**

| File | Change |
|---|---|
| `scripts/ui/strategic_map.gd` | Zoom, grouping, levels of detail, labels, routes, operation details, orders |
| `scripts/strategy/war_sim.gd` | March tracking, HQ estimate, attack commitment, forward deployment |
| `scripts/strategy/faction_profile.gd`, `assets/strategy/*.tres` | `attack_commit`, `forward_squads` |
| `scripts/ui/game_hud.gd` | Badge, short war HUD, F1 / F3 |
| `scripts/debug/world_diagnostics.gd` | `set_overlay_visible` |
| `scripts/game/core_demo.gd` | TimeCompression, reached-speed sampling, overlay hidden at start |
| `scripts/debug/sandbox_selftest.gd` | Fixed-step `_warp`, `warp_fidelity`, `map_ui`, `hud` |
| `README.md` | Updated |
