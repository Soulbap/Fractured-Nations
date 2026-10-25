"""Shared infantry skeleton (CHARACTER-01).

Bone names follow Godot's SkeletonProfileHumanoid exactly (Root, Hips, Spine, Chest,
UpperChest, Neck, Head, Left/Right Shoulder, UpperArm, LowerArm, Hand, finger bones,
UpperLeg, LowerLeg, Foot, Toes), so Godot maps it to the humanoid profile automatically.
Extra bones:
  ATT_*   attachment points (deform flag on, no weights, so the glTF exporter keeps them).
          Rest orientation is "item space": bone Y = item forward, bone Z = item up,
          i.e. an identity rotation in Blender for points aligned with the character.
  CTRL_*  animation authoring controls (IK targets, poles, weapon). Not exported.

Rest pose: A-pose, arms 45 deg below horizontal, palms facing the thighs, character
1.80 m tall, facing +Y, left side at -X. All lengths in metres.
"""
import math

import bpy
from mathutils import Matrix, Vector

HEIGHT = 1.80
ARM_DROP_DEG = 45.0


def _arm_dir(side):
    a = math.radians(ARM_DROP_DEG)
    return Vector((side * math.cos(a), 0.0, -math.sin(a)))


_JOINTS = None


def set_joints(j):
    """VISUAL-03: the built body's joints in reference space (char_body.build); joints() returns them from then on."""
    global _JOINTS
    _JOINTS = j


def joints():
    """Joint positions of the current body in reference space (see char_body: the MakeHuman body's joints with
    heights mapped onto the CHARACTER-01 layout); the CHARACTER-01 layout until a body is built."""
    return dict(_JOINTS) if _JOINTS is not None else ref_joints()


def ref_joints():
    """CHARACTER-01 reference layout: the space every garment and gear piece is authored in.
    side = -1 left (-X), +1 right (+X)."""
    j = {
        "Root": Vector((0, 0, 0)),
        "Hips": Vector((0, 0.0, 0.975)),
        "Spine": Vector((0, -0.008, 1.075)),
        "Chest": Vector((0, -0.012, 1.20)),
        "UpperChest": Vector((0, -0.016, 1.325)),
        "Neck": Vector((0, -0.028, 1.495)),
        "Head": Vector((0, -0.012, 1.595)),
        "HeadTop": Vector((0, -0.012, 1.80)),
    }
    for side, s in ((-1, "Left"), (1, "Right")):
        d = _arm_dir(side)
        sh = Vector((side * 0.172, -0.024, 1.452))
        elbow = sh + d * 0.305 + Vector((0, -0.022, 0))
        fdir = (d + Vector((0, 0.16, 0))).normalized()
        wrist = elbow + fdir * 0.266
        knuckle = wrist + d * 0.093
        j[s + "ShoulderStart"] = Vector((side * 0.022, -0.004, 1.448))
        j[s + "UpperArm"] = sh
        j[s + "LowerArm"] = elbow
        j[s + "Hand"] = wrist
        j[s + "Knuckle"] = knuckle
        j[s + "UpperLeg"] = Vector((side * 0.091, 0.004, 0.932))
        j[s + "LowerLeg"] = Vector((side * 0.097, 0.016, 0.505))
        j[s + "Foot"] = Vector((side * 0.103, -0.024, 0.088))
        j[s + "Toes"] = Vector((side * 0.112, 0.118, 0.022))
        j[s + "ToeTip"] = Vector((side * 0.118, 0.188, 0.018))
    return j


def hand_frame(side):
    """Rest-pose hand frame (axis wrist->knuckle, palm normal, thumb direction)."""
    j = joints()
    s = "Left" if side < 0 else "Right"
    axis = (j[s + "Knuckle"] - j[s + "Hand"]).normalized()
    # Palm faces the thigh: perpendicular to the axis, pointing inward/down.
    inward = Vector((-side, 0, 0))
    palm = (inward - axis * inward.dot(axis)).normalized()
    thumb = axis.cross(palm) if side > 0 else palm.cross(axis)
    if thumb.y < 0:
        thumb = -thumb
    palm = thumb.cross(axis) if side > 0 else axis.cross(thumb)
    return axis, palm.normalized(), thumb.normalized()


# Finger layout in hand space: (name, base offset along axis, offset along thumb dir,
# offset along palm normal, segment lengths, spread angle deg)
FINGERS = [
    ("Index", 0.0, 0.033, 0.004, (0.046, 0.027, 0.022), 6.0),
    ("Middle", 0.004, 0.011, 0.004, (0.050, 0.031, 0.024), 0.0),
    ("Ring", 0.0, -0.011, 0.004, (0.046, 0.030, 0.023), -6.0),
    ("Little", -0.008, -0.032, 0.006, (0.037, 0.022, 0.020), -12.0),
]
FINGER_SEGS = ("Proximal", "Intermediate", "Distal")
THUMB_SEGS = ("Metacarpal", "Proximal", "Distal")
THUMB_LEN = (0.040, 0.034, 0.030)


def finger_chains(side):
    """Returns {bone_name: (head, tail)} for the fingers of one hand in rest pose."""
    j = joints()
    s = "Left" if side < 0 else "Right"
    axis, palm, thumb = hand_frame(side)
    out = {}
    k = j[s + "Knuckle"]
    for name, da, dt, dp, lens, spread in FINGERS:
        base = k + axis * da + thumb * dt + palm * dp
        rot = Matrix.Rotation(math.radians(spread), 3, palm)
        d = (rot @ axis).normalized()
        p = base
        for seg, ln in zip(FINGER_SEGS, lens):
            # slight natural curl towards the palm in rest pose
            d = (d + palm * 0.10).normalized()
            out[s + name + seg] = (p.copy(), p + d * ln)
            p = p + d * ln
    w = j[s + "Hand"]
    tbase = w + axis * 0.022 + thumb * 0.022 + palm * 0.012
    d = (axis * 0.55 + thumb * 0.62 + palm * 0.35).normalized()
    p = tbase
    for seg, ln in zip(THUMB_SEGS, THUMB_LEN):
        out[s + "Thumb" + seg] = (p.copy(), p + d * ln)
        p = p + d * ln
        d = (d + axis * 0.25 + palm * 0.12).normalized()
    return out


# Attachment points: name -> (parent bone, position, forward, up). Rotation identity
# (forward +Y, up +Z) except the weapon/hand points, which are set by the grip pose.
def attachments():
    j = joints()
    return {
        "ATT_Head": ("Head", Vector((0, -0.010, 1.700)), None, None),
        "ATT_Chest": ("UpperChest", Vector((0, 0.150, 1.300)), None, None),
        "ATT_Back": ("UpperChest", Vector((0, -0.150, 1.300)), None, None),
        "ATT_Hip_L": ("Hips", Vector((-0.185, -0.010, 1.000)), None, None),
        "ATT_Hip_R": ("Hips", Vector((0.185, -0.010, 1.000)), None, None),
        "ATT_Weapon": ("RightHand", None, None, None),     # set from grip pose
        "ATT_Magazine": ("ATT_Weapon", None, None, None),  # = ATT_Weapon at rest; the reload clip moves it with the hand
        "ATT_Hand_L": ("LeftHand", None, None, None),      # set from hand frame
    }


# Grip geometry: where the weapon grip centre sits in the right hand, expressed in the
# hand frame (axis, palm, thumb), and the weapon orientation in that frame.
GRIP_IN_HAND = (0.050, 0.038, 0.004)   # along axis, along palm normal, along thumb
GRIP_TILT_DEG = 20.0                    # hand axis runs this far below the bore


def weapon_frame_from_hand(side=1, hand_axis=None, palm=None, thumb=None, wrist=None):
    """Weapon (forward, up, origin) given a right-hand frame.

    Holding a pistol grip: the hand axis runs perpendicular to the grip, i.e. forward and
    ~20 deg down along the bore; the palm faces the weapon's left; the thumb points up
    and wraps over the left side. So weapon forward = axis rotated 20 deg up about palm,
    weapon up ~ thumb, weapon right = -palm.
    """
    if hand_axis is None:
        hand_axis, palm, thumb = hand_frame(side)
        wrist = joints()["RightHand"]
    a = math.radians(GRIP_TILT_DEG)
    fwd = (hand_axis * math.cos(a) + thumb * math.sin(a)).normalized()
    up = (thumb * math.cos(a) - hand_axis * math.sin(a)).normalized()
    origin = wrist + hand_axis * GRIP_IN_HAND[0] + palm * GRIP_IN_HAND[1] + thumb * GRIP_IN_HAND[2]
    return fwd, up, origin


def frame_matrix(fwd, up, origin):
    """4x4 with X = right (fwd x up), Y = forward, Z = up."""
    fwd = fwd.normalized()
    right = fwd.cross(up).normalized()
    upn = right.cross(fwd).normalized()
    m = Matrix((right, fwd, upn)).transposed().to_4x4()
    m.translation = origin
    return m


def bone_list():
    """(name, head, tail, parent, deform, roll_up_vector)."""
    j = joints()
    up = Vector((0, 1, 0))     # roll reference for vertical bones: Z faces forward
    out = [
        ("Root", j["Root"], j["Root"] + Vector((0, 0, 0.12)), None, True, up),
        ("Hips", j["Hips"], j["Spine"], "Root", True, up),
        ("Spine", j["Spine"], j["Chest"], "Hips", True, up),
        ("Chest", j["Chest"], j["UpperChest"], "Spine", True, up),
        ("UpperChest", j["UpperChest"], j["Neck"], "Chest", True, up),
        ("Neck", j["Neck"], j["Head"], "UpperChest", True, up),
        ("Head", j["Head"], j["HeadTop"], "Neck", True, up),
    ]
    for side, s in ((-1, "Left"), (1, "Right")):
        fwd = Vector((0, 1, 0))
        out += [
            (s + "Shoulder", j[s + "ShoulderStart"], j[s + "UpperArm"], "UpperChest", True, Vector((0, 0, 1))),
            (s + "UpperArm", j[s + "UpperArm"], j[s + "LowerArm"], s + "Shoulder", True, -fwd),
            (s + "LowerArm", j[s + "LowerArm"], j[s + "Hand"], s + "UpperArm", True, -fwd),
            (s + "Hand", j[s + "Hand"], j[s + "Knuckle"], s + "LowerArm", True, None),
            (s + "UpperLeg", j[s + "UpperLeg"], j[s + "LowerLeg"], "Hips", True, fwd),
            (s + "LowerLeg", j[s + "LowerLeg"], j[s + "Foot"], s + "UpperLeg", True, fwd),
            (s + "Foot", j[s + "Foot"], j[s + "Toes"], s + "LowerLeg", True, Vector((0, 0, 1))),
            (s + "Toes", j[s + "Toes"], j[s + "ToeTip"], s + "Foot", True, Vector((0, 0, 1))),
        ]
        chains = finger_chains(side)
        for fname in ("Thumb", "Index", "Middle", "Ring", "Little"):
            segs = THUMB_SEGS if fname == "Thumb" else FINGER_SEGS
            parent = s + "Hand"
            for seg in segs:
                bn = s + fname + seg
                h, t = chains[bn]
                out.append((bn, h, t, parent, True, None))
                parent = bn
    return out


def build_armature(coll, name="InfantryRig"):
    arm_data = bpy.data.armatures.new(name)
    arm = bpy.data.objects.new(name, arm_data)
    coll.objects.link(arm)
    arm.show_in_front = True
    bpy.context.view_layer.objects.active = arm
    for o in bpy.context.selected_objects:
        o.select_set(False)
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    for side in (-1, 1):
        hax, hpalm, hthumb = hand_frame(side)
    for bname, head, tail, parent, deform, rollv in bone_list():
        b = eb.new(bname)
        b.head, b.tail = head, tail
        b.use_deform = deform
        if parent:
            b.parent = eb[parent]
            b.use_connect = False
        if rollv is not None:
            b.align_roll(rollv)
        elif "Hand" in bname or any(f in bname for f in ("Thumb", "Index", "Middle", "Ring", "Little")):
            side = -1 if bname.startswith("Left") else 1
            _, palm, _ = hand_frame(side)
            b.align_roll(-palm)       # bone Z points out of the back of the hand
    # Attachment bones
    for aname, (parent, pos, fwd, upv) in attachments().items():
        if aname in ("ATT_Weapon", "ATT_Magazine"):
            f, u, o = weapon_frame_from_hand(1)
            m = frame_matrix(f, u, o)
        elif aname == "ATT_Hand_L":
            ax, palm, thumb = hand_frame(-1)
            o = joints()["LeftHand"] + ax * GRIP_IN_HAND[0] + palm * GRIP_IN_HAND[1]
            m = frame_matrix(ax, thumb, o)
        else:
            m = Matrix.Translation(pos)
        b = eb.new(aname)
        b.head = m.translation
        b.tail = m.translation + m.to_3x3().col[1] * 0.08
        b.align_roll(m.to_3x3().col[2])
        b.parent = eb[parent]
        b.use_deform = True
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def add_controls(arm):
    """Authoring rig: IK targets and poles (CTRL_*, non-deforming) + constraints."""
    j = joints()
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    root = eb["Root"]

    def ctrl(name, head, tail, parent, roll_m=None):
        b = eb.new(name)
        b.head, b.tail = head, tail
        b.parent = parent
        b.use_deform = False
        if roll_m is not None:
            b.align_roll(roll_m)
        return b

    # Weapon control: same rest frame as ATT_Weapon, parented to UpperChest so the rifle
    # follows the torso; the right hand is solved onto it, the left hand onto the handguard.
    att = eb["ATT_Weapon"]
    w = ctrl("CTRL_Weapon", att.head.copy(), att.tail.copy(), eb["UpperChest"])
    w.roll = att.roll
    for side, s in ((-1, "Left"), (1, "Right")):
        hb = eb[s + "Hand"]
        h = ctrl("CTRL_Hand" + s[0], hb.head.copy(), hb.tail.copy(), w if side > 0 else eb["UpperChest"])
        h.roll = hb.roll
        fb = eb[s + "Foot"]
        f = ctrl("CTRL_Foot" + s[0], fb.head.copy(), fb.tail.copy(), root)
        f.roll = fb.roll
        ctrl("CTRL_Knee" + s[0], j[s + "LowerLeg"] + Vector((0, 0.45, 0)), j[s + "LowerLeg"] + Vector((0, 0.5, 0)), root)
        ctrl("CTRL_Elbow" + s[0], j[s + "LowerArm"] + Vector((side * 0.25, -0.35, -0.1)),
             j[s + "LowerArm"] + Vector((side * 0.25, -0.40, -0.1)), eb["UpperChest"])
    bpy.ops.object.mode_set(mode="POSE")
    pb = arm.pose.bones
    for side, s in ((-1, "Left"), (1, "Right")):
        c = s[0]
        ik = pb[s + "LowerLeg"].constraints.new("IK")
        ik.target, ik.subtarget = arm, "CTRL_Foot" + c
        ik.pole_target, ik.pole_subtarget = arm, "CTRL_Knee" + c
        ik.pole_angle = math.radians(-90)
        ik.chain_count = 2
        cr = pb[s + "Foot"].constraints.new("COPY_ROTATION")
        cr.target, cr.subtarget = arm, "CTRL_Foot" + c
        ik = pb[s + "LowerArm"].constraints.new("IK")
        ik.target, ik.subtarget = arm, "CTRL_Hand" + c
        ik.pole_target, ik.pole_subtarget = arm, "CTRL_Elbow" + c
        ik.pole_angle = math.radians(-90)
        ik.chain_count = 2
        cr = pb[s + "Hand"].constraints.new("COPY_ROTATION")
        cr.target, cr.subtarget = arm, "CTRL_Hand" + c
    for b in pb:
        b.rotation_mode = "QUATERNION"
    bpy.ops.object.mode_set(mode="OBJECT")


def deform_bone_names(arm):
    return [b.name for b in arm.data.bones if b.use_deform and not b.name.startswith("ATT_")]
