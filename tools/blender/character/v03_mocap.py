"""VISUAL-03 mocap retargeting: CMU BVH (cgspeed conversion) -> shared infantry skeleton.

Method (world-space rest-relative transfer):
  T_w(f) = S_w(f) * S_w(rest)^-1 * C^-1 * T_w(rest)
where S_w is the source bone's world rotation, T_w the target's and C the minimal rotation that turns the source
bone's rest direction onto the target bone's rest direction (absorbs T-pose vs A-pose and small layout
differences). Bone lengths are never changed; only Hips gets a translation, scaled by the leg-length ratio.
Locomotion is cut to one gait cycle (left heel strike to left heel strike), turned so the travel direction is +Y,
made in place (the mean travel is removed, sway and bob stay), resampled to a fixed frame count and made
seamless by distributing the end-start pose difference over the cycle.
"""
import math
import os

import bpy
from mathutils import Matrix, Quaternion, Vector

# target bone -> (source bone, source child joint used for the bone direction)
MAP = {
    "Hips": ("Hips", None),
    "Spine": ("LowerBack", "Spine"),
    "Chest": ("Spine", "Spine1"),
    "UpperChest": ("Spine1", "Neck1"),
    "Neck": ("Neck1", "Head"),
    "Head": ("Head", None),
}
for _s in ("Left", "Right"):
    MAP.update({
        _s + "Shoulder": (_s + "Shoulder", _s + "Arm"),
        _s + "UpperArm": (_s + "Arm", _s + "ForeArm"),
        _s + "LowerArm": (_s + "ForeArm", _s + "Hand"),
        _s + "Hand": (_s + "Hand", _s + "HandIndex1"),
        _s + "UpperLeg": (_s + "UpLeg", _s + "Leg"),
        _s + "LowerLeg": (_s + "Leg", _s + "Foot"),
        _s + "Foot": (_s + "Foot", _s + "ToeBase"),
        _s + "Toes": (_s + "ToeBase", None),
    })


SKIP = 2


def load_bvh(path):
    before = set(bpy.data.objects)
    bpy.ops.import_anim.bvh(filepath=path, global_scale=1.0, frame_start=0, use_fps_scale=False,
                            update_scene_fps=False, update_scene_duration=False, rotate_mode="NATIVE",
                            axis_forward="-Z", axis_up="Y")
    src = next(o for o in bpy.data.objects if o not in before)
    src.hide_render = True
    act = src.animation_data.action
    # The cgspeed conversion stores the T-pose calibration pose in the first frame: skip it.
    n = int(act.frame_range[1] - act.frame_range[0]) + 1 - SKIP
    f_first = int(act.frame_range[0]) + SKIP
    with open(path, encoding="utf-8", errors="ignore") as fh:
        ft = next(float(l.split(":")[1]) for l in fh if l.startswith("Frame Time"))
    return src, f_first, n, ft


def _head_w(obj, name, posed=True):
    if posed:
        return obj.matrix_world @ obj.pose.bones[name].head
    return obj.matrix_world @ obj.data.bones[name].head_local


def sample(src, f0, n, step=1):
    """Per sampled frame: {bone: (world rotation quaternion, world head)} for every source bone."""
    sc = bpy.context.scene
    out = []
    mw = src.matrix_world
    for f in range(f0, f0 + n, step):
        sc.frame_set(f)
        fr = {}
        for pb in src.pose.bones:
            m = mw @ pb.matrix
            fr[pb.name] = (m.to_quaternion().normalized(), m.translation.copy())
        out.append(fr)
    return out


def rest_frames(obj, turn=None):
    """{bone: (world rest rotation, world rest head)}, optionally turned by `turn` (quaternion about the origin)."""
    mw = obj.matrix_world
    t = turn or Quaternion()
    return {b.name: ((t @ (mw @ b.matrix_local).to_quaternion()).normalized(), t @ (mw @ b.head_local))
            for b in obj.data.bones}


def rest_facing(src):
    """Quaternion about +Z that turns the source rest pose to face +Y (forward = up x right)."""
    mw = src.matrix_world
    right = (mw @ src.data.bones["RightUpLeg"].head_local) - (mw @ src.data.bones["LeftUpLeg"].head_local)
    fwd = Vector((0, 0, 1)).cross(right)
    return Quaternion((0, 0, 1), math.atan2(fwd.x, fwd.y))


def min_rot(a, b):
    a, b = a.normalized(), b.normalized()
    return a.rotation_difference(b)


def corrections(src, arm):
    """C per target bone: source rest direction (turned to face +Y) -> target rest direction (world)."""
    srest = rest_frames(src, rest_facing(src))
    out = {}
    for tb, (sb, schild) in MAP.items():
        if tb not in arm.data.bones or sb not in src.data.bones:
            continue
        b = arm.data.bones[tb]
        tdir = (arm.matrix_world @ b.tail_local) - (arm.matrix_world @ b.head_local)
        if schild and schild in src.data.bones:
            sdir = srest[schild][1] - srest[sb][1]
        else:
            sdir = (rest_facing(src) @ (src.matrix_world @ src.data.bones[sb].tail_local)) - srest[sb][1]
        if sdir.length < 1e-6 or tb == "Hips":
            out[tb] = Quaternion()
        else:
            out[tb] = min_rot(sdir, tdir)
    return out


def leg_length(obj, posed=False):
    if obj.type != "ARMATURE":
        return 1.0
    names = ("LeftUpLeg", "LeftLeg", "LeftFoot") if "LeftUpLeg" in obj.data.bones else ("LeftUpperLeg", "LeftLowerLeg", "LeftFoot")
    p = [_head_w(obj, n, posed) for n in names]
    return (p[1] - p[0]).length + (p[2] - p[1]).length


def find_cycles(samples, dt, side="Left"):
    """Left heel strikes: frames where the foot becomes (nearly) stationary after moving."""
    foot = side + "Foot"
    pos = [s[foot][1] for s in samples]
    sp = [0.0] + [((pos[i] - pos[i - 1]).xy.length) / dt for i in range(1, len(pos))]
    k = 3
    sm = [sum(sp[max(0, i - k):i + k + 1]) / len(sp[max(0, i - k):i + k + 1]) for i in range(len(sp))]
    vmax = sorted(sm)[int(len(sm) * 0.9)]        # robust against single-frame spikes
    strikes = []
    moving = False
    for i, v in enumerate(sm):
        if v > 0.5 * vmax:
            moving = True
        elif moving and v < 0.25 * vmax:
            strikes.append(i)
            moving = False
    return strikes


def contact_onsets(samples, side="Left"):
    """Frames where the foot (lowest of ankle and toe joint) comes down into contact; works for short running takes
    where the foot is never stationary for long."""
    z = [min(s[side + "Foot"][1].z, s[side + "ToeBase"][1].z) for s in samples]
    zs = sorted(z)
    lo, hi = zs[int(len(zs) * 0.05)], zs[int(len(zs) * 0.95)]
    thr, rearm = lo + 0.25 * (hi - lo), lo + 0.6 * (hi - lo)
    out, armed = [], False
    for i in range(1, len(z)):
        if z[i] > rearm:
            armed = True
        elif armed and z[i] <= thr < z[i - 1]:
            out.append(i)
            armed = False
    return out


def pick_cycle(samples, n_hint=None):
    """(i0, i1, phase): one gait cycle (onset to onset of the same foot) nearest the middle of the take; phase is the
    fraction of the cycle at which the *left* foot strikes (0 when the cycle is a left one)."""
    n = len(samples)
    best = None
    for side in ("Left", "Right"):
        on = contact_onsets(samples, side)
        other = contact_onsets(samples, "Right" if side == "Left" else "Left")
        for a, b in zip(on, on[1:]):
            if a < 3:
                continue
            ph = 0.0
            if side == "Right":
                inner = [o for o in other if a < o < b]
                if not inner:
                    continue
                ph = (inner[0] - a) / (b - a)
            score = abs((a + b) / 2 - n / 2) + (0 if side == "Left" else 1000)     # left cycles first
            if best is None or score < best[0]:
                best = (score, a, b, ph)
    if best is None:
        raise RuntimeError("no full gait cycle in take")
    return best[1], best[2], best[3]


def cycle_motion(samples, i0, i1, dt):
    hip = [s["Hips"][1] for s in samples[i0:i1 + 1]]
    d = hip[-1] - hip[0]
    d.z = 0
    T = (i1 - i0) * dt
    return d, T


def retarget_cycle(src, arm, samples, i0, i1, dt, frames, action_name, in_place=True, loop=True, phase=0.0):
    """Bakes samples[i0..i1] into a new action on arm with `frames` keys (frame 0 == frame `frames` when loop)."""
    corr = corrections(src, arm)
    srest = rest_frames(src, rest_facing(src))
    trest = {b.name: b.matrix_local.copy() for b in arm.data.bones}
    scale = leg_length(arm) / leg_length(src)
    travel, T = cycle_motion(samples, i0, i1, dt)
    heading = math.atan2(travel.x, travel.y) if travel.length > 0.05 else 0.0
    Rz = Quaternion((0, 0, 1), heading)            # rotates the travel direction onto +Y
    hip0 = samples[i0]["Hips"][1].copy()
    speed = travel.length / T * scale
    # Hip height: source hips relative to its ground (lowest foot over the clip), scaled.
    ground = min(min(s["LeftToeBase"][1].z, s["RightToeBase"][1].z, s["LeftFoot"][1].z, s["RightFoot"][1].z)
                 for s in samples[i0:i1 + 1])
    tgt_hip_rest = trest["Hips"].translation
    # The root joints differ (CMU Hips sits above the hip joints): match the hip *joint* height instead.
    hip_off = (trest["Hips"].translation.z - trest["LeftUpperLeg"].translation.z) -         scale * (srest["Hips"][1].z - srest["LeftUpLeg"][1].z)
    order = [b.name for b in arm.data.bones]        # parents before children
    act = bpy.data.actions.new(action_name)
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act
    poses = []
    for k in range(frames + (0 if loop else 1)):
        t = k / frames * (i1 - i0)
        a = int(math.floor(t))
        u = t - a
        A, B = samples[i0 + a], samples[min(i0 + a + 1, i1)]
        world = {}
        for tb, (sb, _) in MAP.items():
            if tb not in corr:
                continue
            q = A[sb][0].slerp(B[sb][0], u)
            q = Rz @ q
            tw = q @ srest[sb][0].inverted() @ corr[tb].inverted() @ trest[tb].to_quaternion()
            world[tb] = tw.normalized()
        hp = A["Hips"][1].lerp(B["Hips"][1], u)
        rel = Rz @ (hp - hip0)
        if in_place:
            rel -= Rz @ travel * (t / (i1 - i0))
        hip_pos = Vector((rel.x * scale, rel.y * scale, (hp.z - ground) * scale + hip_off))
        poses.append((world, hip_pos))
    # Loop: spread the end-start difference (rotations and hip position) linearly over the cycle.
    if loop:
        world_e, hip_e = _pose_at(samples, i1, Rz, corr, srest, trest), None
        hp = samples[i1]["Hips"][1]
        rel = Rz @ (hp - hip0) - (Rz @ travel if in_place else Vector())
        hip_e = Vector((rel.x * scale, rel.y * scale, (hp.z - ground) * scale + hip_off))
        w0, h0 = poses[0]
        for k, (world, hp_) in enumerate(poses):
            u = k / frames
            for tb in world:
                d = world_e[tb] @ w0[tb].inverted()        # end vs start
                corr_q = Quaternion().slerp(d, u).inverted()
                world[tb] = (corr_q @ world[tb]).normalized()
            poses[k] = (world, hp_ - (hip_e - h0) * u)
        if phase:
            k0 = int(round(phase * frames)) % frames
            # hip positions are in place, so rotating the loop only needs the forward travel continuity: none (in place)
            poses = poses[k0:] + poses[:k0]
        poses.append(poses[0])
    for k, (world, hip_pos) in enumerate(poses):
        _apply_pose(arm, order, trest, world, hip_pos, tgt_hip_rest)
        for name in world:
            pb = arm.pose.bones[name]
            pb.keyframe_insert("rotation_quaternion", frame=k, group=name)
            if name == "Hips":
                pb.keyframe_insert("location", frame=k, group=name)
    act["fn_frames"] = frames
    act["fn_loop"] = loop
    act["fn_speed"] = speed
    act["fn_period"] = T
    act.use_fake_user = True
    return act, speed, T


def _pose_at(samples, i, Rz, corr, srest, trest):
    s = samples[i]
    out = {}
    for tb, (sb, _) in MAP.items():
        if tb in corr:
            out[tb] = (Rz @ s[sb][0] @ srest[sb][0].inverted() @ corr[tb].inverted() @ trest[tb].to_quaternion()).normalized()
    return out


def _apply_pose(arm, order, trest, world, hip_pos, hip_rest):
    """Sets pose bases so each mapped bone has the given world rotation (unmapped bones keep their basis)."""
    posed = {}
    for name in order:
        b = arm.data.bones[name]
        pb = arm.pose.bones[name]
        rest = trest[name]
        if b.parent:
            pm = posed[b.parent.name]
            prest = trest[b.parent.name]
            base = pm @ prest.inverted() @ rest            # pose matrix with identity basis
        else:
            base = rest.copy()
        if name in world:
            if name == "Hips":
                head = Vector((hip_pos.x, hip_pos.y, hip_pos.z))
            else:
                head = base.translation
            desired = Matrix.Translation(head) @ world[name].to_matrix().to_4x4()
            basis = base.inverted() @ desired
            loc, rot, _ = basis.decompose()
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = rot
            pb.location = loc if name == "Hips" else Vector()
            posed[name] = desired
        else:
            basis = Matrix.LocRotScale(pb.location, pb.rotation_quaternion, None)
            posed[name] = base @ basis


# ------------------------------------------------------------------------------------------ foot locking


CONTACT_H = 0.03       # a heel / ball point within 3 cm of the floor is in contact


def foot_track(arm, act, frames, speed, period):
    """Per frame and foot: ankle position, contact point (heel or ball, whichever is lower relative to its rest
    height), its height, and its position in ground coordinates (in place clip played at `speed` along +Y)."""
    sc = bpy.context.scene
    arm.animation_data.action = act
    dt = period / frames
    out = {"Left": [], "Right": []}
    for f in range(frames):
        sc.frame_set(f)
        for side in out:
            ft, toe = arm.pose.bones[side + "Foot"], arm.pose.bones[side + "Toes"]
            a = ft.head.copy()
            heel = a - Vector((0, 0, ft.bone.head_local.z))           # ankle over the heel, rest ankle height
            ball = toe.head - Vector((0, 0, toe.bone.head_local.z))
            p = heel if heel.z <= ball.z else ball
            g = Vector((p.x, p.y + speed * dt * f))
            out[side].append({"ankle": a, "pt": p.copy(), "h": p.z, "g": g, "kind": "heel" if p is heel else "ball"})
    return out


def contact_segments(track, frames):
    hmin = min(t["h"] for t in track)
    c = [t["h"] < hmin + CONTACT_H for t in track]
    if all(c):
        return [(0, frames)]
    if not any(c):
        return []
    start = next(i for i in range(frames) if not c[i])
    segs, cur = [], None
    for k in range(1, frames + 1):
        i = (start + k) % frames
        if c[i]:
            if cur is None:
                cur = [i, 0]
            cur[1] += 1
        elif cur is not None:
            segs.append(tuple(cur))
            cur = None
    if cur is not None:
        segs.append(tuple(cur))
    return segs


def foot_slip(arm, act, frames, speed, period):
    """Horizontal speed of the contact point over ground while it stays in contact (m/s): mean, p90, max; plus
    the fraction of the cycle each foot is in contact."""
    tr = foot_track(arm, act, frames, speed, period)
    dt = period / frames
    res = {}
    for side, t in tr.items():
        sl = []
        hmin = min(x["h"] for x in t)
        lim = hmin + CONTACT_H
        for i in range(frames):
            j = (i + 1) % frames
            if t[i]["h"] < lim and t[j]["h"] < lim and t[i]["kind"] == t[j]["kind"]:
                gj = t[j]["g"] + (Vector((0, speed * period)) if j < i else Vector((0, 0)))
                sl.append((gj - t[i]["g"]).length / dt)
        sl.sort()
        res[side] = {"floor_cm": round(hmin * 100, 1), "contact_frac": round(sum(1 for x in t if x["h"] < lim) / frames, 2),
                     "mean": round(sum(sl) / len(sl), 3) if sl else None,
                     "p90": round(sl[int(len(sl) * 0.9)], 3) if sl else None, "max": round(sl[-1], 3) if sl else None}
    return res


def _two_bone(H, K, A_target, l1, l2):
    """New knee and ankle positions for hip H reaching A (knee stays in the plane of the current knee K)."""
    d = A_target - H
    dl = max(1e-4, min(d.length, l1 + l2 - 1e-4))
    dn = d.normalized()
    a = (l1 * l1 - l2 * l2 + dl * dl) / (2 * dl)
    h = math.sqrt(max(0.0, l1 * l1 - a * a))
    pole = (K - H) - dn * (K - H).dot(dn)
    pole = pole.normalized() if pole.length > 1e-6 else Vector((0, 1, 0))
    return H + dn * a + pole * h, H + dn * dl


def _aim(pb, new_dir):
    """Rotates a pose bone (armature space, about its head) so its Y axis points along new_dir."""
    m = pb.matrix.copy()
    cur = m.to_3x3().col[1].normalized()
    q = cur.rotation_difference(new_dir.normalized())
    out = (q.to_matrix() @ m.to_3x3()).to_4x4()
    out.translation = m.translation
    pb.matrix = out


def foot_lock(arm, act, frames, speed, period, blend=2):
    """Pins each contact segment's contact point to one ground position (mean over the segment), moving the ankle
    by the same offset with two-bone IK; the foot keeps its orientation. Blends in/out over `blend` frames."""
    sc = bpy.context.scene
    tr = foot_track(arm, act, frames, speed, period)
    dt = period / frames
    report = {}
    for side, t in tr.items():
        ul, ll, ft = arm.pose.bones[side + "UpperLeg"], arm.pose.bones[side + "LowerLeg"], arm.pose.bones[side + "Foot"]
        l1 = (ll.bone.head_local - ul.bone.head_local).length
        l2 = (ft.bone.head_local - ll.bone.head_local).length
        segs = contact_segments(t, frames)
        # Each foot's own floor: mocap marker offsets leave one foot hovering or sinking a few cm.
        hmin = min(x["h"] for x in t)
        target = {i: t[i]["ankle"] - Vector((0, 0, hmin)) for i in range(frames)}
        for s0, ln in segs:
            bl = blend if ln >= 8 else 1
            idx = [(s0 + k) % frames for k in range(ln)]
            wrap = [i < s0 for i in idx]
            g = [t[i]["g"] + (Vector((0, speed * period)) if w else Vector((0, 0))) for i, w in zip(idx, wrap)]
            # One lock per contact point: the heel and the ball are different points of the foot (rolling over
            # from heel to ball must not drag the ball to where the heel was).
            locks = {}
            for kind in ("heel", "ball"):
                gk = [gg for gg, i in zip(g, idx) if t[i]["kind"] == kind]
                if gk:
                    locks[kind] = sum(gk, Vector((0, 0))) / len(gk)
            for k, (i, w) in enumerate(zip(idx, wrap)):
                lock = locks[t[i]["kind"]]
                wgt = min(1.0, (k + 1) / (bl + 1), (ln - k) / (bl + 1))
                gl = lock - (Vector((0, speed * period)) if w else Vector((0, 0)))
                pt = t[i]["pt"] - Vector((0, 0, hmin))
                want_pt = Vector((gl.x, gl.y - speed * dt * i, max(0.0, pt.z)))
                target[i] = target[i] + (want_pt - pt) * wgt
        moved = []
        for f, tgt in sorted(target.items()):
            sc.frame_set(f)
            foot_w = ft.matrix.to_3x3().copy()
            H, K = ul.head.copy(), ll.head.copy()
            Kn, An = _two_bone(H, K, tgt, l1, l2)
            _aim(ul, Kn - H)
            bpy.context.view_layer.update()
            _aim(ll, An - ll.head)
            bpy.context.view_layer.update()
            m = foot_w.to_4x4()
            m.translation = ft.head.copy()
            ft.matrix = m
            bpy.context.view_layer.update()
            for pb in (ul, ll, ft):
                pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
                if f == 0:
                    pb.keyframe_insert("rotation_quaternion", frame=frames, group=pb.name)
            moved.append(round((tgt - t[f]["ankle"]).length * 100, 1))
        report[side] = {"segments": segs, "max_move_cm": max(moved) if moved else 0}
    return report
