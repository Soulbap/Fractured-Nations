"""Faction-specific infantry equipment on the shared CHARACTER-01 body (ASSET-PRODUCTION-01).

Everything is fitted to the same body SDF as char_gear (torso_hull offsets, numeric
surface placement), so pieces work with every uniform and the one shared rig.

Silhouette cues per family (references: public photos of NATO exercises 2020-2025,
Russian Ratnik/Sotnik kit, PLA Type 21 kit):
  NATO  mid-cut ballistic helmet (ECH / Virtus class) with multi-terrain cover, NVG
        shroud, ARC rails and electronic ear defenders; slim plate carrier with a
        triple magazine shingle; combat shirt with plain torso.
  RU    6B47-class rounded helmet with digital cover and goggles on the brow; 6B45-class
        full-wrap body armour with a high collar, shoulder protectors and groin flap,
        6Sh117-class pouches (4 AK magazines across the belly); external knee pads.
  CN    PASGT-lineage (QGF-03 class) helmet with flared skirt and Type 21 cover, side
        rails; Type 19-class carrier with a wide front magazine panel and a flat
        hydration/assault pack.
"""
import math

import bmesh
import numpy as np
from mathutils import Vector

import char_body as B
import char_gear as G
import char_lib as L
import char_sdf as D
import char_skeleton as S

HC = B.HEAD_C


def _v(p):
    return tuple(float(c) for c in p)


def _smooth(objs):
    for o in objs:
        for f in o.data.polygons:
            f.use_smooth = True


# ============================================================================ helmets

HELMETS = {
    # center, radii, cut profile (angle from the front -> rim height), flare, cover material
    "nato": {"c": (0.0, -0.020, 1.722), "r": (0.108, 0.132, 0.114),
             "cut": ([0, 0.75, 1.10, 1.40, 1.80, 2.35, math.pi], [1.752, 1.746, 1.724, 1.700, 1.690, 1.668, 1.660]),
             "flare": 0.0, "cover": "Camo_NATO"},
    "ru": {"c": (0.0, -0.018, 1.716), "r": (0.119, 0.139, 0.122),
           "cut": ([0, 0.70, 1.10, 1.50, 2.00, 2.50, math.pi], [1.742, 1.734, 1.700, 1.652, 1.640, 1.630, 1.626]),
           "flare": 0.02, "cover": "Camo_EMR"},
    "cn": {"c": (0.0, -0.016, 1.714), "r": (0.114, 0.136, 0.118),
           "cut": ([0, 0.60, 1.10, 1.50, 2.00, 2.60, math.pi], [1.744, 1.740, 1.706, 1.652, 1.642, 1.634, 1.630]),
           "flare": 0.22, "cover": "Camo_Type21"},
}


def _cut_z(X, Y, spec):
    a = np.abs(np.arctan2(X, Y - HC.y))
    ang, zs = spec["cut"]
    return np.interp(a, ang, zs)


def _flared(P, spec):
    """Scales X/Y outward near the rim (PASGT-style skirt)."""
    X, Y, Z = P
    if spec["flare"] <= 0:
        return P
    c = spec["c"]
    f = 1.0 + spec["flare"] * np.clip((1.712 - Z) / 0.07, 0, 1) ** 1.5
    return (X / f, (Y - c[1]) / f + c[1], Z)


def helmet_shell(P, spec, extra=0.0, thick=0.011):
    X, Y, Z = P
    Q = _flared(P, spec)
    r = spec["r"]
    outer = D.ellipsoid(Q, spec["c"], tuple(v + extra for v in r))
    inner = D.ellipsoid(Q, spec["c"], tuple(v - thick for v in r))
    d = D.smax(outer, -inner, 0.002)
    return D.smax(d, _cut_z(X, Y, spec) - Z, 0.003)


def build_helmet(coll, mats, fac, voxel=0.0018):
    spec = HELMETS[fac]
    c, r = Vector(spec["c"]), spec["r"]

    def fn(P):
        X, Y, Z = P
        d = helmet_shell(P, spec)
        # Fabric cover: slightly larger, loose folds, elastic rim band.
        d = D.smin(d, helmet_shell(P, spec, 0.003), 0.002)
        d += 0.0011 * D.noise3(P, 0.05, 71 + len(fac), 2)
        rim = D.smax(helmet_shell(P, spec, 0.0055), -(Z - _cut_z(X, Y, spec) - 0.011), 0.002)
        d = D.smin(d, rim, 0.002)
        if fac == "ru":
            # Elastic camouflage band around the crown.
            band = D.smax(helmet_shell(P, spec, 0.008), np.abs(Z - (c.z + 0.035)) - 0.010, 0.002)
            d = D.smin(d, band, 0.002)
        if fac == "nato":
            # Counterweight pouch on the back of the cover.
            d = D.smin(d, D.box(P, (0, c.y - r[1] - 0.004, 1.735), (0.045, 0.016, 0.028), 0.010), 0.006)
        return d
    lo = (-0.16, -0.19, 1.58)
    hi = (0.16, 0.16, 1.87)
    shell_o = D.mesh_sdf(lo, hi, voxel, fn, "Helmet_" + fac, coll, target_tris=3600)
    shell_o.data.materials.append(mats[spec["cover"]])
    parts = [shell_o]
    bm = bmesh.new()
    # Retention harness (all) - four-point chin strap.
    for sd in (-1, 1):
        L.tube_along(bm, [(sd * (r[0] - 0.012), c.y + 0.005, 1.700), (sd * 0.080, 0.014, 1.640), (sd * 0.050, 0.050, 1.585), (sd * 0.012, 0.066, 1.566)],
                     [0.0055] * 4, segs=6, flat=0.35)
        L.tube_along(bm, [(sd * (r[0] - 0.012), c.y - 0.040, 1.690), (sd * 0.070, -0.085, 1.640), (sd * 0.020, -0.090, 1.630)], [0.0055] * 3, segs=6, flat=0.35)
    L.rounded_box(bm, (0.036, 0.014, 0.022), (0, 0.070, 1.568), 0.006, segs=1)
    parts.append(L.new_object("Helmet_harness", bm, coll, [mats["Strap_Black"]]))
    fy = c.y + r[1]
    if fac in ("nato", "cn"):
        # ARC side rails, NVG shroud on the front.
        def rails(P):
            X, Y, Z = P
            Q = _flared(P, spec)
            band = D.smax(D.ellipsoid(Q, spec["c"], tuple(v + 0.011 for v in r)), -D.ellipsoid(Q, spec["c"], tuple(v - 0.002 for v in r)), 0.001)
            a = np.abs(np.arctan2(X, Y - HC.y))
            zr = _cut_z(X, Y, spec) + (0.022 if fac == "nato" else 0.030)
            band = D.smax(band, np.abs(Z - zr) - 0.011, 0.002)
            band = D.smax(band, np.maximum(0.95 - a, a - 2.15) * 0.05, 0.001)
            shroud = D.box(P, (0, fy - 0.004, 1.770 if fac == "nato" else 1.765), (0.024, 0.014, 0.020), 0.005,
                           D.rot_from_axes((1, 0, 0), (0, 0.96, -0.28), (0, 0.28, 0.96)))
            return D.union(band, shroud, k=0.004)
        hard = D.mesh_sdf(lo, (0.16, 0.18, 1.87), voxel, rails, "Helmet_rails", coll, target_tris=1200)
        hard.data.materials.append(mats["Polymer_Black"])
        parts.append(hard)
    bm = bmesh.new()
    if fac == "nato":
        # Electronic ear defenders (cups over the ears, headband under the helmet) + boom mic, IR strobe.
        for sd in (-1, 1):
            L.bm_sphere(bm, 1.0, (sd * 0.094, -0.012, 1.676), scale=(0.028, 0.044, 0.052), segs=16, rings=10)
            L.rounded_box(bm, (0.012, 0.018, 0.055), (sd * 0.108, -0.012, 1.722), 0.004, segs=1)
        L.tube_along(bm, [(-0.115, 0.012, 1.662), (-0.088, 0.062, 1.640), (-0.036, 0.090, 1.625)], [0.003] * 3, segs=6)
        L.bm_sphere(bm, 0.008, (-0.031, 0.094, 1.624), segs=8, rings=6)
        L.rounded_box(bm, (0.020, 0.012, 0.032), (0.045, c.y - r[1] + 0.03, 1.835), 0.004, segs=1)
        parts.append(L.new_object("Helmet_headset", bm, coll, [mats["Polymer_Tan"]]))
    elif fac == "ru":
        # Goggles resting on the brow of the helmet: strap around the shell, frame, lenses.
        zc = 1.770
        pts = []
        for t in np.linspace(-2.35, 2.35, 25):
            k = 1.0 + spec["flare"]
            pts.append((math.sin(t) * (r[0] + 0.012), c.y + math.cos(t) * (r[1] + 0.012), zc - 0.004 * abs(t)))
        L.tube_along(bm, pts, [(0.0035, 0.012)] * len(pts), segs=6, cap=True)
        parts.append(L.new_object("Helmet_gstrap", bm, coll, [mats["Strap_Black"]]))
        bm = bmesh.new()
        for sd in (-1, 1):
            L.bm_sphere(bm, 1.0, (sd * 0.040, fy + 0.020, zc + 0.006), scale=(0.040, 0.020, 0.030), segs=16, rings=8)
        L.rounded_box(bm, (0.030, 0.026, 0.020), (0, fy + 0.022, zc + 0.002), 0.006, segs=1)
        parts.append(L.new_object("Helmet_goggles", bm, coll, [mats["Rubber_Black"]]))
        bm = bmesh.new()
        for sd in (-1, 1):
            L.bm_sphere(bm, 1.0, (sd * 0.040, fy + 0.036, zc + 0.006), scale=(0.034, 0.008, 0.024), segs=14, rings=6)
        parts.append(L.new_object("Helmet_glens", bm, coll, [mats["Lens_Tinted"]]))
    elif fac == "cn":
        # Small radio earpiece on the left, NVG mount plate.
        L.bm_sphere(bm, 1.0, (-0.084, -0.012, 1.676), scale=(0.018, 0.026, 0.030), segs=12, rings=8)
        L.tube_along(bm, [(-0.098, 0.006, 1.664), (-0.080, 0.058, 1.640), (-0.034, 0.088, 1.626)], [0.0028] * 3, segs=6)
        L.rounded_box(bm, (0.040, 0.028, 0.026), (0, fy + 0.014, 1.762), 0.006, segs=1)
        parts.append(L.new_object("Helmet_cnkit", bm, coll, [mats["Polymer_Black"]]))
    _smooth(parts)
    return L.join(parts, "Helmet_" + fac)


# ============================================================================ NATO vest

def build_nato_vest(coll, mats):
    """Slim plate carrier in multi-terrain camo: triple shingle, admin, side radio, IFAK,
    grenade pouches (char_gear vest builder with a NATO layout)."""
    G.VEST_LAYOUTS["nato"] = {"panel": "Camo_NATO", "pouch": "Camo_NATO", "mag_rows": 1, "mag_depth": 0.030,
                              "cummer": (1.080, 1.250), "grenades": True, "chest_radio": False, "side_radio": True}
    return G.build_vest(coll, mats, "nato")


# ============================================================================ RU armour


def ru_armor_sdf(P):
    X, Y, Z = P
    j = S.joints()
    body = D.intersect(G.shell(P, 0.021, 0.056), D.box(P, (0, 0, 1.258), (0.40, 0.40, 0.245), 0.02), 0.006)
    # Thicker front and back plate pockets.
    for sy, yc in ((1, 0.25), (-1, -0.25)):
        plate = D.intersect(G.shell(P, 0.045, 0.070), D.box(P, (0, yc, 1.27), (0.130, 0.25, 0.160), 0.035), 0.006)
        body = D.smin(body, plate, 0.01)
    # High protective collar around the neck, open at the throat.
    collar = D.smax(D.round_cone(P, (0, -0.030, 1.450), (0, -0.026, 1.560), 0.112, 0.098),
                    -D.round_cone(P, (0, -0.030, 1.430), (0, -0.026, 1.600), 0.084, 0.075), 0.003)
    collar = D.smax(collar, -(Z - 1.455), 0.004)
    collar = D.smax(collar, Z - 1.565, 0.004)
    collar = D.smax(collar, -D.box(P, (0, 0.12, 1.53), (0.030, 0.10, 0.06), 0.01), 0.006)
    body = D.smin(body, collar, 0.02)
    # Shoulder protectors over the upper arms.
    for side, s in ((-1, "Left"), (1, "Right")):
        sh, el = j[s + "UpperArm"], j[s + "LowerArm"]
        cc = sh.lerp(el, 0.22) + Vector((side * 0.030, 0, 0.040))
        pad = D.smax(D.ellipsoid(P, _v(cc), (0.074, 0.084, 0.070)), -D.ellipsoid(P, _v(cc), (0.056, 0.066, 0.052)), 0.003)
        pad = D.smax(pad, (cc.z - 0.030) - Z, 0.004)
        body = D.smin(body, pad, 0.004)
    # Groin protector hanging from the front.
    groin = D.box(P, (0, G.surface_y(lambda Q: G.torso_hull(Q, 0.045), 0, 1.0) + 0.006, 0.925), (0.085, 0.012, 0.070), 0.012)
    body = D.smin(body, groin, 0.01)
    body += 0.0012 * D.noise3(P, 0.08, 81, 2)
    return body


def build_ru_armor(coll, mats, voxel=0.0032):
    armor = D.mesh_sdf((-0.32, -0.27, 0.84), (0.32, 0.28, 1.60), voxel, ru_armor_sdf, "RU_armor", coll, target_tris=7000)
    armor.data.materials.append(mats["Camo_EMR"])
    bm_p, bm_h = bmesh.new(), bmesh.new()
    yf = lambda x, z: G.surface_y(lambda Q: G.torso_hull(Q, 0.070), x, z)
    # Four AK magazine pouches across the belly (6Sh117-class), flaps and bungees.
    zc = 1.105
    for x in (-0.108, -0.036, 0.036, 0.108):
        y0 = yf(x, zc) + 0.024
        L.rounded_box(bm_p, (0.066, 0.050, 0.165), (x, y0, zc), 0.010, segs=2)
        L.rounded_box(bm_p, (0.070, 0.054, 0.036), (x, y0 + 0.002, zc + 0.070), 0.008, segs=1)
        L.rounded_box(bm_h, (0.020, 0.010, 0.016), (x, y0 + 0.028, zc + 0.060), 0.004, segs=1)
    # Radio pouch upper left chest and grenade pouches upper right.
    yr = yf(-0.080, 1.36)
    L.rounded_box(bm_p, (0.070, 0.050, 0.110), (-0.080, yr + 0.024, 1.355), 0.010, segs=2)
    for x in (0.060, 0.115):
        L.rounded_box(bm_p, (0.050, 0.046, 0.080), (x, yf(x, 1.34) + 0.022, 1.340), 0.014, segs=2)
    # Side pouches (IFAK right, utility left).
    xs = lambda y, z, sd: G.surface_x(lambda Q: G.torso_hull(Q, 0.056), y, z, sd)
    L.rounded_box(bm_p, (0.050, 0.110, 0.120), (xs(-0.02, 1.12, 1) + 0.022, -0.020, 1.120), 0.012, segs=2)
    L.rounded_box(bm_p, (0.050, 0.090, 0.110), (xs(-0.02, 1.12, -1) - 0.022, -0.020, 1.120), 0.012, segs=2)
    # Drag handle and back utility pouch.
    yb = G.surface_y(lambda Q: G.torso_hull(Q, 0.070), 0, 1.40, front=False)
    L.rounded_box(bm_h, (0.090, 0.016, 0.014), (0, yb - 0.008, 1.420), 0.006, segs=1)
    L.rounded_box(bm_p, (0.200, 0.050, 0.150), (0, G.surface_y(lambda Q: G.torso_hull(Q, 0.070), 0, 1.17, front=False) - 0.022, 1.170), 0.014, segs=2)
    pouches = L.new_object("RU_pouches", bm_p, coll, [mats["Camo_EMR"]])
    hard = L.new_object("RU_hard", bm_h, coll, [mats["Polymer_Black"]])
    bm = bmesh.new()
    # Radio whip antenna from the chest radio over the left shoulder.
    L.tube_along(bm, [(-0.098, yr + 0.02, 1.41), (-0.115, yr - 0.03, 1.55), (-0.125, yr - 0.08, 1.66)], [0.005, 0.004, 0.003], segs=6)
    ant = L.new_object("RU_antenna", bm, coll, [mats["Rubber_Black"]])
    parts = [armor, pouches, hard, ant]
    _smooth(parts)
    return L.join(parts, "RU_armor")


# ============================================================================ CN vest + pack


def cn_vest_sdf(P):
    X, Y, Z = P
    front = D.intersect(G.shell(P, 0.021, 0.062), D.box(P, (0, 0.25, 1.235), (0.150, 0.25, 0.185), 0.040), 0.006)
    back = D.intersect(G.shell(P, 0.021, 0.056), D.box(P, (0, -0.25, 1.265), (0.135, 0.25, 0.165), 0.035), 0.006)
    cummer = D.intersect(G.shell(P, 0.020, 0.040), D.box(P, (0, 0, 1.140), (0.40, 0.40, 0.085), 0.01), 0.004)
    straps = None
    for sd in (-1, 1):
        s = D.intersect(G.shell(P, 0.020, 0.040), D.box(P, (sd * 0.092, 0, 1.47), (0.046, 0.40, 0.11), 0.012), 0.004)
        straps = s if straps is None else D.smin(straps, s, 0.0)
    d = D.smin(D.union(front, back), cummer, 0.012)
    d = D.smin(d, straps, 0.015)
    d += 0.0010 * D.noise3(P, 0.08, 91, 2)
    return d


def build_cn_vest(coll, mats, voxel=0.003):
    panels = D.mesh_sdf((-0.26, -0.26, 0.98), (0.26, 0.28, 1.60), voxel, cn_vest_sdf, "CN_vest", coll, target_tris=5500)
    panels.data.materials.append(mats["Camo_Type21"])
    bm_p, bm_h = bmesh.new(), bmesh.new()
    yf = lambda x, z: G.surface_y(lambda Q: G.torso_hull(Q, 0.062), x, z)
    # Wide front magazine panel: four 5.8 mm magazine pouches side by side, low on the plate.
    zc = 1.150
    for x in (-0.105, -0.035, 0.035, 0.105):
        y0 = yf(x, zc) + 0.022
        L.rounded_box(bm_p, (0.064, 0.044, 0.150), (x, y0, zc), 0.010, segs=2)
        L.rounded_box(bm_h, (0.024, 0.010, 0.020), (x, y0 + 0.025, zc + 0.058), 0.004, segs=1)
    # Large admin / map panel with a velcro ID patch area above the magazines.
    za = 1.330
    ya = yf(0.0, za)
    L.rounded_box(bm_p, (0.230, 0.030, 0.110), (0, ya + 0.014, za), 0.010, segs=2)
    L.rounded_box(bm_h, (0.090, 0.006, 0.040), (0.050, ya + 0.031, za + 0.010), 0.002, segs=1)
    # Side utility pouches and a canteen pouch at the back right.
    xs = lambda y, z, sd: G.surface_x(lambda Q: G.torso_hull(Q, 0.040), y, z, sd)
    for sd in (-1, 1):
        L.rounded_box(bm_p, (0.046, 0.090, 0.120), (xs(0.0, 1.14, sd) + sd * 0.020, 0.000, 1.140), 0.012, segs=2)
    pouches = L.new_object("CN_pouches", bm_p, coll, [mats["Camo_Type21"]])
    hard = L.new_object("CN_hard", bm_h, coll, [mats["Polymer_Black"]])
    parts = [panels, pouches, hard]
    _smooth(parts)
    return L.join(parts, "CN_vest")


def build_cn_pack(coll, mats, voxel=0.004):
    """Flat square hydration / assault pack on the back of the carrier (rigid on ATT_Back)."""
    yb = G.surface_y(lambda Q: G.torso_hull(Q, 0.058), 0.0, 1.28, front=False)
    c = Vector((0, yb - 0.055, 1.300))
    half = (0.145, 0.052, 0.200)

    def fn(P):
        d = D.box(P, _v(c), half, 0.030)
        d = D.smin(d, D.box(P, _v(c + Vector((0, -half[1] - 0.012, -0.03))), (half[0] * 0.80, 0.020, half[2] * 0.60), 0.016), 0.008)
        d += 0.0015 * D.noise3(P, 0.10, 97, 2)
        return d
    lo = _v(c - Vector((half[0] + 0.07, half[1] + 0.07, half[2] + 0.07)))
    hi = _v(c + Vector((half[0] + 0.07, half[1] + 0.07, half[2] + 0.07)))
    body = D.mesh_sdf(lo, hi, voxel, fn, "CN_pack", coll, target_tris=2400)
    body.data.materials.append(mats["Camo_Type21"])
    straps = D.mesh_sdf((-0.22, -0.26, 1.20), (0.22, 0.26, 1.60), 0.003,
                        lambda P: G._strap_band(P, 0.040, 0.052, z_front_min=1.30), "CN_pack_straps", coll, target_tris=1600)
    straps.data.materials.append(mats["Camo_Type21"])
    bm = bmesh.new()
    for sd in (-1, 1):
        L.rounded_box(bm, (0.010, half[1] * 2 + 0.01, 0.020), (sd * (half[0] + 0.003), c.y, c.z + 0.05), 0.003, segs=1)
    L.rounded_box(bm, (0.060, 0.020, 0.012), (0, c.y + 0.02, c.z + half[2] + 0.012), 0.004, segs=1)
    L.tube_along(bm, [(0.11, c.y + 0.03, c.z + half[2]), (0.13, c.y + 0.10, c.z + half[2] + 0.05), (0.14, yb + 0.06, 1.42)], [0.006] * 3, segs=6)
    hard = L.new_object("CN_pack_hard", bm, coll, [mats["Strap_Black"]])
    parts = [body, straps, hard]
    _smooth(parts)
    return L.join(parts, "CN_pack")


# ============================================================================ uniform variants


def nato_shirt_split(jacket, mats):
    """Combat shirt: plain coyote torso under the armour, camo sleeves and collar."""
    me = jacket.data
    me.materials.append(mats["Fabric_Coyote"])
    idx = len(me.materials) - 1
    camo_idx = [i for i, m in enumerate(me.materials) if m.name == "Camo_NATO"][0]
    cs = np.array([p.center for p in me.polygons], np.float32)
    P = (cs[:, 0], cs[:, 1], cs[:, 2])
    dt = B.torso_sdf(P, 0.017)
    da = np.minimum(B.arm_sdf(P, -1, 0.012), B.arm_sdf(P, 1, 0.012))
    torso = (dt < da - 0.004) & (cs[:, 2] < 1.47) & (cs[:, 2] > 0.90)
    for p, t in zip(me.polygons, torso):
        if t and p.material_index == camo_idx:
            p.material_index = idx


def ru_kneepads(coll, mats, voxel=0.0025):
    """External hard-shell knee pads with straps (joined into the RU trousers)."""
    j = S.joints()

    def fn(P):
        d = None
        for s in ("Left", "Right"):
            kn = j[s + "LowerLeg"]
            c = kn + Vector((0, 0.064, 0.010))
            pad = D.smax(D.ellipsoid(P, _v(c), (0.050, 0.030, 0.072)), -D.ellipsoid(P, _v(c + Vector((0, -0.014, 0))), (0.046, 0.026, 0.066)), 0.002)
            pad = D.smax(pad, (kn.y + 0.050) - P[1], 0.003)
            d = pad if d is None else D.smin(d, pad, 0.0)
        return d
    pads = D.mesh_sdf((-0.20, -0.05, 0.38), (0.20, 0.16, 0.62), voxel, fn, "RU_kneepads", coll, target_tris=1600)
    pads.data.materials.append(mats["Polymer_Black"])
    bm = bmesh.new()
    for s, sd in (("Left", -1), ("Right", 1)):
        kn = j[s + "LowerLeg"]
        for dz in (0.055, -0.045):
            ring = []
            for t in np.linspace(0, 2 * math.pi, 17)[:-1]:
                ring.append((kn.x + 0.068 * math.sin(t), kn.y + 0.004 + 0.066 * math.cos(t), kn.z + dz))
            L.tube_along(bm, ring + [ring[0]], [(0.004, 0.011)] * (len(ring) + 1), segs=6, cap=False)
    straps = L.new_object("RU_kneestraps", bm, coll, [mats["Strap_Black"]])
    _smooth([pads, straps])
    return L.join([pads, straps], "RU_kneepads")
