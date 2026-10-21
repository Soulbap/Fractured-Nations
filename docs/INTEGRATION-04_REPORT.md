# INTEGRATION-04 — logistics integration, architecture consolidation, AI roadmap alignment

Branch `feature/integration-04` (worktree `../fractured-nations-integration04`). Not merged into `main`.
No gameplay code was changed. Evidence tags: **[CODE]** read in this branch's source, **[TEST]** run in
the real game during this milestone, **[REPORT]** taken from an earlier milestone report and not re-run,
**[NOT VERIFIED]** assumption or not checked.

## 1. Repository state before integration

| Branch | Commit | Worktree | Relationship | Uncommitted work |
|---|---|---|---|---|
| `feature/world-integration-03` | `21e846a` | `../fractured-nations-integration03` | previous baseline | none |
| `feature/logistics-01-base-02` | `a251782` | `../fractured-nations-logistics01` | 8 commits on top of `21e846a` | none |
| `research/ai-architecture-01` | `4ad57ff` | `../fractured-nations-airesearch01` | 1 commit on top of `21e846a`, **docs only** (`docs/AI-ARCHITECTURE-RESEARCH-01.md`, +1 446 lines) | none |
| `feature/world-base-01` (main checkout) | `a541eee` | `fractured-nations` | ancestor of `21e846a`; old milestone branch | `project.godot` (main scene path, local), 2 untracked files in `docs/` — **left untouched** |
| `feature/unified-sandbox` | `6418b12` | `../fractured-nations-unified` | old baseline | modified road-generator/asset import files in that worktree — untouched |
| others (`asset-production-01`, `blender-skills-01`, `combat-tech-01`, `world-playtest-01`) | unchanged | own worktrees | history | none |

The reported state was verified, not assumed: both branches have `21e846a` as merge base, so the logistics
work and the research are independent (code vs one new doc file) and cannot conflict. `main` is still
`80c494a` (initial commit) and is not the integration target; the baseline chain is
`world-integration-03` → `integration-04`.

## 2. Approach and result

```
21e846a (world-integration-03) ──8 commits──▶ a251782 (logistics-01-base-02) ──┐
        └──1 commit──▶ 4ad57ff (research/ai-architecture-01) ───────────────────┴─▶ merge ─▶ feature/integration-04
```

* New branch `feature/integration-04` and worktree `../fractured-nations-integration04`, created from
  `a251782` so the checkout with uncommitted work was never used.
* `git merge --no-ff research/ai-architecture-01`: clean, one added file, **no conflicts**. All commits of
  both branches are preserved in the history. Nothing was rebased, no branch or worktree removed, nothing
  force-pushed.
* Changes made in this milestone (docs only): `docs/AI_ROADMAP.md` (new), this report (new),
  `CLAUDE.md` (baseline, vehicle/supply/base rules, AI layer rules), `README.md` (baseline pointer).
* Generated data (`worlds/ref_20km`, `scenes/world/ref_20km.tscn`, `.godot/`) was copied from the logistics
  worktree (git-ignored) so the game could run.

## 3. Verified logistics architecture [CODE]

Every ownership claim of the LOGISTICS-01 report was checked against the source.

| Claim | Result |
|---|---|
| `WorldState` authoritative for persistent entities | **Confirmed.** Vehicles are `UnitState` records with a `VehicleState` (`veh`); `vehicle_id` on soldiers; logistics rules/convoys in `WorldState.logistics`; saved in `snapshot()` (`world_state.gd:314`). |
| `WorldSim` the central owner; `VehicleSim` no independent world | **Confirmed.** `WorldSim` owns `vehicles := VehicleSim.new(self)` and `logistics := LogisticsSim.new(self, vehicles)` (`world_sim.gd:29-31`) and ticks them in its own loop (`:153-154`), with a `vehicles` bucket in `tick_usec`. `VehicleSim`, `VehicleTransport`, `VehicleConvoy`, `LogisticsSim`, `BaseSim` are `RefCounted`, none has `_process`/`_physics_process`. |
| `VehicleBody` / proxy only present the record | **Confirmed.** `VehicleBody._physics_process` *sets its transform from the record* (`vehicle_body.gd:65-69`) and probes obstacles; the only simulation-side use of `has_body` is the physics probe (`vehicle_sim.gd:376`). |
| `RoadNetwork` is the road geometry; `VehicleRouter` derived | **Confirmed.** The router holds `net: RoadNetwork` and builds an `AStar3D` from `net.world` / `net.built` / `net.all_roads()`, re-indexing on `changed`; it defines no road. |
| `Inventory.transfer` authoritative for moving supplies | **Confirmed with a precision.** Movement between stores/vehicles goes only through `Inventory.transfer` (`logistics_sim.gd:422,449`). `Inventory.add/take` are used for **sources and sinks**: starting stockpile (`logistics_sim.gd:61`), fuel burn/refuel intake (`:413`), soldier resupply (`:543`), recruit/acquire cost payment and refund (`base_sim.gd:231,245`). That is consistent with "no supplies appear or vanish between stores", but any AI economy (inflow, raids) must also be a named source/sink — recorded in CLAUDE.md. |
| Base and facility state in the existing construction/persistence architecture | **Confirmed.** `ConstructionState.bases` (+`next_base`) in the construction JSON, `StructureState.base_id/inventory/facility`. |
| Near/far does not duplicate, reset or independently simulate | **Confirmed in code**: `VehicleSim.update` advances every vehicle record regardless of body; aboard soldiers are excluded from the abstract step (`world_sim.gd:148`), `CombatBrain` grids (`combat_brain.gd:261,289,651,685`) and `SquadControl._active_members`. **[REPORT]** `veh_tiers`, `transport`, `persist_logistics` test it; see §8 for what was re-run. |

Capabilities listed in the brief (vehicles, transport, logistics, bases) all exist as classes under
`scripts/vehicles/` (8 files, 2 558 lines) and `scripts/logistics/` (4 files). **Differences from the report:** none
in ownership. Additional facts the AI work needs and the report did not state, found while reading:

1. **AI factions have no logistics economy.** The scenario stockpile is given to the *player's* first supply
   depot only (`logistics_sim.gd:_on_structure_added`); `SandboxSetup` builds HQ perimeters for the AI factions,
   not depots, barracks or vehicles; `WarSim._update_reserves` spawns squads from an integer `reserves` with
   no inventory cost. (Roadmap gap G1 → BASE-AI-01.)
2. **`order_transport` does not touch the squad's `OperationState`.** Only RTS player orders call
   `WarSim.release_squads`. Aboard soldiers are safely ignored by `SquadControl`, but an AI operation that
   mounts its own squads must define ownership explicitly. (G7 → OPS-01.)
3. **`WarSim.known` is omniscient within 400 m and not saved**; vehicles are invisible to `CombatBrain`. (G2, G3.)
4. `BaseSim.summary` is computed on demand; there is no readiness cache. (G8.)

## 4. AI architecture reconciled with logistics

The research' layering holds on the real code and needs no change. What changed is the *interface map* —
the research assumed plan names; [AI_ROADMAP.md §2](AI_ROADMAP.md) now lists the implemented calls
(`VehicleSim.order_drive/order_group`, `VehicleTransport.order_transport/order_group/unload`,
`VehicleConvoy.order_convoy`, `LogisticsSim.order_*`, `BaseSim.recruit/acquire_vehicle/summary/add_rule_*`,
`StructureManager.check_building` + `ConstructionState.add_*`) and the vehicle fields the strategic and
operational layers can read. Consequences recorded there:

* **Strategic AI** evaluates `BaseSim.summary`/`base_stock`, vehicle records and `Inventory` totals; no
  strategic logistics simulation. Transport capacity = `VehicleDefs.Def.passengers` of parked, fuelled vehicles.
* **Operational AI** composes existing orders into a persisted task list; the transport hand-over rule is
  defined in OPS-01 (squad stays in its operation while aboard).
* **Tactical AI** evolves inside `SquadControl`/`CombatBrain`; squads aboard never run a tactic. **FLANK** is
  part of AI-SQUAD-01 (tactic `FLANK`, offset point at 90° / 60–100 m from the contact axis, one fire team
  supressing while the other moves).
* **Vehicle combat** minimum interfaces for AI-VEH-01: hull hit volumes in `LineOfFire._units_hit`;
  `VehicleSim.apply_damage` (exists); `WeaponDef.suitability`; vehicles in the `CombatBrain` grid as targets and
  crews as observers; `WEAPON_*` marker for the APC station; `WarSim._on_unit_died` counting vehicle losses.
* **Base AI** extends `BaseSim`/`FacilityDefs`; there is no AI-only base model.

## 5. Known limitations and what they block

Full table with reasoning in [AI_ROADMAP.md §4](AI_ROADMAP.md). Summary:

| # | Limitation | Class |
|---|---|---|
| 1 | AI vehicles clip/queue in crowded yards (confirmed again in this run, §8: a parked vehicle on a road stalled another) | dependency of OPS-01; watch |
| 2 | Cross-country routes ignore trees/rocks | safe for now (INTEL-02 if needed) |
| 3 | Infantry cannot damage vehicles | blocker of AI-VEH-01 only |
| 4 | APC weapon station missing | blocker of AI-VEH-01 / CA-01 |
| 5 | Combined-arms combat | dependency (needs 3, 4, OPS-01) |
| 6 | Placeholder facilities (training, ranges) | safe for now |
| 7 | No income/production | dependency of BASE-AI-01 (seeded stock + explicit HQ inflow) |
| 8 | No route preview | presentation; done in OBS-01 |
| 9 | Combined performance unmeasured | measure at OPS-01 and CA-01 (scenario in roadmap §7) |
| 10 | `--combat-ai-test` precondition failure | repair test site search before SQUAD-01 |

No genuine blocker for **AI-INTEL-01**. No critical integration defect was found, so no code was changed.

## 6. Updated roadmap

[AI_ROADMAP.md](AI_ROADMAP.md) §5 gives, per milestone: objective, reuse, additions, dependencies, visible
improvement, risks, validation, completion criteria. Order:

`AI-INTEL-01 (+AI-OBS-01)` → `AI-SQUAD-01` → `AI-STRAT-01` → `BASE-AI-01` → `AI-OPS-01` → `AI-VEH-01` →
`AI-DEF-01` → `AIR-01` → `AIR-02` → `AI-CA-01` → `BASE-AI-02` → `AI-INTEL-02`.

Deviations from the proposed order, each justified by code: OBS-01 merged with INTEL-01 (contact overlay is its
first consumer); **BASE-AI-01 before OPS-01** because AI factions have no depots, stock or vehicles (§3.1);
the vehicle hit model may be pulled ahead of OPS-01 if needed. Helicopter boarding/cargo must reuse
`VehicleTransport`/`LogisticsSim` through a carrier interface instead of copying them.

## 7. Documentation

`CLAUDE.md`: baseline changed to `feature/integration-04`; rules added for vehicle/supply/base ownership
(`Inventory.add/take` vs `transfer`, aboard soldiers) and for the AI layers. `README.md`: one paragraph pointing to
the roadmap and this report. The research report was *not* copied; the roadmap links to it.

## 8. Tests and checks actually performed

Policy: change-impact testing. The integration merged **documentation only** into a tree whose code is
byte-identical to the already-tested `a251782`, so no code-level regression is possible from the merge itself; the
runs below check that the integrated worktree (fresh worktree, copied world data, re-import) still builds and
runs the systems the AI work will stand on. Not run: the 7-minute `scenario`, `convoy`, `transport`, `veh_drive`,
`logistics`, stress or performance tests (no evidence of regression), `--sandbox-test` full suite.

| Run | Why chosen | Result |
|---|---|---|
| `godot --headless --import` on the new worktree | scripts compile, resources load | OK (only the usual exit-time "resources still in use" notice) |
| `--logistics-test --only veh_tiers,transport_cancel,bases,persist_logistics` | near/far transition with a vehicle, passenger cancel/reassign, bases/recruit/acquire, F5/F9 persistence with soldiers aboard | `persist_logistics` **PASS** (0 diffs, 8 hidden aboard, convoy and truck job finished after load); `transport_cancel` **PASS**; `bases` **FAIL** in this chain, `veh_tiers` **FAIL** in this chain — see below |
| `--logistics-test --only bases` (isolated) | order dependence of the failure | **PASS** |
| `--logistics-test --only veh_tiers` (isolated) | order dependence of the failure | **PASS** (arrived 1.1 m from target, 3 tier changes, 0 teleports, longest stall 0.05 s) |

Analysis of the chain failures [TEST]:

* `bases: recruiting without supplies was allowed`. The refusal itself worked; the reason string was "No personnel
  left in reserve (0)" instead of the expected "Not enough supplies". In the reduced chain `persist_logistics` runs
  first and its recruit consumes the faction's personnel reserve, so the check hit the reserve limit before the
  supply limit. A test-order dependency (the check does not reset `FactionState.reserves`), not a defect. The
  isolated run passes.
* `veh_tiers: did not arrive`. Tier changes (3), teleports (0) and the abstract/body flags passed. The truck sat
  164 m from its target "waiting / Stuck: reversing" for 30 s on the shared test route. In this chain vehicles from
  `bases`/`transport_cancel` remain parked in the same area. This is the already documented limitation
  (§5 #1: parked vehicles on roads are avoided only by cross-country legs, no negotiation); in the original full
  order `veh_tiers` ran last with a clean area. Isolated result: passes (table above).
* Both tests should reset shared state (`FactionState.reserves`, leftover vehicles) at their start; that is a small
  test-isolation task for the next milestone that touches `logistics_selftest.gd`, not done here to keep this
  milestone docs-only.

Visual inspection: this run's `--shots` captured the base, the RTS overview and the map with the logistics
reference images unchanged in git (the run overwrote them; they were restored from git, so the committed images are
the LOGISTICS-01 originals). The brief's wider visual list (player driving, boarding, RTS and map usability) was
**not** re-inspected by eye in this milestone; it rests on LOGISTICS-01 `[INSPECTED]` screenshots and `scenario`
**[REPORT]**.

## 9. Remaining risks

1. Test isolation inside `logistics_selftest.gd` (above) makes partial chains misleading; use `--only` with a single
   check or fix the resets.
2. AI factions have no logistics economy (G1) — OPS-01 cannot be built before BASE-AI-01.
3. Removing the omniscient `known` table (INTEL-01) will change war balance; baseline numbers from
   WORLD-SANDBOX-01B must be compared before and after.
4. Yard congestion for AI assembly points (limitation 1).
5. `--combat-ai-test` is broken by a terrain-tied precondition; SQUAD-01 needs it.
6. Combined performance (WarSim + combat + vehicles + logistics) has never been measured together.
7. The main checkout still has local uncommitted changes (`project.godot` main scene path) and unrelated untracked
   docs; they were intentionally left alone.

## 10. Recommended next milestone

**AI-INTEL-01 (with AI-OBS-01):** it has no unmet dependency, touches only `WarState`, `WarSim` intel/decision code,
`CombatBrain` acquisition and the map layer (not vehicles or logistics), removes the largest believability defect
(omniscient and unsaved knowledge), and gives every later milestone (SQUAD, STRAT, OPS, VEH, DEF) its shared contact
picture and its debugging overlay. Start from `feature/integration-04`.
