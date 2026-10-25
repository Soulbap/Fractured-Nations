"""WORLD-VISUALS-01 surface textures from the CC0 scans (system Python 3 + numpy + Pillow + scipy):

  python tools/blender/env/make_surfaces_v3.py [--only terrain,bark,rock] [--size 2048]

Terrain (assets/terrain/textures/v3_<slot>_alb_ht.png + _nrm_rgh.png, Terrain3D packing: albedo + height in alpha,
OpenGL normal + roughness in alpha, all the same size because Terrain3D builds texture arrays):

  meadow       leafy_grass (short grazed grass with soil)
  rock         mossy_rock (grey granite / gneiss with crustose lichen - the Norwegian bedrock look)
  dirt         forest_ground_04 (brown soil with small stones: tracks, verges, yards)
  heath        sparse_grass graded toward dry heath (brown-olive dwarf shrub / dry grass)
  forest       composite: feather-moss carpet (rocky_terrain_02, graded olive) + humus with spruce needle litter (mud_forest +
               drawn needles), mixed by a tileable two-scale mask, heights from both displacement maps
  gravel       rocky_trail (grey gravel road)
  bog          composite: sphagnum (graded rocky_terrain_02) with wet peat hollows (mud_forest, low roughness)
  asphalt      the existing project asphalt resized (no scan replaces it)

Bark and props (assets/environment/textures/<name>_alb.png + _nrm.png): bark_pine3_lower (pine_bark, grey-brown plates of
an old Scots pine base), bark_pine3_upper (pine_bark graded to the thin orange "flame" bark of the upper stem), bark_spruce3
(fir_tree_01 bark), bark_birch_base3 (bark_brown_02 darkened: fissured base of an old birch), bark_log3 (bark_brown_02),
rock3 (mossy_rock for boulders / outcrops) and lichen3 (lichen_rock).
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image
import scipy.ndimage as nd

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SRC = os.path.join(REPO, "assets", "environment", "source", "polyhaven")
TERRAIN_OUT = os.path.join(REPO, "assets", "terrain", "textures")
ENV_OUT = os.path.join(REPO, "assets", "environment", "textures")
PREV = os.path.join(REPO, "docs", "world_visuals01", "surfaces")
SIZE = 2048


def load(aid, kind, size, mode="RGB"):
    """kind: diff | nor_gl | arm | disp (Poly Haven names)."""
    d = os.path.join(SRC, aid)
    for f in os.listdir(d):
        fl = f.lower()
        if kind in fl and (kind != "disp" or "disp" in fl):
            im = Image.open(os.path.join(d, f)).convert(mode)
            if im.size != (size, size):
                im = im.resize((size, size), Image.LANCZOS)
            return np.asarray(im, np.float32) / 255.0
    raise FileNotFoundError(aid + " " + kind)


def srgb_to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def grade(rgb, mul=(1, 1, 1), sat=1.0, gamma=1.0, lift=0.0):
    """Colour grade in linear light: per-channel gain, saturation, gamma, lift."""
    lin = srgb_to_lin(rgb)
    lum = (lin * np.array([0.2126, 0.7152, 0.0722], np.float32)).sum(axis=2, keepdims=True)
    lin = lum + (lin - lum) * sat
    lin = np.clip(lin, 0, None) ** gamma * np.array(mul, np.float32) + lift
    return lin_to_srgb(lin).astype(np.float32)


def periodic_noise(size, period_px, seed, octaves=4):
    """Tileable fbm: band-limited random field built in the frequency domain (wraps by construction)."""
    rng = np.random.default_rng(seed)
    out = np.zeros((size, size), np.float32)
    amp = 1.0
    total = 0.0
    f0 = size / period_px
    fy = np.fft.fftfreq(size)[:, None] * size
    fx = np.fft.fftfreq(size)[None, :] * size
    r = np.sqrt(fx * fx + fy * fy)
    for o in range(octaves):
        f = f0 * (2 ** o)
        spec = np.exp(-((r - f) ** 2) / (2 * (f * 0.5) ** 2))
        ph = rng.uniform(0, 2 * np.pi, (size, size))
        field = np.real(np.fft.ifft2(spec * np.exp(1j * ph)))
        field = (field - field.mean()) / (field.std() + 1e-6)
        out += field * amp
        total += amp
        amp *= 0.5
    out /= total
    return (out - out.min()) / (out.max() - out.min())


def needles(size, count, seed, length_px=(10, 22), cols=((0.42, 0.26, 0.14), (0.52, 0.34, 0.18), (0.33, 0.22, 0.13))):
    """Spruce needle litter drawn as short wrapped strokes: returns (rgb, alpha) layers."""
    rnd = random.Random(seed)
    from PIL import ImageDraw
    S = size
    col = Image.new("RGB", (S, S), (0, 0, 0))
    al = Image.new("L", (S, S), 0)
    dc, da = ImageDraw.Draw(col), ImageDraw.Draw(al)
    for k in range(count):
        x, y = rnd.uniform(0, S), rnd.uniform(0, S)
        a = rnd.uniform(0, math.pi)
        L = rnd.uniform(*length_px)
        c = rnd.choice(cols)
        g = rnd.uniform(0.75, 1.2)
        fill = tuple(int(min(255, ch * g * 255)) for ch in c)
        for ox in (-S, 0, S):
            for oy in (-S, 0, S):
                x0, y0 = x + ox, y + oy
                x1, y1 = x0 + math.cos(a) * L, y0 + math.sin(a) * L
                if -L < x0 < S + L and -L < y0 < S + L:
                    dc.line([(x0, y0), (x1, y1)], fill=fill, width=2)
                    da.line([(x0, y0), (x1, y1)], fill=255, width=2)
    return np.asarray(col, np.float32) / 255, np.asarray(al, np.float32) / 255


def height_normal(h, strength):
    """Tileable normal map (OpenGL, Y up) from a height field."""
    gx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    gy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    n = np.dstack([-gx, gy, np.ones_like(h)])
    return n / np.linalg.norm(n, axis=2, keepdims=True)


def save_terrain(name, alb, height, nrm_rgb, rough):
    h = (height - height.min()) / max(height.max() - height.min(), 1e-6)
    a = np.dstack([np.clip(alb, 0, 1), h])
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(TERRAIN_OUT, "v3_%s_alb_ht.png" % name))
    n = np.dstack([np.clip(nrm_rgb, 0, 1), np.clip(rough, 0, 1)])
    Image.fromarray((n * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(TERRAIN_OUT, "v3_%s_nrm_rgh.png" % name))
    os.makedirs(PREV, exist_ok=True)
    Image.fromarray((np.clip(alb, 0, 1) * 255).astype(np.uint8)).resize((512, 512)).save(
        os.path.join(PREV, "terrain_%s.jpg" % name), quality=88)
    print("TERRAIN", name)


def scan(aid, size, mul=(1, 1, 1), sat=1.0, gamma=1.0, ao_mix=0.5):
    alb = load(aid, "diff", size)
    arm = load(aid, "arm", size)
    alb = alb * (1 - ao_mix + ao_mix * arm[..., 0:1])
    alb = grade(alb, mul, sat, gamma)
    nrm = load(aid, "nor_gl", size)
    try:
        h = load(aid, "disp", size, "L")
    except FileNotFoundError:
        h = alb.mean(axis=2)
    return alb, h, nrm, arm[..., 1]


def terrain(size):
    os.makedirs(TERRAIN_OUT, exist_ok=True)
    # Meadow: grazed grass, a touch less saturated and more olive than the scan (Nordic summer, not lawn).
    alb, h, n, r = scan("leafy_grass", size, mul=(0.95, 1.0, 0.86), sat=0.9)
    save_terrain("meadow", alb, h, n, np.clip(r * 1.05, 0, 1))
    # Rock: grey granite with lichen; slightly cooler and darker so it reads as wet-weathered bedrock, not concrete.
    alb, h, n, r = scan("mossy_rock", size, mul=(0.86, 0.88, 0.86), sat=0.85, ao_mix=0.6)
    save_terrain("rock", alb, h, n, np.clip(r * 1.0 + 0.05, 0, 1))
    alb, h, n, r = scan("forest_ground_04", size, mul=(0.95, 0.92, 0.88), sat=0.9)
    save_terrain("dirt", alb, h, n, r)
    alb, h, n, r = scan("sparse_grass", size, mul=(1.25, 1.18, 0.95), sat=0.8, gamma=0.95)
    save_terrain("heath", alb, h, n, r)
    alb, h, n, r = scan("rocky_trail", size, mul=(0.9, 0.92, 0.95), sat=0.55)
    save_terrain("gravel", alb, h, n, r)

    # Forest floor: feather-moss carpet with humus / needle-litter hollows.
    moss, mh, mn, mr = scan("rocky_terrain_02", size, mul=(0.62, 0.64, 0.36), sat=0.62, gamma=1.05)
    hum, hh, hn, hr = scan("mud_forest", size, mul=(0.95, 0.86, 0.74), sat=0.75)
    nc, na = needles(size, int(size * size / 70), 7, cols=((0.40, 0.29, 0.18), (0.46, 0.34, 0.21), (0.33, 0.25, 0.16), (0.52, 0.42, 0.28)))
    nc = grade(nc, (1, 1, 1), 1.0)
    hum = hum * (1 - na[..., None] * 0.9) + nc * na[..., None] * 0.9
    hh = hh + na * 0.25
    mask = periodic_noise(size, size / 2.0, 11) * 0.45 + periodic_noise(size, size / 7.0, 12) * 0.35 +         periodic_noise(size, size / 24.0, 13) * 0.2
    m = np.clip((mask - 0.36) / 0.3, 0, 1)
    m = m * m * (3 - 2 * m)
    # Moss sits higher than the litter: height blend makes the edge follow the moss cushions.
    hb = np.clip(m + (mh - 0.5) * 0.6, 0, 1)
    hb = np.clip((hb - 0.3) / 0.45, 0, 1)
    # Litter shows through thin moss too: a little needle colour everywhere.
    moss = moss * (1 - 0.35 * na[..., None]) + nc * 0.35 * na[..., None]
    alb = moss * hb[..., None] + hum * (1 - hb[..., None])
    hgt = (mh * 0.6 + 0.4) * hb + hh * 0.5 * (1 - hb)
    nrm = mn * hb[..., None] + hn * (1 - hb[..., None])
    rough = np.clip(mr * hb + hr * (1 - hb), 0.55, 1)
    save_terrain("forest", alb, hgt, nrm, rough)

    # Bog: sphagnum (yellow-green, some red-brown) with wet dark peat hollows.
    sph, sh, sn, sr = scan("rocky_terrain_02", size, mul=(1.0, 0.9, 0.38), sat=0.85, gamma=0.95)
    red = periodic_noise(size, size / 5.0, 21)
    sph = sph * (1 - 0.35 * red[..., None]) + sph * np.array([1.25, 0.75, 0.55], np.float32) * 0.35 * red[..., None]
    peat, ph, pn, pr = scan("mud_forest", size, mul=(0.7, 0.62, 0.5), sat=0.8)
    wm = periodic_noise(size, size / 4.0, 22) * 0.7 + periodic_noise(size, size / 12.0, 23) * 0.3
    w = np.clip((wm - 0.6) / 0.2, 0, 1)
    alb = sph * (1 - w[..., None]) + (peat * 0.8 + sph * 0.2) * w[..., None]
    hgt = sh * (1 - w) + ph * 0.3 * w
    nrm = sn * (1 - w[..., None]) + np.array([0.5, 0.5, 1.0], np.float32) * w[..., None]
    rough = np.clip(sr * (1 - w) + 0.18 * w, 0, 1)
    save_terrain("bog", alb, hgt, nrm, rough)

    # Asphalt: the project texture at the common size.
    a = Image.open(os.path.join(TERRAIN_OUT, "asphalt_alb_ht.png")).convert("RGBA").resize((size, size), Image.LANCZOS)
    b = Image.open(os.path.join(TERRAIN_OUT, "asphalt_nrm_rgh.png")).convert("RGBA").resize((size, size), Image.LANCZOS)
    a.save(os.path.join(TERRAIN_OUT, "v3_asphalt_alb_ht.png"))
    b.save(os.path.join(TERRAIN_OUT, "v3_asphalt_nrm_rgh.png"))
    print("TERRAIN asphalt")


def save_env(name, alb, nrm, size=1024):
    os.makedirs(ENV_OUT, exist_ok=True)
    Image.fromarray((np.clip(alb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").resize((size, size), Image.LANCZOS).save(
        os.path.join(ENV_OUT, name + "_alb.png"))
    Image.fromarray((np.clip(nrm, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").resize((size, size), Image.LANCZOS).save(
        os.path.join(ENV_OUT, name + "_nrm.png"))
    os.makedirs(PREV, exist_ok=True)
    Image.fromarray((np.clip(alb, 0, 1) * 255).astype(np.uint8)).resize((384, 384)).save(
        os.path.join(PREV, "env_%s.jpg" % name), quality=88)
    print("ENV", name)


def bark(size=2048):
    alb, h, n, r = scan("pine_bark", size)
    lum = alb.mean(axis=2, keepdims=True)
    # Old Scots pine base: thick grey-brown plates, orange only deep in the fissures.
    low = grade(alb * 0.45 + lum * np.array([0.95, 0.85, 0.75], np.float32) * 0.55, (0.78, 0.74, 0.70), 0.75)
    save_env("bark_pine3_lower", low, n)
    # Upper stem: thin flaking orange bark (the "flame" of a Scots pine), smoother relief.
    up = grade(nd.uniform_filter(alb, size=(3, 3, 1)), (1.25, 0.88, 0.62), 1.15, 0.95)
    flat = n * 0.55 + np.array([0.5, 0.5, 1.0], np.float32) * 0.45
    save_env("bark_pine3_upper", up, flat)
    # Norway spruce: thin grey-brown bark of small round scales - the pine plates at half size, greyed, a hint of red.
    half = lambda x: np.tile(np.asarray(Image.fromarray((np.clip(x, 0, 1) * 255).astype(np.uint8)).resize(
        (size // 2, size // 2), Image.LANCZOS), np.float32) / 255, (2, 2, 1))  # noqa: E731
    sp = grade(half(alb) * 0.35 + half(lum.repeat(3, axis=2)) * 0.65, (0.62, 0.55, 0.5), 0.8, 1.0)
    save_env("bark_spruce3", sp, half(n))
    alb, h, n, r = scan("bark_brown_02", size)
    save_env("bark_birch_base3", grade(alb, (0.78, 0.77, 0.76), 0.35, 1.15), n)
    save_env("bark_log3", grade(alb, (0.9, 0.86, 0.8), 0.8), n)


def rocks(size=2048):
    alb, h, n, r = scan("mossy_rock", size, mul=(0.9, 0.9, 0.88), sat=0.85, ao_mix=0.6)
    save_env("rock3", alb, n)
    alb, h, n, r = scan("lichen_rock", size, mul=(1.0, 1.0, 1.0), sat=0.8)
    save_env("lichen3", alb, n)


def main():
    global SIZE
    argv = sys.argv[1:]
    only = None
    for i, a in enumerate(argv):
        if a.startswith("--only="):
            only = a.split("=", 1)[1].split(",")
        elif a == "--size":
            SIZE = int(argv[i + 1])
    if only is None or "terrain" in only:
        terrain(SIZE)
    if only is None or "bark" in only:
        bark()
    if only is None or "rock" in only:
        rocks()


if __name__ == "__main__":
    main()
