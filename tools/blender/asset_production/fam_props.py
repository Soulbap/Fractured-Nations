"""Military infrastructure props, part 1: containers, HESCO, sandbags, concrete walls,
fences and gates, road barriers and checkpoint pieces (ASSET-PRODUCTION-01).

Modular, freely placeable pieces with real dimensions. Lengths follow common modules so
layouts line up without stretching: HESCO MIL1 cells 1.06 m (1.37 m high) and MIL7
cells 2.13 m (2.21 m), 3.0 m fence panels and Jersey barriers, 1.52 m T-wall segments,
20 / 40 ft ISO containers. Front = +Y, origin on the ground; linear pieces run along X.

Each builder takes the ap_lib module (A) and returns an A.Asset.
"""
import math

from mathutils import Vector

import ap_kit as K
import ap_signs as S
from ap_kit import Frame

FT20 = 6.058
FT40 = 12.192
ISO_W = 2.438
ISO_H = 2.591
ALL = (0, 1, 2)
L01 = (0, 1)
L0 = (0,)
L12 = (1, 2)
L2 = (2,)
SMALL = [[0, 20], [20, 60], [60, 160]]
MEDIUM = [[0, 30], [30, 100], [100, 400]]


# =============================================================================== containers


def iso_container(A, aid, length, mat, name):
    """ISO 1CC/1AA dry container: corrugated walls (normal map), frame rails and posts,
    corner castings, double doors with four locking bars at the front (+Y)."""
    a = A.Asset(aid, "prop", name, "Containers",
                "%s ISO dry freight container (%.3f x %.3f x %.3f m), doors at the front." % (name.split(" ")[0], length, ISO_W, ISO_H))
    W, Lg, H = ISO_W, length, ISO_H
    hw, hl = W / 2, Lg / 2
    paint = {"Container_OD": "Paint_OD", "Container_Tan": "Paint_Tan", "Container_Blue": "Paint_Grey",
             "Container_Rust": "Paint_Red", "Container_Grey": "Paint_Grey", "Container_White": "Paint_White"}[mat]
    cc = (0.162, 0.178, 0.118)
    for sx in (-1, 1):
        for sy in (-1, 1):
            for z in (cc[2] / 2, H - cc[2] / 2):
                a.box(cc, (sx * (hw - cc[0] / 2), sy * (hl - cc[1] / 2), z), "Steel_Dark", A.L0, bevel=0.006)
                a.box((0.004, 0.11, 0.06), (sx * (hw + 0.001), sy * (hl - cc[1] / 2), z), "Paint_Black", A.L0)
            a.box((0.15, 0.15, H - 2 * cc[2]), (sx * (hw - 0.075), sy * (hl - 0.09), H / 2), paint, A.L0, bevel=0.01)
            a.box((0.15, 0.17, H), (sx * (hw - 0.075), sy * (hl - 0.085), H / 2), paint, (1,))
    rl = Lg - 2 * cc[1]
    for sx in (-1, 1):
        a.box((0.10, rl, 0.16), (sx * (hw - 0.05), 0, 0.08), paint, A.L01, bevel=0.008)
        a.box((0.07, rl, 0.10), (sx * (hw - 0.035), 0, H - 0.05), paint, A.L01, bevel=0.008)
        if length < 7:
            for y in (-1.025, 1.025):
                a.box((0.004, 0.36, 0.10), (sx * (hw + 0.001), y, 0.07), "Paint_Black", A.L0)
    a.box((0.03, rl, H - 0.26), (-(hw - 0.045), 0, 0.16 + (H - 0.26) / 2), mat, A.L01)
    a.box((0.03, rl, H - 0.26), (hw - 0.045, 0, 0.16 + (H - 0.26) / 2), mat, A.L01)
    a.box((W - 0.30, 0.03, H - 0.26), (0, -(hl - 0.05), 0.16 + (H - 0.26) / 2), mat, A.L01)
    a.box((W - 0.14, rl, 0.03), (0, 0, H - 0.04), mat, A.L01)
    a.box((W - 0.30, 0.16, 0.20), (0, hl - 0.08, H - 0.10), paint, A.L01, bevel=0.01)
    a.box((W - 0.30, 0.16, 0.16), (0, hl - 0.08, 0.08), paint, A.L01, bevel=0.01)
    dw = (W - 0.30) / 2 - 0.006
    dy = hl - 0.035
    for sx in (-1, 1):
        a.box((dw, 0.05, H - 0.36), (sx * (dw / 2 + 0.003), dy, H / 2), mat, A.L01)
        a.box((0.05, 0.06, H - 0.36), (sx * (dw - 0.022), dy + 0.005, H / 2), paint, A.L0)
        a.box((dw, 0.06, 0.05), (sx * (dw / 2 + 0.003), dy + 0.005, H - 0.205), paint, A.L0)
        a.box((dw, 0.06, 0.05), (sx * (dw / 2 + 0.003), dy + 0.005, 0.205), paint, A.L0)
        for z in (0.40, 1.0, 1.6, 2.2):
            a.box((0.06, 0.05, 0.10), (sx * (hw - 0.17), dy + 0.04, z), "Steel_Dark", A.L0)
        for bx in (0.18, 0.58):
            x = sx * (0.003 + bx)
            a.cyl(0.0135, 0.0135, H - 0.20, (x, dy + 0.055, H / 2), "Steel_Galv", A.L0, segs=8)
            a.box((0.03, 0.03, H - 0.20), (x, dy + 0.05, H / 2), "Steel_Galv", (1,))
            for z in (0.17, H - 0.17):
                a.box((0.07, 0.05, 0.06), (x, dy + 0.05, z), "Steel_Dark", A.L0, bevel=0.008)
            a.box((0.025, 0.035, 0.30), (x + sx * 0.03, dy + 0.085, 1.05), "Steel_Galv", A.L0, rot=A.rot_y(sx * 75), bevel=0.006)
            a.box((0.06, 0.03, 0.05), (x + sx * 0.12, dy + 0.06, 1.01), "Steel_Dark", A.L0)
    a.box((W, Lg, H), (0, 0, H / 2), mat, A.L2)
    a.sign(A.RECT01, (0, hl + 0.003, H / 2), (-1, 0, 0), (0, 0, 1), W - 0.02, H - 0.02, S.rect("container_doors"), lods=A.L2)
    a.col_box((W, Lg, H), (0, 0, H / 2))
    a.marker("IP_Doors", (0, hl + 0.9, 0), 180, "stand here to open / load the doors")
    a.marker("ATT_Stack", (0, 0, H), 0, "next container stacks here (castings align)")
    a.ao_height, a.ao_strength = 0.9, 0.30
    a.meta["module"] = {"length": round(Lg, 3), "width": W, "height": H}
    return a


# =============================================================================== HESCO


def hesco(A, aid, cells, cell, height, name):
    """HESCO-type defensive bastion: welded-mesh cage (alpha) around a geotextile liner,
    earth fill 5 cm below the rim, coil hinges at the cell joints. Cells run along X."""
    a = A.Asset(aid, "prop", name, "Defences",
                "%d-cell defensive bastion, cell %.2f x %.2f m, %.2f m high (%.2f m long)." % (cells, cell, cell, height, cells * cell))
    Lx = cells * cell
    x0 = -Lx / 2
    a.box((Lx - 0.02, cell - 0.02, height - 0.01), (0, 0, (height - 0.01) / 2), "Hesco_Liner")
    a.box((Lx - 0.04, cell - 0.04, 0.02), (0, 0, height - 0.06), "Dirt", ALL)
    # Mesh cage: outer skin on all four sides (double-sided alpha) + cell partitions.
    a.box((Lx, cell, height), (0, 0, height / 2), "Hesco_Mesh", L01)
    for i in range(1, cells):
        a.box((0.004, cell - 0.02, height - 0.02), (x0 + i * cell, 0, height / 2), "Hesco_Mesh", L0)
    # Coil hinges (vertical spring pins) at every joint and corner, rim wire.
    for i in range(cells + 1):
        for sy in (-1, 1):
            a.cyl(0.010, 0.010, height, (x0 + i * cell, sy * cell / 2, height / 2), "Steel_Galv", L0, segs=6)
    for sy in (-1, 1):
        a.box((Lx, 0.008, 0.008), (0, sy * cell / 2, height - 0.004), "Steel_Galv", L0)
    a.col_box((Lx, cell, height), (0, 0, height / 2))
    a.marker("SNAP_W", (x0, 0, 0), 90, "next bastion joins here (west end)")
    a.marker("SNAP_E", (-x0, 0, 0), -90, "next bastion joins here (east end)")
    a.ao_height, a.ao_strength = 0.6, 0.30
    a.lod_ranges = [[0, 50], [50, 180], [180, 1200]]
    a.meta["module"] = {"length": Lx, "depth": cell, "height": height, "cells": cells}
    return a


# =============================================================================== sandbags


def A_rot(yaw):
    from mathutils import Matrix
    return Matrix.Rotation(math.radians(yaw), 3, "Z")


def sandbag_wall(A, aid, length, courses, name, mat="Sandbag", double=True):
    """Stacked sandbag wall in stretcher bond, two bags deep (0.64 m). LOD1 one box per
    course, LOD2 a single block."""
    a = A.Asset(aid, "prop", name, "Defences", "Sandbag wall %.1f m long, %d courses (%.2f m high)." % (length, courses, courses * 0.12))
    h = 0.12
    import random
    rnd = random.Random(hash(aid) & 0xFFFF)
    depth_rows = (-0.16, 0.16) if double else (0.0,)
    # WORLD-DETAIL-02: pillow-shaped bags laid tight in running bond (ap_kit.bag_wall), LOD1 the same bags coarser.
    K.bag_wall(a, -length / 2, length / 2, 0.0, courses, rnd, mat, rows=tuple(r * 0.97 for r in depth_rows), lods=(0, 1))
    a.box((length, 0.64 if double else 0.32, courses * h), (0, 0, courses * h / 2), mat, L2)
    a.col_box((length, 0.64 if double else 0.32, courses * h), (0, 0, courses * h / 2))
    a.marker("SNAP_W", (-length / 2, 0, 0), 90)
    a.marker("SNAP_E", (length / 2, 0, 0), -90)
    a.lod_ranges = [[0, 30], [30, 120], [120, 500]]
    a.ao_height, a.ao_strength = 0.5, 0.3
    a.meta["module"] = {"length": length, "height": courses * h}
    return a


def sandbag_single(A):
    a = A.Asset("sandbag_single", "prop", "Sandbag", "Defences", "One filled sandbag 0.60 x 0.32 x 0.13 m.")
    import random
    K.sandbag(a, (0, 0, 0.07), 0.0, "Sandbag", (0, 1), rnd=random.Random(5))
    a.box((0.58, 0.30, 0.12), (0, 0, 0.06), "Sandbag", L2)
    a.col_box((0.60, 0.32, 0.13), (0, 0, 0.065))
    a.lod_ranges = SMALL
    return a


# =============================================================================== concrete


def t_wall(A):
    """T-wall (inverted-T blast wall) segment 1.52 m long, 3.66 m high, base 1.22 m deep,
    lifting loops on top. Runs along X."""
    a = A.Asset("t_wall", "prop", "T-wall blast wall", "Defences",
                "Reinforced concrete T-wall segment: 1.52 m long, 3.66 m high, 0.20-0.30 m stem on a 1.22 x 0.30 m base.")
    Lx, H = 1.52, 3.66
    # Base 1.22 x 0.30 on the ground, stem tapering from 0.30 to 0.20 m (symmetric profile).
    prof = [(-0.61, 0.0), (0.61, 0.0), (0.61, 0.30), (0.15, 0.36), (0.10, H), (-0.10, H), (-0.15, 0.36), (-0.61, 0.30)]
    a.prism(prof, (-Lx / 2, 0, 0), (Lx / 2, 0, 0), "Concrete")
    for sx in (-0.45, 0.45):
        a.tube([(sx - 0.08, 0, H - 0.01), (sx - 0.06, 0, H + 0.10), (sx + 0.06, 0, H + 0.10), (sx + 0.08, 0, H - 0.01)], 0.012, "Steel_Dark", L0, segs=6)
    # Forklift / chain slots at the base (dark recesses).
    for sx in (-0.4, 0.4):
        for sy in (-1, 1):
            a.box((0.20, 0.004, 0.08), (sx, sy * 0.612, 0.12), "Paint_Black", L0)
    a.col_box((Lx, 1.22, 0.30), (0, 0, 0.15))
    a.col_box((Lx, 0.30, H), (0, 0, H / 2))
    a.marker("SNAP_W", (-Lx / 2, 0, 0), 90)
    a.marker("SNAP_E", (Lx / 2, 0, 0), -90)
    a.lod_ranges = [[0, 60], [60, 220], [220, 1500]]
    a.meta["module"] = {"length": Lx, "height": H}
    return a


def jersey_barrier(A):
    """F-shape concrete safety barrier 3.0 m long, 0.81 m high, 0.61 m base, with
    lifting loops and drain slots."""
    a = A.Asset("jersey_barrier", "prop", "Concrete barrier (F-shape)", "Road",
                "F-shape / Jersey concrete barrier, 3.0 x 0.61 x 0.81 m: 75 mm toe, 55 deg and 84 deg faces.")
    Lx = 3.0
    prof = [(-0.305, 0.0), (0.305, 0.0), (0.305, 0.075), (0.21, 0.255), (0.12, 0.81), (-0.12, 0.81), (-0.21, 0.255), (-0.305, 0.075)]
    a.prism(prof, (-Lx / 2, 0, 0), (Lx / 2, 0, 0), "Concrete")
    for sx in (-0.9, 0.9):
        a.tube([(sx - 0.07, 0, 0.80), (sx - 0.05, 0, 0.88), (sx + 0.05, 0, 0.88), (sx + 0.07, 0, 0.80)], 0.010, "Steel_Dark", L0, segs=6)
        for sy in (-1, 1):
            a.box((0.30, 0.004, 0.07), (sx, sy * 0.306, 0.04), "Paint_Black", L0)
    a.col_box((Lx, 0.61, 0.81), (0, 0, 0.405))
    a.marker("SNAP_W", (-Lx / 2, 0, 0), 90)
    a.marker("SNAP_E", (Lx / 2, 0, 0), -90)
    a.lod_ranges = [[0, 40], [40, 150], [150, 800]]
    a.meta["module"] = {"length": Lx, "height": 0.81}
    return a


# =============================================================================== fences


def _fence_post(a, x, h, r=0.030, lods=ALL):
    a.cyl(r, r, h + 0.5, (x, 0, (h - 0.5) / 2), "Steel_Galv", lods, segs=8)
    a.cyl(r + 0.004, r + 0.004, 0.02, (x, 0, h + 0.01), "Steel_Galv", L0, segs=8)


def chainlink_fence(A):
    """Security fence panel 3.0 m: galvanized posts (0.5 m below ground), top rail,
    tension wire, 50 mm chain-link (alpha), Y-arm outriggers with barbed wire."""
    a = A.Asset("chainlink_fence", "prop", "Chain-link fence 3 m", "Fences",
                "Chain-link security fence module 3.0 m x 2.4 m with Y-arm barbed-wire outriggers (top 2.9 m).")
    Lx, H = 3.0, 2.4
    _fence_post(a, -Lx / 2, H, 0.030)
    _fence_post(a, Lx / 2, H, 0.0294)
    a.cyl(0.019, 0.019, Lx, (0, 0, H - 0.05), "Steel_Galv", L01, axis=(1, 0, 0), segs=6)
    a.cyl(0.004, 0.004, Lx, (0, 0, 0.08), "Steel_Galv", L0, axis=(1, 0, 0), segs=4)
    a.poly([(-Lx / 2, 0, 0.05), (Lx / 2, 0, 0.05), (Lx / 2, 0, H - 0.05), (-Lx / 2, 0, H - 0.05)], [(0, 1, 2, 3)], "Chainlink", ALL)
    for x in (-Lx / 2, Lx / 2):
        for sy in (-1, 1):
            a.tube([(x, 0, H), (x, sy * 0.30, H + 0.40)], 0.012, "Steel_Galv", L0, segs=5)
    for sy in (-1, 1):
        for k in range(3):
            t = (k + 1) / 3.0
            a.cyl(0.003, 0.003, Lx, (0, sy * 0.30 * t, H + 0.40 * t), "Steel_Dark", L0, axis=(1, 0, 0), segs=4)
    a.col_box((Lx, 0.08, H), (0, 0, H / 2))
    a.marker("SNAP_W", (-Lx / 2, 0, 0), 90)
    a.marker("SNAP_E", (Lx / 2, 0, 0), -90)
    a.foundation = 0.5
    a.lod_ranges = [[0, 40], [40, 140], [140, 600]]
    a.meta["module"] = {"length": Lx, "height": H}
    return a


def chainlink_gate(A):
    """Double vehicle gate 4.0 m clear opening, closed: welded tube leaves with chain-link
    infill and diagonal brace, heavy hinge posts, drop rod and latch."""
    a = A.Asset("chainlink_gate", "prop", "Chain-link gate 4 m (closed)", "Fences",
                "Double swing gate, 4.0 m clear opening, 2.4 m high, two 2.0 m leaves (closed), hinge posts 0.10 m.")
    H = 2.4
    for sx in (-1, 1):
        a.cyl(0.050, 0.050, H + 0.9, (sx * 2.06, 0, (H - 0.6) / 2 + 0.15), "Steel_Galv", ALL, segs=10)
        a.cyl(0.056, 0.056, 0.02, (sx * 2.06, 0, H + 0.31), "Steel_Galv", L0, segs=10)
        cx = sx * 1.0
        x0, x1 = sx * 0.01, sx * 1.99
        lo, hi = min(x0, x1), max(x0, x1)
        for z in (0.12, H - 0.08):
            a.cyl(0.021, 0.021, 1.98, (cx, 0, z), "Steel_Galv", L01, axis=(1, 0, 0), segs=6)
        for x in (lo, hi):
            a.cyl(0.021, 0.021, H - 0.20, (x, 0, H / 2 + 0.02), "Steel_Galv", L01, segs=6)
        a.cyl_between((lo, 0, 0.15), (hi, 0, H - 0.11), 0.016, "Steel_Galv", L0, segs=6)
        a.poly([(lo, 0, 0.12), (hi, 0, 0.12), (hi, 0, H - 0.08), (lo, 0, H - 0.08)], [(0, 1, 2, 3)], "Chainlink", ALL)
        for z in (0.4, H - 0.4):
            a.box((0.10, 0.06, 0.06), (sx * 2.0, 0, z), "Steel_Dark", L0)
        for sy in (-1, 1):
            a.tube([(sx * 2.06, 0, H + 0.3), (sx * 2.06, sy * 0.30, H + 0.70)], 0.012, "Steel_Galv", L0, segs=5)
    a.cyl(0.012, 0.012, 0.9, (0.06, 0.03, 0.55), "Steel_Dark", L0, segs=6)
    a.box((0.12, 0.05, 0.10), (0.0, 0.03, 1.2), "Steel_Dark", L0)
    a.col_box((4.2, 0.08, H), (0, 0, H / 2))
    a.marker("SNAP_W", (-2.06, 0, 0), 90, "fence joins the west hinge post")
    a.marker("SNAP_E", (2.06, 0, 0), -90, "fence joins the east hinge post")
    a.marker("IP_Gate", (0, 1.5, 0), 180, "open / close the gate")
    a.foundation = 0.6
    a.lod_ranges = [[0, 40], [40, 140], [140, 600]]
    return a


def mesh_fence_temporary(A):
    """Temporary mesh fence panel 3.5 x 2.0 m (Heras type) on two concrete feet."""
    a = A.Asset("mesh_fence_temporary", "prop", "Temporary fence panel", "Fences",
                "Mobile mesh fence panel 3.50 x 2.00 m in tube frame, standing in two concrete-filled feet.")
    Lx, H = 3.5, 2.0
    for x in (-Lx / 2 + 0.02, Lx / 2 - 0.02):
        a.cyl(0.020, 0.020, H, (x, 0, H / 2 + 0.10), "Steel_Galv", L01, segs=6)
        a.box((0.65, 0.20, 0.13), (x, 0, 0.065), "Concrete_Dark", ALL, bevel=0.02)
    for z in (0.12, H + 0.08):
        a.cyl(0.020, 0.020, Lx - 0.04, (0, 0, z), "Steel_Galv", L01, axis=(1, 0, 0), segs=6)
    a.poly([(-Lx / 2 + 0.02, 0, 0.12), (Lx / 2 - 0.02, 0, 0.12), (Lx / 2 - 0.02, 0, H + 0.08), (-Lx / 2 + 0.02, 0, H + 0.08)], [(0, 1, 2, 3)], "Hesco_Mesh", ALL)
    a.col_box((Lx, 0.2, H + 0.1), (0, 0, (H + 0.1) / 2))
    a.marker("SNAP_W", (-Lx / 2, 0, 0), 90)
    a.marker("SNAP_E", (Lx / 2, 0, 0), -90)
    a.lod_ranges = MEDIUM
    return a


# =============================================================================== road barriers


def boom_barrier(A):
    """Checkpoint boom barrier: drive cabinet on a concrete base, 6 m striped arm (closed)
    resting on a fork post."""
    a = A.Asset("boom_barrier", "prop", "Boom barrier 6 m", "Checkpoint",
                "Road boom barrier for a 6 m lane: drive cabinet 0.35 x 0.35 x 1.0 m, 6.0 m red/white arm at 0.9 m, rest post.")
    a.box((0.8, 0.8, 0.20), (0, 0, 0.0), "Concrete", ALL)
    a.box((0.36, 0.36, 1.00), (0, 0, 0.60), "Paint_Yellow", ALL, bevel=0.02)
    a.box((0.40, 0.40, 0.04), (0, 0, 1.12), "Paint_Yellow", L01)
    a.cyl(0.06, 0.06, 0.20, (0.25, 0, 0.92), "Steel_Dark", L01, axis=(1, 0, 0), segs=10)
    n = 12
    for i in range(n):
        x0 = 0.3 + i * 0.5
        a.box((0.5, 0.09, 0.09), (x0 + 0.25, 0, 0.92), "Paint_Red" if i % 2 == 0 else "Paint_White", L01, bevel=0.01)
    a.box((6.0, 0.09, 0.09), (3.3, 0, 0.92), "Paint_White", L2)
    a.box((0.15, 0.03, 0.15), (0.4, 0.05, 0.92), "Reflector_Red", L0)
    a.cyl(0.04, 0.04, 0.85, (6.15, 0, 0.42), "Paint_White", L01, segs=8)
    a.box((0.20, 0.12, 0.06), (6.15, 0, 0.86), "Rubber", L0)
    a.box((0.5, 0.5, 0.15), (6.15, 0, 0.0), "Concrete", L01)
    a.box((0.06, 0.06, 0.4), (-0.12, 0.2, 1.0), "Lamp", L0)
    a.col_box((0.4, 0.4, 1.1), (0, 0, 0.55))
    a.col_box((6.0, 0.10, 0.10), (3.3, 0, 0.92))
    a.marker("IP_Control", (-0.6, 0.6, 0), 135, "operator position")
    a.marker("VEH_Stop", (3.3, 4.0, 0), 180, "vehicle stops here (lane centre)")
    a.foundation = 0.1
    a.lod_ranges = MEDIUM
    return a


def water_barrier(A):
    """Plastic water-filled road barrier 2.0 x 0.5 x 1.0 m, interlocking ends."""
    a = A.Asset("water_barrier", "prop", "Water-filled barrier", "Road", "Plastic water-filled barrier 2.0 x 0.5 x 1.0 m (red/white alternating).")
    prof = [(-0.25, 0.0), (0.25, 0.0), (0.25, 0.12), (0.16, 0.30), (0.10, 1.0), (-0.10, 1.0), (-0.16, 0.30), (-0.25, 0.12)]
    a.prism(prof, (-0.95, 0, 0), (0.95, 0, 0), "Plastic_Orange")
    a.box((1.2, 0.205, 0.22), (0, 0, 0.88), "Plastic_White", L01)
    for sx in (-1, 1):
        a.cyl(0.07, 0.07, 0.8, (sx * 0.98, 0, 0.45), "Plastic_Orange", L01, segs=10)
    a.cyl(0.05, 0.05, 0.04, (0, 0, 1.01), "Plastic_Black", L0, segs=10)
    a.col_box((2.0, 0.5, 1.0), (0, 0, 0.5))
    a.marker("SNAP_W", (-1.0, 0, 0), 90)
    a.marker("SNAP_E", (1.0, 0, 0), -90)
    a.lod_ranges = MEDIUM
    return a


def traffic_cone(A):
    a = A.Asset("traffic_cone", "prop", "Traffic cone", "Road", "Traffic cone 0.75 m with reflective bands.")
    a.box((0.38, 0.38, 0.04), (0, 0, 0.02), "Plastic_Black", ALL, bevel=0.01)
    a.cyl(0.15, 0.025, 0.71, (0, 0, 0.395), "Plastic_Orange", ALL, segs=14)
    a.cyl(0.115, 0.095, 0.10, (0, 0, 0.36), "Plastic_White", L0, segs=14)
    a.cyl(0.075, 0.058, 0.07, (0, 0, 0.56), "Plastic_White", L0, segs=14)
    a.col_box((0.38, 0.38, 0.75), (0, 0, 0.375))
    a.lod_ranges = SMALL
    return a


def guard_booth(A):
    """Prefabricated steel guard booth 1.6 x 1.6 m: windows on all sides, door, roof
    overhang, AC unit, lamp, raised floor on a concrete plinth."""
    a = A.Asset("guard_booth", "prop", "Guard booth", "Checkpoint",
                "Steel sentry booth 1.6 x 1.6 m, 2.6 m high on a 0.15 m plinth, wrap-around windows, door at the back.")
    w = 1.6
    a.skirt(-w / 2 - 0.1, -w / 2 - 0.1, w / 2 + 0.1, w / 2 + 0.1, 0.3, "Concrete", top=0.15)
    a.box_between((-w / 2, -w / 2, 0.15), (w / 2, w / 2, 2.55), "Paint_OD")
    a.box_between((-w / 2 - 0.2, -w / 2 - 0.2, 2.55), (w / 2 + 0.2, w / 2 + 0.2, 2.68), "Paint_OD")
    for yaw, wx in ((0, 0.0), (90, 0.0), (-90, 0.0)):
        F = Frame(K.Frame((0, 0, 0), yaw).p(0, w / 2, 0.15), yaw)
        K.window(a, F, wx, 1.55, 1.3, 0.9, bars=False, frame="Paint_Black", sill=False)
    Fb = Frame((0, -w / 2, 0.15), 180)
    K.door(a, Fb, 0, w=0.8, h=2.0, leaf="Paint_OD", light=False)
    K.wall_light(a, Frame((0, w / 2, 0.15), 0), 0.0, 2.25)
    a.col_between((-w / 2, -w / 2, -0.3), (w / 2, w / 2, 2.68))
    a.marker("IP_Door", (0, -w / 2 - 0.8, 0), 0, "booth door")
    a.marker("IP_Guard", (0, 0, 0.15), 0, "guard stands inside, facing the lane")
    a.lod_ranges = MEDIUM
    a.structure = {"category": "Checkpoint", "max_slope_deg": 8.0, "blocks_navigation": True}
    return a


BUILDERS = {
    "iso_container_20_od": lambda A: iso_container(A, "iso_container_20_od", FT20, "Container_OD", "20 ft container (olive)"),
    "iso_container_20_tan": lambda A: iso_container(A, "iso_container_20_tan", FT20, "Container_Tan", "20 ft container (tan)"),
    "iso_container_20_blue": lambda A: iso_container(A, "iso_container_20_blue", FT20, "Container_Blue", "20 ft container (blue)"),
    "iso_container_20_rust": lambda A: iso_container(A, "iso_container_20_rust", FT20, "Container_Rust", "20 ft container (red)"),
    "iso_container_40_od": lambda A: iso_container(A, "iso_container_40_od", FT40, "Container_OD", "40 ft container (olive)"),
    "iso_container_40_tan": lambda A: iso_container(A, "iso_container_40_tan", FT40, "Container_Tan", "40 ft container (tan)"),
    "hesco_mil1_1": lambda A: hesco(A, "hesco_mil1_1", 1, 1.06, 1.37, "HESCO cell 1.37 m"),
    "hesco_mil1_5": lambda A: hesco(A, "hesco_mil1_5", 5, 1.06, 1.37, "HESCO wall 5.3 m (1.37 m)"),
    "hesco_mil7_2": lambda A: hesco(A, "hesco_mil7_2", 2, 2.13, 2.21, "HESCO wall 4.3 m (2.21 m)"),
    "sandbag_single": sandbag_single,
    "sandbag_wall_2m": lambda A: sandbag_wall(A, "sandbag_wall_2m", 2.0, 8, "Sandbag wall 2 m (1.0 m)"),
    "sandbag_wall_low_2m": lambda A: sandbag_wall(A, "sandbag_wall_low_2m", 2.0, 5, "Sandbag wall 2 m (0.6 m)"),
    "sandbag_wall_green_2m": lambda A: sandbag_wall(A, "sandbag_wall_green_2m", 2.0, 8, "Sandbag wall 2 m (green)", "Sandbag_Green"),
    "t_wall": t_wall,
    "jersey_barrier": jersey_barrier,
    "chainlink_fence": chainlink_fence,
    "chainlink_gate": chainlink_gate,
    "mesh_fence_temporary": mesh_fence_temporary,
    "boom_barrier": boom_barrier,
    "water_barrier": water_barrier,
    "traffic_cone": traffic_cone,
    "guard_booth": guard_booth,
}
