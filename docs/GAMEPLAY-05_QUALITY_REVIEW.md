# GAMEPLAY-05 — Quality Review, Bug Fixing, Visual Polish & Roadmap

Branch `develop` (project standard). Not pushed. Markers: **[RUN]** measured in the real game on ref_20km; **[CODE]** read in
the source; **[NOTE]** judgement. Screenshots 1920×1080 in `docs/gameplay05/` (`before/` = the GAMEPLAY-04 build played
through again at the start of this review).

## 1. Executive summary

The game was played through from the start screen (the GAMEPLAY-04 first-hour playthrough, 20 steps, all PASS, 24 game
minutes) and the systems the player touches were read. The review found real defects in what the player sees rather than
in the simulation underneath:

- **Every squad showed fewer soldiers than it had.** The roster, the command panel and the first-person squad box
  subtracted the fallen from the members although the dead already leave the member list: a squad with 5 soldiers alive
  read **"1/5"**, a full replenished squad "7/8". Fixed in one helper used by all three.
- **The "BLOCKED" garrison** (GAMEPLAY-04 known issue) has a cause: the squad's member recovery re-issued a stuck
  soldier's walk with an order that wipes his defence post; when its retry budget ran out the soldier had no post left,
  nothing ever sent him again and the whole garrison read BLOCKED for the rest of the game. Reproduced with a test, fixed
  in two places (the recovery keeps the post; a defender who cannot reach his post holds where he got to).
- **The EQUIP screen threw an error on every refresh** (48 in one playthrough) and missed a soldier's death in its
  rebuild check.
- **Readability**: fallen soldiers' equipment no longer floods the tactical view (one summary per cluster, contents on
  mouse-over, unregistered weapon types in amber) and appears on the strategic map; captured bases no longer keep the
  enemy's name ("South base 2" held by North → "North base 2"); messages name facilities by base ("Barracks, North base 1")
  instead of structure ids ("Barracks #48"); REARM says *why* it took nothing; locked development cards show their whole
  requirement on hover; EQUIP's Apply buttons are live only when a choice would change something.
- **Log hygiene**: the navmesh bake no longer emits three engine warnings (with backtraces) per bake, which buried real
  errors in every log.
- **Two rendering defects fixed**: soldiers about 12 m from the camera drew no mesh at all (two of eight in a squad close-up:
  the character LODs left a gap at the switch), and every distant tree had black lines across its canopy (the impostors'
  horizontal top cards seen edge-on).
- **Look**: SSAO for ground contact, a little less saturation, distance haze, a softer sky and muted meadow / field tints;
  the tactical view no longer reads as flat lime-and-ochre paint (§10). +0.15–0.65 ms per frame.
- **Rifle accuracy at 200–300 m** was investigated, not buffed: the low hit rate follows from the aim-error formula
  itself (§7.1); changing it is a balance decision with a concrete proposal.

The review's recommendation for the next milestone is **GAMEPLAY-06 "Motorised logistics and battlefield salvage"** (§15):
half of the first hour is walking, the player has no transport, and the equipment loop (find → carry → register → issue)
is capped by what one squad can carry on foot.

## 2. Current game quality assessment

| Area | State | Notes |
|---|---|---|
| Start / New Game | Good | Briefing and tracker clear; first action at 0:07, first shot at 0:24 [RUN] |
| Squad control (RTS) | Good, with friction | Clear command bar with keys; status words were wrong (strength, BLOCKED) — fixed |
| First person | Good | Same weapons and rules; HUD readable |
| Tactical map | Good | Objectives, caches, operations; equipment was missing — added |
| Combat | Solid | Fights decided in 20–60 s at 100–150 m; long range is the DMR's job (§7) |
| Construction | Good | Sites, builders, groundwork on slopes; one placement in the campaign test never finishes (§3, B6) |
| Development | Good | 14 projects; cards trimmed their requirement — tooltip added |
| Equipment / REARM | Works, cluttered | Records sound (save/load exact); markers and messages improved |
| Opportunities | Works | Generated from the world; rewards modest |
| Save / load | Good | Progression snapshot identical before/after F5/F9 [RUN] |
| Visuals | Mixed | Characters, weapons and vegetation good up close; terrain from above reads as flat saturated paint; houses and fences are untextured blocks (§9) |
| Performance | Good | §12 |

## 3. Bugs discovered

| # | Bug | Where | Found by | Status |
|---|---|---|---|---|
| B1 | Squad strength double-counts casualties ("1/5" for 5 alive) | `squad_panel.gd`, `tactical_panel.gd`, `fps_hud.gd` | playthrough screenshot g20 [RUN] | Fixed |
| B2 | Member recovery wipes a tactic's post; the soldier stays BLOCKED with no post, the garrison reads BLOCKED for good | `SquadControl._recover_member_if_needed`, `SquadTactics._tend_forts` | test `u_post_block` (reproduced: 81 s BLOCKED and never recovering) [RUN] | Fixed |
| B3 | EQUIP rebuild signature formats a bool with `%d`: an engine error per refresh, a death did not trigger a rebuild | `equipment_panel.gd:121` | playthrough log (48 errors) [RUN] | Fixed |
| B4 | A captured base keeps a generated enemy name | `BaseSim.capture_base` | GAMEPLAY-04 §12 + playthrough ("Defend South base 2") | Fixed |
| B5 | Navmesh agent sizes not whole voxels: 3 engine warnings + backtrace per bake | `AreaNavigation._new_navmesh` | every log [RUN] | Fixed (same bake) |
| B6 | Campaign check `c_forts`: the timber guard tower placed behind the command post is never finished in 900 s | BUILD on that site | `--campaign-test --only c_forts` [RUN] | Pre-existing, not diagnosed (§3.1) |
| B7 | "Take Verket roadblock" stayed open after the fight in the playthrough | test script | p_state on the save [RUN] | Not a bug: the test moved the squad off at 12 % capture |

### 3.1 B6 (c_forts guard tower)

Reproduced twice with the review's code and once with the squad changes of this review reverted (`SquadControl` from
`2f5b2ee`, `_unblock_post` disabled): the same failure each time, so it predates GAMEPLAY-05. The site is the timber
guard tower the test places 32 m behind the command post; the squad builds the other five structures. Candidates, not yet
separated: (a) its work posts are unreachable, BUILD ends "could not reach the site" after 90 s and the site is blocked for
60 s, again and again; (b) idle-squad auto-building is suspended in contact (`SquadTactics._auto_build` needs
`not a.in_contact`), and since GAMEPLAY-04 the New Game scenario this test uses puts a South fire team 450 m from the
test's base. Next step: print the site's `work_record().why` and the squad's tactic log at the end of `c_forts`; if (b), move
the test's base or let the test order the builders explicitly (the campaign tests already do that for garrisons).

## 4. Bugs fixed (details)

**B1 strength.** `WorldState.mark_fallen` removes a dead soldier from `SquadState.members` and lists him in `fallen`; the UI
computed `members − fallen`. Now `SquadPanel.strength(sq)` = (members, members + fallen capped at a full squad) feeds the roster,
the command panel and the first-person box (`u_strength`: 3 of 8 killed reads 5/8).

**B2 garrison BLOCKED.** `SquadControl` re-issues the walk of a stalled member (`member_replans` = 1) with
`WorldState.issue_move`, which ends the soldier's post (`post_pos = INF`) — correct for a player order, wrong for the same
walk again. After the budget the soldier was BLOCKED with no post: `SquadTactics` only re-sends soldiers with a post, and only
to fortification slots. Two changes: the recovery keeps `post_pos` / `fort_slot` (as the tactics' own re-sends already do), and a
defending soldier (DEFEND / REPOSITION; BUILD and attacks keep their own handling) whose walk to his post ends BLOCKED is sent
again twice, 8 s apart, then holds where he got to (`SquadTactics._unblock_post`, counter `posts_given_up`, a line in the squad
log). `u_post_block` puts one soldier's post inside a command post: BLOCKED for 16 s, then "DEFEND · HOLDING" (before: BLOCKED
until the end of the run).

**B3** `int(u.alive)`. **B4** a name "<old owner> base n" becomes the new owner's first free "base n"; the capture events name
both; new bases use the same free-number rule (no duplicate names after captures). **B5** radius/height rounded up and climb
rounded down to whole voxels — what Recast bakes anyway (0.5 → 0.75 m at 0.75 m cells, 1.8 → 2.0, 0.6 → 0.5).

## 5. Quality-of-life improvements implemented

| Problem shown by the review | Change |
|---|---|
| After a fight, 5–10 overlapping "FALLEN SOLDIERS' EQUIPMENT · 3 WEAPONS · 22 KG AMMO" labels covered the battlefield (g20) | Markers whose labels would overlap are one: "FALLEN EQUIPMENT ×6 · 9 WPN · 39 KG"; mouse over lists "2 × RIFLE 5.56", "1 × MARKSMAN RIFLE 7.62 (NEW)", ammunition; a cluster holding an unregistered type is amber with "NEW: …" (`u_markers`) |
| Equipment was invisible on the strategic map (the Recover opportunity pointed at nothing) | Map shows known equipment: green squares, amber with "new type", named finds labelled, the fallen by count |
| "Squad N2 is ready at Barracks #48" | `LogisticsSim.store_name`: "Barracks, North base 1" (a number only when the base has two of the type) |
| "Defend South base 2" for the player's own base | B4 |
| REARM reported "nothing usable found" for a full cargo, full soldiers and an empty spot alike | "cargo full (4/4): 3 weapons left here", "already fully supplied, no spare weapons here", "nothing here - no known equipment within 30 m and no base stores" |
| Locked development cards cut their requirement ("NEEDS AN OPERATIONAL SUPPLY DE…") | Tooltip with the full requirement |
| EQUIP: eight live APPLY buttons on rows showing "current" | Apply enabled only when the row's choice differs |

## 6. Remaining usability problems (with proposals)

| Problem | Seen | Proposal |
|---|---|---|
| Long marches with nothing to decide (Verket: ~9 minutes) | playthrough §9 GAMEPLAY-04, again here | Transport (GAMEPLAY-06, §15); until then a "march at 2×" hint when no squad is in contact |
| A squad that captures an objective has to stay; nothing says so, and moving off stops the capture (the playthrough's own script did it: Verket roadblock left at 12 %) | p_state | Objective marker shows "capturing 12 % - stay within 70 m"; the squad status shows CAPTURING |
| Map labels collide where several places are close (Verket roadblock, North base 1, Verket, Moen farm cache) | v_map | Same label-box rule as the equipment markers: shorten or stack labels that overlap, full names at closer zoom |
| Order effects are learnt from the button labels only (Z/K/L/J, Shift+RMB, V, O) | review of the command bar | One-line tooltips on command buttons ("Assault: the squad moves on the target by fire and movement, then clears it"); destination ghost while an order is armed |
| The build menu's names differ from messages ("Guard Post" in the menu, "Guard tower site placed") | v_build, log | One display name per structure (StructureCatalog) for menu and messages |
| Settlement houses and the checkpoint / depot read as white boxes from the tactical view | v_overhead, v_base | Asset pass (§9, P-J) |
| Backlit soldiers are almost black against bright grass | v_squad | Rim / ambient term for the infantry materials or slightly stronger sky ambient on characters (test with the look on) |
| The development screen does not say which finds would open more | development screen | A "Discoveries" line per branch: "Find a GPMG to develop Advanced Support Weapons" |

## 7. Combat and AI findings

### 7.1 Rifles at 200–300 m

Measured in GAMEPLAY-04 (arena): rifle 50 m 61 %, 100 m 20.5 %, 200 m 2.5 %, 300 m 0 %. The AI's shot is the ideal line plus a
Gaussian aim error per axis, σ = (0.25° + 0.20° per 100 m) × settle (0.9 when settled) × proficiency (1.0) × suppression, plus the
weapon's spread (0.06° cone + bloom) [CODE `CombatBrain._aim_error`, `CombatSim.current_spread`]. A Monte Carlo of exactly this
model against the hit shapes (torso capsule r 0.30 m to 1.5 m, head sphere 0.14 m; aim at 1.0 m) gives:

| distance | model (current) | arena measured | flatter growth (0.33° + 0.12°/100 m) | no distance growth (0.45° flat) |
|---|---|---|---|---|
| 50 m | 70.8 % | 61.3 % | 65.0 % | 57.0 % |
| 100 m | 23.6 % | 20.5 % | 23.5 % | 23.4 % |
| 150 m | 8.2 % | – | 9.6 % | 11.8 % |
| 200 m | 3.5 % | 2.5 % | 4.4 % | 7.1 % |
| 300 m | 1.0 % | 0.0 % | 1.4 % | 3.4 % |

(The arena is lower by bloom in bursts and the first rough shots; the shape agrees.) Findings:

- **The cause is the aim-error formula**, not engagement rules (the AI does fire at 300 m: 21 aimed single shots in 12 s), target
  tracking (the target stood still) or weapon dispersion (0.06° is negligible). At 300 m one σ is 0.77° = **4.0 m** sideways and
  vertically against a 0.6 m × 1.8 m target.
- The angular error *grows* with distance, so the miss in metres grows with the square of the distance. Even with no growth at
  all (last column) a soldier who hits 23 % at 100 m hits only 3.4 % at 300 m: hit probability for small targets falls with 1/d².
  **Long-range rifle fire can only become effective by making soldiers more accurate at every distance**, which changes every
  GAMEPLAY-02/03 balance result (fights at 100–150 m would end faster).
- Recommendation (not implemented, needs a balance pass with the combat03 series): (a) flatten the growth (0.30° + 0.10°/100 m)
  and (b) let braced/prone, settled riflemen aim tighter (settle factor for rifles 0.7 after `aim_time_s` when still), with
  (c) suppression reduced a little at long range so a pinned enemy is still a fire-superiority result. Expected: 200 m ≈ 7–9 %,
  300 m ≈ 3–4 %, 100 m ≈ 30 %. Validate with `--gameplay04-test --only c_arena` and `--combat03-test --only d_open,d_village
  --seeds=1,2,3` (noisy: differences under 15 points are not conclusive).

### 7.2 Other combat / AI observations

- **Engagement flow** [RUN]: the opening fight (8 v 3 at the Moen checkpoint) took 110 s with 7 of 8 alive; the second
  (Verket roadblock, one squad) 615 s of game time including the march; 1454 player shots over the hour. Fights stay at
  100–150 m, as GAMEPLAY-02/03 tuned them.
- **Near / far consistency**: one resolution path; nothing in this review contradicted it.
- **Suppression**: a soldier at 0.7 suppression hits nothing at 100 m (GAMEPLAY-04 §6.3); combined with §7.1 this makes fire
  superiority decisive, which reads well in play; part of the proposed balance pass.
- **Defence posts**: one unreachable post no longer leaves a garrison BLOCKED (B2). The underlying causes of unreachable posts
  (posts judged on world data without a reachability test) remain; `posts_given_up` in the tactics summary counts them.
- **AI**: the world felt active in the playthrough (South reinforced the checkpoint, East expanded, warnings and defend
  opportunities came in time). AI factions still never salvage equipment (P-D).

## 8. Equipment, progression and logistics findings

- The records are sound: weapons are on a soldier, in a squad's cargo, in a stash or in the armoury; save/load restored
  them exactly in the playthrough (step 18) [RUN].
- **Cargo is small** (one spare weapon per two soldiers): after a fight with 8 dead enemies the squad can take 4 of ~12
  weapons. With markers summarised, the rest stays visible but needs several trips.
- **Vehicle salvage (future)** — can the records support it? [CODE] `VehicleState.cargo` is a bulk `Inventory` (supplies,
  ammunition, fuel in kg), so stash ammunition can go into a truck as it is (`Inventory.transfer`). Weapons are items
  (`SquadState.cargo` id → count), which a vehicle lacks. Needed extension (small): `VehicleState.items` (id → count, capacity
  from `VehicleDefs`), a `SquadEquipment.salvage(vehicle, at)` that mirrors `rearm` (stashes in reach → items/ammo), and
  `deliver` accepting a vehicle at a base with a supply depot (registration unchanged). No second inventory system; the
  existing logistics job types (`LogisticsSim` jobs) can carry a "salvage" job.
- Military Development is legible and permanent; the discovery gates (DMR, GPMG, 84 mm) tie exploration to progression well.
  The weakest link: a registered carbine is procurable without any development, while the DMR needs three steps; fine, but the
  development screen does not say which *finds* would unlock more.

## 9. Visual quality assessment

Screenshots of the real game at 1920×1080; same place, camera and time for before and after (`--gameplay05-test --only v_tour`).

| Area | Assessment |
|---|---|
| Terrain (5A) | Good relief and road integration (shoulders); the ground textures detile well up close. From the tactical camera the colour map dominates: large flat patches of lime meadow and ochre field with hard edges read as paint, not land. Forest floor and rock good. Distant terrain had almost no atmosphere. |
| Vegetation | Pines, spruce and birch convincing within ~80 m; grass tufts dense and well lit. The impostors drew black horizontal lines across the canopy (fixed). The grass is uniformly yellow-green when backlit. |
| Lighting (5B) | Sun direction and shadows fine; no ambient occlusion: buildings, sandbags and soldiers floated; the procedural sky was a saturated postcard blue; ACES tone mapping with exposure 1.05 is right; glow is subtle (kept). |
| Soldiers (5C) | Proportions, uniforms and loadouts good up close (CHARACTER-01 / GAMEPLAY-04 weapons in the hands, roles distinct by kit). Two soldiers out of eight vanished at ~12 m from the camera (fixed). Selection discs are flat light-blue ellipses that read as UI, which they are; acceptable. Backlit soldiers go very dark. |
| Buildings (5D) | Military structures (command post camo net, guard tower, sandbag and fighting positions) are believable and grounded. The checkpoint station and supply depot are plain white boxes from above; settlement houses, barns and sheds are flat-colour blocks with painted windows; fences are untextured grey-brown rails. These are the weakest assets on screen. |
| Effects (5E) | Tracers visible and readable from the tactical view (g07); muzzle flashes and impacts not re-assessed in depth this time (GAMEPLAY-02D tuned them). |
| HUD (5F) | Coherent: one kit (UI-01C), consistent caps headings, keycaps, status words and colours; panels sit in fixed places. Faults found were content, not style: wrong numbers (strength), id names, overlapping world labels, eight live Apply buttons. |

### 9.1 Asset pipeline and the five categories with the most visual benefit

The pipeline is in place and disciplined [CODE]: Blender build scripts per family (`tools/blender/asset_production`,
`tools/blender/env`, `structures`, `character`), authored LODs, procedural tileable textures (`ap_textures.py`), previews, the
QA gate (`build_assets.py -- --qa`, baseline), and in-game checks (GAMEPLAY-04 rendered its weapons in Blender and inspected
them in first and third person). The gap is not process but **coverage**: the ASSET-PRODUCTION-01 military set and the
characters went through it with texture sets; the environment set of the reference world (houses, barns, sheds, fences, road
posts, built for WORLD-TERRAIN-01) did not — flat albedo with vertex colours (`wood_weathered.tres` has no texture). The QA
gate checks geometry and budgets, not material richness.

| # | Category | Why it matters | Proposal |
|---|---|---|---|
| 1 | Settlement buildings (house, barn, shed; WORLD-SETTLEMENT-02 places 11 540 records) | Seen in every tactical view; flat-colour blocks are the strongest "prototype" signal on screen | One trim sheet (painted wood siding, corrugated / tile roof, window frames, foundation stone) through `ap_textures.py`; rebuild the three meshes with UVs onto it; keep the per-instance colour as a tint on the siding only. Budget: same triangle counts, +1 material. In-game check: v_overhead / v_base. |
| 2 | Military utility structures that read as white boxes (checkpoint station, supply depot) | They are the player's own base | Same trim-sheet approach with military textures (OD paint, canvas, plywood, steel); the camo-net command post shows the target level |
| 3 | Terrain colour map (`color.rgba8`, `tools/terrain_ref/generate.py`) | Most pixels of the tactical view | Noisier, less saturated field palette with soft field edges (generation change → world rebuild and new manifest: needs product-owner approval; the in-memory tints of this review are the stop-gap) |
| 4 | Environment props (skigard fence, road posts, mailboxes) | Close to the player in first person | A textured weathered-wood material (grain along the rail UVs); cheap |
| 5 | Infantry materials in backlight | Soldiers go almost black against bright grass from the sun side | A small rim / ambient lift in the infantry materials, checked with the look on (FPS and RTS) |

Vehicles were not on screen in the New Game hour and were not assessed. Suggested gate addition: a "materials without any
texture" count per asset in the QA report, so flat-colour assets are visible in the baseline.

## 10. Visual improvements implemented

| Change | Where | Verified | Cost |
|---|---|---|---|
| SSAO (radius 1.4, intensity 1.6) | `WorldLook` | v_base, v_overhead: structures and trees sit on the ground | part of the total below |
| Grading: saturation 0.86, contrast 1.06 | `WorldLook` | all views: less "postcard" | – |
| Haze: fog 1.6e-4, aerial perspective 0.35, sky affect 0.25 | `WorldLook` | v_land_low / v_fps: hills at 3–6 km now sit in air | – |
| Softer sky (top 0.36/0.49/0.66), sun slightly warm | `WorldLook` | v_fps | – |
| Ground tints: Meadow 0.70/0.84/0.52 → 0.66/0.76/0.52, Field / heath 0.96/0.98/0.70 → 0.86/0.84/0.70 | `WorldLook.GROUND_TINTS` (Terrain3D texture assets, in memory) | v_overhead: lime → muted green; v_base: acid ochre → straw | none |
| Impostor top cards fade when edge-on (`edge_fade` 0.3) | `foliage.gdshader`, six `impostor_*_top.tres` | v_fps / v_land_low: black canopy lines gone | not measurable |
| Character LOD cross-fade (1.5 m) | `InfantryCharacter` | v_squad: 8 of 8 soldiers drawn (6 of 8 before) | +0.3 ms with a whole squad in the band |

Frame rate per view (vsync off, 1920×1080, same build; before = `--legacy-look`):

| View | before fps (ms) | after fps (ms) |
|---|---|---|
| landscape low | 218 (4.59) | 200–217 (4.6–5.0) |
| landscape far | 221 (4.53) | 218 (4.59) |
| overhead village | 312 (3.20) | 283 (3.54) |
| base | 318 (3.14) | 264 (3.79) |
| squad close-up | 326 (3.07) | 277 (3.61) |
| first person | 241 (4.15) | 233 (4.29) |

The whole look costs 0.1–0.65 ms per frame at this resolution (mostly SSAO); every view stays above 200 fps on this machine.
Not changed: tone mapper (ACES kept), glow, shadows, terrain textures, assets.

## 11. Before / after screenshot references

| Subject | Before | After |
|---|---|---|
| Landscape, low camera | `docs/gameplay05/v_land_low_before.png` | `v_land_low_after.png` |
| Landscape, far | `v_land_far_before.png` | `v_land_far_after.png` |
| Overhead, Moen farm | `v_overhead_before.png` | `v_overhead_after.png` |
| Small base | `v_base_before.png` | `v_base_after.png` |
| Squad close-up (LOD gap) | `v_squad_before.png` (6 of 8 visible) | `v_squad_after.png` (8 of 8) |
| First person (canopy lines, haze) | `v_fps_before.png` | `v_fps_after.png` |
| Fallen equipment labels | `docs/gameplay04/g20_sandbox.png`, `before/g20_sandbox.png` | `u_markers.png`, `u_markers_map.png` |
| Strength "1/5" | `before/g20_sandbox.png` (roster) | `u_strength` log: "N1 5/8" |
| Build menu, map (UI review) | – | `v_build_after.png`, `v_map_after.png` |
| The first hour replayed (GAMEPLAY-04 build) | `before/g01…g20` | – |

## 12. Performance findings

Workload `--gameplay05-test --only q_perf`: New Game, the squad assaults the Moen checkpoint; measured at normal speed from the
first shot, 40 s from the tactical camera over the fight, then 30 s in first person (116 units in the world, 401 shots,
vsync off, 1920×1080):

| | tactical camera | first person |
|---|---|---|
| frame avg / p95 / p99 | 3.37 / 5.41 / 6.58 ms | 3.13 / 5.24 / 7.03 ms |
| frame max, frames > 33 ms | 49.98 ms, 3 | 46.48 ms, 1 |
| draw calls / objects / primitives | 586 / 1675 / 1.28 M | 1172 / 1539 / 1.23 M |
| sim per tick: abstract / brain / tactics / war / vehicles | 680 / 738 / 30 / 56 / 76 µs | 552 / 734 / 30 / 47 / 91 µs |
| memory static / video | 2.14 GB / 1.84 GB | same |

Findings:
- **Healthy in play**: ~300 fps average, p99 under 7.1 ms. The look costs 0.1–0.65 ms (§10).
- **Spikes**: 1–3 frames of 46–50 ms in 40 s. Not attributed in this review; candidates are the near-tier navmesh rebake
  (async, but its result is applied on the main thread), vegetation chunk loads when the camera jumps, and the first build of a
  merged character LOD. Next step: tag the frame with the active subsystem (the GAMEPLAY-04 planning-budget probes) when a frame
  exceeds 33 ms.
- **Per-tick simulation ≈ 1.3 ms**, dominated by CombatBrain perception (~0.74 ms) and the abstract tier (0.55–0.68 ms) with
  116 units; tactics and war are cheap. Fine for this scale; the brain grows with soldiers in contact (100 v 100 measured in
  COMBAT-02).
- **First-person draw calls double** (1172 vs 586): LOD0 characters (~35 pieces each) and near vegetation; acceptable.
- **Unbounded records**: fallen stashes are capped (150), the war log (200 events) and route caches are bounded; nothing new found.
- A single DEFEND plan still costs 5–13 ms (GAMEPLAY-04 §10), spread to one per step.

## 13. Core gameplay-loop assessment

**Explore → Fight → Recover → Expand → Build and recruit → Larger operations → Explore further.**

| Link | Supported today | Weak point |
|---|---|---|
| Explore | Yes: caches and finds become known within sight; opportunities point at them | Finds are five placed scenario items; beyond them exploration pays only in supplies; nothing is hidden for reconnaissance to discover |
| Fight | Yes: varied posts, tactics, suppression, explosives | Long-range rifle fire is ineffective (§7.1) |
| Recover | Yes: REARM, cargo, delivery, registration | Carrying capacity on foot; no vehicle salvage; AI never salvages |
| Expand capabilities | Yes: discovery-gated development | 14 projects end within ~1–2 hours; no later goals |
| Build and recruit | Yes | Barracks → one squad at a time; no reason to build a second base except income |
| Larger operations | Partly: several squads, map orders, operations exist for the AI | The player has no transport; a 1.7 km march takes ~9 minutes; no convoy or vehicle play in the first hour |
| Explore further | Weak | Nothing pulls the player beyond the valley after Verket except opportunities of 100–300 kg |

[NOTE] The loop is complete in principle; what is missing is **scale and reach**: a way to move further (vehicles), a reason
to (distinct sites with rare equipment or intelligence), and something to do with what is found beyond the first unlocks.
The world feels active (South's reinforcements, East's expansion, warnings, defend opportunities), and the sandbox player can
ignore the tracker — the world does not depend on it.

## 14. Proposed future features

Each proposal: problem → gameplay → reuse → complexity → dependencies → benefit → when.

**P-A. The player's first vehicle and squad transport in New Game** (GAMEPLAY-06 core)
- Problem: 12 of the first 24 minutes are marches; Verket is 9 minutes away on foot; the player never meets the vehicle game
  that LOGISTICS-01 built.
- Gameplay: a truck is found (an abandoned army depot already exists in the scenario) or procured after Workshop &
  Maintenance; squads board it (existing transport order), drive to an objective, dismount; the truck carries supplies to a
  forward base.
- Reuse: `VehicleSim`, `VehicleTransport`, `VehicleRouter`, `acquire_vehicle`, the RTS/map transport orders (they exist and are
  tested), `stashes` for a "vehicle find".
- Complexity: low–medium (scenario data, a vehicle stash kind, tracker/opportunity text, AI unchanged).
- Dependencies: none new; N1-B vehicle clearance is done.
- Benefit: high — halves dead time, opens the map, makes fuel and roads matter.
- When: **now** (next milestone).

**P-B. Battlefield salvage by vehicle**
- Problem: cargo on foot caps recovery at a few weapons; fallen equipment piles up.
- Gameplay: after a fight, send a truck to "Salvage" a cluster (the marker is the target); it loads weapons and ammunition and
  returns them to the armoury; unknown types are registered on delivery.
- Reuse: `SquadEquipment` (rearm/deliver logic), `LogisticsSim` jobs, `Inventory` for ammunition; new `VehicleState.items` (§8).
- Complexity: medium. Dependencies: P-A. Benefit: high (closes the recover link). When: **now/soon** (same milestone if time).

**P-C. Distinct military sites and reconnaissance targets**
- Problem: exploration pays only at five placed finds.
- Gameplay: a handful of authored site types placed by the scenario generator over the map — radar post, abandoned depot,
  crashed helicopter, fuel dump, signals site — each with a guard size, a loot table (rare weapons, fuel, intel) and an
  "observe first" value: a site reported by a reconnaissance squad shows its defenders (IntelSim contacts) and its loot.
- Reuse: `extra_objectives`, `stashes`, `Opportunities` (observe / take / recover already exist), `IntelSim` reports.
- Complexity: medium (data + placement on ref_20km sites). Benefit: high for the sandbox player. When: **soon**.

**P-D. AI salvage and equipment acquisition**
- Problem: AI factions never REARM or collect; their arsenal never grows from fights.
- Gameplay: an AI squad after a won fight REARMs at stashes within 200 m; AI bases deliver; their compositions use registered
  types. The player loses the monopoly on battlefield loot (and can deny it by holding the field).
- Reuse: `SquadEquipment.order_rearm` (same call), `WarSim` post-fight hook. Complexity: low. When: **soon**.

**P-E. Long-term progression: development tier 2 and squad specialisation**
- Problem: the 14 projects are done in 1–2 hours; then nothing grows except numbers.
- Gameplay: projects that need two discoveries or a captured site (e.g. Mechanised Infantry: truck + depot + 3 objectives;
  Recon Section: a squad composition with DMR + radio, faster reports; Engineer Section: builds 40 % faster, clears obstacles);
  squads keep a specialisation (composition) the player chooses at recruitment.
- Reuse: `DevelopmentDef`, `SquadComposition`, `MilitaryDevelopment` gates. Complexity: low–medium (data). When: **soon**.

**P-F. Rifle accuracy balance pass** (§7.1)
- Problem: rifles are useless beyond 200 m; long-range fights are only DMR fights.
- Reuse: `CombatBrain` constants, combat03 series. Complexity: low code, medium validation. When: **soon** (own small milestone).

**P-G. Defence operations for the player's bases**
- Problem: a warning ("Possible attack…") and a Defend opportunity exist, but defending is manual; garrisons are one squad.
- Gameplay: "Defend base" on the map assigns nearby squads and the base's positions (OpCoordination stages already exist for AI).
- Reuse: `OperationState` DEFEND, `_defence_posture`, garrison. Complexity: medium. When: **later** (after P-A, transport makes
  reinforcement possible).

**P-H. Convoys and supply lines for the player**
- Problem: forward bases need supplies; today stock is faction-wide.
- Gameplay: a forward base's construction draws from its own store; trucks run restock rules (existing `add_rule_restock`).
- Reuse: LOGISTICS-01 rules, convoys. Complexity: medium (economy rule change). When: **later**.

**P-I. Onboarding pass on controls**
- Problem: F1 controls exist, but the tactical keys (Z/K/L/J, Shift+RMB bounds, V formations, O garrison) are learnt only by
  reading the bar; no in-world feedback on what an order will do.
- Gameplay: hover tooltips on command buttons with one line of effect; an order ghost (destination marker + formation
  preview) before release. Reuse: `TacticalPanel`, kit. Complexity: low. When: **now** (polish).

**P-J. Settlement and prop art pass** (§9)
- Houses, barns, sheds and fences are flat-colour blocks; terrain colour map saturated. A Blender pass on the 4 settlement
  meshes (trim sheet: wood siding, roof sheets, windows) and a textured weathered-wood material. Complexity: medium (art).
  When: **soon**, in parallel with gameplay.


## 15. Prioritized development roadmap

### Priority table

| Priority | Issue or improvement | Player impact | Effort | Recommendation |
|---|---|---|---|---|
| P0 | Squad strength shown wrong (B1) | High | Low | **Fixed** |
| P0 | Garrison BLOCKED for good (B2) | High | Low | **Fixed** |
| P0 | Soldiers invisible at 12 m (LOD gap) | High | Low | **Fixed** |
| P1 | Player transport and first vehicle (P-A) | High | Medium | Next milestone |
| P1 | Vehicle salvage (P-B) | High | Medium | Next milestone (second half) |
| P1 | Capture feedback (stay on the objective) | Medium–High | Low | Next polish |
| P1 | `c_forts` timber tower never built (B6) | Low (test) – unknown (game) | Low | Diagnose next |
| P1 | Order tooltips and destination ghost (P-I) | Medium | Low | Next polish |
| P2 | Distinct military sites and recon targets (P-C) | High | Medium | Plan (GAMEPLAY-07) |
| P2 | AI salvage (P-D) | Medium | Low | Plan |
| P2 | Rifle accuracy balance pass (P-F, §7.1) | Medium | Low code / medium validation | Plan |
| P2 | Development tier 2, squad specialisation (P-E) | Medium | Low–medium | Plan |
| P2 | Settlement and prop art pass (P-J) | Medium (visual) | Medium | Plan, in parallel |
| P2 | Frame spikes 46–50 ms attribution | Low–medium | Low | Plan |
| P3 | Map label collisions | Low–medium | Low | Later |
| P3 | Defence operations for the player (P-G) | Medium | Medium | Later |
| P3 | Player supply lines and convoys (P-H) | Medium | Medium | Later |
| P3 | Lobbed 40 mm, recorded weapon audio (GAMEPLAY-04 §13) | Low–medium | Medium | Later |

### Immediate polish (days)
Capture feedback; order tooltips / destination ghost; one structure name for menu and messages; map label collisions;
diagnose B6; spike attribution. (Quality improvements; no new systems.)

### Next gameplay milestone: GAMEPLAY-06 — Motorised logistics and battlefield salvage
Why this and not NAVIGATION N1-C2: the review measured where the player's time goes — half the first hour is walking, and the
equipment loop stops at what a squad can carry. Vehicles, routing (N1-A/B/C1), transport and convoys already exist and are
tested for the AI; the player simply never gets them in New Game. Scope: a truck find / procurement in the opening's second
half, squad transport through the existing orders, a SALVAGE job for a vehicle at an equipment marker (`VehicleState.items`,
`SquadEquipment.salvage`, delivery as today), forward-base resupply by truck using the existing restock rules, tracker and
opportunity text. Essential gameplay; reuses LOGISTICS-01, N1-B, GAMEPLAY-04D. N1-C2 (tracked profiles, pivot turns) only
matters once tracked vehicles are in the player's hands.

### Medium term (systems for larger forces and operations)
GAMEPLAY-07 exploration sites and reconnaissance (P-C) with AI salvage (P-D); development tier 2 and squad specialisation
(P-E); the rifle balance pass (P-F) with the combat03 series; defence operations for the player's bases (P-G); player supply
lines (P-H). Technical debt alongside: cheaper DEFEND plans (cache exposure per area/threat), reachability-checked posts,
NAV-INF near-tier stalls (navinf_04 near fails about one run in two on the unchanged code).

### Longer term (when the foundation is ready)
AI-VEH-01 vehicle combat and combined arms; AIR-01/02; tracked vehicles (N1-C2); proficiency growth (experience); weather /
time of day; a full art pass on terrain textures and settlements; recorded audio. Optional features, in that order of value.

## 16. Known limitations

1. **B6** (`c_forts`: the timber guard tower is never finished) is pre-existing and not diagnosed (§3.1).
2. **navinf_04 near tier** fails about one run in two on the unchanged code as well (3/6 and 6/6 arrived in two baseline runs;
   5/6 and 3/6 with this review's code); far tier always 6/6. Pre-existing near-tier stalls ("no progress after an unstick
   attempt").
3. The **garrison BLOCKED** of GAMEPLAY-04 was not reproduced from its own save in three runs; the mechanism found (B2) is
   reproduced by a test and fixed, and is the only path in the code that leaves a defender BLOCKED without a post. If the
   status shows again, `posts_given_up` and the squad log say which post could not be reached.
4. A defender who cannot reach his post now holds where he stopped; he may stand in the open short of cover.
5. **Rifles at 200–300 m** unchanged (§7.1, a balance decision).
6. **WorldLook** is applied at game start to the world scene; the editor shows the old look (the generated scene is untouched
   by design). Tuned on ref_20km in summer daylight only.
7. The **frame spikes** (46–50 ms, 1–3 per 40 s) are measured, not attributed.
8. Settlement houses, depots and fences remain untextured blocks (art work, not done here).
9. The GAMEPLAY-03 `c_flank` failure and the exit access violation remain as documented there.

## 17. Tests and validation

Targeted, by change (no full suite was run):

| Change | Checks | Result |
|---|---|---|
| Review baseline | GAMEPLAY-04 `g_playthrough` replayed with shots (20 steps) | PASS; found B1, B3, B7 and the visuals |
| Save diagnostics | `--continue --gameplay05-test --only p_state`, `p_watch` (4× near, 8× near, 8× far) | strength fixed; BLOCKED not reproduced from that save |
| B2 garrison | `u_post_block` (fails on the old code: BLOCKED 81 s and counting) | PASS: BLOCKED 16 s, then DEFEND · HOLDING |
| B2 shared code (SquadControl, SquadTactics) | `--campaign-test --only c_forts,c_ai_garrison`; `--combat03-test --only p_posts,f_persist`; `--nav-inf-test --only navinf_02,navinf_04` | c_ai_garrison, p_posts, navinf_02 PASS; f_persist failed once (precondition: no fall back within 500 s), PASS on rerun; c_forts and navinf_04 near fail identically on the baseline (§16) |
| B1 strength | `u_strength` | PASS (3 of 8 killed → 5/8) |
| B3, EQUIP Apply, REARM text, dev tooltip | `--gameplay04-test --only d_setup,d_rearm,d_fallen,d_deliver,d_ui,b_ui` | PASS, 0 script errors (48 formatting errors in the playthrough before) |
| B4 base names | `u_capture_name` | PASS (South base 2 → North base 2) |
| Equipment markers | `u_markers` (tactical and map, with shots) | PASS (7 stashes → 2 markers, DMR flagged) |
| B5 navmesh values | every later run's log | 0 precision warnings (27+ per run before) |
| Character LOD gap | `u_bodies` diagnostic + `v_tour` | 8 of 8 visible |
| Look, impostors | `v_tour` before (`--legacy-look`) and after, frame rates per view | kept (§10) |
| Performance | `q_perf` | §12 |
| World files | `world_manifest.py verify --ignore-editor-metadata` | OK, 535 files unchanged |
| Rifle accuracy | Monte Carlo of `CombatBrain._aim_error` against the hit shapes | matches the GAMEPLAY-04 arena (§7.1) |

`tools/check_scripts.gd` before every run (176 scripts, 0 failures at the end).

## 18. Commits

| Commit | What |
|---|---|
| `e6f83f0` | squad strength, garrison BLOCKED, EQUIP refresh, captured base names |
| `8ecd86f` | equipment markers (tactical, map), facility names, REARM feedback, development tooltips |
| `ef8c304` | soldiers invisible at the LOD switch; navmesh warning spam |
| `638eb4b` | world look, impostor edge fade, `--gameplay05-test`, screenshots |
| (this report) | report, README, CLAUDE.md notes |

Not pushed. Local changes that were in the working tree before this review (`addons/world_edit/plugin.cfg`,
`docs/gameplay01b/menu_1920x1080.png`, the UI-01 zip files, `docs/referanser/`, `worlds/ref_20km.overrides.json`, …) were left
as they were.
