"""Tactical cover props (AI-SQUAD-01): the pieces that make a firefight readable and give squads
real positions to take - a sandbag fighting position, a log barricade, a boulder group and a
hasty earth berm.

Real dimensions, front = +Y, origin on the ground, collision boxes are the actual cover: the
combat line-of-fire, the soldiers' cover search and the navigation mesh all read them through the
StructureDef, so what looks like cover is cover. Each builder takes the ap_lib module (A) and
returns an A.Asset.
"""
import math
import random

from mathutils import Vector

import ap_kit as K

ALL = (0, 1, 2)
L01 = (0, 1)
L0 = (0,)
L1 = (1,)
L2 = (2,)
SMALL = [[0, 25], [25, 90], [90, 400]]
MEDIUM = [[0, 35], [35, 130], [130, 600]]


# =============================================================================== sandbag position


def _bags_along_x(a, x0, x1, y, courses, rnd, mat="Sandbag", notch=None, h=0.12, depth=(-0.16, 0.16)):
    """Sandbags along X from x0 to x1 at row centre y, two bags deep, in running bond (WORLD-DETAIL-02: ap_kit.bag_wall,
    pillow bags on LOD0 / LOD1). `notch` = (xa, xb, courses_kept): the courses above `courses_kept` are left out between xa
    and xb (a firing gap)."""
    K.bag_wall(a, x0, x1, y, courses, rnd, mat, rows=tuple(d * 0.97 for d in depth),
               gaps=[notch] if notch is not None else None, lods=L01)
    for (sa, sb, hh) in _course_blocks(x0, x1, courses, notch, h):
        a.box((sb - sa, 0.64, hh), ((sa + sb) / 2, y, hh / 2), mat, L2)


def _bags_along_y(a, y0, y1, x, courses, rnd, mat="Sandbag", h=0.12, depth=(-0.16, 0.16)):
    K.bag_wall(a, y0, y1, x, courses, rnd, mat, along="y", rows=tuple(d * 0.97 for d in depth), lods=L01)
    a.box((0.64, y1 - y0, courses * h), (x, (y0 + y1) / 2, courses * h / 2), mat, L2)


def _course_blocks(x0, x1, courses, notch, h):
    if notch is None:
        return [(x0, x1, courses * h)]
    return [(x0, notch[0], courses * h), (notch[0], notch[1], notch[2] * h), (notch[1], x1, courses * h)]


def sandbag_fighting_position(A):
    """A two-man fighting position: sandbag horseshoe open to the rear, 6 courses (0.72 m) with a
    lowered firing gap (3 courses) in the front wall, dug-in floor. 3.8 x 3.2 m. Front = +Y: the
    soldiers kneel inside facing the way the position looks."""
    a = A.Asset("sandbag_fighting_position", "prop", "Sandbag fighting position", "Defences",
                "Two-man sandbag fighting position, open rear, 0.72 m walls with a 0.36 m firing gap in the front: 3.8 x 3.2 m.")
    rnd = random.Random(7711)
    h = 0.12
    W = 3.2          # inner width between the side walls' centres
    yf = 1.25        # front wall row centre
    yb = -1.35       # side walls run back to here
    notch = (-0.50, 0.50, 3)
    _bags_along_x(a, -W / 2 - 0.32, W / 2 + 0.32, yf, 6, rnd, notch=notch)
    _bags_along_y(a, yb, yf - 0.28, -W / 2, 6, rnd)
    _bags_along_y(a, yb, yf - 0.28, W / 2, 6, rnd)
    # Dug-in floor: a slightly darker earth pad, one course below the wall base reads as a hollow.
    a.box((W - 0.55, yf - yb - 0.7, 0.03), (0, (yf + yb) / 2 - 0.1, 0.015), "Dirt", ALL)
    # Collision = the walls (the firing gap is lower than the rest of the front wall).
    t = 0.64
    xl0, xl1 = -W / 2 - 0.32, notch[0]
    xr0, xr1 = notch[1], W / 2 + 0.32
    a.col_box((xl1 - xl0, t, 6 * h), ((xl0 + xl1) / 2, yf, 6 * h / 2))
    a.col_box((xr1 - xr0, t, 6 * h), ((xr0 + xr1) / 2, yf, 6 * h / 2))
    a.col_box((notch[1] - notch[0], t, notch[2] * h), (0, yf, notch[2] * h / 2))
    a.col_box((t, yf - 0.28 - yb, 6 * h), (-W / 2, (yf - 0.28 + yb) / 2, 6 * h / 2))
    a.col_box((t, yf - 0.28 - yb, 6 * h), (W / 2, (yf - 0.28 + yb) / 2, 6 * h / 2))
    a.marker("IP_Left", (-0.6, 0.55, 0), 0, "rifleman, left of the firing gap (faces +Y)")
    a.marker("IP_Right", (0.6, 0.55, 0), 0, "rifleman, right of the firing gap (faces +Y)")
    a.lod_ranges = MEDIUM
    a.ao_height, a.ao_strength = 0.6, 0.32
    a.meta["position"] = {"men": 2, "wall_height": 6 * h, "gap_height": notch[2] * h}
    return a


# =============================================================================== log barricade


def _log(a, p0, p1, r, mat_bark, mat_cut, rnd, knots=True):
    """One felled trunk between p0 and p1 (X-ish axis): bark cylinder, lighter cut faces at the
    ends, a few branch stubs."""
    a.cyl_between(p0, p1, r, mat_bark, L0, segs=14, r2=r * 0.93)
    a.cyl_between(p0, p1, r, mat_bark, L1, segs=8, r2=r * 0.93)
    a.cyl_between(p0, p1, r * 0.97, mat_bark, L2, segs=6, r2=r * 0.9)
    d = (Vector(p1) - Vector(p0)).normalized()
    a.cyl(r * 0.96, r * 0.96, 0.02, tuple(Vector(p0) + d * 0.005), mat_cut, L01, axis=tuple(d), segs=14)
    a.cyl(r * 0.90, r * 0.90, 0.02, tuple(Vector(p1) - d * 0.005), mat_cut, L01, axis=tuple(d), segs=14)
    if knots:
        for _ in range(3):
            t = rnd.uniform(0.15, 0.85)
            c = Vector(p0).lerp(Vector(p1), t)
            ang = rnd.uniform(0, math.tau)
            off = Vector((0, math.cos(ang), math.sin(ang)))
            a.cyl(0.035, 0.02, 0.16, tuple(c + off * (r + 0.05)), mat_bark, L0, axis=tuple(off), segs=6)


def log_barricade(A):
    """Three felled pine trunks stacked in a pyramid (two below, one on top): 3.6 m long, 0.76 m
    high, 1.0 m deep. Natural cover for a wood edge; the stack is too high to step over."""
    a = A.Asset("log_barricade", "prop", "Log barricade", "Defences",
                "Stacked felled trunks 3.6 m long, 0.76 m high: improvised cover at a wood edge.")
    rnd = random.Random(4421)
    L = 3.6
    r1, r2 = 0.20, 0.18
    _log(a, (-L / 2, -0.21, r1), (L / 2, -0.21 + rnd.uniform(-0.03, 0.03), r1 + 0.01), r1, "Timber_Dark", "Timber", rnd)
    _log(a, (-L / 2 + 0.10, 0.22, r1), (L / 2 - 0.05, 0.22 + rnd.uniform(-0.03, 0.03), r1), r1, "Timber_Dark", "Timber", rnd)
    _log(a, (-L / 2 + 0.05, 0.0, 0.40 + r2 - 0.03), (L / 2 - 0.12, 0.0, 0.40 + r2 - 0.02), r2, "Timber_Dark", "Timber", rnd)
    # Wedges keeping the pile from rolling.
    for sx in (-L / 2 + 0.45, L / 2 - 0.45):
        a.box((0.14, 0.14, 0.14), (sx, -0.44, 0.07), "Timber", L0, rot=None)
    a.col_box((L, 0.84, 0.40), (0, 0, 0.20))
    a.col_box((L - 0.1, 0.40, 0.36), (0, 0, 0.58))
    a.lod_ranges = SMALL
    a.ao_height, a.ao_strength = 0.5, 0.35
    return a


# =============================================================================== boulders


def _icosphere(subdiv):
    t = (1.0 + math.sqrt(5.0)) / 2.0
    verts = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
             (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    verts = [tuple(Vector(v).normalized()) for v in verts]
    faces = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
             (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    for _ in range(subdiv):
        cache = {}
        out = []

        def mid(i, j):
            key = (min(i, j), max(i, j))
            if key not in cache:
                v = (Vector(verts[i]) + Vector(verts[j])).normalized()
                verts.append(tuple(v))
                cache[key] = len(verts) - 1
            return cache[key]
        for (i, j, k) in faces:
            ij, jk, ki = mid(i, j), mid(j, k), mid(k, i)
            out += [(i, ij, ki), (j, jk, ij), (k, ki, jk), (ij, jk, ki)]
        faces = out
    return verts, faces


def _boulder(a, c, size, seed, lods_sub):
    """One rock: a deformed icosphere (radial noise from a seed that is the same on every LOD so the
    silhouette stays), squashed, base cut flat below the ground line."""
    sx, sy, sz = size
    rnd = random.Random(seed)
    phases = [rnd.uniform(0, math.tau) for _ in range(6)]
    for lod, sub in lods_sub:
        verts, faces = _icosphere(sub)
        pts = []
        for (x, y, z) in verts:
            n = 1.0 + 0.16 * math.sin(3.1 * x + phases[0]) * math.cos(2.7 * y + phases[1]) + 0.10 * math.sin(5.3 * z + phases[2]) \
                + 0.06 * math.sin(9.1 * x + 7.3 * y + phases[3])
            p = Vector((x * sx * n, y * sy * n, z * sz * n))
            if p.z < -0.12 * sz:
                p.z = -0.12 * sz
            pts.append((c[0] + p.x, c[1] + p.y, c[2] + p.z + 0.12 * sz))
        # Faces wound outward (icosphere order is consistent); flat shading reads as fractured stone.
        a.poly(pts, [tuple(f) for f in faces], "Rock", (lod,), smooth=False)


def boulder_cluster(A):
    """Three granite boulders (1.5 / 1.1 / 0.8 m high) half sunk into the ground: hard natural
    cover, 3.4 x 2.4 m."""
    a = A.Asset("boulder_cluster", "prop", "Boulder group", "Defences",
                "Three half-buried boulders, 1.5 / 1.1 / 0.8 m high, 3.4 x 2.4 m: hard natural cover.")
    subs = [(0, 2), (1, 1), (2, 0)]
    _boulder(a, (-0.55, 0.15, 0.0), (1.15, 0.95, 1.30), 11, subs)
    _boulder(a, (0.85, -0.30, 0.0), (0.85, 0.75, 0.95), 23, subs)
    _boulder(a, (0.25, 0.75, 0.0), (0.60, 0.55, 0.68), 37, subs)
    a.col_box((2.0, 1.6, 1.45), (-0.55, 0.15, 0.72))
    a.col_box((1.4, 1.3, 1.00), (0.85, -0.30, 0.50))
    a.col_box((1.0, 0.9, 0.70), (0.25, 0.75, 0.35))
    a.lod_ranges = MEDIUM
    a.ao_height, a.ao_strength = 0.7, 0.4
    return a


# =============================================================================== earth berm


def earth_berm(A):
    """A hasty earth berm: 4.0 m long, 0.8 m high, 1.9 m base, 0.5 m crest, faced with a row of
    sandbags on the front crest (+Y). Quick cover for a squad that has a spade, not engineers."""
    a = A.Asset("earth_berm", "prop", "Earth berm", "Defences",
                "Hasty earth berm 4.0 m long, 0.8 m high with a sandbag crest: low cover that takes minutes to build.")
    rnd = random.Random(9021)
    Lx = 4.0
    prof = [(-0.95, 0.0), (0.95, 0.0), (0.55, 0.34), (0.30, 0.74), (0.14, 0.82), (-0.14, 0.82), (-0.30, 0.74), (-0.55, 0.34)]
    a.prism(prof, (-Lx / 2, 0, 0), (Lx / 2, 0, 0), "Dirt")
    # Sandbag crest row (front side), LOD0 / LOD1 only.
    K.bag_wall(a, -Lx / 2 + 0.1, Lx / 2 - 0.1, 0.16, 1, rnd, z0=0.74, lods=L01)
    a.col_box((Lx, 1.1, 0.82), (0, 0, 0.41))
    a.marker("SNAP_W", (-Lx / 2, 0, 0), 90)
    a.marker("SNAP_E", (Lx / 2, 0, 0), -90)
    a.lod_ranges = [[0, 40], [40, 150], [150, 700]]
    a.ao_height, a.ao_strength = 0.6, 0.3
    a.meta["module"] = {"length": Lx, "height": 0.9}
    return a


BUILDERS = {
    "sandbag_fighting_position": sandbag_fighting_position,
    "log_barricade": log_barricade,
    "boulder_cluster": boulder_cluster,
    "earth_berm": earth_berm,
}
