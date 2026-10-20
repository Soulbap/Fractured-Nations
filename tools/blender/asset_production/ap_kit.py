"""Reusable architectural / equipment parts for buildings, modules and props.

Parts are placed through a wall Frame: local x runs along the wall (the viewer's right
when looking at the wall from outside), local y is the outward normal, z is up. A Frame
for the +Y (front) wall of a building is Frame((0, y_front, 0), 0); the -Y wall is yaw 180,
+X wall yaw -90, -X wall yaw 90 (yaw = rotation of the outward normal from +Y, CCW).
"""
import math

from mathutils import Matrix, Vector

import ap_signs as S

ALL = (0, 1, 2)
L01 = (0, 1)
L0 = (0,)


class Frame:
    def __init__(self, origin, yaw_deg):
        a = math.radians(yaw_deg)
        self.o = Vector(origin)
        self.n = Vector((-math.sin(a), math.cos(a), 0.0))
        self.up = Vector((0, 0, 1))
        self.r = self.up.cross(self.n)
        self.yaw = yaw_deg
        self.m = Matrix((self.r, self.n, self.up)).transposed()

    def p(self, x, y, z):
        return tuple(self.o + self.r * x + self.n * y + self.up * z)

    def box(self, a, size, x, y, z, mat, lods=ALL, bevel=0.0):
        """Box centred at local (x, y, z) with local size (along, out, up)."""
        a.box(size, self.p(x, y, z), mat, lods, rot=self.m, bevel=bevel)

    def cyl(self, a, r, length, x, y, z, mat, axis="z", lods=ALL, segs=10, r2=None):
        ax = {"x": self.r, "y": self.n, "z": self.up}[axis]
        a.cyl(r, r if r2 is None else r2, length, self.p(x, y, z), mat, lods, axis=tuple(ax), segs=segs)

    def sign(self, a, name, x, z, w, h, y=0.012, lods=ALL, back=None):
        a.sign([(0, 0), (1, 0), (1, 1), (0, 1)], self.p(x, y, z), tuple(self.r), (0, 0, 1), w, h, S.rect(name), lods=lods,
               back_mat=back, thick=0.01 if back else 0.0)


# ----------------------------------------------------------------------------- openings


def door(a, F, x, w=0.95, h=2.10, z0=0.0, leaf="Paint_Grey", frame="Paint_Black", double=False, canopy=None, light=True):
    """Steel personnel door on a wall: frame, leaf (or two), handle, kick plate, optional
    canopy and lamp. The wall surface is local y = 0."""
    ft = 0.06
    F.box(a, (w + 2 * ft, 0.05, h + ft), x, 0.025, z0 + (h + ft) / 2, frame, L01)
    if double:
        for s in (-1, 1):
            F.box(a, (w / 2 - 0.01, 0.05, h - 0.01), x + s * w / 4, 0.04, z0 + h / 2, leaf, L01, bevel=0.004)
            F.box(a, (0.03, 0.04, 0.16), x + s * 0.06, 0.075, z0 + 1.05, "Steel_Galv", L0)
    else:
        F.box(a, (w - 0.02, 0.05, h - 0.01), x, 0.04, z0 + h / 2, leaf, L01, bevel=0.004)
        F.box(a, (0.12, 0.04, 0.025), x + w / 2 - 0.12, 0.075, z0 + 1.05, "Steel_Galv", L0)
        F.box(a, (0.06, 0.03, 0.08), x + w / 2 - 0.10, 0.07, z0 + 1.05, "Steel_Galv", L0)
        F.box(a, (w - 0.06, 0.012, 0.25), x, 0.068, z0 + 0.16, "Steel_Galv", L0)
        for zz in (0.25, h - 0.25):
            F.box(a, (0.03, 0.05, 0.12), x - w / 2 + 0.01, 0.07, z0 + zz, "Steel_Dark", L0)
    if canopy:
        cw, cd = w + 0.8, canopy
        F.box(a, (cw, cd, 0.06), x, cd / 2, z0 + h + 0.32, "Paint_Grey", L01)
        for s in (-1, 1):
            a.tube([F.p(x + s * (cw / 2 - 0.05), 0.02, z0 + h + 0.05), F.p(x + s * (cw / 2 - 0.05), cd - 0.05, z0 + h + 0.30)], 0.012, "Steel_Dark", L0, segs=6)
    if light:
        F.box(a, (0.16, 0.10, 0.10), x, 0.05, z0 + h + 0.18 + (0.0 if not canopy else -0.02), "Paint_Black", L0)
        F.box(a, (0.12, 0.02, 0.06), x, 0.105, z0 + h + 0.17, "Lamp", L0)


def window(a, F, x, z, w=1.0, h=1.0, bars=True, shutter=False, frame="Paint_White", sill=True):
    """Window with frame, dark glass, mullion, sill; optional security bars or a steel
    shutter (closed upper half)."""
    F.box(a, (w + 0.08, 0.04, h + 0.08), x, 0.02, z, frame, L01)
    F.box(a, (w - 0.04, 0.02, h - 0.04), x, 0.032, z, "Glass", L01)
    F.box(a, (0.04, 0.03, h - 0.04), x, 0.04, z, frame, L0)
    if sill:
        F.box(a, (w + 0.16, 0.10, 0.04), x, 0.05, z - h / 2 - 0.06, "Concrete_Dark", L01)
    if bars:
        n = max(3, int(w / 0.14))
        for i in range(n):
            bx = x - w / 2 + (i + 0.5) * w / n
            F.cyl(a, 0.008, h, bx, 0.09, z, "Steel_Dark", "z", L0, segs=5)
        for zz in (z - h / 2 + 0.05, z + h / 2 - 0.05):
            F.box(a, (w, 0.02, 0.03), x, 0.09, zz, "Steel_Dark", L0)
    if shutter:
        F.box(a, (w + 0.12, 0.05, h * 0.5), x, 0.11, z + h * 0.25, "Paint_OD", L01, bevel=0.005)


def rollup(a, F, x, w, h, z0=0.0, curtain="Paint_Grey", housing="Paint_OD"):
    """Roller shutter door: guide rails, coil housing, slatted curtain (geometry ridges
    on LOD0), bottom bar."""
    F.box(a, (w, 0.04, h), x, 0.03, z0 + h / 2, curtain, L01)
    n = int(h / 0.18)
    for i in range(1, n):
        F.box(a, (w - 0.02, 0.012, 0.02), x, 0.055, z0 + i * h / n, curtain, L0)
    F.box(a, (w, 0.07, 0.08), x, 0.05, z0 + 0.04, "Steel_Dark", L01)
    for s in (-1, 1):
        F.box(a, (0.10, 0.12, h + 0.45), x + s * (w / 2 + 0.05), 0.06, z0 + (h + 0.45) / 2, housing, L01)
    F.box(a, (w + 0.30, 0.42, 0.50), x, 0.21, z0 + h + 0.25, housing, L01, bevel=0.02)
    # Bollards protecting the rails.
    for s in (-1, 1):
        a.cyl(0.085, 0.085, 1.1, F.p(x + s * (w / 2 + 0.35), 0.35, z0 + 0.55), "Paint_Yellow", L01, segs=12)


def ac_unit(a, F, x, z, wall_offset=0.0):
    """Split air-conditioner outdoor unit on a wall bracket (0.85 x 0.32 x 0.60 m)."""
    y = wall_offset + 0.20
    F.box(a, (0.85, 0.32, 0.60), x, y, z, "Paint_White", L01, bevel=0.015)
    a.sign([(0, 0), (1, 0), (1, 1), (0, 1)], F.p(x - 0.12, y + 0.162, z), tuple(F.r), (0, 0, 1), 0.50, 0.50, S.rect("vent_grille"), lods=L0)
    F.box(a, (0.95, 0.40, 0.04), x, y, z - 0.33, "Steel_Galv", L0)
    for s in (-1, 1):
        F.box(a, (0.04, 0.42, 0.04), x + s * 0.40, wall_offset + 0.21, z - 0.36, "Steel_Galv", L0)
        a.tube([F.p(x + s * 0.40, wall_offset + 0.02, z - 0.75), F.p(x + s * 0.40, wall_offset + 0.40, z - 0.37)], 0.012, "Steel_Galv", L0, segs=5)
    a.tube([F.p(x + 0.45, y, z - 0.1), F.p(x + 0.55, wall_offset + 0.05, z - 0.1), F.p(x + 0.55, wall_offset + 0.05, z + 0.6)], 0.025, "Plastic_White", L0, segs=6)


def wall_light(a, F, x, z, angle=25):
    F.box(a, (0.14, 0.08, 0.14), x, 0.04, z, "Paint_Black", L0)
    F.box(a, (0.32, 0.22, 0.06), x, 0.17, z + 0.03, "Paint_Black", L0)
    F.box(a, (0.28, 0.18, 0.01), x, 0.17, z - 0.0, "Lamp", L0)


def floodlight(a, F, x, z):
    F.box(a, (0.06, 0.30, 0.06), x, 0.15, z, "Steel_Dark", L0)
    F.box(a, (0.36, 0.14, 0.28), x, 0.33, z - 0.08, "Paint_Grey", L0, bevel=0.01)
    F.box(a, (0.30, 0.01, 0.20), x, 0.405, z - 0.10, "Lamp", L0)


def steps(a, F, x, w, height, depth_per=0.28, rise=0.17, mat="Concrete", landing=0.0, rails=True):
    """Steps from the ground up to `height` at the wall, going outward (+local y)."""
    n = max(1, round(height / rise))
    r = height / n
    if landing > 0:
        F.box(a, (w, landing, height), x, landing / 2, height / 2, mat, ALL)
    y0 = landing
    for i in range(n - (1 if landing > 0 else 0)):
        top = height - (i + (1 if landing > 0 else 0)) * r
        F.box(a, (w, depth_per, top), x, y0 + depth_per * (i + 0.5), top / 2, mat, L01 if i else ALL)
    if rails:
        run = y0 + depth_per * n
        for s in (-1, 1):
            xr = x + s * (w / 2 - 0.03)
            pts = [F.p(xr, 0.05, height + 0.9), F.p(xr, landing, height + 0.9), F.p(xr, run, 0.9)] if landing else \
                [F.p(xr, 0.05, height + 0.9), F.p(xr, run, 0.9)]
            a.tube(pts, 0.022, "Steel_Galv", L0, segs=6, cap=True)
            for py, pz in ((0.05, height), (run - 0.1, 0.0)):
                a.cyl(0.022, 0.022, 0.9, F.p(xr, py, pz + 0.45), "Steel_Galv", L0, segs=6)


def downpipe(a, F, x, z_top, y=0.08):
    a.cyl(0.05, 0.05, z_top - 0.15, F.p(x, y, (z_top + 0.15) / 2), "Paint_Grey", L0, segs=8)
    a.tube([F.p(x, y, 0.35), F.p(x, y + 0.18, 0.12)], 0.05, "Paint_Grey", L0, segs=8)


def cable_tray(a, F, x0, x1, z, y=0.12):
    F.box(a, (abs(x1 - x0), 0.15, 0.05), (x0 + x1) / 2, y, z, "Steel_Galv", L0)


# ----------------------------------------------------------------------------- roofs


def gable_roof(a, x0, y0, x1, y1, z_eave, pitch, overhang=0.4, mat="Roof_OD", wall_mat=None, thick=0.10,
               ridge_axis="x", fascia="Paint_Grey", lods=ALL):
    """Gable roof over the rectangle; ridge along X (default) or Y. Gable triangles
    above the eaves get wall_mat."""
    t = math.tan(math.radians(pitch))
    if ridge_axis == "x":
        span = (y1 - y0) / 2 + overhang
        cy = (y0 + y1) / 2
        rise = ((y1 - y0) / 2) * t
        drop = overhang * t
        prof = [(-span, -drop), (0, rise), (span, -drop), (span, -drop + thick), (0, rise + thick), (-span, -drop + thick)]
        a.prism(prof, (x0 - overhang, cy, z_eave), (x1 + overhang, cy, z_eave), mat, lods)
        if wall_mat:
            tri = [(-(y1 - y0) / 2, 0), ((y1 - y0) / 2, 0), (0, rise)]
            a.prism(tri, (x0, cy, z_eave), (x1, cy, z_eave), wall_mat, lods)
        # Fascia boards and ridge cap.
        for s in (-1, 1):
            a.box((x1 - x0 + 2 * overhang, 0.04, 0.18), (( x0 + x1) / 2, cy + s * span, z_eave - drop), fascia, L01)
        a.box((x1 - x0 + 2 * overhang, 0.30, 0.06), ((x0 + x1) / 2, cy, z_eave + rise + thick + 0.01), fascia, L01)
        return rise
    span = (x1 - x0) / 2 + overhang
    cx = (x0 + x1) / 2
    rise = ((x1 - x0) / 2) * t
    drop = overhang * t
    prof = [(-span, -drop), (0, rise), (span, -drop), (span, -drop + thick), (0, rise + thick), (-span, -drop + thick)]
    a.prism(prof, (cx, y0 - overhang, z_eave), (cx, y1 + overhang, z_eave), mat, lods)
    if wall_mat:
        tri = [(-(x1 - x0) / 2, 0), ((x1 - x0) / 2, 0), (0, rise)]
        a.prism(tri, (cx, y0, z_eave), (cx, y1, z_eave), wall_mat, lods)
    for s in (-1, 1):
        a.box((0.04, y1 - y0 + 2 * overhang, 0.18), (cx + s * span, (y0 + y1) / 2, z_eave - drop), fascia, L01)
    a.box((0.30, y1 - y0 + 2 * overhang, 0.06), (cx, (y0 + y1) / 2, z_eave + rise + thick + 0.01), fascia, L01)
    return rise


def mono_roof(a, x0, y0, x1, y1, z_low, z_high, overhang=0.3, mat="Roof_OD", thick=0.10, low_side="-y", lods=ALL):
    """Single-pitch roof falling towards low_side ('-y' or '+y')."""
    sgn = -1 if low_side == "-y" else 1
    yl, yh = (y0 - overhang, y1 + overhang) if sgn < 0 else (y1 + overhang, y0 - overhang)
    slope = (z_high - z_low) / (y1 - y0)
    zl = z_low - overhang * slope
    zh = z_high + overhang * slope
    xa, xb = x0 - overhang, x1 + overhang
    a.poly([(xa, yl, zl), (xb, yl, zl), (xb, yh, zh), (xa, yh, zh),
            (xa, yl, zl + thick), (xb, yl, zl + thick), (xb, yh, zh + thick), (xa, yh, zh + thick)],
           [(3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)] if sgn > 0 else
           [(0, 1, 2, 3), (7, 6, 5, 4), (4, 5, 1, 0), (5, 6, 2, 1), (6, 7, 3, 2), (7, 4, 0, 3)], mat, lods)


# ----------------------------------------------------------------------------- equipment


def lattice_mast(a, x, y, height, width=0.45, mat="Steel_Galv", lods_detail=L0):
    """Triangular lattice mast: three legs, zig-zag bracing every metre (LOD0), plain
    legs on LOD1, a single thin prism on LOD2."""
    legs = [(x + width * 0.577 * math.cos(math.radians(90 + 120 * k)), y + width * 0.577 * math.sin(math.radians(90 + 120 * k))) for k in range(3)]
    for lx, ly in legs:
        a.cyl(0.022, 0.022, height, (lx, ly, height / 2), mat, (0, 1), segs=6)
    z = 0.0
    while z < height - 0.5:
        for k in range(3):
            p0, p1 = legs[k], legs[(k + 1) % 3]
            a.tube([(p0[0], p0[1], z), (p1[0], p1[1], z + 0.5)], 0.009, mat, lods_detail, segs=4, cap=False)
            a.tube([(p1[0], p1[1], z + 0.5), (p0[0], p0[1], z + 1.0)], 0.009, mat, lods_detail, segs=4, cap=False)
        z += 1.0
    a.cyl(width * 0.30, width * 0.22, height, (x, y, height / 2), mat, (2,), segs=3)
    return legs


def guy_wires(a, x, y, z_top, radius, n=3, rot=30.0, mat="Steel_Dark"):
    for k in range(n):
        ang = math.radians(rot + 360.0 * k / n)
        gx, gy = x + radius * math.cos(ang), y + radius * math.sin(ang)
        a.tube([(x, y, z_top), (gx, gy, 0.15)], 0.006, mat, L0, segs=4, cap=False)
        a.box((0.25, 0.25, 0.3), (gx, gy, 0.05), "Concrete", (0, 1))


def dish(a, cx, cy, cz, r, yaw, elev, mat="Paint_White"):
    """Parabolic dish (shallow cone shell) on a short arm, facing yaw / elevation."""
    d = Vector((-math.sin(math.radians(yaw)) * math.cos(math.radians(elev)),
                math.cos(math.radians(yaw)) * math.cos(math.radians(elev)), math.sin(math.radians(elev))))
    c = Vector((cx, cy, cz))
    a.cyl(r, r * 0.25, r * 0.35, tuple(c), mat, (0, 1), axis=tuple(-d), segs=20)
    a.cyl(0.02, 0.02, r * 0.9, tuple(c + d * r * 0.45), "Steel_Dark", (0,), axis=tuple(d), segs=5)
    a.box((0.08, 0.08, 0.10), tuple(c + d * r * 0.95), "Paint_Grey", (0,))


def whip(a, x, y, z, length, mat="Plastic_Black"):
    a.cyl(0.012, 0.004, length, (x, y, z + length / 2), mat, (0,), segs=5)
    a.cyl(0.03, 0.03, 0.10, (x, y, z + 0.05), "Steel_Dark", (0, 1), segs=8)
