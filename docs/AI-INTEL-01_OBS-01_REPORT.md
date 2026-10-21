# AI-INTEL-01 + AI-OBS-01 — persistent faction intelligence and AI observability

Branch `feature/ai-intel-01` (worktree `../fractured-nations-aiintel01`), created from `feature/integration-04`
@ `ead6837` (verified: unchanged on origin, clean worktrees, no conflicts). Not merged into `main`.
Plan before coding: replace the omniscient `WarSim.known` table by reported, aging contacts; keep the one
perception pipeline (`CombatBrain`), the one decision system (`WarSim._decide`) and the one world state.

Evidence tags: **[TEST]** run in the real game (`--ai-intel-test`, `--sandbox-test`), **[VISUAL]** screenshots
looked at, **[CODE]** read in the source, **[LIMIT]** a known limitation.

## 1. Summary

* Factions no longer know where enemies are because they are near. `WarSim.known`, `_update_intel`,
  `intel_m` and `intel_forget_s` are removed; no strategic code reads an enemy soldier's position any more.
* What a faction believes is `WarState.contacts` (a `ContactState` per believed enemy group). Reports come
  from soldiers who **see** an enemy, **hear** gunfire, **take fire**, or hold an objective an enemy stands in;
  they arrive after a delay, merge into existing contacts, and from then on only **age**: confidence falls,
  the uncertainty circle grows, the position stays where it was reported. Contacts are saved with the war.
* `WarSim._decide` / DEFEND read the picture through `threat_near`; an AI faction sends one squad to look at an
  unconfirmed report near its own ground, and drops the belief when nothing is found.
* The strategic map shows the player's picture (and only that), plus a **developer inspector** (**I** factions,
  **T** true positions): contacts with age, confidence and uncertainty circle, the faction's last decisions with
  the numbers they were based on, and a squad's real reason for what it does.

## 2. Files and systems changed

| File | Change |
|---|---|
| `scripts/strategy/contact_state.gd` (new) | `ContactState` record, enums, save/load |
| `scripts/strategy/intel_sim.gd` (new) | `IntelSim`: report API, delay queue, merge, ageing sweep, queries, measurements |
| `scripts/strategy/war_state.gd` | `contacts`, `next_contact_id`, `intel_pending` + save/load |
| `scripts/strategy/war_sim.gd` | owns `intel`; `known` / `_update_intel` / `known_near` removed; `threat_near`; objective-presence reports; `_decide` reads contacts, records decision snapshots, `_investigate`; DEFEND and MOVE operations; `explain_squad`, `explain_faction` |
| `scripts/strategy/operation_state.gd`, `faction_state.gd` | `contact_id`, `reason` (saved); `decisions` (runtime, bounded) |
| `scripts/combat/combat_brain.gd` | four report hooks (target seen / refreshed, shots heard, first fire taken) and `_group_near`; no new sight checks |
| `scripts/ui/strategic_map.gd` | contact markers replace the old known-enemy markers; developer inspector (I / T); `contact_markers()` |
| `scripts/debug/ai_intel_selftest.gd` (new), `core_demo.gd`, `sandbox_selftest.gd` | `--ai-intel-test`; the old `ws.known` helper uses contacts |
| docs | this report, `AI_ROADMAP.md`, `CLAUDE.md`, `README.md` |

Unchanged on purpose: `WorldSim`, `DetailManager`, `SquadControl`, `CombatSim`, `LineOfFire`, `VehicleSim`,
logistics and bases, the order of authority (player > operation > reaction).

## 3. Contact record and ownership

`ContactState` (one believed group; `WarState.contacts[faction][id]`):

| Field | Meaning |
|---|---|
| `id` | stable, from `WarState.next_contact_id` (saved) |
| `faction`, `enemy_faction` | who holds the belief; which enemy faction (−1 = not identified, e.g. gunfire) |
| `kind` | unknown / infantry / vehicle (vehicles recordable, not yet observable, see §12) |
| `source` | seen, took fire, heard, held ground (objective) |
| `pos` | where it was **last reported**; never refreshed from the world |
| `t_seen`, `t_report`, `t_first` | observation time, time the faction received it, first report |
| `conf0`, `unc0` → `conf`, `unc` | confidence / uncertainty radius at the last evidence, and now |
| `strength` | estimated enemy soldiers |
| `ids`, `ids_t` | at most 12 reported enemy unit ids with report times (identity and counting only; no positions) |
| `status` | observed / reported / stale (lost contacts are removed) |
| `investigated_until`, `reports` | cooldown for AI investigation; reports merged |

Ownership: `WarState` stores them (saved in the same world file, no new persistence); only `IntelSim` writes
them; `WarSim` and the map read. The per-faction table is capped at 40 (lowest confidence evicted). Runtime
only: the unit→contact index, per-observer throttles, the inspector history.

## 4. Observation and reporting rules [CODE]

| Source | Trigger | Delay | Position | Confidence at report | Uncertainty |
|---|---|---|---|---|---|
| Seen | `CombatBrain._acquire` / each refresh of a visible target (the line of sight was just checked) | 3 s | the sighted soldier's position | 1.0 | 6 m + 4 % of the distance |
| Took fire | first time a soldier comes under fire (the existing `threat_pos`, already blurred up to 8 %) | 3 s | `threat_pos` | 0.55 | 40 m + 12 % of the distance |
| Heard | an idle soldier hears a recent enemy shot within 150 m (existing hearing loop) | 6 s | **blurred**: ±25 % of the distance (min 10 m), seeded | 0.4 | 40 m + 50 % of the distance |
| Held ground | own and enemy soldiers both inside an objective's radius (capture update) | 1 s | objective centre | 0.8 | half the radius |

Throttle: one report per observing soldier per 2.5 s (4 s for sound/fire). Sound reports carry **no identity**
(`enemy_faction = −1`, kind unknown, strength 2). A sighting carries an estimate of the group size (§12 G9).
There is no radio model and no new line-of-sight check: the existing perception budget is the only detector.

**Near / far.** Perception is `CombatBrain` on records only, the same code in both tiers; reports are made from
records; the sweep is `WorldSim`-owned. The sandbox runs with `distance_lod = false`, so the camera cannot change what
is detected (with LOD on, distant soldiers perceive at half rate: a slower, not different, detection). [TEST] e_tiers.

## 5. Confidence, uncertainty, lifecycle

* `conf = conf0 · exp(−age / τ)`, τ = 90 s (seen, held ground) or 45 s (fire, heard); `unc = unc0 + speed · age`
  (1.2 m/s infantry, 8 m/s vehicles), capped at 800 m.
* **Observed**: seen within the last 7 s. **Reported**: conf ≥ 0.45 or evidence younger than 30 s. **Stale**: below 0.45.
  **Lost**: below 0.12 → removed. A seen contact is lost about 190 s after the last sighting; a heard one
  (0.4 · e^(−t/45)) after about 55 s.
* Fresh evidence from the same unit, or within 60 m (140 m for sound) plus half the contact's uncertainty, updates the
  contact (position averaged while it is being watched, replaced after a gap); a worse source never overwrites a
  fresher better one; a unit 120 m away from its group splits off.

## 6. Strategic AI integration [CODE, TEST]

Leak audit of the decision path (`_decide`, `_update_operation`, `_free_squads`, reserves, capture):

| Reads | Verdict |
|---|---|
| `known_near` in threat detection, defenders estimate, DEFEND "threat" | **replaced** by `intel.threat_near` (strength × confidence, uncertainty circle included) |
| defenders of an enemy objective nobody reported | unchanged assumption (`value · 4`, HQ ≥ 24), now labelled `basis: assumed` in the decision snapshot |
| `_strength_near`, free squads, garrisons, reserves | own forces: legitimate |
| objective ownership, capture progress, `contested`, `presence` | world mechanics of ground the faction's soldiers are standing on; enemy objectives' owners are map knowledge |
| `_lost_by` (ownership history) | public history |

New behaviour: (a) threat response uses the picture (24 enemies in view are estimated "about 21" and South reinforces
Verket; as the reports age the estimate falls 21 → 9 in 130 s); (b) `_investigate`: one free squad within 2.5 km goes to
the most credible unconfirmed contact near an owned objective (no operation already heading there, 150 s cooldown) as a
MOVE operation with `contact_id`; on arrival the contact is weakened (×0.25) unless something newer was seen. Existing operations
are untouched; only the DEFEND quiet-period test reads contacts.

## 7. Debug overlay and inspection (AI-OBS-01)

* **Player view** (always): the player faction's contacts. Filled diamond = observed now, outlined = reported, small and faded
  = stale, "?" ring = group not identified (heard), circle = how far it may have moved, number = believed strength.
* **I** (strategic map): inspector for each faction in turn, then off. Contacts show `#id kind ~strength conf% age source`.
  Bottom panel: contact counts; the last decision with its inputs (threat per owned objective with the contacts used, defenders, action
  taken; the best four attack candidates with score, value, distance, defenders and whether they are `reported` / `assumed`, needed
  strength; the chosen reason); active operations with their `reason`; the best contacts.
* **T** (with the inspector on): true squad positions of the other factions, drawn hollow and labelled `TRUTH`; click one
  to inspect that squad (also shown for the selected own squad). Never read by any decision; off by default.
* **Squad inspection** (`WarSim.explain_squad`): order and target, *who commands it* (operation and whether the player's or the AI's, direct
  player order, garrison, idle), the operation's `reason` and contact, route progress, direct observation (soldiers engaging / under fire /
  in cover with one real `ai_reason`), the faction picture within 600 m.
* Decision snapshots (`FactionState.decisions`, last 10) are captured inside `_decide` from the numbers it used; not saved.
  [LIMIT] No inspector in the RTS view; the F4 soldier card is unchanged.

## 8. Persistence [TEST f_persist]

Contacts and in-flight reports are part of `WarState.to_dict` (same F5 / F9 file). Five contacts of different source/age/confidence
(including one report still in flight): all fields identical after load (0 differences); simulated time resumed from the saved time;
no contact refreshed by the load (confidence follows `conf0 · e^(−age/τ)` from the saved `t_seen`); the report in flight at the save
applied exactly once after the load; the same unit reported again joined its contact (no duplicate, identity kept); `threat_near`
sees the restored contact. `sandbox persist` (341 keys) still passes.

## 9. Near / far consistency [TEST e_tiers]

Same squads, same geometry, camera near and far: hidden squad, near: `t_seen` and position unchanged for 25 s; hidden, far (both squads
abstract, no bodies): unchanged for 25 s, one contact, same id; South walks into view while far: detected without any body (observation 8.1 s after the order; near, the same walk
gave 13.0 s to the *report*, i.e. about 9.9 s to the observation; the test allows 14 s of difference); camera returns: one contact, same id, 16 members, no unit duplicated.
Not magically reacquired, not erased. Difference left: with `distance_lod` on (legacy layouts) far soldiers perceive at half rate.

## 10. Scenarios and results

Results from `--ai-intel-test`. Each scenario resets contacts, reports, operations, test units and garrison stations and can run alone or in any order.
Provenance, honestly: the scenarios were run in groups on the final production code (A, B, D; G, K, J; z, C, E, F, H; I; A again for the player-view
screenshot). A first full chain run had one failure (A waited too briefly for South's report of North) and a later run one (I assumed which enemy South
perceives first); both were test assumptions, fixed and re-run alone. No scenario was weakened to pass: the checks that changed are named in §12.
Result files are local (`benchmarks/raw/`, not committed).

| Scenario | Result |
|---|---|
| z_old_rule | `known` / `intel_m` gone; an enemy squad inside the old reach (objective edge + 400 m) but out of sight: South has 0 contacts, `threat_near` 0 **PASS** |
| **A** initial contact | squads 230 m apart behind a ridge (inside the old 400 m rule, 64/64 sight pairs blocked by terrain): 0 contacts for 25 s on both sides; when South walks into view North's contact appears 3.1-3.8 s after the first sighting (≥ report delay), enemy faction South, infantry, observed, conf 0.97, strength ~9 (true 8), position error 5-14 m; South reports North back; the contact is on the overlay (`contact_markers`) **PASS** |
| **B** lost contact | South walks 45 m back behind the ridge: the contact stays at the reported position (moved 0.0 m, `t_seen` unchanged, 40 m from the truth), conf 0.82 → 0.42 after 60 s, uncertainty 35 → 107 m, stale at 120 s (conf 0.22, ±179 m), dropped by 230 s **PASS** |
| **C** reacquisition | contact 110 s old (conf 0.29, ±146 m); South reappears: the **same** contact id is updated (observed, conf 0.96, error 14 m, one contact about South) **PASS** |
| **D** hearing | South and East shoot at each other 130 m from North behind a fold (0 sight pairs, 359-547 shots): North holds one HEARD contact, unidentified, kind unknown, uncertainty 112 m, position error 13-30 m, no seen contact **PASS** |
| **E** near / far | see §9 **PASS** |
| **F** save / load | see §8 **PASS** |
| **G** strategic response | 24 enemy soldiers (3 squads) visible to Verket's garrison: South's picture "about 21" (one contact, observed 96 %); decision: `threat at Verket: ~21 reported, 8 defenders → reinforce with 1 squads`; operation reason "about 21 enemy reported near Verket, 8 defenders"; the inspector lists it; after the enemy leaves, the estimate falls 21 → 9 in 130 s **PASS** |
| **K** stale report | the intruder is seen, then walks 600 m away out of sight; the contact goes stale; South's next decision sends a free squad to the **reported** position (0 m from it, 507 m from where the intruder is); the squad inspector states "investigate contact #… (seen, 29 % confidence, 113 s old)"; on arrival "nothing found", conf 0.04 **PASS** |
| **H** player authority | North's squad (contact available, enemy in view) ordered by the player: order Move kept with its target, no operation, no AI decision for the player's faction, 58 m carried out, soldiers still perceive the visible enemy (8 seeing); inspector says "the player's direct order" **PASS** |
| **I** three factions | North knows only South, East knows only South, South (between) knows what it perceived; every contact in its own table, ids unique, only enemy unit ids **PASS** |
| **J** performance | §11 **PASS** |

Regression (change-impact): `--sandbox-test --only persist,offensive,reinforce,war --minutes 20` **PASS**; `--only war --minutes 30` **PASS**:
South started 6 / completed 3 operations (before, WORLD-SANDBOX-01B: 7 / 5), East 2 / 1 (2 / 1), South Bridge captured at 21.0 min (20.2), Sentrum
attack still running at 30 min (captured at 29.5), largest attack 24 (24). No squad of two factions met in 30 minutes, so there were no contacts
and no old-rule reactions to compare; the difference in completed operations is not explained by intelligence and is within what the
unseeded AI timing varies by [LIMIT]. Not run (not affected): full suites, `--squad-test`, logistics tests (no code of theirs changed).

**`--combat-ai-test`** (INTEGRATION-04 item 10): diagnosed. The strict "meadow" no longer exists on the corrected terrain. Relaxing the search lets
the suite start, but its symmetric-fight and target-stability checks then fail with *no shots at all* identically on the untouched INTEGRATION-04
baseline (verified in that worktree, then reverted). The suite is a legacy-layout (no war) test, so it cannot exercise this milestone; the relaxed
search was **reverted** rather than leave misleading downstream failures. Roadmap: port its scenarios to the sandbox layout in SQUAD-01.

## 11. Performance [TEST j_perf]

A 64 v 64 open-field battle on top of the war's ~144 soldiers (128 fighters, 112 with bodies, RTS view, about 1 500 shots in 8 s of play):

| Measure | Value |
|---|---|
| frame time, battle | avg 9.5 ms, p99 19.1 ms, max 23.9 ms, **0 frames over 33 ms** (idle baseline 1.7 / 3.0 ms) |
| `CombatBrain` update (existing cost of the battle) | avg 3.8 ms, max 9.9 ms |
| report calls incl. group counting | 10.1 ms total over 840 frames = **12 µs per frame** (0.3 % of the brain cost) |
| reports | 672 filed, 535 applied, 8 contacts created, 527 merged, 0 dropped, 137 in flight at the end (3 s delay) |
| ageing sweep (1 Hz) | avg 32 µs, **max 0.9 ms** (flushing a batch of due reports) |

No all-pairs scanning (reports reuse CombatBrain's perception; group counting looks at ≤ 4 grid cells), no new line-of-sight checks,
no per-contact pathfinding, bounded tables (40 per faction, 600 pending, 12 ids per contact). No optimisation was needed. The old
`_update_intel` (a scan of every enemy against every own soldier's cells every 2 s) is gone.

## 12. Known limitations and dependencies

* **G9 strength estimate** is the number of enemy soldiers within 25 m of the sighted one (±20 % per observer, best of the last few
  seconds): a sighted group is assumed to be seen as a group; composition is not tracked.
* **G10** investigation is one squad walking to a point; no stand-off, no recon task, no vehicle (OPS-01).
* **G11** squads do not use contacts yet (flank / suppress targets belong to SQUAD-01); the 120 m "look there" broadcast remains.
* **G12** only combatants report; no scouts or sensors; unreported garrisons are still assumed (`value · 4`).
* **G13** vehicles and aircraft are not observable or targetable yet (`CombatBrain` grids soldiers only); the contact kind exists.
* Heard contacts have no faction (by design); several heard reports merge by proximity, so two separate fights 140 m apart can become one contact.
* No inspector in the RTS view; decision snapshots are not saved (the history restarts after a load, the picture does not).
* Two tests were changed after they flaked: A now waits up to 10 s for South's report of North; I no longer asserts which enemy South perceives
  first (a squad facing away legitimately misses things), only that North never learns of East, East never of North, and South knows something.
* Visual inspection covers the map overlay and the inspector in the running game (screenshots in `docs/ai_intel01/`); the 3D views show no
  intelligence by design. The **normal player map** screenshot (`i01_a3_player_view_no_dev_overlay.jpg`) is the player's view.

## 13. Recommended next milestone

**AI-SQUAD-01** (fire teams, suppression, FLANK, bounding, withdrawal): the contact picture, the FIRE contacts and `contacts_near` are in place and are
exactly what flank and suppress targets need; the inspector already shows squad reasons, so tactics will be debuggable from day one. Start by porting
the `--combat-ai-test` scenarios to the sandbox layout. Then AI-STRAT-01 (decision snapshots, `basis` flags and reasons exist), then BASE-AI-01 before
AI-OPS-01 (AI factions still own no depots or vehicles, see the roadmap).
