# GAMEPLAY-04 — New Game Experience, Military Development & Expanded Arsenal

Branch `develop` (the project standard allows no milestone branches). Commits: `70b19bd` 04B · `486a24b` 04A · `2520adb`
04C · `3beb152` 04D · `aec1700` 04E · `56fd10b` 04G (this report: the playthrough, the planning budget, the second outpost, the opening
grace rule, the New Game economy).
Not pushed. Markers: **[RUN]** measured in a run of the real game on ref_20km; **[CODE]** read from the code; **[NOTE]**
judgement. The two addenda of the brief (combat accuracy; REARM, recovery and discovery) are integrated in 04C and 04B/04D.

## 1. Executive summary

New Game used to start eight soldiers in an empty valley with the nearest enemy 6.8 km away: nothing happened for the first
half hour. Now:

- **The opening is an operation.** A three-line briefing and a small objective tracker; a South fire team holds the
  **Moen checkpoint** 450 m north, in front of the supply cache the squad needs. Five phases - take command, clear the
  checkpoint, secure the cache, establish a command post, plan the development - are checked against the world in any order
  (no script, no spawned enemies), announced once, saved, and can be hidden. Tips teach first person, the map and REARM.
- **Military Development** (F2): 14 projects in three branches built only from what the game can do (a future capability is
  shown and cannot be started). Paid from the stock, timed in simulated seconds, paused without their facility, permanent
  once done, the same rules for the AI factions (a resource-aware policy, no planner). Locked buildings stay in the build menu
  with the development that unlocks them.
- **Five new weapons** (carbine, 7.62 DMR, 7.62 GPMG, 40 mm grenade launcher, 84 mm recoilless rifle) as data on the existing
  weapon architecture, five roles, original Blender assets, loadouts for NATO / RU / CN, AI use per weapon.
- **Combat accuracy** (addendum): the AI's aim now settles - rough on a new target or after moving, steady after the weapon's
  aim time - and depends on the weapon's optic and a per-soldier proficiency; the same rules for every faction; the player
  keeps his own aim. Measured in a new accuracy arena on the real combat code (before / after, §6).
- **You build your arsenal by exploring** (addendum): weapons lie in the world (the checkpoint's stores, caches, an abandoned
  army depot, every fallen soldier). **REARM** (R) collects ammunition and spare weapons into a squad's cargo; handed in at a
  base the type is **registered**, which opens its development / procurement; the **EQUIP** screen issues weapons from the
  cargo (anywhere), the armoury or procurement (at a base).
- **Opportunities** after the introduction - secure a cache, recover equipment, take an enemy post, observe a distant
  position, defend a threatened base - generated from the world, accepted or ignored, paid when achieved either way.
- **Movement fixes found by playing the opening** with the product owner watching: soldiers stuck at the road next to the
  start (eased road shoulders, steeper climbing, a stuck-on-ledge fix, a frozen-path fix) and grazing trunks (more tree
  clearance in the navmesh). NAV-INF regression cases still pass.

Not done / limits are in §12. The first hour was played through the game's own controls from the start screen (§9).

## 2. Implementation assessment (what existed, what was added)

| Need | Existed | Added (owner) |
|---|---|---|
| New Game start | `ScenarioDef`, `SandboxSetup.create`, caches, `EconomyHud.next_hint` | scenario `extra_objectives`, `structures`, `stashes`, `intro`, `briefing`; `IntroGuide` (WarSim); `ObjectiveTracker` (HUD) |
| Progression | none (every building open) | `DevelopmentDef` data, `MilitaryDevelopment` (WarSim.dev), `FactionState.dev`; F2 `DevelopmentPanel`; locks in construction, AI building, equipment |
| Weapons | `WeaponDef`, `InfantryRole`, `SquadComposition`, `CombatSim`, CombatBrain support weapons | 5 WeaponDefs, 5 roles, 3 compositions; handling / procurement / discovery fields; GL in CombatBrain; per-weapon reach and optics |
| Accuracy | per-shot AI aim error (distance, movement, suppression), weapon spread, reaction delay | aim settling (`UnitState.aim_since`), `UnitState.proficiency`, `WeaponDef.aim_time_s / aim_mult` |
| Equipment / loot | `FactionState` stock, `Inventory` | `SquadEquipment` (WarSim.equip): `WarState.stashes`, `SquadState.cargo`, `FactionState.armory / discovered`; REARM; EQUIP screen |
| Missions | operations (AI), caches | `Opportunities` (WarSim.opps) |
| Navigation | NAV-INF-01 (one grade limit, step-up) | `RoadShoulders` (terrain, memory only), `WorldSim.slope_speed`, `SoldierBody._hop_ledge`, straight fallback, tree clearance |

No second simulation, controller, weapon system, inventory simulator or navigation system was added; every new owner is
listed in CLAUDE.md.

## 3. New Game opening (04A)

| | |
|---|---|
| Start | one North squad of eight at (−1350, 6870), 444 m south of the checkpoint (out of the 400 m sight range); 800 kg supplies, 200 kg ammunition |
| Moen checkpoint | `extra_objectives`: South outpost, radius 70, `hold` 1 (South's AI keeps its fire team there), a guard checkpoint structure; 3 riflemen (composition `riflemen`) |
| Moen farm cache | 1200 kg supplies, 250 kg ammunition, 65 m behind the checkpoint (value 2 once captured: 60 kg/min): outside the fire team's reach to secure it, inside the 80 m that keeps anyone else from securing it while they live (`a_cache_safe`) |
| Checkpoint stores | a stash: 1 carbine, 40 kg ammunition (the first find) |
| Verket roadblock | a second South post (4 soldiers incl. a light MG, sandbag position) 70 m in front of the Verket yard cache with its DMR: the natural next fight |
| Phases | command (moved 40 m) · checkpoint (no enemy within its radius + 40 m) · supplies (the farm cache secured) · foothold (a base) · develop (a project started); optional tips: first person, map, REARM |

Design choices: a fire team of three without fortification after measurements - four riflemen in a fighting
position killed the whole squad in one run of three (the fight is decided in ~20 s at 150 m over open ground); three in
the open lose (7/8 and 8/8 survivors). The tracker is the only guide during the introduction (the early-game hints resume
after it). Skipping guidance (×) hides it; the world does not depend on it.

## 4. Military Development (04B)

| Branch | Project | Needs | Cost / time | Enables |
|---|---|---|---|---|
| Base & Logistics | Field Command | initial | – | command post, supply depot, guard towers, fighting positions, MG emplacement, HESCO, sandbags |
| | Barracks & Personnel | Field Command, operational command post | 300 kg / 2:00 | barracks, barracks module, medical station |
| | Supply Infrastructure | Field Command, supply depot | 250 kg / 1:40 | ammunition magazine (armoury), fuel point, fuel bladder, container yard, vehicle parking |
| | Workshop & Maintenance | Supply Infrastructure, supply depot | 450 kg + 60 ammo / 3:00 | repair bay, vehicle depot |
| | Advanced Base Facilities | Barracks, Workshop, 2 objectives held, command post | 900 kg / 5:00 | fighting bunker, tall HESCO, T-wall, covered MG position |
| Infantry & Weapons | Standard Infantry | initial | – | rifle, LMG, grenades, light launcher |
| | Infantry Equipment Expansion | Standard, supply depot | 250 kg + 120 ammo / 2:00 | 40 mm grenade launcher (grenadier (40 mm)) |
| | Marksman Specialization | Equipment, **DMR discovered**, 1 objective captured, supply depot | 350 kg + 150 ammo / 2:30 | DMR (marksman) |
| | Advanced Support Weapons | Equipment, Supply Infrastructure, **GPMG discovered**, ammunition magazine | 500 kg + 250 ammo / 3:30 | GPMG (heavy gunner) |
| | Heavy Infantry Support | Advanced Support, Workshop, **84 mm discovered**, repair bay | 700 kg + 300 ammo / 4:30 | recoilless rifle (anti-structure gunner) |
| Operations & Intelligence | Basic Operations | initial | – | squad tactics, garrisons, operations |
| | Reconnaissance Capability | Basic, command post | 200 kg / 2:00 | reports reach the faction in 40 % of the time (IntelSim); reconnaissance opportunities |
| | Improved Command Infrastructure | Reconnaissance, Barracks, 1 objective held, command post | 500 kg + 80 ammo / 3:20 | headquarters building; two projects at once |
| | Expanded Operational Coordination | – | – | **future**: shown, cannot be started |

The compact carbine needs no project: registered (one delivered to a base), it can be procured. Knowledge is permanent;
a project's facility only gates its progress (paused, with the reason on the card). AI factions start with the
developments of their start base (scenario rule, documented in `new_game.tres`) and their own weapon types; their policy
starts the cheapest startable project of the profile's preferred branch when it leaves 1500 kg (`b_ai`: South started
Infantry Equipment, East Advanced Base Facilities). The Development Scenario keeps everything open (`b_dev_off`).

## 5. Arsenal (04C)

| Weapon | Role | Key data | Tactical role |
|---|---|---|---|
| Rifle 5.56 (existing) | rifleman | 700 rpm, 30+120, aim 0.8 s | general purpose |
| Compact carbine 5.56 | carbineer | 850 rpm, 30+120, falloff 80–300 m, moving spread 0.75°, aim 0.5 s, AI reach 250 m | close and on the move; does not engage at 300 m |
| Marksman rifle 7.62 | marksman | semi, 20+80, 58 dmg, optic (sight 650 m), aim factor 0.4, aim 1.6 s, reach 650 m | precise at range; takes the farthest-seeing post |
| Light MG 5.56 (existing) | machine gunner | 750 rpm, 100+300, braced | suppression |
| GPMG 7.62 | heavy gunner | 650 rpm, 200+400, 46 dmg, suppression ×3, braced ×0.35, moving ×3.5, carrier speed ×0.8 | heavier suppression, slow, needs a position |
| 40 mm grenade launcher | grenadier (40 mm) | secondary, 6 rounds, burst 5 m / 110, comes down where aimed, 350 m | explosive rounds at seen enemies in cover or groups; friend checks; last rounds kept |
| 84 mm recoilless | anti-structure gunner | secondary, 4 rounds, burst 5.5 m, 950 vs structures, 400 m | fortifications at range |
| Light AT launcher (existing) | grenadier | 2 rockets, 260 m | unchanged |

Sidearms: evaluated and not added (no second-weapon slot for a rifle and a pistol at once without a weapon-switch rework;
the brief puts primaries first). Blender (`tools/blender/asset_production/characters/build_gameplay04_weapons.py`, source
`assets/characters/infantry/blender/gameplay04_weapons.blend`): DMR 5432/1628/262 tris, GPMG 2416/724/122, 40 mm launcher
684/204/57 (+ hip copy), 84 mm 684/204/58 (+ back copy); the CHARACTER-01 carbine is reused. Previews rendered and looked at
(hands on grip and handguard, hip and back placement); in Godot: first person `docs/gameplay04/c_fps_dmr.png`,
`c_fps_gl40.png`, `c_fps_recoilless.png`, third person `c_third_person_roles.png`; bodies and far proxies refresh their look
when a soldier is re-equipped (`c_visual`: all eight roles wear their loadout).

## 6. Combat Accuracy & Weapon Handling Assessment

### 6.1 Existing mechanics discovered [CODE]
| Area | Before GAMEPLAY-04 |
|---|---|
| Target detection | CombatBrain perception 3 Hz, line of sight against terrain / vegetation / structures, 150° field of view, 400 m sight, hearing 150 m |
| Reaction time | on acquisition only: 0.45 s + distance + suppression (`aim_ready_at`) |
| Aiming | one Gaussian aim error per shot: (0.25° + 0.20°/100 m) × braced factor + 1.2° × own speed × weapon factor, × (1 + 2.2 × suppression); no settling: the first shot as good as the tenth |
| Accuracy | aim error (AI) + weapon spread (base, bloom, moving, braced) for AI and player alike; deterministic per seed |
| Range | damage falloff per weapon; one engage range (350 m) and sight range for every weapon |
| Movement | own speed in aim error and spread; target speed through a 0.2 s tracking lag |
| Suppression | degrades aim and acquisition, heads down, tactics (it is not only a decision input) |
| Handling | rpm, magazine, reload, bloom, recoil (first person), AI bursts by distance |
| Friendly fire | friends near the line: shot preview and a 0.5 m margin; grenades / rockets keep friends out of the blast |
| Near / far | one resolution on the records (CombatSim / LineOfFire); effects only differ |

Missing: settling, soldier skill, weapon-specific reach and optics.

### 6.2 Implemented (targeted) [CODE, RUN]
- **Aim settling**: `UnitState.aim_since` (set on acquisition) with `moved_at`; aim error × `aim_first_mult` (2.0) on a fresh
  aim, falling to `aim_settled_mult` (0.9) over the weapon's `aim_time_s`. Computed when a shot is aimed: no per-frame state.
- **Proficiency**: `UnitState.proficiency` (saved, 0.5 for everyone unless a scenario sets it): aim error × (1.35 − 0.7 p),
  settling time × (1.4 − 0.8 p). A property of the soldier, never of a faction.
- **Weapon properties**: `aim_mult` (optic: DMR 0.4, carbine 1.15, GPMG 1.1), `ai_engage_m`, `optic_sight_m`,
  `move_speed_mult`; the weapon's mechanics are the same whoever holds it.
- **Player**: first person uses the weapon's spread only (`c_fps`: 10/10 DMR hits at 50 m); suppression still darkens the
  screen as before.
- `--legacy-aim` switches the model off for comparison.

### 6.3 Deferred [NOTE]
- Suppression strength (a soldier at 0.7 suppression hits nothing at 100 m in both models): a GAMEPLAY-02 balance value;
  not changed without a balance pass.
- Rifle reach: 0–2.5 % at 200–300 m for a standing target (the distance term of the aim error); unchanged to keep the
  GAMEPLAY-02/03 balance; the DMR now fills that role.
- Ballistics (drop, flight time) and stance: the `PROJECTILE` extension point exists; not needed for this milestone.
- Proficiency growth (experience): no RPG system; scenarios may set it.

### 6.4 Accuracy arena
`--gameplay04-test --only c_arena [--legacy-aim]`: one AI shooter, one target that holds fire and never dies (hits counted
from `shot_fired`), squad tactics off, open level ground with a clear line from 50 to 500 m, far tier, seeds 1–3, 12 s per
run. Before = `--legacy-aim` on the same build (the new weapons' data with the old aim model), after = GAMEPLAY-04C.

| case | hit % (before → after) | shots | first hit (s) | friendly hits | friendly holds |
|---|---|---|---|---|---|
| carbine 100 moving shooter | 2.6 → 1.3 | 78 → 79 | 10.9 → 10.1 | 0 → 0 | 0 → 0 |
| carbine 300 | 4.8 → 0.0 | 21 → 0 | 7.7 → -1.0 | 0 → 0 | 0 → 0 |
| carbine 50 | 61.2 → 57.4 | 98 → 101 | 2.2 → 1.8 | 0 → 0 | 0 → 0 |
| dmr 100 | 16.7 → 64.6 | 48 → 48 | 4.0 → 1.9 | 0 → 0 | 0 → 0 |
| dmr 300 | 0.0 → 13.6 | 22 → 22 | -1.0 → 3.6 | 0 → 0 | 0 → 0 |
| dmr 500 | 0.0 → 6.7 | 0 → 15 | -1.0 → 6.4 | 0 → 0 | 0 → 0 |
| gpmg 100 moving shooter | 5.9 → 2.0 | 136 → 152 | 10.9 → 11.3 | 0 → 0 | 0 → 0 |
| gpmg 300 | 5.6 → 5.6 | 54 → 54 | 5.4 → 5.0 | 0 → 0 | 0 → 0 |
| lmg 100 | 30.1 → 30.7 | 163 → 163 | 2.2 → 2.8 | 0 → 0 | 0 → 0 |
| lmg 100 moving shooter | 7.1 → 10.8 | 126 → 65 | 9.8 → 11.0 | 0 → 0 | 0 → 0 |
| lmg 300 | 0.0 → 0.0 | 56 → 58 | -1.0 → -1.0 | 0 → 0 | 0 → 0 |
| rifle 100 | 16.1 → 20.5 | 87 → 88 | 3.0 → 2.7 | 0 → 0 | 0 → 0 |
| rifle 100 friend near line | 9.5 → 8.1 | 42 → 37 | 2.3 → 1.7 | 0 → 0 | 27 → 38 |
| rifle 100 moving shooter | 6.5 → 2.6 | 77 → 78 | 5.2 → 11.3 | 0 → 0 | 0 → 0 |
| rifle 100 moving target | 8.0 → 11.2 | 88 → 89 | 2.4 → 4.6 | 0 → 0 | 0 → 0 |
| rifle 100 recruit | – → 17.0 | – → 88 | – → 2.4 | – → 0 | – → 0 |
| rifle 100 suppressed | 0.0 → 0.0 | 44 → 50 | -1.0 → -1.0 | 0 → 0 | 0 → 0 |
| rifle 100 veteran | – → 32.2 | – → 87 | – → 3.0 | – → 0 | – → 0 |
| rifle 200 | 2.4 → 2.5 | 41 → 40 | 2.3 → 2.4 | 0 → 0 | 0 → 0 |
| rifle 200 recruit | 2.7 → – | 37 → – | 4.6 → – | 0 → – | 0 → – |
| rifle 200 veteran | 2.9 → – | 34 → – | 8.4 → – | 0 → – | 0 → – |
| rifle 300 | 0.0 → 0.0 | 22 → 21 | -1.0 → -1.0 | 0 → 0 | 0 → 0 |
| rifle 300 moving target | 0.0 → 0.0 | 20 → 21 | -1.0 → -1.0 | 0 → 0 | 0 → 0 |
| rifle 300 recruit moving target | 0.0 → 0.0 | 21 → 21 | -1.0 → -1.0 | 0 → 0 | 0 → 0 |
| rifle 50 | 60.0 → 61.3 | 105 → 106 | 1.0 → 1.1 | 0 → 0 | 0 → 0 |

CombatBrain per frame: 541.8 → 552.3 µs

Reading: close range and LMG unchanged; a settled rifle a little better at 100 m (16 → 20 %); moving shooters worse
(their aim restarts); the DMR now does what it is for (100 m 17 → 65 %, 300 m 0 → 14 %, engages at 500 m); the carbine
keeps out of long fights; recruits and veterans differ (17 % vs 32 % at 100 m; an earlier series gave 8 % vs 50 % - three
seeds move single cases by ±7 points). No friendly hits in any case; the shooter held 38 shots with a friend near the line.

### 6.5 Suppression, friendly fire, near / far, cost
- Suppression on the target: 1.0 for every weapon at 100 m; the GPMG reaches it at 300 m where the rifle gives 0.15.
- Friendly fire: 0 friendly hits in 23 cases; grenade launcher holds with a friend 6 m from the impact (`c_gl`).
- Near / far: one resolution path (unchanged); the opening fight, the arena (far) and `c_gl` / `c_recoilless` (near)
  run the same rules; `c_carry` measures the GPMG's slowness in the far tier (17.7 s vs 14.1 s on 60 m), the body applies
  the same factor.
- Cost: CombatBrain 541.8 → 552.3 µs per frame in the arena (+2 %); the aim settling is two multiplications per shot.

### 6.6 Balance check
`--combat03-test --only d_open,d_village --seeds=1,2,3` with all GAMEPLAY-04 changes against the GAMEPLAY-03 final series:
open outpost attacker losses 44 → 36 % (3/3 taken), village 21 → 43 % (2/3 taken). The two move in opposite directions and
inside the noise GAMEPLAY-03 recorded for the village (4–54 %): no systematic shift to attack or defence.

## 7. Equipment, REARM and discovery (04D)

- **Places a weapon can be**: on a soldier, in a squad's cargo (`SquadState.cargo`, one per two soldiers, at least two), in
  the world (`WarState.stashes`), in the faction's armoury (`FactionState.armory`). Nothing is created on the way.
- **REARM** (R / button): the squad walks there (ordinary move), searches 6 s while not under fire (it waits in a fight:
  `d_rearm` found this at the checkpoint), tops up its soldiers' ammunition, grenades and secondary rounds (stash first, then
  its base's stores) and takes spare weapons, unknown types first; specialists are never swapped; any order cancels it.
- **Delivery and discovery**: cargo inside an own base with an operational supply depot goes to the armoury; an unknown type
  is registered (message "Discovery registered: … - Marksman Specialization can now be developed").
- **EQUIP**: per soldier, a role and how it would be met - ready (cargo / armoury / carried), procure (price), locked (what
  unlocks it), unavailable (why). Found weapons are usable without research; a procured one needs the discovery, its
  development and its facility. Old weapons go to the armoury, the cargo or the ground. At most 2 LMG, 1 GPMG, 2 marksmen,
  2 grenadiers of each kind, 2 AT gunners per squad.
- **The fallen** leave their weapons and half their ammunition (merged within 15 m, at most 150 such stashes).
- **World finds (New Game)**: checkpoint stores (carbine), Verket yard cache (DMR), Sørmoen cache (two 40 mm), South Bridge
  cache (GPMG), an abandoned army depot (GPMG, 84 mm); South knows DMR and GPMG, East carbine, GPMG and 84 mm (their AI
  squads field them through `ai_compositions`, `c_ai_comp`).
- Checks: `d_setup, d_rearm, d_field_equip, d_deliver, d_procure, d_fallen, d_persist, d_ui` PASS (save / load restores
  stashes, cargo, armoury and discoveries exactly; a REARM after the save does not survive the load).

## 8. Opportunities (04E)

Generated every 30 s after the introduction, at most four open: defend (a base the faction was warned about), secure (a known
cache), recover (known equipment), take (an enemy post within 4 km), observe (an enemy position 3–9 km away with no report
near it - only with Reconnaissance). Complete when the world says so; rewards 100–300 kg supplies / ammunition through
`faction_deposit`, accepted or not. The tracker shows them with Accept / ×. Checks: `e_offer` (Secure Moen farm cache,
Take Moen checkpoint; no soldier created), `e_complete` (+400 / +100), `e_recon` (Observe Østby, done after watching),
`e_persist`, `e_ui`. The defend opportunity needs a real enemy report near a base and was not provoked by a test.

## 9. The first hour, played [RUN]

`Godot --fullscreen … -- --menu-shot --gameplay04-test --shots --only g_playthrough`: New Game pressed on the start screen,
then the brief's twenty steps through the game's own controls (RTS selection and orders, the map, first person, the
construction tool's cursor, F2, the barracks' panel button, the EQUIP screen, F5 / F9), simulated time compressed on walks
and waits. Screenshots 1920×1080 in `docs/gameplay04/g*.png`. The run was made three times; the first two found design
problems that were fixed before the third (§9.2).

### 9.1 Final run (all 20 steps PASS)

| # | Step | Game time | Note |
|---|---|---|---|
| 1–2 | New Game from the start screen; briefing and first objective | 0:04 / 0:07 | `g01_start` |
| 3 | squad selected and moved (first objective done) | 0:17 | first meaningful action at **0:07** |
| 4–6 | first person, back, the map | 0:19–0:21 | `g04_first_person`, `g06_map` |
| 7 | first encounter: Moen checkpoint cleared by an assault ordered from the tactical view | 2:16 | first shot **0:24**; 7 of 8 alive; `g07_first_encounter` |
| 8 | farm cache secured, REARM at the checkpoint stores | 3:35 | first reward **3:15** (+1200 kg); carbine + 3 rifles in the cargo |
| 9 | Command Post placed with the cursor, built by the squad | 4:51 | first construction |
| 10 | F2, Barracks & Personnel started | 4:52 | `g10_development` |
| 11 | development complete, supply depot built; carbine handed in and registered | 6:52 | first unlock **6:52**; discovery at the same moment |
| 11b | guard tower and two fighting positions (the hint asks for them before the barracks) | 8:29 | 1010 kg left after building them |
| 12 | barracks (unlocked) built | 10:09 | |
| 13 | squad recruited | 11:12 | |
| 14 | registered carbine issued to a recruit on the EQUIP screen | 11:15 | first new weapon **11:15**; `g14_equipment` |
| 15 | opportunity accepted: Take Verket roadblock | 11:38 | recruits garrison the base; the first squad refilled at the barracks |
| 16 | second encounter: the roadblock taken by one squad | 21:52 | 10 min march and fight; both squads at full strength afterwards; base held; `g16_second_encounter` |
| 17–19 | F5, F9, orders after loading | 21:54–21:56 | developments, discoveries, armoury, intro, opportunities identical |
| 20 | the sandbox goes on | 23:56 | three opportunities open; income 90 kg/min; `g20_sandbox` |

Travel and waiting: of the 24 minutes about 12 were marches (the checkpoint 2 min, the roadblock ~9 min with its
fight), about 3 waiting for builders, about 2 waiting for supplies (the barracks), the rest decisions and fights. The longest
stretch without a decision is the march to Verket.

### 9.2 What the earlier runs found (and what changed)

| Run | Finding | Change |
|---|---|---|
| 1 | The command post stands inside the checkpoint's radius, so the base is linked to that objective; South's reinforcement, sent when the player attacked the checkpoint at minute 2, arrived at minute 26, found the post in North hands and counter-attacked: **the base was lost** 43 s after the warning, with its stock, while both squads were 1.4 km away. 10 minutes of waiting for supplies before the recruit. | Opening grace rule `ai_grace_s` (New Game 40 min: no AI *attack* on what the player holds; the war between the AI factions, their expansion and defence go on; a reinforcement answering the player's own attack still comes, warned) |
| 2 | The reinforcement came again at minute 25; this time warned 70 s ahead ("Possible attack on Moen checkpoint: about 9 enemy within 290 m"), a Defend opportunity was offered, **the base held**. But South's AI had meanwhile turned the Verket roadblock into a fortified Forward Outpost (command post, two fighting positions, guard tower, sandbags, two squads) and the second attack failed. The product owner (watching): "not enough resources to fortify anything before the counter-attack". | Scenario outposts (`kind outpost`) are no AI expansion sites. New Game economy: start 800 kg / 200 kg ammunition (was 500 / 120), farm cache 1200 / 250 (was 900 / 150), checkpoint value 2 (60 kg/min held), ammunition income 15 per value (was 12); the fortify hint comes right after the depot and names the threat |
| 3 | All steps PASS (§9.1). | – |

### 9.3 Player-experience measurements (final run)

| Measure | Time |
|---|---|
| first meaningful action | 0:07 |
| first combat (first shot) | 0:24 |
| first resource reward | 3:15 |
| first construction (Command Post finished) | 4:51 |
| first development unlocked | 6:52 |
| first new weapon usable (registered carbine issued) | 11:15 |
| second combat encounter won | 21:52 |

Points of confusion / waiting found: the earlier economy left no room to fortify (fixed); losing the base to an
unseen counter-attack at minute 26 (now later and warned); the walk to Verket is long for an inexperienced player; a captured
South forward store keeps its name ("South base 2" owned by North); one recruit of a garrison stood "BLOCKED" on its way to
a post (`g20`); fallen soldiers' stashes are many after a fight and their labels overlap in the tactical view.

## 10. Performance

| | GAMEPLAY-03 final | GAMEPLAY-04 |
|---|---|---|
| Development Scenario `smoke_dev` (120 s ×4): SquadTactics step avg / max | 901 µs / 5.5 ms | 870 µs / 6.3 ms |
| per tick: brain / tactics / war | 538 / 30.0 / 26.8 µs | 527 / 28.8 / 34.6 µs |
| Accuracy arena, CombatBrain per frame | – | 541.8 → 552.3 µs (legacy → new aim) |
| RoadShoulders at game start | – | 11.2 s first run (1 527 045 vertices), 0.67 s from the cache |
| A judged DEFEND plan | ~12 ms | 5.2 ms (fighting area) – 13.4 ms (whole base) |

The DEFEND spike: plans were already spread by squad id for garrisons; squads choosing a defence on their own could still
plan together. Now at most one such plan per tactics step (`defence_plans_per_step`); the rest one step (0.5 s) later; the
player's and operations' orders are never deferred (`g_defend_spike`: one plan per step, all three squads defending). A single
plan still costs 5–13 ms (§12).

## 11. Tests run (targeted, per change)

| Change | Checks | Result |
|---|---|---|
| 04B development | `--gameplay04-test --only b_lock,b_start,b_pause,b_persist,b_complete,b_future,b_ui,b_ai` | PASS |
| 04A opening | `a_setup, a_cache_safe, a_ui, a_phases, a_persist, a_skip, a_shoulders`; `a_encounter` alone (several runs); `a_road`, `a_trees`, `a_profile` (movement) | PASS |
| Movement (shared) | `--nav-inf-test --only navinf_02,navinf_04` | PASS near and far (after bounding the straight-walk fallback) |
| 04C arsenal | `c_gl, c_recoilless, c_carry, c_fps, c_persist, c_ai_comp, c_visual`, `c_arena` (both models) | PASS |
| Balance | `--combat03-test --only d_open,d_village --seeds=1,2,3` | PASS (§6.6) |
| 04D equipment | `d_setup, d_rearm, d_field_equip, d_deliver, d_procure, d_fallen, d_persist, d_ui` | PASS |
| 04E opportunities | `e_offer, e_complete, e_recon, e_persist, e_ui` | PASS |
| Development Scenario regression | `--scenario=dev --gameplay01b-test --only a_dev,smoke_dev` | PASS |
| 04G | `g_defend_spike` (one plan per step, 2 deferred in the playthrough); `g_playthrough` three runs (§9) | final run PASS |

No full suite was run. Tests are narrow by the product owner's instruction during this milestone (one check, one property,
state set directly instead of waiting through a process). GAMEPLAY-01B `a_new` was updated for the opening (an enemy
444 m away is intended now).

## 12. Known limitations

1. **Road shoulders change the terrain in memory** at every start (not in the world files): roads built by the player get
   the construction groundwork, not this easing; very steep cuts keep a slope beyond the 14 m band.
2. **A single defence plan costs 5–13 ms** (judged posts with exposure); spreading is done, making one plan cheaper is not.
3. **Rifles at 200–300 m** hit 0–2.5 % against a standing man (unchanged GAMEPLAY-02 model); the DMR is the long-range
   answer. **Heavily suppressed soldiers** hit nothing (unchanged).
4. **No proficiency growth**: everyone is 0.5 unless a scenario sets it.
5. **AI factions do not REARM** or collect equipment; their dead do drop theirs.
6. **The 40 mm round flies straight to the point it was aimed at** (no arc): it cannot be lobbed over a wall.
7. **A captured AI store keeps its name** ("South base 2" owned by North); a garrison recruit may stand BLOCKED short of
   its post; many fallen-equipment labels overlap after a fight.
8. **The opening grace (40 min) is a scenario rule**: after it the AI factions may attack the player's base like any other;
   a reinforcement answering the player's own attack is not held back by it.
9. **Distance LOD of new loadouts**: a figure can be missing for a frame when its merged far mesh is first built.
10. **Defend opportunities** were exercised in the playthrough (run 2: offered before the attack, completed when it
   ended) but not by a narrow test (they need a real enemy report near a player base).
11. The GAMEPLAY-03 `c_flank` failure and the exit access violation remain as documented there.
12. Audio is still the synthesized placeholder set; the new weapons reuse rifle / MG / launcher sounds.

## 13. Recommendations

1. **A short manual playtest of the first hour** by the product owner: the opening's numbers (fire teams, costs, project
   times) are tuned by measurement, not by feel.
2. **Cheaper defence plans** (exposure checks cached per area and threat direction across squads).
3. **AI salvage**: AI squads REARM at stashes near them after a fight (uses the same SquadEquipment calls).
4. **Lobbed 40 mm** (an arc with the existing explosive records) and recorded weapon audio for the new weapons.
5. **NAVIGATION N1** remains the next roadmap milestone; the road-shoulder easing and slope rules make the near tier's
   off-road movement more forgiving but do not replace it.
