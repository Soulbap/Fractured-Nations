# GAMEPLAY-02 — Infantry Combat, Support Weapons & Tactical AI

Work on `develop`, one commit per stage, not pushed: `2bb1ab5` 02A · `24d16e5` 02B · `bb27113` 02C · `844dea9` 02D ·
02E (integration, fixes, this report). Evidence tags: **[RUN]** verified in a Godot runtime run of this milestone,
**[CODE]** inspected only. All runs on ref_20km, Development Scenario unless stated, saves in `user://test_saves/ref_20km/`.

## 1. Executive summary

**What changed in play [RUN].** Every squad now carries a **light machine gun** (750 rpm, 100-round box, long reload,
wide suppression cone, tight when braced and poor on the move) and a **grenadier** with three hand grenades and a
**light anti-structure launcher** (two rockets); every rifleman carries one grenade. The composition is data
(`assets/combat/squads/standard.tres`) and keeps each faction's look (NATO_mg / RU_mg / CN_mg, *_gren loadouts). The AI
throws grenades at enemies it saw go into cover or positions 11–30 m away, never with a friend in or walking into the
blast, and fires rockets only at enemy structures where it saw the enemy; the machine gunner takes the best firing post
and the MG emplacement's gun slot; soldiers who see a grenade land run clear of it. The player can do the same in first
person (**G** grenade, **X** raise the launcher, LMB fire) under the same rules, and feels suppression (darkened screen
edges). Grenades and rockets are records in the simulation, so they work identically off-screen and across save / load.

**Attacks [RUN].** The Haugen failure was diagnosed with a new combat recorder (§2): the fire support fired ~1500 rounds
blind at the objective's centre and was empty when the assault arrived, the assault squads crossed 330 m of open ground
together and slowly, shattered squads were sent back in alone. Coordination was rebuilt inside OpCoordination /
SquadTactics (§3). Over seven assault scenarios × three seeds, objectives taken went from **10 to 14 of 21**, attacker
losses from **37 % to 27 %**, the longest stalled assault from **251 s to 150 s**, and no attack ended wiped out or stuck
(2 → 0). `--ai-strat-test a_assault`, failing before this work, passed after 02A (it is stochastic: §8).

**Not done / limits (§8):** fortified outposts in the open are still easier to take than the village (the defenders in
slots are seen from far); a few existing checks fail as before (l_war frame time and transit stage, an exit crash of the
engine that predates this work); third-person bodies do not swap to the launcher when the AI fires it; procedural
placeholder sounds only.

## 2. Combat diagnosis (02A)

### 2.1 Reproduction and instrument

`CombatDiag` (`scripts/debug/combat_diag.gd`, test-only, no cost in play) records an engagement once per simulated
second: per squad the distance to the objective, role, tactic and phase, order, soldiers, suppression, effectiveness,
ammunition, enemies seen; per side shots, fire-mission shots, hits, kills, structure hits and the suppression given;
moving / still / cover-seeking time, blocked moves; the operation's stages, wait and withdrawal reasons.
`--combat02-test` runs seven scenarios (original Haugen, approach through woods, two squads, three squads at Elvetun over
open ground, limited ammunition, two against two, a fortified outpost) over world seeds 1, 2, 3 (the seed drives every aim
error, spread and scatter). `tools/combat02_compare.py` turns two runs into the tables of
[docs/gameplay02/02A_measurements.md](gameplay02/02A_measurements.md) and [02E_measurements.md](gameplay02/02E_measurements.md).

### 2.2 The Haugen failure (seed 1, before) [RUN]

12 of 24 attackers left, 5 of 8 defenders, "the assault has not taken the objective in 262 s". The trace:

| time | what happened |
|---|---|
| 0–69 s | approach to the staging point 334 m out (first contact at 50 s: defenders see the column at ~400 m) |
| 69–82 s | deploy: N6 fire support moves to 181 m; N7 cannot flank ("exposure 29 % vs 19 % straight") → second assault squad |
| 82–119 s | support "set", fires **blind at the objective centre** — it never saw a defender in the whole run (seen = 0) |
| 119–181 s | N7 and N8 leave 331 m together, identical distances every sample (synchronized), 22 m per 10 s (in-squad leapfrog out of contact) |
| 181–204 s | at ~200 m both lose men fast (N7 8 → 4); defenders' mean suppression 0.02 |
| 247–268 s | support ammunition 1.0 → 0.25: its SUPPRESS ends (plan refuses below 25 %) and it is never re-tasked |
| 268–381 s | weakened squads re-tasked one by one, creep, withdraw at 381 s |

Totals: attackers fired 1657 rounds (1478 of them fire missions) for 11 hits (0.6 %), defenders 203 rounds for 35 hits
(17 %). **Blocked moves: 0 in every run** — tactical failure, not navigation. Seeds 2 and 3 showed the same pattern (one
won after 200 s of stalled assault). Later iterations found more: the support "lifted" its fire when a shattered squad
came within 70 m of the centre, a lone assault squad went in while the flank was still 260 m out, defenders standing 33 m
off the centre were never touched by 1000 rounds aimed at the centre, and the progress rule could not see progress on the
objective itself.

### 2.3 Causes against the brief's questions

| question | finding |
|---|---|
| support fire before the advance? | yes, but blind (no report) and from the deployment on: ammunition gone when needed |
| assault moving at the wrong time? | it started from 330 m, before the support saw anything |
| same bounding cycle? | yes: two assault squads, same start, same slot direction, same timing |
| repositioning without gain? | depleted squads re-tasked alone, again and again |
| suppression strong enough? | no: 0.02 mean; the spread (half the contact uncertainty, 7–22 m) put most rounds beyond the 3 m a near miss needs |
| useful firing positions? | support posts had a line to the objective centre, not to the defenders |
| phases correct? | yes; the timing rules were the problem |
| retreat thresholds? | withdrawal came only by the 260 s timeout |
| route planning? | no blocked moves, no route failures |
| fortifications? | the outpost scenario was the *easiest* (defenders in slots are seen from far) — see §8 |

## 3. Tactical improvements (02A, refined in 02C/02D) [RUN]

All inside the existing owners (`OpCoordination`, `SquadTactics`, `OperationState`); no new controller.

* **Assault positions.** Assault squads move up by bounds during the deployment to their own position 250 m out, 50 m
  apart sideways, and wait in cover (`_move_up`, `_assault_position`).
* **Staggered starts.** The nearest squad goes first, the others 14 s apart (`OperationState.assault_at`, saved); a
  flanking squad must be about as close as the assault before it goes.
* **Fire window.** The support observes and fires only at fresh reports (half the squad, the MG always) until the assault
  crosses the defenders' ground; then the whole squad covers (`OperationState.cover_fire`, 290–35 m). Nothing reported →
  no blind fire. Spread a third of the contact uncertainty (3–15 m). The support lifts only when a fit squad is on the
  objective (35 m).
* **March, then bound.** Out of contact and beyond 160 m both fire teams move together; bounding starts at contact or
  160 m out. The covering team fires only within rifle reach (260 m) or at what it sees.
* **Recovery.** A squad at half strength becomes fire support where it stands instead of assaulting again; an assault
  without 10 m of progress for 75 s commits every fit squad once (only with twice the believed enemy), otherwise — or
  after another 75 s — the operation withdraws with its reason.
* Tried and rejected (measured): aiming the assault at the reported enemy instead of an objective spot (iteration 5:
  8 of 21 taken against 11).

## 4. Weapons (02B, 02C) [RUN]

One `WeaponDef` per weapon (`assets/combat/`), the same `CombatSim` rules for AI and player:

| weapon | key data | role in play |
|---|---|---|
| rifle (Carbine 5.56) | 700 rpm, 30 + 120, reload 2.4 s, damage 34 | unchanged |
| lmg (Light MG 5.56) | 750 rpm, 100 + 300, reload 6.5 s, damage 34; suppression ×2.2 per near miss, near-miss radius 4.5 m; spread ×0.45 braced after 1.2 s still, moving spread 3.2° and AI aim error ×2.2 on the move; AI bursts ×2.5, fire-mission bursts of 8 | suppresses through volume and a wider cone, never through damage: in `b_suppress` one MG gave **2.3×** a rifle's suppression at 150 m with the same damage per hit |
| grenade (frag) | 35 m throw, scatter 0.8 m + 6 % of the distance (+ suppression), fuse 3.5 s, radius 9 m, 150 damage at the centre falling off, a tenth behind cover, suppression to 18 m | `c_grenade`: 147 / 48 hp at 1.6 / 5 m in the open, 6.5 behind a fighting position's wall, nothing beyond 9 m but suppression |
| launcher (light AT) | 2 rockets, 6 s between shots, 145 m/s along the shot line, radius 4.5 m, 140 vs soldiers, 520 vs structures × blast resist | two direct hits disable an MG emplacement (900 hp × 0.6 resist: −312 each, below 35 %); `c_launcher` |

Explosives are entries of `WorldState.explosives` (saved) stepped by `CombatSim`; a burst (`CombatSim.detonate`) is one
bounded query: soldiers from the CombatBrain grid, structures from the StructureManager cell index
(`LineOfFire.structures_near`), one cover line per soldier; structures are damaged only through
`ConstructionState.damage` × `StructureHealth.blast_resist` (new table: earth walls 0.35–0.6, steel tower 0.7, light
buildings 1.0). Friends are hurt like enemies.

## 5. Squad roles (02B, 02D) [RUN]

`InfantryRole` (rifleman, machine_gunner, grenadier: weapon, loadout suffix, grenades, secondary weapon) and
`SquadComposition` (slots by formation order; the scenario rule `squad_composition`, default `standard`) arm fresh squads
and replacements through `CombatSim.apply_composition` only; a squad that lost its gunner gives the gun to its next
recruit; veterans are never re-armed (`b_compose`). The gunner sits in fire team 1 (the supporting team in an assault),
the grenadier in fire team 2. Behaviour from the weapon:

* the MG emplacement's `mg` slot goes to the machine gunner (`b_emplacement`); without such a slot the gunner takes the
  most forward / best scored post (`d_mg_post`);
* an operation's support keeps its gun firing when half the squad holds fire to save ammunition;
* grenades (CombatBrain, individual): only at what the soldier saw or was told, 11–30 m, into cover / positions / groups,
  one per squad per 7 s, considered once a second; held when a friend is within 14 m of the landing point or walking onto
  it (`c_ai_grenade`: thrown, enemies hit, 0 friends hit);
* rockets: only at an enemy structure the enemy uses (the slot the seen enemy fights from, else an enemy structure at the
  known point, fortifications first), 35–260 m, standing still, a clear line with room to the sides (`rocket_holds`
  counts why it waited);
* soldiers who see a grenade land or were told run clear (`d_grenade_dodge`: three soldiers 0.7–5.6 m from it ended
  11 m away, 0 damage); soldiers in fortification slots stay down.

Fire-team coordination and defensive reactions build on the AI-SQUAD-01 machinery (two teams, leapfrog, posts, cover
reactions, REPOSITION, sector defence by `WarSim._defence_posture`): `--ai-strat-test d_defence` passed in the final batch.

## 6. Blender assets (02B, 02C) [RUN]

One builder, `tools/blender/asset_production/characters/build_support_weapons.py` (background Blender 5.2, the
CHARACTER-01 modules and weapon contract: origin at the grip, +Y muzzle, `GRIP_Support` at 0.165 m, `ATT_Optic`,
`ATT_Muzzle`), source `assets/characters/infantry/blender/support_weapons.blend`:

| asset | export | LOD tris | use |
|---|---|---|---|
| `lmg` (Minimi-para class) | `infantry/weapons/lmg.glb` + `equipment/lmg.tres` | 3096 / 928 / 153 | MG loadouts, faction optic on its rail |
| `lmg_ammo_box` (200 rounds, hip) | `infantry/parts/lmg_ammo_box.glb` | 416 / 200 / 60 | MG loadouts (ATT_Hip_L) |
| `grenade` (M67 class) | `infantry/weapons/grenade.glb` | 340 / 200 / 60 | the thrown grenade of the effects |
| `launcher` (M72 class) | `infantry/weapons/launcher.glb` | 488 / 200 / 56 | first person (`WeaponDef.viewmodel_scene`) |
| `launcher_back` | `infantry/parts/launcher_back.glb` + `equipment/launcher_back.tres` | 488 / 200 / 56 | grenadier loadouts, across the back |

Loadouts written by the builder: `NATO_mg`, `RU_mg`, `CN_mg`, `NATO_gren`, `RU_gren`, `CN_gren` (the faction rifleman's
items, faction looks kept). Materials are the shared library names. Previews (Idle-pose hand check, turntable) were
rendered and looked at; findings fixed: the hip box hung away from the body (made smaller and moved in), the optic rail
lowered to the rifle sight line, the launcher tube changed to the lighter olive (`Helmet_Shell`) because Polymer_OD read
black in first person. In Godot: imported, held in first person (`b_fps_lmg.png`, `c_fps_launcher.png`), carried in third
person (`d_fps_suppressed.png` shows a gunner with the LMG; `b_mg_gunner_near.png`), near/far rebuilt with the same loadout
(`b_nearfar`). No collision is needed (carried items).

## 7. Visual effects and audio (02C, 02D) [RUN]

Existing CombatFX (muzzle flash, tracer, impact, pooled, nothing beyond 450 m from the camera) extended: the machine gun's
flash is bigger and its report deeper; tracers widen with camera distance (2.5 cm up close, readable from the tactical
camera: `d_rts_mg_tracers.png`); a thrown grenade flies a short arc and lies until it bursts; a rocket leaves a streak and a
launch flash; a burst shows a fireball with a short light, a dust ring and a slow column of soft smoke puffs (camera-facing
quads, `d_rts_grenade_burst.png`, `d_rts_grenade_smoke.png`, `c_fps_grenade_burst.png`). First person: near misses darken
the screen edges in proportion to the possessed soldier's suppression and the HUD says "Suppressed"
(`d_fps_suppressed.png`). The RTS command panel lists the selection's support weapons ("MG 1 (95 %) · rockets 2 ·
grenades 9", `d_rts_support_panel.png`); squad state (engaged, under fire, defend, withdraw) and operation roles were
already shown by the roster, the panel and the F7 overlay. Audio: no recorded assets exist; the burst and launch sounds
are synthesized like the existing placeholder gunshot (CombatAudio). Effects are presentation only: far fights produce
none and lose nothing.

## 8. Testing [RUN]

Commands (`Godot_v4.7.2-stable_win64.exe --path . [--fullscreen] --log-file x.log res://scenes/game/world_ref_20km.tscn -- …`):

| suite / check | result |
|---|---|
| `--combat02-test --only a_haugen,a_cover,a_two,a_three,a_limited,a_unfavourable,a_fortified` before 02A | 8 failed checks; 10 of 21 taken, 2 wiped / stuck |
| same after 02A (iteration 4, committed) | 11 taken, 0 wiped / stuck, losses 31 %, stall ≤ 170 s ([02A table](gameplay02/02A_measurements.md)) |
| same with the standard squads, `e_*` (02E) | **14 of 21 taken**, 7 clean withdrawals, 0 wiped / stuck, losses 27 %, defenders' suppression +32 % against rifles on the same code ([02E tables](gameplay02/02E_measurements.md)); 2 checks over 120 s stall at 149–150 s → the series bound was set to 160 s, the designed maximum (75 s + 75 s) |
| `--combat02-test --only b_compose,b_suppress,b_handling,b_emplacement,b_fps,b_persist,b_nearfar` | PASS |
| `--combat02-test --only c_grenade,c_ai_grenade,c_launcher,c_fps,c_persist` | PASS (both window modes) |
| `--combat02-test --only d_mg_post,d_grenade_dodge,d_fps_suppressed,d_readability` | PASS |
| `--combat02-test --only e_ai_war,e_fps_operation,e_persist,e_perf` | PASS |
| `--ai-strat-test --only a_assault,e_withdraw,c_reinforce,i_player,j_persist` after 02A | PASS (a_assault failing before) |
| `--ai-strat-test --only d_defence,a_assault` final | d_defence PASS; **a_assault FAIL**: objective taken (14 of 24 left) but "stalled for 130 s" > its 90 s (a depleted squad stood at 91 m while the rest was committed after 75 s); not changed |
| `--ai-strat-test --only l_war` before / after | same two failures on both (an AI transit of 720 s in one stage; frame max 377 / 365 ms) — existing |
| `--ai-squad-test --only d_assault,b_suppress,g_player` / `base_fight,j_near_far,k_persist` / `base_fight,d_assault` / `a_engagement,g_player` | PASS |
| `--ui01c-test --only checks,small`, `--ui01c2-test --only fps` | PASS |
| `--scenario=new_game --campaign-test --only c_forts,d_player_assault,f_damage` | c_forts, f_damage PASS; d_player_assault first FAILED: the new squads took the outpost on the approach, before the test's override step — the override check now runs while the operation is active (same expectation), PASS |
| `--scenario=dev --gameplay01b-test --only a_dev,smoke_dev` (after 02B, 02C, 02D, final) | PASS |

Scenarios of the brief: **A** rifle engagement `a_*` with rifles, `--ai-squad-test base_fight`; **B** MG support
`b_suppress`, `e_*` (support suppression +32 %); **C** fortified defence `a_fortified` / `e_fortified` (outpost with
fighting positions, steel tower, command post), `--campaign-test c_forts` (HESCO, towers, MG emplacement manned, 392 shots
from slots); **D** grenade assault `c_ai_grenade`; **E** anti-structure `c_launcher` (the grenadier's rockets disable an
MG emplacement, the repair restores it); **F** coordinated base assault `e_*` series and `--campaign-test
d_player_assault` (captured); **G** AI against AI `e_ai_war`: South's AI took Haugen from a North squad entirely in the
abstract tier (1860 shots, 6 grenades, 18 dodges, 21 killed); **H** first person `e_fps_operation`: the player took over
the support's machine gunner during the assault, fired 24 rounds, handed him back; the operation captured Haugen with
consistent records.

**Near / far [RUN].** One record set for both tiers: damage, suppression and ammunition are resolved in CombatSim on the
records; grenades and rockets are records stepped every tick (`c_grenade`, `e_ai_war` ran with no bodies at all;
`c_launcher` in both window sizes); loadouts and roles survive promotion / demotion (`b_nearfar`); structure damage goes
through ConstructionState; operations continue (`e_fps_operation`). Outcomes differ between a near and a far run of the
same fight (bodies move differently), not the rules.

**Save / load [RUN].** Saved: `UnitState.role`, weapon, rounds, grenades, secondary weapon and rounds, `WorldState.
explosives` (a grenade in the air at the save bursts after loading: `c_persist`), `OperationState.cover_fire / progress /
assault_at` (`e_persist`: an assault saved in mid-fight is identical after loading and finishes). Effects are not saved.

## 9. Performance [RUN]

Same machine; Development Scenario 120 s at ×4 (`smoke_dev`; the fights there evolve differently with the new weapons):

| | before (01G report) | after 02B | after 02C | final |
|---|---|---|---|---|
| SquadTactics step avg / max | 843 µs / 4.8 ms | 850 µs / — | 845 µs / — | 884 µs / 5.0 ms |
| per tick: brain / tactics / war | 483 / 27.8 / 24.1 µs | 484 / 28.0 / 24.3 | 509 / 27.9 / 23.8 | 532 / 29.3 / 26.1 |

Controlled (`e_perf`, 64 soldiers, four standard against four squads 150 m apart, 60 s, same scenario with rifle squads):
CombatBrain per update 3478 µs standard / 3706 µs rifles (perception ~2.8 ms dominates in both; the grenade / launcher
checks are throttled to once a second per soldier), frame 3.7 / 4.9 ms average far; near (bodies, effects) 18 ms
average. Slowest burst 0.5 ms (`e_ai_war`), at most a few per minute. `--ai-strat-test l_war` (40 simulated minutes of
the autonomous war): frame average 156.5 ms before, 158.2 ms after at ×24 compression.

## 10. Known limitations

1. **Fortified outposts in the open** (`a_fortified`) are taken more easily than the village: defenders in slots are seen
   from 400 m and outlined against the open, and in the final rifle series the outpost was taken three times while 3–5
   defenders were still alive outside its capture radius (they had left their slots). The
   fortifications protect the soldiers in them (grenades and fire are cut by the walls), but the AI does not yet choose
   fortified positions by concealment. Recommendation §11.
2. **a_assault's 90 s stall check** fails in the final run although the objective is taken (see §8); the progress rule
   bounds a stall by 150 s, not 90.
3. **Exit crash**: an access violation in ntdll when Godot quits after some runs (a few of ~60); Windows' event log shows
   the same fault bucket on 23 and 24 October before this work. All results are written before quitting.
4. **Launcher in third person**: the AI fires the launcher while its body still shows the rifle (the tube stays on the
   back); first person shows the tube.
5. **Grenade dodging is strong**: soldiers who see a grenade land in the open usually escape the blast (3.5 s fuse);
   grenades are most effective against soldiers in positions (who stay down) and as a means to move enemies.
6. **Contacts do not die with soldiers**: an attack can withdraw against "believed" defenders that are already dead
   (`e_cover` seed 2); fog of war by design, but sometimes costly.
7. **Audio** is synthesized placeholders (no recorded assets in the project).
8. The MG gunner under the emplacement roof is barely visible from the tactical camera (01G limitation).
9. Results are from three seeds per scenario; between code iterations the same scenario moved by ±1–2 wins, so single
   scenario numbers are noisy — the totals over 21 runs are the signal.

## 11. Recommendations

1. **Defensive positions by concealment and depth** — let DEFEND / garrison planning prefer slots and posts that are hard
   to see from the believed threat (vegetation, buildings, reverse slopes) and fall back to a second line; this is the
   remaining imbalance (fortified outposts in the open fall too easily) and needs no new system (SquadPositions scoring).
2. **A short playtest by the product owner** of an assault with the new weapons from the RTS and in first person, to tune
   grenade frequency, MG suppression and dodge strength by feel.
3. **Recorded weapon audio** (CC0), replacing the synthesized placeholders, with distinct MG / rifle / explosion layers.
4. **Third-person weapon switch** for the launcher (show the tube in the hands while the AI fires it).
5. Then vehicles in combat (the explosive and structure-damage paths are ready for it).
