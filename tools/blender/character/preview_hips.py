"""Quick check of hip / waist deformation in a posed clip (default Idle frame 0).

Builds body + uniform (+ standard vest and belt), weights them exactly like the build,
bakes one clip and renders front / side / three-quarter views at hip height.
    blender -b --factory-startup --python tools/blender/character/preview_hips.py -- OUT_PREFIX [CLIP] [FRAME_FRACTION]
"""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402

import char_lib as L  # noqa: E402
import char_skeleton as S  # noqa: E402
import char_body as B  # noqa: E402
import char_textures as T  # noqa: E402
import char_materials as M  # noqa: E402
import char_uniform as U  # noqa: E402
import char_gear as G  # noqa: E402
import char_anim as A  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = argv[0] if argv else os.path.join(tempfile.gettempdir(), "hips")
clip = argv[1] if len(argv) > 1 else "Idle"
frac = float(argv[2]) if len(argv) > 2 else 0.0

L.clear_scene()
tex = T.build_all(tempfile.mkdtemp())
mats = M.build(tex)
arm = S.build_armature(L.collection("Rig"))
body = B.build_body(L.collection("Body"))
L.parent_to_armature(body, arm, auto=True)
L.limit_leg_weights(body)
ref = body.copy()
ref.data = body.data.copy()
bpy.context.scene.collection.objects.link(ref)
ref.hide_render = True
body.hide_render = True
coll = L.collection("U")
uni = U.build_uniform(coll, mats)
for k, o in uni.items():
    M.apply_box_uvs(o)
    L.transfer_weights(o, ref, arm, smooth_iters=2)
    if k == "jacket":
        L.limit_leg_weights(o, *L.JACKET_LEG_FADE)
for fn in (lambda: G.build_vest(coll, mats, "standard"), lambda: G.build_belt(coll, mats, "standard")):
    o = fn()
    M.apply_box_uvs(o)
    L.transfer_weights(o, ref, arm, smooth_iters=4)
A.setup_controls(arm)
acts = A.author_and_bake(arm, only=[clip])
A.remove_controls(arm)
arm.animation_data.action = acts[clip]
f = int(acts[clip]["fn_frames"] * frac)
L.setup_render((700, 800))
bpy.context.scene.render.image_settings.file_format = "JPEG"
for name, az in (("front", 0), ("q34", 40), ("side", 90)):
    L.render_view("%s_%s_%s.jpg" % (out, clip, name), (0, 0.0, 0.95), 1.9, az, 2, lens=50, frame=f)
