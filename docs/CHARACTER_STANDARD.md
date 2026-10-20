# Infantry character asset standard (CHARACTER-01)

The rules every infantry asset follows so that new uniforms, equipment and weapons fit the
shared character without touching the rig, the animation set or the code. The reference
implementation is `tools/blender/character/` (Blender 5.2.2) and `scripts/characters/`
(Godot 4.7.2). See `docs/CHARACTER-01_REPORT.md` for background and measurements.

## 1. Scale, orientation, rest pose

| Rule | Value |
|---|---|
| Units | 1 Blender unit = 1 m |
| Up / forward | Blender **Z up, character faces +Y**; the character's left side is −X. glTF export maps +Y to Godot **−Z** (Godot forward), so nothing is rotated on import |
| Origin | Between the feet on the ground plane (z = 0) |
| Height | 1.80 m standing (crown 1.80 m, eyes 1.69 m, hip joints 0.93 m, shoulder joints 1.45 m) |
| Rest pose | **A-pose**: arms 45° below horizontal, elbows slightly bent, palms facing the thighs, feet under the hips, toes forward |

Every mesh is modelled **in place on the rest pose** in character space. Rigid pieces are
then moved into their attachment space (section 3) by the build script.

## 2. Skeleton

60 bones, one hierarchy for every loadout. Names are exactly Godot's
`SkeletonProfileHumanoid` names (53 of its 56 bones; `LeftEye`, `RightEye`, `Jaw` are not
used), so Godot maps it to the humanoid profile without a BoneMap.

```
Root
└─ Hips
   ├─ Spine ─ Chest ─ UpperChest
   │                  ├─ Neck ─ Head ─ ATT_Head
   │                  ├─ Left/RightShoulder ─ UpperArm ─ LowerArm ─ Hand
   │                  │      Hand ─ Thumb{Metacarpal,Proximal,Distal}
   │                  │      Hand ─ {Index,Middle,Ring,Little}{Proximal,Intermediate,Distal}
   │                  │      RightHand ─ ATT_Weapon      LeftHand ─ ATT_Hand_L
   │                  ├─ ATT_Chest
   │                  └─ ATT_Back
   ├─ ATT_Hip_L, ATT_Hip_R
   └─ Left/RightUpperLeg ─ LowerLeg ─ Foot ─ Toes
```

* Bone axes: Y along the bone. Spine/neck/head rolls put Z forward, arm rolls Z back,
  leg rolls Z forward, hand and finger rolls Z out of the back of the hand.
* Deformation bones carry weights; `ATT_*` bones are flagged *deform* (so the glTF exporter
  keeps them) but carry no weights.
* `Root` never moves: all clips are **in place** (no root motion). Gameplay moves the body.
* Authoring-only bones `CTRL_*` (IK targets, poles, weapon control) exist while clips are
  generated and are deleted before export.

## 3. Attachment points

| Name | Parent bone | Rest position (m, Blender) | Use |
|---|---|---|---|
| `ATT_Head` | Head | (0, −0.010, 1.700) | helmet, eye protection, head accessories |
| `ATT_Chest` | UpperChest | (0, 0.150, 1.300) | rigid chest items (chest radio, map case) |
| `ATT_Back` | UpperChest | (0, −0.150, 1.300) | backpacks, back-mounted kit |
| `ATT_Hip_L` / `ATT_Hip_R` | Hips | (∓0.185, −0.010, 1.000) | holsters, hip pouches |
| `ATT_Weapon` | RightHand | grip centre in the palm | primary weapon (its grip origin) |
| `ATT_Hand_L` | LeftHand | grip point of the support hand | handheld items |

All character-aligned points have an **identity rest rotation in Blender** (bone Y =
forward, Z = up). `ATT_Weapon`'s rest frame is the weapon's frame when the A-pose hand
holds the pistol grip (Y = muzzle direction, Z = weapon up; `char_skeleton.weapon_frame_from_hand`).

Weapon mount points are nodes inside the weapon glTF (weapon space):

| Node | Position (m, weapon space) | Use |
|---|---|---|
| `ATT_Optic` | (0, 0.020, 0.114) | top rail optic |
| `ATT_Underbarrel` | (0, 0.320, 0.048) | fore grip, bipod, launcher |
| `ATT_RailRight` | (0.026, 0.330, 0.074) | laser / light |
| `ATT_Muzzle` | (0, 0.560, 0.074) | suppressor, flash |
| `GRIP_Support` | (0, 0.165, 0.074) | support-hand pose (Y = hand axis, Z = back of hand) |

Weapon space: origin = pistol-grip centre (where the hand closes), +Y muzzle, +Z up,
bore axis at z = 0.074 m.

## 4. Equipment pieces

A piece is one glTF file with up to three meshes named `<id>_LOD0`, `<id>_LOD1`, `<id>_LOD2`,
plus an `InfantryEquipment` resource (`assets/characters/infantry/equipment/<id>.tres`):

| Field | Meaning |
|---|---|
| `id` | unique name, also the glTF mesh prefix |
| `scene` | the glTF |
| `mode` | `SKINNED` (deforms with the body) or `RIGID` (rides on one point) |
| `attach` | rigid pieces: `ATT_*` bone, or `<slot>:<node>` for a mount on another piece (`weapon:ATT_Optic`) |
| `slot` | uniform, uniform_legs, feet, hands, head, eyes, chest, belt, back, weapon, weapon_optic, weapon_underbarrel, weapon_rail |
| `hides_body` | body regions the piece covers: Torso, Arms, Hands, Legs, Feet (Head is never hidden) |

Compatibility requirements:

* **Skinned pieces** are bound to the shared skeleton by bone *name*; their glTF contains a
  copy of the skeleton only for the skin binds (the loader re-targets the meshes onto the
  character's `Skeleton3D`). Weights come from the body: `char_lib.transfer_weights`
  copies them from the `WeightRef` body by nearest-surface interpolation, then smooths and
  limits to 4 influences. Fit to the body by offsetting its surface (`char_body.body_sdf`,
  `char_gear.torso_hull(P, g)`): jacket surface g = 0.017, plate bags 0.055–0.060,
  cummerbund 0.036, belts 0.034, pack straps 0.048. Stay outside the layer below.
* **Rigid pieces** are modelled in place and exported with their origin at the attachment
  point and the character's axes (the build script does this: mesh × inverse(attachment
  rest)). Weapons and accessories are modelled directly in weapon space.
* Keep pieces closed (no open edges facing the camera), triangles only after export.

## 5. Materials and textures

Materials are a **shared library by name** (`scripts/characters/infantry_materials.gd`,
mirrored by `tools/blender/character/char_materials.py`). The glTF carries material names
only (images are not embedded); Godot replaces each surface material with the library
material of the same name, so all pieces and soldiers share ~20 materials.

* Use an existing name where possible: `Camo_M23`, `Fabric_RangerGreen`,
  `Webbing_RangerGreen`, `Webbing_Coyote`, `Cordura_RangerGreen`, `Cordura_Coyote`,
  `Strap_Black`, `Glove_Coyote`, `Boot_Leather`, `Boot_Sole`, `Helmet_Shell`,
  `Polymer_Black`, `Polymer_OD`, `Metal_Black`, `Metal_Worn`, `Lens`, `Lens_Tinted`,
  `Rubber_Black`, `Patch`, `Skin`, `Eye`, `Iris`.
* `Camo_M23` resolves to the **faction camouflage** (North: Nordic woodland, South: arid);
  `Patch` takes the faction colour.
* UVs are world-scale box projections (`char_materials.apply_box_uvs`): one UV unit = the
  material's tile (camo 0.60 m, webbing 0.30 m, hard surfaces 0.25 m), so textures tile and
  never need per-piece atlases. Seams are hidden by the camouflage and webbing patterns.
* Textures: procedural, tileable, 512–1024 px PNG in `assets/characters/infantry/textures/`.
  Greyscale webbing / polymer textures are tinted by the material colour. Import as VRAM
  compressed with mipmaps; `*_normal.png` as normal maps (OpenGL, +Y up).

## 6. Level of detail

| Level | Distance | Content | Typical cost (loadout A / B) |
|---|---|---|---|
| LOD0 | 0–14 m | every piece separate, full materials | ~61k / 65k tris, ~35 surfaces |
| LOD1 | 14–42 m | all pieces merged at runtime, one surface per material | ~18k / 20k tris, ~16 surfaces |
| LOD2 | 42 m–demotion | merged, one vertex-coloured surface | ~3.9k / 4.2k tris, 1 surface |
| Proxy | abstract tier | static Idle-pose mesh, one surface | ~4.2k tris, 1 surface, no skeleton |

Blender writes `_LOD1` (30 %) and `_LOD2` (6.5 %) by collapse decimation
(`char_export.LOD_RATIOS`). Godot merges them per loadout and faction once
(`InfantryLodMerge`), and builds the proxy from the LOD2 pieces skinned into Idle frame 0
(`InfantryProxyMesh`). Distances are `InfantryCharacter.LOD_DISTANCES`. Animation of
characters beyond 45 m is advanced every third frame.

## 7. Animation

| Clip | Frames @30 fps | Loop | Notes |
|---|---|---|---|
| `Idle`, `Crouch_Idle` | 120 | yes | low-ready weapon carry |
| `Walk_F/B/L/R` | 32 | yes | 1.40 m/s, one gait cycle |
| `Run_F/B/L/R` | 32 | yes | 4.50 m/s (gameplay walk speed) |
| `Sprint_F` | 32 | yes | 7.50 m/s, weapon across the chest |
| `CrouchWalk_F/B/L/R` | 32 | yes | 1.20 m/s |

* Naming: `<State>_<Dir>`, Dir ∈ F, B, L, R. Exported as glTF animations with the action
  names; Godot keeps the names and the character sets every clip to loop.
* All locomotion clips are **one gait cycle, left foot strike at frame 0**, so any two blend
  in phase. Speed and natural period per gait are written to
  `assets/characters/infantry/animation_meta.json`; the AnimationTree plays locomotion at
  `speed / stride(speed) × clip length` so planted feet match any speed.
* Clips are authored with IK (`char_anim.py`): feet planted at the clip speed, both hands on
  the weapon (firing hand on `ATT_Weapon`, support hand on `GRIP_Support`), then baked to FK
  with visual keying. A new clip is a new generator function in `char_anim.clip_list()`.
* New weapons keep the same grip convention (origin at the pistol grip, `GRIP_Support`
  node); if the support grip moves more than a few cm, regenerate the clips with the new
  `support_frame()` so the support hand stays on it.

## 8. Blender build and export

```
blender -b --factory-startup --python tools/blender/character/build_infantry.py -- --export [--previews DIR]
```

About 2–3 minutes on the reference machine. It regenerates textures, body, uniform, gear,
weapon, clips and LODs, writes:

* `assets/characters/infantry/rig/infantry_rig.glb`: armature, body regions, all clips
* `assets/characters/infantry/parts/*.glb`, `assets/characters/infantry/weapons/*.glb`
* `assets/characters/infantry/blender/infantry.blend`: editable source (`.gdignore`d)
* `animation_meta.json`, `build_log.json` (triangle counts, timings, validation numbers)

glTF settings (`char_export._export`): GLB, +Y up, `export_apply=False` (armature kept),
skins on, deform bones only, tangents on, materials exported **without images**,
animations as actions with forced sampling, no cameras/lights.

## 9. Godot import and integration

1. Re-import (`Godot --headless --path . --import`). GLB defaults are fine (generate LODs and
   shadow meshes on, animation import on). Textures: VRAM compressed + mipmaps, normal maps
   flagged (already set in the committed `.import` files).
2. Add an `InfantryEquipment` `.tres` for each new piece (section 4).
3. Add or edit an `InfantryLoadout` `.tres` in `assets/characters/infantry/loadouts/`.
4. Use it: `InfantryCharacter.new()` → `setup(InfantryLoadout.by_id("<id>"), faction)`; set
   `body` (CharacterBody3D) so its velocity drives the animation. Soldiers do this
   automatically from `UnitState.loadout` (`SoldierBody._use_infantry_character`);
   the project setting `fractured_nations/characters/use_infantry_character` (or
   `-- --old-soldier`) switches back to the WORLD-CORE-01 placeholder.
5. Check in `scenes/characters/character_lab.tscn` (`benchmarks/char01/run_char_lab.sh
   --checks | --shots | "--perf 60"`).

## 10. Adding a third configuration (worked example)

`C_recon` was added without code changes: it is
`assets/characters/infantry/loadouts/C_recon.tres`, a list of existing pieces (bare
helmet with NVG, standard carrier, heavy belt, carbine with optic and laser, no pack).

A configuration with a **new piece** (for example a different chest rig):

1. Add a builder in `char_gear.py` (e.g. a new entry in `VEST_LAYOUTS`) and its key in
   `build_infantry.stage_gear` and `SKINNED_PIECES` (or `RIGID` + `RIGID_PIECES`).
2. Run the build with `--export --previews`; inspect the renders.
3. Write `equipment/<id>.tres`, reference it from a loadout `.tres`.
4. Re-import, run the lab checks and shots.

A new uniform colourway is a new camo texture + an entry in `InfantryMaterials.TABLE` /
`FACTION_CAMO`; a new uniform cut is a new SDF garment in `char_uniform.py` that sets
`hides_body` for the regions it covers.
