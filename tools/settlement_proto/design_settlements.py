"""WORLD-SETTLEMENT-02: the settlements of ref_20km, laid out the way Haugen (WORLD-SETTLEMENT-01) was.

Not a town generator: a few helpers that do what was done by hand for Haugen, with a short plan per place.
  - Local roads start ON an existing road (a vertex of it, so VehicleRouter links them) and are walked out in
    6 m steps, each step turning at most 8 degrees towards the flattest dry ground and away from other roads.
    Short side roads, farm tracks and yard roads; dead ends are the rule.
  - Buildings stand along the roads in clusters with gaps (setback, side, yaw offset vary), farms as a tun
    (house, barn, shed) at the end of their track, workshops/barns in yard roads.
  - Every building is checked for slope, water, road clearance and overlap (dropped if it does not fit).
Haugen keeps its hand-made design (worlds/settlement_proto/haugen.json). Flyslette øst gets an access road
(A* on an 8 m grid with a grade cost).

Run with Blender's Python (numpy, OpenImageIO):  design_settlements.py  ->  worlds/settlements/ref_20km.json
"""
import heapq
import json
import math
import zlib

import numpy as np
import OpenImageIO as oiio

SRC = "worlds/ref_20km/source/"
OUT = "worlds/settlements/ref_20km.json"
N, SP, HALF = 10240, 1.953125, 10000.0
H = np.memmap(SRC + "height.r32", dtype=np.float32, mode="r", shape=(N, N))
_ii = oiio.ImageInput.open(SRC + "info.png")
INFO = _ii.read_image(format="uint8")
_ii.close()

HOUSE, BARN, SHED = 16, 17, 18
RADIUS = {HOUSE: 9.0, BARN: 13.0, SHED: 4.5}
TINTS = [[1, 1, 1], [1.0, 0.86, 0.52], [0.95, 0.45, 0.36], [0.82, 0.86, 0.9], [0.93, 0.93, 0.88]]
HOUSE_TINTS = [0, 0, 0, 1, 2, 3, 4, 4]
STEP = 6.0

# Road kinds: [class, lane_m, lanes, shoulder_m, paint, max grade]
KIND = {
    "street": ["local", 3.0, 2, 0.5, "asphalt", 0.10],   # through road in a town centre (7 m)
    "local": ["local", 4.6, 1, 0.5, "asphalt", 0.11],    # village road (5.6 m)
    "track": ["track", 3.4, 1, 0.5, "gravel", 0.13],     # farm road (4.4 m)
    "yard": ["local", 5.0, 1, 0.6, "gravel", 0.09],      # industrial / sawmill yard road (6.2 m)
    "access": ["local", 4.0, 1, 0.8, "gravel", 0.10],    # military access road (5.6 m)
}
NAMES = {
    "street": ["Storgata", "Kirkegata", "Jernbanegata", "Torggata", "Strandgata"],
    "local": ["Bakkevegen", "Granlia", "Solbakken", "Furulia", "Kirkevegen", "Skolevegen", "Myrvegen", "Lia",
              "Toppen", "Elvevegen", "Bjørkelia", "Engvegen", "Haugstien", "Nedre veg", "Øvre veg", "Åsvegen"],
    "track": ["gardsveg", "seterveg", "skogsveg", "gardsveg 2", "gardsveg 3", "gardsveg 4"],
    "yard": ["Industrivegen", "Sagvegen", "Verkstedvegen"],
}

# Plans: type and the counts of each road kind; centre = buildings packed along the main road at the
# junction; roadside = scattered houses further out along the main road.
PLANS = {
    "Sentrum": {"type": "C", "street": 3, "local": 9, "track": 3, "yard": 2, "centre": 34, "roadside": 10, "sub": 0.7, "commerce": 7},
    "Østby": {"type": "B", "street": 1, "local": 5, "track": 2, "yard": 1, "centre": 16, "roadside": 5, "sub": 0.5, "commerce": 3},
    "Ødegård": {"type": "B", "local": 3, "track": 2, "yard": 1, "centre": 10, "roadside": 4, "sub": 0.4, "commerce": 2},
    "Elvetun": {"type": "B", "local": 3, "track": 2, "centre": 10, "roadside": 4, "sub": 0.4, "commerce": 2},
    "Strand": {"type": "B", "local": 3, "track": 2, "yard": 1, "centre": 9, "roadside": 4, "sub": 0.3, "commerce": 1},
    "Moen": {"type": "B", "local": 3, "track": 2, "centre": 8, "roadside": 5, "sub": 0.3, "commerce": 1},
    "Verket": {"type": "I", "local": 1, "track": 1, "yard": 2, "centre": 4, "roadside": 3, "sub": 0.0, "commerce": 0, "industry": 9},
    "Elvebakken": {"type": "D", "track": 1, "centre": 2, "roadside": 1},
    "Sørhaug": {"type": "D", "yard": 1, "centre": 3, "roadside": 2},
    "Grensen": {"type": "D", "centre": 4, "roadside": 2, "track": 1},
    "Vestvatn": {"type": "D", "centre": 3, "roadside": 3},
}
VILLAGE = {"type": "A", "local": 1, "track": 2, "centre": 5, "roadside": 3, "sub": 0.0, "commerce": 1}
VILLAGE_VAR = {  # small differences between the villages
    "Nordvik": {"local": 2}, "Kvernes": {"track": 3, "centre": 3}, "Lia": {"local": 2, "centre": 4},
    "Bruvoll": {"track": 1, "centre": 6}, "Sletta": {"track": 3}, "Østmark": {"local": 2, "track": 1},
    "Skogli": {"centre": 4, "roadside": 4}, "Bakken": {"track": 3, "local": 0}, "Fjellfoten": {"local": 2, "track": 1},
}


def height(x, z):
    fx, fz = (x + HALF) / SP, (z + HALF) / SP
    i, j = int(fx), int(fz)
    if i < 1 or j < 1 or i >= N - 2 or j >= N - 2:
        return float("nan")
    tx, tz = fx - i, fz - j
    a = H[j, i] * (1 - tx) + H[j, i + 1] * tx
    b = H[j + 1, i] * (1 - tx) + H[j + 1, i + 1] * tx
    return float(a * (1 - tz) + b * tz)


def info(x, z):
    i = int((x + HALF) / 20000.0 * 2048)
    j = int((z + HALF) / 20000.0 * 2048)
    if i < 0 or j < 0 or i >= 2048 or j >= 2048:
        return np.array([255, 0, 0, 255])
    return INFO[j, i]


def wet(x, z):
    return info(x, z)[3] > 20


class Roads:
    """All road centre lines (world roads and new ones) in a 32 m segment hash."""
    CELL = 32.0

    def __init__(self):
        self.lines = []   # [name, P (n,2), half width, new]
        self.grid = {}

    def add(self, name, P, hw, new):
        rid = len(self.lines)
        self.lines.append([name, P, hw, new])
        for k in range(len(P) - 1):
            a, b = P[k], P[k + 1]
            for cx in range(int(math.floor(min(a[0], b[0]) / self.CELL)), int(math.floor(max(a[0], b[0]) / self.CELL)) + 1):
                for cz in range(int(math.floor(min(a[1], b[1]) / self.CELL)), int(math.floor(max(a[1], b[1]) / self.CELL)) + 1):
                    self.grid.setdefault((cx, cz), []).append((rid, k))
        return rid

    def dist(self, x, z, reach=64.0, skip=None, surface=True):
        """Distance to the nearest road (to its surface edge when surface); skip(rid, k) -> bool excludes segments."""
        best = 1e9
        r = int(math.ceil(reach / self.CELL))
        cx, cz = int(math.floor(x / self.CELL)), int(math.floor(z / self.CELL))
        seen = set()
        for dx in range(-r, r + 1):
            for dz in range(-r, r + 1):
                for rid, k in self.grid.get((cx + dx, cz + dz), ()):
                    if (rid, k) in seen or (skip and skip(rid, k)):
                        continue
                    seen.add((rid, k))
                    P = self.lines[rid][1]
                    a, b = P[k], P[k + 1]
                    ab = b - a
                    t = 0.0 if not ab.any() else min(1.0, max(0.0, ((x - a[0]) * ab[0] + (z - a[1]) * ab[1]) / (ab @ ab)))
                    d = math.hypot(x - a[0] - ab[0] * t, z - a[1] - ab[1] * t) - (self.lines[rid][2] if surface else 0.0)
                    best = min(best, d)
        return best


def frame(P, s):
    seg = np.hypot(*np.diff(P, axis=0).T)
    acc = np.concatenate([[0], np.cumsum(seg)])
    s = min(max(s, 0.0), acc[-1] - 0.01)
    i = int(np.clip(np.searchsorted(acc, s, side="right") - 1, 0, len(P) - 2))
    t = (s - acc[i]) / max(seg[i], 1e-6)
    return P[i] + (P[i + 1] - P[i]) * t, (P[i + 1] - P[i]) / max(seg[i], 1e-6), i, acc


class Site:
    def __init__(self, world, roads, st, plan, rng):
        self.w, self.roads, self.st, self.plan, self.rng = world, roads, st, plan, rng
        self.c = np.array([st["pos"][0], st["pos"][2]])
        self.R = st["radius_m"]
        self.new_roads = []    # [name, kind, P]
        self.blds = []
        self.used_names = set()
        # Main roads through the place: world roads (not streets) coming within 1.6 R.
        self.mains = []
        for rid, (name, P, hw, new) in enumerate(roads.lines):
            if new:
                continue
            d = np.hypot(*(P - self.c).T)
            if d.min() < self.R * 1.6:
                k = int(np.argmin(d))
                acc = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(P, axis=0).T))])
                self.mains.append({"rid": rid, "P": P, "s0": acc[k], "d": d.min(), "len": acc[-1]})
        self.mains.sort(key=lambda m: m["d"])
        self.starts = []   # branch start points (avoid junctions closer than 60 m)

    def name(self, kind):
        for n in NAMES[kind]:
            if n not in self.used_names:
                self.used_names.add(n)
                return ("%s %s" % (self.st["name"], n)) if kind == "track" else ("%s: %s" % (self.st["name"], n))
        return "%s %s %d" % (self.st["name"], kind, len(self.new_roads))

    # --- roads -----------------------------------------------------------------------------------
    def grow(self, start, heading, length, kind, parent_rid):
        maxg = KIND[kind][5]
        pts = [np.array(start, dtype=np.float64)]
        hd = heading
        phase = self.rng.uniform(0, 6.28)
        mean = self.rng.uniform(-1.5, 1.5)   # slow drift: roads curve, not wobble
        for step in range(int(length / STEP)):
            p = pts[-1]
            hp = height(*p)
            best = None
            turn = {"street": 3.0, "local": 5.0, "yard": 5.0}.get(kind, 8.0)
            for dd in (-turn, -turn * 0.5, 0.0, turn * 0.5, turn):
                nh = hd + math.radians(dd)
                q = p + STEP * np.array([math.cos(nh), math.sin(nh)])
                hq = height(*q)
                if math.isnan(hq) or wet(*q):
                    continue
                g = abs(hq - hp) / STEP
                # The first metres ramp off the parent's graded embankment or cut.
                lim = maxg if step * STEP >= 18.0 else 0.35
                cost = g * 25.0 + (200.0 if g > lim else 0.0) + abs(dd - (mean - 3.0 * math.sin(step * 0.08 + phase)) * turn / 8.0) * 0.04
                walked = step * STEP
                d = self.roads.dist(q[0], q[1], 40.0, skip=(lambda rid, k: rid == parent_rid) if walked < 45 else None)
                if d < 28.0:
                    cost += (28.0 - d) * 0.35
                if d < 6.0 and walked > 30:
                    cost += 200.0
                if best is None or cost < best[0]:
                    best = (cost, q, nh)
            if best is None or best[0] >= 200.0:
                break
            pts.append(best[1])
            hd = best[2]
        P = np.array(pts)
        if len(P) < 4:
            return None
        # Light smoothing, start pinned on the parent road.
        S = P.copy()
        for _ in range(2):
            T = S.copy()
            for k in range(1, len(S) - 1):
                T[k] = S[max(0, k - 3):k + 4].mean(axis=0)
            T[0] = P[0]
            T[-1] = S[-1]
            S = T
        return S

    def add_road(self, kind, P):
        name = self.name(kind)
        rid = self.roads.add(name, P, self.hw(kind), True)
        self.new_roads.append([name, kind, P, rid])
        return rid

    @staticmethod
    def hw(kind):
        k = KIND[kind]
        return (k[1] * k[2] + 2 * k[3]) * 0.5

    def branch(self, kind, length, parents, near=1.3, tries=14, min_frac=0.55):
        """A road of this kind leaving one of the parent lines near the place; returns its rid or None."""
        for _ in range(tries):
            par = parents[self.rng.integers(len(parents))]
            P = par["P"]
            seg = np.hypot(*np.diff(P, axis=0).T)
            total = seg.sum()
            if "s0" in par:
                s = par["s0"] + self.rng.uniform(-near, near) * self.R
            else:
                s = self.rng.uniform(0.25, 0.85) * total
            if s < 15 or s > total - 15:
                continue
            p, tan, i, acc = frame(P, s)
            v = P[i] if s - acc[i] < acc[i + 1] - s else P[i + 1]   # a vertex of the parent
            if any(np.hypot(*(v - q)) < 60.0 for q in self.starts):
                continue
            if np.hypot(*(v - self.c)) > self.R * (near + 0.4) and "s0" in par:
                continue
            side = 1 if self.rng.random() < 0.5 else -1
            hd = math.atan2(tan[1], tan[0]) + side * math.radians(self.rng.uniform(65, 110))
            R = self.grow(v, hd, length, kind, par["rid"])
            if R is None:
                continue
            L = float(np.hypot(*np.diff(R, axis=0).T).sum())
            if L < length * min_frac:
                continue
            self.starts.append(v)
            return self.add_road(kind, R)
        return None

    # --- buildings -------------------------------------------------------------------------------
    def fits(self, mesh, x, z):
        r = RADIUS[mesh]
        hs = [height(x + dx, z + dz) for dx in (-r * 0.6, 0, r * 0.6) for dz in (-r * 0.6, 0, r * 0.6)]
        if any(math.isnan(h) for h in hs):
            return False
        drop = max(hs) - min(hs)
        if drop > r * 0.28 or any(wet(x + dx, z + dz) for dx in (-r, r) for dz in (-r, r)):
            return False
        if self.roads.dist(x, z, 48.0) < r * 0.6 + 2.5:
            return False
        for b in ALL_BLDS:
            if abs(b["x"] - x) < 40 and abs(b["z"] - z) < 40 and math.hypot(b["x"] - x, b["z"] - z) < (RADIUS[b["mesh"]] + r) * 0.78:
                return False
        return True

    def put(self, mesh, x, z, yaw, tint):
        drop = max(height(x + dx, z + dz) for dx in (-5, 5) for dz in (-5, 5)) - min(height(x + dx, z + dz) for dx in (-5, 5) for dz in (-5, 5))
        b = {"mesh": mesh, "x": round(float(x), 2), "z": round(float(z), 2),
             "y": round(height(x, z) - 0.05 - min(drop * 0.35, 0.8), 2), "yaw": round(float(yaw), 4), "color": TINTS[tint]}
        self.blds.append(b)
        ALL_BLDS.append(b)
        return True

    def along(self, P, s, side, setback, mesh, tint, yaw_extra=0.0):
        p, tan, _, _ = frame(P, s)
        nrm = np.array([-tan[1], tan[0]]) * side
        for extra in (0.0, 4.0, 8.0):
            q = p + nrm * (setback + extra)
            if self.fits(mesh, *q):
                away = -nrm
                return self.put(mesh, q[0], q[1], math.atan2(away[0], away[1]) + math.radians(yaw_extra), tint)
        return False

    def house_tint(self):
        return HOUSE_TINTS[self.rng.integers(len(HOUSE_TINTS))]

    def cluster_line(self, P, s0, s1, n_max, spacing=(24, 36), gap=(45, 130), cluster=(2, 6), both=0.6, setback=(14, 22)):
        """Houses along P between s0 and s1: clusters with gaps between them."""
        n = 0
        s = s0
        while s < s1 and n < n_max:
            k = self.rng.integers(cluster[0], cluster[1] + 1)
            for _ in range(k):
                if s >= s1 or n >= n_max:
                    break
                sides = [1, -1] if self.rng.random() < both else [1 if self.rng.random() < 0.5 else -1]
                for sd in sides:
                    yaw = self.rng.normal(0, 7) + (90 if self.rng.random() < 0.08 else 0)
                    if n < n_max and self.along(P, s + self.rng.uniform(-4, 4), sd, self.rng.uniform(*setback), HOUSE, self.house_tint(), yaw):
                        n += 1
                s += self.rng.uniform(*spacing)
            s += self.rng.uniform(*gap)
        return n

    def farm(self, P, red=True):
        """Tun at the end of a track: house, barn at right angles, shed."""
        L = float(np.hypot(*np.diff(P, axis=0).T).sum())
        p, tan, _, _ = frame(P, L - 1.0)
        nrm = np.array([-tan[1], tan[0]])
        base = math.atan2(-nrm[0], -nrm[1])
        for sd in (1, -1):
            hq = p + nrm * sd * 15 - tan * 4
            bq = p + tan * 16 + nrm * sd * 6
            sq = p - tan * 14 - nrm * sd * 14
            if self.fits(HOUSE, *hq) and self.fits(BARN, *bq):
                self.put(HOUSE, hq[0], hq[1], base + (0 if sd > 0 else math.pi) + math.radians(self.rng.normal(0, 6)), self.house_tint())
                self.put(BARN, bq[0], bq[1], base + math.pi / 2 + math.radians(self.rng.normal(0, 5)), 2 if red else 4)
                if self.fits(SHED, *sq):
                    self.put(SHED, sq[0], sq[1], base + math.radians(self.rng.uniform(-20, 20)), 0)
                return True
        # No room at the very end: a house alone a little back.
        return self.along(P, L * 0.8, 1, 16, HOUSE, self.house_tint())

    def build(self):
        pl = self.plan
        mains = [m for m in self.mains if m["d"] < self.R * 0.9] or self.mains[:1]
        # Through streets of a town centre, then side roads (some from the town's own roads), farms, yards.
        for _ in range(pl.get("street", 0)):
            self.branch("street", self.rng.uniform(1.0, 1.6) * self.R, mains, near=0.5)
        for _ in range(pl.get("local", 0)):
            parents = mains + [{"rid": r[3], "P": r[2]} for r in self.new_roads if r[1] == "street"]
            self.branch("local", self.rng.uniform(0.9, 1.7) * max(self.R, 160), parents, near=1.0)
        for r in [r for r in self.new_roads if r[1] in ("local", "street")]:
            if self.rng.random() < pl.get("sub", 0):
                self.branch("local", self.rng.uniform(70, 150), [{"rid": r[3], "P": r[2]}])
        for _ in range(pl.get("track", 0)):
            self.branch("track", self.rng.uniform(180, 420), self.mains, near=1.9, min_frac=0.6)
        for _ in range(pl.get("yard", 0)):
            self.branch("yard", self.rng.uniform(80, 150), mains, near=1.4, min_frac=0.7)
        # Centre: houses and a few bigger buildings (shop, garage, co-op) packed along the main road(s).
        n_c = pl.get("centre", 4)
        com = pl.get("commerce", 0)
        for m in mains[:3]:
            span = self.R * (0.55 if pl["type"] in ("C", "B") else 0.4)
            share = n_c // max(1, min(3, len(mains)))
            s = m["s0"] - span
            placed = 0
            while s < m["s0"] + span and placed < share:
                sd = 1 if self.rng.random() < 0.5 else -1
                if com > 0 and self.rng.random() < 0.35 and self.along(m["P"], s, sd, self.rng.uniform(20, 26), BARN, 4 if self.rng.random() < 0.6 else 1, self.rng.normal(0, 4)):
                    com -= 1
                    placed += 1
                elif self.along(m["P"], s, sd, self.rng.uniform(14, 19), HOUSE, self.house_tint(), self.rng.normal(0, 5)):
                    placed += 1
                s += self.rng.uniform(17, 30) if pl["type"] == "C" else self.rng.uniform(22, 38)
        # Roadside houses further out on the main road, both directions.
        for k in range(pl.get("roadside", 0)):
            m = self.mains[k % len(self.mains)]
            s = m["s0"] + (1 if k % 2 else -1) * self.rng.uniform(0.9, 2.2) * self.R
            if 20 < s < m["len"] - 20:
                self.along(m["P"], s, 1 if self.rng.random() < 0.5 else -1, self.rng.uniform(16, 26), HOUSE, self.house_tint(), self.rng.normal(0, 10))
        # Along the new roads.
        dense = {"C": 1.0, "B": 0.75, "A": 0.5, "I": 0.4, "D": 0.4}[pl["type"]]
        for name, kind, P, rid in self.new_roads:
            L = float(np.hypot(*np.diff(P, axis=0).T).sum())
            if kind == "street":
                self.cluster_line(P, 20, L - 10, int(L / 20), spacing=(18, 26), gap=(25, 60), cluster=(3, 7), both=0.85, setback=(13, 18))
            elif kind == "local":
                n = max(2, int(L / 45 * dense * 1.6))
                self.cluster_line(P, 25, L - 5, n, cluster=(2, 6) if pl["type"] in ("C", "B") else (1, 4),
                                  gap=(35, 90) if pl["type"] == "C" else (45, 140))
            elif kind == "track":
                self.farm(P)
                if L > 260 and self.rng.random() < 0.5:
                    self.along(P, L * 0.45, 1 if self.rng.random() < 0.5 else -1, 17, HOUSE, self.house_tint())
            elif kind == "yard":
                n = pl.get("industry", 3) // max(1, pl.get("yard", 1))
                s = 22.0
                while s < L - 10 and n > 0:
                    mesh = BARN if self.rng.random() < 0.65 else SHED
                    if self.along(P, s, 1 if self.rng.random() < 0.5 else -1, self.rng.uniform(19, 26) if mesh == BARN else 12, mesh, 4 if self.rng.random() < 0.5 else 3, 90 if self.rng.random() < 0.4 else 0):
                        n -= 1
                    s += self.rng.uniform(28, 40)


def access_road(roads, target, goal_q):
    """Flyslette øst: A* from the nearest world road vertex to the plateau, 8 m grid, grade-squared cost."""
    best = None
    for rid, (name, P, hw, new) in enumerate(roads.lines):
        if new:
            continue
        d = np.hypot(*(P - target).T)
        k = int(np.argmin(d))
        if best is None or d[k] < best[0]:
            best = (d[k], P[k], rid, name)
    start = best[1]
    G = 8.0
    lo = np.minimum(start, target) - 500
    hi = np.maximum(start, target) + 500
    nx, nz = int((hi[0] - lo[0]) / G), int((hi[1] - lo[1]) / G)
    hgt = np.array([[height(lo[0] + i * G, lo[1] + j * G) for i in range(nx)] for j in range(nz)])
    wetm = np.array([[wet(lo[0] + i * G, lo[1] + j * G) for i in range(nx)] for j in range(nz)])
    s = (int((start[1] - lo[1]) / G), int((start[0] - lo[0]) / G))
    dist = {s: 0.0}
    prev = {}
    pq = [(0.0, s)]
    end = None
    nbr = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1), (-2, 1), (2, 1), (-2, -1), (2, -1), (1, 2), (1, -2), (-1, 2), (-1, -2)]
    while pq:
        dcur, u = heapq.heappop(pq)
        if dcur > dist.get(u, 1e18):
            continue
        x, z = lo[0] + u[1] * G, lo[1] + u[0] * G
        if goal_q(x, z) < 0.8:
            end = u
            break
        for dj, di in nbr:
            v = (u[0] + dj, u[1] + di)
            if not (0 <= v[0] < nz and 0 <= v[1] < nx) or wetm[v]:
                continue
            L = G * math.hypot(dj, di)
            g = abs(hgt[v] - hgt[u]) / L
            if g > 0.12:
                continue
            c = dcur + L * (1.0 + 400.0 * g * g)
            if c < dist.get(v, 1e18):
                dist[v] = c
                prev[v] = u
                heapq.heappush(pq, (c + 0.0, v))
    if end is None:
        return None, best
    path = [end]
    while path[-1] in prev:
        path.append(prev[path[-1]])
    path.reverse()
    P = np.array([[lo[0] + u[1] * G, lo[1] + u[0] * G] for u in path])
    P[0] = start
    # Smooth the grid staircase (start pinned).
    for _ in range(3):
        Q = P.copy()
        for k in range(1, len(P) - 1):
            Q[k] = P[max(0, k - 2):k + 3].mean(axis=0)
        P = Q
        P[0] = start
    return P, best


ALL_BLDS = []


def to_json(name, kind, P):
    k = KIND[kind]
    y = np.array([height(x, z) for x, z in P])
    ys = np.convolve(np.pad(y, 2, mode="edge"), np.ones(5) / 5, mode="valid")
    seg = np.hypot(*np.diff(P, axis=0).T)
    return {"name": name, "class": k[0], "mesh": False, "lane_m": k[1], "lanes": k[2], "shoulder_m": k[3], "paint": k[4],
            "points": [[round(float(x), 2), round(float(h) + 0.02, 2), round(float(z), 2)] for (x, z), h in zip(P, ys)],
            "bridges": [], "culverts": [], "length_m": round(float(seg.sum()), 1)}, float((np.abs(np.diff(ys)) / np.maximum(seg, 0.1)).max())


def main():
    sites = json.load(open(SRC + "sites.json", encoding="utf-8"))
    world = json.load(open(SRC + "roads.json", encoding="utf-8"))
    haugen = json.load(open("worlds/settlement_proto/haugen.json", encoding="utf-8"))
    roads = Roads()
    removed = []
    for r in world["roads"]:
        if r["class"] == "street":
            removed.append(r["name"])
            continue
        lw = r["lane_m"] * r["lanes"] * 0.5 + r["shoulder_m"]
        roads.add(r["name"], np.array([[p[0], p[2]] for p in r["points"]]), lw, False)
    out_roads, out_sites = [], []
    # Haugen: the approved hand-made prototype, unchanged.
    for r in haugen["roads"]:
        roads.add(r["name"], np.array([[p[0], p[2]] for p in r["points"]]), (r["lane_m"] * r["lanes"] + 2 * r["shoulder_m"]) * 0.5, True)
        out_roads.append(r)
    ALL_BLDS.extend(haugen["buildings"])
    out_blds = list(haugen["buildings"])
    out_sites.append({"name": "Haugen", "type": "A (hand-made)", "center": haugen["center"], "radius_m": 160.0,
                      "roads": len(haugen["roads"]), "buildings": len(haugen["buildings"])})
    report = []
    for st in sites["settlements"]:
        if st["name"] == "Haugen":
            continue
        plan = dict(PLANS.get(st["name"], VILLAGE))
        if st["name"] not in PLANS:
            plan.update(VILLAGE_VAR.get(st["name"], {}))
        rng = np.random.default_rng(zlib.crc32(("ws02" + st["name"]).encode("utf-8")))
        s = Site(None, roads, st, plan, rng)
        s.build()
        for name, kind, P, rid in s.new_roads:
            js, g = to_json(name, kind, P)
            out_roads.append(js)
            report.append("  %-34s %-6s %5.0f m  max grade %4.1f %%" % (name, kind, js["length_m"], g * 100))
        out_blds.extend(s.blds)
        out_sites.append({"name": st["name"], "type": plan["type"], "center": [st["pos"][0], st["pos"][2]], "radius_m": st["radius_m"],
                          "roads": len(s.new_roads), "buildings": len(s.blds)})
        print("%-12s %s  roads %2d  buildings %3d" % (st["name"], plan["type"], len(s.new_roads), len(s.blds)))
    # Flyslette øst access road.
    pl = [p for p in sites["plateaus"] if p["name"] == "Flyslette øst"][0]
    pc = np.array([pl["pos"][0], pl["pos"][2]]) if "pos" in pl else np.array([pl["center"][0], pl["center"][2]])
    rot = math.radians(pl["rot_deg"])
    rx, rz = pl["radii_m"]
    def q(x, z):
        dx, dz = x - pc[0], z - pc[1]
        u = dx * math.cos(rot) + dz * math.sin(rot)
        v = -dx * math.sin(rot) + dz * math.cos(rot)
        return math.hypot(u / rx, v / rz)
    P, best = access_road(roads, pc, q)
    if P is not None:
        js, g = to_json("Flyslette øst tilkomstveg", "access", P)
        out_roads.append(js)
        roads.add(js["name"], P, Site.hw("access"), True)
        print("Flyslette øst access road: %.0f m from %s, max grade %.1f %%" % (js["length_m"], best[3], g * 100))
    else:
        print("Flyslette øst: no access road found")
    print("\n".join(report))
    data = {"_comment": "WORLD-SETTLEMENT-02 settlement layer of ref_20km (tools/settlement_proto/design_settlements.py).",
            "world": "ref_20km", "remove_roads": removed, "sites": out_sites, "roads": out_roads, "buildings": out_blds}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
    print("%d sites, %d roads, %d buildings, %d world streets removed -> %s"
          % (len(out_sites), len(out_roads), len(out_blds), len(removed), OUT))


if __name__ == "__main__":
    main()
