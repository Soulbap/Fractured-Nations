"""Tileable textures for the settlement buildings and fences (VISUAL-02), procedural like make_env_textures.py.

  "C:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" tools/blender/env/make_building_textures.py [out_dir]

Each <name>_alb.png (RGB albedo, near neutral where shaders/environment/building.gdshader multiplies a paint colour) and
<name>_nrm.png (OpenGL normal). Metric tile sizes (the shader's uv_scale = 1 / tile):
  bld_siding_lap      2.0 m  horizontal weatherboard (liggende panel), 11 boards, painted, light
  bld_siding_board    2.0 m  vertical board-and-batten (staende panel) for barns and sheds, light (paint colour in the shader)
  bld_roof_tile       2.0 m  clay pantiles, 6 rows, terracotta with per-tile variation and lichen
  bld_roof_sheet      2.0 m  corrugated steel sheet, dark grey, rain streaks
  bld_stone           2.0 m  foundation: dressed stones in rows with mortar
  bld_wood_grey       1.0 m  silvered grey planks (fences, barn ramp, trim), grain along U
  bld_window          one window (UV 0..1): white frame, 2 x 2 panes, dark glass with a sky reflection, curtains
  bld_door            one door (UV 0..1): framed plank door with a brace (painted light; colour in the shader)
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_env_textures import normal_from_height, save, value_noise  # noqa: E402

N = 1024


def grid(n=N):
    y, x = np.mgrid[0:n, 0:n] + 0.5
    return x / n, y / n


def cells(u, v, nu, nv, seed, stagger=0.0):
    """Index and local coords of a (staggered) cell grid; random value per cell."""
    rows = np.floor(v * nv)
    uu = u * nu + stagger * (rows % 2)
    cols = np.floor(uu)
    rng = np.random.Generator(np.random.PCG64(seed))
    table = rng.random(4096)
    idx = ((cols % nu) * 131 + (rows % nv) * 977).astype(np.int64) % 4096
    return table[idx], uu - cols, v * nv - rows


def siding_lap(out):
    u, v = grid()
    boards = 11
    r, fu, fv = cells(u, v, 3, boards, 11, stagger=0.37)
    # Lap profile: each board slopes outward to its lower edge, a shadow line under it.
    lap = 1.0 - fv
    shadow = np.clip((fv - 0.9) / 0.1, 0, 1)
    grain = value_noise((N, N), (2, 48), 12, 3)
    streak = value_noise((N, N), (24, 2), 13, 3)
    h = lap * 0.8 + 0.08 * grain
    base = 0.9 + 0.04 * (r - 0.5) + 0.06 * (grain - 0.5) - 0.07 * np.clip(streak - 0.55, 0, 1)
    col = np.stack([base, base * 0.985, base * 0.95], -1)
    col *= (1.0 - 0.28 * shadow)[..., None]
    # Board ends (butt joints) every few metres.
    joint = (np.abs(fu - 0.5) > 0.497).astype(float)
    col *= (1.0 - 0.25 * joint)[..., None]
    save(os.path.join(out, "bld_siding_lap_alb.png"), col)
    save(os.path.join(out, "bld_siding_lap_nrm.png"), normal_from_height(h - 0.6 * shadow - 0.3 * joint, 3.0))


def siding_board(out):
    u, v = grid()
    nb = 9
    x = (u * nb) % 1.0
    bi = np.floor(u * nb)
    rng = np.random.Generator(np.random.PCG64(21))
    rb = rng.random(nb)[bi.astype(int) % nb]
    batten = (np.abs(x - 0.0) < 0.12) | (np.abs(x - 1.0) < 0.12)
    grain = value_noise((N, N), (36, 3), 22, 3)
    dirt = value_noise((N, N), (6, 6), 23, 3)
    h = np.where(batten, 1.0, 0.45) + 0.1 * grain
    base = 0.82 + 0.06 * (rb - 0.5) + 0.08 * (grain - 0.5) - 0.06 * np.clip(dirt - 0.55, 0, 1)
    edge = np.clip(1.0 - np.minimum(np.abs(x - 0.12), np.abs(x - 0.88)) / 0.015, 0, 1)
    base = base * (1.0 - 0.35 * edge * ~batten)
    col = np.stack([base, base * 0.98, base * 0.96], -1)
    save(os.path.join(out, "bld_siding_board_alb.png"), col)
    save(os.path.join(out, "bld_siding_board_nrm.png"), normal_from_height(h, 2.5))


def roof_tile(out):
    u, v = grid()
    rows, waves = 6, 8
    r, fu, fv = cells(u, v, waves, rows, 31, stagger=0.5)
    wave = 0.5 + 0.5 * np.cos(fu * 2 * math.pi)
    # Each row overlaps the next: thicker at its lower edge, a dark gap above.
    step = fv
    gap = np.clip((0.06 - fv) / 0.06, 0, 1)
    h = 0.6 * wave + 0.35 * step - 0.5 * gap
    lich = np.clip((value_noise((N, N), (16, 16), 32, 4) - 0.68) * 4.0, 0, 1) * 0.8
    tone = 0.85 + 0.3 * (r - 0.5)
    col = np.array([0.56, 0.26, 0.16])[None, None, :] * tone[..., None]
    col = col * (0.82 + 0.25 * wave)[..., None] * (1.0 - 0.55 * gap)[..., None]
    col = col * (1 - lich[..., None]) + np.array([0.42, 0.40, 0.30]) * lich[..., None]
    save(os.path.join(out, "bld_roof_tile_alb.png"), col)
    save(os.path.join(out, "bld_roof_tile_nrm.png"), normal_from_height(h, 5.0))


def roof_sheet(out):
    u, v = grid()
    ribs = 26
    prof = 0.5 + 0.5 * np.cos(u * ribs * 2 * math.pi)
    lap = (np.abs(((v * 2) % 1.0) - 0.0) < 0.012).astype(float)
    streak = value_noise((N, N), (40, 2), 41, 3)
    rust = np.clip((value_noise((N, N), (8, 8), 42, 4) - 0.66) * 3.0, 0, 1)
    base = 0.2 + 0.03 * (streak - 0.5) + 0.04 * prof
    col = np.stack([base, base * 1.02, base * 1.05], -1)
    col = col * (1 - 0.6 * rust[..., None]) + np.array([0.32, 0.18, 0.10]) * 0.6 * rust[..., None]
    col *= (1.0 - 0.4 * lap)[..., None]
    save(os.path.join(out, "bld_roof_sheet_alb.png"), col)
    save(os.path.join(out, "bld_roof_sheet_nrm.png"), normal_from_height(prof * 0.8 - 0.4 * lap, 4.0))


def stone(out):
    u, v = grid()
    r, fu, fv = cells(u, v, 5, 7, 51, stagger=0.45)
    mortar = np.clip(1.0 - np.minimum(np.minimum(fu, 1 - fu) * 5 * 0.4, np.minimum(fv, 1 - fv) * 7 * 0.29) / 0.035, 0, 1)
    rough = value_noise((N, N), (24, 24), 52, 4)
    h = (1 - mortar) * (0.7 + 0.3 * rough)
    tone = 0.42 + 0.12 * (r - 0.5) + 0.08 * (rough - 0.5)
    col = np.stack([tone, tone * 0.98, tone * 0.93], -1) * (1 - 0.35 * mortar[..., None])
    save(os.path.join(out, "bld_stone_alb.png"), col)
    save(os.path.join(out, "bld_stone_nrm.png"), normal_from_height(h, 4.0))


def wood_grey(out):
    u, v = grid()
    planks = 5
    r, fu, fv = cells(u, v, 1, planks, 61)
    grain = value_noise((N, N), (2, 60), 62, 4)
    knots = np.clip((value_noise((N, N), (6, 18), 63, 2) - 0.75) * 6, 0, 1)
    seam = np.clip((np.minimum(fv, 1 - fv) - 0.0) / 0.03, 0, 1)
    tone = 0.46 + 0.1 * (r - 0.5) + 0.14 * (grain - 0.5) - 0.12 * knots
    col = np.stack([tone, tone * 0.96, tone * 0.9], -1) * (0.6 + 0.4 * seam[..., None])
    save(os.path.join(out, "bld_wood_grey_alb.png"), col)
    save(os.path.join(out, "bld_wood_grey_nrm.png"), normal_from_height(0.6 * seam + 0.25 * grain - 0.3 * knots, 3.0))


def window(out):
    n = 512
    u, v = grid(n)
    fr = 0.09
    mull = 0.025
    frame = (u < fr) | (u > 1 - fr) | (v < fr) | (v > 1 - fr)
    cross = (np.abs(u - 0.5) < mull) | (np.abs(v - 0.46) < mull)
    glass = ~(frame | cross)
    sky = np.clip(1.0 - v * 1.2, 0, 1)
    gcol = np.array([0.05, 0.07, 0.09]) + np.array([0.20, 0.24, 0.28]) * sky[..., None] ** 2
    # A diagonal reflection band and curtains at the sides.
    refl = np.clip(1.0 - np.abs((u + v * 0.6) - 0.75) / 0.06, 0, 1) * 0.12
    curtain = ((u < fr + 0.12) | (u > 1 - fr - 0.12)) & glass
    gcol = gcol + refl[..., None]
    gcol = np.where(curtain[..., None], np.array([0.55, 0.52, 0.46]) * (0.7 + 0.3 * np.cos(u * 90)[..., None] ** 2), gcol)
    col = np.where(glass[..., None], gcol, np.array([0.90, 0.89, 0.86]))
    sill_shadow = (v > 1 - fr) & (v < 1 - fr + 0.02)
    col = col * (1 - 0.3 * sill_shadow[..., None])
    h = np.where(frame, 1.0, np.where(cross, 0.8, 0.2))
    save(os.path.join(out, "bld_window_alb.png"), col)
    save(os.path.join(out, "bld_window_nrm.png"), normal_from_height(h, 6.0, wrap=False))


def door(out):
    n = 512
    u, v = grid(n)
    fr = 0.08
    frame = (u < fr) | (u > 1 - fr) | (v < 0.05)
    planks = np.abs(((u - fr) / (1 - 2 * fr) * 5) % 1.0 - 0.5) > 0.47
    brace = (np.abs(v - 0.2) < 0.035) | (np.abs(v - 0.8) < 0.035) | (np.abs((v - 0.2) - (u - fr) * 0.6 / (1 - 2 * fr) * 1.0) < 0.03)
    grain = value_noise((n, n), (8, 2), 71, 3)
    tone = 0.80 + 0.08 * (grain - 0.5)
    col = np.stack([tone, tone * 0.98, tone * 0.95], -1)
    col = col * (1 - 0.35 * planks[..., None])
    handle = (np.abs(u - 0.82) < 0.025) & (np.abs(v - 0.52) < 0.04)
    col = np.where(handle[..., None], np.array([0.12, 0.12, 0.12]), col)
    col = np.where(frame[..., None], np.array([0.9, 0.89, 0.86]), col)
    h = np.where(frame, 1.0, 0.4) + 0.2 * brace - 0.2 * planks
    save(os.path.join(out, "bld_door_alb.png"), col)
    save(os.path.join(out, "bld_door_nrm.png"), normal_from_height(h, 5.0, wrap=False))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "assets/environment/textures"
    os.makedirs(out, exist_ok=True)
    for f in (siding_lap, siding_board, roof_tile, roof_sheet, stone, wood_grey, window, door):
        f(out)


if __name__ == "__main__":
    main()
