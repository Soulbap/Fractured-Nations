"""Filled sandbags as they lie in a wall (WORLD-DETAIL-02), shared by the static asset library (ap_kit.sandbag*) and the
WORLD-BASE-01 structures (make_buildings.py). Pure Python: geometry and layouts only, the callers turn them into meshes.

Reference photographs (Wikimedia Commons, docs/WORLD-DETAIL-02_REPORT.md): a filled polypropylene bag is a pillow, not a
ball - flat where it presses on the bags below and above, plump rounded long sides, one end sewn square and the other folded
or tied into a flattened flap. In a wall the bags lie tight in running bond (each course shifted half a bag), every course
pressed a little into the one below: no light between the bags.

Sizes: an empty bag 0.36 x 0.75 m fills to about 0.60 x 0.32 x 0.14 m. A course is 0.12 m high (the bags overlap
0.02 m: pressed), bags in a course 0.56 m apart (their rounded ends overlap: no gap).
"""
import math

BAG = (0.60, 0.32, 0.14)
COURSE = 0.12
PITCH = 0.56


def _spow(v, e):
    return math.copysign(abs(v) ** e, v)


RINGS = (-1.0, -0.9, -0.62, -0.22, 0.22, 0.62, 0.9, 1.0)


def pillow(size=BAG, tie=1, rnd=None, rings=RINGS, around=10):
    """Vertices and faces of one bag in its own frame: long axis x (centred), width y, height z (centre at mid height).
    tie = +1 / -1: the folded end at +x / -x. The ends are blunt (a filled bag's sewn end is nearly square, rounded at the
    corners), closed by a slightly domed fan. Faces are quads round the body and triangle fans at the two ends, wound
    outward."""
    L, W, H = size
    if rnd is not None:
        L *= rnd.uniform(0.96, 1.03)
        W *= rnd.uniform(0.95, 1.04)
        H *= rnd.uniform(0.93, 1.05)
    verts = []
    for s in rings:
        # Length profile: full along the middle, drawn in to a blunt end (0.6 of the full section at the seam).
        f = 0.6 + 0.4 * (1.0 - abs(s) ** 3.0) ** (1.0 / 3.0)
        g = f
        # The tied end: folded flat (lower, a little wider) over its last fifth.
        u = s * tie
        if u > 0.6:
            k = (u - 0.6) / 0.4
            g = f * (1.0 - 0.45 * k)
            f = min(1.05, f * (1.0 + 0.15 * k))
        x = s * L / 2
        for i in range(around):
            t = (i + 0.5) * math.tau / around
            y = W / 2 * f * _spow(math.cos(t), 0.42)
            z = H / 2 * g * _spow(math.sin(t), 0.42)
            # Pressed flat on the bag below and the one above.
            z = max(-H * 0.46, min(H * 0.47, z))
            verts.append((x, y, z))
    n = len(rings)
    verts.append((-L / 2 - 0.015, 0.0, -H * (0.12 if tie < 0 else 0.0)))
    verts.append((L / 2 + 0.015, 0.0, -H * (0.12 if tie > 0 else 0.0)))
    p0, p1 = len(verts) - 2, len(verts) - 1
    faces = []
    for r in range(n - 1):
        for i in range(around):
            j = (i + 1) % around
            a, b = r * around + i, r * around + j
            c, d = (r + 1) * around + j, (r + 1) * around + i
            faces.append((a, b, c, d))
    last = (n - 1) * around
    for i in range(around):
        j = (i + 1) % around
        faces.append((p0, j, i))
        faces.append((last + i, last + j, p1))
    return verts, faces


def placed(verts, centre, yaw_deg, tilt=(0.0, 0.0)):
    """The bag's vertices turned by yaw (about z) after a small roll / pitch (degrees) and moved to centre."""
    cy, sy = math.cos(math.radians(yaw_deg)), math.sin(math.radians(yaw_deg))
    rx, ry = math.radians(tilt[0]), math.radians(tilt[1])
    cx_, sx_ = math.cos(rx), math.sin(rx)
    cp, sp = math.cos(ry), math.sin(ry)
    out = []
    for (x, y, z) in verts:
        y, z = y * cx_ - z * sx_, y * sx_ + z * cx_          # roll about the bag's long axis
        x, z = x * cp + z * sp, -x * sp + z * cp             # pitch
        out.append((centre[0] + x * cy - y * sy, centre[1] + x * sy + y * cy, centre[2] + z))
    return out


def course(x0, x1, row, z, k, rnd, along="x", size=BAG):
    """One course of bags lying end to end from x0 to x1 (along x at y = row, or along y at x = row), centre height z, the
    k-th course of a wall (odd courses shifted half a bag). The end bags are shortened to finish flush. Returns
    [(centre, yaw_deg, size, tie)]."""
    lo, hi = min(x0, x1), max(x0, x1)
    out = []
    c = lo + (PITCH / 2 if k % 2 == 0 else 0.0)
    while c - PITCH / 2 < hi - 0.02:
        a = max(c - PITCH / 2, lo)
        b = min(c + PITCH / 2, hi)
        if b - a > 0.14:
            L = (b - a) + (size[0] - PITCH)
            m = (a + b) / 2 + rnd.uniform(-0.008, 0.008)
            w = rnd.uniform(-0.012, 0.012)
            centre = (m, row + w, z) if along == "x" else (row + w, m, z)
            yaw = (0.0 if along == "x" else 90.0) + rnd.uniform(-2.0, 2.0)
            out.append((centre, yaw, (L, size[1], size[2]), 1 if (k + int(m / PITCH)) % 2 else -1))
        c += PITCH
    return out


def wall(x0, x1, row, courses, rnd, along="x", rows=(0.0,), z0=0.0, size=BAG, gaps=None):
    """A wall of bags: `rows` side by side (offsets across the wall), `courses` high, from z0. gaps: optional
    [(a, b, from_course)] spans left open from that course up (firing ports). Returns [(centre, yaw, size, tie)]."""
    out = []
    for k in range(courses):
        z = z0 + size[2] / 2 + k * COURSE
        spans = [(min(x0, x1), max(x0, x1))]
        for (ga, gb, kk) in gaps or []:
            if k >= kk:
                nxt = []
                for (sa, sb) in spans:
                    if gb <= sa or ga >= sb:
                        nxt.append((sa, sb))
                        continue
                    if ga > sa:
                        nxt.append((sa, ga))
                    if gb < sb:
                        nxt.append((gb, sb))
                spans = nxt
        for (sa, sb) in spans:
            for r in rows:
                out += course(sa, sb, row + r, z, k + (1 if r > 0 else 0), rnd, along, size)
    return out


def ring(radius, courses, rnd, skip=None, z0=0.0, size=BAG):
    """Bags laid round a circle (a circular fighting position), tangential, courses staggered. skip(k, deg): leave that
    place open. Returns [(centre, yaw, size, tie)]."""
    out = []
    n = max(6, int(round(math.tau * radius / PITCH)))
    L = math.tau * radius / n + (size[0] - PITCH)
    for k in range(courses):
        z = z0 + size[2] / 2 + k * COURSE
        for i in range(n):
            ang = (i + 0.5 * (k % 2)) * math.tau / n
            deg = math.degrees(ang) % 360.0
            if skip and skip(k, deg):
                continue
            c = (radius * math.cos(ang), radius * math.sin(ang), z)
            out.append((c, deg + 90.0 + rnd.uniform(-2.0, 2.0), (L, size[1], size[2]), 1 if i % 2 else -1))
    return out


def layer(x0, x1, y0, y1, z, layers, rnd, size=BAG):
    """Bags laid flat over a rectangle (overhead cover on a roof): rows along x, tight, rows and layers staggered."""
    out = []
    ny = max(1, int(round((y1 - y0) / (size[1] - 0.02))))
    for k in range(layers):
        for j in range(ny):
            y = y0 + (j + 0.5) * (y1 - y0) / ny
            out += course(x0, x1, y, z + size[2] / 2 + k * COURSE, j + k, rnd, "x", size)
    return out
