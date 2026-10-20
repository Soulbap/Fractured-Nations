"""Procedural, IK-authored animation set for the shared infantry rig (CHARACTER-01).

Authoring rig (CTRL_* bones, not exported):
  CTRL_Weapon  child of UpperChest; the carbine's pose (same frame as ATT_Weapon).
  CTRL_HandR   child of CTRL_Weapon at the firing-hand grip  -> IK RightLowerArm + copy rot.
  CTRL_HandL   child of CTRL_Weapon at the support-hand grip -> IK LeftLowerArm + copy rot.
  CTRL_FootL/R child of Root, ankle targets                   -> IK LowerLeg + copy rot.
  CTRL_KneeL/R, CTRL_ElbowL/R pole targets.
Each clip is generated from a small gait model (feet planted at the gameplay speed, so
there is no foot sliding when the game moves the body at that speed), then baked to FK
keys on the deform + attachment bones with visual keying, and the constraints removed.
In place: Root never moves (gameplay drives the body, no root motion).

Locomotion clips are all LOCO_FRAMES long (one full gait cycle, left foot strike at
frame 0) so they blend in phase; Godot scales playback so feet match the actual speed
(see GAIT table, exported to assets/characters/infantry/animation_meta.json).
"""
import json
import math

import bpy
from mathutils import Matrix, Quaternion, Vector

import char_skeleton as S
import char_weapon as W

FPS = 30
LOCO_FRAMES = 32

# name: speed m/s, natural period s, duty factor, stance centre offset (m, + = forward),
# swing lift m, hip drop m, bob m, forward lean deg, crouch
GAIT = {
    "Walk":   dict(speed=1.40, period=1.00, duty=0.60, offset=0.00, lift=0.09, drop=0.035, bob=0.018, lean=3.0),
    "Run":    dict(speed=4.50, period=0.70, duty=0.22, offset=-0.09, lift=0.17, drop=0.075, bob=0.030, lean=9.0),
    "Sprint": dict(speed=7.50, period=0.62, duty=0.16, offset=-0.10, lift=0.22, drop=0.085, bob=0.032, lean=15.0),
    "CrouchWalk": dict(speed=1.20, period=1.05, duty=0.62, offset=0.02, lift=0.08, drop=0.300, bob=0.012, lean=16.0),
}
DIRS = {"F": (0.0, 1.0), "B": (0.0, -1.0), "L": (-1.0, 0.0), "R": (1.0, 0.0)}


def _q(axis, deg):
    return Quaternion(Vector(axis).normalized(), math.radians(deg))


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------------------- authoring rig


def setup_controls(arm):
    """Adds the CTRL_* bones and IK constraints. Rest frames are derived from the skeleton
    and the weapon's support-hand frame so the solved hands land exactly on the grips."""
    j = S.joints()
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones

    def ctrl(name, head, tail, parent, roll_vec=None, roll=None):
        b = eb.new(name)
        b.head, b.tail = head, tail
        b.parent = eb[parent] if parent else None
        b.use_deform = False
        if roll_vec is not None:
            b.align_roll(roll_vec)
        if roll is not None:
            b.roll = roll
        return b

    att = eb["ATT_Weapon"]
    W0 = att.matrix.copy()
    ctrl("CTRL_Weapon", att.head.copy(), att.tail.copy(), "UpperChest", roll=att.roll)
    hr = eb["RightHand"]
    ctrl("CTRL_HandR", hr.head.copy(), hr.tail.copy(), "CTRL_Weapon", roll=hr.roll)
    # Support hand: weapon-space support frame -> armature space at the weapon's rest.
    ax_w, palm_w, thumb_w, grip_w = W.support_frame()
    R0 = W0.to_3x3()
    ax, palm = (R0 @ ax_w).normalized(), (R0 @ palm_w).normalized()
    grip = W0 @ grip_w
    wrist = grip - ax * S.GRIP_IN_HAND[0] - palm * S.GRIP_IN_HAND[1]
    ctrl("CTRL_HandL", wrist, wrist + ax * 0.093, "CTRL_Weapon", roll_vec=-palm)
    for side, s in ((-1, "Left"), (1, "Right")):
        fb = eb[s + "Foot"]
        ctrl("CTRL_Foot" + s[0], fb.head.copy(), fb.tail.copy(), "Root", roll=fb.roll)
        k = j[s + "LowerLeg"]
        ctrl("CTRL_Knee" + s[0], k + Vector((0, 0.6, 0)), k + Vector((0, 0.65, 0)), "Root")
        e = j[s + "LowerArm"]
        ctrl("CTRL_Elbow" + s[0], e + Vector((side * 0.30, -0.25, -0.15)), e + Vector((side * 0.30, -0.30, -0.15)), "UpperChest")
    bpy.ops.object.mode_set(mode="POSE")
    pb = arm.pose.bones
    for side, s in ((-1, "Left"), (1, "Right")):
        c = s[0]
        for limb, tgt, pole in (("LowerLeg", "CTRL_Foot", "CTRL_Knee"), ("LowerArm", "CTRL_Hand", "CTRL_Elbow")):
            ik = pb[s + limb].constraints.new("IK")
            ik.name = "FN_IK"
            ik.target, ik.subtarget = arm, tgt + c
            ik.pole_target, ik.pole_subtarget = arm, pole + c
            ik.pole_angle = math.radians(-90 if limb == "LowerLeg" else 90)
            ik.chain_count = 2
        for bone, tgt in (("Foot", "CTRL_Foot"), ("Hand", "CTRL_Hand")):
            cr = pb[s + bone].constraints.new("COPY_ROTATION")
            cr.name = "FN_CR"
            cr.target, cr.subtarget = arm, tgt + c
    for b in pb:
        b.rotation_mode = "QUATERNION"
    bpy.ops.object.mode_set(mode="OBJECT")


def remove_controls(arm):
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    for pbn in arm.pose.bones:
        for c in list(pbn.constraints):
            pbn.constraints.remove(c)
    bpy.ops.object.mode_set(mode="EDIT")
    for b in list(arm.data.edit_bones):
        if b.name.startswith("CTRL_"):
            arm.data.edit_bones.remove(b)
    bpy.ops.object.mode_set(mode="OBJECT")


# ---------------------------------------------------------------------------- pose helpers


class Poser:
    """Sets bone poses from armature-space targets expressed as if all parents were at
    rest (basis = rest^-1 @ target). Rotations are world-axis deltas about the bone head."""

    def __init__(self, arm):
        self.arm = arm
        self.rest = {b.name: b.matrix_local.copy() for b in arm.data.bones}
        self.keyed = set()

    def rot(self, bone, q, loc=Vector()):
        r = self.rest[bone]
        h = r.translation
        tgt = Matrix.Translation(h + loc) @ q.to_matrix().to_4x4() @ Matrix.Translation(-h) @ r
        self.basis(bone, r.inverted() @ tgt)

    def target(self, bone, m):
        self.basis(bone, self.rest[bone].inverted() @ m)

    def basis(self, bone, m):
        pb = self.arm.pose.bones[bone]
        loc, rot, _ = m.decompose()
        pb.location = loc
        pb.rotation_quaternion = rot
        self.keyed.add(bone)

    def local_rot(self, bone, q):
        pb = self.arm.pose.bones[bone]
        pb.location = Vector()
        pb.rotation_quaternion = q
        self.keyed.add(bone)

    def key(self, frame):
        for name in self.keyed:
            pb = self.arm.pose.bones[name]
            pb.keyframe_insert("location", frame=frame, group=name)
            pb.keyframe_insert("rotation_quaternion", frame=frame, group=name)

    def reset(self):
        for pb in self.arm.pose.bones:
            pb.location = Vector()
            pb.rotation_quaternion = Quaternion()
        self.keyed = set()


def frame_m(fwd, up, origin):
    return S.frame_matrix(Vector(fwd), Vector(up), Vector(origin))


# ---------------------------------------------------------------------------- stance + weapon


STANCE_YAW = -12.0
STANCE_FWD = Matrix.Rotation(math.radians(STANCE_YAW), 3, "Z") @ Vector((0, 1, 0))      # torso bladed to the right (support shoulder forward), split over Chest/UpperChest


def chest_stance_matrix(P, extra_spine=None, hips=None):
    """Armature-space transform this frame applies to the UpperChest (rest -> posed)."""
    m = Matrix.Identity(4)
    if hips is not None:
        q, loc = hips
        h = P.rest["Hips"].translation
        m = Matrix.Translation(h + loc) @ q.to_matrix().to_4x4() @ Matrix.Translation(-h)
    rots = extra_spine or {}
    for bone in ("Spine", "Chest", "UpperChest"):
        q = rots.get(bone, Quaternion())
        h = P.rest[bone].translation
        m = m @ (Matrix.Translation(h) @ q.to_matrix().to_4x4() @ Matrix.Translation(-h))
    return m


def weapon_pose(kind, stance=None):
    """Pose of the carbine grip frame for a carry style. The butt point is given on the
    rest torso and follows the posed chest (stance); the aim direction stays in world."""
    if kind == "sprint":
        # Muzzle down-left across the body, stock high on the right chest.
        butt = Vector((0.110, 0.125, 1.320))
        fwd = Vector((-0.36, 0.62, -0.70)).normalized()
        up = Vector((0.15, 0.55, 0.65))
    elif kind == "crouch":
        butt = Vector((0.100, 0.140, 1.330))
        fwd = Vector((-math.sin(math.radians(9)), math.cos(math.radians(9)), -math.tan(math.radians(18)))).normalized()
        up = Vector((0, 0.3, 1))
    else:
        # Low ready: stock in the shoulder pocket, muzzle 28 deg down, slightly inboard.
        butt = Vector((0.105, 0.135, 1.350))
        fwd = Vector((-math.sin(math.radians(11)), math.cos(math.radians(11)), -math.tan(math.radians(30)))).normalized()
        up = Vector((0, 0.3, 1))
    if stance is not None:
        butt = stance @ butt
        # Follow the chest's yaw (gait twist) but keep the aim pitch in world space.
        cf = stance.to_3x3() @ Vector((0, 1, 0))
        yaw = math.atan2(-cf.x, cf.y) - math.atan2(-STANCE_FWD.x, STANCE_FWD.y)
        rz = Matrix.Rotation(yaw, 3, "Z")
        fwd, up = rz @ fwd, rz @ up
    up = (up - fwd * up.dot(fwd)).normalized()
    butt_local = Vector((0, -W.STOCK_PULL + 0.008, W.BORE_Z - 0.030))
    right = fwd.cross(up)
    grip = butt - (right * butt_local.x + fwd * butt_local.y + up * butt_local.z)
    return frame_m(fwd, up, grip)


# ---------------------------------------------------------------------------- finger grip


def apply_grip_fingers(P):
    """Static finger curls: right hand closes on the pistol grip with the index finger
    straight along the receiver (trigger discipline), left hand wraps the handguard."""
    curl = {
        "Right": {"Index": (14, 8, 6), "Middle": (62, 72, 38), "Ring": (66, 74, 38), "Little": (70, 72, 36)},
        "Left": {"Index": (38, 46, 26), "Middle": (44, 52, 28), "Ring": (48, 54, 28), "Little": (52, 54, 26)},
    }
    thumb = {"Right": (10, 25, 30), "Left": (6, 15, 18)}
    for side, fingers in curl.items():
        for f, angs in fingers.items():
            for seg, a in zip(S.FINGER_SEGS, angs):
                P.local_rot(side + f + seg, _q((1, 0, 0), -a))
        for seg, a in zip(S.THUMB_SEGS, thumb[side]):
            P.local_rot(side + "Thumb" + seg, _q((1, 0, 0), -a))


# ---------------------------------------------------------------------------- generators


FOOT_X = 0.102


def foot_target(P, side, pos_xy, lift, pitch_deg, yaw_deg=0.0):
    """Ankle target for a foot whose sole contact is at pos_xy, pitched about the heel
    (pitch > 0, toes up) or the ball (pitch < 0, heel up)."""
    s = "Left" if side < 0 else "Right"
    rest = P.rest[s + "Foot"]
    ankle0 = rest.translation
    heel0 = Vector((ankle0.x, ankle0.y - 0.045, 0.0))
    ball0 = Vector((ankle0.x, ankle0.y + 0.135, 0.0))
    pivot = heel0 if pitch_deg > 0 else ball0
    q = _q((0, 0, 1), yaw_deg) @ _q((1, 0, 0), pitch_deg)
    off = Vector((pos_xy[0] - ankle0.x + side * FOOT_X, pos_xy[1], lift))
    m = Matrix.Translation(off) @ Matrix.Translation(pivot) @ q.to_matrix().to_4x4() @ Matrix.Translation(-pivot) @ rest
    return m


def gait_frame(P, g, d, phase, carry="low", crouch=False):
    """Poses one frame of a gait cycle. g = GAIT entry, d = direction (x, y) in character
    space, phase in [0, 1). Left foot strikes at phase 0, right at 0.5."""
    S_ = g["speed"] * g["period"]               # stride (m per cycle)
    beta = g["duty"]
    reach = S_ * beta
    dvec = Vector((d[0], d[1], 0))
    lateral = abs(d[0]) > 0.5
    feet = {}
    for side, ph in ((-1, phase), (1, (phase + 0.5) % 1.0)):
        if ph < beta:
            u = ph / beta
            s = reach * (0.5 - u)
            lift = 0.0
            pitch = 12.0 * (1 - smooth(u / 0.18)) if not crouch else 4.0 * (1 - smooth(u / 0.2))
            if u > 0.62:
                pitch = -38.0 * smooth((u - 0.62) / 0.38) * (0.6 if crouch else 1.0)
        else:
            q = (ph - beta) / (1 - beta)
            s = -reach * 0.5 + reach * smooth(q)
            lift = g["lift"] * math.sin(math.pi * min(1.0, q * 1.1)) ** 1.2
            pitch = -38.0 * (1 - smooth(q / 0.3)) + 14.0 * smooth((q - 0.55) / 0.45) if q < 0.98 else 12.0
            if crouch:
                pitch *= 0.6
        if not lateral:
            pos = Vector((0, s * dvec.y + g["offset"] * dvec.y, 0))
            if crouch:
                pos.y += (0.10 if side < 0 else -0.06)
        else:
            # Side steps: feet stay staggered fore/aft so they never cross.
            pos = Vector((s * dvec.x + g["offset"] * 0.3 * dvec.x, (0.07 if side < 0 else -0.07), 0))
            pitch *= 0.5
        if d[1] < -0.5:
            pitch *= 0.6
        feet[side] = (pos, lift, pitch)
        P.target("CTRL_Foot" + ("L" if side < 0 else "R"), foot_target(P, side, (pos.x, pos.y), lift, pitch,
                                                                            yaw_deg=side * -6.0 if not crouch else side * -12.0))
        k = P.rest[("Left" if side < 0 else "Right") + "LowerLeg"].translation
        P.target("CTRL_Knee" + ("L" if side < 0 else "R"), Matrix.Translation(Vector((k.x + side * 0.05, pos.y + 0.7, k.z))))
    # Pelvis: lowest at mid-stance (run) / double support (walk), sway over the stance foot.
    two = 2 * math.pi * phase
    run_like = beta < 0.5
    bob = g["bob"] * (math.cos(2 * two) if run_like else -math.cos(2 * two))
    drop = g["drop"]
    sway = 0.012 * math.cos(two) * (0.4 if run_like else 1.0)
    yaw = 6.0 * math.cos(two) * (1.3 if run_like else 1.0)
    if lateral:
        yaw *= 0.3
    lean = g["lean"] * (dvec.y if not lateral else 0.3)
    hips_loc = Vector((sway if not lateral else sway * 0.5, -0.02 * math.sin(math.radians(lean)), -drop + bob))
    if crouch:
        hips_loc.y -= 0.06
    hips_q = _q((0, 0, 1), yaw) @ _q((1, 0, 0), -lean * 0.45 - (22 if crouch else 0)) @ _q((0, 1, 0), -2.5 * math.cos(two))
    P.rot("Hips", hips_q, hips_loc)
    spine = {
        "Spine": _q((0, 0, 1), -yaw * 0.5 + STANCE_YAW * 0.25) @ _q((1, 0, 0), -lean * 0.20 + (10 if crouch else 0)),
        "Chest": _q((0, 0, 1), -yaw * 0.35 + STANCE_YAW * 0.35) @ _q((1, 0, 0), -lean * 0.20 + (6 if crouch else 0)),
        "UpperChest": _q((0, 0, 1), -yaw * 0.15 + STANCE_YAW * 0.40) @ _q((1, 0, 0), -lean * 0.15 + 2.0 * math.cos(2 * two)),
    }
    for b, q in spine.items():
        P.rot(b, q)
    head_pitch = lean * 0.55 + (16 if crouch else 0) - 2.0 * math.cos(2 * two)
    P.rot("Neck", _q((0, 0, 1), -STANCE_YAW * 0.45 + yaw * 0.2) @ _q((1, 0, 0), head_pitch * 0.4))
    P.rot("Head", _q((0, 0, 1), -STANCE_YAW * 0.45 + yaw * 0.2) @ _q((1, 0, 0), head_pitch * 0.6))
    P.rot("LeftShoulder", _q((0, 0, 1), -26) @ _q((0, 1, 0), 5))
    P.rot("RightShoulder", _q((0, 0, 1), 4) @ _q((0, 1, 0), -4))
    toes = {}
    for side in (-1, 1):
        pitch = feet[side][2]
        P.rot(("Left" if side < 0 else "Right") + "Toes", _q((1, 0, 0), min(0.0, pitch) * -0.7))
    set_weapon(P, carry, spine, (hips_q, hips_loc), bob_phase=two, bob=g["bob"] * 0.5)


def set_weapon(P, carry, spine, hips, bob_phase=0.0, bob=0.0, sway=(0.0, 0.0)):
    """Places CTRL_Weapon so the carbine is at the carry pose in the posed stance (spine
    rotations of this frame without the per-frame bob), plus a small damped bob."""
    stance = chest_stance_matrix(P, spine, hips)
    W = weapon_pose(carry, stance)
    tgt = stance.inverted() @ W
    t = tgt.translation + Vector((sway[0], 0, -bob * 0.4 * math.cos(2 * bob_phase) + sway[1]))
    tgt = Matrix.Translation(t) @ tgt.to_quaternion().to_matrix().to_4x4()
    P.target("CTRL_Weapon", tgt)
    for side, pole in ((-1, Vector((-0.42, -0.10, 0.95))), (1, Vector((0.50, -0.22, 1.00)))):
        P.target("CTRL_Elbow" + ("L" if side < 0 else "R"), stance.inverted() @ Matrix.Translation(pole))
    P.basis("CTRL_HandR", Matrix.Identity(4))   # children of CTRL_Weapon: rest offsets
    P.basis("CTRL_HandL", Matrix.Identity(4))


def idle_frame(P, phase, crouch=False):
    """Standing (or crouched) ready idle: weight shift, breathing, small weapon drift."""
    two = 2 * math.pi * phase
    if crouch:
        # Left foot forward flat, right foot back on the ball of the foot.
        P.target("CTRL_FootL", foot_target(P, -1, (0.0, 0.20), 0.0, 0.0, yaw_deg=8))
        P.target("CTRL_FootR", foot_target(P, 1, (0.03, -0.18), 0.0, -40.0, yaw_deg=-18))
        hips_loc = Vector((0.015, -0.07, -0.335 + 0.004 * math.sin(two)))
        hips_q = _q((0, 0, 1), -8) @ _q((1, 0, 0), -24)
        spine = {"Spine": _q((0, 0, 1), STANCE_YAW * 0.25 + 3) @ _q((1, 0, 0), 12),
                 "Chest": _q((0, 0, 1), STANCE_YAW * 0.35 + 2) @ _q((1, 0, 0), 6 + 0.8 * math.sin(two)),
                 "UpperChest": _q((0, 0, 1), STANCE_YAW * 0.40) @ _q((1, 0, 0), 0.8 * math.sin(two))}
        carry = "crouch"
        head_p = 18
    else:
        P.target("CTRL_FootL", foot_target(P, -1, (-0.02, 0.06), 0.0, 0.0, yaw_deg=10))
        P.target("CTRL_FootR", foot_target(P, 1, (0.04, -0.06), 0.0, 0.0, yaw_deg=-16))
        shift = 0.018 * math.sin(two)
        hips_loc = Vector((shift, 0.0, -0.022 - 0.004 * abs(math.sin(two))))
        hips_q = _q((0, 0, 1), -6 + 1.5 * math.sin(two)) @ _q((0, 1, 0), -2.0 * math.sin(two))
        breath = math.sin(two * 3.0)        # three breaths per idle cycle
        spine = {"Spine": _q((0, 0, 1), STANCE_YAW * 0.25 + 2) @ _q((1, 0, 0), -1),
                 "Chest": _q((0, 0, 1), STANCE_YAW * 0.35 + 2) @ _q((1, 0, 0), 0.8 * breath),
                 "UpperChest": _q((0, 0, 1), STANCE_YAW * 0.40) @ _q((1, 0, 0), 1.2 * breath)}
        carry = "low"
        head_p = 3 + 1.5 * math.sin(two * 2)
    for side in (-1, 1):
        k = P.rest[("Left" if side < 0 else "Right") + "LowerLeg"].translation
        P.target("CTRL_Knee" + ("L" if side < 0 else "R"), Matrix.Translation(Vector((k.x + side * 0.12, 0.8, k.z))))
    P.rot("Hips", hips_q, hips_loc)
    for b, q in spine.items():
        P.rot(b, q)
    look = 6.0 * math.sin(two * 2 + 0.6) if not crouch else 4.0 * math.sin(two)
    P.rot("Neck", _q((0, 0, 1), -STANCE_YAW * 0.45 + look * 0.4) @ _q((1, 0, 0), head_p * 0.4))
    P.rot("Head", _q((0, 0, 1), -STANCE_YAW * 0.45 + look * 0.6) @ _q((1, 0, 0), head_p * 0.6))
    P.rot("LeftShoulder", _q((0, 0, 1), -26) @ _q((0, 1, 0), 5))
    P.rot("RightShoulder", _q((0, 0, 1), 4) @ _q((0, 1, 0), -4))
    P.rot("LeftToes", Quaternion())
    P.rot("RightToes", _q((1, 0, 0), 30) if crouch else Quaternion())
    set_weapon(P, carry, spine, (hips_q, hips_loc), sway=(0.004 * math.sin(two * 2), 0.003 * math.sin(two * 3)))


# ---------------------------------------------------------------------------- clips


def clip_list():
    """(clip name, frames, loop, generator(P, phase))."""
    out = [("Idle", 120, True, lambda P, ph: idle_frame(P, ph)),
           ("Crouch_Idle", 120, True, lambda P, ph: idle_frame(P, ph, crouch=True))]
    for gname in ("Walk", "Run"):
        for dn, dv in DIRS.items():
            out.append((f"{gname}_{dn}", LOCO_FRAMES, True,
                        lambda P, ph, g=GAIT[gname], d=dv: gait_frame(P, g, d, ph, "low")))
    out.append(("Sprint_F", LOCO_FRAMES, True, lambda P, ph: gait_frame(P, GAIT["Sprint"], DIRS["F"], ph, "sprint")))
    for dn, dv in DIRS.items():
        out.append((f"CrouchWalk_{dn}", LOCO_FRAMES, True,
                    lambda P, ph, d=dv: gait_frame(P, GAIT["CrouchWalk"], d, ph, "crouch", crouch=True)))
    return out


def author_and_bake(arm, only=None):
    """Creates every clip as a baked FK action. Returns {clip: action}."""
    P = Poser(arm)
    scene = bpy.context.scene
    scene.render.fps = FPS
    bake_bones = [b.name for b in arm.data.bones if b.use_deform]
    actions = {}
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    if arm.animation_data is None:
        arm.animation_data_create()
    for name, frames, loop, gen in clip_list():
        if only and name not in only:
            continue
        src = bpy.data.actions.new(name + "_src")
        arm.animation_data.action = src
        for f in range(frames + 1):
            P.reset()
            apply_grip_fingers(P)
            gen(P, (f % frames) / frames)
            P.key(f)
        bpy.ops.object.mode_set(mode="POSE")
        for pbn in arm.pose.bones:
            pbn.select = pbn.name in bake_bones
        bpy.ops.nla.bake(frame_start=0, frame_end=frames, step=1, only_selected=True, visual_keying=True,
                         clear_constraints=False, clear_parents=False, use_current_action=False,
                         clean_curves=False, bake_types={"POSE"})
        bpy.ops.object.mode_set(mode="OBJECT")
        baked = arm.animation_data.action
        baked.name = name
        baked.use_fake_user = True
        baked["fn_frames"] = frames
        baked["fn_loop"] = loop
        bpy.data.actions.remove(src)
        actions[name] = baked
    arm.animation_data.action = None
    P.reset()
    return actions


def measure(arm, actions, weapon_obj=None):
    """Validation numbers per clip: support-hand error to the handguard grip, foot slip in
    stance (relative to the authored ground speed) and lowest foot height."""
    import char_weapon as Wm
    ax_w, palm_w, thumb_w, grip_w = Wm.support_frame()
    out = {}
    scene = bpy.context.scene
    for name, act in actions.items():
        arm.animation_data.action = act
        frames = int(act["fn_frames"])
        err_max = 0.0
        for f in range(0, frames + 1, 2):
            scene.frame_set(f)
            pb = arm.pose.bones
            att = arm.matrix_world @ pb["ATT_Weapon"].matrix
            grip = att @ grip_w
            lh = arm.matrix_world @ pb["LeftHand"].matrix
            ax = lh.to_3x3() @ Vector((0, 1, 0))
            palm = -(lh.to_3x3() @ Vector((0, 0, 1)))
            hand_grip = lh.translation + ax * S.GRIP_IN_HAND[0] + palm * S.GRIP_IN_HAND[1]
            err_max = max(err_max, (hand_grip - grip).length)
        out[name] = {"support_hand_err_mm": round(err_max * 1000, 1)}
        # Stance-foot slip: in place, a planted ankle must travel backwards at the clip's
        # ground speed. Slip = |ankle velocity + v * dir| while the ankle is at stance height.
        gname = name.split("_")[0]
        if gname in GAIT and name.split("_")[-1] in DIRS:
            g = GAIT[gname]
            d = DIRS[name.split("_")[-1]]
            slips = []
            prev = {}
            for f in range(frames + 1):
                scene.frame_set(f)
                for side in ("LeftFoot", "RightFoot"):
                    p = (arm.matrix_world @ arm.pose.bones[side].head).copy()
                    ph = ((f - 0.5) / frames + (0.0 if side == "LeftFoot" else 0.5)) % 1.0
                    # Stance by the gait model, excluding heel-strike and toe-off frames.
                    in_stance = 0.08 * g["duty"] < ph < 0.62 * g["duty"]
                    if side in prev and in_stance:
                        vel = (p - prev[side]) * (frames / g["period"])   # one frame = period / frames s
                        slip = Vector((vel.x + d[0] * g["speed"], vel.y + d[1] * g["speed"], 0)).length
                        slips.append(slip)
                    prev[side] = p
            if slips:
                out[name]["stance_slip_mean_ms"] = round(sum(slips) / len(slips), 3)
                out[name]["stance_slip_p90_ms"] = round(sorted(slips)[int(len(slips) * 0.9)], 3)
    arm.animation_data.action = None
    return out


def write_meta(path, actions):
    meta = {"fps": FPS, "loco_frames": LOCO_FRAMES, "gait": GAIT,
            "clips": {n: {"frames": int(a["fn_frames"]), "loop": bool(a["fn_loop"])} for n, a in actions.items()}}
    with open(path, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
