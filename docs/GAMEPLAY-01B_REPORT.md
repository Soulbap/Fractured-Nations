# GAMEPLAY-01B — First Playable Foundation

Branch `feature/gameplay-01b` (from `research/gameplay-01a` = `develop` @ `b9bbc3a` + the GAMEPLAY-01A audit). Not merged,
not pushed. Evidence tags: **[RUN]** verified in a runtime run for this milestone (§7), **[CODE]** code inspection only.

> **Branch note.** The brief asked for `feature/gameplay-01b`; CLAUDE.md's standard is work on `develop` with no
> permanent milestone branches. The branch was created as asked. Merge it into `develop` (ordinary merge) when it is
> approved, and do not keep it as a parallel line.

## 1. Executive summary

**Now playable [RUN]:** start the game → start screen → **New Game** → eight North soldiers near Moen in the south, no
base, 500 kg of supplies. Walk to the reported supply cache, hold it ~30 s (+900 kg). Place a Command Post blueprint,
and the idle squad walks over and builds it in about 65 s. The base opens only when it is finished. Then you build a
Supply Depot (the carried supplies move into it), take the next cache and capture Verket (+60 kg supplies per minute),
build Barracks, recruit a squad through the barracks panel, build a Guard Tower, give orders to the new squad and save
with F5. After a restart, **Continue** brings all of it back, and tactical and strategic orders still work. The scripted
run took **26 game minutes** (§7.1). The **Development Scenario** is unchanged: 3 factions, 12 objectives, 15 squads,
120 soldiers, free and instant construction, free reserves.

**Still incomplete:** the AI never targets player bases and structures cannot be damaged (GAMEPLAY-01F). Player squads
cannot be replenished (01E). There is no pause or in-game menu (you quit the program to return to the start screen).
The work pose is the existing crouch, not a dedicated animation. Roads and paved areas are still free and instant. A
person has not played the loop by hand yet; it was driven by a script through the game's own controls (§7.3).

## 2. Implementation by stage

### Stage A — scenarios, New Game, safe saves (`091c2c7`, `93c041f`)
- `ScenarioDef` (`scripts/strategy/scenario_def.gd`) + `assets/scenarios/dev.tres`, `new_game.tres`: player faction,
  objective renames / owners, per-faction profile / reserves / HQ / squads, squads placed in the open, HQ walls, AI
  bases, start pool, caches, camera, rules. `SandboxSetup.create(demo, routes, scenario)` is the one setup path; the
  old `FACTIONS` constant moved into `dev.tres` in the same order, so squad ids and names are unchanged.
- `WarState.scenario_id`, `rules` (copied from the scenario, saved), `caches`, `guide`; `war.rule(key, fallback)` with
  the Development Scenario's behaviour as fallback (old saves behave as before).
- Start screen `MainMenu` (`scripts/ui/main_menu.gd`, UI-01C kit, 1152×648 logical canvas → 1920×1080 / 1280×720):
  New Game, Continue (with the save's scenario and game time, or why it cannot load), Development Scenario, Quit.
  Backdrop: the terrain above New Game's start. `--scenario=<id>`, `--continue` skip it; tests default to `dev`.
- Saves: `CoreDemo.save_dir()` — `user://saves/<world>/` for play, `user://test_saves/<world>/` whenever a `-test` /
  `-perf` / audit / demo flag is present (also the logistics test's own files). `ConstructionController.load_game()`
  checks both files before replacing anything; a damaged or unknown save is refused with its reason [RUN a_save].
  New Game writes nothing until the player saves.
- Faction-0 assumptions removed: start camera from the player's HQ (if the scenario says so and he holds it) or his
  first squad; `TacticsOverlay.player_faction` reads `WarState.player_faction`.

### Stage B — economy (`0deeabc`)
- `BuildCosts` (`scripts/construction/build_costs.gd`): supplies and soldier-seconds per type, per module for lines;
  `AiBases.BUILD_COST` *is* this table (the AI's values unchanged).
- `FactionState.pool` (Inventory, no capacity, saved): stock without a building. `BaseSim.faction_pay` (atomic; pool
  first, then the order's base, then other bases; returns where it came from), `faction_refund` (back exactly there),
  `faction_deposit` (supply stores, else the pool), `_settle_pool` (pool → first operational supply depot by
  `Inventory.transfer`, once a second). New Game: no `START_STOCK` gift, no free reserve squads.
- Supply caches (`WarSim._update_caches`, in the 1 s capture tick, objective presence rule): known within 260 m;
  one faction alone in the 30 m radius with no other faction within +80 m secures it in 30 s (one soldier: 45 s);
  content paid once; depleted forever; the next unknown cache is revealed ("papers point to …").
- Player income (`WarEconomy.player_income`): scenario rates × owned objective value per minute into stores / pool,
  ledgered; one war-log line per minute (not a toast).
- Paid recruitment (`BaseSim.recruit`): from pool + bases, payment record in the queue entry (cancel refunds it);
  bed limit for the New Game player (soldiers + recruits ≤ beds).
- Recovery (`WarSim._update_recovery`): no soldier left and no barracks able to train → a section of 4 after 120 s at
  the command post (else the start point); never while a soldier lives; saved (`recovery_at`); repeatable; free.
- Feedback: `EconomyHud` (supply strip with income/min and personnel, one dismissible hint, cache and site markers);
  caches on the strategic map; prices and "Needs N kg" on the build cards; cost in the placement panel; refusals with
  the reason.

### Stage C — construction sites and BUILD (`6f0c6af`, + loop fixes in the final commit)
- `StructureState.site` (saved): work, need, payment, crew, workers/why. `ConstructionState.add_site / add_line_site /
  add_work / cancel_site`; `structure_completed` fires once when work ≥ need. `BaseSim` and `LogisticsSim` ignore sites
  and run their normal "added" logic on completion; `facilities_of` excludes sites; a command-post site claims its area
  for placement rules.
- Placement (`ConstructionController`, rule `build_sites`): a paid site, clearings at once, the nearest idle squad called
  (`SquadTactics.assign_builders`). Cancel (Demolish tool on a site, or the site panel) refunds the full payment; a
  finished building is never refunded.
- `SquadTactics` BUILD (`Tactic.BUILD`, `SquadState.tactic_site`): work posts on a ring 1.4 m outside the footprint
  (second ring at 3.9 m; line modules: both sides) on `SquadPositions.valid_ground`, ≥ 1.8 m apart, nearest first;
  soldiers within 3 m of their post, not suppressed, not under fire, not reacting add `tick × workers` to the site.
  A squad more than 120 m away first marches with an ordinary squad move (route system) and starts BUILD on arrival.
- Visuals: sites drawn by `StructureManager` with a translucent construction material, the model squashed to the
  height built (redrawn every 10 %, no navmesh rebake); kneeling soldiers (runtime `UnitState.work_until`); HUD site
  marker (progress, workers or why); site panel (progress, builders, time left, cost, build / cancel).
- AI construction: `AiBases.request` creates the same site record with a crew rate `need / BUILD_TIME_S`, worked in
  `AiBases.update` (the old pending records of earlier saves are still finished by the old code).

## 3. Scenario setup (New Game)

| | |
|---|---|
| Start | one North squad of 8 at **(−1350, 6950)**, yaw −0.6, between Moen (−1500, 7100) and Verket (−350, 6150) |
| Why there | the probe (`--only probe`) found open ground with a road 17 m away, many flat Command-Post sites within 300 m (level ≤ 0.2 m), Verket 1.2 km (first income), no objective radius, nearest enemy soldier 6.8 km, nearest enemy base 11.4 km |
| Player | North (faction 0), NATO kit, 0 objectives, 0 bases, 0 structures, 0 vehicles, 24 personnel in reserve |
| Pool | 500 kg supplies, 120 kg ammunition |
| South (aggressive) | Nordmoen HQ (old North HQ, −7100, −7600) with its main base and HESCO, Elvetun, North Bridge; 5 squads (3 / 1 / 1), 40 reserve |
| East (defensive) | unchanged: East HQ (base, HESCO), Østby, Ødegård; 5 squads, 40 reserve |
| Neutral | Sørmoen (old South HQ, now a village, value 2), Verket, Sentrum, Haugen, Centre / South Bridge |
| Totals | 11 squads, 88 soldiers [RUN a_new] |

## 4. Economy

| Item | Value |
|---|---|
| Start | 500 kg supplies, 120 kg ammo (Command Post affordable at once: no softlock) |
| Costs (supplies) | Command Post 400 · Supply Depot 450 · Barracks 550 · Guard Tower 150 · Vehicle Parking 120 · Ammo Magazine 320 · Fuel Point 160 · Vehicle Depot 750 · Sandbag position 45 · HESCO 12/module · other types by footprint (15–600) |
| Work (soldier-s) | Command Post 480 (≈ 60 s with 8) · Depot 560 · Barracks 640 · Guard Tower 280 · Sandbag 96 · HESCO 16/module |
| Caches | Moen farm 900 + 150 ammo (reported at start, ~430 m) · Verket yard 700 + 200 ammo (1.4 km) · Sørmoen 1200 + 300 ammo (near the neutral Sørmoen) · South Bridge 1000 + 250 ammo + 300 fuel |
| Income | 30 supplies, 12 ammo, 8 fuel per objective value per minute (Verket value 2 → 60 / 24 / 16 per min); personnel 0.25 / value / min |
| Recruitment | 320 kg supplies + 192 kg ammo + 8 personnel, 60 s, needs an operational barracks and beds (Command Post 8, Barracks 32) |
| Free help | none while soldiers live; recovery section of 4 after 120 s on total loss |

Typical order: cache (1400) → Command Post (1000) → Depot (550) → second cache + Verket → Barracks → recruit → Guard
Tower. Development Scenario: all of this off (free instant construction, 9000 / 4000 / 6000 starting stockpile, free
squads every 240 s).

## 5. Construction

- **Eligibility (automatic):** the player's own squads in a `build_sites` scenario with no operation, no garrison
  station, no tactic, not marching, aboard nothing, order NONE or an arrived MOVE (never HOLD), not in contact, and not
  taken off a site by the player in the last 120 s. Checked every 3 s per squad, sites within 150 m; a new site calls the
  nearest eligible squad within 900 m.
- **Explicit:** right-click a site with squads selected, or "Build with selected squads" in the site panel → BUILD owned
  by the player (releases them from operations).
- **Progress:** work posts as in §2; only soldiers at their post work; 8 soldiers build a Command Post in 65 s [RUN].
  Several squads add up.
- **Interruption:** any player order ends BUILD (progress kept, why shown on the site, no automatic return for
  120 s); contact or fire ends a squad-owned BUILD (the squad's own tactics take over; no automatic return for 30 s) and
  pauses a player-ordered one; a site nobody reaches in 90 s is left for 60 s ("cannot reach").
- **Persistence:** the site (work, payment) is in `construction.json`, the squad's BUILD and `tactic_site` in
  `world.json`; after loading, the squad carries on [RUN].
- **Near / far:** the same step on the record in both tiers [RUN: 35 s near vs 39 s far for a guard tower, §7].

## 6. Architecture — what was reused, what was extended

| Need | Owner extended | New code |
|---|---|---|
| Start configuration | `SandboxSetup.create` | `ScenarioDef` resource + 2 files |
| Saves | `ConstructionController.save/load_game`, `WorldState.snapshot` | save folder choice, pre-load validation |
| Resources | `Inventory`, `BaseSim`, `WarEconomy` | `FactionState.pool`, `faction_pay/refund/deposit`, `BuildCosts` |
| Caches | `WarSim` capture tick, `log_event` | `WarState.caches` records |
| Recruitment | `BaseSim.recruit`, `WarSim.spawn_squad` | payment record, bed limit |
| Construction | `StructureState`, `ConstructionState`, `StructureManager`, `AiBases` | `site` record, `add_work`, site visuals |
| Workers | `SquadTactics` (tactic + owner precedence), `SquadPositions.valid_ground`, `issue_move` / `post_pos` | `Tactic.BUILD` |
| UI | `GameHUD`, `LogisticsPanel`, `ConstructionPanel`, `StrategicMap`, UI-01C kit | `MainMenu`, `EconomyHud` |

No new simulation loop, worker pool or navigation representation. Order of authority stays player > operation > squad
tactic > reaction (BUILD is a squad tactic; the player's BUILD is a player tactic).

## 7. Gameplay validation

All runs: Godot 4.7.2 console build, RTX 3070, `--gameplay01b-test` unless stated, saves in `user://test_saves/`.

### 7.1 Integrated first-playable run [RUN] — `docs/gameplay01b/loop_*.png`
`--fullscreen -- --menu-shot --gameplay01b-test --shots --only loop` (the start went through the real menu: its
New Game button), then a second process `--fullscreen -- --continue --gameplay01b-test --shots --only loop_continue`.
Time compression (×2–×8) on the walks; times below are game time.

| # | Step | Result |
|---|---|---|
| 1 | Eight North soldiers in the south | ✔ (−1350, 6952), scenario new_game |
| 2 | Select the squad (tactical view) | ✔ |
| 3 | Strategic map with the reported cache | ✔ `loop_03_map` |
| 4–6 | Move to the cache, secure, supplies up | ✔ arrived ~2 min, secured, +900 kg |
| 7–8 | Command Post location, blueprint through the construction tool's cursor | ✔ "N1 is on the way to build it", −400 kg |
| 9–10 | Soldiers build it; base on completion | ✔ 65 s, 8 working, no base before, "North base 1" after |
| 11–12 | Supply Depot; pool into the depot | ✔ depot holds 550 kg + 270 kg ammo, pool empty |
| 13 | More supplies | ✔ second cache taken, Verket captured (+60/min) |
| 14 | Barracks | ✔ (squad marched back ~1.2 km, then built) |
| 15 | Recruit through the barracks panel button | ✔ squad N2 after 60 s |
| 16 | Defensive structure | ✔ Guard Tower |
| 17 | Command the new squad | ✔ 8 soldiers moving |
| 18 | Save (F5 key) | ✔ 26.0 game minutes after the start |
| 19–20 | Exit, restart, Continue | ✔ continue ok, scenario new_game |
| 21 | Squads, buildings, resources, ownership persisted | ✔ 2 squads / 16 soldiers / 4 structures / 1 base / 990 kg / Verket North / caches |
| 22 | Tactical and strategic orders | ✔ DEFEND at the base, ATTACK operation on Sørmoen moving |

### 7.2 Targeted checks [RUN]

| Check | Result |
|---|---|
| `a_new` | 1 squad / 8, no base/structures/vehicles/objectives, South north (base z −7651), Verket/Sørmoen neutral, East unchanged, camera on the squad, RTS move, map, possession and back |
| `a_save` | test folder; damaged world.json refused by Continue and F9 with the reason, nothing changed; load restores counts, owners, pool, scenario, rules; the player's own save untouched |
| `a_continue` | `--continue` starts New Game from the save |
| `a_dev` / `smoke_dev` | 3 / 12 / 15 / 120, North HQ the player's, AI bases South + East, old rules; no supply strip; 120 s later 19 squads (free reserves + AI recruits) |
| Menu | `menu_1920x1080.png`; New Game started through the menu |
| `b_economy` | start 500/120; no free squad; cache secured in 29 s, +900/+150 once, next revealed; unaffordable Command Post refused with the reason; paid exactly 400; depot takes the pool without loss; no free stockpile; Verket pays 60/min; recruit paid 320/192, cancel refunds exactly; recruit after 60 s, commandable; economy restored by save/load |
| `b_recovery` | all killed → section of 4 after 120 s, pending arrival survives save/load, nothing more while soldiers live |
| `c_build` | CP site assigned at placement; no base at 40 %; 65 s with 8; idle after; player order stops work (progress kept 142→142) and no automatic return; right-click build order; fire pauses (0 work) and resumes; save mid-build → same work (158/158), same stock, squad resumes; one depot; cancel refunds 150 exactly; near 35 s / far 39 s, no bodies far |
| `c_ai` | South order = crewed site, finished in 90 s (BUILD_TIME_S 90), operational store of South's main base |

Regression runs for the changed shared code (Development Scenario): `--ai-war-test --only a_init,b_recruit` PASS
(after B), `--base01-test --only persist` PASS, `--ai-squad-test --only g_player` PASS, `--ui01c-test --only checks`
PASS (after C). No full suite was run.

### 7.3 Verified vs inspected
- Verified at runtime: everything in 7.1 / 7.2. The loop used the game's own paths: the menu button, `RTSController`
  selection and order calls, the construction tool driven through its cursor (`mouse_override`, `primary_action`), the
  barracks panel's real button, the F5 key.
- Not verified: a person playing with mouse and keyboard; play under AI pressure (no enemy came near during the 26
  minutes); `--logistics-test --only bases,persist_logistics` (the 4 pre-existing failures were not rerun); 1280×720 at
  runtime (the layout is the same logical canvas; screenshots were taken at 1920×1080 only, at the product owner's
  request).

## 8. Screenshots (1920×1080, `docs/gameplay01b/`)
`menu_1920x1080` start screen · `loop_01_start` New Game start · `loop_03_map` map with the reported cache ·
`loop_05_cache_securing` cache 47 % · `loop_08_cp_blueprint` Command Post placement · `loop_09_cp_construction` site
53 %, 8 working · `loop_12_base_depot` base with depot · `loop_15_recruit` barracks panel, training a squad ·
`loop_17_base_overview` base with barracks, depot, guard tower, two squads · `loop_20_continued` after Continue ·
`loop_22_map_operation` attack operation from the continued game · `dev_scenario` Development Scenario.

## 9. Performance
- Development Scenario, 120 s at ×4 [RUN smoke_dev]: per physics tick `tactics` 16.6 µs, `war` 23.6 µs, `brain`
  469.5 µs; one SquadTactics step (every 0.5 s, 15–19 squads) 497 µs avg, 731 µs max. BUILD adds nothing there
  (`build_eligible` fails on the rule first). No baseline was measured on `develop` with the same run, so this is an
  absolute figure, not a comparison.
- New costs: caches — one `_near` query per cache per second; `AiBases.update` — one pass over the structures per
  second; auto-build — one pass over the structures per eligible player squad every 3 s; site visuals — a cell redraw
  per 10 % of progress. No per-frame scans.

## 10. Known issues and limits
1. AI factions never target player bases; structures have no condition (01F).
2. Player squads cannot be replenished, only new ones recruited (01E).
3. No in-game menu (Esc) to save and return to the start screen; one save slot; New Game asks no confirmation (it
   overwrites nothing until F5).
4. Near/far build time differs by about 11 % (35 vs 39 s): walking to the posts is slower in the abstract tier
   (`abstract_friction`); the work itself is identical.
5. A line site (HESCO) is cancelled as a whole (no per-module cancel); work posts for lines are both sides of every
   module.
6. Roads and paved areas are still free and instant in New Game.
7. Work pose = crouch (existing clip); site look = translucent tinted model rising with progress, no scaffolding asset.
8. AI squads can collect a cache they walk through (same presence rule), but the AI does not seek caches.
9. The recovery section is free (it does not use reserves); it cannot be farmed because it needs the loss of every
   soldier.
10. Scripted test helpers place buildings on open ground first; the real game lets the player place in forest (trees
    are cleared), where sites are hard to see from above.
11. The construction panel shows prices only when the scenario charges; the Development Scenario keeps its free cards.

## 11. Recommended next step
**GAMEPLAY-01E (small part first): replenishment at the barracks + Defend Area on structures.** The New Game loop now
builds bases and squads, but casualties can only be replaced by whole new squads, and the guard tower and HESCO the
player builds are not yet positions anyone mans. Replenishing a depleted squad at a barracks (`_fill_depleted` for the
player, paid through `faction_pay`) is the smallest next change that makes the bases matter in a fight; firing
positions on structures follow. Before that, a short manual playtest of New Game by the product owner is recommended
to tune the cost / income numbers in `new_game.tres` and `BuildCosts`.

## Files
New: `scripts/strategy/scenario_def.gd`, `assets/scenarios/{dev,new_game}.tres`, `scripts/construction/build_costs.gd`,
`scripts/ui/main_menu.gd`, `scripts/ui/economy_hud.gd`, `scripts/debug/gameplay_selftest.gd`, `docs/gameplay01b/*`.
Changed: `sandbox_setup.gd`, `core_demo.gd`, `war_state.gd`, `faction_state.gd`, `war_sim.gd`, `war_economy.gd`,
`ai_bases.gd`, `base_sim.gd`, `logistics_sim.gd`, `construction_state.gd`, `structure_state.gd`, `structure_manager.gd`,
`construction_controller.gd`, `squad_tactics.gd`, `squad_state.gd`, `unit_state.gd`, `soldier_body.gd`,
`rts_controller.gd`, `game_hud.gd`, `logistics_panel.gd`, `construction_panel.gd`, `strategic_map.gd`,
`squad_panel.gd`, `tactics_overlay.gd`, `logistics_selftest.gd` (test save path); `README.md`, `CLAUDE.md`.
Results: `benchmarks/raw/gameplay01b_test.json` (last run).
