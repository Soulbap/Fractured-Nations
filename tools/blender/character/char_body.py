"""Base body for the shared infantry character (CHARACTER-01).

Modelled as signed-distance fields (char_sdf) built on the skeleton joints so proportions
always match the rig: torso, limbs and feet in one smooth field (Char_Torso/Arms/Legs/Feet
after a split by dominant bone), hands at higher resolution (Char_Hands) and a parametric
head (Char_Head: skull, face, ears, neck, eyes). Garments reuse body_sdf() with an offset,
so clothing always follows the same body. A uniform hides the body regions it covers.
"""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Vector

import char_lib as L
import char_sdf as D
import char_skeleton as S

REGION_OF_BONE = {
    "Hips": "Torso", "Spine": "Torso", "Chest": "Torso", "UpperChest": "Torso", "Neck": "Torso",
    "Head": "Torso", "Root": "Torso",
}
for _s in ("Left", "Right"):
    REGION_OF_BONE.update({
        _s + "Shoulder": "Torso", _s + "UpperArm": "Arms", _s + "LowerArm": "Arms", _s + "Hand": "Hands",
        _s + "UpperLeg": "Legs", _s + "LowerLeg": "Legs", _s + "Foot": "Feet", _s + "Toes": "Feet",
    })
    for _f in ("Thumb", "Index", "Middle", "Ring", "Little"):
        for _g in ("Metacarpal", "Proximal", "Intermediate", "Distal"):
            REGION_OF_BONE[_s + _f + _g] = "Hands"
REGIONS = ("Torso", "Arms", "Legs", "Feet")
BODY_BOUNDS = ((-0.70, -0.20, -0.01), (0.70, 0.26, 1.64))


def _v(p):
    return tuple(float(c) for c in p)


# ---------------------------------------------------------------------------- body field


def torso_sdf(P, grow=0.0, neck=True):
    g = grow
    d = D.union(
        D.ellipsoid(P, (0, 0.000, 0.955), (0.150 + g, 0.104 + g, 0.100 + g)),
        D.ellipsoid(P, (0, 0.006, 1.080), (0.138 + g, 0.098 + g, 0.110 + g)),
        D.ellipsoid(P, (0, -0.006, 1.245), (0.152 + g, 0.110 + g, 0.150 + g)),
        D.ellipsoid(P, (0, -0.010, 1.360), (0.160 + g, 0.098 + g, 0.090 + g)),
        k=0.05)
    pecs = D.union(D.ellipsoid(P, (-0.068, 0.060, 1.318), (0.072 + g, 0.040 + g, 0.058 + g)),
                   D.ellipsoid(P, (0.068, 0.060, 1.318), (0.072 + g, 0.040 + g, 0.058 + g)))
    back = D.union(D.ellipsoid(P, (-0.080, -0.060, 1.300), (0.075 + g, 0.055 + g, 0.120 + g)),
                   D.ellipsoid(P, (0.080, -0.060, 1.300), (0.075 + g, 0.055 + g, 0.120 + g)))
    glutes = D.union(D.ellipsoid(P, (-0.070, -0.055, 0.915), (0.082 + g, 0.068 + g, 0.088 + g)),
                     D.ellipsoid(P, (0.070, -0.055, 0.915), (0.082 + g, 0.068 + g, 0.088 + g)))
    traps = D.union(D.round_cone(P, (0, -0.032, 1.470), (-0.150, -0.026, 1.440), 0.052 + g, 0.042 + g),
                    D.round_cone(P, (0, -0.032, 1.470), (0.150, -0.026, 1.440), 0.052 + g, 0.042 + g))
    neck_d = D.round_cone(P, (0, -0.030, 1.430), (0, -0.020, 1.610), 0.060 + g, 0.052 + g) if neck else None
    d = D.union(d, pecs, back, k=0.035)
    d = D.union(d, glutes, k=0.04)
    d = D.union(d, traps, k=0.04)
    if neck:
        d = D.union(d, neck_d, k=0.03)
    return d


def arm_sdf(P, side, grow=0.0, to_wrist=True):
    j = S.joints()
    s = "Left" if side < 0 else "Right"
    sh, el, wr = j[s + "UpperArm"], j[s + "LowerArm"], j[s + "Hand"]
    g = grow
    delt = D.ellipsoid(P, _v(sh + Vector((side * 0.006, -0.004, -0.016))), (0.052 + g, 0.054 + g, 0.056 + g))
    upper = D.round_cone(P, _v(sh), _v(el), 0.050 + g, 0.038 + g)
    bicep = D.sphere(P, _v(sh.lerp(el, 0.5) + Vector((0, 0.010, 0))), 0.044 + g)
    fore = D.round_cone(P, _v(el), _v(wr), 0.041 + g, 0.027 + g)
    fmus = D.sphere(P, _v(el.lerp(wr, 0.28)), 0.044 + g)
    d = D.union(delt, upper, k=0.04)
    d = D.union(d, bicep, k=0.04)
    d = D.union(d, fore, k=0.025)
    d = D.union(d, fmus, k=0.05)
    return d


def leg_sdf(P, side, grow=0.0):
    j = S.joints()
    s = "Left" if side < 0 else "Right"
    hip, kn, an = j[s + "UpperLeg"], j[s + "LowerLeg"], j[s + "Foot"]
    g = grow
    thigh = D.round_cone(P, _v(hip + Vector((side * 0.006, 0, 0.010))), _v(kn), 0.082 + g, 0.050 + g)
    quad = D.sphere(P, _v(hip.lerp(kn, 0.38) + Vector((0, 0.010, 0))), 0.069 + g)
    knee = D.sphere(P, _v(kn + Vector((0, 0.004, 0))), 0.045 + g)
    shin = D.round_cone(P, _v(kn), _v(an), 0.048 + g, 0.033 + g)
    calf = D.ellipsoid(P, _v(kn.lerp(an, 0.28) + Vector((0, -0.016, 0))), (0.050 + g, 0.052 + g, 0.095 + g))
    d = D.union(thigh, quad, k=0.05)
    d = D.union(d, knee, k=0.03)
    d = D.union(d, shin, k=0.03)
    d = D.union(d, calf, k=0.04)
    return d


def foot_sdf(P, side, grow=0.0):
    j = S.joints()
    s = "Left" if side < 0 else "Right"
    an, ball, tip = j[s + "Foot"], j[s + "Toes"], j[s + "ToeTip"]
    g = grow
    heel = D.sphere(P, _v(an + Vector((0, -0.028, -0.052))), 0.032 + g)
    arch = D.round_cone(P, _v(an + Vector((0, -0.01, -0.02))), _v(ball + Vector((0, 0, 0.004))), 0.036 + g, 0.026 + g)
    sole = D.ellipsoid(P, _v(an.lerp(ball, 0.55) + Vector((side * 0.006, 0, -0.045))), (0.042 + g, 0.095 + g, 0.024 + g))
    toes = D.ellipsoid(P, _v(ball.lerp(tip, 0.45) + Vector((0, 0, 0.002))), (0.046 + g, 0.045 + g, 0.020 + g))
    ankle = D.round_cone(P, _v(an + Vector((0, 0, 0.06))), _v(an), 0.036 + g, 0.034 + g)
    d = D.union(heel, arch, sole, k=0.03)
    d = D.union(d, toes, ankle, k=0.025)
    return D.smax(d, -P[2], 0.004)      # flat sole at z = 0


def body_sdf(P, grow=0.0, parts=("torso", "arms", "legs", "feet")):
    ds = []
    if "torso" in parts:
        ds.append(torso_sdf(P, grow))
    d = ds[0] if ds else None

    def add(x, k):
        nonlocal d
        d = x if d is None else D.smin(d, x, k)

    if "arms" in parts:
        for side in (-1, 1):
            add(arm_sdf(P, side, grow), 0.035)
    if "legs" in parts:
        for side in (-1, 1):
            add(leg_sdf(P, side, grow), 0.045)
    if "feet" in parts:
        for side in (-1, 1):
            add(foot_sdf(P, side, grow), 0.02)
    return d


def build_body(coll, voxel=0.006):
    obj = D.mesh_sdf(BODY_BOUNDS[0], BODY_BOUNDS[1], voxel, body_sdf, "BodySDF", coll, target_tris=16000)
    return obj


# ---------------------------------------------------------------------------- hands


def hand_sdf(P, side, grow=0.0):
    j = S.joints()
    s = "Left" if side < 0 else "Right"
    ax, palm, thumb = S.hand_frame(side)
    w = j[s + "Hand"]
    g = grow
    rot = D.rot_from_axes(thumb, ax, -palm)       # local x = thumb side, y = along hand, z = back
    pc = w + ax * 0.048 + palm * 0.002
    d = D.box(P, _v(pc), (0.040 + g, 0.046 + g, 0.0145 + g), 0.012 + g * 0.5, rot)
    d = D.smin(d, D.round_cone(P, _v(w - ax * 0.05), _v(w + ax * 0.01), 0.029 + g, 0.024 + g), 0.02)
    thenar = D.ellipsoid(P, _v(w + ax * 0.030 + thumb * 0.022 + palm * 0.012), (0.020 + g, 0.024 + g, 0.016 + g),
                         D.rot_from_axes(thumb, ax, -palm))
    d = D.smin(d, thenar, 0.012)
    chains = S.finger_chains(side)
    for fname, segs, r0 in (("Index", S.FINGER_SEGS, 0.0086), ("Middle", S.FINGER_SEGS, 0.0089),
                            ("Ring", S.FINGER_SEGS, 0.0084), ("Little", S.FINGER_SEGS, 0.0075),
                            ("Thumb", S.THUMB_SEGS, 0.0115)):
        for k, seg in enumerate(segs):
            h, t = chains[s + fname + seg]
            ra = r0 * (1 - 0.09 * k) + g
            rb = r0 * (1 - 0.09 * (k + 1)) + g
            if fname == "Thumb" and k == 0:
                ra, rb = 0.016 + g, 0.0125 + g
            d = D.smin(d, D.round_cone(P, _v(h), _v(t), ra, rb), 0.002 if k else 0.006)
    return d


def build_hands(coll, voxel=0.0016, grow=0.0, name="Char_Hands", target=5000):
    objs = []
    j = S.joints()
    for side in (-1, 1):
        s = "Left" if side < 0 else "Right"
        c = j[s + "Hand"] + (j[s + "Knuckle"] - j[s + "Hand"]) * 0.8
        lo = c - Vector((0.13, 0.13, 0.13))
        hi = c + Vector((0.13, 0.13, 0.13))
        objs.append(D.mesh_sdf(_v(lo), _v(hi), voxel, lambda P, sd=side: hand_sdf(P, sd, grow), f"{name}_{s}", coll,
                               target_tris=target // 2))
    return L.join(objs, name)


# ---------------------------------------------------------------------------- regions


def split_regions(body, coll):
    """Splits the weighted body into region objects by dominant bone. Returns {region: obj}."""
    me = body.data
    group_names = {g.index: g.name for g in body.vertex_groups}
    dom = []
    for v in me.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        dom.append(REGION_OF_BONE.get(group_names.get(best.group, "Hips"), "Torso") if best else "Torso")
    out = {}
    for region in REGIONS:
        o = body.copy()
        o.data = body.data.copy()
        o.name = "Char_" + region
        o.data.name = "Char_" + region
        coll.objects.link(o)
        bm = L.bm_from(o)
        kill = []
        for f in bm.faces:
            regs = [dom[v.index] for v in f.verts]
            r = max(set(regs), key=regs.count)
            if r != region:
                kill.append(f)
        bmesh.ops.delete(bm, geom=kill, context="FACES")
        bm.to_mesh(o.data)
        bm.free()
        out[region] = o
    bpy.data.objects.remove(body, do_unlink=True)
    return out


# ---------------------------------------------------------------------------- head


HEAD_C = Vector((0.0, -0.008, 1.690))
EYE_OFF = (0.0315, 0.0690, 0.002)


def head_sdf(P):
    H = HEAD_C

    def p(x, y, z):
        return (H.x + x, H.y + y, H.z + z)

    d = D.ellipsoid(P, p(0, -0.014, 0.026), (0.074, 0.097, 0.088))
    d = D.smin(d, D.ellipsoid(P, p(0, 0.036, 0.032), (0.064, 0.050, 0.062)), 0.03)
    d = D.smin(d, D.ellipsoid(P, p(0, 0.032, -0.030), (0.061, 0.058, 0.058)), 0.03)
    # Jaw: angles, body, chin.
    for sd in (-1, 1):
        d = D.smin(d, D.round_cone(P, p(sd * 0.052, -0.008, -0.060), p(sd * 0.020, 0.070, -0.094), 0.017, 0.014), 0.025)
        d = D.smin(d, D.ellipsoid(P, p(sd * 0.044, 0.052, -0.004), (0.022, 0.020, 0.016)), 0.015)   # cheekbone
    d = D.smin(d, D.ellipsoid(P, p(0, 0.072, -0.094), (0.022, 0.016, 0.017)), 0.02)                 # chin
    d = D.smin(d, D.capsule(P, p(-0.044, 0.078, 0.024), p(0.044, 0.078, 0.024), 0.0115), 0.018)      # brow ridge
    # Eye sockets.
    for sd in (-1, 1):
        d = D.smax(d, -D.ellipsoid(P, p(sd * EYE_OFF[0], EYE_OFF[1] + 0.012, EYE_OFF[2]), (0.019, 0.014, 0.0135)), 0.007)
    # Nose.
    d = D.smin(d, D.round_cone(P, p(0, 0.083, 0.008), p(0, 0.101, -0.033), 0.0080, 0.0100), 0.012)
    for sd in (-1, 1):
        d = D.smin(d, D.sphere(P, p(sd * 0.0125, 0.089, -0.038), 0.0074), 0.007)
    # Lips.
    d = D.smin(d, D.ellipsoid(P, p(0, 0.081, -0.058), (0.020, 0.009, 0.0065)), 0.008)
    d = D.smin(d, D.ellipsoid(P, p(0, 0.078, -0.069), (0.017, 0.009, 0.0065)), 0.008)
    d = D.smax(d, -D.capsule(P, p(-0.018, 0.091, -0.0635), p(0.018, 0.091, -0.0635), 0.0016), 0.002)
    # Ears.
    for sd in (-1, 1):
        ear = D.ellipsoid(P, p(sd * 0.074, -0.014, -0.004), (0.011, 0.021, 0.031))
        ear = D.smax(ear, -D.ellipsoid(P, p(sd * 0.083, -0.010, -0.006), (0.006, 0.013, 0.018)), 0.003)
        d = D.smin(d, ear, 0.006)
    # Neck.
    d = D.smin(d, D.round_cone(P, (0, -0.024, 1.460), (0, -0.016, 1.630), 0.056, 0.050), 0.03)
    return d


def build_head(coll, skin_mat, eye_mat, iris_mat):
    obj = D.mesh_sdf((-0.105, -0.125, 1.455), (0.105, 0.135, 1.815), 0.0016, head_sdf, "Char_Head", coll, target_tris=4500)
    obj.data.materials.append(skin_mat)
    if not obj.data.uv_layers:
        obj.data.uv_layers.new(name="UVMap")
    _head_uv(obj)
    bm = bmesh.new()
    for sd in (-1, 1):
        L.bm_sphere(bm, 0.0118, (sd * EYE_OFF[0], HEAD_C.y + EYE_OFF[1], HEAD_C.z + EYE_OFF[2]), segs=14, rings=10)
        L.bm_sphere(bm, 0.0052, (sd * EYE_OFF[0], HEAD_C.y + EYE_OFF[1] + 0.0098, HEAD_C.z + EYE_OFF[2]),
                    scale=(1, 0.35, 1), segs=12, rings=6, mat=1)
    eyes = L.new_object("Char_Eyes", bm, coll, [eye_mat, iris_mat])
    L.box_uv(eyes, 1.0)
    for p in eyes.data.polygons:
        p.use_smooth = True
    return L.join([obj, eyes], "Char_Head")


def _head_uv(obj):
    """u = angle around the head (0.5 = face centre), v = height. Matches make_skin_texture()."""
    me = obj.data
    uv = me.uv_layers.active.data
    for p in me.polygons:
        for li in p.loop_indices:
            c = me.vertices[me.loops[li].vertex_index].co
            a = math.atan2(c.x - HEAD_C.x, c.y - HEAD_C.y)
            uv[li].uv = (0.5 + a / (2 * math.pi), (c.z - 1.44) / 0.40)


def make_skin_texture(path, n=512, seed=3):
    """Face/skin albedo matching _head_uv (sRGB): tone variation, beard shadow, brows, lips,
    short hair on the crown and back."""
    u = (np.arange(n) + 0.5) / n
    U, V = np.meshgrid(u, 1.0 - u)
    base = np.array([0.76, 0.58, 0.47])
    noise = L.fbm(n, 40, 4, seed)
    blotch = L.fbm(n, 10, 3, seed + 5)
    rgb = base[None, None, :] * (0.93 + 0.09 * noise[..., None]) + (blotch[..., None] - 0.5) * np.array([0.04, 0.0, -0.01])
    a = (U - 0.5) * 2 * math.pi
    z = 1.44 + V * 0.40
    aa = np.abs(a)
    g = lambda q, c, s: np.exp(-((q - c) / s) ** 2)
    sm = lambda t: np.clip(t, 0, 1) ** 2 * (3 - 2 * np.clip(t, 0, 1))

    def mix(rgb, col, w):
        w = np.clip(w, 0, 1)[..., None]
        return rgb * (1 - w) + np.array(col) * w

    stub = sm((1.648 - z) / 0.02) * sm((z - 1.575) / 0.012) * sm((1.05 - aa) / 0.25)
    stub *= 1.0 - 0.8 * g(z, 1.625, 0.012) * g(aa, 0.0, 0.25)          # keep the lips clean
    stub = stub * (0.6 + 0.4 * L.fbm(n, 2.5, 2, seed + 9))
    rgb = mix(rgb, (0.36, 0.27, 0.21), 0.28 * stub)
    lips = g(z, 1.627, 0.0075) * g(aa, 0.0, 0.20)
    rgb = mix(rgb, (0.64, 0.38, 0.35), 0.40 * lips)
    brow = g(z, 1.712, 0.0055) * g(aa, 0.42, 0.16) * sm((aa - 0.12) / 0.06)
    rgb = mix(rgb, (0.24, 0.17, 0.12), 0.70 * brow)
    # Short hair: hairline at the forehead, above the ears, back of the head.
    hairline = 1.752 - 0.045 * sm((aa - 0.6) / 0.9)
    hair = sm((z - hairline) / 0.012) + sm((aa - 2.0) / 0.4) * sm((z - 1.640) / 0.02)
    hair *= 1.0 - g(aa, 1.57, 0.25) * sm((1.705 - z) / 0.02)           # skin around the ears
    hair = np.clip(hair, 0, 1) * (0.75 + 0.25 * L.fbm(n, 2, 2, seed + 13))
    rgb = mix(rgb, (0.33, 0.25, 0.18), 0.85 * hair)
    red = g(z, 1.665, 0.03) * g(aa, 0.0, 0.9) + g(aa, 1.57, 0.2) * g(z, 1.685, 0.03)
    rgb = rgb + red[..., None] * np.array([0.035, -0.01, -0.012])
    return L.save_png(path, np.clip(rgb, 0, 1))
