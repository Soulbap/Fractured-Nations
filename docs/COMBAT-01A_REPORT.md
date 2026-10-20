# COMBAT-01a — Combat core and FPS rifle

Branch `feature/combat-01a`, based on `feature/unit-01a` (d43c954). It follows the research
in COMBAT-TECH-01; the research branch was not merged, its findings were applied directly.
No other worktree was changed, and nothing was merged into `main`.

All results come from scripted runs in the real game: Godot 4.7.2, Jolt, Vulkan,
RTX 3070, 1600×900, on the reference world `ref_20km`. The first-person shots go through
the real input actions (fire, aim, reload, fire mode). **Nobody has play-tested it by hand
yet** (section 7).

## Summary

You can now possess a soldier and fire a rifle:
- semi-automatic and automatic, 700 rounds per minute;
- a 30-round magazine and 120 reserve rounds;
- a 2.4 s reload, R to reload, V to switch fire mode, RMB to aim;
- hits wound or kill other soldiers, friendly fire included.

**How shots are decided.** Every shot is resolved by **one authority, `CombatSim`**,
against **world data and soldier records** (terrain heights, vegetation trunks, structure
boxes, `UnitState` positions). It never uses camera-local physics. That makes the result
identical:
- at 20 m and at 250 m;
- with the camera next to the shooter or 12 km away;
- with or without the target having a physics body.

Physics would have missed the tree and hill cases (§4).

**Interface.** The player and future AI fire through the same call,
`request_fire(unit_id, origin, direction, source)`.

**State.** All weapon and life state is in `UnitState` and runs on simulation time. It
survives Tab, possession changes, long jumps and F5/F9.

**Death.** The soldier stops, leaves its squad's formation and the selection, and becomes
a casualty marker. Dying while possessed returns you to RTS.

**Feedback.** Muzzle flash, tracer, impact puff, hit marker, red-edge damage flash and an
ammo / health HUD. Sounds are temporary synthesised placeholders (§6).

**Performance.** A shot costs 0.25 ms on average (0.82 ms worst) in GDScript. Six seconds
of held automatic fire changed the p99 frame time from 3.34 to 3.44 ms.

## 1. What was implemented

| Part | Files |
|---|---|
| `WeaponDef` resource (static stats only) and the rifle | `scripts/combat/weapon_def.gd`, `assets/combat/rifle.tres` |
| Combat state per soldier in `UnitState` (saved, loaded in place) | `scripts/core/unit_state.gd`, `world_state.gd` (events, `mark_fallen`), `squad_state.gd` (`fallen`) |
| `CombatSim`: fire, spread, reload, damage, death, preview | `scripts/combat/combat_sim.gd` (owned by `WorldSim` like `SquadControl`) |
| `LineOfFire`: authoritative shot / line-of-sight resolution from world data | `scripts/combat/line_of_fire.gd` |
| First-person weapon: input, recoil, aiming field of view, viewmodel | `scripts/units/soldier_body.gd`, `scripts/combat/viewmodel.gd` |
| Effects and audio, local to the camera, pooled | `scripts/combat/combat_fx.gd`, `scripts/combat/combat_audio.gd` (placeholder sounds) |
| HUD: ammo / reserve / mode / health / reload progress, spread crosshair, hit and kill marker, damage flash, death notice | `scripts/ui/game_hud.gd` |
| Death integration: corpse marker, no promotion, no selection, return to RTS | `world_sim.gd`, `detail_manager.gd`, `unit_proxy.gd`, `rts_controller.gd`, `game_controller.gd` |
| Wiring, equipping every soldier, `--combat-test` | `scripts/game/core_demo.gd` |
| Scripted test | `scripts/debug/combat_selftest.gd`, `benchmarks/combat01a/run_test.sh` |

**Rifle (`assets/combat/rifle.tres`, all configurable):**
- 700 rounds per minute, semi and automatic;
- 30-round magazine plus 120 reserve, 2.4 s reload;
- 34 body damage, head ×2.5 (85);
- full damage to 120 m, falling to 60% at 400 m; resolved to 600 m;
- spread: 0.06° aimed and still, +1.2° at walking speed, +0.22° per automatic shot up to
  +1.8°, recovering 4°/s;
- recoil kick 0.55° up and ±0.25° sideways (first person only).

Health is one pool of 100 per soldier.

## 2. Existing functionality reused

- **COMBAT-TECH-01 patterns:**
  - Jeh3no's weapon-resource field set (minus its runtime fields);
  - bukkbeek's try-fire flow (busy → empty → auto-reload → consume → resolve → cooldown),
    on simulation time instead of `Timer` nodes;
  - cluttered-code's zone multipliers and damage / death events;
  - the record-based soldier hit test from the lab (2,999 of 3,000 agreement with Jolt).
- **Godot built-ins:**
  - `Geometry3D.segment_intersects_sphere` / `_cylinder` (soldiers, rocks);
  - `AABB.intersects_segment` (structure boxes in local space);
  - `RandomNumberGenerator` with seeds;
  - `AudioStreamPlayer` / `AudioStreamPlayer3D`, `CPUParticles3D`, `OmniLight3D`.
- **Our data:**
  - `StructureManager`: its cell index (`_index`), records and the same collision boxes
    its physics colliders use;
  - `VegetationStreamer.get_cell_instances`, which already filters construction clearings,
    with collider sizes from the vegetation library (the same as
    `InstanceColliderStreamer`);
  - `Terrain3DData.get_height`, which includes groundwork edits.
- **Existing systems:**
  - possession (`player_controlled`) decides who may fire;
  - `UnitProxy` became the casualty marker;
  - `DetailManager`, `SquadControl` and the RTS needed only one check each for the dead;
  - the F5/F9 world save carries the new fields automatically.
- **The rifle model.** The first-person rifle uses the same part sizes as the carbine in
  `tools/blender/make_soldier.py`. The third-person muzzle is that model's barrel end.

No new dependencies.

## 3. Architecture and integration points

```
SoldierBody (possessed): LMB / R / V / RMB
        |  request_fire(id, eye, view dir, PLAYER)       future AI: request_fire(id, eye, aim, AI)
        v                                                        |
CombatSim (WorldSim.combat) <------------------------------------+
  - controller check: PLAYER only for the possessed soldier, AI only for the others
  - UnitState: alive, mag, reload_until, next_shot_at (sim time), bloom, shot_counter
  - spread from seed (world_seed, unit_id, shot_counter)
  - LineOfFire.trace(origin, end, shooter) -> blocker, distance, hit unit, zone
  - apply_damage once on the target record -> death -> mark_fallen
  - WorldState signals: shot_fired, unit_damaged, unit_died, reload_started / finished
        |
        +--> CombatFX (only near the camera), GameHUD, GameController (possessed death),
             RTSController (selection), WorldSim (body -> casualty marker)
```

**How a shot is resolved (`LineOfFire.trace`), in order:**
1. **Structures.** Every placed module or building in the cells near the line. The line is
   transformed into each instance's local space (also for sheared fences) and tested
   against its collision boxes and stair ramps. A muzzle inside a box is blocked at 0 m.
2. **Terrain.** A height march with 1 m steps near the muzzle and 2 m beyond, adaptive by
   the height above the ground, refined by bisection.
3. **Trees and rocks.** Instances with colliders in 16 m buckets along the line.
   Capsules are tested as vertical cylinders between base and height; rocks as spheres.
   Clearings are respected, and the buckets of cleared cells are dropped on a
   `clearings_changed` signal.
4. **Soldiers.** Living soldiers near the line: head sphere (r 0.14 at 1.62 m) and torso
   capsule (r 0.30, 0–1.50 m); the nearest hit wins. The shooter and the dead are
   excluded.

Physics queries are not used for authority; cost was measured first (§5). Water does not
stop rounds.

**Extension points:**
- `WeaponDef.delivery` (HITSCAN now; PROJECTILE for later ballistics, still through
  `CombatSim`);
- `Source.AI` and `preview_shot()` for COMBAT-01b aim and line-of-fire checks;
- `LineOfFire.clear_line()` for perception.

## 4. Tests

Run with `bash benchmarks/combat01a/run_test.sh combat --shots` (about 5 min). Result:
**PASS** (`benchmarks/combat01a/combat_test.json`).

| # | Scenario | Result |
|---|---|---|
| 1 | Possessed soldier, real input, body shots at 20 / 150 / 250 m | 34.0 / 32.56 / 27.70 per hit; expected 34.0 / 32.54 / 27.69 from the drop-off curve. 2 hits each; at 250 m 2 of 6 shots hit the target, the rest hit a soldier standing on the line (§4 note). The 150 and 250 m targets had **no physics body** |
| 2 | Head and body | head 85.0 (zone HEAD), body 34.0 (BODY) |
| 3 | Self-hit | 0: straight down from the eye stops at the terrain (1.6 m); a shot starting inside the own chest does not hit the shooter |
| 4 | Friendly fire | a squad mate at 20 m loses 34 HP |
| 5 | HESCO, building, terrain, vegetation | tall HESCO stops at 8.94 m; barracks at 8.75 m (physics agrees exactly in both); a hill stops a 525 m shot at 180 m; a trunk stops a 181 m shot at 156 m. **Physics saw no tree at all.** Target HP unchanged in every case |
| 6 | Same, camera 12 km away (no physics near, no bodies) | identical: structure / structure / terrain / tree |
| 7 | 40 seeded shots (1.2° spread) at a target 100 m away, with the camera near (target has a body) and 12 km away (no body) | identical results shot by shot (4 hits of 40) |
| 8 | Ammo, fire rate, reload per soldier | 11 shots in 1.0 s (700 rpm = 11.7); A 19/120 after the burst, B 27/120 after 3; firing during reload refused; reload completes after 2.42 s (30 / 109); B unchanged |
| 9 | Persistence | identical after Tab, possessing another soldier, a 12 km jump (abstract) and back (body), and F5 → change → F9 (health, magazine, reserve, fire mode, reload, shot counter) |
| 10 | Killed soldier | dead, killer recorded, did not move in 2 s, move order refused, not selectable, cannot fire, out of the squad's members and listed among its fallen, no body, casualty marker shown, further hits ignored, name kept |
| 11 | Death while possessed | the game returns to RTS (tactical camera current, mouse released); possessing the dead soldier is refused; Tab stays in RTS; possessing another living soldier works |
| 12 | Sustained automatic fire, 6 s held | see §5 |

**Note on #1.** The two test targets stood on the same bearing, at 150 and 250 m. The
remaining four 250 m shots hit the nearer soldier, who was on the line of fire and died,
as the rules intend. Every death in the run is logged with its killer in the JSON.

**Analytic hits vs physics, near the camera (investigation):**

| Comparison | Agreement | Discrepancies |
|---|---|---|
| Soldiers: analytic head + torso vs the bodies' movement capsule (r 0.35, 0–1.80 m), 2,000 rays aimed at and around bodies, other bodies excluded | 1,655 / 2,000 (698 both hit; 245 physics only; 100 analytic only) | The "analytic only" cases include rays that hit the **terrain collider first**: terrain was not excluded in this run. The exclusion is now in the test but has **not been rerun**. All mismatches lie within 0.35 m of the body axis, the grazing band between the two shapes. The physics capsule is the *movement* shape: wider (0.35 vs 0.30) and taller (1.80 vs head top 1.76), so grazing rays that clip its outer 5 cm or its top count for physics only. This is intentional: hit zones should not be the walking collider, and the analytic model is the authority in both tiers |
| Terrain: 400 grazing lines 0.2–1.5 m above uneven ground, 30–150 m | 400 / 400 | worst distance difference 0.05 m (height-map interpolation vs Jolt heightfield triangles) |
| Structures (HESCO, barracks) | identical distances (8.94, 8.75 m) | none |
| Hill at long range (shot 525 m) | data 180.4 m vs physics 174.8 m | the line skims a ridge almost parallel; both block, at different points along it |
| Trees beyond 40 m | data blocks, physics none | expected: tree colliders only exist within 40 m |

**Edge cases covered:** grazing hits (above); overlapping targets (the nearest soldier on
the line takes the round, #1); self-hits (#3); a blocker immediately in front of the
muzzle (a muzzle inside a box is blocked at 0 m, by code; covered by the "inside own
chest" case for soldiers).

**Regression suites on this branch:** see §8.

## 5. Performance

Possessed soldier in the open meadow, 1600×900:

| Measurement | Value |
|---|---|
| FPS idle (240 frames) | 2.82 ms average, p99 3.34, max 3.37 |
| Holding automatic fire for 6 s (37 shots, one reload, 2,189 frames) | 2.74 ms average, p99 3.44, max 4.16 |
| Shot resolution | 0.25 ms average, 0.82 ms worst, full 600 m line |
| Breakdown of a typical shot | structures 3 µs, terrain 28 µs, trees 150 µs, soldiers 15 µs |
| Effects | 37 shots shown; pools of 24 tracers / flashes / impacts and 12 3D players, no allocation per shot |

The tree bucket walk is the largest cost. It was measured before adding any new caching
system; the existing per-cell instance data is cached in 16 m buckets on first use. It is
fine for one shooter. For COMBAT-01b squads (16 v 16) it should be cut, for example by
stopping at the target distance (AI shots), coarser buckets far out, or per-shot early
exit (§9).

**Before this milestone**, measured with the same scene and method: UNIT-01A FPS in a
squad was 2.42 / 3.52 ms. Today's idle 2.82 / 3.34 ms is from a different view (looking
across the meadow at the forest edge, 1,316 draw calls vs 1,261).

## 6. Feedback, audio and screenshots

**Effects** appear only if the shot starts or ends within 450 m of the active camera;
beyond that, the sound alone plays up to 900 m:
- muzzle flash with a brief light (small at the first-person muzzle);
- a tracer streak along the path;
- an impact puff (dust, or red on soldiers);
- hit and kill ticks for the player;
- 3D gunfire for other soldiers;
- reload clicks.

Abstract or distant shots produce no nodes.

**Audio: temporary placeholders.** `CombatAudio` synthesises the gunshot (crack plus
noise body plus low thump), the reload (three clicks) and the hit ticks at startup. I did
not download sound files, because this environment requires a per-file approval for
downloads. Replacing them is a one-line change per stream in `CombatFX.setup()`.
Suggested CC0 sources to approve:
- Kenney *Impact Sounds* / *Interface Sounds* (CC0);
- freesound.org recordings explicitly marked CC0, for example by searching
  "rifle shot CC0" and "magazine reload CC0".

Record the chosen files' URLs and licences in `assets/combat/LICENSES.md`.

**Screenshots** (`docs/combat01a/`, real Godot frames):

| Required | File |
|---|---|
| FPS rifle use | `c01a_fps_rifle_hit.jpg` (rifle, muzzle flash, tracer, red impact on the target, hit marker, ammo HUD 27/120 SEMI) |
| Visible target and hit feedback | `c01a_fps_rifle_hit.jpg` |
| Shooting around a constructed base | `c01a_shooting_at_hesco.jpg` (automatic fire into tall HESCO; tracer and impact on the wall) |
| Target at longer range | `c01a_long_range_250m_ads.jpg` (aiming, target at 250 m on the crosshair with hit marker) |
| Death / casualty | `c01a_casualty_rts.jpg` (casualty markers, panel shows Sierra's remaining strength), `c01a_casualty_fps.jpg`, `c01a_possessed_death_back_to_rts.jpg` |

## 7. Known limitations and manual testing

**Known limitations:**
- **Presentation is simple.** A box-built first-person rifle with no animations; aiming
  only narrows the field of view and lowers the rifle (no see-through sight); casualties
  are lying grey capsules; the third-person soldier model does not animate firing or
  dying.
- **Hit model.** Upright soldiers only (no crouch or prone). The hit model is a head
  sphere plus torso capsule, separate from the movement capsule (§4). No limbs.
- **Hitscan.** No bullet travel time or drop; fine at these ranges, ballistics later.
- **No penetration.** Thin fences block like walls (chain-link fence included, same boxes
  as physics). Water does not stop rounds; foliage does not, only trunks and rocks.
- **Terrain cliffs.** The adaptive terrain march assumes slopes up to 1.5 rise per metre;
  sharper cliff edges may be stepped over by up to a few centimetres.
- **Corpses.** One marker per casualty, kept forever (no clean-up yet). Dead soldiers keep
  their ammunition (no pickup).
- **Testing switch.** `SoldierBody.require_mouse_capture` is turned off only by the
  scripted test, because its window may not get OS mouse capture.

**Needs manual testing:**
- **Feel:** mouse sensitivity while firing, recoil strength, automatic spread, and how
  hard 250 m shots are with RMB aiming.
- **Capture click:** first click to capture the mouse must not fire; Esc releases it;
  firing starts after the next click.
- **Placeholder sounds:** volume and timing in your speakers (temporary).
- **Effects:** whether the tracer and impact read well in forest and against bases, and
  whether the flash is too bright at night (no night lighting yet).
- **Dying while possessed:** the switch to RTS and the death notice, then possessing
  another soldier.
- **Long sessions:** F5, quit, restart, F9 with casualties present.

## 8. Regression suites on this branch

COMBAT-01a changed shared code: `UnitState` / `WorldState` (fields, save, no orders for the
dead), the `WorldSim` tick, `DetailManager` promotion, RTS selection, possession and the
spawn. Only the suites that cover that code were run. Construction, terrain and vegetation
code was not touched.

| Suite | Result |
|---|---|
| WORLD-CORE-02 `large` (tiers, possession, jumps, orders) | **PASS** |
| UNIT-01A `squad` | **1 failed check out of ~15:** while Alpha stood still for 6 s, its follower Bravo received **1** new move order (limit 0). The walking rate was 8.74 orders / 10 s, within the limit of 12. All other checks passed: selection, line / column, passing, around the base, hold, regroup, blocked report, possession, long jump, save/load and zoom. The same check gave 0 in the UNIT-01A run. Combat code does not touch the follow logic, so this is probably timing at the moment Alpha stops, but it is **not confirmed**: no rerun was made |
| WORLD-BASE-01 `base`, WORLD-INTEGRATION-01 `integration` | **not run** (no change to construction, terrain or vegetation) |

Results are in `benchmarks/combat01a/` (`large_test.json`, `unit_test.json` and logs).

**Follow-up:** rerun `bash benchmarks/combat01a/run_test.sh squad`. If the single standing
order recurs, Follow should skip re-issuing while the followed unit's speed is about zero.

## 9. Recommendations for COMBAT-01b

1. **Perception on `LineOfFire.clear_line`** from the eye to the target's head / torso, at
   2–4 Hz per soldier with a per-frame budget. Cut the tree cost first: stop at the target
   distance, and use bigger buckets beyond 150 m.
2. **AI firing through `request_fire(..., Source.AI)`** with an aim error from distance and
   target movement. `preview_shot()` can reject shots that would hit a friend or a wall.
3. **Rules of engagement on `SquadState`** (weapons free / hold fire). Fallen members are
   already tracked for the RTS panel.
4. **Abstract-tier combat (COMBAT-01c)** needs no new resolver. Records, seeds and data
   occlusion already work without bodies; run the brain at a lower rate.
5. **Audio:** replace the placeholders with approved CC0 recordings before broader
   play-testing.
