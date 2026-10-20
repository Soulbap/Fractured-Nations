"""Diagnostic: thigh-bone influence on body vertices above the hip joints (waist / belly /
buttocks). Large values there make the waist collapse and the jacket hem flap when the
legs flex.  blender -b --factory-startup --python tools/blender/character/diag_weights.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import char_lib as L  # noqa: E402
import char_skeleton as S  # noqa: E402
import char_body as B  # noqa: E402

L.clear_scene()
arm = S.build_armature(L.collection("Rig"))
body = B.build_body(L.collection("Body"))
L.parent_to_armature(body, arm, auto=True)
if "--fixed" in sys.argv:
    L.limit_leg_weights(body)
names = {g.index: g.name for g in body.vertex_groups}
bands = {}
for v in body.data.vertices:
    if abs(v.co.x) > 0.25:
        continue
    zb = round(v.co.z * 20) / 20
    if zb < 0.80 or zb > 1.15:
        continue
    leg = sum(g.weight for g in v.groups if "UpperLeg" in names[g.group])
    tot = sum(g.weight for g in v.groups) or 1
    b = bands.setdefault("%.2f" % zb, [0.0, 0])
    b[0] = max(b[0], leg / tot)
print("FNDIAG", json.dumps({k: round(v[0], 3) for k, v in sorted(bands.items())}))
