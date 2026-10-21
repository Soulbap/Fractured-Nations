# AI-ARCHITECTURE-RESEARCH-01 — Combined-arms military AI for FRACTURED NATIONS

Research and architecture milestone. **No gameplay code was changed.** Branch
`research/ai-architecture-01` (worktree `../fractured-nations-airesearch01`, from
`feature/world-integration-03` @ 21e846a) holds this document only.

Evidence tags used throughout: **[VERIFIED]** read in the source of 21e846a (file:line given) or
measured by an existing test; **[DOCUMENTED]** from a project report or plan; **[RESEARCHED]**
from an external source listed in §34; **[PROPOSED]** a recommendation, not implemented;
**[UNKNOWN]** not enough evidence.

---

## 1. Executive summary

FRACTURED NATIONS already has the skeleton of a three-level military AI, and it is the right
skeleton: one authoritative `WorldState` with plain records (`UnitState`, `SquadState`,
`OperationState`, `ObjectiveState`, `StructureState`), one simulation step (`WorldSim`) that
runs the abstract tier, squads, the war, perception/tactics and combat in that order, and a
`DetailManager` that swaps representations (bodies / proxies) without touching records. The
strategic AI (`WarSim._decide`) is a rule-ordered utility scorer over objectives; the
operational layer is the `OperationState` life cycle with four types; the tactical layer is
`CombatBrain` (perception, target choice, firing, cover reactions) on records only, so it is
identical in both tiers. **The architecture does not need replacing.** [VERIFIED]

What is missing is not a framework but *information and vocabulary*: the AI has no shared
contact model beyond a 2-second "known enemy soldier" table and 120 m squad shouts; squads
have no tactical vocabulary beyond Move / Hold / Follow / Regroup and a per-soldier cover
reaction; operations have no notion of composition, transport, supply or phases beyond
move-engage-secure; bases are geometry only (structures carve navmeshes and block the
abstract grid, nothing else); vehicles are records with no movement (LOGISTICS-01 is adding
`VehicleSim` / `VehicleRouter` / `VehicleState`, uncommitted at the time of writing).

**Recommendation (the smallest coherent set):**

1. **Keep** the record-centric, three-level ownership (`WarSim` → `OperationState` → squads /
   `CombatBrain`) and the single simulation loop. Keep utility scoring for the strategic level,
   state machines for operations and reactions, and the data-driven `StructureDef` /
   `InfantryLoadout` approach for content.
2. **Extend** with five things, in this order of dependency: (a) a shared **contact /
   intelligence record** per faction (`WarState`), fed by `CombatBrain` and consumed by
   `WarSim`, operations and squads — replacing both the `known` table and the ad-hoc shouts;
   (b) a **squad tactical layer** in `SquadControl` (fire team split, bound, suppress, flank,
   withdraw) built from the existing slot / route / reaction primitives; (c) **capability and
   facility metadata** on `UnitState` / `StructureDef` (data, not code) so operations can be
   composed without naming assets; (d) a **mission plan on `OperationState`** — a small ordered
   task list (assemble, mount, move, dismount, assault, hold, return) advanced by the existing
   1 s `_update_operation`, instead of an HTN engine; (e) a **coarse influence layer** on the
   existing 50 m `StrategicRoutes` grid (threat, control, route risk), updated incrementally
   from the contact record.
3. **Add** two genuinely new, narrow components when their consumers exist: a **facility
   service / reservation table** inside `ConstructionState` (lightweight, saved, tier-agnostic)
   and a **helicopter flight controller** (kinematic, waypoint + altitude-above-ground
   autopilot, abstract tier = great-circle along a terrain-clearance profile).
4. **Avoid**: a GOAP/HTN planning engine, behaviour-tree runtime, a separate base simulation,
   per-unit influence maps, a second road/route representation, a vehicle "framework" ahead of
   LOGISTICS-01, and aircraft-specific intelligence.

Roadmap (§31): quick wins first (contact record + squad bounding + observability overlay),
then operational plans and facilities after LOGISTICS-01 lands, then helicopters, then AI base
construction and base defence, with combined-arms operations as the integrating milestone.

---

## 2. Verified current architecture

### 2.1 Simulation loop and ownership [VERIFIED]

`scripts/core/world_sim.gd:123-146` — every physics tick (1/60 s simulated; `TimeCompression`
raises the tick rate rather than the step, `scripts/core/time_compression.gd`):

```
WorldSim._physics_process(delta)
  state.time += delta
  for u in units without a body and alive:  _abstract_step(u)      # straight-line travel, structure sliding, terrain/deck height
  squads.update(delta)        # SquadControl: every 0.5 s (update_interval), follow every 1 s
  war.update(delta)           # WarSim: capture 1 s, intel 2 s, operations 1 s, reserves 5 s, faction decisions every profile.decision_s
  brain.update(delta)         # CombatBrain: perception round robin at perception_hz=3 per soldier, los_budget=24 sight checks/frame, cover search budget, engagement for "soldiers with something to do"
  combat.update(delta)        # CombatSim: reload timers etc.
```

Bodies (`SoldierBody`, `VehicleBody`) run in their own `_physics_process` and write position,
yaw, velocity and move state back into the record (`soldier_body.gd:123-139, 273-278`).

```
                    ┌──────────────────────────────────────────────────────────────┐
                    │  WorldState (authoritative, saved)                            │
                    │  units{UnitState} squads{SquadState} war:WarState            │
                    │  construction:ConstructionState  roads:RoadNetwork  time      │
                    └───────▲───────────▲─────────────▲───────────▲────────────────┘
   writes orders/           │           │             │           │ reads footprints,
   capture/ops/known        │           │             │           │ carves nav, blocks grid
┌────────────┐  decisions ┌─┴────────┐  │  ┌──────────┴──┐  ┌─────┴─────────────┐
│ FactionPro-│──────────▶ │ WarSim   │──┼─▶│ SquadControl│  │ StructureManager   │
│ file (.tres)│           │ (strategy│  │  │ (orders →   │  │ (pads, grass, MM,  │
└────────────┘           │  + ops)  │  │  │  per-soldier│  │  collision, nav     │
                          └─┬───────┘  │  │  moves,     │  │  obstacles,         │
                   routes   │          │  │  routes)    │  │  blocks_point)      │
                 ┌──────────▼───┐      │  └──────┬──────┘  └─────────┬──────────┘
                 │StrategicRoutes│     │         │ UnitState.order    │
                 │ 50 m AStarGrid│     │         ▼                    ▼
                 └──────────────┘     │   ┌────────────────────────────────────┐
                                      │   │ WorldSim abstract step  │ SoldierBody│  ← DetailManager promotes/demotes
                                      │   │ (no body)               │ (navmesh)  │     by distance to the observer
                                      │   └────────────┬────────────┴─────┬──────┘
                                      │                │ positions         │
                 ┌──────────────┐     │   ┌────────────▼───────────────────▼──────┐
                 │ LineOfFire   │◀────┼───│ CombatBrain (records only):            │
                 │ (structures, │     │   │ perceive → acquire → engage/fire;       │
                 │  trees,      │     └───│ under fire → cover search → react_target│
                 │  terrain,    │         └────────────────┬───────────────────────┘
                 │  unit hulls) │                          │ request_fire
                 └──────────────┘         ┌────────────────▼───────────────────────┐
                                          │ CombatSim: one shot resolution, damage,  │
                                          │ death → signals (FX, HUD, WarSim, Brain) │
                                          └──────────────────────────────────────────┘
```

Order ownership, highest first [VERIFIED, `war_sim.gd:15-19` comment and code]: the player's
direct orders (`RTSController.order_move → _player_takes → sim.squads.order_move`,
`rts_controller.gd:204-218`; `WorldState.issue_move/halt`, `world_state.gd:124-147, 262-273`)
release a squad from its operation (`WarSim.release_squads`); operations issue squad routes
(`follow_route`); `CombatBrain` only ever sets `UnitState.react_target` (a temporary goal the
body / abstract step prefers to the order, `combat_brain.gd:16-23`), and any new order cancels
the reaction (`world_state.gd:140-146`). **There is no place where two AI levels write the
same field** — this is the single most valuable property of the current code and the proposals
below preserve it.

### 2.2 Subsystem audit

The twelve questions of the brief, per subsystem. "Tier" = detailed (bodies) / abstract /
both.

#### WorldState / UnitState / SquadState (`scripts/core/world_state.gd`, `unit_state.gd`, `squad_state.gd`) [VERIFIED]

* Responsibilities: the records and their save/load (`snapshot/restore/apply_snapshot`,
  `world_state.gd:289-372`; `apply_snapshot` overwrites fields in place so bodies keep valid
  references). Orders at unit level (`issue_move`, `issue_group_move`, `halt`, `detach`).
* Decision logic: none (data). Inputs: everything; outputs: signals `order_changed`,
  `squad_changed`, `shot_fired`, `unit_damaged`, `unit_died`, `restored`, `saving`.
* `UnitState` fields relevant to AI: `order/order_target/move_state`, combat state
  (`ai_state`, `target_id`, `target_last_pos`, `target_seen_at`, `target_visible`), tactic
  (`tactic`, `react_target`, `react_state`, `cover_pos`, `threat_pos`, `under_fire_until`,
  `anchor_pos`), weapon/ammo (`weapon_id`, `mag`, `reserve`), `loadout`, `has_body`,
  `player_controlled`. `Kind { SOLDIER, VEHICLE }`; vehicles have speed 0 and `issue_move`
  refuses them (`world_state.gd:124-127`). All of it is persisted (`to_dict`,
  `unit_state.gd:128-170`).
* `SquadState`: members, leader, `Order { NONE, MOVE, HOLD, FOLLOW, REGROUP }`, formation
  LINE/COLUMN, spacing, `detached`, `blocked`, `fallen`, `roe`, `op_id`, `route`, `route_i`,
  `station_objective`. Persisted.
* Tier: both (the records are the unit). Performance: dictionaries keyed by id; `units_where`
  scans. Limitation: no vehicle-specific state (LOGISTICS-01 adds `UnitState.veh`
  [DOCUMENTED]); no "last known contact" record except on the soldier that saw it; no
  capability or role fields. Strength: every field needed by AI is already a persisted, plain
  value — new AI state has an obvious home. Extension points: new fields on the records with
  `to_dict/from_dict`; new record types inside `WarState` (as `OperationState` was added).

#### WorldSim (`scripts/core/world_sim.gd`) [VERIFIED]

* Abstract step (`:164-208`): straight-line travel at `u.speed` toward `order_target` (or
  `react_target`), arrival at `abstract_arrive_m`=1 m, structure avoidance by
  `_free_direction` (look-ahead + next-step tests against `StructureManager.blocks_point`,
  45°/90°/135° sliding, BLOCKED when nothing is free; WORLD-INTEGRATION-03 fix), height from
  terrain or bridge deck (`_settle_height`). Vehicles are not moved (speed 0).
* Tier: abstract only; owns the registries `bodies`, `proxies`. Performance: O(units) per
  tick; measured in WORLD-PLAYTEST-01 as part of a ~1.4 ms tick with the war running
  [DOCUMENTED]. Limitation: no path search in the abstract tier ("an abstract unit does not
  find a gate on its own", comment `:228-233`); no vehicle kinematics (LOGISTICS-01's
  `VehicleSim` is planned to be owned here [DOCUMENTED]). Extension points: additional
  per-tick steps are added here in order (vehicles, later aircraft); the tier-independence rule
  ("records only") is what every new mover must honour.

#### DetailManager (`scripts/core/detail_manager.gd`) [VERIFIED]

* Promote within 120 m / demote beyond 150 m of the observer (`:36-39`), one runtime navmesh
  area of 440 m re-centred when the observer drifts 45 m (async bake on a worker), terrain
  collision streamed around the observer, vehicles and structures carved as obstacles
  (`_rebake`, `:203-238`). `activate_at` for map jumps / possession.
* Tier: it *is* the tier boundary. Performance: bakes measured at 0.009 ms incremental to
  tens of ms full [DOCUMENTED, WORLD-PLAYTEST-01]. Limitation: exactly one observer and one
  navmesh area — a second "interest point" (e.g. a base under attack the player watches on the
  map) has no bodies; vehicles get a body but today it is static. Strength: representation
  swap never copies state. Extension: `promote_radius` per kind (aircraft need bodies/visuals
  at longer ranges but no navmesh), multiple areas later if ever needed (the class comment
  explicitly anticipates "one region per area around active units").

#### WarState / WarSim (`scripts/strategy/war_state.gd`, `war_sim.gd`) [VERIFIED]

* Records: `FactionState` (profile id, HQ objective, reserves, recovery/decision timers,
  statistics, `last_decision` text), `ObjectiveState` (kind hq/town/village/bridge/junction,
  value 1..3, owner, capture progress, contested, history, presence), `OperationState` (type
  ATTACK/DEFEND/REINFORCE/MOVE, phase PLANNING→MOVING→ENGAGING→SECURING→COMPLETED/FAILED/CANCELLED,
  squads, staging_pos, losses, route_preview), war log (200 entries). All saved.
* Decision logic — strategic (`_decide`, `:671-776`, every `decision_s` = 25–30 s per AI
  faction): (0) depleted squads (< `min_squad_size`) go home; (1) threatened owned objectives
  (`known_near` within `threat_radius`) get REINFORCE until defenders ≥ `threat_ratio` ×
  known attackers; (2) valuable objectives without a garrison get DEFEND; (3) one ATTACK if
  not recovering, fewer than `max_attacks` running, and enough free soldiers: target = argmax
  over objectives of `value·w_value − d_km·w_distance + w_neutral|w_enemy + w_retake`,
  need = `defenders·attack_ratio` (unseen garrison assumed `value·4`, HQ ≥ 24), commit =
  max(need, `attack_commit` × free); (4) forward deployment of idle HQ squads to the front
  objective. Free squads = not in an operation, ≥ min size, minus garrison keeps
  (`_free_squads`). All numbers from `FactionProfile` (.tres, `aggressive` / `defensive`).
* Decision logic — operational (`_update_operation`, `:411-520`, every 1 s): per type, a
  state machine over phases driven by squad routes finishing, objective owner / capture
  state, losses (`fail_ratio`=0.35), timeouts (`assault_timeout_s`=1200,
  `defend_quiet_s`=150); re-sends a squad that lost its route; REINFORCE turns into ATTACK
  if the objective fell, or joins a running operation at the same objective.
* Intelligence (`_update_intel`, `:222-258`, every 2 s): `known[faction][enemy_unit_id] =
  [position, time]` when any own soldier is within `intel_m`=400 m (per-faction 128 m grid
  from `CombatBrain._fgrid`) or the enemy is within an owned objective's radius + 400 m;
  forgotten after `intel_forget_s`=90 s. This is the **only** faction-level knowledge; it is
  omniscient within 400 m (no line of sight, no vegetation) and blind beyond.
* Reserves (`_update_reserves`): a new 8-man squad at the HQ every 240 s while reserves and
  `max_squads`=9 allow. Capture (`_update_capture`): presence inside radius, 90 s to capture,
  contested when two factions present.
* Inputs: `StrategicRoutes.route`, `CombatBrain._near/_fgrid`, objectives; outputs: squad
  routes via `SquadControl.follow_route`, log events, `FactionState.last_decision`. Tier: both
  (records). Performance: measured `war_update_us_avg` 53–89 µs with max 7–9 ms spikes
  (route planning) in WORLD-INTEGRATION-03 perf runs [VERIFIED, `benchmarks/raw/integration03_test.json`].
* Limitations: objectives are the only strategic vocabulary (no roads, bridges-as-infrastructure
  beyond `kind`, no bases, no supply); `known` is a unit list, not an estimate; no force
  composition (infantry only); operations are single-echelon (every squad gets the same route
  and the same ENGAGING order); no staging/assembly beyond `staging_m`=350 m; replanning is
  "send again from here"; no withdrawal except FAILED by losses; one target per decision.
* Strengths: operations are real squads with real routes; the player can take any squad at
  any time; the decision is explainable (`last_decision` string); everything is data-driven
  through `FactionProfile`. Extension points: `_decide` scoring (more terms, more candidate
  actions), `OperationState` (new types / a plan list), `known` → contact records,
  `_update_operation` (new phases), `FactionProfile` (new weights).

#### SquadControl (`scripts/core/squad_control.gd`) [VERIFIED]

* Turns squad orders into per-soldier move orders at formation slots (`_send_to_slots`,
  `_slots`, `_assign`), follows routes waypoint by waypoint (`follow_route`, `_update_route`:
  next leg when the leader is within `route_reach_m`=30 m; stall after `route_stall_s`=25 s
  → `_replan` up to 3 times then skip), routes any Move longer than `route_min_m`=150 m or
  crossing water/cliffs through `StrategicRoutes` (`_routed_move`), column on the march and
  the ordered formation on the last leg, Follow slots re-issued when they move
  `follow_reissue_m`, status (MOVING/PARTIAL/DONE) from member move states.
* Tier: both. Cadence: 0.5 s. Limitations: no tactical orders (bound, suppress, flank, take
  cover as a squad), no fire-team sub-structure, no speed/stance control, formation = LINE or
  COLUMN only, no vehicle awareness. Strengths: the slot/route mechanism is simple and
  proven over 13 km marches (sandbox `navigation` test) [VERIFIED]. Extension points: new
  `SquadState.Order` values and a per-squad tactical state advanced in `update()`; slots are
  already "preferences" that bodies and the abstract tier execute identically.

#### CombatBrain (`scripts/combat/combat_brain.gd`) [VERIFIED]

* Perception (`_perceive`, `:316-391`): hearing of recent enemy shots within 150 m;
  candidate enemies from a 64 m grid nearest first (`_candidates`, `max_candidates`=3),
  line of sight through `LineOfFire.sight` (structures, trees with foliage layers, terrain,
  unit hulls; vegetation cells warmed ahead of sight lines), `sight_range`=400 m,
  `fov_deg`=150 plus `awareness_m`=25 all round, target memory 6 s, watch the last known
  position 8 s after losing it. Contact sharing (`_share_contact`): squad mates within 120 m
  with no target turn to look at the contact (a `watch`, not a record). Under fire
  (`_under_fire`): a near miss / hit sets `threat_pos`, alerts squad mates within 30 m.
* Tactics (`_tactics`, `:745-813`): a per-soldier reaction state machine NONE → SEEK_COVER →
  IN_COVER → RETURNING, with a budgeted cover search (candidates "here", structures, rocks,
  terrain; `_cover_score` = can-fire 10/7, −0.35·distance, kind bonus; reachability by navmesh
  path when a body exists, straight-line footprint test otherwise) and bad-cover memory.
* Engagement (`_engage`): reaction time, aim error, bursts, friendly-fire check along the
  ray, tactical reload, `ai_shot_budget`=10 shots per frame, `distance_lod` halves the
  perception rate far from the observer (disabled in the sandbox so outcomes do not depend
  on the camera, `core_demo.gd:335-337`).
* Tier: both (records only). Performance: `brain_update_us_avg` ≈ 0.9–1.0 ms at 282 soldiers,
  2.7 ms at 362 with a 50 v 50 battle [VERIFIED, integration03 perf]. Profiling counters per
  phase exist (`prof`, `summary()`).
* Limitations: individual-only decisions (no squad-level fire distribution, no suppression
  model beyond "under fire → cover", no flanking, no withdrawal); contacts are not stored
  anywhere a squad or operation can read except `target_last_pos` on the observer; only
  soldiers perceive and only soldiers are targets (`_ensure_grid` indexes SOLDIER kind only,
  `:650`); no weapon/target suitability beyond one rifle. Strengths: tier-independent,
  budgeted, deterministic (`_rand` seeded from world seed + id + time), explainable
  (`ai_reason`, `cover_note`, `_event`). Extension points: `_perceive` → emit contact reports;
  `_candidates` → include vehicles with a different hit model; `_cover_score` → squad role
  terms; `order_mode(u)` is where squad tactical states will change how a soldier reacts.

#### CombatSim / LineOfFire (`scripts/combat/combat_sim.gd`, `line_of_fire.gd`) [VERIFIED]

One shot = one `request_fire` resolved once against world data (`LineOfFire.trace`), damage
applied to the record, signals for effects. `WeaponDef` resources (`assets/combat/*.tres`).
Limitation: targets are soldiers (head sphere + torso capsule, `:393`); no vehicle hull, no
armour, no area effects. Strength: tier- and camera-independent; adding a vehicle hit model is
a `_units_hit` extension, not a new system.

#### StrategicRoutes / RoadNetwork / AreaNavigation [VERIFIED]

* `StrategicRoutes`: 50 m passability/cost grid over the 20 km map (160 000 cells) in
  `AStarGrid2D`, slopes, water, bridges, roads cheap (built roads re-marked incrementally on
  `RoadNetwork.changed`), cached in `user://` with a fingerprint of the source data.
  `route()` returns straight-leg-checked waypoints; measured "a long route costs a few
  milliseconds" [DOCUMENTED] and max `war_update` spikes of 7–9 ms coincide with route
  planning [VERIFIED]. Limitation: infantry semantics (a cell is passable if a soldier can
  walk it; no road width / turning radius / vehicle class); no risk term.
* `RoadNetwork`: world roads (124 / 302 km) + built roads, `nearest()`, bridge decks,
  grading; the single road authority [VERIFIED, WORLD-PLAYTEST-01]. LOGISTICS-01 plans a
  derived `VehicleRouter` graph index over its vertices [DOCUMENTED].
* `AreaNavigation`: one 440 m navmesh (cell 0.5 m, agent radius 0.5) baked from Terrain3D,
  tree trunks and structure/vehicle obstacles, async re-centre. Not sized for the world (by
  design).

#### StructureManager / StructureCatalog / StructureDef / StructureState / ConstructionState [VERIFIED]

* Records: `StructureState` (type id, position + yaw or points + removed modules, road
  profile; `faction`), `ConstructionState` (records, clearings, JSON save). Types:
  `StructureDef` (74 types: size, collision boxes, ramps, nav blocking, walkable, line
  layout/fit, snap groups, surface roads/areas). Markers (`IP_*`, `VEH_*`, `ATT_*`,
  `SNAP_*`, `SEAT_*`, `DOOR_*`, `CARGO_*`) exist **only** in the imported GLB scenes as
  `Node3D` children plus the `fn_asset` metadata dictionary written by
  `tools/asset_lab/ap_post_import.gd` and in the JSON sidecars; `StructureDef` does not carry
  them and `StructureCatalog.mesh_of()` discards the scene after taking the first mesh
  (`structure_catalog.gd:41-58`). [VERIFIED]
* Derived per frame-budget: MultiMesh per 128 m cell, collision bodies per cell near the
  observer, navmesh obstacles, abstract blocking grid (8 m cells), pads, grass clearing,
  road grading/painting. `nav_obstacles(center, half)`, `blocks_point(p, r)`,
  `water_height`, `check_building`, `check_line`, `snap_point`, `_ids_in(rect)`.
* Limitations for AI: no notion of a *base* (which structures belong together), no facility
  semantics (what a Supply Depot does), no occupancy, no owner-faction behaviour (the
  `faction` field is stored but nothing reads it for gameplay), markers unreachable from
  gameplay code without instantiating the GLB. Strengths: everything derives from records;
  placement validation is reusable by an AI builder exactly as by the player
  (`check_building`/`check_line` + `ConstructionState.add_building/add_line`), which the
  integration self-test already does programmatically [VERIFIED,
  `scripts/debug/integration03_selftest.gd:_build/_line`].

#### SoldierBody / UnitProxy / VehicleBody [VERIFIED]

`SoldierBody`: `NavigationAgent3D` + RVO, stuck detection and unstick, possession hand-over,
viewmodel. `UnitProxy`: static far mesh. `VehicleBody` (21e846a): `StaticBody3D`, writes
position/yaw into the record, carves the navmesh (`FOOTPRINT` 2.9 × 6.1); LOGISTICS-01
turns it into an `AnimatableBody3D` presentation that *reads* the record and probes obstacles
ahead for the driving code [DOCUMENTED, read in the committed diff of 3f34dd2].

#### Time compression, persistence, tests [VERIFIED]

Fixed 1/60 s steps at k× (`TimeCompression`), measured reached speed (8.0× reached in the
integration03 perf run, CPU-bound ~10–11× with the full war [DOCUMENTED]). Save/load: one
JSON for units+squads+war (`WorldState.save_file`) and one for construction; records applied
in place. Tests: a chain of scripted self-tests driven through the real game (`--sandbox-test`,
`--playtest-test`, `--integration03-test`, …) with `--only`, screenshots, JSON results — the
natural home for the evaluation scenarios of §32.

### 2.3 LOGISTICS-01 / BASE-02 state [VERIFIED by inspection, nothing modified]

Branch `feature/logistics-01-base-02` @ 3f34dd2 (one commit: `docs/logistics01/LOGISTICS_PLAN.md`,
`tools/logistics/inspect_vehicle.gd`, re-exported vehicle GLBs without body wheels, a
`VehicleBody` rewrite). The worktree has substantial **uncommitted** work: a new
`scripts/vehicles/` directory, `scripts/debug/logistics_selftest.gd`, and modifications to
`world_sim.gd`, `world_state.gd`, `unit_state.gd`, `detail_manager.gd`, `game_controller.gd`,
`structure_manager.gd`, `rts_controller.gd`, `game_hud.gd`, `unit_proxy.gd`, `vehicle_body.gd`
(59 files, +654/−339 at the time of reading). Its plan [DOCUMENTED]:

* `UnitState.veh: VehicleState` (type, speed, steer, fuel, route + progress, status, input,
  occupants, cargo, convoy, job), `VehicleDefs` static table, `VehicleSim` owned by `WorldSim`
  (one kinematic bicycle-model step per vehicle record per tick, pure-pursuit steering,
  footprint tests against structures and vehicles, near-tier physics probe), `VehicleRouter`
  (graph index over `RoadNetwork` vertices + off-road legs from a local 2 m grid or the 50 m
  grid), `Inventory` (depot `StructureState`, vehicle cargo, faction stockpile; one
  `transfer`), `UnitState.vehicle_id` + `VehicleState.occupants` for passengers, facility
  fields on `StructureState` and `ConstructionState.bases`, `GameController.Mode.DRIVE`.
  Phases A (driving) → B (transport) → C (inventory/convoys) → D (facilities/bases).

**Assumptions this research makes about it:** the names above are the plan's; none of the
APIs are verified as implemented. Where a proposal depends on them it says so, and the
integration point is described in terms of the *record* (e.g. "a vehicle record with a route
and occupants") rather than a function name.

### 2.4 Duplications, hidden coupling, repeated work found [VERIFIED]

| Finding | Where | Severity |
|---|---|---|
| Two "who knows what" mechanisms: `WarSim.known` (faction, 400 m omniscient, 2 s) and `CombatBrain` per-soldier targets + `_share_contact` watches (LOS-based, 3 Hz). Operations read the first, soldiers the second; they can disagree (a faction "knows" a soldier its troops cannot see). | `war_sim.gd:222-258`, `combat_brain.gd:496-515` | medium — the root of most "AI feels omniscient / blind" issues |
| `WarSim` reaches into `CombatBrain` internals (`sim.brain._ensure_grid()`, `_fgrid`, `_near`) for its unit grid. | `war_sim.gd:224-225, 848` | low — fine as a shared spatial index, but it should be named as such |
| Defender estimate for unseen garrisons is a constant (`value·4`, HQ ≥ 24), not an estimate from history or reconnaissance. | `war_sim.gd:724-731` | medium (strategic quality) |
| Every squad of an operation gets its own `routes.route()` call to the same target at start and again on re-send; a 4-squad attack = 4 A* searches on the 160 k grid (7–9 ms spikes seen). | `war_sim.gd:361-379` | low now; grows with convoys |
| Structure blocking is computed three ways for three consumers: navmesh obstacles (bodies), `blocks_point` grid (abstract tier), `LineOfFire._structures_hit` (shots). All derive from the same boxes — not duplication of truth, but three caches that must be invalidated together (they are, via `area_changed` / `clearings_changed`). | `structure_manager.gd:398-425, 1746-1776`, `line_of_fire.gd:174` | low — document, keep |
| `StructureState.faction` is written, never read by gameplay. | `structure_state.gd:13` | the base-ownership hook already exists |
| `UnitState` has 25 combat/tactic fields; vehicles will add a sub-record. Fine, but the record is becoming the blackboard — which is the recommendation (§29), so name it as such. | `unit_state.gd` | none |

No conflicting-order path was found: the ownership rule (player > operation > reaction)
is enforced by construction (`release_squads`, `_cancel_reaction`, `order_mode(u) == "player"`).

---

## 3. Current AI responsibilities and data ownership (summary table)

| Decision | Owner today | Writes | Cadence | Tier |
|---|---|---|---|---|
| Which objective to attack / defend / reinforce, with how many | `WarSim._decide` + `FactionProfile` | `OperationState`, squad routes, log | 25–30 s per AI faction | both |
| Operation phase, re-send, garrison, end | `WarSim._update_operation` | `OperationState`, `SquadState.op_id/route/station` | 1 s | both |
| Where reinforcements appear | `WarSim._update_reserves` | new units/squads | 5 s check, 240 s interval | both |
| What a faction knows about enemies | `WarSim._update_intel` | `WarSim.known` (runtime only, **not saved**) | 2 s | both |
| Long-distance path | `StrategicRoutes.route` | returns waypoints | on demand | both |
| Squad movement, formation, route following, status | `SquadControl` | `SquadState`, `UnitState.order` | 0.5 s | both |
| Per-soldier perception, target, fire | `CombatBrain` | `UnitState` combat fields, `request_fire` | 3 Hz perception, per-frame engagement | both |
| Per-soldier cover reaction | `CombatBrain._tactics` | `UnitState.tactic/react_*` | 3 Hz | both |
| Local path, avoidance, stuck recovery | `SoldierBody` | `UnitState` position/velocity/move_state | 60 Hz | detailed |
| Abstract movement, structure sliding | `WorldSim._abstract_step` | `UnitState` position | 60 Hz | abstract |
| Which tier a unit is in | `DetailManager` | nodes only | 60 Hz | — |
| Structures: placement, geometry, nav, blocking | `StructureManager` on `ConstructionState` | caches | event / budget | both |
| Player override | `RTSController`, `WorldState.issue_*`, `GameController.possess` | records | input | both |

Not owned by anyone today: contacts as records; squad tactics; force composition;
transport; supply; facility use; bases; airspace. [VERIFIED by absence]

---

## 4. Existing strengths and limitations (for the architecture decision)

**Strengths to build on** [VERIFIED]: one record per entity in both tiers; ownership by
construction; low-frequency, budgeted, staggered AI (3 Hz perception, 1 s operations, 25–30 s
strategy, 24 LOS checks / 10 shots / 16 cover evaluations per frame); deterministic randomness;
data-driven personalities and content; explanation strings on records (`ai_reason`,
`cover_note`, `last_decision`, operation `outcome`); a scripted-scenario test culture; the
asset pipeline already emits interaction markers.

**Limitations that shape the proposals** [VERIFIED]: no shared contact memory; no squad
tactical vocabulary; infantry-only everything (grid semantics, hit model, perception,
operations); bases are geometry; no composition / capability notion; the strategic scorer
considers one action type per step; `known` is not saved (after a load the AI forgets what it
knew — a real behavioural discontinuity); markers unreachable at runtime without scene
instancing.

---

## 5. Strategic faction AI research

### 5.1 What exists [VERIFIED]

`WarSim._decide` is a **rule-ordered utility scorer**: fixed priority of concerns (recover →
threats → garrisons → one attack → forward deployment), with utility only inside the attack
choice. This is the structure most published campaign AIs share: Total War's campaign AI is a
layered system where the Grand Tactical Analyser decides attack/defend and lower layers
decompose [RESEARCHED, Total War AI series on gamedeveloper.com; Cakmak & Davidson ACCU 2018
on evaluating under limited memory/time]; Bannerlord's lords weigh distance, power, garrison,
nearby parties and fief value per candidate action [RESEARCHED, TaleWorlds blog 68]. Dave
Mark's Infinite Axis Utility System formalises "score every candidate action by a product of
response curves over considerations" [RESEARCHED, gameai.com IAUS; GDC 2013/2015].

### 5.2 Assessment against the brief's topics

| Topic | Today | Gap | Proposal (all [PROPOSED]) |
|---|---|---|---|
| Objective selection | utility over value/distance/retake | one action type per decision; candidate set = objectives only | score **actions** (attack X, reinforce Y, establish FOB at Z, escort convoy W, recon R) in one list; pick top-k within force budget |
| Roads / bridges priority | bridges are objectives of kind `bridge` | road segments and supply lines have no value | derive **supply-line value** from `StrategicRoutes` paths HQ→held objectives: cells on the path of ≥2 routes get a value; bridges on them inherit it (data on `ObjectiveState`/a new `RouteValue` table, recomputed when ownership changes) |
| Base establishment | none | no base concept | an action "establish FOB at candidate site" scored by distance-to-front, road access (`RoadNetwork.nearest`), site suitability (`StructureManager.check_building` grid sample), supply distance; executed by the AI builder (§17) |
| Defensive planning | garrison counts per value | no terrain / influence input | garrison size from the threat layer (§21) rather than a constant |
| Resource allocation / reserves | reserves spawn at HQ, `attack_commit` share | no supply, no transport allocation | once LOGISTICS-01's `Inventory` exists: reserves become *stock* (ammo, fuel) + *replacements*, and an attack's need includes transport capacity |
| Multiple fronts | `max_attacks` and per-threat reinforcement | threats handled first-come | score threats by (objective value × enemy strength estimate × confidence) and allocate from the free pool in score order — already the shape of step 1, needs the estimate |
| Response to offensives | reinforce when `known_near > 0` | binary | a contact estimate with strength/confidence (§20) |
| Threat assessment | `known_near` counts | omniscient 400 m | contact records with decay (§20) + influence (§21) |
| Recovery after defeats | `recovery_s` timer | — | keep; add "regroup at nearest held objective" as the FAILED exit instead of releasing squads where they stand (today `_end` leaves squads in place) |
| Long-term goals | none (greedy) | — | a persisted `FactionState.focus` (objective id or region) that biases scoring for several decisions; cheap, explainable, enough for believable "campaigns" |

### 5.3 Technique comparison for the strategic level

* **Utility scoring (extend what exists)** — fits: candidate actions are few (tens), decisions
  are every 25–30 s, explanations are natural ("attack Sentrum 7.2: value 3, distance 2.1 km,
  retake"). Risk: oscillation between two similar scores → keep hysteresis (bonus for the
  current focus, cooldowns as `recovery_s` already does).
* **Hierarchical planning (HTN) at the strategic level** — fits the operational decomposition
  better than the strategic choice; see §6. Not needed here.
* **Goal-based (GOAP) search over world state** — strategic state space (objectives × forces ×
  supply) and the cost of simulating outcomes make search expensive and opaque; MCTS as in Rome
  II [RESEARCHED] is a large investment with little gameplay return in a three-faction sandbox.
* **Influence-informed scoring** — the practical complement: most of the missing inputs
  (threat, control, route risk) are spatial fields; §21.

**Recommendation:** EXTEND `WarSim._decide` into an action-list utility scorer with
contact-based estimates and influence terms; keep `FactionProfile` as the weight table; add
`FactionState.focus`. No rewrite.

---

## 6. Operational military AI research

### 6.1 What exists [VERIFIED]

`OperationState` + `_update_operation`: one route per squad to one target, phases driven by
observation, four types. Operations are the right unit of command: they own squads
(`op_id`), release on player order, survive save/load, show on the map.

### 6.2 Needs from the brief vs. the record

Mission decomposition, composition, capability matching, staging/assembly, transport,
supply preparation, synchronisation, monitoring, replanning, withdrawal: none exist. The
question is what representation to add.

### 6.3 Comparison

| Approach | Fit for operations here | Notes |
|---|---|---|
| **HTN** (Killzone 2 bots, SHOP-style; Guerrilla's Decima planner) [RESEARCHED] | Conceptually ideal: "capture objective" decomposes into assemble → mount → move → dismount → assault → hold. But a planner *engine* (methods, preconditions, backtracking) is a new framework with its own debugging; Guerrilla built it for per-bot plans replanned every few hundred ms, a different scale. | Take the **decomposition idea**, not the engine: author the decompositions by operation type as data (an ordered task list with preconditions), executed by the existing 1 s updater. |
| **GOAP** (F.E.A.R.) [RESEARCHED] | Searches action chains to satisfy a goal — good when actions are many and combinable per agent; operations have few actions and strong ordering. Search cost and opacity not justified. | Avoid. |
| **Utility** | Good for *choosing* an operation (§5), poor for *sequencing* it. | Use at the strategic level only. |
| **Hierarchical state machine** | What `_update_operation` already is. Adding a plan list (task index + per-task state) is an HSM with data-driven states. | **Extend.** |
| **Behaviour trees** | Natural for sequencing with fallbacks; but a BT runtime for ~10 operations ticking at 1 Hz is overhead for little, and BT state is awkward to persist mid-tree. | Avoid as a runtime; the plan list gives the same sequence/fallback semantics with trivially saved state. |
| **Hybrid: utility → plan list → squad state machines → reactions** | The layered pattern of Killzone (strategy → squads → individuals) and Total War (GTA → tactics → units) [RESEARCHED]. | **Recommended.** |

### 6.4 Proposed operational model [PROPOSED]

* `OperationState.plan: Array[Task]` where a Task is a small dictionary `{kind, args, state,
  since}` with kinds drawn from a fixed set: `assemble(at)`, `mount(vehicle_ids)`,
  `move(route_to, formation)`, `dismount(at)`, `assault(objective)`, `hold(objective,
  quiet_s)`, `escort(convoy_op)`, `recon(area)`, `withdraw(to)`, `return(base)`, `resupply(base)`.
  `plan_i` is the current task. Authoring is per operation type, as data (a `.tres` or a
  table in `WarSim`), parameterised by what the force has (a plan for a mechanized attack
  includes mount/dismount; a foot attack does not).
* `OperationState.elements: Array[Element]` — role-tagged groups of squads/vehicles
  (`assault`, `support`, `transport`, `escort`, `reserve`) so one operation commands several
  echelons with different tasks (today every squad does the same thing). Elements may have
  their own current task (a support element `hold`s a firing position while the assault
  element `assault`s).
* `_update_operation` advances tasks: a task completes on an observable condition (squads at
  the assembly point; all mounted; route finished; dismounted; objective owned; quiet period),
  fails on its own condition (losses, timeout, transport lost), and failure handlers are part
  of the plan (`on_fail: withdraw`). Replanning = regenerate the plan from the current task
  with current resources; cancellation = `withdraw/return` tasks appended, which also gives
  orderly retreats instead of leaving squads where the operation died.
* Requirements and composition: an operation type declares needs in capabilities (§24):
  `{infantry: n, transport_seats: n, direct_fire: k, recon: 1}`; `_decide` fills them from
  free units by capability, location and readiness. This is where "a supply truck does not get
  sent to assault" is enforced — by data, once.
* Synchronisation: tasks can be gated on another element's task (`after: support.hold`), a
  rendezvous is just an `assemble(at)` shared by elements. Timing by condition, not by clock.
* Monitoring and interruption: the player can still take any squad (`release_squads`);
  an element losing its last squad triggers the task's failure handler.
* Save/load: the plan is plain data on `OperationState.to_dict` — this is the main reason
  to prefer a data plan over a planner runtime.

Dependencies: capability tags (§24), contact record (§20) for assault/hold conditions, and
LOGISTICS-01's transport records for `mount/dismount` (the task kinds can exist before; they
simply do not appear in plans until vehicles do).

---

## 7. Tactical infantry AI research

### 7.1 What exists [VERIFIED]

Individual: perception, acquisition, bursts, reload, friendly-fire check, hearing, watch
directions, cover search and reaction with memory of bad cover, return to anchor. Squad:
formations, routes, follow, regroup, ROE, status. Coordination: squad alert on being fired
upon (30 m), contact look-sharing (120 m). Measured: 50 v 50 battles resolve in minutes with
plausible casualties [DOCUMENTED, COMBAT-02 / SANDBOX reports].

### 7.2 Missing vs. tuning

| Behaviour | State | Verdict |
|---|---|---|
| Cover selection, terrain use | exists, scored | tuning only (weights, candidate radius by order mode) |
| Suppression | missing: hits are the only effect of fire; "under fire" only triggers cover seeking | **missing mechanic** — a per-unit `suppression` value raised by near misses, decaying, reducing aim/perception and biasing toward cover; cheap (near-miss detection already exists in `_on_shot`) |
| Fire and movement / bounding | missing | **missing squad behaviour** — needs fire teams |
| Flanking | missing | missing; needs contact record + squad tactic + threat-aware target point |
| Formation adaptation | LINE/COLUMN, column on march | add WEDGE/ECHELON and automatic spacing by contact (cheap) |
| Squad cohesion | slots + regroup + follow | exists |
| Coordinated advances between squads | operations send all squads the same route | needs elements (§6) and "bound" at squad level |
| Defensive positioning | garrison = stand at `_slot_in` | missing: occupy cover facing the threat axis — reuse `_cover_candidates` at squad scale |
| Ambush reaction, withdrawal, regroup | reaction = cover; withdrawal none | add squad tactic `WITHDRAW(to)` (route back, column, no stops) and an operation `withdraw` task |
| Casualty response | fallen list; depleted squads go home at the strategic level | leader re-election exists (`set_leader`); fine |
| Ammunition awareness | tactical reload, `reserve` persisted | add "low ammo" into squad status → operation `resupply` trigger (needs logistics) |
| Threat prioritisation | nearest-first, switch when 0.6× closer | add weapon/target suitability when vehicles exist (§23) |
| Coordination with vehicles / helicopters | none | via operation elements and support requests (§11) |

### 7.3 Decision ownership [PROPOSED]

* **Soldier**: look, shoot, reload, take cover, follow the slot. Never plans beyond ~20 m.
* **Fire team** (new, 2 per 8-man squad = `members` split by index, no new record — a
  `SquadState.teams: Array[PackedInt32Array]` field): a bound target and a stance
  (moving / firing). Slots per team.
* **Squad** (`SquadControl` tactical state on `SquadState`): `tactic ∈ {NONE, BOUND,
  SUPPRESS, FLANK, WITHDRAW, DEFEND}` with a target contact and a timer; computes team targets
  from contact + cover candidates; re-evaluates every 2–3 s; falls back to NONE when the
  contact is lost or the operation task changes.
* **Operation**: which squads do what (elements), where the objective is, when to withdraw.
* **Strategic**: whether to fight at all.

### 7.4 The forest encounter (worked example) [PROPOSED, all primitives exist unless noted]

1. *Detect*: `CombatBrain._perceive` acquires a target (exists).
2. *Share*: `_acquire` also writes a **contact record** to the faction's contact table
   (§20); squad mates read "contacts near me" instead of the 120 m watch broadcast.
3. *Evaluate cover*: `SquadControl` asks `_cover_candidates`-style evaluation for the squad's
   current area against the contact position (reuse the budgeted search with a squad-level
   request).
4. *Firing position*: squad tactic SUPPRESS: team A slots = best cover spots with `can_fire`;
   ROE free; soldiers' own reactions still run under them (they already prefer `react_target`).
5. *Suppress*: team A fires at the contact's last known position even without LOS (new: a
   `suppress_at` target in `_engage` — a burst at a point is already how `request_fire`
   works; the suppression value lands on enemies near the impact line via `_on_shot`).
6. *Flank*: team B gets a route (`StrategicRoutes` or local straight legs) to a point offset
   90° from the contact axis at ~60–100 m, formation column, then BOUND to the contact.
7. *Casualties*: squad status counts fallen; below `min_squad_size`-like threshold the tactic
   becomes WITHDRAW toward the operation's staging point.
8. *Withdraw*: route back, suppression team breaks contact last. Operation task `on_fail`.

All of this is squad-level state advanced in `SquadControl.update` at 0.5 s with the
existing slot mechanism; no per-soldier planning.

---

## 8. Ground vehicle AI research

### 8.1 What exists and what LOGISTICS-01 plans

Vehicles: a record kind, a static body, carved obstacles [VERIFIED]. LOGISTICS-01
[DOCUMENTED]: kinematic bicycle model, pure pursuit (Coulter 1992 [RESEARCHED]) with a
speed profile from curvature and braking look-ahead, a road graph index over `RoadNetwork`
vertices, off-road legs from a local obstacle grid or the 50 m grid, footprint tests against
structures and other vehicles, near-tier physics probe for trees/soldiers, stuck recovery,
fuel. This matches current industry practice: Arma Reforger builds a road network graph from
the map's roads for vehicle pathfinding, with per-vehicle pathfinding flags [RESEARCHED,
Bohemia modding update June 2024]; Arma 3's long history of convoy failures (intersections,
bridges, formation drift, off-road vehicles steering back to roads) [RESEARCHED, BI forums and
dev blog] is a catalogue of what the router and follower must handle explicitly.

### 8.2 Navigation recommendations [PROPOSED] — complementing, not replacing, the plan

* **Vehicle classes on the road graph**: the graph edge carries width class and grade from
  `RoadNetwork` (the audit already computes widths per class and grades); a truck is refused
  a track below its width, a tank accepts steeper grades. Bridges: the deck span is an edge
  with a load class (data on `roads.json` bridge spans; a later property).
* **Intersections**: the Arma 3 failure case "the road continues through an intersection"
  is a graph-link problem; the plan's "link vertices of different roads within 8 m" is the
  right fix; recommend a junction node with explicit turn edges so convoys do not stall when
  the pure-pursuit look-ahead jumps roads.
* **Off-road traversability**: reuse `StrategicRoutes` slope classes but with per-class
  `max_slope` (grid cost arrays are per-cell; a second small cost table per class is a few
  hundred KB). Do not build a vehicle navmesh.
* **Convoy spacing / formation**: a convoy is an operation element with a lead vehicle and
  followers that target "the lead's path, N metres behind along the polyline" (path-following
  follow, not position follow — avoids the Arma formation-drift problem). Speed = min over
  members. Intersections: followers hold at the junction node until the leader clears it.
* **Reversing, recovery, parking**: three-point turns are rare on roads; in yards, reversing
  into a `VEH_*` marker is a short scripted manoeuvre (drive to approach point, reverse along
  a straight to the marker). Recovery: if stuck > T, reverse 5 m along the recorded path,
  replan; after 3 failures the vehicle reports BLOCKED with a reason (player feedback, §15).
* **Abstract tier**: a vehicle without a body still integrates the same bicycle step on the
  record (plan) — the correct choice; at 16× that is O(vehicles) per tick with no physics.
  Consistency: because the router is the same, the abstract vehicle cannot "teleport across a
  river" — it follows the same polyline.

### 8.3 Tactical vehicle behaviour [PROPOSED]

Vehicles get a `CombatBrain` entry when they have a weapon (APC/IFV/tank): same
perception loop (eye at the commander's hatch height, `WEAPON_*` marker for the muzzle),
different hit model (hull box + turret, from the asset bounds), different target suitability
(§23). Behaviour by role, data in `VehicleDefs`:

| Role | Behaviour in an operation |
|---|---|
| Logistics truck | no combat brain; `withdraw` on contact within R; cargo jobs |
| APC | transport element: mount → move → dismount at the dismount point short of contact, then support position 100–200 m behind infantry with LOS (reuse `_cover_candidates` with vehicle-sized candidates: a hull-down check is simply "the candidate spot has a terrain crest between it and the contact at hull height but not at turret height" — two `LineOfFire.clear_line` calls at two heights) |
| IFV / tank | support/assault element: engagement ranges from `WeaponDef`, target priority armour > soft; keeps `standoff` distance; retreats when `health` or ammo below thresholds (role rule) |
| Recon vehicle | `recon(area)` tasks: drive to vantage cells (high ground from the terrain, LOS to the area), report contacts, avoid engagement |

Return-to-base / repair / refuel: triggered by thresholds in the vehicle record, executed as
an operation task `return(base)` + facility requests (§13). No separate vehicle AI layer: the
vehicle is an element member with a role.

---

## 9. Helicopter flight and mission AI research

### 9.1 Flight model choice [PROPOSED, RESEARCHED]

The research literature converges on a layered autopilot: an outer loop producing setpoints
(heading, altitude / height above ground, speed, vertical velocity) from waypoints and a
terrain-following module, and an inner loop that realises them [RESEARCHED: layered PID
autopilots for mini-UAVs; terrain-following as a vertical-velocity command; cascaded height
control]. For a game with no aerodynamic requirement, the inner loop can be **kinematic**:

* State on the record: position, heading, velocity vector, `agl` (height above ground),
  `attitude` (pitch/bank for presentation only). Per tick: accelerate toward the commanded
  velocity with limits (max speed, max accel, max climb/descent rate, max turn rate as a
  function of speed), bank derived from lateral acceleration, pitch from longitudinal.
* Outer loop: **pure pursuit in 3D** on a route of waypoints with a speed-scaled look-ahead;
  altitude command = max(route altitude, terrain profile under the look-ahead + clearance);
  the terrain profile comes from sampling `Terrain3D` heights along the next ~1–2 km at the
  flight direction, plus a **coarse obstacle height layer** (tree canopy height from
  vegetation chunks, structure heights from `StructureDef.size`, masts) at the 50 m grid.
* Hover and landing: a separate mode with position hold (critically damped spring to the
  pad point, deadband) and a descent rate schedule; landing requires the pad test (§16).
* Physics-based (RigidBody with lift/torque) is not needed and hurts determinism under time
  compression and tier transitions. Hybrid = kinematic authority + visual-only sway.

Preventing the named failures:

| Failure | Measure |
|---|---|
| Oscillation | look-ahead ≥ 2 × turn radius at current speed; critically damped altitude loop with rate limit; no integral term except in hover |
| Endless circling | waypoints reached by *passing a plane perpendicular to the leg*, not by radius; unreachable (too tight) waypoints are rejected at route time by minimum-radius smoothing of the polyline |
| Unstable hover | position deadband, decreasing gains with altitude error, wind not modelled |
| Unsafe descents | descent rate limited by `agl` (slower under 30 m), approach only along a corridor that is clear in the obstacle layer |
| Terrain collisions | the clearance profile is a hard floor on commanded altitude; a sample ahead above the floor triggers an immediate climb command regardless of route (reflex) |
| Landing on unsuitable terrain | pad test: slope, clearance radius, no water, no structure, from `StructureManager.check_building`-style sampling |
| Tier transition artefacts | the record holds the full kinematic state in both tiers; the abstract tier integrates the same controller at the same tick, only the body/visual is absent (same approach as the vehicles) — no "snap" possible |
| CPU | O(aircraft) per tick; terrain samples per aircraft per tick ≈ 8–16 height lookups; obstacle layer lookups O(1) |

Under time compression: same fixed step; flight at 16× is 16 steps per frame, trivially cheap
for a handful of aircraft.

### 9.2 Routing in 3D [PROPOSED]

No 3D navigation volume. Routes are 2D polylines from `StrategicRoutes` with a different cost
table (water passable, slopes passable, **known air-defence threat cells** expensive — §21)
plus an altitude profile derived at route time: cruise altitude = max(terrain + clearance over
a corridor width) per leg, with a "nap-of-the-earth" option that lowers the clearance and
raises the cost of ridge crossings. Ridges are crossed at the lowest sampled point of the leg
corridor (one pass over the terrain samples).

### 9.3 Mission behaviours [PROPOSED]

Operation elements of role `air_transport`, `air_attack`, `air_utility` with tasks:

* Transport: `takeoff` → `move(pickup_pad)` → `land` → `mount(squad)` → `takeoff` → `move(LZ)`
  → `land` → `dismount` → `takeoff` → `return(base)`. Extraction is the mirror. LZ selection:
  score candidate cells near the objective by pad test + distance to the objective + threat
  layer + approach corridor clearness; the same scoring as AI base-site selection with other
  weights. Emergency diversion: when the LZ's threat rises above a threshold while en route,
  re-select.
* Attack: `armed_recon(area)` (orbit at standoff with LOS sampling, report contacts),
  `cas(target_contact)` (attack runs: approach along a corridor that keeps terrain between the
  aircraft and known AD threats, engage within `WeaponDef` range, break off below ammo or
  above damage thresholds), `escort(element)` (station relative to the escorted element's
  centroid, re-task to `cas` on contact).
* Utility: cargo tasks = transport tasks with `CARGO_*` instead of seats.

The operational AI assigns these by capability (§24); the flight controller executes. No
aircraft-specific strategic AI.

---

## 10. Future aircraft and UAV compatibility [PROPOSED]

Requirements that cost nothing now and prevent a redesign later:

* `UnitState.kind` gains `AIRCRAFT` (as `VEHICLE` was added) with a sub-record like `veh`
  (`air`): the *same* record pattern. Domain (`ground`, `air`) is a capability tag, not a class.
* The flight controller is parameterised by a `FlightDef` (hover-capable or not, min speed,
  turn radius, climb rate, runway needed). Fixed-wing = `min_speed > 0` and `runway` facility
  capability for take-off/landing; UAV = long endurance, sensor capability, no seats.
* Airspace: a per-base pad/runway reservation (§13) and an altitude-band convention
  (transport cruise, attack, UAV loiter) in the route cost table are enough for separation
  at this scale; no ATC simulation.
* Sensors: a `sensor` capability with range and a "detection mode" (visual / thermal) feeds
  the same contact record (§20) with confidence by mode.
* Fuel / ammo / readiness: already planned fields (`fuel` on `VehicleState`); readiness is a
  facility question (§18).

Nothing of this needs code now beyond keeping `kind` and the capability tags open-ended.

---

## 11. Combined-arms coordination [PROPOSED]

The mechanism is §6's operation plan with elements and roles, plus three conventions:

* **Shared objective, per-element tasks**: infantry `assault`, APCs `support(behind,
  200 m)`, tanks `overwatch(firing_position)`, attack helicopter `cas(contact)`, transports
  `return(base)` after `dismount`. All reference the same `target_objective` and the same
  contact table, so target information is shared by construction.
* **Rendezvous and staging**: `assemble(at)` tasks gate `move`; the assembly point is the
  operation's `staging_pos` (exists) chosen with the threat layer. Transport allocation: the
  `transport` element's seats must cover the assault element's members (capability match in
  `_decide`), else the plan degrades to a foot march (plan authoring handles the fallback).
* **Support requests**: a squad tactic that cannot resolve a contact (SUPPRESS for > T with
  no progress, or an armoured contact) sets `SquadState.request = {kind: "fire_support",
  contact_id}`; the operation updater matches it to an element with the capability
  (`direct_fire` vehicle, `cas` aircraft) within range and retasks it; if none, escalates to
  `_decide` (a "reinforce op" candidate action). Player visibility: requests appear on the
  map like events; the player can answer them personally.
* **Replanning on loss of a supporting unit**: element empty → its task fails → the plan's
  failure handler (continue without support / withdraw) runs. Deterministic and explainable.

Cross-domain movement (ground route vs air route) is handled by each element's domain; the
`assemble`/`rendezvous` task is domain-agnostic (a point and a radius).

The player retains authority: `release_squads` on any direct order (exists); for vehicles and
aircraft the same release on `possess` / drive / fly. An operation that loses its assault
element to the player continues with what it has or withdraws — never fights the player's
orders.

---

## 12. Military bases as functional AI environments

### 12.1 Verified basis

Bases are sets of `StructureState` records with a `faction`; nothing groups them, nothing
gives them capabilities [VERIFIED]. LOGISTICS-01 plans `ConstructionState.bases` and facility
fields on `StructureState` [DOCUMENTED]. Markers exist in the GLB scenes and the JSON sidecars
[VERIFIED] but not in `StructureDef`.

### 12.2 Principle: capabilities derive from structures [PROPOSED]

* A **base** is a persisted record in `ConstructionState` (the plan's `bases`): id, faction,
  centre, radius, member structure ids (explicit membership set at placement time by
  proximity to a base centre or by the player's choice; the AI builder sets it). Freely placed
  structures far from any base are not in one. No tiers, templates, grids or road requirements.
* A base's **capabilities** are the sum of its members' `StructureDef.capabilities` (new data
  field, §13) weighted by facility state (destroyed, occupied, stocked): "this base can
  stage 3 squads, park 6 vehicles, land 1 helicopter, refuel, store 2 000 units of ammo".
  Computed on change (structure added/removed, inventory changed), cached on the base record,
  never per frame.
* The AI reads base capabilities the way it reads objectives today; a base with an HQ is also
  an objective (kind `hq`/`base`) for capture purposes, which the war already handles.

---

## 13. Facility interaction and reservations architecture [PROPOSED]

### 13.1 Metadata: what is needed on top of what exists

`StructureDef` (data, `.tres`) gains:

| Field | Source | Use |
|---|---|---|
| `capabilities: Array[StringName]` e.g. `[&"infantry_staging", &"vehicle_parking", &"refuel", &"ammo_storage", &"repair", &"helipad", &"recruit", &"cargo_handling", &"command"]` | authored per type in `make_prop_defs.py` / the pipeline's structure block | base capability sums; mission requirements |
| `service_points: Array[ServicePoint]` = `{name, local_pos, local_yaw, kind (IP/VEH/PAD/DOOR/CARGO), capacity, size}` | **copied from the sidecar markers by the def writers** (the sidecars already have `markers[].name/pos/yaw`), so no runtime GLB instancing | docking, parking, loading, boarding, landing |
| `capacity: Dictionary` (seats for barracks, slots for parking, stock caps for depots) | authored | capacity limits |

This is the "new asset becomes AI-compatible by following the marker conventions" requirement:
the pipeline already writes markers; the def writer copies them; the AI consumes
`service_points` generically by `kind`. Buildings without markers still work (capabilities
only, service point = footprint edge nearest the road).

### 13.2 Reservations [PROPOSED] — one narrow component

Where: a `FacilityTable` object held by `ConstructionState` (saved with it; not a node; no
per-frame loop). Entries: `{structure_id, point_name, holder_unit_id, kind, since, until}`.
API shape: `request(unit, capability, near, radius) → reservation or null`,
`release(reservation)`, `holders(structure_id)`, `free_points(structure_id, kind)`. Lookup is
over the base's member structures (tens), not the world's; a unit asks when it needs a
service (an operation task), not per frame.

Workflow (the brief's 8 steps) mapped to tasks: `request` → `move(point)` (ground router /
flight controller) → arrive → `wait` if the point became occupied in between (re-request with
the next free point, else queue entry with a timeout) → `interact` (timer + inventory
transfer / board / refuel) → `release` → next task. Timeouts: reservations expire at `until`
(task-kind default) so a destroyed or stuck unit frees the point; cancellation on operation
end releases everything held by its units; priority = operation priority (player > AI
attack > ambient); deadlocks avoided by never holding two reservations at once per unit and
by the timeout; unreachable facility = router failure → task fails with reason, base marks the
point `unreachable` for N minutes (feedback to the player: "fuel point unreachable: blocked
entrance"); destruction = structure removed → table entries dropped, holders' tasks fail;
abstract tier: identical (timers and records); save/load: part of `construction.json`.

Why not an existing system: `StructureManager` is geometry and caches; `WarSim` is faction
decisions; `ConstructionState` is the right owner because the table is *construction state*
(what is where and who uses it) and is saved with it.

---

## 14. Infantry behaviour inside bases [PROPOSED]

Operational (needed) vs ambient (optional):

| Operational | Mechanism |
|---|---|
| Recruitment / spawning | `_update_reserves` spawns at a `recruit`-capable structure's `IP_*` point instead of a fixed offset from the HQ objective; barracks capacity caps resident squads |
| Barracks assignment / squad assembly | a squad's `station_objective` becomes `station_base`; idle squads at a base `hold` at staging points (`infantry_staging` service points, or the yard) |
| Guard duty / defensive positions | base defence tasks (§18): squads `DEFEND` with slots on defensive structures' `IP_*` points (fighting positions, towers, bunkers) facing the threat axis |
| Patrols | an ambient-but-useful `patrol(ring)` operation type: a route around the perimeter at walking speed; contacts feed the contact table (bases detect approaches) |
| Boarding | `mount` tasks at `VEH_*`/`DOOR_*` points (LOGISTICS-01 phase B) |
| Ammunition | `resupply` task at an `ammo_storage` point → `UnitState.reserve` from inventory |
| Preparing / returning / reorganising | plan tasks `assemble`, `return`, `resupply`; depleted squads merge (`WorldState` squad operations exist) |
| Casualty handling | out of scope for gameplay value; record only |

Ambient (visual only, near tier only, no records): idle animations at staging points,
walking between points when the detail tier is active. Not simulated in the abstract tier.

---

## 15. Ground vehicle base operations [PROPOSED]

* **Entering**: gates are `fence_gate`-like defs with `blocks_navigation = false`; the vehicle
  router treats a base perimeter as impassable except at structures with capability
  `vehicle_gate` (data); the entrance point is the gate's service point.
* **Internal movement**: player-built roads and yards are already in `RoadNetwork` /
  surfaces; inside a base the router uses the local 2 m obstacle grid LOGISTICS-01 plans (yards
  and roads cheap, grass allowed, structures blocked) — no separate base traffic system.
* **Parking / service**: reservations (§13) on `VEH_*` points; approach = router to the
  point's approach position, final = scripted reverse/forward along a straight.
* **Accessibility evaluation**: when a base's layout changes, run a **reachability check**
  once (flood fill on the local grid from each gate with the largest vehicle footprint) and
  mark service points `unreachable`; surface that to the player in the construction UI
  ("Vehicle Depot: no vehicle access from a gate"). This is the single most valuable
  anti-frustration feature for freely built bases and is cheap (one flood fill per change).
* **Collisions, waiting, blocked entrances**: vehicle–vehicle footprint tests exist in the
  plan; a blocked vehicle waits up to T then re-requests; a gate blocked by a stuck vehicle
  for > T triggers the stuck recovery of that vehicle (reverse + replan).

---

## 16. Helicopter base operations [PROPOSED]

* **Landing areas: hybrid.** A placeable helipad asset/def with capability `helipad` is the
  preferred, reservable, lit, deconflicted option; **any clear flat ground** passes an
  automatic pad test (slope ≤ 5°, clearance radius 20 m free of structures/trees/units
  from the obstacle layer, not water, not a road) for LZs and emergencies. Bases without a
  pad can still receive helicopters on a yard (yards pass the test by construction).
* Approach corridors: the pad's approach heading is chosen at reservation time as the
  direction with the lowest obstacle profile in the obstacle layer within 500 m, stored on
  the reservation; multiple helicopters queue on the pad reservation and hold at a holding
  point 300 m out at separate altitudes (band = queue index × 30 m).
* Rotor/ground clearance: pad test radius from the `FlightDef`; buildings near a pad lower
  its score, trees inside the radius fail it.
* Refuel / rearm / repair / boarding: reservations on the pad; the service happens at the
  pad (no taxiing); `SEAT_*`/`CARGO_*` for boarding positions.
* Threats: a pad within the threat layer above a threshold is unavailable for landing; a
  helicopter on the ground under threat `takeoff`s and diverts to the nearest safe pad (an
  operation task on the base defence plan).

---

## 17. AI base construction and expansion [PROPOSED]

Comparison: rule-based (simple, rigid), templates (fast, repetitive, fail on terrain),
constraint-based placement (correct, can be slow), procedural layout (over-engineering),
hybrid. StarCraft-style optimisers (GA + combat simulation, ASP wall-ins) [RESEARCHED] solve
a different problem (chokepoint walls on fixed maps) at a cost this game does not need.

**Recommended incremental hybrid:**

1. **Site**: score candidate cells (the 50 m grid) by: distance to the front/objective,
   road access (`RoadNetwork.nearest` ≤ 300 m), flat buildable fraction (sample
   `check_building` for the largest intended footprint on a coarse lattice — the integration
   self-test's site search does exactly this and found sites in < 1 s [VERIFIED]), water
   absence, threat layer, supply distance (route length to the nearest friendly depot).
2. **Layout**: a small set of **relative templates** per base role (outpost, FOB, main base)
   expressed as *desired structures with preferred relative positions and tolerances*, placed
   one by one with `check_building`; on failure, search a spiral of alternatives within the
   tolerance; perimeter lines from `check_line` with a gate on the road side; yards last.
   Roads: one access road from the gate to `RoadNetwork.nearest` via the existing road tool
   logic (it refuses bad junctions; try the next junction point as the test does).
3. **Validation before commit**: the §15 reachability check from the gate to every vehicle
   service point and a soldier reachability check (abstract blocking grid flood fill); if a
   service point is unreachable, remove the offending structure and retry once, else drop
   that structure. This guarantees no AI base with blocked gates or unusable depots.
4. **Expansion**: later decisions add structures by the same method when capabilities are
   short (e.g. "needs parking for 4 more vehicles").

Cost: dozens of `check_building` calls and one flood fill per placement decision; run inside
a strategic decision (25–30 s), optionally spread over frames. Executed through
`ConstructionState.add_*` exactly like the player, so saves, grading, clearing and navigation
are identical [VERIFIED mechanism].

---

## 18. Base defence [PROPOSED]

A **base is an operation target**, and defence is an operation type (`DEFEND_BASE`) with a
plan: `occupy(defensive_points)` for infantry elements (slots = `IP_*` points of fighting
positions, towers, bunkers, facing the threat axis from the contact table), `reinforce_gate`
for APC elements, `overwatch` for tanks, `takeoff + divert` for helicopters,
`withdraw(inner yard)` for logistics vehicles, `request(reinforce)` escalation to `_decide`,
`return + repair` for damaged units via facility requests, inventory jobs re-prioritised by
the base's threat flag. The trigger is the contact table: contacts within the base radius +
margin with confidence above a threshold. The standing garrison (today `station_objective`)
is the default element.

Is a base-level defence coordinator needed? **No new AI level.** The operation updater *is*
the coordinator: one operation per threatened base, elements by capability, tasks as above.
This keeps the ownership rule (operation > reactions) and avoids a fourth order source.
`CombatBrain` and `SquadControl` behave as in any operation.

---

## 19. Base operational readiness [PROPOSED]

Readiness is a **query over records**, computed on change and cached on the base record:
available infantry (squads with `station_base`, not in an operation, ≥ min size), vehicles by
capability and status (parked, fuelled, undamaged), aircraft (on a pad, fuelled, armed),
stock (inventory per kind), capacities (parking/landing/loading free points from the
`FacilityTable`), repair/transport capability, assigned operations, threat (contact table),
last resupply time. The questions in the brief are then direct comparisons ("can we launch a
transport mission" = a fuelled transport helicopter on a free pad + a squad at staging +
pad reservation available). No duplicate inventory; the only new stored data is the cached
summary with its version stamp.

---

## 20. Perception, reconnaissance and intelligence [PROPOSED]

### 20.1 The contact record

A per-faction table in `WarState` (saved): `contacts[faction][enemy_unit_id] = Contact
{pos, vel, t_seen, t_reported, kind, strength_class, confidence, source_kind}`. Written by:

* `CombatBrain._acquire` / `_perceive` when a soldier (later vehicle crew, aircraft sensor)
  sees an enemy — the LOS test already happened; cost: one dictionary write per acquisition,
  not per frame.
* Hearing (`_on_shot` recent shots) as low-confidence contacts at the shot origin.
* Objective presence (the capture update already counts soldiers inside radius) as contacts
  with `source_kind = objective`.

Read by: `WarSim._decide` (threat and defender estimates replace `known_near`), operation
tasks (assault/hold conditions, cas targets), `SquadControl` tactics (contact to suppress/
flank), the influence layer (§21), the map (fog of war display: the player's faction sees its
own contacts only), base readiness (threat).

Decay: confidence × e^(−Δt/τ) with τ by source (seen 60 s, heard 30 s, objective 120 s);
dropped below a threshold; a contact seen again is refreshed, not duplicated. Position
uncertainty = `vel × Δt` (a growing circle); replanning uses the circle, not the point.

What this replaces: `WarSim.known` (omniscient within 400 m) and the `_share_contact` watch
broadcast (becomes "read contacts within R"). This single change removes omniscience,
persists knowledge across save/load, and gives every level the same picture — the brief's
helicopter-convoy example becomes: sensor acquisition writes the contact; the operation
updater's `recon` task reports it (it is already in the table); `_decide` sees a supply-route
threat term rise in the influence layer at the next decision.

### 20.2 Cost control [VERIFIED constraints]

Perception stays as it is (3 Hz, 24 LOS checks per frame budget). Vehicle crews and aircraft
sensors join the same round robin with their own ranges; an aircraft sensor sweep is a
candidate scan on the faction grid with a cheap height-based LOS (terrain march only, no
trees) at a lower rate (1 Hz). No continuous sensory checks beyond the existing budgets.

---

## 21. Influence maps and spatial reasoning [PROPOSED]

Evaluated options against the existing 50 m `StrategicRoutes` grid (160 000 cells, two
packed arrays, incremental road re-marking already implemented [VERIFIED]):

| Option | Memory | Update | Fit |
|---|---|---|---|
| Extend the 50 m grid with influence layers (threat per faction, control, route risk) | 3 factions × 2 layers × 160 k × 4 B ≈ 4 MB | incremental: stamp a contact's influence (radius 300–600 m, ~100 cells) when it is written/decays; control from objective ownership changes | **best**: route planning can read risk as cost directly (`AStarGrid2D` weight scale per cell), base siting and LZ scoring read it, no second world representation |
| Separate lower-resolution layer (200 m) | 10 k cells per layer | trivial | too coarse for route risk on a 7 m road; fine as a strategic summary derived from the 50 m layer |
| Sparse regional updates | — | — | what "stamp on write" is |
| Localised tactical grids (8 m) around contacts | small, transient | per squad tactic | **yes, transient**: `CombatBrain` already evaluates cover candidates locally; a squad-level 8 m "threat from contact" stamp for flank/suppress targets is computed on request and discarded |
| Per-unit influence maps | — | — | avoid |

Dave Mark's modular influence map system (GDC 2018 / Game AI Pro 2) [RESEARCHED] describes
exactly this layering (proximity, threat, hazards as separate maps combined on query); the
recommendation applies it to the existing grid rather than a new system. Construction
changes: structures affect the blocking grid, not influence; a base stamps a defensive-control
influence from its capabilities. Uncertainty: stamps scale by contact confidence and radius by
position uncertainty.

Air-defence threats are a third layer (known AD contacts with their range) read by the air
route cost table — no aircraft-specific intelligence system.

---

## 22. Logistics-aware AI [PROPOSED, depends on LOGISTICS-01 phase C]

Once inventory and cargo exist: `_decide` gains supply terms (an attack needs ammo stock at
the launching base ≥ need; a base below threshold generates a `resupply(base)` candidate
action scored by its importance and the route risk layer); convoys are operations with
transport + escort elements; `escort` is a support task; "attack an enemy supply route" is an
`interdict(route cells)` operation targeting the enemy's high-value supply cells from the
influence layer (the AI can see roads, not enemy inventories). Nothing here needs a logistics
AI of its own — operations and scoring absorb it.

---

## 23. Unified combat AI [PROPOSED]

Keep `CombatSim.request_fire` as the single shot path and `LineOfFire` as the single
resolver. Extensions:

* Target hit models by kind: soldier (exists), vehicle (hull box + turret box from asset
  bounds, armour class per facing as a damage multiplier — no ballistics), aircraft (hull
  sphere). `_units_hit` walks the same unit grid.
* `WeaponDef` gains `suitability` per target class (rifle vs armour ≈ 0, autocannon vs
  infantry/light, AT vs armour, AD vs air) and range bands; `CombatBrain._candidates` scores
  candidates by suitability × distance, so a tank ignores a rifleman behind an APC and an AD
  vehicle looks up. Multiple weapons per unit = pick the best suitable weapon per shot.
* Suppression (§7.2) as a per-unit value affecting aim error and perception rate.
* Friendly fire: the existing ray check works for vehicles (bigger exclusion).
* Disengagement: role thresholds (health, ammo) → squad/element tactic WITHDRAW.
* Air: ground-based AD is the same engagement loop with an `air` suitability; helicopters
  engaging ground targets use the same `request_fire` with their `WEAPON_*` origin.

What to avoid: armour penetration tables, ballistic trajectories, aircraft dogfighting.

---

## 24. Capability-based mission assignment [PROPOSED]

Tags, not names. `UnitState` gains `capabilities: Array[StringName]` derived once at spawn
from its def (`InfantryLoadout` → `[infantry, direct_fire]`; `VehicleDefs` entry → e.g.
`[ground_mobility, infantry_transport(8), direct_fire, anti_armor]`; `FlightDef` →
`[air_mobility, infantry_transport(10)]`) and `readiness` fields. `StructureDef` gains
`capabilities` (§13). Operation types declare requirements in tags with counts; `_decide`
fills requirements from free units by (tag, readiness, distance, base). Strategic code never
names `truck_6x6` or `supply_depot`. This also makes new assets AI-usable by data alone.

---

## 25. Near/far simulation consistency [PROPOSED, grounded in VERIFIED tier rules]

Rule set, extending the one the code already follows for soldiers:

| Activity | Authority (both tiers) | Detailed adds | Abstract uses |
|---|---|---|---|
| Infantry movement | `UnitState` order/slot | navmesh + RVO | straight legs + structure sliding (exists) |
| Vehicle driving | vehicle record route + bicycle step | collider, probe for trees/soldiers | same step, structure footprints only (plan) |
| Helicopter flight | aircraft record + kinematic controller | visual, rotor FX | same controller, same terrain samples |
| Combat | `CombatBrain`/`CombatSim` on records (exists) | effects | same |
| Reconnaissance | contact table writes from the same perception loop | — | same |
| Convoys | element follow-the-path rule on records | — | same |
| Boarding / cargo / refuel / repair | reservation + timer + record transfer (`occupants`, `Inventory.transfer`) | animation (walk to door) | timer only — **the transfer happens at the timer's end in both tiers**, never on animation events |
| Facility queues | `FacilityTable` (records) | — | same |
| Base defence / missions | operation plan tasks (records) | — | same |

Frequencies: records at 60 Hz for movers (kinematics must be exact under compression),
squads 2 Hz, contacts on event + 1 Hz decay sweep, operations 1 Hz, strategy per profile.
Transitions: because every authority above lives in records integrated at the same step in
both tiers, promotion/demotion changes nothing but nodes — the existing `_promote/_demote`
pattern (no copying) holds. The only transition hazards are animation-driven effects, which
the rule above forbids as authorities.

---

## 26. Performance and scheduling [PROPOSED, with VERIFIED baselines]

Baselines (integration03 perf run, 282 soldiers, war running): `war_update` 53–89 µs avg
(max 7–9 ms on route planning), `brain_update` 0.9–2.7 ms, 50 v 50 RTS 6.5 ms avg frame,
8× reached, ~10–11× CPU bound [VERIFIED/DOCUMENTED].

Scheduling plan:

* Strategy: per faction every 25–30 s (exists); the action-list scorer is O(candidates ×
  terms) ≈ sub-millisecond; AI base siting may take a few ms → spread over frames (a
  coroutine-style budget like the cover search) or run once per decision.
* Operations: 1 Hz (exists); plan task checks are O(elements).
* Squad tactics: 2 Hz in `SquadControl.update` (exists at 2 Hz); cover-candidate requests go
  through the existing budgeted search (16 evaluations/frame).
* Perception: unchanged budgets; vehicles/aircraft join the round robin.
* Contacts: write on event; decay sweep 1 Hz over the table (hundreds of entries).
* Influence: stamp on contact write/decay (~100 cells each); never a full-grid pass except
  on load.
* Route planning: the 7–9 ms spikes are the one real hot spot today; mitigate by (a) one
  route per operation element instead of per squad (squads share the element's polyline with
  offsets), (b) `AStarGrid2D.jumping_enabled` evaluation on the 50 m grid (undocumented
  speed-up factor; must be measured [RESEARCHED]), (c) HPA*-style clustering [RESEARCHED,
  Botea et al. 2004] only if (a)+(b) are insufficient — 160 k cells is small for A*.
* Movers: O(units) per tick; vehicles/aircraft add a few hundred ops each. At 16× the budget
  is the existing ~1.4 ms tick; keep vehicle/aircraft counts in the tens, not hundreds.
* Determinism: all randomness through the seeded `_rand` pattern (exists); no wall-clock in
  decisions.
* Profiling: extend `WorldSim.tick_usec` with `vehicles`, `aircraft`, `contacts`, `influence`
  buckets and `CombatBrain.prof` style counters; the F3 overlay already shows tick buckets.

Do not: plan per soldier, evaluate influence per unit, search routes per frame, run facility
searches over all structures (the `FacilityTable` is per base).

---

## 27. Debugging and observability [PROPOSED]

Build on what exists [VERIFIED]: F3 performance overlay (`WorldDiagnostics`), F4 AI overlay
per soldier (state, target, sight, why not firing; `game_hud.gd`), `ai_reason`, `cover_note`,
`FactionState.last_decision`, operation `outcome`, the war log, scripted tests with JSON
results, `--shots`.

Add, all in the existing HUD/map:

* **Strategic**: per AI faction, the last scored action list (top 5 with their terms) stored
  on `FactionState.last_scores` (runtime, not saved) and shown in the map's faction panel.
* **Operation**: plan with the current task highlighted, element roles, requirements vs
  assigned, replanning reason — on the existing operation detail panel.
* **Squad**: tactic, target contact, team bounds — a line in the squad row and slot markers
  (the RTS already draws slots).
* **Contacts**: the player's faction contact table as fading markers on the map and in RTS;
  a debug toggle shows all factions' contacts.
* **Influence**: a debug map overlay (one layer at a time) drawn from the grid, like the
  route-grid debug already in the map.
* **Vehicles/aircraft**: destination, route polyline, reservation, status reason on the
  unit's F4 card.
* **Bases**: readiness summary and unreachable service points in the construction panel.
* **Cost**: tick buckets per system already in F3; add per-faction AI µs.

All of this is "show the record" — no separate application, little code.

---

## 28. External technical research (relevance per source; links in §34)

| Source | Relevance to FRACTURED NATIONS |
|---|---|
| Orkin, *Three States and a Plan* (F.E.A.R., GDC 2006) | The canonical GOAP: planning per agent with three execution states. Shows why per-agent planning works for a few dozen NPCs; not the right tool for 300 soldiers at 16× — informs the "avoid GOAP" verdict and the value of a tiny execution vocabulary (our soldiers have one: move / react / fire). |
| Isla, *Handling Complexity in the Halo 2 AI* (GDC 2005) and the Halo 3 follow-up | Behaviour trees as prioritised lists with self-describing behaviours; the knowledge/perception layering. Informs: keep per-soldier behaviour a prioritised reaction, keep perception and memory separate from decision (our contact record). |
| Verweij / Straatman / Champandard, Killzone 2 multiplayer bots (GAIC 2009, thesis 2007); Guerrilla, HTN planning in Decima | Hierarchically layered bots: strategy → squads → individuals with an HTN planner per bot. Informs the layering and the decision to take HTN decomposition as data rather than an engine. |
| Gorniak & Davis, *SquadSmart* (AIIDE 2007); Hoang et al., HTN for UT bots (AIIDE 2005) | Squad-level hierarchical plans coordinating members — the shape of the proposed squad tactic layer. |
| Dave Mark, Infinite Axis Utility System (GDC 2013/2015); modular influence maps (GDC 2018 / Game AI Pro 2) | Utility scoring with response curves and layered influence maps — the strategic scorer extension and the influence layer design. |
| Champandard, *The Core Mechanics of Influence Mapping* | Practical influence-map mechanics (propagation, decay, combination); supports the stamp-on-write approach. |
| Creative Assembly, Total War AI series; Cakmak & Davidson (ACCU 2018); GDC 2016 siege AI | Layered campaign/battle AI with a top-level analyser and decomposition to units; limited-time evaluation. Reinforces strategic → operational → unit layering; MCTS noted as a heavier alternative not needed here. |
| TaleWorlds, Bannerlord campaign AI blogs | Lords scoring actions by distance, power, garrison, fief value under the same rules as the player — the same "AI uses the player's systems" principle this game follows. |
| Relic, Company of Heroes / CoH3 patch notes and modding guide | Squad cover search parameters, cover lockouts, squad heat-maps — evidence that squad-level cover search with tuned parameters is the practical industry approach (not per-soldier planning). |
| Bohemia Interactive, Arma 3 AI path-following OPREP; Arma Reforger modding update (road network graph, pathfinding flags) | The catalogue of vehicle AI failure modes and the accepted fix (a road graph from map roads + per-vehicle flags), matching LOGISTICS-01's router plan. |
| Coulter 1992, *Implementation of the Pure Pursuit Path Tracking Algorithm* | The steering law LOGISTICS-01 adopts; look-ahead/speed trade-offs. |
| Layered PID autopilot / terrain-following research (UAV papers, patent) | Outer loop setpoints + terrain-following as vertical-velocity command — the structure recommended for the kinematic helicopter controller. |
| Botea, Müller, Schaeffer, *Near Optimal Hierarchical Path-Finding* (HPA*, 2004) | The fallback if route-planning spikes remain after cheaper fixes. |
| Godot docs: navigation performance, navmesh chunking, `AStarGrid2D` jumping mode; Terrain3D navigation docs | Confirms the current one-area navmesh strategy and the 50 m grid approach; `jumping_enabled` is an untested speed-up to measure. |
| Barriga, Stanescu & Buro, building placement optimisation (AIIDE 2014); Čertický, wall-in placement with ASP | What AI base construction research optimises (chokepoint walls via simulation); justification for the simpler template + validation method here. |
| Robbins, Supreme Commander 2 neural-net platoon AI (GDC) | Noted as the learned alternative; not pursued (opacity, data needs). |

Facts about proprietary implementations above are what the cited talks/blogs state; nothing
beyond that is asserted.

---

## 29. AI architecture comparison

| Architecture | Solves | Does not solve | Integration | Complexity / runtime / debugging | Infantry / vehicles / helicopters / strategy | Near-far / save-load / AI-assisted dev | Verdict |
|---|---|---|---|---|---|---|---|
| **Utility AI** | choosing among weighted candidates (targets, actions, cover) | sequencing, coordination | extends `_decide`, `_cover_score`, candidate scoring | low / tiny / good (scores are explanations) | ✓ (cover, targets) / ✓ / ✓ (LZ) / ✓✓ | records only / trivial / excellent (tables) | **EXTEND** (strategic + scoring everywhere) |
| **Behaviour trees** | per-agent prioritised reactive behaviour with fallbacks | shared knowledge, multi-agent sequencing | would replace `CombatBrain` state machines and `_tactics` — no gain | medium / per-agent tick / visual but needs tooling | ✓ / ✓ / ✓ / ✗ | tree state is awkward to persist | **AVOID** as runtime; keep the prioritised-list *idea* in `_tactics` |
| **HTN** | goal decomposition into ordered subtasks | choosing goals, spatial reasoning | plan lists on `OperationState` capture the benefit | engine: high; data plan: low | ✗ / ✗ / ✗ / ✓ (operations) | plan = data, persists | **EXTEND** (decomposition as data), AVOID (engine) |
| **GOAP** | emergent action chains per agent | scale, predictability | no natural host | high / search per replan / poor | ✓(few agents) / — / — / ✗ | state-space search vs save | **AVOID** |
| **FSM / HSM** | explicit, persistable control flow | large flat machines | what operations, tactics and vehicle status already are | low / tiny / good | ✓ / ✓ / ✓ (flight modes) / ✓ (op phases) | enums on records | **PRESERVE + EXTEND** |
| **Influence maps** | spatial threat/control/risk | sequencing | layers on the 50 m grid | low–medium / incremental / visual overlay | ✓ (local) / ✓ / ✓✓ (AD, LZ) / ✓✓ | arrays saved or rebuilt from contacts on load | **EXTEND** (grid layers) |
| **Blackboard** | shared state between levels | decisions | `WorldState`/`UnitState`/`WarState` *are* the blackboard | none | ✓ all | by construction | **PRESERVE** (name it) |
| **Event-driven** | reactions without polling | long-term planning | signals exist (`shot_fired`, `unit_died`, `order_changed`, `area_changed`) | low | ✓ all | events are transient; state in records | **PRESERVE** (contacts on event) |
| **Rule-based** | explainable priorities | nuance | `_decide` steps 0–4 are rules | low | — / — / — / ✓ | trivial | **PRESERVE** as the outer ordering of the utility scorer |
| **Hybrid (utility → data plans → HSM → reactions + influence + records-as-blackboard)** | all of the above at this scale | nothing it needs to | all of it is extension | lowest total | ✓ / ✓ / ✓ / ✓ | ✓ / ✓ / ✓ | **RECOMMENDED** |

AI-assisted development suitability: data tables (profiles, plans, capability tags, weights)
and plain records are what an LLM-driven workflow edits and tests most reliably; planner
engines and BT editors are not.

---

## 30. Proposed future architecture

```
 STRATEGIC (per AI faction, 25-30 s)          WarSim._decide  [EXTEND]
   inputs: WarState (objectives, bases, contacts, influence layers, inventories*), FactionProfile, FactionState.focus
   output: candidate actions scored → OperationState(s) with requirements filled by capability
                     │
 OPERATIONAL (1 s)   ▼                        WarSim._update_operation  [EXTEND]
   OperationState.plan (tasks) + elements (roles) ; requests from squads ; facility requests
   → squad tactical orders, vehicle/aircraft orders, reservations, withdraw/return
                     │
 BASE (on change)    │   ConstructionState.bases + FacilityTable [NEW, narrow]  readiness cache [EXTEND]
                     │
 SQUAD (2 Hz)        ▼                        SquadControl  [EXTEND]
   tactic state (bound / suppress / flank / withdraw / defend), fire teams, slots, routes
                     │
 UNIT (3 Hz / 60 Hz) ▼
   CombatBrain [EXTEND: contacts out, suitability, suppression, vehicle & air crews]
   WorldSim abstract step [PRESERVE] · VehicleSim* [LOGISTICS-01] · FlightSim [NEW] · SoldierBody [PRESERVE]
                     │
 SHARED DATA         ▼
   WorldState / UnitState (+capabilities, veh*, air) / SquadState (+tactic, teams) / WarState (+contacts, focus)
   StrategicRoutes grid (+influence layers, vehicle & air cost tables) [EXTEND] · RoadNetwork [PRESERVE]
   StructureDef (+capabilities, service_points) [EXTEND] · ConstructionState (+bases, FacilityTable) [EXTEND/NEW]
   DetailManager [PRESERVE; per-kind radii] · CombatSim/LineOfFire [EXTEND: hit models]
   * = LOGISTICS-01 scope
```

Classification of every component:

| Component | Class | Why |
|---|---|---|
| `WorldState`, `UnitState`, `SquadState`, `WarState` records | PRESERVE (+fields) | the blackboard; adding fields is the established pattern |
| `WorldSim` loop, abstract step | PRESERVE | tier-independent authority; new movers are added as steps |
| `DetailManager` | PRESERVE | representation swap without copying; per-kind radii are parameters |
| `WarSim._decide` | EXTEND | action-list utility with contacts/influence/capabilities/focus |
| `OperationState` / `_update_operation` | EXTEND | data plans + elements; the HSM stays |
| `SquadControl` / `SquadState` | EXTEND | tactic layer on existing slots/routes |
| `CombatBrain` | EXTEND | contact output, suitability, suppression, non-infantry crews |
| `CombatSim` / `LineOfFire` / `WeaponDef` | EXTEND | hit models, suitability, multi-weapon |
| `StrategicRoutes` | EXTEND | influence layers, per-domain cost tables; single grid |
| `RoadNetwork` | PRESERVE | authority; vehicle graph is a derived index (LOGISTICS-01) |
| `StructureDef` / `StructureCatalog` / def writers | EXTEND | capabilities + service points from sidecar markers |
| `StructureManager` | PRESERVE | geometry/caches; reachability check reuses its grids |
| `ConstructionState` | EXTEND | bases, facility table |
| `FacilityTable` | NEW (narrow) | no existing owner for reservations; saved with construction |
| Helicopter flight controller (`FlightSim` + `FlightDef`) | NEW | no existing mover handles 3D; kinematic, record-based, both tiers |
| Contact table | NEW data in `WarState` (EXTEND) | replaces `known` and watch broadcasts |
| AI base builder | NEW logic inside `WarSim` decisions, using `ConstructionState` | the construction system is preserved; only the placement policy is new |
| Observability panels | EXTEND HUD/map | show records |
| `VehicleSim`, `VehicleRouter`, `Inventory` | LOGISTICS-01 (not classified here) | assumed per plan |
| Planner engine (HTN/GOAP), BT runtime | AVOID | no scale or persistence benefit |
| Separate base/campaign/battle simulation | AVOID | violates one-world rule |
| Per-aircraft intelligence / airspace manager | AVOID | contacts + influence + pad reservations suffice |
| Second road or world representation | AVOID | grid layers and road graph index are derived caches of existing authorities |
| Base-level AI "coordinator" class | AVOID | an operation type does it without a fourth order source |

Ownership of authoritative state stays exactly where it is: records in `WorldState`,
operations in `WarState`, structures in `ConstructionState`, roads in `RoadNetwork`; derived
caches (influence, road graph, facility free lists, base readiness) are rebuildable and say so.
Save/load boundary: everything AI-relevant that must survive a load is on records (contacts,
plans, tactics, reservations, focus); caches rebuild on `restored`.

---

## 31. Incremental AI development roadmap

Dependencies: LOGISTICS-01 phases A–D (vehicles, transport, inventory, facilities) are a
parallel track; milestones below marked (L-A…L-D) need that phase merged. Order is by
dependency and gameplay value, not by the brief's list.

### Quick wins (no dependency on LOGISTICS-01)

| # | Milestone | Goal | Affects | New | Value | Complexity / risk | Validation |
|---|---|---|---|---|---|---|---|
| Q1 | **AI-INTEL-01** contact table | one shared, decaying, saved contact model; remove `known` omniscience; map fog-of-war markers | `WarState`, `WarSim._update_intel/_decide`, `CombatBrain._acquire/_on_shot`, map | contact record | AI stops reacting to unseen forces; player sees what its troops see | low / low; perf: event writes + 1 Hz decay | Scenario J; `sandbox --only war` outcomes not degraded; `persist` keeps contacts |
| Q2 | **AI-OBS-01** observability | strategic score list, operation plan panel, squad tactic line, contact overlay, influence overlay stub | HUD, map, `FactionState.last_scores` | — | every later milestone is debuggable | low / none | screenshots per panel |
| Q3 | **AI-SQUAD-01** squad tactics | fire teams, BOUND / SUPPRESS / WITHDRAW / DEFEND tactics, suppression value, wedge formation | `SquadControl`, `SquadState`, `CombatBrain` (suppression, suppress_at), `UnitState` | — | visibly better firefights, the forest example | medium / medium (balance) | Scenario A; `combat-tactics` regression |
| Q4 | **AI-STRAT-01** action-list scorer | candidate actions with contact/influence terms, `focus`, better defender estimates, orderly FAILED exit | `WarSim._decide/_end`, `FactionProfile`, `StrategicRoutes` (threat/control layers from Q1) | influence layers (data) | believable multi-front behaviour | medium / medium | Scenario I; long autonomous war run (`--minutes`) compared to WORLD-SANDBOX-01B numbers |

### Foundations (after L-A/L-B)

| # | Milestone | Goal | Dependencies | Notes |
|---|---|---|---|---|
| F1 | **AI-OPS-01** operation plans and elements | data plans, roles, requirements by capability tags, support requests, withdraw/return | Q1, Q3; L-B for `mount/dismount` tasks | the backbone of everything after; Scenario B (foot and mechanized variants) |
| F2 | **AI-VEH-01** vehicle tactical AI | crews in `CombatBrain`, hit models, suitability, role behaviours, convoy follow rule | L-A, F1 | Scenarios C, D |
| F3 | **BASE-AI-01** facilities and readiness | `StructureDef` capabilities + service points (def writers), `FacilityTable`, base membership, readiness cache, reachability check + UI feedback, infantry base behaviour | L-C/L-D (inventory, facility fields) | Scenario E precondition; §13–15, §19 |
| F4 | **AI-DEF-01** base defence | `DEFEND_BASE` operation plan, defensive point occupation, logistics withdrawal, reinforcement escalation | F1, F3 | Scenario E |

### Air

| # | Milestone | Goal | Dependencies |
|---|---|---|---|
| A1 | **AIR-01** helicopter flight | `FlightDef`/`FlightSim`, obstacle height layer, pad test, hover/land, abstract tier, `AIRCRAFT` kind, presentation body; a dev flight showcase | assets (next asset milestone), F3 for pads |
| A2 | **AIR-02** helicopter missions | transport/extraction/CAS/escort tasks, LZ scoring, AD threat layer in route cost, base pad operations | A1, F1, Q1 |

### Integration and expansion

| # | Milestone | Goal | Dependencies |
|---|---|---|---|
| C1 | **AI-CA-01** combined-arms operations | mechanized + armour + air plans, synchronisation gates, support requests across domains; Scenario H and L | F1, F2, A2 |
| C2 | **BASE-AI-02** AI base construction | site scoring, template placement, validation, expansion decisions; Scenario K | F3, Q4 |
| C3 | **AI-INTEL-02** spatial intelligence | full influence layers (route risk, supply corridors), recon operations, interdiction | Q1, Q4, F1 |

Performance checkpoints at Q3, F1, F2, A1, C1 against the integration03 baseline using the
same scenarios (§26). Each milestone keeps the change-impact test policy.

---

## 32. Evaluation scenarios

All reproducible as `--ai-test --only <id>` scenarios in the existing self-test chain (extend
`Integration03SelfTest`), deterministic by seed, accelerated. "Current" = what the existing
tests show today; nothing below is claimed tested unless marked.

| Id | Scenario | Intended behaviour | Verified current behaviour | Missing | Architecture | Metrics | Deps / perf risk |
|---|---|---|---|---|---|---|---|
| A | Tactical infantry: two squads vs a defended position | contact shared; suppression element fires; bounding/flanking element moves; withdrawal below strength | soldiers acquire, fire, take cover individually; squads keep formation [VERIFIED, combat-tactics tests] | squad tactics, suppression, contacts | Q1, Q3 | time to contact, suppression exposure, flank angle achieved, casualties ratio, orders per minute | none |
| B | Mechanized assault | mount at base, convoy to dismount point, dismount, assault with APC support | none (vehicles static) [VERIFIED] | L-A/B, F1, F2 | F1, F2 | dismount distance to contact, time mounted, APC support LOS share | vehicle sim cost |
| C | Armoured support | tanks overwatch, infantry assault, target selection by suitability | none | F2 | F2, §23 | target suitability hits, friendly fire 0, hull-down share | — |
| D | Convoy logistics with a blocked route | reroute, escort reacts, mission continues, delivery recorded | none | L-A/C, F1, F2 | F1, F2 | delivery time, reroute count, stall time | route planning spikes |
| E | Base defence | guards detect, positions occupied, APC to gate, trucks withdraw, reinforcement requested | garrison stands at objective slots; soldiers react to fire [VERIFIED] | F3, F4 | F3, F4 | detection distance, positions occupied within T, losses | — |
| F | Helicopter transport | pickup, flight with terrain clearance, LZ selection, insertion, return | none | A1, A2 | A1, A2 | min AGL, oscillation metric (altitude error RMS), LZ score, time | — |
| G | Helicopter support | armed recon, CAS, disengage on threat/ammo | none | A2 | A2 | targets engaged by suitability, AD exposure time | — |
| H | Combined-arms operation | assembly, synchronised departure, elements with roles, success | none | C1 | C1 | synchronisation error at rendezvous, element task completion | all |
| I | Multiple fronts | allocation by scored threat, reserves held | greedy per-threat reinforcement [VERIFIED code] | Q4 | Q4 | objectives held, reserve use, decision explanations | — |
| J | Intelligence uncertainty | contact decays, recon tasked, plans use uncertainty circle | `known` forgets after 90 s; no recon [VERIFIED] | Q1, C3 | Q1, C3 | contact confidence over time, recon dispatch latency | — |
| K | AI-built base | site chosen, structures placed, gate and depots reachable | site search + programmatic placement exist in tests [VERIFIED] | C2 | C2 | reachability pass rate, placement time, structures placed | placement cost per decision |
| L | Persistent simulation far from the player | operation completes identically with the camera away; no tier artefacts | infantry operations do (sandbox `navigation`, `war`) [VERIFIED] | vehicles/aircraft in abstract tier | L-A, A1 | state divergence between a near and a far run of the same seed, frame time | tick cost at 16× |

Each scenario must fail when its precondition is missing (project rule).

---

## 33. Dependencies and risks

* **LOGISTICS-01 shape**: every vehicle-related proposal assumes the plan's record layout
  (`UnitState.veh`, routes on the record, `Inventory` with one transfer, facility fields). If
  the implementation diverges, §8, §13–15 integrate at the record level; names change, not
  the architecture. The uncommitted state was not inspected beyond file names.
* **Contact table replacing `known`**: changes AI aggressiveness (less omniscient); profile
  weights will need re-tuning; validate with the autonomous war scenario before and after.
* **Squad tactics vs. player orders**: tactics must end on any player order exactly as
  reactions do (`order_mode == "player"`); regression risk in `_tactics`.
* **Route-planning spikes** with more elements/convoys: mitigations listed in §26; measure
  `jumping_enabled` early.
* **Helicopter assets** do not exist; A1 depends on an asset milestone following
  `docs/ASSET_STANDARD.md` conventions (markers `SEAT_*`, `CARGO_*`, `WEAPON_*`, rotor).
* **Save compatibility**: every new record field must default sensibly in `from_dict`
  (the project already does this); caches must rebuild on `restored`.
* **Balance**: more capable AI may make the three-faction war faster or one-sided; keep
  `FactionProfile` as the tuning surface.

---

## 34. Sources and references

Project (all [VERIFIED]/[DOCUMENTED] in `feature/world-integration-03` @ 21e846a and
`feature/logistics-01-base-02` @ 3f34dd2): `scripts/core/world_sim.gd`, `world_state.gd`,
`unit_state.gd`, `squad_state.gd`, `squad_control.gd`, `detail_manager.gd`,
`time_compression.gd`; `scripts/strategy/war_sim.gd`, `war_state.gd`, `operation_state.gd`,
`objective_state.gd`, `faction_state.gd`, `faction_profile.gd`, `strategic_routes.gd`,
`sandbox_setup.gd`; `scripts/combat/combat_brain.gd`, `combat_sim.gd`, `line_of_fire.gd`;
`scripts/units/soldier_body.gd`, `vehicle_body.gd`, `unit_proxy.gd`;
`scripts/construction/structure_manager.gd`, `structure_catalog.gd`, `structure_def.gd`,
`structure_state.gd`, `construction_state.gd`; `scripts/world/road_network.gd`,
`area_navigation.gd`; `scripts/rts/rts_controller.gd`; `scripts/debug/*selftest.gd`,
`world_diagnostics.gd`; `docs/WORLD-INTEGRATION-03_REPORT.md`, `WORLD-PLAYTEST-01_REPORT.md`,
`WORLD-SANDBOX-01B_REPORT.md`, `INTEGRATION-02_REPORT.md`, `ASSET_STANDARD.md`,
`docs/logistics01/LOGISTICS_PLAN.md`; `benchmarks/raw/integration03_test.json` (local).

External [RESEARCHED]:

* Orkin, J. — *Three States and a Plan: The AI of F.E.A.R.* (GDC 2006): https://pages.cs.wisc.edu/~dyer/cs540/handouts/gdc2006_orkin_jeff_fear.pdf ; GDC Vault: https://gdcvault.com/play/1013282/Three-States-and-a-Plan
* Isla, D. — *Handling Complexity in the Halo 2 AI* (GDC 2005); Halo 3 lecture slides: https://web.cs.wpi.edu/~rich/courses/imgd4000-d10/lectures/halo3.pdf ; background: https://en.wikipedia.org/wiki/Behavior_tree_(artificial_intelligence,_robotics_and_control)
* Verweij, T. — *A Hierarchically-Layered Multiplayer Bot System for a First-Person Shooter* (MSc thesis, Killzone 2): https://www.guerrilla-games.com/media/News/Files/VUA07_Verweij_Hierarchically-Layered-MP-Bot_System.pdf ; Champandard/Verweij/Straatman, *Killzone 2 Multiplayer Bots* (GAIC 2009): https://www.slideshare.net/guerrillagames/killzone-2-multiplayer-bots ; Guerrilla, *HTN planning in Decima*: https://www.guerrilla-games.com/read/htn-planning-in-decima
* Gorniak, P., Davis, I. — *SquadSmart: Hierarchical Planning and Coordinated Plan Execution for Squads of Characters* (AIIDE 2007): https://ojs.aaai.org/index.php/AIIDE/article/view/18775 ; Hoang, Lee-Urban, Muñoz-Avila — HTN for UT bots (AIIDE 2005): https://faculty.cc.gatech.edu/~surban6/publs/AIIDE05.pdf ; Nau et al. on game HTN: https://www.cs.umd.edu/~nau/papers/nau2013game.pdf
* Mark, D. — Infinite Axis Utility System: https://gameai.com/iaus.php ; *Architecture Tricks: Managing Behaviors in Time, Space, and Depth* (GDC 2013): https://www.gdcvault.com/play/1018040/Architecture-Tricks-Managing-Behaviors ; Modular, scalable influence map system (GDC 2018 / Game AI Pro 2): https://gameai.com/imap.php
* Champandard, A. — *The Core Mechanics of Influence Mapping*: https://www.gamedev.net/articles/programming/artificial-intelligence/the-core-mechanics-of-influence-mapping-r2799
* Creative Assembly — *The AI of Total War* series (gamedeveloper.com): https://www.gamedeveloper.com/programming/the-road-to-war-the-ai-of-total-war-part-1- ; Cakmak, D., Davidson, G. — *How AI can deliver entertainment in Total War* (ACCU 2018): https://accu.org/conf-docs/PDFs_2018/Guy_Davidson__Duygu_Cakmak_-_How_AI_can_deliver_entertainment_in_Total_War.pdf ; Arsenault, A. — *Have Fun Storming the Castle* (GDC 2016 siege AI): https://gdcvault.com/play/1023038/Have-Fun-Storming-the-Castle
* TaleWorlds — Bannerlord campaign AI dev blogs: https://www.taleworlds.com/en/Games/Bannerlord/Blog/68 ; https://taleworlds.com/en/Games/Bannerlord/Blog/4
* Relic — Company of Heroes squad AI (community modding guide, Essence Engine cover search): https://coh2.org/topic/63245/squad-ai-a-how-to ; CoH3 AI patch notes: https://steamcommunity.com/sharedfiles/filedetails/changelog/2942790265?p=8
* Bohemia Interactive — *OPREP: AI path-following improvements* (Arma 3): https://dev.arma3.com/post/ai-path-following-improvements ; Arma 3 AI driving feedback thread: https://forums.bohemia.net/forums/topic/191515-ai-driving-feedback-topic/ ; Arma Reforger modding update (road network graph, pathfinding flags): https://reforger.armaplatform.com/news/modding-update-june-7-2024 ; Reforger 1.2 (AI driving): https://reforger.armaplatform.com/news/update-june-26-2024-2
* Coulter, R. C. — *Implementation of the Pure Pursuit Path Tracking Algorithm* (CMU-RI-TR-92-01): https://www.ri.cmu.edu/publications/implementation-of-the-pure-pursuit-path-tracking-algorithm/ ; derivation notes: https://av2.readthedocs.io/en/latest/theory/pure-pursuit.html
* Layered autopilot / terrain following: mini-UAV layered PID vs adaptive (Politecnico di Torino): https://staff.polito.it/giorgio.guglieri/Flight_Mechanics_Research_Team/Papers_files/17_AEAT-10-2014-0161.pdf ; helicopter waypoint PID guidance (IST Lisbon): https://isr.tecnico.ulisboa.pt/wp-content/uploads/2015/05/1572_prev3.pdf ; terrain-following vertical-velocity command (patent US 11644850): https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/11644850
* Botea, A., Müller, M., Schaeffer, J. — *Near Optimal Hierarchical Path-Finding* (2004): https://webdocs.cs.ualberta.ca/~mmueller/ps/hpastar.pdf
* Godot docs — navigation performance: https://docs.godotengine.org/en/4.3/tutorials/navigation/navigation_optimizing_performance.html ; navmesh chunks: https://docs.godotengine.org/en/4.3/tutorials/navigation/navigation_using_navigationmeshes.html ; `AStarGrid2D`: https://docs.godotengine.org/en/4.3/classes/class_astargrid2d.html ; Terrain3D navigation: https://terrain3d.readthedocs.io/en/latest/docs/navigation.html
* Barriga, N., Stanescu, M., Buro, M. — *Building Placement Optimization in Real-Time Strategy Games* (AIIDE 2014): https://ojs.aaai.org/index.php/AIIDE/article/view/12735 ; Čertický, M. — *Implementing a Wall-In Building Placement in StarCraft with Declarative Programming*: https://deepai.org/publication/implementing-a-wall-in-building-placement-in-starcraft-with-declarative-programming
* Robbins, M. — Supreme Commander 2 neural-network AI (GDC coverage): https://gamedeveloper.com/programming/video-three-unorthodox-uses-for-video-game-ai
* Jack, M. — *Tactical Position Selection: An Architecture and Query Language* (Game AI Pro / Game AI Pro 360): https://www.routledge.com/Game-AI-Pro-360-Guide-to-Tactics-and-Strategy/Rabin/p/book/9780367150884 (contents not available online; cited for the architecture name only)

---

## 35. Open questions

1. **LOGISTICS-01 final shape** — which of the plan's records land as planned (`VehicleState`,
   `Inventory`, facility fields, `bases`)? Decides the exact integration of F1–F4.
2. **Fire teams** — split by member index (no new record) or an explicit `teams` field? The
   latter persists leaders per team; recommended but needs save-format care.
3. **Contact confidence model** — exponential decay per source is proposed; whether the
   player's map should show decayed contacts (believability vs. clarity) is a design choice.
4. **Influence layer resolution** — 50 m matches the grid; is 50 m enough for route risk on
   roads (a road cell is 50 m wide in the grid)? Measure with Scenario D.
5. **Suppression effect size** — how strongly it reduces aim/perception without making
   firefights static; needs playtests, not research.
6. **Helicopter assets and `FlightDef` numbers** — turn radius, climb rate, hover ceiling are
   design values to be chosen with the asset milestone.
7. **Multiple observers** — should a base under attack that the player watches on the map get
   bodies (a second `DetailManager` area)? Not needed for correctness (records decide), only for
   spectacle; deferred.
8. **AI base templates** — authored by hand (recommended, 3–4 templates) or derived from the
   player's bases (learning layouts)? Hand-authored first.
9. **`AStarGrid2D.jumping_enabled`** on a weighted grid — Godot's docs do not state whether
   jumping respects weight scales; must be tested before relying on it.
10. **Determinism across tiers for vehicles and aircraft** — the plan integrates records at
    60 Hz in both tiers; the near-tier physics probe (trees, soldiers) introduces tier-dependent
    input. Acceptable (a stop for a tree is local), but Scenario L should measure divergence.
