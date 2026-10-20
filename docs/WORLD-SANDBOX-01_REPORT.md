# WORLD-SANDBOX-01 — Persistent faction warfare, strategic map and military operations

Branch `feature/world-sandbox-01`, based on `feature/combat-02` (3b76ade). No other worktree
was changed and nothing was merged into `main`.

All results come from scripted runs of the real game: Godot 4.7.2, Jolt, Vulkan, RTX 3070,
1600×900, `ref_20km`, vsync off. The war runs through the ordinary systems:
- unit and squad records in `WorldState`;
- `SquadControl` movement and formations;
- `DetailManager` bodies, navigation and the abstract tier;
- `CombatBrain`, `CombatSim` and `LineOfFire`.

The new strategic layer only issues orders to those systems. It never moves a soldier or
decides a fight itself.

**Nobody has play-tested this by hand.** Section 10 separates what was verified from what
was only measured, and lists what a manual playtest should judge.

## Summary

- **Three factions** share the 20 km world:
  - North is the player.
  - South is an aggressive AI.
  - East is a defensive AI.

  Each AI follows a configurable profile (`assets/strategy/*.tres`).
- **Twelve objectives** sit at real places on the map: three HQs, five settlements, three river
  bridges and one junction village. Each objective has an owner, a value and a capture state
  (presence → contested → progress → transfer).
- **Operations** (ATTACK, DEFEND, REINFORCE, MOVE) send real squads along planned routes. The
  squads fight with the normal combat AI. Operations end as completed, failed or cancelled,
  and record their losses.
- **Routes** cover the whole world on a 50 m grid. They prefer roads, cross the river only on
  bridges and never enter a lake or climb a cliff. A planned route takes 0.4–2 ms; the grid
  loads from cache in 24 ms.
- **Strategic map** (M):
  - territory, objectives with capture progress;
  - your squads, and only the enemy forces your soldiers have seen;
  - operations with their routes, and the war log;
  - orders by right-click or buttons, and jumps to the tactical view.
- **Camera transitions no longer stall.** A map jump or possessing a distant soldier used to
  freeze for about 400 ms. It now takes 16–21 ms (one outlier of 65 ms); the possession call
  dropped from 613 ms to 6 ms.
- **Command priority:** player order > operation > CombatBrain reaction. Any direct RTS order
  releases the squad from its operation.
- **Save / load** (F5 / F9) restores the whole war: 0 differences across 336 compared keys with 4
  operations in progress.
- **Time compression** (`,` and `.`; 1 / 2 / 4 / 8×) keeps the physics step at 1/60 s.
- **War log and HUD notifications** report captures, operations, reinforcements and
  exhausted reserves.

All eight requested scenarios pass (§6).

## 1. Architecture

```
WorldSim._physics_process
  abstract_step → squads.update → war.update → brain.update → combat.update
                                    │
              WarSim ───────────────┤ capture (1 s), intel (2 s), operations (1 s),
                                    │ reserves (5 s), faction AI (per profile)
                                    ▼
                       issues orders through SquadControl.follow_route / WorldState.issue_move
```

| File | Role |
|---|---|
| `scripts/strategy/war_state.gd` | Authoritative war record: factions, objectives, operations, event log. Part of the `WorldState` snapshot. |
| `faction_state.gd`, `objective_state.gd`, `operation_state.gd` | Plain records with `to_dict` / `from_dict`. |
| `faction_profile.gd` + `assets/strategy/aggressive.tres`, `defensive.tres` | AI personality (decision interval, attack limits, force ratios, scoring weights, recovery). |
| `scripts/strategy/war_sim.gd` | Capture, intelligence, operations, reserves, faction AI. Owned by `WorldSim` as `sim.war`. |
| `scripts/strategy/strategic_routes.gd` | World passability grid and A* routes. |
| `scripts/strategy/sandbox_setup.gd` | Objectives, factions, starting squads and HQ fortifications. |
| `scripts/ui/strategic_map.gd` | The strategic map. |
| `scripts/world/terrain_collision_streamer.gd` | Terrain collision built in pieces (transition fix). |
| `scripts/debug/sandbox_selftest.gd` | Scenarios, measurements, screenshots (`--sandbox-test`). |

Changes to existing systems:
- `SquadState` gained `op_id`, `route`, `route_i` and `station_objective`, all persisted.
- `SquadControl.follow_route` follows a route leg by leg. A leg that makes no progress for
  25 s is skipped, and the skips are counted.
- Abstract units in `WorldSim` now follow walls. Without this they stuck on HQ HESCO lines
  outside the detail radius.
- `WorldState` emits a `saving` signal and saves the war.
- `DetailManager` and `AreaNavigation` changed for the transition fix (§4).
- `GameController`, `RtsController` and `SquadPanel` limit command to the player faction while a
  war is active. Player orders release squads from operations.
- `GameHud` shows war notifications and a WAR line.
- `UnitVisuals` adds a third uniform colour.

The sandbox is the default start (`core_demo.gd`). Every earlier test flag (`--core-test`,
`--combat-test`, `--integration-test` …) still builds the old two-faction layout, so the
older suites are unchanged.

## 2. Factions, objectives and capture

| Objective | Kind | Start owner |
|---|---|---|
| North HQ | hq | North |
| South HQ | hq | South |
| East HQ | hq | East |
| Sentrum | town | neutral |
| Østby | town | East |
| Verket | town | South |
| Elvetun | village | North |
| Haugen | village | neutral |
| Ødegård | village | East |
| North Bridge | bridge | North |
| Centre Bridge | bridge | neutral |
| South Bridge | bridge | neutral |

Each faction starts with five squads of eight soldiers (120 soldiers in total). Reserves are
North 32, South 40 and East 40. Each HQ is fortified with a 56 × 56 m HESCO perimeter with
four gates, built through the ordinary construction system.

**Capture.** Every second each objective counts the living soldiers of each faction inside its
radius:
- Two or more soldiers of one faction alone, without the owner present, build progress. Speed
  scales with numbers (`capture_ref` 4); a full capture takes 90 s at the reference strength.
- If two factions are present, the objective is *contested* and progress freezes.
- Progress decays when the attackers leave: over 30 s if the owner returns, 180 s if the
  objective is empty.
- At 100 % the objective changes owner, and the history records `[time, owner]`.

The map draws the progress arc and blinks the ring while the objective is contested.

**Reserves.** Every 240 s a faction with reserves and fewer than 9 squads gets a new squad of
8 at its HQ. A faction without reserves can no longer replace losses, and the log says so.

## 3. Faction AI and operations

Each AI decides every `decision_s` (South 25 s, East 45 s), in this order:
1. **Depleted squads** (below `min_squad_size`) return home and merge into garrisons.
2. **Threatened objectives:** if known enemy strength within `threat_radius` exceeds the
   local force by `threat_ratio`, the AI sends REINFORCE from the nearest free squads.
3. **Garrisons:** the HQ and valuable objectives keep `hq_squads` / `garrison_squads` on
   DEFEND.
4. **Offensive:** candidate targets are scored on value, distance (from the faction's nearest
   owned objective, not from the HQ), neutral or enemy owner, and whether the faction lost it
   earlier. The AI attacks the best target if its free strength reaches `attack_ratio`
   times the known enemy strength there, up to `max_attacks` active attacks.

After a failed attack the faction recovers for `recovery_s` (South 120 s, East 360 s) before it
attacks again.

| | South (aggressive) | East (defensive) |
|---|---|---|
| Decision interval | 25 s | 45 s |
| Max simultaneous attacks | 2 | 1 |
| HQ / other garrison squads | 1 / 0 | 2 / 1 |
| Force ratio for attack | 1.2 | 2.0 (and ≥ 16 soldiers) |
| Max attack distance | 11 km | 6 km |
| Recovery after failure | 120 s | 360 s |

**Operation lifecycle.** PLANNING → MOVING → ENGAGING → SECURING → COMPLETED / FAILED / CANCELLED.
- **ATTACK** routes each squad to a staging point 350 m short of the target. From there the
  squads assault, and the CombatBrain takes over contact.
- An attack **fails** when losses exceed 65 % of its starting strength (`fail_ratio` 0.35 left),
  or after 20 minutes without success.
- **DEFEND** ends after 150 s without enemies near the objective.
- **REINFORCE** that arrives at an objective that has meanwhile been lost turns into a
  counter-attack. Otherwise it joins the operation there or stays as garrison.
- Stuck squads are rerouted.

**Intelligence.** Every 2 s each faction marks enemy soldiers within 400 m of its own soldiers as
known. Known contacts are forgotten after 90 s without contact. AI threat assessment uses only
this knowledge, and so does the player's map.

## 4. Routes and camera transitions

**StrategicRoutes.** A 400 × 400 grid of 50 m cells covers the world.
- **Impassable cells:**
  - slope above 32°;
  - lakes (from the terrain's lake polygons);
  - the river (polyline with width plus a 12 m margin).
- **Roads** cost 0.45 of open ground.
- **Bridges:** road segments that span the river (±3 points) open it. Roads that only run along a
  bank do not.
- The four bridges longer than 50 m are found automatically.
- **Routes:** `AStarGrid2D`; corners plus every fourth cell, with each leg checked for clearance.

| | |
|---|---|
| Grid build, first start | 1115 ms (cached in `user://strategic/ref_20km_grid.bin`) |
| Grid load from cache | 24 ms |
| One route across the map | 0.4–2 ms |
| Route check, six HQ / objective pairs | all cross only at bridges, 0 samples in water or on impassable ground |

**The ~400 ms transitions.** A jump from the map or a possession of a distant soldier stalled
for several frames. Profiling showed two causes:
- Terrain3D rebuilt every collision shape in the 200 m radius in one call (~390 ms).
- The navmesh source geometry was built on the main thread (~115 ms).

The fix:
- **`TerrainCollisionStreamer`** replaces Terrain3D's dynamic collision in the sandbox.
  - It covers the same area with HeightMapShape3D chunks of 32 × 32 cells (62.5 m), built from
    the terrain heights (groundwork edits included).
  - Chunks nearest the observer are built first, within 3 ms per frame.
  - Possession builds the chunks within 40 m at once.
  - `DetailManager` gives a soldier a body only when the chunk under it exists, so nobody
    stands on missing ground.
- **Threaded navmesh source:** async rebakes build the source geometry and bake on a
  `WorkerThreadPool` task. The previous navmesh stays active until the new one is ready.

| | Before | After |
|---|---|---|
| Worst frame of a map jump | 395–400 ms (3 frames over 33 ms) | 16–21 ms (one 65 ms outlier in one run) |
| `possess()` call | 613 ms | 6 ms |
| Map → RTS → FPS in scenario 6 | — | worst frame 47.5 ms, one frame |

Both can be switched off for comparison: `--no-ground-stream` and `--no-thread-nav`. A
`WorkerThreadPool` task that was never collected caused an exit crash (code 139). It was found
by bisecting with these flags and fixed with `wait_for_task_completion`.

## 5. Strategic map, player control and persistence

**Map (M).**
- **Background and territory:**
  - The macro map preview is the background.
  - The territory overlay gives each point to the nearest objective within
    1600 m + 600 m × value, with darker borders.
- **Objectives:** icons by kind (star = HQ, ring = town, diamond = village, bar = bridge), plus
  capture arc and contested blink.
- **Squads:**
  - Your squads show as NATO infantry symbols with id and strength.
  - Squads at the same objective are drawn in a row so they don't overlap.
- **Enemies:** only known enemy groups, as fading diamonds.
- **Operations:** routes and labels (`ATTACK #1 · moving`).
- **Side panel:**
  - faction summary;
  - selection info;
  - buttons Attack / Defend / Reinforce / Move / Cancel op / View;
  - operation list with Go / ✕;
  - war log.
- **Input:**
  - Wheel zoom; middle-drag or WASD pan; Home shows the whole map.
  - LMB selects; drag a box to select several.
  - RMB orders the selection: an enemy or neutral objective = attack, your own = reinforce,
    open ground = move.
  - G views the selection in 3D.

**Control.** In RTS and FPS you only command North (`command_any_faction = false`). A direct RTS
order (move, hold, follow, regroup) calls `release_squads` and takes the squad out of its
operation. Operations override CombatBrain reactions through the existing reaction
cancellation in `issue_move`.

**Time compression.** `,` / `.` step through 1 / 2 / 4 / 8×; first person always runs at 1×.
Raising `Engine.time_scale` alone stretched the physics step to 0.13 s at 8×. Now
`physics_ticks_per_second` rises with the scale, so the step stays 1/60 s. Measured at 8×:
- step 0.0167 s;
- 480 ticks/s;
- achieved speed 6.4× (the frame budget limits it).

**Persistence.** `WarState` is part of the `WorldState` snapshot: factions, objectives with
history, operations with squads and phases, and the event log. Each squad's route and progress
are saved too. The comparison signature is taken at save time through the new `saving` signal,
so an order issued after F5 doesn't count as a difference.

**HUD.** War events appear as notifications at the top centre for 9 s, at most 4 at a time, and
the HUD shows a WAR line. The full log (last 200 events) is in the map panel.

## 6. Automated scenarios

Runner: `bash benchmarks/sandbox01/run_test.sh sandbox [--shots] [--only a,b]`. The
scenarios set forces up close and run time compressed. There are no long real-time runs.

| # | Scenario | Result |
|---|---|---|
| 1 | Routes: six pairs across the world | **PASS** — all cross only at bridges, 0 samples in water or on impassable ground |
| 2 | Offensive: 3 North squads attack neutral Haugen held by 1 squad | **PASS** — engaging → securing → completed; captured after 181 s; 12 of 24 attackers lost, no defenders left |
| 3 | Reinforcement: South takes Elvetun, North reinforces from 3.7 km | **PASS** — route without water; arrived after 855 s; converted to a counter-attack and recaptured Elvetun; 372 shots by the reinforcements; no South soldiers left |
| 4 | Map → RTS → FPS during an operation | **PASS** — jump worst frame 47.5 ms (one frame); 2 player shots; units 144 = 144; no duplicate shots; damage events match damaging shots; operation membership kept |
| 5 | Navigation: a 12.56 km march across the river | **PASS** — crossed at bridge 1; 0 of ~175 000 position samples in water; completed |
| 6 | Save / load with 4 active operations | **PASS** — 0 differences across 336 keys |
| 7 | Extended autonomous war: 40 sim-minutes at 24× (100 s real) | **PASS** — see below |
| 8 | Time compression at 8× | **PASS** — step 0.0167 s, 480 ticks/s, achieved 6.4× |

Scenario 7 in detail:
- **Operations:** 9 operations (2 completed, 1 failed, 6 moving).
- **War activity:** 5 captures and 13 reinforcements.
- **Health checks:**
  - no capture loops;
  - no stuck soldiers;
  - state consistency OK.
- **Activity:** the longest time a faction had no operation was 2.3 minutes for East and 0 for
  South.
- **Cost:**
  - `WarSim` averaged 1219 µs per tick at the coarse 24× step, with a maximum of 10.3 ms;
  - faction AI decisions took at most 3.4 ms.

Logs: `benchmarks/sandbox01/sandbox_run2_scenarios.log` (scenarios 2–7), `sandbox_test.log`
(scenario 8), `transitions_before.log` (transitions before the fix),
`sandbox_run1_partial.log` (first run, including the save/load difference that was fixed).

## 7. Performance

| Situation | p99 (ms) | Max (ms) | Notes |
|---|---|---|---|
| Map overview | 3.8 | 10.1 | `WarSim` 66 µs, brain 0.85 ms |
| RTS at HQ | 5.9 | – | |
| War far away | 4.0 | – | |
| War far away, 8× | 11.9 | – | measured before the fixed-step fix |
| 50 v 50, RTS | 7.7 | 14.7 | `WarSim` ~80 µs, brain 1.9 ms |
| 50 v 50, FPS | 8.5 | 13.8 | |

No frame was over 33 ms. Static memory is about 1.9 GB. The strategic layer itself costs well
under 0.1 ms per tick at 1×; combat remains the dominant cost.

## 8. Screenshots (`docs/sandbox01/`)

| File | Shows |
|---|---|
| `s01_01_strategic_map_start.jpg` | Whole map at war start |
| `s01_02_objectives_and_borders.jpg` | Objectives and territory borders |
| `s01_03_force_markers.jpg` | Zoomed view of the centre (Sentrum, Centre Bridge) after an East capture, with the capture zone |
| `s01_04_operation_planned.jpg` | A planned player operation with its route |
| `s01_05_forces_on_strategic_route.jpg` | Reinforcements on their route |
| `s01_06_objective_under_attack.jpg` | Contested objective |
| `s01_07_territory_changed.jpg` | Territory after a capture |
| `s01_08_rts_active_operation.jpg` | RTS view of an active operation |
| `s01_09_fps_same_operation.jpg` | First person in the same operation |
| `s01_10_multiple_operations.jpg` | Two simultaneous player attacks on Sentrum and Centre Bridge |
| `s01_11_map_after_autonomous_war.jpg` | Map after the AI factions fought on their own; East holds the centre |

## 9. Regressions run and not run (change-impact)

| Suite | Run? | Why |
|---|---|---|
| `integration` (WORLD-INTEGRATION-01) | **Run — PASS** | Abstract units now follow walls, and squad / world state gained route code; this suite checks abstract units against structures |
| `large` (WORLD-CORE-02) | **Run — PASS** | Long abstract marches through the changed movement code |
| `squad`, `combat`, `combat-ai`, `combat-scale`, `combat-tactics` | Not run | Their abstract movement never meets structures, and the route code is inactive without routes. The ground streamer and threaded navmesh are only enabled in the sandbox |
| `core`, `base` | Not run | No change to their code paths |

## 10. Verified, measured, and not yet judged

**Verified by automated checks:** everything in §6. This includes:
- bridges-only routes;
- capture and transfer;
- operation phases and outcomes;
- counter-attacks;
- player orders overriding operations;
- shot and unit consistency across views;
- save / load equality;
- fixed-step time compression.

**Measured only:** frame times (§7) and transition times (§4).

**Needs a manual playtest:**
- whether the AI factions feel aggressive or defensive enough, and how long a war lasts;
- readability of the map at different zoom levels: marker overlap and colour of known enemies;
- whether right-click orders are intuitive (attack / reinforce / move by target);
- pacing of reserves and reinforcements (240 s) and capture time (90 s);
- what it feels like to be in an assault in first person while the operation runs around you.

## 11. Known limitations and open defects

- **Test warps use coarse physics steps.** The accelerated scenarios (`_warp`, 8–32×) still
  scale `Engine.time_scale` alone, so their physics step reached up to 0.53 s. The mechanics
  were verified, but combat fidelity in those warps is coarser than in play. The in-game
  compression is fixed (§5); the test helper is not.
- **Long marches are slow.** A cross-map operation takes about 30 game minutes on foot. There
  are no vehicles yet.
- **One 65 ms transition outlier** was seen once and not reproduced.
- **Intelligence is simple.** It is proximity-based (400 m), with no line-of-sight check, no
  scouting and no reports from civilians.
- **No supply.** Strength comes only from reserves at the HQ.
- **The AI uses squads only.** It does not build fortifications.
- **`feature/character-01` is not integrated.** It is visual only, branched from an old base and
  touches the soldier scripts.
- **Distance LOD is off in the sandbox,** so distant fights are independent of where the camera
  is. This costs some AI time when many fights run at once.

## 12. Recommendations for the next milestone

1. Switch the test `_warp` to the fixed-step time scale so accelerated combat matches play.
2. Add transport (trucks on the road network) to shorten marches, and use the route grid for
   them.
3. Add supply and line-of-sight intelligence so that holding bridges and junctions matters.
4. Let AI factions use the construction system for field fortifications at captured
   objectives.
5. Run a manual playtest of one complete war before tuning the profiles.
