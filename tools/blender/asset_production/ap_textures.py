"""Procedural, tileable textures for the ASSET-PRODUCTION-01 static library (numpy -> PNG).

Every texture tiles (FFT-filtered noise, periodic patterns, wrap-around stamping) and is
used through world-scale box UVs: one UV unit = the material's tile in metres
(ap_materials.MATERIALS). Greyscale bases (paint, canvas, galvanized steel) are tinted by
the material colour, so one image serves many materials and Godot uploads it once.

Output: assets/military/textures/<name>.png (albedo, sRGB) and <name>_normal.png
(tangent space, OpenGL / +Y up, as glTF and Godot expect).
"""
import math
import os

import numpy as np

import char_lib as L

F = np.float32


# ----------------------------------------------------------------------------- noise


def fnoise(n, cut, seed, power=2.0):
    """Tileable noise in [0, 1]: white noise low-passed at `cut` cycles per tile."""
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.standard_normal((n, n)))
    fy = np.fft.fftfreq(n)[:, None] * n
    fx = np.fft.fftfreq(n)[None, :] * n
    r = np.sqrt(fx * fx + fy * fy)
    out = np.real(np.fft.ifft2(f / (1.0 + (r / cut) ** (2.0 * power))))
    out -= out.min()
    return (out / max(out.max(), 1e-9)).astype(F)


def fractal(n, seed, cuts=(2, 6, 18, 60), weights=(0.45, 0.30, 0.17, 0.08)):
    acc = np.zeros((n, n), F)
    for i, (c, w) in enumerate(zip(cuts, weights)):
        acc += fnoise(n, c, seed + 31 * i) * w
    acc -= acc.min()
    return acc / max(acc.max(), 1e-9)


def ramp(x, lo, hi):
    return np.clip((x - lo) / (hi - lo), 0.0, 1.0)


def normal_map(h, strength):
    """OpenGL tangent-space normal map from a periodic height field (px units)."""
    return L.normal_from_height(h, strength)


def stamp_discs(n, items, out, value_fn=None, height=None):
    """Draws soft discs on a torus. items: (cx, cy, rx, ry, angle, colour(3), height).
    Later items cover earlier ones. Writes colour into out (n, n, 3) and a dome height
    into `height` (n, n) when given."""
    for cx, cy, rx, ry, ang, col, h in items:
        r = max(rx, ry)
        x0, x1 = int(cx - r - 2), int(cx + r + 3)
        y0, y1 = int(cy - r - 2), int(cy + r + 3)
        xs = np.arange(x0, x1)
        ys = np.arange(y0, y1)
        dx = (xs - cx)[None, :]
        dy = (ys - cy)[:, None]
        ca, sa = math.cos(ang), math.sin(ang)
        u = (dx * ca + dy * sa) / rx
        v = (-dx * sa + dy * ca) / ry
        d = np.sqrt(u * u + v * v)
        a = np.clip((1.0 - d) * r * 0.8, 0, 1)
        ix = np.ix_(ys % n, xs % n)
        if col is not None:
            out[ix] = out[ix] * (1 - a[..., None]) + np.asarray(col, F)[None, None, :] * a[..., None]
        if height is not None:
            dome = np.sqrt(np.clip(1.0 - d * d, 0, 1)) * h
            height[ix] = np.where(a > 0.5, np.maximum(height[ix] * (1 - a), dome), height[ix])


def voronoi_cells(n, count, seed):
    """Tileable Voronoi: returns (cell id per pixel, distance to the nearest edge proxy)."""
    rng = np.random.default_rng(seed)
    pts = rng.uniform(0, n, (count, 2)).astype(F)
    ids = np.zeros((n, n), np.int32)
    d1 = np.zeros((n, n), F)
    d2 = np.zeros((n, n), F)
    xx = np.arange(n, dtype=F)[None, :, None]
    for r0 in range(0, n, 32):
        yy = np.arange(r0, min(n, r0 + 32), dtype=F)[:, None, None]
        dx = np.abs(xx - pts[None, None, :, 0])
        dy = np.abs(yy - pts[None, None, :, 1])
        dx = np.minimum(dx, n - dx)
        dy = np.minimum(dy, n - dy)
        dd = dx * dx + dy * dy
        part = np.argpartition(dd, 1, axis=2)[:, :, :2]
        a = np.take_along_axis(dd, part, axis=2)
        order = np.argsort(a, axis=2)
        a = np.take_along_axis(a, order, axis=2)
        part = np.take_along_axis(part, order, axis=2)
        ids[r0:r0 + 32] = part[:, :, 0]
        d1[r0:r0 + 32] = np.sqrt(a[:, :, 0])
        d2[r0:r0 + 32] = np.sqrt(a[:, :, 1])
    return ids, d2 - d1


def save(tex_dir, name, rgb, alpha=None):
    path = os.path.join(tex_dir, name + ".png")
    L.save_png(path, np.clip(rgb, 0, 1).astype(F), alpha)
    return path


def grey(v):
    return np.dstack([v, v, v])


# ----------------------------------------------------------------------------- recipes


def paint(tex_dir, n=1024, seed=101):
    """Greyscale painted steel (tinted per material): broad fading, vertical rain
    streaks (V is up on walls), soft dirt patches, fine speckle, small paint chips."""
    shade = 0.86 + 0.13 * (fnoise(n, 1.5, seed) - 0.5)
    shade += 0.05 * (fnoise(n, 7, seed + 1) - 0.5)
    shade += 0.025 * (fnoise(n, 160, seed + 2) - 0.5)
    col = fnoise(n, 50, seed + 3)[0, :][None, :]
    along = fnoise(n, 3, seed + 4)
    streak = ramp(col, 0.50, 0.85) * (0.4 + 0.9 * along)
    shade -= 0.09 * streak
    dirt = ramp(fnoise(n, 4, seed + 9), 0.62, 0.95)
    shade -= 0.08 * dirt
    chips = ramp(fnoise(n, 70, seed + 13) + 0.25 * fnoise(n, 9, seed + 14), 0.97, 1.02)
    shade = shade * (1 - chips) + 0.42 * chips
    save(tex_dir, "paint", grey(shade))
    h = 0.6 * fnoise(n, 260, seed + 20) + 3.0 * fnoise(n, 10, seed + 21) - 1.5 * chips
    save(tex_dir, "paint_normal", normal_map(h, 1.2))


def ribs_normal(tex_dir, name, n, ribs, slope, trapezoid=True, base_name="paint"):
    """Corrugation along U (vertical ribs on walls) plus the paint's orange peel."""
    x = np.arange(n, dtype=F)
    ph = 2 * math.pi * x / (n / ribs)
    prof = np.clip(np.sin(ph) * 2.2, -1, 1) if trapezoid else np.sin(ph)
    h1 = np.repeat(prof[None, :], n, axis=0) * (n / ribs) * slope / 4.0
    h = h1 + 0.5 * fnoise(n, 220, 7)
    save(tex_dir, name, normal_map(h, 1.0))


def galvanized(tex_dir, n=512, seed=111):
    """Galvanized steel: spangle crystals (Voronoi), fine scratches, mild white rust."""
    ids, edge = voronoi_cells(n, 260, seed)
    rng = np.random.default_rng(seed + 1)
    tone = rng.uniform(0.80, 0.98, ids.max() + 1).astype(F)[ids]
    tone -= 0.05 * np.exp(-edge / 1.2)
    tone += 0.05 * (fnoise(n, 3, seed + 2) - 0.5)
    scratch = fnoise(n, 120, seed + 3, power=1.0)
    scratch = np.repeat(scratch[:1, :], n, axis=0) * 0.5 + fnoise(n, 90, seed + 4) * 0.5
    tone += 0.04 * (scratch - 0.5)
    white = ramp(fnoise(n, 6, seed + 5), 0.70, 0.95)
    tone = tone * (1 - 0.3 * white) + 0.95 * 0.3 * white
    save(tex_dir, "galvanized", grey(tone))
    h = 0.8 * (tone - tone.mean()) * 4 + 0.8 * fnoise(n, 200, seed + 6)
    save(tex_dir, "galvanized_normal", normal_map(h, 1.0))


def concrete(tex_dir, n=1024, seed=121):
    """Cast concrete (coloured): cloudy tone, pores, water stains, faint hairline cracks."""
    base = fractal(n, seed)
    shade = 0.84 + 0.22 * base
    pores = fnoise(n, 280, seed + 2)
    pore_mask = ramp(pores, 0.80, 0.93)
    shade *= 1.0 - 0.30 * pore_mask
    stains = ramp(fnoise(n, 3, seed + 7), 0.55, 0.9)
    shade *= 1.0 - 0.12 * stains
    ids, edge = voronoi_cells(n, 14, seed + 9)
    crack = np.exp(-(edge / 0.9) ** 2) * ramp(fnoise(n, 8, seed + 10), 0.55, 0.75)
    shade *= 1.0 - 0.25 * crack
    rgb = np.dstack([shade * 0.63, shade * 0.62, shade * 0.59])
    save(tex_dir, "concrete", rgb)
    h = 1.5 * base * 6 - 2.5 * pore_mask - 3.0 * crack
    save(tex_dir, "concrete_normal", normal_map(h, 0.8))


def cmu_block(tex_dir, n=1024, seed=131):
    """Concrete masonry units 400 x 200 mm, 10 mm mortar, running bond. Tile 1.6 m:
    4 blocks across, 8 courses."""
    px = n / 1.6
    yy, xx = np.mgrid[0:n, 0:n].astype(F)
    course = np.floor(yy / (0.2 * px)).astype(int)
    off = (course % 2) * 0.2 * px
    bx = (xx + off) % (0.4 * px)
    by = yy % (0.2 * px)
    m = 0.010 * px / 2
    jx = np.minimum(bx, 0.4 * px - bx)
    jy = np.minimum(by, 0.2 * px - by)
    joint = np.clip(1.0 - np.minimum(jx, jy) / m, 0, 1) ** 0.5
    block_id = (np.floor((xx + off) / (0.4 * px)).astype(int) % 4) + course * 4
    rng = np.random.default_rng(seed)
    tone = rng.uniform(0.90, 1.06, 64).astype(F)[block_id % 64]
    pores = ramp(fnoise(n, 300, seed + 1), 0.78, 0.92)
    shade = tone * (0.92 + 0.12 * fractal(n, seed + 2)) * (1 - 0.25 * pores)
    shade = shade * (1 - joint) + 0.78 * joint
    rgb = np.dstack([shade * 0.60, shade * 0.59, shade * 0.56])
    save(tex_dir, "cmu", rgb)
    h = -6.0 * joint + 0.8 * fnoise(n, 250, seed + 3) - 1.0 * pores
    save(tex_dir, "cmu_normal", normal_map(h, 1.0))


def asphalt(tex_dir, n=1024, seed=141):
    """Weathered asphalt (tile 4 m): dark binder with light aggregate speckle, worn
    lighter patches, oil stains, sealed crack lines."""
    fine = fnoise(n, 420, seed)
    agg = ramp(fine, 0.62, 0.80)
    dark = ramp(fnoise(n, 380, seed + 1), 0.70, 0.85)
    wear = fractal(n, seed + 2)
    shade = 0.30 + 0.10 * wear + 0.16 * agg - 0.06 * dark
    oil = ramp(fnoise(n, 5, seed + 3), 0.72, 0.95)
    shade -= 0.07 * oil
    ids, edge = voronoi_cells(n, 6, seed + 4)
    seal = np.exp(-(edge / 2.0) ** 2) * ramp(fnoise(n, 6, seed + 5), 0.5, 0.65)
    shade = shade * (1 - 0.7 * seal) + 0.12 * 0.7 * seal
    rgb = np.dstack([shade, shade * 0.99, shade * 0.97])
    save(tex_dir, "asphalt", rgb)
    h = 3.0 * agg + 1.0 * fine - 1.5 * dark + 2.0 * wear
    save(tex_dir, "asphalt_normal", normal_map(h, 1.0))


def gravel(tex_dir, n=1024, seed=151):
    """Crushed-stone gravel (tile 2 m): angular stones 8-35 mm in greys and browns over
    a dusty fines layer."""
    rng = np.random.default_rng(seed)
    px = n / 2.0
    fines = 0.42 + 0.10 * fractal(n, seed + 1)
    rgb = np.dstack([fines * 1.02, fines * 0.97, fines * 0.88]).astype(F)
    h = np.zeros((n, n), F)
    palette = np.array([[0.56, 0.55, 0.53], [0.46, 0.45, 0.44], [0.62, 0.58, 0.52], [0.38, 0.37, 0.36],
                        [0.52, 0.47, 0.40], [0.68, 0.66, 0.62]], F)
    count = int(2.0 * 2.0 * 2600)
    items = []
    for _ in range(count):
        r = rng.uniform(0.004, 0.0175) * px
        col = palette[rng.integers(len(palette))] * rng.uniform(0.85, 1.12)
        items.append((rng.uniform(0, n), rng.uniform(0, n), r, r * rng.uniform(0.55, 0.95), rng.uniform(0, math.pi), col, r))
    stamp_discs(n, items, rgb, height=h)
    rgb *= (0.92 + 0.12 * fnoise(n, 3, seed + 2))[..., None]
    save(tex_dir, "gravel", rgb)
    save(tex_dir, "gravel_normal", normal_map(h + 2.0 * fnoise(n, 300, seed + 3), 0.9))


def dirt(tex_dir, n=1024, seed=161):
    """Compacted earth (tile 4 m): brown mottling, darker damp patches, small pebbles."""
    rng = np.random.default_rng(seed)
    # Low contrast at the tile scale (4 m) so the repeat does not read from a distance;
    # most variation sits in the 0.1-0.5 m band.
    base = fractal(n, seed, cuts=(3, 8, 24, 70), weights=(0.15, 0.30, 0.35, 0.20))
    shade = 0.84 + 0.20 * base
    damp = ramp(fnoise(n, 10, seed + 1), 0.62, 0.92)
    shade *= 1 - 0.08 * damp
    rgb = np.dstack([shade * 0.47, shade * 0.40, shade * 0.30]).astype(F)
    h = 4.0 * base + 1.2 * fnoise(n, 160, seed + 2)
    px = n / 4.0
    items = []
    for _ in range(1600):
        r = rng.uniform(0.003, 0.012) * px
        c = rng.uniform(0.35, 0.55)
        items.append((rng.uniform(0, n), rng.uniform(0, n), r, r * rng.uniform(0.6, 1.0), rng.uniform(0, 3.1), (c, c * 0.95, c * 0.86), r))
    stamp_discs(n, items, rgb, height=h)
    save(tex_dir, "dirt", rgb)
    save(tex_dir, "dirt_normal", normal_map(h, 0.9))


def canvas(tex_dir, n=1024, seed=171):
    """Greyscale cotton/polyester canvas (tile 2 m): plain weave, seam-free soiling."""
    yy, xx = np.mgrid[0:n, 0:n].astype(F)
    weave = 0.5 + 0.5 * np.sin(xx * math.pi * 0.5) * np.sin(yy * math.pi * 0.5)
    shade = 0.90 + 0.05 * weave
    shade += 0.10 * (fnoise(n, 2, seed) - 0.5)
    shade += 0.04 * (fnoise(n, 12, seed + 1) - 0.5)
    stain = ramp(fnoise(n, 5, seed + 2), 0.65, 0.95)
    shade -= 0.10 * stain
    save(tex_dir, "canvas", grey(shade))
    h = 0.8 * weave + 5.0 * fnoise(n, 14, seed + 3)
    save(tex_dir, "canvas_normal", normal_map(h, 0.8))


def wood(tex_dir, n=512, seed=181):
    """Sawn softwood (tile 1.2 m, grain along U), coloured; tinted lighter for plywood."""
    yy, xx = np.mgrid[0:n, 0:n].astype(F)
    warp = fnoise(n, 6, seed) * 8.0
    rings = np.sin(2 * math.pi * (yy / n) * 30 + warp) * 0.5 + 0.5
    rings = rings ** 1.5
    fibre = np.repeat(fnoise(n, 80, seed + 1)[:, :1], n, axis=1) * 0.5 + fnoise(n, 60, seed + 2) * 0.5
    shade = 0.82 + 0.12 * rings + 0.06 * (fibre - 0.5)
    rng = np.random.default_rng(seed + 3)
    for _ in range(3):
        cx, cy = rng.uniform(0, n, 2)
        d = np.sqrt(np.minimum(np.abs(xx - cx), n - np.abs(xx - cx)) ** 2 * 0.15 + np.minimum(np.abs(yy - cy), n - np.abs(yy - cy)) ** 2)
        shade *= 1 - 0.35 * np.exp(-(d / 6.0) ** 2)
    rgb = np.dstack([shade * 0.66, shade * 0.52, shade * 0.36])
    save(tex_dir, "wood", rgb)
    save(tex_dir, "wood_normal", normal_map(2.0 * rings + 1.0 * fibre, 1.0))


def hesco_liner(tex_dir, n=512, seed=191, cells=8):
    """Geotextile liner with the weld-mesh grid printed faintly into it, so the grid
    reads at distance where the alpha mesh fades (tile = 8 x 76 mm)."""
    yy, xx = np.mgrid[0:n, 0:n].astype(F)
    weave = 0.5 + 0.5 * np.sin(xx * math.pi / 1.5) * np.sin(yy * math.pi / 1.5)
    shade = 0.94 + 0.05 * weave - 0.10 * (fnoise(n, 1.5, seed) - 0.5)
    period = n / cells
    d = np.minimum(np.abs(((xx + period / 2) % period) - period / 2), np.abs(((yy + period / 2) % period) - period / 2))
    grid = d < 3.0
    pil = np.clip(d / (period / 2), 0, 1)
    shade *= 0.88 + 0.12 * pil
    rgb = np.dstack([shade * 0.64, shade * 0.58, shade * 0.45])
    rgb = np.where(grid[..., None], rgb * 0.75 + 0.55 * 0.25, rgb)
    save(tex_dir, "hesco_liner", rgb)
    save(tex_dir, "hesco_liner_normal", normal_map(4.0 * pil + 0.5 * weave, 1.0))


def wire_mesh(tex_dir, n=512, cells=8, wire_px=5.0, seed=193):
    yy, xx = np.mgrid[0:n, 0:n].astype(F)
    period = n / cells
    wx = np.abs(((xx + period / 2) % period) - period / 2) < wire_px / 2
    wy = np.abs(((yy + period / 2) % period) - period / 2) < wire_px / 2
    alpha = (wx | wy).astype(F)
    shade = 0.80 + 0.25 * fnoise(n, 30, seed) - 0.12 * (wx & wy)
    rust = ramp(fnoise(n, 12, seed + 2), 0.75, 1.0)
    rgb = grey(shade * 0.68)
    rgb = rgb * (1 - 0.5 * rust[..., None]) + np.array([0.45, 0.30, 0.18], F) * 0.5 * rust[..., None]
    save(tex_dir, "wire_mesh", rgb, alpha)


def chainlink(tex_dir, n=512, diamonds=8, wire_px=4.0, seed=195):
    yy, xx = np.mgrid[0:n, 0:n].astype(F)
    p = n / diamonds
    u = (xx + yy) / p
    v = (xx - yy) / p
    du = np.abs(u - np.round(u)) * p / math.sqrt(2)
    dv = np.abs(v - np.round(v)) * p / math.sqrt(2)
    alpha = ((du < wire_px / 2) | (dv < wire_px / 2)).astype(F)
    save(tex_dir, "chainlink", grey(0.66 + 0.25 * fnoise(n, 25, seed)), alpha)


def camo_net(tex_dir, n=512, seed=197):
    """Garnished camouflage net: muted woodland patches, about half open."""
    a = fnoise(n, 12, seed)
    b = fnoise(n, 5, seed + 1)
    garnish = (a > 0.52).astype(F)
    yy, xx = np.mgrid[0:n, 0:n].astype(F)
    p = n / 8
    net = ((np.abs(((xx + yy) % p) - p / 2) < 1.2) | (np.abs(((xx - yy) % p) - p / 2) < 1.2)).astype(F)
    alpha = np.clip(garnish + net, 0, 1)
    cols = np.array([[0.25, 0.28, 0.18], [0.30, 0.31, 0.21], [0.33, 0.30, 0.21], [0.21, 0.23, 0.15]], F)
    rgb = cols[np.clip((b * 4).astype(int), 0, 3)] * (0.9 + 0.2 * fnoise(n, 60, seed + 2))[..., None]
    rgb = np.where(net[..., None] > 0.5, np.array([0.18, 0.18, 0.14], F), rgb)
    save(tex_dir, "camo_net", rgb, alpha)


def rubber(tex_dir, n=256, seed=199):
    shade = 0.85 + 0.12 * (fnoise(n, 40, seed) - 0.5) + 0.06 * (fnoise(n, 4, seed + 1) - 0.5)
    save(tex_dir, "rubber", grey(shade))
    save(tex_dir, "rubber_normal", normal_map(1.5 * fnoise(n, 90, seed + 2), 1.0))


def build_all(tex_dir):
    os.makedirs(tex_dir, exist_ok=True)
    paint(tex_dir)
    # Container walls: 8 trapezoid ribs per 2.24 m tile (ISO side-wall pitch ~0.28 m).
    ribs_normal(tex_dir, "container_ribs_normal", 1024, 8, 0.9, trapezoid=True)
    # Roof sheet: 32 sine ribs per 2.432 m tile (76 mm corrugated profile).
    ribs_normal(tex_dir, "roof_sheet_normal", 1024, 32, 0.8, trapezoid=False)
    galvanized(tex_dir)
    concrete(tex_dir)
    cmu_block(tex_dir)
    asphalt(tex_dir)
    gravel(tex_dir)
    dirt(tex_dir)
    canvas(tex_dir)
    wood(tex_dir)
    hesco_liner(tex_dir)
    wire_mesh(tex_dir)
    chainlink(tex_dir)
    camo_net(tex_dir)
    rubber(tex_dir)
