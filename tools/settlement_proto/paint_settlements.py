"""WORLD-SETTLEMENT-02: ground paint of the settlement layer (the Haugen rules for every place).

For each settlement: the generator's round settlement disc (pale colour-map tint) and the removed streets are
refilled from the nearest of a ring of field samples just outside (wavy Voronoi parcels), mown grass only as
gardens round the buildings, new roads get asphalt or gravel with worn verges.
Writes worlds/settlements/ref_20km_paint.bin.gz: little-endian uint32 triples (vertex key j * 10240 + i,
control bits 14..31 (base, overlay, blend), colour RGBA8), applied in memory by SettlementLayer.

The removed streets were also graded into the heightmap (cut/fill blended over ~40 m). Their corridors are
filled with a smooth surface interpolated from the ground outside them (normalised box blur), faded out
towards the kept roads, written to ref_20km_height.bin.gz (uint32 key, float32 height). The heights of the
layer's buildings and road points are then taken from the smoothed ground (rewrites ref_20km.json).

Run with Blender's Python:  paint_settlements.py
"""
import gzip
import json

import sys

import numpy as np
import OpenImageIO as oiio

sys.path.insert(0, "tools/terrain_ref")
from fn_noise import fbm, perlin  # noqa: E402  (the generator's own noise)

SRC = "worlds/ref_20km/source/"
LAYER = "worlds/settlements/ref_20km.json"
OUT = "worlds/settlements/ref_20km_paint.bin.gz"
OUT_H = "worlds/settlements/ref_20km_height.bin.gz"
N, SP, HALF = 10240, 1.953125, 10000.0
CTRL = np.memmap(SRC + "control.r32", dtype=np.uint32, mode="r", shape=(N, N))
COL = np.memmap(SRC + "color.rgba8", dtype=np.uint8, mode="r", shape=(N, N, 4))
H = np.memmap(SRC + "height.r32", dtype=np.float32, mode="r", shape=(N, N))
_cfg = oiio.ImageSpec()
_cfg.attribute("oiio:UnassociatedAlpha", 1)   # alpha is the water mask, not coverage
_ii = oiio.ImageInput.open(SRC + "info.png", _cfg)
SETTLE = _ii.read_image(format="uint8")[..., 2].astype(np.float32) / 255.0   # the generator's settlement mask
_ii.close()
GRASS, DIRT, FIELD, FOREST, GRAVEL, ASPHALT = 0, 2, 3, 4, 5, 7
HI = np.uint32(0xFFFFC000)


def control(base, over, blend):
    b8 = np.clip(np.round(blend * 255.0), 0, 255).astype(np.uint32)
    return (np.uint32(base) << 27) | (np.asarray(over, dtype=np.uint32) << 22) | (b8 << 14)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


class Win:
    def __init__(self, lo, hi):
        self.i0 = max(1, int(np.floor((lo[0] + HALF) / SP)))
        self.j0 = max(1, int(np.floor((lo[1] + HALF) / SP)))
        self.i1 = min(N - 2, int(np.ceil((hi[0] + HALF) / SP)))
        self.j1 = min(N - 2, int(np.ceil((hi[1] + HALF) / SP)))
        self.X = (np.arange(self.i0, self.i1 + 1) * SP - HALF)[None, :]
        self.Z = (np.arange(self.j0, self.j1 + 1) * SP - HALF)[:, None]
        self.shape = (self.j1 - self.j0 + 1, self.i1 - self.i0 + 1)

    def field(self):
        return np.full(self.shape, 1e9, dtype=np.float32)

    def stamp(self, f, P, hw, reach, tag=None, idx=0):
        band = hw + reach
        for a, b in zip(P[:-1], P[1:]):
            lo = np.minimum(a, b) - band
            hi = np.maximum(a, b) + band
            ia = max(0, int((lo[0] + HALF) / SP) - self.i0)
            ib = min(self.shape[1], int((hi[0] + HALF) / SP) - self.i0 + 2)
            ja = max(0, int((lo[1] + HALF) / SP) - self.j0)
            jb = min(self.shape[0], int((hi[1] + HALF) / SP) - self.j0 + 2)
            if ia >= ib or ja >= jb:
                continue
            X = self.X[:, ia:ib]
            Z = self.Z[ja:jb, :]
            ab = b - a
            L2 = max(float(ab @ ab), 1e-9)
            t = np.clip(((X - a[0]) * ab[0] + (Z - a[1]) * ab[1]) / L2, 0, 1)
            d = np.hypot(X - a[0] - ab[0] * t, Z - a[1] - ab[1] * t) - hw
            sub = f[ja:jb, ia:ib]
            m = d < sub
            sub[m] = d[m]
            if tag is not None:
                tag[ja:jb, ia:ib][m] = idx


def box(a, r):
    """Box blur of radius r (pixels) with edge clamping (cumulative sums)."""
    for ax in (0, 1):
        p = np.pad(a, [(r + 1, r), (0, 0)] if ax == 0 else [(0, 0), (r + 1, r)], mode="edge")
        c = np.cumsum(p, axis=ax)
        a = (c[2 * r + 1:, :] - c[:-2 * r - 1, :]) / (2 * r + 1) if ax == 0 else (c[:, 2 * r + 1:] - c[:, :-2 * r - 1]) / (2 * r + 1)
    return a


def inpaint(val, hole, iters=10):
    """Fills hole pixels from their nearest non-hole neighbours (repeated 1-pixel growth)."""
    val = val.copy()
    hole = hole.copy()
    for _ in range(iters):
        if not hole.any():
            break
        for dj, di in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            src = np.roll(np.roll(val, dj, 0), di, 1)
            ok = np.roll(np.roll(~hole, dj, 0), di, 1)
            m = hole & ok
            val[m] = src[m]
            hole = hole & ~m
    return val


MAX_GRADE = {"local": 0.11, "track": 0.13}


def sample(w, a, x, z):
    fx, fz = (x + HALF) / SP - w.i0, (z + HALF) / SP - w.j0
    i = np.clip(np.floor(fx).astype(int), 0, a.shape[1] - 2)
    j = np.clip(np.floor(fz).astype(int), 0, a.shape[0] - 2)
    tx, tz = np.clip(fx - i, 0, 1), np.clip(fz - j, 0, 1)
    return (a[j, i] * (1 - tx) + a[j, i + 1] * tx) * (1 - tz) + (a[j + 1, i] * (1 - tx) + a[j + 1, i + 1] * tx) * tz


def grade_roads(w, h, mine, L):
    """The site's new roads graded into the terrain like the generator's own roads: a smoothed, grade-limited
    profile pinned at the road it leaves (its start lies on that road's graded surface), steep dead-end tails
    cut off, and the terrain of a narrow corridor set to the profile (full under the surface, fading out over
    4 m). Updates the layer's road points (trimmed tails, profile heights)."""
    by_name = {r["name"]: r for r in L["roads"]}
    target = np.zeros_like(h)
    weight = np.zeros_like(h)
    for P, hw, paint, name in mine:
        rd = by_name[name]
        pts = np.array(rd["points"], dtype=np.float64)
        y = sample(w, h, pts[:, 0], pts[:, 2])
        maxg = 0.10 if name.startswith("Flyslette") else MAX_GRADE.get(rd["class"], 0.11)
        seg = np.hypot(np.diff(pts[:, 0]), np.diff(pts[:, 2]))
        # Steep tail of a dead end: cut it off (no road should end on a slope it cannot climb).
        while len(pts) > 6 and abs(y[-1] - y[-2]) / max(seg[-1], 0.1) > maxg * 1.6:
            pts, y, seg = pts[:-1], y[:-1], seg[:-1]
        prof = np.convolve(np.pad(y, 3, mode="edge"), np.ones(7) / 7, mode="valid")
        prof[0] = y[0]
        g = maxg * np.maximum(seg, 0.5)
        for _ in range(3):
            for i in range(1, len(prof)):
                prof[i] = np.clip(prof[i], prof[i - 1] - g[i - 1], prof[i - 1] + g[i - 1])
            for i in range(len(prof) - 2, 0, -1):
                prof[i] = np.clip(prof[i], prof[i + 1] - g[i], prof[i + 1] + g[i])
            prof[0] = y[0]
        rd["points"] = [[round(float(p[0]), 2), round(float(v) + 0.02, 2), round(float(p[2]), 2)] for p, v in zip(pts, prof)]
        rd["length_m"] = round(float(seg.sum()), 1)
        # Corridor.
        for k in range(len(pts) - 1):
            a, b = pts[k, [0, 2]], pts[k + 1, [0, 2]]
            band = hw + 4.0
            lo, hi = np.minimum(a, b) - band, np.maximum(a, b) + band
            ia = max(0, int((lo[0] + HALF) / SP) - w.i0)
            ib = min(w.shape[1], int((hi[0] + HALF) / SP) - w.i0 + 2)
            ja = max(0, int((lo[1] + HALF) / SP) - w.j0)
            jb = min(w.shape[0], int((hi[1] + HALF) / SP) - w.j0 + 2)
            if ia >= ib or ja >= jb:
                continue
            X = w.X[:, ia:ib]
            Z = w.Z[ja:jb, :]
            ab = b - a
            t = np.clip(((X - a[0]) * ab[0] + (Z - a[1]) * ab[1]) / max(float(ab @ ab), 1e-9), 0, 1)
            d = np.hypot(X - a[0] - ab[0] * t, Z - a[1] - ab[1] * t)
            wt = 1.0 - smoothstep(hw + 0.5, band, d)
            ht = prof[k] + (prof[k + 1] - prof[k]) * t
            sw = weight[ja:jb, ia:ib]
            st = target[ja:jb, ia:ib]
            m = wt > sw
            st[m] = ht[m]
            sw[m] = wt[m]
    return h * (1 - weight) + target * weight


def disc(col):
    r, g, b = col[..., 0].astype(np.int32), col[..., 1].astype(np.int32), col[..., 2].astype(np.int32)
    return (r > 188) & (g > 194) & (b > 173) & (np.abs(r - g) < 16)


def noise(I, J):
    h = (I.astype(np.int64) * 73856093) ^ (J.astype(np.int64) * 19349663)
    return (np.abs(h) % 1000) / 1000.0


def main():
    L = json.load(open(LAYER, encoding="utf-8"))
    W = json.load(open(SRC + "roads.json", encoding="utf-8"))
    removed = set(L["remove_roads"])
    keep, old = [], []
    for r in W["roads"]:
        P = np.array([[p[0], p[2]] for p in r["points"]])
        hw = (r["lane_m"] * r["lanes"] + 2 * r["shoulder_m"]) * 0.5
        (old if r["name"] in removed else keep).append((P, hw))
    new = [(np.array([[p[0], p[2]] for p in r["points"]]), (r["lane_m"] * r["lanes"] + 2 * r["shoulder_m"]) * 0.5, r["paint"], r["name"])
           for r in L["roads"]]
    blds = np.array([[b["x"], b["z"]] for b in L["buildings"]])
    changes = {}
    hchanges = {}
    windows = []   # (Win, smoothed heights) for re-sampling the layer's heights
    for st in L["sites"] + [{"name": "Flyslette øst tilkomstveg", "center": None}]:
        if st["center"] is None:
            mine = [r for r in new if r[3].startswith("Flyslette")]
            pts = np.concatenate([r[0] for r in mine])
            c = pts.mean(axis=0)
            R = 0.0
        else:
            c = np.array(st["center"], dtype=np.float64)
            R = st["radius_m"]
            mine = [r for r in new if r[3].startswith(st["name"] + " ") or r[3].startswith(st["name"] + ":")]
            if st["name"] == "Haugen":
                mine = [r for r in new if r[3] in ("Haugvegen", "Bakkeli", "Sagvegen") or r[3].endswith("Haugen gardsveg")]
        reach = max(2.4 * R, R + 250.0) if R > 0 else 0.0
        lo, hi = c - reach, c + reach
        for P, _, _, _ in mine:
            lo = np.minimum(lo, P.min(axis=0) - 20)
            hi = np.maximum(hi, P.max(axis=0) + 20)
        w = Win(lo, hi)
        ctrl = np.array(CTRL[w.j0:w.j1 + 1, w.i0:w.i1 + 1])
        col = np.array(COL[w.j0:w.j1 + 1, w.i0:w.i1 + 1])
        d_keep, d_old, d_new, garden = w.field(), w.field(), w.field(), w.field()
        which = np.zeros(w.shape, dtype=np.int32)
        for P, hw in keep:
            if (P.max(axis=0) >= lo).all() and (P.min(axis=0) <= hi).all():
                w.stamp(d_keep, P, hw, 8.0)
        for P, hw in old:
            if (P.max(axis=0) >= lo).all() and (P.min(axis=0) <= hi).all():
                w.stamp(d_old, P, hw, 56.0)
        near_new = [r for r in new if (r[0].max(axis=0) >= lo).all() and (r[0].min(axis=0) <= hi).all()]
        for k, (P, hw, paint, name) in enumerate(near_new):
            w.stamp(d_new, P, hw, 4.0, which, k)
        for b in blds[(blds[:, 0] > lo[0] - 50) & (blds[:, 0] < hi[0] + 50) & (blds[:, 1] > lo[1] - 50) & (blds[:, 1] < hi[1] + 50)]:
            w.stamp(garden, np.array([b, b + [0.01, 0]]), 0.0, 45.0)
        I = np.arange(w.i0, w.i1 + 1)[None, :] + np.zeros(w.shape, np.int64)
        J = np.arange(w.j0, w.j1 + 1)[:, None] + np.zeros(w.shape, np.int64)
        n = noise(I, J)
        new_ctrl = ctrl.copy()
        new_col = col.copy()
        # The generator's settlement mask (info.png, 9.8 m texels), smoothed: the disc, with a soft edge.
        si = np.clip(((w.X[0] + HALF) / 20000.0 * 2048).astype(int), 0, 2047)
        sj = np.clip(((w.Z[:, 0] + HALF) / 20000.0 * 2048).astype(int), 0, 2047)
        settle = box(box(SETTLE[sj][:, si], 4), 4) if R > 0 else np.zeros(w.shape)
        # 0. Heights: the old street corridors back to a smooth natural surface, and the small-scale relief
        #    the generator left out of the disc (0.12 m perlin at 6 m, generate.py build_full) put back.
        hgt = np.array(H[w.j0:w.j1 + 1, w.i0:w.i1 + 1], dtype=np.float64)
        wgt = (1.0 - smoothstep(34.0, 52.0, d_old)) * smoothstep(8.0, 22.0, d_keep)
        if True:  # always: the new roads are graded here too
            m = (d_old > 52.0).astype(np.float64)
            num, den = hgt * m, m
            for _ in range(2):
                num, den = box(num, 30), box(den, 30)
            smooth = np.where(den > 0.02, num / np.maximum(den, 1e-6), hgt)
            new_h = hgt * (1 - wgt) + smooth * wgt
            XX = np.broadcast_to(w.X, w.shape)
            ZZ = np.broadcast_to(w.Z, w.shape)
            new_h += 0.12 * perlin(XX / 6.0, ZZ / 6.0, 3031 + 83) * np.clip(settle, 0, 1) * smoothstep(4.0, 12.0, d_keep)
            # The generator also flattened the place to a plane and damped its 55 m relief (rough * (1 - 0.8 open
            # site)): give the flattened disc that relief back, away from the kept roads.
            opened = smoothstep(0.05, 0.6, box(settle, 10))
            new_h += fbm(XX / 55.0, ZZ / 55.0, 3031 + 81, 4) * 1.6 * 0.7 * opened * smoothstep(10.0, 35.0, d_keep)
            new_h = grade_roads(w, new_h, mine, L)
            jj, ii = np.nonzero(np.abs(new_h - hgt) > 0.03)
            for kk, hv in zip(((jj + w.j0).astype(np.int64) * N + (ii + w.i0)).tolist(), new_h[jj, ii].tolist()):
                hchanges[kk] = hv
            windows.append((w, new_h))
            print("  height: %d vertices, max change %.1f m" % (len(jj), float(np.abs(new_h - hgt).max())))
        dist_c = np.hypot(w.X - c[0], w.Z - c[1])
        w_disc = smoothstep(0.2, 0.7, settle) * (dist_c < max(R * 1.8, 1.0))
        # Old streets: first the ground right beside them (no stripe of another field) ...
        street = (d_old <= 4.5) & (d_keep > 3.0)
        if street.any():
            fill_c = inpaint(ctrl.astype(np.int64), street).astype(np.uint32)
            fill_col = np.stack([inpaint(col[..., k].astype(np.int32), street).astype(np.uint8) for k in range(4)], axis=2)
            new_ctrl = np.where(street, fill_c, new_ctrl)
            new_col = np.where(street[..., None], fill_col, new_col)
        # 1. ... then the disc, refilled from the fields round the place (dithered edge).
        target = (d_keep > 3.0) & (w_disc > 0.02) & (w_disc > n * 0.98)
        seeds = []
        if R > 0:
            base = ctrl >> 27
            # Dense ring just outside the disc: every disc point continues the ground nearest outside it.
            for a in np.linspace(0, 2 * np.pi, 180, endpoint=False) + 0.07:
                d = np.array([np.cos(a), np.sin(a)])
                for r in np.arange(0.5 * R, 3.2 * R, 3.0):
                    q = c + d * r
                    ii, jj = int(round((q[0] + HALF) / SP)) - w.i0, int(round((q[1] + HALF) / SP)) - w.j0
                    if not (0 <= ii < w.shape[1] and 0 <= jj < w.shape[0]):
                        break
                    if settle[jj, ii] > 0.08 or d_keep[jj, ii] < 6.0 or d_old[jj, ii] < 6.0 or d_new[jj, ii] < 6.0:
                        continue
                    if base[jj, ii] in (FIELD, GRASS):
                        seeds.append((q + d * 4.0, ctrl[jj, ii], col[jj, ii]))
                    break
        if seeds and target.any():
            jj, ii = np.nonzero(target)
            # Domain warp: long, wavy parcel edges instead of straight wedges towards the centre.
            wx, wz = w.X[0, ii], w.Z[jj, 0]
            qx = wx + (np.sin(wz / 97.0 + 1.3) + 0.6 * np.sin((wx + wz) / 53.0) + 0.3 * np.sin(wx / 13.0)) * 0.25 * max(R, 120.0)
            qz = wz + (np.cos(wx / 89.0 + 0.4) + 0.6 * np.cos((wx - wz) / 61.0) + 0.3 * np.cos(wz / 17.0)) * 0.25 * max(R, 120.0)
            S = np.array([s[0] for s in seeds])
            k = np.concatenate([np.argmin((qx[a:a + 20000, None] - S[None, :, 0]) ** 2 + (qz[a:a + 20000, None] - S[None, :, 1]) ** 2, axis=1)
                                for a in range(0, len(qx), 20000)])
            sc = np.array([s[1] for s in seeds], dtype=np.uint32)
            scol = np.array([s[2] for s in seeds], dtype=np.uint8)
            new_ctrl[jj, ii] = sc[k]
            # Colour blends at the disc edge (the control map cannot: it is dithered above).
            wd = np.clip(w_disc[jj, ii] * 1.6, 0, 1)[:, None]
            new_col[jj, ii, :3] = np.clip(scol[k, :3] * wd + new_col[jj, ii, :3] * (1 - wd), 0, 255).astype(np.uint8)
            gw = 1.0 - smoothstep(14.0, 30.0, garden[jj, ii] + 8.0 * (n[jj, ii] - 0.5))
            g = gw > 0.02
            over = (new_ctrl[jj, ii] >> 27)
            new_ctrl[jj[g], ii[g]] = control(GRASS, over[g], np.clip(0.15 + 0.25 * n[jj[g], ii[g]] + (1 - gw[g]) * 0.6, 0, 1))
            gcol = np.array([168, 199, 133], dtype=np.float64)
            new_col[jj[g], ii[g], :3] = np.clip(new_col[jj[g], ii[g], :3] * (1 - gw[g, None] * 0.6) + gcol * gw[g, None] * 0.6, 0, 255).astype(np.uint8)
        # 2. Gardens round buildings outside the disc too (light touch: only the tint).
        # 3. New roads.
        on = d_new < 3.5
        if on.any():
            jj, ii = np.nonzero(on)
            dd = d_new[jj, ii]
            hw = np.array([near_new[k][1] for k in which[jj, ii]])
            asph = np.array([near_new[k][2] == "asphalt" for k in which[jj, ii]])
            nn = n[jj, ii]
            surf = dd < -0.3 + 0.4 * nn
            cur_base = new_ctrl[jj, ii] >> 27
            vb = 1.0 - smoothstep(hw - 0.5, hw + 3.0, dd + hw)
            val = control(cur_base, np.full(len(jj), DIRT), vb * (0.6 + 0.3 * nn))
            val = np.where(surf & asph, control(ASPHALT, np.full(len(jj), DIRT), np.clip(0.1 + 0.08 * nn, 0, 1)), val)
            val = np.where(surf & ~asph, control(DIRT, np.full(len(jj), GRAVEL), np.clip(0.55 + 0.12 * nn, 0, 0.68)), val)
            new_ctrl[jj, ii] = val
        diff = ((new_ctrl & HI) != (ctrl & HI)) | (new_col != col).any(axis=2)
        jj, ii = np.nonzero(diff)
        keys = (jj + w.j0).astype(np.int64) * N + (ii + w.i0)
        cv = new_col[jj, ii].astype(np.uint32)
        colv = cv[:, 0] | (cv[:, 1] << 8) | (cv[:, 2] << 16) | (cv[:, 3] << 24)
        for kk, cc, co in zip(keys.tolist(), (new_ctrl[jj, ii] & HI).tolist(), colv.tolist()):
            changes[kk] = (cc, co)
        print("%-26s seeds %2d  changed %7d" % (st["name"], len(seeds), len(keys)))
    keys = np.array(sorted(changes), dtype=np.uint32)
    arr = np.zeros((len(keys), 3), dtype="<u4")
    arr[:, 0] = keys
    arr[:, 1] = [changes[k][0] for k in keys.tolist()]
    arr[:, 2] = [changes[k][1] for k in keys.tolist()]
    with gzip.open(OUT, "wb", compresslevel=9) as f:
        f.write(arr.tobytes())
    print("%d vertices -> %s" % (len(keys), OUT))
    hk = np.array(sorted(hchanges), dtype=np.uint32)
    ha = np.zeros(len(hk), dtype=[("k", "<u4"), ("h", "<f4")])
    ha["k"] = hk
    ha["h"] = [hchanges[k] for k in hk.tolist()]
    with gzip.open(OUT_H, "wb", compresslevel=9) as f:
        f.write(ha.tobytes())
    print("%d height vertices -> %s" % (len(hk), OUT_H))
    # Layer heights from the smoothed ground.
    def ground(x, z):
        for w, nh in windows:
            fx, fz = (x + HALF) / SP - w.i0, (z + HALF) / SP - w.j0
            i, j = int(fx), int(fz)
            if 0 <= i < nh.shape[1] - 1 and 0 <= j < nh.shape[0] - 1:
                tx, tz = fx - i, fz - j
                return float((nh[j, i] * (1 - tx) + nh[j, i + 1] * tx) * (1 - tz) + (nh[j + 1, i] * (1 - tx) + nh[j + 1, i + 1] * tx) * tz)
        fx, fz = (x + HALF) / SP, (z + HALF) / SP
        i, j = int(fx), int(fz)
        tx, tz = fx - i, fz - j
        return float((H[j, i] * (1 - tx) + H[j, i + 1] * tx) * (1 - tz) + (H[j + 1, i] * (1 - tx) + H[j + 1, i + 1] * tx) * tz)
    for b in L["buildings"]:
        hs = [ground(b["x"] + dx, b["z"] + dz) for dx in (-5, 5) for dz in (-5, 5)]
        b["y"] = round(ground(b["x"], b["z"]) - 0.05 - min((max(hs) - min(hs)) * 0.35, 0.8), 2)
    with open(LAYER, "w", encoding="utf-8") as f:
        json.dump(L, f, indent=1, ensure_ascii=False)
    print("layer heights re-sampled -> %s" % LAYER)


if __name__ == "__main__":
    main()
