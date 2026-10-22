# PROJECT-CONSOLIDATION-01 report — one project, one branch, one documented world

Date 2026-10-22. Godot 4.7.2. Evidence tags: **[GIT]** repository state, **[CODE]** read in the source,
**[TEST]** measured in the running game, **[VISUAL]** screenshots from the real renderer, **[LIMIT]** open item.

## 1. Result

| | Before | After |
|---|---|---|
| Project folders | 14 (main folder + 13 worktrees), the main folder on an old branch without the world | **`C:\Users\Hafnor\Desktop\Game Dev\fractured-nations`** on `develop`, with the canonical world |
| Development line | a chain of milestone branches, newest `feature/ai-war-logistics-01` (not pushed at the time of the audit) | **`develop`** (local = `origin/develop`); `main` unchanged at `80c494a` |
| Unintegrated work | `feature/combat-tech-01`, `feature/blender-skills-01` (1 commit each) | merged into `develop` |
| World data | git-ignored copies in each worktree, three different versions | one canonical copy, a committed SHA-256 manifest, an external backup |

Nothing was deleted: no branch, worktree, user file, world or terrain data. No force push, no history rewrite.

## 2. Git consolidation [GIT]

* `feature/ai-war-logistics-01` @ `337c72f` already contained all 25 other local branches (including `main`,
  `research/ai-architecture-01`, `ai-combat-strat-01`, `integration-04`, `world-base-01`). It was found on `origin`
  at the same commit when B1 started (pushed by the AI-WAR session after the audit); upstream was set, nothing diverged.
* `develop` was created at `337c72f` in the main folder (after the folder's local files were secured, §5) and the two
  missing branches were merged into it with ordinary merges; `feature/ai-war-logistics-01` stays at `337c72f` as history.

| Commit | What |
|---|---|
| `0b53bd6` | Merge `feature/combat-tech-01`: COMBAT-TECH-01 report, `tools/combat_probe.gd`, lab fragment `docs/combat_tech01/lab/`. No overlap with `develop`. |
| `ba34c24` | Merge `feature/blender-skills-01`: `.claude/skills` (blender-skills), QA gate `ap_qa.py` + `build_assets.py --qa*`, winding fixes in `char_lib` / `ap_lib`, regenerated building / module / prop / road GLBs with QA sidecars. |
| `ba64141` | `tools/terrain_ref/world_manifest.py`, `worlds/ref_20km.manifest.json`, the design document (§5). |
| (this commit) | Documentation: CLAUDE.md, README, AI roadmap, this report. |

**Conflicts and resolution (file by file).** Only `assets/military/vehicles/apc_8x8.glb` and `truck_6x6.glb` conflicted
(binary). The blender-skills branch started at `21e846a`, before LOGISTICS-01 (`3f34dd2`) exported the vehicle bodies
without wheels (the game drives separate wheel meshes); it re-exported the older wheel-integrated bodies. **Kept the
`develop` versions** (blobs `9631f5ad`, `fc31fa93`, identical to `337c72f`). The auto-merged `qa` blocks in
`apc_8x8.json` / `truck_6x6.json` described those older meshes (detached parts at the wheel positions), so the two
sidecars were also kept from `develop`; the game does not read `qa`. `catalog.json` merged automatically; every one of
the 100 entries was checked against the GLB actually in the merge result (no mismatch). `CLAUDE.md` / `README.md`
merged without conflict.

**Lab project.** `docs/combat_tech01/lab/project.godot` is an isolated COMBAT-TECH-01 experiment. It cannot run on its
own (its `res://third/bukkbeek/*` autoloads were never committed), so it is kept unchanged as reference material.
After the import, the editor's file-system cache lists `tools/combat_probe.gd` but nothing under
`docs/combat_tech01/` — Godot skips the nested project folder, so it is not part of the game. No `.gdignore` was added
(it could stop the lab opening as its own project and is not needed).

## 3. Canonical Godot project

* Root: `C:\Users\Hafnor\Desktop\Game Dev\fractured-nations` (the repository's main worktree), branch `develop`.
* Godot 4.7.2-stable, Forward+ / Vulkan, Jolt. Main scene `res://scenes/game/world_ref_20km.tscn`
  (`project.godot`, unchanged by the consolidation; the folder's stale local edit to `world_core_02.tscn` was
  backed up and discarded).
* `git status` after the work: clean except `docs/Fractured Nations Terrain Reference Map.png` (§5).

## 4. Canonical development world: `ref_20km`

| | |
|---|---|
| World id | `ref_20km` (`worlds/ref_20km/world_config.tres`, `ReferenceWorldConfig`) |
| Size | 20 000 × 20 000 m, centred on the origin (current value, editable) |
| Terrain | Terrain3D, vertex spacing 1.953125 m, region size 1024, seed 3031, base height 150 m, heights 51–1216 m |
| Scenes | main `scenes/game/world_ref_20km.tscn` → generated `scenes/world/ref_20km.tscn` |
| Content | 124 roads (302 km, 4 roads with bridge spans), river (12 pieces) and lakes Tjernet, Storvatnet, Langvatnet, Fjellvatnet, `sites.json` settlements, vegetation in 128 m chunks, three faction HQ sites (`base_sites`), bases and objectives from `sandbox_setup.gd` / `ai_bases.gd` |

**Sources and generated data** (as recorded per file in the manifest):

| Role | Files | Written by |
|---|---|---|
| config | `world_config.tres` (tracked) | by hand; `tools/build_world.gd` re-saves it |
| source | `height.r32`, `control.r32`, `color.rgba8`, `roads.json`, `water.json`, `sites.json`, `vegetation.png`, `info.png`, `generation_stats.json`, `macro_height.npy` | `tools/terrain_ref/generate.py` from `tools/terrain_ref/layout_ref03.json` |
| analysis | `playability.json`, `playability_map.png` | `tools/terrain_ref/analyze.py` |
| preview | `preview_macro.png`, `preview_height.png` | `generate.py` |
| generated | `terrain/` (Terrain3D regions), `vegetation/`, `water/`, `terrain_assets.tres`, `terrain_material.tres`, `scenes/world/ref_20km.tscn` | `tools/build_world.gd` + `ReferenceWorldBuilder`; scene re-edited by `rebuild_structures.gd` |
| editor_metadata | `source/*.import` | Godot importer |

**Copies compared [TEST]** (SHA-256 of all 540 files):

| Worktree | Difference from the canonical copy (`aiwar01`) |
|---|---|
| `aistrat01` | none (byte-identical) |
| `integration04`, `logistics01` | 5 `source/*.import` files (editor metadata) |
| `playtest01`, `integration03` | 73 files: 66 Terrain3D regions, `terrain_assets.tres`, `terrain_material.tres`, 5 `.import` — editor re-saves (`uid` fields added), same sources |
| `unified` | 463 files: an older world (different `height.r32` / `roads.json`) |

**Backup** (outside every repository and worktree):
`C:\Users\Hafnor\Desktop\Game Dev\fractured-nations-backups\2026-10-22_PROJECT-CONSOLIDATION-01\`
* `ref_20km_from_aiwar01/` — `worlds/ref_20km/` + `scenes/world/ref_20km.tscn` (540 files, 2 423 901 122 bytes),
  `sha256sums.txt`, a copy of the manifest; verified file by file against the source.
* `main-folder-local-files/` — the main folder's untracked documents and its old `project.godot` edit.
* `worktree-unique-files/` — the three untracked screenshots from `fractured-nations-unified`.

**Manifest.** `worlds/ref_20km.manifest.json` (committed): world id, size, config values, the repository commit and
the last generator change (`21e846a`), provenance, per-role totals, and path / size / SHA-256 / role of every file.
`python tools/terrain_ref/world_manifest.py verify` reported **OK, 540 / 540** for the backup and for the main folder
after the copy, after two headless imports and after the whole regression.

**Reproducibility [LIMIT].** The sources rebuild the world (`tools/terrain_ref/build_ref_world.sh`, ~14 min), but not
bit-identically: the generated files carry editor re-saves and the bridge/culvert placement of `rebuild_structures.gd`,
and the generator does not record its build provenance. Restore from the backup; rebuild only for an intended world change,
then re-create the manifest.

## 5. Local files in the main folder

| File | Action |
|---|---|
| `docs/FRACTURED_NATIONS_komplett_spilldesign_arkitektur_v03 (1).docx` | not in git → committed unchanged (`ba64141`), original name kept; copy in the backup |
| `docs/Fractured Nations Terrain Reference Map.png` | byte-identical to the tracked `docs/terrain01/reference_map_03.png` → not committed again (no duplicate); left in place untouched, copy in the backup |
| `project.godot` local edit (`main_scene` = `world_core_02.tscn`, the only change) | backed up (`project.godot.diff`), discarded |
| `worlds/tile_*`, `real_20km`, `scale_4km`, `edit_test_2km` (+ scenes) | old git-ignored benchmark worlds, kept untouched |

The checkout to `develop` was checked beforehand: none of the folder's 1 962 ignored files is tracked in `develop`
(git would overwrite ignored files silently) and the switch deletes no tracked file.

## 6. Verification

### 6.1 Targeted tests for the integrated changes [TEST]

| Test | Result |
|---|---|
| Blender QA gate, all 100 assets: `build_assets.py -- --qa --qa-strict --qa-baseline benchmarks/asset01/qa_baseline.json` (no export) | 1 "new" finding: `boulder_cluster` z-fighting (190 pairs) — an AI-SQUAD-01 prop built after the baseline was recorded (baseline has 96 assets), not an integration defect. APC 8x8 passes; the truck's findings are all in the baseline. Working tree unchanged. |
| Godot asset validator `benchmarks/asset01/run_lab.sh --validate` | 98 / 100. `apc_8x8`, `truck_6x6`: "asset floats" — the validator (`tools/asset_lab/asset_lab.gd:322`, ASSET-PRODUCTION-01) was never updated for the wheel-less bodies of LOGISTICS-01; the GLBs are byte-identical to `337c72f`. All 52 regenerated GLBs pass. |
| `--integration03-test --only catalog,base,base_nav` | catalog and base pass; `base_nav abstract_round_wall_into_base` fails (4 of 8 far-tier soldiers reach the base round a wall) — **identical on `337c72f`**. |
| Headless `--import` | 2 known "placeholder instance" SCRIPT ERRORs (VegetationMask / VegetationMeshDef), also in `aisquad01`'s import log; world data unchanged. |

### 6.2 Milestone regression (the one justified full run) [TEST]

Justified because AI-WAR-LOGISTICS-01 had not re-run F–O, the AI-strat, AI-squad and sandbox suites after its last
road / vehicle changes, and the consolidation added 52 regenerated assets. Six suites, 115 minutes, all completed:

| Suite | Failed checks | Classification |
|---|---|---|
| `--ai-war-test` A–O + `m_move`, `m_march`, `m_haugen` (30 min) | M (`m_save`: no mechanised operation, 7 checks), N (`n_long`: "no free transport vehicle", no time saving) | pre-existing / order-dependent: isolated on `develop` M and N pass; isolated on `337c72f` N fails |
| `--ai-war-test` road scenarios `r_yard,r_exit,r_lanes,r_offroad,r_gaps,r_obstacles,r_convoy,r_overlay` (10 min) | R exit 2 of 24 spots; R obstacles (truck blocked by a building); R1 (`r_yard`: truck not at the road end within 500 s) | pre-existing: on `337c72f` all three fail; on `develop` isolated R exit and R1 fail, R obstacles passes (flaky) |
| `--logistics-test --only veh_drive,transport,logistics,convoy,bases,persist_logistics` (17 min) | 22: supply conservation in `convoy` / `logistics`, `transport` arrivals, `bases` (recruiting, refunds, ownership), 1 fuel rounding difference after load | pre-existing: the AI-WAR session's own run on `337c72f` (15:56) has the same convoy-conservation and transport failures; `bases` isolated fails identically on both (3 checks); the extra `bases` failures in the long run come from the preceding scenarios (no personnel left). The LOGISTICS-01 suite predates the AI economy, which now also adds and takes supplies. |
| `--ai-strat-test` (16 min) | G (seen group produced no action); L (a frame took 468 ms) | G pre-existing (same failure in the AI-WAR session's 11:10 run); L is a performance spike, see §6.4 |
| `--ai-squad-test` (20 min) | C (maneuver team 61 m short of the flank position), L (tactic update 2022 µs/tick), `base_orders` (nobody reacted to fire) | `base_orders` fails on both; C fails on `337c72f` and passes on `develop` isolated (flaky); L performance |
| `--sandbox-test` (22 min) | reinforcements did not take part in the fight; the war did not progress | pass isolated on both trees (`--only reinforce,war`): order / timing dependent in the long run |

**No failure is introduced by the integration**: every check that fails on `develop` also fails on `337c72f` (or is
order-dependent and passes isolated on `develop`); the integration changed no script, scene, StructureDef or vehicle
asset. Comparison logs and artefacts are in the session scratchpad; screenshots that the tests rewrote in tracked
`docs/` folders were restored to the committed versions, and new test screenshots were not committed.

### 6.3 Visual [VISUAL]

Screenshots rendered by the regression in the main folder (real renderer, 1600×900): the RTS view of a settlement
(terrain, asphalt and gravel roads, houses, trees, a squad in combat), first person (infantry, HESCO line, grass,
forest horizon), the strategic map (river, three bridges, lakes, faction areas, objectives, war log), an AI base (hangar,
fuel point, a truck against the building — the known R exit failure). FPS, RTS and the 2D map show the same world;
the sandbox suite's `map_rts_fps`, `hud`, `map_ui` and `characters` checks pass.

### 6.4 Performance [TEST]

| Measurement | Value |
|---|---|
| Full war (`o_war`, 40 simulated min, 181 → 273 units, 20 operations of which 6 mounted, 1 convoy) | 266.8 s real (~9× time compression); frame avg 118 ms / p99 169 ms / max 317 ms (frames carry many ticks); tick avg: abstract 0.49 ms, brain 0.93 ms, vehicles 0.15 ms, war 0.04 ms; `route_ms_max` 1.53 ms over 115 strategic routes; vehicle tick 76 µs |
| Spikes | `war_update_us_max` **418 ms** (full war), 210 ms (sandbox); `strat_us_max` 99 ms; AI-strat L: one 468 ms frame |
| Road audit (`--road-audit`) | 30 300 nodes, 31 239 edges, 18 components (main 99.2 %), 49 repaired gaps, 16 near misses, 17 unexplained isolated roads; 2 604 routes planned, **294 failed** (Elvetun 98, Kvernes 51, 3–6 to/from village streets); `plan_ms_max` 390 ms. **Identical on `337c72f`** (294 / 391 ms). The AI-WAR report's 102 failures and 1 257 ms come from a 12:13 run before its last two commits. |
| Battle 50 v 50 (sandbox) | avg 10.1 ms, p99 17–22 ms, max 31–37 ms |

The 400 ms-class war spikes match the VehicleRouter graph work reported by AI-WAR-LOGISTICS-01 (first build ~0.5 s,
~130 ms rebuild after construction) and single slow vehicle plans (390 ms); not optimised here (out of scope), they
belong to NAVIGATION N1.

## 7. Documentation updated

* `CLAUDE.md` — new first section *Project standard* (one folder, `develop`, no milestone branches / worktrees, old
  branches as history, session workflow), *Canonical development world* (scenes, config, sources vs generated,
  manifest, backup, "do not regenerate to repair"), *System owners*; AI-WAR test commands, import note, lab note.
* `README.md` — project standard at the top, opening instructions (`develop`, world data), reference-world section
  (canonical world, manifest, backup).
* `docs/AI_ROADMAP.md` — status line and §8 rewritten: where to work, NAVIGATION N1 scope, the known `base_nav` failure.
* This report.

## 8. Navigation: status and NAVIGATION N1

The NAVIGATION-ARCHITECTURE-01 findings (session analysis, read-only) were re-checked on `develop`: the referenced
code is unchanged (`vehicle_router.gd` 21 / 38 / 201 / 252 / 412 / 482 / 657 / 691, `strategic_routes.gd` 107 / 250 / 374,
`squad_control.gd` 39 / 177; the integration touched no navigation code).

**Exists [CODE].** 50 m strategic grid with slope, water, roads and bridge openings, incrementally updated for built roads
(`StrategicRoutes`); road graph over `RoadNetwork` with off-road legs (straight, 3 m local grid aware of structures, slopes,
water and parked vehicles, or the strategic grid), per-vehicle `offroad_factor` / `max_grade` (truck 3.0 / 0.40, APC 1.7 /
0.55), gap repair, run-time bypass, reversing, convoys (`VehicleRouter`, `VehicleSim`, `VehicleConvoy`); near-tier navmesh
around the observer with structures and trees carved (`AreaNavigation`), NavigationAgent3D + RVO + stuck handling
(`SoldierBody`); squad route following with stall re-planning (`SquadControl`); road audit and overlay.

**Missing.** Tracked vehicles (only truck and wheeled APC exist); terrain type and vegetation in route costs (the
cross-country planner ignores trees and rocks); road / bridge width and load in the graph; bridges as objects that can be
disabled; height check on graph junctions (`_link_junctions`); route invalidation when roads, bridges or structures change;
**far-tier path finding round structures** — abstract units slide along a wall and stop (`WorldSim._free_direction`), which
is what `base_nav abstract_round_wall_into_base` shows, so the same squad behaves differently near and far.

**N1 plan (measure first, then build on the existing owners).** Baseline with the existing counters (strategic routes and
time, vehicle plans and time, `route_replanned` / `route_skips`, `stuck_reroutes`, SoldierBody BLOCKED, `VehicleSim.stats`,
`tick_usec`, road audit) plus one new counter: route-stall timeouts while the leader is reacting (`CombatBrain`
`react_target` vs the 25 s `route_stall_s`). Planned acceptance scenarios (not claims that they work today): infantry round
a building; infantry finds the opening in a wall; a tracked vehicle off-road round a blocked road; wheeled APC vs tracked
vehicle choose different routes; a convoy over a narrow bridge; a bridge becomes unusable while units are on the way; a
new base over a valid route; a squad round a defence line far from the player; the same situation near and far. Design
direction: closed walls are blocked (not just expensive) and open gates are passages in both tiers, by reusing
`VehicleRouter`'s 3 m local planner as the shared local layer for vehicles and far-tier infantry; a budgeted round-robin
route queue copied from `CombatBrain`; no HPA* / flow fields without a measured need.

## 9. Worktree cleanup plan (nothing removed)

All 13 worktrees are on branches contained in `develop` and pushed to `origin`; all are clean except `unified`.

| Worktree | Branch | Unique content | Recommendation |
|---|---|---|---|
| `aiwar01` | `feature/ai-war-logistics-01` | world copy = canonical (backed up); ignored logs `w1–w9`, `benchmarks/raw` | keep until `develop` is approved, then removable |
| `aistrat01` | `feature/ai-combat-strat-01` | world identical to canonical; `benchmarks/raw`, `logs/` | removable |
| `aisquad01`, `aiintel01`, `airesearch01`, `integration04`, `logistics01`, `asset01`, `blenderskills01`, `combat-tech01` | (their branches) | only ignored test logs / `benchmarks/raw` | removable |
| `integration03`, `playtest01` | (their branches) | older editor re-saves of the world (sources identical) | removable |
| `unified` | `feature/unified-sandbox` | 46 modified files = editor re-saves (uid / unique_id / import format, no content); 3 untracked screenshots `docs/integration02/s01b_08–10_*` — sandbox-test output (the regression regenerated files with the same names), backed up; an older world | removable after the product owner accepts discarding the editor re-saves |

Removing a worktree (`git worktree remove`) does not delete its branch; the branches stay on `origin` as history.
The ignored `benchmarks/raw` / log files are test output and are not needed. Each removal needs explicit approval.

## 10. Open items

* `main` is unchanged (`80c494a`). **Recommendation:** fast-forward `main` to `develop` once the product owner accepts
  this report — `develop` contains every branch, the integration added no failure, and the remaining failures are
  documented as pre-existing. A fast-forward needs no merge.
* Pre-existing test failures to fix in later milestones: `base_nav` far-tier wall; R exit (2 / 24 docks), R1 / `r_yard`,
  flaky R obstacles; Elvetun / Kvernes routes; AI-war M / N order dependence; LOGISTICS-01 suite vs the AI economy
  (conservation, transport, bases); AI-strat G; AI-squad `base_orders`, flaky C; long-run sandbox reinforce / war.
* Performance: 400 ms-class war-update spikes and 390 ms single vehicle plans (N1).
* Asset pipeline: the asset validator does not know wheel-less vehicle bodies; `boulder_cluster` z-fighting is not in the
  QA baseline; the vehicle and AI-SQUAD-01 prop GLBs predate the blender-skills winding fix (re-export later with the QA
  gate, then re-record the baseline).
* `docs/Fractured Nations Terrain Reference Map.png` remains as an untracked duplicate in the main folder (safe to delete
  by the product owner; identical copy in git and in the backup).

## 11. Next milestone

**NAVIGATION N1 — Baseline, Off-road & Obstacle Navigation Foundation** on `develop` in this folder (§8). First task:
the measurement baseline and the nine acceptance scenarios as short scripted tests, starting from the failing
`base_nav abstract_round_wall_into_base` (far-tier squad round a wall), before any navigation change.
