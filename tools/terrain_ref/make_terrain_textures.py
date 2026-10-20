"""Procedural, seamlessly tiling ground textures for the reference world (Terrain3D slots
4-6): forest floor (needles, moss, twigs), gravel and bog (sphagnum, wet hollows).

Output per texture, like the existing ambientCG sets: <name>_alb_ht.png (RGB albedo +
height in alpha) and <name>_nrm_rgh.png (OpenGL normal + roughness in alpha), 1024^2.
Run with Blender's Python:  python make_terrain_textures.py <out_dir>
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate import write_png, to_u8  # noqa: E402
from fn_noise import _fade, _GRAD, smoothstep  # noqa: E402

N = 1024


def pnoise(period, seed):
    """Periodic gradient noise over the N x N texture with `period` cells per side."""
    rng = np.random.Generator(np.random.PCG64(seed))
    ang = rng.random((period, period)) * 2 * math.pi
    g = np.stack([np.cos(ang), np.sin(ang)], axis=-1)
    t = (np.arange(N) + 0.5) * period / N
    x, y = np.meshgrid(t, t)
    xi = np.floor(x).astype(int)
    yi = np.floor(y).astype(int)
    fx, fy = x - xi, y - yi
    x0, y0, x1, y1 = xi % period, yi % period, (xi + 1) % period, (yi + 1) % period

    def d(gx, gy, dx, dy):
        gg = g[gy, gx]
        return gg[..., 0] * dx + gg[..., 1] * dy
    u, v = _fade(fx), _fade(fy)
    a = d(x0, y0, fx, fy) + u * (d(x1, y0, fx - 1, fy) - d(x0, y0, fx, fy))
    b = d(x0, y1, fx, fy - 1) + u * (d(x1, y1, fx - 1, fy - 1) - d(x0, y1, fx, fy - 1))
    return (a + v * (b - a)) * 1.41


def pfbm(period, seed, octaves=4, gain=0.5):
    tot = np.zeros((N, N))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        tot += pnoise(period * 2 ** o, seed + o) * amp
        norm += amp
        amp *= gain
    return tot / norm


def worley(cells, seed):
    """Periodic cellular noise: (F1, F2 - F1, cell id) for `cells` cells per side."""
    rng = np.random.Generator(np.random.PCG64(seed))
    pts = rng.random((cells, cells, 2))
    ids = rng.random((cells, cells))
    t = (np.arange(N) + 0.5) * cells / N
    x, y = np.meshgrid(t, t)
    xi = np.floor(x).astype(int)
    yi = np.floor(y).astype(int)
    f1 = np.full((N, N), 9.0)
    f2 = np.full((N, N), 9.0)
    cid = np.zeros((N, N))
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            cx, cy = xi + dx, yi + dy
            p = pts[cy % cells, cx % cells]
            d = np.hypot(cx + p[..., 0] - x, cy + p[..., 1] - y)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            cid = np.where(closer, ids[cy % cells, cx % cells], cid)
            f1 = np.where(closer, d, f1)
    return f1, f2 - f1, cid


def strokes(count, length_px, width_px, seed, curl=0.0):
    """Random short line segments (needles, twigs, grass) on a wrapped canvas."""
    rng = np.random.Generator(np.random.PCG64(seed))
    img = np.zeros((N, N))
    col = np.zeros((N, N))
    for _ in range(count):
        x0, y0 = rng.random(2) * N
        a = rng.random() * math.pi * 2
        ln = length_px * (0.6 + 0.8 * rng.random())
        steps = int(ln) + 1
        tone = rng.random()
        for k in range(steps):
            a += curl * (rng.random() - 0.5)
            px = int(x0 + math.cos(a) * k) % N
            py = int(y0 + math.sin(a) * k) % N
            for w in range(width_px):
                img[(py + w) % N, px] = 1.0
                col[(py + w) % N, px] = tone
    return img, col


def save(out, name, alb, height, rough, normal_strength):
    h = (height - height.min()) / max(1e-6, height.max() - height.min())
    hl = np.roll(h, 1, axis=1)
    hr = np.roll(h, -1, axis=1)
    hu = np.roll(h, 1, axis=0)
    hd = np.roll(h, -1, axis=0)
    nx = (hl - hr) * normal_strength
    ny = (hd - hu) * normal_strength  # OpenGL (Y+) convention
    nz = np.ones_like(nx)
    nl = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.stack([nx / nl * 0.5 + 0.5, ny / nl * 0.5 + 0.5, nz / nl * 0.5 + 0.5, rough], axis=-1)
    write_png(os.path.join(out, name + "_alb_ht.png"), to_u8(np.concatenate([np.clip(alb, 0, 1), h[..., None]], axis=-1)))
    write_png(os.path.join(out, name + "_nrm_rgh.png"), to_u8(np.clip(nrm, 0, 1)))
    print("wrote", name)


def forest_floor(out):
    base = pfbm(8, 10, 5)
    moss = smoothstep(0.1, 0.35, pfbm(6, 20, 4) + 0.2 * pfbm(32, 21, 2))
    needles, ntone = strokes(70000, 8, 1, 30, 0.05)
    twigs, _ = strokes(220, 36, 2, 31, 0.25)
    litter = np.array([0.36, 0.27, 0.17])
    needle_c = np.array([0.48, 0.34, 0.20])
    moss_c = np.array([0.27, 0.33, 0.14])
    alb = litter * (0.9 + 0.18 * base)[..., None]
    alb = alb + (moss_c - alb) * (moss * 0.75)[..., None]
    nd = needles * (1.0 - moss * 0.7)
    alb = alb + ((needle_c * (0.8 + 0.45 * ntone[..., None])) - alb) * nd[..., None] * 0.7
    alb = alb + (np.array([0.24, 0.18, 0.12]) - alb) * twigs[..., None] * 0.8
    alb *= (0.92 + 0.1 * pfbm(48, 33, 2))[..., None]
    height = 0.4 * base + 0.5 * moss + 0.3 * nd + 0.5 * twigs + 0.2 * pfbm(64, 34, 2)
    rough = 0.88 + 0.08 * moss
    save(out, "forest_floor", alb, height, rough, 6.0)


def gravel(out):
    f1, edge, cid = worley(70, 40)
    f1b, edgeb, cidb = worley(150, 41)
    stone = smoothstep(0.0, 0.18, edge)
    stoneb = smoothstep(0.0, 0.15, edgeb)
    tone = 0.5 * cid + 0.5 * pfbm(8, 42, 3) * 0.5 + 0.25
    dust = smoothstep(-0.1, 0.4, pfbm(5, 43, 4))
    c1 = np.array([0.50, 0.47, 0.42])
    c2 = np.array([0.62, 0.58, 0.50])
    grit = np.array([0.40, 0.36, 0.30])
    pebble = c1 + (c2 - c1) * np.clip(tone, 0, 1)[..., None]
    pebble *= (0.8 + 0.35 * cidb)[..., None] * 0.5 + 0.5
    alb = grit + (pebble - grit) * np.maximum(stone, stoneb * 0.8)[..., None]
    alb = alb + (np.array([0.55, 0.50, 0.42]) - alb) * (dust * 0.45)[..., None]
    height = np.maximum(stone * (1 - f1 * 0.6), stoneb * 0.6 * (1 - f1b * 0.5)) + 0.1 * pfbm(40, 44, 2)
    rough = 0.9 - 0.08 * stone
    save(out, "gravel", alb, height, rough, 7.0)


def bog(out):
    base = pfbm(12, 50, 5)
    hummock = smoothstep(-0.25, 0.3, pfbm(16, 51, 4) + 0.3 * pfbm(48, 55, 2))
    red = smoothstep(0.15, 0.5, pfbm(10, 52, 3))
    pools = smoothstep(0.38, 0.5, -pfbm(6, 53, 4))
    grass, gt = strokes(30000, 12, 1, 54, 0.15)
    sph_g = np.array([0.50, 0.50, 0.24])
    sph_r = np.array([0.46, 0.30, 0.18])
    peat = np.array([0.18, 0.14, 0.10])
    alb = sph_g + (sph_r - sph_g) * (red * 0.6)[..., None]
    alb = alb * (0.78 + 0.3 * hummock + 0.08 * pfbm(96, 56, 2))[..., None]
    alb = alb + (np.array([0.66, 0.60, 0.36]) * (0.8 + 0.4 * gt[..., None]) - alb) * (grass * (0.4 + 0.6 * hummock))[..., None] * 0.75
    alb = alb + (peat - alb) * (pools * 0.9)[..., None]
    height = 0.6 * hummock + 0.2 * base + 0.3 * grass * hummock - 0.6 * pools
    rough = 0.85 - 0.6 * pools
    save(out, "bog", alb, height, rough, 5.0)


def asphalt(out):
    """Worn rural asphalt: dark grey binder with light aggregate, faint patching."""
    f1, edge, cid = worley(220, 60)
    agg = smoothstep(0.0, 0.12, edge) * (cid > 0.55)
    base = pfbm(6, 61, 4)
    patch = smoothstep(0.25, 0.45, pfbm(3, 62, 3))
    col = np.array([0.20, 0.20, 0.21]) * (0.85 + 0.25 * base)[..., None]
    col = col + (np.array([0.40, 0.39, 0.37]) - col) * (agg * 0.6)[..., None]
    col = col * (1 - 0.15 * patch)[..., None]
    height = 0.3 * base + 0.4 * agg
    save(out, "asphalt", col, height, 0.8 - 0.1 * agg, 3.0)


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    forest_floor(out)
    gravel(out)
    bog(out)
    asphalt(out)


if __name__ == "__main__":
    main()
