"""Faction camouflage textures for the infantry families (ASSET-PRODUCTION-01).

Original patterns in the spirit of the real ones, 1024 px for one 0.60 m tile (the
character pipeline's camo tile, char_textures.TILE_FABRIC_M):
  * camo_nato_albedo.png     multi-terrain: soft tan/khaki field, olive and brown blobs,
                             thin dark branches, pale specks (MultiCam / MTP family)
  * camo_emr_albedo.png      Russian digital (EMR "Tsifra" family): 5 mm pixels in light
                             olive, green, brown and black
  * camo_type21_albedo.png   PLA Type 21 digital ("star sky" family): 4.7 mm pixels,
                             cloud-shaped clusters plus scattered single-pixel specks
"""
import numpy as np

import char_lib as L

F = np.float32


def _soft(field, thr, width):
    return np.clip((field - thr) / width, 0, 1)


def _lay(rgb, mask, col):
    return rgb * (1 - mask[..., None]) + np.asarray(col, F)[None, None, :] * mask[..., None]


def camo_nato(path, n=1024, seed=301):
    rgb = np.zeros((n, n, 3), F)
    base = L.fbm(n, 220, 3, seed, gain=0.5)
    rgb[:] = np.asarray((0.60, 0.53, 0.40), F)
    rgb = _lay(rgb, _soft(base, 0.48, 0.10), (0.68, 0.62, 0.48))          # lighter sand field
    rgb = _lay(rgb, _soft(base, 0.66, 0.06) * 0.8, (0.73, 0.69, 0.56))
    # Olive-green and brown blobs, slightly stretched vertically, soft printed edges.
    g = L.fbm(n, 95, 3, seed + 3, gain=0.5, aniso=(1.0, 0.7))
    rgb = _lay(rgb, _soft(g, 0.58, 0.035), (0.40, 0.41, 0.27))
    b = L.fbm(n, 80, 3, seed + 5, gain=0.5, aniso=(1.0, 0.7))
    rgb = _lay(rgb, _soft(b, 0.60, 0.03), (0.47, 0.37, 0.26))
    # Thin dark-brown branches: ridged noise kept where a medium noise is high.
    r = L.fbm(n, 40, 2, seed + 7, aniso=(1.0, 0.45))
    ridge = 1.0 - np.abs(r - 0.5) * 2.0
    keep = _soft(L.fbm(n, 70, 2, seed + 9), 0.55, 0.08)
    rgb = _lay(rgb, _soft(ridge, 0.93, 0.03) * keep, (0.26, 0.21, 0.15))
    # Pale specks.
    s = L.fbm(n, 6, 1, seed + 11)
    rgb = _lay(rgb, _soft(s, 0.72, 0.04) * _soft(L.fbm(n, 60, 2, seed + 12), 0.5, 0.1) * 0.8, (0.80, 0.77, 0.66))
    rgb *= (0.94 + 0.08 * L.fbm(n, 5, 2, seed + 21))[..., None]
    return L.save_png(path, np.clip(rgb, 0, 1))


def _digital(n, cell, layers, field_col, seed, specks=None):
    """Pixelated pattern: noise on a coarse grid (cell px per pixel), thresholded into
    colour layers, then upscaled with nearest neighbour. layers: [(scale, thr, colour)]."""
    assert n % cell == 0, "cell must divide the tile size (tileable)"
    m = n // cell
    rgb = np.zeros((m, m, 3), F) + np.asarray(field_col, F)
    for k, (scale, thr, col) in enumerate(layers):
        f = L.fbm(m, scale, 3, seed + 13 * k, gain=0.55)
        jitter = np.random.default_rng(seed + k).uniform(-0.03, 0.03, (m, m))
        mask = (f + jitter > thr).astype(F)
        rgb = _lay(rgb, mask, col)
    if specks:
        rng = np.random.default_rng(seed + 99)
        for density, col in specks:
            mask = (rng.uniform(0, 1, (m, m)) < density).astype(F)
            rgb = _lay(rgb, mask, col)
    rgb = np.repeat(np.repeat(rgb, cell, axis=0), cell, axis=1)
    return rgb


def camo_emr(path, n=1024, seed=331):
    cell = 8                                # 1024 px / 0.60 m -> 8 px = 4.7 mm pixels
    rgb = _digital(n, cell, [(16, 0.53, (0.33, 0.39, 0.25)), (11, 0.60, (0.38, 0.31, 0.22)),
                             (7, 0.66, (0.13, 0.13, 0.11))], (0.55, 0.56, 0.43), seed)
    rgb *= (0.94 + 0.09 * L.fbm(n, 6, 2, seed + 21))[..., None]
    return L.save_png(path, np.clip(rgb, 0, 1))


def camo_type21(path, n=1024, seed=361):
    cell = 8                                # 4.7 mm pixels (cell must divide the 1024 px tile)
    rgb = _digital(n, cell, [(14, 0.50, (0.22, 0.29, 0.17)), (12, 0.60, (0.50, 0.45, 0.31)),
                             (7, 0.66, (0.10, 0.12, 0.09)), (9, 0.70, (0.55, 0.60, 0.42))], (0.36, 0.42, 0.27), seed,
                   specks=[(0.012, (0.60, 0.62, 0.46)), (0.014, (0.10, 0.12, 0.09))])
    rgb *= (0.94 + 0.09 * L.fbm(n, 6, 2, seed + 21))[..., None]
    return L.save_png(path, np.clip(rgb, 0, 1))


def build(tex_dir):
    import os
    p = lambda name: os.path.join(tex_dir, name)
    camo_nato(p("camo_nato_albedo.png"))
    camo_emr(p("camo_emr_albedo.png"))
    camo_type21(p("camo_type21_albedo.png"))
    return {"camo_nato": p("camo_nato_albedo.png"), "camo_emr": p("camo_emr_albedo.png"), "camo_type21": p("camo_type21_albedo.png")}
