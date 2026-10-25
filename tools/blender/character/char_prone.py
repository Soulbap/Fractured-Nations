"""COMBAT-01 prone clips and the stand <-> prone change on the VISUAL-03 rig.

The CMU takes the soldier is built from have no prone or crawling capture, so these clips are posed procedurally on the
same rig with the same weapon tools as the captured ones (char_anim: two-bone IK onto the grips, the grip fingers, the
cheek weld's eye), from the prone firing position of infantry field manuals and reference photos:
  * body flat and straight behind the rifle (slightly angled), legs spread, feet turned out flat / toes dug in,
  * chest raised on both elbows, the support elbow under the rifle, the firing elbow out to the side on the ground,
  * butt in the shoulder pocket, cheek on the stock, the eye on the sight line (the rifle is placed on the eye and the
    head is turned within the neck's range until the butt sits in the shoulder; `checks` reports what is left).
Clips (all in place; the game moves the body):
  Prone_Idle      2 s loop, rifle at a low ready, a slow breath
  Prone_Aim       2 s loop, cheek weld, eye on the sight line
  Prone_Fire      6 frames, kick on the shoulder (one-shot over Prone_Aim)
  ProneCrawl_F    one low-crawl cycle (left knee + right elbow, then the other side), played at speed / stride
  Stand_To_Prone  1.0 s: ready stance -> kneel -> hands down -> flat (Posture.TRANSITION_S stand -> prone)
  Prone_To_Stand  1.1 s: the same way up
Geometry agreed with the game's hit and sight model (scripts/combat/posture.gd PRONE): hips above UnitState.position,
head ~0.75 m in front of it at ~0.3 m, feet ~1 m behind. `prone_layout` measures it on the result.
"""
import math

import bpy
from mathutils import Matrix, Quaternion, Vector

import char_anim as A
import char_weapon as W

FPS = 30
PRONE_FRAMES = 60
FIRE_FRAMES = 6
CRAWL_FRAMES = 40
DOWN_FRAMES = 30
UP_FRAMES = 33
HIP_Z = 0.13                      # Hips head above the ground, lying
HIP_PITCH = -84.0                 # whole body tipped forward about the hips (deg)
CHEST_LIFT = (4.0, 5.0, 6.0)      # Spine / Chest / UpperChest raised on the elbows (deg)
FEET = {"Left": Vector((-0.24, -0.86, 0.10)), "Right": Vector((0.22, -0.84, 0.10))}
CRAWL_SPEED = 0.81                # m/s: Posture.SPEED[PRONE] x 4.5
EYE_RELIEF = 0.075                # eye behind the sight's rear (m)
LOW_READY = (-9.0, 6.0)           # Prone_Idle: muzzle pitch / inboard yaw against the aim (deg)

# Elbow poles (chest frame, as char_anim.CARRIES) that put the elbows down on the ground with the chest tipped forward.
POLES = dict(pole_r=(0.34, 0.40, -0.34), pole_l=(-0.20, 0.42, -0.36))

BODY = ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder", "RightShoulder",
        "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
        "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]


def _fingers(arm):
    return [b.name for b in arm.data.bones if any(f in b.name for f in ("Thumb", "Index", "Middle", "Ring", "Little"))]


def _x(deg):
    return Quaternion((1, 0, 0), math.radians(deg))


def _legs(arm, R, feet, poles_down=0.55):
    """Both legs onto foot (ankle) targets, knees towards the ground; feet turned with the toes dug in behind."""
    for s in ("Left", "Right"):
        ul, ll = arm.pose.bones[s + "UpperLeg"], arm.pose.bones[s + "LowerLeg"]
        l1, l2 = R.len[s + "Leg"]
        H = ul.head.copy()
        side = 1.0 if s == "Right" else -1.0
        pole = H + Vector((0.12 * side, -0.25, -poles_down))
        Kn, An = A.two_bone(H, ll.head.copy(), feet[s], l1, l2, pole)
        A._aim_bone(arm, s + "UpperLeg", Kn - H)
        A._aim_bone(arm, s + "LowerLeg", An - ll.head)


def _feet_down(arm, R, toe_deg=-100.0, turn=12.0):
    for s in ("Left", "Right"):
        fb = arm.pose.bones[s + "Foot"]
        side = 1.0 if s == "Right" else -1.0
        rot = Quaternion((0, 0, 1), math.radians(-turn * side)) @ _x(toe_deg)
        m = (rot.to_matrix() @ R.rest[s + "Foot"].to_3x3()).to_4x4()
        m.translation = fb.head.copy()
        A._set_world(fb, m)
        arm.pose.bones[s + "Toes"].rotation_quaternion = _x(-25.0)
    bpy.context.view_layer.update()


def _eye(arm):
    return arm.pose.bones["Head"].matrix @ A.head_to_sight.eye_local


def _rifle_on_eye(arm, pitch=0.0, yaw=3.0, cant=0.0):
    """Weapon frame with the sight line through the right eye (EYE_RELIEF behind the sight), muzzle level forward
    (pitch / yaw in degrees: + up / + inboard)."""
    fwd = Quaternion((0, 0, 1), math.radians(yaw)) @ (_x(pitch) @ Vector((0, 1, 0)))
    up = Quaternion((0, 0, 1), math.radians(yaw)) @ (_x(pitch) @ Vector((0, 0, 1)))
    up = Quaternion(fwd, math.radians(cant)) @ up
    right = fwd.cross(up).normalized()
    up = right.cross(fwd).normalized()
    rot = Matrix((right, fwd, up)).transposed()
    sight_local = Vector((0, -0.05, A.SIGHT_Z))
    origin = _eye(arm) + fwd * EYE_RELIEF - rot @ sight_local
    m = rot.to_4x4()
    m.translation = origin
    return m


def _rifle_from_butt(butt, pitch, yaw):
    fwd = Quaternion((0, 0, 1), math.radians(yaw)) @ (_x(pitch) @ Vector((0, 1, 0)))
    up = Quaternion((0, 0, 1), math.radians(yaw)) @ (_x(pitch) @ Vector((0, 0, 1)))
    right = fwd.cross(up).normalized()
    up = right.cross(fwd).normalized()
    rot = Matrix((right, fwd, up)).transposed()
    m = rot.to_4x4()
    m.translation = butt - rot @ A.BUTT_LOCAL
    return m


def _pocket(arm, R):
    """Shoulder pocket: where the butt plate belongs (the aim carry's butt point on this chest)."""
    ch = arm.pose.bones["UpperChest"].matrix
    rot = ch.to_3x3() @ R.chest_rest.to_3x3().inverted()
    return arm.pose.bones["RightUpperArm"].head + rot @ Vector(A.CARRIES["aim"]["butt"])


def _butt(Wm):
    return Wm @ A.BUTT_LOCAL


def _fit_head(arm, R, pitch=0.0, yaw=3.0):
    """Turns neck and head (and the chest a little) so that a rifle laid on the eye has its butt in the shoulder pocket:
    the cheek weld seen from the shoulder. Returns the remaining butt-pocket distance (m)."""
    def err():
        return (_butt(_rifle_on_eye(arm, pitch, yaw)) - _pocket(arm, R)).length
    best = err()
    limits = {(1, 0, 0): (-30.0, 30.0), (0, 1, 0): (-20.0, 20.0), (0, 0, 1): (-25.0, 25.0)}
    acc = {k: 0.0 for k in limits}
    for step in (6.0, 3.0, 1.5, 0.75):
        for _ in range(10):
            improved = False
            for ax, (lo, hi) in limits.items():
                for sgn in (1, -1):
                    if not lo <= acc[ax] + sgn * step <= hi:
                        continue
                    for bn, share in (("Neck", 0.45), ("Head", 0.55)):
                        A._rotate_world(arm, bn, Quaternion(Vector(ax), math.radians(sgn * step * share)))
                    e = err()
                    if e < best - 1e-5:
                        best = e
                        acc[ax] += sgn * step
                        improved = True
                    else:
                        for bn, share in (("Head", 0.55), ("Neck", 0.45)):
                            A._rotate_world(arm, bn, Quaternion(Vector(ax), math.radians(-sgn * step * share)))
            if not improved:
                break
    return best


def lie(arm, R, lift=1.0, breath=0.0, sway=(0.0, 0.0), feet=None):
    """The prone body for the current frame, from rest (no action may be assigned): hips down and tipped forward, chest
    on the elbows, head up, legs back and spread."""
    A.reset_pose(arm)
    hb = arm.pose.bones["Hips"]
    q = Quaternion((0, 0, 1), math.radians(sway[0])) @ _x(HIP_PITCH)
    m = (q.to_matrix() @ R.rest["Hips"].to_3x3()).to_4x4()
    m.translation = Vector((sway[1], 0.0, HIP_Z))
    A._set_world(hb, m)
    for bone, deg in zip(("Spine", "Chest", "UpperChest"), CHEST_LIFT):
        A._rotate_world(arm, bone, _x((deg + breath) * lift))
    # Face forward: the head comes up off the ground line (the cheek weld fine-tunes it).
    A._rotate_world(arm, "Neck", _x(40.0 * lift + 8.0))
    A._rotate_world(arm, "Head", _x(30.0 * lift + 6.0))
    _legs(arm, R, feet or FEET)
    _feet_down(arm, R)


def _arms(arm, R, Wm, trigger):
    ch = arm.pose.bones["UpperChest"].matrix.copy()
    e = A.solve_arms(R, Wm, "prone", ch)
    A.grip_fingers(arm, trigger)
    return e


def _snapshot(arm, bones):
    return {b: (arm.pose.bones[b].location.copy(), arm.pose.bones[b].rotation_quaternion.copy()) for b in bones}


def _key(arm, act_name, poses, loop):
    """A new action keyed from per-frame local poses (rotation every bone, location on Hips)."""
    act = bpy.data.actions.new(act_name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    frames = poses + ([poses[0]] if loop else [])
    for f, pose in enumerate(frames):
        for b, (loc, rot) in pose.items():
            pb = arm.pose.bones[b]
            pb.location, pb.rotation_quaternion = loc, rot
            pb.keyframe_insert("rotation_quaternion", frame=f, group=b)
            if b == "Hips":
                pb.keyframe_insert("location", frame=f, group=b)
    arm.animation_data.action = None
    act["fn_frames"] = len(poses) if loop else len(poses) - 1
    act["fn_loop"] = loop
    return act


def _ease(t):
    return A._ease(t)


class Prone:
    def __init__(self, builder):
        self.b = builder
        self.arm = builder.arm
        self.R = builder.R
        A.CARRIES.setdefault("prone", dict(A.CARRIES["aim"], **POLES))
        self.bones = BODY + _fingers(self.arm)
        self.checks = {}

    def _pose_frame(self, aim, breath=0.0, recoil=(0.0, 0.0), crawl=None):
        """Poses one frame; returns the arm errors and the rifle frame."""
        arm, R = self.arm, self.R
        feet = None
        sway = (0.0, 0.0)
        lift = 1.0
        push = 0.0
        if crawl is not None:
            # Low crawl: one knee drawn up the side while the opposite elbow reaches, then the other side; the hips roll
            # and sway with it; the chest stays lower.
            ph = crawl
            kl = math.sin(math.pi * min(1.0, ph * 2.0)) ** 2 if ph < 0.5 else 0.0
            kr = math.sin(math.pi * min(1.0, (ph - 0.5) * 2.0)) ** 2 if ph >= 0.5 else 0.0
            feet = {"Left": FEET["Left"].lerp(Vector((-0.44, -0.50, 0.12)), kl),
                    "Right": FEET["Right"].lerp(Vector((0.42, -0.50, 0.12)), kr)}
            sway = (7.0 * math.sin(2 * math.pi * ph), 0.035 * math.sin(2 * math.pi * ph))
            lift = 0.7
            push = 0.05 * math.sin(2 * math.pi * ph)
        lie(arm, R, lift=lift, breath=breath, sway=sway, feet=feet)
        pitch, yaw = (0.0, 3.0) if aim else (LOW_READY[0], 3.0 + LOW_READY[1])
        fit = _fit_head(arm, R, 0.0, 3.0)
        Wm = _rifle_on_eye(arm, 0.0, 3.0)
        if not aim:
            # Low ready: the rifle turns down and in about the butt, the head comes off the stock.
            butt = _butt(Wm)
            q = Quaternion((0, 0, 1), math.radians(LOW_READY[1])) @ _x(LOW_READY[0])
            m3 = q.to_matrix() @ Wm.to_3x3()
            Wm = m3.to_4x4()
            Wm.translation = butt - m3 @ A.BUTT_LOCAL
            A._rotate_world(arm, "Head", _x(-8.0))
        if push:
            Wm.translation += Vector((0, push, 0))
        if recoil[0] or recoil[1]:
            fwd = Wm.to_3x3() @ Vector((0, 1, 0))
            rr = Wm.to_3x3() @ Vector((1, 0, 0))
            m3 = Quaternion(rr, math.radians(recoil[1])).to_matrix() @ Wm.to_3x3()
            t = Wm.translation - fwd * recoil[0]
            Wm = m3.to_4x4()
            Wm.translation = t
            A._rotate_world(arm, "UpperChest", Quaternion(rr, math.radians(-recoil[1] * 0.3)))
        e = _arms(arm, R, Wm, trigger=aim)
        return e, fit, Wm

    def loop(self, name, aim, frames=PRONE_FRAMES):
        arm = self.arm
        arm.animation_data.action = None
        poses, errs, fits = [], [], []
        for f in range(frames):
            breath = 0.8 * math.sin(2 * math.pi * f / frames)
            e, fit, _ = self._pose_frame(aim, breath)
            errs.append(max(e.values()))
            fits.append(fit)
            poses.append(_snapshot(arm, self.bones))
        act = _key(arm, name, poses, True)
        self.checks[name] = {"hand_err_mm": round(max(errs) * 1000, 1), "butt_to_pocket_mm": round(max(fits) * 1000, 1)}
        return act

    def fire(self):
        arm = self.arm
        arm.animation_data.action = None
        poses = []
        for f in range(FIRE_FRAMES + 1):
            back, up = A._recoil(f)
            e, _, _ = self._pose_frame(True, 0.0, (back * 0.7, up * 0.6))
            poses.append(_snapshot(arm, self.bones))
        act = _key(arm, "Prone_Fire", poses, False)
        return act

    def crawl(self):
        arm = self.arm
        arm.animation_data.action = None
        poses, errs = [], []
        for f in range(CRAWL_FRAMES):
            e, _, _ = self._pose_frame(False, 0.0, crawl=f / CRAWL_FRAMES)
            errs.append(max(e.values()))
            poses.append(_snapshot(arm, self.bones))
        act = _key(arm, "ProneCrawl_F", poses, True)
        period = CRAWL_FRAMES / FPS
        self.b.meta["ProneCrawl_F"] = {"speed": CRAWL_SPEED, "period": round(period, 4), "dir": [0.0, 1.0], "carry": "prone"}
        self.checks["ProneCrawl_F"] = {"hand_err_mm": round(max(errs) * 1000, 1)}
        return act

    # --- posture change ------------------------------------------------------------------------------------------

    def _from_action(self, act_name, frame=0):
        arm = self.arm
        arm.animation_data.action = self.b.actions[act_name]
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        pose = _snapshot(arm, self.bones)
        # the world rifle frame of that pose (right hand -> weapon)
        Wm = arm.pose.bones["RightHand"].matrix @ self.R.hand_r_in_w.inverted()
        arm.animation_data.action = None
        return pose, Wm

    def _kneel(self, low):
        """Going down / coming up: on the left knee with the right foot planted (low=False), or both knees down and the
        body tipped well forward (low=True); rifle held at a ready carry on the chest."""
        arm, R = self.arm, self.R
        A.reset_pose(arm)
        hb = arm.pose.bones["Hips"]
        hz, hy, pitch = (0.42, 0.10, -48.0) if low else (0.64, 0.04, -12.0)
        m = (_x(pitch).to_matrix() @ R.rest["Hips"].to_3x3()).to_4x4()
        m.translation = Vector((0.0, hy, hz))
        A._set_world(hb, m)
        lean = 22.0 if low else 6.0
        for bone, share in (("Spine", 0.4), ("Chest", 0.3), ("UpperChest", 0.3)):
            A._rotate_world(arm, bone, _x(-lean * share * 0.2))
        A._rotate_world(arm, "Neck", _x(18.0 if low else 4.0))
        A._rotate_world(arm, "Head", _x(14.0 if low else 2.0))
        if low:
            feet = {"Left": Vector((-0.20, -0.50, 0.09)), "Right": Vector((0.20, -0.48, 0.09))}
        else:
            feet = {"Left": Vector((-0.16, -0.46, 0.10)), "Right": Vector((0.17, 0.34, 0.08))}
        for s in ("Left", "Right"):
            ul, ll = arm.pose.bones[s + "UpperLeg"], arm.pose.bones[s + "LowerLeg"]
            l1, l2 = R.len[s + "Leg"]
            H = ul.head.copy()
            side = 1.0 if s == "Right" else -1.0
            knee_forward = (not low) and s == "Right"
            pole = H + (Vector((0.10 * side, 0.9, 0.2)) if knee_forward else Vector((0.10 * side, 0.6, -0.6)))
            Kn, An = A.two_bone(H, ll.head.copy(), feet[s], l1, l2, pole)
            A._aim_bone(arm, s + "UpperLeg", Kn - H)
            A._aim_bone(arm, s + "LowerLeg", An - ll.head)
        for s in ("Left", "Right"):
            fb = arm.pose.bones[s + "Foot"]
            flat = s == "Right" and not low
            rot = Quaternion() if flat else _x(-70.0)
            mm = (rot.to_matrix() @ R.rest[s + "Foot"].to_3x3()).to_4x4()
            mm.translation = fb.head.copy()
            A._set_world(fb, mm)
            arm.pose.bones[s + "Toes"].rotation_quaternion = Quaternion() if flat else _x(-35.0)
        bpy.context.view_layer.update()
        ch = arm.pose.bones["UpperChest"].matrix.copy()
        Wm = A.carry_matrix(R, "ready", ch, arm.pose.bones["RightUpperArm"].head.copy())
        if low:
            # the rifle forward and down in the hands (not into the ground): butt below the shoulder, muzzle 30 deg down
            Wm = _rifle_from_butt(_pocket(arm, R) + Vector((0.0, 0.10, -0.10)), -30.0, 10.0)
        _arms(arm, R, Wm, False)
        return _snapshot(arm, self.bones), Wm

    def change(self, name, keys, frames, flat_first):
        """A posture change through key poses [(t, pose, rifle frame)]: local rotations slerped (eased per segment), the
        hips location blended, the arms solved onto the blended rifle frame every frame (elbow poles of the prone
        position near the flat end, of the ready carry elsewhere)."""
        arm, R = self.arm, self.R
        arm.animation_data.action = None
        poses = []
        errs = []
        for f in range(frames + 1):
            t = f / frames
            i = 0
            while i < len(keys) - 2 and t > keys[i + 1][0]:
                i += 1
            t0, p0, w0 = keys[i]
            t1, p1, w1 = keys[i + 1]
            k = _ease((t - t0) / max(t1 - t0, 1e-6))
            A.reset_pose(arm)
            for b in self.bones:
                pb = arm.pose.bones[b]
                l0, r0 = p0[b]
                l1, r1 = p1[b]
                pb.rotation_quaternion = r0.slerp(r1, k) if r0.dot(r1) >= 0 else r0.slerp(-r1, k)
                pb.location = l0.lerp(l1, k)
            bpy.context.view_layer.update()
            q = w0.to_quaternion().slerp(w1.to_quaternion(), k)
            Wm = q.to_matrix().to_4x4()
            Wm.translation = w0.translation.lerp(w1.translation, k)
            ch = arm.pose.bones["UpperChest"].matrix.copy()
            near_flat = (flat_first and i == 0 and k < 0.5) or (not flat_first and i == len(keys) - 2 and k > 0.5)
            e = A.solve_arms(R, Wm, "prone" if near_flat else "ready", ch)
            A.grip_fingers(arm, False)
            errs.append(max(e.values()))
            poses.append(_snapshot(arm, self.bones))
        act = _key(arm, name, poses, False)
        self.checks[name] = {"hand_err_mm": round(max(errs) * 1000, 1), "frames": frames}
        return act

    def build(self, want):
        out = {}
        if want("Prone_Idle") or want("Stand_To_Prone") or want("Prone_To_Stand"):
            out["Prone_Idle"] = self.loop("Prone_Idle", False)
        if want("Prone_Aim"):
            out["Prone_Aim"] = self.loop("Prone_Aim", True)
        if want("Prone_Fire"):
            out["Prone_Fire"] = self.fire()
        if want("ProneCrawl_F"):
            out["ProneCrawl_F"] = self.crawl()
        if (want("Stand_To_Prone") or want("Prone_To_Stand")) and "Ready_Idle" in self.b.actions:
            self.b.actions.update(out)
            stand, ws = self._from_action("Ready_Idle", 0)
            flat, wf = self._from_action("Prone_Idle", 0)
            kneel, wk = self._kneel(False)
            low, wl = self._kneel(True)
            if want("Stand_To_Prone"):
                out["Stand_To_Prone"] = self.change("Stand_To_Prone", [(0.0, stand, ws), (0.34, kneel, wk), (0.66, low, wl), (1.0, flat, wf)], DOWN_FRAMES, False)
            if want("Prone_To_Stand"):
                out["Prone_To_Stand"] = self.change("Prone_To_Stand", [(0.0, flat, wf), (0.32, low, wl), (0.64, kneel, wk), (1.0, stand, ws)], UP_FRAMES, True)
        for n, act in out.items():
            self.b.actions[n] = act
            self.b.meta.setdefault(n, {"carry": "prone"})
        self.checks["layout"] = prone_layout(self.arm, self.b.actions.get("Prone_Aim") or self.b.actions.get("Prone_Idle"))
        self.b.checks.update({"prone": self.checks})
        return out


def prone_layout(arm, act):
    """Where the prone body lies relative to the origin (armature space, +Y forward): head centre, eye, hips, feet - to
    compare with scripts/combat/posture.gd PRONE."""
    if act is None:
        return {}
    arm.animation_data.action = act
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    pb = arm.pose.bones
    head_c = pb["Head"].matrix @ Vector((0, 0.09, 0.0))
    out = {"head": [round(x, 3) for x in pb["Head"].head], "head_mid": [round(x, 3) for x in head_c],
           "eye": [round(x, 3) for x in _eye(arm)], "hips": [round(x, 3) for x in pb["Hips"].head],
           "feet": [[round(x, 3) for x in pb[s + "Foot"].head] for s in ("Left", "Right")],
           "chest_top": [round(x, 3) for x in pb["UpperChest"].tail]}
    arm.animation_data.action = None
    return out
