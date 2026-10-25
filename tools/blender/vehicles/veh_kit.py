"""VEHICLE-ASSETS-01 component kit: tyres and rims, track running gear, weapons and remote
weapon stations, lamps, mirrors and the small exterior equipment every military vehicle
carries. All functions build into ap_vehicle Parts in vehicle space unless they say
`local` (geometry around the part's pivot = origin), and tag geometry per LOD.

Conventions: +Y front, +X right, Z up, metres. A wheel template is local with its axle
along X and its OUTER face towards +X; left-side instances are turned 180 deg about Z.
"""
import math

import bmesh
from mathutils import Matrix, Vector

import ap_lib as A
import ap_vehicle as V

ALL, L01, L0, L12, L2 = A.ALL, A.L01, A.L0, A.L12, A.L2


# ============================================================================ outlines


def arc_pts(yc, zc, r, a0, a1, n):
    """Points on a circle arc in the Y-Z plane, angles in degrees (0 = +Y, 90 = +Z)."""
    return [(yc + r * math.cos(math.radians(a0 + (a1 - a0) * k / n)), zc + r * math.sin(math.radians(a0 + (a1 - a0) * k / n)))
            for k in range(n + 1)]


def arch_flare(p, yc, zc, r, a0, a1, x_in, x_out, depth, mat="Rubber", lods=L01, n=14):
    """Wheel-arch flare: a band of rectangular section following an arch (angles as arc_pts)
    from x_in to x_out, `depth` thick radially."""
    rings = []
    for (y, z) in arc_pts(yc, zc, r, a0, a1, n):
        d = Vector((0, y - yc, z - zc)).normalized()
        o = Vector((0, y, z))
        rings.append([tuple(o + Vector((x_in, 0, 0))), tuple(o + Vector((x_out, 0, 0))),
                      tuple(o + Vector((x_out, 0, 0)) + d * depth), tuple(o + Vector((x_in, 0, 0)) + d * depth)])
    p.a.loft(rings, mat, lods, closed=True, cap=True, recalc=True)


def coil_spring(p, a, b, r, wire=0.014, turns=6, mat="Paint_Black", lods=L0, segs=6):
    a, b = Vector(a), Vector(b)
    ax = (b - a).normalized()
    ref = Vector((1, 0, 0)) if abs(ax.x) < 0.9 else Vector((0, 1, 0))
    u = ax.cross(ref).normalized()
    w = ax.cross(u)
    pts = []
    n = turns * 10
    for k in range(n + 1):
        t = k / n
        an = 2 * math.pi * turns * t
        pts.append(tuple(a.lerp(b, t) + (u * math.cos(an) + w * math.sin(an)) * r))
    p.a.tube(pts, wire, mat, lods, segs=segs, cap=True)


# ============================================================================ wheels


def tyre(p, r_out, width, r_rim, lugs=20, lug_h=0.020, style="xzl", lods=ALL, mat="Tyre"):
    """Military off-road tyre around the X axis at the origin (local part).

    The carcass is a lathe (bead, bulging sidewall, rounded shoulder, crown); the tread is
    real geometry: staggered directional lug blocks across the crown that run over the
    shoulder (style "xzl": Michelin XZL-like block pattern of military trucks / APCs;
    "ndt": chevron bars of non-directional traction tyres)."""
    hw = width / 2
    rb = r_out - lug_h          # crown under the lugs
    side_bulge = r_rim + (rb - r_rim) * 0.55
    prof = [
        (r_rim + 0.005, -hw + 0.03), (r_rim + 0.03, -hw + 0.005), (side_bulge - 0.04, -hw - 0.006),
        (side_bulge + 0.04, -hw - 0.010), (rb - 0.06, -hw + 0.002), (rb - 0.025, -hw + 0.022), (rb - 0.004, -hw + 0.06),
        (rb, -hw * 0.45), (rb, 0.0), (rb, hw * 0.45),
        (rb - 0.004, hw - 0.06), (rb - 0.025, hw - 0.022), (rb - 0.06, hw - 0.002), (side_bulge + 0.04, hw + 0.010),
        (side_bulge - 0.04, hw + 0.006), (r_rim + 0.03, hw - 0.005), (r_rim + 0.005, hw - 0.03),
    ]
    V.revolve(p, prof, (0, 0, 0), (1, 0, 0), mat, lods=(0,), segs=max(36, lugs * 2), smooth=True)
    V.revolve(p, prof[::2] + [prof[-1]], (0, 0, 0), (1, 0, 0), mat, lods=(1,), segs=max(20, lugs), smooth=True)
    V.revolve(p, [(r_rim, -hw), (r_out - 0.01, -hw), (r_out, -hw * 0.6), (r_out, hw * 0.6), (r_out - 0.01, hw), (r_rim, hw)],
              (0, 0, 0), (1, 0, 0), mat, lods=(2,), segs=12, smooth=True)
    pitch = 2 * math.pi / lugs
    for k in range(lugs):
        a0 = k * pitch
        for side in (-1, 1):
            off = 0.0 if side < 0 else pitch * 0.5
            if style == "xzl":
                # Block from the centre line to the shoulder, leaning with the rotation.
                _lug(p, a0 + off, pitch * 0.42, side * 0.015, side * (hw - 0.012), rb, r_out, skew=side * pitch * 0.18, mat=mat)
                # Shoulder block running down the sidewall.
                _shoulder(p, a0 + off + side * pitch * 0.14, pitch * 0.34, side, hw, rb, lug_h, mat)
            else:
                _lug(p, a0 + off, pitch * 0.30, side * 0.03, side * (hw - 0.01), rb, r_out, skew=side * pitch * 0.55, mat=mat)
                _shoulder(p, a0 + off + side * pitch * 0.5, pitch * 0.26, side, hw, rb, lug_h, mat)
    # LOD1: coarser lugs only across the crown (silhouette at 45-180 m).
    for k in range(lugs // 2):
        a0 = k * pitch * 2
        _lug(p, a0, pitch * 0.8, -hw + 0.02, hw - 0.02, rb, r_out, skew=0.0, mat=mat, lods=(1,))


def _lug(p, ang, span, t0, t1, rb, rt, skew, mat, lods=(0,)):
    """One tread block on the crown: angular span `span` centred at `ang`, across the
    width from t0 to t1, sheared by `skew` (radians) from t0 to t1."""
    def pt(a, t, r):
        return (t, -math.sin(a) * r, math.cos(a) * r)
    a_lo, a_hi = ang - span / 2, ang + span / 2
    base = [pt(a_lo, t0, rb - 0.004), pt(a_hi, t0, rb - 0.004), pt(a_hi + skew, t1, rb - 0.004), pt(a_lo + skew, t1, rb - 0.004)]
    top = [pt(a_lo + 0.01, t0, rt), pt(a_hi - 0.01, t0, rt), pt(a_hi + skew - 0.01, t1, rt), pt(a_lo + skew + 0.01, t1, rt)]
    _block(p, base, top, mat, lods)


def _shoulder(p, ang, span, side, hw, rb, h, mat, lods=(0,)):
    def pt(a, t, r):
        return (t, -math.sin(a) * r, math.cos(a) * r)
    a_lo, a_hi = ang - span / 2, ang + span / 2
    t_out = side * (hw + 0.002)
    base = [pt(a_lo, side * (hw - 0.03), rb - 0.004), pt(a_hi, side * (hw - 0.03), rb - 0.004),
            pt(a_hi, t_out, rb - 0.09), pt(a_lo, t_out, rb - 0.09)]
    top = [pt(a_lo + 0.01, side * (hw - 0.03), rb + h * 0.55), pt(a_hi - 0.01, side * (hw - 0.03), rb + h * 0.55),
           pt(a_hi - 0.01, t_out + side * h * 0.35, rb - 0.08), pt(a_lo + 0.01, t_out + side * h * 0.35, rb - 0.08)]
    _block(p, base, top, mat, lods)


def _block(p, base, top, mat, lods):
    verts = list(base) + list(top)
    faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    for i in lods:
        bm, idx = p.a.bms[i], p.a._slot(i, mat)
        vs = [bm.verts.new(Vector(c)) for c in verts]
        fs = [bm.faces.new([vs[k] for k in f]) for f in faces]
        for f in fs:
            f.material_index = idx
        bmesh.ops.recalc_face_normals(bm, faces=fs)


def rim(p, r_rim, width, style="military", nuts=10, mat="Paint_Green", hub_mat="Paint_Green", lods=ALL, beadlock=True):
    """Steel wheel rim at the origin (local), outer face +X: well and flanges, a dished disc
    with hand holes, the hub with wheel nuts, CTIS valve and (military) a bolted beadlock."""
    hw = width / 2
    # Rim barrel + flanges (visible between the tyre beads).
    V.revolve(p, [(r_rim - 0.03, -hw + 0.02), (r_rim + 0.012, -hw + 0.02), (r_rim + 0.012, -hw + 0.045),
                  (r_rim - 0.02, -hw + 0.06), (r_rim - 0.03, hw - 0.06), (r_rim + 0.012, hw - 0.045),
                  (r_rim + 0.012, hw - 0.02), (r_rim - 0.03, hw - 0.02)],
              (0, 0, 0), (1, 0, 0), mat, lods=L01, segs=32, smooth=False)
    # Disc dished outward, then the hub.
    disc_t = hw - 0.09
    V.disc(p, [(r_rim - 0.03, hw - 0.04), (r_rim * 0.80, disc_t + 0.01), (r_rim * 0.55, disc_t), (r_rim * 0.40, disc_t + 0.03),
               (r_rim * 0.33, disc_t + 0.05), (0.0, disc_t + 0.05)], 0.014, (0, 0, 0), (1, 0, 0), mat, lods=L01, segs=32)
    if 2 in lods:
        V.disc(p, [(r_rim, hw - 0.03), (r_rim * 0.35, hw - 0.04), (0.0, hw - 0.04)], 0.02, (0, 0, 0), (1, 0, 0), mat, lods=(2,), segs=10)
    # Hand holes in the disc (dark recesses).
    for k in range(6 if style == "military" else 5):
        a = 2 * math.pi * k / (6 if style == "military" else 5) + 0.3
        rr = r_rim * 0.67
        c = (disc_t + 0.012, -math.sin(a) * rr, math.cos(a) * rr)
        p.a.cyl(r_rim * 0.11, r_rim * 0.11, 0.01, c, "Paint_Black", L0, axis=(1, 0, 0), segs=10)
    # Hub, nuts, cap.
    hub_r = r_rim * 0.30
    V.revolve(p, [(hub_r, disc_t + 0.04), (hub_r, disc_t + 0.09), (hub_r * 0.6, disc_t + 0.11), (hub_r * 0.45, disc_t + 0.16),
                  (0.0, disc_t + 0.17)], (0, 0, 0), (1, 0, 0), hub_mat, lods=L01, segs=20, smooth=True)
    for k in range(nuts):
        a = 2 * math.pi * k / nuts
        rr = hub_r * 0.78
        p.a.cyl(0.016, 0.016, 0.03, (disc_t + 0.10, -math.sin(a) * rr, math.cos(a) * rr), "Steel_Dark", L0, axis=(1, 0, 0), segs=6)
    # CTIS valve and air line (central tyre inflation, standard on military wheels).
    p.a.cyl(0.022, 0.022, 0.06, (disc_t + 0.19, 0, 0), "Steel_Dark", L0, axis=(1, 0, 0), segs=8)
    p.a.tube([(disc_t + 0.17, 0, 0.02), (disc_t + 0.13, 0, r_rim * 0.5), (disc_t + 0.06, 0, r_rim * 0.85)], 0.008, "Steel_Dark", L0, segs=5)
    if beadlock and style == "military":
        ring_r0, ring_r1 = r_rim * 0.80, r_rim * 0.97
        V.ring_band(p, ring_r0, ring_r1, hw - 0.05, hw - 0.025, (0, 0, 0), (1, 0, 0), mat, lods=L0, segs=32)
        for k in range(16):
            a = 2 * math.pi * k / 16
            rr = (ring_r0 + ring_r1) / 2
            p.a.cyl(0.011, 0.011, 0.018, (hw - 0.018, -math.sin(a) * rr, math.cos(a) * rr), "Steel_Dark", L0, axis=(1, 0, 0), segs=6)


def wheel_template(veh, name, r_out, width, r_rim, lugs=20, style="xzl", rim_mat="Paint_Green", nuts=10, beadlock=True):
    """A local wheel part (tyre + rim) used through instances; returns the part."""
    p = veh.part(name, pivot=(0, 0, 0), axis="x", note="template", local=True)
    p.a.ao_strength = 0.0
    tyre(p, r_out, width, r_rim, lugs=lugs, style=style)
    rim(p, r_rim, width, mat=rim_mat, hub_mat=rim_mat, nuts=nuts, beadlock=beadlock)
    return p


def wheels(veh, template, axles, track, z, parent=None, steer=()):
    """Instances the template at every axle (list of y positions, front first) on both
    sides (x = +-track/2), names Wheel_L1 / Wheel_R1 ..., markers WHEEL_* (axle-side)."""
    out = []
    for i, y in enumerate(axles, 1):
        for side, x in (("L", -track / 2), ("R", track / 2)):
            n = "Wheel_%s%d" % (side, i)
            out.append(veh.instance(n, template, parent=parent, pivot=(x, y, z), yaw=180.0 if side == "L" else 0.0,
                                    axis="x", note="spin x" + (", steer z" if i in steer else "")))
            veh.marker("WHEEL_%d%s" % (i, side), (x, y, z), note="wheel centre, axle %d" % i)
    return out


# ============================================================================ tracks


class Belt:
    """Closed track path around circles in the Y-Z plane (seen from +X: Y right = forward,
    Z up). circles: [(y, z, r)] in counter-clockwise order around the loop as seen from +X
    (i.e. front wheel ... over the top ... rear wheel ... along the bottom). The path runs on
    the outside of every circle (track pitch line)."""

    def __init__(self, circles, step=0.02):
        self.c = [(Vector((y, z)), r) for y, z, r in circles]
        n = len(self.c)
        tang = []
        for i in range(n):
            (ca, ra), (cb, rb) = self.c[i], self.c[(i + 1) % n]
            d = cb - ca
            Ld = d.length
            dh = d / Ld
            right = Vector((dh.y, -dh.x))          # outside of a CCW loop
            s = max(-1.0, min(1.0, (ra - rb) / Ld))
            al = math.asin(s)
            nrm = right * math.cos(al) + dh * math.sin(al)
            tang.append((ca + nrm * ra, cb + nrm * rb, nrm))
        pts = []
        for i in range(n):
            pa, pb, nrm = tang[i]
            seg = (pb - pa).length
            k = max(1, int(seg / step))
            for j in range(k):
                pts.append(pa.lerp(pb, j / k))
            # arc on circle i+1 from this tangent's end to the next tangent's start: on a CCW
            # loop the outward normal turns counter-clockwise (angle increasing)
            cb, rb = self.c[(i + 1) % n]
            n0 = nrm
            n1 = tang[(i + 1) % n][2]
            a0 = math.atan2(n0.y, n0.x)
            a1 = math.atan2(n1.y, n1.x)
            da = a1 - a0
            while da < -1e-9:
                da += 2 * math.pi
            while da >= 2 * math.pi:
                da -= 2 * math.pi
            k = max(1, int(abs(da) * rb / step))
            for j in range(k):
                a = a0 + da * j / k
                pts.append(cb + Vector((math.cos(a), math.sin(a))) * rb)
        self.pts = pts
        acc = [0.0]
        for i in range(1, len(pts) + 1):
            acc.append(acc[-1] + (pts[i % len(pts)] - pts[i - 1]).length)
        self.acc = acc
        self.length = acc[-1]

    def at(self, s):
        """(point, unit tangent, outward normal) at arc length s."""
        s = s % self.length
        lo, hi = 0, len(self.acc) - 1
        while hi - lo > 1:
            m = (lo + hi) // 2
            if self.acc[m] <= s:
                lo = m
            else:
                hi = m
        a, b = self.pts[lo % len(self.pts)], self.pts[(lo + 1) % len(self.pts)]
        seg = max(self.acc[lo + 1] - self.acc[lo], 1e-9)
        t = (s - self.acc[lo]) / seg
        d = (b - a).normalized()
        return a.lerp(b, t), d, Vector((d.y, -d.x))


def track_links(p, belt, x, width, pitch, link_fn, lods=(0,), offset=0.0):
    """Places one link per pitch along the belt (count rounded so the loop closes).
    link_fn(p, origin3, fwd3, out3, across3, pitch, width, lods) builds one link."""
    n = max(8, int(round(belt.length / pitch)))
    pt = belt.length / n
    for k in range(n):
        q, d, o = belt.at(offset + k * pt)
        origin = Vector((x, q.x, q.y))
        fwd = Vector((0, d.x, d.y))
        out = Vector((0, o.x, o.y))
        link_fn(p, origin, fwd, out, Vector((1, 0, 0)), pt, width, lods)
    return n


def _oriented_box(p, origin, fwd, out, across, l, w, h, off_f, off_a, off_o, mat, lods):
    """Box l (along fwd) x w (across) x h (along out), centred at origin + offsets."""
    c = origin + fwd * off_f + across * off_a + out * off_o
    rot = Matrix((across, fwd, out)).transposed()
    if rot.determinant() < 0:
        rot = Matrix((-across, fwd, out)).transposed()
    p.a.box((w, l, h), tuple(c), mat, lods, rot=rot)


def steel_link(p, origin, fwd, out, across, pitch, width, lods):
    """Leopard 2 style double-pin steel link (Diehl 570 type): shoe with a rubber pad on the
    ground side, end connectors outboard, a centre guide horn pair on the inside."""
    hw = width / 2
    if 0 in lods:
        _oriented_box(p, origin, fwd, out, across, pitch * 0.80, width - 0.10, 0.045, 0, 0, 0.0, "Steel_Dark", (0,))
        _oriented_box(p, origin, fwd, out, across, pitch * 0.58, width * 0.40, 0.035, 0, -width * 0.25, 0.038, "Rubber", (0,))
        _oriented_box(p, origin, fwd, out, across, pitch * 0.58, width * 0.40, 0.035, 0, width * 0.25, 0.038, "Rubber", (0,))
        for s in (-1, 1):
            # end connectors joining the pins of neighbouring links
            _oriented_box(p, origin, fwd, out, across, pitch * 0.42, 0.06, 0.075, pitch * 0.5, s * (hw - 0.03), 0.004, "Steel_Dark", (0,))
            # pin ends (two pins per link)
            for f in (-0.32, 0.32):
                _oriented_box(p, origin, fwd, out, across, 0.05, width - 0.02, 0.062, pitch * f, 0, -0.013, "Steel_Dark", (0,))
        # guide horns in the centre, inside the loop
        _oriented_box(p, origin, fwd, out, across, pitch * 0.40, 0.045, 0.10, 0, -0.045, -0.07, "Steel_Dark", (0,))
        _oriented_box(p, origin, fwd, out, across, pitch * 0.40, 0.045, 0.10, 0, 0.045, -0.07, "Steel_Dark", (0,))
    if 1 in lods:
        _oriented_box(p, origin, fwd, out, across, pitch * 0.92, width, 0.07, 0, 0, 0.01, "Steel_Dark", (1,))


def rubber_link(p, origin, fwd, out, across, pitch, width, lods):
    """Composite rubber band track segment (Soucy, as on Norwegian CV90): continuous band
    with a chevron cleat outside and a steel-cored guide lug inside."""
    hw = width / 2
    if 0 in lods:
        _oriented_box(p, origin, fwd, out, across, pitch * 1.0, width, 0.028, 0, 0, 0.0, "Rubber", (0,))
        # chevron cleat: two angled bars meeting at the centre
        for s in (-1, 1):
            c = origin + across * (s * hw * 0.48) + out * 0.026
            ax = (across * s + fwd * 0.55).normalized()
            fw = out.cross(ax).normalized()
            rot = Matrix((ax, fw, out)).transposed()
            if rot.determinant() < 0:
                rot = Matrix((-ax, fw, out)).transposed()
            p.a.box((hw * 0.98, pitch * 0.34, 0.03), tuple(c), "Rubber", (0,), rot=rot)
        _oriented_box(p, origin, fwd, out, across, pitch * 0.55, 0.07, 0.085, 0, 0, -0.055, "Rubber", (0,))
    if 1 in lods:
        _oriented_box(p, origin, fwd, out, across, pitch * 1.02, width, 0.05, 0, 0, 0.01, "Rubber", (1,))


def belt_band(p, belt, x, width, thick, mat, lods=(2,), step=0.25):
    """Continuous band (far LOD): a lofted rectangle section around the whole loop."""
    n = max(12, int(belt.length / step))
    rings = []
    for k in range(n):
        q, d, o = belt.at(k * belt.length / n)
        c = Vector((x, q.x, q.y))
        out = Vector((0, o.x, o.y))
        hw = width / 2
        rings.append([tuple(c + Vector((-hw, 0, 0)) - out * thick / 2), tuple(c + Vector((hw, 0, 0)) - out * thick / 2),
                      tuple(c + Vector((hw, 0, 0)) + out * thick / 2), tuple(c + Vector((-hw, 0, 0)) + out * thick / 2)])
    rings.append(rings[0])
    p.a.loft(rings, mat, lods, closed=True, cap=False, recalc=False)


def road_wheel_template(veh, name, r, width, gap=0.09, rim_mat="Paint_Green", tyre_mat="Rubber", spokes=0, holes=6):
    """Dual rubber-tyred road wheel (local, axle X, outer face +X) with the gap for the
    track's centre guide horns."""
    p = veh.part(name, pivot=(0, 0, 0), axis="x", note="template", local=True)
    p.a.ao_strength = 0.0
    hw = width / 2
    tw = (width - gap) / 2       # width of each wheel disc
    for s in (-1, 1):
        t0 = s * gap / 2
        t1 = s * hw
        lo, hi = min(t0, t1), max(t0, t1)
        tr = 0.055               # rubber tyre thickness
        V.revolve(p, [(r - tr, lo + 0.005), (r - 0.012, lo), (r, lo + 0.012), (r, hi - 0.012), (r - 0.012, hi), (r - tr, hi - 0.005)],
                  (0, 0, 0), (1, 0, 0), tyre_mat, lods=L01, segs=32, smooth=True)
        # dished steel / aluminium disc
        dish = 0.035 * s
        face = hi if s > 0 else lo
        V.disc(p, [(r - tr, face), (r * 0.62, face - dish * 0.3), (r * 0.30, face + dish * 0.2), (0.0, face + dish * 0.2)], 0.016 * s,
               (0, 0, 0), (1, 0, 0), rim_mat, lods=L01, segs=28)
        V.revolve(p, [(r - tr - 0.008, lo + 0.004), (r - tr - 0.008, hi - 0.004)], (0, 0, 0), (1, 0, 0), rim_mat, lods=L0, segs=28, smooth=False)
        for k in range(holes):
            a = 2 * math.pi * k / holes + 0.25
            rr = r * 0.48
            p.a.cyl(r * 0.10, r * 0.10, 0.012, ((hi if s > 0 else lo) - dish * 0.05, -math.sin(a) * rr, math.cos(a) * rr), "Paint_Black", L0,
                    axis=(1, 0, 0), segs=10)
    # hub cap with bolts on the outer face
    V.revolve(p, [(r * 0.22, hw + 0.01), (r * 0.18, hw + 0.05), (0.0, hw + 0.06)], (0, 0, 0), (1, 0, 0), rim_mat, lods=L0, segs=16)
    for k in range(8):
        a = 2 * math.pi * k / 8
        p.a.cyl(0.011, 0.011, 0.02, (hw + 0.035, -math.sin(a) * r * 0.16, math.cos(a) * r * 0.16), "Steel_Dark", L0, axis=(1, 0, 0), segs=6)
    p.a.cyl(r, r, width, (0, 0, 0), tyre_mat, lods=(2,), axis=(1, 0, 0), segs=10)
    return p


def sprocket_template(veh, name, r_pitch, width, teeth, mat="Paint_Green", tooth_mat="Steel_Dark"):
    """Drive sprocket (local): two toothed rings with a hub between them."""
    p = veh.part(name, pivot=(0, 0, 0), axis="x", note="template", local=True)
    p.a.ao_strength = 0.0
    ring_t = 0.05
    for s in (-1, 1):
        x0 = s * (width / 2 - ring_t / 2)
        outline = []
        for k in range(teeth):
            a = 2 * math.pi * k / teeth
            for da, rr in ((-0.42, r_pitch - 0.03), (-0.22, r_pitch + 0.045), (0.22, r_pitch + 0.045), (0.42, r_pitch - 0.03)):
                aa = a + da * (2 * math.pi / teeth)
                outline.append((math.sin(aa) * rr, math.cos(aa) * rr))
        V.side_loft(p, [(x0 - ring_t / 2, outline), (x0 + ring_t / 2, outline)], tooth_mat, lods=L0)
        p.a.cyl(r_pitch + 0.02, r_pitch + 0.02, ring_t, (x0, 0, 0), tooth_mat, lods=(1, 2), axis=(1, 0, 0), segs=16)
    V.revolve(p, [(r_pitch - 0.05, -width / 2 + ring_t), (r_pitch * 0.55, -width / 2 + 0.02), (r_pitch * 0.30, 0.0),
                  (r_pitch * 0.55, width / 2 - 0.02), (r_pitch - 0.05, width / 2 - ring_t)], (0, 0, 0), (1, 0, 0), mat, lods=L01, segs=24)
    V.revolve(p, [(r_pitch * 0.32, width / 2 - 0.01), (r_pitch * 0.26, width / 2 + 0.06), (0.0, width / 2 + 0.07)], (0, 0, 0), (1, 0, 0),
              mat, lods=L0, segs=16)
    for k in range(10):
        a = 2 * math.pi * k / 10
        p.a.cyl(0.012, 0.012, 0.02, (width / 2 + 0.04, -math.sin(a) * r_pitch * 0.2, math.cos(a) * r_pitch * 0.2), "Steel_Dark", L0,
                axis=(1, 0, 0), segs=6)
    return p


def running_gear(veh, side, x, roadwheels, rw_r, sprocket, idler, rollers, track_w, pitch, link="steel",
                 parent="Body", rw_template=None, sp_template=None, id_template=None, ro_template=None, ground=0.0):
    """One side's tracked running gear: road wheel / sprocket / idler / roller instances
    (each its own pivot, spin about X) and the track (part Track_<side>) as individual links
    on LOD0, one block per link on LOD1 and a band on LOD2.

    roadwheels: [y] (centres at z = ground + rw_r + track thickness); sprocket / idler:
    (y, z, r_pitch); rollers: [(y, z, r)]."""
    t_th = 0.07 if link == "steel" else 0.05
    zc = ground + rw_r + t_th
    for i, y in enumerate(roadwheels, 1):
        veh.instance("RoadWheel_%s%d" % (side, i), rw_template, parent, (x, y, zc), 180.0 if side == "L" else 0.0, note="spin x")
    veh.instance("Sprocket_%s" % side, sp_template, parent, (x, sprocket[0], sprocket[1]), 180.0 if side == "L" else 0.0, note="spin x (drive)")
    veh.instance("Idler_%s" % side, id_template, parent, (x, idler[0], idler[1]), 180.0 if side == "L" else 0.0, note="spin x")
    for i, (y, z, r) in enumerate(rollers, 1):
        veh.instance("Roller_%s%d" % (side, i), ro_template, parent, (x, y, z), 180.0 if side == "L" else 0.0, note="spin x")
    # Belt circles counter-clockwise seen from +X (Y forward to the right): front (+Y) end
    # first, then over the top towards the rear, around the rear end and back along the bottom.
    front = sprocket if sprocket[0] > idler[0] else idler
    rear = idler if front is sprocket else sprocket
    circ = [(front[0], front[1], front[2] + t_th / 2)]
    for y, z, r in sorted(rollers, key=lambda c: -c[0]):
        circ.append((y, z, r + t_th / 2))
    circ.append((rear[0], rear[1], rear[2] + t_th / 2))
    for y in sorted(roadwheels):
        circ.append((y, zc, rw_r + t_th / 2))
    # Seen from +X with Y to the right, CCW goes front -> top -> rear -> bottom: Y decreasing
    # along the top. Our list is front, rollers (rear-ward), rear, wheels (front-ward): CCW.
    belt = Belt([(c[0], c[1], c[2]) for c in circ])
    tp = veh.part("Track_%s" % side, parent=parent, pivot=(x, 0, zc), axis="", note="track loop (links follow Belt; prepared for UV / link animation)")
    fn = steel_link if link == "steel" else rubber_link
    n = track_links(tp, belt, x, track_w, pitch, fn, lods=(0, 1))
    belt_band(tp, belt, x, track_w, t_th * 1.2, "Steel_Dark" if link == "steel" else "Rubber", lods=(2,))
    # far LOD: the wheel zone inside the band as one block (road wheels have no LOD2)
    ys = sorted(roadwheels)
    tp.box((track_w * 0.85, ys[-1] - ys[0] + 2 * rw_r, 2 * rw_r), (x, (ys[0] + ys[-1]) / 2, zc), "Paint_Green", (2,))
    veh.meta.setdefault("tracks", {})[side] = {"links": n, "pitch_m": round(belt.length / n, 4), "length_m": round(belt.length, 3)}
    return belt


# ============================================================================ weapons


def m2_hmg(p, pos, fwd=(0, 1, 0), lods=L01, mat="Paint_Black"):
    """Browning M2 .50: receiver, feed cover, spade grips, barrel with carrying handle and
    perforated barrel support. pos = rear of the receiver (on the bore line)."""
    o = Vector(pos)
    f = Vector(fwd).normalized()
    up = Vector((0, 0, 1))
    side = f.cross(up).normalized()
    up = side.cross(f).normalized()
    rot = Matrix((side, f, up)).transposed()

    def at(a, b, c):
        return tuple(o + side * a + f * b + up * c)
    p.a.box((0.11, 0.60, 0.17), at(0, 0.30, 0.0), mat, lods, rot=rot)
    p.a.box((0.10, 0.30, 0.05), at(0, 0.40, 0.10), mat, L0, rot=rot)
    p.a.box((0.16, 0.05, 0.12), at(0, -0.02, 0.0), mat, L0, rot=rot)
    for s in (-1, 1):
        p.a.cyl_between(at(s * 0.07, -0.02, 0.0), at(s * 0.07, -0.16, -0.02), 0.016, mat, L0, segs=6)
    p.a.cyl_between(at(0, 0.60, 0.0), at(0, 0.82, 0.0), 0.040, mat, lods, segs=10)
    p.a.cyl_between(at(0, 0.82, 0.0), at(0, 1.62, 0.0), 0.020, mat, lods, segs=8)
    p.a.cyl_between(at(0, 1.58, 0.0), at(0, 1.66, 0.0), 0.028, mat, L0, segs=8)
    p.a.tube([at(0, 0.66, 0.04), at(0, 0.68, 0.13), at(0, 0.86, 0.13), at(0, 0.90, 0.04)], 0.012, mat, L0, segs=5)
    # ammunition can on the left
    p.a.box((0.12, 0.30, 0.20), at(-0.15, 0.30, -0.06), "Paint_OD", L01, rot=rot)


def protector_rws(veh, name, parent, pos, yaw=0.0, gun="m2", mount_parent_pivot=None, scale=1.0, lods=ALL):
    """Kongsberg Protector (RS4-type) remote weapon station: a yawing base with the
    elevating cradle (weapon on the left, sight head on the right, ammunition box behind).
    Parts: <name> (yaw about Z) and <name>_Gun (pitch about X at the trunnions)."""
    x, y, z = pos
    s = scale
    base = veh.part(name, parent=parent, pivot=(x, y, z), axis="z", note="Protector RWS yaw")
    g = veh.part(name + "_Gun", parent=name, pivot=(x, y + 0.05 * s, z + 0.48 * s), axis="x", note="Protector RWS elevation")
    with V.bevel(base, 0.01):
        # turntable and pedestal
        base.a.cyl(0.36 * s, 0.38 * s, 0.10 * s, (x, y, z + 0.05 * s), "Paint_Green", lods, segs=24)
        base.a.box((0.56 * s, 0.62 * s, 0.30 * s), (x, y - 0.05 * s, z + 0.25 * s), "Paint_Green", lods)
        # side frames carrying the cradle trunnions
        for sx in (-1, 1):
            base.a.box((0.07 * s, 0.42 * s, 0.34 * s), (x + sx * 0.30 * s, y + 0.02 * s, z + 0.48 * s), "Paint_Green", L01)
        # ammunition box at the rear
        base.a.box((0.40 * s, 0.26 * s, 0.32 * s), (x - 0.02 * s, y - 0.34 * s, z + 0.36 * s), "Paint_Green", L01)
    base.a.box((0.30 * s, 0.03 * s, 0.22 * s), (x - 0.02 * s, y - 0.49 * s, z + 0.36 * s), "Paint_Black", L0)
    with V.bevel(g, 0.008):
        # sight head (day / thermal cameras, laser rangefinder) on the right
        g.a.box((0.24 * s, 0.38 * s, 0.30 * s), (x + 0.44 * s, y + 0.06 * s, z + 0.50 * s), "Paint_Green", L01)
        # weapon cradle on the left
        g.a.box((0.18 * s, 0.70 * s, 0.16 * s), (x - 0.10 * s, y + 0.12 * s, z + 0.47 * s), "Paint_Green", L01)
    for k, (dz, r) in enumerate(((0.07, 0.055), (-0.06, 0.045))):
        g.a.cyl(r * s, r * s, 0.03 * s, (x + 0.44 * s, y + 0.26 * s, z + (0.50 + dz) * s), "Glass", L0, axis=(0, 1, 0), segs=12)
    g.a.box((0.08 * s, 0.03 * s, 0.05 * s), (x + 0.52 * s, y + 0.255 * s, z + 0.43 * s), "Glass", L0)
    g.a.box((0.04 * s, 0.30 * s, 0.24 * s), (x + 0.33 * s, y + 0.04 * s, z + 0.50 * s), "Paint_Green", L01)
    if gun == "m2":
        m2_hmg(g, (x - 0.10 * s, y - 0.18 * s, z + 0.50 * s), lods=L01)
    elif gun == "mag":
        g.a.box((0.08 * s, 0.50 * s, 0.12 * s), (x - 0.10 * s, y + 0.15 * s, z + 0.50 * s), "Paint_Black", L01)
        g.a.cyl_between((x - 0.10 * s, y + 0.40 * s, z + 0.50 * s), (x - 0.10 * s, y + 0.95 * s, z + 0.50 * s), 0.016, "Paint_Black", L01, segs=8)
    # LOD2: one block for the whole station
    base.a.box((0.70 * s, 0.80 * s, 0.55 * s), (x, y - 0.05 * s, z + 0.30 * s), "Paint_Green", (2,))
    g.a.cyl_between((x - 0.10 * s, y + 0.2 * s, z + 0.5 * s), (x - 0.10 * s, y + 1.4 * s, z + 0.5 * s), 0.04, "Paint_Black", (2,), segs=6)
    return base, g


def smoke_launchers(p, origin, fwd, n=4, spread_deg=12.0, elev=35.0, mat="Paint_Green", lods=L01, tube_r=0.045, length=0.28):
    """A bank of grenade dischargers fanned out horizontally."""
    o = Vector(origin)
    for k in range(n):
        yaw = math.radians((k - (n - 1) / 2) * spread_deg)
        f = Vector(fwd).normalized()
        d = Matrix.Rotation(yaw, 3, "Z") @ f
        d = (d + Vector((0, 0, math.tan(math.radians(elev))))).normalized()
        b = o + Vector((math.cos(yaw), math.sin(yaw), 0)) * 0.0 + Vector((0, 0, 0)) + (Matrix.Rotation(yaw, 3, "Z") @ Vector((0.09 * (k - (n - 1) / 2), 0, 0)))
        p.a.cyl_between(tuple(b), tuple(b + d * length), tube_r, mat, lods, segs=10)
        p.a.cyl(tube_r * 0.8, tube_r * 0.8, 0.01, tuple(b + d * (length + 0.004)), "Paint_Black", L0, axis=tuple(d), segs=10)


# ============================================================================ small equipment


def lamp(p, center, normal, r=0.085, depth=0.06, housing="Paint_Black", lens="Plastic_White", lods=L01, square=False, w=None, h=None):
    """Lamp: housing + lens facing `normal`."""
    c, n = Vector(center), Vector(normal).normalized()
    if square:
        up = Vector((0, 0, 1))
        sd = n.cross(up).normalized()
        rot = Matrix((sd, n, up)).transposed()
        p.a.box((w + 0.03, depth, h + 0.03), tuple(c), housing, lods, rot=rot)
        p.a.box((w, 0.01, h), tuple(c + n * depth / 2), lens, lods, rot=rot)
    else:
        p.a.cyl(r + 0.015, r + 0.01, depth, tuple(c), housing, lods, axis=tuple(n), segs=16)
        p.a.cyl(r, r * 0.95, 0.012, tuple(c + n * depth / 2), lens, lods, axis=tuple(n), segs=16)


def mirror(p, arm_from, head, size=(0.04, 0.24, 0.32), mat="Paint_Black", lods=L01, yaw=0.0):
    p.a.tube([tuple(arm_from), tuple(Vector(head) + Vector((0, 0, -size[2] / 2 + 0.02)))], 0.014, "Steel_Dark", lods, segs=6)
    p.a.box(size, tuple(head), mat, lods, rot=A.rot_z(yaw), bevel=0.01)
    p.a.box((size[0] * 0.3, size[1] - 0.03, size[2] - 0.03), tuple(Vector(head) + Vector((0, -size[0] * 0.55, 0)) @ A.rot_z(-yaw)),
            "Glass", L0, rot=A.rot_z(yaw))


def antenna(p, base, height, mat="Plastic_Black", lods=L01, r=0.006):
    b = Vector(base)
    p.a.cyl(0.035, 0.04, 0.10, tuple(b + Vector((0, 0, 0.05))), "Paint_Black", lods, segs=10)
    p.a.cyl(0.012, 0.012, 0.12, tuple(b + Vector((0, 0, 0.16))), "Steel_Dark", L0, segs=6)
    p.a.cyl(r, r * 0.6, height, tuple(b + Vector((0, 0, 0.22 + height / 2))), mat, L0, segs=5)


def jerrycan(p, center, yaw=0.0, mat="Paint_Green", lods=L0):
    c = Vector(center)
    p.a.box((0.17, 0.35, 0.47), tuple(c), mat, lods, rot=A.rot_z(yaw), bevel=0.015)
    p.a.box((0.04, 0.12, 0.05), tuple(c + Vector((0, 0.06, 0.25)) @ A.rot_z(-yaw)), mat, lods, rot=A.rot_z(yaw))


def tow_eye(p, center, normal, lods=L0, mat="Steel_Dark"):
    c, n = Vector(center), Vector(normal).normalized()
    p.a.box((0.08, 0.10, 0.10), tuple(c), mat, lods)
    p.a.cyl(0.07, 0.07, 0.03, tuple(c + n * 0.08), mat, lods, axis=(0, 0, 1) if abs(n.z) < 0.5 else (1, 0, 0), segs=10)


def shackle(p, center, axis=(1, 0, 0), r=0.06, lods=L0, mat="Paint_Green"):
    c = Vector(center)
    pts = []
    ax = Vector(axis).normalized()
    up = Vector((0, 0, -1))
    sd = ax.cross(up).normalized()
    for k in range(9):
        a = math.pi * k / 8
        pts.append(tuple(c + sd * math.cos(a) * r + up * math.sin(a) * r * 1.3))
    p.a.tube(pts, 0.014, mat, lods, segs=6)


def towing_pintle(p, center, lods=L0, mat="Paint_Black"):
    c = Vector(center)
    p.a.box((0.14, 0.12, 0.14), tuple(c), mat, lods, bevel=0.01)
    p.a.cyl(0.05, 0.05, 0.04, tuple(c + Vector((0, -0.09, 0.0))), "Steel_Dark", lods, axis=(0, 0, 1), segs=10)


def opening(shell, pts, outward, depth=0.40, out=0.10, interior="Paint_White"):
    """Registers a boolean opening through `shell` (a VehicleAsset.shell part): the polygon
    `pts` pushed `out` outside and `depth` into the body along `outward`."""
    ps = [Vector(c) for c in pts]
    n = Vector(outward).normalized()

    def build(tmp):
        tmp.a.loft([[tuple(c + n * out) for c in ps], [tuple(c - n * depth) for c in ps]], "Paint_White", (0,),
                   closed=True, cap=True, recalc=True)
    shell.veh.cut(shell, build, interior)


def cavity(shell, stations, interior="Paint_White"):
    """Registers the interior volume (hull_loft stations, half profiles) cut out of `shell`."""
    def build(tmp):
        V.hull_loft(tmp, stations, "Paint_White", (0,))
    shell.veh.cut(shell, build, interior)


def window(p, corners, outward, frame=0.03, glass="Glass", frame_mat="Rubber", lods=L01, proud=0.012, cut=None, depth=0.35):
    """Armoured window on a body surface: the glass block sits just proud of the surface
    (armoured glass is thick and nearly flush) inside a raised rubber / steel frame band.
    corners on the body surface (any winding); outward = a vector pointing out of the body.
    cut: a shell part to open behind the glass on LOD0 (see-through glass into the cabin);
    LOD1 / LOD2 keep the opaque glass."""
    cs = [Vector(c) for c in corners]
    n = (cs[1] - cs[0]).cross(cs[2] - cs[1]).normalized()
    if n.dot(Vector(outward)) < 0:
        cs.reverse()
        n = -n
    ctr = sum(cs, Vector()) / len(cs)
    inner = [c + (ctr - c).normalized() * frame for c in cs]
    pane = [tuple(c + n * (proud * 0.6)) for c in inner]
    if cut is not None:
        opening(cut, [tuple(c + n * proud * 0.2) for c in inner], n, depth=depth, out=0.06)
        V.plate(p, pane, 0.012, "Glass_Vehicle", tuple(i for i in lods if i == 0))
        V.plate(p, pane, proud * 0.6 + 0.01, glass, tuple(i for i in lods if i != 0))
    else:
        V.plate(p, pane, proud * 0.6 + 0.01, glass, lods)
    k = len(cs)
    for i in range(k):
        a, b = cs[i], cs[(i + 1) % k]
        ai, bi = inner[i], inner[(i + 1) % k]
        V.plate(p, [tuple(a + n * proud), tuple(b + n * proud), tuple(bi + n * proud), tuple(ai + n * proud)],
                proud + 0.006, frame_mat, lods if frame > 0.035 else L0)
