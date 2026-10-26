# COMBAT-POLISH-01 — Infantry AI, animation and terrain polish

Branch `develop`, after WORLD-COVER-01.1. Four things changed, all in existing systems.

## 1. AI squads take cover at the end of their moves

**Change:** `SquadTactics._settle` is the end-of-move cover step from WORLD-COVER-01.1. It now runs for AI factions' squads too, with
the same post search (`SquadPositions.find_posts` → `CombatBrain.cover_spots`) and the same assignment of posts to soldiers. Nothing
was duplicated.

| Rule | Player squads | AI squads |
|---|---|---|
| Mode | the squad's behaviour | COMBAT (threat within 350 m) |
| Arrived with no threat in reach | order ends as it is | keeps watching while it stays; settles once a threat is reported |
| Operation still approaching | — | skipped (the operation hands out roles on arrival) |
| Threat swings > 75° (at most every 30 s) | settles again | settles again |
| Squads in a tactic, garrisons, HOLD / FOLLOW | never | never |

**Where it applies:** an operation's SECURE stage (squads moving into the objective), reinforcements once arrived, stationed squads
and other AI moves outside an approach. These moves used to end in plain formation slots.

**Unchanged:** WarSim and OpCoordination are not touched. Defending squads in contact still use DEFEND posts, and attacking squads
still use the cover posts of their BOUND / ASSAULT / FLANK legs, as before.

**Posture fix:** AI squads are AWARE by default, and AWARE never counted the threat as "near". An AI soldier standing at a settled
post therefore stayed upright where only lying down protects. Such a soldier now keeps low like a COMBAT soldier
(`CombatBrain._choose_posture`). The rule applies only at a settled post.

**Off switch:** `--no-ai-end-cover`.

## 2. Prone on slopes

**Cause:** the prone clips lie flat in the body's frame, and nothing laid the body onto the ground.

- Facing uphill, the head sank into the slope and the legs hung in the air.
- Facing downhill, the head and rifle stood 0.45-0.5 m up and the feet were buried.
- The aim modifier ran at only 25 % while prone, so the rifle followed the body's tilt, not the target.

**Changes:**

- **Tilt:** `InfantryCharacter.slope_at` reads the terrain heights at the head, feet and both sides. The prone body is turned onto
  that slope about the point under the hips (at most 26° along it, 15° across). This applies to the near body and the far proxy
  mesh, weighted by the posture change's progress, so standing and crouching soldiers stay upright.
- **Aim:** prone, the spine may bend up or down as far as the slope needs (sideways still only a little). A small correction
  measured on the rifle's own bore removes the clip's offset.
- **What stays level:** the tilt is presentation only. The record, its hit volumes and the eye (`Posture`) are unchanged, and shots
  do not come from the character's muzzle (only the effects do).

**Measured** on a 0.29-grade slope, two soldiers per direction, each aiming at an enemy 60 m off:

| Facing | Head / hips / feet above ground (m) | Rifle off target |
|---|---|---|
| downhill, before | 0.44-0.49 / 0.14 / −0.06 (buried) | 12-33° |
| downhill, after | 0.37-0.39 / 0.15 / 0.11-0.15 | 0.0-0.2° |
| uphill, after | 0.31-0.33 / 0.14 / 0.10-0.15 | 0.0-0.1° |
| across, after | 0.26-0.35 / 0.11-0.16 / 0.00-0.24 | 0.2° |

**FPS:** the possessed prone soldier keeps his posture, with the eye 0.42 m above the ground.

Shots: `prone_slope_side.jpg`, `prone_slope_rts.jpg`, `prone_slope_fps.jpg`.

## 3. Relief readable on the ground

**Change:** the terrain shader (`terrain_visual02.gdshader`) measures the local concavity: the ground against the mean of rings
4.5 m and 10 m round it. It needs no new data, because the microrelief is in the heights.

- **Hollows and ditch bottoms:** damper and darker. On open ground, soil shows in patches where the hollow is deepest.
- **Crests:** slightly drier.
- **Grass tufts:** the grass placement shader takes the same damp tone in the hollows, because the tufts cover most of the ground.

The tint fades out between 540 and 900 m. Off switch: `--no-relief-tint`.

Shots, before / after: `ditch_rts_before.jpg` / `ditch_rts_after.jpg`, and `ditch_eye_before.jpg` / `ditch_eye_after.jpg`. The
roadside ditch now reads from the RTS camera as a damp strip; before, it was invisible.

## 4. `c_flank`

**Cause:** an *ordered* flank was refused whenever every route was more than 55 % exposed. On the test site's open ground the flank
was 93 % exposed against 100 % going straight in, so the order never ran. This was a rule problem, not a missing route.

**Fix:**

- An ordered flank (player or operation) is now carried out when it is no more exposed than going straight in.
- A flank the squad would choose instead of an assault must still be under 55 % and clearly safer.

**Test correction:** after the flank succeeded, the test also counted the support team walking onto the taken objective
(`PH_OCCUPY`) as "leaving its role". The check now measures the maneuver itself.

**Result:** `c_flank` PASS. The flank was accepted, the maneuver team reached its position (2.9 m), the target was taken (8 v 0)
and the support team moved 86 m (limit 110).

## 5. Verification

| Run | Result |
|---|---|
| `--combat-polish01-test --only a_ai_cover` (AI squad sent like an operation, enemy reported 230 m off) | after: 5 of 6 protected (5 prone), 17.6 m from the point; before (`--no-ai-end-cover`): 0 of 6, all standing |
| `--combat-polish01-test --only p_prone` (real game, side / RTS / FPS shots) | PASS (table §2) |
| `--combat-polish01-test --only t_ground` (eye / RTS shots, with and without the tint) | shots inspected |
| `--world-cover11-test --only d_combat_move` (the player's end-of-move cover) | PASS, 6 of 6 protected |
| `--ai-strat-test --only d_defence` | PASS |
| `--ai-squad-test --only c_flank` | PASS |
| `--ai-strat-test --only a_assault` | FAIL, see below |
| `tools/check_scripts.gd` | all 197 scripts compile |

**`a_assault`:** it fails identically on the unchanged code (`git stash`): 16 losses, withdrawal. With this milestone, end-of-move
cover never acted in that scenario (0 settles, 0 waits). The failure is pre-existing.

## 6. Remaining issues

- **Level geometry under a tilted body:** the prone record (eye, hit volumes) stays level. On a 16° slope the eye is up to ~0.2 m
  from where the tilted body's head is drawn.
- **Defence untouched:** AI defences in contact use DEFEND posts as before. The end-of-move step covers the moves before contact.
- **`a_assault`:** fails as described in §5 (pre-existing); not investigated here.
