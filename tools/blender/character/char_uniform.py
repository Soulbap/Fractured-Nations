"""Uniform pieces (CHARACTER-01): combat jacket, trousers, boots, gloves.

Modelled as offsets of the body SDF (char_body), so every garment follows the shared body.
Reference: Norwegian M23 / Nordic Combat Uniform (2025): stand-up collar, upper-arm
pockets with velcro panel, removable elbow protectors, trousers with integrated knee
protectors, thigh cargo and lower-leg pockets, bloused over black leather combat boots.
"""
import math

import bmesh
import numpy as np
from mathutils import Vector

import char_body as B
import char_lib as L
import char_sdf as D
import char_skeleton as S


def _v(p):
    return tuple(float(c) for c in p)


def _cut_beyond(P, point, normal, keep_radius_center, r):
    """SDF of the region beyond a plane but only near a point (to cut sleeves/legs locally)."""
    beyond = -D.plane(P, point, normal)        # negative beyond the plane (along normal)
    near = D.sphere(P, keep_radius_center, r)
    return D.intersect(beyond, near)


def neck_shift():
    """(forward offset, radius factor) of the body's neck at the collar against the CHARACTER-01 neck."""
    j = S.joints()
    ny = (j["Neck"].y + j["Head"].y) / 2 - (-0.028 + -0.012) / 2
    return ny, getattr(B, "NECK_R", 0.058) / 0.058


def jacket_sdf(P, seed=31):
    j = S.joints()
    X, Y, Z = P
    d = B.torso_sdf(P, 0.017)
    # The jacket hangs straight from the chest to the hem (no waist).
    d = D.smin(d, D.ellipsoid(P, (0, -0.004, 1.06), (0.163, 0.120, 0.30)), 0.05)
    # Lower jacket hangs straight: vertical sides and a level hem (rounded box), no
    # ballooning under the belt.
    d = D.smin(d, D.box(P, (0, -0.006, 0.990), (0.166, 0.118, 0.230), 0.060), 0.04)
    # The hem wraps over the tops of the trouser legs, so the trousers never poke
    # through the jacket at the hips (clean, straight hem line).
    for side in (-1, 1):
        d = D.smin(d, D.smax(B.leg_sdf(P, side, 0.025), 0.862 - Z, 0.004), 0.02)
    arms = None
    for side, s in ((-1, "Left"), (1, "Right")):
        a = B.arm_sdf(P, side, 0.012)
        sh, el, wr = j[s + "UpperArm"], j[s + "LowerArm"], j[s + "Hand"]
        fdir = (wr - el).normalized()
        udir = (el - sh).normalized()
        # Cuff: slightly wider band at the wrist.
        a = D.smin(a, D.round_cone(P, _v(wr - fdir * 0.060), _v(wr - fdir * 0.012), 0.044, 0.043), 0.01)
        # Elbow protector pocket (back of the elbow).
        a = D.smin(a, D.ellipsoid(P, _v(el + Vector((0, -0.045, 0.004))), (0.045, 0.022, 0.055)), 0.012)
        # Upper-arm pocket with velcro panel on the outer side.
        out = Vector((side * 0.707, 0, 0.707))
        out = (out - udir * out.dot(udir)).normalized()
        across = udir.cross(out).normalized()
        pc = sh.lerp(el, 0.45) + out * 0.057
        a = D.smin(a, D.box(P, _v(pc), (0.050, 0.068, 0.012), 0.008, D.rot_from_axes(across, udir, out)), 0.006)
        # Sleeve ends at the wrist.
        a = D.smax(a, -_cut_beyond(P, _v(wr - fdir * 0.012), _v(fdir), _v(wr), 0.14), 0.004)
        arms = a if arms is None else D.smin(arms, a, 0.01)
    d = D.smin(d, arms, 0.035)
    # Neck opening and stand-up collar, around the body's neck (VISUAL-03: ny = how far this neck sits ahead of
    # the CHARACTER-01 one; nr = its radius over the authored 0.058 m).
    ny, nr = neck_shift()
    neck = D.round_cone(P, (0, -0.030 + ny, 1.40), (0, -0.018 + ny, 1.70), 0.061 * nr, 0.056 * nr)
    d = D.smax(d, -neck, 0.006)
    d = D.smax(d, Z - 1.535, 0.008)
    collar = D.round_cone(P, (0, -0.030 + ny, 1.455), (0, -0.022 + ny, 1.548), 0.080 * nr, 0.071 * nr)
    collar = D.smax(collar, -D.round_cone(P, (0, -0.030 + ny, 1.40), (0, -0.018 + ny, 1.62), 0.062 * nr, 0.057 * nr), 0.002)
    collar = D.smax(collar, Z - 1.548, 0.004)
    d = D.smin(d, collar, 0.01)
    # Front zip placket.
    d = D.smin(d, D.box(P, (0, 0.126, 1.17), (0.012, 0.010, 0.30), 0.006), 0.012)
    # Hem below the belt line (covers the trouser waist).
    d = D.smax(d, 0.865 - Z, 0.01)
    # Fabric: folds at the elbows, waist bunching, general wrinkles.
    n = D.noise3(P, 0.09, seed, 3)
    d += 0.0016 * n
    for s in ("Left", "Right"):
        el = j[s + "LowerArm"]
        w = np.exp(-(D.sphere(P, _v(el), 0.0) / 0.06) ** 2)
        d += 0.0022 * w * np.sin((X * 0.3 + Z) * 210.0)
    waist = np.exp(-((Z - 0.95) / 0.04) ** 2)
    d += 0.0018 * waist * np.sin(np.arctan2(X, Y) * 14.0)
    return d


def trousers_sdf(P, seed=37):
    j = S.joints()
    X, Y, Z = P
    pelvis = D.smax(B.torso_sdf(P, 0.017), Z - 1.080, 0.01)
    d = pelvis
    for side, s in ((-1, "Left"), (1, "Right")):
        hip, kn, an = j[s + "UpperLeg"], j[s + "LowerLeg"], j[s + "Foot"]
        lg = B.leg_sdf(P, side, 0.021)
        # Bloused over the boots.
        lg = D.smin(lg, D.round_cone(P, _v(an + Vector((0, 0.004, 0.06))), _v(an + Vector((0, 0.0, 0.17))), 0.063, 0.058), 0.03)
        # Integrated knee protector.
        lg = D.smin(lg, D.ellipsoid(P, _v(kn + Vector((0, 0.052, 0.012))), (0.056, 0.026, 0.075)), 0.014)
        # Thigh cargo pocket (outer side) with a flap.
        tp = hip.lerp(kn, 0.48)
        lg = D.smin(lg, D.box(P, _v(tp + Vector((side * 0.070, 0.018, 0))), (0.012, 0.064, 0.084), 0.010), 0.016)
        lg = D.smin(lg, D.box(P, _v(tp + Vector((side * 0.077, 0.018, 0.076))), (0.009, 0.068, 0.015), 0.006), 0.004)
        # Lower-leg pocket.
        cp = kn.lerp(an, 0.62)
        lg = D.smin(lg, D.box(P, _v(cp + Vector((side * 0.058, 0.004, 0))), (0.012, 0.048, 0.058), 0.008), 0.01)
        d = D.smin(d, lg, 0.04)
    # Waistband.
    d = D.smin(d, D.smax(B.torso_sdf(P, 0.021), np.abs(Z - 1.064) - 0.016, 0.004), 0.004)
    d = D.smax(d, Z - 1.080, 0.006)
    d = D.smax(d, 0.118 - Z, 0.008)
    n = D.noise3(P, 0.10, seed, 3)
    d += 0.0020 * n
    for s in ("Left", "Right"):
        kn = j[s + "LowerLeg"]
        w = np.exp(-(D.sphere(P, _v(kn + Vector((0, -0.04, 0.0))), 0.0) / 0.07) ** 2)
        d += 0.0025 * w * np.sin(Z * 190.0)
    ank = np.exp(-((Z - 0.17) / 0.05) ** 2)
    d += 0.0035 * ank * np.sin(Z * 150.0 + np.arctan2(X, Y) * 3.0)
    return d


def boot_sdf(P, side):
    j = S.joints()
    s = "Left" if side < 0 else "Right"
    an, ball, tip = j[s + "Foot"], j[s + "Toes"], j[s + "ToeTip"]
    X, Y, Z = P
    d = B.foot_sdf(P, side, 0.008)
    shaft = D.round_cone(P, _v(an + Vector((0, -0.006, 0.0))), _v(an + Vector((0, -0.002, 0.125))), 0.046, 0.044)
    d = D.smin(d, shaft, 0.03)
    # Heel counter and toe box.
    d = D.smin(d, D.ellipsoid(P, _v(an + Vector((0, -0.040, -0.040))), (0.040, 0.040, 0.048)), 0.02)
    d = D.smin(d, D.ellipsoid(P, _v(ball + Vector((side * 0.002, 0.030, 0.012))), (0.043, 0.060, 0.030)), 0.02)
    # Sole: forefoot slab + thicker heel block, slight toe spring, flat bottom.
    heel_y, toe_y = an.y - 0.080, tip.y + 0.016
    fore = D.box(P, _v(Vector((ball.x, ball.y + 0.012, 0.011))), (0.047, 0.088, 0.011), 0.010)
    heel = D.box(P, _v(Vector((an.x, heel_y + 0.048, 0.016))), (0.041, 0.048, 0.016), 0.008)
    waist = D.box(P, _v(Vector((an.x * 0.5 + ball.x * 0.5, (an.y + ball.y) / 2, 0.012))), (0.036, 0.06, 0.012), 0.008)
    sole = D.union(fore, heel, waist, k=0.012)
    d = D.smin(d, sole, 0.006)
    # Lacing / tongue ridge on the instep.
    d = D.smin(d, D.round_cone(P, _v(ball + Vector((0, -0.02, 0.038))), _v(an + Vector((0, 0.046, 0.118))), 0.013, 0.017), 0.012)
    d = D.smax(d, Z - (an.z + 0.125), 0.006)
    d = D.smax(d, -Z, 0.002)
    return d


def glove_sdf(P, side):
    j = S.joints()
    s = "Left" if side < 0 else "Right"
    el, wr = j[s + "LowerArm"], j[s + "Hand"]
    ax, palm, thumb = S.hand_frame(side)
    fdir = (wr - el).normalized()
    d = B.hand_sdf(P, side, 0.0022)
    d = D.smin(d, D.round_cone(P, _v(wr - fdir * 0.055), _v(wr + ax * 0.012), 0.0335, 0.030), 0.012)
    # Padded back of the hand and knuckle strip.
    d = D.smin(d, D.box(P, _v(wr + ax * 0.050 - palm * 0.016), (0.038, 0.034, 0.006), 0.005, D.rot_from_axes(thumb, ax, -palm)), 0.006)
    # Wrist strap.
    d = D.smin(d, D.round_cone(P, _v(wr - fdir * 0.030), _v(wr - fdir * 0.012), 0.0355, 0.0355), 0.003)
    d = D.smax(d, -_cut_beyond(P, _v(wr - fdir * 0.058), _v(-fdir), _v(wr), 0.15), 0.002)
    return d


# ---------------------------------------------------------------------------- builders


def build_jacket(coll, mats, voxel=0.004):
    obj = D.mesh_sdf((-0.64, -0.19, 0.84), (0.64, 0.23, 1.58), voxel, jacket_sdf, "Uni_Jacket", coll, target_tris=10000)
    obj.data.materials.append(mats["Camo_M23"])
    # Faction patch (velcro flag) on the left upper-arm pocket.
    j = S.joints()
    sh, el = j["LeftUpperArm"], j["LeftLowerArm"]
    udir = (el - sh).normalized()
    out = Vector((-0.707, 0, 0.707))
    out = (out - udir * out.dot(udir)).normalized()
    across = udir.cross(out).normalized()
    bm = bmesh.new()
    rot = __import__("mathutils").Matrix((across, udir, out)).transposed()
    L.rounded_box(bm, (0.075, 0.050, 0.004), sh.lerp(el, 0.40) + out * 0.071, 0.0015, rot=rot, segs=1)
    patch = L.new_object("Uni_Patch", bm, coll, [mats["Patch"]])
    return L.join([obj, patch], "Uni_Jacket")


def build_trousers(coll, mats, voxel=0.0036):
    obj = D.mesh_sdf((-0.24, -0.21, 0.10), (0.24, 0.20, 1.10), voxel, trousers_sdf, "Uni_Trousers", coll, target_tris=8000)
    obj.data.materials.append(mats["Camo_M23"])
    return obj


def build_boots(coll, mats, voxel=0.0025):
    j = S.joints()
    objs = []
    for side, s in ((-1, "Left"), (1, "Right")):
        an = j[s + "Foot"]
        lo = (an.x - 0.085, an.y - 0.12, -0.01)
        hi = (an.x + 0.085, j[s + "ToeTip"].y + 0.05, an.z + 0.14)
        o = D.mesh_sdf(lo, hi, voxel, lambda P, sd=side: boot_sdf(P, sd), "Uni_Boot_" + s, coll, target_tris=1800)
        objs.append(o)
    obj = L.join(objs, "Uni_Boots")
    obj.data.materials.append(mats["Boot_Leather"])
    obj.data.materials.append(mats["Boot_Sole"])
    for p in obj.data.polygons:
        if p.center.z < 0.031:
            p.material_index = 1
    return obj


def build_gloves(coll, mats, voxel=0.0016):
    j = S.joints()
    objs = []
    for side, s in ((-1, "Left"), (1, "Right")):
        c = j[s + "Hand"] + (j[s + "Knuckle"] - j[s + "Hand"]) * 0.6
        lo = _v(c - Vector((0.14, 0.14, 0.14)))
        hi = _v(c + Vector((0.14, 0.14, 0.14)))
        objs.append(D.mesh_sdf(lo, hi, voxel, lambda P, sd=side: glove_sdf(P, sd), "Uni_Glove_" + s, coll, target_tris=2000))
    obj = L.join(objs, "Uni_Gloves")
    obj.data.materials.append(mats["Glove_Coyote"])
    return obj


def build_uniform(coll, mats):
    return {
        "jacket": build_jacket(coll, mats),
        "trousers": build_trousers(coll, mats),
        "boots": build_boots(coll, mats),
        "gloves": build_gloves(coll, mats),
    }
