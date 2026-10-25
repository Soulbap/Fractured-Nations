# VISUAL-03 reference collection

Collected 2026-10-25 for the soldier anatomy / rig / locomotion overhaul (docs/VISUAL-03_REPORT.md).
Images are ~1000 px renditions downloaded from Wikimedia Commons by `tools/visual03/fetch_references.py`
(first pass: public domain / CC only; second pass: any licence, for private study only, per the product
owner on 2026-10-25). Every file below was looked at in contact sheets; the ones marked **key** were studied
at full size and drive concrete decisions. Nothing here is copied into a game asset; they are study material.

Quantitative sources (not images):

| Source | What it gives | Decision it supports |
|---|---|---|
| de Leva P. (1996) *Adjustments to Zatsiorsky-Seluyanov's segment inertia parameters*, J. Biomech 29(9) — male segment lengths (stature 1741 mm): thigh HJC-KJC 422 mm, shank KJC-AJC 434 mm, upper arm 282 mm, forearm 269 mm, hand 86 mm, foot 258 mm, head VERT-CERV 243 mm. Landmark definitions: [BMClab data](https://github.com/BMClab/BMC/tree/master/data) | segment lengths scaled to 1.80 m | skeleton lengths check (audit §1.3); the new body keeps 1.80 m and these ratios |
| Drillis & Contini (1966) height fractions as reproduced in Winter, *Biomechanics and Motor Control of Human Movement* (hip 0.530 H, knee 0.285 H, shoulder 0.818 H, shoulder width 0.259 H, hip width 0.191 H, foot 0.152 H) | joint heights and breadths | rest-pose landmark targets |
| Perry & Burnfield, *Gait Analysis* (normal walking): hip 30° flexion at initial contact → ~10° extension at terminal stance; knee ~5° at contact, 15–20° loading response, ~60° peak swing; pelvic rotation ±4–5° (leading side forward at initial contact), obliquity ±4–5° (swing side drops in single support); lateral pelvis travel ~4–5 cm, vertical ~4–5 cm peak-to-peak (lowest at double support) | walking kinematics targets | audit §2 (defects), mocap retarget acceptance numbers |
| [Lancashire walking pelvis study](https://clok.uclan.ac.uk/14690) (obliquity ~8–9° total excursion), [pelvic step, VU Amsterdam](https://research.vu.nl/en/publications/pelvic-step-the-contribution-of-horizontal-pelvis-rotation-to-ste/) (pelvis rotation in phase with the leading leg at walking speed) | pelvis phase / amplitude | the inverted pelvis yaw of the CHARACTER-01 clips is a defect, not a style |
| Novacheck (1998) *The biomechanics of running*, Gait & Posture 7: running hip ~40–50° flexion in swing, ~10–20° extension at toe-off; knee ~40° at mid-stance, 90–105° peak swing; flight phase; trunk lean small (~5–10°) | running kinematics targets | audit §2: CHARACTER-01 Run_F never brings the thigh in front of vertical |
| [CMU Graphics Lab Motion Capture Database](http://mocap.cs.cmu.edu/) via the cgspeed BVH conversion ([mirror](https://github.com/Shriinivas/cmubvh)) | real human locomotion (walk, jog, run, 90° turns, sudden stops, sneaking, careful run) | locomotion foundation (Phase 5); clips in `assets/characters/infantry/mocap/cmu/` |
| Kenney *Animated Characters Bundle / Survivors / Retro / Protagonists* (CC0, local copy) | stylised rigs + clips | evaluated and rejected (report §3) |

## Topics and what they decide

* **01 anatomy** — Muybridge plate 557 (nude man standing, front/side/back, key): neutral stance, feet a hand-width apart,
  knees straight, pelvis level, shoulders wider than hips; femur / fibula / ulna plates for joint landmarks.
* **02 pelvis, hip, knee** — Gray 244/253 (femur), 319/320 (pelvis), 345–348 (knee), Blausen hip (key): the hip joint
  centre sits inside the pelvis, medial to the greater trochanter and ~8–9 cm from the midline; the widest point of the
  hips is the trochanters, *below* the iliac crest; the femur shaft runs obliquely inward to the knee (knees closer than
  hips), so thighs converge and the knee centres sit under the hip joints, not outside them.
* **03 uniform and gear** — current issue uniforms (MultiCam/OCP, Flecktarn, MTP/Virtus, Nordic), plate carriers,
  helmets, belts: silhouette references for Phase 6 (not used before the anatomy gate).
* **04 standing** — relaxed guard / security stances with rifle: weight on both feet, knees soft (≈5–10°, not 30°),
  muzzle down, stock by the hip or in the pocket.
* **05 walking** — Muybridge 1887 walking plates (key: V0048618, L0075726–30) and dismounted patrols: heel strike with an
  almost straight leading knee and a dorsiflexed foot; trailing thigh only ~15–20° behind vertical; narrow step width
  (feet land near the line of progression); upright torso; patrols carry the rifle at low ready and walk with a
  normal (not crouched) gait.
* **06 running** — Muybridge running plates (key: V0048619, 1887-060 half-mile gait, 066a) and soldiers running with
  rifles (key: NETCOM Best Warrior 079/084, Gilbert stress shoot): thigh drives well in front of the body, foot lands
  under the knee, flight phase, trunk lean ~10°; with a rifle the weapon is carried diagonally across the chest
  (port arms) and the arms stop swinging.
* **07 aiming / firing** — standing firing positions (key: 200313 range series, 554th MP barricade, 7th SFG 1043):
  bladed stance, support foot forward, knees soft, torso leaning into the weapon, head down on the stock.
* **08 crouching** — kneeling and crouched security (key: 809th MRBC M4 zero, Senegalese/US troops, US Army Spc):
  kneeling on the trailing knee or squatting on the balls of the feet; crouch-walk with hips low and trunk forward.
* **09 turning and stopping** — Muybridge woman walking, turning and stopping; Tomb of the Unknown Soldier turn;
  the CMU subject 16 turn / stop clips are the motion source.

## Files
