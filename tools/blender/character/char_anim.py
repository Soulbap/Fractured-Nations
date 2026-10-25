"""Infantry animation set (VISUAL-03): CMU motion capture for the body, a weapon-handling layer on top.

Every clip starts from real capture (v03_mocap: retargeted, cut to a loop, in place, feet locked), so pelvis, legs,
weight transfer and timing stay those of a person walking or running. The weapon layer then
  * damps the thorax counter-rotation (a rifle carrier keeps the shoulders squarer than a free-armed walker) and
    adds the carry's stance (bladed torso for ready / aim),
  * places the rifle relative to the posed chest for the carry style (patrol, low ready, ready, run, port, crouch,
    aim), letting it lag the chest's roll and pitch and move with the captured arm swing, so the weapon rides on the
    body instead of being frozen in space,
  * solves both arms analytically onto the grips (firing hand on the pistol grip = ATT_Weapon, support hand on the
    handguard frame of char_weapon.support_frame) with natural elbow poles, and curls the fingers into a grip,
  * for aim, turns the head onto the stock so the right eye is on the sight line.
Crouch clips lower the captured walk (legs re-solved onto the same foot plants); aim, fire and reload are upper-body
poses on the captured idle. Clip list: clip_list(). Gait meta (speed, period, direction) goes to
animation_meta.json; the game plays loops at speed / stride.
"""
import json
import math
import os

import bpy
from mathutils import Matrix, Quaternion, Vector

import char_skeleton as S
import char_weapon as W
import v03_mocap as MC

FPS = 30
LOCO_FRAMES = 32
IDLE_FRAMES = 120
HERE = os.path.dirname(os.path.abspath(__file__))
MOCAP_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "..", "assets", "characters", "infantry", "mocap", "cmu"))

# Carry styles: butt point relative to the right shoulder joint in the chest frame (x right, y forward, z up, m),
# muzzle yaw (deg, + = inboard / to the left), pitch (deg, + = up), cant (deg, + = top to the right), how much the
# rifle's orientation is stabilised against the chest's roll / pitch (0 = rides on the chest), the thorax counter
# rotation kept (1 = as captured), the stance yaw of the chest (deg, - = support shoulder forward) and the elbow
# poles (shoulder-relative, chest frame).
CARRIES = {
    "patrol": dict(butt=(-0.055, 0.135, -0.165), yaw=16, pitch=-36, cant=10, stab=0.45, counter=0.55, stance=-6,
                   pole_r=(0.30, -0.20, -0.45), pole_l=(-0.30, 0.05, -0.50)),
    "low": dict(butt=(-0.060, 0.150, -0.110), yaw=11, pitch=-27, cant=5, stab=0.45, counter=0.5, stance=-10,
                pole_r=(0.30, -0.25, -0.40), pole_l=(-0.30, 0.05, -0.50)),
    "ready": dict(butt=(-0.050, 0.150, -0.075), yaw=8, pitch=-14, cant=2, stab=0.5, counter=0.45, stance=-14,
                  pole_r=(0.32, -0.20, -0.35), pole_l=(-0.28, 0.10, -0.50)),
    "run": dict(butt=(-0.050, 0.140, -0.100), yaw=13, pitch=-22, cant=4, stab=0.35, counter=0.6, stance=-8,
                pole_r=(0.30, -0.25, -0.40), pole_l=(-0.30, 0.05, -0.50)),
    "port": dict(butt=(0.010, 0.120, -0.200), yaw=58, pitch=24, cant=55, stab=0.25, counter=0.7, stance=-4,
                 pole_r=(0.35, -0.10, -0.40), pole_l=(-0.30, 0.00, -0.45)),
    "crouch": dict(butt=(-0.055, 0.150, -0.090), yaw=9, pitch=-18, cant=3, stab=0.45, counter=0.45, stance=-14,
                   pole_r=(0.32, -0.20, -0.35), pole_l=(-0.28, 0.10, -0.50)),
    "aim": dict(butt=(-0.050, 0.070, 0.040), yaw=24, pitch=0, cant=0, stab=0.85, counter=0.25, stance=-24,
                pole_r=(0.40, -0.05, -0.25), pole_l=(-0.20, 0.15, -0.55)),
}
# Posture per carry: mean forward lean of the thorax (deg from vertical) and head pitch (deg, - = looking down) the
# clip is corrected to by a constant offset (the captured variation stays). None keeps the capture's own value.
POSTURE = {"patrol": (4, -4), "low": (5, -4), "ready": (8, -2), "run": (None, 0), "port": (None, 0),
           "crouch": (None, -2), "aim": (6, None)}
BUTT_LOCAL = Vector((0, -W.STOCK_PULL + 0.008, W.BORE_Z - 0.030))
# Sight line above the grip origin: the red dot's tube axis on the optic rail (ATT_Optic + 0.058), the same height as the
# faction optics and the DMR scope (fac_weapons OPTIC_Z + SIGHT_H). VISUAL-03 part 2 measured against BORE_Z + 0.072,
# 26 mm low, so the cheek weld aimed the eye under the dot.
SIGHT_Z = W.MOUNTS["ATT_Optic"].z + 0.058
AIM_SHIFT_MAX = 0.05               # the rifle moves at most this far (m) to meet the eye after the head has turned

# Locomotion: clip -> (takes to try, motion, carry). The first take that has a clean stretch of that motion is used.
LOCO = {
    "Walk_F": (("16_15",), "forward", "patrol"),
    "Walk_B": (("09_12", "41_02"), "backward", "low"),
    "Walk_L": (("69_42", "69_43", "69_48"), "left", "low"),
    "Walk_R": (("69_42", "69_43", "69_48"), "right", "low"),
    "Brisk_F": (("16_21",), "forward", "low"),
    "Jog_F": (("35_17",), "forward", "ready"),
    "Run_F": (("16_46",), "forward", "run"),
}
# Faster backward / sideways clips reuse the walking ones (the game rarely strafes fast; playback rate follows the
# speed). Sprint: the run with the rifle at port arms.
DERIVED = {"Jog_B": "Walk_B", "Jog_L": "Walk_L", "Jog_R": "Walk_R", "Run_B": "Walk_B", "Run_L": "Walk_L",
           "Run_R": "Walk_R"}
TURNS = {"Turn_L": (("69_16", "69_17", "69_18", "69_19", "69_13"), "turn_left"),
         "Turn_R": (("69_18", "69_19", "69_16", "69_17", "69_13"), "turn_right")}
IDLE_TAKE = "77_02"
# COMBAT-01 posture clips (char_prone).
PRONE_CLIPS = ["Prone_Idle", "Prone_Aim", "Prone_Fire", "ProneCrawl_F", "Stand_To_Prone", "Prone_To_Stand"]
CROUCH_DROP = 0.30                 # crouch walk: pelvis lowered (m)


# ------------------------------------------------------------------------------------------------ helpers


def _take(name):
    path = os.path.join(MOCAP_DIR, name + ".bvh")
    if not os.path.exists(path):
        import zipfile
        zipfile.ZipFile(os.path.join(MOCAP_DIR, "zip", name + ".zip")).extractall(MOCAP_DIR)
    return path


def _frame(fwd, up, origin):
    return S.frame_matrix(Vector(fwd), Vector(up), Vector(origin))


def _rot_about(axis, deg):
    return Quaternion(Vector(axis).normalized(), math.radians(deg))


def _set_world(pb, m):
    # rotation and position only: a matrix with scale or shear would leave it on the bone's (unkeyed) scale channel,
    # where it stays from frame to frame (a forearm grew 4 % and the hand missed the grip by 12 mm)
    loc, rot, _ = m.decompose()
    pb.matrix = Matrix.LocRotScale(loc, rot, None)
    bpy.context.view_layer.update()


def _rotate_world(arm, bone, q):
    """Rotates a pose bone by world quaternion q about its head."""
    pb = arm.pose.bones[bone]
    m = pb.matrix.copy()
    r = (q.to_matrix() @ m.to_3x3()).to_4x4()
    r.translation = m.translation
    _set_world(pb, r)


def _yaw_of(m):
    f = m.to_3x3() @ Vector((0, 0, 1))         # bone Z ~ forward for the spine bones? use projection fallback
    return math.atan2(f.x, f.y)


def _heading(arm, bone):
    """Yaw of a bone's sideways axis turned to forward (robust for spine / pelvis whatever their roll)."""
    pb = arm.pose.bones[bone]
    r = pb.matrix.to_3x3()
    rest = arm.data.bones[bone].matrix_local.to_3x3()
    # the world direction that was +Y (forward) at rest
    f = r @ (rest.inverted() @ Vector((0, 1, 0)))
    return math.atan2(f.x, f.y)


def two_bone(H, K, T, l1, l2, pole):
    """Knee/elbow and end positions for root H reaching target T, bending towards `pole`."""
    d = T - H
    dl = max(1e-4, min(d.length, l1 + l2 - 1e-4))
    dn = d.normalized()
    a = (l1 * l1 - l2 * l2 + dl * dl) / (2 * dl)
    h = math.sqrt(max(0.0, l1 * l1 - a * a))
    p = (pole - H) - dn * (pole - H).dot(dn)
    p = p.normalized() if p.length > 1e-6 else Vector((0, 0, -1))
    return H + dn * a + p * h, H + dn * dl


def _aim_bone(arm, bone, direction):
    pb = arm.pose.bones[bone]
    m = pb.matrix.copy()
    q = m.to_3x3().col[1].normalized().rotation_difference(direction.normalized())
    out = (q.to_matrix() @ m.to_3x3()).to_4x4()
    out.translation = m.translation
    _set_world(pb, out)


def _basis(axis, palm):
    axis = axis.normalized()
    palm = (palm - axis * palm.dot(axis)).normalized()
    return Matrix((axis, palm, axis.cross(palm))).transposed()


class Rig:
    """Rest data of the armature the layer needs."""

    def __init__(self, arm):
        self.arm = arm
        b = arm.data.bones
        self.rest = {x.name: x.matrix_local.copy() for x in b}
        self.att_w = self.rest["ATT_Weapon"]
        self.hand_r_in_w = self.att_w.inverted() @ self.rest["RightHand"]
        ax, palm, _ = S.hand_frame(-1)
        self.hand_l_basis_rest = _basis(ax, palm)
        self.len = {}
        for s in ("Left", "Right"):
            self.len[s + "Arm"] = ((b[s + "LowerArm"].head_local - b[s + "UpperArm"].head_local).length,
                                   (b[s + "Hand"].head_local - b[s + "LowerArm"].head_local).length)
            self.len[s + "Leg"] = ((b[s + "LowerLeg"].head_local - b[s + "UpperLeg"].head_local).length,
                                   (b[s + "Foot"].head_local - b[s + "LowerLeg"].head_local).length)
        self.chest_rest = self.rest["UpperChest"]
        self.sh_r_rest = b["RightUpperArm"].head_local.copy()
        self.sh_l_rest = b["LeftUpperArm"].head_local.copy()
        self.eye_r = None
        self.carry_fit = fit_carries(self)


# ------------------------------------------------------------------------------------------------ weapon layer


def _reach(R, carry):
    """Hand-to-shoulder distance over arm length for both hands with the chest at rest (1 = fully stretched)."""
    Wm = carry_matrix(R, carry, R.chest_rest, R.sh_r_rest)
    hr = (Wm @ R.hand_r_in_w).translation
    ax_w, palm_w, _, grip_w = W.support_frame()
    Rw = Wm.to_3x3()
    wl = Wm @ grip_w - (Rw @ ax_w) * S.GRIP_IN_HAND[0] - (Rw @ palm_w) * S.GRIP_IN_HAND[1]
    rr = (hr - R.sh_r_rest).length / sum(R.len["RightArm"])
    rl = (wl - R.sh_l_rest).length / sum(R.len["LeftArm"])
    return rr, rl


def _reach_pose(R, arm, Wm):
    """As _reach, for the rifle at Wm and the current pose's shoulders."""
    hr = (Wm @ R.hand_r_in_w).translation
    ax_w, palm_w, _, grip_w = W.support_frame()
    Rw = Wm.to_3x3()
    wl = Wm @ grip_w - (Rw @ ax_w) * S.GRIP_IN_HAND[0] - (Rw @ palm_w) * S.GRIP_IN_HAND[1]
    rr = (hr - arm.pose.bones["RightUpperArm"].head).length / sum(R.len["RightArm"])
    rl = (wl - arm.pose.bones["LeftUpperArm"].head).length / sum(R.len["LeftArm"])
    return rr, rl


def fit_carries(R, limit=0.93):
    """Brings every carry within reach of this body's arms (the styles were authored on CHARACTER-01 proportions):
    while a hand would have to stretch past `limit` of its arm length, the butt moves towards the chest centre and
    back, and the muzzle turns inboard. Returns the reach before / after per carry."""
    out = {}
    for name, c in CARRIES.items():
        before = _reach(R, name)
        for _ in range(40):
            rr, rl = _reach(R, name)
            if max(rr, rl) <= limit:
                break
            bx, by, bz = c["butt"]
            if rl > limit:
                c["butt"] = (bx - 0.006, by - 0.003, bz)
                c["yaw"] += 1.0
            if rr > limit:
                c["butt"] = (c["butt"][0], c["butt"][1] - 0.006, c["butt"][2] + 0.004)
        out[name] = {"before": [round(x, 3) for x in before], "after": [round(x, 3) for x in _reach(R, name)],
                     "butt": [round(x, 3) for x in c["butt"]], "yaw": c["yaw"]}
    return out


def carry_matrix(R, carry, chest_m, sh_r):
    """Weapon frame (armature space) for a carry style on the posed chest frame `chest_m` (UpperChest pose matrix,
    rotation part relative to rest = chest orientation), right shoulder joint sh_r."""
    c = CARRIES[carry]
    rot = chest_m.to_3x3() @ R.chest_rest.to_3x3().inverted()      # chest rotation since rest
    fwd = Vector((0, 1, 0))
    fwd = _rot_about((0, 0, 1), c["yaw"]) @ (_rot_about((1, 0, 0), c["pitch"]) @ fwd)
    up = Vector((0, 0, 1))
    up = _rot_about((0, 0, 1), c["yaw"]) @ (_rot_about((1, 0, 0), c["pitch"]) @ up)
    up = _rot_about(fwd, c["cant"]) @ up
    butt = sh_r + rot @ Vector(c["butt"])
    fwd_w, up_w = rot @ fwd, rot @ up
    right = fwd_w.cross(up_w).normalized()
    up_w = right.cross(fwd_w).normalized()
    origin = butt - (right * BUTT_LOCAL.x + fwd_w * BUTT_LOCAL.y + up_w * BUTT_LOCAL.z)
    return _frame(fwd_w, up_w, origin)


def _stabilise(m_chest_locked, rest_like, s):
    """Blends the weapon orientation towards `rest_like` (the same carry on an upright chest with the chest's
    heading) by s; position unchanged."""
    q = m_chest_locked.to_quaternion().slerp(rest_like.to_quaternion(), s)
    out = q.to_matrix().to_4x4()
    out.translation = m_chest_locked.translation
    return out


def solve_arms(R, Wm, carry, chest_m, extra_l=None):
    """Both arms onto the weapon frame Wm (armature space): right hand on the pistol grip, left on the support
    grip (extra_l: override (axis, palm, grip) in weapon space)."""
    arm = R.arm
    c = CARRIES[carry]
    rot = chest_m.to_3x3() @ R.chest_rest.to_3x3().inverted()
    out = {}
    # Right hand: the ATT_Weapon relation of the rest pose.
    hr = Wm @ R.hand_r_in_w
    ax_w, palm_w, thumb_w, grip_w = extra_l or W.support_frame()
    Rw = Wm.to_3x3()
    ax, palm = (Rw @ ax_w).normalized(), (Rw @ palm_w).normalized()
    grip = Wm @ grip_w
    wrist_l = grip - ax * S.GRIP_IN_HAND[0] - palm * S.GRIP_IN_HAND[1]
    hl_rot = _basis(ax, palm) @ R.hand_l_basis_rest.inverted() @ R.rest["LeftHand"].to_3x3()
    hl = hl_rot.to_4x4()
    hl.translation = wrist_l
    for side, target, pole_off in (("Right", hr, c["pole_r"]), ("Left", hl, c["pole_l"])):
        ua, la, hb = arm.pose.bones[side + "UpperArm"], arm.pose.bones[side + "LowerArm"], arm.pose.bones[side + "Hand"]
        H = ua.head.copy()
        l1, l2 = R.len[side + "Arm"]
        pole = H + rot @ Vector(pole_off)
        Kn, An = two_bone(H, la.head.copy(), target.translation, l1, l2, pole)
        _aim_bone(arm, side + "UpperArm", Kn - H)
        _aim_bone(arm, side + "LowerArm", An - la.head)
        m = target.copy()
        m.translation = hb.head.copy()
        _set_world(hb, m)
        out[side] = (hb.head - target.translation).length
    return out


GRIP_CURL = {
    "Right": {"Index": (8, 6, 4), "Middle": (70, 80, 50), "Ring": (74, 80, 48), "Little": (78, 78, 46)},
    "Left": {"Index": (48, 58, 38), "Middle": (56, 66, 42), "Ring": (60, 68, 42), "Little": (64, 68, 40)},
}
TRIGGER_CURL = (30, 42, 22)
THUMB_GRIP = {"Right": (18, 26, 22), "Left": (10, 18, 14)}


def grip_fingers(arm, trigger=False):
    for side, fingers in GRIP_CURL.items():
        for f, angs in fingers.items():
            if trigger and side == "Right" and f == "Index":
                angs = TRIGGER_CURL
            for seg, a in zip(("Proximal", "Intermediate", "Distal"), angs):
                pb = arm.pose.bones[side + f + seg]
                pb.rotation_mode = "QUATERNION"
                pb.rotation_quaternion = _rot_about((1, 0, 0), a)
        for seg, a in zip(("Metacarpal", "Proximal", "Distal"), THUMB_GRIP[side]):
            pb = arm.pose.bones[side + "Thumb" + seg]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = _rot_about((1, 0, 0), a)
    bpy.context.view_layer.update()


def spine_layer(arm, carry, extra_yaw=0.0):
    """Damps the thorax counter-rotation against the pelvis and adds the carry's stance yaw, spread over
    Spine / Chest / UpperChest (world-Z rotations about each bone)."""
    c = CARRIES[carry]
    yp = _heading(arm, "Hips")
    yc = _heading(arm, "UpperChest")
    rel = (yc - yp + math.pi) % (2 * math.pi) - math.pi
    # (a rotation by +a about Z lowers the heading atan2(x, y) by a)
    corr = (1.0 - c["counter"]) * rel + math.radians(c["stance"] + extra_yaw)
    for bone, share in (("Spine", 0.3), ("Chest", 0.35), ("UpperChest", 0.35)):
        _rotate_world(arm, bone, Quaternion((0, 0, 1), corr * share))
    # keep the head looking where it looked (the neck takes back the added torso yaw)
    _rotate_world(arm, "Neck", Quaternion((0, 0, 1), -corr * 0.6))


def _lean_and_head(arm):
    """(thorax lean deg, head pitch deg) in the body's sagittal plane (heading of the pelvis)."""
    y = _heading(arm, "Hips")
    fwd = Vector((math.sin(y), math.cos(y), 0))
    ch = arm.pose.bones["UpperChest"]
    up = (ch.tail - arm.pose.bones["Spine"].head).normalized()
    lean = math.degrees(math.atan2(up.dot(fwd), up.z))
    hf = _bone_forward(arm, "Head")
    pitch = math.degrees(math.atan2(hf.z, hf.dot(fwd)))
    return lean, pitch, fwd


def _bone_forward(arm, bone):
    pb = arm.pose.bones[bone]
    rest = arm.data.bones[bone].matrix_local.to_3x3()
    return (pb.matrix.to_3x3() @ (rest.inverted() @ Vector((0, 1, 0)))).normalized()


def posture_offsets(arm, frames, carry):
    """Constant (lean, head) corrections that bring the clip's mean to the carry's POSTURE."""
    want_lean, want_head = POSTURE.get(carry, (None, None))
    sc = bpy.context.scene
    ls, hs = [], []
    for f in range(0, frames, max(1, frames // 16)):
        sc.frame_set(f)
        lean, pitch, _ = _lean_and_head(arm)
        ls.append(lean)
        hs.append(pitch)
    dl = 0.0 if want_lean is None else want_lean - sum(ls) / len(ls)
    dh = 0.0 if want_head is None else want_head - sum(hs) / len(hs)
    return dl, dh


def apply_posture(arm, dl, dh):
    """Leans the thorax by dl (deg, + = forward) over Spine / Chest / UpperChest and pitches the head by dh after it
    (the neck and head take back the thorax change first)."""
    _, _, fwd = _lean_and_head(arm)
    side = fwd.cross(Vector((0, 0, 1))).normalized()       # right
    # rotation about `side` by +a tips the top backwards (up -> -fwd); forward lean is -a
    for bone, share in (("Spine", 0.4), ("Chest", 0.3), ("UpperChest", 0.3)):
        _rotate_world(arm, bone, Quaternion(side, math.radians(-dl * share)))
    total = dh + dl          # thorax lean tipped the head with it
    for bone, share in (("Neck", 0.45), ("Head", 0.55)):
        _rotate_world(arm, bone, Quaternion(side, math.radians(total * share)))


HEAD_LIMITS = {(1, 0, 0): (-22.0, 6.0), (0, 1, 0): (-14.0, 14.0), (0, 0, 1): (-20.0, 20.0)}


def sight_offset(arm, Wm):
    """The right eye's offset from the sight line (perpendicular to it, armature space)."""
    eye_local = getattr(head_to_sight, "eye_local", None)
    if eye_local is None:
        return Vector()
    v = arm.pose.bones["Head"].matrix @ eye_local - Wm @ Vector((0, -0.05, SIGHT_Z))
    d = Wm.to_3x3() @ Vector((0, 1, 0))
    return v - d * v.dot(d)


def head_to_sight(arm, Wm):
    """Cheek weld: turns neck and head (within HEAD_LIMITS, degrees about world X / Y / Z) so the right eye comes as
    close to the sight line as it can. Returns the eye's remaining offset from the line (vector, armature space)."""
    sight_o = Wm @ Vector((0, -0.05, SIGHT_Z))
    sight_d = Wm.to_3x3() @ Vector((0, 1, 0))
    eye_local = getattr(head_to_sight, "eye_local", None)
    if eye_local is None:
        return Vector()
    hb = arm.pose.bones["Head"]

    def off():
        return sight_offset(arm, Wm)

    acc = {k: 0.0 for k in HEAD_LIMITS}
    best = off().length
    for step in (6.0, 3.0, 1.5, 0.75):
        for _ in range(8):
            improved = False
            for axis, (lo, hi) in HEAD_LIMITS.items():
                for sgn in (1, -1):
                    if not lo <= acc[axis] + sgn * step <= hi:
                        continue
                    for bn, share in (("Neck", 0.5), ("Head", 0.5)):
                        _rotate_world(arm, bn, _rot_about(axis, sgn * step * share))
                    e = off().length
                    if e < best - 1e-5:
                        best = e
                        acc[axis] += sgn * step
                        improved = True
                    else:
                        for bn, share in (("Head", 0.5), ("Neck", 0.5)):
                            _rotate_world(arm, bn, _rot_about(axis, -sgn * step * share))
            if not improved:
                break
    return off()


def weapon_layer(R, carry, frames, sway=0.10, trigger=False, recoil=None, extra_yaw=0.0, aim_head=False,
                 left_override=None):
    """Applies the weapon layer to every frame of the armature's current action and keys the touched bones.
    recoil(f) -> (back m, up deg) adds a firing kick. Returns validation numbers."""
    arm = R.arm
    sc = bpy.context.scene
    act = arm.animation_data.action
    keyed = ["Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand",
             "RightUpperArm", "RightLowerArm", "RightHand"]
    fingers = [b.name for b in arm.data.bones if any(f in b.name for f in ("Thumb", "Index", "Middle", "Ring", "Little"))]
    # Captured right-hand swing relative to the chest, for the weapon's sway (mean removed).
    hand_rel = []
    for f in range(frames):
        sc.frame_set(f)
        ch = arm.pose.bones["UpperChest"].matrix
        hand_rel.append(ch.inverted() @ arm.pose.bones["RightHand"].head)
    mean = sum(hand_rel, Vector()) / len(hand_rel)
    dl, dh = posture_offsets(arm, frames, carry)
    errs = []
    sight = []
    shifts = []
    poses = []

    def place(f):
        """Posture, spine and the carried rifle (stabilised, swaying, kicked) for frame f: (Wm, chest matrix)."""
        sc.frame_set(f)
        for pb in arm.pose.bones:
            pb.rotation_mode = "QUATERNION"
            pb.scale = Vector((1, 1, 1))
        apply_posture(arm, dl, dh)
        spine_layer(arm, carry, extra_yaw)
        ch = arm.pose.bones["UpperChest"].matrix.copy()
        sh_r = arm.pose.bones["RightUpperArm"].head.copy()
        Wm = carry_matrix(R, carry, ch, sh_r)
        # Stabilise against the chest's pitch and roll but keep its heading.
        yaw = _heading(arm, "UpperChest")
        upright = Matrix.Translation(ch.translation) @ Quaternion((0, 0, 1), -yaw).to_matrix().to_4x4() @             Matrix.Translation(-ch.translation) @ R.chest_rest
        upright.translation = ch.translation
        Wu = carry_matrix(R, carry, upright, sh_r)
        Wm = _stabilise(Wm, Wu, CARRIES[carry]["stab"])
        # Sway with the captured arm swing (chest space -> world).
        Wm.translation += ch.to_3x3() @ ((hand_rel[f] - mean) * sway)
        if recoil:
            back, up = recoil(f)
            fwd = Wm.to_3x3() @ Vector((0, 1, 0))
            rr = Wm.to_3x3() @ Vector((1, 0, 0))
            q = Quaternion(rr, math.radians(up))
            m3 = q.to_matrix() @ Wm.to_3x3()
            t = Wm.translation - fwd * back
            Wm = m3.to_4x4()
            Wm.translation = t
            # the shoulder and chest take the kick
            _rotate_world(arm, "UpperChest", Quaternion(rr, math.radians(-up * 0.35)))
        return Wm, ch

    # Cheek weld fit: the mean offset (chest space) still left between eye and sight line after the head has turned
    # moves the rifle once for the whole clip (the butt sits that much lower / further in on the shoulder); per frame the
    # rifle then only closes what the capture's own motion adds (at most AIM_SHIFT_MAX).
    fit = Vector()
    if aim_head:
        res = []
        for f in range(frames):
            Wm, ch = place(f)
            res.append(ch.to_3x3().inverted() @ head_to_sight(arm, Wm))
        fit = sum(res, Vector()) / len(res)
    for f in range(frames):
        Wm, ch = place(f)
        if aim_head:
            Wm.translation += ch.to_3x3() @ fit
            # head to the stock as far as a shooter bends, then the rifle up to the eye (cheek weld)
            rest_off = head_to_sight(arm, Wm)
            shifts.append(rest_off.length)
            if rest_off.length > AIM_SHIFT_MAX:
                rest_off = rest_off.normalized() * AIM_SHIFT_MAX
            Wm.translation += rest_off
            # back along the bore (the sight line stays on the eye) while a hand would have to stretch too far
            for _ in range(16):
                if max(_reach_pose(R, arm, Wm)) <= 0.97:
                    break
                Wm.translation -= Wm.to_3x3() @ Vector((0, 0.005, 0))
            sight.append(sight_offset(arm, Wm).length)
        reach = _reach_pose(R, arm, Wm)
        e = solve_arms(R, Wm, carry, ch, left_override)
        errs.append((e["Right"], e["Left"], reach))
        grip_fingers(arm, trigger)
        poses.append({b: (arm.pose.bones[b].location.copy(), arm.pose.bones[b].rotation_quaternion.copy())
                      for b in keyed + fingers})
    for f, pose in enumerate(poses):
        for b, (loc, rot) in pose.items():
            pb = arm.pose.bones[b]
            pb.location = loc
            pb.rotation_quaternion = rot
            pb.keyframe_insert("rotation_quaternion", frame=f, group=b)
    # close the loop
    for b, (loc, rot) in poses[0].items():
        pb = arm.pose.bones[b]
        pb.rotation_quaternion = rot
        pb.keyframe_insert("rotation_quaternion", frame=frames, group=b)
    return {"posture_fix_deg": [round(dl, 1), round(dh, 1)], "hand_err_mm_r": round(max(e[0] for e in errs) * 1000, 1), "hand_err_mm_l": round(max(e[1] for e in errs) * 1000, 1),
            "reach_at_worst": [round(x, 3) for x in max(errs, key=lambda e: max(e[0], e[1]))[2]],
            "sight_err_mm": round(max(sight) * 1000, 1) if sight else None,
            "sight_err_mean_mm": round(sum(sight) / len(sight) * 1000, 1) if sight else None,
            "rifle_to_eye_mm": round(max(shifts) * 1000, 1) if shifts else None,
            "aim_fit_mm": [round(x * 1000, 1) for x in fit] if aim_head else None}


# ------------------------------------------------------------------------------------------------ clips


class Builder:
    def __init__(self, arm, weight_ref=None):
        self.R = Rig(arm)
        self.arm = arm
        self.ref = weight_ref
        self.actions = {}
        self.meta = {}
        self.checks = {}
        self._src = {}

    def _samples(self, take):
        if take not in self._src:
            src, f0, n, ft = MC.load_bvh(_take(take))
            self._src[take] = (src, MC.sample(src, f0, n), ft)
        return self._src[take]

    def loco(self, clip, takes, motion, carry):
        err = None
        for take in takes:
            src, samples, ft = self._samples(take)
            try:
                if motion == "forward":
                    sub = samples
                else:
                    a, b = MC.find_window(samples, ft, motion)
                    sub = samples[a:b + 1]
                i0, i1, phase = MC.pick_cycle(sub)
                break
            except RuntimeError as e:
                err = e
        else:
            raise err
        reset_pose(self.arm)
        act, speed, period, direction = MC.retarget_cycle(src, self.arm, sub, i0, i1, ft, LOCO_FRAMES, clip,
                                                          phase=phase, align="travel" if motion == "forward" else "facing")
        self._ground(act, LOCO_FRAMES)
        before = MC.foot_slip(self.arm, act, LOCO_FRAMES, speed, period, direction)
        lock = MC.foot_lock(self.arm, act, LOCO_FRAMES, speed, period, direction)
        self.meta[clip] = {"take": take, "speed": round(speed, 3), "period": round(period, 4),
                           "dir": [round(direction.x, 3), round(direction.y, 3)], "carry": carry}
        self.checks[clip] = {"slip_before_lock": before, "slip": MC.foot_slip(self.arm, act, LOCO_FRAMES, speed, period, direction),
                             "lock": lock}
        return act

    def _ground(self, act, frames):
        """Puts the lowest sole point of the cycle on the floor (Hips location keys)."""
        sc = bpy.context.scene
        self.arm.animation_data.action = act
        low = 1e9
        for f in range(0, frames, 2):
            sc.frame_set(f)
            for s in ("Left", "Right"):
                for b in ("Foot", "Toes"):
                    pb = self.arm.pose.bones[s + b]
                    low = min(low, pb.head.z - self.arm.data.bones[s + b].head_local.z)
        hb = self.arm.data.bones["Hips"]
        d_local = hb.matrix_local.to_3x3().inverted() @ Vector((0, 0, -low))
        for fc in MC_fcurves(act, "Hips", "location"):
            for kp in fc.keyframe_points:
                kp.co.y += d_local[fc.array_index]
                kp.handle_left.y += d_local[fc.array_index]
                kp.handle_right.y += d_local[fc.array_index]
            fc.update()

    def crouchify(self, act, frames, drop=CROUCH_DROP, lean=18.0):
        """Lowers the pelvis of a captured cycle and bends the legs onto the same foot plants."""
        sc = bpy.context.scene
        arm = self.arm
        reset_pose(arm)
        arm.animation_data.action = act
        R = self.R
        poses = []
        for f in range(frames):
            sc.frame_set(f)
            feet = {s: (arm.pose.bones[s + "Foot"].head.copy(), arm.pose.bones[s + "Foot"].matrix.to_3x3().copy(),
                        arm.pose.bones[s + "Toes"].rotation_quaternion.copy()) for s in ("Left", "Right")}
            hb = arm.pose.bones["Hips"]
            m = hb.matrix.copy()
            m.translation.z -= drop
            m.translation.y -= 0.06
            _set_world(hb, m)
            _rotate_world(arm, "Hips", Quaternion(Vector((1, 0, 0)), math.radians(-lean)))
            _rotate_world(arm, "Spine", Quaternion(Vector((1, 0, 0)), math.radians(lean * 0.55)))
            _rotate_world(arm, "Chest", Quaternion(Vector((1, 0, 0)), math.radians(lean * 0.2)))
            for s in ("Left", "Right"):
                a, frot, toes = feet[s]
                ul, ll = arm.pose.bones[s + "UpperLeg"], arm.pose.bones[s + "LowerLeg"]
                l1, l2 = R.len[s + "Leg"]
                H = ul.head.copy()
                pole = H + Vector((0.08 if s == "Right" else -0.08, 0.8, 0))
                Kn, An = two_bone(H, ll.head.copy(), a, l1, l2, pole)
                _aim_bone(arm, s + "UpperLeg", Kn - H)
                _aim_bone(arm, s + "LowerLeg", An - ll.head)
                fb = arm.pose.bones[s + "Foot"]
                mm = frot.to_4x4()
                mm.translation = fb.head.copy()
                _set_world(fb, mm)
            keys = ["Hips", "Spine", "Chest"] + [s + b for s in ("Left", "Right") for b in ("UpperLeg", "LowerLeg", "Foot")]
            poses.append({b: (arm.pose.bones[b].location.copy(), arm.pose.bones[b].rotation_quaternion.copy()) for b in keys})
        for f, pose in enumerate(poses + [poses[0]]):
            for b, (loc, rot) in pose.items():
                pb = arm.pose.bones[b]
                pb.location, pb.rotation_quaternion = loc, rot
                pb.keyframe_insert("rotation_quaternion", frame=f, group=b)
                if b == "Hips":
                    pb.keyframe_insert("location", frame=f, group=b)

    def copy(self, name, src_name, carry=None):
        """A new action from an existing one (keys copied), weapon layer applied again when carry is given."""
        a = self.actions[src_name].copy()
        a.name = name
        a.use_fake_user = True
        return a

    def finish(self, name, act, carry, frames, loop=True, **kw):
        reset_pose(self.arm)
        self.arm.animation_data.action = act
        res = self.weapon(carry, frames, **kw)
        act["fn_frames"] = frames
        act["fn_loop"] = loop
        self.actions[name] = act
        self.checks.setdefault(name, {})["weapon"] = res
        return act

    def weapon(self, carry, frames, **kw):
        return weapon_layer(self.R, carry, frames, **kw)

    def build_all(self, only=None):
        want = lambda n: only is None or n in only  # noqa: E731
        need = set()
        for clip in LOCO:
            if want(clip) or any(want(k) for k, v in DERIVED.items() if v == clip) or \
                    (clip == "Run_F" and want("Sprint_F")) or (clip.startswith("Walk_") and want("CrouchWalk_" + clip[-1])):
                need.add(clip)
        bases = {}
        for clip in LOCO:
            if clip in need:
                takes, motion, carry = LOCO[clip]
                bases[clip] = self.loco(clip, takes, motion, carry)
        # Crouch walks from the walks (before their weapon layer).
        for d in "FBLR":
            if "Walk_" + d in bases and want("CrouchWalk_" + d):
                c = bases["Walk_" + d].copy()
                c.name = "CrouchWalk_" + d
                c.use_fake_user = True
                self.crouchify(c, LOCO_FRAMES)
                m = dict(self.meta["Walk_" + d])
                m["speed"] = round(m["speed"] * 0.85, 3)        # shorter steps in a crouch: same cadence, 85 % stride
                self.meta["CrouchWalk_" + d] = m
                self.finish("CrouchWalk_" + d, c, "crouch", LOCO_FRAMES)
        # Derived fast directional clips: copies of the walking keys before the layer, with a faster carry.
        for name, base in DERIVED.items():
            if want(name) and base in bases:
                c = bases[base].copy()
                c.name = name
                c.use_fake_user = True
                self.meta[name] = dict(self.meta[base], carry="ready")
                self.finish(name, c, "ready", LOCO_FRAMES)
        if want("Sprint_F") and "Run_F" in bases:
            c = bases["Run_F"].copy()
            c.name = "Sprint_F"
            c.use_fake_user = True
            self.meta["Sprint_F"] = dict(self.meta["Run_F"], carry="port")
            self.finish("Sprint_F", c, "port", LOCO_FRAMES, sway=0.06)
        for clip, act in bases.items():
            if want(clip):
                self.finish(clip, act, LOCO[clip][2], LOCO_FRAMES)
            else:
                bpy.data.actions.remove(act)
        for clip, (takes, motion) in TURNS.items():
            if not want(clip):
                continue
            err = None
            for take in takes:
                src, samples, ft = self._samples(take)
                try:
                    a, b = MC.find_window(samples, ft, motion, min_s=0.6)
                    sub = samples[a:b + 1]
                    try:
                        i0, i1, phase = MC.pick_cycle(sub)
                    except RuntimeError:
                        # turning steps barely lift the feet: one second of the turn, looped by the end blend
                        i0, i1, phase = 0, min(len(sub) - 1, int(round(1.0 / ft))), 0.0
                    break
                except RuntimeError as e:
                    err = e
            else:
                raise err
            reset_pose(self.arm)
            act, speed, period, direction = MC.retarget_cycle(src, self.arm, sub, i0, i1, ft, LOCO_FRAMES, clip,
                                                              phase=phase, align="facing", unwind=True)
            self._ground(act, LOCO_FRAMES)
            self.meta[clip] = {"take": take, "turn_rate": round(act["fn_turn_rate"], 3), "period": round(period, 4)}
            self.finish(clip, act, "low", LOCO_FRAMES)
        if any(want(n) for n in ("Idle", "Ready_Idle", "Crouch_Idle", "Aim", "Fire", "Reload")):
            self.idles(want)
        if any(want(n) for n in PRONE_CLIPS):
            # COMBAT-01: prone and the change of posture (char_prone; needs Ready_Idle for the standing end).
            import char_prone as P
            P.Prone(self).build(want)
        return self.actions

    def idles(self, want):
        src, samples, ft = self._samples(IDLE_TAKE)
        n = len(samples)
        span = int(round(IDLE_FRAMES / FPS / ft))
        i0 = max(0, (n - span) // 2)
        i1 = min(n - 1, i0 + span)
        reset_pose(self.arm)
        base, speed, period, _ = MC.retarget_cycle(src, self.arm, samples, i0, i1, ft, IDLE_FRAMES, "Idle_base",
                                                   align="facing", in_place=True)
        self._ground(base, IDLE_FRAMES)
        MC.foot_lock(self.arm, base, IDLE_FRAMES, 0.0, period)
        self.meta["Idle"] = {"take": IDLE_TAKE, "period": round(IDLE_FRAMES / FPS, 3)}
        jobs = [("Idle", "low", {}), ("Ready_Idle", "ready", {}),
                ("Aim", "aim", {"aim_head": True, "trigger": True, "sway": 0.0}),
                ("Fire", "aim", {"aim_head": True, "trigger": True, "sway": 0.0, "recoil": _recoil})]
        for name, carry, kw in jobs:
            if not want(name):
                continue
            c = base.copy()
            c.name = name
            c.use_fake_user = True
            frames = IDLE_FRAMES
            if name == "Fire":
                frames = FIRE_FRAMES
                _trim(c, FIRE_FRAMES)
            self.finish(name, c, carry, frames, loop=name != "Fire", **kw)
        if want("Crouch_Idle"):
            c = base.copy()
            c.name = "Crouch_Idle"
            c.use_fake_user = True
            self.crouch_idle(c)
            self.finish("Crouch_Idle", c, "crouch", IDLE_FRAMES)
        if want("Reload"):
            c = base.copy()
            c.name = "Reload"
            c.use_fake_user = True
            _trim(c, RELOAD_FRAMES)
            self.finish("Reload", c, "ready", RELOAD_FRAMES, loop=False, left_override=None)
            self.checks["Reload"]["magazine"] = reload_left_hand(self, c, RELOAD_FRAMES)
        bpy.data.actions.remove(base)

    def crouch_idle(self, act):
        """Squat-crouch on the captured idle: left foot forward flat, right foot back on its ball."""
        sc = bpy.context.scene
        arm = self.arm
        reset_pose(arm)
        arm.animation_data.action = act
        R = self.R
        poses = []
        for f in range(IDLE_FRAMES):
            sc.frame_set(f)
            hb = arm.pose.bones["Hips"]
            m = hb.matrix.copy()
            m.translation.z -= 0.40
            m.translation.y -= 0.05
            _set_world(hb, m)
            _rotate_world(arm, "Hips", Quaternion(Vector((1, 0, 0)), math.radians(-24)))
            _rotate_world(arm, "Spine", Quaternion(Vector((1, 0, 0)), math.radians(14)))
            _rotate_world(arm, "Chest", Quaternion(Vector((1, 0, 0)), math.radians(4)))
            for s, fwd, heel, toe_bend in (("Left", 0.20, 0.0, 0.0), ("Right", -0.20, 0.11, 40.0)):
                ul, ll = arm.pose.bones[s + "UpperLeg"], arm.pose.bones[s + "LowerLeg"]
                rest_a = arm.data.bones[s + "Foot"].head_local
                x = rest_a.x * 1.15
                target = Vector((x, rest_a.y + fwd, rest_a.z + heel))
                l1, l2 = R.len[s + "Leg"]
                H = ul.head.copy()
                pole = H + Vector((0.15 if s == "Right" else -0.15, 0.9, 0.0))
                Kn, An = two_bone(H, ll.head.copy(), target, l1, l2, pole)
                _aim_bone(arm, s + "UpperLeg", Kn - H)
                _aim_bone(arm, s + "LowerLeg", An - ll.head)
                fb = arm.pose.bones[s + "Foot"]
                mm = (Quaternion(Vector((1, 0, 0)), math.radians(-toe_bend)).to_matrix() @ R.rest[s + "Foot"].to_3x3()).to_4x4()
                mm.translation = fb.head.copy()
                _set_world(fb, mm)
                tb = arm.pose.bones[s + "Toes"]
                tb.rotation_quaternion = Quaternion(Vector((1, 0, 0)), math.radians(toe_bend))
            keys = ["Hips", "Spine", "Chest"] + [s + b for s in ("Left", "Right") for b in ("UpperLeg", "LowerLeg", "Foot", "Toes")]
            poses.append({b: (arm.pose.bones[b].location.copy(), arm.pose.bones[b].rotation_quaternion.copy()) for b in keys})
        for f, pose in enumerate(poses + [poses[0]]):
            for b, (loc, rot) in pose.items():
                pb = arm.pose.bones[b]
                pb.location, pb.rotation_quaternion = loc, rot
                pb.keyframe_insert("rotation_quaternion", frame=f, group=b)
                if b == "Hips":
                    pb.keyframe_insert("location", frame=f, group=b)


FIRE_FRAMES = 6
RELOAD_FRAMES = 75


def _recoil(f):
    """Kick of one shot over FIRE_FRAMES: back (m) and muzzle rise (deg), recovered by the end."""
    t = f / FIRE_FRAMES
    k = math.sin(math.pi * min(1.0, t * 1.6)) if t < 0.62 else max(0.0, 1.0 - (t - 0.62) / 0.38) * 0.2
    return 0.022 * k, 3.5 * k


def _trim(act, frames):
    """Drops keys after `frames` (one-shots cut from the idle base)."""
    for fc in MC_fcurves(act):
        for kp in list(fc.keyframe_points)[::-1]:
            if kp.co.x > frames + 0.5:
                fc.keyframe_points.remove(kp)


# Reload: the support hand on the magazine (weapon space): fist round the lower body of the magazine from its left side,
# fingers up towards the magwell, palm against it. The same point serves every rifle (the magazine rides on the hand).
MAG_GRIP = Vector((0.0, 0.088, -0.095))
MAG_AXIS = Vector((0.0, -0.20, 1.0)).normalized()
MAG_PALM = Vector((1.0, 0.15, 0.0))
MAG_PULL = 0.085                                   # magazine drawn out of the well before it moves away (m)
# phase ends (fraction of the clip): reach, grab, pull out, to the pouch, swap, back under the well, insert, seat, back
RELOAD_PHASES = (0.12, 0.16, 0.26, 0.42, 0.48, 0.62, 0.72, 0.76, 1.0)


def reload_left_hand(b, act, frames):
    """Reload: the support hand leaves the handguard for the magazine, draws it out of the well, takes it to the left
    belt pouch (stowed, the new one drawn), brings it back under the well, inserts it and returns to the handguard.
    Keys the left arm and the ATT_Magazine bone, which carries the weapon's detachable magazine with the hand from the
    grab to the seat (identity = in the well before and after, so the magazine and rifle stay together)."""
    arm = b.arm
    R = b.R
    sc = bpy.context.scene
    reset_pose(arm)
    arm.animation_data.action = act
    ax_w, palm_w, thumb_w, grip_w = W.support_frame()
    keys = ["LeftUpperArm", "LeftLowerArm", "LeftHand"]
    t_reach, t_grab, t_pull, t_pouch, t_swap, t_under, t_in, t_seat, _ = RELOAD_PHASES
    poses, mags = [], []
    offset = None
    pm = arm.pose.bones["ATT_Magazine"]
    for f in range(frames + 1):
        sc.frame_set(f)
        t = f / frames
        ch = arm.pose.bones["UpperChest"].matrix
        hr = arm.pose.bones["RightHand"].matrix
        Wm = hr @ R.hand_r_in_w.inverted()
        W3 = Wm.to_3x3()
        pouch = ch @ (R.chest_rest.inverted() @ Vector((-0.115, 0.235, 1.07)))
        g_hand = Wm @ grip_w
        seat = Wm @ MAG_GRIP
        drawn = seat - W3 @ Vector((0, 0, MAG_PULL))
        on_mag = 1.0
        if t < t_reach:
            k = _ease(t / t_reach)
            p, on_mag = g_hand.lerp(seat, k), k
        elif t < t_grab:
            p = seat
        elif t < t_pull:
            p = seat.lerp(drawn, _ease((t - t_grab) / (t_pull - t_grab)))
        elif t < t_pouch:
            p = drawn.lerp(pouch, _ease((t - t_pull) / (t_pouch - t_pull)))
        elif t < t_swap:
            p = pouch
        elif t < t_under:
            p = pouch.lerp(drawn, _ease((t - t_swap) / (t_under - t_swap)))
        elif t < t_in:
            p = drawn.lerp(seat, _ease((t - t_under) / (t_in - t_under)))
        elif t < t_seat:
            p = seat
        else:
            k = _ease((t - t_seat) / (1.0 - t_seat))
            p, on_mag = seat.lerp(g_hand, k), 1.0 - k
        ax = (W3 @ ax_w).normalized().lerp((W3 @ MAG_AXIS).normalized(), on_mag).normalized()
        palm = (W3 @ palm_w).normalized().lerp((W3 @ MAG_PALM).normalized(), on_mag).normalized()
        palm = (palm - ax * palm.dot(ax)).normalized()
        wrist = p - ax * S.GRIP_IN_HAND[0] - palm * S.GRIP_IN_HAND[1]
        ua, la, hb = arm.pose.bones["LeftUpperArm"], arm.pose.bones["LeftLowerArm"], arm.pose.bones["LeftHand"]
        H = ua.head.copy()
        l1, l2 = R.len["LeftArm"]
        rot = ch.to_3x3() @ R.chest_rest.to_3x3().inverted()
        Kn, An = two_bone(H, la.head.copy(), wrist, l1, l2, H + rot @ Vector((-0.30, 0.0, -0.50)))
        _aim_bone(arm, "LeftUpperArm", Kn - H)
        _aim_bone(arm, "LeftLowerArm", An - la.head)
        hl = (_basis(ax, palm) @ R.hand_l_basis_rest.inverted() @ R.rest["LeftHand"].to_3x3()).to_4x4()
        hl.translation = hb.head.copy()
        _set_world(hb, hl)
        poses.append({k: arm.pose.bones[k].rotation_quaternion.copy() for k in keys})
        # the magazine: in the well until the grab, then rigidly in the hand until it is seated again
        attw = arm.pose.bones["ATT_Weapon"].matrix
        if t_grab <= t < t_seat:
            if offset is None:
                offset = hb.matrix.inverted() @ attw
            _set_world(pm, hb.matrix @ offset)
        else:
            _set_world(pm, attw.copy())
        mags.append((pm.location.copy(), pm.rotation_quaternion.copy()))
    for f, pose in enumerate(poses):
        for k, rot in pose.items():
            pb = arm.pose.bones[k]
            pb.rotation_quaternion = rot
            pb.keyframe_insert("rotation_quaternion", frame=f, group=k)
        pm.location, pm.rotation_quaternion = mags[f]
        pm.keyframe_insert("location", frame=f, group="ATT_Magazine")
        pm.keyframe_insert("rotation_quaternion", frame=f, group="ATT_Magazine")
    seat_err = max((m[0].length for m in mags[:int(t_grab * frames)] + mags[int(t_seat * frames) + 1:]), default=0.0)
    return {"mag_travel_m": round(max(m[0].length for m in mags), 3), "mag_rest_err_mm": round(seat_err * 1000, 2)}


def reset_pose(arm):
    """Rest pose on every bone: a clip only keys some channels, and Blender keeps the last value on the others."""
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.location = Vector()
        pb.rotation_quaternion = Quaternion()
        pb.scale = Vector((1, 1, 1))
    bpy.context.view_layer.update()


def _ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def MC_fcurves(act, bone=None, prop=None):
    curves = []
    path = f'pose.bones["{bone}"].{prop}' if bone else None
    if hasattr(act, "layers") and len(act.layers):
        for lay in act.layers:
            for st in lay.strips:
                for cb in st.channelbags:
                    curves += [fc for fc in cb.fcurves if path is None or fc.data_path == path]
    else:
        curves = [fc for fc in act.fcurves if path is None or fc.data_path == path]
    return curves


# ------------------------------------------------------------------------------------------------ entry points


def clip_list():
    return list(LOCO) + list(DERIVED) + ["Sprint_F"] + ["CrouchWalk_" + d for d in "FBLR"] + list(TURNS) + \
        ["Idle", "Ready_Idle", "Crouch_Idle", "Aim", "Fire", "Reload"] + PRONE_CLIPS


def build_clips(arm, weight_ref=None, only=None):
    """Builds every clip (or `only`); returns (actions, meta, checks)."""
    sc = bpy.context.scene
    sc.render.fps = FPS
    eye = head_eye_local(arm)
    head_to_sight.eye_local = eye
    b = Builder(arm, weight_ref)
    b.checks["carry_fit"] = b.R.carry_fit
    b.build_all(set(only) if only else None)
    for src, _, _ in b._src.values():
        # the raw takes' actions would otherwise be exported as clips of the rig
        act = src.animation_data.action if src.animation_data else None
        bpy.data.objects.remove(src, do_unlink=True)
        if act is not None:
            bpy.data.actions.remove(act)
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.location = Vector()
        pb.rotation_quaternion = Quaternion()
    return b.actions, b.meta, b.checks


def head_eye_local(arm):
    """Right eye position in the Head bone's rest space (char_body stored the eye centres)."""
    import char_body as B
    eyes = B._STATE.get("eyes")
    if not eyes:
        return None
    right = max(eyes, key=lambda e: e[0][0])[0]
    return arm.data.bones["Head"].matrix_local.inverted() @ Vector(right)


def write_meta(path, actions, meta):
    """animation_meta.json: per-clip frames / loop and the gait table (speed, period, direction) the game uses."""
    gait = {}
    for k in ("Walk_F", "Brisk_F", "Jog_F", "Run_F", "Sprint_F", "CrouchWalk_F", "ProneCrawl_F"):
        if k in meta and "speed" in meta[k]:
            gait[k.split("_")[0]] = {"speed": meta[k]["speed"], "period": meta[k]["period"]}
    if "Sprint" in gait:
        gait["Sprint"] = {"speed": 7.5, "period": gait["Run"]["period"] * 0.92}
    out = {"fps": FPS, "loco_frames": LOCO_FRAMES, "gait": gait, "clip_meta": meta,
           "clips": {n: {"frames": int(a["fn_frames"]), "loop": bool(a["fn_loop"])} for n, a in actions.items()}}
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
