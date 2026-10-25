"""VISUAL-03: clearance of the radio antennas from the face and the magazine path of the reload, measured on a built
character .blend (the deformed meshes, every second frame of the clips).
    blender -b assets/characters/infantry/blender/infantry.blend --python tools/visual03/check_clearance.py -- OUT.json
    blender -b assets/characters/infantry/blender/factions.blend --python tools/visual03/check_clearance.py -- OUT.json
Antenna = the faces of a gear mesh with the Rubber_Black material (helmet goggle straps excluded: they sit on the head).
"""
import json
import os
import sys

import bpy
from mathutils.bvhtree import BVHTree

ARGV = sys.argv[sys.argv.index("--") + 1:]
OUT = ARGV[0]
ACTIONS = ARGV[ARGV.index("--actions") + 1] if "--actions" in ARGV else None
CLIPS = ["Aim", "Fire", "Ready_Idle", "Idle", "Reload", "Walk_F", "Run_F"]


def deformed(o, dg):
    ev = o.evaluated_get(dg)
    me = ev.to_mesh()
    vs = [ev.matrix_world @ v.co for v in me.vertices]
    polys = [tuple(p.vertices) for p in me.polygons]
    mats = [p.material_index for p in me.polygons]
    ev.to_mesh_clear()
    return vs, polys, mats


def main():
    if ACTIONS:
        with bpy.data.libraries.load(os.path.abspath(ACTIONS)) as (src, dst):
            dst.actions = [a for a in src.actions if a in CLIPS]
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    if arm.animation_data is None:
        arm.animation_data_create()
    head = next(o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("Char_Head") and
                o.name.rsplit("_LOD", 1)[-1] in ("0", o.name))
    gear = []
    for o in bpy.data.objects:
        if o.type != "MESH" or "_LOD" in o.name and not o.name.endswith("_LOD0"):
            continue
        if "helmet" in o.name.lower() or "goggle" in o.name.lower():
            continue
        idx = [i for i, m in enumerate(o.data.materials) if m and m.name.startswith("Rubber_Black")]
        if idx and o.find_armature() is not None:
            gear.append((o, set(idx)))
    out = {"head": head.name, "pieces": {}}
    sc = bpy.context.scene
    for clip in CLIPS:
        act = bpy.data.actions.get(clip)
        if act is None:
            continue
        arm.animation_data.action = act
        n = int(act.frame_range[1])
        for f in range(0, n + 1, 2):
            sc.frame_set(f)
            dg = bpy.context.evaluated_depsgraph_get()
            hv, hp, _ = deformed(head, dg)
            tree = BVHTree.FromPolygons(hv, hp)
            for o, idx in gear:
                vs, polys, mats = deformed(o, dg)
                ant = {v for p, m in zip(polys, mats) if m in idx for v in p}
                if not ant:
                    continue
                d = min(tree.find_nearest(vs[i])[3] for i in ant)
                rec = out["pieces"].setdefault(o.name, {})
                if clip not in rec or d < rec[clip]["min_mm"] / 1000:
                    rec[clip] = {"min_mm": round(d * 1000, 1), "frame": f}
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1)


try:
    main()
except Exception:
    import traceback
    traceback.print_exc()
    sys.stdout.flush()
    import os
    os._exit(1)
import os
os._exit(0)
