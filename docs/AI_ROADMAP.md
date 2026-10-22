# AI roadmap — consolidated after INTEGRATION-04, updated after AI-INTEL-01 / AI-OBS-01 and AI-SQUAD-01

Single planning document for the AI milestones after LOGISTICS-01. It merges
[AI-ARCHITECTURE-RESEARCH-01](AI-ARCHITECTURE-RESEARCH-01.md) (the *why* and the technique
comparison — not repeated here) with the code that actually exists on
`feature/integration-04` (LOGISTICS-01 / BASE-02 verified, see
[INTEGRATION-04_REPORT.md](INTEGRATION-04_REPORT.md) §4). Where the research assumed the
LOGISTICS-01 *plan*, this document uses the *implemented* names.

**Status (NAVIGATION N1-B, 2026-10-23).** N1-B (vehicle routing, base access, off-road clearance, soft links, plan caches) is
complete: see [NAVIGATION-N1B_REPORT.md](NAVIGATION-N1B_REPORT.md) and §8. The next milestone is N1-C (bridges, tracked
profiles), waiting for product-owner approval.

**Earlier status (NAVIGATION N1 baseline, 2026-10-22).** All AI milestones up to AI-WAR-LOGISTICS-01 are on the single
development branch `develop` in the one project folder. NAVIGATION N1 measurement, diagnostics and acceptance
scenarios are complete; navigation implementation is waiting for product-owner approval. See
[NAVIGATION-N1_REPORT.md](NAVIGATION-N1_REPORT.md) and §8.

**Earlier status.** AI-INTEL-01 and AI-OBS-01 are **done** (branch `feature/ai-intel-01`, report
[AI-INTEL-01_OBS-01_REPORT.md](AI-INTEL-01_OBS-01_REPORT.md)): factions hold a persistent, aging contact
picture built from reports; strategic decisions read it; the map shows it and a developer inspector explains
decisions and squads. **AI-SQUAD-01 is done** (branch `feature/ai-squad-01`, report [AI-SQUAD-01_REPORT.md](AI-SQUAD-01_REPORT.md)): fire teams, suppression, DEFEND / SUPPRESS / ASSAULT / FLANK / BOUND / REPOSITION / WITHDRAW / REGROUP, tactical RTS orders, four cover props. Everything else below is still planned. Next recommended: **AI-STRAT-01**.

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
| G2 | ~~No faction-level contact model.~~ **Resolved (AI-INTEL-01):** `WarState.contacts` / `IntelSim`; the omniscient `known` table is gone. Still open from it: `CombatBrain` indexes soldiers only, so vehicles cannot yet be *targets or observers* (the contact schema already has `Kind.VEHICLE`). | `intel_sim.gd`, `combat_brain.gd:_ensure_grid` | done; vehicle observation/targeting in AI-VEH-01 |
| G3 | **Vehicles cannot be hurt by weapons.** `LineOfFire._units_hit` has soldier hit volumes only; `VehicleSim.apply_damage(id, amount, source)` is the existing hook (destruction, passenger ejection, cargo stays are tested through it). `WarSim._on_unit_died` ignores vehicles. | `line_of_fire.gd`, `vehicle_sim.gd:113` | AI-VEH-01 |
| G4 | **No capability tags.** Squads/vehicles are matched by `kind`/`type_id`; `VehicleDefs.Def` has `passengers`, cargo capacity, fuel, speeds but no role/weapon data; `FacilityDefs` has the facility table but `StructureDef` carries no capabilities or service points. | `vehicle_defs.gd`, `facility_defs.gd` | OPS-01 (units: derive from defs) / BASE-AI-01 (facilities: extend `FacilityDefs`, not a second table) |
| G5 | **Operations are single-echelon, squad-only.** One route + one ENGAGING order for every squad; no assembly gate, no mount/dismount, no withdrawal except FAILED-by-losses (squads stay where they are). | `war_sim.gd:_update_operation` | OPS-01 |
| G6 | ~~Squad tactics are minimal~~ **Resolved (AI-SQUAD-01).** Was: **Squad tactics are minimal** (Move/Hold/Follow/Regroup + per-soldier cover reaction). No fire teams, suppression, flank, bound, withdraw. | `squad_control.gd`, `combat_brain.gd:_tactics` | SQUAD-01 |
| G7 | **Operation ↔ transport hand-over is not defined.** `order_transport` does not release a squad from its `OperationState`; only RTS player orders do (`rts_controller.gd:476`). An AI operation that mounts a squad must keep ownership consistent itself. | `vehicle_transport.gd` (no `release_squads`/`op_id`) | OPS-01 (define: squad stays in its op while aboard; op owns the vehicle element) |
| G8 | **Bases are named groups, not services.** No reservation of docks/parking, no readiness cache, no reachability check for service points; dock slots are retried on conflict (`dock_world`, `parking_world`). | `logistics_sim.gd`, `base_sim.gd:summary` | BASE-AI-01 (cache) / DEF-01 (reservations only if contention is observed) |

### Gaps found by AI-INTEL-01 / AI-OBS-01

| # | Gap | Evidence | Resolved in |
|---|---|---|---|
| G9 | **Strength estimates are approximate.** A sighting reports the number of enemy soldiers within 25 m of the sighted one (with ±20 % noise per observer) and the table keeps the best estimate of the last few seconds; the number of soldiers a squad actually *saw* is not tracked. Good enough for reinforcement sizing (24 visible → "about 20-21"), not for composition. | `combat_brain.gd:_group_near`, `intel_sim.gd:_report_seen` | INTEL-02 / OPS-01 (composition by kind when vehicles exist) |
| G10 | **Investigation is a one-squad MOVE operation** (`OperationState.contact_id`): the squad walks to the reported position and the contact is weakened if nothing newer was seen. No stand-off, no recon task, no vehicle. | `war_sim.gd:_investigate` | OPS-01 (`recon` plan task) |
| G11 | ~~Squads do not use contacts yet.~~ **Resolved (AI-SQUAD-01):** `SquadTactics` reads `IntelSim.contacts_near` and what its soldiers see. Was: **Squads do not use contacts yet.** `SquadControl` and `CombatBrain._tactics` still react only to what a soldier sees; `_share_contact` (squad mates turn to look) remains. `IntelSim.contacts_near` and the FIRE contacts are the inputs SQUAD-01 needs. | `combat_brain.gd:_share_contact` | SQUAD-01 |
| G12 | **Only combatants report.** No scouts, observation posts or sensors; a faction with no soldier near an enemy knows nothing, so AI attacks against unseen garrisons still assume `value · 4` defenders. | `war_sim.gd:_decide` (`basis: assumed`) | INTEL-02 (recon operations) |
| G13 | **No faction-level hearing of far events.** Hearing is per idle soldier within 150 m and creates a wide HEARD contact; explosions and vehicle noise do not exist yet. | `intel_sim.gd:report_heard` | VEH-01 (vehicle engine/weapon sounds feed the same call) |

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
| 10 | `--combat-ai-test` precondition failure (site search tied to old terrain) | **Diagnosed in AI-INTEL-01, not repaired** | The strict "meadow" (slope ≤ 4°, ≤ 4.5 m relief within 50 m, ≤ 4 trees in 70 m) no longer exists on the corrected terrain. Relaxing it lets the suite start but then fails identically on the untouched INTEGRATION-04 baseline (no shots in the symmetric fights on the substitute site), so the relaxed search was reverted rather than leave misleading downstream failures. The suite runs in the legacy layout (no war); port its scenarios to the sandbox layout in the `--ai-intel-test` style at the start of SQUAD-01. |

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

### AI-INTEL-01 — persistent faction intelligence (+ AI-OBS-01) — **DONE**
* **Delivered.** `ContactState` / `WarState.contacts` / `IntelSim` (owned by `WarSim`); reports from
  `CombatBrain` (sight, gunfire heard, fire taken) and from soldiers holding an objective an enemy stands
  in; 3 s (sight) / 6 s (sound) delay; merge by unit identity and proximity; confidence decay, growing
  uncertainty, OBSERVED → REPORTED → STALE → LOST; saved with the war; `WarSim.known` removed; strategic
  decisions use `threat_near`; stale reports near own ground are investigated by one squad; the map shows
  the player's picture; the **I / T** developer inspector shows any faction's picture, last decisions
  (`FactionState.decisions`, bounded runtime snapshots) and any squad's reason.
* **Kept for later milestones.** The inspector is a map overlay; the F4 soldier card is unchanged. Plan
  and element panels belong to OPS-01; influence layers to STRAT-01 / INTEL-02.
* **Open items** are gaps G9-G13 above.

### AI-SQUAD-01 — fire teams, suppression, flank, bound, withdraw, defend — **DONE**
* **Delivered.** `SquadState.teams` / `tactic*` (saved), `SquadTactics` + `SquadPositions`, suppression and fire missions in
  `CombatBrain`, terrain-chosen formations, tactical RTS orders (Z K L J Backspace, Shift+RMB, bar, F7 overlay), attack
  operations assault with the tactics, four cover props, `--ai-squad-test` / `--squad-demo`. Differences from the plan below:
  tactics are a squad record + engine, not only a `tactic` enum; the flank point is a terrain- and exposure-checked route,
  not a 90 degree offset; the choice is scores with recorded reasons.
* **Open items.** Vehicles as targets (AI-VEH-01); prone / crouch for pinned soldiers; smoke; balance of dug-in defenders;
  the AI never attacks without an operation (STRAT-01 / OPS-01 decide when).
* **Original plan (kept for reference).**
* **Objective.** Firefights show recognisable infantry tactics instead of individual cover-hopping.
* **Reuse.** Slots/routes in `SquadControl`, `CombatBrain` cover search and `react_target`,
  `_on_shot` near-miss detection, contacts from INTEL-01.
* **Add.** `SquadState.teams` (two fire teams, persisted leader per team) and `SquadState.tactic ∈
  {NONE, BOUND, SUPPRESS, FLANK, WITHDRAW, DEFEND}` + target contact + timer; per-unit `suppression`
  value (aim/perception penalty, cover bias); `suppress_at` target in `_engage`; flank target point =
  90° offset at 60–100 m on a cover/terrain-valid cell; wedge formation. Tactics end on any player
  order and on loss of the contact. Squads that are **aboard a vehicle never run a tactic**.
* **Depends on.** INTEL-01 (done), porting the combat-ai scenarios to the sandbox layout (limitation 10).
  **Risk.** Balance and tactic oscillation; tactic must not fight the operation task → tactic is
  entered/left only by the operation (or by contact when idle).
* **Validation.** Scenario A (two squads vs a defended position): suppression team fires without
  LOS, flank team reaches an offset point, withdrawal below strength; `combat-tactics`, `squad`
  regression; 50 v 50 `brain_update` within the old budget.
* **Done when.** Scenario A passes deterministically (seed) and a player-ordered squad is unaffected.
* **Visible.** Squads split, one pins the enemy while the other moves around.

### AI-WAR-LOGISTICS-01 — autonomous warfare with bases, economy, transport and a verified road network — **DONE** (with limitations)
* **Delivered.** AI bases (compound, income ledger, recruitment, vehicle depots), mechanised operations (ASSEMBLE, MOUNT,
  TRANSIT as convoys, DISEMBARK) with foot fallbacks, readiness and resupply, counterattacks, a logistics-aware strategic
  scorer, the near/far movement-speed fix, and a road audit (`--road-audit`, overlay F8) with the corrections it led to:
  graph gap repair, bridging of blocked road stretches, right-hand lane, off-road vehicles, run-time obstacle bypass and
  three-point-turn recovery, validated parking spots, open gates in the HQ perimeters. Report:
  [AI-WAR-LOGISTICS-01_REPORT.md](AI-WAR-LOGISTICS-01_REPORT.md).
* **Open items.** Faction logistics inspector panel and route/convoy overlays; trees and rocks in the cross-country planner;
  VehicleRouter rebuild spike after construction (~130 ms); a full-war performance run after the final road changes; visual
  boarding/convoy sequence; Kvernes and Elvetun are not truck-enterable.

### AI-COMBAT-STRAT-01 — coordinated operations and strategic decisions — **DONE** (replaces AI-STRAT-01 below)
* **Delivered.** Attack operations use the squad tactics by default and run as one operation with roles and stages
  (`OpCoordination`); an operation can withdraw to a fallback point under cover and release its squads;
  `StrategicDecision` scores attack / reinforce / join / garrison / recover with labelled intelligence, a reserve
  and focus hysteresis; `StrategicInfluence` is the threat layer (route risk); garrisons take sectors with a local
  reserve; the inspector shows stages, roles, forces and every candidate action with its utility. Report:
  [AI-COMBAT-STRAT-01_REPORT.md](AI-COMBAT-STRAT-01_REPORT.md).
* **Open items.** Crouch / prone, counterattack from the defence reserve, smoke, vehicles in operations
  (AI-OPS-01 / AI-VEH-01), an operation that retakes a lost objective after recovering, balance of the approach march
  on the 20 km map (an attack takes about 20 simulated minutes to arrive).

### AI-STRAT-01 — strategic decisions and threat awareness (done by AI-COMBAT-STRAT-01, kept for reference)
* **Objective.** Factions allocate forces across fronts for reasons the player can read.
* **Reuse.** `WarSim._decide`, `FactionProfile`, `StrategicRoutes`, contacts (`IntelSim.threat_near`,
  `contacts_near`), the decision snapshots (`FactionState.decisions`: threats, scored candidates with
  `basis` reported / assumed / none, chosen reason), the `OperationState.reason` strings.
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

## 8. NAVIGATION N1 hand-off

### N1-A implementation (2026-10-22)

* **Complete on `develop`.** Abstract infantry now uses bounded 5 m local route refinement only when a
  direct step meets an obstacle. One search is budgeted per physics tick, a successful corridor is shared
  by the squad, retries are bounded, and a closed route reports its reason instead of crossing geometry.
* **Member recovery.** `SquadControl` tracks meaningful progress per soldier and gives a stalled member one
  controlled retry while pausing for Hold, transport, possession and tactical reactions. The leader can no
  longer hide a permanently stranded member.
* **Parity verified.** N1-02, N1-08 and N1-09 now pass with 8/8; near -> far, far -> near and save/load keep
  orders without teleportation. Vehicle N1-03/04/05 remain green and N1-06 remains unsupported by design.
* **Scope choice.** `VehicleRouter` remains unchanged. N1-A uses a small profile-neutral infantry adapter
  patterned on its bounded local grid; vehicle migration, dynamic bridges, vegetation costs and tracked
  profiles remain N1-B/N1-C work. Full evidence: [NAVIGATION-N1A_REPORT.md](NAVIGATION-N1A_REPORT.md).

* **Baseline complete.** `--navigation-n1-test [--only n1_01,...,n1_09]` provides nine isolated,
  deterministic acceptance scenarios and writes diagnostics only below `user://navigation_n1/`.
  Runtime counters now distinguish route failure reasons, graph builds/rebuilds, vehicle bypass attempts,
  squad route stalls and stalls while reacting. They do not change planning or movement.
* **Measured defect.** The same 16.1 m gate is reliable near the camera (7/8 at the goal, maximum stall
  0.3 s) but not in the abstract tier (6/8, two remain about 47 m away, maximum stall 522.2 s). The closed
  perimeter remains blocked in both tiers and no sampled unit penetrates a structure. This reproduces and
  narrows the older `base_nav` failure: `WorldSim._free_direction` is local wall sliding, not pathfinding;
  `SquadControl` watches only the leader, so stranded formation members do not trigger a route replan.
* **Vehicle baseline.** Runtime local bypass, distinct truck/APC route costs and a three-vehicle bridge
  convoy work. Selectively disabling one bridge is unsupported because bridges are inferred geometry, not
  route entities. The road audit currently finds 18 components and 294 failures in 2604 location/profile
  requests; the legacy yard/exit reproduction still exposes blocked service approaches.
* **Implementation order after approval.** (1) extract the existing 3 m local search behind one profile-
  driven interface; (2) use one squad-level local corridor for abstract infantry while retaining near-tier
  `NavigationAgent3D`; (3) unify passability/profile inputs and dirty-region versioning for structures and
  roads; (4) add explicit wheeled/tracked profiles and only then vegetation costs; (5) harden service-point,
  convoy and bridge constraints; (6) repeat the nine scenarios plus targeted regressions and performance.
  Bridge destruction remains outside N1 until a persistent bridge entity is designed.
* **Guardrails.** Extend `StrategicRoutes`, `RoadNetwork`, `VehicleRouter`, `VehicleSim`, `SquadControl`,
  `WorldSim`, `SoldierBody` and `AreaNavigation`; do not add a competing navigation engine. No HPA*, flow
  fields or global per-unit searches without measured need. Do not begin implementation without explicit
  product-owner approval. Full findings and acceptance criteria: [NAVIGATION-N1_REPORT.md](NAVIGATION-N1_REPORT.md).

### N1-B implementation (2026-10-23)

* **Vehicle base access.** All 24 dock/parking spots of the AI bases now leave and re-enter (baseline 23/24). The faults were
  clearance (a straight leg and a spline 1.9 m from a depot corner, lane shifts into structures, unchecked joins), a false
  "arrived" 43 m from a dock, and a reverse that swung into walls. `VehicleSim` follows a route in reverse when it lies behind
  a closed front.
* **Off-road.** Trunks, rocks and settlement colliders (`StructureManager.blocks_trunk`) are hard obstacles for planning;
  clearance tiers and a continuous line check replace the cell-centre test; trucks and APCs keep their distinct profiles.
* **Road connectivity.** Short links from isolated streets to another component are planned per vehicle at route time (soft
  links), never added to the graph. Audit failures 294 -> 104, unexplained 180 -> 2; the rest are steep isolated villages.
* **Performance.** Plans avg 127 -> 57 ms, p99 326 -> 162 ms; yard bursts 427 -> 61 ms. Open: village starts in dense woods
  (~290-430 ms) and the one-off vegetation cache rebuild after a structure change.
* **Tests.** `--navigation-n1b-test` (N1B-01..10). Evidence and the order-dependent suites: [NAVIGATION-N1B_REPORT.md](NAVIGATION-N1B_REPORT.md).
