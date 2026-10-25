"""VISUAL-03 prototype build: anatomical body + rig, review renders, mocap previews.

    blender -b --factory-startup --python tools/blender/character/v03_proto.py -- OUT_DIR [--stage body|all]

Writes OUT_DIR/proto_<pose>_<view>.jpg, OUT_DIR/proto_measure.json and (stage all) the motion previews, and
saves assets/characters/infantry/blender/v03_proto.blend.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402
from mathutils import Quaternion, Vector  # noqa: E402

import char_lib as L  # noqa: E402
import v03_body as VB  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
STAGE = argv[argv.index("--stage") + 1] if "--stage" in argv else "body"
os.makedirs(OUT, exist_ok=True)
PROJECT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))


def skin_material():
    m = L.pbr_material("Skin_Proto", (0.72, 0.56, 0.47), 0.55)
    return m


def measure(arm, body):
    """Silhouette widths at landmark heights (front view), joint table, stature."""
    vs = [body.matrix_world @ v.co for v in body.data.vertices]
    out = {"stature": round(max(v.z for v in vs), 4), "joints": VB.joint_table(arm), "widths": {}, "depths": {}}
    for name, z in (("shoulders", 1.45), ("chest", 1.30), ("waist", 1.08), ("hips_crest", 1.00), ("trochanters", 0.92),
                    ("crotch-5cm", 0.80), ("mid_thigh", 0.70), ("knee", 0.50), ("calf", 0.38), ("ankle", 0.10)):
        band = [v for v in vs if abs(v.z - z) < 0.006]
        if band:
            out["widths"][name] = round(max(v.x for v in band) - min(v.x for v in band), 3)
            out["depths"][name] = round(max(v.y for v in band) - min(v.y for v in band), 3)
    crotch = min((v.z for v in vs if abs(v.x) < 0.01 and v.z > 0.5 and v.z < 1.0), default=None)
    out["crotch_height"] = round(crotch, 4) if crotch else None
    return out


def pose_reset(arm):
    for pb in arm.pose.bones:
        pb.location = Vector()
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion()
        pb.scale = Vector((1, 1, 1))


def rot_world(arm, bone, axis, deg):
    """Rotates a pose bone by a world-space axis/angle about its head (parents as currently posed)."""
    bpy.context.view_layer.update()
    pb = arm.pose.bones[bone]
    mw = pb.matrix.copy()
    q = Quaternion(Vector(axis).normalized(), math.radians(deg))
    rot = q.to_matrix().to_4x4()
    h = mw.translation.copy()
    new = rot @ mw
    new.translation = h
    pb.matrix = new
    bpy.context.view_layer.update()


FINGER_CURL = {"Index": (18, 22, 12), "Middle": (22, 26, 14), "Ring": (26, 28, 14), "Little": (30, 30, 16)}


def relax_hands(arm, sign=1.0):
    """Natural resting curl of the fingers (local bend about each finger bone's X axis)."""
    for s in ("Left", "Right"):
        for f, angs in FINGER_CURL.items():
            for seg, a in zip(("Proximal", "Intermediate", "Distal"), angs):
                pb = arm.pose.bones[s + f + seg]
                pb.rotation_mode = "QUATERNION"
                pb.rotation_quaternion = Quaternion((1, 0, 0), math.radians(sign * a))
        for seg, a in zip(("Proximal", "Distal"), (10, 14)):
            pb = arm.pose.bones[s + "Thumb" + seg]
            pb.rotation_quaternion = Quaternion((1, 0, 0), math.radians(sign * a))


def stance_legs(arm, ankle_x=0.115):
    """Brings the feet under the hips (MakeHuman's rest stands with the feet ~0.4 m apart)."""
    bpy.context.view_layer.update()
    for side, s in ((-1, "Left"), (1, "Right")):
        h = arm.pose.bones[s + "UpperLeg"].head
        a = arm.pose.bones[s + "Foot"].head
        cur = math.atan2(abs(a.x) - abs(h.x), h.z - a.z)
        want = math.atan2(ankle_x - abs(h.x), h.z - a.z)
        rot_world(arm, s + "UpperLeg", (0, 1, 0), side * math.degrees(cur - want))
        rot_world(arm, s + "Foot", (0, 1, 0), -side * math.degrees(cur - want))


def pose_neutral(arm):
    """Arms hanging at the sides, palms in (from the A-pose rest), feet under the hips, fingers relaxed."""
    pose_reset(arm)
    stance_legs(arm)
    relax_hands(arm)
    for side, s in ((-1, "Left"), (1, "Right")):
        ua = arm.pose.bones[s + "UpperArm"]
        d = (ua.tail - ua.head).normalized()
        target = Vector((side * 0.12, 0.02, -1)).normalized()
        ax = d.cross(target)
        rot_world(arm, s + "UpperArm", ax, math.degrees(d.angle(target)))
        rot_world(arm, s + "LowerArm", (1, 0, 0), -8)


def pose_ready(arm):
    """Relaxed ready stance without a weapon: feet shoulder width, support foot a half step forward,
    knees soft (~8 deg), slight forward lean, hands in front at belt height."""
    pose_neutral(arm)
    rot_world(arm, "Hips", (0, 0, 1), -10)
    rot_world(arm, "Spine", (1, 0, 0), -4)
    rot_world(arm, "Chest", (0, 0, 1), 6)
    for side, s in ((-1, "Left"), (1, "Right")):
        rot_world(arm, s + "UpperLeg", (1, 0, 0), 6 if side < 0 else -4)
        rot_world(arm, s + "LowerLeg", (1, 0, 0), -10)
        rot_world(arm, s + "Foot", (1, 0, 0), 4)
        rot_world(arm, s + "UpperArm", (1, 0, 0), 18)
        rot_world(arm, s + "LowerArm", (1, 0, 0), 55)


def _legs(arm, side, hip_flex, knee_flex, abduct=0.0):
    s = "Left" if side < 0 else "Right"
    rot_world(arm, s + "UpperLeg", (1, 0, 0), hip_flex)
    if abduct:
        rot_world(arm, s + "UpperLeg", (0, 1, 0), -side * abduct)      # + = foot away from the midline
    rot_world(arm, s + "LowerLeg", (1, 0, 0), -knee_flex)
    rot_world(arm, s + "Foot", (1, 0, 0), knee_flex - hip_flex)


# name -> list of (side, hip flexion, knee flexion, abduction) + extra torso / arm moves
STRESS = {
    "lunge": [(-1, 65, 75, 0), (1, -25, 10, 0)],
    "squat": [(-1, 105, 125, 12), (1, 105, 125, 12)],
    "kneel": [(-1, 85, 85, 5), (1, -5, 95, 0)],
    "high_knee": [(-1, 95, 110, 0), (1, -15, 15, 0)],
    "wide_step": [(-1, 20, 15, 30), (1, -20, 5, 25)],
    "aim_twist": [(-1, 10, 12, 4), (1, -8, 10, 6)],
}


def pose_stress(arm, name):
    pose_neutral(arm)
    for side, hf, kf, ab in STRESS[name]:
        _legs(arm, side, hf, kf, ab)
    if name in ("squat", "kneel"):
        rot_world(arm, "Spine", (1, 0, 0), -20)
    if name == "aim_twist":
        rot_world(arm, "Spine", (0, 0, 1), -15)
        rot_world(arm, "Chest", (0, 0, 1), -12)
        # shooting-hand elbow out and back, support arm reaching forward to the handguard
        rot_world(arm, "RightUpperArm", (1, 0, 0), 55)
        rot_world(arm, "RightUpperArm", (0, 1, 0), 30)
        rot_world(arm, "RightLowerArm", (1, 0, 0), 50)
        rot_world(arm, "LeftUpperArm", (1, 0, 0), 70)
        rot_world(arm, "LeftUpperArm", (0, 0, 1), -20)
        rot_world(arm, "LeftLowerArm", (1, 0, 0), 15)


def render_views(prefix, frame=None, target_z=0.92):
    for v, az in (("front", 0), ("q34", 35), ("side", 90), ("back", 180)):
        L.render_view(os.path.join(OUT, f"{prefix}_{v}.jpg"), (0, 0, target_z), 3.4, az, 4, lens=50, res=(560, 880),
                      frame=frame)


MOCAP_DIR = os.path.join(PROJECT, "assets", "characters", "infantry", "mocap", "cmu")
# clip name -> (BVH, which detected cycle: index into the steady-state strikes)
# Chosen after the comparison renders (report §4.3): 16_15 walk, 16_21 brisk walk, 35_17 jog, 16_46 run.
# Rejected: 35_01 (one foot hovers / slips after retarget), 16_55 (hunched run), 141_02 (half-cycle take).
LOCO = {"Walk_F": ("16_15.bvh", None), "Brisk_F": ("16_21.bvh", None), "Jog_F": ("35_17.bvh", None),
        "Run_F": ("16_46.bvh", None)}
LOCO_FRAMES = 32


def ground_fix(arm, body, act, frames):
    """Shifts the Hips keys so the lowest sole vertex over the cycle touches z = 0 (mocap ground differs)."""
    import v03_mocap as MC  # noqa: F401
    sc = bpy.context.scene
    arm.animation_data.action = act
    deps = bpy.context.evaluated_depsgraph_get()
    low = []
    for f in range(0, frames, 2):
        sc.frame_set(f)
        ev = body.evaluated_get(deps)
        me = ev.to_mesh()
        low.append(min((ev.matrix_world @ v.co).z for v in me.vertices))
        ev.to_mesh_clear()
    dz = -min(low)
    hb = arm.data.bones["Hips"]
    # Hips location is in bone space: convert the world z shift.
    d_local = hb.matrix_local.to_3x3().inverted() @ Vector((0, 0, dz))
    for fc in _fcurves(act, "Hips", "location"):
        for kp in fc.keyframe_points:
            kp.co.y += d_local[fc.array_index]
            kp.handle_left.y += d_local[fc.array_index]
            kp.handle_right.y += d_local[fc.array_index]
    return dz, min(low)


def _fcurves(act, bone, prop):
    path = f'pose.bones["{bone}"].{prop}'
    curves = []
    if hasattr(act, "layers") and len(act.layers):
        for lay in act.layers:
            for st in lay.strips:
                for cb in st.channelbags:
                    curves += [fc for fc in cb.fcurves if fc.data_path == path]
    else:
        curves = [fc for fc in act.fcurves if fc.data_path == path]
    return curves


def foot_slip(arm, act, frames, speed, period):
    """Mean / p90 horizontal speed of the planted foot (ankle) relative to the ground when the body moves at
    `speed` (in place clip): planted = lowest 35 % of the ankle heights."""
    sc = bpy.context.scene
    arm.animation_data.action = act
    dt = period / frames
    res = {}
    for side in ("LeftFoot", "RightFoot"):
        ps = []
        for f in range(frames + 1):
            sc.frame_set(f)
            ps.append((arm.matrix_world @ arm.pose.bones[side].head).copy())
        zs = sorted(p.z for p in ps)
        zlim = zs[int(len(zs) * 0.35)]
        sl = []
        for i in range(1, len(ps)):
            if ps[i].z <= zlim and ps[i - 1].z <= zlim:
                v = (ps[i] - ps[i - 1]) / dt + Vector((0, speed, 0))
                sl.append(Vector((v.x, v.y)).length)
        sl.sort()
        res[side] = {"mean": round(sum(sl) / max(1, len(sl)), 3), "p90": round(sl[int(len(sl) * 0.9)] if sl else 0, 3)}
    return res


def gait_numbers(arm, act, frames):
    """Same measurements as visual03_audit.gait_numbers, on the prototype."""
    sc = bpy.context.scene
    arm.animation_data.action = act
    rows = []
    mw = arm.matrix_world
    for f in range(frames):
        sc.frame_set(f)
        P = lambda n: mw @ arm.pose.bones[n].head  # noqa: E731
        lh, rh = P("LeftUpperLeg"), P("RightUpperLeg")
        ax = rh - lh
        r = {"pelvis_yaw": -math.degrees(math.atan2(ax.y, ax.x)), "obliquity": math.degrees(math.atan2(lh.z - rh.z, abs(ax.x))),
             "pelvis_x_cm": (lh + rh).x * 50, "pelvis_z_cm": (lh + rh).z * 50}
        for s in ("Left", "Right"):
            hip, knee, ank = P(s + "UpperLeg"), P(s + "LowerLeg"), P(s + "Foot")
            r[s[0] + "_knee_flex"] = 180 - math.degrees((hip - knee).angle(ank - knee))
            th = knee - hip
            r[s[0] + "_hip_flex"] = math.degrees(math.atan2(th.y, -th.z))
            r[s[0] + "_foot_y"] = ank.y
        rows.append(r)
    out = {k: [round(min(x[k] for x in rows), 1), round(max(x[k] for x in rows), 1)]
           for k in ("pelvis_yaw", "obliquity", "pelvis_x_cm", "pelvis_z_cm", "L_knee_flex", "L_hip_flex")}
    out["pelvis_yaw_follows_leading_leg"] = sum(x["pelvis_yaw"] * (x["L_foot_y"] - x["R_foot_y"]) for x in rows) > 0
    return out


def checker_ground():
    import bmesh
    g = bpy.data.objects.get("PreviewGround")
    if g:
        bpy.data.objects.remove(g, do_unlink=True)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=30)
    me = bpy.data.meshes.new("GridGround")
    bm.to_mesh(me)
    ob = bpy.data.objects.new("PreviewGround", me)
    bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.new("GridMat")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    chk = nt.nodes.new("ShaderNodeTexChecker")
    chk.inputs["Scale"].default_value = 60.0          # 0.5 m squares on the 60 m plane (UV 0..1 -> 30 cells... x2)
    chk.inputs["Color1"].default_value = (0.20, 0.19, 0.17, 1)
    chk.inputs["Color2"].default_value = (0.32, 0.30, 0.27, 1)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(tc.outputs["Generated"], chk.inputs["Vector"])
    nt.links.new(chk.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.95
    me.materials.append(mat)


def render_motion(arm, act, name, speed, period, frames, cycles=2, views=(("side", 90), ("front", 0), ("q34", 35))):
    """Renders the clip with the character travelling at `speed` over a checker floor (camera follows), so foot
    slip is visible. Writes <name>_<view>.gif and an 8-frame <name>_<view>_sheet.png."""
    sc = bpy.context.scene
    arm.animation_data.action = act
    dt = period / frames
    paths = {v: [] for v, _ in views}
    for i in range(frames * cycles):
        f = i % frames
        sc.frame_set(f)
        y = speed * dt * i
        arm.location = (0, y, 0)
        bpy.context.view_layer.update()
        for v, az in views:
            p = os.path.join(OUT, "_tmp", f"{name}_{v}_{i:03d}.png")
            L.render_view(p, (0, y, 0.92), 3.6, az, 6, lens=45, res=(420, 620))
            paths[v].append(p)
    arm.location = (0, 0, 0)
    return paths


def main():
    L.clear_scene()
    arm, body = VB.build_human()
    body.data.materials.clear()
    body.data.materials.append(skin_material())
    for p in body.data.polygons:
        p.use_smooth = True
    m = measure(arm, body)
    with open(os.path.join(OUT, "proto_measure.json"), "w", encoding="utf-8") as fh:
        json.dump(m, fh, indent=1)
    L.setup_render((560, 880))
    bpy.context.scene.render.image_settings.file_format = "JPEG"
    arm.hide_render = True
    if "--nostills" not in argv:
        pose_reset(arm)
        render_views("proto_rest")
        pose_neutral(arm)
        render_views("proto_neutral")
    if "--stress" in argv:
        for name in STRESS:
            pose_stress(arm, name)
            for v, az in (("front", 0), ("q34", 35), ("side", 90), ("back", 180)):
                L.render_view(os.path.join(OUT, f"stress_{name}_{v}.jpg"), (0, 0, 0.75), 3.0, az, 8, lens=50,
                              res=(480, 640))
            if name in ("lunge", "squat", "wide_step", "kneel"):      # groin / hip close-ups
                bpy.context.view_layer.update()
                hz = arm.pose.bones["Hips"].head.z
                for v, az in (("front", 0), ("q34", 35), ("back", 180)):
                    L.render_view(os.path.join(OUT, f"stress_{name}_hip_{v}.jpg"), (0, 0, hz - 0.08), 1.3, az, 4, lens=50,
                                  res=(480, 480))
    pose_reset(arm)
    if STAGE == "all":
        import v03_mocap as MC
        checker_ground()
        bpy.context.scene.render.image_settings.file_format = "PNG"
        results = {}
        only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else list(LOCO)
        for clip in only:
            bvh, pick = LOCO[clip]
            path = os.path.join(MOCAP_DIR, bvh)
            if not os.path.exists(path):        # the takes are committed zipped
                import zipfile
                zipfile.ZipFile(os.path.join(MOCAP_DIR, "zip", bvh.replace(".bvh", ".zip"))).extractall(MOCAP_DIR)
            src, f0, n, ft = MC.load_bvh(path)
            samples = MC.sample(src, f0, n)
            i0, i1, phase = MC.pick_cycle(samples)
            strikes = [i0, i1]
            act, speed, period = MC.retarget_cycle(src, arm, samples, i0, i1, ft, LOCO_FRAMES, clip, phase=phase)
            dz, low = ground_fix(arm, body, act, LOCO_FRAMES)
            slip = MC.foot_slip(arm, act, LOCO_FRAMES, speed, period)
            lock = MC.foot_lock(arm, act, LOCO_FRAMES, speed, period) if "--nolock" not in argv else None
            slip_after = MC.foot_slip(arm, act, LOCO_FRAMES, speed, period)
            gait = gait_numbers(arm, act, LOCO_FRAMES)
            results[clip] = {"bvh": bvh, "strikes": strikes, "cycle": [i0, i1], "speed_ms": round(speed, 3),
                             "period_s": round(period, 3), "stride_m": round(speed * period, 3), "ground_shift_m": round(dz, 3),
                             "slip": slip, "foot_lock": lock, "slip_after_lock": slip_after, "phase": round(phase, 3), "gait": gait}
            print("CLIP", clip, results[clip])
            if "--norender" not in argv:
                paths = render_motion(arm, act, clip, speed, period, LOCO_FRAMES)
                results[clip]["frames"] = {v: p for v, p in paths.items()}
            bpy.data.objects.remove(src, do_unlink=True)
        with open(os.path.join(OUT, "proto_motion.json"), "w", encoding="utf-8") as fh:
            json.dump(results, fh, indent=1)
        arm.animation_data.action = None
        pose_reset(arm)
    path = os.path.join(PROJECT, "assets", "characters", "infantry", "blender", "v03_proto.blend")
    if STAGE == "all":
        bpy.ops.wm.save_as_mainfile(filepath=path, check_existing=False)


try:
    main()
except Exception:
    import traceback
    traceback.print_exc()
    sys.stdout.flush()
    os._exit(1)
os._exit(0)
