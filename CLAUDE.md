# Fractured Nations — development instructions

Modern military sandbox in Godot 4.7.2 (Vulkan, Jolt, Terrain3D). User-facing overview and
launch instructions: [README.md](README.md). Chat language with the product owner is
Norwegian; code, comments and docs are English.

## Branch workflow

- **`feature/ai-war-logistics-01` is the newest AI branch** (worktree `../fractured-nations-aiwar01`): AI-COMBAT-STRAT-01 +
  AI-WAR-LOGISTICS-01 (AI bases and economy, mechanised operations and convoys, resupply, counterattacks, the road network
  audit `--road-audit` / overlay F8 and the vehicle navigation fixes; report
  [docs/AI-WAR-LOGISTICS-01_REPORT.md](docs/AI-WAR-LOGISTICS-01_REPORT.md)). Scenarios: `--ai-war-test [--only a_init,...,r_yard,r_obstacles,r_convoy,r_overlay,r_exit]`.
  Prefer the short road scenarios (`r_yard`, `r_convoy`, `r_overlay`, minutes) over `r_drive` (20 km routes, ~20 minutes).
- `feature/ai-combat-strat-01` is the baseline below it (worktree `../fractured-nations-aistrat01`):
  `feature/ai-squad-01` + AI-COMBAT-STRAT-01 (coordinated multi-squad operations, withdrawal, the strategic
  utility scorer, defence sectors; report [docs/AI-COMBAT-STRAT-01_REPORT.md](docs/AI-COMBAT-STRAT-01_REPORT.md)).
  New AI milestones branch from it.
- `feature/ai-squad-01` (worktree `../fractured-nations-aisquad01`) is the baseline below it:
  `feature/ai-intel-01` + AI-SQUAD-01 (fire teams, suppression, squad tactics, tactical RTS orders, cover props).
  New AI milestones branch from it; the plan is [docs/AI_ROADMAP.md](docs/AI_ROADMAP.md).
- `feature/ai-intel-01` (worktree `../fractured-nations-aiintel01`) is the baseline below it:
  `feature/integration-04` + AI-INTEL-01 / AI-OBS-01 (faction contact intelligence and the AI inspector).
- `feature/integration-04` (worktree `../fractured-nations-integration04`) is the integration baseline below it:
  `feature/world-integration-03` + `feature/logistics-01-base-02` (vehicles, transport, logistics, bases)
  + `research/ai-architecture-01` (docs only), integrated in INTEGRATION-04. New milestones branch from
  it (`feature/<milestone>`) and merge back into it or its successor. The AI plan is
  [docs/AI_ROADMAP.md](docs/AI_ROADMAP.md); the next milestone is AI-INTEL-01.
- `feature/world-integration-03` (worktree `../fractured-nations-integration03`) is the previous baseline
  and `feature/logistics-01-base-02` (worktree `../fractured-nations-logistics01`) its logistics branch;
  both stay as history.
- Do not continue parallel development on the old feature branches
  (`feature/world-sandbox-01b`, `feature/character-01`, `feature/combat-*`, ...). They stay
  as they are, with their worktrees, as history.
- Use a git worktree per milestone (`../fractured-nations-<milestone>`). Generated, git-ignored
  data (`worlds/ref_*`, `scenes/world/ref_*.tscn`, `.godot/`) is copied from an existing
  worktree or rebuilt with `tools/terrain_ref/build_ref_world.sh` (about 14 min).
- Nothing is merged into `main` without the product owner's explicit approval. Commit and
  push milestone results; never force-push.
- Each milestone ends with a report in `docs/<MILESTONE>_REPORT.md` and an updated README.

## Architecture principles

- **One authoritative world simulation** (`WorldState` / `WorldSim`). A soldier is a
  `UnitState` record; `SoldierBody` (near, physical) and `UnitProxy` (far, cheap) are only
  representations of it. Possession, orders, combat and saves read and write the record.
- **No duplicate controllers.** FPS control, AI movement, combat (`CombatSim`, `CombatBrain`),
  squads and the war (`WarSim`) each have exactly one implementation. If two systems collide,
  fix the cause; do not add a parallel system, a compatibility layer or a manager that
  papers over it.
- **Near/far consistency.** Anything shown on a body must come from persisted record state
  (e.g. `UnitState.loadout`) so it survives demotion/promotion, possession and save/load.
  Distant units use the cheapest representation (`InfantryProxyMesh`, abstract simulation).
- **Data-driven content.** Characters are `InfantryLoadout` / `InfantryEquipment` resources on
  one shared rig; structures come from `StructureCatalog` (code-built field set +
  `assets/military/defs/**/*.tres`; props via `tools/asset_production/make_prop_defs.py`).
  New content is data, not code.
- **Faction look is a table, not an identity.** `WorldState.FACTION_LOADOUTS` (and
  `InfantryMaterials.FACTION_CAMO`) say what a faction's soldiers wear; nothing in the war,
  diplomacy or combat reads it. North / South / East stay the faction identities.
- **Future-proofing.** Nothing soldier-specific may be hardcoded where vehicles, logistics or
  bases will need it (e.g. muzzle positions come from the held weapon's mount, not offsets).
- **One road network** (`RoadNetwork`, `WorldState.roads`): the world's roads.json plus the
  roads built in construction. Route planning, construction snapping and terrain work all read
  it; never add a second road representation. Paved areas are not roads (no route shortcut).
- **Vehicles, supplies and bases (LOGISTICS-01).** `VehicleSim` (owned by `WorldSim`) is the only
  vehicle mover, one kinematic step on the `UnitState`/`VehicleState` record in both tiers; `VehicleBody`
  and `UnitProxy` only display it. `VehicleRouter` is a derived index over `RoadNetwork`, never a second
  road definition. `Inventory.transfer` moves supplies between stores; `Inventory.add/take` are only for
  sources and sinks (start stock, costs, fuel burn, resupply). Bases live in `ConstructionState.bases` +
  `StructureState.base_id`; `FacilityDefs` is the table of what buildings do. Soldiers aboard
  (`UnitState.vehicle_id >= 0`) are changed only by `VehicleTransport`.
- **Faction knowledge is reported, never read off the world.** What an AI faction believes about
  the enemy is `WarState.contacts` (`ContactState`), written only by `IntelSim.report_*` and aged by
  `IntelSim.update`; the only detection pipeline is `CombatBrain` perception (sightings, gunfire
  heard, fire taken), plus soldiers holding an objective an enemy stands in. Strategic and
  operational code reads `WarSim.threat_near` / `IntelSim.contacts_*` and must never look up an
  enemy `UnitState` position it has not been told about. A contact's `pos` is where it was last
  reported; it is never refreshed from the world.
- **Squad tactics (AI-SQUAD-01).** `SquadState.teams` (two fire teams for four or more soldiers, a leader each,
  validated by `SquadTactics.validate` after every casualty) and `SquadState.tactic*` (DEFEND, SUPPRESS, ASSAULT,
  FLANK, BOUND, REPOSITION, WITHDRAW, REGROUP; owner player / operation / squad; phase, target, route, why / rejected
  strings) are the only tactical state; everything is saved and every step derives from it, so near, far, load and
  possession behave the same. `SquadTactics` (owned by `WorldSim.tactics`) steps squads twice a second; soldiers carry
  a tactic out only through ordinary move orders to a `UnitState.post_pos`, fire missions (`fire_at`, fired by
  `CombatBrain` through `CombatSim.request_fire` at a *reported* position, never a hidden soldier) and their own cover
  reactions near the post. Every ordinary squad order calls `SquadTactics.on_order` (player > operation > squad
  tactic > reaction); a squad with a soldier aboard a vehicle never runs a tactic. `SquadPositions` does the post,
  flank and exposure measurements on world data against believed positions only. Suppression is a decaying value on
  the unit record (`suppression_at`). No planner, no second blackboard: choices are a few scores with their reasons.
- **Operations and strategy (AI-COMBAT-STRAT-01).** `OperationState` carries a stage (APPROACH, DEPLOY, SUPPORT,
  ASSAULT, SECURE, WITHDRAW, DONE; `stage_why`, `wait_reason`, `withdraw_why`, `fallback_pos`) and per-squad roles
  (`SquadState.op_role`: assault, support, maneuver, reserve, security, reinforce). `OpCoordination`
  (`WarSim.coord`) assigns roles and advances the stages from the squads' own state (assessment, tactic, position);
  every stage has a success condition, a timeout and a fallback, and it never reclaims a squad whose tactic is owned
  by the player. Attack operations use `SquadTactics` by default (`--legacy-ops` is the old walk-in, for comparison
  only). `StrategicDecision` (`WarSim.strat`) is the utility scorer (attack / reinforce / join / garrison /
  recover / withdraw) reading only IntelSim contacts and `StrategicInfluence` (threat grid, route risk) with a basis
  label (confirmed / reported / stale / assumed / none), a reserve, `FactionState.focus` hysteresis and
  `FactionProfile` weights. `WarSim._defence_posture` spreads garrisoning squads over sectors facing the believed
  threat, with a local reserve from three squads. Decisions, stages and roles are shown by the AI inspector.
- **AI layers** (strategic `WarSim._decide` -> operations `OperationState` -> squad tactics
  `SquadControl` -> individual `CombatBrain`) all read and write the same records and call the same
  APIs as the player (see the interface map in [docs/AI_ROADMAP.md](docs/AI_ROADMAP.md)). Order of
  authority: player > operation > squad tactic > reaction. No planner engine, behaviour-tree runtime,
  second blackboard, AI-only transport/vehicle/inventory/base system.
- **Building must work on uneven terrain**: groundwork in `StructureManager`, never
  flat-site hunting.
- Large generated worlds: one `RoadContainer` per ~50 RoadPoints (O(n²)); foliage cards are
  shadow-fill-rate bound; vegetation lives in 128 m cell chunks. See the WORLD-TECH reports.

## Testing policy (mandatory)

- **Change-impact testing.** Run only the tests that directly cover the changed code and its
  dependents, e.g. `--sandbox-test --only characters,map_fps,persist`. Say which tests you
  chose and why before running them.
- Shared systems changed → also run the affected integration scenarios, not the whole suite.
- Visual/UI changes: run the real game and inspect screenshots (`--shots`).
- Never rerun tests that passed unless later changes could affect them. No automatic full
  regression after a commit, phase or bug fix; at most **one** justified full-suite run per
  milestone, announced beforehand with the reason.
- A failing test is investigated and the failing test plus its dependencies rerun, never
  replaced by a full run.
- Keep tests to minutes. Accelerate simulated time or place forces close together instead of
  long real-time runs. Long routes/stress runs are optional.
- Check that a test really exercises what it claims (INTEGRATION-02: a "pass" with no target
  alive proved nothing). Scenarios must fail when their precondition is missing.

## Practical notes

- Test runs: `Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --log-file x.log res://scenes/game/world_ref_20km.tscn -- --sandbox-test [--shots] [--only a,b] [--shot-dir=res://docs/...]`.
  Use the GUI exe with `--log-file` for runs that may spam errors. LOGISTICS-01 scenarios:
  `--logistics-test --only veh_drive,transport,logistics,convoy,bases,persist_logistics,scenario` (the `scenario`
  run is the brief's end-to-end acceptance through the real controls). Integration scenarios of the
  combined baseline: `--integration03-test --only catalog,factions,base,base_nav,long_route,views,persist,vehicles,perf`.
- AI-COMBAT-STRAT-01 scenarios: `--ai-strat-test [--shots] [--only s0_repro,a_assault,b_reduced,c_reinforce,d_defence,e_withdraw,f_fronts,g_intel,h_deadlock,i_player,j_persist,k_near,l_war,m_perf,z_visual]`
  (results in `benchmarks/raw/ai_strat_test.json`, screenshots in `docs/ai_strat01/`; `l_war` is a 40 simulated
  minute autonomous war and takes about 3 real minutes, `z_visual` is the screenshot run). `--legacy-ops` /
  `--no-squad-ai` switch the new behaviour off for comparison.
- AI-SQUAD-01 scenarios: `--ai-squad-test [--shots] [--only a_engagement,b_suppress,c_flank,d_assault,f_withdraw,g_player,h_intel,i_casualties,j_near_far,k_persist,l_perf,z_showcase]`
  (baseline of the unchanged combat: `base_fight,base_far,base_orders`; each scenario resets itself through
  `CombatScenario`; results in `benchmarks/raw/ai_squad_test.json`). `--squad-demo` runs the showcase encounter in the
  real game and leaves it running. RTS keys: **Z** assault, **K** suppress, **L** flank, **J** defend, **Backspace**
  withdraw (each at the cursor, or arm from the bottom-right bar and click), **Shift+RMB** move by bounds, **V** cycles
  auto / line / column / wedge / staggered / dispersed, **F7** fire teams, posts and missions overlay.
- AI-INTEL-01 scenarios: `--ai-intel-test [--shots] [--only z_old_rule,a_initial,b_lost,c_reacquire,d_hearing,e_tiers,f_persist,g_strategy,k_investigate,h_player,i_factions,j_perf]`
  (each resets its own state; results in `benchmarks/raw/ai_intel_test.json`). Strategic map developer keys:
  **I** AI inspector (cycles factions: their contact picture, last decisions, operations), **T** (with the
  inspector on) true squad positions, labelled TRUTH, click one to inspect that squad.
- After adding `class_name` scripts or assets run `Godot ... --headless --path . --import` once.
- A script that fails to compile makes a test hang until timeout; check the log head first.
- Blender asset pipeline: `tools/blender/` (+Y forward, one joined mesh, origin on the ground,
  material names drive faction colours; character: `tools/blender/character/`, standard in
  `docs/CHARACTER_STANDARD.md`). Always inspect imported assets in Godot, not only Blender.
  The `blender-*` agent skills (EL4CTEO/blender-skills, MIT) are installed in
  `.claude/skills/`; start Blender work with `fn-blender-pipeline` (our conventions on top of
  them) and run the QA gate `build_assets.py -- --qa` after geometry changes
  (`--qa-strict --qa-baseline benchmarks/asset01/qa_baseline.json` = no new defects).
- Python on Windows: open files with `encoding='utf-8'`.
