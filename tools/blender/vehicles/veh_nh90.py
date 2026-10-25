"""VEH-06 NH90 TTH, NATO tactical transport helicopter (NHIndustries; German Army / Finnish /
Belgian TTH configuration: sliding cabin doors both sides, rear ramp, twin nose wheels,
main wheels in sponsons, four-blade main and tail rotors). A NATO reference vehicle, not a
representation of Norway's helicopter fleet.

Reference: assets/military/vehicles/_references/nh90_tth/ (notes.md, manifest.json).
Dimensions used (Leonardo / NHIndustries data): length 19.56 m rotors turning, fuselage
16.13 m, main rotor diameter 16.30 m, height 5.23-5.31 m (tail rotor); tail rotor diameter
3.2 m, mast position, sponson and gear positions estimated from photographs.
"""
import math

from mathutils import Matrix, Vector

import ap_lib as A
import ap_vehicle as V
import veh_kit as K

ALL, L01, L0, L12, L2 = A.ALL, A.L01, A.L0, A.L12, A.L2

ID = "nh90_tth"
PAINT = "Paint_Green"

FUS = 16.13
YN, YT = 8.07, 8.07 - FUS          # nose tip, tail end
MAST = (0.0, 2.05, 4.12)           # rotor hub centre
R_MAIN = 8.15
TR_R = 1.60
TR_SIDE = -1                       # tail rotor on the left (port) side of the fin; stabiliser right
TR_C = (TR_SIDE * 0.42, -7.72, 3.63)
CAB_W = 2.50
CAB_Z0, CAB_Z1 = 0.48, 3.00

# Fuselage sections (y, width, z bottom, z top, superellipse exponent), nose to tail; read from
# the side / front photographs (bulbous radome nose, tall flat-sided cabin, thick rising boom).
STATIONS = [
    (YN, 0.40, 0.98, 1.36, 2.2),
    (YN - 0.20, 1.20, 0.72, 1.72, 2.2),
    (YN - 0.60, 1.85, 0.56, 2.08, 2.4),
    (YN - 1.10, 2.28, 0.49, 2.56, 2.8),
    (YN - 1.80, CAB_W, 0.47, 2.95, 3.4),
    (YN - 2.60, CAB_W, CAB_Z0, CAB_Z1, 4.0),
    (-0.40, CAB_W, CAB_Z0, CAB_Z1, 4.0),
    (-1.40, 2.46, 0.95, CAB_Z1, 3.4),
    (-2.40, 2.10, 1.60, CAB_Z1, 3.0),
    (-3.30, 1.55, 1.95, CAB_Z1, 2.6),
    (-4.60, 1.15, 2.20, 3.05, 2.4),
    (-6.20, 0.90, 2.40, 3.12, 2.3),
    (-7.30, 0.70, 2.55, 3.20, 2.2),
    (YT + 0.15, 0.55, 2.68, 3.25, 2.2),
    (YT, 0.40, 2.78, 3.22, 2.2),
]


def _sec(y):
    st = STATIONS
    if y >= st[0][0]:
        return st[0][1:]
    for (ya, *pa), (yb, *pb) in zip(st[:-1], st[1:]):
        if yb <= y <= ya:
            t = (ya - y) / (ya - yb)
            return tuple(a + (b - a) * t for a, b in zip(pa, pb))
    return st[-1][1:]


def surf(y, t, s=1, inset=0.0):
    """Point on the fuselage surface at station y, `t` degrees round the section from the
    top (0) over the side (90) to the bottom (180), on side s; inset moves it inwards."""
    w, z0, z1, n = _sec(y)
    a = math.radians(90.0 - t)
    c, sn = math.cos(a), math.sin(a)
    zc, hz = (z0 + z1) / 2, (z1 - z0) / 2
    x = (w / 2 - inset) * abs(c) ** (2 / n)
    z = zc + (hz - inset) * math.copysign(abs(sn) ** (2 / n), sn)
    return (s * x, y, z)


def out_dir(y, t, s=1):
    w, z0, z1, n = _sec(y)
    x, _, z = surf(y, t, s)
    return (x, 0.0, z - (z0 + z1) / 2)


def fuselage_stations():
    # extra stations in the nose so the radome / windscreen curvature is smooth
    ys = sorted({y for y, *_ in STATIONS} | {YN - 0.08, YN - 0.38, YN - 0.82, YN - 1.42}, reverse=True)
    return [(y, V.round_half(*_sec(y)[:3], _sec(y)[3], 18)) for y in ys]


def patch(p, s, y0, y1, t0, t1, off, thick, mat, lods=ALL, nu=6, nv=5):
    """A panel (door, hatch) that follows the fuselage: the surface between stations y0..y1 and
    angles t0..t1 on side s, `off` outside the skin, `thick` deep. Closed slab."""
    import bmesh
    for i in lods:
        bm, idx = p.a.bms[i], p.a._slot(i, mat)
        nu_, nv_ = (nu, nv) if i == 0 else (2, 2)

        def grid(o):
            out = []
            for a in range(nu_ + 1):
                row = []
                for b in range(nv_ + 1):
                    y = y0 + (y1 - y0) * a / nu_
                    t = t0 + (t1 - t0) * b / nv_
                    q = Vector(surf(y, t, s))
                    d = Vector(out_dir(y, t, s)).normalized()
                    row.append(bm.verts.new(q + d * o))
                out.append(row)
            return out
        go, gi = grid(off + thick), grid(off)
        fs = []
        for a in range(nu_):
            for b in range(nv_):
                fs.append(bm.faces.new((go[a][b], go[a + 1][b], go[a + 1][b + 1], go[a][b + 1])))
                fs.append(bm.faces.new((gi[a][b + 1], gi[a + 1][b + 1], gi[a + 1][b], gi[a][b])))
        rim = [(a, 0) for a in range(nu_)] + [(nu_, b) for b in range(nv_)] + [(a, nv_) for a in range(nu_, 0, -1)] + \
              [(0, b) for b in range(nv_, 0, -1)]
        for k in range(len(rim)):
            (a0, b0), (a1, b1) = rim[k], rim[(k + 1) % len(rim)]
            fs.append(bm.faces.new((go[a0][b0], gi[a0][b0], gi[a1][b1], go[a1][b1])))
        for f in fs:
            f.material_index = idx
            f.smooth = True
        bmesh.ops.recalc_face_normals(bm, faces=fs)


def surf_window(p, s, corners, cut=None, frame=0.04, proud=0.025, depth=0.30):
    """Window with corners given as (y, t) on side s."""
    pts = [surf(y, t, s) for y, t in corners]
    yc = sum(c[0] for c in corners) / len(corners)
    tc = sum(c[1] for c in corners) / len(corners)
    K.window(p, pts, out_dir(yc, tc, s), frame=frame, proud=proud, cut=cut, depth=depth)


def curved_window(p, s, y0, y1, t0, t1, cut=None, frame=0.035, lods=L01):
    """Window that follows the doubly curved skin: a rectangle in (station y, angle t) space
    on side s. Curved glass (see-through on LOD0), a rubber frame band of four strips, and
    the matching opening through the shell."""
    dy = frame
    dt = frame / max(0.3, _sec((y0 + y1) / 2)[0] / 2) * 57.3
    yy0, yy1 = (y0, y1) if y0 > y1 else (y1, y0)
    tt0, tt1 = min(t0, t1), max(t0, t1)
    gl = (0,) if cut is not None else ()
    patch(p, s, yy0 - dy, yy1 + dy, tt0 + dt, tt1 - dt, 0.004, 0.012, "Glass_Vehicle" if cut is not None else "Glass",
          lods=tuple(i for i in lods if i in gl) if cut is not None else lods, nu=6, nv=6)
    if cut is not None:
        patch(p, s, yy0 - dy, yy1 + dy, tt0 + dt, tt1 - dt, 0.004, 0.014, "Glass", lods=tuple(i for i in lods if i != 0), nu=3, nv=3)
    for a, b, c, d in ((yy0, yy0 - dy, tt0, tt1), (yy1 + dy, yy1, tt0, tt1), (yy0 - dy, yy1 + dy, tt0, tt0 + dt), (yy0 - dy, yy1 + dy, tt1 - dt, tt1)):
        patch(p, s, a, b, c, d, 0.0, 0.022, "Rubber", lods=(0,), nu=4, nv=4)
    if cut is not None:
        ring = []
        n = 6
        for k in range(n):
            ring.append((yy0 - dy * 0.5 - (yy0 - yy1 - dy) * k / n, tt0 + dt * 0.5))
        for k in range(n):
            ring.append((yy1 + dy * 0.5, tt0 + dt * 0.5 + (tt1 - tt0 - dt) * k / n))
        for k in range(n):
            ring.append((yy1 + dy * 0.5 + (yy0 - yy1 - dy) * k / n, tt1 - dt * 0.5))
        for k in range(n):
            ring.append((yy0 - dy * 0.5, tt1 - dt * 0.5 - (tt1 - tt0 - dt) * k / n))
        outer = [tuple(Vector(surf(y, t, s)) + Vector(out_dir(y, t, s)).normalized() * 0.15) for y, t in ring]
        inner = [surf(y, t, s, inset=0.30) for y, t in ring]

        def build(tmp, outer=outer, inner=inner):
            tmp.a.loft([outer, inner], "Paint_White", (0,), closed=True, cap=True, recalc=True)
        cut.veh.cut(cut, build, "Paint_Grey")


def surf_opening(sh, s, corners, depth=0.35):
    pts = [surf(y, t, s) for y, t in corners]
    yc = sum(c[0] for c in corners) / len(corners)
    tc = sum(c[1] for c in corners) / len(corners)
    K.opening(sh, pts, out_dir(yc, tc, s), depth=depth, out=0.15, interior="Paint_Grey")


def airfoil_half(chord, thick, y_le):
    """Symmetric airfoil (plan view) half outline: leading edge (x = 0) -> right surface ->
    trailing edge (x = 0); chord along -Y from y_le."""
    pts = []
    for k in range(9):
        t = k / 8
        x = thick / 2 * 2.9 * (math.sqrt(max(t, 1e-6)) * 0.30 - 0.126 * t - 0.351 * t * t + 0.284 * t ** 3 - 0.1036 * t ** 4)
        pts.append((0.0 if k in (0, 8) else max(x, 0.002), y_le - chord * t))
    return pts


def blade(p, angle_deg, r0, r1, chord, z, lods=ALL):
    """One main rotor blade along the direction angle (deg about Z from +Y): airfoil sections
    lofted from the root to the swept, tapered NH90 tip; slight pitch and droop."""
    a = math.radians(angle_deg)
    d = Vector((-math.sin(a), math.cos(a), 0))       # span direction
    side = Vector((math.cos(a), math.sin(a), 0))     # chord direction (leading edge towards +side)
    rings = []
    span = [(r0, chord * 0.75, 0.0), (r0 + 0.35, chord, 0.0), (r1 - 0.85, chord, 0.0), (r1 - 0.30, chord * 0.80, -0.10), (r1, chord * 0.35, -0.32)]
    for r, c, sweep in span:
        droop = -0.012 * (r / r1) ** 2 * r
        pitch = math.radians(6.0 - 4.0 * r / r1)
        base = Vector(MAST) + d * r + Vector((0, 0, z - MAST[2] + droop)) + side * sweep
        ring = []
        th = 0.11 * c
        for k in range(12):
            tt = k / 12 * 2 * math.pi
            # ellipse-like airfoil around (leading edge at +0.25c, trailing edge at -0.75c)
            cx = 0.5 * c * math.cos(tt) - 0.25 * c
            cy = th * 0.5 * math.sin(tt) * (1.0 - 0.45 * max(0.0, -math.cos(tt)))
            off = side * cx + Vector((0, 0, 1)) * cy
            off = Matrix.Rotation(pitch, 3, d) @ off
            ring.append(tuple(base + off))
        rings.append(ring)
    p.a.loft(rings, "Paint_Black", lods, closed=True, cap=True, smooth=True, recalc=True)


def build():
    veh = V.VehicleAsset(ID, "NH90 TTH", "Military helicopter",
                         "NHIndustries NH90 TTH tactical transport helicopter (NATO reference configuration).")
    veh.lod_ranges = [[0, 60], [60, 260], [260, 3000]]
    b = veh.part("Body", note="fuselage")
    sh = veh.shell("Body")
    # ------------------------------------------------------------ fuselage (smooth loft) with the cockpit / cabin volume
    V.hull_loft(sh, fuselage_stations(), PAINT, ALL, smooth=True)

    def inner(y, top_cut=0.0, floor=None):
        w, z0, z1, n = _sec(y)
        return V.round_half(w - 0.14, (floor if floor is not None else z0 + 0.24), z1 - 0.07 - top_cut, n, 12)
    K.cavity(sh, [(YN - 0.95, inner(YN - 0.95, 0.05, 0.80)), (YN - 1.80, inner(YN - 1.80, 0.0, 0.72)), (-0.40, inner(-0.40, 0.0, 0.72)),
                  (-1.40, inner(-1.40, 0.0, 1.10)), (-1.95, inner(-1.95, 0.0, 1.45))], "Paint_Grey")
    # sponsons with the main gear bays
    for s in (-1, 1):
        V.pod_loft(b, s * (CAB_W / 2 - 0.05), [(2.95, 0.10, 0.88, 1.02), (2.55, 1.10, 0.62, 1.30), (0.90, 1.25, 0.55, 1.36),
                                                (-0.20, 1.00, 0.65, 1.30), (-0.70, 0.12, 0.95, 1.08)], PAINT, ALL, n=2.4)
    # ------------------------------------------------------------ cockpit glazing (on the skin, see-through on LOD0)
    for s in (-1, 1):
        curved_window(b, s, YN - 0.46, YN - 1.40, 3, 60, cut=sh)          # windscreen
        curved_window(b, s, YN - 0.92, YN - 1.92, 64, 108, cut=sh)        # side window
        curved_window(b, s, YN - 0.52, YN - 0.98, 110, 142, cut=sh)       # chin window
        curved_window(b, s, YN - 1.50, YN - 2.05, 8, 40, cut=sh, frame=0.03)   # roof window
    b.box((0.04, 0.10, 0.45), (0, YN - 0.30, 1.70), "Steel_Dark", L0, rot=A.rot_x(-35))                          # upper wire cutter
    # cockpit doors (pilot / co-pilot), hinged at the front edge, following the skin
    for tag, s in (("Pilot", 1), ("CoPilot", -1)):
        y0, y1 = YN - 1.98, YN - 2.92
        d = veh.part("Door_" + tag, parent="Body", pivot=surf(y0, 95, s), axis="z", note="cockpit door, hinge at the front")
        ds = veh.shell("Door_" + tag)
        patch(ds, s, y0, y1, 52, 150, 0.004, 0.03, PAINT)
        surf_opening(sh, s, [(y0 - 0.04, 55), (y1 + 0.04, 55), (y1 + 0.04, 147), (y0 - 0.04, 147)])
        pts = [(y0 - 0.10, 64), (y1 + 0.10, 64), (y1 + 0.10, 100), (y0 - 0.10, 100)]
        w = [tuple(Vector(surf(y, t, s)) + Vector(out_dir(y, t, s)).normalized() * 0.034) for y, t in pts]
        K.window(d, w, out_dir((y0 + y1) / 2, 82, s), frame=0.035, proud=0.02, cut=ds, depth=0.08)
        hp = Vector(surf(y1 + 0.12, 112, s)) + Vector((s * 0.06, 0, 0))
        V.handle(d, tuple(hp), tuple(hp + Vector((0, 0.16, 0))), 0.03, (s, 0, 0), lods=L0)
    # ------------------------------------------------------------ cabin sliding doors, windows, ramp
    for tag, s in (("L", -1), ("R", 1)):
        y0, y1 = 3.62, 1.86
        d = veh.part("Door_Slide_" + tag, parent="Body", pivot=surf(y0, 90, s), axis="slide -y",
                     note="sliding cabin door (slides aft along the fuselage)")
        ds = veh.shell("Door_Slide_" + tag)
        patch(ds, s, y0, y1, 40, 146, 0.006, 0.035, PAINT)
        surf_opening(sh, s, [(y0 - 0.05, 43), (y1 + 0.05, 43), (y1 + 0.05, 143), (y0 - 0.05, 143)])
        pts = [(3.38, 62), (2.82, 62), (2.82, 92), (3.38, 92)]
        w = [tuple(Vector(surf(y, t, s)) + Vector(out_dir(y, t, s)).normalized() * 0.04) for y, t in pts]
        K.window(d, w, (s, 0, 0), frame=0.04, proud=0.02, cut=ds, depth=0.08)
        for tt, rr in ((38, 0.022), (148, 0.018)):
            ra, rb = Vector(surf(y0 + 0.05, tt, s)), Vector(surf(-0.30, tt, s))
            b.cyl_between(tuple(ra + Vector((s * 0.03, 0, 0))), tuple(rb + Vector((s * 0.03, 0, 0))), rr, "Steel_Dark", L01, segs=6)
        for y0w in (1.36, 0.36):
            surf_window(b, s, [(y0w, 62), (y0w - 0.62, 62), (y0w - 0.62, 92), (y0w, 92)], cut=sh)
        hp = Vector(surf(y1 + 0.10, 100, s)) + Vector((s * 0.06, 0, 0))
        V.handle(d, tuple(hp), tuple(hp + Vector((0, 0, 0.25))), 0.03, (s, 0, 0), lods=L0)
    rp = veh.part("Ramp", parent="Body", pivot=(0.0, -0.45, 0.62), axis="x", note="rear ramp, hinge at the lower front edge")
    rp.loft([[(-0.95, -0.45, 0.60), (0.95, -0.45, 0.60), (0.95, -0.45, 0.66), (-0.95, -0.45, 0.66)],
             [(-0.85, -2.45, 1.62), (0.85, -2.45, 1.62), (0.85, -2.40, 1.70), (-0.85, -2.40, 1.70)]], PAINT, ALL, closed=True, cap=True, recalc=True)
    ramp_n = Vector((0, -1.02, -2.0)).normalized()
    K.opening(sh, [(-0.86, -0.50, 0.70), (0.86, -0.50, 0.70), (0.80, -2.36, 1.62), (-0.80, -2.36, 1.62)], tuple(ramp_n), depth=0.45, out=0.35,
              interior="Paint_Grey")
    # ------------------------------------------------------------ landing gear
    for s in (-1, 1):
        x = s * 1.60
        b.box((0.16, 0.70, 0.12), (s * 1.42, 1.40, 0.62), "Steel_Dark", L01, rot=A.rot_x(-12))   # trailing arm
        b.cyl_between((s * 1.40, 1.70, 1.20), (s * 1.52, 1.20, 0.72), 0.06, "Steel_Dark", L01, segs=10)  # oleo
        V.revolve(b, [(0.20, -0.11), (0.33, -0.12), (0.36, -0.06), (0.36, 0.06), (0.33, 0.12), (0.20, 0.11), (0.20, -0.11)],
                  (x, 1.15, 0.36), (1, 0, 0), "Rubber", ALL, segs=20, smooth=True)
        V.disc(b, [(0.20, s * 0.11 + 0.0), (0.0, s * 0.10)], 0.02 * s, (x, 1.15, 0.36), (1, 0, 0), "Paint_Grey", L01, segs=16)
    for s in (-1, 1):
        V.revolve(b, [(0.12, -0.08), (0.24, -0.09), (0.26, -0.04), (0.26, 0.04), (0.24, 0.09), (0.12, 0.08), (0.12, -0.08)],
                  (s * 0.17, YN - 1.25, 0.26), (1, 0, 0), "Rubber", ALL, segs=16, smooth=True)
    b.cyl_between((0, YN - 1.30, 0.80), (0, YN - 1.25, 0.30), 0.06, "Steel_Dark", L01, segs=10)
    b.box((0.40, 0.08, 0.08), (0, YN - 1.25, 0.28), "Steel_Dark", L01)
    # ------------------------------------------------------------ nose equipment, antennas, lights
    b.sphere(0.20, (0, YN - 0.95, 0.52), "Paint_Grey", L01, segs=16, rings=10)     # FLIR turret
    b.cyl(0.08, 0.08, 0.20, (0, YN - 0.95, 0.66), "Paint_Grey", L01, segs=10)
    b.sphere(0.07, (0, YN - 0.82, 0.48), "Glass", L0, segs=10, rings=6)
    for s in (-1, 1):
        b.box((0.03, 0.40, 0.05), (s * 0.20, YN - 0.40, 1.95), "Steel_Dark", L0, rot=A.rot_x(-40))   # wire cutters
        K.lamp(b, (s * 0.5, YN - 1.60, 0.40), (0, 0.2, -1), r=0.06, depth=0.05, lods=L0)
        b.box((0.04, 0.10, 0.06), surf(-2.00, 66, s), "Reflector_Red" if s < 0 else "Plastic_White", L0)
        K.antenna(b, (s * 0.50, 5.6, 2.90), 0.45)
    b.box((0.05, 1.4, 0.06), (0, -3.0, 3.10), "Paint_Black", L0)                   # HF antenna rail on the boom
    b.cyl(0.03, 0.03, 0.9, (0, 0.6, 0.30), "Paint_Black", L0, axis=(0, 0, 1), segs=6)
    # ------------------------------------------------------------ engine cowlings, intakes, exhausts, mast fairing
    for s in (-1, 1):
        V.pod_loft(b, s * 0.55, [(4.10, 0.20, CAB_Z1 - 0.06, CAB_Z1 + 0.10), (3.70, 0.82, CAB_Z1 - 0.06, CAB_Z1 + 0.55),
                                 (1.40, 0.90, CAB_Z1 - 0.06, CAB_Z1 + 0.68), (-0.30, 0.80, CAB_Z1 - 0.06, CAB_Z1 + 0.60),
                                 (-1.30, 0.30, CAB_Z1 - 0.06, CAB_Z1 + 0.25)], PAINT, ALL)
        b.cyl(0.20, 0.20, 0.08, (s * 0.55, 3.73, CAB_Z1 + 0.30), "Paint_Black", L01, axis=(0, 1, 0), segs=16)   # intake
        V.revolve(b, [(0.17, 0.0), (0.21, 0.35), (0.24, 0.55)], (s * 0.85, -0.55, CAB_Z1 + 0.40), (s * 0.7, -0.6, 0.35),
                  "Paint_Black", L01, segs=14)                                       # exhaust
    V.pod_loft(b, 0.0, [(3.6, 0.10, CAB_Z1 - 0.05, CAB_Z1 + 0.05), (3.0, 0.70, CAB_Z1 - 0.05, CAB_Z1 + 0.85), (1.2, 0.80, CAB_Z1 - 0.05, CAB_Z1 + 0.95),
                        (0.2, 0.40, CAB_Z1 - 0.05, CAB_Z1 + 0.55), (-0.5, 0.10, CAB_Z1 - 0.05, CAB_Z1 + 0.05)], PAINT, ALL, n=2.2)
    # ------------------------------------------------------------ tail: fin, stabiliser, bumper
    fin = []
    for z, chord, y_le, th in ((3.05, 1.90, -6.30, 0.28), (4.10, 1.30, -7.05, 0.22), (4.85, 0.95, -7.55, 0.17)):
        fin.append((z, airfoil_half(chord, th, y_le)))
    V.plan_loft(b, fin, PAINT, ALL, smooth=True)
    # horizontal stabiliser (on the side opposite the tail rotor), airfoil in the side view
    def stab_outline(chord, y_le, z, th):
        up = [(y, z + th / 2 * math.sin(math.pi * k / 8) * (1.0 - 0.35 * k / 8)) for k, (_, y) in enumerate(airfoil_half(chord, th, y_le))]
        lo = [(y, z - th / 2 * math.sin(math.pi * k / 8) * (1.0 - 0.35 * k / 8)) for k, (_, y) in enumerate(airfoil_half(chord, th, y_le))]
        return up + list(reversed(lo))[1:-1]
    sx0, sx1 = sorted((-TR_SIDE * 0.20, -TR_SIDE * 1.80))
    st0, st1 = stab_outline(1.00, -6.55, 2.92, 0.10), stab_outline(0.70, -6.75, 3.04, 0.07)
    V.side_loft(b, [(sx0, st0 if sx0 == -TR_SIDE * 0.20 else st1), (sx1, st1 if sx0 == -TR_SIDE * 0.20 else st0)], PAINT, ALL, smooth=True)
    b.box((0.10, 0.30, 0.25), (0, -6.6, 2.42), "Steel_Dark", L01)                    # tail bumper
    b.cyl(0.18, 0.18, 0.38, (TR_SIDE * 0.21, TR_C[1], TR_C[2]), PAINT, L01, axis=(1, 0, 0), segs=14)   # tail gearbox
    # ------------------------------------------------------------ main rotor: mast, hub, blades (separate)
    mr = veh.part("MainRotor", parent="Body", pivot=MAST, axis="z", note="main rotor (spins about Z, counter-clockwise seen from above)")
    mr.cyl(0.16, 0.16, 0.55, (MAST[0], MAST[1], MAST[2] - 0.30), "Steel_Dark", ALL, segs=14)
    mr.cyl(0.42, 0.42, 0.06, (MAST[0], MAST[1], MAST[2] - 0.45), "Steel_Dark", L01, segs=20)      # swashplate
    for k in range(4):
        a = math.radians(45 + 90 * k)
        d = Vector((-math.sin(a), math.cos(a), 0))
        c = Vector(MAST)
        mr.box((0.30, 0.75, 0.10), tuple(c + d * 0.42), "Steel_Dark", ALL, rot=A.rot_z(math.degrees(a)))       # hub arm
        mr.cyl_between(tuple(c + d * 0.25 + Vector((0, 0, 0.12))), tuple(c + d * 0.70 + Vector((0, 0, 0.08))), 0.045, "Paint_Black", L0, segs=8)  # damper
        mr.cyl_between(tuple(c + d * 0.25 + Vector((0, 0, -0.30))), tuple(c + d * 0.62 + Vector((0, 0, -0.05))), 0.025, "Steel_Dark", L0, segs=6)  # pitch link
    mr.cyl(0.22, 0.12, 0.25, (MAST[0], MAST[1], MAST[2] + 0.15), "Steel_Dark", L01, segs=14)
    for k in range(4):
        bl = veh.part("Blade_%d" % (k + 1), parent="MainRotor", pivot=MAST, axis="pitch along span", note="main rotor blade")
        blade(bl, 45 + 90 * k, 0.75, R_MAIN, 0.60, MAST[2])
    # ------------------------------------------------------------ tail rotor (separate, own pivot)
    tr = veh.part("TailRotor", parent="Body", pivot=TR_C, axis="x", note="tail rotor (spins about X)")
    V.revolve(tr, [(0.0, -0.10), (0.14, -0.10), (0.14, 0.08), (0.06, 0.16), (0.0, 0.16)], TR_C, (TR_SIDE, 0, 0), "Steel_Dark", ALL, segs=12)
    for k in range(4):
        a = math.radians(45 + 90 * k)
        d = Vector((0, math.cos(a), math.sin(a)))
        c = Vector(TR_C) + Vector((TR_SIDE * 0.05, 0, 0))
        rings = []
        for r, ch in ((0.15, 0.20), (0.40, 0.26), (TR_R - 0.05, 0.24), (TR_R, 0.14)):
            base = c + d * r
            side = Vector((0, -math.sin(a), math.cos(a)))
            ring = [tuple(base + side * (0.5 * ch * math.cos(t)) + Vector((1, 0, 0)) * (0.022 * math.sin(t))) for t in
                    [2 * math.pi * q / 8 for q in range(8)]]
            rings.append(ring)
        tr.loft(rings, "Paint_Black", ALL, closed=True, cap=True, smooth=True, recalc=True)
    # ------------------------------------------------------------ interior (seen through the glazing / open doors)
    b.box((1.80, 0.40, 0.50), (0, YN - 1.20, 1.55), "Plastic_Black", L0)            # instrument panel
    for s in (-1, 1):
        b.box((0.55, 0.55, 0.12), (s * 0.55, YN - 2.10, 1.05), "Canvas_Green", L0)
        b.box((0.55, 0.12, 0.80), (s * 0.55, YN - 2.42, 1.45), "Canvas_Green", L0)
        b.box((0.40, 3.60, 0.10), (s * 0.95, 1.20, 1.00), "Canvas_Green", L0)        # troop seats along the walls
        b.box((0.06, 3.60, 0.55), (s * 1.12, 1.20, 1.35), "Canvas_Green", L0)
    b.box((2.0, 0.05, 1.9), (0, YN - 2.70, 1.60), "Paint_Black", L0)                # cockpit bulkhead
    # ------------------------------------------------------------ collision, markers, metadata
    veh.col_between((-1.25, -1.0, 0.48), (1.25, YN - 0.8, 2.98))
    veh.col_between((-0.9, YN - 0.8, 0.8), (0.9, YN, 2.0))
    veh.col_between((-0.5, YT, 2.0), (0.5, -1.0, 3.3))
    veh.col_between((-0.15, -7.9, 3.0), (0.15, -6.4, 5.1))
    veh.col_between((-1.9, -0.6, 0.0), (1.9, 3.0, 1.35))
    for tag, s in (("L", -1), ("R", 1)):
        veh.marker("DOOR_" + tag, (s * 2.2, 2.7, 0.0), yaw=90 if s < 0 else -90, note="sliding cabin door")
    veh.marker("DOOR_RAMP", (0.0, -3.4, 0.0), note="rear ramp")
    veh.marker("SEAT_PILOT", (0.55, YN - 2.10, 1.15))
    veh.marker("SEAT_COPILOT", (-0.55, YN - 2.10, 1.15))
    for k in range(10):
        s = -1 if k % 2 == 0 else 1
        veh.marker("SEAT_%d" % (k + 1), (s * 0.95, 2.80 - (k // 2) * 0.70, 1.10), yaw=-90 * s, note="troop seat")
    veh.marker("ROTOR_MAIN", MAST, note="main rotor hub (spin about Z)")
    veh.marker("ROTOR_TAIL", TR_C, note="tail rotor hub (spin about X)")
    veh.meta.update({
        "reference": "NH90 TTH (NHIndustries), NATO transport configuration",
        "dimensions_m": {"fuselage": FUS, "main_rotor_d": 2 * R_MAIN, "tail_rotor_d": 2 * TR_R, "mast_y": MAST[1], "hub_z": MAST[2]},
        "paint": PAINT,
    })
    veh.qa = {"tol": 0.08}
    return veh


BUILDERS = {ID: build}
DETAILS = {ID: {
    "rotor_head": (MAST, 4.0, 40, 20, 50),
    "nose": ((0, YN - 1.5, 1.6), 6.0, 30, 10, 50),
}}
