"""Procedural textures for the WORLD-TERRAIN-01 environment assets (numpy + OpenImageIO).

Foliage cards (RGBA, alpha-tested): pine tuft, spruce spray, birch leaf twig, juniper,
willow shrub, fern frond. Bark (RGB, V runs up the stem): pine (grey plates -> orange
flakes), spruce (grey-brown scales), birch (white with black lenticels, dark base).
Wood end grain for stumps and logs. Each colour texture gets a matching normal map.

Run with Blender's Python (or any Python with numpy + OpenImageIO):
  python tools/blender/env/make_env_textures.py assets/environment/textures
"""
import math
import os
import sys

import numpy as np
import OpenImageIO as oiio

RNG = np.random.Generator(np.random.PCG64(2026))


def save(path, arr):
    arr = np.clip(arr, 0.0, 1.0)
    if arr.ndim == 2:
        arr = arr[..., None]
    h, w, c = arr.shape
    out = oiio.ImageOutput.create(path)
    spec = oiio.ImageSpec(w, h, c, oiio.UINT8)
    # Straight (unassociated) alpha: otherwise OIIO divides RGB by alpha when writing PNG (bright card fringes; VISUAL-02).
    spec.attribute("oiio:UnassociatedAlpha", 1)
    out.open(path, spec)
    out.write_image(np.ascontiguousarray((arr * 255 + 0.5).astype(np.uint8)))
    out.close()
    print("wrote", path)


def downsample(a, f):
    h, w = a.shape[:2]
    return a.reshape(h // f, f, w // f, f, *a.shape[2:]).mean(axis=(1, 3))


def normal_from_height(h, strength, wrap=True):
    if wrap:
        dx = np.roll(h, -1, 1) - np.roll(h, 1, 1)
        dy = np.roll(h, -1, 0) - np.roll(h, 1, 0)
    else:
        dy, dx = np.gradient(h)
        dx, dy = dx * 2, dy * 2
    nx = -dx * strength
    ny = dy * strength  # OpenGL / glTF (+Y up in texture space)
    nz = np.ones_like(nx)
    n = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / n * 0.5 + 0.5, ny / n * 0.5 + 0.5, nz / n * 0.5 + 0.5], axis=-1)


def value_noise(shape, cells, seed, octaves=4, wrap=True):
    """Tileable smooth value noise in [0,1]."""
    rng = np.random.Generator(np.random.PCG64(seed))
    h, w = shape
    total = np.zeros(shape)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        cy, cx = cells[0] * 2 ** o, cells[1] * 2 ** o
        g = rng.random((cy, cx))
        y = np.linspace(0, cy, h, endpoint=False)
        x = np.linspace(0, cx, w, endpoint=False)
        yi = np.floor(y).astype(int)
        xi = np.floor(x).astype(int)
        ty = (y - yi)[:, None]
        tx = (x - xi)[None, :]
        ty = ty * ty * (3 - 2 * ty)
        tx = tx * tx * (3 - 2 * tx)
        y1 = (yi + 1) % cy
        x1 = (xi + 1) % cx
        a = g[yi][:, xi]
        b = g[yi][:, x1]
        c = g[y1][:, xi]
        d = g[y1][:, x1]
        total += amp * ((a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty)
        norm += amp
        amp *= 0.5
    return total / norm


# ------------------------------------------------------------------ rasterizer
class Canvas:
    """RGBA canvas with anti-aliased thick lines and ellipses (supersampled)."""

    def __init__(self, size, ss=2):
        self.n = size * ss
        self.ss = ss
        self.rgb = np.zeros((self.n, self.n, 3))
        self.a = np.zeros((self.n, self.n))
        self.h = np.zeros((self.n, self.n))

    def line(self, p0, p1, w0, w1, col, height=1.0, shade=0.0):
        """p in 0..1 canvas coords (x right, y down)."""
        n = self.n
        x0, y0 = p0[0] * n, p0[1] * n
        x1, y1 = p1[0] * n, p1[1] * n
        r = max(w0, w1) * n * 0.5 + 2
        xa, xb = int(max(0, min(x0, x1) - r)), int(min(n, max(x0, x1) + r + 1))
        ya, yb = int(max(0, min(y0, y1) - r)), int(min(n, max(y0, y1) + r + 1))
        if xb <= xa or yb <= ya:
            return
        yy, xx = np.mgrid[ya:yb, xa:xb] + 0.5
        dx, dy = x1 - x0, y1 - y0
        l2 = dx * dx + dy * dy + 1e-9
        t = np.clip(((xx - x0) * dx + (yy - y0) * dy) / l2, 0, 1)
        d = np.hypot(xx - (x0 + t * dx), yy - (y0 + t * dy))
        hw = (w0 + (w1 - w0) * t) * n * 0.5
        cov = np.clip(hw - d + 0.5, 0, 1)
        # Cylinder-ish shading across the stroke.
        across = np.clip(d / np.maximum(hw, 0.5), 0, 1)
        lit = 1.0 - shade * across * across
        sub = self.a[ya:yb, xa:xb]
        m = cov > sub * 0.999
        c = np.array(col)[None, None, :] * lit[..., None]
        self.rgb[ya:yb, xa:xb][m] = c[m]
        self.h[ya:yb, xa:xb][m] = (height * (1 - across * across))[m]
        self.a[ya:yb, xa:xb] = np.maximum(sub, cov)

    def leaf(self, c, length, width, ang, col, serr=0.0, vein=0.75):
        """Ovate leaf with midrib, centred at c, pointing along ang (radians)."""
        n = self.n
        cx, cy = c[0] * n, c[1] * n
        L = length * n
        W = width * n
        r = L * 0.6 + 2
        xa, xb = int(max(0, cx - r)), int(min(n, cx + r + 1))
        ya, yb = int(max(0, cy - r)), int(min(n, cy + r + 1))
        if xb <= xa or yb <= ya:
            return
        yy, xx = np.mgrid[ya:yb, xa:xb] + 0.5
        u = ((xx - cx) * math.cos(ang) + (yy - cy) * math.sin(ang)) / (L * 0.5)
        v = (-(xx - cx) * math.sin(ang) + (yy - cy) * math.cos(ang)) / (W * 0.5)
        # Egg shape: wider near the base (u<0), pointed tip.
        prof = np.sqrt(np.clip(1 - u * u, 0, 1)) * (1.0 - 0.35 * u)
        if serr > 0:
            prof *= 1.0 - serr * (0.5 + 0.5 * np.sin(u * 40.0))
        inside = np.abs(v) < prof
        edge = np.clip((prof - np.abs(v)) * W * 0.5, 0, 1)
        cov = np.where(inside, edge, 0.0)
        shade = 0.85 + 0.25 * (1 - np.abs(v)) - 0.12 * (np.abs(v) < 0.07) * vein
        sub = self.a[ya:yb, xa:xb]
        m = cov > 0.01
        cc = np.array(col)[None, None, :] * shade[..., None]
        self.rgb[ya:yb, xa:xb][m] = cc[m]
        self.h[ya:yb, xa:xb][m] = (0.6 + 0.4 * (1 - np.abs(v)))[m]
        self.a[ya:yb, xa:xb] = np.maximum(sub, cov)

    def result(self, dilate_rgb=True):
        rgb = downsample(self.rgb, self.ss)
        a = downsample(self.a, self.ss)
        h = downsample(self.h, self.ss)
        # Premultiplied downsample -> straight colour; bleed colour into transparent
        # texels so mipmaps do not darken the cut-out edges.
        prgb = downsample(self.rgb * self.a[..., None], self.ss)
        rgb = np.where(a[..., None] > 0.01, prgb / np.maximum(a[..., None], 1e-4), rgb)
        if dilate_rgb:
            for _ in range(8):
                m = a < 0.05
                acc = np.zeros_like(rgb)
                cnt = np.zeros(a.shape)
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        sh = np.roll(np.roll(rgb, dy, 0), dx, 1)
                        sa = np.roll(np.roll(a, dy, 0), dx, 1) >= 0.05
                        acc += sh * sa[..., None]
                        cnt += sa
                fill = m & (cnt > 0)
                rgb[fill] = acc[fill] / cnt[fill][:, None]
                a2 = a.copy()
                a2[fill] = 0.05
                a = np.where(fill, 0.05, a)
            a = np.where(a <= 0.05, 0.0, a)
        return rgb, a, h


def jitter_col(base, amt):
    return np.clip(np.array(base) * (1 + (RNG.random(3) - 0.5) * amt), 0, 1)


# ------------------------------------------------------------------ foliage cards
def pine_tuft(out):
    """Scots pine branch end: a few twigs ending in dense brush-like needle tufts.
    Card is drawn with the branch base at the bottom centre, tips toward the top."""
    cv = Canvas(512)
    twig = (0.33, 0.22, 0.13)
    needle = (0.17, 0.25, 0.12)
    tips = []
    base = (0.5, 0.98)
    for k in range(5):
        a = math.radians(-90 + (k - 2) * 24 + RNG.normal(0, 6))
        ln = 0.42 + RNG.random() * 0.25
        tip = (base[0] + math.cos(a) * ln * 0.9, base[1] + math.sin(a) * ln)
        cv.line(base, tip, 0.022, 0.012, twig, shade=0.5)
        tips.append((tip, a))
        # Secondary tuft half way.
        if RNG.random() < 0.7:
            t = 0.45 + RNG.random() * 0.2
            mid = (base[0] + (tip[0] - base[0]) * t, base[1] + (tip[1] - base[1]) * t)
            a2 = a + RNG.choice([-1, 1]) * math.radians(35 + RNG.random() * 20)
            tip2 = (mid[0] + math.cos(a2) * 0.18, mid[1] + math.sin(a2) * 0.18)
            cv.line(mid, tip2, 0.012, 0.008, twig, shade=0.5)
            tips.append((tip2, a2))
    for (tip, a) in tips:
        # Needle brush along the last part of each twig: paired needles, 4-7 cm,
        # pointing forward along the shoot.
        for j in range(140):
            t = RNG.random() ** 0.6
            back = 0.22 * t
            px = tip[0] - math.cos(a) * back
            py = tip[1] - math.sin(a) * back
            na = a + RNG.normal(0, 0.75)
            nl = 0.06 + RNG.random() * 0.05
            col = jitter_col(needle, 0.35) * (0.75 + 0.35 * (1 - t))
            cv.line((px, py), (px + math.cos(na) * nl, py + math.sin(na) * nl), 0.0045, 0.002, col, height=0.8)
    rgb, a, h = cv.result()
    save(os.path.join(out, "pine_tuft_alb.png"), np.concatenate([rgb, a[..., None]], -1))
    save(os.path.join(out, "pine_tuft_nrm.png"), normal_from_height(h, 2.0, wrap=False))


def spruce_spray(out):
    """Norway spruce branch spray seen from above: central axis with alternating side
    shoots, short dense needles; base at the bottom, tip at the top."""
    cv = Canvas(512)
    twig = (0.30, 0.21, 0.14)
    needle = (0.11, 0.21, 0.10)
    axis = [(0.5, 0.98)]
    for i in range(1, 9):
        x = 0.5 + RNG.normal(0, 0.012)
        axis.append((x, 0.98 - i * 0.115))
    for i in range(len(axis) - 1):
        cv.line(axis[i], axis[i + 1], 0.02 - i * 0.0015, 0.018 - i * 0.0015, twig, shade=0.5)
    shoots = []
    for i in range(1, len(axis) - 1):
        for side in (-1, 1):
            ln = (0.36 - i * 0.03) * (0.8 + 0.4 * RNG.random())
            a = math.radians(-90 + side * (55 + RNG.normal(0, 8)))
            p0 = axis[i]
            p1 = (p0[0] + math.cos(a) * ln, p0[1] + math.sin(a) * ln)
            cv.line(p0, p1, 0.012, 0.006, twig, shade=0.5)
            shoots.append((p0, p1, a))
            # Tertiary shoots.
            for k in range(2):
                t = 0.35 + 0.3 * k
                q0 = (p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t)
                b = a + side * math.radians(-40) * (1 if k else -1) * -1
                q1 = (q0[0] + math.cos(b) * ln * 0.35, q0[1] + math.sin(b) * ln * 0.35)
                cv.line(q0, q1, 0.007, 0.004, twig, shade=0.4)
                shoots.append((q0, q1, b))
    shoots.append((axis[0], axis[-1], -math.pi / 2))
    for (p0, p1, a) in shoots:
        L = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        cnt = int(L * 420)
        for j in range(cnt):
            t = RNG.random()
            px = p0[0] + (p1[0] - p0[0]) * t
            py = p0[1] + (p1[1] - p0[1]) * t
            side = RNG.choice([-1, 1])
            na = a + side * math.radians(50 + RNG.normal(0, 15))
            nl = 0.028 + RNG.random() * 0.018
            col = jitter_col(needle, 0.4) * (0.8 + 0.5 * t)
            cv.line((px, py), (px + math.cos(na) * nl, py + math.sin(na) * nl), 0.005, 0.0025, col, height=0.8)
    rgb, a, h = cv.result()
    save(os.path.join(out, "spruce_spray_alb.png"), np.concatenate([rgb, a[..., None]], -1))
    save(os.path.join(out, "spruce_spray_nrm.png"), normal_from_height(h, 2.0, wrap=False))


def birch_twig(out):
    """Birch twig cluster with small triangular-ovate serrated leaves on drooping shoots."""
    cv = Canvas(512)
    twig = (0.28, 0.18, 0.13)
    leaf = (0.27, 0.40, 0.12)
    base = (0.5, 0.02)  # birch twigs hang: base at the top
    shoots = []
    for k in range(6):
        a = math.radians(90 + (k - 2.5) * 22 + RNG.normal(0, 6))
        pts = [base]
        ang = a
        for s in range(6):
            ang += RNG.normal(0, 0.12) + 0.02 * (math.pi / 2 - ang)
            last = pts[-1]
            pts.append((last[0] + math.cos(ang) * 0.13, last[1] + math.sin(ang) * 0.13))
        for i in range(len(pts) - 1):
            cv.line(pts[i], pts[i + 1], 0.009 - i * 0.001, 0.008 - i * 0.001, twig, shade=0.4)
        shoots.append(pts)
    for pts in shoots:
        for i in range(1, len(pts)):
            for k in range(6):
                t = RNG.random()
                px = pts[i - 1][0] + (pts[i][0] - pts[i - 1][0]) * t
                py = pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * t
                ang = math.atan2(pts[i][1] - pts[i - 1][1], pts[i][0] - pts[i - 1][0]) + RNG.choice([-1, 1]) * (0.7 + RNG.random() * 0.6)
                ln = 0.05 + RNG.random() * 0.025
                c = (px + math.cos(ang) * ln * 0.55, py + math.sin(ang) * ln * 0.55)
                col = jitter_col(leaf, 0.35)
                cv.leaf(c, ln, ln * 0.72, ang, col, serr=0.06)
    rgb, a, h = cv.result()
    save(os.path.join(out, "birch_twig_alb.png"), np.concatenate([rgb, a[..., None]], -1))
    save(os.path.join(out, "birch_twig_nrm.png"), normal_from_height(h, 1.5, wrap=False))


def grass_tuft(out):
    """Meadow grass tuft for the camera-local particle grass: fanning blades of mixed
    green/olive with a few dry stems and seed heads; base at the bottom centre."""
    cv = Canvas(256)
    greens = [(0.30, 0.42, 0.14), (0.36, 0.46, 0.16), (0.42, 0.46, 0.18), (0.48, 0.47, 0.24)]
    for k in range(70):
        x0 = 0.5 + RNG.normal(0, 0.08)
        a = math.radians(-90 + RNG.normal(0, 22))
        ln = 0.55 + RNG.random() * 0.42
        bend = RNG.normal(0, 0.25)
        pts = [(x0, 0.995)]
        ang = a
        for s in range(5):
            ang += bend * 0.25
            pts.append((pts[-1][0] + math.cos(ang) * ln / 5, pts[-1][1] + math.sin(ang) * ln / 5))
        col = jitter_col(greens[RNG.integers(len(greens))], 0.25)
        dry = RNG.random() < 0.12
        if dry:
            col = jitter_col((0.62, 0.56, 0.36), 0.2)
        for i in range(len(pts) - 1):
            w0 = 0.022 * (1 - i / 5) + 0.003
            w1 = 0.022 * (1 - (i + 1) / 5) + 0.002
            cv.line(pts[i], pts[i + 1], w0, w1, np.array(col) * (0.7 + 0.3 * i / 5), height=0.5 + 0.1 * i, shade=0.3)
        if dry and RNG.random() < 0.6:
            tip = pts[-1]
            for j in range(10):
                cv.leaf((tip[0] + RNG.normal(0, 0.012), tip[1] + RNG.normal(0, 0.03)), 0.03, 0.012,
                        math.radians(-90 + RNG.normal(0, 30)), jitter_col((0.58, 0.50, 0.32), 0.2))
    rgb, a, h = cv.result()
    save(os.path.join(out, "grass_tuft_alb.png"), np.concatenate([rgb, a[..., None]], -1))


def dwarf_shrub_tuft(out):
    """Boreal forest-floor cover (blueberry/lingonberry): short woody stems with many small
    oval leaves, dark green with a few reddish leaves; base at the bottom centre."""
    rnd = np.random.Generator(np.random.PCG64(77))
    cv = Canvas(256)
    for k in range(16):
        x0 = 0.5 + rnd.normal(0, 0.12)
        a = math.radians(-90 + rnd.normal(0, 28))
        ln = 0.45 + rnd.random() * 0.4
        p0 = (x0, 0.995)
        p1 = (x0 + math.cos(a) * ln, 0.995 + math.sin(a) * ln)
        cv.line(p0, p1, 0.012, 0.006, (0.30, 0.28, 0.16), shade=0.3)
        for j in range(16):
            t = 0.25 + 0.75 * rnd.random()
            px = p0[0] + (p1[0] - p0[0]) * t
            py = p0[1] + (p1[1] - p0[1]) * t
            ang = a + rnd.choice([-1, 1]) * (0.6 + rnd.random() * 0.8)
            ln2 = 0.055 + rnd.random() * 0.03
            base = (0.20, 0.32, 0.12) if rnd.random() > 0.08 else (0.45, 0.20, 0.12)
            col = np.clip(np.array(base) * (1 + (rnd.random(3) - 0.5) * 0.4), 0, 1)
            cv.leaf((px + math.cos(ang) * ln2 * 0.5, py + math.sin(ang) * ln2 * 0.5), ln2, ln2 * 0.6, ang, col)
    rgb, a, h = cv.result()
    save(os.path.join(out, "dwarf_shrub_alb.png"), np.concatenate([rgb, a[..., None]], -1))


def juniper_spray(out):
    cv = Canvas(256)
    twig = (0.30, 0.22, 0.15)
    needle = (0.24, 0.32, 0.22)
    for k in range(9):
        a = math.radians(-90 + (k - 4) * 14 + RNG.normal(0, 5))
        p0 = (0.5 + RNG.normal(0, 0.04), 0.99)
        p1 = (p0[0] + math.cos(a) * 0.9, p0[1] + math.sin(a) * 0.9)
        cv.line(p0, p1, 0.015, 0.006, twig, shade=0.4)
        for j in range(700):
            t = RNG.random() ** 0.8
            px = p0[0] + (p1[0] - p0[0]) * t
            py = p0[1] + (p1[1] - p0[1]) * t
            na = a + RNG.normal(0, 0.9)
            nl = 0.035 + RNG.random() * 0.03
            cv.line((px, py), (px + math.cos(na) * nl, py + math.sin(na) * nl), 0.01, 0.004,
                    jitter_col(needle, 0.4) * (0.75 + 0.4 * t), height=0.8)
    rgb, a, h = cv.result()
    save(os.path.join(out, "juniper_alb.png"), np.concatenate([rgb, a[..., None]], -1))
    save(os.path.join(out, "juniper_nrm.png"), normal_from_height(h, 2.0, wrap=False))


def willow_twig(out):
    cv = Canvas(256)
    twig = (0.32, 0.24, 0.16)
    leaf = (0.30, 0.40, 0.17)
    for k in range(7):
        a = math.radians(-90 + (k - 3) * 15 + RNG.normal(0, 5))
        p0 = (0.5, 0.99)
        p1 = (p0[0] + math.cos(a) * 0.95, p0[1] + math.sin(a) * 0.95)
        cv.line(p0, p1, 0.014, 0.006, twig, shade=0.4)
        for j in range(14):
            t = 0.15 + 0.85 * RNG.random()
            px = p0[0] + (p1[0] - p0[0]) * t
            py = p0[1] + (p1[1] - p0[1]) * t
            ang = a + RNG.choice([-1, 1]) * (0.5 + RNG.random() * 0.4)
            ln = 0.12 + RNG.random() * 0.05
            c = (px + math.cos(ang) * ln * 0.5, py + math.sin(ang) * ln * 0.5)
            cv.leaf(c, ln, ln * 0.35, ang, jitter_col(leaf, 0.35))
    rgb, a, h = cv.result()
    save(os.path.join(out, "willow_alb.png"), np.concatenate([rgb, a[..., None]], -1))
    save(os.path.join(out, "willow_nrm.png"), normal_from_height(h, 1.5, wrap=False))


def fern_frond(out):
    """Bracken/lady-fern frond: rachis with lance-shaped pinnae, longest in the middle."""
    cv = Canvas(256)
    stem = (0.32, 0.36, 0.15)
    leaf = (0.27, 0.42, 0.13)
    p0 = (0.5, 0.99)
    p1 = (0.5, 0.03)
    cv.line(p0, p1, 0.012, 0.004, stem, shade=0.3)
    for i in range(18):
        t = 0.1 + i * 0.05
        y = p0[1] + (p1[1] - p0[1]) * t
        ln = 0.46 * math.sin(math.pi * min(1.0, t * 1.02)) ** 0.8 * (1 - 0.25 * t)
        for side in (-1, 1):
            ang = math.radians(-90 + side * (68 - 20 * t))
            c = (0.5 + math.cos(ang) * ln * 0.5, y + math.sin(ang) * ln * 0.5)
            col = jitter_col(leaf, 0.2) * (0.85 + 0.25 * t)
            cv.leaf(c, ln, ln * 0.17, ang, col, serr=0.3, vein=1.0)
    rgb, a, h = cv.result()
    save(os.path.join(out, "fern_alb.png"), np.concatenate([rgb, a[..., None]], -1))
    save(os.path.join(out, "fern_nrm.png"), normal_from_height(h, 1.5, wrap=False))


# ------------------------------------------------------------------ bark / wood
def bark_pine(out):
    """Two tiling 512^2 textures (U around the stem, V up the stem):
    bark_pine_lower: thick grey-brown plates separated by deep vertical fissures;
    bark_pine_upper: thin, papery orange-red flaking bark (upper stem and branches)."""
    W = H = 512
    v1 = value_noise((H, W), (4, 4), 1, 4)
    v2 = value_noise((H, W), (32, 12), 2, 3)
    warp = value_noise((H, W), (3, 4), 5, 2)
    xs = (np.arange(W)[None, :] / W + 0.08 * (warp - 0.5)) % 1.0
    cx = xs * 7
    fiss_v = np.abs((cx % 1.0) - 0.5) * 2
    fiss_v = fiss_v + 0.25 * (value_noise((H, W), (10, 7), 6, 2) - 0.5)
    hb = np.abs(value_noise((H, W), (6, 14), 7, 1) - 0.5) * 2
    plate = np.clip(np.minimum(fiss_v * 1.8, hb * 9.0), 0, 1)
    grey = np.array([0.47, 0.41, 0.35]) * (0.75 + 0.45 * v1[..., None])
    col = grey * (1 - 0.6 * (1 - plate)[..., None]) * (0.9 + 0.15 * plate[..., None])
    save(os.path.join(out, "bark_pine_lower_alb.png"), col)
    save(os.path.join(out, "bark_pine_lower_nrm.png"), normal_from_height(plate * 0.9 + 0.1 * v2, 6.0))
    flake = value_noise((H, W), (40, 10), 4, 2)
    orange = np.array([0.60, 0.36, 0.22]) * (0.78 + 0.35 * v2[..., None])
    orange = orange * (0.9 + 0.2 * (flake[..., None] > 0.55))
    curl = np.clip((value_noise((H, W), (24, 8), 8, 2) - 0.62) * 6, 0, 1)
    orange = orange * (1 - 0.25 * curl[..., None])
    save(os.path.join(out, "bark_pine_upper_alb.png"), orange)
    save(os.path.join(out, "bark_pine_upper_nrm.png"), normal_from_height(0.5 + 0.3 * flake + 0.3 * curl, 3.0))


def bark_spruce(out):
    W, H = 512, 512
    v1 = value_noise((H, W), (8, 8), 11, 4)
    sc = value_noise((H, W), (90, 60), 12, 2)
    scales = np.clip((sc - 0.45) * 4, 0, 1)
    col = np.array([0.33, 0.27, 0.22]) * (0.75 + 0.4 * v1[..., None])
    col = col * (0.8 + 0.3 * scales[..., None])
    lichen = np.clip((value_noise((H, W), (16, 12), 13, 4) - 0.66) * 4, 0, 1)
    col = col + (np.array([0.50, 0.52, 0.44]) - col) * (lichen * 0.35)[..., None]
    hgt = 0.6 * scales + 0.4 * v1
    save(os.path.join(out, "bark_spruce_alb.png"), col)
    save(os.path.join(out, "bark_spruce_nrm.png"), normal_from_height(hgt, 4.0))


def bark_birch(out):
    """bark_birch: tiling white bark with black horizontal lenticels and blotches;
    bark_birch_base: dark, deeply fissured base of old birches."""
    W = H = 512
    v1 = value_noise((H, W), (8, 8), 21, 4)
    col = np.ones((H, W, 3)) * np.array([0.86, 0.85, 0.80]) * (0.9 + 0.12 * v1[..., None])
    yy, xx = np.mgrid[0:H, 0:W]
    lent = np.zeros((H, W))
    for _ in range(260):
        cy = RNG.random() * H
        cx = RNG.random() * W
        ln = 12 + RNG.random() * 50
        th = 1.0 + RNG.random() * 2.5
        dy = np.abs(((yy - cy + H / 2) % H) - H / 2)
        dx = np.abs(((xx - cx + W / 2) % W) - W / 2)
        d = dy / th + np.clip(dx - ln / 2, 0, None) / 2.0
        lent = np.maximum(lent, np.clip(1.2 - d, 0, 1))
    blotch = np.clip((value_noise((H, W), (5, 4), 22, 4) - 0.62) * 4, 0, 1)
    dark = np.clip(lent * 0.9 + blotch * 0.7, 0, 1)
    col = col * (1 - dark[..., None] * 0.85)
    save(os.path.join(out, "bark_birch_alb.png"), col)
    save(os.path.join(out, "bark_birch_nrm.png"), normal_from_height(0.7 - 0.5 * lent, 3.0))
    v3 = value_noise((H, W), (20, 6), 23, 3)
    fiss = np.abs(value_noise((H, W), (6, 9), 24, 2) - 0.5) * 2
    plate = np.clip(fiss * 3, 0, 1)
    basec = np.array([0.22, 0.20, 0.18]) * (0.7 + 0.5 * v3[..., None]) * (0.6 + 0.4 * plate[..., None])
    white = np.clip((value_noise((H, W), (8, 8), 25, 3) - 0.6) * 3, 0, 1)
    basec = basec + (np.array([0.7, 0.68, 0.62]) - basec) * (white * 0.5)[..., None]
    save(os.path.join(out, "bark_birch_base_alb.png"), basec)
    save(os.path.join(out, "bark_birch_base_nrm.png"), normal_from_height(plate * 0.8 + 0.2 * v3, 6.0))


def wood_end(out):
    N = 256
    yy, xx = np.mgrid[0:N, 0:N] / N - 0.5
    r = np.hypot(xx, yy)
    wob = value_noise((N, N), (6, 6), 31, 3)
    rings = 0.5 + 0.5 * np.sin((r + 0.03 * wob) * 2 * math.pi * 26)
    col = np.array([0.62, 0.47, 0.30]) * (0.82 + 0.18 * rings[..., None])
    bark = np.clip((r - 0.44) / 0.04, 0, 1)
    col = col * (1 - bark[..., None]) + np.array([0.25, 0.19, 0.14]) * bark[..., None]
    grey = value_noise((N, N), (5, 5), 32, 3)
    col = col * (0.75 + 0.25 * grey[..., None]) * np.array([0.95, 0.95, 1.0])
    save(os.path.join(out, "wood_end_alb.png"), col)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "assets/environment/textures"
    os.makedirs(out, exist_ok=True)
    for f in (grass_tuft, dwarf_shrub_tuft, pine_tuft, spruce_spray, birch_twig, juniper_spray, willow_twig, fern_frond,
              bark_pine, bark_spruce, bark_birch, wood_end):
        f(out)


if __name__ == "__main__":
    main()
