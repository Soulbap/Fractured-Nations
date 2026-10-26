# HELMET-FIX-01 — round helmet crowns

Follow-up to the ASSET-INTEGRATION-01 review: the NATO soldiers' helmet was flat on top
(`docs/asset_integration01/w_hk416_side.jpg`).

## Cause

The helmet geometry (`fac_gear.build_helmet`, an ellipsoid shell SDF) was round. The flattening happened when the piece
was moved onto the body: `char_body.to_body_space` → `unwarp_z` is `np.interp`, which **clamps** every height above
its last reference knot (HeadTop, 1.80 m) to the body's crown. The head-fitted helmet reaches 1.835 m, so its top
~35 mm (outer and inner shell, NVG shroud top, IR strobe) were pressed onto one plane 0.101 m above `ATT_Head`.
**RU (6B47) and CN (QGF-03) helmets had the same defect**, because all three go through the same path.

## Fix

* `build_factions._head_to_body_space` (used by `_rigid` for `ATT_Head` pieces): the same unwarp, but above the last
  knot it extends the last segment's slope instead of clamping. `char_body` itself is unchanged, so no other piece moves.
* The NATO IR strobe was placed in the air above the shell. The clamp used to hide that. It now sits on the cover at
  the back of the crown, along the shell normal (`fac_gear.build_helmet`).
* Only `nato_helmet.glb`, `ru_helmet.glb` and `cn_helmet.glb` were re-exported. They were built into a scratch
  `--root`, and only these three files were copied. Rims, harness, attachment frame (`ATT_Head`), LOD triangle counts and
  materials are unchanged. The crowns are now continuous domes 36–38 mm higher. The inner shell clears the scalp by
  about 2 cm (before, it lay on the crown).

## Validation

* Profile of the exported LOD0 cover (drop from the top across the helmet): before 0 mm over ~85 % of the width (flat);
  after a smooth 0 → 60–70 mm dome for all three.
* Godot: `--asset-integration-test --shots --only w_weapons --fullscreen` PASS (hold, eye and grip unchanged).
  Shots are in `docs/helmet_fix01/`: `game_after_w_hk416_side.jpg` (compare with `asset_integration01/w_hk416_side.jpg`),
  the three riflemen side by side `lab_before_side.jpg` / `lab_after_side.jpg` / `lab_after_front.jpg`, and the Blender
  close-up `blender_nato_closeups.jpg`. The head and eyepro do not show through the shell.
