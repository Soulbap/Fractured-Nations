# INTEGRATION-02 — Unified sandbox and character

Branch `feature/unified-sandbox`, created from `feature/world-sandbox-01b` (`b56f3cb`) with
`feature/character-01` (`2935d40`) merged in (merge base: WORLD-CORE-02, `ba5a952`). The old
branches and all their worktrees are untouched; nothing was merged into `main`. The work was
done in its own worktree, `fractured-nations-unified`.

All numbers come from scripted runs of the real game: Godot 4.7.2, Jolt, Vulkan, RTX 3070,
1600×900, `ref_20km`. Screenshots in `docs/integration02/` are captures of the running
unified game.

**Nobody has play-tested this by hand yet.** The runs show that the pieces work together, not
how the game feels.

## 1. Approach

WORLD-SANDBOX-01B is the authoritative foundation. CHARACTER-01 diverged from WORLD-CORE-02,
so it only touches soldier presentation: 205 files, of which only 7 overlap the sandbox's
changes. The overlap was resolved by hand, then the seams between the two were checked in
the running game, because a clean merge does not show that soldier visuals, combat and the
first-person view agree.

### Conflicts resolved

| File | Conflict | Resolution |
|---|---|---|
| `scripts/core/unit_state.gd` | `to_dict` / `from_dict`: COMBAT-01/02 added many persisted fields, CHARACTER-01 added `loadout` | Both: the combat fields and `loadout` are persisted |
| `scripts/debug/core_selftest.gd`, `large_world_selftest.gd` | Sandbox: `brain.enabled = false` for old tests; CHARACTER-01: `--shot-dir=` argument | Both kept |
| `.gitignore` | Both added a `__pycache__` entry | The sandbox block (it already contains it) |
| `README.md` | Two different "current state" paragraphs | Sandbox state first, CHARACTER-01 paragraph kept, stale WORLD-CORE-01 line dropped |
| `soldier_body.gd`, `unit_proxy.gd` | Auto-merged | Reviewed by hand: character set-up in `bind()` composes with the sandbox's body life-cycle |

### Seams found and fixed (not visible as conflicts)

1. **Save/load lost the loadout of existing soldiers.** `WorldState.apply_snapshot` updates
   living units in place and copied every field except `loadout`. A soldier that existed when
   F9 was pressed kept whatever it had; the saved kit was ignored. It now copies `loadout`
   (`world_state.gd`). Test: loadouts of the squad were blanked, F9 pressed, all 133 soldiers
   came back with the saved kit.
2. **Shots left from a hardcoded offset of the old placeholder carbine**
   (`Vector3(0.03, 1.22, -0.80)`). `SoldierBody.muzzle_position()` now uses the muzzle mount
   of the weapon the character actually holds (`InfantryCharacter.muzzle()`, the weapon's
   `ATT_Muzzle` node). Weapon changes, other weapons and future vehicles' crew weapons need no
   offset tables.
3. **The first-person rifle was a separate box-model carbine** built to match the old
   placeholder. `Viewmodel` now instances the possessed soldier's own weapon pieces (carbine,
   optic, foregrip: the same assets and materials the third-person character carries), so
   first and third person show the same weapon. The box code is gone. The muzzle flash and
   tracer start at the weapon's `ATT_Muzzle`.
4. **The optic could not be looked through.** The red-dot's tube is a solid cylinder, so ADS
   showed a black disc. In the first-person view the faces across the bore are discarded by a
   small shader on the optic housing and the lens is nearly clear; the aim is centred on the
   optic. The third-person model is unchanged.
5. **Crouch had no gameplay input** (CHARACTER-01 limitation). Soldiers whose COMBAT-02
   tactic is `IN_COVER` now crouch (`character.crouched` follows `unit.tactic`), from existing
   record state; no new system.

Nothing was duplicated: there is still one soldier controller (`SoldierBody`), one combat
implementation, one movement implementation. Characters are a representation chosen in
`SoldierBody.bind()`; distant units keep `UnitProxy` with the loadout's single-surface proxy
mesh.

## 2. What is integrated

- WORLD-SANDBOX-01B complete: three-faction war, strategic map, operations, RTS, FPS,
  combat (COMBAT-01a/01b/02), squads (UNIT-01A), construction (WORLD-BASE-01), persistence.
- CHARACTER-01: modular infantry on one rig (loadouts A standard, B heavy, C recon),
  animation clips, carbine with optic and foregrip, proxy and LOD meshes, Blender build
  scripts in `tools/blender/character/`, standard in `docs/CHARACTER_STANDARD.md`.
- INTEGRATION-02 test scenario `characters` in `scripts/debug/sandbox_selftest.gd`.
- `CLAUDE.md`: branch workflow, architecture principles and the testing policy.

## 3. Tests and visual validation

Policy: change-impact testing, no full suite. Changed: `SoldierBody`, `Viewmodel`,
`InfantryCharacter`, `UnitState` persistence. Chosen: the new `characters` scenario, the
sandbox scenarios that cover those paths (`transitions`, `map_fps`, `persist`), and `perf`
(frame times). Not run: war simulation, map UI, operations, construction, navigation, combat
AI — none of that code changed.

| Run | Result |
|---|---|
| Project import + launch | Clean import (31 s); the game starts on `world_ref_20km.tscn` |
| `characters` | **PASS** (final run, below) |
| `transitions`, `map_fps`, `persist` | **PASS** (strategic map → RTS jump → possession → FPS fire → back, F5/F9 whole war) |
| `perf` | PASS; frame times in §4 |

`characters` (new, real war on the 20 km world, real input paths):

- **Integration check:** 32 soldier bodies each wear the persisted loadout with every piece
  attached (A 21, B 11); 96 distant soldiers show the loadout proxy mesh.
- **Movement:** 8 of 8 moving soldiers animate with their real velocity (4.5 m/s).
- **Possession / FPS:** possess a soldier, aim at an enemy, hold fire: 2 player shots,
  first-person weapon present, muzzle 1.06 m in front of the camera; Tab returns the soldier to
  the simulation with its character.
- **Third-person muzzle:** (0.00, 0.91, −0.84) in body space: chest height, in front.
- **Near/far:** camera moved 3.5 km away: all 8 soldiers become proxies (0 bodies); back:
  8 bodies, same kit.
- **Save/load:** 133 soldiers, 0 loadout mismatches after blanking the squad's loadouts and
  loading.

Screenshots (`docs/integration02/`): `s01b_char_rts_25m`, `_90m`, `_after_return`,
`s01b_char_fps_hip`, `_ads` (target visible through the optic), `_firing`,
`s01b_08_rts_active_operation`, `s01b_09_fps_same_operation`.

The first version of the scenario passed without firing (the enemy squad had already been
killed by the AI); this was found by reading the output, the scenario now spawns the target
after the movement check, pauses the combat brain while shooting, and fails when no target
exists.

## 4. Performance

Same `perf` scenario, same build, character on vs `--old-soldier` (placeholder soldiers):

| Situation | Characters: avg / p99 / max (ms) | Placeholder: avg / p99 / max (ms) |
|---|---|---|
| RTS at HQ (24 bodies) | 1.99 / 3.9 / 7.2 | 1.74 / 2.9 / 30.9 |
| War far away (0 bodies) | 2.44 / 5.0 / 7.4 | 2.40 / 3.2 / 6.5 |
| 50 v 50 battle, RTS (80 bodies) | **9.65 / 19.2 / 21.6** | 3.38 / 13.1 / 17.2 |
| 50 v 50 battle, FPS (37 bodies) | **7.18 / 13.6 / 40.4** | 3.75 / 10.3 / 35.8 |
| War far away at 8× | 22.1 (2.9× reached) | 22.4 |

- **Regression with many close soldiers.** 80 detailed, animated soldiers cost about 6 ms
  more per frame (≈ 100 fps instead of ≈ 300 fps). This matches CHARACTER-01's own lab
  figures (60 soldiers 2.4–7.2 ms), so it is the cost of the character itself and not an
  integration fault. Idle, far and normal-size situations are unchanged. Skeleton and
  attachment updates dominate; options are listed in §5.
- At 8× the achieved speed was 2.9× in both variants in this `perf`-only run; the 01B report's
  6.7× came from a longer scenario sequence, so the numbers are not comparable with it.

## 5. Remaining limitations

- **Run animation looks wrong** (reported during the session): at 4.5 m/s the trailing leg
  extends far back. The same pose is in the CHARACTER-01 lab render, so this is the clip, not
  the integration. Fixing it is animation work in `tools/blender/character/char_anim.py`.
- **Cost of many close soldiers** (§4). Candidates: shared animation for squads, fewer bones
  or no attachment bones at LOD2, lower animation rate by screen size rather than by distance.
- The optic is see-through only in first person (shader on the viewmodel); the asset itself is
  a solid tube. A hollow tube in `char_weapon.build_red_dot` would remove the special case.
- No aim, lean, prone, jump or turn-in-place clips; no first-person arms.
- Crouching only follows the COMBAT-02 cover tactic; the player has no crouch input, and the
  collision capsule does not shrink while crouched.
- AI soldiers move at one speed (4.5 m/s); gait blending between walk/run/sprint still slides
  a little (see the CHARACTER-01 report).
- Not tested here: vehicles with crew, a hand-played session, the earlier test scripts
  (`--core-test`, `--large-test`, `--combat-*`) beyond what changed code paths required.

## 6. Launching the unified sandbox

Requirements: Godot 4.7.2 (standard), Blender 5.x only if the reference world has to be built.

```bash
git checkout feature/unified-sandbox
```

1. The git-ignored reference world must exist (`worlds/ref_20km/`, `scenes/world/ref_20km.tscn`,
   about 2.4 GB). Build it once with `bash tools/terrain_ref/build_ref_world.sh` (about 14
   min), or copy those two paths from another worktree that has it.
2. Open `project.godot` in Godot 4.7.2 (first import about a minute; restart the editor once
   if it complains about Terrain3D), or run `Godot_v4.7.2-stable_win64.exe --path .`.
3. Press **F5**. The main scene is `scenes/game/world_ref_20km.tscn`. You are North in the
   tactical view at your HQ.

Controls: M strategic map, LMB select, RMB move/attack, P take over the selected soldier
(first person), Tab back to tactical, RMB aim, LMB fire, R reload, V fire mode, F5 / F9 save /
load, F1 all controls, F3 counters. Full list: README.

Checks of this milestone:

```bash
Godot_v4.7.2-stable_win64.exe --path . --resolution 1600x900 --log-file x.log res://scenes/game/world_ref_20km.tscn -- --sandbox-test --shots --only characters
```

Add `--old-soldier` after `--` to show the old placeholder soldiers (comparison only).

## 7. Next steps

`feature/unified-sandbox` is the single development baseline; new milestones branch from it
(see `CLAUDE.md`). Suggested first items: fix the Run clip, then animation cost for large
battles.
