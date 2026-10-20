# COMBAT-02 — Scalable combat and tactical AI

Branch `feature/combat-02`, based on `feature/combat-01b` (c84fd1a, including its Follow
fix). No other worktree was changed and nothing was merged into `main`.

All results come from scripted runs of the real game: Godot 4.7.2, Jolt, Vulkan, RTX 3070,
1600×900, `ref_20km`, with vsync off. The soldiers are ordinary unit and squad records. The
HESCO lines are ordinary construction records. Everything is run by the real systems:
- `DetailManager` bodies, navigation and the abstract tier;
- `SquadControl` orders;
- `CombatBrain`, `CombatSim` and `LineOfFire`.

RTS and FPS input goes through the real input actions.

**Nobody has play-tested this by hand.** Section 9 separates what was verified from what
was only measured, and lists what the manual playtest should judge.

## Summary

**Scale.** 100 v 100 now costs about half the AI time of COMBAT-01b (§1.2 has the exact comparison):

| | COMBAT-01b | COMBAT-02 |
|---|---|---|
| AI time per tick, camera at the fight | 8.8 ms (120 bodies) | 5.3 ms (200 bodies; 4.5 ms with the same 120-body layout) |
| AI time per tick, camera far away | 8.7 ms | 4.2 ms |
| p99 frame time, camera at the fight | 18.7 ms | 13.8 ms (200 bodies; 10.7 ms with 120) |

Fights continue unchanged without bodies, kilometres from the camera. Two simultaneous
50 v 50 battles 2.75 km apart run together. Several shot and line-of-sight bottlenecks were
found by profiling and removed, among them:
- a hidden quadratic copy in the vegetation data, the "8 ms cold-cache spike";
- a full sort of every enemy per perception update;
- a linear squad search per soldier per frame;
- a full unit scan per shot.

**Tactics.** A soldier who comes under fire reacts:
- **Triggers:** a shot passing within 3 m, a hit, or a squad mate within 30 m coming under
  fire.
- **Knowledge:** the soldier learns only roughly where the fire comes from (blurred by up to
  8 % of the distance). It never learns enemy positions it has not seen.
- **Cover search:** it looks for cover near itself or its held position: behind HESCO,
  buildings, rocks, tree trunks, or terrain that rises towards the threat.
- **Choosing a spot:** each spot is checked against the actual threat direction with the
  same world data as the shots. A spot it can fire from beats one that only hides it.
- **Then:** it walks there through the normal movement code and fights from the spot.

**Orders stay in charge.**
- The reaction is a separate, temporary movement goal. It never touches the soldier's or
  the squad's order.
- The order decides how far and how long the soldier may react:
  - Hold: 12 m around the held spot, and it walks back when calm.
  - Move: 6 m and 5 s, then the order continues.
  - Follow: 8 m and 8 s.
  - Regroup: 5 m and 4 s.
- Hold Fire takes cover without firing.
- Any new player order ends the reaction at once, and so does possessing the soldier.

**Bugs found and fixed on the way.**
- **HESCO seams.** HESCO lines left 3 cm seams between their cells, and shots passed
  through them. The line of fire now closes the seams.
- **Hearing.** An idle soldier that had turned towards a sound stayed blind behind it for
  good. Idle soldiers now scan around them.
- **Test bugs (one COMBAT-01b check never measured anything).** GDScript lambdas copy
  integers and floats, so four test measurements could never fail. One was the COMBAT-01b
  check that "the holding squad gets no orders". All four now use references.

**Tests.** All automated suites pass:
- the new tactics suite (14 checks);
- the new scaling suite;
- COMBAT-01b, COMBAT-01a, the squad suite, large world and construction integration.

## 1. Large-scale combat and performance

### 1.1 Method

`bash benchmarks/combat02/run_test.sh combat-scale [--shots]` (`combat_scale_selftest.gd`)
sets up the battles:
- **Layout:** N v N infantry in squads of 10 lines, at most 5 squads side by side, then a
  second rank 15 m behind. The two sides are 120 m apart on the COMBAT-01b meadow.
- **Measurement:** the first 3 s after spawning are measured separately as the cold start.
  Then 8 s with the camera at the fight, and 8 s with the camera 12 km away.
- **Two battles:** two 50 v 50 battles 2.75 km apart, with the camera jumping between them
  every 3 s.

Health is raised so everyone keeps fighting; weapons and accuracy are unchanged. The
COMBAT-01b code was measured with the same test before any change
(`benchmarks/combat02/combat_scale_before.json`).

### 1.2 Results

| Case | Version | Bodies | Frame avg / p99 / max (ms) | AI avg / max (ms) | Sight checks per tick | Shots in 8 s | Cold start: AI max / frame max (ms) |
|---|---|---|---|---|---|---|---|
| Baseline, no test squads | 01b / 02 | 0 | 1.75 / 2.23 / 9.1 → 1.73 / 2.18 / 6.7 | 0.16 → 0.17 | 0.1 | – | – |
| 16 v 16, camera at the fight | 01b → 02 | 32 | 1.86 / 3.92 / 4.8 → 1.84 / 3.86 / 4.7 | 0.87 / 2.2 → 0.79 / 2.1 | 1.6 → 1.65 | 371 → 384 | 2.5 / 11 → 3.0 / 14 |
| 16 v 16, camera 12 km away | 01b → 02 | 3–4 | 1.67 / 3.43 / 4.6 → 1.66 / 3.14 / 4.1 | 0.86 / 2.4 → 0.65 / 2.0 | 1.6 → 0.81 | 415 → 400 | |
| 50 v 50, camera at the fight | 01b → 02 | 100 | 2.49 / 8.40 / 9.8 → 2.29 / 7.07 / 8.2 | 3.39 / 6.3 → 2.37 / 4.8 | 6.3 → 5.8 | 1,156 → 1,219 | 8.5 / 19 → 7.9 / 19 |
| 50 v 50, camera 12 km away | 01b → 02 | 1–3 | 1.96 / 6.60 / 8.3 → 1.78 / 5.26 / 8.5 | 3.31 / 6.4 → 1.89 / 6.5 | 6.3 → 3.3 | 1,202 → 1,195 | |
| 100 v 100, camera at the fight | 01b (120 bodies) → 02 (200 bodies) | 120 → 200 | 5.88 / 18.74 / 22.0 → 3.78 / 13.84 / 15.9 | 8.80 / 18.1 → 5.27 / 11.1 | 17.6 → 12.1 | 1,840 → 1,306 | 18.3 / 40 → see note |
| 100 v 100, camera 12 km away | 01b → 02 | 1–3 | 3.34 / 13.89 / 16.1 → 2.15 / 9.74 / 13.7 | 8.70 / 13.9 → 4.24 / 11.6 | 17.9 → 7.0 | 1,862 → 1,214 | |
| Two 50 v 50 battles 2.75 km apart, camera jumping every 3 s | 02 | 100 | 3.56 / 14.85 / 418 (5 frames over 33 ms: the 4 camera jumps, §8) | 3.47 / 7.5 | 12.8 | 2,306 | |

No frame went over 33 ms in any single battle, at either camera position.

**Note on 100 v 100.** The COMBAT-02 run put the squads in two ranks (a 180 m front), so
that the southern line no longer stood in the river as it did in a first run with a 360 m
front. With the two-rank layout all 200 soldiers are within 120 m of the camera and have
physics bodies; with the COMBAT-01b layout 120 did. The 100 v 100 row therefore compares
COMBAT-01b with 120 bodies against COMBAT-02 with 200 bodies, and is not exactly like for
like. With the same one-rank layout as COMBAT-01b, COMBAT-02 measured 4.46 ms AI time and
10.7 ms p99 in an earlier run of the same test. Fewer shots in 8 s at 100 v 100 come from
the tactical reactions (soldiers in cover, shots held for the shot budget) and the denser
two-rank layout.

**Reading the table.**
- "AI" is `CombatBrain.update` per physics tick (60 Hz), including the shots it fires.
  - COMBAT-02 includes the tactical reactions; COMBAT-01b had none.
  - Frames often run more than one physics tick, so frame times are not the sum of AI
    times.
- "Far" means the camera is 12 km away and the battle has no bodies (except the default
  soldiers at site C).
- **Memory:** a 100 v 100 battle added about 12 MB (17 MB with the camera far away, where proxies are used) of static memory while it existed.
  That covers 200 soldier records with bodies or proxies; it is released when the battle is
  removed.

### 1.3 What was changed, and why (profiling first)

The COMBAT-01b brain was profiled per section at 100 v 100 before anything was changed
(µs per tick):

| | Perception | Engagement (incl. shots) | Shots | Grid |
|---|---|---|---|---|
| COMBAT-01b | 6,038 | 2,660 | 1,450 | 95 |

Of the 6 ms of perception, only about 1.9 ms were sight checks.

| Bottleneck (measured) | Change |
|---|---|
| Every perception update collected all enemies within 400 m and sorted them with a lambda (about 100 enemies, 10 updates per tick) | Per-faction 128 m grid; field-of-view and distance filter first; then a small sorted insert of the k nearest (k = 4). No full sort |
| `WorldState.squad_of` searched all squads linearly, once per soldier per frame (rules of engagement) | Index rebuilt only when membership changes |
| Each shot tested every unit in the world for hits (`LineOfFire._units_hit`) | Units from the brain's 64 m grid along the shot (cells crossed plus neighbours, provably complete for 0.6 m) |
| Hearing scanned every listener within 150 m for every shot | Shots are kept for 1 s; an idle soldier checks them at its own perception update |
| Every soldier was processed every frame | Idle soldiers (no target, no reload, no look direction) are skipped |
| Many shooters' bursts landing on the same frame (largest spikes) | `ai_shot_budget`: at most 10 AI shots per tick, rotating start; a soldier over the budget fires one tick later and keeps its fire interval |
| **Vegetation cold cache: 8 ms spike** | Two causes. (1) `LineOfFire._fill_cell` appended to the packed array held in the bucket dictionary, which copied the whole bucket for every trunk (copy on write, quadratic). It now collects per bucket and stores once: a cell costs about 0.8 ms on average, 2.0 ms at most. (2) Sight lines and cover searches no longer fill cells inline: missing cells are queued and filled one per tick, and the line is checked a tick or two later |
| Distant battles cost as much as near ones | `distance_lod`: soldiers more than 700 m from the observer perceive at half rate. Firing, reloading and damage are unchanged |

**Not changed, because measurements did not call for it:**
- **Multithreading, ECS, a new framework, and caching sight lines between pairs.** The
  sight check itself costs 85–120 µs and is still the largest single item, about 2 ms per
  tick at 100 v 100 (§8).
- **The weapon's 600 m range for every miss.** Misses keep flying to their real end.

**Determinism.** Everything new is seeded or count-based: the shot budget order, the warm
queue, cover search order and budget, and the threat blur. Two exceptions:
- with `distance_lod` on (the default), a distant battle's outcome depends a little on
  where the camera was;
- cover reachability uses the navmesh where bodies exist, and the straight line where they
  do not.

`CombatBrain.distance_lod = false` makes outcomes camera-independent again.

## 2. Persistent distant combat

- **No bodies needed.** Perception, targets, firing, damage, death and tactical reactions
  use `UnitState` only. In the abstract tier a reaction moves the record straight towards
  its cover and stops at structures, like abstract orders.
- **Tier changes mid-fight** (`tactics` suite, `tiers_with_tactics`): 16 soldiers fought
  while the camera went 12 km away and back twice.
  - With no bodies: 174 and 102 shots. With bodies: 195 and 169.
  - 38 promotions and 38 demotions.
  - 0 duplicated or missing shot counters; every soldier's health loss equals the damage
    of the shots that hit it.
- **Two battles at once** (scale suite): both keep fighting while the camera jumps between
  them; nothing is lost or repeated.
- **Arriving and possessing:** possession in an ongoing fight was tested in
  `open_to_cover` (§6).
- **Save / load during combat** (`save_load_tactics`): F5 during reactions, 4 s of
  fighting, then F9.
  - Every soldier's tactical and combat signature compared equal at the restore: tactic,
    reaction goal and state, cover, threat, held spot, under-fire time, target, ammunition
    and reload.
  - The squad's order, rules of engagement, members and fallen were unchanged.
  - The 5 soldiers dead at the save fired 0 shots after the load.
  - Damage events matched damaging shots.

## 3. Tactical reactions

### 3.1 State

The reaction state is added to `UnitState` and saved with it:

| Field | Meaning |
|---|---|
| `tactic` | NONE / SEEK_COVER / IN_COVER / RETURNING |
| `react_target`, `react_state` | Temporary movement goal; MOVING / ARRIVED / FAILED |
| `react_until` | End of a brief reaction (INF while holding) |
| `cover_pos` | The reserved spot |
| `threat_pos`, `threat_at`, `under_fire_until` | What the soldier believes about incoming fire |
| `anchor_pos` | The held spot |
| `tactic_cooldown_until` | Earliest time for a new reaction |

The combat state (engaging, observing and so on) is unchanged and runs alongside. A soldier
can be "engaging / in cover".

### 3.2 Under fire

- **Triggers:** an enemy shot whose line passes within 3 m of the soldier's body, a hit, or
  (once) a squad mate within 30 m coming under fire.
- **The threat position** is the shooter's eye position, blurred sideways by a seeded error
  of up to ±8 % of the distance. It is updated when fire comes from a clearly different
  place. It is not the shooter's identity.
- **Under fire lasts 6 s** after the last such shot.
- **Turning:** a soldier without a target turns towards the threat. It still needs its own
  sight line before it can shoot.

### 3.3 Cover search

Cover is searched locally and on demand. There is no baked cover map.

**Candidates.** The search collects candidate spots, then filters them:
- **Where they come from:**
  - the soldier's own spot;
  - for every structure module nearby, the spot just behind it relative to the threat;
  - the same behind rocks with radius 0.5 m or more, and behind trunks with radius 0.25 m
    or more;
  - terrain spots on rings of 3 / 6 / 9 / 12 m where the ground rises at least 0.9 m
    within 8 m towards the threat.
- **Which are kept:** only those within the order's radius, on usable ground (not in water
  or structures), and at most 14, nearest and most solid first.

**Rejected:**
- spots reserved by another soldier (1.1 m);
- spots where another soldier is standing (1.0 m);
- spots that could not be reached within the last 30 s.

**Protection.** Two short traces with the same `LineOfFire` data as shots, from the spot
towards the threat:
- **The torso line (1.1 m) must be stopped close to the spot:** within 6 m by a structure,
  rock or trunk, or within 15 m by terrain (a reverse slope). Otherwise the spot is
  rejected as "no protection from the threat".
- **The eye line (1.55 m)** decides whether the soldier can fire from there.

**Score.**
- A fighting position scores 10, full cover 7. On Hold Fire it is the other way round: 9
  and 10.
- −0.35 per metre of distance.
- +2 for staying where it is, +1 for a structure, +0.5 for a rock.

**Reachability.** It is checked only for the chosen spot, falling back to the next one:
- with a body: a navigation path that ends at the spot and is not longer than 2.5 times
  the straight line plus 4 m;
- without a body: the straight line must not cross a structure footprint.

A spot that fails is remembered as unreachable for 30 s.

**Cost.** At most 16 candidate evaluations per tick for all soldiers together, spread over
ticks. In the 100 v 100 battle cover cost about 30 µs per tick.

### 3.4 After choosing

1. **SEEK_COVER:** the soldier walks there through the normal body or abstract movement.
   It arrives within 1.5 m, or the attempt ends as FAILED after stuck handling.
2. **IN_COVER:** the soldier faces the threat or its target and fights.
   - Protection is re-checked every 4 s.
   - After at least 6 s in cover, a spot that no longer protects is given up and a new
     search runs.
   - This dwell time is what stops it flipping between spots.
3. **End:**
   - Move / Follow / Regroup: when the reaction time is up, the order resumes. No new brief
     reaction for 12 s.
   - Holding: after 10 s without fire it goes RETURNING to the held spot.
   - A FAILED cover is marked unreachable and the soldier searches again.

### 3.5 Firing from cover

- **Same shooting model.** Firing from cover uses the COMBAT-01b engagement and
  `request_fire`.
- **Own-cover check.** Before a shot from cover, the actual shot direction (with its aim
  error) is traced for 3 m. If the soldier's own cover is in the way, it waits for the next
  shot instead.
- **Protection is not invulnerability.** Incoming shots are resolved against the cover's
  real boxes. A soldier behind standard HESCO still shows head and shoulders (the hit model
  reaches 1.76 m, HESCO 1.37 m) and is still hit there. In `open_to_cover`, 14 South hits
  landed on North after it reached cover.
- **Friendly fire checks** are unchanged.
- **Crouching was not implemented.** The soldier model, the hit shapes, the eye height and
  the animations would all have to change together; it is listed for later (§10).

## 4. Squad orders remain authoritative

**How a reaction moves a soldier.**
- A reaction moves the soldier only through `react_target`.
- `SoldierBody._ai_step` and `WorldSim._abstract_step` prefer it to the order while it is
  set, and pause the order. They never write the order.
- `WorldState.issue_move` (every player and squad order) and `halt` (Hold) end a reaction
  and pause new ones for 3 s.
- Follow's own slot updates do not end it (`cancel_reaction = false`), so a follower can
  finish a short dash to cover.
- `GameController.possess` clears the soldier's reaction and search at once.

**Measured** in the `tactics` suite:

| Order | Result |
|---|---|
| Hold | 5 of 6 soldiers used the HESCO wall 9 m away and ignored the one 25 m away. Nobody went more than 7.6 m from the held spot (limit 12 m). After the threat stopped, all were back within 1.0 m in 11.8 s. No unit orders, and the squad order stayed Hold |
| Move | 80 m across the front under fire with HESCO on the path. 3 soldiers took a 5.0 s cover break. The squad arrived (DONE) 2.0 m from its destination in 30 s and fired 195 shots on the move |
| Follow | The leader's squad walked 80 m under fire; followers stayed within 15.5 m of the leader. While the leader stood: 0 new follower orders (the COMBAT-01b Follow fix still holds) |
| Hold Fire | 6 of 6 reached cover in 3.2 s and fired 0 shots |
| Weapons Free | Fires from cover: 380 shots in `open_to_cover`, 0 of them stopped by their own cover |
| Possession | The possessed soldier had tactic "-" and no reaction in the same tick, and still none after 1 s. The squad mates kept their reactions |

## 5. HUD, readability and debugging

**Squad panel.**
- The rows scroll inside the space above the bottom HUD text. The overlap reported in
  COMBAT-01b is gone: with 9 squads the panel ends at y 403 and the text starts at 419.
- Each row shows the squad, faction, living (+ fallen), formation, order and progress,
  then `| n engaging, n under fire, n to / in cover`, then the FREE / HOLD button.
- The selected squad is highlighted. Its tag over the leader still shows the order and
  HOLD FIRE.

**F4 tactical debug** (optional, both views):
- per soldier: the tactic ("engaging / in cover"), and whether the soldier walks an order
  ("(order)") or an AI reaction ("(AI reaction)");
- the cover reason, for example "{cover: structure 9 m (can fire)}" or "{no usable cover
  within hold (taken by North-NS-2)}";
- an orange line towards the believed threat, a green ring on the chosen cover, and a
  dashed line along the reaction path;
- in the corner, the tactic counts and the cover search statistics (searches, found, none,
  unreachable).

**Unchanged:** the RTS zoom (5–200 m, `RTSCamera` exports), Tab, possession and all other
controls.

## 6. Automated validation

### 6.1 Tactics suite

`bash benchmarks/combat02/run_test.sh combat-tactics --shots` (`combat_tactics_selftest.gd`)
gives **PASS** (all 14 checks; `benchmarks/combat02/combat_tactics_test.json`).

- **Setup:** a threat squad of 6 holds 110 m south and fires, with raised health. The
  soldiers under test have raised health where a scenario must last.
- **`--only a,b`** runs single scenarios during development.

| Check | Result |
|---|---|
| Cover evaluation (direct) | Behind HESCO against the threat: protected, can fire. The same spot with the threat behind, in front of the wall, and in the open: all rejected |
| Open ground → cover | Under fire after 1.1 s, first move to cover 1.1 s, half in cover 3.4 s, 6 of 6 in cover. Spots 2.2 m apart. None unprotected against the real threat. 0 shots into own cover; at most 1 cover move per soldier; longest walk 1.8 s |
| Already in cover | 4 of 4 "staying here", drift 0.0 m, 144 shots |
| Wrong side of a wall | Soldiers 3 m on the threat side of a 10 m wall moved round to its far side (1.2–1.7 m behind it). 0 samples of "in cover" without protection |
| Unreachable cover | Soldier south of a closed HESCO ring. The protected spot inside was found, failed the path check, and was rejected (1 unreachable) and never chosen. The soldier took the reachable spot north of the ring |
| No stacking | 8 soldiers, an 8 m wall: 6 in cover, spots at least 1.18 m apart, bodies at least 1.1 m apart. The other 2 reported "taken by …" and fought from where they stood |
| Hold area, Move, Follow, Hold Fire, possession | §4 |
| No permanent loop | At most 1 cover move per soldier in `open_to_cover`; no soldier in SEEK_COVER for more than 1.8 s; brief reactions end at their limit (5.0 s against 5 s) |
| Save / load, dead stay dead, damage | §2 |
| Tiers with tactics | §2 |
| Squad panel | 9 squads, 0 px overlap |

### 6.2 The other suites on this branch

All run on this branch with `bash benchmarks/combat02/run_test.sh <kind>`. Logs and JSON
are in `benchmarks/combat02/`.

| Suite | Result | Notes |
|---|---|---|
| `combat-tactics` (COMBAT-02) | **PASS** | 14 checks, final run with screenshots |
| `combat-scale` (COMBAT-02) | **PASS** | §1.2 |
| `combat-ai` (COMBAT-01b) | **PASS** | Run with tactical reactions off, testing the 01b layer. Open fight hit ratio 11.4 %; holding-squad order frames 0 with the corrected counter |
| `combat` (COMBAT-01a) | **PASS** | Includes the HESCO seam change in `LineOfFire` |
| `squad` (UNIT-01A) | **PASS** | Follow: 0 orders while the leader stands |
| `large` (WORLD-CORE-02) | **PASS** | |
| `integration` (WORLD-INTEGRATION-01, construction) | **PASS** | |
| `base` | not run | Construction is unchanged; integration covers construction on `ref_20km` |

`combat-ai` was rerun after the idle-scan fix (§7.2); `combat`, `squad`, `large` and
`integration` ran before it. They have the AI switched off, so the scan does not affect
them.

### 6.3 Screenshots

These are real frames from the test runs (`docs/combat02/`):

| File | Shows |
|---|---|
| `c02_01_open_before_reaction.jpg` | North in the open, HESCO line in front, South firing (tracers), before anyone reacts |
| `c02_02_moving_to_cover.jpg`, `c02_02_moving_to_cover_f4.jpg` | Soldiers walking to the wall; with F4: "seeking cover (AI reaction)", green cover rings, dashed paths |
| `c02_03_fighting_from_hesco.jpg` | Six soldiers spread along the HESCO, firing over it |
| `c02_03b_hold_fire_in_cover.jpg` | The Hold Fire squad in cover, not firing |
| `c02_03c_staying_behind_hesco.jpg` | Soldiers that were already in cover, staying |
| `c02_04_hold_squad_keeps_its_area.jpg` | Hold squad: five behind the near wall, the far wall unused |
| `c02_05_scale_100v100_rts.jpg` (also 16v16, 50v50) | The 100 v 100 battle from the tactical camera |
| `c02_06_fps_possession_in_firefight.jpg` | First person behind HESCO in the fight, a tracer outgoing |
| `c02_07_squad_panel_many_squads.jpg` | 9 squads: the panel scrolls above the HUD text |
| `c02_08_f4_tactical_diagnostics.jpg` | F4: engaging / in cover, threat lines, cover rings, reasons |

## 7. Defects found and fixed outside the new features

1. **HESCO seams (shots through walls).** `ModularLine` places round(length / 1.06 m)
   cells, so a 12 m line has cells 1.09 m apart with 3 cm gaps, and shots and sight lines
   exactly on a seam went through.
   - **Fix:** `LineOfFire` closes the seams by extending line modules 0.12 m each way along
     the line.
   - **Not touched:** construction itself (cell count, visuals, saved bases) and physics
     colliders. The 3 cm gaps still exist there, which is harmless for walking.
2. **Idle soldiers blind behind them.** A soldier that turned towards a sound and then lost
   it kept facing that way. With a 150° field of view it never noticed enemies more than
   25 m behind it. Found by the COMBAT-01b stability test after the symmetry fights.
   - **Fix:** idle attention scans ±110° around the heading every 8 s (seeded by time and
     id). The body does not turn for it.
3. **Vegetation buckets filled in quadratic time** (§1.3).
4. **Test measurements that could not fail.** GDScript lambdas capture integers and floats
   by value. Four measurements were updated inside `_run_for(..., func(): ...)` callbacks
   and stayed 0:
   - COMBAT-01b `orders_and_possession.holding_south_order_frames`, which was reported in
     the COMBAT-01b report as 0;
   - three new ones (longest reaction, follower distance, and one count).

   All now use dictionaries. With the corrected counter the COMBAT-01b check still passes
   (0 order frames).
5. **`DetailManager` demotion counter.** Fixed in COMBAT-01b, carried over.

## 8. Remaining performance bottlenecks

1. **Camera jumps: about 410 ms frames.** Jumping the tactical camera 2.75 km or 12 km
   gives one frame of 390–420 ms in every case, including with no battle at all ("far" cold
   start). That is the existing synchronous re-centre of terrain collision and the navmesh
   (`DetailManager.activate_at` / `_update_collision`), not combat. It is the most visible
   hitch left; making the re-centre asynchronous is a WORLD-CORE item.
2. **Sight checks.** 85–125 µs each in GDScript, about 2 ms per tick at 100 v 100 (19
   checks per tick, budget 24). The next steps would be:
   - a shorter terrain march for lines that stay high above the ground;
   - re-checking a visible current target less often;
   - moving `LineOfFire` to native code if 200+ soldiers per battle become normal.
3. **Shots.** About 200–220 µs each to resolve. Misses fly the rifle's full 600 m through
   terrain and tree data.
4. **AI time per tick at 100 v 100 is still 4.5–5.3 ms** (60 Hz physics), about a
   quarter to a third of a 60 fps frame. It is fine on this machine (p99 frame 11–14 ms) but
   leaves less room on weaker CPUs.
5. **Body promotion of 100+ soldiers at once** (cold start, 18–40 ms frames) is
   `DetailManager` instantiating bodies in one tick. Staggering promotions would help.

## 9. Verified, measured, and not yet judged

**Implemented and verified by automated scenarios in the real world:**
- scaling to 100 v 100 and two simultaneous battles;
- distant fighting without bodies, and tier changes, with no duplicates;
- reactions to incoming fire;
- cover from HESCO (including staying, the wrong side, unreachable spots, and no stacking);
- Hold, Move, Follow and Hold Fire under fire;
- possession override;
- save / load of tactical state;
- the squad panel layout and the F4 overlay.

**Automatically tested but not manually verified:** whether any of it *feels* right.
- the pace of reactions (about 1 s to react, 2–3 s into cover);
- whether 6 / 12 m radii and 5–8 s reactions read as believable;
- whether soldiers standing upright behind HESCO look right without crouching;
- whether the shot budget or the half-rate distant perception is noticeable;
- whether players understand "AI reaction" vs "order" without F4.

**Covered only by unit-level checks, not by a dedicated scenario:**
- **Terrain, rock and building cover** use the same evaluation as HESCO, which the test
  checks directly. No scenario was staged on a reverse slope or behind a rock, and the
  meadow battles mostly found no cover at all (correctly: it is open ground).
- **Regroup reactions** (5 m / 4 s) follow the same code path as Move.

**For the manual playtest:**
1. Is the cover choice believable around real bases, walls and rocks, and in forests?
2. Is a 5 s cover break on Move too long or too short? Should moving squads react at all?
3. Do held soldiers return to their spots at the right moment (10 s of calm)?
4. Do idle soldiers noticing enemies behind them (the ±110° scan) feel fair?
5. Does a 100 v 100 fight read in RTS? Can you tell who is under fire or in cover?

## 10. Known limitations

- **No crouching or prone posture.** Cover lower than about 1.5 m protects the torso only.
- **No suppression, morale, flanking or coordinated movement** (out of scope). Every
  soldier reacts on its own; the squad only shares "under fire".
- **The threat is a single point per soldier.** Fire from two sides makes it follow the
  latest clearly different direction.
- **Cover in open terrain** often does not exist. Soldiers then keep fighting where they
  stand and search again every 4 s, which is cheap.
- **Abstract-tier cover** is reached in a straight line, and its reachability is a
  structure-footprint check. Navmesh paths exist only near the camera.
- **Followers' brief cover dashes** can put them a few metres out of formation until the
  next slot update.
- **The meadow test area** has no rocks and no slopes, so the scenarios use HESCO. Other
  cover types are covered by the direct evaluation, not by staged scenarios.

## 11. Recommendations for the next gameplay milestone

1. **Posture.** Crouch behind low cover: hit shapes, eye height and an animation together.
   It would make HESCO and low walls much more meaningful.
2. **Squad-level cover use.** Spread a squad along a wall when it holds a position, before
   it comes under fire. Today soldiers react individually.
3. **Suppression as an input to the existing reactions.** A near miss could lower accuracy
   and lengthen pauses, without a separate system.
4. **Asynchronous detail re-centre** (§8.1), and staggered body promotion.
5. **Manual playtest of COMBAT-01a, 01b and 02 together** (§9), then tune radii, times,
   scan and accuracy from what is seen.

## 12. Files

New:
- `scripts/debug/combat_tactics_selftest.gd`
- `scripts/debug/combat_scale_selftest.gd`
- `benchmarks/combat02/` (runner, logs, JSON before and after)
- `docs/combat02/` (screenshots)

Changed:
- `combat_brain.gd` (rewritten around the COMBAT-01b rules)
- `line_of_fire.gd`: unit index, cell warming and the quadratic fill fix, HESCO seams
- `unit_state.gd`, `world_state.gd` (squad index, orders end reactions)
- `squad_control.gd`, `soldier_body.gd` and `world_sim.gd` (reaction movement)
- `combat_sim.gd`, `game_controller.gd`
- `squad_panel.gd`, `game_hud.gd`
- `core_demo.gd`, `README.md`
- `combat_ai_selftest.gd`: tactics off for the 01b layer, a lambda capture fix, and
  `--only` / `--debug`
