# Fractured Nations — development instructions

Modern military sandbox in Godot 4.7.2 (Vulkan, Jolt, Terrain3D). User-facing overview and
launch instructions: [README.md](README.md). Chat language with the product owner is
Norwegian; code, comments and docs are English.

## Branch workflow

- **`feature/integration-04` is the current baseline** (worktree `../fractured-nations-integration04`):
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
- After adding `class_name` scripts or assets run `Godot ... --headless --path . --import` once.
- A script that fails to compile makes a test hang until timeout; check the log head first.
- Blender asset pipeline: `tools/blender/` (+Y forward, one joined mesh, origin on the ground,
  material names drive faction colours; character: `tools/blender/character/`, standard in
  `docs/CHARACTER_STANDARD.md`). Always inspect imported assets in Godot, not only Blender.
- Python on Windows: open files with `encoding='utf-8'`.
