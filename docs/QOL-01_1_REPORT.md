# QOL-01.1 — Movement paces and tactical movement refinement

Branch `develop`, on top of the QOL-01 commits. The player chooses the behaviour and the objective; the AI chooses WALK, RUN or SPRINT from the situation. No new movement system: the record's pace (`WorldSim.pace_of`) drives both tiers, and the character's existing stride-matched locomotion shows it.

## 1. Final movement speeds

| Pace | Speed | Clip |
|---|---|---|
| WALK | 1.8 m/s | the captured brisk walk (1.83 m/s, played at its own stride) |
| RUN | 4.5 m/s | the captured run (4.45 m/s); the speed every soldier had before |
| SPRINT | 6.2 m/s | between the run (4.45) and sprint (7.5) clips |

- **Always on:** the paces need no flag; `--uniform-pace` restores 4.5 m/s for every soldier, for comparison.
- **Why WALK is 1.8 and not 2.0 m/s:** at 2.0 the stand blend space mixes the walk and jog clips (a half-jog). 1.8 m/s is the brisk-walk clip itself.
- **Speeds scale with `UnitState.speed`:** a soldier of `speed` 4.5 gets the table above; slower soldiers scale down.
- **Old paces in saves:** WALK / BRISK became WALK, JOG / RUN became RUN (`SquadState` "pace3" marker).
- **Explicit player pace:** Ctrl+right click = SPRINT, Alt+right click = WALK, kept for the whole move. A cover dash still sprints.
- **Avoidance cap raised:** the body's avoidance agent capped speeds at 4.5 (`nav.max_speed = walk_speed`), which made sprint 4.5. It now allows the sprint speed; the pace still decides the desired speed.
- **Posture caps:** `Posture.MAX_SPEED` limits crouched movement to 1.6 m/s (the crouch-walk clip striding ~1.6x) and prone to 0.81 m/s (the crawl clip), whatever the pace. Measured on sprint orders: crouch 1.6, prone 0.81.

## 2. Behaviour-aware pace selection (`WorldSim.pace_of`)

The pace comes from what the records say, not from one speed per mode. "Open ground" is the strategic grid's forest cover (`StrategicRoutes.cover_at` < 0.25). A choice is held for 3 s per soldier so a soldier at a wood's edge does not change gait every few steps.

| Situation | Pace |
|---|---|
| cover dash (reaction) | SPRINT |
| player's own pace for the move | that pace |
| assault / flank / bound / withdraw leg | SPRINT when fired on, within 300 m of the believed threat or on open ground; else RUN |
| moving to posts (defend, suppress, reposition, regroup, build) | RUN; SPRINT when fired on |
| operation squads | RUN (SPRINT when fired on) |
| fired on while moving | SPRINT |
| SAFE | WALK on short direct moves (< 120 m), RUN on longer ones; RUN when a threat is believed within 300 m |
| AWARE | RUN; WALK when advancing towards a believed threat 80-250 m ahead |
| COMBAT | RUN; within 300 m of a threat: SPRINT on open ground, WALK in cover when heading towards it |
| STEALTH | RUN far from threats; within 350 m: WALK in cover, SPRINT across open ground |
| garrison | WALK |

STEALTH crouches on the move only at WALK within 150 m of the believed threat, and never while sprinting or dashing. This removes the permanent crouch-walk of QOL-01. A SAFE squad that sees an enemy acts as AWARE (QOL-01), so it walks when it closes on that enemy.

Measured (`m_modes`, 6-soldier squads marching 300 m, share of moving samples):

| | WALK / RUN / SPRINT, no enemy (quiet spot 13.7 km from any enemy) | WALK / RUN / SPRINT, enemy reported 200-300 m off (open site) |
|---|---|---|
| SAFE | 0 / 1.0 / 0 | 0.77 / 0.23 / 0 (acts AWARE, closing on the contact) |
| AWARE | 0 / 1.0 / 0 | 0 / 1.0 / 0 |
| COMBAT | 0 / 1.0 / 0 | 0 / 0.07 / 0.93 (open ground near a threat) |
| STEALTH | 0 / 1.0 / 0 | 0 / 0 / 1.0 (open ground) |

- **Pace changes:** 2.3 per soldier per minute with nothing known, 3.3 with an enemy known.
- **Formation spread:** at most 5.5 m (9-15 m with an enemy known, STEALTH widest).
- **A test pitfall found on the way:** the "no enemy" march at the open test site met a live AI garrison about 250 m away. The checks now find a quiet spot automatically.

## 3. Animation verification (`m_paces`)

- **Speeds:** a single soldier on the walk spot, through the real body and controller. Measured median body speed: walk 1.80, run 4.50, sprint 6.20 m/s against the table.
- **Playback:** the character plays its locomotion at stride-matched rate (cycles = speed / interpolated stride), so the feet track the ground at every pace. The recordings (`docs/qol01_1/rec/`, contact sheets `sheet_pace_walk / run / sprint.png`) show a walk at walk, a run and a sprint with full leg drive; no running in place.
- **Foot slip numbers:** the in-engine numbers stay unusable, as the VISUAL-03 report says (process-frame sampling of bones that move in physics frames). Contact was judged from the frames.
- **Crouch and prone:** capped at their clips (above). Crouched movement can no longer reach 2.5 m/s.

## 4. Short tactical movement (`s_short`)

**Finding: the problem is real.** A COMBAT (or AWARE / STEALTH) squad told to move 70 m, with a reported enemy 200 m off and a concrete barrier beside its destination, ends its move in the open: 1 of 6 soldiers protected (STEALTH 0). Yet every soldier had protecting cover within 10 m. Short moves walk straight to formation slots; nothing at squad level looks for cover at the end of a move. Only a defence (DEFEND, `_judged_posts`) or a cover reaction does.

**Correction tried and taken out again:** snap each slot to the best protected `CombatBrain.cover_spots` spot within 10 m. It planned correctly (6 of 6 slots on protected spots), but the soldiers arrive within the ordinary 1.0-1.3 m tolerance. Next to a trunk or rock, a metre off is out of its shadow, so it still ended at 0-1 protected. With a precise-arrival flag the soldiers still ended about 1 m off. No measurable improvement, so per the brief nothing was shipped.

**Follow-up:** this belongs to WORLD-COVER-01: cover spots at the end of a move, arrival precision for cover posts, occupancy.

The STEALTH run also left one soldier stuck 6.8 m short of his slot beside the barrier ("no progress after an unstick attempt"). That is existing navigation behaviour at a structure.

## 5. Combat interruptions (`i_multi`, QOL-01 `i_interrupt`)

**Bug found and fixed:** after a halt, the interruption count and its 40 s cooldown were reset when the resumed move's route came back from RouteService (`follow_route` called `on_order` again). So the 3-halt limit never held on long moves. Routes of an order already given no longer reset the order (`follow_route(..., new_order := false)`).

| Run | Result |
|---|---|
| march, 650 m past three enemy groups | halted once (the limit and cooldown now hold), resumed, arrived 8 m from the goal in 248 s simulated, fired back |
| replacement order while halted | takes over at once; the new goal is the move goal |
| HOLD while halted | the hold stands; no resume (QOL-01 `i_interrupt`) |

**After the limit:** the squad presses on, but its soldiers keep returning fire and dashing for cover on their own (individual CombatBrain reactions are never switched off). New in QOL-01.1: a squad that is pinned down (half or more pinned) still halts after the limit, at most once per cooldown, because it cannot march anyway.

**Limit and cooldown kept:** 3 halts, 40 s. With the count working they behaved sensibly in the runs above.

## 6. STEALTH fire discipline (`f_stealth`)

| Case | Result |
|---|---|
| enemy 40 m away holding its fire | engaged after 1.0 s (inside the 50 m limit) |
| enemy firing from 140 m | the squad is compromised (acts COMBAT) and answers after 1.7 s |
| player's SUPPRESS order at a reported enemy 150 m away, squad not found | accepted, first shot after 0.3 s |

**Change:** a fight the player ordered (assault, suppress, flank, defend) now outranks the mode; before, the 50 m rule could have silenced a player's suppression. A soldier who is hit fires back at any range (unchanged).

## 7. Test results

| Run | Result |
|---|---|
| `--qol011-test --shots` (q_spike, m_paces, m_modes, s_short, i_multi, f_stealth, c_views) | PASS |
| `--qol01-test --only b_modes,p_posture,i_interrupt` | PASS. p_posture's STEALTH-moving check now expects crouching only at WALK and upright sprinting across the open site. |
| `--ai-squad-test --only d_assault,f_withdraw` | PASS (assault and withdrawal under the new paces) |

## 8. Performance

- **Profile grids:** built at load (`StrategicRoutes.prebuild_profiles`, 52-53 ms each, about 160 ms added to the loading).
- **First COMBAT / STEALTH order after load:** frames 16.6-16.7 ms median, worst frame 17.6 / 20.7 ms (vsync 60 Hz). Before, the first order of each mode paid its 53 ms grid build in one frame.
- **`pace_of`:** a few comparisons and one grid lookup per moving soldier per tick, plus a hold table. No measurable change in the tactics / brain costs measured in QOL-01 `q_perf`.

## 9. Remaining limitations

- **Short moves:** they end in the open even when cover is close (§4).
- **Pace hold:** a pace choice lasts 3 s, so a soldier reaching open ground starts sprinting within that time (fire taken overrides the hold at once).
- **Open-ground resolution:** "open ground" is judged per 50 m grid cell of forest cover; a lone rock or a ditch does not count.
- **Animation transitions:** walk ↔ sprint at a wood's edge rely on the locomotion blend (about 0.3 s). Measured pace changes stay at about 2-3 per soldier per minute.
- **AI factions:** they use the same pace rules (operations RUN, sprint under fire, garrisons walk), so their marches and assaults are a little faster under fire than before QOL-01.1.
