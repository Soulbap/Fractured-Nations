# AI roadmap — consolidated after INTEGRATION-04

Single planning document for the AI milestones after LOGISTICS-01. It merges
[AI-ARCHITECTURE-RESEARCH-01](AI-ARCHITECTURE-RESEARCH-01.md) (the *why* and the technique
comparison — not repeated here) with the code that actually exists on
`feature/integration-04` (LOGISTICS-01 / BASE-02 verified, see
[INTEGRATION-04_REPORT.md](INTEGRATION-04_REPORT.md) §4). Where the research assumed the
LOGISTICS-01 *plan*, this document uses the *implemented* names.

Evidence tags: **[CODE]** read in the source of this branch, **[REPORT]** from a project
report, **[PROPOSED]** a decision for the milestone, **[UNKNOWN]** needs measurement.

## 1. Rules every milestone keeps

1. One world, one record per entity. New AI state lives on `UnitState` / `SquadState` /
   `WarState` / `ConstructionState` and is saved; caches rebuild on `restored`.
2. Ownership order stays **player > operation > squad tactic > individual reaction**. No two levels
   write the same field. A player order releases the squad from its operation
   (`WarSim.release_squads`) and cancels tactics/reactions.
3. AI commands **the same APIs the player uses**. No AI-only transport manager, vehicle controller,
   inventory, base manager or construction path.
4. Both tiers run the same record code; nothing in AI depends on a body existing.
5. Every milestone ships a visible gameplay improvement, an observability hook (what is it thinking
   and why — a string on a record), a change-impact test set, and a scenario that **fails when its
   precondition is missing**.
6. No planner engine (GOAP/HTN), no behaviour-tree runtime, no second blackboard, no per-unit
   influence maps. Plans are data on `OperationState`; choices are utility scores.
7. Faction differences stay in `FactionProfile` (numbers) until a gameplay case needs more. Doctrine
   is *not* a framework: add a weight, not a class.

## 2. Interface map: what AI commands today [CODE]

All of these exist and are what operations / strategic AI must call. Every call returns
`{ok, reason}` (or a bool) — AI must handle refusal and log the reason.

| AI intent | Call | Owner / notes |
|---|---|---|
| Move a squad (route, formation) | `SquadControl.order_move(ids, p)`, `follow_route(sq, route, formation)` | exists; aboard members are skipped (`vehicle_id >= 0`, `_active_members`) |
| Drive a vehicle | `VehicleSim.order_drive(id, p)`, `order_group(ids, p)` (≥ 2 vehicles and > 600 m → convoy), `halt(id)` | route planned by `VehicleRouter`; refusals carry a reason ("Path blocked", fuel, unreachable) |
| Convoy | `VehicleConvoy.order_convoy(ids, dest)`, `redirect`, `stop` | leader/follower spacing already enforced |
| Board / carry / set down a squad | `VehicleTransport.order_transport(vid, squad, dest)`, `order_group(vids, sqids, dest)`, `unload(vid)`, `cancel(vid)` | phases APPROACH→BOARDING→TRANSIT→UNLOADING in `VehicleState.phase`; capacity truck 12 / APC 8; leftover soldiers reported |
| Load / unload / deliver / refuel / repair | `LogisticsSim.order_load / order_unload / order_delivery / order_refuel / order_repair` | vehicle drives to the depot dock, timer, `Inventory.transfer` |
| Resupply squads | `LogisticsSim.order_resupply(squad_ids, "s<id>"/"v<id>")` | soldiers refill `reserve` from the source inventory |
| Find stores | `LogisticsSim.stores(faction, kind)`, `nearest_store(pos, faction, item, kind)`, `inventory_of(key)` | key = structure/vehicle |
| Recruit / acquire | `BaseSim.recruit(barracks_id)`, `acquire_vehicle(depot_id, type)` | costs paid from the base's stores; queues on `StructureState.facility` |
| Base query | `BaseSim.bases_of(faction)`, `summary(bid)`, `base_stock(bid)`, `facilities_of(bid)`, `base_of_position` | summary is computed on demand today (no cache yet) |
| Automation | `BaseSim.add_rule_restock / add_rule_refuel`, `on_manual_order` pauses a rule 3 min | rules in `WorldState.logistics`, persisted |
| Build | `StructureManager.check_building / check_line` + `ConstructionState.add_building / add_line` | same path as the player and the integration tests |
| Squads / spawn | `WarSim.spawn_squad(f, p, n)` | used for reserves **without any inventory cost** — see gap G1 |

Vehicle state the strategic and operational layers can read without new code: `UnitState.faction,
position, health`, `VehicleState.type_id, fuel, status/reason, route/route_i, occupants, pending, phase,
squad_id, cargo (Inventory), convoy_id, job, def()` (passengers, fuel capacity, cargo capacity, speeds).
Readiness today = `status == PARKED/DRIVING`, fuel fraction, health, cargo, `job.is_empty()`.

## 3. Gaps found in the code that shape the order

| # | Gap | Evidence | Resolved in |
|---|---|---|---|
| G1 | **AI factions have no logistics economy.** `SandboxSetup` builds HQ perimeters only; the starting stockpile goes to the *player's* first supply depot; AI reserves are `f.reserves` integers spawned by `spawn_squad` with no inventory cost; AI factions own no vehicles. | `sandbox_setup.gd`, `logistics_sim.gd:_on_structure_added`, `war_sim.gd:_update_reserves` | BASE-AI-01 (prerequisite of OPS-01) |
| G2 | **No faction-level contact model.** `WarSim.known` is omniscient within 400 m, forgotten after 90 s and **not saved**; `CombatBrain` indexes soldiers only (vehicles are invisible to it). | `war_sim.gd:_update_intel`, `combat_brain.gd:_ensure_grid` | AI-INTEL-01 |
| G3 | **Vehicles cannot be hurt by weapons.** `LineOfFire._units_hit` has soldier hit volumes only; `VehicleSim.apply_damage(id, amount, source)` is the existing hook (destruction, passenger ejection, cargo stays are tested through it). `WarSim._on_unit_died` ignores vehicles. | `line_of_fire.gd`, `vehicle_sim.gd:113` | AI-VEH-01 |
| G4 | **No capability tags.** Squads/vehicles are matched by `kind`/`type_id`; `VehicleDefs.Def` has `passengers`, cargo capacity, fuel, speeds but no role/weapon data; `FacilityDefs` has the facility table but `StructureDef` carries no capabilities or service points. | `vehicle_defs.gd`, `facility_defs.gd` | OPS-01 (units: derive from defs) / BASE-AI-01 (facilities: extend `FacilityDefs`, not a second table) |
| G5 | **Operations are single-echelon, squad-only.** One route + one ENGAGING order for every squad; no assembly gate, no mount/dismount, no withdrawal except FAILED-by-losses (squads stay where they are). | `war_sim.gd:_update_operation` | OPS-01 |
| G6 | **Squad tactics are minimal** (Move/Hold/Follow/Regroup + per-soldier cover reaction). No fire teams, suppression, flank, bound, withdraw. | `squad_control.gd`, `combat_brain.gd:_tactics` | SQUAD-01 |
| G7 | **Operation ↔ transport hand-over is not defined.** `order_transport` does not release a squad from its `OperationState`; only RTS player orders do (`rts_controller.gd:476`). An AI operation that mounts a squad must keep ownership consistent itself. | `vehicle_transport.gd` (no `release_squads`/`op_id`) | OPS-01 (define: squad stays in its op while aboard; op owns the vehicle element) |
| G8 | **Bases are named groups, not services.** No reservation of docks/parking, no readiness cache, no reachability check for service points; dock slots are retried on conflict (`dock_world`, `parking_world`). | `logistics_sim.gd`, `base_sim.gd:summary` | BASE-AI-01 (cache) / DEF-01 (reservations only if contention is observed) |

## 4. Limitations from LOGISTICS-01, classified

| # | Limitation | Class | Why / when |
|---|---|---|---|
| 1 | AI vehicles clip/queue in crowded yards (up to 2.3 m² overlap, "stopped behind another vehicle") | **Dependency of OPS-01** (watch item) | An assembly point with 4+ vehicles will hit this. Mitigation inside OPS-01: stagger departures (convoy already does), spread assembly slots by `parking_world`. Real fix (yard negotiation) only if OPS-01 scenarios show stalls. |
| 2 | Cross-country planner ignores trees/rocks | **Safe for now** | Road routes are cleared; near-tier probe + stuck recovery handle the rest. Revisit with INTEL-02 (route risk) or if OPS-01 off-road legs stall. |
| 3 | Infantry cannot damage vehicles | **Blocker of AI-VEH-01** (not of earlier milestones) | Hit model + `apply_damage` wiring is AI-VEH-01 step 1. |
| 4 | APC weapon station missing | **Blocker of AI-VEH-01 / CA-01** | Needs `WEAPON_*` marker on the APC asset, a `WeaponDef`, and a crew entry in `CombatBrain`. |
| 5 | Vehicle/infantry combined-arms combat | **Dependency** | Requires 3 + 4 + OPS-01 elements. |
| 6 | Facility functions that are placeholders (training, ranges, …) | **Safe for now** | AI needs barracks, depots, magazine, fuel, repair — all functional. |
| 7 | No resource production / income | **Dependency of STRAT-01/BASE-AI-01 scoring** | A faction that only spends will run dry and the AI must show believable behaviour at zero stock. Decision: BASE-AI-01 gives each AI faction a finite seeded stockpile plus a slow, explicit **supply inflow at the HQ** (a data rate in `FactionProfile`), no production chain. |
| 8 | No route preview / vehicle feedback for the player | **Presentation improvement** | OBS-01 draws vehicle routes and AI plans from the same record (`VehicleState.route`); do it there. |
| 9 | Performance with WarSim + combat + vehicles + logistics together | **Dependency (measure per milestone)** | Existing numbers are per subsystem (§6). One combined scenario defined in §7, run at OPS-01 and CA-01. |
| 10 | `--combat-ai-test` precondition failure (site search tied to old terrain) | **Safe to leave, but fix before SQUAD-01** | It is the one test that exercises scripted engagements; SQUAD-01 changes combat behaviour, so its site search must be repaired (small, test-only) at the start of that milestone. Not caused by logistics. |

## 5. Milestones

Order is the research order with three changes the code justifies: **OBS-01 is built together with
INTEL-01** (the contact overlay is its first consumer); **BASE-AI-01 moves before OPS-01** (G1: there is
nothing to operate without AI bases, stock and vehicles); **AI-VEH-01 is split** — the hit model and
`apply_damage` wiring may be pulled forward as a small prerequisite if SQUAD-01 playtests show vehicles
ought to react to fire, otherwise it stays after OPS-01.

```
INTEL-01+OBS-01 → SQUAD-01 → STRAT-01 → BASE-AI-01 → OPS-01 → VEH-01 → DEF-01
                                                          └────────→ AIR-01 → AIR-02 → CA-01
                                         BASE-AI-02, INTEL-02 last
```

### AI-INTEL-01 — persistent faction intelligence (+ AI-OBS-01)
* **Objective.** Factions know what their troops have seen, not everything within 400 m; knowledge
  fades, persists across save/load, and the player sees the same picture on the map.
* **Reuse.** `CombatBrain._acquire/_perceive/_on_shot` (writers), `WarSim._update_intel` (replaced),
  `WarState.to_dict`, map layer code from LOGISTICS-01 for markers, `FactionState.last_decision`.
* **Add.** `WarState.contacts[faction][enemy_id] = {pos, vel, t_seen, confidence, source}`; 1 Hz decay;
  uncertainty radius = speed × age; `_share_contact` reads contacts instead of the 120 m watch;
  vehicles are *recordable* contacts even though `CombatBrain` cannot target them yet (record
  `kind`); OBS: contact overlay (map + RTS), strategic score list on `FactionState.last_scores`, F4 card
  for vehicles (status reason, route).
* **Depends on.** Nothing. **Risk.** Less omniscient AI shifts war balance → compare with the
  WORLD-SANDBOX-01B autonomous-war numbers before/after; tune `FactionProfile`.
* **Validation.** Contact written on sight, decays, survives F5/F9, never created without LOS/hearing;
  `known_near` replaced in `_decide`; sandbox `war,persist` outcomes within the previous band.
* **Done when.** No code reads `WarSim.known`; contacts persist; the player's faction map shows only
  its own contacts; war runs 20 sim-minutes without regression in capture rate.
* **Visible.** Enemy markers appear when seen and fade; AI no longer reinforces against unseen forces.

### AI-SQUAD-01 — fire teams, suppression, flank, bound, withdraw, defend
* **Objective.** Firefights show recognisable infantry tactics instead of individual cover-hopping.
* **Reuse.** Slots/routes in `SquadControl`, `CombatBrain` cover search and `react_target`,
  `_on_shot` near-miss detection, contacts from INTEL-01.
* **Add.** `SquadState.teams` (two fire teams, persisted leader per team) and `SquadState.tactic ∈
  {NONE, BOUND, SUPPRESS, FLANK, WITHDRAW, DEFEND}` + target contact + timer; per-unit `suppression`
  value (aim/perception penalty, cover bias); `suppress_at` target in `_engage`; flank target point =
  90° offset at 60–100 m on a cover/terrain-valid cell; wedge formation. Tactics end on any player
  order and on loss of the contact. Squads that are **aboard a vehicle never run a tactic**.
* **Depends on.** INTEL-01 (contact), test-site repair for `--combat-ai-test` (limitation 10).
  **Risk.** Balance and tactic oscillation; tactic must not fight the operation task → tactic is
  entered/left only by the operation (or by contact when idle).
* **Validation.** Scenario A (two squads vs a defended position): suppression team fires without
  LOS, flank team reaches an offset point, withdrawal below strength; `combat-tactics`, `squad`
  regression; 50 v 50 `brain_update` within the old budget.
* **Done when.** Scenario A passes deterministically (seed) and a player-ordered squad is unaffected.
* **Visible.** Squads split, one pins the enemy while the other moves around.

### AI-STRAT-01 — strategic decisions and threat awareness
* **Objective.** Factions allocate forces across fronts for reasons the player can read.
* **Reuse.** `WarSim._decide`, `FactionProfile`, `StrategicRoutes`, contacts, the existing
  `last_decision` string.
* **Add.** Action-list scorer (attack / reinforce / defend / recover), strength estimates from contacts
  (replacing `value·4` for unseen garrisons), `FactionState.focus` with hysteresis, orderly FAILED exit
  (retreat to nearest owned objective instead of standing still), first threat/control influence layer on
  the 50 m grid (stamped from contacts and objective ownership).
* **Depends on.** INTEL-01. **Risk.** Oscillation; mitigated by focus bonus and cooldowns.
* **Validation.** Scenario I (multiple fronts); long autonomous war run vs SANDBOX-01B numbers.
* **Done when.** Reinforcement choices are explained in `last_scores`; no duplicate op on one objective.
* **Visible.** Faction reacts to a feint, falls back instead of dying in place.

### BASE-AI-01 — AI factions use the existing bases and logistics
* **Objective.** AI factions own real bases with stock and vehicles, recruit through barracks, acquire
  trucks/APCs from depots, and the player can see and attack that economy.
* **Reuse.** `BaseSim` (recruit, acquire, rules, `base_stock`, `summary`), `LogisticsSim`, `FacilityDefs`,
  `Inventory`, `StructureManager` build path, `SandboxSetup`.
* **Add.** (a) `SandboxSetup`: each AI HQ gets a base made with the *construction system* (HQ, barracks,
  supply depot, vehicle depot, magazine/fuel) and a seeded stockpile — generalising the player's
  `starter_given` rule to every faction; (b) `_update_reserves` recruits via `BaseSim.recruit` when a barracks
  exists (fallback: current behaviour), so reserves cost stock; (c) AI vehicle acquisition rule and the
  restock/refuel rules created for AI bases through `add_rule_*`; (d) a cached **readiness summary** per
  base (infantry free, vehicles by status/fuel, stock per item, free docks) with a version stamp, plus the
  FactionProfile supply-inflow rate (limitation 7); (e) optional reachability flood fill on base layout
  change (gate → service points) with feedback in the construction panel.
* **Depends on.** Nothing hard (can run after STRAT-01 or alongside). **Risk.** Sandbox balance (AI now
  spends stock); setup time; AI bases must pass the same layout checks as the player's.
* **Validation.** AI bases exist after sandbox setup and after load; stock decreases on recruit and
  conserves under `Inventory.transfer`; an AI faction with an empty magazine stops recruiting
  (precondition fails otherwise); `logistics persist`, `bases`, `sandbox persist`.
* **Done when.** All three factions have bases that `BaseSim.bases_of` returns and that appear on the map;
  the war runs on stock, not integers.
* **Visible.** Enemy bases with trucks and depots that can be raided; a starved faction slows down.

### AI-OPS-01 — coordinated operations with infantry, vehicles and supply
* **Objective.** An AI attack assembles at its base, mounts, travels as a convoy, dismounts short of the
  objective, assaults, holds, and returns or withdraws.
* **Reuse.** `OperationState` + `_update_operation`, `VehicleTransport.order_group`, `VehicleConvoy`,
  `VehicleSim.order_drive`, `SquadControl`, `LogisticsSim.order_resupply/refuel`.
* **Add.** `OperationState.plan` (task list: `assemble`, `mount`, `move`, `dismount`, `assault`, `hold`,
  `withdraw`, `return`, `resupply`; each `{kind, args, state, since}`; completed by observable
  conditions, saved as plain data), `elements` (roles: assault / transport / support / reserve), capability
  tags **derived from defs** (`VehicleDefs.passengers`, cargo; infantry), requirement matching in `_decide`
  with fallback to a foot march, define G7 (squad stays in its op while aboard; the op also holds the
  vehicle ids; player taking a vehicle or squad releases it), orderly withdraw/return tasks.
* **Depends on.** INTEL-01, SQUAD-01 (assault/hold tactics), BASE-AI-01 (vehicles and stock exist).
  **Risk.** Yard congestion (limitation 1); route-planning spikes (one route per element, not per squad);
  persistence of mid-plan state.
* **Validation.** Scenario B (mechanized and foot variants): mounted → convoy → dismount → objective
  owned; save/load mid-`move`; camera-away run = camera-near run (tier divergence metric); combined
  performance scenario (§7) first run.
* **Done when.** Scenario B passes in both tiers and an operation survives F5/F9 and a player taking its
  vehicle.
* **Visible.** AI convoys of trucks/APCs with infantry driving to the front.

### AI-VEH-01 — vehicle combat and combined infantry/vehicle behaviour
* **Objective.** Vehicles can be shot, fight back, and cooperate with infantry.
* **Reuse.** `LineOfFire._units_hit`, `CombatSim.request_fire` (single shot path), `VehicleSim.apply_damage`
  (already handles disabled/destroyed, passenger ejection, cargo remains), `WeaponDef`, `CombatBrain`.
* **Add (minimum interfaces).** (1) vehicle hit volumes (hull box + optional turret) in `_units_hit`, armour
  as a per-class damage multiplier, no ballistics; (2) `WeaponDef.suitability` per target class and
  `CombatBrain._candidates` scoring by it; (3) vehicle entries in the perception grid (`_ensure_grid` indexes
  soldiers only, `combat_brain.gd:651/685`) as *targets* and crews as *observers*; (4) APC remote weapon
  station: `WEAPON_*` marker + `WeaponDef` + crew entry; (5) `WarSim._on_unit_died` counts vehicle
  losses; (6) role rules in data (truck withdraws under fire, APC dismounts then supports at 100–200 m).
* **Depends on.** OPS-01 elements. **Risk.** Rifle-vs-armour balance; friendly-fire ray for larger hulls.
* **Validation.** Scenario C/D subset: rifle does ~no damage to APC, AT does; passengers eject on
  destruction; no friendly fire; `squad`, `combat`, `logistics bases` regression.
* **Done when.** A destroyed APC leaves a wreck with cargo and dismounted survivors under squad control.
* **Visible.** Ambushed convoys; APC fire support.

### AI-DEF-01 — coordinated base defence
* **Objective.** A threatened base defends itself rather than only its garrison.
* **Reuse.** Operation type with plan tasks (DEFEND_BASE), contacts, base readiness cache, `BaseSim`.
* **Add.** `occupy(defensive points)` using existing defensive structures, trucks withdraw to the inner yard,
  reinforcement requests to `_decide`, repair/refuel return tasks. Reservations (`FacilityTable`) only if
  docks are observed to deadlock.
* **Depends on.** OPS-01, BASE-AI-01 (+ VEH-01 for APC gate defence). **Validation.** Scenario E.
* **Done when.** A base attacked by a mixed force holds or reports why it fell.

### AIR-01 / AIR-02 — record-authoritative helicopters; transport, extraction, support
Unchanged from research §9/§10/§16: `UnitState.kind = AIRCRAFT` + `air` sub-record, kinematic `FlightSim`
owned by `WorldSim` (same step in both tiers), pad test, `DetailManager` per-kind radii. **New constraint
from LOGISTICS-01:** boarding, seats, cargo and `Inventory.transfer` for aircraft must reuse
`VehicleTransport`/`LogisticsSim` through a domain-agnostic "carrier" interface (`passengers`, `cargo`,
`occupants`), not a copy. Needs a helicopter asset milestone first (`docs/ASSET_STANDARD.md` markers).
AIR-02 adds `air_transport` plan tasks (takeoff / land / mount / dismount) and LZ scoring.

### AI-CA-01 — combined-arms operations
Integrates OPS-01 + VEH-01 + AIR-02: synchronised gates between elements, fire-support requests
(`SquadState.request`) answered by vehicles/aircraft, cross-domain replanning on element loss. Scenario H/L,
second combined performance run.

### BASE-AI-02 — AI base construction and expansion
Site scoring (50 m grid, road access, flat fraction via `check_building`, water, threat layer, supply
distance), small relative templates, validation (reachability flood fill from BASE-AI-01), placement through
`ConstructionState.add_*`. Depends on BASE-AI-01, STRAT-01. Scenario K.

### AI-INTEL-02 — spatial intelligence
Route-risk and supply-corridor layers on the 50 m grid, recon operations, interdiction, risk-aware vehicle
routing (`VehicleRouter` edge weights read the layer; the router stays a derived index). Also the place to
make the cross-country planner aware of trees/rocks if needed (limitation 2). Depends on INTEL-01, STRAT-01,
OPS-01.

## 6. Doctrine and risk tolerance (deferred, kept cheap)

Differences between North/South/East stay numbers in `FactionProfile` (aggression, threat ratio, commit
fraction, withdrawal threshold, supply reserve, preference for vehicles vs foot). Add a field when a
scenario needs it (STRAT-01: withdrawal threshold; OPS-01: vehicle preference and reserve stock; VEH-01:
stand-off distance). No doctrine class hierarchy before two factions demonstrably need different *logic*,
not different numbers.

## 7. Performance plan

Existing measurements (not repeated): vehicle step 0.33–0.38 ms per tick for 20 vehicles; brain 0.9–2.7 ms
at 282–362 soldiers; war update 53–89 µs avg with 7–9 ms route-planning spikes; driving the truck 6.5 ms
frame; 16× war reached 12.6× with 10 vehicles (CPU-limited) [REPORT: LOGISTICS-01 §8,
WORLD-INTEGRATION-03].

**Combined-arms performance scenario (`--ai-perf`, first run at OPS-01, again at CA-01):** 3 factions,
war running with ≥ 280 soldiers, ≥ 3 simultaneous AI operations of which one mechanized (8+ vehicles in
2 convoys), logistics rules active, player camera moving between near and far (≥ 10 tier changes of
vehicles with passengers), 1 min each at 1×, 4× and 8× compression. Report avg/p99/max frame, tick buckets
(`abstract, squads, war, brain, combat, vehicles`), route-planning max, and the accumulated requested-vs-reached
time compression. Budget: no frame > 33 ms at 1×, 8× reached, tick ≤ 2 ms avg. Mitigations already named
in the research: one route per element, `AStarGrid2D.jumping_enabled` test, HPA* only if needed.

## 8. How to start the next milestone without ambiguity

* Branch from `feature/integration-04` (worktree `../fractured-nations-<milestone>`).
* AI-INTEL-01 touches `WarState`, `WarSim._update_intel/_decide`, `CombatBrain._acquire/_on_shot`,
  map layer. It must **not** touch `scripts/vehicles/` or `scripts/logistics/`.
* Test set: `--sandbox-test --only war,persist,navigation`, `--squad-test`, the repaired
  `--combat-ai-test`, plus a new `--ai-test --only intel_*`.
