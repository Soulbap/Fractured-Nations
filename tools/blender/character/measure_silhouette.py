"""Prints the width profile of the clothed character (jacket + trousers) per height, and
renders a front / side orthographic silhouette of the lower torso. Used to check body
proportions (waist, hips, thighs) after changing char_body / char_uniform.

    blender -b --factory-startup --python tools/blender/character/measure_silhouette.py -- OUT_PREFIX
"""
import json
import math
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402

import char_lib as L  # noqa: E402
import char_textures as T  # noqa: E402
import char_materials as M  # noqa: E402
import char_uniform as U  # noqa: E402

out = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.join(tempfile.gettempdir(), "sil")
L.clear_scene()
tex = T.build_all(tempfile.mkdtemp())
mats = M.build(tex)
coll = L.collection("U")
uni = U.build_uniform(coll, mats)
prof = {}
pts = []
for k in ("jacket", "trousers"):
    o = uni[k]
    pts += [o.matrix_world @ v.co for v in o.data.vertices]
for z in [0.60 + 0.05 * i for i in range(17)]:
    band = [p for p in pts if abs(p.z - z) < 0.012]
    if band:
        prof["%.2f" % z] = {"half_width_x": round(max(abs(p.x) for p in band if abs(p.x) < 0.30), 3),
                            "depth_y": round(max(p.y for p in band) - min(p.y for p in band), 3)}
print("FNSIL", json.dumps(prof))
L.setup_render((700, 900))
for o in list(uni.values()):
    o.hide_render = False
cam = bpy.data.objects.new("C", bpy.data.cameras.new("C"))
bpy.context.scene.collection.objects.link(cam)
cam.data.type = "ORTHO"
cam.data.ortho_scale = 1.1
bpy.context.scene.camera = cam
for name, loc, rot in (("front", (0, 3, 1.0), (math.radians(90), 0, math.radians(180))),
                       ("side", (3, 0, 1.0), (math.radians(90), 0, math.radians(90)))):
    cam.location = loc
    cam.rotation_euler = rot
    bpy.context.scene.render.filepath = out + "_" + name + ".png"
    bpy.ops.render.render(write_still=True)
