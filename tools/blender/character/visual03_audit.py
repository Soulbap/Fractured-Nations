"""VISUAL-03 audit of the shipped CHARACTER-01 soldier (infantry.blend): renders and gait numbers.

Opens assets/characters/infantry/blender/infantry.blend read-only (never saved) and writes
  <out>/before_<look>_<view>.jpg      rest pose and Idle, bare body and dressed
  <out>/before_<clip>_side.jpg / _front.jpg   8-frame contact sheets of a locomotion clip
  <out>/before_gait.json             pelvis / knee / hip numbers per clip (see gait_numbers)
    blender -b assets/characters/infantry/blender/infantry.blend --python tools/blender/character/visual03_audit.py -- OUT_DIR
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import char_lib as L  # noqa: E402

OUT = sys.argv[sys.argv.index("--") + 1]
os.makedirs(OUT, exist_ok=True)
arm = bpy.data.objects["InfantryRig"]
DRESSED = ("uniform_jacket", "uniform_trousers", "uniform_boots", "uniform_gloves", "vest_standard",
           "belt_standard", "helmet_covered", "carbine", "optic_reddot", "foregrip", "Char_Head")
BARE = ("Char_Torso", "Char_Arms", "Char_Legs", "Char_Feet", "Char_Hands", "Char_Head")


def show(names):
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        base = o.name.rsplit("_LOD", 1)[0]
        o.hide_render = not (o.name.endswith("_LOD0") and base in names)


def set_clip(name):
    arm.animation_data_create()
    arm.animation_data.action = bpy.data.actions[name] if name else None
    if not name:
        for pb in arm.pose.bones:
            pb.location = Vector()
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.rotation_euler = (0, 0, 0)


def views(prefix, frame=0):
    for v, az in (("front", 0), ("q34", 35), ("side", 90), ("back", 180)):
        L.render_view(os.path.join(OUT, f"{prefix}_{v}.jpg"), (0, 0, 0.92), 3.4, az, 4, lens=50, res=(560, 880), frame=frame)


def sheet(clip, view, az, n=8):
    act = bpy.data.actions[clip]
    f0, f1 = act.frame_range
    paths = []
    for i in range(n):
        f = int(round(f0 + (f1 - f0) * i / n))
        p = os.path.join(OUT, f"_tmp_{clip}_{view}_{i}.png")
        L.render_view(p, (0, 0, 0.92), 3.4, az, 4, lens=50, res=(300, 520), frame=f)
        paths.append(p)
    L.contact_sheet(paths, os.path.join(OUT, f"before_{clip}_{view}.png"), n)
    for p in paths:
        os.remove(p)


def world(bone, head=True):
    pb = arm.pose.bones[bone]
    return arm.matrix_world @ (pb.head if head else pb.tail)


def angle(a, b):
    return math.degrees(a.angle(b)) if a.length > 1e-6 and b.length > 1e-6 else 0.0


def gait_numbers(clip):
    """Per frame: pelvis yaw (deg, + = left hip ahead), obliquity (deg, + = left hip higher),
    lateral and vertical pelvis travel (cm), knee flexion and hip flexion per side, and the
    fore/aft foot positions, so the phase of pelvis rotation can be compared with the legs."""
    act = bpy.data.actions[clip]
    set_clip(clip)
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    rows = []
    for f in range(f0, f1):
        bpy.context.scene.frame_set(f)
        lh, rh = world("LeftUpperLeg"), world("RightUpperLeg")
        axis = rh - lh       # left -> right hip joint
        yaw = math.degrees(math.atan2(axis.y, axis.x))   # left hip ahead -> right hip behind -> axis.y < 0 ... sign below
        obl = math.degrees(math.atan2(lh.z - rh.z, abs(axis.x)))
        mid = (lh + rh) * 0.5
        r = {"f": f, "pelvis_yaw": round(-yaw, 2), "obliquity": round(obl, 2),
             "pelvis_x_cm": round(mid.x * 100, 2), "pelvis_z_cm": round(mid.z * 100, 2)}
        for s in ("Left", "Right"):
            hip, knee, ank = world(s + "UpperLeg"), world(s + "LowerLeg"), world(s + "Foot")
            r[s[0] + "_knee_flex"] = round(180 - angle(hip - knee, ank - knee), 1)
            thigh = knee - hip
            r[s[0] + "_hip_flex"] = round(math.degrees(math.atan2(thigh.y, -thigh.z)), 1)
            r[s[0] + "_foot_y_cm"] = round(ank.y * 100, 1)
        rows.append(r)

    def rng(k):
        v = [x[k] for x in rows]
        return [round(min(v), 2), round(max(v), 2)]
    # Phase check: pelvis yaw should be positive (left hip ahead) when the left foot is ahead.
    corr = sum((x["pelvis_yaw"]) * (x["L_foot_y_cm"] - x["R_foot_y_cm"]) for x in rows)
    summary = {k: rng(k) for k in ("pelvis_yaw", "obliquity", "pelvis_x_cm", "pelvis_z_cm", "L_knee_flex", "L_hip_flex")}
    summary["pelvis_yaw_follows_leading_leg"] = corr > 0
    # Obliquity: during left stance (left foot moving back, under the body) the right (swing) side should drop -> + obliquity.
    summary["frames"] = f1 - f0
    return summary, rows


L.setup_render((560, 880))
bpy.context.scene.render.image_settings.file_format = "JPEG"
report = {}
for look, names in (("bare", BARE), ("dressed", DRESSED)):
    show(names)
    set_clip(None)
    views(f"before_{look}_rest")
    set_clip("Idle")
    views(f"before_{look}_idle")
show(DRESSED)
bpy.context.scene.render.image_settings.file_format = "PNG"
for clip in ("Walk_F", "Run_F", "CrouchWalk_F"):
    set_clip(clip)
    sheet(clip, "side", 90)
    sheet(clip, "front", 0)
for clip in ("Walk_F", "Jog_F", "Run_F", "CrouchWalk_F", "Idle"):
    s, rows = gait_numbers(clip)
    report[clip] = {"summary": s, "frames": rows}
with open(os.path.join(OUT, "before_gait.json"), "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=1)
os._exit(0)
