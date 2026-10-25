"""Reference-based world generation for FRACTURED NATIONS (WORLD-TERRAIN-01).

Builds a 20 x 20 km northern-European landscape from a hand-authored geographic layout
(tools/terrain_ref/layout_ref03.json, traced from docs/terrain01/reference_map_03.png).
The reference picture is NOT read as a heightmap: the layout lists the river, lakes,
massif, rocky hills, farmland, settlements, flat plateaus and road waypoints, and this
script turns them into a coherent elevation model:

  1. macro relief (2048^2, 9.77 m): regional slope toward the river, rolling hills scaled
     by a hilliness field (farmland flat, rocky hills rough), the NE massif along a ridge
     axis with passes, lakes as basins with closed rims, settlements and plateaus
     flattened to gently tilted planes;
  2. drainage (512^2): priority-flood + D8 flow accumulation, stream valleys carved in
     proportion to catchment size so every valley drains to the river, a lake or the edge;
  3. roads: A* on the 512^2 grid between the layout waypoints with a slope-squared cost,
     smoothed, then graded (moving average + max-grade clamp, bridges above the river);
  4. full resolution (10240^2, 1.953 m): bicubic upsample, rock-aware detail noise,
     river channel and banks, road cuts/fills, Terrain3D control map (texture ids/blend);
  5. maps for Godot: vegetation (forest density, pine/birch share, wetness), colour tint
     (field patchwork, forest, alpine), water and road JSON, preview PNGs and statistics.

Run with Blender's bundled Python (it ships numpy and OpenImageIO):
  "C:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" \
      tools/terrain_ref/generate.py --layout tools/terrain_ref/layout_ref03.json \
      --out worlds/ref_20km/source [--macro-only]

Output coordinates: Godot world space, +X east, +Z south, map centred on the origin,
so reference km (x, y_north) -> X = x*1000 - 10000, Z = 10000 - y*1000.
"""
import argparse
import heapq
import json
import math
import os
import sys
import time
import zlib

import numpy as np
import OpenImageIO as oiio

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fn_noise import fbm, perlin, ridged, smoothstep  # noqa: E402

# Terrain3D texture slots (must match ReferenceWorldBuilder.make_assets()).
TEX_GRASS, TEX_ROCK, TEX_DIRT, TEX_FIELD, TEX_FOREST, TEX_GRAVEL, TEX_BOG, TEX_ASPHALT = 0, 1, 2, 3, 4, 5, 6, 7

T0 = time.time()


def log(msg):
    print("[%6.1fs] %s" % (time.time() - T0, msg), flush=True)


# ----------------------------------------------------------------------------------
# Small helpers
# ----------------------------------------------------------------------------------

def grid_km(res, size_km):
    """Vertex-aligned grid: index i -> i * size/res km. Returns X(east), Y(north) in km."""
    pitch = size_km / res
    xs = np.arange(res, dtype=np.float32) * pitch
    ys = size_km - np.arange(res, dtype=np.float32) * pitch
    return np.meshgrid(xs, ys)


def box_blur(a, r):
    """Separable box blur with radius r pixels (edge-clamped)."""
    if r < 1:
        return a
    r = int(r)
    out = a.astype(np.float32)
    for axis in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[axis] = (r + 1, r)
        p = np.pad(out, pad, mode="edge")
        c = np.cumsum(p, axis=axis, dtype=np.float64)
        if axis == 0:
            out = ((c[2 * r + 1:, :] - c[:-2 * r - 1, :]) / (2 * r + 1)).astype(np.float32)
        else:
            out = ((c[:, 2 * r + 1:] - c[:, :-2 * r - 1]) / (2 * r + 1)).astype(np.float32)
    return out


def blur(a, r):
    """Approximate gaussian (three box passes)."""
    r3 = max(1, int(round(r / 1.7)))
    return box_blur(box_blur(box_blur(a, r3), r3), r3)


def smin(a, b, k):
    """Polynomial smooth minimum (blend width k, same units as a and b): no crease where
    a cap takes over from the terrain."""
    hk = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - hk * hk * k * 0.25


def ellipse_q(px, py, center, radii, rot_deg):
    """Normalized elliptical radius (1 on the ellipse)."""
    a = math.radians(rot_deg)
    dx = px - center[0]
    dy = py - center[1]
    u = dx * math.cos(a) + dy * math.sin(a)
    v = -dx * math.sin(a) + dy * math.cos(a)
    return np.sqrt((u / radii[0]) ** 2 + (v / radii[1]) ** 2)


def polyline_dist(px, py, pts):
    """Distance (same units as pts) from every point to a polyline and the arc parameter
    of the closest point. pts: list of (x, y)."""
    best = np.full(px.shape, np.inf, dtype=np.float32)
    best_s = np.zeros(px.shape, dtype=np.float32)
    s0 = 0.0
    for i in range(len(pts) - 1):
        ax, ay = pts[i]
        bx, by = pts[i + 1]
        dx, dy = bx - ax, by - ay
        l2 = dx * dx + dy * dy
        seg_len = math.sqrt(l2)
        t = np.clip(((px - ax) * dx + (py - ay) * dy) / l2, 0.0, 1.0)
        d = np.hypot(px - (ax + t * dx), py - (ay + t * dy))
        m = d < best
        best[m] = d[m]
        best_s[m] = (s0 + t * seg_len)[m]
        s0 += seg_len
    return best, best_s, s0


def catmull_weights(t):
    t2 = t * t
    t3 = t2 * t
    return (
        -0.5 * t3 + t2 - 0.5 * t,
        1.5 * t3 - 2.5 * t2 + 1.0,
        -1.5 * t3 + 2.0 * t2 + 0.5 * t,
        0.5 * t3 - 0.5 * t2,
    )


def upsample_axis(a, factor, axis, start, count):
    """Catmull-Rom upsampling of a along axis by an integer factor, output indices
    start..start+count (vertex-aligned: output i samples source i / factor)."""
    n = a.shape[axis]
    i = np.arange(start, start + count)
    base = i // factor
    t = ((i % factor) / factor).astype(np.float32)
    w = catmull_weights(t)
    out = None
    for k in range(4):
        idx = np.clip(base - 1 + k, 0, n - 1)
        taken = np.take(a, idx, axis=axis)
        wk = w[k][:, None] if axis == 0 else w[k][None, :]
        out = taken * wk if out is None else out + taken * wk
    return out


def bilinear(a, fx, fy):
    """Bilinear sample of grid a at fractional pixel coords (fx = column, fy = row)."""
    h, w = a.shape
    fx = np.clip(fx, 0, w - 1.001)
    fy = np.clip(fy, 0, h - 1.001)
    x0 = np.floor(fx).astype(np.int64)
    y0 = np.floor(fy).astype(np.int64)
    tx = fx - x0
    ty = fy - y0
    return (a[y0, x0] * (1 - tx) * (1 - ty) + a[y0, x0 + 1] * tx * (1 - ty)
            + a[y0 + 1, x0] * (1 - tx) * ty + a[y0 + 1, x0 + 1] * tx * ty)


def write_png(path, arr):
    if arr.ndim == 2:
        arr = arr[..., None]
    arr = np.ascontiguousarray(arr)
    h, w = arr.shape[:2]
    ch = 1 if arr.ndim == 2 else arr.shape[2]
    spec = oiio.ImageSpec(w, h, ch, oiio.UINT8)
    # Our 4th channel is data (wetness, water, height, roughness), not coverage: without this OIIO treats the pixels as
    # premultiplied and divides RGB by alpha when it writes a PNG (VISUAL-02: vegetation.png, info.png and the packed
    # terrain textures had saturated RGB wherever alpha was small).
    spec.attribute("oiio:UnassociatedAlpha", 1)
    out = oiio.ImageOutput.create(path)
    out.open(path, spec)
    out.write_image(arr)
    out.close()


def to_u8(a):
    return np.clip(np.round(a * 255.0), 0, 255).astype(np.uint8)


# ----------------------------------------------------------------------------------
# Generator
# ----------------------------------------------------------------------------------

class Generator:
    def __init__(self, layout, out_dir):
        self.L = layout
        self.out = out_dir
        os.makedirs(out_dir, exist_ok=True)
        self.seed = int(layout["seed"])
        self.size_km = layout["size_m"] / 1000.0
        self.full = int(layout["full_res"])
        self.R = int(layout["macro_res"])
        self.D = int(layout["drain_res"])
        self.pitch_km = self.size_km / self.R
        self.X, self.Y = grid_km(self.R, self.size_km)
        self.stats = {}

    # ------------------------------------------------------------------ macro relief
    def build_macro(self):
        L, X, Y, s = self.L, self.X, self.Y, self.seed
        reg = L["regional"]
        riv = L["river"]
        rpts = self.river_points()
        # Distance on the drainage grid, upsampled: exact enough for the macro relief
        # (the channel itself is cut at full resolution).
        f = self.R // self.D
        Xd, Yd = grid_km(self.D, self.size_km)
        dd, sd, r_len = polyline_dist(Xd, Yd, rpts)
        d_r = np.maximum(upsample_axis(upsample_axis(dd, f, 0, 0, self.R), f, 1, 0, self.R), 0.0)
        s_r = upsample_axis(upsample_axis(sd, f, 0, 0, self.R), f, 1, 0, self.R)
        self.river_len_km = r_len
        # Water level along the river, smoothed so the Voronoi seams between segments
        # do not show up as creases in the valley sides.
        lvl = riv["level_m"][0] + (riv["level_m"][1] - riv["level_m"][0]) * np.clip(s_r / r_len, 0, 1)
        lvl = blur(lvl, 60)
        self.d_river, self.s_river, self.river_level = d_r, s_r, lvl

        # Domain warp shared by hills and forests so features bend naturally.
        wx = X + 0.55 * fbm(X / 3.0, Y / 3.0, s + 11, 3)
        wy = Y + 0.55 * fbm(X / 3.0 + 7.3, Y / 3.0 - 2.1, s + 12, 3)
        self.wx, self.wy = wx, wy

        large = fbm(X / reg["large_noise_km"], Y / reg["large_noise_km"], s + 1, 3)
        h = (lvl + reg["valley_rise_m"] * (1.0 - np.exp(-d_r / reg["valley_rise_km"]))
             + reg["north_rise_m"] * smoothstep(6.0, 19.0, Y)
             + reg["large_noise_m"] * large * smoothstep(0.4, 3.0, d_r))

        # Hilliness: 0 = flat farmland, 1 = rough rocky hills.
        H = np.full(X.shape, reg["default_hilliness"], dtype=np.float32)
        farm = np.zeros(X.shape, dtype=np.float32)
        rock = np.zeros(X.shape, dtype=np.float32)
        massif = np.zeros(X.shape, dtype=np.float32)
        rocky_h = np.zeros(X.shape, dtype=np.float32)
        for z in L["zones"]:
            if z["type"] == "farmland":
                q = ellipse_q(wx, wy, z["center_km"], z["radii_km"], z["rot_deg"])
                m = (1.0 - smoothstep(0.55, 1.05, q)) * z["strength"]
                farm = np.maximum(farm, m)
                H = H + (0.1 - H) * m
            elif z["type"] == "rocky":
                q = ellipse_q(wx, wy, z["center_km"], z["radii_km"], z["rot_deg"])
                q = q + 0.35 * fbm(X / 0.7, Y / 0.7, s + 22, 3)
                m = 1.0 - smoothstep(0.0, 1.35, q)
                rock = np.maximum(rock, smoothstep(0.25, 0.8, m))
                H = H + (1.0 - H) * m
                rg = ridged(X / 0.8 + 3.1, Y / 0.8 - 1.7, s + 21, 5)
                dome = m * m * (3.0 - 2.0 * m)
                rocky_h = np.maximum(rocky_h, z["peak_m"] * (0.7 * dome + 0.55 * dome * rg * rg))
            elif z["type"] == "massif":
                d_a, _, _ = polyline_dist(X, Y, z["axis_km"])
                hw = z["halfwidth_km"]
                prof = (1.0 - smoothstep(0.0, hw, d_a)) ** 1.5
                rg = ridged(X / 1.25 + 9.0, Y / 1.25 + 4.0, s + 31, 6)
                mh = z["peak_m"] * prof * (0.42 + 0.78 * rg)
                mh += 70.0 * prof * ridged(X / 0.45, Y / 0.45, s + 32, 4)
                for p in z.get("passes_km", []):
                    dp = np.hypot(X - p[0], Y - p[1])
                    mh *= 1.0 - 0.6 * np.exp(-(dp / p[2]) ** 2)
                massif = np.maximum(massif, 1.0 - smoothstep(0.2, 1.0, d_a / hw))
                h = h + mh
                H = H + (1.0 - H) * massif * 0.7
        fp = reg["floodplain_km"]
        flood = smoothstep(fp[0], fp[1], d_r)
        H = H * (0.1 + 0.9 * flood)
        hills = fbm(wx / reg["hills_km"], wy / reg["hills_km"], s + 2, 5)
        h = h + reg["hills_m"] * H * (1.15 * hills + 0.3)
        h = h + rocky_h * (0.3 + 0.7 * flood)
        self.H, self.farm, self.rock, self.massif = H, farm, rock, massif

        # Valley profile (WORLD-PLAYTEST-01): a floodplain just above the water, then valley
        # sides that rise at a bounded grade. The cap grows without limit away from the river,
        # so it only acts where the relief would otherwise drop straight into the channel.
        # (Previously the valley floor was clamped to "level + 25 m" for ~1 km, which left the
        # river in a 27 m vertical-walled canal wherever the regional rise lifted the land.)
        fp_km, fp_w, grade = self.valley_params(X, Y, H, rock, massif)
        cap = (lvl + riv["floodplain_above_m"] + fp_km["rise_m"] * smoothstep(0.0, 1.0, d_r / fp_w)
               + grade * np.maximum(d_r - fp_w, 0.0) * 1000.0)
        h = smin(h, cap, 4.0)
        h = np.maximum(h, lvl + riv["floodplain_above_m"])
        self.valley_cap = cap.astype(np.float32)
        self.valley_floor = (lvl + riv["floodplain_above_m"]).astype(np.float32)
        self.h = h.astype(np.float32)
        log("macro relief: %.0f..%.0f m" % (self.h.min(), self.h.max()))

    def valley_params(self, X, Y, H, rock, massif):
        """River valley shape fields (any resolution, X/Y in km): floodplain width (km),
        valley-side grade (rise/run) and the floodplain's gentle rise. Varied with noise and
        terrain character so the banks do not repeat: wide flat meadows in farmland, narrow
        floodplains and steeper (but never vertical) sides in rocky ground."""
        v = self.L["river"].get("valley", {})
        s = self.seed
        n1 = smoothstep(-0.45, 0.45, fbm(X / 1.4, Y / 1.4, s + 151, 3))
        n2 = smoothstep(-0.5, 0.5, fbm(X / 0.9 + 4.0, Y / 0.9, s + 152, 3))
        fpw = v.get("floodplain_km", [0.04, 0.32])
        fp_w = fpw[0] + (fpw[1] - fpw[0]) * n1 * (1.0 - 0.6 * np.clip(H, 0, 1))
        gr = v.get("grade", [0.07, 0.24])
        grade = gr[0] + (gr[1] - gr[0]) * n2 + v.get("rock_grade", 0.22) * np.maximum(rock, massif)
        return {"rise_m": v.get("floodplain_rise_m", 1.6)}, np.maximum(fp_w, 0.02), grade

    def parcels(self, X, Y):
        """Field parcels (analytic, any resolution): blocks of ~1.4 km bounded by warped
        lines, each with its own orientation; inside a block a staggered grid of
        rectangular parcels. Returns (random 0..1 per parcel, distance to the parcel
        edge in m, hedgerow flag per parcel)."""
        s = self.seed
        cw, ch = self.L["vegetation"]["field_cell_m"]
        wx = X + 0.55 * fbm(X / 3.0, Y / 3.0, s + 11, 3)
        wy = Y + 0.55 * fbm(X / 3.0 + 7.3, Y / 3.0 - 2.1, s + 12, 3)
        bwx = (wx + 0.25 * fbm(X / 0.6, Y / 0.6, s + 68, 2)) / 1.4
        bwy = (wy + 0.25 * fbm(X / 0.6 + 5.0, Y / 0.6, s + 69, 2)) / 1.4
        bi = np.floor(bwx)
        bj = np.floor(bwy)
        bh = ((bi * 92837111).astype(np.int64) ^ (bj * 689287499).astype(np.int64)) & 0xFFFF
        ang = (bh % 360) * (math.pi / 180.0)
        u = (X * np.cos(ang) + Y * np.sin(ang)) * 1000.0 / cw
        v = (-X * np.sin(ang) + Y * np.cos(ang)) * 1000.0 / ch
        vi = np.floor(v)
        # Stagger rows so parcels do not align in a perfect chessboard.
        ui2 = np.floor(u + 0.5 * (np.mod(vi, 2)))
        parcel = ((ui2 * 73856093).astype(np.int64) ^ (vi * 19349663).astype(np.int64) ^ (bh * 83492791)) & 0xFFFF
        fu = u + 0.5 * np.mod(vi, 2) - ui2
        fv = v - vi
        edge = np.minimum(np.minimum(fu, 1.0 - fu) * cw, np.minimum(fv, 1.0 - fv) * ch)
        bedge = np.minimum(np.minimum(bwx - bi, 1 - (bwx - bi)), np.minimum(bwy - bj, 1 - (bwy - bj))) * 1400.0
        edge = np.minimum(edge, bedge)
        rnd = (parcel % 97) / 97.0
        return rnd.astype(np.float32), edge.astype(np.float32), ((parcel // 7) % 5) < 2

    CROPS = np.array([[0.92, 0.88, 0.62], [0.86, 0.88, 0.70], [0.60, 0.80, 0.48], [0.52, 0.70, 0.42],
                      [0.72, 0.62, 0.48], [0.74, 0.80, 0.54], [0.66, 0.78, 0.50]], dtype=np.float32)

    def tint_of(self, X, Y, dens, field, rnd, alpine, bog):
        """Terrain3D colour-map multiplier (<= 1): forests darker, crop patchwork,
        alpine heath, bog, meadow variation."""
        tint = np.ones(dens.shape + (3,), dtype=np.float32) * np.array([0.80, 0.82, 0.74], dtype=np.float32)
        mv = 0.07 * fbm(X / 0.25, Y / 0.25, self.seed + 71, 3)
        tint = tint + np.stack([mv * 1.2, mv, -mv * 0.5], axis=-1)
        forest_c = np.array([0.40, 0.50, 0.30], dtype=np.float32)
        # Canopy mottling (crowns and gaps at ~6-20 m) so the far field, where no tree
        # meshes are drawn, reads as forest rather than flat paint.
        canopy = 0.72 + 0.5 * (0.6 * fbm(X / 0.012, Y / 0.012, self.seed + 72, 2) + 0.4 * fbm(X / 0.005, Y / 0.005, self.seed + 73, 1) + 0.5)
        forest_c = forest_c[None, None, :] * np.clip(canopy, 0.55, 1.2)[..., None] if np.ndim(X) == 2 else forest_c
        tint = tint + (forest_c - tint) * dens[..., None]
        ci = (rnd * 977).astype(np.int64) % len(self.CROPS)
        crops = self.CROPS[ci] * 0.7 + np.array([0.70, 0.74, 0.56], dtype=np.float32) * 0.3
        tint = np.where(field[..., None], crops, tint)
        a = (alpine * (1 - dens))[..., None] * 0.7
        tint = tint + (np.array([0.94, 0.88, 0.76], dtype=np.float32) - tint) * a
        tint = np.where(bog[..., None], tint * np.array([0.98, 0.88, 0.66], dtype=np.float32), tint)
        return np.clip(tint, 0.0, 1.0)

    def river_points(self):
        """River centreline in km, Chaikin-smoothed into meanders (cached)."""
        if getattr(self, "_rpts", None) is None:
            P = np.array(self.L["river"]["points_km"], dtype=np.float64)
            for _ in range(4):
                Q = [P[0]]
                for a, b in zip(P[:-1], P[1:]):
                    Q.append(0.75 * a + 0.25 * b)
                    Q.append(0.25 * a + 0.75 * b)
                Q.append(P[-1])
                P = np.array(Q)
            self._rpts = [tuple(p) for p in P]
        return self._rpts

    def _settle_dist(self):
        """Distance in km to the nearest settlement edge."""
        d = np.full(self.X.shape, np.inf, dtype=np.float32)
        for st in self.L["settlements"]:
            d = np.minimum(d, np.hypot(self.X - st["center_km"][0], self.Y - st["center_km"][1]) - st["radius_km"])
        return np.maximum(d, 0.0)

    def _plane_flatten(self, mask_full, core, max_grade):
        """Blends h toward a least-squares plane fitted inside core (bool), with the
        plane slope clamped to max_grade. mask_full: 0..1 blend weight."""
        idx = np.nonzero(core)
        if idx[0].size < 8:
            return
        xs = self.X[idx] * 1000.0
        ys = self.Y[idx] * 1000.0
        hs = self.h[idx]
        A = np.stack([xs - xs.mean(), ys - ys.mean(), np.ones_like(xs)], axis=1)
        coef, *_ = np.linalg.lstsq(A, hs, rcond=None)
        gx, gy, c = coef
        g = math.hypot(gx, gy)
        if g > max_grade:
            gx, gy = gx * max_grade / g, gy * max_grade / g
        plane = (self.X * 1000.0 - xs.mean()) * gx + (self.Y * 1000.0 - ys.mean()) * gy + c
        self.h = self.h + (plane - self.h) * mask_full
        return plane

    def flatten_sites(self):
        """Settlements and plateaus become gently tilted, open planes."""
        X, Y = self.X, self.Y
        self.open_sites = np.zeros(X.shape, dtype=np.float32)
        self.settle = np.zeros(X.shape, dtype=np.float32)
        noise = 0.12 * fbm(X / 0.35, Y / 0.35, self.seed + 41, 3)
        for st in self.L["settlements"]:
            r = st["radius_km"]
            d = np.hypot(X - st["center_km"][0], Y - st["center_km"][1]) / r + noise
            m = 1.0 - smoothstep(0.7, 2.2, d)
            core = d < 0.9
            self._plane_flatten(m * (0.72 + 0.2 * smoothstep(0.3, 0.6, st["radius_km"])), core, 0.04)
            self.settle = np.maximum(self.settle, 1.0 - smoothstep(0.8, 1.15, d))
            self.open_sites = np.maximum(self.open_sites, 1.0 - smoothstep(1.0, 1.9, d))
        for pl in self.L["plateaus"]:
            q = ellipse_q(X, Y, pl["center_km"], pl["radii_km"], pl["rot_deg"]) + noise
            m = 1.0 - smoothstep(0.85, 1.7, q)
            self._plane_flatten(m * 0.95, q < 0.9, 0.025)
            self.open_sites = np.maximum(self.open_sites, 1.0 - smoothstep(0.8, 1.15, q))
        # Sites next to the river must not rebuild a wall above the bank.
        self.h = np.maximum(smin(self.h, self.valley_cap, 4.0), self.valley_floor)
        log("sites flattened")

    def build_lakes(self):
        X, Y = self.X, self.Y
        self.lake_mask = np.zeros(X.shape, dtype=np.float32)
        self.lake_info = []
        self.lake_id = np.full(X.shape, -1, dtype=np.int16)
        for i, lk in enumerate(self.L["lakes"]):
            q = ellipse_q(X, Y, lk["center_km"], lk["radii_km"], lk["rot_deg"])
            q = q + 0.16 * fbm(X / 0.32 + i * 13.0, Y / 0.32, self.seed + 51 + i, 4)
            ring = (q > 1.0) & (q < 1.3)
            level = float(np.percentile(self.h[ring], 30))
            inside = q < 1.0
            # Rim: everything just outside the shore rises from the water level.
            dist_m = np.maximum(q - 1.0, 0.0) * min(lk["radii_km"]) * 1000.0
            band = (q >= 1.0) & (q < 1.6)
            rim = level + 0.7 + 0.06 * dist_m
            lift = np.maximum(rim - self.h, 0.0) * (1.0 - smoothstep(1.05, 1.6, q))
            self.h = np.where(band, self.h + lift, self.h)
            # Shore slope cap (WORLD-PLAYTEST-01): the ground outside the shore rises at a
            # bounded grade instead of dropping vertically onto the lake bottom (steeper on
            # rocky ground). The cap grows with distance, so far terrain is untouched.
            sg = 0.16 + 0.12 * smoothstep(-0.5, 0.5, fbm(X / 0.5 + i * 7.0, Y / 0.5, self.seed + 161 + i, 3)) \
                + 0.35 * np.maximum(self.rock, self.massif)
            outside = q >= 1.0
            self.h = np.where(outside, smin(self.h, level + 1.2 + sg * dist_m, 2.0), self.h)
            depth = lk["depth_m"]
            bottom = level - 0.9 - (depth - 0.9) * smoothstep(0.0, 0.55, 1.0 - q)
            self.h = np.where(inside, np.minimum(self.h, bottom), self.h)
            for isl in lk.get("islands_km", []):
                di = np.hypot(X - isl[0], Y - isl[1]) / isl[2]
                self.h = np.where(di < 1.2, np.maximum(self.h, level + 5.0 * (1.0 - di) - 0.6), self.h)
            self.lake_mask = np.maximum(self.lake_mask, inside.astype(np.float32))
            self.lake_id[inside] = i
            self.lake_info.append({"name": lk["name"], "level": level, "q": q})
            log("lake %s level %.1f m, %.2f km^2" % (lk["name"], level, inside.sum() * self.pitch_km ** 2))

    # ------------------------------------------------------------------ drainage
    def drainage(self):
        f = self.R // self.D
        D = self.D
        hd = self.h.reshape(D, f, D, f).mean(axis=(1, 3))
        Xd, Yd = grid_km(D, self.size_km)
        # Tiny smooth perturbation so flow over flats does not run in straight D8 lines.
        hd = hd + 0.8 * fbm(Xd / 0.4, Yd / 0.4, self.seed + 45, 3)
        river = self.d_river.reshape(D, f, D, f).min(axis=(1, 3)) < 0.06
        lake = self.lake_mask.reshape(D, f, D, f).max(axis=(1, 3)) > 0.5
        outlet = river | lake
        n = D * D
        flat_h = hd.ravel().astype(np.float64)
        filled = flat_h.copy()
        recv = np.full(n, -1, dtype=np.int64)
        visited = np.zeros(n, dtype=bool)
        heap = []
        for r in range(D):
            for c in range(D):
                if r == 0 or c == 0 or r == D - 1 or c == D - 1 or outlet[r, c]:
                    i = r * D + c
                    visited[i] = True
                    heapq.heappush(heap, (flat_h[i], i))
        order = []
        nbr = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
        eps = 0.01
        while heap:
            hc, i = heapq.heappop(heap)
            order.append(i)
            r, c = divmod(i, D)
            for dr, dc in nbr:
                rr, cc = r + dr, c + dc
                if 0 <= rr < D and 0 <= cc < D:
                    j = rr * D + cc
                    if not visited[j]:
                        visited[j] = True
                        nh = max(flat_h[j], hc + eps)
                        filled[j] = nh
                        recv[j] = i
                        heapq.heappush(heap, (nh, j))
        cell_km2 = (self.size_km / D) ** 2
        acc = np.full(n, cell_km2)
        for i in reversed(order):
            if recv[i] >= 0:
                acc[recv[i]] += acc[i]
        # Carve: depth grows with catchment; keep each cell above its receiver.
        depth = np.where(acc > 0.25, np.clip(2.8 * np.sqrt(acc) - 0.8, 0.0, 16.0), 0.0)
        carved = filled - depth
        for i in order:
            j = recv[i]
            if j >= 0 and carved[i] < carved[j] + 0.03:
                carved[i] = carved[j] + 0.03
        delta = np.maximum(flat_h - carved, 0.0).reshape(D, D).astype(np.float32)
        self.acc = acc.reshape(D, D).astype(np.float32)
        # Catchment max over 3x3 cells: a road crossing a D8 channel diagonally still hits it.
        a = np.pad(self.acc, 1, mode="edge")
        self.acc_max3 = np.max(np.stack([a[1 + dy:1 + dy + D, 1 + dx:1 + dx + D]
                                         for dy in (-1, 0, 1) for dx in (-1, 0, 1)]), axis=0)
        # Upsample to the macro grid and widen big valleys.
        up = upsample_axis(upsample_axis(delta, f, 0, 0, self.R), f, 1, 0, self.R)
        up = np.maximum(np.maximum(blur(up, 6), 0.85 * blur(up, 14)), 0.7 * blur(up, 32))
        protect = np.maximum(np.maximum(self.lake_mask, self.open_sites),
                             1.0 - smoothstep(0.08, 0.5, self.d_river))
        protect = np.maximum(protect, blur(self.lake_mask, 12))
        self.h = self.h - up * (1.0 - np.clip(protect, 0, 1))
        accm = upsample_axis(upsample_axis(np.log10(self.acc), f, 0, 0, self.R), f, 1, 0, self.R)
        # Wetness along drainage lines: from ~0.3 km^2 catchments upward, a few cells wide.
        self.stream = smoothstep(-0.6, 0.6, accm) * (1.0 - smoothstep(0.1, 0.4, self.d_river))
        self.stream = np.maximum(blur(self.stream, 4), 0.6 * blur(self.stream, 10))
        log("drainage: max catchment %.0f km^2, max carve %.1f m" % (self.acc.max(), float(delta.max())))

    # ------------------------------------------------------------------ roads
    def route_roads(self):
        L = self.L
        D = self.D
        f = self.R // D
        hd = self.h.reshape(D, f, D, f).mean(axis=(1, 3)).astype(np.float64)
        river_d = self.d_river.reshape(D, f, D, f).min(axis=(1, 3))
        lake = self.lake_mask.reshape(D, f, D, f).max(axis=(1, 3)) > 0.3
        cell_m = self.size_km * 1000.0 / D
        pitch = self.size_km / D
        steps = [(dr, dc) for dr in (-2, -1, 0, 1, 2) for dc in (-2, -1, 0, 1, 2)
                 if (dr, dc) != (0, 0) and math.gcd(abs(dr), abs(dc)) == 1]
        river_pen = 260.0
        roads_out = []
        fixed = {}  # waypoint (rounded km) -> graded height, shared by junctions
        classes = L["road_classes"]
        order = sorted(range(len(L["roads"])), key=lambda k: list(classes).index(L["roads"][k]["class"]))
        used = np.zeros((D, D), dtype=np.float32)
        near = np.zeros((D, D), dtype=np.float32)
        meet_cells = 250.0 / cell_m

        def rc_of(p):
            return (int(round((self.size_km - p[1]) / pitch)), int(round(p[0] / pitch)))

        def astar(a, b, slope_cost):
            (r0, c0), (r1, c1) = a, b
            margin = int(2.0 / pitch)
            rmin, rmax = max(0, min(r0, r1) - margin), min(D - 1, max(r0, r1) + margin)
            cmin, cmax = max(0, min(c0, c1) - margin), min(D - 1, max(c0, c1) + margin)
            r0, r1 = min(max(r0, 0), D - 1), min(max(r1, 0), D - 1)
            c0, c1 = min(max(c0, 0), D - 1), min(max(c1, 0), D - 1)
            g = {(r0, c0): 0.0}
            came = {}
            heap = [(0.0, r0, c0)]
            while heap:
                _, r, c = heapq.heappop(heap)
                if (r, c) == (r1, c1):
                    break
                gc = g[(r, c)]
                for dr, dc in steps:
                    rr, cc = r + dr, c + dc
                    if rr < rmin or rr > rmax or cc < cmin or cc > cmax:
                        continue
                    if lake[rr, cc]:
                        continue
                    dist = math.hypot(dr, dc) * cell_m
                    grade = abs(hd[rr, cc] - hd[r, c]) / dist
                    cost = dist * (1.0 + slope_cost * grade * grade + (8.0 * (grade - 0.12) if grade > 0.12 else 0.0))
                    if river_d[rr, cc] < 0.05:
                        cost += river_pen * cell_m / 40.0
                    # Keep away from existing roads (no parallel duplicates) except
                    # close to this segment's own waypoints, where roads meet.
                    if near[rr, cc] > 0.0:
                        ea = math.hypot(rr - r0, cc - c0)
                        eb = math.hypot(rr - r1, cc - c1)
                        if min(ea, eb) > meet_cells:
                            cost *= 1.0 + 3.0 * near[rr, cc]
                    ng = gc + cost
                    if ng < g.get((rr, cc), 1e30):
                        g[(rr, cc)] = ng
                        came[(rr, cc)] = (r, c)
                        hgt = math.hypot(rr - r1, cc - c1) * cell_m * 0.75
                        heapq.heappush(heap, (ng + hgt, rr, cc))
            path = [(r1, c1)]
            while path[-1] != (r0, c0):
                path.append(came[path[-1]])
            return path[::-1]

        junction_keys = {}
        for rd in L["roads"]:
            for w in rd["waypoints_km"]:
                key = (round(w[0], 4), round(w[1], 4))
                junction_keys[key] = junction_keys.get(key, 0) + 1
        # Junction positions as built by the first road through them: that road may relax
        # its curve through the junction (a pinned waypoint left a corner); later roads meet
        # it there.
        moved = {}
        for k in order:
            rd = L["roads"][k]
            cls = classes[rd["class"]]
            keys = [(round(w[0], 4), round(w[1], 4)) for w in rd["waypoints_km"]]
            wps = [list(moved.get(key, w)) for key, w in zip(keys, rd["waypoints_km"])]
            pts = [tuple(wps[0])]
            for a, b in zip(wps[:-1], wps[1:]):
                cells = astar(rc_of(a), rc_of(b), cls["slope_cost"])
                for (r, c) in cells[1:-1]:
                    pts.append((c * pitch, self.size_km - r * pitch))
                    used[r, c] = 1.0
                pts.append(tuple(b))
            pts = self._cut_spurs(pts, [tuple(w) for w, key in zip(wps, keys) if key in moved] + [tuple(wps[0]), tuple(wps[-1])])
            # Only waypoints shared with other roads (junctions) and the ends are pinned;
            # interior waypoints just steer the route (pinning them left 10 m kinks).
            pins = [tuple(wps[0]), tuple(wps[-1])] + [tuple(w) for w, key in zip(wps[1:-1], keys[1:-1]) if key in moved]
            path = self._smooth_path(pts, pins, cls.get("min_radius_m", 20.0))
            for key in keys:
                if junction_keys.get(key, 0) >= 2 and key not in moved:
                    w = moved.get(key, key)
                    j = int(np.argmin(np.hypot(path[:, 0] - w[0], path[:, 1] - w[1])))
                    moved[key] = (float(path[j, 0]), float(path[j, 1]))
            wps = [list(moved.get(key, w)) for key, w in zip(keys, wps)]
            # Repulsion field for later roads: 1 on this road, fading over ~3 cells.
            near = np.maximum(near, np.clip(blur(used, 3) * 6.0, 0.0, 1.0))
            roads_out.append(self._grade_road(rd, cls, path, wps, fixed, keys))
            log("road %-22s %-9s %6.2f km" % (rd["name"], rd["class"], roads_out[-1]["length_m"] / 1000.0))
        self.roads = roads_out
        self.road_fixed = fixed
        self.road_moved = moved
        # WORLD-SETTLEMENT-02: with a settlement layer (worlds/settlements/) the generated street grids are off.
        if not self.L.get("settlement_layer", False):
            self._settlement_streets()

    def _cut_spurs(self, pts, keep):
        """Removes dead-end spurs from an A* polyline (WORLD-PLAYTEST-01): where the route
        comes back within ~1.5 grid cells of a point it passed before (a detour out to an
        off-route waypoint and back), the loop between is cut. Sections holding a point in
        `keep` (junctions fixed by earlier roads, the ends) stay. Rv2 ran 100 m out and back
        on itself to a junction waypoint, leaving a 2 m step where the two halves met."""
        P = np.array(pts, dtype=np.float64)
        keep_set = {(round(k[0], 4), round(k[1], 4)) for k in keep}
        is_keep = np.array([(round(p[0], 4), round(p[1], 4)) in keep_set for p in pts])
        tol = 1.5 * self.size_km / self.D
        out = []
        i = 0
        n = len(P)
        while i < n:
            out.append(i)
            j_cut = -1
            for j in range(n - 1, i + 3, -1):
                if np.hypot(*(P[j] - P[i])) < tol and not is_keep[i + 1:j].any():
                    j_cut = j
                    break
            i = j_cut if j_cut > 0 else i + 1
        return [pts[k] for k in out]

    def _settlement_streets(self):
        """Street grids for towns (85 m blocks aligned with the main road through the
        centre) and short side streets for villages; graded like the other roads and
        painted with asphalt (class "street", no Road Generator mesh)."""
        cls = self.L["road_classes"]["street"]
        paved = [r for r in self.roads if r["class"] in ("primary", "secondary")]
        n0 = len(self.roads)
        for st in self.L["settlements"]:
            c = np.array(st["center_km"], dtype=np.float64)
            R = st["radius_km"]
            # Orientation: length-weighted mean direction of the paved roads inside the
            # settlement, modulo 90 deg (a grid is 90-degree symmetric: average 4*angle).
            acc = np.zeros(2)
            for r in paved:
                P = r["path_km"]
                inside = np.hypot(P[:-1, 0] - c[0], P[:-1, 1] - c[1]) < R * 1.3
                d = np.diff(P, axis=0)[inside]
                if len(d):
                    ln = np.hypot(d[:, 0], d[:, 1])
                    a4 = 4.0 * np.arctan2(d[:, 1], d[:, 0])
                    acc += np.array([np.sum(ln * np.cos(a4)), np.sum(ln * np.sin(a4))])
            ang = math.atan2(acc[1], acc[0]) / 4.0 if np.hypot(*acc) > 1e-6 else 0.0
            u = np.array([math.cos(ang), math.sin(ang)])
            v = np.array([-u[1], u[0]])
            lines = []
            if st["kind"] == "town":
                sp = 0.095
                n = int(R / sp)
                for axis, other in ((u, v), (v, u)):
                    for k in range(-n, n + 1):
                        off = k * sp
                        if abs(off) > R * 0.92:
                            continue
                        half = math.sqrt(max(0.0, (R * 0.95) ** 2 - off * off))
                        if half < 0.06:
                            continue
                        a = c + other * off - axis * half
                        b = c + other * off + axis * half
                        lines.append((a, b))
            else:
                # Stable seed (Python's str hash is randomised per process, so the village
                # streets used to change on every generator run).
                rnd = np.random.default_rng(zlib.crc32(st["name"].encode("utf-8")))
                for sgn in (1, -1):
                    a = c + v * sgn * 0.02
                    lines.append((a, a + v * sgn * R * rnd.uniform(0.8, 1.1)))
                if R > 0.16:
                    a = c + u * R * 0.3
                    lines.append((a, a + v * R * 0.8 * (1 if rnd.random() < 0.5 else -1)))
            kept = []
            for a, b in lines:
                m = (a + b) * 0.5
                a2 = self._trim_steep(m, a)[1]
                b2 = self._trim_steep(m, b)[1]
                if np.hypot(*(b2 - a2)) >= 0.03:
                    kept.append((a2, b2))
            for i, (a, b) in enumerate(kept):
                L_km = float(np.hypot(*(b - a)))
                npts = max(2, int(L_km / 0.01) + 1)
                path = np.stack([np.linspace(a[0], b[0], npts), np.linspace(a[1], b[1], npts)], axis=1)
                rd = {"name": "%s gate %d" % (st["name"], i + 1), "class": "street"}
                self.roads.append(self._grade_road(rd, cls, path, [tuple(a), tuple(b)], {}))
        log("streets: %d in %d settlements" % (len(self.roads) - n0, len(self.L["settlements"])))

    def _smooth_path(self, pts, anchors, min_radius_m=20.0):
        """Chaikin smoothing with fixed anchor points, uniform ~10 m resampling, a light
        moving average, then curve relaxation: points on curves tighter than min_radius_m
        are pulled toward their neighbours until the radius (measured over +-20 m) is met
        or the pass budget runs out. Anchors (junctions, ends) stay exactly in place.
        WORLD-PLAYTEST-01: the old version pinned every waypoint and left the moving
        average's clustered points (3 m apart around tight bends), which produced 10 m
        radius kinks and, with a mean-spacing grade clamp, 25-45 % grades."""
        P = np.array(pts, dtype=np.float64)
        anchor_set = {(round(a[0], 4), round(a[1], 4)) for a in anchors}
        is_anchor = np.array([(round(p[0], 4), round(p[1], 4)) in anchor_set for p in pts])
        for _ in range(4):
            Q = [P[0]]
            QA = [True]
            for i in range(len(P) - 1):
                a, b = P[i], P[i + 1]
                if is_anchor[i + 1] and i + 1 < len(P) - 1:
                    Q.append(0.75 * a + 0.25 * b)
                    QA.append(False)
                    Q.append(b)
                    QA.append(True)
                    continue
                Q.append(0.75 * a + 0.25 * b)
                QA.append(False)
                Q.append(0.25 * a + 0.75 * b)
                QA.append(False)
            Q.append(P[-1])
            QA.append(True)
            P = np.array(Q)
            is_anchor = np.array(QA)
        out = self._resample(P, 0.01)
        pins = self._pin_indices(out, anchors)
        for _ in range(3):
            sm = out.copy()
            sm[2:-2] = (out[:-4] + out[1:-3] + out[2:-2] + out[3:-1] + out[4:]) / 5.0
            out = sm
            for k, a in pins:
                out[k] = a
        out[0], out[-1] = P[0], P[-1]
        out = self._resample_pinned(out, pins, 0.01)
        pins = self._pin_indices(out, anchors)
        fixed = np.zeros(len(out), dtype=bool)
        fixed[[k for k, _ in pins]] = True
        fixed[0] = fixed[-1] = True
        r_km = min_radius_m / 1000.0
        for _ in range(80):
            if len(out) < 5:
                break
            a, b, c = out[:-4], out[2:-2], out[4:]
            ab = np.linalg.norm(b - a, axis=1)
            bc = np.linalg.norm(c - b, axis=1)
            ca = np.linalg.norm(c - a, axis=1)
            cross = np.abs((b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (b[:, 1] - a[:, 1]) * (c[:, 0] - a[:, 0]))
            rad = np.where(cross > 1e-12, ab * bc * ca / (2.0 * cross + 1e-15), np.inf)
            tight = np.zeros(len(out), dtype=bool)
            tight[2:-2] = rad < r_km
            # Spread the correction over the whole bend (neighbours too).
            tight[1:-1] |= tight[:-2] | tight[2:]
            tight &= ~fixed
            if not tight.any():
                break
            lap = np.zeros_like(out)
            lap[1:-1] = 0.5 * (out[:-2] + out[2:]) - out[1:-1]
            out[tight] += 0.5 * lap[tight]
        return self._resample_pinned(out, self._pin_indices(out, anchors), 0.01)

    @staticmethod
    def _resample(P, step_km):
        seg = np.hypot(np.diff(P[:, 0]), np.diff(P[:, 1]))
        s = np.concatenate([[0.0], np.cumsum(seg)])
        n = max(2, int(round(s[-1] / step_km)) + 1)
        si = np.linspace(0.0, s[-1], n)
        return np.stack([np.interp(si, s, P[:, 0]), np.interp(si, s, P[:, 1])], axis=1)

    def _resample_pinned(self, P, pins, step_km):
        """Uniform resampling between consecutive pinned indices (pins stay exact)."""
        idx = sorted({0, len(P) - 1} | {k for k, _ in pins})
        parts = []
        for a, b in zip(idx[:-1], idx[1:]):
            if b <= a:
                continue
            r = self._resample(P[a:b + 1], step_km)
            parts.append(r if not parts else r[1:])
        return np.concatenate(parts) if parts else P

    @staticmethod
    def _pin_indices(P, anchors):
        pins = []
        for a in anchors:
            k = int(np.argmin(np.hypot(P[:, 0] - a[0], P[:, 1] - a[1])))
            pins.append((k, np.array(a, dtype=np.float64)))
        return pins

    def _straighten_bridges(self, path):
        """Replaces the path across every river crossing (plus ~40 m run-up on each side)
        by a straight line, so the road and the bridge deck coincide."""
        riv = self.L["river"]
        fx = path[:, 0] / self.pitch_km
        fy = (self.size_km - path[:, 1]) / self.pitch_km
        d_r = bilinear(self.d_river, fx, fy)
        width_r = np.interp(bilinear(self.s_river, fx, fy) / self.river_len_km, [0, 1], riv["width_m"])
        wet = d_r * 1000.0 < width_r * 0.5 + riv["bank_m"] + 6.0
        path = path.copy()
        i = 0
        n = len(path)
        while i < n:
            if wet[i]:
                j = i
                while j + 1 < n and wet[j + 1]:
                    j += 1
                a, b = max(0, i - 4), min(n - 1, j + 4)
                if b - a >= 2:
                    t = np.linspace(0.0, 1.0, b - a + 1)[:, None]
                    path[a:b + 1] = path[a] * (1 - t) + path[b] * t
                i = j + 1
            else:
                i += 1
        return path

    def _street_profile(self, path, fx, fy):
        """Street heights (WORLD-PLAYTEST-01): every street samples one shared, smoothed
        street surface, so crossing streets meet at the same height (graded one by one they
        met with steps of up to 12 m); near an already graded road the street blends to that
        road's profile so it joins it level."""
        if getattr(self, "_street_surface", None) is None:
            self._street_surface = blur(self.h, 4)
            pts, hs = [], []
            for r in self.roads:
                if r["class"] != "street":
                    pts.append(r["path_km"])
                    hs.append(r["height"])
            self._graded_pts = np.concatenate(pts) if pts else np.zeros((0, 2))
            self._graded_h = np.concatenate(hs) if hs else np.zeros(0)
        p = bilinear(self._street_surface, fx, fy).astype(np.float64)
        pins = {}
        if len(self._graded_pts):
            for i in range(len(path)):
                d = np.hypot(self._graded_pts[:, 0] - path[i, 0], self._graded_pts[:, 1] - path[i, 1]) * 1000.0
                k = int(np.argmin(d))
                w = 1.0 - smoothstep(8.0, 45.0, d[k])
                if w > 0.0:
                    p[i] = p[i] + (self._graded_h[k] - p[i]) * w
                if d[k] < 4.0:
                    pins[i] = float(self._graded_h[k])
        # Crossings with streets graded before this one keep their height.
        for r in self.roads:
            if r["class"] != "street":
                continue
            Q = r["path_km"]
            for i in range(len(path)):
                d = np.hypot(Q[:, 0] - path[i, 0], Q[:, 1] - path[i, 1]) * 1000.0
                k = int(np.argmin(d))
                if d[k] < 4.0:
                    pins[i] = float(r["height"][k])
        # Grade limit between the pins (a street climbing a hillside is cut and filled).
        seg = np.hypot(np.diff(path[:, 0]), np.diff(path[:, 1])) * 1000.0
        g = self.L["road_classes"]["street"]["max_grade"] * np.maximum(seg, 0.5)
        for _ in range(4):
            for i, v in pins.items():
                p[i] = v
            for i in range(1, len(p)):
                p[i] = np.clip(p[i], p[i - 1] - g[i - 1], p[i - 1] + g[i - 1])
            for i in range(len(p) - 2, -1, -1):
                p[i] = np.clip(p[i], p[i + 1] - g[i], p[i + 1] + g[i])
        for i, v in pins.items():
            p[i] = v
        return p

    def _trim_steep(self, a, b, max_grade=0.15):
        """Shortens a street (a, b in km, a nearer the settlement centre for side streets)
        to where the ground gets steeper than max_grade: village streets stop at the
        hillside instead of climbing it."""
        L_km = float(np.hypot(*(b - a)))
        n = max(2, int(L_km / 0.01) + 1)
        t = np.linspace(0.0, 1.0, n)
        P = a[None, :] + (b - a)[None, :] * t[:, None]
        if getattr(self, "_h_b1", None) is None:
            self._h_b1 = blur(self.h, 1)
        h = bilinear(self._h_b1, P[:, 0] / self.pitch_km, (self.size_km - P[:, 1]) / self.pitch_km)
        gr = np.abs(np.diff(h)) / (L_km * 1000.0 / (n - 1))
        steep = np.nonzero(gr > max_grade)[0]
        if steep.size == 0:
            return a, b
        return a, P[max(1, int(steep[0]))]

    def _grade_road(self, rd, cls, path, wps, fixed, keys=None):
        riv = self.L["river"]
        path = self._straighten_bridges(path)
        fx = path[:, 0] / self.pitch_km
        fy = (self.size_km - path[:, 1]) / self.pitch_km
        ground = bilinear(self.h, fx, fy).astype(np.float64)
        d_r = bilinear(self.d_river, fx, fy)
        lvl = bilinear(self.river_level, fx, fy)
        ds = 10.0
        seg = np.hypot(np.diff(path[:, 0]), np.diff(path[:, 1])) * 1000.0
        if seg.size:
            ds = float(np.mean(seg))
        width_r = np.interp(bilinear(self.s_river, fx, fy) / self.river_len_km, [0, 1], riv["width_m"])
        bridge = d_r * 1000.0 < width_r * 0.5 + riv["bank_m"] + 6.0
        deck = lvl + 6.5
        p = ground.copy()
        win = max(1, int(60.0 / ds))
        # Fixed heights at shared waypoints (junctions with earlier roads).
        fixed_idx = {}
        if keys is None:
            keys = [(round(w[0], 4), round(w[1], 4)) for w in wps]
        for w, key in zip(wps, keys):
            j = int(np.argmin(np.hypot(path[:, 0] - w[0], path[:, 1] - w[1])))
            if key in fixed:
                fixed_idx[j] = fixed[key]
        street = rd["class"] == "street"
        if street:
            p = self._street_profile(path, fx, fy)
        for _ in range(0 if street else 30):
            k = np.ones(2 * win + 1) / (2 * win + 1)
            pp = np.pad(p, win, mode="edge")
            p = np.convolve(pp, k, mode="valid")
            p = np.where(bridge, np.maximum(p, deck), p)
            for j, v in fixed_idx.items():
                p[j] = v
        # Per-segment grade limit (the path spacing is not exactly uniform).
        g = cls["max_grade"] * np.maximum(seg, 0.5) if seg.size else np.zeros(0)
        for _ in range(0 if street else 3):
            for i in range(1, len(p)):
                p[i] = np.clip(p[i], p[i - 1] - g[i - 1], p[i - 1] + g[i - 1])
            for i in range(len(p) - 2, -1, -1):
                p[i] = np.clip(p[i], p[i + 1] - g[i], p[i + 1] + g[i])
            p = np.where(bridge, np.maximum(p, deck), p)
            for j, v in fixed_idx.items():
                p[j] = v
        for w, key in zip(wps, keys):
            if key not in fixed:
                j = int(np.argmin(np.hypot(path[:, 0] - w[0], path[:, 1] - w[1])))
                fixed[key] = float(p[j])
        # Bridge spans as index ranges.
        spans = []
        i = 0
        while i < len(bridge):
            if bridge[i]:
                j = i
                while j + 1 < len(bridge) and bridge[j + 1]:
                    j += 1
                spans.append([max(0, i - 1), min(len(bridge) - 1, j + 1)])
                i = j + 1
            else:
                i += 1
        length = float(np.sum(seg))
        # Culverts: the road crosses a drainage channel (catchment >= 0.4 km^2 on the D8
        # grid) on a fill. One culvert per crossing, at the highest fill.
        Dn = self.acc.shape[0]
        di = np.clip(np.round(path[:, 0] / (self.size_km / Dn)).astype(int), 0, Dn - 1)
        dj = np.clip(np.round((self.size_km - path[:, 1]) / (self.size_km / Dn)).astype(int), 0, Dn - 1)
        st = (self.acc_max3[dj, di] >= 0.4).astype(np.float32)
        fill = p - ground
        culverts = []
        i = 0
        while i < len(p):
            if st[i] > 0.5 and fill[i] > 0.3 and not bridge[i] and d_r[i] > 0.15:
                j = i
                while j + 1 < len(p) and st[j + 1] > 0.5:
                    j += 1
                k = i + int(np.argmax(fill[i:j + 1]))
                culverts.append(k)
                i = j + 1
            else:
                i += 1
        return {"name": rd["name"], "class": rd["class"], "path_km": path, "height": p, "culverts": culverts,
                "ground": ground, "bridges": spans, "length_m": length,
                "half_w": cls["lane_m"] * cls["lanes"] * 0.5, "shoulder": cls["shoulder_m"]}

    # ------------------------------------------------------------------ vegetation / tint maps
    def build_cover(self):
        L, X, Y, s = self.L, self.X, self.Y, self.seed
        vg = L["vegetation"]
        wx, wy = self.wx, self.wy
        gy, gx = np.gradient(self.h, self.pitch_km * 1000.0)
        slope = np.degrees(np.arctan(np.hypot(gx, gy)))
        self.slope_macro = slope
        n = fbm(wx / vg["forest_km"], wy / vg["forest_km"], s + 61, 5)
        clear = fbm(X / 0.5, Y / 0.5, s + 62, 3)
        forest = n * 1.5 + vg["forest_bias"] + 0.8 * fbm(X / 0.32, Y / 0.32, s + 60, 3)
        forest += vg["farmland_forest"] * self.farm
        forest -= 1.1 * self.open_sites * (0.8 + 0.4 * clear) + 1.4 * self.settle
        forest -= 1.0 * (1.0 - smoothstep(0.08, 0.6, self.d_river)) * (1.0 - self.H)
        forest -= 0.35 * smoothstep(0.35, 0.6, clear)  # natural clearings and meadows
        forest += 0.35 * self.rock * (1.0 - self.farm)
        tl = vg["treeline_m"]
        forest *= 1.0 - smoothstep(tl[0], tl[1], self.h + 60.0 * fbm(X / 0.6, Y / 0.6, s + 63, 3))
        forest *= 1.0 - smoothstep(34.0, 44.0, slope)
        forest = np.where(self.lake_mask > 0.5, -1.0, forest)
        forest = np.clip(forest, -1.0, 1.0)
        dens = smoothstep(0.0, 0.45, forest)

        near_settle = 1.0 - smoothstep(0.8, 2.6, self._settle_dist())
        low = 1.0 - smoothstep(0.35, 0.7, self.H)
        farm_like = np.maximum(np.maximum(self.farm, near_settle * 0.8), low * 0.6)
        fieldable = (farm_like > 0.35) & (slope < 9.0) & (self.lake_mask < 0.5) & (self.settle < 0.5)             & (self.d_river > 0.06) & (forest < 0.25 + 0.5 * self.farm)
        self.fieldable = blur(fieldable.astype(np.float32), 1)
        self.field_thr = (0.4 + 0.4 * farm_like).astype(np.float32)
        rnd, edge, hedgy = self.parcels(X, Y)
        self.forest_pre = dens.astype(np.float32)
        field = fieldable & (rnd < self.field_thr)
        hedge = fieldable & (edge < 7.0) & hedgy
        dens = np.where(field, 0.0, dens)
        dens = np.where(hedge, np.maximum(dens, 0.55), dens)
        self.field = field
        self.forest_dens = dens.astype(np.float32)

        # Species shares: pine on dry/rocky/high ground, birch on edges, wet ground and
        # near the treeline, spruce in moist valleys (the remainder).
        wet = np.clip(self.stream * 0.8 + (1.0 - smoothstep(4.0, 12.0, slope)) * 0.25
                      * (1.0 - smoothstep(0.0, 0.8, self.H)) + 0.25 * fbm(X / 0.8, Y / 0.8, s + 65, 3), 0, 1)
        wet = np.where(self.lake_mask > 0.5, 1.0, wet)
        edge_f = smoothstep(0.0, 0.25, dens) * (1.0 - smoothstep(0.35, 0.75, dens))
        pine = np.clip(0.2 + 0.5 * self.rock + 0.45 * smoothstep(250.0, 600.0, self.h)
                       + 0.25 * fbm(X / 1.1, Y / 1.1, s + 66, 3) - 0.5 * wet, 0.05, 0.9)
        birch = np.clip(0.12 + 0.55 * edge_f + 0.45 * wet * (1 - self.rock) + 0.5 * smoothstep(tl[0] - 120, tl[1], self.h)
                        + 0.2 * fbm(X / 0.9, Y / 0.9, s + 67, 3), 0.0, 0.9)
        birch = np.minimum(birch, 1.0 - pine)
        # Bog: flat, wet, low-lying hollows away from fields.
        bog = (wet > 0.5) & (slope < 4.0) & (~field) & (self.settle < 0.2) & (self.lake_mask < 0.5) \
            & (self.d_river > 0.15)
        self.wet = wet.astype(np.float32)
        self.bog = bog
        self.pine = pine.astype(np.float32)
        self.birch = birch.astype(np.float32)
        log("cover: forest %.0f%%, fields %.0f%%, bog %.1f%%" % (
            100.0 * float((dens > 0.4).mean()), 100.0 * float(field.mean()), 100.0 * float(bog.mean())))


    # ------------------------------------------------------------------ VISUAL-02 cover model
    def zone_weights(self, X, Y):
        """Soft weights (0..1) of the layout's landscape zones (cover_v2.zones), per zone type."""
        out = {}
        for z in self.L["cover_v2"].get("zones", []):
            q = ellipse_q(X, Y, z["center_km"], z["radii_km"], z.get("rot_deg", 0.0))
            q = q + 0.18 * fbm(X / 1.3 + 3.1, Y / 1.3, self.seed + 301, 3)
            w = (1.0 - smoothstep(0.55, 1.25, q)) * z.get("strength", 1.0)
            out[z["type"]] = np.maximum(out.get(z["type"], 0.0), w)
        return out

    def stands(self, X, Y):
        """Forestry stands (analytic, any resolution): warped blocks of ~stand_m metres in staggered rows, each with a
        random 0..1 (its age class) and the distance to the stand edge in metres."""
        sm = self.L["cover_v2"].get("stand_m", 260.0) / 1000.0
        wx = X + 0.30 * fbm(X / 1.7, Y / 1.7, self.seed + 311, 3)
        wy = Y + 0.30 * fbm(X / 1.7 + 4.2, Y / 1.7 - 1.3, self.seed + 312, 3)
        # One orientation per ~2 km block (a spatially varying angle would shear the grid into slivers).
        bi = np.floor(wx / 2.1)
        bj = np.floor(wy / 2.1)
        bh = ((bi * 92837111).astype(np.int64) ^ (bj * 689287499).astype(np.int64) ^ (self.seed * 7)) & 0xFFFF
        ang = ((bh % 180) - 90) * (math.pi / 360.0)
        u = (wx * np.cos(ang) + wy * np.sin(ang)) / sm
        v = (-wx * np.sin(ang) + wy * np.cos(ang)) / (sm * 0.7)
        vi = np.floor(v)
        shift = 0.5 * np.mod(vi, 2) + 0.3 * np.mod(vi, 3)
        ui = np.floor(u + shift)
        hsh = ((ui * 73856093).astype(np.int64) ^ (vi * 19349663).astype(np.int64) ^ (self.seed * 83492791)) & 0xFFFF
        rnd = ((hsh % 997) / 997.0).astype(np.float32)
        fu = u + shift - ui
        fv = v - vi
        edge = np.minimum(np.minimum(fu, 1 - fu) * sm, np.minimum(fv, 1 - fv) * sm * 0.7) * 1000.0
        return rnd, edge.astype(np.float32)

    def build_cover_v2(self):
        """VISUAL-02 vegetation cover. One set of environmental parameters - elevation, slope, moisture, distance to the
        river, rockiness, farmland / settlement influence and a few landscape zones from the layout - drives forest
        density, age (forestry stands with clear-cuts and regrowth), species and the open land together, so a moist valley,
        a dry pine moor or a farmed valley floor differ in trees, ground and colour at once."""
        L, X, Y, s = self.L, self.X, self.Y, self.seed
        vg = L["vegetation"]
        cv = L["cover_v2"]
        gy, gx = np.gradient(self.h, self.pitch_km * 1000.0)
        slope = np.degrees(np.arctan(np.hypot(gx, gy)))
        self.slope_macro = slope
        Z = self.zone_weights(X, Y)
        zero = np.zeros(X.shape, dtype=np.float32)
        z_spruce, z_pine = Z.get("spruce_forestry", zero), Z.get("pine_moor", zero)
        z_wet, z_mtn = Z.get("wetland", zero), Z.get("mountain_birch", zero)
        tl = vg["treeline_m"]

        # Moisture and dryness.
        low = 1.0 - smoothstep(0.0, 0.8, self.H)
        wet = np.clip(self.stream * 0.85 + (1.0 - smoothstep(3.0, 11.0, slope)) * 0.3 * low
                      + 0.22 * fbm(X / 0.8, Y / 0.8, s + 65, 3) + 0.35 * z_wet
                      + 0.25 * (1.0 - smoothstep(0.1, 0.5, self.d_river)), 0, 1)
        wet = np.where(self.lake_mask > 0.5, 1.0, wet).astype(np.float32)
        dry = np.clip(0.55 * self.rock + 0.35 * smoothstep(260.0, 620.0, self.h) + 0.6 * z_pine
                      + 0.25 * smoothstep(14.0, 30.0, slope) - 0.6 * wet + 0.15 * fbm(X / 1.4, Y / 1.4, s + 321, 3), 0, 1)

        # Where forest can stand: almost everywhere outside farmland, settlements, lakes, bog and steep rock; natural
        # openings are rarer and larger than the old two-scale blobs.
        # Farmed land round the villages follows the terrain and a warped outline, not a disc.
        near_settle = 1.0 - smoothstep(0.6, 2.2, self._settle_dist() + 0.7 * fbm(X / 1.1, Y / 1.1, s + 335, 3)
                                       + 0.9 * smoothstep(0.35, 0.8, self.H))
        cultural = np.clip(np.maximum(self.farm, near_settle * 0.85), 0, 1)
        ok = cv.get("opening_km", 2.4)
        n_big = fbm(self.wx / ok, self.wy / ok, s + 331, 4)
        n_mid = fbm(X / 0.55, Y / 0.55, s + 332, 3)
        forest = 0.95 + 0.55 * n_big + 0.22 * n_mid
        # Farmland and villages: woodlots and tree belts along streams instead of continuous forest.
        lots = smoothstep(0.22, 0.45, fbm(X / 0.6, Y / 0.6, s + 333, 3) + 0.55 * self.stream + 0.25 * self.rock)
        forest = forest * (1.0 - cultural) + (lots - 0.25) * cultural
        forest -= 1.1 * self.open_sites + 1.5 * self.settle
        forest -= 0.9 * (1.0 - smoothstep(0.06, 0.45, self.d_river)) * low
        forest -= 0.5 * z_wet * smoothstep(0.55, 0.85, wet)
        forest *= 1.0 - smoothstep(tl[0], tl[1], self.h + 70.0 * fbm(X / 0.6, Y / 0.6, s + 63, 3))
        forest *= 1.0 - smoothstep(34.0, 44.0, slope)
        forest = np.where(self.lake_mask > 0.5, -1.0, forest)
        inside = smoothstep(0.0, 0.35, np.clip(forest, -1, 1)).astype(np.float32)

        # Forestry stands: age 0 = fresh clear-cut, ~0.25 regrowth, 0.5 middle-aged, 1 mature / old. Clear-cuts are common
        # in the spruce forestry zone, rare elsewhere, absent on the moors and in the mountain birch.
        rnd, sedge = self.stands(X, Y)
        p_cut = np.clip(cv.get("clearcut_share", 0.06) + 0.12 * z_spruce - 0.08 * (z_pine + z_mtn) - 0.06 * cultural, 0, 0.3)
        age = np.where(rnd < p_cut, 0.04 * rnd / np.maximum(p_cut, 1e-3),
                       np.clip((rnd - p_cut) / np.maximum(1.0 - p_cut, 1e-3), 0, 1) ** 0.8)
        age = np.where(cultural > 0.6, np.maximum(age, 0.55), age)
        # Old open stands on rocky / dry ground.
        age = np.maximum(age, 0.75 * smoothstep(0.55, 0.9, dry))
        self.cut = ((age < 0.06) & (inside > 0.5)).astype(np.float32)

        # Density by stand age and site: regrowth closes up, old stands thin, moors and mountain birch stay open.
        a_den = np.where(age < 0.06, 0.08, np.interp(age, [0.06, 0.25, 0.55, 1.0], [0.55, 0.85, 0.82, 0.68]))
        site = 1.0 - 0.35 * smoothstep(0.5, 1.0, dry) - 0.12 * z_pine - 0.4 * z_mtn - 0.35 * smoothstep(0.55, 0.85, wet) * (1 - z_spruce)
        dens = inside * a_den * site
        # Soft forest edges: a 20-60 m band of thinner, younger trees (not a wall of trunks).
        edge_band = smoothstep(0.0, 0.6, inside) * (1.0 - smoothstep(0.6, 1.0, blur(inside, 3)))
        dens = dens * (1.0 - 0.45 * edge_band)
        # Stand boundaries read as slight gaps / density changes.
        dens = dens * (0.88 + 0.12 * smoothstep(0.0, 12.0, sedge))

        # Fields (the same parcel model as before, on the new open farmland).
        lowH = 1.0 - smoothstep(0.35, 0.7, self.H)
        farm_like = np.maximum(np.maximum(self.farm, near_settle * 0.8), lowH * 0.6)
        fieldable = (farm_like > 0.35) & (slope < 9.0) & (self.lake_mask < 0.5) & (self.settle < 0.5) \
            & (self.d_river > 0.06) & (forest < 0.25 + 0.5 * self.farm)
        self.fieldable = blur(fieldable.astype(np.float32), 1)
        self.field_thr = (0.4 + 0.4 * farm_like).astype(np.float32)
        prnd, pedge, hedgy = self.parcels(X, Y)
        self.forest_pre = dens.astype(np.float32)
        field = fieldable & (prnd < self.field_thr)
        hedge = fieldable & (pedge < 7.0) & hedgy
        dens = np.where(field, 0.0, dens)
        dens = np.where(hedge, np.maximum(dens, 0.55), dens)
        self.field = field
        self.forest_dens = np.clip(dens, 0, 1).astype(np.float32)

        # Species: pine on dry, rocky, high and moor ground; birch on wet ground, edges, regrowth, near farms and towards
        # the treeline; spruce (the remainder) in moist valleys and the forestry zone.
        young = 1.0 - smoothstep(0.15, 0.45, age)
        pine = np.clip(0.08 + 0.75 * dry + 0.3 * z_pine - 0.35 * wet - 0.25 * z_spruce
                       + 0.12 * fbm(X / 1.1, Y / 1.1, s + 66, 3), 0.03, 0.92)
        birch = np.clip(0.06 + 0.45 * edge_band + 0.5 * wet * (1 - self.rock) + 0.35 * young + 0.3 * cultural
                        + 0.7 * z_mtn + 0.5 * smoothstep(tl[0] - 150, tl[1], self.h) + 0.15 * fbm(X / 0.9, Y / 0.9, s + 67, 3)
                        - 0.2 * z_spruce, 0.0, 0.95)
        birch = np.minimum(birch, 1.0 - pine)
        boggy = wet + 0.35 * z_wet * smoothstep(-0.2, 0.3, fbm(X / 0.4, Y / 0.4, s + 341, 3))
        bog = (boggy > 0.62) & (slope < 5.0) & (~field) & (self.settle < 0.2) & (self.lake_mask < 0.5) & (self.d_river > 0.15)
        # Open bog: the trees thin out to scattered pine and birch.
        self.forest_dens = np.where(bog, self.forest_dens * 0.25, self.forest_dens).astype(np.float32)
        self.wet, self.bog = wet, bog
        self.pine, self.birch = pine.astype(np.float32), birch.astype(np.float32)
        self.age = age.astype(np.float32)
        self.edge_band = edge_band.astype(np.float32)
        self.dry = dry.astype(np.float32)
        log("cover v2: forest %.0f%% (dense %.0f%%), clear-cuts %.1f%%, fields %.0f%%, bog %.1f%%" % (
            100.0 * float((self.forest_dens > 0.25).mean()), 100.0 * float((self.forest_dens > 0.7).mean()),
            100.0 * float(self.cut.mean()), 100.0 * float(field.mean()), 100.0 * float(bog.mean())))

    # VISUAL-02 field palette: mostly leys (grass for silage / hay, the common Nordic field), some grain, little tilled soil;
    # each parcel stays one flat colour (the ground shader reads the parcel's colour as its identity).
    CROPS_V2 = np.array([[0.66, 0.76, 0.52], [0.60, 0.72, 0.48], [0.71, 0.78, 0.55], [0.64, 0.74, 0.50],
                         [0.88, 0.84, 0.62], [0.84, 0.82, 0.64], [0.68, 0.59, 0.47], [0.70, 0.75, 0.55]], dtype=np.float32)

    def tint_of_v2(self, X, Y, dens, field, rnd, alpine, bog, pine, birch, age, wet, cut):
        """Colour-map multiplier for the VISUAL-02 cover: meadow by moisture, forest by species and age, clear-cuts,
        ley-dominant fields, alpine heath, bog."""
        s = self.seed
        dryish = smoothstep(0.25, 0.75, 1.0 - wet)
        meadow = np.array([0.74, 0.80, 0.66], dtype=np.float32) * (1 - dryish[..., None]) \
            + np.array([0.84, 0.83, 0.70], dtype=np.float32) * dryish[..., None]
        mv = 0.05 * fbm(X / 0.3, Y / 0.3, s + 71, 3)
        tint = meadow + np.stack([mv * 1.1, mv, -mv * 0.4], axis=-1)
        spruce_c = np.array([0.34, 0.44, 0.30], dtype=np.float32)
        pine_c = np.array([0.46, 0.50, 0.34], dtype=np.float32)
        birch_c = np.array([0.54, 0.62, 0.38], dtype=np.float32)
        sp = np.clip(1.0 - pine - birch, 0, 1)
        fc = spruce_c * sp[..., None] + pine_c * pine[..., None] + birch_c * birch[..., None]
        fc = fc * (0.92 + 0.16 * smoothstep(0.1, 0.5, age))[..., None]
        # Open dry pine moor: lichen and heather between the trees lighten the stand.
        fc = fc + (np.array([0.70, 0.70, 0.56], dtype=np.float32) - fc) * (0.45 * smoothstep(0.5, 0.95, pine) * (1.0 - smoothstep(0.3, 0.8, dens)))[..., None] * (1.0 + 0.10 * (1.0 - smoothstep(0.1, 0.4, age)))[..., None]
        w = smoothstep(0.04, 0.45, dens)[..., None]
        tint = tint + (fc - tint) * w
        cut_c = np.array([0.80, 0.74, 0.58], dtype=np.float32)
        tint = tint + (cut_c - tint) * (cut * (1.0 - w[..., 0]))[..., None] * 0.85
        ci = (rnd * 977).astype(np.int64) % len(self.CROPS_V2)
        tint = np.where(field[..., None], self.CROPS_V2[ci], tint)
        a = (alpine * (1 - dens))[..., None] * 0.7
        tint = tint + (np.array([0.90, 0.86, 0.74], dtype=np.float32) - tint) * a
        tint = np.where(bog[..., None], tint * np.array([0.98, 0.88, 0.66], dtype=np.float32), tint)
        return np.clip(tint, 0.0, 1.0)

    # ------------------------------------------------------------------ outputs
    def write_macro_outputs(self):
        R = self.R
        veg = np.stack([to_u8(self.forest_dens), to_u8(self.pine), to_u8(self.birch), to_u8(self.wet)], axis=2)
        write_png(os.path.join(self.out, "vegetation.png"), veg)
        # Terrain info for scattering: rockiness, field, settlement, water proximity.
        tl = self.L["vegetation"]["treeline_m"]
        rocky = np.maximum(np.maximum(self.rock, self.massif * smoothstep(tl[0] - 150, tl[1], self.h)),
                           smoothstep(24.0, 38.0, self.slope_macro))
        riv_w = np.interp(self.s_river / self.river_len_km, [0, 1], self.L["river"]["width_m"]) * 0.5
        water = np.maximum(self.lake_mask, (self.d_river * 1000.0 < riv_w + 25.0).astype(np.float32))
        info = np.stack([to_u8(rocky), to_u8(self.field.astype(np.float32)), to_u8(self.settle),
                         to_u8(np.maximum(water, blur(self.lake_mask, 3)))], axis=2)
        write_png(os.path.join(self.out, "info.png"), info)
        alpine = smoothstep(self.L["vegetation"]["treeline_m"][0] - 80, self.L["vegetation"]["treeline_m"][1], self.h)
        rnd, _, _ = self.parcels(self.X, self.Y)
        if "cover_v2" in self.L:
            # VISUAL-02: stand map for the scatter - R age (0 clear-cut .. 1 mature), G forest edge band, B dryness,
            # A clear-cut flag.
            stand = np.stack([to_u8(self.age), to_u8(self.edge_band), to_u8(self.dry), to_u8(self.cut)], axis=2)
            write_png(os.path.join(self.out, "stand.png"), stand)
            self.tint = self.tint_of_v2(self.X, self.Y, self.forest_dens, self.field, rnd, alpine, self.bog,
                                        self.pine, self.birch, self.age, self.wet, self.cut)
        else:
            self.tint = self.tint_of(self.X, self.Y, self.forest_dens, self.field, rnd, alpine, self.bog)

    def preview(self, name="preview_macro.png"):
        """Satellite-style preview: hillshade x cover colours, water, roads."""
        h = self.h
        R = self.R
        gy, gx = np.gradient(h, self.pitch_km * 1000.0)
        # Sun from the north-west (like the reference shading), 40 degrees elevation.
        nx, ny, nz = -gx, gy, np.ones_like(h)
        nl = np.sqrt(nx * nx + ny * ny + nz * nz)
        lx, ly, lz = -0.55, 0.55, 0.63
        shade = np.clip((nx * lx + ny * ly + nz * lz) / nl, 0, 1)
        shade = 0.35 + 0.85 * shade
        base = np.array([0.42, 0.52, 0.27])
        col = np.ones((R, R, 3)) * base
        col = col * self.tint / 0.92 if hasattr(self, "tint") else col
        rockc = np.array([0.55, 0.54, 0.52])
        rock_b = smoothstep(28.0, 40.0, self.slope_macro) if hasattr(self, "slope_macro") else 0
        col = col + (rockc - col) * np.asarray(rock_b)[..., None]
        if hasattr(self, "forest_dens"):
            fcol = np.array([0.13, 0.24, 0.11])
            col = col + (fcol - col) * (self.forest_dens[..., None] * 0.85)
        col = col * shade[..., None]
        water = np.array([0.10, 0.22, 0.32])
        riv = self.d_river * 1000.0 < np.interp(self.s_river / self.river_len_km, [0, 1], self.L["river"]["width_m"]) * 0.5
        col = np.where((self.lake_mask > 0.5)[..., None] | riv[..., None], water, col)
        if hasattr(self, "roads"):
            for rd in self.roads:
                c = {"primary": (0.82, 0.80, 0.76), "secondary": (0.78, 0.75, 0.68),
                     "local": (0.70, 0.62, 0.50), "track": (0.62, 0.55, 0.42), "street": (0.45, 0.45, 0.45)}[rd["class"]]
                w = {"primary": 2, "secondary": 1, "local": 1, "track": 0, "street": 0}[rd["class"]]
                fx = np.round(rd["path_km"][:, 0] / self.pitch_km).astype(int)
                fy = np.round((self.size_km - rd["path_km"][:, 1]) / self.pitch_km).astype(int)
                for dx in range(-w, w + 1):
                    for dy in range(-w, w + 1):
                        col[np.clip(fy + dy, 0, R - 1), np.clip(fx + dx, 0, R - 1)] = c
        for st in []:
            cx = int(st["center_km"][0] / self.pitch_km)
            cy = int((self.size_km - st["center_km"][1]) / self.pitch_km)
            rr = int(st["radius_km"] / self.pitch_km * 0.6)
            yy, xx = np.ogrid[-rr:rr + 1, -rr:rr + 1]
            m = (xx * xx + yy * yy) <= rr * rr
            y0, x0 = cy - rr, cx - rr
            sub = col[max(0, y0):y0 + 2 * rr + 1, max(0, x0):x0 + 2 * rr + 1]
            mm = m[max(0, -y0):max(0, -y0) + sub.shape[0], max(0, -x0):max(0, -x0) + sub.shape[1]]
            sub[mm] = sub[mm] * 0.5 + np.array([0.62, 0.42, 0.36]) * 0.5
        img = to_u8(np.clip(col, 0, 1))
        write_png(os.path.join(self.out, name), img)
        # Small elevation preview with the same grey ramp as the reference inset.
        hn = np.clip((h + 50.0) / 1250.0, 0, 1)
        write_png(os.path.join(self.out, "preview_height.png"), to_u8(hn)[::2, ::2])

    # ------------------------------------------------------------------ full resolution
    def build_full(self):
        """Writes height.r32 and control.r32 (10240^2 float32, row 0 = north edge)."""
        full = self.full
        f = full // self.R
        sp = self.L["size_m"] / full  # metres per vertex
        riv = self.L["river"]
        reg = self.L["regional"]
        rough = np.clip(0.25 + 0.75 * np.maximum(self.rock, self.massif) + 0.3 * self.H - 0.3 * self.farm, 0.1, 1.0)
        rough = rough * (1.0 - 0.8 * self.open_sites)
        rpts = [(p[0] * 1000.0 - 10000.0, 10000.0 - p[1] * 1000.0) for p in self.river_points()]
        rsegs = []
        s0 = 0.0
        for a, b in zip(rpts[:-1], rpts[1:]):
            l = math.hypot(b[0] - a[0], b[1] - a[1])
            rsegs.append((a, b, s0, l))
            s0 += l
        rlen = s0
        wmax = riv["width_m"][1] * 0.5 + riv["bank_m"] * 1.6 + 160.0
        # Road segments in world metres with graded heights.
        segs = []
        for ri, rd in enumerate(self.roads):
            P = rd["path_km"]
            wx = P[:, 0] * 1000.0 - 10000.0
            wz = 10000.0 - P[:, 1] * 1000.0
            hgt = rd["height"]
            br = np.zeros(len(P), dtype=bool)
            for a, b in rd["bridges"]:
                br[a:b + 1] = True
            for i in range(len(P) - 1):
                segs.append((wx[i], wz[i], wx[i + 1], wz[i + 1], hgt[i], hgt[i + 1], rd["half_w"], rd["shoulder"],
                             br[i] and br[i + 1], ri, rd["class"]))
        segs = np.array([s[:10] for s in segs], dtype=np.float64)
        seg_cls = []
        for rd in self.roads:
            seg_cls += [rd["class"]] * (len(rd["path_km"]) - 1)
        seg_cls = np.array(seg_cls)
        surf_cls = np.array([{"primary": 0, "secondary": 1, "local": 2, "track": 3, "street": 4}[c] for c in seg_cls])
        smin_z = np.minimum(segs[:, 1], segs[:, 3])
        smax_z = np.maximum(segs[:, 1], segs[:, 3])

        hpath = os.path.join(self.out, "height.r32")
        cpath = os.path.join(self.out, "control.r32")
        fh = open(hpath, "wb")
        fc = open(cpath, "wb")
        fcol = open(os.path.join(self.out, "color.rgba8"), "wb")
        strip = 256
        cols = np.arange(full)
        Xw = -10000.0 + cols * sp
        stats_slope = np.zeros(91, dtype=np.int64)
        hmin, hmax = 1e9, -1e9
        # Macro maps needed per pixel (upsampled per strip).
        maps = {"forest": self.forest_pre, "rock": self.rock.astype(np.float32),
                "fieldable": self.fieldable, "fthr": self.field_thr, "bog": self.bog.astype(np.float32),
                "settle": self.settle, "rough": rough.astype(np.float32), "wet": self.wet,
                "alpine": smoothstep(self.L["vegetation"]["treeline_m"][0] - 60, self.L["vegetation"]["treeline_m"][1] + 40, self.h).astype(np.float32),
                "lake": self.lake_mask}
        v2 = "cover_v2" in self.L
        if v2:
            maps.update({"pine": self.pine, "birch": self.birch, "age": self.age, "cut": self.cut})
        prev_tail = None
        for r0 in range(0, full, strip):
            # One-row halo above and below for slope.
            ra = max(0, r0 - 1)
            rb = min(full, r0 + strip + 1)
            n = rb - ra
            Zw = -10000.0 + np.arange(ra, rb) * sp
            XX, ZZ = np.meshgrid(Xw, Zw)
            # Bicubic macro height.
            sr0 = ra // f
            sr1 = min(self.R, (rb - 1) // f + 3)
            src = self.h[max(0, sr0 - 2):sr1 + 2]
            off = max(0, sr0 - 2)
            hx = upsample_axis(src, f, 1, 0, full)
            H = upsample_axis(np.pad(hx, ((0, 0), (0, 0)), mode="edge"), f, 0, ra - off * f, n) if False else None
            # Upsample rows: build an index map relative to the cut-out.
            i = np.arange(ra, rb)
            base = i // f
            t = ((i % f) / f).astype(np.float32)
            w = catmull_weights(t)
            H = np.zeros((n, full), dtype=np.float32)
            for k in range(4):
                idx = np.clip(base - 1 + k, 0, self.R - 1) - off
                H += hx[idx] * w[k][:, None]

            def up(m):
                sub = m[max(0, sr0 - 2):sr1 + 2]
                mx = upsample_axis(sub, f, 1, 0, full)
                out = np.zeros((n, full), dtype=np.float32)
                for k in range(4):
                    idx = np.clip(base - 1 + k, 0, self.R - 1) - off
                    out += mx[idx] * w[k][:, None]
                return out

            M = {k: up(v) for k, v in maps.items()}
            # Detail noise: gentle everywhere, stronger on rock.
            det = fbm(XX / 55.0, ZZ / 55.0, self.seed + 81, 4)
            det_r = ridged(XX / 38.0, ZZ / 38.0, self.seed + 82, 3)
            H += det * reg["detail_m"] * M["rough"] + (det_r - 0.4) * reg["detail_rocky_m"] * smoothstep(0.35, 0.9, M["rock"])
            H += 0.12 * perlin(XX / 6.0, ZZ / 6.0, self.seed + 83) * (1.0 - M["settle"])

            # River channel and banks (nearest segment wins).
            dR = np.full((n, full), np.inf, dtype=np.float32)
            sR = np.zeros((n, full), dtype=np.float32)
            zlo, zhi = Zw[0] - wmax, Zw[-1] + wmax
            for a, b, s_a, l in rsegs:
                if max(a[1], b[1]) < zlo or min(a[1], b[1]) > zhi:
                    continue
                x0 = max(0, int((min(a[0], b[0]) - wmax + 10000.0) / sp))
                x1 = min(full, int((max(a[0], b[0]) + wmax + 10000.0) / sp) + 1)
                if x1 <= x0:
                    continue
                px = XX[:, x0:x1]
                pz = ZZ[:, x0:x1]
                dx, dz = b[0] - a[0], b[1] - a[1]
                tt = np.clip(((px - a[0]) * dx + (pz - a[1]) * dz) / (l * l), 0, 1)
                d = np.hypot(px - a[0] - tt * dx, pz - a[1] - tt * dz)
                sub = dR[:, x0:x1]
                m = d < sub
                sub[m] = d[m]
                sR[:, x0:x1][m] = (s_a + tt * l)[m]
            near = np.isfinite(dR)
            if near.any():
                frac = sR / rlen
                lvl = riv["level_m"][0] + (riv["level_m"][1] - riv["level_m"][0]) * frac
                half = (riv["width_m"][0] + (riv["width_m"][1] - riv["width_m"][0]) * frac) * 0.5
                # Meander wobble of the bank line so the channel is not a perfect tube.
                half = half * (1.0 + 0.12 * perlin(XX / 90.0, ZZ / 90.0, self.seed + 84))
                depth = riv["channel_depth_m"]
                # Bank width varies along the river (gravel shelves, steeper cut banks).
                bank = riv["bank_m"] * (0.65 + 0.9 * smoothstep(-0.5, 0.5, fbm(XX / 140.0, ZZ / 140.0, self.seed + 85, 2)))
                above = riv["floodplain_above_m"]
                q = dR / half
                chan = lvl - 0.6 - (depth - 0.6) * np.sqrt(np.clip(1.0 - q * q, 0, 1))
                bankh = lvl - 0.6 + (above + 0.9) * smoothstep(half, half + bank, dR)
                target = np.where(dR < half, chan, bankh)
                inner = dR < half + bank
                H = np.where(near & inner, target, H)
                # Outside the bank: hold the water in (minimum height close to the bank) and
                # cap the rise at a bounded grade, so the land meets the bank without a wall.
                # The macro relief is already grade-limited; this only resolves the last tens
                # of metres the 9.8 m macro grid cannot. The cap fades out with distance.
                d_o = dR - half - bank
                g_full = 0.45 + 0.15 * smoothstep(-0.5, 0.5, fbm(XX / 260.0, ZZ / 260.0, self.seed + 86, 2))
                outer = near & (~inner) & (d_o < 150.0)
                lo = lvl + 0.3 + above * (1.0 - smoothstep(30.0, 70.0, d_o))
                hi = lvl + above + 0.3 + g_full * np.maximum(d_o, 0.0)
                capped = np.maximum(smin(H, hi, 1.5), lo)
                fade = 1.0 - smoothstep(80.0, 150.0, d_o)
                H = np.where(outer, H + (capped - H) * fade, H)
                river_px = near & (dR < half)
                riv_half = half
                bank_px = near & (dR >= half) & (dR < half + bank * (0.55 + 0.3 * perlin(XX / 11.0, ZZ / 11.0, self.seed + 87)))
            else:
                river_px = np.zeros((n, full), dtype=bool)
                riv_half = np.zeros((n, full), dtype=np.float32)
                bank_px = river_px

            # Roads: nearest segment height and class; cut/fill blend.
            dS = np.full((n, full), np.inf, dtype=np.float32)
            hS = np.zeros((n, full), dtype=np.float32)
            wS = np.zeros((n, full), dtype=np.float32)
            cS = np.full((n, full), -1, dtype=np.int8)
            bS = np.zeros((n, full), dtype=bool)
            reach = 40.0
            cand = np.nonzero((smax_z > Zw[0] - reach) & (smin_z < Zw[-1] + reach))[0]
            for si in cand:
                ax, az, bx, bz, ha, hb, hw, sh, isb = segs[si][:9]
                x0 = max(0, int((min(ax, bx) - reach + 10000.0) / sp))
                x1 = min(full, int((max(ax, bx) + reach + 10000.0) / sp) + 1)
                zr0 = max(0, int((min(az, bz) - reach - Zw[0]) / sp))
                zr1 = min(n, int((max(az, bz) + reach - Zw[0]) / sp) + 1)
                if x1 <= x0 or zr1 <= zr0:
                    continue
                px = XX[zr0:zr1, x0:x1]
                pz = ZZ[zr0:zr1, x0:x1]
                dx, dz = bx - ax, bz - az
                l2 = dx * dx + dz * dz
                if l2 < 1e-6:
                    continue
                tt = np.clip(((px - ax) * dx + (pz - az) * dz) / l2, 0, 1)
                d = np.hypot(px - ax - tt * dx, pz - az - tt * dz)
                sub = dS[zr0:zr1, x0:x1]
                m = d < sub
                sub[m] = d[m]
                hS[zr0:zr1, x0:x1][m] = (ha + tt * (hb - ha))[m]
                wS[zr0:zr1, x0:x1][m] = hw + sh
                cS[zr0:zr1, x0:x1][m] = surf_cls[si]
                bS[zr0:zr1, x0:x1][m] = bool(isb)
            onroad = np.isfinite(dS)
            if onroad.any():
                diff = np.abs(H - hS)
                fall = np.clip(5.0 + 1.6 * diff, 5.0, 24.0)
                wgt = 1.0 - smoothstep(wS + 1.0, wS + 1.0 + fall, dS)
                # Bridges: only the channel and its banks stay open under the deck; the
                # rest of the span is the embankment (abutment) up to the deck height.
                # WORLD-PLAYTEST-01: excluding whole bridge segments left the deck ends
                # 2-6 m above the ground.
                open_ch = bS & np.isfinite(dR) & (dR < riv_half + riv["bank_m"] * 1.6 + 2.0)
                wgt = np.where(onroad & ~open_ch, wgt, 0.0)
                # Bridge approaches: keep the river channel under the deck.
                H = H + (hS - H) * wgt

            # Slope for texturing (degrees).
            gzz, gxx = np.gradient(H, sp)
            slope = np.degrees(np.arctan(np.hypot(gxx, gzz)))
            core = slice(r0 - ra, r0 - ra + min(strip, full - r0))
            Hc = H[core]
            hmin = min(hmin, float(Hc.min()))
            hmax = max(hmax, float(Hc.max()))
            sc = slope[core]
            stats_slope += np.bincount(np.clip(sc.astype(np.int64).ravel(), 0, 90), minlength=91)

            Mc = {k: v[core] for k, v in M.items()}
            Xk = (XX[core] + 10000.0) / 1000.0
            Yk = (10000.0 - ZZ[core]) / 1000.0
            rnd, edge, hedgy = self.parcels(Xk, Yk)
            fieldable = Mc["fieldable"] > 0.5
            field = fieldable & (rnd < Mc["fthr"])
            hedge = fieldable & (edge < 3.0) & hedgy
            dens = np.where(field, 0.0, Mc["forest"])
            dens = np.where(hedge, np.maximum(dens, 0.6), dens)
            Mc["forest"] = np.clip(dens, 0, 1)
            Mc["field"] = field.astype(np.float32)
            ctrl = self._control(XX[core], ZZ[core], sc, Mc, dS[core], wS[core], cS[core], river_px[core], dR[core], Hc,
                                 bank_px[core])
            if v2:
                tint = self.tint_of_v2(Xk, Yk, Mc["forest"], field, rnd, Mc["alpine"], Mc["bog"] > 0.5, Mc["pine"],
                                       Mc["birch"], Mc["age"], Mc["wet"], Mc["cut"])
            else:
                tint = self.tint_of(Xk, Yk, Mc["forest"], field, rnd, Mc["alpine"], Mc["bog"] > 0.5)
            rgba = np.concatenate([to_u8(tint), np.full(tint.shape[:2] + (1,), 128, dtype=np.uint8)], axis=2)
            fh.write(Hc.astype("<f4").tobytes())
            fc.write(ctrl.astype("<u4").tobytes())
            fcol.write(rgba.tobytes())
            if (r0 // strip) % 8 == 0:
                log("full res rows %d/%d" % (r0, full))
        fh.close()
        fc.close()
        fcol.close()
        self.stats["height_min_m"] = hmin
        self.stats["height_max_m"] = hmax
        self.stats["slope_hist_deg"] = stats_slope.tolist()
        log("full res done: %.1f..%.1f m" % (hmin, hmax))

    def _control(self, XX, ZZ, slope, M, dS, wS, cS, river_px, dR, H, bank_px=None):
        s = self.seed
        n1 = fbm(XX / 23.0, ZZ / 23.0, s + 91, 3)
        n2 = perlin(XX / 7.0, ZZ / 7.0, s + 92)
        forest = M["forest"] + 0.18 * n1
        base = np.full(XX.shape, TEX_GRASS, dtype=np.uint32)
        over = np.full(XX.shape, TEX_GRASS, dtype=np.uint32)
        blend = np.zeros(XX.shape, dtype=np.float32)
        # Forest floor with a soft edge into the meadow.
        fb = smoothstep(0.25, 0.6, forest)
        is_forest = fb > 0.5
        base = np.where(is_forest, TEX_FOREST, base)
        over = np.where(is_forest, TEX_GRASS, TEX_FOREST)
        blend = np.where(is_forest, 1.0 - fb, fb)
        # VISUAL-02 clear-cuts: grass with bare patches (slash, ruts), no forest floor.
        if "cut" in M:
            cutm = (M["cut"] > 0.5) & (M["forest"] < 0.3)
            base = np.where(cutm, TEX_GRASS, base)
            over = np.where(cutm, TEX_DIRT, over)
            blend = np.where(cutm, np.clip(0.15 + 0.45 * smoothstep(0.1, 0.7, n2) * smoothstep(-0.2, 0.4, n1), 0, 0.7), blend)
        # Fields.
        fld = M["field"] > 0.5
        base = np.where(fld, TEX_FIELD, base)
        over = np.where(fld, TEX_GRASS, over)
        blend = np.where(fld, np.clip(0.15 + 0.15 * n1, 0, 1) * smoothstep(0.5, 0.9, 1.0 - M["field"] + 0.5), blend)
        # Dry alpine grass / heath above the treeline.
        alp = M["alpine"] > 0.5
        base = np.where(alp & ~is_forest, TEX_FIELD, base)
        over = np.where(alp & ~is_forest, TEX_ROCK, over)
        blend = np.where(alp & ~is_forest, np.clip(0.25 + 0.35 * n1, 0, 1), blend)
        # Bog.
        bog = (M["bog"] + 0.25 * n1) > 0.55
        base = np.where(bog, TEX_BOG, base)
        over = np.where(bog, TEX_GRASS, over)
        blend = np.where(bog, np.clip(0.2 + 0.4 * n2, 0, 1), blend)
        # Settlement yards: gravel patches.
        # Settlements: mown grass with small gravel yards (no large bare patches).
        yard = (M["settle"] > 0.75) & (n2 > 0.55) & (n1 > 0.25)
        base = np.where(yard, TEX_DIRT, base)
        over = np.where(yard, TEX_GRAVEL, over)
        blend = np.where(yard, 0.5, blend)
        # Rock on steep slopes and rocky ground (overlay wins).
        rb = smoothstep(27.0, 40.0, slope + 6.0 * n1) + 0.6 * smoothstep(0.6, 1.0, M["rock"]) * smoothstep(14.0, 26.0, slope)
        rb = np.clip(rb + 0.75 * M["alpine"] * smoothstep(6.0, 18.0, slope), 0, 1)
        use_rock = rb > 0.08
        over = np.where(use_rock, TEX_ROCK, over)
        blend = np.where(use_rock, np.maximum(rb, 0.0), blend)
        # River bed and banks: gravel/dirt.
        rbk = np.isfinite(dR) & (dR < np.where(river_px, 1e9, 0.0) + 0.0)
        base = np.where(river_px, TEX_GRAVEL, base)
        over = np.where(river_px, TEX_DIRT, over)
        blend = np.where(river_px, 0.5, blend)
        # Wet bank shelf: dirt with gravel patches between the water and the meadow.
        if bank_px is not None:
            base = np.where(bank_px, TEX_DIRT, base)
            over = np.where(bank_px, TEX_GRAVEL, over)
            blend = np.where(bank_px, np.clip(0.35 + 0.3 * n2, 0, 1), blend)
        # Lake beds.
        lk = M["lake"] > 0.5
        base = np.where(lk, TEX_DIRT, base)
        over = np.where(lk, TEX_GRAVEL, over)
        blend = np.where(lk, 0.4, blend)
        # Unpaved roads: gravel surface with dirt verges; paved roads get gravel shoulders
        # (the Road Generator mesh covers the carriageway).
        onr = np.isfinite(dS)
        street = onr & (cS == 4) & (dS < wS - 0.2)
        unpaved = onr & (cS >= 2) & (cS != 4)
        surf = unpaved & (dS < wS - 0.3 + 0.5 * n2)
        verge = onr & (dS < wS + 2.5 + 1.0 * n2) & ~surf
        # Dirt as base/overlay so the particle grass (excluded_texture_id = dirt) stays
        # off the track surface and thins out on the verges.
        base = np.where(verge, TEX_GRASS, base)
        over = np.where(verge, TEX_DIRT, over)
        blend = np.where(verge, 1.0 - smoothstep(wS - 0.5, wS + 3.0, dS), blend)
        base = np.where(surf, TEX_DIRT, base)
        over = np.where(surf, TEX_GRAVEL, over)
        blend = np.where(surf, np.clip(0.55 + 0.12 * n2, 0, 0.68), blend)
        base = np.where(street, TEX_ASPHALT, base)
        over = np.where(street, TEX_GRAVEL, over)
        blend = np.where(street, np.clip(0.1 + 0.1 * n2, 0, 1), blend)
        b8 = np.clip(np.round(blend * 255.0), 0, 255).astype(np.uint32)
        return (base << 27) | (over << 22) | (b8 << 14)

    # ------------------------------------------------------------------ json outputs
    def write_json(self):
        riv = self.L["river"]
        # Dense river centreline (every ~25 m) with width and water level.
        P = np.array(self.river_points(), dtype=np.float64)
        seg = np.hypot(np.diff(P[:, 0]), np.diff(P[:, 1]))
        s = np.concatenate([[0.0], np.cumsum(seg)])
        si = np.linspace(0, s[-1], int(s[-1] / 0.025) + 1)
        # Catmull-like smoothing of the polyline for the water mesh.
        cx = np.interp(si, s, P[:, 0])
        cy = np.interp(si, s, P[:, 1])
        for _ in range(4):
            cx[1:-1] = (cx[:-2] + 2 * cx[1:-1] + cx[2:]) / 4.0
            cy[1:-1] = (cy[:-2] + 2 * cy[1:-1] + cy[2:]) / 4.0
        frac = si / s[-1]
        river = {"name": riv["name"],
                 "points": [[float(x * 1000 - 10000), float(10000 - y * 1000)] for x, y in zip(cx, cy)],
                 "width": [float(riv["width_m"][0] + (riv["width_m"][1] - riv["width_m"][0]) * t) + 6.0 for t in frac],
                 "level": [float(riv["level_m"][0] + (riv["level_m"][1] - riv["level_m"][0]) * t) for t in frac]}
        lakes = []
        for i, info in enumerate(self.lake_info):
            # Shoreline: march around the lake on the macro grid (polar samples of q=1).
            lk = self.L["lakes"][i]
            cxk, cyk = lk["center_km"]
            pts = []
            for a in np.linspace(0, 2 * math.pi, 180, endpoint=False):
                r = np.linspace(0.02, max(lk["radii_km"]) * 2.0, 400)
                xs = cxk + r * math.cos(a)
                ys = cyk + r * math.sin(a)
                fx = xs / self.pitch_km
                fy = (self.size_km - ys) / self.pitch_km
                qv = bilinear(info["q"].astype(np.float32), fx, fy)
                k = int(np.argmax(qv > 1.0))
                rr = r[max(0, k)] + 0.012  # a little past the shore, under the bank
                pts.append([float((cxk + rr * math.cos(a)) * 1000 - 10000), float(10000 - (cyk + rr * math.sin(a)) * 1000)])
            lakes.append({"name": info["name"], "level": info["level"], "outline": pts})
        with open(os.path.join(self.out, "water.json"), "w", encoding="utf-8") as fp:
            json.dump({"river": river, "lakes": lakes}, fp)

        roads = []
        for rd in self.roads:
            P = rd["path_km"]
            pts = [[round(float(x * 1000 - 10000), 2), round(float(h), 2), round(float(10000 - y * 1000), 2)]
                   for (x, y), h in zip(P, rd["height"])]
            cls = self.L["road_classes"][rd["class"]]
            roads.append({"name": rd["name"], "class": rd["class"], "mesh": cls["mesh"],
                          "lane_m": cls["lane_m"], "lanes": cls["lanes"], "shoulder_m": cls["shoulder_m"],
                          "points": pts, "bridges": rd["bridges"], "culverts": [int(k) for k in rd["culverts"]],
                          "length_m": rd["length_m"]})
        sites = {"settlements": [], "plateaus": [], "settlement_layer": bool(self.L.get("settlement_layer", False))}
        for st in self.L["settlements"]:
            x, y = st["center_km"]
            fx, fy = x / self.pitch_km, (self.size_km - y) / self.pitch_km
            sites["settlements"].append({"name": st["name"], "kind": st["kind"], "radius_m": st["radius_km"] * 1000,
                                         "pos": [x * 1000 - 10000, float(bilinear(self.h, np.array([fx]), np.array([fy]))[0]), 10000 - y * 1000]})
        for pl in self.L["plateaus"]:
            x, y = pl["center_km"]
            fx, fy = x / self.pitch_km, (self.size_km - y) / self.pitch_km
            sites["plateaus"].append({"name": pl["name"], "radii_m": [r * 1000 for r in pl["radii_km"]], "rot_deg": pl["rot_deg"],
                                      "pos": [x * 1000 - 10000, float(bilinear(self.h, np.array([fx]), np.array([fy]))[0]), 10000 - y * 1000]})
        # Junctions: waypoints shared by two or more paved (mesh) roads, including
        # crossings where both roads continue (4-way).
        cnt = {}
        for rd in self.L["roads"]:
            if not self.L["road_classes"][rd["class"]]["mesh"]:
                continue
            for w in rd["waypoints_km"]:
                key = (round(w[0], 4), round(w[1], 4))
                cnt[key] = cnt.get(key, 0) + 1
        junctions = []
        for (kx, ky), n in cnt.items():
            if n >= 2:
                x, y = self.road_moved.get((kx, ky), (kx, ky))
                fx, fy = x / self.pitch_km, (self.size_km - y) / self.pitch_km
                hj = self.road_fixed.get((kx, ky))
                if hj is None:
                    hj = float(bilinear(self.h, np.array([fx]), np.array([fy]))[0])
                junctions.append([x * 1000 - 10000, float(hj), 10000 - y * 1000])
        with open(os.path.join(self.out, "roads.json"), "w", encoding="utf-8") as fp:
            json.dump({"roads": roads, "junctions": junctions}, fp)
        with open(os.path.join(self.out, "sites.json"), "w", encoding="utf-8") as fp:
            json.dump(sites, fp, ensure_ascii=False, indent=1)
        self.stats["roads_km"] = {c: round(sum(r["length_m"] for r in self.roads if r["class"] == c) / 1000.0, 2)
                                  for c in self.L["road_classes"]}
        self.stats["bridges"] = sum(len(r["bridges"]) for r in self.roads)
        self.stats["culverts"] = sum(len(r["culverts"]) for r in self.roads)
        self.stats["lakes"] = [{"name": i["name"], "level_m": round(i["level"], 1)} for i in self.lake_info]
        self.stats["lake_area_km2"] = round(float(self.lake_mask.sum()) * self.pitch_km ** 2, 3)
        self.stats["forest_share"] = round(float((self.forest_dens > 0.4).mean()), 4)
        self.stats["field_share"] = round(float(self.field.mean()), 4)
        self.write_godot_config()
        with open(os.path.join(self.out, "generation_stats.json"), "w", encoding="utf-8") as fp:
            json.dump(self.stats, fp, indent=1)

    def write_godot_config(self):
        """worlds/<name>/world_config.tres for the Godot pipeline (ReferenceWorldConfig).
        main_road is a sample of the first primary road (used by benchmarks/diagnostics to
        find a road); base_sites are only the CORE demo spawn points (natural plateaus),
        nothing is built there."""
        name = self.L["name"]
        hs = self.L["size_m"] * 0.5
        prim = next(r for r in self.roads if r["class"] == "primary")
        P = prim["path_km"]
        idx = np.linspace(0, len(P) - 1, 9).astype(int)
        mr = ", ".join("%.4f, %.4f" % ((P[i, 0] * 1000 - hs) / hs, (hs - P[i, 1] * 1000) / hs) for i in idx)
        demo = []
        for nm in self.L.get("demo_spawn_plateaus", []):
            pl = next(p for p in self.L["plateaus"] if p["name"] == nm)
            x, y = pl["center_km"]
            demo.append("%.4f, %.4f, 80" % ((x * 1000 - hs) / hs, (hs - y * 1000) / hs))
        txt = """[gd_resource type="Resource" script_class="ReferenceWorldConfig" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/world/reference_world_config.gd" id="1_cfg"]

[resource]
script = ExtResource("1_cfg")
world_name = "%s"
world_size_m = %.1f
vertex_spacing = %.6f
region_size = 1024
world_seed = %d
base_height = 150.0
base_sites = PackedVector3Array(%s)
main_road = PackedVector2Array(%s)
branch_roads = Array[PackedVector2Array]([])
tree_spacing_m = 6.5
bush_spacing_m = 9.0
rock_spacing_m = 20.0
road_clearance_m = 5.0
max_tree_slope_deg = 38.0
source_directory = "res://worlds/%s/source"
""" % (name, self.L["size_m"], self.L["size_m"] / self.full, self.seed, ", ".join(demo), mr, name)
        path = os.path.join(os.path.dirname(os.path.abspath(self.out)), "world_config.tres")
        with open(path, "w", encoding="utf-8", newline="") as fp:
            fp.write(txt)

    def save_macro(self):
        np.save(os.path.join(self.out, "macro_height.npy"), self.h)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--layout", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--macro-only", action="store_true")
    a = ap.parse_args()
    with open(a.layout, encoding="utf-8") as fp:
        layout = json.load(fp)
    g = Generator(layout, a.out)
    g.build_macro()
    g.flatten_sites()
    g.build_lakes()
    g.drainage()
    if "cover_v2" in layout:
        g.build_cover_v2()
    else:
        g.build_cover()
    g.route_roads()
    g.write_macro_outputs()
    g.preview()
    g.save_macro()
    if not a.macro_only:
        g.build_full()
    g.write_json()
    log("done")


if __name__ == "__main__":
    main()
