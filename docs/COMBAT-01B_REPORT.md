# COMBAT-01b — AI perception and autonomous engagement

Branch `feature/combat-01b`, based on `feature/combat-01a` (94e728e). No other worktree was
changed, and nothing was merged into `main`.

All results come from scripted runs of the real game: Godot 4.7.2, Jolt, Vulkan, RTX 3070,
1600×900, on the reference world `ref_20km`. The squads in the tests are ordinary soldier
and squad records. They are run by the real systems: `DetailManager` bodies and the
abstract tier, `SquadControl` orders, the new `CombatBrain`, and `CombatSim` / `LineOfFire`.
RTS input (Ctrl+click, Y, P, Tab, F5/F9, LMB) goes through the real input actions.

**Nobody has play-tested this by hand yet.** Section 10 lists what a manual playtest
needs to judge.

## Summary

Soldiers now fight on their own.

**Perception.** A soldier notices enemies within 400 m when they are in its 150° field of
view or within 25 m (any direction). A sight check succeeds only if the line is clear of:
- terrain;
- tree trunks and rocks;
- foliage near the line;
- buildings and HESCO.

Detection is decided on `UnitState` data, so it gives the same answer wherever the camera
is and whether or not the soldier has a body.

**Targeting and memory.**
- The soldier keeps its target instead of flipping between equally good enemies.
- A hidden target is remembered for 6 s at its last known position, then dropped.
- After that the soldier looks at that position for a while, but never walks after it.

**Engagement.** A soldier with a target:
- turns towards it and waits a short reaction time;
- fires bursts through the same `CombatSim.request_fire()` as the player, with the same
  rifle, ammunition, reload, spread, damage and occlusion;
- aims with a seeded, configurable human error.

The AI fires while walking, at reduced accuracy. It holds fire when a friendly soldier is
in its line of fire.

**Squad control.**
- Weapons Free (the default) and Hold Fire are set per squad, with Y or the FREE / HOLD
  button in the squad panel.
- Move, Hold, Follow and Regroup are unchanged: the AI never issues a movement order.
- Possessing a soldier switches off only that soldier's AI.

**Persistence.** Everything survives promotion and demotion, FPS/RTS switches and F5/F9.

**Measurements.**
- 16 vs 16 on open ground costs about 0.9 ms of `CombatBrain` time per physics frame. It
  added 0.12 ms to the average frame time and 2.0 ms to the 99th-percentile (p99) frame
  time.
- No frame went over 33 ms in any case.

**The two COMBAT-01a issues.**
- The Follow regression was a real defect, not timing. It is fixed, and 8 out of 8
  repeats now pass (§1.1).
- The corrected analytic-versus-physics comparison was rerun. It separates expected
  shape differences from implementation errors (§1.2).

## 1. COMBAT-01a issues resolved first

### 1.1 Squad Follow regression (UNIT-01A)

**Rerun.** The full squad suite passed once. That proves nothing about an intermittent
failure, so I added `--follow-repeat N`, which runs only the Follow check N times. I also
made the check record every new order given after the leader stops.

**Measurement fix.** The check counted `order_changed`, but that signal also fires when a
soldier *arrives*. It now counts new orders and arrivals separately. The failing run in
COMBAT-01a fits this exactly: 6 events after the stop, against 4 in a passing run. That
is one real new order plus that order's own arrival.

**Reproduced** in 1 of 6 repeats (`benchmarks/combat01b/follow_repro_before_fix.log`):

```
t_after_stop 6.72 s, unit 11, leader moved 0.0 m, leader speed 0.0,
unit had no order (arrived), new order to a slot 3.93 m away
```

**Cause.** In UNIT-01A, `SquadControl._update_follow` re-sent a follower to its slot
whenever the follower stood more than `follow_settle_m` (3 m) away without an order. It
compared the soldier's *position* with the slot. A follower can end its walk 3–4 m off the
slot:
- crowd avoidance pushes it;
- stuck handling ends an order as ARRIVED up to `blocked_distance` (3 m) away.

Such a follower got the same slot again while the leader stood perfectly still. A BLOCKED
follower got its unreachable slot again every second.

**Fix** (`squad_control.gd`). Each follower remembers the slot it was last ordered to.
- If that slot has not moved by `follow_reissue_m` (4 m), the soldier keeps what it has:
  walking, stopped nearby, or BLOCKED.
- Only a soldier pushed more than `follow_drift_m` (6 m) away is sent back.
- A moving leader moves the slots, so followers still get new orders while it walks.

The test threshold was not loosened. It now also requires at most one new order per
follower after the stop (the final slot, once the lead term disappears).

**After the fix:** 8 out of 8 repeats pass (`follow_repro_after_fix.log`).

| Measure | Result |
|---|---|
| New orders while the leader stands | 0 in every repeat |
| New orders while settling | 0 in 7 repeats; 3 in one, all at 0.52 s after the stop with the slot moved 4.27 m (the walking lead dropping out, correct) |
| Orders while the leader walks | 64–72 per 20 s walk, about 8.5 per soldier per 10 s, unchanged from UNIT-01A |
| Followers' distance to the leader | within 8–11 m |

The full squad suite on this branch passes (§9).

### 1.2 Analytic versus physics hit comparison

The comparison now runs each of the 2,000 rays in two ways:
- against both shapes by dense 5 mm sampling, independently of both implementations;
- through the implementations themselves.

**Classes of mismatch.**
- **Shape difference (expected).** The hit model (head sphere r 0.14 at 1.62 m plus a torso
  capsule r 0.30 from 0 to 1.50 m) differs from the movement capsule (r 0.35, 1.80 m)
  along that ray. These are deliberate and stay.
- **Grazing.** Within 1 cm of a surface.
- **Implementation error.** An implementation contradicts its own shape by more than 1 cm.

The check fails on any analytic implementation error, and on any mismatch not explained
by these classes. Results are in §9.

## 2. Architecture and decisions

| Part | Where |
|---|---|
| `CombatBrain`: perception, target choice, memory, engagement, ROE, debug counters | `scripts/combat/combat_brain.gd` (new; owned by `WorldSim` next to `SquadControl` and `CombatSim`) |
| AI state per soldier (saved): `ai_state`, `target_id`, `target_seen_at`, `target_last_pos`, `target_visible`, `target_aim_y`, `aim_ready_at`, `burst_left`, `next_burst_at`, `watch_yaw`, `watch_until`; `ai_reason` (debug only) | `scripts/core/unit_state.gd` |
| Squad rules of engagement (saved) | `scripts/core/squad_state.gd` (`roe`), `squad_control.gd` (`set_roe`) |
| Sight with foliage: `LineOfFire.sight()` / `foliage_layers()` | `scripts/combat/line_of_fire.gd` |
| Standing soldiers turn to `watch_yaw` (body and abstract tier) | `soldier_body.gd`, `world_sim.gd` |
| Death clears AI state | `combat_sim.gd` (`kill`) |
| RTS: Y toggles ROE; squad panel FREE / HOLD buttons, alive + fallen, number engaging; "HOLD FIRE" on the squad tag | `rts_controller.gd`, `squad_panel.gd`, `game_hud.gd` |
| F4 AI debug overlay | `game_hud.gd` |
| Follow fix | `squad_control.gd` |
| Tests | `scripts/debug/combat_ai_selftest.gd` (new), `squad_selftest.gd` (follow diagnostics, `--follow-repeat`), `combat_selftest.gd` (classified comparison), `benchmarks/combat01b/run_test.sh` |

**Decisions that affect later combat work.**

1. **The brain is a plain `RefCounted` owned by `WorldSim`, updated in its physics step**
   between `SquadControl` and `CombatSim`. It reads and writes only `UnitState` /
   `SquadState`. It is not a node, does not touch bodies, and needs no behaviour-tree
   framework. Each soldier's state is one enum plus a few fields. COMBAT-TECH-01 also
   concluded that LimboAI / Beehave were not needed at this size.
2. **One authority for shots.** The brain calls `CombatSim.request_fire(..., Source.AI)`.
   `request_fire` already refuses an AI shot for the possessed soldier
   (`not_controller`), so the brain could not fire for the player even if it tried.
3. **The brain never moves soldiers.** Movement stays with unit and squad orders. Combat
   only turns a *standing* soldier towards what it watches (`watch_yaw`); moving soldiers
   keep facing their path and fire on the move. Cover-seeking and pursuit belong to later
   milestones and should be added as orders through `SquadControl`, not inside the brain.
4. **Sight and fire use the same world data.** Sight is `LineOfFire.trace` without
   soldiers, plus a foliage count. Leaves and undergrowth stop eyes but not bullets. Trunks,
   rocks, terrain and structures stop both.
5. **Everything is seeded** from `world_seed`, the unit id and its shot counter: aim error,
   burst length and pauses. A replay of the same state gives the same shots.
6. **Earlier milestones' test suites switch the brain off** (`brain.enabled = false`).
   Their squads stand within sight of enemies and would otherwise start fighting. The AI
   is tested by `combat_ai_selftest.gd`. In normal play the brain is always on. Note that
   the default layout has 4 North and 4 South soldiers facing each other at site C, so
   they now fight as soon as the game starts.

## 3. Perception and target selection

| Setting (`CombatBrain`) | Default |
|---|---|
| `perception_hz` | 3 updates per soldier per second, staggered round robin over the physics frames |
| `sight_range` | 400 m |
| `fov_deg` | 150° around where the soldier looks: the target, else `watch_yaw`, else its heading |
| `awareness_m` | 25 m, any direction |
| `max_candidates` | 3 new candidates per update (the current target is extra) |
| `los_budget` | 24 sight checks per physics frame for all soldiers together; the rest wait a frame |
| `target_memory_s` | 6 s |
| `switch_ratio` | 0.6: a visible target is only replaced by one closer than 60 % of its distance |
| `watch_after_lost_s` | 8 s |
| `hearing_m` | 150 m: enemy shots make a soldier without a target look towards the shooter |
| `contact_share_m` | 120 m: squad mates look towards a contact one of them reports |

**Candidates.** Candidates come from a 64 m grid of living soldiers, rebuilt at most once
per physics frame, nearest first. There is no global scan per soldier.

**Sight check.** The sight check (`_see`):
- tests the height that was visible last time first, then the other (head 1.55 m /
  torso 1.1 m);
- skips the torso test when the head is under the horizon;
- records which height is visible, and the AI aims there.

Behind standard HESCO only the head is visible, so shooters aim at the head (§8).

**Foliage** (`LineOfFire`). Every tree whose trunk stands within `foliage_m` (2.5 m) of the
line is one layer of foliage. Trees within `foliage_skip_m` (3 m) of either end do not
count. At `foliage_block` (3) layers the line is hidden. I tightened this from 2.0 m / 4
layers after the first forest run. With the old values, 63 % of the North-to-South sight
lines into 35 m of forest were clear; now 44 % are.

**Knowledge rules.** A soldier never learns an enemy's position without a sight check.
- Hearing and squad reports only turn it to *look*.
- The last known position is not updated while the target is hidden.

## 4. Engagement

1. **Track.** The soldier faces the target if standing. If walking it keeps walking, and
   its view follows the target for perception.
2. **Reaction.** It waits `reaction_s` 0.45 s + 0.15 s per 100 m after acquiring a new
   target.
3. **Bursts.** All lengths and pauses are seeded.
   - Below 40 m: 4–6 rounds.
   - Below 120 m: 2–4 rounds.
   - Below 250 m: 1–2 rounds.
   - Beyond that: single shots.
   - Pauses are 0.25 s + distance / 250 + up to 0.35 s.
4. **Aim point.** It aims at the visible height, trailing a moving target by `track_lag_s`
   (0.2 s × its velocity).
5. **Aim error.** One standard deviation per axis is 0.25° + 0.20° per 100 m + 1.2° when
   walking at full speed. `CombatSim` then adds the weapon's own spread and bloom: base,
   moving and sustained fire.
6. **Friendly check.** It runs only when a friend stands within 1.5 m of the line.
   - The shot preview (`CombatSim.preview_shot`) runs with zero spread.
   - A friend's body axis must also stay at least 0.5 m clear of the torso radius around
     the line.
   - If either check fails, the soldier waits (reason "friendly in line of fire").
7. **Fire** with `request_fire(..., Source.AI)`. Cooldown, ammunition and reload are the
   weapon's.
   - An empty magazine reloads automatically.
   - With no target, a magazine below 50 % is topped up.
   - With nothing left, the reason is "no ammunition".
8. **Stop.**
   - When the target dies, everyone tracking it drops it at once, in the same tick.
   - When it hides, the soldier stops firing and its state becomes LOST TARGET.
   - Hold Fire stops fire before the next shot.

**Outcome on open ground.** Of the open-fight shots at 120 m, 11 % hit. Most misses fly
past the target and land in the ground behind it ("misses long" in the logs).

**Symmetry check.** One fight is decided by who falls first, so the test runs four more
8 vs 8 fights with other seeds and the factions swapping sides.

| | Fight 1 | Fight 2 | Fight 3 | Fight 4 |
|---|---|---|---|---|
| Winning faction | 1 | 1 | 0 | 0 |
| Winning side | z− | z+ | z+ | z− |

No faction or side bias.

## 5. Rules of engagement and squad orders

- **Weapons Free** (default): soldiers engage on their own.
- **Hold Fire**: they detect, track and turn to enemies (state *observing*, reason "hold
  fire") but never fire on their own. Switching back allows the next shot immediately.
- **RTS controls**: Y toggles the selected squads, or use the FREE / HOLD button on each
  squad-panel row. A squad on Hold Fire shows "HOLD FIRE" in amber on its tag.
- **Squad panel rows** now also show fallen members (`7 +1 fallen`) and how many are
  engaging.
- **Loose soldiers** (not in a squad) are always Weapons Free.

**Interaction with orders** (measured in §8):
- Holding squads fight from where they stand (drift 0.0 m, never an order).
- A moving squad fires while it walks: 214 of 226 shots were fired at walking speed. It
  still arrives (DONE, 1.9 m from the destination).
- A Follow squad keeps following and fights.
- No soldier pursues a target that disappears.
- Possession changes nothing for the other soldiers.

## 6. Tiers, persistence and determinism

**Tiers.**
- Perception, target choice and firing use only `UnitState`.
- An abstract soldier (no body) shoots from its record's eye with the same `request_fire`.
- With the camera 12 km away, the test squads had no bodies and fired 167 and 107 shots in
  two 4 s phases. Back at the fight, with 16 bodies, they fired 187 and 168.
- Over the two demotion / promotion cycles:
  - every shooter's shot counter rose by exactly one per shot (no duplicates, no gaps);
  - damage events matched damaging shots (108 = 108);
  - every soldier's health loss equals the damage of the shots that hit it.

**Save / load.** The AI fields and the squad ROE are in `to_dict` / `copy_combat_from` and
`SquadState.to_dict`. The test pressed F5 during a fight with 16 soldiers engaged and one
squad on Hold Fire, let the fight run 3 s, then pressed F9. Every AI signature compared
equal at the moment of the restore: target, seen time, aim time, burst, watch direction,
ammunition and reload. The fight then resumed with the ROE kept: North fired 87 shots,
South (Hold Fire) none.

**FPS / RTS.** Possessing a soldier and Tab back changed no other soldier's target. 15 out
of 15 engagements were kept on possession, and 18 out of 18 on Tab.

## 7. Visual feedback and debugging

- **Normal HUD**: the squad panel shows FREE / HOLD, fallen members and the number
  engaging; a squad tag shows HOLD FIRE.
- **F4 (optional, both views)**: one tag per soldier within 400 m of the camera, showing:
  - name, AI state, target, "seen" or "mem Ns";
  - the reason the soldier is not firing (aiming / between bursts / hold fire / target
    hidden / friendly in line of fire / reloading / out of range / no ammunition);
  - magazine and reserve;
  - a red line to a visible target, grey to a remembered position.

  Tags that would overlap become coloured dots. A corner panel shows the counts per state,
  sight checks per frame and their cost, brain time, AI shots, acquisitions, switches and
  friendly holds.
- **Log**: `CombatBrain.log_events = true` prints decisions ("sees S-3 at 120 m", "drops
  target (lost contact)"). The last 200 are kept in `CombatBrain.events` in any case.
- **Effects**: nearby AI shots use the COMBAT-01a effects (muzzle flash at the third-person
  muzzle, tracer, impacts, 3D sound).

**Screenshots** (`docs/combat01b/`, real game frames from the test run):

| File | What it shows |
|---|---|
| `c01b_open_exchange_fire.jpg` | Two 8-soldier squads 120 m apart exchanging fire (tracers) |
| `c01b_open_debug_overlay.jpg` | The same fight with F4: targets, "seen", "between bursts", ammunition |
| `c01b_forest_edge_firefight.jpg`, `c01b_forest_edge_debug.jpg` | South at the forest edge, North in the open, firing |
| `c01b_blocked_line_of_sight_wall.jpg` | Tall HESCO between two squads: everyone idle, no sight, no shots (F4) |
| `c01b_rts_hold_fire_selected.jpg` | Squad selected, HOLD FIRE tag and HOLD buttons |
| `c01b_rts_squad_combat_status.jpg`, `c01b_rts_selection_combat_status.jpg` | Squad panel with engaging counts, fallen, Follow / Hold / Move squads in combat |
| `c01b_fps_possession_during_engagement.jpg` | First person, the player firing while the squad fights on |

## 8. Automated acceptance tests

`bash benchmarks/combat01b/run_test.sh combat-ai --shots` takes about 17 minutes and
writes `benchmarks/combat01b/combat_ai_test.json` and `combat-ai_test.log`. Result:
**PASS**.

Each scenario spawns fresh squads on open ground about 6 km from the default soldiers,
then removes them afterwards. Health is raised only where a fight must last for a
measurement (stated per row). Weapons, ammunition and accuracy are never changed.

| # | Requirement | Scenario and result |
|---|---|---|
| 1 | Clear visibility: detect and fire | 8 v 8 at 120 m. First sight 0.07 s / 0.13 s, first shots 0.70 s / 0.77 s (reaction time). 260 shots, 29 hits (11 %), 9 deaths, 7 reloads |
| 2 | Hills and structures block | **Ridge**: squads 190 m apart on open spots with a ridge between. Over 10 s: 0 sightings, 0 shots (1,440 sight checks). South then walks 45 m over the ridge: contact after 7.0 s, then fire both ways. **Tall HESCO** (2.2 m) between squads 80 m apart: 0 sightings, 0 shots in 10 s. **Standard HESCO** (1.37 m): South aims at the exposed heads (aim height 1.55 for all 7 shooters); 52 of 167 shots stopped by the wall; every hit re-tested against the wall's boxes: none crosses it (hits 1.31–1.64 m above the feet) |
| 3 | Forest affects perception | South 35 m inside a forest (9 trees within 12 m), North 90 m out in the open, Hold Fire. Clear sight pairs: 28 of 64 (19 foliage, 17 trunk). At the edge: 64 of 64. Weapons Free at the edge: 478 shots, 146 stopped by trunks |
| 4 | No switching between equal targets | One soldier, two enemies at equal distance, 15 s: one target, 0 switches. A third enemy at a much closer distance: switches to it. All enemies gone: LOST TARGET, dropped after 5.92 s (memory 6 s), no movement, no order |
| 5 | Hold Fire prevents shots | Two squads on Hold Fire 120 m apart, 8 s: 8 + 8 soldiers seeing a target, 0 shots |
| 6 | Weapons Free restores | Ctrl+click a soldier, Y: North fires in the same tick (33 shots), South (still Hold) 0. Y again: 0 North shots afterwards |
| 7 | Reload and ammunition | One soldier with 3 + 32 rounds against a target with raised health: exactly 35 shots, 2 reloads, RELOADING state seen, 0 shots during reloads, ends 0 / 0 with "no ammunition"; no shot faster than the fire interval |
| 8 | No fire through a friend | Friend 15 m ahead on the line, enemy 55 m: 0 shots, 15 friendly holds, friend undamaged. Friend steps 4 m aside: 15 shots |
| 9 | Possession disables only that soldier's AI | During the fight: possessed soldier state "player", 0 AI shots from it; its squad mates 32 shots in 4 s; all other members' orders and the squad order unchanged; the player fired through LMB |
| 10 | Orders work during combat | Move 80 m across the front under fire (health 600): DONE in 20 s, 1.9 m from the destination, 214 shots fired while walking. Hold squad: 0.0 m drift, no orders. Follow squad: still Follow, within 12.8 m of the leader, 95 shots |
| 11 | Death without duplicate damage | Open fight: damage events = damaging shots (29), 0 damage to the dead, 0 shots by the dead, no death reported twice, no dead soldier left in a squad, no living soldier holding a dead target after the death tick |
| 12 | FPS / RTS keep engagements | 15 / 15 kept on possession, 18 / 18 on Tab back; the released soldier is "engaging" again |
| 13 | Save / load | F5 → 3 s → F9: 0 differences in 16 AI signatures + ROE; fight resumes (87 / 0 shots with South on Hold) |
| 14 | Promotion / demotion | Health 2000 so nobody dies: 34 demotions and 34 promotions mid-fight, 629 shots, 0 duplicate or missing shot counters, damage per soldier = sum of its hits |
| 15 | 16 v 16 without degradation | See §9 performance: +0.12 ms average, +2.0 ms p99, 0 frames over 33 ms |

Every scenario also checks, every tick, that magazines stay within 0..30 and reserves at
or above 0. There were no violations.

## 9. Performance and regressions

### Performance

Each case was measured for 8 s while the fight runs. Health is raised to 100,000 so all 32
keep fighting.
- "Brain" is `CombatBrain.update` per physics frame (60 Hz), including the shots it fires.
- "Sight" is one `LineOfFire.sight` check.
- The baseline has 28 default soldiers and the camera on the meadow, with no test squads.
- The vsync is off, which is why the frame times are low.

| Case | Bodies | Frame avg / p99 / max (ms) | Brain avg / max (µs) | Sight checks per frame (µs each) | Shots (resolve avg / max µs) |
|---|---|---|---|---|---|
| Baseline RTS | 0 | 1.82 / 2.09 / 2.41 | 120 / 176 | 0 | 0 |
| 8 v 8 open RTS | 16 | 1.85 / 3.17 / 4.15 | 485 / 1,679 | 0.80 (125) | 190 (228 / 439) |
| 8 v 8 open FPS | 16 | 2.27 / 3.63 / 4.32 | 463 / 1,593 | 0.75 (124) | 188 (210 / 427) |
| 16 v 16 open RTS | 32 | 1.94 / 4.08 / 4.56 | 915 / 1,923 | 1.60 (122) | 400 (224 / 475) |
| 16 v 16 open FPS | 32 | 2.44 / 4.67 / 5.52 | 889 / 2,454 | 1.55 (123) | 390 (218 / 428) |
| 16 v 16 forest RTS | 32 | 2.13 / 4.86 / 5.29 | 1,230 / 2,412 | 9.60 (91) | 0 (no sight through 90 m of forest) |
| 16 v 16 forest FPS | 32 | 6.28 / 9.24 / 9.51 | 1,196 / 2,361 | 9.30 (91) | 0 |

- **No frame over 33 ms in any case.**
- **16 v 16 open RTS against the baseline:** +0.12 ms average, +1.99 ms p99.
- **Forest FPS frame time** (6.3 ms) is the rendering of the forest around a first-person
  camera, not combat. The brain costs the same in RTS.
- **The most expensive case is a forest with nobody visible.** Each update tries up to 3
  candidates with 2 checks each, which reaches 9.6 checks per frame, still inside the
  24-check budget. The budget never cut in.
- **Where brain time goes on open ground.** Of 0.9 ms:
  - sight checks about 0.2 ms;
  - shots about 0.2 ms (the same `LineOfFire` cost as COMBAT-01a);
  - the rest is GDScript per-soldier overhead: the engage loop over every soldier per
    frame, the grid and the living count.

  Section 11 lists cheap ways to reduce this.
- **One-off spike: about 8 ms** of brain time (8.1 and 7.9 ms in the two runs) in the forest firefight, the first time sight
  lines reached into new vegetation cells. `LineOfFire._ensure_cell` fills its trunk
  buckets the first time. The same area measured later stays below 2.5 ms. Pre-filling the
  cells around a fight is a COMBAT-01c item.

`LineOfFire` was profiled before adding anything: 91–125 µs per sight check, 210–228 µs
per shot. No new cache was needed for COMBAT-01b. The only optimisations are the ones
built into the design: staggering, the per-frame budget, nearest-first candidates, and
skipping the torso test under the horizon.

### Regressions

Each suite was run with `bash benchmarks/combat01b/run_test.sh <kind>` on this branch, one
after another; logs and JSON are in `benchmarks/combat01b/`.

| Suite | Result | Notes |
|---|---|---|
| `combat-ai` (COMBAT-01b) | **PASS**, twice | `combat-ai_test_run1.log` and `combat-ai_test.log`. The two runs gave identical shots, hits and deaths: the AI is deterministic for the same world seed |
| `combat` (COMBAT-01a) | **PASS** | Unchanged numbers: FPS hits at 20 / 150 / 250 m give 34.0 / 32.56 / 27.70; determinism 40/40 identical; shot resolve 234 µs average |
| `squad` (UNIT-01A) | **PASS** | Follow: 0 new orders while the leader stands, 0 while settling, 4 arrivals, 8.2 orders per soldier per 10 s of walking |
| `squad --follow-repeat` | 1 of 6 failed before the fix, 8 of 8 pass after | `follow_repro_before_fix.log`, `follow_repro_after_fix.log` (§1.1) |
| `large` (WORLD-CORE-02) | **PASS** | |
| `base`, `integration` | not run | Construction and groundwork are untouched (as in COMBAT-01a) |

**Analytic versus physics, corrected and rerun** (`combat`, check `analytic_vs_physics`).

Soldiers, 2,000 rays:
- 1,755 agree (848 hit both).
- 245 hit only the physics capsule.
- All 245 are **shape differences**: the ray passes inside the r 0.35 / 1.80 m movement
  capsule but outside the r 0.30 torso and r 0.14 head.
- **0 analytic implementation errors**, **0 physics implementation errors**, 0 unexplained.

COMBAT-01a's 1,655 / 2,000 mixed in terrain hits; with terrain excluded the agreement is
higher, and the remainder is the deliberate difference between the hit model and the
movement capsule. Terrain grazing: 400 / 400 agree, largest distance difference 0.01 m.

## 10. Known limitations and what a manual playtest must judge

**Limitations.**
- **No cover-seeking, suppression, morale, flanking or pursuit** (out of scope). Soldiers
  stand in the open and trade fire where their orders put them.
- **Foliage is approximated from trunk positions.** The model is a corridor count. There
  is no undergrowth data, and a lone bush does not hide anyone. Values are tunable on
  `LineOfFire`.
- **Detection is binary.** Within range, in view and with a clear line, a soldier sees the
  enemy at once (at the next perception update). There is no gradual spotting by distance,
  movement or posture; the reaction time is the only delay.
- **Squad contact reports and hearing only turn heads.** A soldier still needs its own
  sight line before it can shoot.
- **Hits are rare at range.** 11 % at 120 m in the open; most misses land behind the
  target. This is the combined effect of the AI's aim error and the rifle's spread and
  bloom; all of them are tunable.
- **Lopsided fights.** A single fight can end lopsided because early casualties snowball
  (§4 symmetry).
- **Default layout.** Site C's 4 North and 4 South soldiers start 24 m apart, so they
  fight immediately when a game starts. This is correct behaviour, but it may surprise.
- **Placeholder sounds.** Sounds are still the COMBAT-01a synthesised placeholders, and
  many shots near the camera share the pooled 3D players.
- **Third-person visuals.** Soldiers turn when they are on a target, but have no aiming
  pose or firing animation.
- **Squad panel layout.** With six or more squads, the squad panel grows into the HUD text
  at the bottom left (visible in `c01b_rts_selection_combat_status.jpg`). This is an
  existing UNIT-01A layout limit; it should move or scroll.

**For a larger manual playtest:**
1. Do fights at 50–300 m feel right in pace and lethality? Check the reaction time, burst
   lengths and pauses, the aim error, and the time to kill.
2. Is forest concealment believable at the edge and inside? Check the foliage corridor and
   threshold.
3. Is the 150° field of view plus 25 m awareness right, or do soldiers notice things
   behind them too easily or too late?
4. Readability: can you tell who is firing at whom without F4? Check tracers and sounds
   with 16+ shooters.
5. Does Hold Fire behave as a player expects when the squad is being shot at? It holds
   even then, by design.
6. Possessing a soldier in a firefight: check the HUD, being hit, and death returning you
   to RTS while the squad fights on.
7. Moving squads under fire: is shooting on the move too accurate or too inaccurate?
8. The site C start fight: keep it, or move those groups apart?

## 11. Recommendations for COMBAT-01c (large-scale distant combat)

1. **Cut per-frame overhead before adding more soldiers.**
   - Keep a living-soldier list updated by signals instead of counting every frame.
   - Only run `_engage` for soldiers that have a target or are reloading; idle ones need
     nothing per frame.
   - Batch the grid rebuild.
2. **Pre-fill `LineOfFire` vegetation buckets** around active fights (asynchronous or
   spread over frames) to remove the cold-cache spike.
3. **Distant fights.** Lower `perception_hz` for soldiers far from every observer.
   Consider resolving far shots in batches; the data is already there. The brain needs no
   other change to run without bodies.
4. **Measure 50 v 50 and 100 v 100** with the same test (`_perf_case`) and set the
   `los_budget` from those numbers.
5. **Tactics as orders.** Cover-seeking or suppression should come in as orders through
   `SquadControl`, so the brain stays the place where the trigger is pulled.

## 12. Files

New:
- `scripts/combat/combat_brain.gd`
- `scripts/debug/combat_ai_selftest.gd`
- `benchmarks/combat01b/run_test.sh`
- logs and JSON in `benchmarks/combat01b/`
- screenshots in `docs/combat01b/`

Changed:
- `unit_state.gd`, `squad_state.gd`, `squad_control.gd` (ROE, Follow fix)
- `world_sim.gd`, `combat_sim.gd`, `line_of_fire.gd`
- `soldier_body.gd`, `detail_manager.gd` (demotion counter fixed: it lost demotions while
  the camera moved fast)
- `rts_controller.gd`, `squad_panel.gd`, `game_hud.gd`
- `core_demo.gd`, `README.md`
- the earlier test suites (AI off, Follow diagnostics, classified comparison)
