# Fractured Nations — development instructions

Modern military sandbox in Godot 4.7.2 (Vulkan, Jolt, Terrain3D). User-facing overview and
launch instructions: [README.md](README.md). Chat language with the product owner is
Norwegian; code, comments and docs are English.

## Project standard (PROJECT-CONSOLIDATION-01) — read this first

- **One project, one folder:** all ordinary development happens in
  `C:\Users\Hafnor\Desktop\Game Dev\fractured-nations` (this folder, the repository's main worktree).
  It is the only active Godot game project. Check `git -C <this folder> branch --show-current` says
  `develop` before you change anything; if you find yourself in a `../fractured-nations-<name>` folder,
  you are in an old worktree kept as history — stop and move here.
- **One active line: `develop`.** Work, commit and push on `develop`, in separate commits per logical
  phase. `main` is the stable branch and is only updated (fast-forward from `develop`) with the
  product owner's explicit approval. Never force-push, never rewrite pushed history.
- **No permanent milestone branches and no new worktrees.** A milestone is a series of commits on
  `develop` plus its report. A temporary branch is allowed for a risky experiment only; merge it back
  into `develop` (ordinary merge) when it is done and do not leave it as a parallel game version. Do
  not create worktrees or project copies without a concrete technical reason agreed with the product owner.
- **Old branches stay as history.** Every earlier `feature/*` / `research/*` branch (up to
  `feature/ai-war-logistics-01` @ `337c72f`) is contained in `develop`; their worktrees
  (`../fractured-nations-*`) are only kept until the product owner approves removing them
  (status: [docs/PROJECT-CONSOLIDATION-01_REPORT.md](docs/PROJECT-CONSOLIDATION-01_REPORT.md)). Do not develop there.
- **Session workflow:** open this project → read this file and the roadmap ([docs/AI_ROADMAP.md](docs/AI_ROADMAP.md),
  ASSET-INTEGRATION-01 is done - see its report; the next milestone is defined with the product owner) → read the systems you will touch (owners below) → implement →
  targeted tests + visual Godot validation → update the report / README → commit to `develop`.
- Each milestone ends with a report in `docs/<MILESTONE>_REPORT.md` and an updated README.

## Canonical development world: `ref_20km`

- Main scene `res://scenes/game/world_ref_20km.tscn` (`project.godot` main scene) instances the generated
  world scene `res://scenes/world/ref_20km.tscn`. Config `worlds/ref_20km/world_config.tres`
  (`ReferenceWorldConfig`): currently 20 000 × 20 000 m centred on the origin, Terrain3D vertex spacing
  1.953125 m, region size 1024, seed 3031. These are the current values, not limits: size, terrain, roads,
  bridges, rivers, lakes, forests, settlements, bases and faction areas can all be changed in this project.
- **Sources** (`worlds/ref_20km/source/`, written by `tools/terrain_ref/generate.py` from
  `tools/terrain_ref/layout_ref03.json`; since VISUAL-02 the cover - `vegetation.png`, `info.png`, `stand.png`, `color.rgba8`,
  `control.r32` - comes from `layout_ref03_visual02.json` (`cover_v2`) on the unchanged relief and roads, merged by
  `tools/visual02/build_candidate.gd`): `height.r32`, `control.r32`, `color.rgba8`, `roads.json`,
  `water.json`, `sites.json`, `vegetation.png`, `info.png`, `stand.png`, `generation_stats.json`, `macro_height.npy`;
  `playability.json` / `playability_map.png` come from `analyze.py`. **Generated** (by `tools/build_world.gd`
  + `ReferenceWorldBuilder`): `terrain/` (Terrain3D regions), `vegetation/`, `water/`, `terrain_assets.tres`,
  `terrain_material.tres`, `scenes/world/ref_20km.tscn` (bridges/culverts re-placed by
  `tools/terrain_ref/rebuild_structures.gd`). Full rebuild: `tools/terrain_ref/build_ref_world.sh` (~14 min).
- Everything except `world_config.tres` is git-ignored (2.4 GB). The committed manifest
  `worlds/ref_20km.manifest.json` (SHA-256 of all 540 files) identifies the canonical copy:
  `python tools/terrain_ref/world_manifest.py verify --ignore-editor-metadata` must say OK. After an
  intended world change, re-create it (`... world_manifest.py create --note "<what changed>"`) and commit it.
  Backup of the consolidated copy: `../fractured-nations-backups/2026-10-22_PROJECT-CONSOLIDATION-01/`; of the files VISUAL-02
  replaced: `../fractured-nations-backups/2026-10-25_VISUAL-02_pre_adoption/`.
- **Do not regenerate the world to "repair" it**: the generated files carry later editor re-saves and
  structure placement, so a rebuild is not bit-identical and can lose edits. Restore from the backup instead.
- Other worlds: `worlds/test_2km` (tracked, small test world); `worlds/tile_*`, `real_20km`, `scale_4km`,
  `edit_test_2km` in this folder are old git-ignored benchmark worlds (kept, not used by the game).

## System owners (do not build parallel versions)

`WorldSim` (tick, both tiers, abstract movement) · `WarSim` (faction strategy, operations; owns `OpCoordination`,
`StrategicDecision`, `IntelSim`, `WarEconomy`, `AiBases`, `OpTransport`, `WarLogistics`, `StrategicRoutes`) ·
`OperationState` (operation data, stages incl. transport stages) · `SquadControl` (squad orders, formation slots,
route following / replanning) · `SquadTactics` + `SquadPositions` (tactical legs, flank, bound, posts) ·
`CombatBrain` (perception, firing, cover reactions via `react_target`; never routes) · `SoldierBody` (near-tier
body: NavigationAgent3D + RVO, stuck handling) · `DetailManager` + `AreaNavigation` (near tier, runtime navmesh
around the observer) · `VehicleSim` (only vehicle mover) / `VehicleRouter` (vehicle routes over `RoadNetwork`) /
`VehicleConvoy` / `VehicleTransport` · `RoadNetwork` (`WorldState.roads`, the only road data) ·
`StrategicRoutes` (50 m world grid for infantry routes) · `StructureManager` / `ConstructionState` (structures,
groundwork, blocking footprints) · `RoadAudit` (`--road-audit`, overlay F8). Navigation analysis and the N1 plan:
[docs/PROJECT-CONSOLIDATION-01_REPORT.md](docs/PROJECT-CONSOLIDATION-01_REPORT.md).

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
- **Vehicle clearance (NAVIGATION N1-B).** `VehicleRouter` plans for the vehicle's `circle_r` plus a tracking margin; a route
  must never be accepted on the bare footprint radius. Solid vegetation (`StructureManager.blocks_trunk`) is a hard obstacle
  for cross-country legs; roads are not checked against it. A short link between road components is a *soft link* planned per
  vehicle (`VehicleRouter._soft`), never a graph edge. Vehicle navigation tests: `--navigation-n1b-test`.
- **Settlements (WORLD-SETTLEMENT-02).** `SettlementLayer` (`scripts/world/settlement_layer.gd`, data in `worlds/settlements/`) is
  the only settlement source of ref_20km: it removes the generated streets in `RoadNetwork.load_world` (their slots stay, so road keys and
  bridge ids do not move) and adds its local roads; writes its heights and ground paint into Terrain3DData in memory at game start
  (`CoreDemo._start_sandbox`, never saved); its buildings and removals are a read-only `WorldOverrides` layer under the user's own
  overrides file (user records win; only the user's records are saved). Edit the places in `tools/settlement_proto/design_settlements.py`
  (Haugen: `design_haugen.py`), then run `paint_settlements.py` and `build_overrides.gd`. `--no-settlements` switches it off.
- **Bridges (NAVIGATION N1-C1).** A bridge is `RoadNetwork.Bridge` (stable id `bridge_r<road>_s<span>` from roads.json, state OPEN /
  CLOSED / DISABLED, saved in `WorldState.snapshot()["bridges"]`); `RoadNetwork.set_bridge_state` is the only writer and emits
  `bridge_changed`. Navigation owners keep derived data only (`VehicleRouter` switches graph vertices off, `StrategicRoutes` closes the
  cells under the span, `WorldSim._infantry_blocked` refuses the deck) and never a second copy of the state. `deck_height` stays the
  *physical* deck; refuse a deck with `blocking_bridge_at` / `deck_open`. Closed means: nothing new enters, what is on the deck finishes
  (never teleport or delete). `VehicleSim` brakes short of a closed deck and re-plans one vehicle per tick; `SquadControl` re-routes or
  stops the march with a reason; operations report `route blocked` and fail after 300 s. `BridgeMarkers` is a debug indicator only.
  Tests: `--navigation-n1c1-test`.
- **Scenarios, economy and construction sites (GAMEPLAY-01B).** A game starts from a `ScenarioDef`
  (`assets/scenarios/dev.tres`, `new_game.tres`) through the one `SandboxSetup.create`; its rules are copied into
  `WarState.rules` (saved) and every economy switch reads `war.rule(...)` with the Development Scenario's behaviour as
  fallback. `BuildCosts` is the one cost / work table (player and AI). Stock without a building is `FactionState.pool`;
  the player pays with `BaseSim.faction_pay/faction_refund`. A placed structure can be a site (`StructureState.site`):
  no facility until `ConstructionState.add_work` completes it once (`structure_completed`); soldiers build through the
  squad tactic BUILD (`SquadTactics`), AI sites through a crew rate in `AiBases.update`. Tests save to `user://test_saves`.
- **Base warfare (GAMEPLAY-01C–01G).** Fortification slots are data (`DefenceDefs`); who holds one is the soldier record
  (`UnitState.fort_slot` / `fort_pos`, saved), never a reservation table; both tiers hold a soldier in his slot and any move
  order takes him out (`WorldState.leave_fort`). GARRISON_BASE is `SquadState.garrison_base` (DEFEND at the base through
  `SquadTactics`). Every base has one objective (`WarSim.sync_bases`: the held objective it stands on, else its own kind
  `base` objective); the objective's owner is the base's ownership and `WarSim._transfer` → `BaseSim.capture_base` is the
  only path a base changes hands. Condition is `StructureState.hp` / `repair` (`StructureHealth` table); damage never deletes
  a structure or a base; repair is BUILD work on the same record. AI expansion: `AiBases` templates + `WarState.expansions`.
- **Weapons, roles and explosives (GAMEPLAY-02).** A weapon is a `WeaponDef` (`assets/combat/*.tres`: rifle, lmg, grenade,
  launcher) - role, suppression per near miss and its radius, braced / moving handling, AI bursts, blast fields - and the
  same `CombatSim` rules serve AI and player. What a soldier carries is its `InfantryRole` (`assets/combat/roles/`, saved as
  `UnitState.role`, grenades, `sec_id` / `sec_ammo`); a squad's roles come from a `SquadComposition` (`assets/combat/squads/`,
  scenario rule `squad_composition`, default `standard`) through `CombatSim.apply_composition` only (fresh squads,
  replacements; veterans keep their weapons). Grenades and rockets are entries of `WorldState.explosives` (saved) stepped by
  `CombatSim`; a burst (`CombatSim.detonate`) is one bounded query (brain grid, `LineOfFire.structures_near`) and damages
  structures only through `ConstructionState.damage` x `StructureHealth.blast_resist`. AI use is individual (`CombatBrain`):
  only at what the soldier saw or was told, with friend checks and per-squad rate limits. `OperationState.cover_fire` is the
  fire support's window (OpCoordination). Tests: `--combat02-test [--only a_*,b_*,c_*,d_*,e_*] [--seeds=1,2,3]`
  (`CombatDiag` records engagements; `tools/combat02_compare.py` compares series).
- **Defensive warfare (GAMEPLAY-03).** A defence's posts are judged in `SquadTactics._judged_posts` (fortification slots and
  natural posts on one scale: protection, line of fire, concealment = `SquadPositions.exposure` from the believed threat's side,
  prepared, sector, elevation, distance; weights `post_w`, weapon modifiers `role_post_w`); a REPOSITION keeps the soldiers whose
  posts still serve. A garrison / stationed defence never withdraws for being outnumbered: it falls back a line
  (`SquadState.defence_line`, saved; REPOSITION with `tactic_leg >= 100`, shown as "Fall back (line N)") inside the objective's
  capture radius and keeps `garrison_base`. Fire support ranks reports (fortified first); OpCoordination's `idle_commit_s` and
  "support joins the assault". Tests: `--combat03-test [--shots] [--only p_posts,f_threat,f_persist,f_override,g_launcher_hands,
  g_grenade_react,i_player,j_persist,d_open,d_village,d_forest,d_reverse] [--seeds=1,2,3]` (results
  `benchmarks/raw/combat03_test.json`, compare with `tools/combat03_compare.py`, shots `docs/gameplay03/`).
- **Road shoulders and slopes (GAMEPLAY-04A).** `RoadShoulders` (`scripts/world/road_shoulders.gd`) eases the terrain beside every
  world road into the road surface in memory at game start (like the settlement layer: never saved, manifest untouched; cached in
  `user://terrain/`), and puts the vegetation of those cells back on the ground when chunks load. Infantry climbs grades up to
  `WorldSim.INFANTRY_MAX_GRADE` (tan 50°) slower uphill through `WorldSim.slope_speed` in both tiers (navmesh, abstract step,
  SoldierBody floor angle). `--no-road-shoulders` switches the easing off for comparison.
- **Road edges (ROAD-QUALITY-01).** Meshed roads are fitted to their Road Generator **collider**, not to RoadNetwork's line (the mesh
  is 2 m wider per side - its gutter -, 0.2 m higher, and junctions are separate meshes): `RoadShoulders` measures the edge with rays
  every 2 m and tests every nearby vertex with one ray; under the collider the terrain lies 0.28 m (carriageway) to 0.04 m (edge)
  below it, beyond the edge a 3 m landing at most 0.35 steep, between two roads edge to edge. Raise `RoadShoulders.CACHE_VERSION`
  whenever compute() changes (the cache key does not see code). Plants >= 1 m inside an edge are kept under the asphalt and masked
  from the grass (`mask_grass`). Steep natural banks beyond the band stay obstacles. Never "fix" a road edge in SoldierBody (no
  higher step / hop): measure it with `--road-quality-test --only survey` and fix the terrain.
- **World look (VISUAL-02).** The terrain is drawn with `shaders/world/terrain_visual02.gdshader` (Terrain3D's default shader plus
  colour-map softening, open-ground macro variation, field patterns, distant canopy), applied in memory by `GroundLook` like
  `WorldLook` (`--legacy-ground` for the old shader); the grass tufts match it. Settlement buildings / fences use
  `shaders/environment/building.gdshader` (instance colour paints only siding and doors). Vegetation cover is `cover_v2`
  (`generate.py build_cover_v2`, `stand.png`, scatter v2 in `ReferenceWorldBuilder._trees_v2`): one set of environmental
  parameters drives density, stand age, species and ground together; saplings (ids 22-23) have no collider. Procedural
  4-channel PNGs must be written with straight alpha (`oiio:UnassociatedAlpha`). Survey: `--visual02-test --only survey`.
- **Military Development and the opening (GAMEPLAY-04A/B).** `MilitaryDevelopment` (`WarSim.dev`, data `assets/development/*.tres`,
  state `FactionState.dev`) is the only unlock authority: `structure_lock` / `weapon_lock` / `role_lock` for player and AI alike; scenario
  rule `development`. The New Game opening is scenario data (`ScenarioDef.intro`, `extra_objectives`, `structures`) checked against the
  world by `IntroGuide` (`WarSim.intro`) and shown by `ObjectiveTracker`. Tests: `--gameplay04-test --only <check>` (narrow checks).
- **World look (GAMEPLAY-05).** `WorldLook` (`scripts/world/world_look.gd`) sets SSAO, grading, haze, sky, sun colour and two
  terrain texture tints in memory at game start (`CoreDemo._ready`; the generated world scene and manifest are untouched);
  `--legacy-look` switches it off for comparison. Tune the look there, not in `scenes/world/ref_20km.tscn`. Infantry LODs
  cross-fade (`InfantryCharacter.LOD_MARGIN`, fade SELF): plain hysteresis left soldiers invisible at the switch.
- **Aim and capture (GAMEPLAY-05B).** The AI aim model lives in `CombatBrain.AIM_PROFILES` ("g05b" default; `--aim=g04` the
  GAMEPLAY-04 model for comparisons); change accuracy there and validate with `c_arena --arena-seeds=` plus combat03/combat02
  series on both profiles. Capture state is `WarSim.capture_state(o, f)` - every UI surface reads it. A HOLD / REGROUP issued by
  the tactics themselves is marked `tactic_hold` (not the player's order; the squad may build again). `RoadShoulders` eases the
  terrain to the road *mesh* (`MESH_EDGE_M`), which is wider than `RoadNetwork.width`.
- **Terrain collision and slots beside bridges (BRIDGE-NAV-01).** `TerrainCollisionStreamer` turns each HeightMapShape3D chunk
  90° so its quad diagonal is Terrain3D's (mesh, navmesh faces); `Terrain3DData.get_height` is neither triangulation (measure walking
  surfaces with rays). A squad slot beside a deck on wet / too-steep ground goes onto the deck (`SquadControl._free_ground`);
  `SoldierBody._ground_waypoint` reaches waypoints on the ground plane (navmesh heights can be ~1.5 m off).
- **Soldier (VISUAL-03).** MakeHuman body (`char_body_mh` / `char_body`, MPFB extension: build without `--factory-startup`),
  CMU mocap + rifle layer (`char_anim` / `v03_mocap`), built into `assets/characters/infantry/` by `build_infantry.py --export`,
  `build_factions.py --export`, `build_gameplay04_weapons.py --export` (`--root DIR` for trial builds; standard:
  `docs/CHARACTER_STANDARD.md`). Garments are authored in CHARACTER-01 *reference space* and moved onto the body with
  `char_body.to_body_space`. A detachable magazine is a split child of the weapon (`char_weapon.split_magazine`,
  `<weapon>_Mag_LOD*`) that `InfantryCharacter._hang_magazine` puts on `ATT_Magazine`; only `Reload` moves that bone. Write
  bone poses through `char_anim._set_world` (rotation + position only). Movement paces (`WorldSim.pace_of`) are opt-in with
  `--paces`. Validation: `--paces --visual03-test [--shots]` (A-F), `tools/visual03/check_loadouts.gd`, `check_clearance.py`.
- **Combat posture (COMBAT-01).** Stand / crouch / prone is `UnitState.posture` (+ `posture_from`, `posture_at`,
  `posture_hold_until`; saved) read through the `Posture` table (`scripts/combat/posture.gd`): eye (`CombatSim.eye_of`),
  AI look / aim points, analytic hit volumes (`LineOfFire` via `Posture.hit`, `segment_capsule`), speed (`WorldSim.move_speed`,
  both tiers), steadiness, grass top. Never store posture elsewhere; the character and proxies only show it (prone clips
  seeked to `Posture.progress`). Moves stand up through `Posture.for_move` (`WorldState.issue_move`, reactions); the AI picks
  a posture in `CombatBrain._choose_posture`. Prone numbers come from the clips (`char_prone.prone_layout`) - keep them in step.
- **Concealment and perception (COMBAT-01).** Grass only delays noticing (`CombatBrain.acquire_delay`, `Concealment` reads
  the grass placement data); it never blocks sight or bullets (`--no-concealment` off). A kept "visible" answer while
  vegetation cells fill must never refresh a target's position (that leaked hidden enemies); fire needs a sighting within 1.2 s.
- **Combat presentation (COMBAT-01).** Sounds are files from `tools/audio/make_combat_sounds.py` (`assets/audio/combat`,
  original, regenerate - do not hand-edit); `CombatFX` chooses close / distant by listener distance and delays by sound
  travel; nothing moves the player's view except his own recoil. First person is the soldier's own arms
  (`Viewmodel` + `InfantryCharacter`); new weapons follow `docs/CHARACTER_STANDARD.md` §3.1 (sight line z 0.172, `ATT_Muzzle`
  at the muzzle, glass `Lens`, `WeaponDef.ads_fov`). RTS contact markers (`ContactMarkers`) read only the selected soldiers'
  perception records. AI aim profile `c01` (`--aim=g05b` for the old one).
- **Named weapons and vehicles (ASSET-INTEGRATION-01).** A weapon piece carries its hold (`InfantryEquipment.aim_eye` = sight
  line x / height and eye relief, `support_grip`, `hold_shift`; table in `tools/asset_integration/make_weapon_data.py`, which also
  writes the 16 `assets/combat/weapons/<id>.tres`, the development roles `assets/combat/roles/dev/dev_<id>.tres` - a subfolder
  so the equipment screen never lists them - and the `<FAM>_w_<id>` loadouts). `InfantryGripIK` (after the aim / flinch
  modifiers) straightens the head onto the bore, brings the weapon's sight line to the right eye and solves both arms onto the
  weapon's grips for every weapon while aiming; never pose a weapon in SoldierBody. A secondary launcher is
  `WeaponDef.held_piece`. Vehicles of the pack are `VehicleDefs.pack_ids()` (`articulated`, `tracked`, `drivable`; the economy's
  `BaseSim.VEHICLES` and `all_ids()` stay truck / APC); `VehicleVisual` poses their GLB pivots from the sidecar's axes. The
  Development Scenario's armoury (`DevArmoury`, rule `dev_armoury`, F10) gives roles through `CombatSim.give_role`. Tests:
  `--asset-integration-test [--shots] [--only r_registry,w_weapons,f_fps,p_posture,v_switch,v_vehicles,v_drive,v_transport,s_persist]`.
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
- AI-WAR-LOGISTICS-01 scenarios: `--ai-war-test [--only a_init,b_recruit,c_vehicle,d_mech,e_convoy,f_preop,g_delivery,h_shortage,i_counter,j_base_loss,l_player,m_save,n_long,o_war,m_move,m_march,m_haugen]`
  and the road scenarios `--only r_yard,r_exit,r_lanes,r_offroad,r_gaps,r_obstacles,r_convoy,r_overlay` (minutes);
  `r_drive` drives 20 km routes (~20 minutes, optional). `--road-audit` writes `benchmarks/raw/road_audit.json`.
- GAMEPLAY-01B: `--scenario=new_game|dev` / `--continue` skip the start screen (tests default to dev).
  `--scenario=new_game --gameplay01b-test [--shots] --only a_new,a_save,b_economy,b_recovery,c_build,c_ai`
  (`a_dev`, `smoke_dev` with `--scenario=dev`; `a_continue` / `loop_continue` with `--continue`); the integrated loop:
  `--menu-shot --gameplay01b-test --shots --only loop` then `--continue --gameplay01b-test --shots --only loop_continue`.
  Screenshots at 1920x1080 only (`--fullscreen`), in `docs/gameplay01b/`.
- UI-01C HUD (kit in `scripts/ui/kit/`, one style for every mode): `--ui01c-test [--shots] [--only shots,checks,small]`
  (RTS roster / command panel) and `--ui01c2-test [--shots] [--only construction,vehicle,markers,map,fps]` (run
  `--fullscreen` for 1920x1080 captures in `docs/ui_01c/`). HUD sizes are in the 1152x648 logical canvas
  (stretch mode canvas_items). Building thumbnails: `Godot_v4.7.2-stable_win64.exe --path . --script res://tools/ui/make_structure_thumbs.gd`.
- ROAD-QUALITY-01: `--road-quality-test [--only survey,cross,squads,along,shots,probe,perf,nav_climb] [--sites=a,b] [--at=x:z:side]
  [--shot-tag=t]` (results `benchmarks/raw/road_quality_test_<tag>.json`, merged per tag; shots `docs/road_quality01/`, `--fullscreen`).
  `survey` takes ~3 s; `cross,squads,along` ~10 min. A changed shoulder rule recomputes on the next start (~30 s, then cached).
- GAMEPLAY-05 review checks: `--scenario=new_game --gameplay05-test [--shots] --only u_post_block,u_strength,u_markers,u_capture_name,u_bodies,v_tour,q_perf`
  (`v_tour --shot-tag=before --legacy-look` / `--shot-tag=after` for comparable look screenshots with frame rates; `q_perf` the
  opening fight's frame times; `--continue ... --only p_state,p_watch` diagnoses the last test save). Results
  `benchmarks/raw/gameplay05_test.json`, shots `docs/gameplay05/`. Known flaky on unchanged code: `--nav-inf-test` navinf_04 near
  tier (about one run in two); `--campaign-test c_forts` fails (timber guard tower never built; GAMEPLAY-05 report §3.1).
- COMBAT-01 checks: `--combat01-test [--shots] [--only v_detect,p_posture,g_grass,a_accuracy,f_gunplay,t_withdraw,r_markers,s_visibility,p_ai_posture]`
  (one deterministic run each, results `benchmarks/raw/combat01_test.json`, shots `docs/combat01/`; `--fullscreen` for
  1920x1080). Known pre-existing: `--ai-squad-test k_persist` K(suppress)/K(flank) and the `l_perf` tactics step limit.
  Prone / posture clips: `tools/blender/character/char_prone.py`, built by `build_infantry.py --export` (then revert the
  unchanged parts / weapons GLBs it rewrites; keep rig, `animation_meta.json`, `build_log.json`, the blend).
- After adding `class_name` scripts or assets run `Godot ... --headless --path . --import` once (two
  "placeholder instance" SCRIPT ERRORs from VegetationMask / VegetationMeshDef during a headless import are known
  and harmless).
- `docs/combat_tech01/lab/` is an isolated COMBAT-TECH-01 experiment with its own `project.godot` (reference
  material, incomplete: its third-party files were never committed). The editor skips that folder; it is not a
  second game project.
- A script that fails to compile makes a test hang until timeout; check the log head first, or run
  `Godot_console.exe --headless --path . --script res://tools/check_scripts.gd` (compiles every script, exit 1 on failure).
- GAMEPLAY-01C–01G scenarios: `--scenario=new_game --campaign-test [--shots] --only c_forts,c_ai_garrison,d_targets,d_ai_war,d_player_assault,e_replenish,e_expansion,f_damage,f_ai_repair,g_pause`
  (`--fullscreen` for 1920x1080 shots in `docs/gameplay01c/`; results `benchmarks/raw/campaign_test.json`); the campaign:
  `--menu-shot --campaign-test --shots --only g_campaign`, then `--continue --campaign-test --shots --only g_campaign_continue`,
  `--continue --campaign-test --only g_menu_return`. Blender: `build_assets.py -- --only <ids> --export --save-blend` keeps
  `assets/military/blender/<id>.blend`.
- Blender asset pipeline: `tools/blender/` (+Y forward, one joined mesh, origin on the ground,
  material names drive faction colours; character: `tools/blender/character/`, standard in
  `docs/CHARACTER_STANDARD.md`). Always inspect imported assets in Godot, not only Blender.
  The `blender-*` agent skills (EL4CTEO/blender-skills, MIT) are installed in
  `.claude/skills/`; start Blender work with `fn-blender-pipeline` (our conventions on top of
  them) and run the QA gate `build_assets.py -- --qa` after geometry changes
  (`--qa-strict --qa-baseline benchmarks/asset01/qa_baseline.json` = no new defects).
- Vehicle pack (VEHICLE-ASSETS-01): `tools/blender/vehicles/build_vehicles.py` (`ap_vehicle.VehicleAsset` = parts with pivots on top
  of `ap_lib.Asset`; shells with boolean cabin cuts on LOD0; `veh_kit` tyres / tracks / RWS) -> `assets/military/vehicles/<id>/`,
  `.blend` in `assets/military/blender/vehicles/`; Godot check `tools/vehicle_assets/run_vehicle_lab.sh --validate | --shots`.
  Reference photos: `tools/vehicle_assets/fetch_references.py` (Wikimedia rate-limits: standard thumb widths only).
- Weapon pack (WEAPON-ASSETS-01): `tools/blender/weapons/build_weapons.py` (`wpn_lib.Weapon` parts = `PIV_<Part>` pivots, the
  magazine part on `ATT_Magazine`; meshes `<id>[_<Part>]_LOD0/1/2`, weapon space of CHARACTER_STANDARD §3) -> `assets/weapons/{nato,russian}/<id>/`
  (.glb, sidecar, `InfantryEquipment` .tres, `source/*.blend`). New weapon material names must be added to both `build_weapons.WEAPON_MATERIALS`
  and `InfantryMaterials.TABLE`. Godot check `tools/weapon_assets/run_weapon_lab.sh --validate | --shots | --showcase`; references
  `fetch_references.py --pack weapons`.
- Python on Windows: open files with `encoding='utf-8'`.
