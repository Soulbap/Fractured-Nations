# QOL-01 — Tactical controls, squad behaviour, command feedback and usability

Branch `develop`. A usability milestone on top of the existing AI layers; no new planner, navigation or combat system.
The player decides *what* a squad does and *how cautiously*; `SquadControl`, `SquadTactics`, `CombatBrain` and
`StrategicRoutes` decide how.

## 1. Summary

| Feature | What it is now |
|---|---|
| Behaviour modes | SAFE / AWARE / COMBAT / STEALTH per squad (`SquadState.behaviour`, saved). **X** / **Shift+X** cycles; the MODE row of the command panel sets one. AWARE is the default and the behaviour every squad had before. |
| Selected vs actual | The choice is never overwritten. `SquadTactics.behaviour_now` derives what the squad acts on: a SAFE squad under fire acts as COMBAT, a SAFE squad that only sees an enemy acts as AWARE, and a STEALTH squad that has been fired on or has fired is *compromised* for 30 s and acts as COMBAT. The panel shows "acting COMBAT", and the roster tints the mode icon. |
| Behaviour routes | An order's strategic route uses a profile grid (roads / open ground / forest cost) and avoids the faction's *believed* enemy, within a detour limit. |
| Posture, reactions, fire | STEALTH crouch-walks near a reported enemy and lies prone while holding near it (but never crawls a march). SAFE stays upright until fired on. COMBAT goes low when halted near a threat. Cover dashes on the move are wider and longer in COMBAT and shorter in SAFE. STEALTH does not open fire beyond 50 m until found. |
| Interrupted moves | A player squad whose move meets contact halts through the ordinary tactic choice (defend / suppress / withdraw, or for COMBAT a bound past contact off to the side), keeps the move's **final goal**, and resumes when the contact is over. HOLD or any new order wins. At most 3 halts per order, with a 40 s cooldown after each resume. |
| Order feedback | One description from the records (`SquadControl.describe_order`): planning, moving (distance, route leg), interrupted, blocked (with the navigation's reason), route blocked (bridge), arrived, holding, following, aboard. It feeds the panel's order line, the roster, the field tag and an acknowledgement for every move. |
| Notices | `SquadReports`: under fire (after 45 s quiet), casualties (grouped over 5 s), halted / resumed / move broken off / pressing on, arrived, blocked. Vehicle failures carry their vehicle. A click selects the squad or vehicle and frames the camera on where it is now, from any view. |
| Overview | The roster shows the mode icon, a "MOVING · 640 M" / "HALTED · DEFEND" / "PLANNING ROUTE" status and a tooltip with the order. A double click or **C** frames the camera on the selection. |
| Command panel | Rebuilt after the product owner's review (CoH used as inspiration). It is a compact grid at the bottom right: rows MOVE / COMBAT / SQUAD / MODE, each tile an icon over its name with the hotkey in the corner and the full help as a tooltip. The info card on the left holds callsign, strength, status, order line, health / ammunition / suppression, formation, ROE and support weapons. Icons for hold, bound, follow, assault, suppress, flank, garrison, rearm and the four modes were redrawn. |
| Continuity | Back from first person with nothing selected, the soldier's squad is selected. The map opens with the tactical selection and hands its own back on close. The FPS squad card shows the mode. Records are the same in every view. |

## 2. Existing systems reused

- **Interruptions:** `SquadTactics._consider` / `start` / `_finish` / `_restore` / `_resume_previous` (prev_order existed). QOL-01 decides *when* a moving player squad may consider a tactic, and makes the remembered target the move's final goal.
- **Routes:** `StrategicRoutes` (same 50 m grid, solid cells, bridges and roads), `RouteService` (jobs, dedupe, cache, budget) and `StrategicInfluence.threat` (the faction's believed enemy, never the world).
- **Posture:** `Posture` and `CombatBrain._choose_posture`, with their hold times and the prone ground check; reactions use `CombatBrain._start_search`.
- **Fire discipline:** the ROE gate in `_engage` / `_fire_mission` / `_support_weapons`.
- **Notices:** `WarSim.log_event` / `event_logged`, the HUD toasts and the map's event list (both already clickable for places).
- **UI kit:** `FNCommandButton` gained a compact mode; the command panel, roster, field tag and FPS card share `SquadPanel.squad_status`.

## 3. Behaviour modes and their actual effects

| Effect | SAFE | AWARE (default) | COMBAT | STEALTH |
|---|---|---|---|---|
| Route grid (road / open / forest cost per m) | 0.32 / 1.0 / +0.35 x density | ordinary grid (0.45 / 1.0) | 0.95 / 1.25 / -0.5 x density | 1.6 / 1.6 / -0.95 x density |
| Believed-threat cost (per strength) | x0.6 | x1.5 | x3 + ring | x4 + ring |
| Detour limit vs the ordinary route | 1.2x | 1.25x | 1.4x | 1.75x |
| Spacing | 1x | 1x | 1.4x | 1.25x |
| Halted posture | upright unless fired on | as before | crouch with a threat within 300 m | crouch within 250 m, prone within 150 m while holding |
| Moving posture | upright | upright | upright (runs) | crouched within 250 m of a reported enemy |
| Cover reaction on the move (radius, time) | 0.8x | 1x | 1.6x | 1.4x (compromised: COMBAT) |
| Interrupts a move when | half the squad is fired on or pinned | 2 fired on, 1 pinned or 2 engaging | any contact seen or firing | fired on |
| Resumes after quiet | 10 s | 15 s | 20 s | 20 s |
| Weapon readiness | relaxed unless engaging or fired on | as before | ready | ready |
| Fire | normal | normal | normal | holds beyond 50 m until found; no fire missions, no self-chosen SUPPRESS |
| Pace (only with `--paces`) | order's | order's | run when reacting | brisk near a threat |

Limitations, kept honest:
- Noise from movement is not simulated, so STEALTH reduces only what the detection model represents: posture (crouch / prone noticing delay, grass concealment), not firing (gunfire is heard), and routes away from believed enemies and through forest.
- The movement speed of the paces applies only with `--paces` (the game default is 4.5 m/s for every pace).
- Routes are planned on the 50 m grid for moves longer than 150 m (or blocked straight lines). Short moves walk straight to their slots in every mode.
- "Cover" for routes is forest density (vegetation.png, the map the trees were scattered from). Buildings and terrain masking are not in the grid; line of sight from a threat is not either (the threat's 250 m cells and a ring around them stand in for "exposed to").
- AI factions keep AWARE. Their operations ("op" routes) are planned as before, and their moves are never interrupted / resumed by this code (they belong to WarSim).

## 4. Route-choice comparison (`r_routes`)

40 start / destination pairs, 1.6 km chords through the open test site and four objectives on `ref_20km`, each planned for all four profiles. Every route passed the leg check; all 40 pairs gave different SAFE and STEALTH routes.

| Mean over 40 pairs | SAFE | AWARE | COMBAT | STEALTH |
|---|---|---|---|---|
| Share of the route on road cells | 0.51 | 0.45 | 0.36 | 0.14 |
| Mean forest density along the route | 0.22 | 0.24 | 0.29 | 0.50 |

The pair with the largest difference, (-7767, -7158) → (-6433, -8042):

| | Length | Road share | Forest density |
|---|---|---|---|
| SAFE | 1973 m | 0.87 | 0.32 |
| AWARE | 1973 m | 0.87 | 0.32 |
| COMBAT | 1717 m | 0.64 | 0.24 |
| STEALTH | 2009 m | 0.01 | 0.75 |

On that pair, SAFE / AWARE take the road, COMBAT a shorter cross-country line and STEALTH the forest for 2 % more distance.

With a believed enemy (strength 4) on the ordinary route's midpoint:

| | Closest distance to the enemy | Length |
|---|---|---|
| Ordinary route | 0 m | – |
| SAFE | 100 m | 1973 m |
| AWARE | 100 m | 1973 m |
| COMBAT | 450 m | 2028 m |
| STEALTH | 450 m | 2028 m |

SAFE and AWARE only leave the threatened 250 m cell. The first run showed COMBAT doing the same, so COMBAT and STEALTH now also price a ring of cells around a threat at a third.

A live STEALTH order received the stealth route (19 waypoints, profile "stealth"). Profile grids are built on first use in about 53 ms each. A profiled route takes 0.25 ms median; the 55 ms maximum includes a grid build. Two searches (profile + ordinary, for the detour check) run only when a profile grid or a threat is involved.

## 5. Order feedback and resumption (`b_modes`, `i_interrupt`, `n_notices`)

- **Move acknowledgement:** "Move accepted: QB AWARE, 109 m direct" (route planning, behaviour and distance per squad). A tactic's acceptance / refusal reasons are unchanged.
- **Changing the mode mid-move:** the mode went through COMBAT → STEALTH → SAFE → AWARE during a move. The order stayed MOVE to the same target with no tactic; the spacing changed (4.2 / 3.75 / 3.0 m); a march re-plans its route for the new mode.
- **Save / load:** behaviour STEALTH and interrupts = 2 came back through a real save and load (`construction.save` / `load_game`, `user://test_saves`).
- **Interrupt:** an AWARE squad moving across an enemy's front (keep-alive soldiers) was halted after 1 s. Owner: squad; tactic: DEFEND, "6 posts ... threat seen 212 m"; the order line read "Move interrupted: defend - resumes when the contact is over (356 m to go)"; the remembered target was the move's final goal.
- **Resume and arrival:** with the enemy gone, the move resumed to the same goal (82 s simulated, including the calm period and the defence's own wind-down) and arrived 8 m from it. The squad's notices were interrupted, under_attack, resumed and arrived.
- **HOLD wins:** HOLD given while interrupted: no resume; the remembered order is the hold and the squad defends where it holds, as any holding squad does.
- **Blocked:** "1 soldier cannot reach his place: <navigation reason>" became a notice.
- **Click on a notice:** selected the squad and put the camera focus within 0 m of its centroid. A notice of a squad that no longer exists does nothing harmful.

Before QOL-01, a squad interrupted on a route remembered only the leg's waypoint (the route was dropped) and stopped half way after the fight. Now it resumes to the final goal.

## 6. Squad overview and event interactions

Screenshots (1920x1080, `docs/qol01/`):
- `01_rts_panel_stealth_move.png`: compact command grid, STEALTH selected, order line, roster with mode icons, field tag with the distance.
- `01b_tile_tooltip.png`: hovering a tile shows its name and help (real hover through the viewport).
- `02_notice_and_roster.png`: a clickable squad notice.
- `03_two_squads_mixed.png`: two squads in different modes.
- `04_map_selection.png`: the map opened with the tactical selection.
- `05_fps_squad_card.png`: first person, squad card with the mode.

## 7. FPS / RTS / map continuity (`c_views`)

1. Squad QA (COMBAT) selected, then a soldier possessed: the selection is kept.
2. Selection cleared, back to the tactical view: QA is selected again (the possessed soldier's squad) and is still COMBAT.
3. Map opened: the map's selection is [QA].
4. Another squad selected on the map, map closed: the tactical selection is that squad.

All the same records: nothing is copied between views.

## 8. Targeted test results

Chosen by change impact.

| Run | Why | Result |
|---|---|---|
| `--qol01-test` (all eight checks, `--shots`) | the new features | PASS (see §10 for the final run) |
| `--navigation-n1c1-test --only n1c1_02,n1c1_07` | squad route requests now go through profiles; bridge stop reason | n1c1_02 PASS. n1c1_07 failed first: my change cleared the bridge stop reason (it was set before `clear_route`). Fixed, rerun PASS. |
| `--ui01c-test --only checks` | the command panel and roster were rebuilt | PASS |
| `--ai-squad-test --only g_player,base_orders,k_persist` | player orders, tactics and persistence | g_player PASS. k_persist K(suppress) / K(flank) is the known pre-existing failure. base_orders "nobody reacted to fire" is the baseline defect documented since AI-SQUAD-01; failed identically on two reruns, and the interrupt code does not engage there (the squad is under 40 m from its goal). |

No full-suite run (no cross-system risk beyond these).

## 9. Performance (`q_perf`)

Four player squads of eight march 400 m past an enemy squad of eight, 40 simulated seconds, once all AWARE (the pre-QOL-01 behaviour) and once one squad per mode:

| per tick | all AWARE | four modes |
|---|---|---|
| SquadTactics step avg / max | 2.0 / 8.8 ms | 1.8 / 8.6 ms |
| CombatBrain update avg / max | 1.7 / 5.8 ms | 1.9 / 6.2 ms |
| SquadReports pass (1 Hz) avg / max | 0.20 / 0.51 ms | 0.25 / 0.58 ms |

Same order of magnitude: the modes add no per-frame searches. Route costs are in §4.

## 10. Final run

See `benchmarks/raw/qol01_test.json` (written by the last full `--qol01-test --shots` run).

## 11. Comparison with the Arma 3 AI references (Bohemia Interactive wiki)

Source: the product owner pasted the pages (AI Behaviour, AI Skill, Suppression, CfgBrains / AI Config Reference, AI Group Vehicle Management); the wiki itself is behind bot verification. Arma's numbers are not copied.

| Topic | Arma 3 | Fractured Nations now | Relevant improvement / future task |
|---|---|---|---|
| Behaviour modes | CARELESS / SAFE / AWARE / COMBAT / STEALTH set per group, override formation and speed. SAFE turns AWARE on detection. COMBAT bounds always and is slow (about a minute to cross a road); STEALTH is mostly prone. | Four modes (no CARELESS: SAFE keeps self-preservation). Selected vs effective kept apart. Bounding only when the situation calls for it (COMBAT bounds past contact off to the side); no crawling marches. | Done in QOL-01. The brief explicitly avoids Arma's slow COMBAT. |
| Skill | Sub-skills (aimingAccuracy, aimingShake, aimingSpeed, spotDistance, spotTime, courage, reloadSpeed, commanding, general) interpolated through CfgAISkill curves and difficulty coefficients. | One aim model (`CombatBrain.AIM_PROFILES`: base / range / moving error, first-shot and settle multipliers, `proficiency_mult`), reaction 0.45 s + 0.15 s per 100 m, perception and noticing delays (`acquire_delay`). | *Future task*: a small per-soldier skill record (aim, spot, courage) feeding the existing multipliers - veterans vs recruits - instead of one global profile. Not in QOL-01. |
| Aim error | `AIBrainAimingErrorComponent`: an error cone that settles over 0.2-2 s by skill, grows when the target is lost, with moving / turning / shooting / damage / fatigue / suppression influences. | The same idea exists: first-shot and settled multipliers, a moving penalty, suppression x4 on aim error, posture steadiness. No growth after losing the target, no damage / fatigue terms. | *Future task*: aim error rising for a few seconds after a target is lost; a damage term. Cheap additions to `_aim_error`. |
| Suppression | Built by close bullets, hits, explosions, fire (weights 0.5), decays in 1-10 s by skill; AI avoids beaten zones in path planning; smoke above a threshold. | `suppression_at` from near misses per weapon (`WeaponDef` radius and amount), decays; pinned / suppressed thresholds change posture, firing ("head down") and squad tactics (pinned teams wait, hopeless pin → local withdrawal). Routes avoid the believed enemy (QOL-01), not beaten zones. | *Future task*: decay time by soldier skill / courage (with the skill record); smoke has no asset yet. Beaten-zone avoidance for local legs is a possible later step via `SquadPositions.exposure`. |
| Stance and terrain | `visibleSize` per stance (sprint 1.0, stand 0.7, kneel 0.3, prone 0.1), `grassCover` per surface, `AIAvoidStance` per surface (avoid prone except stealth). | `Posture` table (eye, hit volumes, speed, steadiness, grass top), `Concealment` from grass placement, `posture_notice_s` per stance, prone ground check (slope, wet, deck, structures). | Matches in spirit. QOL-01 adds stance by behaviour. *Possible*: a moving-visibility factor per pace (sprint more visible) - `notice_moving_mult` exists, not by pace. |
| Visibility / noise | camouflage, audible, sensitivityEar, audibleFire / visibleFire per weapon. | Sight lines with foliage, hearing of gunfire (`hearing_m`), concealment. No movement noise. | STEALTH uses only what exists (stated in §3). *Future*: per-weapon audibility (suppressed weapons) if such weapons arrive. |
| Path planning | Behaviour changes paths (picture on the AI Behaviour page); roads preferred in SAFE / AWARE; vehicles `preferRoads`; COMBAT / STEALTH use cover. | QOL-01 profile grids (road / forest cost, threat avoidance, detour limit) on the existing 50 m grid; vehicles keep `VehicleRouter` on `RoadNetwork`. | Done for infantry orders. *Future*: building / terrain-masking cover in the grid. |
| Vehicles, groups | A group vehicle pool (`addVehicle`), seat roles assigned by the leader, `orderGetIn` / `allowGetIn`, `unloadInCombat` (wheeled transports unload when combat starts), `ejectDamageLimit`. AWARE disembarks from wheeled transport when enemies are known. | `VehicleTransport` (squad boards an assigned vehicle; seats from the vehicle def; order, convoy and logistics), the player orders boarding / unloading. Squads aboard never run tactics. No automatic dismount on contact. | Kept out of QOL-01 (brief: no new vehicle AI, no forced dismount by COMBAT). *Future task*: a behaviour-aware dismount rule in `VehicleTransport` (stop and unload when a transported squad is fired on, skipped for SAFE). |
| Countermeasures | Smoke when suppressed (threshold 0.8, delay 20 s). | No smoke grenades. | Future, with a smoke asset and `CombatSim` explosive type. |

## 12. Known limitations and deferred work

- **Combat interruptions:** only the player's squads are interrupted and resumed; AI faction squads are unchanged.
- **Detection:** STEALTH cannot hide movement noise (not simulated).
- **Route cover:** forest density only; no buildings and no terrain masking in the cover layer.
- **Speed:** pace differences apply only with `--paces`.
- **Panel:** the formation tile shows the current formation name (Auto / Line ...). Icons were redrawn by hand on the 24 grid; further polish is possible after the product owner's look.
- **Known failures (pre-existing):** `--ai-squad-test` k_persist and base_orders.
- **Deferred:** per-soldier skill record, aim error after a lost target, behaviour-aware dismount, smoke, beaten-zone avoidance for local legs (see §11).

## 13. Changed or added state

- `SquadState`: `behaviour`, `interrupted`, `interrupts`, `interrupt_until`, `prev_pace` (saved, defaults for old saves).
- `prev_target` of a move that a tactic interrupts is now the move's final goal (`SquadControl.move_goal`), not its current leg.
- `StrategicRoutes` cache: the grid now carries `cover` and its fingerprint includes `vegetation.png`. The cached grid is rebuilt once (about 1.3 s) on the first start.
- `WarSim.log_event` takes an optional `extra` dictionary (`{"squad": id}` / `{"unit": id}`).
- New files: `scripts/core/squad_behaviour.gd`, `scripts/core/squad_reports.gd`, `scripts/debug/qol01_selftest.gd`.
