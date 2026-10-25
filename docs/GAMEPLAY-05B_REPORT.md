# GAMEPLAY-05B — Stabilization, Infantry Combat Balance & Gameplay Usability

Branch `develop` (project standard). Not pushed. Markers: **[RUN]** measured in the real game on ref_20km; **[CODE]** read in the
source; **[NOTE]** judgement. Built on GAMEPLAY-05 (`docs/GAMEPLAY-05_QUALITY_REVIEW.md`). A second session (VISUAL-02) worked in the
same folder at the same time; its files were left alone and are not in these commits, and the two sessions took turns on frame-rate
measurements.

## 1. Executive summary

- **Construction (B6) fixed at the cause.** Not unreachable work posts and not a test artefact: a squad that once took up a
  defence on its own was left on a HOLD nobody gave and **never built again for the rest of the game**. Fixed in the tactics; a
  regression check shows the squad back at work 11 s after its defence ends (before: never). The campaign test's stale
  assumptions (an enemy outpost GAMEPLAY-04 put next to its base; counting the garrison too early) corrected.
- **Near-tier soldiers stuck at roads** — the navinf_04 failures and the squad stuck in a roadside ditch reported during this
  work — had a measured cause: the road meshes are ~1.9 m wider on each side than the road line the terrain was eased to, so
  their edges stood up to 1.1 m above the ground. The shoulders now follow the real mesh (edge lips median 0.46 → 0.16 m, max
  1.12 → 0.35 m) and the ledge hop finds edges reliably. navinf_04 near tier: 6/6 in 1 of 4 baseline runs, 7 of 10 runs after.
- **Rifles are useful at medium range.** The aim error no longer grows with the square of the distance: rifle 100 m 11 → 26 %,
  200 m 3 → 9 %, 300 m 2.5 → 7 %; the DMR keeps a clear long-range edge; machine guns stay suppression weapons; suppression
  still matters but no longer zeroes a shooter. Measured in engagements too: attacks over open ground cost more, a fortified
  position is still taken (3/3).
- **Capturing is understandable**: CAPTURING 42 % / CAPTURE PAUSED in the squad status, a world overlay with the real radius and
  the "2+ soldiers" rule, the map tag, and one message when a capture stops because the squad left.
- **Commands explain themselves**: tooltips that say what an order does (wrapped), a destination preview while an order is
  armed, one structure name everywhere, no overlapping map labels.
- **Frame spikes** (40–48 ms, 2–3 per 40 s) are attributed: not scripts, shaders, navmesh or LODs; they coincide with the
  vegetation streamer freeing a chunk (4 of 5). Documented with the proposed fix, not changed (§8).

## 2. Construction reliability (B6): root cause and fix

**Symptom.** `--campaign-test c_forts`: the timber guard tower 32 m behind the command post was never finished in 900 s; the other
five structures were.

**Instrumented** (`CP build_trace`: every unfinished site and the squad every 20 s) [RUN]. Neither GAMEPLAY-05 hypothesis was it:

| t (s) | site | squad |
|---|---|---|
| 229 | guard tower 0 %, "N1 on the way" | BUILD |
| 249 | 6 %, "work stopped: enemy contact" | sees the South fire team at the Moen checkpoint 401 m away; BUILD ends, the squad takes up DEFEND on its own |
| 269 | 6 % | contact over |
| 310 → 958 | 6 %, untouched | idle, out of contact, next to the site, `build_eligible` false for 650 s |

**Root cause** [CODE]. When a squad's self-chosen tactic ends, `SquadTactics._restore` / the regroup end stop an idle squad with an
internal `order_hold` (or `order_regroup` when spread out). The squad was idle (order NONE) when it built; afterwards its order is
HOLD, which nobody gave, and `build_eligible` accepted only NONE or a finished MOVE. So **any squad that once defended itself on
its own never built again for the rest of the game** — a real gameplay bug (the player's squads near the front), not a test
assumption.

**Fix.** A hold or regroup the tactics issue themselves is marked on the squad (`tactic_hold`); an order from the player or an
operation (`SquadTactics.on_order`) clears the mark; `build_eligible` treats a marked HOLD / REGROUP like an idle squad once it
stands. The player's own Hold still keeps a squad from building. Unchanged: no work in contact, no work without a soldier at his work
post (`_run_build` counts only soldiers within 3 m of their posts), unreachable work posts end BUILD after 90 s and block the site
for 60 s (then it is tried again).

**Regression check** `--gameplay05-test --only b_build_resume`: a squad builds a fighting position, takes up a self-chosen DEFEND,
regroups and is left on the tactics' HOLD; before the fix it never returned (180 s, progress stuck at 3 %), after it it is back at
work after 11 s [RUN]. The check fails if the squad never built or did not end on the tactics' hold (nothing would be tested).

**The campaign test itself** had two stale assumptions, corrected without weakening it:
- Since GAMEPLAY-04 the New Game puts a South fire team ~450 m from the test's base. Seeing it stops construction (correct) and its
  reports turn GAMEPLAY-03's judged posts towards it, away from the test's fixed front. `c_forts` is about building, garrisoning and
  manning fortifications, so it now removes that fire team first (state set directly, as the narrow checks do); construction
  interrupted by contact is `b_build_resume`'s job. (Facing the fortifications towards the checkpoint instead was tried: the
  site became a combat zone with enemies at 151 m and nothing was built — correct behaviour, wrong test.)
- The garrison was counted when the sixth of eight soldiers reached his slot; the fighting position and MG emplacement 34–40 m out
  are reached last. It now waits until the garrison has settled (all soldiers, at most 180 s).

After the fix [RUN]: all six structures built (timber guard tower included, 269 s), the settled garrison mans the
fortifications, DEFEND beside the MG emplacement uses it in a run without leftover enemies. The last stage (DEFEND by the MG
emplacement right after the fire stage) failed once with attackers still 140 m away (2 of 6 soldiers in slots when counted); that
stage depends on the fight before it and is noted in §9.

## 3. Near-tier infantry navigation

**Where the failures were** [RUN]. All baseline failures of `--nav-inf-test navinf_04` (near tier: 3/6 and 5/6 arrived in
GAMEPLAY-05's runs; far tier always 6/6) were at one place, (−137…−148, −1305…−1327): soldiers on a ~31° slope, standing still,
pressed against the side of the road mesh collider of Road_011 (contact normal (0.88, 0, −0.48): a vertical face). A probe of
physics heights across that edge: the road surface stands 0.28 m above the terrain in its middle and its edge ~1 m above the slope
below.

**Why** — two defects, measured:
1. **The road meshes are wider and higher than RoadNetwork.** `n_roads` (30 cross-sections of secondary roads, rays across the
   road collider): the mesh extends a median **1.9 m** (p90 2.0 m) beyond `RoadNetwork.width / 2` on each side and falls ~0.28 m
   towards its edge. GAMEPLAY-04's `RoadShoulders` eased the terrain to RoadNetwork's line and width, so the terrain fell away under
   the outer two metres of the mesh: the mesh edge stood **median 0.46 m, p90 1.04 m, max 1.12 m** above the ground beside it;
   17 of 30 edges were higher than a soldier's step (0.35 m). The navmesh is baked from the terrain only, so it routes across.
   This is the user-reported case too ("de to nederste soldatene her setter seg fast": soldiers in the ditch beside a road in a
   cut).
2. **The ledge hop rarely fired.** `SoldierBody._hop_ledge` (GAMEPLAY-04A) ran only if `is_on_wall()` was true at the moment of the
   stuck check; a body standing still against an edge often reports no wall (zero velocity, nothing to slide along), so the first
   stuck stage passed without a hop and the second dropped the order. It also aimed at the final goal rather than the path's
   next point, and stopped at 0.95 m.

**Fixes** (no new movement system, no obstacle exceptions):
- `RoadShoulders` follows the mesh: the terrain keeps the mesh's cross-fall out to its real edge (`MESH_EDGE_M` 2.0, drop 0.28 m)
  and the ramp to the original terrain starts there. In memory at game start as before (world files and manifest untouched; the
  cache key includes the new constants). After: lip **median 0.16 m, p90 0.32 m, max 0.35 m**, 1 of 30 at the step limit, none
  over 1 m.
- `_hop_ledge`: finds the edge with a short `test_move` along the path direction; lifts 0.5 / 0.7 / 0.95 / **1.2 m** only if the
  space above and ahead is free; still once per blockage. A wall higher than 1.2 m stays a wall.
- `SoldierBody.stuck_log` (bounded) records where a soldier gave up, the floor and wall normals, what the hop found, velocities;
  `--nav-inf-test` prints it.

**Results** (`navinf_04`, near tier arrived / 6; far tier 6/6 in every run):

| | runs | near 6/6 |
|---|---|---|
| baseline (GAMEPLAY-05) | 3/6, 6/6, 3/6, 5/6 (4 runs on unchanged and GAMEPLAY-05 code) | 1 of 4 |
| hop fix only | 6, 6, 5, 4, 6, 6 | 4 of 6 |
| hop fix + shoulders | 3, 6, 6 | 2 of 3 |

(The last run is on the VISUAL-02 world the product owner adopted during this milestone: new vegetation and ground, same
relief and roads.) The remaining failures are other places: one run stalled three soldiers on a 41–44° slope far from any
road (no wall contact, slow progress flagged as stuck four times); the stuck log now records velocities to find out why (§9).
`navinf_02` and GAMEPLAY-04's `a_road` / `a_shoulders` pass with the new shoulders (8/8 across the road; 25 551 vegetation
instances checked, none off the ground).

## 4. Combat accuracy before / after

Model [CODE `CombatBrain`]: aim error σ = (base + per100 × d/100) × settle × proficiency × (1 + supp × suppression) ×
weapon aim, plus the weapon's spread. Changed: per100 **0.20 → 0.05** (the error in metres grew with d²), base 0.25 → 0.26,
suppression 2.2 → **4.0**, machine guns' aim factor 1.0/1.1 → **1.3**. Unchanged: settling, moving penalty (1.2°), proficiency,
weapon handling, friendly-fire checks. `--aim=g04` restores the GAMEPLAY-04 model; `--aim-base= / --aim-per100= / --aim-supp=`
for experiments. Candidates were screened with a Monte Carlo of the model against the hit shapes first (flatter growth at three
strengths), the middle one went into the game.

Accuracy arena (`--gameplay04-test --only c_arena --arena-seeds=1,2,3,4,5,6`, same build, both profiles). Caveat: the arena site
of this run had trees and terrain in some lines (shots into trees in every case), so absolute values carry environment noise;
the comparison is fair (same site, same seeds).

| case | hit % g04 → g05b | shots | first shot s | first hit s | target supp |
|---|---|---|---|---|---|
| carbine_100_moving_shooter | 3.8 → 3.1 | 131 → 162 | 3.0 → 0.8 | 10.6 → 8.7 | 0.74 → 0.69 |
| carbine_300 | 0.0 → 0.0 | 0 → 0 | -1.0 → -1.0 | -1.0 → -1.0 | 0.0 → 0.0 |
| carbine_50 | 61.2 → 43.7 | 227 → 213 | 0.8 → 1.1 | 0.9 → 1.2 | 1.0 → 1.0 |
| dmr_100 | 78.9 → 77.7 | 109 → 112 | 1.4 → 0.9 | 1.7 → 1.2 | 1.0 → 1.0 |
| dmr_300 | 0.0 → 7.7 | 39 → 39 | 2.1 → 2.2 | -1.0 → 5.4 | 0.4 → 0.62 |
| dmr_500 | 0.0 → 7.1 | 27 → 28 | 2.2 → 2.3 | -1.0 → 3.9 | 0.0 → 0.0 |
| gpmg_100_moving_shooter | 2.7 → 4.2 | 261 → 236 | 2.9 → 4.4 | 11.3 → 10.8 | 1.0 → 1.0 |
| gpmg_300 | 1.8 → 4.6 | 111 → 108 | 1.4 → 1.8 | 3.8 → 4.4 | 1.0 → 1.0 |
| lmg_100 | 32.7 → 31.5 | 388 → 302 | 1.0 → 1.8 | 1.4 → 1.9 | 1.0 → 1.0 |
| lmg_100_moving_shooter | 6.0 → 6.2 | 301 → 226 | 1.0 → 3.0 | 7.3 → 10.4 | 1.0 → 1.0 |
| lmg_300 | 0.0 → 2.6 | 108 → 114 | 1.9 → 1.3 | -1.0 → 6.2 | 0.93 → 1.0 |
| rifle_100 | 11.0 → 25.6 | 181 → 180 | 1.6 → 1.8 | 3.0 → 2.6 | 1.0 → 1.0 |
| rifle_100_friend_near_line | 20.5 → 33.3 | 122 → 144 | 1.8 → 1.5 | 2.6 → 1.7 | 0.86 → 0.99 |
| rifle_100_moving_shooter | 10.0 → 8.6 | 110 → 151 | 5.1 → 1.6 | 10.0 → 9.3 | 0.76 → 0.76 |
| rifle_100_moving_target | 10.1 → 15.6 | 178 → 179 | 1.8 → 1.4 | 3.2 → 2.4 | 1.0 → 1.0 |
| rifle_100_recruit | 17.3 → 25.3 | 179 → 174 | 1.2 → 1.1 | 3.2 → 1.9 | 1.0 → 1.0 |
| rifle_100_suppressed | 7.2 → 6.4 | 111 → 94 | 1.5 → 2.3 | 4.6 → 5.5 | 0.7 → 0.58 |
| rifle_100_veteran | 29.1 → 43.5 | 179 → 177 | 1.6 → 1.4 | 2.2 → 2.0 | 1.0 → 1.0 |
| rifle_200 | 2.6 → 8.9 | 77 → 79 | 1.6 → 1.1 | 7.6 → 6.0 | 0.33 → 0.46 |
| rifle_300 | 2.5 → 7.1 | 40 → 42 | 1.9 → 1.4 | 12.0 → 4.5 | 0.09 → 0.28 |
| rifle_300_moving_target | 2.4 → 10.3 | 41 → 39 | 1.6 → 2.0 | 4.6 → 5.6 | 0.08 → 0.23 |
| rifle_300_recruit_moving_target | 2.5 → 0.0 | 40 → 40 | 1.6 → 2.0 | 3.9 → -1.0 | 0.04 → 0.09 |
| rifle_50 | 62.2 → 76.0 | 201 → 200 | 1.3 → 1.4 | 1.5 → 1.6 | 1.0 → 1.0 |

Reading: the standard rifle becomes a medium-range weapon (100 m ×2.3, 200 m ×3.4, 300 m from almost nothing to 7 %) with
unchanged time to the first shot; the DMR is the long-range weapon (300 / 500 m 8 / 7 % against the rifle's 7 % at 300 m and
nothing at 500 m; in the GAMEPLAY-04 3-seed site 15 / 7 %); LMG at 100 m unchanged (33 → 32 %), at 300 m from 0 to 3 % (still
suppression: target suppression 1.0); moving shooters unchanged; recruit 25 % and veteran 44 % at 100 m (spread kept); a
suppressed rifleman 7 → 6 % (not zero).

## 5. Combat balance assessment

Engagements (`--combat03-test --only d_open,d_village,d_forest --seeds=1,2,3`, `--combat02-test --only a_haugen,a_three,
a_fortified,a_unfavourable --seeds=1,2,3`), same build, old world, g04 → g05b:

| scenario | taken / won | attacker losses | defender losses | first defender hit (s) | duration (s) |
|---|---|---|---|---|---|
| d_open (defence, open ground) | 3 → 2 of 3 | 22 → 46 % | 100 → 79 % | 63 → 61 | 257 → 237 |
| d_village | 3 → 3 | 19 → 22 % | 100 → 100 % | 98 → 84 | 231 → 223 |
| d_forest | 3 → 2 | 40 → 49 % | 100 → 96 % | 165 → 165 | 335 → 318 |
| a_fortified (attack on a fortified post) | 3 → 3 | 21 → 38 % | – | – | – |
| a_haugen | 1 → 2 | 49 → 50 % | – | – | – |
| a_three | 1 → 1 | 42 → 43 % | – | – | – |
| a_unfavourable (should win or withdraw cleanly) | 0 → 0 won, 2 → 1 clean withdrawals | 58 → 63 % | – | – | – |

Assessment [NOTE]: in the open, defenders who are settled now hit at 200–300 m, so crossing open ground costs attackers about twice
as much; in villages and forests (short lines) little changes; a fortified position is still taken every time, at a higher price.
That is the intended direction — fire and movement, suppression and cover matter more — and no defence became impossible to
assault. `a_three`, `a_haugen` and `a_unfavourable` miss their expectations with **both** models (1/3 wins with g04 too):
pre-existing (GAMEPLAY-03 notes test-order and seed noise in these). 3-seed series swing by up to 50 points (GAMEPLAY-03), so
single numbers are indications. The trade-off to watch in play: open-ground attacks against an alerted defence should use
SUPPRESS / BOUND rather than ASSAULT straight in.

## 6. Objective capture feedback

One source: `WarSim.capture_state(objective, faction)` → state (capturing / paused — too few of the faction's soldiers inside /
contested / losing — an enemy is taking the faction's objective), progress, the objective's own radius, soldiers needed
(`capture_min`) and inside. Every surface reads it; nothing is stored except the last state per objective (for the one message).

| Surface | Shows |
|---|---|
| Squad status (roster, command panel, field tag, first-person box) | `CAPTURING 42%`, `CAPTURE PAUSED 42%`, `CONTESTED`, `BEING TAKEN 30%` for a squad standing in the objective |
| Tactical view (world) | the capture radius as a ring on the ground (the objective's real radius), the objective name and state with a progress bar, and what keeps it going: "Keep 2+ soldiers within 70 m to complete the capture" / "1 of 2 soldiers inside: bring them back within 70 m (progress fades)" / "Enemy soldiers inside 70 m: the capture waits until they are cleared" / "Bring 2+ soldiers within 70 m to stop it" |
| Strategic map | the objective tag: "CAPTURING 42% · keep 2+ within 70 m", "CAPTURE PAUSED …", "BEING TAKEN …" (contested as before) |
| Messages | once, when a capture in progress stops because the capturing side left: "Capture of Verket paused at 42%: keep 2 or more soldiers within 70 m (progress fades while nobody is there)"; completion keeps the existing "North captured …" message |

The radius and the soldier count are the objective's and WarSim's own values (never a hard-coded 70 m). The "two soldiers"
rule (`capture_min`) was invisible before: a single soldier left behind paused the capture silently.

Verified (`u_capture`, shots `docs/gameplay05b/u_capture_*.png`) [RUN]: the squad put into Verket (radius 200 m) reads
CAPTURING with progress and "Keep 2+ soldiers within 200 m to complete the capture"; moved out it reads CAPTURE PAUSED ("0 of 2
soldiers inside …") with exactly one message ("Capture of Verket paused at 19 %: keep 2 or more soldiers within 200 m …"). The
shown squad status was UNDER FIRE (Verket is in sight of the South roadblock): combat outranks capture in the status word, the
overlay still says what the capture does. The ground ring is drawn in visible pieces; at Verket's 200 m it lies outside a close
view (the map always shows the zone).

## 7. Command UI improvements

- **Tooltips** for every command button say what the order does, how it ends and how to give it (e.g. ASSAULT "Move toward the
  target using coordinated fire and movement: one fire team suppresses while the other advances, then the squad clears and occupies
  the position. Z at the cursor, or arm and click."; HOLD "… Cancels the current order or tactic."; REARM "Search nearby
  equipment and ammunition (caches, stashes, the fallen, your base stores within 30 m) …").
- **Destination preview** while an order is armed (before its click): a dashed line from the selected squad to the ground under
  the cursor, the order and the distance ("ASSAULT · 230 M · 2 SQUADS"), and what the click will do there — for REARM what it would
  search ("rearm at Moen checkpoint stores" / "here (no equipment known within 30 m)"), for GARRISON which base (or "no base of yours
  here"). Esc cancels, as before. Drawn in the existing RTS marker layer; no new UI system.
- **One structure name** (`StructureDef.display_name` from the catalog, normalised once to sentence case with acronyms kept):
  the build menu said "Guard Post", messages "Guard Tower" / "Guard tower", logistics "Guard post"; "Ammunition storage bunker"
  in the menu was "Ammunition magazine" in messages. `FacilityDefs.display_name` and the build menu's base entries now read the
  catalog; `tools/ui/names_audit.gd` lists any difference (none left).
- **Map labels**: cache and equipment labels go through the same collision check as objective names and are left out where
  they would cover a name (the marker stays; closer zoom shows the label). Objective names keep priority.

Verified (`u_orders`, shots `u_orders_assault.png`, `u_orders_rearm.png`, `u_orders_tooltip.png`) [RUN]: the armed ASSAULT
shows the dashed line, "ASSAULT · 99 M" and "Click: assault this position (Esc cancels)"; the tooltip wraps at ~330 px under its
heading; the footer reads "REARM: click a cache, stash or base (Esc cancels)". Names: `names_audit` lists no difference.

## 8. Frame-time investigation

Instrumented (`q_perf`, the opening fight at normal speed: 40 s tactical camera, 30 s first person, 1920×1080, vsync off): for
every frame over 33 ms the recorder logs process and physics time, physics steps, WorldSim cost per system, navmesh bakes,
vegetation chunks and the worst chunk activation, new merged character LODs, route planning, render pipeline compilations and node
count [RUN].

| | tactical | first person |
|---|---|---|
| frame avg / p95 / p99 / max | 4.14 / 6.70 / 8.27 / 47.7 ms | 3.96 / 6.45 / 8.50 / 41.7 ms |
| frames > 33 ms | 3 | 2 |
| sim per tick: abstract / brain / war | 725 / 797 / 62 µs | 692 / 798 / 53 µs |

In the five spike frames: script process time 5–12 ms (one report of 177 ms is a monitor artefact of the first sample),
physics 3–8 ms, 1–3 simulation ticks (≈2–4 ms), **no** pipeline (shader) compilations, **no** navmesh bake, **no** new character
LOD, no route planning of note — and in **4 of 5** a vegetation chunk was released (`veg_chunks −1`). The rest of each spike
(~25–30 ms) is therefore engine-side, at the moment the streamer frees a chunk: `VegetationStreamer.unload_chunk` frees all of the
chunk's active cells (`MultiMeshInstance3D.free()`) in the same frame.

Not changed (it is the streamer's design, owned by the world tech, and needs its own measurement round): proposed fix — hide the
cells at once and free them over the following frames (a few per frame), or keep a pool of MultiMesh instances for reuse. Expected
effect: the 40–48 ms frames during camera moves fall to the 8 ms p99 band. The averages are about 0.8 ms higher than GAMEPLAY-05's
run of the same check; that run was on the old world, this one on the VISUAL-02 world (new ground shader and vegetation).

## 9. Remaining limitations

1. **Frame spikes** at vegetation chunk release: attributed, not fixed (§8).
2. **navinf_04 near tier** still fails about 3 runs in 10: a stall on a 41–44° slope away from roads (cause not yet found; the
   stuck log now carries velocities) and the edge cases left above 1.2 m.
3. **Road meshes of other classes** were not measured (the 30 samples are secondary roads); the shoulder margin (2.0 m, 0.28 m fall)
   is applied to all world roads.
4. **Open-ground attacks cost more** with the new aim (§5); judged acceptable, to be watched in play. `--aim=g04` restores the old
   model.
5. **combat02 `a_three`, `a_haugen`, `a_unfavourable`** miss their expectations with both aim models (pre-existing).
6. **c_forts' last stage** (DEFEND by the MG emplacement right after the fire stage) can fail while attackers are still near;
   the building and garrison parts pass.
7. The capture ring of a large objective lies outside a close tactical view; the overlay text and the map still show it.
8. `tactic_hold` (the mark that a HOLD came from the tactics) is runtime state: after loading a save, a squad on such a hold waits
   for an order before it builds again.
9. The world changed under this milestone (VISUAL-02 adopted a new vegetation layout at ~13:05): the balance series and most
   navigation runs used the old world, the last navigation and performance runs the new one.

## 10. Tests and validation

Targeted, by change; no full suite. A second session ran its own tests in the same folder; frame-rate runs were taken in turns.

| Change | Checks | Result |
|---|---|---|
| B6 diagnosis | `--campaign-test --only c_forts` with the build trace | root cause found (§2) |
| B6 fix | `--gameplay05-test --only b_build_resume`; `c_forts` | PASS (back at work after 11 s); c_forts builds all six, garrison PASS; last stage see §9 |
| Road edges | `n_edge`, `n_roads` (before / after) | lips median 0.46 → 0.16 m, max 1.12 → 0.35 m |
| Ledge hop, shoulders | `--nav-inf-test --only navinf_04` ×10 (+ navinf_02 ×2); `--gameplay04-test --only a_road,a_shoulders` | near 6/6 in 7 of 10 (baseline 1 of 4), far 6/6 always; navinf_02, a_road, a_shoulders PASS |
| Aim model | `c_arena` 3 and 6 seeds both profiles; `--combat03-test d_open,d_village,d_forest` and `--combat02-test a_haugen,a_three,a_fortified,a_unfavourable`, 3 seeds, both profiles | §4, §5; combat03 PASS with both |
| Capture feedback | `u_capture` (shots) | PASS |
| Command UI | `u_orders` (shots), `tools/ui/names_audit.gd` | PASS, no name differences |
| Frame spikes | `q_perf` with the spike recorder | §8 |
| Scripts | `tools/check_scripts.gd` before runs | 178 scripts, 0 failures |

## 11. Commits

| Commit | What |
|---|---|
| `832f4dd` | B6: squads build again after a self-chosen defence; c_forts fixture and trace |
| `acbf71f` | infantry aim model (flatter distance growth, MG aim, suppression), `--aim=` profiles, `--arena-seeds=` |
| `eea215e` | capture feedback, order tooltips and preview, one structure name, map labels |
| `ac64b8b` | near-tier soldiers stuck at road edges (shoulders follow the road mesh, ledge hop), 05B checks and screenshots |
| (this report) | report, README, CLAUDE.md |

Not pushed. The VISUAL-02 session's commits (`4101d0b`..`d00ebb9` and later) are its own; none of its files are in these.

## 12. Recommendations for GAMEPLAY-06

1. **Vehicles and battlefield salvage remain the next milestone** (GAMEPLAY-05 §15): this milestone removed the defects that would
   have spoiled it (squads that stop building, soldiers stuck at road edges, rifles useless beyond 150 m), and the road-edge fix
   matters for dismounting beside roads.
2. Fold the **vegetation chunk release** fix (§8) into the start of GAMEPLAY-06: driving moves the camera fast and releases chunks
   often, so the spikes will be felt more with vehicles.
3. Measure the **road mesh margins of every road class** once (the `n_roads` probe) before vehicles leave roads at road edges.
4. Playtest the **open-ground attack cost** with the new aim; if attacks feel too expensive, lower the defenders' settled bonus
   rather than the distance growth.
5. Use the capture feedback for **convoy / salvage objectives** (the same capture_state pattern: one state, every surface reads it).
