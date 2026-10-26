"""Civilian cover and yard props (WORLD-DETAIL-02): the everyday objects of Norwegian farms, villages, roadsides and
yards that soldiers use as cover - wrapped round bales, firewood stacks, garden walls, concrete blocks, concrete pipes,
skip containers, a transformer kiosk and pallet stacks - plus a picket fence for property boundaries (visual only).

Real dimensions (references in docs/world_detail02/refs/), front = +Y, origin on the ground, collision boxes = the solid
part (they become the box solids of the vegetation library ids in assets/environment/nordic_library.tres, which the
line of fire, the collider streamer, the navmesh and the AI cover search read). Each builder takes the ap_lib module (A)
and returns an A.Asset.
"""
import math
import random

ALL = (0, 1, 2)
L01 = (0, 1)
L0 = (0,)
L1 = (1,)
L2 = (2,)
YARD = [[0, 40], [40, 140], [140, 700]]


# =============================================================================== round bales


def bale_row(A, aid, n, wrap, seed):
    """Wrapped round bales (rundballer, 1.25 m across, 1.2 m wide) lying on their round side in a row along X, ends
    touching - how they are stored at the field edge or by the barn. Each bale sags a little and sits slightly askew."""
    a = A.Asset(aid, "prop", "Round bales x%d" % n, "Rural",
                "%d stretch-wrapped silage round bales, 1.25 m diameter, 1.2 m wide, in a row (%.1f m long)." % (n, n * 1.27))
    rnd = random.Random(seed)
    r, w = 0.625, 1.2
    Lx = n * 1.27
    for k in range(n):
        x = -Lx / 2 + 0.635 + k * 1.27 + rnd.uniform(-0.03, 0.03)
        y = rnd.uniform(-0.06, 0.06)
        rr = r * rnd.uniform(0.97, 1.02)
        # The bale settles: its centre is a little lower than its radius.
        z = rr - 0.035
        a.cyl(rr, rr, w, (x, y, z), wrap, L0, axis=(0, 1, 0), segs=28)
        a.cyl(rr, rr, w, (x, y, z), wrap, L1, axis=(0, 1, 0), segs=14)
        # Flat end faces bulge where the film overlaps: a thin disc on each end.
        for sy in (-1, 1):
            a.cyl(rr * 0.82, rr * 0.55, 0.05, (x, y + sy * (w / 2 + 0.024), z), wrap, L0, axis=(0, sy, 0), segs=20)
    a.box((Lx, w, 2 * r - 0.08), (0, 0, r - 0.04), wrap, L2)
    a.col_box((Lx - 0.1, w, 2 * r - 0.1), (0, 0, r - 0.05))
    a.lod_ranges = YARD
    a.ao_height, a.ao_strength = 0.5, 0.3
    return a


def round_bales_white(A):
    return bale_row(A, "round_bales_white", 4, "Wrap_White", 101)


def round_bales_green(A):
    return bale_row(A, "round_bales_green", 4, "Wrap_Green", 102)


# =============================================================================== firewood


def firewood_stack(A):
    """Split birch firewood stacked between end posts (vedstabel) 3.0 m long, 1.35 m high, 0.6 m deep, the pieces
    lying across (cut ends to the front and back), a corrugated sheet on top weighed down with two planks."""
    a = A.Asset("firewood_stack", "prop", "Firewood stack", "Rural",
                "Split firewood stacked 3.0 x 0.6 x 1.35 m between end posts under a corrugated sheet.")
    rnd = random.Random(311)
    Lx, D, H = 3.0, 0.6, 1.35
    # End posts (two per end) and a pair of bearers on the ground.
    for sx in (-1, 1):
        for sy in (-1, 1):
            a.box((0.08, 0.08, H + 0.1), (sx * (Lx / 2 + 0.04), sy * 0.24, (H + 0.1) / 2 - 0.07), "Timber_Dark", L01)
    for sy in (-1, 1):
        a.box((Lx + 0.2, 0.09, 0.09), (0, sy * 0.2, 0.045), "Timber_Dark", L01)
    # Pieces: wedge-shaped splits (quarter / third of a 0.2 - 0.3 m round), rows from 0.09 m up.
    z = 0.095
    piece = 0
    while z < H - 0.08:
        x = -Lx / 2 + 0.02
        row_h = rnd.uniform(0.09, 0.12)
        while x < Lx / 2 - 0.1:
            d = rnd.uniform(0.09, 0.15)
            hh = row_h * rnd.uniform(0.94, 1.0)
            ang = rnd.uniform(-0.12, 0.12)
            prof = [(-d / 2, -hh / 2), (d / 2, -hh / 2), (d * 0.42, hh * 0.3), (0.0, hh / 2), (-d * 0.45, hh * 0.25)]
            prof = [(u * math.cos(ang) - v * math.sin(ang), u * math.sin(ang) + v * math.cos(ang)) for u, v in prof]
            cx, cz = x + d / 2, z + hh / 2
            # Depth and offset from the piece's number, never the same for touching pieces (coplanar ends z-fight).
            piece += 1
            depth = 0.5 + (piece * 0.0137) % 0.12
            yoff = ((piece * 7) % 9 - 4) * 0.0071
            a.prism([(cx + u, cz + v) for u, v in prof], (0, -depth / 2 + yoff, 0), (0, depth / 2 + yoff, 0), "Timber", L0,
                    up=(0, 0, 1))
            x += d * 1.12 + 0.006
        z += row_h * 0.985
    # LOD1 / LOD2: the stack as a block.
    a.box((Lx, D, H - 0.09), (0, 0, 0.09 + (H - 0.09) / 2), "Timber", (1, 2))
    # Sheet roof, a little wider than the stack, sloping to the back, two planks on it.
    a.box((Lx + 0.4, D + 0.3, 0.02), (0, -0.02, H + 0.04), "Roof_Galv", ALL, rot=None)
    for sx in (-0.8, 0.9):
        a.box((0.15, D + 0.4, 0.04), (sx, 0, H + 0.065), "Timber_Dark", L0)
    a.col_box((Lx, D, H), (0, 0, H / 2))
    a.lod_ranges = YARD
    a.ao_height, a.ao_strength = 0.8, 0.35
    return a


# =============================================================================== walls and fences


def garden_wall_concrete(A):
    """Low rendered garden wall (6.0 m, 0.9 m high, 0.25 m thick) on a footing, a cap stone on top and an expansion joint
    in the middle - the boundary wall of a village plot towards the road."""
    a = A.Asset("garden_wall_concrete", "prop", "Garden wall (concrete)", "Settlement",
                "Low concrete garden wall 6.0 m long, 0.9 m high, 0.25 m thick, with a cap.")
    Lx, H, T = 6.0, 0.9, 0.25
    a.box((Lx, T + 0.1, 0.12), (0, 0, 0.06), "Concrete_Dark", L01)
    a.box((Lx / 2 - 0.01, T, H - 0.18), (-Lx / 4 - 0.005, 0, 0.12 + (H - 0.18) / 2), "Concrete", L01)
    a.box((Lx / 2 - 0.01, T, H - 0.18), (Lx / 4 + 0.005, 0, 0.12 + (H - 0.18) / 2), "Concrete", L01)
    a.box((Lx + 0.04, T + 0.08, 0.06), (0, 0, H - 0.03), "Concrete_Dark", L01, bevel=0.01)
    a.box((Lx, T, H), (0, 0, H / 2), "Concrete", L2)
    a.col_box((Lx, T + 0.08, H), (0, 0, H / 2))
    a.marker("SNAP_W", (-Lx / 2, 0, 0), 90)
    a.marker("SNAP_E", (Lx / 2, 0, 0), -90)
    a.lod_ranges = YARD
    a.ao_height, a.ao_strength = 0.5, 0.3
    return a


def garden_wall_stone(A):
    """Low mortared natural-stone garden wall (6.0 m, 0.85 m, 0.4 m thick): coursed granite blocks of varying size with a
    flat stone cap - the older version of the plot wall."""
    a = A.Asset("garden_wall_stone", "prop", "Garden wall (stone)", "Settlement",
                "Low mortared stone garden wall 6.0 m long, 0.85 m high, 0.4 m thick.")
    rnd = random.Random(907)
    Lx, H, T = 6.0, 0.85, 0.4
    # Mortar core, then the face stones standing a little proud of it on both faces.
    a.box((Lx - 0.04, T - 0.06, H - 0.08), (0, 0, (H - 0.08) / 2), "Concrete_Dark", L01)
    z = 0.0
    for row_h in (0.24, 0.21, 0.19, 0.13):
        x = -Lx / 2
        while x < Lx / 2 - 0.05:
            w = min(rnd.uniform(0.3, 0.6), Lx / 2 - x)
            for sy in (-1, 1):
                a.box((w - 0.03, 0.09, row_h - 0.025), (x + w / 2, sy * (T / 2 - 0.04) + sy * rnd.uniform(0.0, 0.015),
                                                        z + row_h / 2), "Rock", L0, bevel=0.02)
            x += w
        z += row_h
    a.box((Lx, T, H - 0.08), (0, 0, (H - 0.08) / 2), "Rock", (1, 2))
    a.box((Lx + 0.04, T + 0.06, 0.08), (0, 0, H - 0.04), "Rock", ALL, bevel=0.015)
    a.col_box((Lx, T + 0.04, H), (0, 0, H / 2))
    a.marker("SNAP_W", (-Lx / 2, 0, 0), 90)
    a.marker("SNAP_E", (Lx / 2, 0, 0), -90)
    a.lod_ranges = YARD
    a.ao_height, a.ao_strength = 0.5, 0.3
    return a


def picket_fence(A):
    """White picket fence (stakittgjerde) 4.0 m section: posts every 2 m, two rails, pointed pickets 0.95 m high with
    gaps. Thin painted boards: a boundary, not cover (no collision box)."""
    a = A.Asset("picket_fence", "prop", "Picket fence 4 m", "Settlement",
                "White painted picket fence section 4.0 m long, 0.95 m high.")
    Lx, H = 4.0, 0.95
    for x in (-Lx / 2 + 0.05, 0.0, Lx / 2 - 0.05):
        a.box((0.09, 0.09, H + 0.1), (x, -0.06, (H + 0.1) / 2), "Paint_White", ALL)
    for z in (0.25, 0.75):
        a.box((Lx - 0.1, 0.03, 0.08), (0, -0.005, z), "Paint_White", L01)
    x = -Lx / 2 + 0.12
    while x < Lx / 2 - 0.08:
        prof = [(-0.035, 0.05), (0.035, 0.05), (0.035, H - 0.06), (0.0, H), (-0.035, H - 0.06)]
        a.prism([(x + u, v) for u, v in prof], (0, 0.0, 0), (0, 0.02, 0), "Paint_White", L0, up=(0, 0, 1))
        x += 0.12
    # LOD1 / 2: the pickets as one board with the rails.
    a.box((Lx, 0.02, H - 0.1), (0, 0.01, 0.05 + (H - 0.1) / 2), "Paint_White", (1, 2))
    a.lod_ranges = [[0, 30], [30, 90], [90, 260]]
    a.ao_height, a.ao_strength = 0.4, 0.25
    return a


# =============================================================================== yard and site materials


def concrete_blocks(A):
    """Interlocking concrete blocks (betongklosser) 1.6 x 0.8 x 0.8 m with studs, stacked two high in a running bond -
    a site barrier or a bin wall: 4.8 m long, 1.6 m high (plus studs)."""
    a = A.Asset("concrete_blocks", "prop", "Concrete block wall", "Industrial",
                "Interlocking 1.6 x 0.8 x 0.8 m concrete blocks stacked two high, 4.8 m long, 1.6 m high.")
    rnd = random.Random(55)
    for row, xs in enumerate([(-1.6, 0.0, 1.6), (-0.8, 0.8)]):
        z = 0.4 + row * 0.8
        for x in xs:
            dx, dy = rnd.uniform(-0.03, 0.03), rnd.uniform(-0.025, 0.025)
            a.box((1.58, 0.79, 0.79), (x + dx, dy, z), "Concrete_Dark", L01, bevel=0.02)
            for sx in (-0.4, 0.4):
                a.cyl(0.13, 0.12, 0.08, (x + dx + sx, dy, z + 0.435), "Concrete_Dark", L0, segs=12)
    # Top row ends at 0.8: the two upper blocks centred over the joints; the ends step down.
    a.box((4.8, 0.8, 0.8), (0, 0, 0.4), "Concrete_Dark", L2)
    a.box((3.2, 0.8, 0.8), (0, 0, 1.2), "Concrete_Dark", L2)
    a.col_box((4.8, 0.8, 0.8), (0, 0, 0.4))
    a.col_box((3.2, 0.8, 0.8), (0, 0, 1.2))
    a.lod_ranges = YARD
    a.ao_height, a.ao_strength = 0.7, 0.3
    return a


def concrete_pipes(A):
    """Three concrete drainage pipes (1.0 m outer, 0.8 m bore, 2.0 m long) stored in a pyramid on timber chocks at a
    road works or depot: 2.1 m wide, 1.95 m high."""
    a = A.Asset("concrete_pipes", "prop", "Concrete pipe stack", "Industrial",
                "Three 1000 mm concrete pipes 2.0 m long stacked two-and-one, 2.1 m wide, 1.95 m high.")
    R, r, Ly = 0.5, 0.4, 2.0
    pts = [(-0.52, 0.56), (0.52, 0.56), (0.0, 0.56 + 0.9)]
    for (x, z) in pts:
        for lods, segs in ((L0, 24), (L1, 12), (L2, 8)):
            _pipe(a, x, z, r, R, Ly, segs, lods)
    for sy in (-0.7, 0.7):
        a.box((2.3, 0.12, 0.08), (0, sy, 0.04), "Timber_Dark", L01)
        for sx in (-1.04, 1.04):
            a.box((0.12, 0.12, 0.14), (sx, sy, 0.15), "Timber_Dark", L0)
    a.col_box((2.1, Ly, 1.06), (0, 0, 0.53))
    a.col_box((1.0, Ly, 0.9), (0, 0, 1.5))
    a.lod_ranges = YARD
    a.ao_height, a.ao_strength = 0.7, 0.3
    return a


def _pipe(a, x, z, r, R, Ly, segs, lods):
    """A whole concrete pipe along Y: outer wall facing out, bore facing in, an annulus at each end - one closed shell."""
    verts, faces = [], []
    for y in (-Ly / 2, Ly / 2):
        for k in range(segs):
            t = k / segs * math.tau
            c, s_ = math.cos(t), math.sin(t)
            verts.append((x + R * c, y, z + R * s_))
            verts.append((x + r * c, y, z + r * s_))
    n = 2 * segs
    for k in range(segs):
        o0, i0 = 2 * k, 2 * k + 1
        o1, i1 = 2 * ((k + 1) % segs), 2 * ((k + 1) % segs) + 1
        faces.append((o0, o1, n + o1, n + o0))      # outer wall
        faces.append((i0, n + i0, n + i1, i1))      # bore
        faces.append((o0, i0, i1, o1))              # end at -Y
        faces.append((n + o0, n + o1, n + i1, n + i0))  # end at +Y
    a.poly(verts, faces, "Concrete", lods)


def skip(A, aid, paint, seed):
    """Open lift skip (liftcontainer, 8 m3): sloped ends, 3.6 m long at the top, 3.0 m on the floor, 1.8 m wide, 1.5 m
    high, ribbed sides, lifting arms at the ends; filled with building waste to near the rim."""
    a = A.Asset(aid, "prop", "Skip container", "Industrial",
                "Open steel lift skip 3.6 x 1.8 x 1.5 m (8 m3) with sloped ends, half full of waste.")
    rnd = random.Random(seed)
    H, W = 1.5, 1.8
    xb, xt = 1.5, 1.8
    # The hull: an open steel tub (floor, two sloped ends, two side walls), outside and inside faces.
    for inset, flip in ((0.0, False), (0.04, True)):
        hw, b, t, z0 = W / 2 - inset, xb - inset, xt - inset * 1.4, 0.08 + inset
        v = [(-b, -hw, z0), (b, -hw, z0), (b, hw, z0), (-b, hw, z0), (-t, -hw, H), (t, -hw, H), (t, hw, H), (-t, hw, H)]
        f = [(0, 3, 2, 1), (0, 1, 5, 4), (2, 3, 7, 6), (1, 2, 6, 5), (3, 0, 4, 7)]
        if flip:
            f = [tuple(reversed(q)) for q in f]
        a.poly(v, f, paint, ALL if not flip else L01)
    # Skids under it, rib stiffeners on the long sides, the top rim, lifting pins at the ends.
    for sy in (-0.55, 0.55):
        a.box((3.0, 0.14, 0.1), (0, sy, 0.05), "Steel_Dark", L01)
    for sy in (-1, 1):
        for x in (-1.1, -0.37, 0.37, 1.1):
            a.box((0.08, 0.06, H - 0.12), (x, sy * (W / 2 + 0.03), 0.08 + (H - 0.12) / 2), paint, L0)
        a.box((3.6, 0.08, 0.1), (0, sy * (W / 2 + 0.03), H - 0.05), paint, L01)
    for sx in (-1, 1):
        for sy in (-1, 1):
            a.cyl(0.06, 0.06, 0.3, (sx * 1.66, sy * (W / 2 + 0.12), 1.05), "Steel_Dark", L0, axis=(0, 1, 0), segs=8)
    # Waste near the rim: broken boards, a few blocks, plastic.
    a.box((3.2, W - 0.12, 0.04), (0, 0, H - 0.3), "Dirt", L01)
    for k in range(9):
        a.box((rnd.uniform(0.6, 1.4), rnd.uniform(0.08, 0.2), 0.03), (rnd.uniform(-1.2, 1.2), rnd.uniform(-0.6, 0.6),
              H - 0.272 + k * 0.0045), "Timber_Dark", L0, rot=None)
    a.col_box((3.4, W + 0.1, H), (0, 0, H / 2))
    a.lod_ranges = YARD
    a.ao_height, a.ao_strength = 0.6, 0.3
    return a


def skip_green(A):
    return skip(A, "skip_green", "Paint_Green", 61)


def skip_yellow(A):
    return skip(A, "skip_yellow", "Paint_Yellow", 62)


def transformer_kiosk(A):
    """Transformer kiosk (nettstasjon) of a rural power line: a precast concrete box 2.4 x 1.9 m, 2.3 m high with a
    shallow gable roof of sheet steel, grey louvred steel doors on the front and one end, warning sign, gravel apron."""
    a = A.Asset("transformer_kiosk", "prop", "Transformer kiosk", "Infrastructure",
                "Precast concrete transformer kiosk (nettstasjon) 2.4 x 1.9 x 2.3 m with steel doors.")
    Lx, W, H = 2.4, 1.9, 2.15
    a.box((Lx + 0.6, W + 0.6, 0.05), (0, 0, 0.025), "Gravel", L01)
    a.box((Lx, W, H - 0.03), (0, 0, (H + 0.03) / 2), "Concrete", ALL, bevel=0.02)
    A_kit_roof(a, Lx, W, H)
    # Doors: a double door on the front (+Y), one on the east end, with louvres.
    for x in (-0.48, 0.48):
        a.box((0.86, 0.04, 1.95), (x, W / 2 + 0.02, 1.02), "Paint_Grey", L01)
        for k in range(6):
            a.box((0.6, 0.03, 0.03), (x, W / 2 + 0.045, 0.4 + k * 0.08), "Steel_Dark", L0)
    a.box((0.04, 0.9, 1.95), (Lx / 2 + 0.02, 0, 1.02), "Paint_Grey", L01)
    a.box((0.3, 0.012, 0.3), (0, W / 2 + 0.05, 2.0), "Paint_Yellow", L0)
    a.col_box((Lx, W, H + 0.3), (0, 0, (H + 0.3) / 2))
    a.lod_ranges = [[0, 50], [50, 180], [180, 900]]
    a.ao_height, a.ao_strength = 0.8, 0.3
    return a


def A_kit_roof(a, Lx, W, H):
    """Shallow sheet gable over the kiosk, ridge along X, 0.15 m overhang."""
    rise = 0.3
    o = 0.15
    a.prism([(-(W / 2 + o), H - 0.01), (W / 2 + o, H - 0.01), (0.0, H + rise)], (-Lx / 2 - o, 0, 0), (Lx / 2 + o, 0, 0),
            "Roof_Galv", ALL, up=(0, 0, 1))


def _pallet(a, x, y, z, lods):
    """One EUR pallet 1.2 x 0.8 x 0.144 m (long side along X): three bottom boards, nine blocks, deck boards."""
    if lods == L0:
        for yy in (-0.33, 0.0, 0.33):
            a.box((1.2, 0.1, 0.022), (x, y + yy, z + 0.011), "Timber", L0)
            for xx in (-0.53, 0.0, 0.53):
                a.box((0.14, 0.1, 0.078), (x + xx, y + yy, z + 0.061), "Timber_Dark", L0)
        for xx in (-0.53, 0.0, 0.53):
            a.box((0.14, 0.8, 0.022), (x + xx, y, z + 0.111), "Timber", L0)
        for yy in (-0.35, -0.175, 0.0, 0.175, 0.35):
            a.box((1.2, 0.1, 0.022), (x, y + yy, z + 0.133), "Timber", L0)
    else:
        a.box((1.2, 0.8, 0.144), (x, y, z + 0.072), "Timber", lods)


def material_stack(A):
    """A builder's yard corner: three stacks of empty EUR pallets (8, 6 and 9 high), a pallet of cement bags under
    shrink film and a white bulk bag of sand - about 3.9 x 1.1 m, up to 1.3 m high."""
    a = A.Asset("material_stack", "prop", "Pallets and materials", "Industrial",
                "Stacked EUR pallets, a pallet of cement sacks and a bulk bag: 3.9 x 1.1 m, 1.3 m high.")
    rnd = random.Random(808)
    stacks = [(-1.35, 0.0, 8), (0.0, 0.1, 6), (1.35, -0.05, 9)]
    for (x, y, n) in stacks:
        for k in range(n):
            dx, dy = rnd.uniform(-0.03, 0.03), rnd.uniform(-0.02, 0.02)
            _pallet(a, x + dx, y + dy, k * 0.144, L0)
        a.box((1.2, 0.8, n * 0.144), (x, y, n * 0.144 / 2), "Timber", (1, 2))
    # The middle stack carries a load of cement bags (shrink-wrapped) instead of more pallets.
    z = 6 * 0.144
    for layer in range(3):
        for j, (bx, by, sw, sd) in enumerate([(-0.3, -0.2, 0.6, 0.4), (0.3, -0.2, 0.6, 0.4), (-0.3, 0.2, 0.6, 0.4), (0.3, 0.2, 0.6, 0.4)]):
            a.box((sw - 0.02, sd - 0.02, 0.12), (bx, 0.1 + by, z + 0.06 + layer * 0.12), "Canvas_White", L0, bevel=0.03)
    a.box((1.2, 0.8, 0.36), (0, 0.1, z + 0.18), "Canvas_White", (1, 2))
    # Bulk bag behind the stacks.
    a.box((0.9, 0.9, 0.95), (0.7, -0.75, 0.475), "Canvas_White", L01, bevel=0.12)
    a.box((0.9, 0.9, 0.95), (0.7, -0.75, 0.475), "Canvas_White", L2)
    a.col_box((1.2, 0.8, 8 * 0.144), (-1.35, 0.0, 4 * 0.144))
    a.col_box((1.2, 0.8, 6 * 0.144 + 0.36), (0.0, 0.1, (6 * 0.144 + 0.36) / 2))
    a.col_box((1.2, 0.8, 9 * 0.144), (1.35, -0.05, 4.5 * 0.144))
    a.col_box((0.9, 0.9, 0.95), (0.7, -0.75, 0.475))
    a.lod_ranges = YARD
    a.ao_height, a.ao_strength = 0.6, 0.3
    return a


BUILDERS = {
    "round_bales_white": round_bales_white,
    "round_bales_green": round_bales_green,
    "firewood_stack": firewood_stack,
    "garden_wall_concrete": garden_wall_concrete,
    "garden_wall_stone": garden_wall_stone,
    "picket_fence": picket_fence,
    "concrete_blocks": concrete_blocks,
    "concrete_pipes": concrete_pipes,
    "skip_green": skip_green,
    "skip_yellow": skip_yellow,
    "transformer_kiosk": transformer_kiosk,
    "material_stack": material_stack,
}
