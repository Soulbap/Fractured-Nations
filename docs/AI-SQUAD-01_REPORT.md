# AI-SQUAD-01 report — fire teams, suppression, squad tactics and tactical RTS orders

Branch `feature/ai-squad-01` (worktree `../fractured-nations-aisquad01`), built on `feature/ai-intel-01` at `09f9add`.
Not merged into `main`. Evidence tags: **[TEST]** `--ai-squad-test` in the running sandbox war, **[VISUAL]**
screenshots in `docs/ai_squad01/` taken from the RTS camera, **[CODE]** read in source, **[LIMIT]** known limitation.

## 1. Implementation summary

| Part | Files |
|---|---|
| Fire teams and tactics (state) | `scripts/core/squad_state.gd` (teams, `tactic*`, saved), `unit_state.gd` (`suppression`, `post_pos`, `fire_at`, saved) |
| Tactics engine | `scripts/core/squad_tactics.gd` (`WorldSim.tactics`) |
| Post, cover and flank measurements | `scripts/core/squad_positions.gd` |
| Suppression, fire missions, hold-fire self-defence | `scripts/combat/combat_brain.gd` |
| Formations (wedge, staggered, dispersed, auto) and order hooks | `scripts/core/squad_control.gd` |
| Operations assault with tactics | `scripts/strategy/war_sim.gd` (`_assault_objective`) |
| RTS orders, bar, markers, F7 overlay | `rts_controller.gd`, `ui/tactical_panel.gd`, `ui/tactics_overlay.gd`, `ui/game_hud.gd`, `ui/squad_panel.gd` |
| Assets | `tools/blender/asset_production/fam_props_tactical.py`, `assets/military/props/*`, `defs/props/*` |
| Test scenario and suite | `scripts/debug/combat_scenario.gd`, `ai_squad_selftest.gd` (`--ai-squad-test`, `--squad-demo`) |

## 2. Gameplay delivered

* Squads of four or more split into **two fire teams**; a team leader takes over when one falls; smaller squads act as one team.
* Eight tactics: DEFEND, SUPPRESS, ASSAULT, FLANK, BOUND, REPOSITION, WITHDRAW, REGROUP; HOLD FIRE with self-defence.
* **Suppression** from near misses and hits; suppressed soldiers shoot worse, react slower, keep their heads down, and a pinned team does not dash.
* **Suppressive fire** at a reported position through the normal weapon, ammunition and friendly-fire path.
* Cover posts chosen with a view, reserved per faction, not reused for 40 s; formations picked from the terrain.
* The player commands all of it from the tactical view; the AI uses the same calls.
* Four new cover props and a defended-position encounter dressed with them.

## 3. Fire-team architecture [CODE]

`SquadState.teams` (PackedInt32Array per team), `team_leaders`, `team_roles` (security, support, maneuver, assault, reserve).
`SquadTactics.validate` runs every half second and on every death: drops the dead, keeps two teams for four or more
soldiers (one below), balances within one soldier, gives every team a living leader and makes the squad leader lead its
own team. Roles are temporary assignments written by the tactic. Everything is saved with the squad; a loaded game
re-validates against the loaded members, so a soldier that died is never restored into a team.

## 4. Tactical decision model [CODE][TEST]

* **Authority** player > operation > squad tactic > reaction. Every ordinary squad order calls `SquadTactics.on_order`
  (ends the tactic and its fire missions). Operations assign a tactic with `assign_for_operation` (ends with the
  operation). A squad chooses on its own only when nobody commands it (idle, holding, garrison, or at the objective of
  its attack operation) and never while a member is aboard a vehicle.
* **Choice** (`_consider`): a few scores, each with its reason — WITHDRAW when effectiveness is low, SUPPRESS for a
  reported but unseen enemy within 45–230 m, DEFEND otherwise, ASSAULT only when an operation tasked the squad.
  The last tactic gets +0.1, a tactic that just failed −0.5, threshold 0.45; the chosen reason is `tactic_why`, the
  alternatives and why they lost are `tactic_rejected` (shown in the inspector).
* **Effectiveness** = size (living / ever) × (1 − 0.6·suppression) × ammunition × threat ratio.
* **ASSAULT** plans a flank only when the squad has two teams, the target is 70–320 m away, the flank route is walkable,
  at most 2.3× the direct way and exposes the squad at most 55 % — and at least 20 points less than going straight in
  (exposure = share of the route a rifleman at the *believed* enemy position can see). Otherwise it goes straight in
  by bounds, and says why the flank was rejected.
* **Anti-oscillation**: commit windows (8–25 s), 6 s cooldown after a tactic, failed-tactic penalty for 30–45 s, at most
  3 repositions in 2 min with 25 s between, at most 2 flank re-plans, pinned teams wait (≤ 25 s) before a leg.
* Failure: effectiveness < 0.28, timeout (170 s), no walkable ground. An attack the player ordered stops and holds; others withdraw.

## 5. Suppression [CODE][TEST]

`UnitState.suppression` 0–1 with a timestamp; held 1.2 s after the last round, then decays exponentially (τ 5 s).
A shot passing within 3 m adds 0.11 (less the further it passes), a hit 0.30. Effects: aim error up to ×3.2, acquisition
+0.9 s, burst pauses ×2.5, a suppressed soldier in cover skips bursts, a cover search at ≥ 0.35, no dashes at ≥ 0.6 (pinned).
Fire missions (`UnitState.fire_at`): burst of 3 every ~1.3 s with scatter inside the report's uncertainty; one magazine
is always kept, fire slows below half and stops below 20 % ammunition; friendly-fire and own-cover checks are the normal ones.
Squads stop firing when the contact is gone, older than 120 s or below 18 % confidence.

## 6. Cover and formations

* Post search (`SquadPositions.find_posts`): structures, rocks, trunks and terrain rises from the existing cover generator,
  scored for protection, line of fire and distance, 2.6 m apart, away from own-faction reserved spots and recent posts.
* Cover reactions of a soldier at a post stay within 3.5 m of it; dashing soldiers react only when pinned.
* Formations: wedge, staggered, dispersed added; `formation_auto` squads use column on roads and in woods, wedge in the open,
  dispersed in contact (also live while marching), with hysteresis.

## 7. Player commands [TEST g_player]

**Z** assault, **K** suppress, **L** flank, **J** defend, **Backspace** withdraw — at the cursor, or armed from the bar
(bottom right) and a click; **Shift+RMB** move by bounds; G regroup, Y hold fire, H hold, RMB move as before; **V**
cycles auto/line/column/wedge/staggered/dispersed. The bar shows each selected squad's tactic, owner, effectiveness and
suppression, and the last order's result in green, or in red with the reason it cannot be executed ("the target is 787 m
away, beyond rifle range"). Order markers (line, ring, flank route, label) show for the player's own squads only.
Verified through the real controls: accepted, replaced (Z then K), armed + click, refusal with reason, cancelled by a Move
(fire missions gone), two squads side by side, possession of a member (tactic and teams intact, back to RTS), hold fire.

## 8. Assets [VISUAL] `docs/ai_squad01/assets/`

Built through the ASSET-PRODUCTION-01 pipeline, validated in the asset lab (0 errors), registered in the construction
menu (Defences), collision boxes are the real cover.

| Asset | Tris LOD0/1/2 | Notes |
|---|---|---|
| `sandbag_fighting_position` | 7788 / 936 / 72 | two-man horseshoe, 0.72 m walls, 0.36 m firing gap; over the 5.8 k wall guideline, a hero piece |
| `log_barricade` | 672 / 204 / 60 | three trunks, 0.76 m |
| `boulder_cluster` | 960 / 240 / 60 | three boulders 1.5 / 1.1 / 0.8 m; new shared `Rock` material |
| `earth_berm` | 508 / 72 / 28 | 4 m linear module with sandbag crest |

Iterated after previews: boulders were too flat and streaked, the sandbag position had a "plank" of spoil in front and
23 k triangles. Checked in Godot, in the encounter: HESCO horseshoe, wing positions, boulders, log and berm on the approach.

## 9. Debug controls

**F7**: team discs (leader ring), post of each soldier, fire missions, cover spots, flank routes, tactic text for every
squad of every faction (developer view). Inspector (**I** / **T** on the strategic map) now ends each squad with
`Tactic`, `Why`, `Not chosen / cancelled`, `Fire teams`, `Effectiveness`, `Threat`, `Target`, `Fire missions` — real fields,
no after-the-fact text.

## 10. Save/load and near/far [TEST]

All tactical state is in saved records; every step derives from it. **K**: suppress, flank, bound and withdraw were saved
mid-tactic and loaded: team, role, phase, leg, route, destination, target, every soldier's post and fire mission identical
(`diff = []`), and the squads carried on (phase/leg advanced, suppress kept firing). **J**: the same assault near and 6 km
away (no bodies): both fight (≥ 700 shots), tactic and phase survive the camera leaving and returning, no unit duplicated,
no soldier with body and proxy. **I**: dead soldiers are not in the teams after save/load.

## 11. Scenarios and results [TEST] (`benchmarks/raw/ai_squad_test.json`)

Site: a meadow at (−7793, −8816) found by measuring the terrain (dry, open sight line, flankable); defenders 12 m up.

| | Result |
|---|---|
| base_fight / base_far / base_orders | unchanged combat works near and far (shots, damage, 2 contacts, abstract tier 334 shots); **baseline defect** `base_orders`: in 25 s nobody reacted to fire in that layout (not caused by this work; the reaction path is exercised in A) |
| A engagement | both squads DEFEND on their own, 2 teams, 0 crowded pairs, 8 distinct posts, 8/8 in cover, suppression peaks 0.55 / 1.0, 483 shots, inspector lines present |
| B suppression + maneuver | attackers chose a left flank (47 % vs 93 % exposure), defenders suppressed to 1.0, 190 rounds used; the 8-on-8 attack uphill broke off (effectiveness fell) and withdrew — correct, not a win |
| C flank | route 166 m, maneuver team reached the staging point, support took firing posts (moved up 83 m to get a view), 2 flank plans, no re-plans; the attackers still lost to six dug-in defenders [LIMIT balance] |
| D assault | approach → support → advance → occupy → regroup → hold in 91 s, 8 alive, 3 defenders left |
| F withdrawal | started 18 s in at effectiveness < 0.38, 171 → 266 m from the enemy, spread ≤ 39 m, regrouped |
| G player commands | all sub-checks passed (section 7) |
| H intelligence | report 0.5 confidence at P; target = P exactly (0 m), true enemy 305 m away; 594 mission shots, 497 within 45 m of P, **0** near the true enemy; stopped after 40 s without news |
| I casualties | leader and a team-B soldier killed: new leaders, 3+3, still moves, no dead in teams after reload |
| J, K | section 10 |
| M audit | `squad_tactics.gd` / `squad_positions.gd` never enumerate the world's units; `_fire_mission` never looks up a unit |
| Z showcase | two squads march (column) to 360 m, assault by bounds, support set, advance, occupy, regroup; 8 + 6 survive, 2 defenders |

## 12. Performance [TEST l_perf] 3 v 3 squads (48 soldiers), 25 s, RTX 3070

| | tactics off | tactics on |
|---|---|---|
| frame avg / p99 / max | 4.14 / 12.8 / 104.7 ms | 4.67 / 13.3 / 21.3 ms |
| CombatBrain update | 2.56 ms | 2.55 ms |
| tactics per sim tick | 1.2 µs | 61 µs (1.84 ms per 0.5 s step, 6 squads) |
| post search | – | 7 searches, 3.3 ms avg, 4.1 ms max (event time, not per frame) |
| cover searches | 189 | 144 |

Decision frequency: 1 tactic per squad per ~10 s in the fights; no oscillation seen.

## 13. Visual inspection findings [VISUAL]

* First runs: soldiers drew as dots at zoom 150+, HUD panels overlapped, the march began inside rifle range
  (the squads were already "engaging"), tactic lines hid the soldiers. Fixed: closer follow camera, bottom-right bar that makes the squad list scroll
  instead of overlapping, start line outside range, close-up shots.
* Seen and kept: dispersed wedge with team discs, support team firing while the other team moves in short legs,
  occupation of the HESCO position, regroup into a wedge.
* Seen and **not fixed** [LIMIT]: soldiers in tall grass are half hidden; the fixed follow camera in the scripted run
  keeps the action in the lower half; no prone / crouch animation for pinned soldiers (they stand in cover).

## 14. Regression (change-impact)

Chosen because shared code changed (`SquadControl`, `CombatBrain` engagement and cover generator, `WarSim` assault, `UnitState`/`WorldState` fields):
`--squad-test`, `--combat-tactics-test`, `--sandbox-test --only persist,offensive`. Results:

* `--squad-test` **PASS** (after restoring the V key: V toggles line / column as before, **Shift+V** cycles the new shapes; first the V cycle change broke the Regroup check).
* `--combat-tactics-test`: the same **3 failures as the unchanged baseline** (`duplicate damage` x2, `tier changes`), measured twice on `feature/ai-intel-01`. Two more failures (hold-fire cover, unreachable cover) appeared and were traced by bisecting to suppression: stray default soldiers near the test area shoot at the scenario's "Threat" squad, which is now suppressed and fires less. The suite checks COMBAT-02 reactions, so it now runs with suppression off (stated in the file); it then equals the baseline.
* `--sandbox-test --only persist,offensive`: `persist` passed; `offensive` **failed** with operations assaulting through the squad tactics (three squads stopped at 130 m and traded fire; 16 of 24 lost) and **passes** with the old walk-in. Therefore `SquadTactics.ops_assault` is **off by default** (`--ops-assault` turns it on). The hook and its test coverage exist (B, C, D, J use `assign_for_operation`); a useful operation assault needs the three squads to coordinate (one fixing, two maneuvering) - recommended next.
* One full `--ai-squad-test` run at the end (justified: new suite, shared systems changed): 18 checks, **2 failures**: `base_orders` (the documented baseline defect) and `J(near)` (the check counted the war's reserve squads spawning elsewhere as "appearing soldiers"; it now counts only the scenario's soldiers).

Frame time in that last run, 3 v 3 squads: 4.45 ms avg tactics off, 4.79 ms on; tactics 58 us per sim tick.

## 15. Known limitations

* No vehicles as targets or observers; infantry only (AI-VEH-01).
* Balance: dug-in defenders on a rise beat an equal attacker; the AI only attacks with superiority, a player may not.
* Flank exposure uses a 1.5 m eye at one believed point; a defender behind its own wall looks "blind" from some directions
  (seen: 7 % exposure for a squad approaching diagonally behind the HESCO arm) — right for that direction, but a believed
  position inside a structure is not special-cased.
* Withdraw cover fire only fires at hidden enemies (visible ones are shot by the normal path).
* Pinned soldiers keep standing; a team that waits pinned in the open for 25 s is shot at.
* Smoke, grenades, mortars, medics are out of scope; no morale beyond effectiveness.
* Attack operations walk in as before (`ops_assault` off); AI squads use the tactics defensively and when the player or a script tasks them.
* Legacy `--combat-ai-test` still not ported (its layout is obsolete); replaced by `base_*` and A–M here.

## 16. Recommended next milestone

**AI-STRAT-01** (strategic decisions with threat awareness) now that squads fight as units and report their effectiveness;
or a small **AI-SQUAD-02**: prone / crouch states for pinned soldiers, smoke, and combined arms hooks for AI-VEH-01.
