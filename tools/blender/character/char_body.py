"""Shared infantry body (VISUAL-03): the MakeHuman body of char_body_mh in the reference rest pose, cut into the
regions the loadouts hide (Char_Torso/Arms/Legs/Feet/Hands) plus Char_Head (head and neck, textured skin, eyes).

Reference space. Every garment and gear builder (char_uniform, char_gear, fac_gear) is authored around the
CHARACTER-01 layout (char_skeleton.ref_joints). The body is reposed so its limbs point the way that layout's limbs
do (A-pose, feet under the hips, palms to the thighs); heights differ by a few centimetres, so builders work in
*reference space*: the body's heights mapped piecewise-linearly onto the reference landmarks (ground, ankle, knee,
hip joint, shoulder joint, crown) by warp_z, while x and y stay as they are. The body field functions below
(torso_sdf, leg_sdf, ...) take reference-space points and measure the real body; a finished piece goes back to body
space with to_body_space(). So the garments keep their authored details and still fit this body.
"""
import math

import bmesh
import bpy
import numpy as np
import openvdb as vdb
from mathutils import Matrix, Vector

import char_body_mh as MH
import char_lib as L
import char_skeleton as S

REGION_OF_BONE = {"Hips": "Torso", "Spine": "Torso", "Chest": "Torso", "UpperChest": "Torso", "Root": "Torso",
                  "Neck": "Head", "Head": "Head"}
for _s in ("Left", "Right"):
    REGION_OF_BONE.update({
        _s + "Shoulder": "Torso", _s + "UpperArm": "Arms", _s + "LowerArm": "Arms", _s + "Hand": "Hands",
        _s + "UpperLeg": "Legs", _s + "LowerLeg": "Legs", _s + "Foot": "Feet", _s + "Toes": "Feet",
    })
    for _f in ("Thumb", "Index", "Middle", "Ring", "Little"):
        for _g in ("Metacarpal", "Proximal", "Intermediate", "Distal"):
            REGION_OF_BONE[_s + _f + _g] = "Hands"
REGIONS = ("Torso", "Arms", "Legs", "Feet", "Hands")

# Old head (CHARACTER-01) the helmets and eyewear were fitted to: cranium ellipsoid centre and radii (reference
# space). The new head is measured the same way and head-mounted rigid pieces are fitted by head_fit().
REF_HEAD_C = Vector((0.0, -0.024, 1.716))
REF_HEAD_R = Vector((0.073, 0.095, 0.089))
HEAD_C = Vector((0.0, -0.008, 1.690))          # CHARACTER-01 head centre (helmet authoring)

NECK_R = 0.058                                  # body's neck radius at the collar (measured by build)
_WARP_NEW = np.array([0.0, 1.0])
_WARP_REF = np.array([0.0, 1.0])
_FIELDS = {}
_SEGS = {}
_STATE = {}


def _v(p):
    return tuple(float(c) for c in p)


# ---------------------------------------------------------------------------- reference space


def warp_z(z):
    """Body height -> reference height."""
    return np.interp(z, _WARP_NEW, _WARP_REF)


def unwarp_z(z):
    """Reference height -> body height."""
    return np.interp(z, _WARP_REF, _WARP_NEW)


def to_ref(p):
    return Vector((p[0], p[1], float(warp_z(p[2]))))


def to_body(p):
    return Vector((p[0], p[1], float(unwarp_z(p[2]))))


def leg_fade(fade):
    """char_lib.limit_leg_weights band (z_lo, z_hi, centre_drop) from reference to body heights."""
    z_lo, z_hi, drop = fade
    return float(unwarp_z(z_lo)), float(unwarp_z(z_hi)), drop


def to_body_space(obj):
    """Moves a piece authored in reference space onto the body (vertex heights unwarped)."""
    me = obj.data
    co = np.empty(len(me.vertices) * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    mw = np.array(obj.matrix_world)
    if not np.allclose(mw, np.eye(4)):
        raise ValueError("to_body_space expects a piece with an identity transform: " + obj.name)
    co[:, 2] = unwarp_z(co[:, 2])
    me.vertices.foreach_set("co", co.ravel())
    me.update()
    return obj


# ---------------------------------------------------------------------------- body field


def _make_field(obj, name, lo, hi, voxel, half_width_m, keep=None):
    """Signed distance of the (closed) mesh in body space, as a dense array (negative inside)."""
    me = obj.data
    pts = np.array([v.co[:] for v in me.vertices], dtype=np.float32)
    tris = []
    for p in me.polygons:
        if keep is not None and not keep(p):
            continue
        vs = list(p.vertices)
        for k in range(1, len(vs) - 1):
            tris.append((vs[0], vs[k], vs[k + 1]))
    tris = np.array(tris, dtype=np.int32)
    xf = vdb.createLinearTransform(voxelSize=voxel)
    hw = max(3, int(math.ceil(half_width_m / voxel)))
    g = vdb.FloatGrid.createLevelSetFromPolygons(pts, triangles=tris, transform=xf, halfWidth=hw)
    i0 = np.floor(np.array(lo) / voxel).astype(int)
    i1 = np.ceil(np.array(hi) / voxel).astype(int)
    arr = np.full(tuple(i1 - i0 + 1), hw * voxel, dtype=np.float32)
    g.copyToArray(arr, ijk=tuple(int(c) for c in i0))
    _FIELDS[name] = (arr, i0 * voxel, voxel, hw * voxel)


def _sample(name, X, Y, Z):
    arr, lo, vox, far = _FIELDS[name]
    fx = (X - lo[0]) / vox
    fy = (Y - lo[1]) / vox
    fz = (Z - lo[2]) / vox
    n = arr.shape
    inside = (fx >= 0) & (fy >= 0) & (fz >= 0) & (fx < n[0] - 1) & (fy < n[1] - 1) & (fz < n[2] - 1)
    ix = np.clip(np.floor(fx).astype(np.int64), 0, n[0] - 2)
    iy = np.clip(np.floor(fy).astype(np.int64), 0, n[1] - 2)
    iz = np.clip(np.floor(fz).astype(np.int64), 0, n[2] - 2)
    tx = np.clip(fx - ix, 0, 1).astype(np.float32)
    ty = np.clip(fy - iy, 0, 1).astype(np.float32)
    tz = np.clip(fz - iz, 0, 1).astype(np.float32)
    out = np.zeros(np.shape(X), dtype=np.float32)
    for dx in (0, 1):
        wx = tx if dx else 1 - tx
        for dy in (0, 1):
            wy = ty if dy else 1 - ty
            for dz in (0, 1):
                wz = tz if dz else 1 - tz
                out += wx * wy * wz * arr[ix + dx, iy + dy, iz + dz]
    return np.where(inside, out, far)


def _seg_dist(X, Y, Z, a, b):
    ax, ay, az = a
    bx, by, bz = b
    dx, dy, dz = bx - ax, by - ay, bz - az
    ll = dx * dx + dy * dy + dz * dz
    t = np.clip(((X - ax) * dx + (Y - ay) * dy + (Z - az) * dz) / max(ll, 1e-9), 0.0, 1.0)
    qx, qy, qz = X - (ax + t * dx), Y - (ay + t * dy), Z - (az + t * dz)
    return np.sqrt(qx * qx + qy * qy + qz * qz)


def _build_segments():
    """Bone segments per region label (reference space) for splitting space between torso, limbs, head."""
    j = S.joints()
    segs = {"Torso": [(j["Hips"], j["Spine"]), (j["Spine"], j["Chest"]), (j["Chest"], j["UpperChest"]),
                      (j["UpperChest"], j["Neck"])],
            "Neck": [(j["Neck"], j["Head"])],
            "Head": [(j["Head"], j["HeadTop"])]}
    for side, s in ((-1, "Left"), (1, "Right")):
        c = s[0]
        segs["Torso"].append((j["UpperChest"], j[s + "UpperArm"] * 0.6 + j["UpperChest"] * 0.4))
        segs["Torso"].append((j["Hips"], j[s + "UpperLeg"]))
        segs["Arm" + c] = [(j[s + "UpperArm"], j[s + "LowerArm"]), (j[s + "LowerArm"], j[s + "Hand"])]
        segs["Hand" + c] = [(j[s + "Hand"], j[s + "Knuckle"]), (j[s + "Knuckle"], j[s + "Knuckle"] + (j[s + "Knuckle"] - j[s + "Hand"]) * 0.9)]
        segs["Leg" + c] = [(j[s + "UpperLeg"], j[s + "LowerLeg"]), (j[s + "LowerLeg"], j[s + "Foot"])]
        segs["Foot" + c] = [(j[s + "Foot"], j[s + "Toes"]), (j[s + "Toes"], j[s + "ToeTip"]),
                            (j[s + "Foot"], j[s + "Foot"] + Vector((0, -0.05, -0.06)))]
    _SEGS.clear()
    _SEGS.update({k: [(_v(a), _v(b)) for a, b in v] for k, v in segs.items()})


def _region_wall(P, labels):
    """Negative inside the cells of `labels` (nearest-bone split of space), positive in the other cells."""
    X, Y, Z = P
    din = None
    dout = None
    for k, segs in _SEGS.items():
        d = None
        for a, b in segs:
            s = _seg_dist(X, Y, Z, a, b)
            d = s if d is None else np.minimum(d, s)
        if k in labels:
            din = d if din is None else np.minimum(din, d)
        else:
            dout = d if dout is None else np.minimum(dout, d)
    return 0.5 * (din - dout)


def body_dist(P, field="body"):
    X, Y, Z = P
    return _sample(field, X, Y, unwarp_z(Z))


def _region(P, grow, labels, field="body"):
    return np.maximum(body_dist(P, field) - grow, _region_wall(P, labels))


def torso_sdf(P, grow=0.0, neck=True):
    return _region(P, grow, ("Torso", "Neck") if neck else ("Torso",))


def arm_sdf(P, side, grow=0.0, to_wrist=True):
    return _region(P, grow, ("ArmL",) if side < 0 else ("ArmR",))


def leg_sdf(P, side, grow=0.0):
    return _region(P, grow, ("LegL",) if side < 0 else ("LegR",))


def foot_sdf(P, side, grow=0.0):
    return _region(P, grow, ("FootL",) if side < 0 else ("FootR",))


def hand_sdf(P, side, grow=0.0):
    return _region(P, grow, ("HandL",) if side < 0 else ("HandR",), field="hand_L" if side < 0 else "hand_R")


def body_sdf(P, grow=0.0, parts=("torso", "arms", "legs", "feet")):
    labels = []
    if "torso" in parts:
        labels += ["Torso", "Neck"]
    if "arms" in parts:
        labels += ["ArmL", "ArmR"]
    if "legs" in parts:
        labels += ["LegL", "LegR"]
    if "feet" in parts:
        labels += ["FootL", "FootR"]
    return _region(P, grow, tuple(labels))


# ---------------------------------------------------------------------------- build


def _world_aim(arm, bone, direction, up_ref=None, up_axis=2):
    """Poses `bone` (armature space about its head) so its Y axis points along `direction`; with up_ref, its
    `up_axis` column is turned towards up_ref as well."""
    pb = arm.pose.bones[bone]
    m = pb.matrix.copy()
    r = m.to_3x3()
    q = r.col[1].normalized().rotation_difference(direction.normalized())
    r = q.to_matrix() @ r
    if up_ref is not None:
        y = r.col[1].normalized()
        cur = r.col[up_axis].normalized()
        want = (up_ref - y * up_ref.dot(y)).normalized()
        ang = math.atan2(cur.cross(want).dot(y), cur.dot(want))
        r = Matrix.Rotation(ang, 3, y) @ r
    out = r.to_4x4()
    out.translation = m.translation
    pb.matrix = out
    bpy.context.view_layer.update()


def repose_to_reference(arm, body, extra=()):
    """Turns the MakeHuman rest pose into the reference A-pose: thigh, shin, upper arm and forearm directions and
    the hand frame of char_skeleton.ref_joints, feet kept flat; then applies it as the rest pose."""
    R = S.ref_joints()
    bpy.context.view_layer.objects.active = arm
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    bpy.context.view_layer.update()
    for side, s in ((-1, "Left"), (1, "Right")):
        foot_r = arm.pose.bones[s + "Foot"].matrix.to_3x3().copy()
        _world_aim(arm, s + "UpperLeg", R[s + "LowerLeg"] - R[s + "UpperLeg"])
        _world_aim(arm, s + "LowerLeg", R[s + "Foot"] - R[s + "LowerLeg"])
        pf = arm.pose.bones[s + "Foot"]
        m = foot_r.to_4x4()
        m.translation = pf.matrix.translation
        pf.matrix = m
        bpy.context.view_layer.update()
        _world_aim(arm, s + "UpperArm", R[s + "LowerArm"] - R[s + "UpperArm"])
        _world_aim(arm, s + "LowerArm", R[s + "Hand"] - R[s + "LowerArm"])
        # Hand: axis wrist -> knuckles as in the reference; thumb side forward-up like the reference hand frame.
        ax, palm, thumb = _ref_hand_frame(side)
        _world_aim(arm, s + "Hand", ax)
        # rotate about the hand axis so the index->little line points along the reference thumb direction
        hb = arm.pose.bones[s + "Hand"]
        y = hb.matrix.to_3x3().col[1].normalized()
        idx = arm.pose.bones[s + "IndexProximal"].head - arm.pose.bones[s + "LittleProximal"].head
        cur = (idx - y * idx.dot(y)).normalized()
        want = (thumb - y * thumb.dot(y)).normalized()
        ang = math.atan2(cur.cross(want).dot(y), cur.dot(want))
        m = hb.matrix.copy()
        r = Matrix.Rotation(ang, 3, y) @ m.to_3x3()
        o = r.to_4x4()
        o.translation = m.translation
        hb.matrix = o
        bpy.context.view_layer.update()
    # Bake the pose into the meshes and make it the rest pose.
    for obj in (body,) + tuple(extra):
        if obj is None:
            continue
        L.activate(obj)
        mod = next((m for m in obj.modifiers if m.type == "ARMATURE"), None)
        if mod is None:
            mod = obj.modifiers.new("Armature", "ARMATURE")
            mod.object = arm
        bpy.ops.object.modifier_apply(modifier=mod.name)
    L.activate(arm)
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    for obj in (body,) + tuple(extra):
        if obj is not None and obj.vertex_groups:
            L._add_armature_mod(obj, arm)


def _ref_hand_frame(side):
    """Hand frame (axis, palm, thumb) of the CHARACTER-01 reference layout."""
    saved = S._JOINTS
    S._JOINTS = None
    try:
        return S.hand_frame(side)
    finally:
        S._JOINTS = saved


def _body_joints(arm):
    """Joint dictionary in body space with the names char_skeleton.joints() provides."""
    b = arm.data.bones
    j = {n: b[n].head_local.copy() for n in ("Hips", "Spine", "Chest", "UpperChest", "Neck", "Head")}
    j["Root"] = Vector((0, 0, 0))
    j["HeadTop"] = b["Head"].tail_local.copy()
    for s in ("Left", "Right"):
        for n in ("Shoulder", "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot", "Toes"):
            j[s + n] = b[s + n].head_local.copy()
        j[s + "ShoulderStart"] = b[s + "Shoulder"].head_local.copy()
        j[s + "Knuckle"] = b[s + "MiddleProximal"].head_local.copy()
        j[s + "ToeTip"] = b[s + "Toes"].tail_local.copy()
    return j


def _set_warp(jb):
    R = S.ref_joints()
    crown = _STATE["crown"]
    new = [0.0, jb["LeftFoot"].z, jb["LeftLowerLeg"].z, jb["LeftUpperLeg"].z, jb["LeftUpperArm"].z, crown]
    ref = [0.0, R["LeftFoot"].z, R["LeftLowerLeg"].z, R["LeftUpperLeg"].z, R["LeftUpperArm"].z, R["HeadTop"].z]
    global _WARP_NEW, _WARP_REF
    _WARP_NEW = np.array(new)
    _WARP_REF = np.array(ref)


def build(coll, mats):
    """Builds the body. Returns dict: arm, pieces {body_torso.., body_head}, weight_ref, info (measurements)."""
    arm, body, eye_helpers = MH.build_human()
    for c in list(arm.users_collection):
        c.objects.unlink(arm)
    L.collection("Rig").objects.link(arm)
    for o in (body, eye_helpers):
        if o is None:
            continue
        for c in list(o.users_collection):
            c.objects.unlink(o)
        coll.objects.link(o)
    repose_to_reference(arm, body)
    if eye_helpers is not None:
        # the helper eyes follow the head bone, which the repose does not move
        eye_helpers.parent = None
    zs = [v.co.z for v in body.data.vertices]
    _STATE["crown"] = max(zs)
    jb = _body_joints(arm)
    _set_warp(jb)
    S.set_joints({k: to_ref(v) for k, v in jb.items()})
    _build_segments()
    global NECK_R
    co = np.array([v.co[:] for v in body.data.vertices])
    band = co[(np.abs(warp_z(co[:, 2]) - 1.545) < 0.006) & (np.abs(co[:, 0]) < 0.09)]
    if len(band):
        NECK_R = float((band[:, 0].max() - band[:, 0].min()) / 2)
    # Fields (body space): whole body at 4 mm, hands at 1.5 mm.
    _make_field(body, "body", (-0.75, -0.30, -0.02), (0.75, 0.40, 1.86), 0.004, 0.14)
    for side, s in ((-1, "L"), (1, "R")):
        c = jb[("Left" if side < 0 else "Right") + "Knuckle"]
        _make_field(body, "hand_" + s, _v(c - Vector((0.16, 0.16, 0.16))), _v(c + Vector((0.16, 0.16, 0.16))), 0.0015, 0.03)
    _add_attachments(arm)
    for p in body.data.polygons:
        p.use_smooth = True
    body.data.materials.clear()
    body.data.materials.append(mats["SkinBody"])
    # Weight reference for garments: the whole body with its MakeHuman weights (never exported).
    ref = body.copy()
    ref.data = body.data.copy()
    ref.name = ref.data.name = "WeightRef"
    L.collection("Reference").objects.link(ref)
    ref.hide_render = True
    eyes = _build_eyes(coll, eye_helpers, mats, arm)
    parts = split_regions(body, coll, mats)
    head = parts.pop("Head")
    head_uv_and_skin(head, mats, eyes)
    measure_head(head)
    _STATE["head_obj"] = head
    _STATE["skin_rgb"] = skin_colours(head)
    for o in list(parts.values()) + [head, ref]:
        strip_non_bone_groups(o, arm)
    head = L.join([head, eyes], "Char_Head")
    pieces = {"body_" + k.lower(): v for k, v in parts.items()}
    pieces["body_head"] = head
    _STATE["head_obj"] = head
    info = {"warp_body": [round(x, 4) for x in _WARP_NEW], "warp_ref": [round(x, 4) for x in _WARP_REF],
            "head_fit": head_fit_info(), "neck_r": round(NECK_R, 4)}
    return {"arm": arm, "pieces": pieces, "weight_ref": ref, "info": info}


def _add_attachments(arm):
    """ATT_* bones (CHARACTER_STANDARD §3): reference positions moved onto the body; weapon / hand points from the
    body's hands."""
    L.activate(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    for aname, (parent, pos, _, _) in S.attachments().items():
        if aname == "ATT_Weapon":
            f, u, o = S.weapon_frame_from_hand(1)
            m = S.frame_matrix(f, u, to_body(o))
        elif aname == "ATT_Hand_L":
            ax, palm, thumb = S.hand_frame(-1)
            o = S.joints()["LeftHand"] + ax * S.GRIP_IN_HAND[0] + palm * S.GRIP_IN_HAND[1]
            m = S.frame_matrix(ax, thumb, to_body(o))
        else:
            m = Matrix.Translation(to_body(pos))
        b = eb.new(aname)
        b.head = m.translation
        b.tail = m.translation + m.to_3x3().col[1] * 0.08
        b.align_roll(m.to_3x3().col[2])
        b.parent = eb[parent]
        b.use_deform = True
    bpy.ops.object.mode_set(mode="OBJECT")


# ---------------------------------------------------------------------------- head, eyes, regions


EYE_R = 0.0120


def _build_eyes(coll, helpers, mats, arm):
    """Eyeballs with a slightly proud iris dome at the MakeHuman eye helper positions, skinned to Head."""
    centres = []
    if helpers is not None:
        me = helpers.data
        co = np.array([v.co[:] for v in me.vertices])
        for sgn in (-1, 1):
            sel = co[co[:, 0] * sgn > 0]
            centres.append((Vector(sel.mean(axis=0)), float(np.max(np.linalg.norm(sel - sel.mean(axis=0), axis=1)))))
        bpy.data.objects.remove(helpers, do_unlink=True)
    else:
        j = S.joints()
        for sgn in (-1, 1):
            centres.append((to_body(j["Head"] + Vector((sgn * 0.032, 0.085, 0.04))), EYE_R))
    bm = bmesh.new()
    for c, r in centres:
        r = min(max(r * 0.97, 0.010), 0.0135)
        L.bm_sphere(bm, r, c, segs=14, rings=10)
        L.bm_sphere(bm, r * 0.46, c + Vector((0, r - r * 0.36, 0)), segs=12, rings=8, mat=1)
    eyes = L.new_object("Char_Eyes", bm, coll, [mats["Eye"], mats["Iris"]])
    L.box_uv(eyes, 1.0)
    for p in eyes.data.polygons:
        p.use_smooth = True
    eyes.vertex_groups.new(name="Head").add(list(range(len(eyes.data.vertices))), 1.0, "REPLACE")
    L._add_armature_mod(eyes, arm)
    _STATE["eyes"] = [(_v(c), r) for c, r in centres]
    return eyes


def split_regions(body, coll, mats):
    """Splits the weighted body into region objects by dominant bone. Returns {region: obj} incl. Head."""
    me = body.data
    group_names = {g.index: g.name for g in body.vertex_groups}
    bone_groups = {i for i, n in group_names.items() if n in REGION_OF_BONE}
    dom = []
    for v in me.vertices:
        best = max((g for g in v.groups if g.group in bone_groups), key=lambda g: g.weight, default=None)
        dom.append(REGION_OF_BONE[group_names[best.group]] if best else "Torso")
    out = {}
    for region in REGIONS + ("Head",):
        o = body.copy()
        o.data = body.data.copy()
        o.name = o.data.name = "Char_" + region
        coll.objects.link(o)
        bm = L.bm_from(o)
        kill = []
        for f in bm.faces:
            regs = [dom[v.index] for v in f.verts]
            if max(set(regs), key=regs.count) != region:
                kill.append(f)
        bmesh.ops.delete(bm, geom=kill, context="FACES")
        bm.to_mesh(o.data)
        bm.free()
        L.remove_empty_groups(o)
        out[region] = o
    bpy.data.objects.remove(body, do_unlink=True)
    return out


def strip_non_bone_groups(obj, arm):
    """Drops MakeHuman's helper / measurement vertex groups (body, scalp, joint-*, ...): only bone weights stay."""
    bones = {b.name for b in arm.data.bones}
    for g in list(obj.vertex_groups):
        if g.name not in bones:
            obj.vertex_groups.remove(g)


def head_uv_and_skin(head, mats, eyes):
    """Cylindrical UV around the head axis (u = angle, 0.5 = face; v = height) and the skin albedo painted from the
    MakeHuman vertex groups (scalp hair, lips) and the eye positions (brows, beard shadow) into that UV."""
    import char_textures  # noqa: F401  (texture dir conventions)
    head.data.materials.clear()
    head.data.materials.append(mats["SkinHead"])
    me = head.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    co = np.array([v.co[:] for v in me.vertices])
    hc = Vector(_STATE["eyes"][0][0]).lerp(Vector(_STATE["eyes"][1][0]), 0.5) - Vector((0, 0.075, 0.0))
    _STATE["head_axis"] = _v(hc)
    z0, z1 = float(co[:, 2].min()) - 0.002, float(co[:, 2].max()) + 0.002
    _STATE["head_v"] = (z0, z1)
    ang = np.arctan2(co[:, 0] - hc.x, co[:, 1] - hc.y)
    u = 0.5 + ang / (2 * math.pi)
    v = (co[:, 2] - z0) / (z1 - z0)
    uv = me.uv_layers.active.data
    for p in me.polygons:
        us = [u[me.loops[li].vertex_index] for li in p.loop_indices]
        wrap = max(us) - min(us) > 0.5
        for li in p.loop_indices:
            vi = me.loops[li].vertex_index
            uu = u[vi]
            if wrap and uu < 0.5:
                uu += 1.0
            uv[li].uv = (uu, v[vi])
    _STATE["head_uv"] = (u, v)


def skin_colours(head):
    """Per-vertex sRGB colour of the head piece."""
    me = head.data
    n = len(me.vertices)
    co = np.array([v.co[:] for v in me.vertices])
    gidx = {g.name: g.index for g in head.vertex_groups}

    def group(name):
        w = np.zeros(n)
        gi = gidx.get(name)
        if gi is None:
            return w
        for v in me.vertices:
            for g in v.groups:
                if g.group == gi:
                    w[v.index] = g.weight
        return w

    base = np.array([0.74, 0.56, 0.45])
    col = np.tile(base, (n, 1))
    (el, _), (er, _) = _STATE["eyes"]
    ey = (el[2] + er[2]) / 2
    front = co[:, 1] > el[1] - 0.06
    sm = lambda t: np.clip(t, 0, 1) ** 2 * (3 - 2 * np.clip(t, 0, 1))  # noqa: E731
    # Short military cut: the MakeHuman scalp group where it exists, else a hairline from the eye positions
    # (forehead ~6 cm above the eyes, over the ears, down to the nape behind them).
    ex_c = (el[0] + er[0]) / 2
    ey_c = (el[1] + er[1]) / 2
    back = sm((ey_c - 0.07 - co[:, 1]) / 0.03)
    hairline = ey + 0.062 - 0.075 * back - 0.03 * sm((np.abs(co[:, 0] - ex_c) - 0.06) / 0.02) * (1 - back)
    geo = sm((co[:, 2] - hairline) / 0.008)
    ears = np.exp(-((np.abs(co[:, 0]) - 0.075) / 0.012) ** 2) * np.exp(-((co[:, 2] - ey) / 0.03) ** 2) * (1 - back)
    hair = np.maximum(sm(group("scalp") * 1.6), geo * (1 - ears))
    col = col * (1 - hair[:, None] * 0.88) + np.array([0.24, 0.18, 0.13]) * hair[:, None] * 0.88
    # Brows: a band above each eye.
    for ex, _, ez in (el, er):
        dx = np.abs(co[:, 0] - ex)
        b = np.exp(-((co[:, 2] - (ez + 0.019)) / 0.0045) ** 2) * sm((0.026 - dx) / 0.008) * front
        col = col * (1 - b[:, None] * 0.7) + np.array([0.22, 0.16, 0.11]) * b[:, None] * 0.7
    yfront = co[:, 1].max()
    mouth = np.exp(-((co[:, 2] - (ey - 0.077)) / 0.006) ** 2) * sm((0.024 - np.abs(co[:, 0])) / 0.006) * sm((co[:, 1] - (yfront - 0.03)) / 0.006)
    lips = np.maximum(sm(group("lips") * 1.5), mouth)
    col = col * (1 - lips[:, None] * 0.45) + np.array([0.63, 0.38, 0.35]) * lips[:, None] * 0.45
    # Beard shadow on the jaw and upper lip.
    jaw = sm((ey - 0.045 - co[:, 2]) / 0.02) * sm((co[:, 2] - (ey - 0.135)) / 0.02) * front * (1 - lips)
    col = col * (1 - jaw[:, None] * 0.22) + np.array([0.36, 0.28, 0.22]) * jaw[:, None] * 0.22
    return np.clip(col, 0, 1)


def make_skin_texture(path, head, n=512):
    """Rasterises the head's skin colours (computed by build() before the helper groups were dropped) into the head
    UV (written as sRGB PNG); returns path."""
    col = _STATE["skin_rgb"]
    me = head.data
    uvl = me.uv_layers.active.data
    img = np.zeros((n, n, 3))
    wgt = np.zeros((n, n))
    for p in me.polygons:
        if max(p.vertices) >= len(col):       # the joined eyes
            continue
        lis = list(p.loop_indices)
        for k in range(1, len(lis) - 1):
            tri = (lis[0], lis[k], lis[k + 1])
            uvs = np.array([uvl[li].uv[:] for li in tri]) % 1.0001
            if np.ptp(uvs[:, 0]) > 0.5:
                uvs[:, 0] = np.where(uvs[:, 0] < 0.5, uvs[:, 0] + 1.0, uvs[:, 0])
            cs = np.array([col[me.loops[li].vertex_index] for li in tri])
            px = uvs * (n - 1)
            x0, y0 = np.floor(px.min(axis=0)).astype(int)
            x1, y1 = np.ceil(px.max(axis=0)).astype(int)
            xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
            a, b, c = px
            den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
            if abs(den) < 1e-9:
                continue
            l1 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / den
            l2 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / den
            l3 = 1 - l1 - l2
            m = (l1 >= -0.02) & (l2 >= -0.02) & (l3 >= -0.02)
            if not m.any():
                continue
            cc = l1[..., None] * cs[0] + l2[..., None] * cs[1] + l3[..., None] * cs[2]
            xi, yi = xs[m] % n, np.clip(ys[m], 0, n - 1)
            img[yi, xi] += cc[m]
            wgt[yi, xi] += 1
    filled = wgt > 0
    img[filled] /= wgt[filled][:, None]
    # Fill the gaps by dilation, then a little pore-scale variation.
    for _ in range(12):
        if filled.all():
            break
        acc = np.zeros_like(img)
        cnt = np.zeros_like(wgt)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh = np.roll(np.roll(img, dx, 1), dy, 0)
            sf = np.roll(np.roll(filled, dx, 1), dy, 0)
            acc += sh * sf[..., None]
            cnt += sf
        grow = (~filled) & (cnt > 0)
        img[grow] = acc[grow] / cnt[grow][:, None]
        filled = filled | grow
    img[~filled] = np.array([0.74, 0.56, 0.45])
    img = img * (0.95 + 0.07 * L.fbm(n, 40, 4, 3)[..., None])
    return L.save_png(path, np.clip(img[::-1], 0, 1))


def head_fit_info():
    """Cranium of the built head (reference space) vs the CHARACTER-01 head: centre and per-axis scale used to fit
    helmets and eyewear (head_fit_matrix)."""
    return _STATE.get("head_fit")


def measure_head(head):
    """Cranium extent above the eyes (reference space): centre and half sizes; stores head_fit."""
    co = np.array([v.co[:] for v in head.data.vertices])
    ey = (_STATE["eyes"][0][0][2] + _STATE["eyes"][1][0][2]) / 2
    cr = co[co[:, 2] > ey + 0.005]
    zr = warp_z(cr[:, 2])
    half = np.array([np.abs(cr[:, 0]).max() * 0.92, (cr[:, 1].max() - cr[:, 1].min()) / 2, zr.max() - warp_z(ey)])
    centre = np.array([0.0, (cr[:, 1].max() + cr[:, 1].min()) / 2, zr.max() - half[2]])
    ref_half = np.array([REF_HEAD_R.x, REF_HEAD_R.y, REF_HEAD_C.z + REF_HEAD_R.z - (HEAD_C.z + 0.002)])
    scale = half / ref_half
    _STATE["head_fit"] = {"centre": [round(c, 4) for c in centre], "half": [round(c, 4) for c in half],
                          "scale": [round(c, 4) for c in scale]}
    return _STATE["head_fit"]


def head_fit_matrix():
    """Reference-space transform that maps a piece fitted to the CHARACTER-01 head onto this head: scale about the
    old cranium top, then move the crowns together."""
    hf = _STATE.get("head_fit")
    if not hf:
        return Matrix.Identity(4)
    s = hf["scale"]
    top_old = Vector((0, REF_HEAD_C.y, REF_HEAD_C.z + REF_HEAD_R.z))
    top_new = Vector((0, hf["centre"][1], hf["centre"][2] + hf["half"][2]))
    sc = Matrix.Diagonal((s[0], s[1], s[2], 1.0))
    return Matrix.Translation(top_new) @ sc @ Matrix.Translation(-top_old)
