"""Procedural, tileable textures for the infantry set (numpy -> PNG, deterministic).

All tile with world-scale box UVs (char_lib.box_uv): a texture covers TILE_M metres.
Greyscale textures (webbing, polymer) are tinted by the material colour so one image
serves several materials (ranger green / coyote / black webbing).
"""
import math
import os

import numpy as np

import char_lib as L

TILE_FABRIC_M = 0.60     # camo + ripstop tile
TILE_WEBBING_M = 0.30    # cordura / PALS tile
TILE_HARD_M = 0.25       # polymer / metal noise


def _disc_field(n, centers, radii):
    """Union of discs on a torus (tileable), returns mask in [0,1] with 1 px soft edge."""
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    m = np.zeros((n, n), np.float32)
    for (cx, cy), r in zip(centers, radii):
        x0, x1 = int(cx - r - 2), int(cx + r + 3)
        y0, y1 = int(cy - r - 2), int(cy + r + 3)
        xs = np.arange(x0, x1) % n
        ys = np.arange(y0, y1) % n
        dx = (np.arange(x0, x1) - cx)[None, :]
        dy = (np.arange(y0, y1) - cy)[:, None]
        d = np.sqrt(dx * dx + dy * dy)
        v = np.clip(r + 0.5 - d, 0, 1)
        m[np.ix_(ys, xs)] = np.maximum(m[np.ix_(ys, xs)], v)
    return m


def camo_nordic(path, palette, n=1024, seed=11):
    """Original Nordic woodland camo in the spirit of the Norwegian M23 (NCU) pattern:
    a mid-green field, large khaki patches, dark-green clusters built from small round
    'dots' with dotted edges, and sparse near-black dot groups. palette = dict of
    sRGB triples: field, light, dark, black."""
    rng = np.random.default_rng(seed)
    px_per_m = n / TILE_FABRIC_M
    rgb = np.zeros((n, n, 3)) + np.array(palette["field"])
    # Large light (khaki) patches with slightly irregular edges.
    big = L.fbm(n, 150, 4, seed, gain=0.5)
    light = np.clip((big - 0.57) * 24, 0, 1)
    rgb = rgb * (1 - light[..., None]) + np.array(palette["light"]) * light[..., None]
    # Dark-green clusters: dots placed where a medium noise is high, so edges break up.
    med = L.fbm(n, 85, 3, seed + 3, gain=0.45)
    pts, rad = [], []
    count = int(n * n / 260)
    xy = rng.uniform(0, n, (count, 2))
    for x, y in xy:
        v = med[int(y) % n, int(x) % n]
        if v > 0.53 + rng.uniform(-0.06, 0.06):
            pts.append((x, y))
            rad.append(rng.uniform(0.0055, 0.0105) * px_per_m)
    dark = _disc_field(n, pts, rad)
    core = np.clip((med - 0.62) * 22, 0, 1)
    dark = np.maximum(dark, core)
    rgb = rgb * (1 - dark[..., None]) + np.array(palette["dark"]) * dark[..., None]
    # Near-black dot groups, smaller and sparser.
    blk = L.fbm(n, 55, 2, seed + 7)
    pts, rad = [], []
    xy = rng.uniform(0, n, (int(n * n / 700), 2))
    for x, y in xy:
        if blk[int(y) % n, int(x) % n] > 0.64:
            pts.append((x, y))
            rad.append(rng.uniform(0.0035, 0.006) * px_per_m)
    black = _disc_field(n, pts, rad)
    rgb = rgb * (1 - black[..., None]) + np.array(palette["black"]) * black[..., None]
    # Print/fabric irregularity and slight fading.
    grain = L.fbm(n, 6, 2, seed + 21)
    rgb *= (0.93 + 0.10 * grain)[..., None]
    rgb = rgb * 0.94 + 0.06 * rgb.mean(axis=2, keepdims=True)
    return L.save_png(path, np.clip(rgb, 0, 1))


PALETTE_M23 = {"field": (0.37, 0.43, 0.25), "light": (0.57, 0.52, 0.37), "dark": (0.19, 0.25, 0.16), "black": (0.10, 0.12, 0.09)}
# Second faction (South): arid / dry-terrain colouring of the same pattern family.
PALETTE_ARID = {"field": (0.62, 0.55, 0.40), "light": (0.76, 0.69, 0.54), "dark": (0.42, 0.35, 0.24), "black": (0.30, 0.31, 0.22)}


def ripstop_normal(path, n=512, seed=5):
    """Ripstop grid (5 mm squares) + weave noise + soft creases, as a tangent normal map."""
    px_per_m = n / TILE_FABRIC_M
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    period = max(2, round(0.005 * px_per_m * 1.0))
    period = n / round(n / period)
    gx = np.exp(-((((xx % period) - period / 2) / 0.7) ** 2))
    gy = np.exp(-((((yy % period) - period / 2) / 0.7) ** 2))
    weave = (np.sin(xx * math.pi) * np.sin(yy * math.pi)) * 0.2
    crease = L.fbm(n, 60, 3, seed, gain=0.6)
    h = 0.6 * np.maximum(gx, gy) + 0.15 * weave + 6.0 * crease
    nm = L.normal_from_height(h, 1.6)
    rough = 0.80 + 0.12 * L.fbm(n, 20, 2, seed + 3)
    L.save_png(path, nm)
    return rough


def cordura(path_albedo, path_normal, n=512, seed=8):
    """Greyscale cordura weave with PALS webbing rows every 25.4 mm (vertical stitch bars
    every 38 mm). Tinted per material."""
    px_per_m = n / TILE_WEBBING_M
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    weave = 0.5 + 0.25 * np.sin(xx * 2.1) * np.sin(yy * 2.1)
    grain = L.fbm(n, 12, 3, seed)
    row = 0.0254 * px_per_m
    row = n / round(n / row)
    band = ((yy % row) / row)
    pals = np.where(band < 0.62, 1.0, 0.0)
    edge = np.exp(-((band - 0.0) / 0.05) ** 2) + np.exp(-((band - 0.62) / 0.05) ** 2)
    stitch_p = n / round(n / (0.038 * px_per_m))
    stitch = np.exp(-((((xx % stitch_p) - 2) / 1.2) ** 2)) * (band < 0.62)
    alb = 0.78 + 0.10 * weave + 0.14 * (grain - 0.5) + 0.06 * pals - 0.25 * edge * 0.4 - 0.12 * stitch
    L.save_png(path_albedo, np.dstack([alb] * 3))
    h = 0.8 * pals - 0.6 * stitch + 0.15 * weave + 2.0 * grain
    L.save_png(path_normal, L.normal_from_height(h, 1.4))


def smooth_cordura(path_normal, n=256, seed=9):
    """Plain cordura (no PALS rows) for pouch bodies, packs and gloves."""
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    weave = np.sin(xx * 2.1) * np.sin(yy * 2.1)
    h = 0.15 * weave + 3.0 * L.fbm(n, 18, 3, seed)
    L.save_png(path_normal, L.normal_from_height(h, 1.3))


def leather(path_albedo, path_normal, n=512, seed=12):
    pores = L.fbm(n, 2.0, 2, seed)
    wr = L.fbm(n, 25, 3, seed + 1)
    alb = 0.85 + 0.12 * (wr - 0.5) + 0.06 * (pores - 0.5)
    L.save_png(path_albedo, np.dstack([alb] * 3))
    L.save_png(path_normal, L.normal_from_height(1.5 * pores + 4.0 * wr, 1.0))


def hard_noise(path_albedo, path_normal, n=512, seed=14):
    """Polymer / parkerized finish: fine stipple + soft wear variation (greyscale)."""
    st = L.fbm(n, 1.5, 2, seed)
    wear = L.fbm(n, 40, 3, seed + 2)
    alb = 0.88 + 0.10 * (wear - 0.5) + 0.05 * (st - 0.5)
    L.save_png(path_albedo, np.dstack([alb] * 3))
    L.save_png(path_normal, L.normal_from_height(1.2 * st, 1.0))


def build_all(tex_dir):
    os.makedirs(tex_dir, exist_ok=True)
    p = lambda name: os.path.join(tex_dir, name)
    camo_nordic(p("camo_m23_albedo.png"), PALETTE_M23, seed=11)
    camo_nordic(p("camo_arid_albedo.png"), PALETTE_ARID, seed=29)
    ripstop_normal(p("fabric_ripstop_normal.png"))
    cordura(p("webbing_pals_albedo.png"), p("webbing_pals_normal.png"))
    smooth_cordura(p("cordura_normal.png"))
    leather(p("leather_albedo.png"), p("leather_normal.png"))
    hard_noise(p("polymer_albedo.png"), p("polymer_normal.png"))
    return {k: p(v) for k, v in {
        "camo": "camo_m23_albedo.png", "camo_arid": "camo_arid_albedo.png", "ripstop_n": "fabric_ripstop_normal.png",
        "pals": "webbing_pals_albedo.png", "pals_n": "webbing_pals_normal.png", "cordura_n": "cordura_normal.png",
        "leather": "leather_albedo.png", "leather_n": "leather_normal.png",
        "polymer": "polymer_albedo.png", "polymer_n": "polymer_normal.png"}.items()}
