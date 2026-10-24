# GAMEPLAY-01C–01G — Base Warfare, Defensive Assets & Dynamic Campaign

Work on `develop`; GAMEPLAY-01B was already merged there (`f71ae21`), so no merge was needed. One commit per stage, not pushed:
`dbd507b` 01C · `c9f9968` 01D · `b322330` 01E · `c226984` 01F · `29cebfc`, `6a95d83`, `7f55630` 01G · this report.
Evidence tags: **[RUN]** verified in a runtime run of this milestone (§5), **[CODE]** inspected only.

## 1. Executive summary

**Now playable [RUN].** From the start screen's New Game the player does the GAMEPLAY-01B early game (cache, Command Post,
Supply Depot, Verket, Barracks, a recruit), then builds a fighting position and an MG emplacement, orders a squad to
**Garrison** the base (key **O**) and sees its soldiers take the towers, positions and walls; attacks a South outpost from the
strategic map with two squads and captures it with its buildings intact; meets a South counterattack (warned, repelled);
repairs a damaged command post; founds a third base; saves with F5. After a restart **Continue** brings back ownership, squads,
buildings, damage, garrisons, resources and operations exactly, and the AI factions carry on (East launched a new attack).
That run took 49 game minutes from the menu (§5.3). **Esc** opens an in-game menu (resume, save, load, main menu, quit).

**In the war [RUN].** Every base is a strategic objective: the AI chose an enemy base as its best target on its own, attacked it
with its operation machinery (support, assault, secure) with the camera 6 km away and captured it; garrisons fight from
fortifications (460 shots from the slots, none into their own walls); AI factions expand with a Defensive Base template
paid and built site by site; structures take damage, are disabled (a barracks stops recruiting) and are repaired by soldiers
or AI crews; depleted squads are refilled in place at a barracks.

**Not done / limits** (§6): no MG weapon exists, so the MG slot takes any soldier; slots are entered by a short snap from the
access point (no climbing animation); rifles are the only weapon, so heavy damage in the tests comes through the damage API; AI repairs and AI
construction use abstract crews; one pre-existing `--ai-strat-test a_assault`
failure (same on the code before this work). A person has not played it by hand yet.

## 2. Implementation

### 2.1 GAMEPLAY-01C — defensive positions, garrison and assets (`dbd507b`)

- **Slots as data.** `DefenceDefs` (`scripts/construction/defence_defs.gd`) is a table like `FacilityDefs`: per structure type a
  list of slots (local position, facing, sector, access point, optional role `mg`), or a line rule (HESCO MIL1 and sandbag walls:
  a slot behind every n-th module, on the side towards the base). The numbers follow the assets' `IP_*` / new `DEF_*` markers.
  Covered: steel and timber guard towers (two elevated slots each), the new fighting position (2) and MG emplacement (gunner + one),
  the existing two-man sandbag position (2), HESCO (every 3rd cell), sandbag walls (every module). Tall HESCO, the old MG nest
  (roof at 1.6 m: a standing soldier's eye is inside it) and the bunker (one solid collision box) have no slots.
- **Who holds a slot is on the soldier record** (`UnitState.fort_slot`, `fort_pos`, `fort_exit`, saved). No reservation table: a
  slot is taken while a living soldier of the faction has it in his record, so death, any other order, a disabled or captured
  structure all free it by themselves. `SquadPositions.fort_slots` returns the free slots of operational structures of the
  faction near a point, ranked by facing against the believed threat (never a hidden enemy) and distance.
- **Taking and leaving a slot.** The soldier walks to the slot's access point with an ordinary move order, then takes the slot
  (`SquadTactics._tend_forts`): both tiers hold him exactly at `fort_pos` — `WorldSim._abstract_step` and `SoldierBody._hold_fort`
  (a tower platform too: no navmesh or ladder climbing needed). Any move / hold order steps him out to the exit first
  (`WorldState.leave_fort`); a body follows its record. In a slot `CombatBrain.order_mode` is `fort`: he fires and is suppressed
  normally, but makes no cover moves out of the position. A slot whose structure is gone / disabled / captured is given up and the
  defence re-plans (REPOSITION).
- **DEFEND uses fortifications.** `SquadTactics._defend_posts`: free slots within 35 m of the spot first, natural cover posts for
  the rest (the old search, unchanged). REPOSITION uses the same. A slot "protects" within its sector (`_bad_posts`).
- **GARRISON_BASE** = `SquadState.garrison_base` (saved). `SquadTactics.assign_garrison` / `order_garrison`; `_garrison_step` marches
  the squad to the base when away and starts DEFEND at the base with the whole base area as slot radius (slots spread round the
  base when no threat is known, facing the threat otherwise). It stays until another order: every non-internal order clears it
  (`on_order`), a lost base clears it. Player garrisons run under player authority (no autonomous withdrawal); AI garrisons are
  squad-owned and are not ended by calm.
- **AI garrisons.** `WarSim._garrison` (end of a successful operation) and `_update_garrisons` (every 5 s, idle stationed AI
  squads) assign the base on the objective; real squads, no free units, and the AI's existing keep-counts decide how many.
- **Player interface.** `O` / the command panel's Garrison button (click a base), the facility panel's "Garrison this base with
  the selected squads"; the squad list and panel show `GARRISON · <base>`; any other order cancels it.
- **Assets** (§4): new `fighting_position` and `mg_emplacement`, rebuilt `guard_tower_steel`.

### 2.2 GAMEPLAY-01D — bases as strategic targets (`c9f9968`)

- **One base = one objective.** `WarSim.sync_bases` (every 5 s and after a load) links each base to an objective: the objective it
  stands on if its faction holds it (a headquarters base keeps its HQ objective), else its own objective of kind `base`
  (`ObjectiveState.base_id`, saved; name, position and radius follow the base; value 1 + stores + barracks/HQ building). The base
  record stores the link (`ConstructionState.bases[].objective`, saved). A base objective disappears with the base's last
  facility; operations on it end ("no longer exists").
- **Ownership has one authority**: the objective's owner. Capture is the existing objective rule (presence, contest, decay) and
  `WarSim._transfer` hands over exactly the bases *linked* to that objective (before, any base within the radius + 60 m went
  with a neighbouring town). `BaseSim.capture_base` now also takes the base's non-facility structures (towers, positions, walls)
  intact; queues are refunded as before.
- **Everything else is reused unchanged**: the strategic scorer sees base objectives as attack / defence / garrison candidates, the
  operation lifecycle and `OpCoordination` roles run the assault, the map shows them (new walled-square symbol) and the
  player orders attacks on them from the map like on any objective. Base objectives give no income (economy baseline kept).
- **Warnings** for the player's bases (`WarSim._update_base_alerts`, every 5 s, from the faction's IntelSim picture and the
  capture state only): enemy activity near, a possible attack (enemy within radius + 220 m), under attack (contested or being
  captured), each once until 180 s of quiet. Toasts with a place are clickable (tactical camera goes there); map events too.
- **Fix found by the tests**: a squad taken out of an operation (a player order) counted as casualties, so a coordinated attack
  withdrew after a player override. `release_squads` now removes its strength from the operation.

### 2.3 GAMEPLAY-01E — AI expansion and replenishment (`b322330`)

- **Replenishment** (`BaseSim.replenish`): a queue entry `replenish` at an operational barracks for a squad of the same faction
  standing at the base (within 220 m): missing soldiers up to the squad size (never more, other pending replacements counted),
  personnel from the reserves, cost = recruit cost per soldier (320 / 192 per eight), paid like a recruit (the player from pool and
  bases, the AI from the base), bed limit for the New Game player, time = 60 s per eight, at least 20 s. On completion the
  recruits spawn at the barracks and join the squad (`add_to_squad`, fire teams re-validated) — same id and name. If the squad has
  left the base the entry waits (saying why); if it was wiped out the paid recruits form a new squad. Cancel refunds exactly
  (payment record) and returns the personnel. Saved with the facility's queue. Player: barracks panel "Replenish <squad> +n
  (cost)". AI: unchanged existing path (recruits of a finished AI squad first fill depleted squads at the base,
  `_fill_depleted`); no extra AI replenishment decision was added.
- **Emergency recovery unchanged**: it triggers only with no soldier alive and nothing queued (replenishment entries count as
  queued), so normal replenishment can never start it.
- **AI expansion** (`AiBases` templates Forward Outpost / Defensive Base / Main Base from existing buildings only; `WarEconomy`
  decision `expand`): scenario rule `ai_expansion` (on in New Game, off in the Development Scenario so its baseline is unchanged),
  at most `ai_base_limit` (2) established bases beyond the first, one expansion at a time, 900 s cooldown, none before 300 s, a
  supply reserve beyond the template cost, at least 3 squads. Site: a held, non-HQ objective at least 1.5 km from every
  established base, with no enemy reported within its radius + 600 m and not threatened; preferring value and closeness to the
  front, at the objective's edge on the side of the main base. Main Base is chosen when the faction has no operational barracks
  (recovery after losing it). Construction is the shared site path (`AiBases.request`: paid, crew rate, site record); the
  record `WarState.expansions` (saved) advances when each building stands; when the template is complete one free squad
  garrisons the base. A command post lost before it stood ends the expansion.

### 2.4 GAMEPLAY-01F — damage, repair and recovery (`c226984`)

- **Condition** on the structure record: `StructureState.hp` (-1 = undamaged) and `repair` (a work record with the same fields
  as a construction site), both saved; points and resistance per type in `StructureHealth` (one table, like `BuildCosts`).
  Bands: damaged below 70 %, **disabled** below 35 %, destroyed at 0. Damage never deletes a structure; the base, its owner and
  the stores of a disabled building stay.
- **Damage from combat**: a shot whose trace ends on a structure damages it by `WeaponDef.damage × structure_mult ×
  StructureHealth.resist(type)`. Rifles barely scratch fortifications: 300 rounds at the steel tower from 60 m (223 hits) took
  8 % [RUN]. No heavier weapon exists; `ConstructionState.damage` is the API an explosive will call (the tests use it for
  heavy damage).
- **Disabled = no function** (`is_operational()`): barracks refuse recruits and replacements, a store gives and takes nothing
  (its stock is kept), beds drop (`capacity`), vehicle depot refuses, queues pause, guard posts and fortification slots are given
  up (soldiers on a disabled tower step out). Emergency recovery checks the barracks' operational state too.
- **Repair = construction work on the same record**: `ConstructionController.order_repair` (panel "Repair (n kg supplies)") pays
  `repair_cost` (60 % of the build cost per missing share) and starts the repair record; the BUILD tactic works it exactly like
  a site (auto-build by idle squads, right-click with selected squads, the panel button), contact stops / fire pauses it,
  progress is kept and saved. Development Scenario: free and instant, like its construction. AI: `WarEconomy` chooses
  `repair_structure` for the most important damaged structure when the stores can pay and no enemy is reported within 400 m;
  `AiBases.request_repair` pays from the base and an abstract crew works it (stops while enemies are reported near).
- **Capture keeps damage** (the record moves owner, `hp` stays) [RUN].
- **Look**: damaged structures get a world-space soot / scorch overlay that covers more per band; a destroyed one slumps a little.
  Only the cell's visuals are redrawn when the band changes (no navmesh rebake, collision unchanged).
- **Faction recovery** is the sum of what exists: surviving squads stay, garrisons of remaining bases hold, the strategic scorer
  re-evaluates every decision, a faction without an operational barracks expands with the Main Base template when it can pay,
  and repairs restore damaged facilities. No resurrection system.

### 2.5 GAMEPLAY-01G — in-game menu, integration and campaign (`29cebfc`, `6a95d83`, `7f55630`)

- **In-game menu** (`PauseMenu`, UI-01C kit, same layout language as the start screen): **Esc** pauses the tree (the simulation
  stops) and shows Resume / Save Game / Load Game / Main Menu / Quit Game; Esc or Resume returns (first person gets its captured
  mouse back). Save and Load use the existing safe path (`ConstructionController.save` / `load_game`: both files validated
  first; a damaged save is refused with its reason and the Load button is disabled). Main Menu and Quit ask once for
  confirmation; Main Menu reloads the scene and shows the start screen (`CoreDemo.return_to_menu`) without starting a scenario.
  Esc keeps its old meanings first: it closes the map, cancels a construction tool, an armed order or a selection; only with
  nothing to cancel does it open the menu.
- Campaign validation, operations / navigation / economy review: §5.3–5.5.

## 3. Architecture

| Need | Owner extended (no parallel system) | New data |
|---|---|---|
| Fortification positions | `SquadPositions` (search), `SquadTactics` DEFEND / REPOSITION (use), `WorldSim._abstract_step` + `SoldierBody` (holding), `CombatBrain.order_mode` (no cover moves in a slot), `WorldState.issue_move` / `halt` (leaving) | `DefenceDefs` table; `UnitState.fort_slot/fort_pos/fort_exit` |
| GARRISON_BASE | `SquadTactics` (order authority, DEFEND), `RTSController`, `TacticalPanel`, `LogisticsPanel`, `WarSim._garrison` | `SquadState.garrison_base` |
| Bases as targets | `WarSim` (capture tick, `_transfer`, strategic AI, operations) | `ObjectiveState.base_id` / kind `base`; `bases[].objective` |
| Capture of a base | `WarSim._transfer` → `BaseSim.capture_base` (the only path) | — |
| Warnings | `WarSim.log_event`, `GameHUD` toasts, map events | runtime alert state |
| Replenishment | `BaseSim` queue (recruit rules), `WarSim.spawn_recruits`, `WorldState.add_to_squad` | queue entry kind `replenish` |
| AI expansion | `AiBases.request` (paid sites, crews), `WarEconomy.decide` | `AiBases.TEMPLATES`, `WarState.expansions`, `FactionState.expand_next_at`, rules `ai_expansion` / `ai_base_limit` |
| Damage / repair | `CombatSim.resolve`, `ConstructionState` (`damage`, `start_repair`, `add_work`), BUILD tactic, `AiBases` crews, `BaseSim` function checks | `StructureHealth` table; `StructureState.hp/repair`; `WeaponDef.structure_mult` |
| In-game menu | `CoreDemo` (save / load / start screen), UI-01C kit | `PauseMenu` |

- **Authority**: player > operation > squad tactic > reaction is unchanged. A garrison is a squad-level order: the player's runs
  under player ownership and never withdraws or ends on its own; any player order or operation ends it. AI garrisons are
  squad-owned.
- **Persistent state** is only in the saved records listed above; slot occupancy, alerts and expansion search state are derived
  (`fort_pos` is saved so a loaded soldier is still in his tower).
- **AI decision flow** unchanged: `StrategicDecision` scores base objectives like others (value, distance, believed defenders,
  route risk) → `start_operation` → `OpCoordination` roles and stages → `SquadTactics` → `CombatBrain`; `WarEconomy` adds two
  candidates (`expand`, `repair_structure`) to its utility list.
- **Near / far**: every new behaviour runs on the records in both tiers (the slot hold, capture, damage, repair work, AI crews,
  expansion). The AI-vs-AI base capture ran entirely without bodies near it [RUN d_ai_war].

## 4. Blender assets

| Asset | Source (Blender) | Export | LOD0/1/2 tris | Materials | Collision | Slots |
|---|---|---|---|---|---|---|
| Fighting position (new) | `fam_modules.fighting_position`, `assets/military/blender/fighting_position.blend` | `assets/military/modules/fighting_position.glb` + `.json` + `defs/fighting_position.tres` | 6444 / 96 / 48 | Sandbag, Dirt, Timber, Paint_OD (shared library) | 3 boxes (front and side parapets, 1.08 m) | 2 riflemen |
| MG emplacement (new) | `fam_modules.mg_emplacement`, `.../mg_emplacement.blend` | `.../modules/mg_emplacement.glb` ... | 11576 / 168 / 72 | + Plywood | 6 boxes (parapets 1.2 m, roof from 2.22 m, two posts) | gunner (role mg) + assistant |
| Steel guard tower (rebuilt) | `fam_buildings.guard_tower_steel`, `.../guard_tower_steel.blend` | `assets/military/buildings/guard_tower_steel.glb` ... | 2872 / 908 / 284 | unchanged | legs, floor, 4 breastwork walls to +1.05 m, roof from +1.85 m | 2 elevated |
| Timber guard tower, HESCO, sandbag wall, two-man sandbag position | existing | existing | — | — | unchanged | via DefenceDefs |

- Built by the project pipeline (`build_assets.py`, background Blender 5.2), `--save-blend` (new) keeps the editable scene of
  each built asset in `assets/military/blender/` (with `.gdignore`, so Godot does not try to import `.blend`).
- New sandbag walls: pillow-shaped bevelled bags in running bond over an earth core (the library's older lens-shaped bags show
  light between them); QA gate: 0 errors for both new assets; the tower has no finding beyond its recorded baseline.
- Godot validator (`benchmarks/asset01/run_lab.sh --validate`): 0 errors for all three. Previews: `docs/gameplay01c/blender/`.
- Why the tower was rebuilt: its cabin was one solid collision box with glass at 1.05–1.55 m; a sentry (eye 1.6 m in the
  simulation) stood inside the box and no shot could leave it. Now an open firing band at 1.05–1.85 m over a breastwork.

## 5. Testing

All runs: Godot 4.7.2 GUI build, RTX 3070, ref_20km, saves in `user://test_saves/`. Screenshots 1920×1080 (`--fullscreen`)
in `docs/gameplay01c/`. Compile check before every run: `tools/check_scripts.gd` (new).

### 5.1 New scenarios (`--scenario=new_game --campaign-test --only …`)

| Check | Result [RUN] |
|---|---|
| `c_forts` | the squad built CP, fighting position, MG emplacement, steel + timber towers, a 24-cell HESCO line (0 gaps) and a sandbag wall as paid sites (206 s); Garrison through the RTS order: 6–8 of 8 soldiers in distinct slots (0 duplicates), 4 on tower platforms, MG emplacement manned; 460 shots fired from the slots at an enemy squad, 0 blocked by their own fortification; save / load: garrison and all 8 slots back; a move order empties every slot and ends the garrison, nobody left inside a footprint or on a platform; DEFEND next to the MG emplacement takes it (2 MG slots) |
| `c_ai_garrison` | South mans its HQ base (7 soldiers in HESCO slots, 1 garrison squad of 10), no squads created |
| `d_targets` | the player's CP base becomes objective "North base 1" (kind base, owner North, value 1, no income); South's HQ base stays linked to Nordmoen HQ; map symbol; an approaching enemy squad raises "Possible attack on North base 1 …" once |
| `d_ai_war` | an East outpost 1.3 km from South's free squads: **South chose it itself** (best target, utility 4.2, after 250 s), marched 5.5 km round the river, fire support → assault → secure, capture contested, completed ("East base 2 captured"), base + 4 structures South's intact, East's garrison ended, 0 bodies near (camera 5.8 km away), save / load mid-march continued the operation |
| `d_player_assault` | strategic-map ATTACK with 4 squads on a South outpost; one squad taken out by a direct order (the operation went on: fix in §2.2); captured, all 4 structures now the player's |
| `e_replenish` | 3 of 8 killed; replenish: 120 kg supplies + 72 kg ammo + 3 personnel paid; second request refused ("replacements on the way"); cancel refunded exactly; saved and loaded with the entry; 24 s later the same squad N1 has 8 soldiers, 2 fire teams, still one squad |
| `e_expansion` | South (supplies topped up for the test) chose a **Defensive Base at North Bridge** (940 kg template), command post as a site (no base until finished), saved / loaded mid-construction, all six buildings built one after another in 7.3 game minutes, a squad garrisons it, the base is linked to North Bridge, no second expansion during the cooldown |
| `f_damage` | 300 rifle rounds: tower at 92 %; heavy damage disables the tower (its 2 soldiers step out) and the barracks (recruit refused with the reason, beds 40 → 8); repair 264 kg paid, worked by the squad, 0 work while under fire, survives save / load (work 10 / 10), done in 38 s, recruiting works again; a captured damaged tower keeps 350 points |
| `f_ai_repair` | South's barracks at 30 %: the economy orders `repair_structure`, its crew restores it to 100 % |
| `g_pause` | Esc opens the menu, the tree is paused and game time frozen, the mouse free; Save Game writes the test slot; Load Game loads it and closes the menu; a damaged world.json disables Load and is refused with the reason, nothing changes; Esc resumes; from first person too |
| `g_menu_return` | Main Menu reloads to the start screen with 0 squads (no scenario started) and Continue available (`g_main_menu_returned.png`) |

### 5.2 Regression runs for changed shared code

| Run | Why | Result |
|---|---|---|
| `--ai-squad-test --only a_engagement,g_player,k_persist` | DEFEND / REPOSITION, order cancellation, saved tactics | PASS (after 01C); `a_engagement` PASS again after 01F (shots now damage structures) |
| `--gameplay01b-test --only c_build` | BUILD (generalised to repairs), auto-build eligibility | PASS (after 01C and after 01F) |
| `--ai-strat-test --only a_assault,i_player,j_persist` | operation release, `_transfer` | `i_player`, `j_persist` PASS; `a_assault` FAIL — **pre-existing**: the identical failure (same losses 12 / 24, "assault has not taken the objective in 262 s") on the scripts of `f71ae21` (before this work) |
| `--gameplay01b-test --scenario=dev --only a_dev` | Development Scenario baseline after base objectives | PASS (3 factions, 12 objectives, 15 squads, 120 soldiers, old rules) |
| `--gameplay01b-test --only b_economy` | income without base objectives, stores | PASS |
| `--gameplay01b-test --only b_recovery` | emergency recovery with replenishment queued | PASS |
| `--ai-war-test --only b_recruit` | AI recruiting through the changed queue | PASS |

Not rerun: the four pre-existing `--logistics-test` failures reported by GAMEPLAY-01B (the systems changed here do not include
vehicle logistics; still open). No full suite was run.

### 5.3 The campaign (§9.2 of the brief) [RUN]

Process 1: `--fullscreen -- --menu-shot --campaign-test --shots --only g_campaign` (the start went through the start screen's
New Game button). Process 2: `-- --continue --campaign-test --shots --only g_campaign_continue`. Process 3: `-- --continue
--campaign-test --only g_menu_return`. Time compression ×2–×8 on walks, construction and waiting; times are game time. Steps 1–18
of the first part are the GAMEPLAY-01B loop (cache, CP, depot, Verket, barracks, recruit, guard tower, F5), all OK.

| # | Brief step | Result |
|---|---|---|
| 1–8 | menu → New Game, eight North soldiers, cache, Command Post, Supply Depot, Verket captured, Barracks, recruit | ✔ (26 game minutes, as GAMEPLAY-01B) |
| 9 | defensive fortifications | ✔ fighting position + MG emplacement (paid sites, built by the squad) |
| 10–11 | Garrison Base, soldiers in positions | ✔ N2 garrisons North base 1 through the RTS order, soldiers in slots |
| 12–13 | player attack on an enemy base, capture | ✔ map ATTACK with 2 squads on "South base 4" (an outpost placed 1.2 km away for the test: New Game has no enemy base within reach of the start); captured, 4 structures now North's |
| 14 | AI counterattack | ✔ a South squad's ATTACK operation on the captured base; the player was warned; the attackers withdrew (effectiveness 0.14) |
| 15 | replenish casualties | – no squad had casualties in this run (shown by `e_replenish`) |
| 16 | repair damaged infrastructure | ✔ the command post (scratched by rifle fire) repaired for 7 kg by a squad the player sent (every squad held a base: no idle builder) |
| 17 | expand | ✔ a second command post near Verket, third base |
| 18 | save | ✔ F5 at 49.0 game minutes |
| 19–21 | restart, Continue, everything back | ✔ squads 3, soldiers 24, bases 3, supplies 2212, all 15 owners, damage of every damaged structure, garrisons, 8 active operations identical |
| 22 | AI factions continue | ✔ AI operations started 17 → 18 within the next 5 game minutes (East: "attack Centre Bridge") |
| menu | Esc → Main Menu | ✔ start screen, 0 squads (no scenario started), Continue available |

### 5.4 Reviews (§9.4–9.7)

- **Operations** [RUN]: multi-squad ATTACK with roles (fire support, assault), stages approach → deploy → support → assault →
  secure, contested capture, withdrawal of a beaten counterattack and failure recovery all occurred in `d_ai_war`, `d_player_assault`
  and the campaign. One defect found and fixed: a squad taken out of an operation by the player counted as its casualties, so the
  operation withdrew ("only 8 of 24 left") — `release_squads` now removes its strength.
- **Navigation** [RUN]: soldiers reach and leave every slot type (`c_forts`: 0 left inside a footprint or on a platform after a
  move order); HESCO lines leave their ends open (the garrison walked round them); towers are entered at their stair foot; squads
  approached outposts across country and round the river (5.5 km detour by bridge in `d_ai_war`); builders and repair crews
  reached their sites. Elevated slots use a snap from the access point instead of climbing (§6). No navigation code changed.
- **Economy**: the GAMEPLAY-01B numbers are unchanged (500 kg start, CP 400, depot 450, barracks 550, guard tower 150, sandbag
  45, HESCO 12/module, recruit 320 + 192 + 8, income 30 per value per minute). New prices follow the same table: fighting
  position 50, MG emplacement 90; repair 60 % of the build cost per missing share; replenishment the recruit price per soldier;
  base objectives give no income. In the campaign the player had 900–2900 kg at hand after the early game and never stalled; no
  rebalancing was made without measurements beyond these runs.
- **GAMEPLAY-01B limitations**: near / far construction timing (±11 %) and forest visibility of sites were not changed (no safe
  one-line fix found); roads stay free; the work pose is still the crouch; one save slot (the menu uses it). The four pre-existing
  `--logistics-test` failures concern vehicle logistics, which this work did not change; they were not rerun and stay open.

### 5.5 Development Scenario [RUN]

`--scenario=dev --gameplay01b-test --only a_dev,smoke_dev` after the last change: 3 factions, 12 objectives, 15 squads, 120
soldiers, North HQ the player's, free construction and reserves (AI expansion is a New Game rule and off here). PASS.

### 5.6 Performance [RUN]

Same run on the same machine before (`f71ae21` scripts) and after (`6a95d83`): Development Scenario, 120 s at ×4.

| | before | after |
|---|---|---|
| SquadTactics step (every 0.5 s, 15–19 squads) | 501 µs avg, 867 µs max | 843 µs avg, 4784 µs max |
| per physics tick: tactics / war / brain | 16.8 / 23.5 / 469.5 µs | 27.8 / 24.1 / 482.9 µs |
| fortification slot search | — | 663 µs avg (7 searches, when a garrison plans its posts) |

The extra step time is the AI garrisons now defending their HQ walls (DEFEND running instead of standing idle); the max is a
step in which several garrisons plan at once. Two costs were found and fixed on the way: a soldier in a wall slot recomputed the
whole wall's slots every step (4.4 ms avg; now one slot), and slot lists are cached per structure. War update (base sync and
alerts every 5 s) stays at ~24 µs per tick. New fortification meshes: 6.4 k / 11.6 k triangles at LOD0, 48–96 at LOD2,
4–5 shared library materials; smoke only on disabled buildings near the camera.

### 5.7 Screenshots (1920×1080, `docs/gameplay01c/`) and previews

Blender previews `blender/fighting_position.jpg`, `mg_emplacement.jpg`, `guard_tower_steel.jpg` · `c_fort_base_built` the
player's base with every new defence · `c_tower_manned`, `c_mg_manned`, `c_fighting_position_manned`, `c_garrison_firing`
soldiers in their positions / firing · `c_ai_garrison` South in its HESCO · `d_map_player_base` a base objective on the map ·
`d_map_player_assault`, `g_map_operation` the strategic map during an assault · `d_player_assault` the assault ·
`d_capture_in_progress` capture under way · `d_captured_installation`, `g_captured_outpost` captured outposts ·
`d_ai_captured_outpost` the outpost South took from East off-screen · `e_ai_outpost` South's Defensive Base at North Bridge ·
`e_replenished_at_barracks` · `f_damaged_barracks` (soot and smoke) · `f_repair_in_progress` · `g_player_base_garrison` ·
`g_campaign_before_save` · `g_map_after_continue` · `g_pause_menu` · `g_main_menu_returned` · `loop_01/09/17` early game.
Looked at: the camera of the MG / fighting-position close-ups is high, so the soldiers inside are partly hidden by the roof;
the map labels a base once (a double label was fixed); the first damage overlay read as camouflage and was replaced.

## 6. Known limitations

1. **No MG weapon** exists: the MG emplacement's gunner slot is marked `mg` and goes to an MG-armed soldier first, otherwise to
   any rifleman. No new weapon or turret simulation was added.
2. **Entering a slot is a snap**: a soldier walks to the access point (tower stair foot, position rear) and is placed in the slot
   (≤ ~5 m); leaving puts him back on the access point. Bodies do not climb stairs; first person can still walk up the timber
   tower's ramp.
3. **Fixed eye height** (1.6 m) for line of fire: crouching is visual only; positions are designed for standing fire.
4. Old MG nest, bunker and tall HESCO have no slots (their collision or height does not allow firing); a trench was not made.
5. **Damage** comes only from rifle hits in play; heavy damage in the tests is applied through `ConstructionState.damage`, the
   hook a future explosive / vehicle weapon will use. Line structures (HESCO) have one condition for the whole line.
6. **AI repairs** run with an abstract crew (no soldiers walk there), like AI construction since GAMEPLAY-01B.
7. **AI replenishment** uses the existing path (new recruits first fill depleted squads at the base); no separate AI decision.
8. A **garrisoned squad does not auto-build or auto-repair** (it holds the base); the player sends a squad by right-click.
9. **Expansion sites** are held objectives only; a base can join an existing forward supply store, then it stands on that
   objective (no own base objective). The AI does not seek neutral ground for bases.
10. Base objectives use the existing capture rule (2 soldiers present, 90 s with 4); defenders in tower slots count.
11. `--ai-strat-test a_assault` fails identically on the code before this work (pre-existing; not investigated further here).
12. The four pre-existing `--logistics-test` failures from GAMEPLAY-01B were not rerun.
13. Not verified by hand: mouse / keyboard play of the whole loop; 1280×720 at runtime (same logical canvas).

## 7. Recommendations

1. **A manual playtest of the campaign by the product owner** (New Game → base → garrison → assault), to tune prices, capture
   time and how often the AI attacks the player — the runs show the loop works, not how it feels.
2. **GAMEPLAY-02: support weapons** — an MG and a light anti-structure weapon (data: `WeaponDef` + loadouts), which give the MG
   emplacement its gunner and let damage come from play instead of the API; the damage hook and resistances are in place.
3. **Movement into positions**: a short climb / step-in animation and navmesh links for tower stairs, replacing the snap.
4. **AI economy for the player's pressure**: the AI chooses bases as targets by the same score as objectives; New Game's South
   rarely has forces to spare for a distant player base. Watch this in the playtest before changing weights.
5. Investigate the pre-existing `a_assault` failure in the AI-COMBAT-STRAT suite (3 squads stall at Haugen).
