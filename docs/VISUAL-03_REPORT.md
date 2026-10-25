# VISUAL-03 — Soldier character, anatomy, rigging & animation overhaul

Status: **second approval checkpoint.** The anatomy prototype (§4) was approved on 2026-10-25. Since then the full
soldier has been built — rifle handling over the motion capture, the whole clip set, uniforms and equipment refitted to
the new body for all three factions, the Godot animation tree with aim / fire / reload layers and turning clips — and
validated in the VISUAL-02 world (§8–§10). It is **staged**: the new assets live in `assets/characters/infantry_v03/`
and are used only when the game is started with `--soldier-v03`; without the flag the game plays exactly as before.
Replacing the shipped soldier waits for the product owner's approval of §8–§11.

## 1. Diagnosis of the current soldier (Phase 1)

Tool: `tools/blender/character/visual03_audit.py` opens the shipped `assets/characters/infantry/blender/infantry.blend`
read-only and writes renders and gait numbers to `docs/visual03/before/` (`before_gait.json`).

### 1.1 Pipeline as found

| Part | Where | Finding |
|---|---|---|
| Mesh | `char_body.py` | Body = union of ~30 SDF ellipsoids / round cones on the skeleton joints, meshed by OpenVDB. Torso is four stacked ellipsoids + separate "hips", "glutes", "pecs" blobs |
| Skeleton | `char_skeleton.py` | 60 bones, Godot humanoid names, A-pose, hand-placed joint coordinates |
| Skinning | `char_lib.transfer_weights`, `limit_leg_weights` | automatic heat weights on the SDF body, copied to garments by nearest surface; a later patch limits UpperLeg influence at the waist |
| Animation | `char_anim.py` | every clip is procedural: a small gait model places IK foot targets, the pelvis/spine get sine curves, then everything is baked to FK |
| Godot | `scripts/characters/infantry_character.gd` | BlendTree: idle ↔ 2D blend space (Walk/Jog/Run × F/B/L/R) ↔ crouch; playback rate = speed / stride so feet match; no root motion; Sprint_F is not in the tree |
| Weapon | `ATT_Weapon` on the right hand; both hands IK-solved onto the carbine during authoring | the weapon never aims: there is no aim/fire/reload pose at all |
| Turning / start / stop | — | no clips; turning on the spot is faked by feeding a sideways step into the blend space |
| LOD | LOD0/1/2 per piece (collapse decimation), runtime merge, static proxy | works; not a cause of the visual problems |

### 1.2 What is wrong, and where it comes from

The problems come from **three** places at once: the mesh, the authored poses and the procedural gait model.
Replacing the mesh alone would not fix the motion.

**Mesh (body shape).** See `docs/visual03/before/sheet_bare_rest.jpg`. The torso reads as a stack of rings (visible
creases between the ellipsoids at the belly and waist), the abdomen bulges, the pelvis has no bony landmarks (no iliac
crest, no trochanter), the crotch and buttock region is one rounded mass ("diaper"), thighs and shins are tubes with a
knee ball, the chest is flat in profile and the neck long and thin. Dressed, the trousers inherit this volume, so
the hips look wide and soft.

**Skeleton lengths are *not* the main problem.** Against de Leva (1996) scaled to 1.80 m: thigh 0.427 m (ref. 0.437),
shank 0.417 m (0.449), upper arm 0.305 m (0.291), forearm 0.266 m (0.278); hip joint height 0.932 m, knee 0.505 m,
shoulder 1.452 m all within a few cm of Drillis & Contini. The skeleton can be kept in spirit; the joints of the new
body come from the anatomical mesh instead of hand-typed coordinates.

**Poses.** The `Idle` holds both knees bent 27–31° (relaxed standing is ~5°), the pelvis 2.2 cm low, feet wide and
toes turned out (front view `sheet_dressed_idle.jpg`): this is the "crouching with wide hips" look.

**Gait model** (`before_gait.json`, numbers per clip; references in §2):

| Measure | Walk_F | Run_F | Reference |
|---|---|---|---|
| Pelvis rotation follows the leading leg | **no (inverted)** | **no (inverted)** | yes: the leading leg's side of the pelvis is forward at heel strike |
| Pelvic obliquity | ±2.5°, peak at heel strike, stance side drops | same | ±4–5°, swing side drops in single support |
| Thigh angle to vertical (hip flex / ext) | +26° / **−41°** | **+2°** / −58° | walk +30° / −10…−15°; run +40…50° / −15…−20° |
| Knee flexion | 0–60° | 29–89° | walk 5–60°; run 40° stance, 90–105° swing |
| Lateral pelvis travel | ±1.4 cm, phase shifted ~20 % | ±0.6 cm | ±2–2.5 cm over the stance foot |

So the walking pelvis swings backwards on the side whose leg steps forward, the trailing leg is pushed ~40° behind
the body, and the run never brings the thigh in front of the body: the legs paddle behind a squatting pelvis
(`before_Run_F_side.png`). These are model errors (sign of `yaw`, phase of `sway`, foot targets offset backwards by
`offset`, constant `drop`), not artistic choices.

**Gameplay speed.** `SoldierBody` inherits `walk_speed = 4.5` m/s from the FPS controller, so every AI soldier and the
player move at a 16 km/h run everywhere (`GAIT.Run` is labelled "gameplay walk speed"). Even perfect clips would make
squads look like they are always running. This is a gameplay setting outside this milestone's scope, but it decides
which clip is seen most; see §6.

## 2. Reference research (Phase 2)

Collection and index: [docs/visual03/references/INDEX.md](visual03/references/INDEX.md) (~110 images in nine topics,
source page, licence and author for every file; key images marked and their decisions listed). Quantitative sources:
de Leva 1996 segment lengths, Drillis & Contini height fractions, Perry & Burnfield walking kinematics, Novacheck 1998
running kinematics, pelvis studies (Lancashire, VU Amsterdam). Motion source: the CMU Graphics Lab Motion Capture
Database (53 takes in `assets/characters/infantry/mocap/cmu/`).

## 3. Kenney animated characters (evaluated, not used)

`Kenney Game Assets All-in-1 3.7.0/3D assets/Animated Characters {Bundle, Survivors, Retro, Protagonists}` (CC0),
inspected with `blender -b` (scratch scripts, the collection was not modified and nothing was copied):

* Models: `characterMedium/Small/LargeMale/LargeFemale.fbx` (+ .blend sources), 1.5–1.8k triangles, 58-bone
  Mixamo-like skeleton (`Hips, Spine, Chest, UpperChest, Neck, Head, LeftUpLeg, LeftLeg, LeftFoot, LeftToes, …`,
  three-segment index finger and two-segment thumb only) plus foot-roll / IK control bones.
* Clips (FBX + .blend, one action each, besides a 2-frame "Targeting Pose"): attack, crouch, crouchIdle, crouchWalk,
  death, idle, interactGround, interactStanding, jump, kick, punch, racingIdle/Left/Right, run (16 frames @24 fps),
  shoot, walk (32 @30 fps). Survivors / Retro / Protagonists ship only idle / jump / run on the same rig.
* Import: FBX imports into Blender 5.2 without errors; Godot imports FBX natively, so technically usable.
* Proportions: total height ≈ 3.7 heads, hip joint at ~35 % of the height (human ≈ 53 %), oversized head and hands.
* Motion (contact sheets rendered on the medium model): cartoon timing, the run is a long-flight bound with the arms
  spread like wings, no rifle handling, 3-finger hands. Retargeting the curves onto human proportions would keep the
  exaggerated poses and timing.

Decision (agreed with the product owner, "altfor cartoony"): **not reused**. CMU motion capture is used instead.

## 4. Prototype (Phases 3–5)

Build: `blender -b --factory-startup --python tools/blender/character/v03_proto.py -- docs/visual03/proto [--stress] [--stage all [--only Walk2_F,...]] [--nostills] [--norender]`
(then `python tools/visual03/make_previews.py docs/visual03/proto` for the GIFs and contact sheets). Modules:
`v03_body.py` (body + rig), `v03_mocap.py` (BVH retargeting, cycle cutting, foot locking). The source scene is saved
to `assets/characters/infantry/blender/v03_proto.blend`. Nothing in the game uses it yet.

### 4.1 Body (Phase 3)

Base: the MakeHuman base mesh through **MPFB 2.0.18** (Blender extension from extensions.blender.org, installed in the
user's Blender 5.2; MakeHuman output is CC0). It is a sculpted, anatomically built adult body with game topology
(13.4k vertices, 13.4k quads = 26.8k triangles before LODs), so pelvis, iliac crest, trochanters, gluteals, knees, calves, clavicles and shoulder girdle
come from an artist's anatomy rather than from blobs. Macro parameters (`v03_body.MACRO`): male, 25 years, muscle
0.62, weight 0.46 (lean, athletic), proportions 0.55, scaled to 1.80 m.

Rest-pose joints (from MakeHuman's joint helpers, `proto_measure.json`) against the references:

| Joint (height above floor) | Prototype | Reference (1.80 m) | CHARACTER-01 |
|---|---|---|---|
| hip joint centre | 0.971 m | ~0.93–0.95 (0.52–0.53 H) | 0.932 |
| knee | 0.516 m | 0.513 (0.285 H) | 0.505 |
| ankle | 0.075 m | 0.070 (0.039 H) | 0.088 |
| shoulder joint | 1.448 m | ~1.43–1.47 (0.818 H acromion) | 1.452 |
| hip joint spacing | 0.221 m | ~0.17–0.19 | 0.182 |
| bitrochanteric breadth (mesh) | 0.354 m | 0.344 (0.191 H) | ~0.33 |

Renders: `docs/visual03/proto/sheet_rest.jpg` (A-pose rest, front / ¾ / side / back) and `sheet_neutral.jpg` (arms at
the sides, feet under the hips, relaxed fingers). Compared with Muybridge plate 557 and the anatomy plates: level pelvis
with the widest point at the trochanters, thighs converging to the knees, straight knees, feet under the hips, shoulders
clearly wider than the hips, natural lumbar curve and gluteal mass in profile.

### 4.2 Rig and skinning (Phase 4)

MPFB's `game_engine` skeleton (53 bones) is fitted to the body's joint helper cubes and renamed one-to-one to the
shared skeleton (`v03_body.RENAME`: pelvis→Hips, spine_01..03→Spine/Chest/UpperChest, thigh→UpperLeg, calf→LowerLeg,
ball→Toes, clavicle→Shoulder, fingers 3×4 + thumb 3 …), so every bone name Godot and the game code use still exists.
The 7 `ATT_*` points are not added yet (Phase 8). Weights are MakeHuman's hand-made weights for that skeleton.

Pitfall found and fixed: MPFB fits the rig to the `joint-*` helper groups; created with `detailed_helpers=False` it
silently falls back to the *default* body's joint positions (the first build had the shoulders 18 cm too low).

Stress poses (`sheet_stress.jpg`, hip close-ups `sheet_stress_hips.jpg`): lunge, deep squat, kneel, high knee, wide
step, aim with torso twist. No collapsing hips, twisted thighs or detached joints; the groin and gluteal fold keep
their volume in the squat and lunge. Remaining: a sharp skin fold on top of the thigh at extreme hip flexion (kneel,
squat), which trousers will cover; corrective shapes are not planned.

### 4.3 Locomotion foundation (Phase 5, first part)

Source: CMU motion capture (§2). `v03_mocap.py` retargets in world space relative to the rest poses (formula in the
module header), cuts one gait cycle (left contact to left contact, detected from foot height with hysteresis; the
take's first frame is the cgspeed T-pose and is skipped), turns it so the travel is +Y, removes the mean travel
(in place, as the game requires), loops it seamlessly over 32 frames, puts each foot on its own floor (the takes
leave one foot hovering 2–4 cm) and **locks planted feet**: each contact segment's heel or ball point is pinned to one
ground position for the clip's own speed by two-bone leg IK.

Candidates were rendered side by side and judged against the Muybridge plates and the running-soldier photos:

| Clip | Take | Speed | Cycle | Stride | Verdict |
|---|---|---|---|---|---|
| Walk_F | 16_15 walk | 1.19 m/s | 1.13 s | 1.35 m | **chosen**: relaxed, upright, natural arm swing |
| Brisk_F | 16_21 walk | 1.83 m/s | 0.93 s | 1.70 m | **chosen** (patrol / brisk walk) |
| Jog_F | 35_17 run/jog | 3.29 m/s | 0.76 s | 2.50 m | **chosen** |
| Run_F | 16_46 run/jog | 4.45 m/s | 0.68 s | 3.00 m | **chosen**: upright (~8° lean), clear flight phase, thigh well in front |
| — | 35_01 walk | 1.35 m/s | | | rejected: one foot hovers and skates after retargeting |
| — | 16_55 run | 4.4 m/s | | | rejected: hunched (25° trunk lean), looks like sneaking |
| — | 141_02 run | | | | rejected: take shorter than a full cycle |

Gait numbers of the chosen clips on the prototype (same measurement as the audit, §1.2):

| Measure | Walk_F (after) | Walk_F (CHARACTER-01) | Run_F (after) | Run_F (CHARACTER-01) |
|---|---|---|---|---|
| Pelvis rotation follows leading leg | **yes** (−4.6…+2.1°) | no | no¹ (−10…+7°) | no |
| Pelvic obliquity | −4.7…+6.4° | ±2.5° | −4.2…+7.6° | ±2.5° |
| Thigh to vertical (flex / ext) | +24° / −24° | +26° / −41° | **+38° / −30°** | +2° / −58° |
| Knee flexion | 2–59° | 0–60° | 11–99° | 29–89° |
| Pelvis vertical travel | 3.7 cm | 3.6 cm | 8.7 cm | 6 cm |

¹ In running, pelvis and thorax rotation change phase with speed (real capture, not an authoring choice); the
walking clip is the one where the inverted pelvis was visible.

Foot slip of the contact point over the ground while it is planted, after locking (`proto_motion.json`,
`slip_after_lock`, m/s, mean / p90): Walk 0.01–0.02 / 0.05–0.07, Brisk 0.03 / 0.12–0.18, Jog 0.09–0.28 / 0.35–1.5,
Run 0.15–0.24 / 0.67–0.97. The p90 values of jog and run are the touchdown / lift-off frames, where the pin blends in
and out over one frame. Before locking the walk slipped 0.4–0.7 m/s.

Previews (character travels at the clip speed over a 1 m checker floor, camera follows, so planted feet must stand
still on the checker): `docs/visual03/proto/<clip>.gif` (side, front and ¾ views side by side, real time, two cycles) and
`<clip>_<view>_sheet.jpg` (8 frames of one cycle). Before / after: `docs/visual03/compare_walk_side.jpg`,
`compare_run_side.jpg`, `compare_body_rest.jpg`.

Not in this prototype (next steps after approval): rifle handling (both hands on the weapon by IK on top of the
captured legs and spine: the clips here swing their free arms), backward / sideways clips, start, stop and turn
clips (takes 16_08, 16_17–20, 16_33/34, 16_41–44, 16_57 are downloaded for that), crouch / crouch walk, aim, fire
reaction, reload.

## 5. Questions for the approval gate

1. Anatomy and proportions of the prototype body (`sheet_rest.jpg`, `sheet_neutral.jpg`, stress sheets).
2. Basic locomotion (walk, brisk walk, jog, run previews).
3. **Gameplay speed:** soldiers move at 4.5 m/s (a run) for every move today. Proposed for Phase 8: AI soldiers walk
   at ~1.3–1.8 m/s on routine moves and run (4.5 m/s) only when the order or the situation calls for it; the FPS
   player keeps walk / sprint. This is a gameplay change and needs a decision.

## 6. Remaining visual defects (prototype)

* Bald head, no face texture, placeholder skin material: the head will be under a helmet; the face gets its texture
  in Phase 6.
* Hip joint spacing 0.22 m is a few cm wider than the anatomical reference; the stance and walk renders do not show a
  wide-hip look, but it is the first place to look if the dressed soldier reads as wide.
* Skin fold on top of the thigh at extreme hip flexion.
* Chest reads soft and rounded in frontal light, and the pectoral bulges when the arm swings far forward (run, ¾
  view, first frames): build is MakeHuman muscle 0.62 / weight 0.46; a broader, harder chest (muscle ~0.7, torso
  targets) is one parameter change once the product owner has judged the build. Under a plate carrier this area is
  covered.
* Jog / run keep a little slip at touchdown and lift-off (see §4.3).
* Fingers: one relaxed curl pose; grip poses come with the weapon.

## 7. Tests performed

No game code changed in this phase, so no Godot test suite was run (change-impact policy). Checks run:

* `visual03_audit.py` on the shipped `infantry.blend` (before renders and gait numbers).
* `v03_proto.py` body build, measurement, stills, stress poses, mocap retarget + foot lock + gait / slip
  measurement for the chosen clips, motion renders; all outputs looked at.
* Kenney evaluation scripts (scratch, read-only on the collection).

---

# Part 2 — the full soldier (after the anatomy approval)

## 8. Implementation

### 8.1 One body for every builder (`char_body.py`, `char_body_mh.py`, `char_skeleton.py`)

The MakeHuman body replaces the SDF body in the shared pipeline (no parallel body is kept):

* **Arms lengthened.** In the dressed tests the support hand could not reach the handguard. Measured: upper arm 0.267 m
  against ~0.33 m (de Leva / Drillis), fingertips at 0.44 H standing instead of ~0.38 H. The rifle itself is in
  proportion (0.84 m overall, 0.28 m grip–butt, 0.56 m grip–muzzle: an HK416 / M4 with the stock out). MakeHuman's own
  targets `measure-upperarm-length-incr` (1.0) and `measure-lowerarm-length-incr` (0.15) fix it: upper arm 0.334 m.
* **Reference rest pose.** The body is reposed so limbs point like CHARACTER-01's A-pose (feet under the hips, arms
  45° down, palms to the thighs) and the pose is applied as rest. Every garment and gear builder is authored around that
  layout; with the same limb directions they can run unchanged.
* **Reference space.** Builders work in a space whose heights are mapped piecewise-linearly onto the CHARACTER-01
  landmarks (ground, ankle, knee, hip joint, shoulder joint, crown); `torso_sdf`, `leg_sdf`, `arm_sdf`, `foot_sdf`,
  `hand_sdf` now measure the real body there: an OpenVDB level set of the body (4 mm; hands 1.5 mm), split between
  torso, neck, arms, hands, legs and feet by nearest bone. A finished piece goes back with `to_body_space`. Collars
  follow the new neck (`neck_shift`); helmets and eyewear are fitted to the measured cranium (`head_fit_matrix`).
* **Head.** Head + neck are their own piece with a cylindrical UV and a painted skin texture (short military cut,
  brows, lips, beard shadow), material `SkinHead` (`skin_head_v03_albedo.png`); eyeballs with iris at MakeHuman's eye
  helpers. `ATT_*` points are placed on the body (CHARACTER_STANDARD §3).
* Fixed on the way: `char_lib.remove_empty_groups` removed vertex groups by index while the indices shifted (the head
  lost all its weights and the helmet floated); MakeHuman's helper groups (`body`, `joint-*`, `scalp` ...) are stripped
  before weight transfer.

Result: the whole CHARACTER-01 / ASSET-PRODUCTION-01 set (13 shared pieces, NATO / RU / CN uniforms, helmets, vests,
armour, packs) rebuilds on the new body without per-piece rework; weapons are unchanged (weapon space).

### 8.2 Weapon handling over the motion capture (`char_anim.py`, `v03_mocap.py`)

Every clip starts from captured motion; the rifle layer is added on top, per frame:

1. **Posture** — a *constant* correction brings the clip's mean thorax lean and head pitch to the carry's target
   (the idle take looked down 30°); the captured variation stays.
2. **Spine** — the thorax counter-rotation is damped (a rifle carrier keeps the shoulders squarer: 25–70 % kept per
   carry) and the carry's stance yaw is added (bladed for ready / aim), spread over Spine / Chest / UpperChest.
3. **Rifle** — placed on the *posed* chest for the carry (patrol, low ready, ready, run, port arms, crouch, aim): butt
   relative to the right shoulder joint, muzzle yaw / pitch / cant; its orientation is partly stabilised against the
   chest's roll and pitch and it moves with 10 % of the captured right-hand swing, so it rides on the body (bob and
   pump in the jog and run) instead of being frozen.
4. **Arms** — two-bone IK onto the grips (firing hand on the pistol grip = `ATT_Weapon`, support hand on the handguard
   frame), with elbow poles per carry; hands take the grip frames; fingers curl into a grip (index along the receiver,
   on the trigger in aim / fire).
5. **Aim** — the butt in the shoulder pocket, then a cheek weld: neck and head turn (within limits of 22° pitch, 14°
   roll, 20° yaw) to bring the right eye to the sight line, and the rifle rises the last centimetres to the eye
   (remaining distance 36 mm, 7 mm in Fire).
6. **Reach fit** — carries whose grips the arms cannot reach (styles were authored on CHARACTER-01 proportions) move
   their butt inboard / back and turn the muzzle inboard until both hands reach within 93 % of the arm length.

Clips (all in `assets/characters/infantry_v03/animation_meta.json`):

| Clip | Source | Carry | Notes |
|---|---|---|---|
| Idle / Ready_Idle | CMU 77_02 (weight shift), 4 s loop | low / ready | relaxed and combat-ready stance |
| Walk_F, Brisk_F | 16_15 (1.19 m/s), 16_21 (1.83 m/s) | patrol / low | |
| Jog_F, Run_F | 35_17 (3.29 m/s), 16_46 (4.45 m/s) | ready / run | |
| Sprint_F | 16_46 | port arms | rifle across the chest |
| Walk_B | 09_12 backward stretch | low | |
| Walk_L / Walk_R | 69_42 / 69_48 sideways stretches | low | captured side steps (0.4 m/s) |
| Jog_* / Run_* B/L/R | the walking B/L/R keys | ready | (see §11) |
| CrouchWalk_F/B/L/R | the walks, pelvis −0.30 m, legs re-solved onto the same footfalls | crouch | |
| Crouch_Idle | the idle, squat on the forefoot of the trailing foot | crouch | |
| Turn_L / Turn_R | 69_16 / 69_18 turn-in-place, the turn unwound | low | the game turns the body |
| Aim | the idle legs + aim carry + cheek weld | aim | upper body layer |
| Fire | 6 frames: 22 mm kick, 3.5° rise, chest takes 35 % | aim | one-shot |
| Reload | 2.5 s: support hand to the magazine, chest pouch, back | ready | one-shot |

Every clip ends with both hands on their grips (largest error 0.9 mm, support hand) — `build_log.json` `anim_check`.

### 8.3 Godot (`scripts/characters/infantry_character.gd`, `infantry_aim_modifier.gd`, `soldier_body.gd`)

* **Staging.** `InfantryCharacter.asset_root()` is `res://assets/characters/infantry_v03/` with `--soldier-v03`, else
  the shipped root; the rig, `animation_meta.json` and `InfantryLoadout.dir()` follow it. `tools/visual03/stage_loadouts.py`
  mirrors all 27 loadouts and the rebuilt equipment into the staging root (weapons stay shared).
  `tools/visual03/check_loadouts.gd` builds every loadout: all 27 build with all 26 clips (the `*_hmg` loadouts' missing
  optic / muzzle mount is the same with the shipped soldier).
* **Tree.** Relaxed ↔ ready idle (`alert`), turning in place by the turn clips (blend by yaw rate, played at the
  rate the body turns) instead of the CHARACTER-01 side-step trick, the locomotion blend space (walk, brisk, jog, run,
  sprint; crouch), then upper-body layers filtered to the spine, arms and fingers: **Aim** (blend), **Fire** (one-shot,
  20 ms in), **Reload** (one-shot). Blend weights ease (move 0.2–0.3 s, crouch 0.33 s, aim 0.25 s, ready 0.4 s); a
  frame's blend step is capped at 1/20 s so a hitch eases instead of snapping. Playback rate keeps the stride matched to
  the speed, sideways with the side steps' own stride.
* **Aim direction.** `InfantryAimModifier` (SkeletonModifier3D) turns Spine / Chest / UpperChest towards the aim point
  (yaw ±69°, pitch ±46°) with the aim blend as its influence; arms, head and rifle follow as children, so the soldier
  aims where the AI aims while its legs keep walking where it goes.
* **From the record, read-only.** `SoldierBody._character_layers`: aim point = the target the soldier tracks (seen in
  the last 6 s) or shot at in the last 2.5 s; ready stance while the AI is not idle, watching or under fire; reload
  while `reload_until` runs; a recoil one-shot per new shot (`shot_counter`). The possessed body shows none of it.

### 8.4 Movement speed (kept at 4.5 m/s)

`WorldSim.pace_of / move_speed` (walk 1.3, brisk 1.8, jog 3.3, run 4.5 m/s, chosen from the state the AI already writes:
reaction / fire taken -> run, assault / flank / bound / withdraw -> run, other tactics -> jog, operations past the
approach -> run, garrison -> walk, else the pace the order chose, else jog; both tiers; `SquadState.pace` saved; RTS
Ctrl / Alt + right-click = run / walk) is **off by default**: per the product owner, movement speeds, tactical approaches
and combat balance belong to COMBAT-01. Without `--paces` every soldier moves at 4.5 m/s as before (the animation set
has all four gaits either way). Impact review before switching it off: one `--ai-strat-test a_assault` run took Haugen
at the old pace and withdrew at the new one (17 losses against 10); `e_withdraw` and `--ai-squad-test c_flank / k_persist`
fail the same with and without the paces (site / tactics, not pace). Single stochastic runs; not pursued in VISUAL-03.

## 9. Validation

### 9.1 Blender (`tools/visual03/blender_previews.py`)

`docs/visual03/blender/<clip>.mp4`: the dressed soldier (NATO-class kit, carbine with red dot and grip) travelling at the
clip's speed over a 1 m checker floor, side and three-quarter views, real time: Idle, Ready_Idle, Walk_F, Brisk_F,
Jog_F, Run_F, Sprint_F, Walk_B, Walk_L, CrouchWalk_F, Crouch_Idle, Turn_L, Aim, Fire, Reload.

### 9.2 Godot, VISUAL-02 world (`--soldier-v03 --paces --visual03-test --shots`)

`scripts/debug/visual03_selftest.gd`; recordings in `docs/visual03/godot/video/*.mp4`, stills in `docs/visual03/godot/`:

| Test | What ran | Result |
|---|---|---|
| A individual | one soldier: walk / jog / run orders, stop, turn on the spot | speeds 1.30 / 3.30 / 4.50 m/s through the real controller; turn clip used (blend 1.0); PASS |
| B squad | eight soldiers: jog 60 m, a 90 deg change of direction at a run, a walk | formation kept, all eight at 1.30 m/s on the walk; animation of 8 characters 156 us per frame (about 20 us each), frame 3.35 ms; PASS |
| C combat | two fire teams of four 70 m apart, AI on (kept alive) | 264 shots, rifles raised (aim blend 1.0) and firing at their targets; PASS (120 m apart in tall grass they never saw each other) |
| D terrain | four soldiers up and down a 16 % slope on open ground | feet on the slope, no floating; PASS |
| E transitions | stand, move, stop, crouch, stand, raise, move aiming, fire x4, reload, lower | no blend weight changes by more than 0.40 in one frame (the move blend after a screenshot hitch); PASS |
| F views | first person from another soldier 3 m away; RTS at 15, 40, 110 m | `f_fps_close.jpg`, `f_rts_*.jpg`; LODs switch as before |

The in-engine foot-slip numbers the test prints are not usable (bone positions sampled in process frames while the
body moves in physics frames, with screenshot hitches); foot contact was judged from the recordings and from the Blender
measurement of the planted contact point after locking (walk p90 0.17-1.9 m/s: most frames still, single touchdown /
lift-off frames slip).

## 10. Before / after

* Body: `docs/visual03/compare_body_rest.jpg`; walk / run: `compare_walk_side.jpg`, `compare_run_side.jpg`.
* In game: the default run (CHARACTER-01 soldier) against `--soldier-v03`, same views as `docs/visual03/godot/f_*.jpg`.

## 11. Remaining visual defects

* **Sideways and backward at speed.** The captured side steps are slow (0.4 m/s); faster sideways movement plays them
  faster (no sliding, a quick shuffle). Jog / run backward and sideways reuse the walking keys. A faster strafe capture
  is the fix (the AI faces its direction of travel, so this shows mainly when aiming while moving).
* **Foot contact** at touchdown / lift-off of jog and run: single frames where the contact moves from heel to ball.
* **Turn clips** are one second of a turning take looped: the step pattern repeats on long turns.
* **Reload** is a support-hand cycle on a fixed rifle; the magazine itself does not move.
* **Aim**: the sight line ends ~36 mm from the eye after the head search (the rifle closes most of it).
* **Radio whip antenna** of the vests can cross the face when the head is turned onto the stock.
* **Chest** reads soft in frontal light (MakeHuman muscle 0.62).
* `*_hmg` loadouts (shipped and staged): the heavy MG has no optic / muzzle mount (outside VISUAL-03).

## 12. Tests performed (part 2)

* Blender: `build_infantry.py --export --root assets/characters/infantry_v03` (+ previews), `build_factions.py --export
  --root ...`, `blender_previews.py`; `anim_check` numbers in `assets/characters/infantry_v03/build_log.json`.
* Godot: `check_scripts.gd` (181 scripts), `--import`, `tools/visual03/check_loadouts.gd` with and without `--soldier-v03`,
  `--visual03-test` A-F (PASS).
* Shared systems touched (WorldSim movement, SquadControl orders): with the paces off the movement code returns the old
  speed; `--ai-squad-test --only c_flank,d_assault,f_withdraw,k_persist` and `--ai-strat-test --only a_assault,e_withdraw,
  j_persist` were run during the impact review (§8.4). No full suite.

## 13. Replacing the shipped soldier (after approval)

1. `build_infantry.py --export` and `build_factions.py --export` without `--root` (writes the canonical root), or move
   `assets/characters/infantry_v03/*` over `assets/characters/infantry/` and run `stage_loadouts.py`-equivalent path fixes.
2. Drop `ASSET_ROOT_V03` / `--soldier-v03`, the old SDF garment references in CHARACTER_STANDARD, and the `Skin`
   material; update `docs/CHARACTER_STANDARD.md` (body source, rest pose, clip set, layers).
3. Re-import, `check_loadouts.gd`, `--visual03-test` (without `--soldier-v03`), the character lab.
