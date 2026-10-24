# GAMEPLAY-01A — Gameplay Architecture Audit & First Playable Sandbox

Research only. Branch `research/gameplay-01a` (from `develop` @ `b9bbc3a`, UI-01C.1 merged). No gameplay code, scene,
asset or balance value was changed; the only file added is this report.

Evidence tags used throughout: **[RUN]** verified in a runtime run made for this audit (§9.3), **[TEST]** covered by an
existing automated scenario and its last recorded result, **[CODE]** code inspection only, **[UNVERIFIED]** not checked.

Product-owner addition received during the audit (2026-10-24): **the player should start in the south instead of the
north.** It is treated as a design requirement for New Game (§3, §8 D1) and its code impact is listed in §5 (G2).

---

## 1. Executive Summary

The project is **closer to a playable sandbox than its UI suggests, but further from a *New Game* than its feature list
suggests.** Almost every simulation system a first playable needs exists and runs on one record-centric world
(`WorldState` / `WorldSim`): squads with fire teams and tactics, perception-driven combat, faction intelligence,
coordinated operations, capture of objectives, bases with facilities, inventories, recruitment queues, vehicles,
convoys, transport, delivery jobs with repeat, and save/load of all of it. The current game starts straight into the
three-faction war without any debug setup [RUN], and the player can command squads in RTS and on the map, build a
base, recruit, acquire trucks and run deliveries through the real UI [TEST].

What is missing is mostly **the connections between these systems that turn them into a loop with stakes**:

1. **No game start configuration.** `SandboxSetup` hard-codes one scenario (North = player with 5 squads + 32
   reserves, AI bases for South/East). There is no main menu, no New Game, no scenario choice, no "load on start"
   except a developer flag. The player faction is hard-coded to 0 (North) in a few places (§5 G2) — relevant to the
   new "start in the south" requirement.
2. **The player's economy has no scarcity and no source.** Player construction is free and instant
   (`ConstructionController` → `ConstructionState.add_building`); the first supply depot receives a large free
   stockpile (9 000 supplies / 4 000 ammo / 6 000 fuel, `FacilityDefs.START_STOCK`); the player gets free squads every
   240 s from reserves (`WarSim._update_reserves`); income (`WarEconomy.income`) exists **only for AI factions**.
   Nothing the player does on the map changes what they can build.
3. **Construction has no workers.** Buildings appear the moment they are clicked. The AI already has the right
   intermediate record — a paid, timed, persisted *pending build* (`WarState.builds`, `AiBases.request/update`) — but no
   soldier works on it either. Structures have **no health**: nothing can damage, repair or meaningfully capture a
   building (only `BaseSim.capture_base` flips faction ids when an objective changes hands).
4. **Defensive positions are not a concept.** `SquadTactics` DEFEND finds posts from generic cover candidates
   (`CombatBrain.cover_spots`: behind any structure instance, rock, tree, terrain fold). Guard posts are counted
   (`BaseSim.guard_posts`) but no code uses them; no structure declares firing positions, capacity or a tower platform;
   right-click on a structure is a plain move.
5. **Player bases are invisible to the war.** Bases are not `ObjectiveState`s, so AI factions never target, attack or
   capture a player base, and the player gets no warning about an approaching threat to it (BASE-01 §8 confirms).
6. **Recruitment does not replenish player squads.** Player recruits always form a new squad
   (`BaseSim._finish_squad`); only AI recruits fill depleted squads (`_fill_depleted`). Beds (`capacity`) are shown but
   not enforced.

None of these needs a new architecture. Each is a small extension of an existing owner (§4, §6). The shortest credible
path is: **scenario data + player faction choice → one abstract construction resource with income and pickups →
blueprint + automatic squad construction → structure condition and base-as-objective → defend-area manning →
replenishment.** Vehicles, helicopters and combined arms are not needed for that loop (§7).

**Combat observation (UI-01C.1, "own side fired little").** The evidence does not show a bug: the UI-01C.2 test that
produced it stops counting after the **first three shots** of either side (`ui01c2_selftest.gd:565`, loop ends when
`shots ≥ 3`), the enemy section was spawned *facing* the squad while the squad's facing was not set, and the possessed
soldier (`player_controlled`) is excluded from AI perception and firing. A symmetric 8 v 8 baseline was run for this
audit (§9.3) to check the general case. A small reproducible test is proposed in §9.4.

---

## 2. Current Gameplay Inventory

| System | Current implementation | Runtime evidence | Status | Main gap |
|---|---|---|---|---|
| Game start / entry | Main scene `world_ref_20km.tscn` → `CoreDemo._start_large_world` → `_start_sandbox` → `SandboxSetup.create` | [RUN] plain launch: 3 factions, 12 objectives, 15 squads, 120 soldiers, AI bases for South/East, no errors, RTS camera framed on North HQ | Functional (one fixed scenario) | No menu, no New Game, no scenario choice, no "continue" |
| Scenario configuration | `SandboxSetup.OBJECTIVES` / `FACTIONS` constants, `AiBases.START_LAYOUT`, `FacilityDefs.START_STOCK` | [CODE] | Prototype | Code constants, not data; one scenario only |
| Player faction | `WarState.player_faction` (saved), set to 0 in `SandboxSetup.create` | [CODE] | Partial | Faction 0 hard-coded in `CoreDemo` start, `TacticsOverlay.player_faction` never set (§5 G2) |
| Guidance | HUD short hints (`GameHUD`, F1 controls), war log (`WarSim.log_event`) | [TEST] UI-01C | Partial | No contextual "what next" guidance |
| Save / load | F5/F9: `WorldState.snapshot` (units, squads, war incl. ops/contacts/builds, logistics, bridges) to `world.json` + `ConstructionState.to_dict` to `construction.json`; one slot | [RUN] base01 persist; [TEST] `ai-war m_save`, `ai-strat j_persist`, `ai-squad k_persist` | Functional (in-session) | One slot, load only into a running war; start-from-save only via `--load-construction` |
| Resources | `Inventory` (ammo, fuel, supplies) on stores and vehicles; `BaseSim.base_stock/pay/refund` | [TEST] logistics | Functional | Three physical items; no single abstract construction resource for the player |
| Income | `WarEconomy.income` per owned objective value, AI only | [TEST] ai-war a_init/b_recruit | Partial | Player has no income at all |
| Construction costs | `AiBases.BUILD_COST` / `BUILD_TIME_S` (AI only) | [CODE] | Present but inaccessible | Player builds free and instant |
| Base establishment | Command Post founds a 150 m base (`BaseSim._on_added`, `placement_rule`) | [RUN] base01; [TEST] BASE-01 | Functional | — |
| Construction progress / workers | AI: `WarState.builds` timer; player: none | [CODE] | Missing (player) | No blueprint, no workers, no progress |
| Placement rules | `StructureManager.check_building` (slope, water, overlap, trees, groundwork), roads/bridges, base area | [RUN] base01; [TEST] BASE-01 | Functional | — |
| Structure damage / repair | none on `StructureState` | [CODE] | Missing | No health, no destruction, no repair |
| Structure capture | `BaseSim.capture_base` flips base + facility factions when an objective is captured (`WarSim._transfer`) | [CODE] | Partial | Only bases within 60 m of an objective; player bases never |
| HESCO / fortifications | `ModularLine` lines with snapping (`connect_group`, `snap_points`), cover props, guard tower | [TEST] WORLD-BASE-01, AI-SQUAD-01 | Functional (as obstacles/cover) | No firing positions, no capacity |
| Defend / posts | `SquadTactics` DEFEND, `SquadPositions.find_posts` from `CombatBrain.cover_spots` | [TEST] ai-squad a/d | Functional (generic cover) | Does not use structures as positions; guard posts unused |
| Right-click context | `RTSController.order_move_at`: friendly vehicle → board; else move | [CODE] | Partial | No structure/enemy context (man, attack) |
| Recruitment | `BaseSim.recruit` (320 supplies + 192 ammo + 8 reserves, 60 s), logistics panel button | [TEST] logistics bases (4 known failing checks, BASE-01 §6) | Functional | Player recruits never replenish; capacity unenforced; free reserve arrivals bypass it |
| Squad replenishment | AI only (`_fill_depleted`) | [CODE] | Partial | Not available to the player |
| RTS selection & orders | Click / box / Ctrl squad select, RMB move, Shift+RMB bound, Z/K/L/J/Backspace tactics, H hold, F follow, G regroup, V formation, Y ROE | [RUN] ai-squad g_player; [TEST] UI-01C | Functional | Not all reachable without keys (bar exists for tactics) |
| Squad tactics | Fire teams, suppression, DEFEND…REGROUP, owner precedence player > operation > squad | [RUN] base_fight / g_player; [TEST] AI-SQUAD-01 | Functional | Crouch/prone, smoke (AI-SQUAD-01 open items) |
| Combat / CombatBrain | Perception (FOV, terrain, vegetation, structures), acquisition, aim error, ammo, cover reactions | [RUN] base_fight | Functional | Vehicles cannot be hit (G3 of roadmap) |
| FPS possession | `GameController.possess`, Tab back, FPS HUD | [TEST] UI-01C.2 | Functional | — |
| Player operations | Strategic map: select squads → Attack / Defend / Reinforce / Move, cancel; `WarSim.start_operation(..., player=true)` with `OpCoordination` stages | [RUN] ai-strat i_player; [TEST] UI-01C.2 map operation | Functional | No mechanised transport for player ops (`mech.plan` skipped when `player_ordered`); no "operation from RTS" |
| Territory | 12 `ObjectiveState`s, presence-based capture (`WarSim._update_capture`, 90 s, ≥ 2 soldiers) | [TEST] sandbox / ai-strat | Functional | All objectives behave alike apart from `value`; no per-kind benefit |
| AI factions | `StrategicDecision`, `OpCoordination`, `WarEconomy`, `AiBases`, `OpTransport`, `WarLogistics` | [RUN] plain start; [TEST] ai-war o_war, ai-strat l_war | Functional | Never target player bases; limited base expansion |
| Logistics / vehicles | `VehicleSim`, `VehicleRouter`, convoys, transport, `LogisticsSim` jobs (load/unload/deliver repeat/refuel/repair), automation rules | [TEST] logistics, ai-war, N1-B/C1 | Functional | Not needed for the first loop |
| Reconnaissance | `IntelSim` contacts (observed → reported → stale → lost) on the map | [TEST] ai-intel | Functional (map) | RTS view shows every enemy body near the camera (no fog in 3D) |

---

## 3. First 30 Minutes — Player Journey

**Intended design (New Game)**, with the product owner's addition: the player starts **in the south** with one squad of
eight, no base, no vehicles and a small stock; AI factions are active elsewhere.

Verified current behaviour is marked **Now:**; everything else is the intended design.

### Stage 0 — Start (minute 0)
- **Required:** a "New Game" entry that creates a scenario with one player squad in a safe southern area, small stock,
  AI factions with their bases and forces elsewhere; "Development Scenario" still available; "Continue" from a save.
- **Now:** [RUN] the game always starts the development war: North (player) with 5 squads at North HQ / Elvetun / North
  Bridge, 32 reserves, a HESCO perimeter around North HQ; South and East AI with full bases and trucks.
- **Existing:** `SandboxSetup.create` (objectives, factions, squads, fortifications, AI start bases), `WarState.player_faction`,
  `FactionState.reserves`, `AiBases.create_start_base`, the save format.
- **Missing:** scenario data (which factions, who is the player, starting squads per place, reserves, starting stock,
  which bases), a start screen, faction-0 assumptions removed.
- **Blockers:** player-faction hard-coding (§5 G2); `SandboxSetup` also gives the player HQ objective a fortified
  perimeter — a New Game player should have none.
- **Simplest path:** turn `SandboxSetup.OBJECTIVES/FACTIONS` into two scenario dictionaries (or one `.tres`/JSON each)
  read by the *same* `create` function; pick with a small start screen and a `--scenario=dev|new` flag (dev stays the
  default for tests). §6 GAMEPLAY-01B.

### Stage 1 — Explore (minutes 0–5)
- **Required:** move the squad by RTS/map, see what is around (map, contacts), find something worth taking.
- **Now:** RTS tactical orders work [RUN `g_player`]; map move/attack orders work [TEST UI-01C.2, `ai-strat i_player` RUN]; the map shows objectives and the faction's
  contact picture; [CODE] in the 3D view every enemy body near the camera is visible regardless of what the faction knows.
- **Missing:** places that give something (supply caches, abandoned depots); a reason to explore. Objectives today are
  12 fixed places, all worth only `value` 1–3 for AI income.
- **Simplest path:** **supply caches** as data on the scenario (a position + an amount, drawn on the map as "reported" or
  discovered when a soldier sees it), collected by a squad standing in it — the same presence rule as objective capture
  (`WarSim._update_capture`) and `Inventory.add` as the explicit source. No new pickup system.

### Stage 2 — Secure resources (minutes 5–10)
- **Required:** the squad takes a cache / small objective and the faction's stock grows.
- **Existing:** objective capture, `WarEconomy.income` (per owned objective value, delivered to the main base store,
  ledgered in `FactionState.ledger`).
- **Missing:** income for the player; somewhere to put it before a base exists.
- **Simplest path:** enable `WarEconomy.income` for the player faction; while the player has no base, hold the stock as a
  faction-level pool (`FactionState`) and move it into the first store when one exists (one explicit `Inventory.add`,
  replacing today's free `START_STOCK` gift). §8 D3 discusses the pool.

### Stage 3 — First Command Post (minutes 8–12)
- **Required:** place a Command Post blueprint; the squad walks there and builds it; it costs most of the starting stock.
- **Now:** [RUN] B → Command Post → LMB places a finished CP instantly and free; base "North base 1" (150 m) is created.
- **Existing:** `ConstructionController`, `BaseSim.placement_rule`, base record, map ring.
- **Missing:** cost, blueprint state, workers, progress.
- **Simplest path:** the player pays from the faction pool / base stock (`AiBases.BUILD_COST` becomes the shared table
  with one *construction* cost per type) and a placed building is a **site** (a `StructureState` with
  `facility.build = {progress, work_s}`) instead of a pending record outside construction; see Stage 4.

### Stage 4 — Soldiers build (minutes 10–20)
- **Required:** idle soldiers walk to the site, work visibly, progress rises; danger and player orders interrupt.
  The squad stays the command unit.
- **Existing:** `SquadState.tactic*` with owners; posts (`UnitState.post_pos`) reached by ordinary move orders;
  `SquadTactics.on_order` releases a tactic on any player order; `CombatBrain` cover reactions near a post; the AI's
  timed build.
- **Missing:** a WORK activity, work posts round a footprint, progress accrual, a "work" pose/animation, idle-squad
  auto-assignment.
- **Simplest path:** one new tactic **BUILD** in `SquadTactics` (not a worker simulation): posts = points round the site
  footprint (`SquadPositions`-style ground checks), progress per second = soldiers within 3 m of their post that are not
  under fire (`suppression_at` / `under_fire_until`) × rate; owner SQUAD when auto-assigned (only to squads with
  `order NONE/HOLD`, no operation, no player tactic, inside the base area), owner PLAYER when ordered by right-clicking
  the site. Any player order ends it through `on_order` as today. Same code runs far from the camera (record only).

### Stage 5 — Barracks, defences, supply (minutes 15–25)
- **Required:** build barracks, HESCO/positions, depot; the squad mans the defences with **Defend Area**.
- **Existing:** all building types and HESCO lines; DEFEND tactic; guard posts counted.
- **Missing:** structures as defensive positions (firing points, capacity, tower platform), right-click to man.
- **Simplest path:** firing positions as **data on the `StructureDef`** (local points + facing, like `snap_points`; for
  modular HESCO one point per module side), offered to `SquadPositions.find_posts` as `structure` candidates with
  capacity 1 and reserved per squad (`_reserved` exists). Authored points in the asset defs, no runtime geometry.

### Stage 6 — Recruit and replenish (minutes 20–30)
- **Required:** barracks trains replacements that fill the depleted squad, then new squads; costs resource and time.
- **Existing:** `BaseSim.recruit` queue (cost, 60 s), `_fill_depleted` (AI).
- **Missing:** replenishment for player squads; capacity limit; removal of free reserve arrivals in New Game.
- **Simplest path:** a "Replenish" action on a barracks/at a squad standing in the base that queues *n* replacements into
  that squad (`_fill_depleted` for one chosen squad), and a scenario switch that turns off `_update_reserves` free
  arrivals for the player.

### Stage 7 — Defend and expand (minute 30+)
- **Required:** AI attacks arrive with warning; the player defends, then runs operations, takes objectives, opens a
  second base.
- **Existing:** AI operations, contacts, operations from the map, multiple bases per faction in the data.
- **Missing:** player bases as AI targets, warning on threat near a base, condition/damage of structures.
- **Simplest path:** each base registers an `ObjectiveState` (kind `base`, value from its facilities) when founded;
  AI decisions and capture then work unchanged; `IntelSim.threat_near` around player bases raises a war-log warning.

---

## 4. Architecture and Ownership Map

| Domain | Owner (record / system) | How new gameplay connects |
|---|---|---|
| World state | `WorldState` (units, squads, war, logistics, construction, roads) / `WorldSim` tick | Scenario data creates records only through existing calls |
| Scenario / start | `SandboxSetup.create` (called by `CoreDemo._start_sandbox`) | Becomes data-driven; New Game and Dev are two inputs to the same function |
| Factions & territory | `WarState.factions` (`FactionState`), `WarState.objectives` (`ObjectiveState`), capture in `WarSim._update_capture` | Bases register an objective; caches use the same presence rule |
| Squads & soldiers | `SquadState`, `UnitState`; `SquadControl` (orders, routes), `SquadTactics` (tactics, owners), `SquadPositions` | BUILD tactic and structure posts live here |
| Combat | `CombatSim` (shots, damage), `CombatBrain` (perception, firing, reactions), `LineOfFire` | Structure damage reads the same shot resolution (later) |
| Operations | `OperationState`; `WarSim.start_operation`, `OpCoordination`, `OpTransport` | Player ops already use them |
| Strategy (AI) | `StrategicDecision`, `IntelSim`, `StrategicInfluence`, `WarEconomy`, `AiBases`, `WarLogistics` | Player base objectives become candidates automatically |
| Construction | `ConstructionState` (structures, bases, clearings), `StructureManager` (placement, groundwork, collision, nav), `ConstructionController` (player input), `AiBases` (AI orders) | Sites + build cost; one path for player and AI |
| Resources | `Inventory` on stores/vehicles; `BaseSim.pay/refund/base_stock`; sources only via `Inventory.add` | Abstract construction resource = `supplies` (§8 D2) |
| Recruitment | `BaseSim.recruit/_finish_squad/_fill_depleted`, `FactionState.reserves` | Replenish for player |
| Logistics & vehicles | `VehicleSim`, `VehicleRouter`, `VehicleConvoy`, `VehicleTransport`, `LogisticsSim`, `BaseSim` rules | Unchanged for the first loop |
| UI | `GameHUD`, `RTSController`, `ConstructionPanel`, `LogisticsPanel`, `StrategicMap`, `TacticsOverlay`, UI kit | Start screen, cost/progress display, replenish button |
| Persistence | `WorldState.snapshot/apply_snapshot` (+ `WarState`, `LogisticsState`, roads) and `ConstructionState.to_dict` | Every new field goes on an existing record's `to_dict` |

Order of authority stays **player > operation > squad tactic > reaction**; BUILD and auto-manning are squad-tactic level
(owner SQUAD) unless the player ordered them (owner PLAYER).

---

## 5. Gameplay Gaps and Dependencies

Ranked by impact on the first playable. **B** = true blocker of a New Game loop, **I** = important, **P** = can wait.

| # | Gap | Class | Evidence | Depends on |
|---|---|---|---|---|
| G1 | No scenario selection / New Game; `SandboxSetup` constants | B | `sandbox_setup.gd:18-35`, `core_demo.gd:_start_sandbox` | — |
| G2 | Player faction hard-coded to 0: `SandboxSetup.create` (`war.player_faction = 0`, `FACTIONS[0]` player, log text "North (you)"); `CoreDemo._start_large_world` (`_first_soldier_of(0)`, `faction(0).hq_objective`); `TacticsOverlay.player_faction` (default 0, never assigned — would show North as "mine" if the player is South); `RTSController.player_faction` default 0 (assigned in `_start_sandbox`, fine) | B for "start in the south" | grep results §9.1 | G1 |
| G3 | Player economy free: free instant construction, free `START_STOCK`, free reserve arrivals, no player income | B | `construction_controller.gd:390`, `logistics_sim.gd:58`, `war_sim.gd:954-976`, `war_economy.gd:46-51` | G1 (scenario switch) |
| G4 | No construction sites / workers / progress | B | `ConstructionState.add_building` is the only player path | G3 (cost) |
| G5 | Player bases not objectives → no AI pressure, no warning, no capture | I (B for "defend the base") | `BASE-01_REPORT §8`, `WarSim._transfer` | — |
| G6 | Structures have no condition (damage/repair/capture-with-damage) | I | `structure_state.gd` has no health | G5 |
| G7 | Structures are not defensive positions; guard posts unused; no right-click man | I | `base_sim.gd:guard_posts` (no caller), `cover_spots` | — |
| G8 | Player recruits never replenish; capacity unenforced | I | `base_sim.gd:_finish_squad` comment | G3 |
| G9 | No reasons to explore (caches, per-kind objective benefits) | I | `SandboxSetup.OBJECTIVES` value only | G3 |
| G10 | Squad loss recovery for New Game (all soldiers dead) | I | `_update_reserves` is the only free source | G1, G3 |
| G11 | Player soldiers do not resupply ammunition automatically (manual `order_resupply` only; AI has `WarLogistics`) | P | `logistics_sim.gd:494`, `logistics_panel.gd:387` | — |
| G12 | 3D view shows all enemies near the camera (no fog in RTS) | P | no visibility filter in `unit_visuals` / RTS | — |
| G13 | Player operations never use vehicles (`mech.plan` skipped for player ops) | P | `war_sim.gd:563` | §7 |
| G14 | Vehicles cannot be damaged by weapons | P | `combat_sim.gd:111` soldiers only; `VehicleSim.apply_damage` has no weapon caller | §7 |
| G15 | Contextual guidance ("what next") | P | HUD hints only | G1–G4 |
| G16 | Known failing logistics checks (`--logistics-test --only bases,persist_logistics`: 4 checks, pre-existing) | P (fix when touching BaseSim) | `BASE-01_REPORT §6` | — |

Dependency chain for the loop: **G1 → G2 → G3 → G4 → (G7, G8) → G5 → G6**; G9/G10 attach to G3; G11–G16 are independent.

Cross-system risks checked (from the brief):

| Risk | Finding |
|---|---|
| Soldiers on construction disappearing from command | Avoided if BUILD is a squad tactic: members stay in `SquadState.members`, only `post_pos` changes. A per-soldier worker pool would break this — do not build one. |
| Defence assignments overriding player orders | `SquadTactics.on_order` already cancels tactics on every player order; auto-manning must be owner SQUAD and `_autonomy_ok`-gated. |
| Recruits not recognised by WarSim | Recruits come from `WarSim.spawn_squad/spawn_recruits` → `WorldState.add_squad`, the same path as starting squads. Safe. |
| Captured structures keep wrong faction | `capture_base` rewrites `StructureState.faction` and `bases[id].faction` [CODE]; HESCO lines outside a base keep their old faction (lines have no `base_id`). Note for G6. |
| Double resource deduction | `BaseSim.pay` is atomic; `cancel_queue` refunds once; `AiBases.update` refunds a failed site once [CODE]. A player site must pay once at placement and refund on cancel through the same calls. |
| Operation vs direct order conflict | RTS orders call `release_squads` via `_player_takes`; test `ai-war l_player` [TEST] and `ai-squad g_player` [RUN] cover it. |
| Save/load losing progress | Pending AI builds (`WarState.builds`), recruit queues (`facility.queue`), ops, contacts are saved [CODE/TEST]. Load order: `world.json` then `construction.json` (`ConstructionController.load_saved`); a site record must live in construction data, not in a runtime cache. |
| Player vs AI ownership rules | Same capture code for everyone; player bases are the exception (G5). |
| Near vs far | All proposed additions are record-only (posts, progress, objectives) so both tiers run them; only the work pose is a body concern. |

---

## 6. Proposed Implementation Roadmap

Five steps; the first four make the New Game loop, the fifth adds pressure. Each is one milestone of commits on `develop`.

### GAMEPLAY-01B — Scenarios, New Game and the southern start
- **Objective.** Two start configurations through one setup path; the player can be any faction; New Game starts in
  the south with one squad of eight.
- **Reuse.** `SandboxSetup.create`, `FactionState`, `AiBases.create_start_base`, `WarState.player_faction`, save format.
- **Minimum changes.** Scenario data (factions incl. player flag and profile, reserves, starting squads per place,
  fortified HQs, AI bases, starting stock) for `dev` (exactly today's) and `new_game`; `--scenario=` flag and a small
  start screen (New Game / Development Scenario / Continue); remove the faction-0 assumptions (G2); scenario id saved in
  `WarState` so Continue knows what it loaded; "Continue" = start the scenario's world then `load_saved()` (the existing
  `--load-construction` path).
- **Dependencies.** Decision D1 (which faction / where in the south).
- **Acceptance.** New Game: one 8-soldier squad of the player faction at the southern start, no base, no vehicles, the AI
  factions running; Development Scenario identical to today (same counts as §9.3 plain run); Continue resumes a save.
- **Verification.** New `--scenario-test` (start both, count squads/bases/vehicles, save → restart → continue);
  regression `--ai-war-test --only a_init`, `--base01-test --only persist`, `--ui01c-test --only checks`.
- **Out of scope.** Economy changes, workers, guidance text beyond one start line.

### GAMEPLAY-01C — One construction resource, costs and income for the player
- **Objective.** Building costs something; resources come from taking ground and caches.
- **Reuse.** `Inventory` `supplies` as the abstract construction resource; `BaseSim.pay/refund`; `AiBases.BUILD_COST` as
  the single cost table (extended to every player-buildable type); `WarEconomy.income`; objective capture.
- **Minimum changes.** Player construction pays (refused with reason when short; panel shows cost); New Game turns off
  the free `START_STOCK` gift and free reserve arrivals (scenario flags; Dev keeps them); player income enabled; a
  faction pool until the first store exists (D3); supply caches as scenario data collected by presence.
- **Dependencies.** 01B.
- **Acceptance.** New Game: the starting stock pays for a Command Post and little else; taking a cache or a village
  visibly raises the stock (war log + HUD); Dev Scenario unchanged.
- **Verification.** Targeted scenario: cost paid once, refund on cancel, income after capture, cache collected once,
  save/load keeps pool and caches. `--logistics-test --only bases` (fix or reconfirm the 4 old failures).
- **Out of scope.** Production chains, per-material costs, trade.

### GAMEPLAY-01D — Blueprints and automatic construction by squads
- **Objective.** Placing a building makes a site; idle squads in the base walk there and build it; danger and orders
  interrupt.
- **Reuse.** `ConstructionState` (site = `StructureState` with build progress in `facility`), `StructureManager` (site
  drawn as ghost/scaffold variant, footprint already blocking), `SquadTactics` (new BUILD tactic, owner SQUAD/PLAYER),
  `SquadPositions` ground checks, `UnitState.post_pos`, suppression/under-fire values. AI pending builds migrate to the
  same site record (one path).
- **Minimum changes.** BUILD tactic; auto-assignment of idle squads inside the base; right-click on a site = build order;
  progress shown on the site and in the panel; work pose on `InfantryCharacter` (existing animation set or a simple
  loop); sites saved.
- **Dependencies.** 01C (cost).
- **Acceptance.** The New Game squad builds a Command Post in a few minutes of play while visible at work; giving it a
  move order stops work and the site waits; shooting near it pauses work; it resumes when idle again; far from the
  camera the same site finishes in the same time.
- **Verification.** Scenario: near and far build times equal (±10 %), player order releases the squad, under-fire pause,
  save mid-build → load → progress kept, AI site via the same path (`--ai-war-test --only a_init,f_preop`).
- **Out of scope.** Engineers as a separate class, construction vehicles, resource delivery to sites.

### GAMEPLAY-01E — Defend Area, structure positions and replenishment
- **Objective.** Defend Area mans HESCO, towers, positions and cover; right-click a structure to man it; depleted squads
  refill at a barracks.
- **Reuse.** DEFEND tactic and `find_posts`, `_reserved`, `snap_points`-style def data, `BaseSim.guard_posts`,
  `_fill_depleted`, `recruit` queue.
- **Minimum changes.** Firing positions on `StructureDef` (authored local points + facing + height, e.g. tower
  platform), fed into `cover_spots` as `structure` candidates with capacity; DEFEND with a radius; right-click on a own
  structure with a squad selected = DEFEND there; a "Replenish squad" barracks action and the capacity check.
- **Dependencies.** 01D (bases worth defending); asset work for tower platform and HESCO firing points (Blender
  pipeline, `fn-blender-pipeline`).
- **Acceptance.** Defend Area on a walled base puts soldiers at HESCO firing points and the tower first, natural cover
  after; no position holds two soldiers; a move order empties them; a squad of 3 returns to 8 at the barracks for the
  recruit cost.
- **Verification.** Scenario in a built base: positions used, line of fire from positions to an approaching enemy, player
  override; `--ai-squad-test --only a_engagement,d_assault,g_player` regression.
- **Out of scope.** Building interiors, garrisoning houses, AI using the new positions (next step).

### GAMEPLAY-01F — Bases in the war: objectives, warnings, condition
- **Objective.** AI factions attack player bases, the player is warned, captured bases keep damaged buildings.
- **Reuse.** `ObjectiveState`, `StrategicDecision` candidates, `IntelSim.threat_near`, `capture_base`, `CombatSim` shot
  resolution.
- **Minimum changes.** Base → objective registration; threat warning event; `StructureState.condition` (saved) damaged by
  explosive/heavy hits only (rifles do not wreck HESCO), repaired by the BUILD tactic at supply cost; capture keeps
  condition; AI garrisons use the 01E positions.
- **Dependencies.** 01D, 01E.
- **Acceptance.** An AI attack on a player base is announced before contact, is defended from the positions, and a lost
  base appears on the map under the enemy with its damaged buildings, retakable and repairable.
- **Verification.** Accelerated scenario with the AI attacking a placed base; save/load of condition and owner.
- **Out of scope.** Destruction physics, rubble, building collapse.

---

## 7. Deferred Systems

| System | Why it waits | What already supports it later |
|---|---|---|
| Vehicle combat (hit model, APC weapon) | Not needed for an infantry/base loop; roadmap G3/limitation 4 | `VehicleSim.apply_damage`, `ContactState.Kind.VEHICLE`, `WeaponDef` mounts |
| Player mechanised operations | Player can already transport by RTS (T/U, RMB vehicle) | `OpTransport` (AI), `VehicleTransport.order_group` |
| Transport / attack helicopters, helipads | Large new movement and combat domain | Kinematic movement pattern of `VehicleSim`, `FacilityDefs` (helipad = a facility kind with parking/service points like `parking_spot`) |
| Tanks / vehicle orders as purchases | Economy must exist first (01C) | `BaseSim.acquire_vehicle`, `VEHICLES` table |
| Complex combined-arms operations | Needs vehicle combat + mech player ops | `OperationState` stages/roles |
| Advanced destruction | 01F condition is enough | `StructureState` record |
| Sophisticated logistics (supply to sites, routes graph) | Abstract resource at base level is enough | `LogisticsSim` jobs with repeat, `BaseSim` rules |
| Extensive AI base expansion | AI already builds forward depots/barracks/positions | `AiBases.request/find_site` |
| Fog of war in the 3D view | Map intel is enough for the first loop | `IntelSim` contacts per faction |

---

## 8. Open Design Decisions

| # | Decision | Recommended default | Consequences |
|---|---|---|---|
| D1 | **"Start in the south": which faction is the player?** (a) The player *is* the South faction (south-west, at today's South HQ site / Verket region) and North becomes an AI faction; (b) the player stays "North" in identity but starts at a southern location. | (a) Player = South in New Game, starting near Verket/Moen (south, away from the East front), with no HQ base; North becomes an AI faction with the `aggressive` profile, South's old AI base is not created. Dev Scenario: keep North as player unless you say otherwise. | (a) uses existing records with only data changes; the player's soldiers wear the South kit (`FACTION_LOADOUTS[1]`, RU) unless the table is changed — the table is cosmetic. (b) would need a fourth faction or a confusing name. |
| D2 | One abstract construction resource: which one? | Reuse `supplies` (kg) as "Supplies"; ammo and fuel stay separate | No new item type; recruit/vehicle costs already use supplies |
| D3 | Where does stock live before the first base exists? | A faction pool on `FactionState` (saved), shown in the HUD, moved into the first store at once | Small; avoids requiring a depot before a Command Post |
| D4 | Free reserve arrivals in New Game | Off; reserves only via barracks | Makes recruitment meaningful; needs G10 recovery |
| D5 | Recovery if the starting squad dies | A small reinforcement group arrives at the start area after a delay, once, paid from the faction pool (or free once) | Prevents dead-end games without making losses meaningless |
| D6 | Construction speed | ~2–4 min of play for a Command Post with 8 soldiers; scales with soldiers working | Tunable per type in the cost table |
| D7 | Should auto-construction take squads from defending? | Only squads with no order/op/tactic, or HOLD inside the base; never a DEFEND squad | Defence keeps priority; player can always order a squad to build |
| D8 | Capturing caches and objectives: same rule? | Same presence rule, caches shorter (30 s) and one-shot | No second capture system |

---

## 9. Evidence and Verification

### 9.1 Source files and functions read

- Start: `scripts/game/core_demo.gd` (`_ready`, `_start_large_world`, `_start_sandbox`, flags), `scripts/strategy/sandbox_setup.gd`.
- Player faction uses: `sandbox_setup.gd:42`, `core_demo.gd:290-291,422`, `tactics_overlay.gd:21,82,132`, `rts_controller.gd:42`,
  `war_state.gd:9,86`; other readers use `war.player_faction` generically (`game_hud`, `strategic_map`, `squad_panel`,
  `construction_controller`, `logistics_sim`, `vehicle_sim`, `squad_control`).
- Economy: `scripts/logistics/base_sim.gd` (`recruit`, `_finish_squad`, `_fill_depleted`, `acquire_vehicle`, `pay`, `refund`,
  `guard_posts`, `capture_base`), `logistics_sim.gd` (`_on_structure_added` START_STOCK, jobs, `order_resupply`),
  `facility_defs.gd` (`START_STOCK`, `parking_spot`), `inventory.gd`, `strategy/war_economy.gd`, `strategy/ai_bases.gd`,
  `strategy/faction_profile.gd` (income rates).
- War: `strategy/war_sim.gd` (`update`, `_update_capture`, `_transfer`, `start_operation`, `release_squads`,
  `_update_reserves`, `spawn_squad`), `war_state.gd` (`to_dict/from_dict`).
- Squads/combat: `core/squad_tactics.gd` (`_autonomy_ok`, `posture`, DEFEND), `core/squad_positions.gd` (`find_posts`),
  `combat/combat_brain.gd` (`update` engagement gate, `_perceive`, `cover_spots`), `combat/combat_sim.gd:111,198`,
  `vehicles/vehicle_sim.gd:151`.
- Controls/UI: `rts/rts_controller.gd` (`_unhandled_input`, `order_move_at`, `order_tactic`, `_pick_structure`),
  `ui/strategic_map.gd` (`_button`, `order`, `_order_at`), `ui/logistics_panel.gd`, `ui/game_hud.gd`.
- Construction/persistence: `construction/construction_controller.gd` (`save`, `load_saved`, placement), `structure_state.gd`,
  `structure_def.gd` (`snap_points`, `connect_group`), `core/world_state.gd` (`snapshot`, `apply_snapshot`, `save_file`).
- Reports: BASE-01, AI_ROADMAP, UI-01C phase 2 (observation), AI-WAR-LOGISTICS-01, AI-COMBAT-STRAT-01.

### 9.2 Existing automated coverage relevant to the loop

`--base01-test` (CP, facilities, rules, collision, infantry/vehicle, persist, views), `--logistics-test` (bases, recruit,
vehicles, delivery, resupply; 4 known pre-existing failures), `--ai-war-test` (a_init … m_save, l_player), `--ai-strat-test`
(i_player, j_persist, l_war), `--ai-squad-test` (base_fight, g_player, k_persist), `--ai-intel-test`, `--ui01c-test`,
`--ui01c2-test`. No test covers: a start other than the dev war, a non-zero player faction, player construction cost,
player income, construction by soldiers, structure positions, replenishment of player squads.

### 9.3 Runtime runs made for this audit

All on `research/gameplay-01a` = `develop` @ `b9bbc3a`, Godot 4.7.2 console build, 1600 × 900, RTX 3070. Chosen per
the testing policy: one plain start (entry flow), and the three existing scenarios that cover the brief's paths 1–8
with the least run time. No full suite was run.

| Run | Command (after `--`) | Time | Result | What it shows |
|---|---|---|---|---|
| Plain start | none (`--quit-after 2400` frames) | 58 s | exit 0, no script errors | Game starts into the war without debug setup: `{"factions":3,"objectives":12,"squads":15,"soldiers":120}`, AI bases for South (centre −3007, 3737; 6 buildings, 1 truck) and East (7802, 178; 6 buildings, 1 truck), route grid from cache (75 ms) |
| Combat + player override | `--ai-squad-test --only base_fight,g_player` | 89 s | PASS | `base_fight` (8 v 8, North attacking, South defending, 40 s): 437 shots, **North 271 / South 166**, 26 damage events, cover peak 6, alive 7 / 6. `g_player`: assault/flank/defend/withdraw accepted through the real input, player order releases the squad from its operation, Hold Fire, multi-squad Defend, possession keeps the squad tactic, out-of-range refusal with reason |
| Command Post, buildings, save/load | `--base01-test --only persist` | 20 s | PASS | Real input B → CP (rotated 45°) founds "North base 1" (150 m); barracks, depot, parking, 2 guard posts placed; refusals: no base / too steep / road / outside / overlap / second CP; **depot stock = free START_STOCK 4000/6000/9000**; save → clear → load identical (41 structures) |
| Player operation | `--ai-strat-test --only i_player` | 57 s | PASS | A player DEFEND order on a squad inside an operation takes it over ("N6: DEFEND accepted", role was fire support); the operation continues without it and later withdraws with a stated reason ("only 8 of 24 soldiers left") |

**Interpretation of the firing observation.** In the symmetric-sized baseline the player faction (North) fired *more*
than the enemy (271 v 166), so there is no evidence of a general rule that makes the player's side fire less. The
UI-01C.1 numbers come from a 12 s window that ends after the third shot, with an enemy spawned facing the squad and the
squad's own facing unset; the possessed soldier does not fire by AI. The remaining candidate causes worth one controlled
test (§9.4 item 3): facing/field of view at the moment of contact, `friendly_holds` (a friendly in the line of fire —
likely when the possessed soldier stands in front of his squad), and `perception_hz` / reaction time
(`reaction_s` 0.45 s + 0.15 s per 100 m).

**Side effect to note.** `--base01-test --only persist` saves through the real F5 path, so it overwrote
`user://saves/ref_20km/construction.json` and `world.json` (the single save slot). Any personal save there from before
this audit is gone; this is the existing test's behaviour, and it is another argument for save slots (01B).

### 9.4 Reproduction steps for identified problems

1. **Player faction ≠ 0 (G2).** Set `war.player_faction = 1` and `FACTIONS[1][1] = true` in a scratch copy of
   `SandboxSetup`; start; press F7: `TacticsOverlay` marks North squads as "mine" (`player_faction` stays 0); the start
   camera frames North HQ (`core_demo.gd:291`). [CODE — not run, would need a code change.]
2. **Free player economy (G3).** Start the game, B → Command Post anywhere valid → placed at once without cost; build a
   supply depot → war log "the first supply depot receives the starting stockpile"; wait 240 s game time → "A new squad (8)
   arrived at North HQ" while reserves last. [RUN for the CP via base01; reserves CODE]
3. **Firing asymmetry check (proposed test, not implemented).** In `--ai-squad-test` style: two 8-soldier squads,
   mirrored positions 150 m apart on open ground, both WEAPONS_FREE, facing each other, no possession; count shots and
   first-shot time per side over 60 s; repeat with sides swapped (faction 0 ↔ 1) and with one soldier of faction 0
   possessed but idle. Expected: equal within noise; if the possessed run differs, the cause is the possessed soldier
   (no AI fire, `_share_contact` skipped for `player_controlled`). The existing `base_fight` is attacker-vs-defender and
   therefore not symmetric by design.

### 9.5 Unverified assumptions / not completed

- Interactive play through the real mouse/keyboard by a person was not done; runtime evidence comes from scripted
  scenarios that drive the real input paths.
- Player transport and logistics panels were not exercised in this audit (covered by `--logistics-test` historically).
- No visual (`--shots`) run was made; this audit changed nothing visual.
- Asset feasibility of firing points on HESCO/tower models was not inspected in Blender.
