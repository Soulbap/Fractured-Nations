"""Load-bearing and head equipment (CHARACTER-01).

All pieces are fitted to the shared body: shells are offsets of the jacket surface
(torso_hull), pouches are placed on surfaces found numerically, so a piece built for this
body fits every uniform built on it. Soft goods are SDF meshes, hard parts bmesh.

References: Norwegian/Nordic infantry 2019-2025 (Telemark Bn., Noble Jump, Saber Strike
photos): high-cut helmet (Ops-Core FAST M/12, Galvion Caiman M24) with cover, ARC rails,
ComTac-style headset and NVG shroud; ranger-green plate carrier (NFM Thor/Heidrun family)
with a triple M4 magazine shingle, admin pouch, side radio; coyote assault pack.
"""
import math

import bmesh
import numpy as np
from mathutils import Matrix, Vector

import char_body as B
import char_lib as L
import char_sdf as D
import char_skeleton as S


def _v(p):
    return tuple(float(c) for c in p)


def torso_hull(P, g):
    """Jacket-compatible torso surface grown by g beyond the BODY (jacket itself = 0.017)."""
    d = B.torso_sdf(P, g, neck=False)
    return D.smin(d, D.ellipsoid(P, (0, -0.004, 1.06), (0.146 + g, 0.103 + g, 0.283 + g)), 0.05)


def surface_y(fn, x, z, front=True, lo=0.0, hi=0.4):
    """Y of the zero level of fn along a ray at (x, z) going out the front (or back)."""
    sgn = 1.0 if front else -1.0
    a, b = lo, hi
    for _ in range(40):
        m = 0.5 * (a + b)
        P = (np.array([x], np.float32), np.array([sgn * m], np.float32), np.array([z], np.float32))
        if fn(P)[0] < 0:
            a = m
        else:
            b = m
    return sgn * 0.5 * (a + b)


def surface_x(fn, y, z, side=1.0, lo=0.0, hi=0.4):
    a, b = lo, hi
    for _ in range(40):
        m = 0.5 * (a + b)
        P = (np.array([side * m], np.float32), np.array([y], np.float32), np.array([z], np.float32))
        if fn(P)[0] < 0:
            a = m
        else:
            b = m
    return side * 0.5 * (a + b)


def shell(P, g_in, g_out):
    return D.smax(torso_hull(P, g_out), -torso_hull(P, g_in), 0.003)


def _material_by(obj, mats_list, fn):
    """Assigns material index fn(face_center) for every face."""
    me = obj.data
    for m in mats_list:
        me.materials.append(m)
    for p in me.polygons:
        p.material_index = fn(p.center)


# =========================================================================== plate carriers


VEST_LAYOUTS = {
    # Standard: slick ranger-green carrier, triple M4 shingle, admin, side radio, IFAK.
    "standard": {"panel": "Webbing_RangerGreen", "pouch": "Cordura_RangerGreen", "mag_rows": 1, "mag_depth": 0.026,
                 "cummer": (1.085, 1.245), "grenades": False, "chest_radio": False, "side_radio": True},
    # Heavy: coyote carrier, double-stack magazine shingle (6 mags), grenade pouches,
    # chest-mounted radio with antenna, bigger cummerbund and side pouches.
    "heavy": {"panel": "Webbing_Coyote", "pouch": "Cordura_Coyote", "mag_rows": 2, "mag_depth": 0.040,
              "cummer": (1.070, 1.265), "grenades": True, "chest_radio": True, "side_radio": False},
}


def vest_sdf_parts(P, lay):
    """Returns (panels_sdf, pouches_sdf) for one layout."""
    X, Y, Z = P
    z0, z1 = lay["cummer"]
    front = D.intersect(shell(P, 0.021, 0.060), D.box(P, (0, 0.25, 1.255), (0.128, 0.25, 0.150), 0.035), 0.006)
    back = D.intersect(shell(P, 0.021, 0.055), D.box(P, (0, -0.25, 1.265), (0.130, 0.25, 0.160), 0.035), 0.006)
    cummer = D.intersect(shell(P, 0.020, 0.036), D.box(P, (0, 0, (z0 + z1) / 2), (0.40, 0.40, (z1 - z0) / 2), 0.01), 0.004)
    straps = None
    for sd in (-1, 1):
        s = D.intersect(shell(P, 0.020, 0.034), D.box(P, (sd * 0.088, 0, 1.47), (0.034, 0.40, 0.11), 0.012), 0.004)
        straps = s if straps is None else D.smin(straps, s, 0.0)
    panels = D.union(front, back, k=0.0)
    panels = D.smin(panels, cummer, 0.012)
    panels = D.smin(panels, straps, 0.015)
    # Drag handle on the back panel.
    yb = surface_y(lambda Q: torso_hull(Q, 0.055), 0.0, 1.40, front=False)
    panels = D.smin(panels, D.box(P, (0, yb - 0.010, 1.405), (0.045, 0.012, 0.010), 0.006), 0.004)
    return panels


def build_vest(coll, mats, layout, voxel=0.003):
    lay = VEST_LAYOUTS[layout]
    fn = lambda P: vest_sdf_parts(P, lay)
    panels = D.mesh_sdf((-0.25, -0.26, 1.02), (0.25, 0.27, 1.60), voxel, fn, "Vest_" + layout, coll, target_tris=5500)
    panels.data.materials.append(mats[lay["panel"]])
    parts = [panels]
    pouch_mat = mats[lay["pouch"]]
    # Magazine shingle on the front plate bag.
    yf = lambda x, z: surface_y(lambda Q: torso_hull(Q, 0.060), x, z)
    rows = lay["mag_rows"]
    depth = lay["mag_depth"]
    zc = 1.170
    bm_p = bmesh.new()
    bm_m = bmesh.new()
    for x in (-0.074, 0.0, 0.074):
        y0 = yf(x, zc) + depth - 0.002
        L.rounded_box(bm_p, (0.068, depth * 2, 0.150), (x, y0, zc), 0.010, segs=2)
        # Elastic retention band and pull tab.
        L.rounded_box(bm_p, (0.071, depth * 2 + 0.006, 0.020), (x, y0, zc + 0.040), 0.005, segs=1)
        for k in range(rows):
            dy = (k - (rows - 1) / 2) * 0.026
            L.rounded_box(bm_m, (0.060, 0.022, 0.040), (x, y0 + dy, zc + 0.090), 0.004, segs=1)
            L.rounded_box(bm_m, (0.030, 0.012, 0.010), (x, y0 + dy, zc + 0.113), 0.004, segs=1)
    # Admin / map pouch above the shingle.
    za = 1.318
    ya = yf(0.0, za)
    L.rounded_box(bm_p, (0.180, 0.034 if layout == "standard" else 0.044, 0.090), (0, ya + 0.016, za), 0.010, segs=2)
    L.rounded_box(bm_p, (0.186, 0.040 if layout == "standard" else 0.050, 0.018), (0, ya + 0.018, za + 0.040), 0.006, segs=1)
    # Side pouches on the cummerbund.
    xs = lambda y, z, sd: surface_x(lambda Q: torso_hull(Q, 0.036), y, z, sd)
    if lay["side_radio"]:
        x = xs(-0.01, 1.16, -1)
        L.rounded_box(bm_p, (0.046, 0.075, 0.150), (x - 0.020, -0.010, 1.16), 0.010, segs=2)
        L.rounded_box(bm_m, (0.040, 0.062, 0.040), (x - 0.020, -0.010, 1.252), 0.006, segs=1)   # radio top
    x = xs(-0.03, 1.15, 1)
    L.rounded_box(bm_p, (0.042, 0.100, 0.110), (x + 0.018, -0.030, 1.15), 0.012, segs=2)          # IFAK
    if lay["grenades"]:
        for sd in (-1, 1):
            x = xs(0.065, 1.15, sd)
            L.rounded_box(bm_p, (0.050, 0.050, 0.085), (x + sd * 0.015, 0.075, 1.15), 0.014, segs=2)
            x = xs(-0.07, 1.15, sd)
            L.rounded_box(bm_p, (0.048, 0.070, 0.120), (x + sd * 0.020, -0.075, 1.15), 0.012, segs=2)
    if lay["chest_radio"]:
        # Radio on the left shoulder strap / upper chest with a short whip antenna.
        yr = yf(-0.085, 1.39) + 0.002
        L.rounded_box(bm_p, (0.060, 0.040, 0.090), (-0.090, yr + 0.020, 1.385), 0.010, segs=2)
        L.rounded_box(bm_m, (0.052, 0.034, 0.030), (-0.090, yr + 0.022, 1.440), 0.006, segs=1)
    pouches = L.new_object("Vest_pouches", bm_p, coll, [pouch_mat])
    hard = L.new_object("Vest_hard", bm_m, coll, [mats["Polymer_Black"]])
    parts += [pouches, hard]
    # Antenna (thin flexible whip) for the radio. It is bent out and back over the left shoulder, below head height: aiming
    # turns the face towards the left shoulder (stance yaw), and a whip standing up beside the head crossed the face.
    bm = bmesh.new()
    if lay["side_radio"]:
        x = xs(-0.01, 1.16, -1) - 0.020
        pts = [(x - 0.004, -0.035, 1.27), (x - 0.010, -0.085, 1.36), (x - 0.012, -0.150, 1.43), (x - 0.008, -0.220, 1.47)]
    else:
        yr = yf(-0.085, 1.39) + 0.002
        pts = [(-0.105, yr + 0.010, 1.455), (-0.150, yr - 0.010, 1.500), (-0.195, yr - 0.050, 1.560)]
    L.tube_along(bm, pts, [0.0055, 0.0045, 0.0035, 0.003][:len(pts)], segs=6)
    ant = L.new_object("Vest_antenna", bm, coll, [mats["Rubber_Black"]])
    parts.append(ant)
    for p in parts:
        for f in p.data.polygons:
            f.use_smooth = True
    return L.join(parts, "Vest_" + layout)


# =========================================================================== belts


BELT_LAYOUTS = {
    "standard": {"mag_pouches": 0, "dump": True, "canteen": True, "etool": False},
    "heavy": {"mag_pouches": 2, "dump": True, "canteen": True, "etool": True},
}


def build_belt(coll, mats, layout, voxel=0.003):
    lay = BELT_LAYOUTS[layout]

    def fn(P):
        X, Y, Z = P
        band = D.intersect(shell(P, 0.016, 0.034), D.box(P, (0, 0, 1.032), (0.40, 0.40, 0.026), 0.008), 0.003)
        return band
    belt = D.mesh_sdf((-0.24, -0.22, 0.96), (0.24, 0.22, 1.10), voxel, fn, "Belt_" + layout, coll, target_tris=2500)
    belt.data.materials.append(mats["Webbing_RangerGreen"])
    bm = bmesh.new()
    bh = bmesh.new()
    xs = lambda y, z, sd: surface_x(lambda Q: torso_hull(Q, 0.034), y, z, sd)
    ys = lambda x, z, fr: surface_y(lambda Q: torso_hull(Q, 0.034), x, z, fr)
    # Buckle (front).
    yb = ys(0.0, 1.032, True)
    L.rounded_box(bh, (0.060, 0.012, 0.044), (0, yb + 0.004, 1.032), 0.004, segs=1)
    # IFAK rear left, dump pouch rear right (rolled), canteen right hip.
    yr = ys(-0.085, 1.02, False)
    L.rounded_box(bm, (0.110, 0.055, 0.090), (-0.085, yr - 0.022, 1.010), 0.014, segs=2)
    if lay["dump"]:
        L.rounded_box(bm, (0.100, 0.045, 0.060), (0.090, yr - 0.018, 1.030), 0.018, segs=2)
    if lay["canteen"]:
        x = xs(0.0, 1.0, 1)
        L.rounded_box(bm, (0.060, 0.090, 0.140), (x + 0.024, -0.020, 0.985), 0.022, segs=2)
        L.rounded_box(bh, (0.040, 0.040, 0.020), (x + 0.024, -0.020, 1.066), 0.010, segs=1)
    # Multitool / knife pouch left front.
    x = xs(0.05, 1.0, -1)
    L.rounded_box(bm, (0.032, 0.040, 0.105), (x - 0.012, 0.060, 0.995), 0.008, segs=1)
    for i in range(lay["mag_pouches"]):
        xm = -0.065 - i * 0.068
        ym = ys(xm, 1.02, True)
        L.rounded_box(bm, (0.064, 0.050, 0.120), (xm, ym + 0.020, 1.000), 0.010, segs=2)
        L.rounded_box(bh, (0.024, 0.018, 0.030), (xm, ym + 0.020, 1.070), 0.004, segs=1)
    if lay["etool"]:
        # Folding entrenching tool in its carrier on the left hip.
        x = xs(-0.06, 1.0, -1)
        L.rounded_box(bm, (0.050, 0.075, 0.200), (x - 0.025, -0.060, 0.955), 0.016, segs=2)
        L.bm_cyl(bh, 0.012, 0.012, 0.080, (x - 0.025, -0.060, 1.085), segs=8)
    pouches = L.new_object("Belt_pouches", bm, coll, [mats["Cordura_RangerGreen"]])
    hard = L.new_object("Belt_hard", bh, coll, [mats["Polymer_Black"]])
    for o in (pouches, hard):
        for f in o.data.polygons:
            f.use_smooth = True
    return L.join([belt, pouches, hard], "Belt_" + layout)


# =========================================================================== packs


def _strap_band(P, g_in, g_out, x_in=0.066, x_out=0.118, z_front_min=1.30):
    """Pack shoulder straps: bands over the shoulders down to z_front_min on the front."""
    out = None
    for sd in (-1, 1):
        s = D.intersect(shell(P, g_in, g_out), D.box(P, (sd * (x_in + x_out) / 2, 0, 1.47), ((x_out - x_in) / 2, 0.40, 0.11), 0.010), 0.003)
        lower = D.intersect(shell(P, g_in, g_out), D.box(P, (sd * 0.105, 0.20, (z_front_min + 1.38) / 2), (0.022, 0.20, (1.38 - z_front_min) / 2 + 0.01), 0.008), 0.003)
        s = D.smin(s, lower, 0.01)
        out = s if out is None else D.smin(out, s, 0.0)
    return out


def build_pack(coll, mats, kind, voxel=0.004):
    """kind: 'assault' (25 l, rides on the plate carrier) or 'ruck' (60 l + mat + M72)."""
    g_back = 0.058                      # outside the back plate bag
    yb = surface_y(lambda Q: torso_hull(Q, g_back), 0.0, 1.28, front=False)
    if kind == "assault":
        c = Vector((0, yb - 0.078, 1.300))
        half = (0.135, 0.075, 0.205)
    else:
        c = Vector((0, yb - 0.135, 1.240))
        half = (0.175, 0.130, 0.300)

    def fn(P):
        d = D.box(P, _v(c), half, 0.045 if kind == "ruck" else 0.035)
        # Slight taper (narrower at the top) and a domed lid.
        lid = D.ellipsoid(P, _v(c + Vector((0, 0.0, half[2] - 0.02))), (half[0] * 0.95, half[1] * 0.95, 0.06))
        d = D.smin(d, lid, 0.02)
        front_pocket = D.box(P, _v(c + Vector((0, -half[1] - 0.015, -half[2] * 0.25))), (half[0] * 0.75, 0.030, half[2] * 0.55), 0.020)
        d = D.smin(d, front_pocket, 0.01)
        if kind == "ruck":
            for sd in (-1, 1):
                side = D.box(P, _v(c + Vector((sd * (half[0] + 0.03), -0.01, -0.08))), (0.035, half[1] * 0.70, half[2] * 0.55), 0.020)
                d = D.smin(d, side, 0.01)
            # Padded back panel / frame sheet towards the body.
            d = D.smin(d, D.box(P, _v(c + Vector((0, half[1] - 0.01, -0.02))), (half[0] * 0.92, 0.02, half[2] * 0.95), 0.015), 0.01)
        d += 0.0018 * D.noise3(P, 0.12, 41 if kind == "ruck" else 43, 2)
        return d
    lo = _v(c - Vector((half[0] + 0.09, half[1] + 0.07, half[2] + 0.09)))
    hi = _v(c + Vector((half[0] + 0.09, half[1] + 0.07, half[2] + 0.12)))
    body = D.mesh_sdf(lo, hi, voxel, fn, "Pack_" + kind, coll, target_tris=5000 if kind == "ruck" else 3000)
    body.data.materials.append(mats["Cordura_Coyote"])
    # Shoulder straps over the plate-carrier straps.
    straps = D.mesh_sdf((-0.22, -0.26, 1.20), (0.22, 0.26, 1.60), 0.003,
                        lambda P: _strap_band(P, 0.034, 0.048, z_front_min=1.27), "Pack_straps", coll, target_tris=2000)
    straps.data.materials.append(mats["Cordura_Coyote" if kind == "assault" else "Cordura_RangerGreen"])
    parts = [body, straps]
    bm = bmesh.new()
    # Compression straps and buckles.
    for sd in (-1, 1):
        for dz in (-0.10, 0.08):
            L.rounded_box(bm, (0.010, half[1] * 2 + 0.01, 0.022), (sd * (half[0] + (0.065 if kind == "ruck" else 0.004)), c.y, c.z + dz), 0.003, segs=1)
    L.rounded_box(bm, (0.050, 0.020, 0.012), (0, c.y + half[1] * 0.4, c.z + half[2] + 0.050), 0.004, segs=1)  # grab handle
    straps_hard = L.new_object("Pack_hard", bm, coll, [mats["Strap_Black"]])
    parts.append(straps_hard)
    if kind == "ruck":
        bm = bmesh.new()
        # Sleeping mat rolled on top, under the lid straps.
        L.bm_cyl(bm, 0.078, 0.078, 0.50, (0, c.y + 0.00, c.z + half[2] + 0.100), axis=(1, 0, 0), segs=18)
        mat_roll = L.new_object("Pack_mat", bm, coll, [mats["Fabric_RangerGreen"]])
        bm = bmesh.new()
        # M72 LAW strapped vertically to the right side.
        lx, ly, lz = half[0] + 0.080, c.y - 0.03, c.z - 0.02
        L.bm_cyl(bm, 0.033, 0.033, 0.64, (lx, ly, lz), axis=(0, -0.10, 1), segs=14)
        L.bm_cyl(bm, 0.037, 0.037, 0.045, (lx, ly + 0.029, lz - 0.29), axis=(0, -0.10, 1), segs=14)
        L.bm_cyl(bm, 0.037, 0.037, 0.045, (lx, ly - 0.029, lz + 0.29), axis=(0, -0.10, 1), segs=14)
        law = L.new_object("Pack_m72", bm, coll, [mats["Polymer_OD"]])
        bm = bmesh.new()
        # Radio in the lid with a long antenna.
        pts = [(-0.12, c.y - 0.02, c.z + half[2]), (-0.13, c.y - 0.04, c.z + half[2] + 0.25), (-0.14, c.y - 0.07, c.z + half[2] + 0.50)]
        L.tube_along(bm, pts, [0.006, 0.004, 0.003], segs=6)
        ant = L.new_object("Pack_antenna", bm, coll, [mats["Rubber_Black"]])
        parts += [mat_roll, law, ant]
    for p in parts:
        for f in p.data.polygons:
            f.use_smooth = True
    obj = L.join(parts, "Pack_" + kind)
    return obj


# =========================================================================== head gear


HC = B.HEAD_C


def _helmet_cut_z(Xa, Ya):
    a = np.abs(np.arctan2(Xa, Ya - HC.y))
    return np.interp(a, [0, 0.75, 1.10, 1.30, 1.95, 2.35, math.pi], [1.752, 1.748, 1.733, 1.724, 1.724, 1.672, 1.662])


HELMET_R = (0.106, 0.130, 0.112)
HELMET_C = (0.0, -0.020, 1.722)


def helmet_shell_sdf(P, extra=0.0):
    X, Y, Z = P
    outer = D.ellipsoid(P, HELMET_C, tuple(r + extra for r in HELMET_R))
    inner = D.ellipsoid(P, HELMET_C, tuple(r - 0.011 for r in HELMET_R))
    d = D.smax(outer, -inner, 0.002)
    d = D.smax(d, _helmet_cut_z(X, Y) - Z, 0.003)
    return d


def build_helmet(coll, mats, variant, voxel=0.0018):
    """variant 'covered' (camo cover, standard) or 'bare' (ranger green shell + NVG kit)."""

    def fn(P):
        X, Y, Z = P
        d = helmet_shell_sdf(P)
        if variant == "covered":
            # Cover: slightly larger, loose fabric folds and an elastic band at the rim.
            d = D.smin(d, helmet_shell_sdf(P, 0.003), 0.002)
            d += 0.0010 * D.noise3(P, 0.05, 51, 2)
            rim = D.smax(helmet_shell_sdf(P, 0.005), -(Z - _helmet_cut_z(X, Y) - 0.010), 0.002)
            d = D.smin(d, rim, 0.002)
        # Velcro loop panels (top and back) are slightly raised.
        top = D.smax(helmet_shell_sdf(P, 0.0025), D.ellipsoid(P, (0, -0.02, 1.84), (0.045, 0.06, 0.03)), 0.002)
        d = D.smin(d, top, 0.001)
        return d
    shell_o = D.mesh_sdf((-0.13, -0.17, 1.64), (0.13, 0.13, 1.86), voxel, fn, "Helmet_" + variant, coll, target_tris=3400)
    shell_o.data.materials.append(mats["Camo_M23" if variant == "covered" else "Helmet_Shell"])
    parts = [shell_o]
    # ARC side rails, NVG shroud, harness and chin strap (hard parts).
    def rails(P):
        X, Y, Z = P
        band = D.smax(D.ellipsoid(P, HELMET_C, tuple(r + 0.010 for r in HELMET_R)), -D.ellipsoid(P, HELMET_C, tuple(r - 0.002 for r in HELMET_R)), 0.001)
        a = np.abs(np.arctan2(X, Y - HC.y))
        zr = _helmet_cut_z(X, Y) + 0.016
        band = D.smax(band, np.abs(Z - zr) - 0.011, 0.002)
        band = D.smax(band, np.maximum(0.85 - a, a - 2.25) * 0.05, 0.001)
        shroud = D.box(P, (0, HELMET_C[1] + HELMET_R[1] - 0.006, 1.758), (0.024, 0.014, 0.020), 0.005,
                       D.rot_from_axes((1, 0, 0), (0, 0.96, -0.28), (0, 0.28, 0.96)))
        return D.union(band, shroud, k=0.004)
    hard = D.mesh_sdf((-0.13, -0.17, 1.64), (0.13, 0.15, 1.86), voxel, rails, "Helmet_rails", coll, target_tris=1200)
    hard.data.materials.append(mats["Polymer_Black"])
    parts.append(hard)
    bm = bmesh.new()
    # Retention harness: side straps to the chin cup and a nape strap.
    for sd in (-1, 1):
        L.tube_along(bm, [(sd * 0.093, -0.010, 1.722), (sd * 0.082, 0.012, 1.650), (sd * 0.050, 0.050, 1.585), (sd * 0.012, 0.066, 1.566)],
                     [0.0055, 0.0055, 0.0055, 0.0055], segs=6, flat=0.35)
        L.tube_along(bm, [(sd * 0.093, -0.040, 1.715), (sd * 0.070, -0.085, 1.640), (sd * 0.020, -0.090, 1.630)],
                     [0.0055, 0.0055, 0.0055], segs=6, flat=0.35)
    L.rounded_box(bm, (0.036, 0.014, 0.022), (0, 0.070, 1.568), 0.006, segs=1)
    harness = L.new_object("Helmet_harness", bm, coll, [mats["Strap_Black"]])
    parts.append(harness)
    # Headset ear cups on rail arms + boom mic (left).
    bm = bmesh.new()
    for sd in (-1, 1):
        L.bm_sphere(bm, 1.0, (sd * 0.093, -0.012, 1.680), scale=(0.024, 0.040, 0.048), segs=16, rings=10)
        L.rounded_box(bm, (0.010, 0.016, 0.050), (sd * 0.106, -0.012, 1.722), 0.004, segs=1)
    L.tube_along(bm, [(-0.110, 0.010, 1.665), (-0.085, 0.060, 1.640), (-0.035, 0.088, 1.625)], [0.003, 0.003, 0.003], segs=6)
    L.bm_sphere(bm, 0.008, (-0.030, 0.092, 1.624), segs=8, rings=6)
    headset = L.new_object("Helmet_headset", bm, coll, [mats["Polymer_OD"]])
    parts.append(headset)
    if variant == "bare":
        bm = bmesh.new()
        # NVG mount arm + monocular flipped up, battery pack (counterweight) at the back.
        fy = HELMET_C[1] + HELMET_R[1]
        L.rounded_box(bm, (0.040, 0.030, 0.028), (0, fy + 0.014, 1.770), 0.006, segs=1)
        L.bm_cyl(bm, 0.021, 0.019, 0.105, (0, fy + 0.050, 1.808), axis=(0, 0.55, 0.83), segs=16)
        L.bm_cyl(bm, 0.024, 0.024, 0.018, (0, fy + 0.020, 1.762), axis=(0, 0.55, 0.83), segs=16)
        L.rounded_box(bm, (0.090, 0.040, 0.050), (0, HELMET_C[1] - HELMET_R[1] - 0.012, 1.745), 0.012, segs=2)
        L.rounded_box(bm, (0.018, 0.010, 0.030), (0.040, -0.070, 1.84), 0.004, segs=1)           # IR strobe
        nvg = L.new_object("Helmet_nvg", bm, coll, [mats["Polymer_Black"]])
        parts.append(nvg)
    for p in parts:
        for f in p.data.polygons:
            f.use_smooth = True
    return L.join(parts, "Helmet_" + variant)


def build_eyepro(coll, mats, voxel=0.0010):
    """Wrap-around ballistic glasses with a thin black frame."""

    def lens(P):
        X, Y, Z = P
        sh = D.smax(D.ellipsoid(P, (0, HC.y - 0.002, HC.z + 0.004), (0.090, 0.110, 0.13)),
                    -D.ellipsoid(P, (0, HC.y - 0.002, HC.z + 0.004), (0.0885, 0.1085, 0.13)), 0.0005)
        a = np.abs(np.arctan2(X, Y - HC.y))
        ztop = HC.z + 0.015 - 0.008 * (a / 1.3) ** 2
        zbot = HC.z - 0.013 + 0.008 * (a / 1.3) ** 2 + 0.010 * np.exp(-(X / 0.011) ** 2)
        reg = np.maximum(np.maximum(Z - ztop, zbot - Z), (a - 1.28) * 0.05)
        return D.smax(sh, reg, 0.0015)
    lo, hi = (-0.10, -0.03, 1.66), (0.10, 0.11, 1.72)
    lens_o = D.mesh_sdf(lo, hi, voxel, lens, "Eyepro_lens", coll, target_tris=1600)
    lens_o.data.materials.append(mats["Lens_Tinted"])
    bm = bmesh.new()
    # Top frame bar following the lens and temple arms to the ears.
    pts = []
    for t in np.linspace(-1.28, 1.28, 15):
        x = 0.0895 * math.sin(t)
        y = HC.y - 0.002 + 0.1095 * math.cos(t)
        z = HC.z + 0.015 - 0.008 * (abs(t) / 1.3) ** 2 + 0.0015
        pts.append((x, y, z))
    L.tube_along(bm, pts, [0.0022] * len(pts), segs=6, cap=True)
    for sd in (-1, 1):
        L.tube_along(bm, [(sd * 0.086, 0.020, 1.712), (sd * 0.082, -0.020, 1.705), (sd * 0.080, -0.045, 1.690)], [0.002, 0.002, 0.002], segs=5)
    frame = L.new_object("Eyepro_frame", bm, coll, [mats["Polymer_Black"]])
    return L.join([lens_o, frame], "Eyepro")
