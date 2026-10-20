"""Modular base expansions (ASSET-PRODUCTION-01): independently placeable installations.

Shooting range (firing point, target line, backstop berm, control tower), obstacle
course elements, tactical training (shoot house, MOUT wall), vehicle training (incline
ramp, parking pad), open repair bay, container storage area, fuel storage (bladder berm,
fuel point), ammunition storage magazine, communications lattice tower, guard
checkpoint, defensive fighting positions.

Each module is a visual / collision asset with markers; what it does for training,
capacity, repairs or logistics is up to the gameplay systems (not implemented here).
Front = +Y, origin on the ground at the footprint centre.
"""
import math
import random

import ap_kit as K
import ap_signs as S
from ap_kit import Frame

ALL = (0, 1, 2)
L01 = (0, 1)
L0 = (0,)
L12 = (1, 2)
L2 = (2,)


def _st(cat="Base modules", slope=8.0, gap=None, nav=True):
    s = {"category": cat, "max_slope_deg": slope, "blocks_navigation": nav}
    if gap is not None:
        s["max_ground_gap"] = gap
    return s


def _sandbag_row(a, x0, x1, y, courses, lods=L0, seed=1, mat="Sandbag", along="x"):
    """A sandbag wall along X (or Y) on LOD0, one block on LOD1/2."""
    rnd = random.Random(seed)
    n = max(1, int(abs(x1 - x0) / 0.6))
    step = (x1 - x0) / n
    for k in range(courses):
        off = 0.3 if k % 2 else 0.0
        for i in range(n):
            c = x0 + (i + 0.5) * step + (off if i < n - 1 else 0)
            p = (c, y, 0.065 + k * 0.12) if along == "x" else (y, c, 0.065 + k * 0.12)
            sc = (abs(step) / 2 - 0.005, 0.165, 0.074) if along == "x" else (0.165, abs(step) / 2 - 0.005, 0.074)
            a.sphere(1.0, p, mat, lods, scale=sc, segs=8, rings=4)
    lo = (min(x0, x1), y - 0.17, 0) if along == "x" else (y - 0.17, min(x0, x1), 0)
    hi = (max(x0, x1), y + 0.17, courses * 0.12) if along == "x" else (y + 0.17, max(x0, x1), courses * 0.12)
    a.box_between(lo, hi, mat, L12)


# =============================================================================== shooting range


def range_firing_point(A):
    """Covered firing point for 6 lanes (2.5 m each): roof on posts, concrete firing
    slab, shooting mats, low sandbag rests, lane number boards, range flag pole."""
    a = A.Asset("range_firing_point", "module", "Range firing point (6 lanes)", "Training",
                "Covered rifle firing point, 6 lanes x 2.5 m (15 m), 4 m deep roof, firing slab, lane boards and range flag.")
    W, D = 15.0, 4.0
    a.skirt(-W / 2, -D / 2, W / 2, D / 2 + 1.0, 0.3, "Concrete", top=0.10)
    for x in (-W / 2 + 0.1, 0.0, W / 2 - 0.1):
        for y in (-D / 2 + 0.1, D / 2 - 0.1):
            a.box((0.15, 0.15, 2.8), (x, y, 1.5), "Paint_OD", ALL)
    K.mono_roof(a, -W / 2, -D / 2, W / 2, D / 2, 2.9, 3.2, overhang=0.3, mat="Roof_OD", low_side="+y")
    for i in range(6):
        x = -W / 2 + 1.25 + i * 2.5
        a.box((0.9, 1.9, 0.02), (x, 0.3, 0.11), "Canvas_Green", L01)
        _sandbag_row(a, x - 0.6, x + 0.6, D / 2 + 0.6, 3, seed=i)
        if i < 4:
            a.sign(A.RECT01, (x, D / 2 + 0.95, 0.85), (-1, 0, 0), (0, 0, 1), 0.4, 0.4, S.rect("lane_%d" % (i + 1)), lods=L01,
                   back_mat="Steel_Galv", thick=0.01)
        a.cyl(0.02, 0.02, 0.6, (x, D / 2 + 0.95, 0.35), "Steel_Galv", L0, segs=5)
    # Range flag pole with a red flag, and the live-fire board.
    a.cyl(0.04, 0.03, 7.0, (W / 2 + 1.0, D / 2, 3.5), "Steel_Galv", ALL, segs=8)
    a.box((0.02, 1.2, 0.8), (W / 2 + 1.0, D / 2 + 0.62, 6.5), "Paint_Red", L01)
    Frame((-W / 2 + 0.1, -D / 2 - 0.05, 0.1), 180).sign(a, "plate_range", 0, 1.8, 1.4, 0.7, back="Paint_Grey")
    a.col_between((-W / 2, -D / 2, -0.3), (W / 2, D / 2 + 1.0, 0.10))
    for x in (-W / 2 + 0.1, 0.0, W / 2 - 0.1):
        for y in (-D / 2 + 0.1, D / 2 - 0.1):
            a.col_box((0.15, 0.15, 2.8), (x, y, 1.5))
    for i in range(6):
        a.marker("IP_Lane_%d" % (i + 1), (-W / 2 + 1.25 + i * 2.5, 0.5, 0.10), 0, "firing position, faces down range (+Y)")
    a.marker("ATT_DownRange", (0, D / 2 + 25.0, 0), 0, "first target line (25 m); place range_target_line along +Y")
    a.marker("ATT_Tower", (-W / 2 - 4.0, -D / 2 - 2.0, 0), 0, "range control tower")
    a.structure = _st("Training", 5.0, 0.4)
    a.meta["lanes"] = 6
    return a


def range_target_line(A):
    """Target line for 6 lanes: Figure 11 targets on timber frames behind a low earth
    berm that protects the target mechanisms, distance board."""
    a = A.Asset("range_target_line", "module", "Range target line (6 lanes)", "Training",
                "Target line 15 m wide: six 0.5 x 1.0 m silhouette targets on timber frames, 0.8 m protective earth berm, distance board.")
    W = 15.0
    a.prism([(-1.2, 0.0), (1.2, 0.0), (0.4, 0.8), (-0.4, 0.8)], (-W / 2 - 0.5, 0, 0), (W / 2 + 0.5, 0, 0), "Dirt", ALL)
    for i in range(6):
        x = -W / 2 + 1.25 + i * 2.5
        for dx in (-0.3, 0.3):
            a.box((0.06, 0.06, 1.9), (x + dx, -0.9, 0.95), "Timber", L01)
        a.box((0.7, 0.04, 0.06), (x, -0.9, 0.55), "Timber", L0)
        a.sign(A.RECT01, (x, -0.88, 1.35), (-1, 0, 0), (0, 0, 1), 0.5, 1.0, S.rect("target_fig11"), lods=ALL, back_mat="Plywood", thick=0.01)
    Frame((W / 2 + 1.0, 0.8, 0), 0).sign(a, "range_100", 0, 1.4, 0.8, 0.8, back="Steel_Galv")
    a.cyl(0.03, 0.03, 1.4, (W / 2 + 1.0, 0.79, 0.7), "Steel_Galv", L01, segs=6)
    a.col_box((W + 1.0, 2.4, 0.8), (0, 0, 0.4))
    for i in range(6):
        a.marker("IP_Target_%d" % (i + 1), (-W / 2 + 1.25 + i * 2.5, -0.9, 1.35), 180, "target centre (faces the firing point, -Y)")
    a.lod_ranges = [[0, 60], [60, 240], [240, 1200]]
    a.structure = _st("Training", 8.0, 0.3)
    return a


def range_backstop(A):
    """Earth backstop berm 20 m long, 4 m high with timber bullet-catch face."""
    a = A.Asset("range_backstop", "module", "Range backstop berm", "Training",
                "Earth backstop berm 20 m x 8 m base, 4 m high, behind the target lines (impact face toward -Y).")
    L = 20.0
    a.prism([(-4.0, -0.2), (4.0, -0.2), (1.2, 4.0), (-1.2, 4.0)], (-L / 2, 0, 0), (L / 2, 0, 0), "Dirt", ALL)
    for sx in (-1, 1):
        a.prism([(-4.0, -0.2), (4.0, -0.2), (1.2, 4.0), (-1.2, 4.0)], (sx * L / 2, 0, 0), (sx * (L / 2 + 0.01), 0, 0), "Dirt", ALL)
    for i in range(10):
        a.box((1.9, 0.12, 2.0), (-L / 2 + 1.0 + i * 2.0, -2.25, 1.4), "Timber_Dark", L01, rot=A.rot_x(-34))
    a.col_box((L, 8.0, 4.0), (0, 0, 2.0))
    a.lod_ranges = [[0, 80], [80, 320], [320, 2000]]
    a.structure = _st("Training", 10.0, 1.0)
    return a


def range_tower(A):
    """Range control tower: 2.5 x 2.5 m cabin at 3 m on steel legs, windows all round,
    external stair, loudspeakers."""
    a = A.Asset("range_tower", "module", "Range control tower", "Training",
                "Range control tower: 2.5 x 2.5 m cabin, floor 3.0 m, glazing on all sides, stair, PA loudspeakers.")
    c, fl = 2.5, 3.0
    for sx in (-1, 1):
        for sy in (-1, 1):
            a.box((0.5, 0.5, 0.25), (sx * 1.05, sy * 1.05, 0.0), "Concrete", ALL)
            a.box((0.12, 0.12, fl), (sx * 1.05, sy * 1.05, fl / 2), "Paint_White", ALL)
    a.box((c + 0.3, c + 0.3, 0.12), (0, 0, fl), "Steel_Dark", ALL)
    a.box_between((-c / 2, -c / 2, fl + 0.06), (c / 2, c / 2, fl + 2.4), "Paint_White")
    for k in range(4):
        F = Frame(Frame((0, 0, 0), 90 * k).p(0, c / 2, fl + 0.06), 90 * k)
        F.box(a, (c - 0.3, 0.03, 1.0), 0, 0.0, 1.45, "Glass", ALL)
    a.box_between((-c / 2 - 0.3, -c / 2 - 0.3, fl + 2.4), (c / 2 + 0.3, c / 2 + 0.3, fl + 2.52), "Paint_Red")
    for sx in (-1, 1):
        a.box((0.3, 0.25, 0.3), (sx * 0.9, c / 2 + 0.2, fl + 2.75), "Paint_Grey", L01, rot=A.rot_x(-15))
    for k in range(10):
        t = (k + 0.5) / 10
        a.box((0.8, 0.24, 0.04), (c / 2 + 0.5, -1.4 + t * 2.4, 0.1 + t * (fl - 0.1)), "Steel_Dark", L01)
    for sx in (c / 2 + 0.1, c / 2 + 0.9):
        a.cyl_between((sx, -1.4, 0.05), (sx, 1.0, fl), 0.03, "Paint_White", L01, segs=6)
    a.col_between((-1.2, -1.2, -0.25), (1.2, 1.2, fl + 2.5))
    a.marker("IP_Stair", (c / 2 + 0.5, -2.0, 0), 0)
    a.marker("IP_Officer", (0, 0, fl + 0.06), 0, "range officer, overlooks the firing point (+Y)")
    a.structure = _st("Training", 8.0, 0.4)
    return a


# =============================================================================== obstacle course


def obstacle_wall(A):
    a = A.Asset("obstacle_wall", "module", "Obstacle: climbing wall", "Training", "Timber climbing wall 3.0 m wide x 2.1 m high with foot boards.")
    for x in (-1.45, 1.45):
        a.box((0.15, 0.15, 2.7), (x, 0, 1.05), "Timber_Dark", ALL)
    for k in range(8):
        a.box((2.9, 0.05, 0.25), (0, 0.06, 0.15 + k * 0.255), "Timber", ALL)
    for sy in (-1, 1):
        a.box((2.6, 0.08, 0.08), (0, sy * 0.3, 0.6), "Timber_Dark", L0)
    a.col_box((3.0, 0.2, 2.1), (0, 0, 1.05))
    a.foundation = 0.3
    a.marker("IP_Approach", (0, 2.0, 0), 180)
    a.lod_ranges = [[0, 40], [40, 140], [140, 600]]
    a.structure = _st("Training", 10.0, 0.3)
    return a


def obstacle_balance(A):
    a = A.Asset("obstacle_balance", "module", "Obstacle: balance logs", "Training", "Three balance logs 5 m long at 0.4 / 0.7 / 1.0 m on timber posts.")
    for i, h in enumerate((0.4, 0.7, 1.0)):
        x = (i - 1) * 1.2
        a.cyl(0.10, 0.10, 5.0, (x, 0, h), "Timber_Dark", ALL, axis=(0, 1, 0), segs=10)
        for y in (-2.3, 0.0, 2.3):
            a.box((0.14, 0.14, h + 0.4), (x, y, (h - 0.4) / 2), "Timber", L01)
    a.col_box((2.8, 5.0, 1.1), (0, 0, 0.55))
    a.lod_ranges = [[0, 40], [40, 140], [140, 600]]
    a.structure = _st("Training", 10.0, 0.3, nav=False)
    return a


def obstacle_crawl(A):
    a = A.Asset("obstacle_crawl", "module", "Obstacle: low crawl wire", "Training", "Low-crawl lane 3 x 8 m: wire grid at 0.5 m on short pickets.")
    for x in (-1.5, -0.5, 0.5, 1.5):
        for k in range(9):
            y = -4.0 + k
            a.cyl(0.015, 0.015, 0.6, (x, y, 0.2), "Steel_Dark", L01, segs=5)
    for x in (-1.5, -0.5, 0.5, 1.5):
        a.cyl(0.004, 0.004, 8.0, (x, 0, 0.5), "Steel_Dark", L0, axis=(0, 1, 0), segs=4)
    for k in range(9):
        a.cyl(0.004, 0.004, 3.0, (0, -4.0 + k, 0.5), "Steel_Dark", L0, axis=(1, 0, 0), segs=4)
    a.box((3.2, 8.2, 0.03), (0, 0, 0.0), "Dirt", ALL)
    a.lod_ranges = [[0, 40], [40, 140], [140, 600]]
    a.structure = _st("Training", 10.0, 0.3, nav=False)
    return a


def obstacle_tires(A):
    a = A.Asset("obstacle_tires", "module", "Obstacle: tyre run", "Training", "Tyre run: 2 x 8 truck tyres laid flat, 6 m long.")
    for i in range(8):
        for sx in (-0.45, 0.45):
            y = -2.8 + i * 0.8
            a.cyl(0.38, 0.38, 0.22, (sx + (0.1 if i % 2 else 0), y, 0.11), "Rubber", ALL, segs=14)
            a.cyl(0.22, 0.22, 0.23, (sx + (0.1 if i % 2 else 0), y, 0.115), "Dirt", L01, segs=12)
    a.lod_ranges = [[0, 40], [40, 140], [140, 600]]
    a.structure = _st("Training", 10.0, 0.3, nav=False)
    return a


def obstacle_net(A):
    """A-frame cargo net climb 4.5 m high, 3 m wide."""
    a = A.Asset("obstacle_net", "module", "Obstacle: cargo net A-frame", "Training", "Timber A-frame 4.5 m high with cargo nets on both faces.")
    H = 4.5
    for x in (-1.5, 1.5):
        for sy in (-1, 1):
            a.cyl_between((x, sy * 1.8, 0), (x, 0, H), 0.09, "Timber_Dark", ALL, segs=8)
    a.cyl(0.09, 0.09, 3.2, (0, 0, H), "Timber_Dark", ALL, axis=(1, 0, 0), segs=8)
    for sy in (-1, 1):
        for k in range(10):
            t = (k + 0.5) / 10
            a.cyl_between((-1.4, sy * 1.8 * (1 - t), H * t), (1.4, sy * 1.8 * (1 - t), H * t), 0.012, "Canvas_Tan", L0, segs=4)
        for k in range(8):
            x = -1.4 + k * 0.4
            a.cyl_between((x, sy * 1.75, 0.05), (x, 0.0, H - 0.05), 0.012, "Canvas_Tan", L0, segs=4)
        a.poly([(-1.4, sy * 1.8, 0.0), (1.4, sy * 1.8, 0.0), (1.4, 0, H), (-1.4, 0, H)], [(0, 1, 2, 3)] if sy > 0 else [(3, 2, 1, 0)], "Hesco_Mesh", L12)
    a.col_box((3.2, 0.3, H), (0, 0, H / 2))
    a.lod_ranges = [[0, 50], [50, 180], [180, 800]]
    a.structure = _st("Training", 10.0, 0.3)
    return a


def obstacle_monkey_bars(A):
    a = A.Asset("obstacle_monkey_bars", "module", "Obstacle: monkey bars", "Training", "Steel monkey bars 4 m long, 2.2 m high.")
    for y in (-2.0, 2.0):
        for x in (-0.4, 0.4):
            a.cyl(0.04, 0.04, 2.6, (x, y, 1.0), "Paint_Grey", ALL, segs=8)
    for x in (-0.4, 0.4):
        a.cyl(0.03, 0.03, 4.0, (x, 0, 2.2), "Paint_Grey", L01, axis=(0, 1, 0), segs=8)
    for k in range(13):
        a.cyl(0.018, 0.018, 0.8, (0, -1.8 + k * 0.3, 2.21), "Steel_Galv", L0, axis=(1, 0, 0), segs=6)
    a.col_box((0.9, 4.1, 2.25), (0, 0, 1.12))
    a.foundation = 0.3
    a.lod_ranges = [[0, 40], [40, 140], [140, 600]]
    a.structure = _st("Training", 10.0, 0.3)
    return a


# =============================================================================== tactical training


def shoot_house(A):
    """Close-quarters shoot house 12 x 9 m: plywood-on-timber walls 2.4 m, no roof
    (catwalk observation from above in reality), four rooms, corridor, doorways."""
    a = A.Asset("shoot_house", "module", "Shoot house (CQB)", "Training",
                "Close-quarters battle house 12 x 9 m, 2.4 m plywood walls on timber framing, four rooms, corridor, open top, "
                "observation catwalk.")
    W, D, H, t = 12.0, 9.0, 2.4, 0.12
    walls = [  # (x0, y0, x1, y1) segments; gaps are doorways
        (-6, -4.5, -1.0, -4.5), (0.0, -4.5, 6, -4.5),                 # back wall with rear door
        (-6, 4.5, -0.6, 4.5), (0.6, 4.5, 6, 4.5),                     # front wall with entrance
        (-6, -4.5, -6, 4.5), (6, -4.5, 6, 4.5),
        (-6, 0.6, -3.6, 0.6), (-2.6, 0.6, -1.2, 0.6), (1.2, 0.6, 2.6, 0.6), (3.6, 0.6, 6, 0.6),   # corridor north side
        (-6, -1.2, -3.6, -1.2), (-2.6, -1.2, -1.2, -1.2), (1.2, -1.2, 2.6, -1.2), (3.6, -1.2, 6, -1.2),
        (-1.2, 0.6, -1.2, 4.5), (1.2, 0.6, 1.2, 4.5), (-1.2, -4.5, -1.2, -1.2), (1.2, -4.5, 1.2, -1.2),
    ]
    a.box_between((-W / 2 - 0.3, -D / 2 - 0.3, -0.3), (W / 2 + 0.3, D / 2 + 0.3, 0.05), "Concrete", ALL)
    for x0, y0, x1, y1 in walls:
        if abs(x1 - x0) > abs(y1 - y0):
            a.box_between((min(x0, x1), y0 - t / 2, 0.05), (max(x0, x1), y0 + t / 2, H), "Plywood")
        else:
            a.box_between((x0 - t / 2, min(y0, y1), 0.05), (x0 + t / 2, max(y0, y1), H), "Plywood")
    for x in (-6, -3, 0, 3, 6):
        for y in (-4.5, 4.5):
            a.box((0.14, 0.14, H + 0.05), (x, y, H / 2), "Timber", L0)
    a.box_between((-W / 2, -0.05, H + 0.6), (W / 2, 0.05 + 0.6, H + 0.68), "Steel_Dark", L01)
    for x in (-6, 0, 6):
        a.box((0.10, 0.10, H + 0.7), (x, 0.3, (H + 0.7) / 2), "Steel_Dark", L01)
    for x0, y0, x1, y1 in walls:
        lo = (min(x0, x1) - t / 2, min(y0, y1) - t / 2, 0)
        hi = (max(x0, x1) + t / 2, max(y0, y1) + t / 2, H)
        a.col_between(lo, hi)
    a.marker("IP_Entry", (0, D / 2 + 1.5, 0), 180, "stack-up point at the front entrance")
    a.marker("IP_Rear_Entry", (-0.5, -D / 2 - 1.5, 0), 0)
    for k, (x, y) in enumerate(((-3.6, 2.5), (3.6, 2.5), (-3.6, -2.8), (3.6, -2.8))):
        a.marker("IP_Room_%d" % (k + 1), (x, y, 0.05), 0, "room centre (target placement)")
    a.structure = _st("Training", 5.0, 0.4)
    return a


def mout_wall(A, aid="mout_wall_window", kind="window"):
    """MOUT training wall section 4 m x 2.6 m, concrete block, with a window or door
    opening (freely placeable to build practice streets)."""
    a = A.Asset(aid, "module", "MOUT wall (%s)" % kind, "Training", "Concrete-block urban training wall 4.0 x 0.2 x 2.6 m with a %s opening." % kind)
    L, H, t = 4.0, 2.6, 0.2
    if kind == "window":
        a.box_between((-L / 2, -t / 2, 0), (L / 2, t / 2, 0.9), "Concrete_Block")
        a.box_between((-L / 2, -t / 2, 2.0), (L / 2, t / 2, H), "Concrete_Block")
        a.box_between((-L / 2, -t / 2, 0.9), (-0.6, t / 2, 2.0), "Concrete_Block")
        a.box_between((0.6, -t / 2, 0.9), (L / 2, t / 2, 2.0), "Concrete_Block")
        a.box((1.24, t + 0.04, 0.06), (0, 0, 0.87), "Concrete", L01)
    else:
        a.box_between((-L / 2, -t / 2, 0), (-0.5, t / 2, H), "Concrete_Block")
        a.box_between((0.5, -t / 2, 0), (L / 2, t / 2, H), "Concrete_Block")
        a.box_between((-0.5, -t / 2, 2.1), (0.5, t / 2, H), "Concrete_Block")
    a.box((L + 0.04, t + 0.06, 0.08), (0, 0, H + 0.04), "Concrete", L01)
    a.col_box((L, t, H), (0, 0, H / 2))
    a.marker("SNAP_W", (-L / 2, 0, 0), 90)
    a.marker("SNAP_E", (L / 2, 0, 0), -90)
    a.lod_ranges = [[0, 50], [50, 200], [200, 1000]]
    a.structure = _st("Training", 6.0, 0.4)
    return a


# =============================================================================== vehicle training / maintenance


def vehicle_ramp(A):
    """Vehicle training incline: concrete ramp 4 m wide, 30 % up, 3 m flat top, 30 % down
    (total 17 m), side kerbs."""
    a = A.Asset("vehicle_ramp", "module", "Vehicle incline ramp (30 %)", "Vehicle training",
                "Concrete driver-training ramp 4 m wide: 30 % climb to 2.1 m, 3 m level top, 30 % descent (17 m long).")
    h, run, top, w = 2.1, 7.0, 3.0, 4.0
    y0 = -(run + top / 2)
    prof = [(y0, 0), (-top / 2, h), (top / 2, h), (-y0, 0)]
    pts = []
    for sx in (-w / 2, w / 2):
        pts += [(sx, y, z) for y, z in prof]
    a.poly(pts, [(0, 1, 5, 4)[::-1], (1, 2, 6, 5)[::-1], (2, 3, 7, 6)[::-1], (0, 3, 2, 1), (4, 5, 6, 7)], "Concrete")
    for sx in (-1, 1):
        x = sx * (w / 2 + 0.1)
        pts = [(x - 0.1, y, z) for y, z in prof] + [(x + 0.1, y, z + 0.25) for y, z in prof]
        kb = [(x - 0.1, prof[0][0], 0), (x + 0.1, prof[0][0], 0)]
        a.poly([(x - 0.1, y, z + 0.25) for y, z in prof] + [(x + 0.1, y, z + 0.25) for y, z in prof],
               [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6)], "Paint_Yellow", L01)
    a.box_between((-w / 2 - 0.2, -top / 2, -0.4), (w / 2 + 0.2, top / 2, h), "Concrete", ALL)
    a.col_box((w, top, h), (0, 0, h / 2))
    a.structure = _st("Vehicle training", 4.0, 0.6, nav=False)
    a.structure["ramps_godot"] = [[-w / 2, 0, top / 2, w, h, run], [-w / 2, 0, -top / 2 - run, w, h, run]]
    a.marker("VEH_Start", (0, y0 - 6.0, 0), 0, "vehicle starts the climb northbound (+Y)")
    a.marker("VEH_End", (0, -y0 + 6.0, 0), 0)
    return a


def vehicle_parking_pad(A):
    """Concrete hardstanding 24 x 14 m with six marked bays (4 x 8 m) and wheel stops."""
    a = A.Asset("vehicle_parking_pad", "module", "Vehicle parking pad", "Vehicle training",
                "Concrete vehicle park 24 x 14 m, six 4 x 8 m bays with yellow lines and wheel stops, drive lane in front.")
    W, D = 24.0, 14.0
    a.box_between((-W / 2, -D / 2, -0.3), (W / 2, D / 2, 0.08), "Concrete", ALL)
    for i in range(7):
        x = -W / 2 + i * 4.0
        a.box_between((x - 0.05, -D / 2 + 0.3, 0.08), (x + 0.05, -D / 2 + 8.3, 0.085), "Paint_Yellow", L01)
    for i in range(6):
        x = -W / 2 + 2.0 + i * 4.0
        a.box((1.8, 0.2, 0.12), (x, -D / 2 + 0.8, 0.14), "Concrete_Dark", L0)
    a.box_between((-W / 2 + 0.3, -D / 2 + 8.5, 0.08), (W / 2 - 0.3, -D / 2 + 8.6, 0.085), "Paint_White", L01)
    for i in range(6):
        a.marker("VEH_Bay_%d" % (i + 1), (-W / 2 + 2.0 + i * 4.0, -D / 2 + 4.5, 0.08), 180, "parked vehicle, nose to the wheel stop")
    a.lod_ranges = [[0, 60], [60, 250], [250, 1500]]
    a.structure = _st("Vehicle training", 3.0, 0.3, nav=False)
    return a


def repair_bay(A):
    """Open vehicle repair bay: steel portal frame 10 x 14 m, 6 m clear, roof only,
    inspection pit, gantry crane beam with chain hoist, tool cabinets."""
    a = A.Asset("repair_bay", "module", "Vehicle repair bay (open)", "Maintenance",
                "Open maintenance shelter 10 x 14 m, 6.0 m clear height, inspection pit 1 x 6 m, 5 t gantry beam and hoist.")
    W, D, H = 10.0, 14.0, 6.0
    a.box_between((-W / 2 - 0.5, -D / 2 - 0.5, -0.3), (W / 2 + 0.5, D / 2 + 0.5, 0.1), "Concrete", ALL)
    for y in (-D / 2, -D / 6 * 1.0, D / 6, D / 2):
        for sx in (-1, 1):
            a.box((0.25, 0.25, H), (sx * W / 2, y, H / 2), "Paint_OD", ALL)
        a.box((W + 0.25, 0.25, 0.4), (0, y, H + 0.2), "Paint_OD", L01)
    K.gable_roof(a, -W / 2, -D / 2, W / 2, D / 2, H + 0.4, 10, overhang=0.5, mat="Roof_OD", ridge_axis="y")
    a.box_between((-0.5, -3.0, 0.1), (0.5, 3.0, 0.102), "Paint_Black", ALL)
    for sx in (-0.55, 0.55):
        a.box((0.1, 6.2, 0.06), (sx, 0, 0.13), "Paint_Yellow", L01)
    a.box((0.3, D, 0.4), (0, 0, H - 0.3), "Paint_Yellow", L01)
    a.box((0.35, 0.35, 0.5), (0, 1.0, H - 0.8), "Paint_Yellow", L0)
    a.cyl(0.01, 0.01, 2.5, (0, 1.0, H - 2.3), "Steel_Dark", L0, segs=4)
    for k in range(3):
        a.box((0.6, 1.2, 1.0), (W / 2 - 0.5, -D / 2 + 2.0 + k * 1.3, 0.6), "Paint_Red", L01, bevel=0.02)
    a.box((2.0, 0.8, 0.9), (-W / 2 + 0.6, -D / 2 + 3.0, 0.55), "Steel_Dark", L01)
    for y in (-D / 2, -D / 6, D / 6, D / 2):
        for sx in (-1, 1):
            a.col_box((0.25, 0.25, H), (sx * W / 2, y, H / 2))
    a.col_between((-W / 2 - 0.5, -D / 2 - 0.5, -0.3), (W / 2 + 0.5, D / 2 + 0.5, 0.1))
    a.marker("VEH_Pit", (0, 0, 0.1), 0, "vehicle over the inspection pit, nose +Y")
    a.marker("VEH_Bay_2", (3.0, 0, 0.1), 0, "second vehicle position")
    a.marker("IP_Tools", (W / 2 - 1.5, -D / 2 + 3.3, 0.1), -90)
    a.structure = _st("Maintenance", 4.0, 0.5, nav=False)
    return a


# =============================================================================== storage areas


def container_yard(A):
    """Container storage area: 28 x 16 m gravel pad with kerbs, six 20 ft containers
    (two stacked), floodlight poles and a forklift lane."""
    a = A.Asset("container_yard", "module", "Container storage area", "Logistics",
                "Gravel storage yard 28 x 16 m with six 20 ft containers (two rows, partly double-stacked), kerbs and two light poles.")
    W, D = 28.0, 16.0
    a.box_between((-W / 2, -D / 2, -0.3), (W / 2, D / 2, 0.05), "Gravel", ALL)
    for sx in (-1, 1):
        a.box((0.2, D, 0.2), (sx * W / 2, 0, 0.1), "Concrete", L01)
    for sy in (-1, 1):
        a.box((W, 0.2, 0.2), (0, sy * D / 2, 0.1), "Concrete", L01)
    mats = ["Container_OD", "Container_Tan", "Container_OD", "Container_Blue", "Container_Rust", "Container_OD"]
    k = 0
    for row_y in (-4.5, 4.5):
        for i, x in enumerate((-8.0, -2.8, 2.4)):
            for lvl in ((0, 1) if (row_y < 0 and i == 0) else (0,)):
                m = mats[k % len(mats)]
                k += 1
                z0 = 0.05 + lvl * 2.591
                cx = x + 0.15 * lvl
                a.box_between((cx - 1.219, row_y - 3.029, z0), (cx + 1.219, row_y + 3.029, z0 + 2.591), m)
                for sy in (-1, 1):
                    for sx in (-1, 1):
                        a.box((0.17, 0.18, 0.12), (cx + sx * 1.13, row_y + sy * 2.94, z0 + 0.06), "Steel_Dark", L0)
                        a.box((0.17, 0.18, 0.12), (cx + sx * 1.13, row_y + sy * 2.94, z0 + 2.53), "Steel_Dark", L0)
                a.sign(A.RECT01, (cx, row_y + 3.03, z0 + 1.30), (-1, 0, 0), (0, 0, 1), 2.4, 2.55, S.rect("container_doors"), lods=ALL)
                a.col_between((cx - 1.219, row_y - 3.029, z0), (cx + 1.219, row_y + 3.029, z0 + 2.591))
    for x in (-W / 2 + 0.6, W / 2 - 0.6):
        a.cyl(0.08, 0.05, 8.0, (x, 0, 4.0), "Steel_Galv", ALL, segs=8)
        a.box((0.4, 0.5, 0.15), (x, 0.3, 7.9), "Paint_Grey", L01)
        a.box((0.35, 0.45, 0.01), (x, 0.3, 7.82), "Lamp", L01)
    a.marker("VEH_Forklift_Lane", (8.0, 0, 0.05), 90, "forklift / container handler lane (east)")
    for row_y in (-4.5, 4.5):
        for i, x in enumerate((-8.0, -2.8, 2.4)):
            a.marker("ATT_Slot_%s%d" % ("S" if row_y < 0 else "N", i + 1), (x, row_y, 0.05), 0, "container slot")
    a.marker("ATT_Slot_S4", (11.0, -4.5, 0.05), 0, "free container slot")
    a.lod_ranges = [[0, 80], [80, 320], [320, 2000]]
    a.structure = _st("Logistics", 3.0, 0.4)
    return a


def fuel_bladder_berm(A):
    """Fuel storage: 50 m3 collapsible fabric tank inside an earth bund with a liner,
    hose manifold and fuel-hazard boards."""
    a = A.Asset("fuel_bladder_berm", "module", "Fuel bladder in bund", "Fuel",
                "Bulk fuel storage: 50 m3 collapsible fabric tank (9 x 6 m, 1.2 m high) inside a 1.2 m earth bund 13 x 10 m with liner.")
    W, D = 13.0, 10.0
    for sy in (-1, 1):
        a.prism([(-1.4, 0), (1.4, 0), (0.4, 1.2), (-0.4, 1.2)], (-W / 2, sy * D / 2, 0), (W / 2, sy * D / 2, 0), "Dirt", ALL)
    for sx in (-1, 1):
        a.prism([(-1.4, 0), (1.4, 0), (0.4, 1.2), (-0.4, 1.2)], (sx * W / 2, -D / 2 + 1.0, 0), (sx * W / 2, D / 2 - 1.0, 0), "Dirt", ALL)
    a.box_between((-W / 2 + 0.6, -D / 2 + 0.6, 0.0), (W / 2 - 0.6, D / 2 - 0.6, 0.02), "Rubber", ALL)
    # Pillow tank: flattened ellipsoid, flat bottom.
    a.sphere(1.0, (0, 0, 0.02), "Rubber", ALL, scale=(4.5, 3.0, 1.2), segs=28, rings=12)
    a.cyl(0.08, 0.08, 6.0, (2.0, -4.0, 0.25), "Plastic_Black", L01, axis=(1, 0, 0), segs=8)
    a.box((1.2, 0.6, 0.8), (5.5, -5.8, 0.4), "Paint_Yellow", L01)
    for x in (-3.0, 3.0):
        Frame((x, D / 2 + 1.5, 0), 0).sign(a, "flammable", 0, 1.3, 0.6, 0.6, back="Steel_Galv")
        a.cyl(0.03, 0.03, 1.3, (x, D / 2 + 1.49, 0.65), "Steel_Galv", L01, segs=6)
    for sy in (-1, 1):
        a.col_box((W, 2.8, 1.2), (0, sy * D / 2, 0.6))
    a.col_box((9.0, 6.0, 1.2), (0, 0, 0.6))
    a.marker("IP_Manifold", (5.5, -6.6, 0), 0, "hose manifold / pump connection")
    a.marker("VEH_Tanker", (8.0, -9.0, 0), 90, "fuel tanker connects here")
    a.lod_ranges = [[0, 60], [60, 240], [240, 1500]]
    a.structure = _st("Fuel", 4.0, 0.5)
    a.meta["capacity_m3"] = 50
    return a


def fuel_point(A):
    """Vehicle fuel point: canopy over two dispensers on a concrete island, spill kit,
    fire extinguisher stand, warning boards."""
    a = A.Asset("fuel_point", "module", "Vehicle fuel point", "Fuel",
                "Two-lane vehicle fuel point: 10 x 8 m canopy at 5 m, dispenser island, spill kit and fire point.")
    W, D, H = 10.0, 8.0, 5.0
    a.box_between((-W / 2 - 2, -D / 2 - 1, -0.3), (W / 2 + 2, D / 2 + 1, 0.06), "Concrete", ALL)
    a.box_between((-0.8, -2.5, 0.06), (0.8, 2.5, 0.22), "Concrete_Dark", ALL)
    for y in (-2.0, 2.0):
        a.box((0.35, 0.35, H), (0, y, H / 2), "Paint_White", ALL)
    a.box_between((-W / 2, -D / 2, H), (W / 2, D / 2, H + 0.6), "Paint_White", ALL)
    for y in (-0.9, 0.9):
        a.box((0.5, 0.8, 1.8), (0, y, 1.12), "Paint_Grey", L01, bevel=0.03)
        Frame((0.25, y, 0.22), -90).sign(a, "gauge_dial", 0, 1.3, 0.3, 0.3, y=0.005, lods=L0)
        for sx in (-1, 1):
            a.tube([(sx * 0.25, y, 1.4), (sx * 0.6, y, 1.0), (sx * 0.4, y + 0.2, 0.9)], 0.02, "Plastic_Black", L0, segs=5)
    a.box((0.6, 0.4, 0.9), (-W / 2 - 1.0, 3.0, 0.5), "Paint_Yellow", L01)
    a.box((0.4, 0.3, 1.2), (-W / 2 - 1.0, 2.2, 0.66), "Paint_Red", L01)
    for x, name in ((W / 2 + 1.0, "no_smoking"), (-W / 2 - 1.0, "plate_fuel")):
        a.cyl(0.03, 0.03, 2.0, (x, -D / 2 - 0.5, 1.0), "Steel_Galv", L01, segs=6)
        w = 1.2 if name.startswith("plate") else 0.6
        Frame((x, -D / 2 - 0.48, 0), 0).sign(a, name, 0, 2.2, w, 0.6, back="Steel_Galv")
    a.col_box((1.6, 5.0, 0.22), (0, 0, 0.11))
    for y in (-2.0, 2.0):
        a.col_box((0.35, 0.35, H), (0, y, H / 2))
    a.col_box((W, D, 0.6), (0, 0, H + 0.3))
    a.marker("VEH_Lane_W", (-2.8, 0, 0.06), 0, "vehicle refuels here (west lane, heading +Y)")
    a.marker("VEH_Lane_E", (2.8, 0, 0.06), 0, "vehicle refuels here (east lane)")
    a.structure = _st("Fuel", 3.0, 0.4, nav=False)
    return a


def ammo_magazine(A):
    """Earth-covered ammunition magazine (igloo): corrugated steel arch 6 x 12 m under
    an earth mound, reinforced-concrete headwall with steel double doors, lightning
    protection masts."""
    a = A.Asset("ammo_magazine", "module", "Ammunition storage bunker", "Ammunition",
                "Earth-covered magazine: 6 m wide steel arch, 12 m deep, earth mound 0.6 m over the crown, concrete headwall "
                "with 2.4 x 2.6 m steel double door, two lightning masts.")
    Wd, Dp, H = 6.0, 12.0, 3.4
    # Earth mound: trapezoid section from the headwall to the back, then a sloped end
    # down to the ground (one loft: front ring, back ring, ground ring).
    def ring(y, top_half, base_half, h):
        return [(-base_half, y, 0.0), (base_half, y, 0.0), (top_half, y, h), (-top_half, y, h)]
    a.loft([ring(Dp / 2, Wd / 2 + 0.6, Wd / 2 + 3.5, H + 0.6), ring(-Dp / 2, Wd / 2 + 0.6, Wd / 2 + 3.5, H + 0.6),
            ring(-Dp / 2 - 3.6, Wd / 2 + 0.6, Wd / 2 + 3.5, 0.0)], "Dirt", ALL, closed=True, cap=False)
    # Headwall with wing walls, door, arch outline, vent.
    a.box_between((-Wd / 2 - 1.2, Dp / 2, 0), (Wd / 2 + 1.2, Dp / 2 + 0.4, H + 1.0), "Concrete")
    for sx in (-1, 1):
        a.prism([(-0.2, 0.0), (0.2, 0.0), (0.2, 0.6), (-0.2, H + 0.6)], (sx * (Wd / 2 + 1.0), Dp / 2 + 0.4, 0),
                (sx * (Wd / 2 + 1.0), Dp / 2 + 2.6, 0), "Concrete", ALL)
    F = Frame((0, Dp / 2 + 0.4, 0), 0)
    F.box(a, (2.5, 0.06, 2.7), 0, 0.03, 1.35, "Paint_OD", ALL)
    F.box(a, (0.02, 0.07, 2.6), 0, 0.04, 1.35, "Steel_Dark", L0)
    for x in (-0.6, 0.6):
        F.box(a, (0.12, 0.08, 0.04), x, 0.07, 1.3, "Steel_Galv", L0)
    F.sign(a, "plate_ammo", 0, 3.2, 1.8, 0.9, y=0.012)
    F.sign(a, "explosive", 2.4, 2.0, 0.6, 0.6, y=0.012)
    F.sign(a, "no_smoking", -2.4, 2.0, 0.6, 0.6, y=0.012)
    K.wall_light(a, F, 1.8, 3.0)
    a.cyl(0.25, 0.25, 0.8, (0, -2.0, H + 0.9), "Steel_Galv", L01, segs=10)
    for sx in (-1, 1):
        a.cyl(0.05, 0.03, 9.0, (sx * (Wd / 2 + 4.5), 0.0, 4.5), "Steel_Galv", L01, segs=6)
    a.box_between((-2.0, Dp / 2 + 0.4, -0.2), (2.0, Dp / 2 + 5.0, 0.08), "Concrete", ALL)
    a.col_box((Wd + 7.0, Dp, H + 0.6), (0, 0, (H + 0.6) / 2))
    a.col_between((-Wd / 2 - 1.2, Dp / 2, 0), (Wd / 2 + 1.2, Dp / 2 + 0.4, H + 1.0))
    a.marker("IP_Door", (0, Dp / 2 + 1.5, 0.08), 180, "magazine door")
    a.marker("VEH_Loading", (0, Dp / 2 + 8.0, 0), 180, "truck reverses to the apron")
    a.lod_ranges = [[0, 70], [70, 280], [280, 2000]]
    a.structure = _st("Ammunition", 4.0, 0.8)
    a.meta["capacity_t_neq"] = 20
    return a


# =============================================================================== communications / checkpoint / DFP


def comms_tower(A):
    """Free-standing 24 m guyed lattice communications tower with dish, panel antennas
    and whips on a concrete base."""
    a = A.Asset("comms_tower", "module", "Communications tower 24 m", "Communications",
                "Guyed 24 m triangular lattice tower: two microwave dishes, three sector panels, whip antennas, warning light.")
    H = 24.0
    a.box((1.2, 1.2, 0.4), (0, 0, 0.0), "Concrete", ALL)
    K.lattice_mast(a, 0, 0, H, 0.60)
    for z, r in ((8.0, 7.0), (16.0, 10.0), (23.0, 13.0)):
        K.guy_wires(a, 0, 0, z, r, 3, 0.0)
    for yaw in (0, 120, 240):
        x, y = 0.55 * math.cos(math.radians(yaw + 90)), 0.55 * math.sin(math.radians(yaw + 90))
        a.box((0.34, 0.09, 1.6), (x, y, 22.0), "Plastic_White", L01, rot=A.rot_z(yaw))
    K.dish(a, 0, 0.55, 18.0, 0.6, 0, 3)
    K.dish(a, -0.5, -0.2, 15.0, 0.45, 120, 2)
    for k, ln in enumerate((3.5, 2.5)):
        K.whip(a, 0.12 * (k - 0.5), 0, H, ln)
    a.cyl(0.07, 0.07, 0.15, (0, 0, H + 0.08), "Paint_Red", L01, segs=8)
    a.col_box((0.8, 0.8, H), (0, 0, H / 2))
    a.marker("ATT_Top", (0, 0, H), 0, "antenna mounting")
    a.lod_ranges = [[0, 100], [100, 400], [400, 3000]]
    a.structure = _st("Communications", 8.0, 0.3)
    return a


def checkpoint_station(A):
    """Vehicle checkpoint for one lane: canopy over the inspection lane, guard booth,
    boom barrier, speed bumps, concrete chicane blocks, signs."""
    a = A.Asset("checkpoint_station", "module", "Guard checkpoint", "Checkpoint",
                "Entry control point, one 4.5 m lane: 8 x 12 m canopy, guard booth, boom barrier, two speed bumps, "
                "Jersey-barrier chicane, checkpoint and speed signs.")
    a.box_between((-6.0, -10.0, -0.3), (6.0, 10.0, 0.05), "Asphalt", ALL)
    for sx in (-1, 1):
        for y in (-5.5, 5.5):
            a.box((0.3, 0.3, 5.0), (sx * 4.0, y, 2.5), "Paint_White", ALL)
    a.box_between((-4.4, -6.0, 5.0), (4.4, 6.0, 5.6), "Paint_White", ALL)
    a.box_between((-4.4, 5.98, 5.05), (4.4, 6.02, 5.55), "Paint_Red", L01)
    for x in (-3.0, 0.0, 3.0):
        a.box((0.5, 0.6, 0.05), (x, 0, 4.97), "Lamp", L01)
    # Booth (west of the lane).
    bx, by = -3.6, 0.0
    a.box_between((bx - 0.8, by - 0.8, 0.05), (bx + 0.8, by + 0.8, 2.6), "Paint_OD")
    for k in range(4):
        F = Frame(Frame((bx, by, 0), 90 * k).p(0, 0.8, 0.05), 90 * k)
        F.box(a, (1.2, 0.03, 0.8), 0, 0.0, 1.55, "Glass", ALL)
    a.box_between((bx - 1.0, by - 1.0, 2.6), (bx + 1.0, by + 1.0, 2.72), "Paint_OD")
    # Boom barrier across the lane at y = 3.
    a.box((0.36, 0.36, 1.0), (-2.6, 3.0, 0.55), "Paint_Yellow", ALL)
    for i in range(10):
        a.box((0.5, 0.09, 0.09), (-2.3 + i * 0.5 + 0.25, 3.0, 0.92), "Paint_Red" if i % 2 == 0 else "Paint_White", L01)
    a.box((5.0, 0.09, 0.09), (0.2, 3.0, 0.92), "Paint_White", L2)
    # Speed bumps and chicane blocks before the checkpoint.
    for y in (7.0, -7.0):
        a.prism([(-0.25, 0.0), (0.25, 0.0), (0.0, 0.07)], (-2.3, y, 0.05), (2.3, y, 0.05), "Paint_Yellow", ALL, up=(0, 0, 1))
    for (x, y) in ((-1.0, 9.0), (1.5, 8.0)):
        a.prism([(-0.305, 0.0), (0.305, 0.0), (0.21, 0.255), (0.12, 0.81), (-0.12, 0.81), (-0.21, 0.255)],
                (x - 1.5, y, 0.05), (x + 1.5, y, 0.05), "Concrete", ALL)
    for x, name, w in ((3.4, "checkpoint", 1.4), (-3.4, "speed_15", 0.6)):
        a.cyl(0.03, 0.03, 2.4, (x, 9.5, 1.2), "Steel_Galv", L01, segs=6)
        Frame((x, 9.52, 0), 0).sign(a, name, 0, 2.6, w, 0.7 if w > 1 else 0.6, back="Steel_Galv")
    a.col_between((bx - 0.8, by - 0.8, 0), (bx + 0.8, by + 0.8, 2.7))
    for sx in (-1, 1):
        for y in (-5.5, 5.5):
            a.col_box((0.3, 0.3, 5.0), (sx * 4.0, y, 2.5))
    a.col_box((3.0, 0.61, 0.81), (-1.0, 9.0, 0.45))
    a.col_box((3.0, 0.61, 0.81), (1.5, 8.0, 0.45))
    a.marker("VEH_Inspect", (0.2, 0.0, 0.05), 180, "vehicle stops for inspection (inbound -Y)")
    a.marker("IP_Guard", (bx, by, 0.05), 90, "guard in the booth")
    a.marker("IP_Search", (1.8, 0.0, 0.05), -90, "searcher position beside the vehicle")
    a.marker("SNAP_Road_N", (0.0, 10.0, 0), 0, "road continues north")
    a.marker("SNAP_Road_S", (0.0, -10.0, 0), 180, "road continues south")
    a.marker("SNAP_Fence_W", (-6.0, 0, 0), 90, "perimeter fence joins (west)")
    a.marker("SNAP_Fence_E", (6.0, 0, 0), -90, "perimeter fence joins (east)")
    a.structure = _st("Checkpoint", 4.0, 0.4, nav=False)
    return a


def dfp_sandbag_ring(A):
    """Two-man fighting position: circular sandbag parapet 3 m across, 1.0 m high, with
    a firing port facing +Y and an opening at the back."""
    a = A.Asset("dfp_sandbag_ring", "module", "Fighting position (sandbags)", "Defences",
                "Circular sandbag fighting position, 3.0 m outer diameter, 1.0 m high, firing port forward, rear entrance.")
    rnd = random.Random(11)
    R = 1.3
    for k in range(8):
        n = 14
        for i in range(n):
            ang = (i + 0.5 * (k % 2)) * 2 * math.pi / n
            deg = math.degrees(ang)
            if 250 < deg < 290:
                continue                                 # rear entrance (-Y)
            if k in (5, 6) and 80 < deg < 100:
                continue                                 # firing port (+Y)
            c = (R * math.cos(ang), R * math.sin(ang), 0.065 + k * 0.12)
            a.sphere(1.0, c, "Sandbag", L0, scale=(0.30, 0.165, 0.074), segs=8, rings=4)
    # LOD1/2: a plain ring.
    a.cyl(R + 0.17, R + 0.17, 0.96, (0, 0, 0.48), "Sandbag", L12, segs=12)
    a.cyl(R - 0.17, R - 0.17, 0.01, (0, 0, 0.97), "Dirt", L12, segs=12)
    a.box_between((-1.0, -1.0, -0.01), (1.0, 1.0, 0.01), "Dirt", L0)
    a.col_box((3.0, 3.0, 1.0), (0, 0, 0.5))
    a.marker("IP_Firing_1", (-0.4, 0.6, 0), 0, "rifleman, faces the port (+Y)")
    a.marker("IP_Firing_2", (0.4, 0.6, 0), 0)
    a.marker("IP_Entrance", (0, -2.0, 0), 0)
    a.lod_ranges = [[0, 40], [40, 160], [160, 800]]
    a.structure = _st("Defences", 10.0, 0.3)
    return a


def mg_nest(A):
    """Machine-gun nest with overhead cover: U-shaped sandbag walls, timber posts and a
    sandbagged plywood roof, firing slit forward."""
    a = A.Asset("mg_nest", "module", "MG position with overhead cover", "Defences",
                "Machine-gun position 3.0 x 3.0 m: 1.0 m sandbag walls, 4 timber posts, plywood roof with sandbags at 1.6 m, "
                "0.4 m firing slit forward.")
    _sandbag_row(a, -1.5, 1.5, 1.35, 8, seed=2)
    _sandbag_row(a, -1.2, 1.2, -1.5, 8, seed=3, along="y")
    _sandbag_row(a, -1.2, 1.2, 1.5, 8, seed=4, along="y")
    for sx in (-1.2, 1.2):
        for sy in (-1.2, 1.1):
            a.box((0.12, 0.12, 1.6), (sx, sy, 0.8), "Timber", L01)
    a.box((3.4, 3.2, 0.05), (0, 0, 1.62), "Plywood", ALL)
    rnd = random.Random(5)
    for i in range(5):
        for j in range(5):
            a.sphere(1.0, (-1.3 + i * 0.65, -1.3 + j * 0.65, 1.72), "Sandbag", L0, scale=(0.30, 0.165, 0.074), segs=8, rings=4)
    a.box((3.3, 3.1, 0.15), (0, 0, 1.72), "Sandbag", L12)
    a.col_box((3.4, 0.35, 1.0), (0, 1.35, 0.5))
    a.col_box((0.35, 2.4, 1.0), (-1.5, 0, 0.5))
    a.col_box((0.35, 2.4, 1.0), (1.5, 0, 0.5))
    a.col_box((3.4, 3.2, 0.25), (0, 0, 1.72))
    a.marker("IP_Gunner", (0, 0.7, 0), 0, "gunner, weapon on the parapet (+Y)")
    a.marker("IP_Entrance", (0, -2.0, 0), 0)
    a.lod_ranges = [[0, 40], [40, 160], [160, 800]]
    a.structure = _st("Defences", 10.0, 0.3)
    return a


BUILDERS = {
    "range_firing_point": range_firing_point,
    "range_target_line": range_target_line,
    "range_backstop": range_backstop,
    "range_tower": range_tower,
    "obstacle_wall": obstacle_wall,
    "obstacle_balance": obstacle_balance,
    "obstacle_crawl": obstacle_crawl,
    "obstacle_tires": obstacle_tires,
    "obstacle_net": obstacle_net,
    "obstacle_monkey_bars": obstacle_monkey_bars,
    "shoot_house": shoot_house,
    "mout_wall_window": lambda A: mout_wall(A, "mout_wall_window", "window"),
    "mout_wall_door": lambda A: mout_wall(A, "mout_wall_door", "door"),
    "vehicle_ramp": vehicle_ramp,
    "vehicle_parking_pad": vehicle_parking_pad,
    "repair_bay": repair_bay,
    "container_yard": container_yard,
    "fuel_bladder_berm": fuel_bladder_berm,
    "fuel_point": fuel_point,
    "ammo_magazine": ammo_magazine,
    "comms_tower": comms_tower,
    "checkpoint_station": checkpoint_station,
    "dfp_sandbag_ring": dfp_sandbag_ring,
    "mg_nest": mg_nest,
}
