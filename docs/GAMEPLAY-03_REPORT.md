# GAMEPLAY-03 — Defensive Warfare, Concealment & Tactical Depth

Branch: `develop` (the project standard allows no milestone branches; see CLAUDE.md). Commits: `0040236` 03A, `be98a95`
03B, `6d88ecc` 03C, `51425c7` 03D, 03E (this report, the integrated tests). Not pushed.

Markers: **[RUN]** measured in a run of the real game on ref_20km; **[CODE]** read from the code; **[NOTE]** judgement.

## 1. Executive summary

Before this milestone a garrison gave its base away: a squad defending a fortified outpost judged itself by an
effectiveness that halves when it is outnumbered, so a little suppression made it **withdraw 110–190 m out of the base
with no casualties**, and the attackers walked in (open outpost taken 3/3 at 11 % attacker losses) [RUN]. Posts were
chosen without regard to whether the enemy could see them.

Now [RUN, CODE]:

- **Positions are judged against the believed threat**: fortification slots and natural posts on one scale (protection,
  line of fire, concealment measured from three viewpoints on the threat's side, prepared positions, sector, elevation,
  distance), weapon-aware (the MG takes the widest arc it is least seen from and the MG emplacement's gun slot; the
  grenadier a concealed post). A changed threat moves only the soldiers whose posts no longer serve.
- **Layered defence**: a garrison or stationed defence never leaves for being outnumbered. It falls back **a line at a
  time inside the objective's capture radius** (secondary, then last round the objective), the forward fire team first
  while the other covers, pinned squads wait; the garrison assignment is kept; the player's order still overrides.
- **Attackers** rank fire support by danger (enemies reported at fortifications first, MG on the most dangerous report,
  never at unreported positions), commit sooner when nobody is advancing, send a support squad that can no longer
  suppress in with the assault, hold depleted squads as a reserve and retry from another side. The Haugen "130 s stall"
  was half a measuring error and half a real coordination defect; both are fixed (§5).
- **Polish**: the AI grenadier visibly shoulders the launcher (rifle away) before firing; grenades are noticed after a
  seeded delay, and a soldier who cannot get clear gets down (which now really reduces the blast); the MG emplacement's
  roof leaves the rear open so a manned emplacement reads as manned; "Fall back (line N)" is shown.
- **Outcome** (before → after, same sites and seeds): attacker losses at the open outpost **11 % → 44 %**, reverse slope
  24 → 46 % (one of three attacks now fails), forest 39 → 42 %, village 31 → 21 % (noise: §9); fortification slots given
  up 8.3 → 3.7; the defence holds the objective contested for 78–186 s instead of leaving it. Attackers still usually
  win against one squad with three — a defence costs them now instead of being a walk-in.

## 2. Baseline diagnosis (03A, before any change) [RUN]

`--combat03-test` (new, `scripts/debug/combat03_selftest.gd`): one standard South squad garrisons a command-post base;
three standard North squads attack it from 500 m with an ATTACK operation, camera far away, seeds 1–3. The sites come from
a deterministic search round Haugen (`_site`): **A** open outpost with two fighting positions, an MG emplacement and a
steel tower (`d_open`), **B** forest edge (`d_forest`), **C** the village (`d_village`, Haugen), **D** reverse slope
(`d_reverse`, crest 6 m). `CombatDiag` was extended with the defence metrics: first sighting each way (time, distance),
first hit, defender soldier-seconds seen by an attacker, soldier-seconds inside the capture radius, post changes,
fortification slots given up, deepest line, contested seconds.

| before | taken | attacker losses | first seen (m) | defenders seen (soldier-s) | slots given up |
|---|---|---|---|---|---|
| open outpost | 3/3 | 11 % | 346 | 413 | 8.3 |
| village | 2/3 | 31 % | 398 | 275 | 0 |
| forest edge | 2/3 | 39 % | 43 | 32 | 0 |
| reverse slope | 3/3 | 24 % | 35 | 32 | 0 |

Findings:

1. **The garrison withdrew instead of fighting.** `_run_defend` withdraws below `withdraw_eff` 0.38; the assessment's
   `threat` factor halves the effectiveness when the believed enemy outnumbers the squad, so 24 against 8 plus light
   suppression put a fresh, unhurt garrison below the line: it left 110–190 m out of its base (all 8.3 slots per run given up)
   and the attackers captured an empty objective.
2. **Posts ignored concealment.** Slots won by their cover alone; natural posts were found by `find_posts` without a view
   from the enemy side. On open ground the defenders were seen from 346 m; at the forest edge only from 43 m (the trees,
   not the choice, concealed them).
3. **The MG was not placed by its arc**, and posts were chosen once, before a threat was known, and then kept.

## 3. Position selection (03A) [CODE, RUN]

- `SquadPositions.exposure(p, threat)`: share of three viewpoints (on the threat bearing and ±25°, 60–300 m out, eye 1.6 m)
  that see a soldier at `p` (1.35 m) through the same `LineOfFire.sight` the perception uses (terrain, structures,
  foliage layers: **concealment**; bullets stop only at trunks, structures and terrain: **cover** stays the separate
  `protected` test). Cached 60 s per 2 m cell and 25 m threat cell, invalidated when construction changes.
- `SquadTactics._judged_posts`: slots and natural candidates on one score, weights `post_w` (protect 3, fire 2, conceal 2.5,
  prepared 1, sector 1, elevated 0.4, distance) and weapon modifiers `role_post_w` (MG arc / exposure, grenadier margin);
  exposure only for the best `count × post_exposure_per` candidates; MG slot bonus when the squad has an MG.
- Posts planned before any threat was believed are judged again once one is (`planned_blind`).
- A REPOSITION keeps the soldiers whose post still serves (`_post_still_good`: a slot whose arc faces the threat, natural
  cover that protects from it).
- `p_posts`: forest edge exposure 0.0 for all 8 posts; open outpost all 8 in slots, the MG gunner in the MG emplacement's
  gun slot, no shared posts. Plan cost **~12 ms** per DEFEND plan (8–16 exposure checks, 3.7–8.8 ms of it) — a spike at
  the moment a squad is ordered, not per tick (§10).

## 4. Layered defence (03B) [CODE, RUN]

- A garrison (`garrison_base`) or a squad stationed on an objective judges holding **without the outnumbered factor**.
  When it cannot hold it calls `_fall_back`: line 1 a third of the radius behind its front, line 2 round the objective's
  centre, posts only **inside the capture radius − 8 m** and behind the line it leaves. `SquadState.defence_line` (saved).
  The move is a REPOSITION in stages ≥ 100: the forward fire team moves while the other fires at the threat, then the other;
  then DEFEND holds the line (commit 25 s). Pinned (≥ 50 %) squads wait up to 20 s before getting up. Only from its last line
  does it withdraw — and a garrison then still keeps its base assignment.
- Capture rules are unchanged (`WarSim._update_capture`); the defence only stays inside the area that decides it.
- Threat direction: `f_threat` — the believed enemy reported from 120° to the side: the squad repositioned [RUN].
- Persistence: `f_persist` — saved in the middle of a fall back (test save folder), identical squad record after loading,
  the fall back completed to a held line 1 with the garrison kept [RUN].
- Player override: `f_override` and `i_player` — a move order takes a falling-back garrison out of it at once (garrison
  ended, order MOVE) [RUN].
- AI garrisons use the same rules (they are the same code); campaign `d_ai_war` (South AI captures an East outpost
  off-screen) passed: the outpost now held a minute longer (4.5 vs 3.5 min) [RUN].

## 5. Attacker interaction (03C) [CODE, RUN]

- **Known threats only**: fire support ranks the faction's contacts near the objective — an enemy reported within 6 m of
  an operational enemy fortification +3, fresh (≤ 15 s) +1.5, strength × confidence; only reports are fired at, never an
  empty structure. The MG always takes the most dangerous report. At the open outpost the support fired at a fortified
  contact 200–333 times per attack [RUN].
- **Commitment**: when no assault squad is actually advancing, the stall decision ("everyone goes in together", then break
  off) comes after `idle_commit_s` 40 s instead of 75 s. A depleted assault squad without a firing position holds in cover
  as the reserve. A re-tasked assault goes for another spot of the objective, not across the same ground.
- **Support joins the assault**: a fire-support squad that cannot suppress any more (ammunition < 25 %, no firing position)
  but is not depleted joins the assault. The Haugen trace had an 8-man support squad idle for 140 s while the assault went
  in three men at a time.
- **Explosives**: rockets at the open outpost 1–2 per attack, grenades 4–10 per attack at the forest edge and reverse slope
  (positions behind cover) [RUN].
- **Haugen `a_assault` 130 s stall** (brief: investigate, do not raise the threshold): two causes.
  1. *Measuring*: the stall counted only "an attacking squad got 10 m closer". In the village the assaulting squads fight
     from the houses at the objective's edge; their centres stay put while they clear it. The run that failed with 121 s
     was a won close fight (defenders 6 → 0 during the "stall"). A defender put out of the fight now counts as progress;
     the 90 s limit is unchanged and the distance-only value is still reported (`max_stall_distance_only_s`).
  2. *Behaviour*: the idle support squad above (fixed). After both: `a_assault` PASS [RUN].
- Balanced outcomes: §9.

## 6. Combat polish (03D) [CODE, RUN]

- **Launcher in the hands**: the AI grenadier shoulders the launcher before firing (`launcher_raise_s` 0.8 s, the update is
  spent on it) and holds it 2.5 s after; `UnitState.sec_raised_at / sec_shown_until` (saved). The body shows the launcher at
  the weapon bone and hides the rifle and the back launcher (`InfantryCharacter.show_secondary`). `g_launcher_hands`: raised
  1.9 s before the rocket left, rifle hidden at the shot, rifle back 2.5 s after [RUN].
- **Grenade reactions**: noticed after a seeded delay (0.5–1.5 s; the thrower's friends 0.2–0.5 s; × (1 + suppression));
  a soldier who cannot get out of the blast in the time left, or is pinned, gets down where he is (`UnitState.down_until`,
  saved) — and the burst now reaches a downed soldier at 0.35 m and with half the fragments (`CombatSim.blast_down_height /
  blast_down_factor`): getting down is a real choice, not an animation. `g_grenade_react`; `d_grenade_dodge` damage 135 →
  58 for the same throw [RUN].
- **Readability**: "Fall back (line N)" as the tactic name (HUD, roster, inspector); defending / suppressed / support / garrison
  states already shown by UI-01C (`d_readability` shots: `docs/gameplay03/d_rts_*.png`).
- No new audio (no assets beyond the existing placeholders).

## 7. Blender assets [RUN]

| Asset | Change | Build | QA gate | Godot |
|---|---|---|---|---|
| MG emplacement (`fam_modules.mg_emplacement`, `assets/military/blender/mg_emplacement.blend`) | the sandbagged roof covers the front two thirds (gun and both slots), the rear third is open; front and side parapets, firing band, gun sill and slots unchanged; roof collision box shortened accordingly | `build_assets.py -- --only mg_emplacement --export --save-blend --previews --qa --qa-strict --qa-baseline ...` | pass, 0 new findings | validator 0 errors (9992 / 168 / 72 tris, 5 materials) |

Renders: `docs/gameplay03/blender/mg_emplacement_blender.jpg` (Blender) and `mg_emplacement_godot.jpg` (Godot asset lab);
the top view shows the open rear. Why: from the RTS camera the old full roof made a manned emplacement look like an empty
box. Cover against the enemy is unchanged (parapets and roof over the slots).

## 8. Testing [RUN]

Change-impact runs per stage (announced in the session), then the integrated 03E runs.

| Run | Covers | Result |
|---|---|---|
| `--combat03-test --shots` (one complete run of the new suite, 1920x1080) | A `d_open`, B `d_forest`, C `d_village`, D layered (`d_*` lines, `f_persist`), F rockets / grenades in `d_*`, I `i_player`, J `j_persist`, `p_posts`, `f_threat`, `g_launcher_hands` | see below |
| `--combat02-test --only b_suppress,b_emplacement,d_mg_post,d_readability,e_perf` | E MG suppression, readability, performance | PASS |
| `--ai-squad-test --only c_flank` | G flanking | see below |
| `--scenario=new_game --campaign-test --only d_ai_war` | H AI vs AI off-screen | PASS |
| `--scenario=dev --gameplay01b-test --only smoke_dev` | performance baseline | PASS |
| per stage: `--ai-strat-test --only a_assault,d_defence,e_withdraw`, `--ai-squad-test --only f_withdraw,a_engagement`, `--campaign-test --only c_ai_garrison,d_player_assault,d_ai_war`, `--combat02-test --only c_launcher,c_grenade,d_grenade_dodge,d_mg_post,c_forts` | regressions of the touched systems | PASS (after the fixes below) |

`--combat03-test --shots` results (final run, then reruns of the three checks fixed in 03E):

| Check | Result |
|---|---|
| `p_posts` | forest edge: 8 posts, exposure 0.0; open outpost: 8 of 8 in slots, MG gunner in the MG emplacement's gun slot, no shared posts; plan 12.0 / 11.8 ms |
| `f_threat` | threat reported from 120° to the side: 1 reposition, 8 of 8 moved (none of the old posts covered the new bearing) |
| `f_persist` | saved during the fall back (`user://test_saves/.../combat03_fallback.sav`), identical after loading, completed to DEFEND line 1, garrison kept |
| `f_override` | (rerun) fell back by itself; a move order: garrison ended, order MOVE |
| `g_launcher_hands` | launcher raised 2.0 s before the rocket, rifle hidden at the shot, rifle back 2.5 s after |
| `g_grenade_react` | (rerun) noticed after 1.1–1.3 s; one got clear (7.7 m), the one standing on the landing spot got down (no time), the pinned one stayed down |
| `i_player` | RTS garrison order taken, 8 of 8 in slots, 197–639 rounds fired, fell back to line 1, no post outside the capture area, garrison kept; first person in the contested base: fired, back to RTS, garrison kept; a move order overrode the garrison |
| `j_persist` | saved during the assault with the objective contested (31 soldiers, 5 structures, 3 contacts): no difference after loading in units (orders, posts, slots, health, ammunition, grenades, rockets, suppression), squads (garrison, tactic, line, role), structures, contacts, operation, objective; the fight went on to an outcome (attack failed, base held) |
| `d_open / d_village / d_forest / d_reverse` | 3 seeds each: §9 |

Other 03E runs: `combat02 b_suppress, b_emplacement, d_mg_post, d_readability, e_perf` PASS; `campaign d_ai_war` PASS (AI vs AI
off-screen, no bodies near, base and structures changed hands); `smoke_dev` PASS; `ai-squad c_flank` FAIL — also on the
GAMEPLAY-02 code (`5134601`, two runs, same failure), so not caused by this milestone (§11).

Screenshots (1920x1080, inspected): `docs/gameplay03/i_player_garrison_manned.png` (RTS: the player's outpost, slots and posts,
GARRISON in the HUD), `i_player_fps_in_base.png` (first person in the contested base: the MG emplacement from behind with
its open rear, soldiers in a fighting position), `p_posts_forest.png`, `p_posts_open.png`, `f_threat_reoriented.png`,
`b_mg_emplacement_manned.png`, `b_mg_firing_rts.png`, `d_rts_*.png`, `e_large_fight_near.png`; asset renders in
`docs/gameplay03/blender/`.

**Near / far.** The defence series and `j_persist` run with the camera kilometres away (abstract tier, no bodies); `d_ai_war`
off-screen; `i_player` and `g_launcher_hands` with bodies near the camera (near tier) and first person. The fall back,
the post choice and the launcher state are on the records (`defence_line`, `post_pos`, `fort_slot`, `sec_raised_at`,
`down_until`), so both tiers and a save in between behave the same; only the bodies' paths differ.

**Test changes and why** (none made merely to pass):

- `combat02 d_mg_post` (03A): "MG on the most forward post" was meaningless with 1.5 m spacing; it now checks the MG is on
  one of the two least exposed posts (what the new rule promises).
- `ai-strat a_assault` (03C): progress also counts defenders put out of the fight (§5).
- `combat03 g_grenade_react` (03D/E): a soldier who stood where the grenade landed and noticed late gets down instead of
  running (the rule); the check accepts "clear or down for lack of time", at least one clear, nobody before the delay; and
  it now requires a clean place (no other soldiers within 300 m: stray fire pinned a "free" soldier in the full run).
- `combat03 f_override` (03E): when the attack does not push the garrison back in that run, the fall back is started through
  the same `_fall_back` call (reported as `fall_back_started_by_test`); `f_persist` checks that it happens by itself.
- `campaign d_ai_war`: passes alone; run after `d_player_assault` in one session South holds instead of attacking (its
  decision has no candidates after losing a base in the previous check) — a test-order dependence, not 03B.

## 9. Balance comparison [RUN]

`tools/combat03_compare.py benchmarks/raw/gameplay03/combat03_before.json benchmarks/raw/gameplay03/combat03_final.json`
(3 seeds each, same sites; averages):

| scenario | taken | attacker losses | defender losses | first seen (m) | defenders seen (soldier-s) | slots given up | deepest line | contested (s) | explosives |
|---|---|---|---|---|---|---|---|---|---|
| A open outpost | 3 → 3 | 11 % → 44 % | 100 % → 100 % | 346 → 332 | 413 → 451 | 8.3 → 3.7 | – → 1.7 | – → 118 | – → 2.0 |
| C village | 2 → 3 | 31 % → 21 % | 96 % → 100 % | 398 → 399 | 275 → 207 | 0 → 0 | – → 1.7 | – → 78 | – → 0.3 |
| B forest edge | 2 → 3 | 39 % → 42 % | 83 % → 100 % | 43 → 32 | 32 → 39 | 0 → 0 | – → 1.7 | – → 186 | – → 7.7 |
| D reverse slope | 3 → 2 | 24 % → 46 % | 100 % → 92 % | 35 → 43 | 32 → 37 | 0 → 0 | – → 1.7 | – → 117 | – → 8.3 |

Per stage (attacker losses, open / village / forest / reverse): before 11 / 31 / 39 / 24 %; 03A 7 / 8 / 32 / 29 %;
03B 36 / 25 / 31 / 38 %; final 44 / 21 / 42 / 46 %. Reading [NOTE]:

- The decisive change is 03B: a garrison that stays makes the attack pay (open outpost ×4 the losses). 03A alone changed
  little in outcome (posts were already fortifications on open ground; concealment helped the forest and reverse slope
  defenders to be seen later: 43 → 29–32 m).
- Three squads still beat one in most runs — with a 3:1 ratio that is the expected result; the defence now costs the
  attacker 40–46 % at prepared or concealed positions, and the reverse slope held once.
- The 3-seed series are noisy (single runs of the village moved between 4 % and 54 % losses in this milestone's
  intermediate runs; GAMEPLAY-02 saw the same). Differences under ~15 points are not conclusions.
- Defenders seen from about the same distance on open ground (the fortifications stand in the open: §11).

## 10. Performance [RUN]

Same machine. `smoke_dev` (Development Scenario 120 s at ×4), against the GAMEPLAY-02 final numbers:

| | GAMEPLAY-02 final | GAMEPLAY-03 final |
|---|---|---|
| SquadTactics step avg / max | 884 µs / 5.0 ms | 901 µs / 5.5 ms |
| per tick: brain / tactics / war | 532 / 29.3 / 26.1 µs | 538 / 30.0 / 26.8 µs |

`e_perf` (64 soldiers, far): CombatBrain per update 3478 → 3577 µs (standard), frame 3.7 → 4.25 ms average. Same at 1600x900 in the final tree: far 3369 µs / 3.83 ms (p99 17 ms), near (bodies, effects) 16.6 ms average (GAMEPLAY-02: 18 ms).

DEFEND planning with judged posts costs ~12 ms once per plan (exposure 3.7–8.8 ms of it, cached 60 s); with a few squads
planning in the same tick this is a visible spike — staggering plans over ticks is the recommended follow-up (§12).

## 11. Known limitations

1. **Fortifications in the open are still seen from 330+ m**: concealment cannot hide a sandbag structure on a bare field;
   the defence there is cover and fallback, not concealment. Camouflage nets / siting rules for building are not in scope.
2. **Three squads against one usually win** (by design of the scenario); the defender's advantage is losses and time, not
   victory. Larger AI garrisons are AiBases' decision (unchanged).
3. **Plan cost spike** ~12 ms per DEFEND plan (§10).
4. **Merged distance LODs** keep the rifle: beyond 12 m from the camera the third-person launcher is drawn but the rifle
   of the merged LOD mesh is not hidden (the merge is per loadout).
5. **No prone animation**: a soldier who gets down for a grenade crouches visibly; the record (`down_until`) carries the
   real effect.
6. **`d_ai_war` test-order dependence** (§8) and the pre-existing exit access violation (Godot quits with a fault in ntdll
   after some runs; results are written before).
7. **`c_flank`** (AI-SQUAD-01 test): fails in this milestone's runs and equally on the GAMEPLAY-02 code (the flanking team is stopped by its own effectiveness rule after losses, or the support team moves); FLANK was not changed here. Pre-existing, to be looked at with the squad tactics.
8. Placeholder audio unchanged.

## 12. Recommendations

1. **Stagger and budget post planning** (one DEFEND plan per tick per faction; exposure checks across ticks) before larger
   garrisons are common.
2. **Garrison size from the threat**: AiBases could add a second squad to a base under a believed threat — the defence now
   makes that worth it.
3. **Siting and camouflage for construction**: a camouflage-net structure and a preview of exposure from the enemy side when
   placing fortifications (uses `SquadPositions.exposure`).
4. **Resupply in the fight**: support squads run dry (the Haugen trace); a short ammunition run from the operation's
   vehicle or base would keep the support firing instead of joining the assault.
5. **NAVIGATION N1** stays the next milestone in the roadmap; the defensive work does not depend on it.
