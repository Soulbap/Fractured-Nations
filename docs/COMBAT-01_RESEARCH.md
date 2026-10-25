# COMBAT-01 — Combat Visibility, Gunplay & Tactical AI

**Status:** research and implementation planning only. No combat, movement, or asset-pipeline code was changed for this report.

## 1. Executive summary

FRACTURED NATIONS does **not** need a replacement combat architecture. It already has a sound, unusually well-integrated foundation: `UnitState` is the authoritative persistent record; `CombatSim` is the sole owner of shots, reloads, damage and death; `LineOfFire` resolves the same world data near and far from the camera; `CombatBrain` owns individual awareness and firing; `SquadTactics` owns tactical intent; and `WarSim` / `OpCoordination` own the operation. This is the right three-level split to preserve.

The largest player-facing opportunities are therefore integration and tuning work, not wholesale simulation:

1. **[Essential] Establish a reproducible visibility/readability matrix before changing detection values.** The reported VISUAL-03 failure at 120 m in tall grass is not explained by the current code: grass is not an AI occluder, while a clear 120 m encounter is already documented as detecting and firing. The likely causes are a test-specific view/terrain/tree setup, unloaded vegetation cells delaying a query, or a scenario/observability problem. Do not globally increase sight range.
2. **[Essential] Make the existing combat legible at range.** Validate the new soldier's silhouette/LOD at 50–500 m, correct dark backlighting, tune optics, and make flashes, tracers and impacts read without turning enemies into glowing outlines. The VISUAL-03 rig is already the correct foundation and must remain so.
3. **[Essential] Playtest and tune the existing squad tactics before adding more tactical systems.** Suppression, local cover, fire missions, fire teams, bounding, flanking, assault and withdrawal are present. The key risk is that their live timing, post selection and presentation have not been judged enough in the real player loop—not that the project lacks a planner.
4. **[Recommended] Improve weapon feedback and role differentiation using the existing `WeaponDef` / `CombatFX` path.** Aim settling, recoil, spread bloom, role data and animation layers already exist. The visible weak point is placeholder synthesized weapon audio and generic surface impacts, not a missing gun model.
5. **[Avoid] A global detection-distance increase, permanent enemy markers/outlines, per-frame full-world raycasts, a second tactical blackboard, or a general ballistic/injury rewrite.** Each conflicts with either the intended concealment, performance, player clarity, or the current authoritative design.

The target experience should be: contact is understandable; movement, cover and fire superiority matter; squads make small, readable tactical decisions quickly; and player weapons remain dependable. Believability comes from visibility, timing, reaction and feedback—not from random inaccuracy or elaborate simulation.

## 2. Audit method and confidence

This audit read the live `develop` sources and the existing COMBAT-01A/01B, COMBAT-02, GAMEPLAY-05 and VISUAL-03 reports. It did not run stochastic combat suites, alter a test, or make a gameplay change.

Terminology used below:

- **Confirmed:** directly present in current source or a documented measured project result.
- **Likely:** an inference from the code and prior result; requires the stated focused scenario before changing balance.
- **External pattern:** a documented technique from a public technical source. It is not a claim about unpublished internals of a commercial game.

## 3. Current architecture and dependencies

### 3.1 Authority and update order — confirmed

```text
WarSim / OperationState / OpCoordination          strategic and operation intent
                 |
SquadControl + SquadTactics                       formation, orders, teams, tactic posts/missions
                 |
CombatBrain                                        perception, memory, engagement, suppression, cover reaction
                 |
CombatSim + LineOfFire                            one authoritative shot, hit, damage and death result
                 |
UnitState / WorldState                            persistent data across save, FPS/RTS and detail tiers
                 |
SoldierBody + InfantryCharacter + CombatFX/HUD    movement, VISUAL-03 animation and presentation only
```

`WorldSim._physics_process` advances abstract infantry, squad control, squad tactics, vehicles/logistics, war, combat brain, then combat/reload/explosives. This order is coherent: a squad decides intent before a soldier fires, and the shot result is authoritative before effects consume its event.

| Layer | What currently works | Important dependencies / limits |
|---|---|---|
| `WorldState`, `UnitState` | Health, ammo, reload, target memory, suppression, tactical reaction, cover and fire mission state serialize with the unit. Possession and promotion/demotion preserve authority. | The record deliberately has no posture/exposure state beyond standing/cover location; adding crouch/prone is cross-cutting work. |
| `CombatSim`, `LineOfFire` | One fire request handles controller ownership, magazine, cooldown, deterministic spread, hit, damage, death and events. Analytic world tracing supports terrain, structures, trunks/rocks and units with or without physics bodies. | Primary weapons are hitscan; this is an intentional extension point, not a defect. Foliage blocks sight but not bullets. |
| `CombatBrain` | Staggered 3 Hz perception, 400 m base sight range, 150° FOV, near awareness, LOS, head/torso checks, target memory, hearing/look direction, contact sharing, range/role-aware engagement, bursts, friendly-fire checks, suppression, local cover, grenade/launcher use. | Spotting is binary once a candidate is checked; grass is absent from the occlusion model; shared reports only direct attention, not immediate fire. |
| `SquadControl`, `SquadTactics` | Existing player orders remain authoritative; teams, DEFEND, SUPPRESS, ASSAULT, FLANK, BOUND, REPOSITION, WITHDRAW and REGROUP are implemented. Tactics use known/observed contacts, posts and bounded searches. | Tactical cadence is 0.5 s and assessment/replanning is constrained; live quality hinges on candidate quality, thresholds and animation/readability. |
| `WarSim`, `OperationState`, `OpCoordination` | Operations carry distinct stages including approach, deploy, support, assault, secure and withdraw. Squad roles and `cover_fire` exist. | Operational staging cannot substitute for local perception: a squad still needs a credible contact and local maneuver space. |
| Soldier/FPS presentation | VISUAL-03 supports LOD0/1/2, ready, aim, fire and reload upper-body layers. `CombatFX` has pooled flashes/tracers/impacts/3D sounds; FPS uses recoil, ADS and a weapon viewmodel. | Existing LOD distances are 12 m and 28 m; long-range readability is primarily silhouette/contrast/optics/VFX rather than close LOD alone. Audio is explicitly placeholder. |

### 3.2 What is already strong

- A combat result does not depend on camera distance, a physics body, or whether the player switches between RTS and FPS. This is valuable for the persistent-world requirement and should not be compromised.
- Ray/tracing data is shared by sight, shots, cover assessment and explosive cover checks. That avoids the common contradiction in which AI “sees” through cover or a far-away unit cannot be hit.
- The brain uses a faction grid, staggered checks, a LOS budget, warm vegetation cells and a distant perception LOD. The project has already measured 100 v 100 rather than relying on intuition.
- Weapons are data-driven and role-aware. `WeaponDef` already holds cadence, damage drop-off, accuracy/recovery, handling, effective/AI range, optic sight range, suppression, bracing and audiovisual hooks.
- Suppression does not reduce damage or manufacture misses. It changes acquisition/aim and tactical movement, which fits the design principle better than arbitrary health or hit-chance inflation.
- Squad tactics explicitly use reported/observed information rather than hidden enemy positions, and individual cover reactions remain subordinate to player orders.

### 3.3 Partial, weak or contradictory areas

| Finding | Evidence and effect | Assessment |
|---|---|---|
| Grass has visual presence but no AI-concealment representation. | `LineOfFire.foliage_layers()` counts tree trunks in a corridor; it does not query grass. | **Confirmed.** This makes the VISUAL-03 tall-grass result a scenario/diagnostic question, not an intended grass rule. |
| Detection is binary. | A target inside range/FOV with a clear check is acquired at the next perception update. Exposure, target movement and firing only influence awareness indirectly (aim, hearing or contact), not detection confidence. | **Confirmed.** A lightweight exposure/signature accumulator could improve believability later, but it is not first priority. |
| The player-facing long-range readability criteria are not yet formalized. | The soldier LOD bug at ~12 m was fixed; existing reports acknowledge backlit soldiers can be too dark. There is no cited 50/100/200/300/500 m checklist. | **Confirmed.** This is a visual QA gap, not proof that a new rendering architecture is required. |
| Weapon feedback has a solid event path but generic content. | Pooled flash/tracer/impact and 3D sound work; `CombatAudio` says it creates temporary synthesized placeholder sounds. Impacts are flesh/dust, not material-driven. | **Confirmed.** High player-visible return for an asset/content pass. |
| Existing tactics are more advanced than older limitations say. | Current `SquadTactics` implements fire teams and named tactics; `CombatBrain` implements local cover/suppression/fire missions. Older COMBAT-01B limitations are historical. | **Confirmed.** Do not plan duplicate cover, suppression or flanking systems. |
| Long-range rifle effectiveness requires a deliberate balance decision. | GAMEPLAY-05 measured very low 200–300 m rifle hit rates and attributes them to AI angular error, not line-of-fire failure. Current aim profile has already been flattened relative to a prior profile. | **Confirmed.** Do not change by reflex; separate player weapon feel from AI accuracy and validate pace. |
| Detailed pose does not yet affect the hit model. | Hit shapes remain analytic standing head/torso; the character has an animation blend including crouch, but combat’s authoritative eye/hit geometry is standing. | **Confirmed.** Crouch/prone should be a future integrated feature, not a shader or animation-only addition. |

## 4. External research and applicability

The sources below are technical documentation or first-party development material. Where a source exposes configurable behavior, it is evidence of a design pattern—not a reason to reproduce every parameter.

| External pattern | Problem it solves / conceptual operation | Fit and integration judgement |
|---|---|---|
| Arma 3 config separates sensory signatures, engagement ranges, fire-mode probability/cadence, ammunition purpose and suppression radii. Its public references expose `visibleFire`, `audibleFire`, target threat, range probability, and close-bullet/hit suppression parameters. [AI config reference](https://community.bohemia.net/wiki/Arma_3%3A_AI_Config_Reference) | Prevents one generic “enemy seen” value from controlling every weapon and target. Weapon characteristics influence whether/when an AI employs a weapon; near fire becomes a separate reaction stimulus. | **Fit: high, difficulty: low–medium.** FRACTURED NATIONS already has the good subset: weapon roles, sight/engage ranges, hearing, bursts, near-miss suppression and fire missions. Add only data that produces a clearly observed gameplay difference; do not emulate Arma’s full config surface. |
| Arma 3’s documented `CanSee` capabilities distinguish eye, optics and ear sensing; its vehicle sensor documentation treats visual target size and sensor spectra as different inputs. [Targeting reference](https://community.bohemia.net/wiki/A3_Targeting_config_reference), [sensors reference](https://community.bohemia.net/wiki/Arma_3_Sensors_config_reference) | Keeps “I saw”, “I heard”, and “my optic/sensor knows” from collapsing into omniscience. | **Fit: high, difficulty: low for infantry.** Preserve the existing rule that hearing/contact reports turn heads rather than grant firing authority. Later, let optic sight range and a brief muzzle/fire signature affect *candidate priority*, not magically reveal a target. |
| Unreal’s AI Perception separates sight radius, lose-sight radius, peripheral vision, hearing range and stimulus max age; it supports affiliation filtering and a close-awareness region. [AI Perception](https://dev.epicgames.com/documentation/unreal-engine/ai-perception-in-unreal-engine?lang=en-US) | Avoids target flicker, forgetfulness and abrupt 360° awareness by making acquisition, retention and stimulus age explicit. | **Fit: high, difficulty: low.** The project already has FOV, awareness, memory and hearing. The useful addition is a small hysteresis/confidence layer, only after the visibility matrix proves a player-facing problem. |
| Unreal EQS generates candidate items, filters inexpensive failures before scoring, and returns a best or near-best result. Its own documentation warns EQS is experimental; its test pawn can be expensive. [EQS overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/environment-query-system-overview?application_version=4.27), [EQS testing warning](https://dev.epicgames.com/documentation/en-us/unreal-engine/environment-query-testing-pawn-in-unreal-engine) | Makes cover/firing-position selection explainable: generate local candidates, reject unsafe/unreachable ones, score the remainder. | **Fit: high conceptually, low implementation need.** `CombatBrain.cover_spots` and `SquadTactics` already implement a bounded, local equivalent. Keep it; do not add an EQS-like framework or global baked cover map. |
| Arma 3 exposed suppression as controllable AI state and weapon resting/deployment as distinct gameplay concepts. [Arma 3 SPOTREP #00040](https://dev.arma3.com/post/spotrep-00040) | Lets near fire shape behavior without demanding a hit, while a stable firing position can trade mobility for accuracy. | **Fit: high, difficulty: low–medium.** Near-miss suppression and bracing already exist. Validate the threshold/dwell timing first; later add a visibly communicated supported-rest benefit before considering prone. |
| Godot selects automatic mesh LOD by screen coverage, taking viewport resolution and FOV into account; manual visibility ranges/HLOD can substitute coarser representation and can also fade labels/particles. [mesh LOD](https://docs.godotengine.org/en/latest/tutorials/3d/mesh_lod.html), [visibility ranges](https://docs.godotengine.org/en/4.1/tutorials/3d/visibility_ranges.html) | Preserves perceived shape while reducing rendering work; importantly, it recognizes that distance in metres alone is not visual readability. | **Fit: high, difficulty: low–medium.** The new soldier already has authored LOD ranges and fades. Audit *screen-space silhouette* at target distances before changing its meshes; use restrained range-limited labels only in RTS. |
| Godot recommends combining LOD/HLOD with culling and bounded effects, and notes that MultiMesh instances should be spatially partitioned because an entire MultiMesh shares visibility. [3D performance](https://docs.godotengine.org/en/4.5/tutorials/performance/optimizing_3d_performance.html), [MultiMesh](https://docs.godotengine.org/en/4.4/tutorials/performance/using_multimesh.html) | Prevents effects/vegetation/LOD solutions from shifting the bottleneck rather than solving it. | **Fit: high, difficulty: low.** Keep current camera-radius FX pools and vegetation-cell locality. Do not make per-soldier VFX/lights permanent or globally visible. |

### Confirmed versus speculation about established games

The Arma and engine behaviors above are confirmed only to the degree their public documents describe configuration/interfaces. This report does **not** claim hidden AI implementations for Arma, Battlefield, Squad or Ghost Recon. Battlefield V’s public GDC material confirms that DICE treated AI dialogue as a combined audio/technical readability system, but it does not establish combat decision internals. [Battlefield V AI Dialogue](https://gdcvault.com/play/1026007/-Battlefield-V-AI)

The transferable conclusion is modest: players understand firefights through a combined signal—sight, sound, movement, impacts, cover response and squad behavior. The project should use that lesson without copying another game’s detection distances or accuracy tables.

## 5. Combat visibility diagnosis

### 5.1 Player visibility at 50–500 m

The correct solution is not a permanent enemy outline. The player should first see a moving human silhouette, then derive information from stance, muzzle/trace, sound and behavior; the RTS may add a restrained selection/contact aid when a squad has identified a target.

| Distance | Required player read | Existing support | Recommended acceptance criterion |
|---|---|---|---|
| 50 m | Faction, weapon posture, animation, cover use and immediate threat direction. | LOD0/1 character, aim/fire/reload layers, muzzle flash, impacts and audio exist. | A player recognizes an armed human and whether they are firing/using cover within one second in daylight and backlight. |
| 100 m | Human silhouette, movement and muzzle/trace; faction is usually inferred from context/uniform, not UI. | Current visuals and combat effects should support this; older test documented open 120 m contact. | Moving or firing soldiers remain identifiable against grass/trees without markers. |
| 200 m | Direction/number of shooters and whether a position is dangerous; not necessarily precise individual identity. | Tracer width increases with camera distance; rifle handling is already less effective at range. | A player can locate active fire/impacts and decide to seek cover, flank, use optics or move closer. |
| 300 m | Contact direction and broad element location; optics/DMR establish meaningful advantage. | Weapon resources already distinguish `optic_sight_m`, `ai_engage_m` and handling. | Unmagnified FPS can see activity but must not promise reliable identification or rifle lethality. |
| 500 m | Terrain-scale contact, muzzle/tracer/audio cue and RTS map/contact context. | 400 m default base AI sight, 600 m primary shot resolution and 900 m sound FX cap exist. | Visible activity is intermittent and contextual; no floating permanent enemy IDs. |

**[Essential] Visibility/readability pass.** Test silhouette contrast, shadow, visual LOD transitions, foliage overlap, muzzle brightness, tracer density and scope framing at these distances on the actual reference terrain. Fix the known backlit-soldier issue with material/ambient/rim adjustment before considering any enemy aid. Keep the new VISUAL-03 character and its LOD/animation pipeline intact.

**[Recommended] Restrained RTS aids.** Show a small contact pip or short-lived “under fire” direction on a selected squad only when its members have a live/remembered contact; fade by distance/confidence and keep it separate from FPS. This communicates squad knowledge without granting the player an always-on wallhack.

**[Avoid] Enlarging distant soldiers, permanent coloured silhouettes, or an always-visible enemy nameplate.** These remove vegetation/terrain from the tactical game and would mask rather than diagnose contrast and LOD problems.

### 5.2 The VISUAL-03 120 m tall-grass report

**Finding: likely test-specific or observability-specific, not intended grass concealment.** The project’s own COMBAT-01B acceptance report documented clear 8 v 8 detection at 120 m (first sight 0.07/0.13 s and first shots about 0.7 s). Current `CombatBrain` uses 400 m base sight, 150° FOV, 25 m peripheral awareness and three staggered new candidates per update. Crucially, `LineOfFire`’s foliage layer logic counts nearby **tree trunks** and terrain/structure/rock collisions; grass is visually rendered but is not a sight blocker.

Possible explanations, in descending order to test:

1. A tree/terrain/structure blocked the eye-to-head/torso rays, or three tree-foliage layers crossed the corridor.
2. The squads spawned outside their initial FOV and never received a trigger that turned them toward each other; contact sharing/hearing only changes attention after an initial event.
3. Vegetation cells were not warm yet, delaying checks, or a LOS budget queue made the observation look like no detection.
4. The screenshot/visual test lacked CombatBrain instrumentation and was interpreted as an AI failure when the soldiers were seeing but held by ROE/range/reload/own-cover/friendly-line logic.

**[Essential] Reproduce once, deterministically, before tuning.** Build a short debug scenario with two 8-person squads at exactly 120 m and record: head/torso LOS blockers and foliage count per pair; FOV direction; query timing/budget/warm state; `target_id`, `target_visible`, AI reason and ROE. Run variants on bare ground, grass-only, one-tree corridor and existing tall grass. This is a focused diagnostic scenario, not a stochastic suite. The expected grass-only result today is detection; if it is not, the trace identifies the actual rule.

If gameplay later calls for grass concealment, implement it as a **low-cost local exposure modifier** (grass height/density around target, reduced by movement/firing) that slows acquisition or lowers confidence—not an opaque hard wall and not a blanket shorter sight range. It must be measured at 50/100/200 m and only apply where grass is visually dense enough to justify it.

## 6. Gunplay and audiovisual feedback assessment

### 6.1 Current behavior — confirmed

- FPS and AI use the same `CombatSim.request_fire` and deterministic spread path. A player-owned unit cannot also fire under AI control.
- A rifle has data for cadence, magazine/reload, damage and falloff, base/moving/bloom spread, recovery, recoil, role, bracing, handling/aim time, AI range and optional optic sight range.
- The brain adds target-acquisition delay, settling, proficiency, movement and suppression; it chooses bursts by distance. It does not deliberately lower damage to prolong a fight.
- `CombatFX` consumes shot/reload/explosive events, pools muzzle flashes/tracers/impacts/3D audio and skips distant visual effects. First-person gets camera recoil, ADS, hit/kill tick and reload sound.
- VISUAL-03 feeds ready/aim/fire/reload animation layers from gameplay state, so animation can be synchronized through the existing event/state path.

### 6.2 Assessment and recommendations

| Recommendation | Classification | Problem / proposal | Integration and risk |
|---|---|---|---|
| Establish a four-role handling sheet (carbine/rifle, DMR, LMG/GPMG, launcher) using existing resource fields. | **Essential** | Each role needs a clear tactical promise: carbine fast handling but lower long-range confidence; rifle baseline; DMR longer sight/engage and slower acquisition; machine gun sustained suppression with slower/less mobile handling. Preserve first-shot reliability and let bloom/recovery, movement and position govern sustained fire. | Low difficulty. `WeaponDef` and `CombatBrain` already expose the fields. Balance changes can shift time-to-kill, so measure 8 v 8 before/after. |
| Replace placeholder reports with licensed, role-specific close/mid/distant layers; add material-aware impact sounds and VFX. | **Recommended** | Current audio is synthesized and impacts are generic dust/flesh. A sharp nearby crack, distant report, route-appropriate reverb/attenuation, and wood/earth/metal/stone impacts make cause/effect legible. | Medium content work, low architectural risk. Keep pooled emitters and camera radii; do not make each shot allocate nodes/lights. |
| Tighten animation-event alignment from actual fire/reload state. | **Recommended** | The visual layer already knows aim/fire/reload. Verify muzzle flash/shot audio occurs on the same visual moment as authoritative `shot_fired`; visually begin reload at `reload_started`, retain the authoritative completion timer. | Low–medium. Never make animation the authority for ammo/damage. |
| Add subtle nearby incoming-fire cues. | **Recommended** | Suppression is currently represented in record/HUD logic, but player feedback should include crack/whiz, dust snap and a restrained directional cue. Avoid large red arcade arrows. | Medium. Event-driven from shot segment proximity; reuse the existing near-miss calculation. |
| Hit confirmation stays restrained. | **Recommended** | The existing small hit/kill tick is sufficient for FPS. Prefer impact, target reaction and sound over large crosshair UI. | Low. Must not expose hits through unseen cover. |
| Projectile drop/travel for ordinary rifles, simulation-heavy wind, complex wound states or bullet-sponge health. | **Avoid** | They add latency/edge cases without addressing present readability or squad behavior. | High complexity, weak gameplay return. Keep a future projectile extension for weapons that need it. |

### 6.3 Damage, reactions and fairness

The current health/damage model is intentionally readable: body and head zones, falloff, real cover blockers, one death path, no duplicate hits across LOD tiers. Preserve that. Future hit reactions should be short visual flinches or downed-state presentation tied to authoritative damage/death—not aim-disrupting ragdoll physics that changes collision/hit authority.

## 7. AI perception and target selection

### Current model — confirmed

1. A per-faction grid finds near candidates without sorting all enemies.
2. A candidate must pass range/FOV (or close awareness), then eye-to-head/torso LOS. Trees/rocks/terrain/structures block; three foliage layers hide.
3. The soldier keeps a visible target unless a materially closer candidate wins the switch ratio; it remembers last position for six seconds and watches it briefly after loss.
4. Hearing remembers a recent enemy shot within 150 m; squad contact sharing within 120 m directs idle members to look. Neither source grants firing knowledge.
5. A visible target is tracked with reaction/settle delay, predicted movement and friendly/own-cover checks. Weapon, ammo, reload, range, movement and suppression gate the shot.

This is a good baseline: it produces understandable fallibility without omniscience.

### Next perception work

| Recommendation | Classification | Why / conceptual operation | Integration |
|---|---|---|---|
| Instrument the perception chain in the focused visibility scenario. | **Essential** | Makes a failure explainable as FOV, range, occlusion, foliage, budget/warming, memory, ROE or a fire hold. | Low. Extend debug data/overlay only; no gameplay rule change. |
| Add acquisition/retention hysteresis only if the scenario/playtest proves popping. | **Recommended** | Keep a target for a short grace distance/time after it was seen, while LOS remains authoritative for firing. This mirrors the useful distinction between sight and lose-sight range in public engine practice. | Low–medium. Existing memory/switch fields provide most of the needed state. |
| Add a small exposure/signature score only after grass/movement tests. | **Optional** | Movement, firing and exposed silhouette can shorten acquisition; low posture/dense grass can lengthen it. Decay/threshold means no per-frame global query. | Medium. Store it with candidate memory or derive from local target/context data at staggered perception ticks. |
| Share confidence and direction, not exact unit identity/position, at squad level. | **Recommended** | A reported contact should raise candidate priority / orient a teammate; it should not make every rifle snap to perfect aim. | Low. This extends the present watch/contact model. |
| Global all-enemy scans, per-frame LOS for every pair, or instant squad-wide target replication. | **Avoid** | They break scale, concealment and the current knowledge rule. | High cost and design harm. |

## 8. Suppression, cover and squad tactics

### Current behavior — confirmed

Incoming rounds that pass near a soldier or hit them increase suppression. It decays over time, slows acquisition, worsens AI aim, can inhibit a dash, and triggers temporary local cover reactions. The cover search is bounded: it samples positions behind nearby construction, rocks, trunks and terrain rises; requires threat-side protection; scores firing versus full cover; checks reachability; reserves a spot; rechecks it; and lets the original order resume or return to its anchor.

At squad level, two fire teams and a small score-based tactic set are already present. Assessments use observed/known contacts, casualties, suppression, ammunition and estimated opposition. Operations add staged support/assault/withdraw intent. The hierarchy is appropriate:

```text
player order > operation assignment > squad tactic > individual cover reaction > firing decision
```

### Practical tactical recommendations

| Recommendation | Classification | What problem it solves | Fit / difficulty |
|---|---|---|---|
| Tune and playtest the current support-before-movement gates. | **Essential** | Prevents attackers walking exposed while defenders can freely fire. A maneuver team should wait when too much of its support/maneuver element is pinned, while the support team issues a short fire mission at a known/reported position. | Low–medium. Existing `pinned_go`, fire missions, `cover_fire`, BOUND/SUPPRESS and operation stages are the reuse path. |
| Make tactic transitions visible to the player. | **Essential** | “Why are they waiting?” becomes actionable when the selected squad says “supporting”, “bounding to cover”, “repositioning” or “withdrawing: casualties/suppression.” | Low. Current tactic reasons/events/assessment are already stored; expose concise text/icons without noisy markers. |
| Improve candidate quality before expanding behavior count. | **Recommended** | A simple flank/bound is only believable when it finds cover/reachable space and declines a bad route. Favor better scoring/rejection and a short cooldown over more GOAP phases. | Medium. Extend existing `cover_spots`, post planning and flank route checks. |
| Add a clear stalled-assault re-evaluation. | **Recommended** | A squad that has not gained ground, has weak effectiveness or lacks a viable support position should reposition/withdraw, not repeat frontal dashes. | Low–medium. Existing `approach_stall_s`, assault timeout, effectiveness and withdraw logic are direct hooks. |
| Casualty response remains bounded and immediate. | **Recommended** | Losing a leader/fire-team member should reduce aggressiveness and raise regroup/withdraw weight, but not cause every squad to freeze. | Low. Team validation/effectiveness already see fallen members. |
| Full military drill simulation, universal perfect formations, an unconstrained planner, or automatic long retreat chains. | **Avoid** | These add waiting, micromanagement and debugging opacity—the opposite of the design goal. | High complexity, poor pacing. |

## 9. Combat pacing and balance

The current philosophy is mostly aligned: real blockers, weapon roles, positioning, cover, bursts and suppression determine outcomes; bullets do not become arbitrarily weak. GAMEPLAY-05 describes ordinary 100–150 m fights ending in roughly 20–60 seconds, which is a sensible baseline to protect.

| Design lever | Desired effect | Guardrail |
|---|---|---|
| First-shot accuracy and aim settling | Deliberate stationary shots feel trustworthy; initial contact matters. | Do not make rifles randomly inaccurate to stretch fights. |
| Movement and bloom | Sustained fire while moving is less effective, encouraging short moves and support fire. | A moving squad must still remain responsive; never make every contact a hard stop. |
| Suppression | Makes exposed movement risky and creates a reason to seek cover/reposition. | Cap the delay/dwell; a pinned team needs a way to recover, return fire, flank or withdraw. |
| Cover quality | Produces understandable survivability and choices. | Cover should mitigate rather than guarantee safety; head/shoulder exposure is useful readability. |
| Weapon roles | DMR/LMG/launcher create squad-level choices. | Do not make base rifles ineffective merely to sell a specialist weapon. |
| Withdrawal/reposition | Stops suicide loops and explains a lost attack. | Brief, local and visible; not a map-wide chase or a permanent refusal to engage. |

**[Essential] Keep movement speed at 4.5 m/s for this milestone.** Its relationship with open-ground exposure, cover radius, bounding leg length and weapon stability should be measured together in the later implementation pass. The disabled paces system must not be introduced as an isolated animation change.

## 10. Performance and scale

The existing design already follows the right scalable shape: fixed-cadence perception, round-robin LOS budget, spatial grids, local cover candidates, warmth queue, per-frame shot/cover budgets, pooled presentation, and detail-tier-independent simulation. Existing COMBAT-02 measurements indicate it can run large fights without bodies and that prior bottlenecks were addressed.

| Area | Keep | Improve only when profiled | Avoid |
|---|---|---|---|
| Perception | 3 Hz staggered checks, FOV/range prefilter, grid candidates, current target priority, warm cells. | Add exposure score at the same cadence; use an event to prioritize recent muzzle/heard contacts. | Every-soldier/every-enemy per-frame rays; full target sorting. |
| Cover | Local candidate generation, shared trace data, global evaluation budget and reservation. | Cache only short-lived local candidates after a measurement shows the need. | A global pre-baked cover graph for the entire persistent world. |
| Suppression | Shot-segment event drives a nearby spatial query; decay stored on unit. | Bound particles/audio to camera and use LOD for incoming cues. | Per-frame projectile proximity scans for all soldiers. |
| Projectiles/VFX | Analytic hitscan for small arms and pooled, camera-radius visuals. | Use real projectile records only for grenades/rockets or a demonstrable gameplay need. | Every ordinary bullet as a visible physics body. |
| Animation/rendering | Existing character LOD/HLOD/far animation update, proxies and FX radius. | Audit visual contrast and LOD with resolution/FOV; use spatially partitioned instances. | Raising LOD/particle/light quality globally to solve a local readability issue. |

## 11. Proposed implementation phases

These phases are intentionally additive to the present systems. Each phase should be stopped or re-scoped if its validation says the player-visible issue is not real.

### Phase 0 — establish the truth (Essential)

- Add the deterministic 120 m visibility probe and a compact debug capture: LOS blockers/foliage, FOV, candidate/budget/warm state, target/memory/ROE/fire reason.
- Capture the player visibility matrix at 50/100/200/300/500 m in clear, grass-only, tree/brush edge, backlit and overcast conditions using the VISUAL-03 soldier.
- Record current fight timing, first-contact delay, hits, suppression duration, cover choices and tactic transitions in the three short scenarios below.

**Exit criterion:** product/design can identify whether the perceived problem is visual contrast, a specific occluder, FOV/attention, a queue delay, rules of engagement, or a genuine perception gap.

### Phase 1 — visibility and explanation (Essential)

- Correct contrast/backlight/LOD issues found by the matrix without changing the soldier pipeline.
- Tune existing flash/tracer/impact visibility at range; add concise selected-squad contact/tactic explanation.
- If verified, add short-lived RTS contact pips based on known confidence only.

**Exit criterion:** a player can locate meaningful combat at the intended ranges and explain why their squad is firing, seeking cover, waiting, moving or withdrawing.

### Phase 2 — tune existing fire and tactics (Essential)

- Establish per-role handling targets in current weapon resources; retain a predictable first shot.
- Tune current suppression/cover/bound gates for “support, then move,” plus stalled-assault re-evaluation.
- Add only the smallest necessary perception hysteresis/exposure adjustment proven by Phase 0.

**Exit criterion:** attackers do not repeatedly cross open ground under effective defender fire, but fights do not stall into permanent suppression or over-caution.

### Phase 3 — presentation quality (Recommended)

- Replace placeholder weapon sound assets; add distance layers and material-aware impacts.
- Confirm visual fire/reload timing against authoritative events; add restrained incoming-fire cues and hit reactions.

**Exit criterion:** shots, impacts, cover hits and reloads are understandable in both FPS and RTS without excessive HUD.

### Phase 4 — optional depth after proof (Optional)

- Add small exposure/signature confidence (grass/movement/firing), a supported-rest presentation/benefit, and later integrated crouch/prone only when animation, eye/hit geometry, navigation and AI all share the same authoritative state.

**Exit criterion:** each addition improves a demonstrated decision rather than increasing simulation for its own sake.

## 12. Risks and regression controls

| Change risk | Mitigation |
|---|---|
| Raising detection globally erases concealment and makes forest fights instant. | Test clear, grass, forest edge and forest interior separately; modify confidence/local exposure before range. |
| More accurate long-range AI shortens every fight, not just long-range fire. | Validate 50–300 m role tests and time-to-contact/time-to-kill together; do not tune a 300 m miss in isolation. |
| Strong suppression locks units down. | Cap suppression influence, retain recovery/withdraw paths, show the reason, and test a one-sided fortified attack. |
| Tactic changes fight player orders or reveal hidden information. | Preserve authority order and use only contact/soldier knowledge; run save/load, FPS/RTS possession and distant-detail parity checks. |
| Better FX/audio hurts large battles. | Keep camera-radius gates, pooling and distant LOD; profile with the current scale scenario before increasing pool/lighting density. |
| Animation changes desync combat. | Authoritative events remain `CombatSim`/`WorldState`; animation consumes state, never controls damage/ammo. |
| Adding grass concealment makes visual and simulation data disagree. | Derive from the same local vegetation density/height data used to render the field, with explicit debug output and boundary tests. |

## 13. Lightweight validation plan

Do not use long stochastic suites as the first line of validation. Use one deterministic seed per target scenario, short capture windows, and the current debug overlay/log where helpful.

| Test | Purpose | Minimum observations |
|---|---|---|
| Visibility probe: 8 v 8, 120 m | Resolve the VISUAL-03 report. | Pair LOS blockers/foliage, FOV, first sight/shot, target state and fire hold reason; clear vs grass-only vs tree corridor. |
| Open 8 v 8 | Baseline readability and weapon/pacing. | Time to first contact/shot/casualty, shots/hits, cover reactions, fight duration, player screenshot from FPS and RTS. |
| Forest 8 v 8 | Preserve meaningful concealment without permanent deadlock. | Sight pairs, foliage/terrain blockers, reacquisition, hearing/contact behavior, frame/LOS budget. |
| 12 attackers vs 8 fortified defenders | Validate support-before-movement, cover, assault stall and withdrawal. | Fire-mission time, bounds/posts used, exposed movement, pinned fraction, retreat/reposition reason, outcome/time. |
| Role lane at 50/100/200/300 m | Keep weapon roles understandable. | First-shot and short-burst grouping, moving-vs-still effect, settle time, DMR/LMG behavior, player feel note. |
| Regression spot checks | Protect persistent architecture. | Save/load mid-contact, RTS↔FPS possession, body/proxy transition, player order cancels tactic/reaction, no friendly fire. |

For every implementation phase, capture a short before/after video from one fixed camera and one FPS viewpoint, inspect the actual Godot scene, and record the command-line/profile counters already provided by the systems. A result that merely “feels more realistic” but makes the scenario slower, less readable or less responsive should not pass.

## 14. Open design decisions for product-owner approval

1. **Grass concealment:** Should dense tall grass slow AI acquisition in a way that movement/firing can overcome, or remain primarily visual/player concealment? Recommendation: test first; if needed, adopt only a mild acquisition-confidence modifier.
2. **Long-range baseline:** Is the desired standard rifle outcome at 200–300 m closer to intermittent suppressive fire, or a credible chance of single-shot lethality for skilled/settled AI? Recommendation: keep base rifles modest at 300 m and let DMR/optics/rested positions create the distinction.
3. **RTS contact aids:** Are selected-squad, confidence-fading pips acceptable, or should all knowledge stay in world effects and the map? Recommendation: selected-squad-only pips, no permanent enemy markers.
4. **Suppression feel:** Should the possessed player receive only audiovisual nearby-fire cues, or a mild camera/handling response as well? Recommendation: cues first; do not take player aim control away without a separate usability test.
5. **Withdrawal authority:** May autonomous squads withdraw from a locally hopeless fight while defending player interests, or must they always await a direct order? Recommendation: permit short, explained local withdrawal with a clear player override.
6. **Posture scope:** Is crouch/prone a near-term combat feature? Recommendation: defer until it is funded as one integrated state across animation, collision/hits, LOS, cover scoring, navigation and AI—never as an animation-only patch.

## 15. Source and project reference index

### Project sources inspected

- `scripts/core/world_sim.gd`, `world_state.gd`, `unit_state.gd`
- `scripts/combat/combat_sim.gd`, `line_of_fire.gd`, `combat_brain.gd`, `weapon_def.gd`, `combat_fx.gd`, `combat_audio.gd`, `viewmodel.gd`
- `scripts/core/squad_control.gd`, `squad_tactics.gd`, `squad_state.gd`
- `scripts/strategy/war_sim.gd`, `operation_state.gd`, `op_coordination.gd`
- `scripts/units/soldier_body.gd`, `scripts/characters/infantry_character.gd`, `infantry_aim_modifier.gd`
- `docs/COMBAT-01A_REPORT.md`, `COMBAT-01B_REPORT.md`, `COMBAT-02_REPORT.md`, `GAMEPLAY-05_QUALITY_REVIEW.md`, `GAMEPLAY-05B_REPORT.md`, `CHARACTER-01_REPORT.md`

### External technical sources

- [Bohemia Interactive Community — Arma 3 AI Config Reference](https://community.bohemia.net/wiki/Arma_3%3A_AI_Config_Reference)
- [Bohemia Interactive Community — Arma 3 Targeting Config Reference](https://community.bohemia.net/wiki/A3_Targeting_config_reference)
- [Bohemia Interactive Community — Arma 3 Sensors Config Reference](https://community.bohemia.net/wiki/Arma_3_Sensors_config_reference)
- [Arma 3 Dev Hub — SPOTREP #00040](https://dev.arma3.com/post/spotrep-00040)
- [Epic Developer Community — AI Perception](https://dev.epicgames.com/documentation/unreal-engine/ai-perception-in-unreal-engine?lang=en-US)
- [Epic Developer Community — Environment Query System](https://dev.epicgames.com/documentation/unreal-engine/environment-query-system?application_version=4.27)
- [Godot Engine documentation — Mesh LOD](https://docs.godotengine.org/en/latest/tutorials/3d/mesh_lod.html)
- [Godot Engine documentation — Visibility Ranges / HLOD](https://docs.godotengine.org/en/4.1/tutorials/3d/visibility_ranges.html)
- [Godot Engine documentation — Optimizing 3D Performance](https://docs.godotengine.org/en/4.5/tutorials/performance/optimizing_3d_performance.html)

