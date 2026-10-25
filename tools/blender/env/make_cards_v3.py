"""WORLD-VISUALS-01 foliage card atlases (system Python 3 + numpy + Pillow + scipy):

  python tools/blender/env/make_cards_v3.py [--only spruce,pine,birch,ground,bush] [--preview]

Writes assets/environment/textures/<name>_alb.png (straight alpha, colour bled into the transparent area so mip maps do not
darken the edges) and <name>_nrm.png (OpenGL tangent space, per sprig orientation) for:

  spruce3   2x2 atlas, Norway spruce branch sprays seen from above (comb-type branchlets) - from the scanned fir sprigs of
            Poly Haven fir_tree_01 (CC0), graded to spruce colour
  pine3     2x2 atlas, Scots pine branch ends with brush-like needle tufts - from pine_tree_01's sprig (CC0), glaucous grade
  birch3    2x2 atlas, hanging birch twigs with small serrated leaves (drawn)
  ground3   4x2 atlas of side-view ground plants for the particle grass (drawn): 0 meadow grass, 1 meadow grass with flowers,
            2 wavy hair-grass (smyle), 3 heather, 4 bilberry, 5 lingonberry, 6 fern, 7 sedge / cotton grass
  bush3     2x2 atlas, side-view shrub cards: 0 willow / sallow, 1 juniper, 2 rowan sapling, 3 dense birch scrub

Every card is reproducible from its seed. Inspect the --preview contact sheet (docs/world_visuals01/cards/).
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
import scipy.ndimage as nd

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SRC = os.path.join(REPO, "assets", "environment", "source", "polyhaven")
OUT = os.path.join(REPO, "assets", "environment", "textures")
PREV = os.path.join(REPO, "docs", "world_visuals01", "cards")


# ------------------------------------------------------------------ canvas
class Canvas:
    """Straight-alpha RGB + alpha + tangent-space normal, painted back to front."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.rgb = np.zeros((h, w, 3), np.float32)
        self.a = np.zeros((h, w), np.float32)
        self.n = np.zeros((h, w, 3), np.float32)
        self.n[..., 2] = 1.0

    def over(self, rgb, a, n, x0=0, y0=0):
        """Composites a layer (arrays of the layer's size) at x0, y0."""
        h, w = a.shape
        xa, ya = max(x0, 0), max(y0, 0)
        xb, yb = min(x0 + w, self.w), min(y0 + h, self.h)
        if xb <= xa or yb <= ya:
            return
        sl = (slice(ya, yb), slice(xa, xb))
        ls = (slice(ya - y0, yb - y0), slice(xa - x0, xb - x0))
        la = a[ls][..., None]
        self.rgb[sl] = rgb[ls] * la + self.rgb[sl] * (1 - la)
        self.n[sl] = n[ls] * la + self.n[sl] * (1 - la)
        self.a[sl] = a[ls] + self.a[sl] * (1 - a[ls])

    def save(self, name, downscale=1):
        rgb, a, n = self.rgb, self.a, self.n
        if downscale > 1:
            # Premultiplied downsampling keeps edges clean.
            pre = np.dstack([rgb * a[..., None], a, n * a[..., None]])
            k = downscale
            H, W = a.shape[0] // k, a.shape[1] // k
            pre = pre[:H * k, :W * k].reshape(H, k, W, k, -1).mean(axis=(1, 3))
            a = pre[..., 3]
            safe = np.maximum(a, 1e-4)[..., None]
            rgb = pre[..., 0:3] / safe
            n = pre[..., 4:7] / safe
        rgb, n = bleed(rgb, a), bleed(n, a)
        n = n / np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-4)
        alb = np.dstack([np.clip(rgb, 0, 1), np.clip(a, 0, 1)])
        Image.fromarray((alb * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + "_alb.png"))
        nrm = np.clip(n * 0.5 + 0.5, 0, 1)
        # Roughness in alpha (Terrain-style packing is not used by the foliage shader; keep 1).
        Image.fromarray((nrm * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, name + "_nrm.png"))
        return alb


def bleed(rgb, a, thr=0.02):
    """Fills transparent texels with the colour of the nearest opaque one (no dark mip fringes)."""
    mask = a < thr
    if not mask.any() or mask.all():
        return rgb
    idx = nd.distance_transform_edt(mask, return_distances=False, return_indices=True)
    out = rgb[idx[0], idx[1]]
    return out


# ------------------------------------------------------------------ sprigs (scanned twig atlases)
def load_sprigs(model, boxes, grade, yellow_fix=0.0):
    d = np.asarray(Image.open(os.path.join(SRC, model, model + "_twig_diff_2k.jpg")).convert("RGB"), np.float32) / 255
    al = np.asarray(Image.open(os.path.join(SRC, model, model + "_twig_alpha_2k.jpg")).convert("L"), np.float32) / 255
    out = []
    for (x0, y0, x1, y1) in boxes:
        rgb = d[y0:y1, x0:x1].copy()
        a = al[y0:y1, x0:x1].copy()
        # Neighbouring geometry of the scan atlas (cones, bark) can reach into the box: keep the largest piece only.
        lab, n = nd.label(nd.binary_dilation(a > 0.5, iterations=2))
        if n > 1:
            sizes = nd.sum(np.ones_like(a), lab, index=range(1, n + 1))
            a = a * (lab == (int(np.argmax(sizes)) + 1))
        if yellow_fix > 0:
            # Brown / yellow dead needles: most become green (a few stay).
            r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
            yel = np.clip((r - g * 0.92) * 6.0, 0, 1) * yellow_fix
            lum = rgb.mean(axis=2, keepdims=True)
            green = np.dstack([lum * 0.78, lum * 1.0, lum * 0.66])
            rgb = rgb * (1 - yel[..., None]) + green * yel[..., None]
        rgb = grade(rgb)
        out.append((bleed(rgb, a), a))
    return out


def place(canvas, sprig, base, angle, length, roll=0.0, shade=1.0, hue=None, flip=False):
    """Pastes a sprig with its stem base at `base` (px), pointing at `angle` (rad, 0 = up, clockwise), `length` px long;
    `roll` turns it about its own axis (width foreshortened by cos(roll), normal tilted)."""
    rgb, a = sprig
    sh, sw = a.shape
    s = length / sh
    w = max(math.cos(roll), 0.25)
    if flip:
        rgb, a = rgb[:, ::-1], a[:, ::-1]
    r = np.array([math.cos(angle), math.sin(angle)])
    u = np.array([math.sin(angle), -math.cos(angle)])
    M = np.column_stack([r * s * w, -u * s])
    Mi = np.linalg.inv(M)
    B = np.array([sw * 0.5, sh])
    # Bounding box of the transformed sprig.
    corners = [np.array(base) + M @ (np.array(c, float) - B) for c in ((0, 0), (sw, 0), (0, sh), (sw, sh))]
    xs = [c[0] for c in corners]
    ys = [c[1] for c in corners]
    x0, y0 = int(math.floor(min(xs))) - 1, int(math.floor(min(ys))) - 1
    x1, y1 = int(math.ceil(max(xs))) + 1, int(math.ceil(max(ys))) + 1
    W, H = x1 - x0, y1 - y0
    if W <= 1 or H <= 1:
        return
    # Inverse map: src = B + Mi (dest - base); PIL wants src = a x + b y + c for dest pixel (x, y) in the layer.
    off = B + Mi @ (np.array([x0, y0], float) - np.array(base))
    coeffs = (Mi[0, 0], Mi[0, 1], off[0], Mi[1, 0], Mi[1, 1], off[1])
    layers = []
    for ch in range(3):
        im = Image.fromarray(rgb[..., ch].astype(np.float32), "F")
        layers.append(np.asarray(im.transform((W, H), Image.AFFINE, coeffs, Image.BILINEAR), np.float32))
    am = np.asarray(Image.fromarray(a.astype(np.float32), "F").transform((W, H), Image.AFFINE, coeffs, Image.BILINEAR),
                    np.float32)
    col = np.dstack(layers) * shade
    if hue is not None:
        col = col * np.array(hue, np.float32)
    rts = np.array([r[0], -r[1]])
    n = np.array([math.sin(roll) * rts[0], math.sin(roll) * rts[1], math.cos(roll)], np.float32)
    nl = np.broadcast_to(n, (H, W, 3)).copy()
    canvas.over(col, np.clip(am, 0, 1), nl, x0, y0)


def grade_spruce(rgb):
    lum = rgb.mean(axis=2, keepdims=True)
    tgt = np.array([0.60, 0.80, 0.55], np.float32)
    out = rgb * 0.45 + lum * tgt * 0.55
    # Norway spruce: deep green, a little darker and less yellow than the fir scan (target mean ~0.12 / 0.22 / 0.09).
    return np.clip(out * np.array([0.66, 0.98, 0.58], np.float32), 0, 1)


def grade_pine(rgb):
    lum = rgb.mean(axis=2, keepdims=True)
    out = rgb * 0.55 + lum * np.array([0.78, 0.92, 0.80], np.float32) * 0.45
    return np.clip(out * np.array([0.84, 0.92, 0.84], np.float32), 0, 1)


FIR_BOXES = [(623, 816, 1323, 1591), (1296, 923, 1964, 1703), (1333, 79, 1924, 758), (384, 92, 881, 641),
             (1007, 529, 1295, 822), (789, 589, 944, 786), (1100, 199, 1209, 471)]
PINE_BOXES = [(70, 87, 453, 908), (1331, 698, 1921, 1064)]


def stick(canvas, p0, p1, w0, w1, rgb=(0.23, 0.17, 0.12)):
    """Woody axis drawn as a tapered quad strip (supersampled canvas)."""
    img = Image.new("L", (canvas.w, canvas.h), 0)
    dr = ImageDraw.Draw(img)
    p0, p1 = np.array(p0, float), np.array(p1, float)
    d = p1 - p0
    L = np.linalg.norm(d)
    if L < 1:
        return
    t = d / L
    nrm = np.array([-t[1], t[0]])
    poly = [tuple(p0 + nrm * w0), tuple(p1 + nrm * w1), tuple(p1 - nrm * w1), tuple(p0 - nrm * w0)]
    dr.polygon(poly, fill=255)
    a = np.asarray(img, np.float32) / 255
    col = np.broadcast_to(np.array(rgb, np.float32), (canvas.h, canvas.w, 3)).copy()
    canvas.over(col, a, np.broadcast_to(np.array([0, 0, 1], np.float32), (canvas.h, canvas.w, 3)).copy())


def spruce_spray(seed, size=1024):
    """Norway spruce branch end from above: main axis bottom -> top, comb branchlets both sides, denser and darker toward
    the stem (older needles), a leading shoot at the tip."""
    rnd = random.Random(seed)
    sprigs = load_sprigs("fir_tree_01", FIR_BOXES, grade_spruce)
    c = Canvas(size, size)
    base = np.array([size * 0.5 + rnd.uniform(-20, 20), size * 0.98])
    tip = np.array([size * 0.5 + rnd.uniform(-60, 60), size * 0.05])
    # Slight curve of the main axis.
    bend = rnd.uniform(-0.12, 0.12) * size

    def axis(t):
        p = base + (tip - base) * t
        return p + np.array([math.sin(t * math.pi) * bend, 0])
    n_side = rnd.randint(9, 12)
    items = []
    for i in range(n_side):
        t = 0.1 + 0.82 * (i + rnd.uniform(-0.2, 0.2)) / n_side
        for side in (-1, 1):
            if rnd.random() < 0.12:
                continue
            ang = side * math.radians(rnd.uniform(38, 68)) * (1.0 - 0.25 * t)
            ln = size * (0.40 - 0.24 * t) * rnd.uniform(0.8, 1.15)
            roll = math.radians(rnd.uniform(-45, 45))
            depth = rnd.random()
            shade = (0.68 + 0.32 * t) * rnd.uniform(0.9, 1.08)
            items.append((depth, axis(t), ang, ln, roll, shade, rnd.randrange(len(sprigs)), rnd.random() < 0.5))
    items.sort(key=lambda it: it[0])
    # Inner (back) sprigs, then the axis, then the front ones.
    for it in items[:len(items) // 2]:
        place(c, sprigs[it[6]], it[1], it[2], it[3], it[4], it[5], flip=it[7])
    pts = [axis(k / 12) for k in range(13)]
    for k in range(12):
        stick(c, pts[k], pts[k + 1], 6.5 * (1 - k / 13) + 1.5, 6.5 * (1 - (k + 1) / 13) + 1.5)
    for it in items[len(items) // 2:]:
        place(c, sprigs[it[6]], it[1], it[2], it[3], it[4], it[5], flip=it[7])
    lead = axis(0.93)
    place(c, sprigs[0], lead, math.radians(rnd.uniform(-8, 8)), size * 0.2, 0.0, 1.05)
    return c


def pine_tuft(seed, size=1024):
    """Scots pine branch end: a short woody branch carrying 4-7 brush-like needle tufts that turn upward."""
    rnd = random.Random(seed)
    sprigs = load_sprigs("pine_tree_01", PINE_BOXES, grade_pine, yellow_fix=0.75)
    c = Canvas(size, size)
    root = np.array([size * 0.5, size * 0.99])
    items = []
    n = rnd.randint(7, 9)
    for i in range(n):
        f = (i + 0.5) / n
        ang = math.radians(-42 + 84 * f + rnd.uniform(-8, 8))
        reach = size * rnd.uniform(0.14, 0.34)
        fork = root + np.array([math.sin(ang), -math.cos(ang)]) * reach
        ln = min(size * rnd.uniform(0.36, 0.5), fork[1] - size * 0.03)
        items.append((rnd.random(), fork, ang * 0.55, ln, math.radians(rnd.uniform(-40, 40)), rnd.uniform(0.82, 1.05), i))
    for it in sorted(items, key=lambda x: x[0]):
        stick(c, root, it[1], 7, 4, rgb=(0.30, 0.20, 0.14))
    for it in sorted(items, key=lambda x: x[0]):
        sp = sprigs[0] if rnd.random() < 0.75 else sprigs[1]
        place(c, sp, it[1], it[2], it[3], it[4], it[5], flip=rnd.random() < 0.5)
    return c


# ------------------------------------------------------------------ drawn foliage
def leaf_poly(cx, cy, length, width, ang, serr=10, tip=1.0, rnd=None):
    """Ovate-triangular serrated leaf (birch type), base at (cx, cy), pointing at ang (rad, 0 = up)."""
    pts = []
    m = 18
    for k in range(m + 1):
        t = k / m
        # Widest at 30 % of the length, pointed tip.
        half = width * 0.5 * math.sin(math.pi * min(1.0, t / 0.92) ** 0.75) * (1.15 - 0.3 * t)
        if serr and 0.1 < t < 0.95 and k % 2 == 1:
            half *= 1.12
        pts.append((t * length, half))
    poly = [(x, y) for x, y in pts] + [(x, -y) for x, y in reversed(pts)]
    ca, sa = math.cos(ang), math.sin(ang)
    out = []
    for x, y in poly:
        # leaf x along its axis (up), y across.
        dx = y * ca + x * sa
        dy = y * sa - x * ca
        out.append((cx + dx, cy + dy))
    return out


def draw_layer(size, fn):
    """Runs fn(draw_rgba, draw_normal) on a supersampled RGBA layer; returns (rgb, a, n) arrays."""
    col = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    nim = Image.new("RGB", (size, size), (128, 128, 255))
    fn(ImageDraw.Draw(col), ImageDraw.Draw(nim))
    arr = np.asarray(col, np.float32) / 255
    n = np.asarray(nim, np.float32) / 255 * 2 - 1
    return arr[..., :3], arr[..., 3], n


def ncol(nx, ny):
    nz = math.sqrt(max(0.0, 1 - nx * nx - ny * ny))
    return (int((nx * 0.5 + 0.5) * 255), int((ny * 0.5 + 0.5) * 255), int((nz * 0.5 + 0.5) * 255))


def birch_twigs(seed, size=1024):
    """Hanging birch twigs (weeping habit of Betula pendula), alternate small leaves, light and dark leaf tones."""
    rnd = random.Random(seed)
    c = Canvas(size, size)

    def paint(dc, dn):
        stems = []
        top = np.array([size * 0.5 + rnd.uniform(-60, 60), size * 0.02])
        for k in range(rnd.randint(5, 7)):
            p = top + np.array([rnd.uniform(-size * 0.32, size * 0.32), rnd.uniform(0, size * 0.18)])
            pts = [p.copy()]
            d = np.array([rnd.uniform(-0.25, 0.25), 1.0])
            for j in range(14):
                d = d / np.linalg.norm(d)
                p = p + d * size * 0.052
                d = d + np.array([rnd.uniform(-0.12, 0.12), 0.05])
                pts.append(p.copy())
            stems.append(pts)
        for pts in stems:
            for j in range(len(pts) - 1):
                dc.line([tuple(pts[j]), tuple(pts[j + 1])], fill=(62, 40, 32, 255), width=max(2, int(6 - j * 0.3)))
        for pts in stems:
            for j in range(1, len(pts)):
                for side in (-1, 1):
                    if rnd.random() < 0.25:
                        continue
                    p = pts[j]
                    ang = math.pi + side * math.radians(rnd.uniform(30, 75))  # pointing down and out
                    L = size * rnd.uniform(0.045, 0.07)
                    stalk = p + np.array([math.sin(ang), -math.cos(ang)]) * L * 0.25
                    dc.line([tuple(p), tuple(stalk)], fill=(70, 60, 30, 255), width=2)
                    g = rnd.uniform(0.82, 1.12)
                    lc = (int(88 * g), int(124 * g), int(42 * g), 255) if rnd.random() < 0.7 else (int(70 * g), int(104 * g), int(34 * g), 255)
                    poly = leaf_poly(stalk[0], stalk[1], L, L * 0.72, ang)
                    dc.polygon(poly, fill=lc)
                    roll = rnd.uniform(-0.6, 0.6)
                    dn.polygon(poly, fill=ncol(roll * math.cos(ang), roll * math.sin(ang)))
                    # Midrib.
                    tipp = stalk + np.array([math.sin(ang), -math.cos(ang)]) * L * 0.9
                    dc.line([tuple(stalk), tuple(tipp)], fill=(int(lc[0] * 1.15), int(lc[1] * 1.12), int(lc[2] * 1.1), 255), width=1)
    rgb, a, n = draw_layer(size, paint)
    c.over(rgb, a, n)
    return c


def blades(dc, dn, rnd, x, ybase, count, hmin, hmax, spread, cols, width=(3, 6), curl=0.35, seed_heads=0.0,
           head_col=(200, 190, 160)):
    """Grass blades from a tussock base: tapered curved polygons."""
    for k in range(count):
        h = rnd.uniform(hmin, hmax)
        x0 = x + rnd.uniform(-spread, spread)
        lean = rnd.uniform(-0.55, 0.55)
        w = rnd.uniform(*width)
        col = rnd.choice(cols)
        g = rnd.uniform(0.8, 1.15)
        col = tuple(int(min(255, ch * g)) for ch in col) + (255,)
        pts_l, pts_r = [], []
        m = 10
        for j in range(m + 1):
            t = j / m
            px = x0 + lean * h * t + curl * lean * h * t * t
            py = ybase - h * t + curl * abs(lean) * h * t * t * 0.6
            ww = w * (1 - t) ** 0.8 + 0.5
            pts_l.append((px - ww, py))
            pts_r.append((px + ww, py))
        poly = pts_l + pts_r[::-1]
        dc.polygon(poly, fill=col)
        dn.polygon(poly, fill=ncol(rnd.uniform(-0.5, 0.5), 0.1))
        if seed_heads > 0 and rnd.random() < seed_heads:
            hx, hy = pts_l[-1][0], pts_l[-1][1]
            for s in range(rnd.randint(6, 14)):
                dx, dy = rnd.uniform(-10, 10), rnd.uniform(0, 34)
                dc.ellipse([hx + dx - 2.5, hy + dy - 4, hx + dx + 2.5, hy + dy + 4], fill=head_col + (255,))


def ground_tile(kind, seed, size=512):
    """Side-view plant card (base at the bottom edge) for the particle ground cover."""
    rnd = random.Random(seed)
    c = Canvas(size, size)
    yb = size - 2

    def paint(dc, dn):
        cx = size * 0.5
        if kind == "grass":
            blades(dc, dn, rnd, cx, yb, 120, size * 0.35, size * 0.95, size * 0.28,
                   [(78, 104, 46), (92, 118, 52), (70, 96, 40), (110, 124, 62), (124, 128, 70)], curl=0.45)
        elif kind == "grass_flowers":
            blades(dc, dn, rnd, cx, yb, 95, size * 0.3, size * 0.85, size * 0.3,
                   [(82, 108, 48), (96, 120, 56), (112, 126, 64)], curl=0.45, seed_heads=0.25, head_col=(170, 150, 120))
            for k in range(rnd.randint(5, 8)):
                fx = cx + rnd.uniform(-size * 0.32, size * 0.32)
                fy = yb - rnd.uniform(size * 0.45, size * 0.85)
                dc.line([(fx, yb), (fx + rnd.uniform(-8, 8), fy)], fill=(80, 104, 46, 255), width=3)
                kind_f = rnd.random()
                if kind_f < 0.5:  # buttercup
                    for p in range(5):
                        a = p / 5 * 2 * math.pi
                        dc.ellipse([fx + math.cos(a) * 7 - 6, fy + math.sin(a) * 7 - 6, fx + math.cos(a) * 7 + 6,
                                    fy + math.sin(a) * 7 + 6], fill=(232, 196, 40, 255))
                elif kind_f < 0.8:  # clover / yarrow white
                    dc.ellipse([fx - 11, fy - 9, fx + 11, fy + 9], fill=(236, 232, 214, 255))
                else:  # harebell / cranesbill
                    dc.ellipse([fx - 8, fy - 8, fx + 8, fy + 8], fill=(130, 112, 190, 255))
        elif kind == "hairgrass":
            blades(dc, dn, rnd, cx, yb, 160, size * 0.25, size * 0.6, size * 0.3,
                   [(84, 100, 42), (98, 108, 50), (76, 92, 38)], width=(1.5, 3), curl=0.8)
            for k in range(rnd.randint(10, 16)):
                fx = cx + rnd.uniform(-size * 0.3, size * 0.3)
                top = yb - rnd.uniform(size * 0.6, size * 0.92)
                dc.line([(fx, yb), (fx + rnd.uniform(-20, 20), top)], fill=(112, 98, 80, 255), width=2)
                for s in range(14):
                    sx = fx + rnd.uniform(-26, 26)
                    sy = top + rnd.uniform(0, 70)
                    dc.line([(fx, sy - 10), (sx, sy)], fill=(128, 108, 108, 255), width=1)
                    dc.ellipse([sx - 2, sy - 2, sx + 2, sy + 2], fill=(140, 118, 116, 255))
        elif kind == "heather":
            # Woody stems branching upward, covered by tiny scale leaves; some tips in flower.
            for k in range(rnd.randint(26, 34)):
                x0 = cx + rnd.uniform(-size * 0.3, size * 0.3)
                pts = [(x0, yb)]
                d = np.array([rnd.uniform(-0.6, 0.6), -1.0])
                p = np.array([x0, yb], float)
                for j in range(9):
                    d = d / np.linalg.norm(d)
                    p = p + d * size * rnd.uniform(0.045, 0.075)
                    d = d + np.array([rnd.uniform(-0.25, 0.25), -0.08])
                    pts.append(tuple(p))
                dc.line(pts, fill=(78, 58, 44, 255), width=2)
                flower = rnd.random() < 0.3
                for j, q in enumerate(pts[2:]):
                    for s in range(26):
                        lx, ly = q[0] + rnd.uniform(-13, 13), q[1] + rnd.uniform(-12, 12)
                        tip = j >= len(pts) - 5
                        if flower and tip and rnd.random() < 0.7:
                            col = (int(128 * rnd.uniform(0.85, 1.1)), int(92 * rnd.uniform(0.85, 1.1)), int(112 * rnd.uniform(0.85, 1.1)), 255)
                        else:
                            g = rnd.uniform(0.75, 1.15)
                            col = (int(66 * g), int(80 * g), int(46 * g), 255)
                        dc.ellipse([lx - 2, ly - 3, lx + 2, ly + 3], fill=col)
                        dn.ellipse([lx - 2, ly - 3, lx + 2, ly + 3], fill=ncol(rnd.uniform(-0.6, 0.6), rnd.uniform(-0.3, 0.6)))
        elif kind in ("bilberry", "lingonberry"):
            tall = kind == "bilberry"
            n_st = rnd.randint(18, 24) if tall else rnd.randint(16, 22)
            for k in range(n_st):
                x0 = cx + rnd.uniform(-size * 0.3, size * 0.3)
                h = rnd.uniform(0.5, 0.95) * size if tall else rnd.uniform(0.25, 0.5) * size
                p = np.array([x0, yb], float)
                d = np.array([rnd.uniform(-0.4, 0.4), -1.0])
                pts = [tuple(p)]
                for j in range(6):
                    d = d / np.linalg.norm(d)
                    p = p + d * h / 6
                    # Bilberry stems are angular: zig-zag.
                    d = d + np.array([rnd.choice([-0.35, 0.35]) if tall else rnd.uniform(-0.2, 0.2), 0])
                    pts.append(tuple(p))
                dc.line(pts, fill=(70, 110, 46, 255) if tall else (90, 62, 44, 255), width=4 if tall else 3)
                for q in pts[1:]:
                    for s in range(5 if tall else 5):
                        ang = rnd.uniform(-1.5, 1.5)
                        L = rnd.uniform(18, 28) if tall else rnd.uniform(14, 20)
                        g = rnd.uniform(0.8, 1.15)
                        col = (int(72 * g), int(118 * g), int(40 * g), 255) if tall else (int(40 * g), int(70 * g), int(30 * g), 255)
                        poly = leaf_poly(q[0] + rnd.uniform(-6, 6), q[1] + rnd.uniform(-8, 8), L, L * (0.75 if tall else 0.7), ang, serr=0)
                        dc.polygon(poly, fill=col)
                        dn.polygon(poly, fill=ncol(math.sin(ang) * 0.5, rnd.uniform(0.0, 0.5)))
                if not tall and rnd.random() < 0.45:
                    q = pts[-1]
                    for s in range(rnd.randint(2, 5)):
                        bx, by = q[0] + rnd.uniform(-12, 12), q[1] + rnd.uniform(-6, 14)
                        dc.ellipse([bx - 6, by - 6, bx + 6, by + 6], fill=(178, 28, 30, 255))
                if tall and rnd.random() < 0.25:
                    q = pts[rnd.randint(2, len(pts) - 1)]
                    dc.ellipse([q[0] - 6, q[1] - 2, q[0] + 6, q[1] + 10], fill=(40, 46, 86, 255))
        elif kind == "fern":
            # Lady fern / buckler fern clump: 9-12 arching fronds, many narrow pinnae, back fronds darker.
            fronds = []
            for k in range(rnd.randint(9, 12)):
                fronds.append((rnd.random(), math.radians(rnd.uniform(-55, 55)), size * rnd.uniform(0.45, 0.8)))
            for depth, ang, L in sorted(fronds):
                p = np.array([cx + rnd.uniform(-14, 14), yb], float)
                m = 48
                pts = []
                for j in range(m + 1):
                    t = j / m
                    a2 = ang * (1 + 1.1 * t * t)
                    pts.append(p + np.array([math.sin(a2), -math.cos(a2)]) * L * t * (1 - 0.18 * t))
                g = rnd.uniform(0.85, 1.1) * (0.78 + 0.25 * depth)
                dc.line([tuple(q) for q in pts], fill=(int(96 * g), int(112 * g), int(52 * g), 255), width=3)
                for j in range(6, m):
                    t = j / m
                    q = pts[j]
                    dvec = pts[min(j + 1, m)] - pts[j - 1]
                    dvec = dvec / (np.linalg.norm(dvec) + 1e-6)
                    side = np.array([-dvec[1], dvec[0]])
                    pl = L * 0.13 * math.sin(math.pi * min(1.0, (t - 0.08) / 0.95)) + 2
                    for sgn in (-1, 1):
                        tipq = q + side * sgn * pl + dvec * pl * 0.45
                        mid = q + (tipq - q) * 0.42
                        perp = np.array([-(tipq - q)[1], (tipq - q)[0]]) * 0.16
                        poly = [tuple(q), tuple(mid + perp), tuple(tipq), tuple(mid - perp)]
                        h = rnd.uniform(0.92, 1.08)
                        col = (int(64 * g * h), int(104 * g * h), int(36 * g * h), 255)
                        dc.polygon(poly, fill=col)
                        dn.polygon(poly, fill=ncol(sgn * 0.4 * side[0], 0.35))
        elif kind == "sedge":
            blades(dc, dn, rnd, cx, yb, 90, size * 0.4, size * 0.95, size * 0.18,
                   [(96, 112, 58), (110, 120, 66), (84, 100, 52), (128, 120, 74)], width=(2, 4), curl=0.25)
            for k in range(rnd.randint(4, 9)):
                fx = cx + rnd.uniform(-size * 0.22, size * 0.22)
                fy = yb - rnd.uniform(size * 0.55, size * 0.95)
                dc.line([(fx, yb), (fx + rnd.uniform(-10, 10), fy)], fill=(100, 108, 60, 255), width=3)
                for s in range(28):
                    a = rnd.uniform(0, 2 * math.pi)
                    r = rnd.uniform(0, 16)
                    dc.ellipse([fx + math.cos(a) * r - 4, fy + math.sin(a) * r - 4, fx + math.cos(a) * r + 4,
                                fy + math.sin(a) * r + 4], fill=(240, 238, 230, 255))
    S = size * 2
    big = Canvas(S, S)

    def paint2(dc, dn):
        # Draw at 2x for anti-aliasing: scale every coordinate through a wrapper.
        class Scaled:
            def __init__(self, d):
                self.d = d

            def _s(self, pts):
                if pts and isinstance(pts[0], (tuple, list, np.ndarray)):
                    return [(x * 2, y * 2) for x, y in pts]
                return [v * 2 for v in pts]

            def line(self, pts, fill=None, width=1):
                self.d.line(self._s(list(pts)), fill=fill, width=int(width * 2))

            def polygon(self, pts, fill=None):
                self.d.polygon(self._s(list(pts)), fill=fill)

            def ellipse(self, box, fill=None):
                self.d.ellipse(self._s(list(box)), fill=fill)
        paint(Scaled(dc), Scaled(dn))
    rgb, a, n = draw_layer(S, paint2)
    big.over(rgb, a, n)
    return big


def shrub_tile(kind, seed, size=1024):
    """Side-view shrub cards for bush meshes."""
    rnd = random.Random(seed)
    c = Canvas(size, size)
    if kind == "juniper":
        sprigs = load_sprigs("fir_tree_01", FIR_BOXES, lambda rgb: np.clip(
            (rgb * 0.4 + rgb.mean(axis=2, keepdims=True) * np.array([0.62, 0.78, 0.66]) * 0.6) * np.array([0.88, 0.98, 0.84]), 0, 1))
        base = np.array([size * 0.5, size * 0.99])
        for k in range(46):
            t = rnd.random()
            p = base + np.array([rnd.uniform(-0.18, 0.18) * size * (1 - t * 0.6), -t * size * 0.75])
            place(c, sprigs[rnd.randrange(len(sprigs))], p, math.radians(rnd.uniform(-35, 35)), size * rnd.uniform(0.18, 0.3),
                  math.radians(rnd.uniform(-50, 50)), 0.75 + 0.3 * t)
        return c
    if kind == "rowan":
        def paint(dc, dn):
            base = (size * 0.5, size * 0.99)
            for k in range(3):
                top = (size * 0.5 + rnd.uniform(-size * 0.2, size * 0.2), size * rnd.uniform(0.1, 0.3))
                dc.line([base, top], fill=(96, 84, 70, 255), width=10)
                for j in range(5):
                    t = 0.35 + 0.13 * j
                    q = (base[0] + (top[0] - base[0]) * t, base[1] + (top[1] - base[1]) * t)
                    for sgn in (-1, 1):
                        ang = sgn * math.radians(rnd.uniform(50, 75))
                        L = size * rnd.uniform(0.18, 0.26)
                        e = (q[0] + math.sin(ang) * L, q[1] - math.cos(ang) * L)
                        dc.line([q, e], fill=(110, 120, 60, 255), width=4)
                        for m in range(7):  # pinnate leaf: leaflets along the rachis
                            tt = (m + 1) / 8
                            lq = (q[0] + (e[0] - q[0]) * tt, q[1] + (e[1] - q[1]) * tt)
                            for s2 in (-1, 1):
                                la = ang + s2 * math.radians(70)
                                g = rnd.uniform(0.85, 1.15)
                                poly = leaf_poly(lq[0], lq[1], L * 0.28, L * 0.1, la, serr=8)
                                dc.polygon(poly, fill=(int(70 * g), int(112 * g), int(40 * g), 255))
                                dn.polygon(poly, fill=ncol(rnd.uniform(-0.5, 0.5), 0.3))
        rgb, a, n = draw_layer(size, paint)
        c.over(rgb, a, n)
        return c
    # willow / birch scrub: many oval leaves on upright twigs
    def paint(dc, dn):
        base = (size * 0.5, size * 0.99)
        n_st = 14 if kind == "willow" else 18
        for k in range(n_st):
            ang = math.radians(rnd.uniform(-34, 34))
            L = size * rnd.uniform(0.5, 0.8)
            pts = [base]
            p = np.array(base, float)
            for j in range(8):
                a2 = ang * (1 + 0.15 * j)
                p = p + np.array([math.sin(a2), -math.cos(a2)]) * L / 8
                pts.append(tuple(p))
            dc.line(pts, fill=(86, 70, 54, 255), width=6)
            for q in pts[2:]:
                for s in range(6):
                    la = rnd.uniform(-2.2, 2.2)
                    if kind == "willow":
                        ll, lw = rnd.uniform(40, 62), rnd.uniform(14, 20)
                        g = rnd.uniform(0.82, 1.15)
                        col = (int(84 * g), int(110 * g), int(64 * g), 255)
                    else:
                        ll, lw = rnd.uniform(26, 36), rnd.uniform(18, 24)
                        g = rnd.uniform(0.82, 1.15)
                        col = (int(88 * g), int(124 * g), int(42 * g), 255)
                    poly = leaf_poly(q[0] + rnd.uniform(-20, 20), q[1] + rnd.uniform(-20, 20), ll, lw, la, serr=6)
                    dc.polygon(poly, fill=col)
                    dn.polygon(poly, fill=ncol(math.sin(la) * 0.4, rnd.uniform(0.0, 0.5)))
    rgb, a, n = draw_layer(size, paint)
    c.over(rgb, a, n)
    return c


def fern_frond(seed, size=1024):
    """One fern frond seen from above (lady fern / male fern type): rachis bottom to top, alternate lanceolate pinnae with
    lobed pinnules, widest at 40 % of the length, tapering to a pointed tip."""
    rnd = random.Random(seed)
    c = Canvas(size, size)

    def paint(dc, dn):
        x0, y0, y1 = size * 0.5, size * 0.99, size * 0.02
        curve = rnd.uniform(-0.06, 0.06) * size
        n = rnd.randint(17, 20)
        g0 = rnd.uniform(0.88, 1.1)

        def rach(t):
            return (x0 + math.sin(t * math.pi) * curve, y0 + (y1 - y0) * t)
        pts = [rach(k / 40) for k in range(41)]
        dc.line(pts, fill=(int(96 * g0), int(118 * g0), int(56 * g0), 255), width=7)
        for i in range(n):
            t = 0.08 + 0.9 * (i + 0.5) / n
            for side in (-1, 1):
                tt = t + (0.012 if side > 0 else 0.0)
                px, py = rach(tt)
                width = math.sin(math.pi * min(1.0, (tt - 0.02) / 0.98) ** 0.8)
                L = size * 0.36 * width * (1.0 if tt > 0.12 else 0.7) * rnd.uniform(0.9, 1.08)
                if L < 6:
                    continue
                ang = math.radians(rnd.uniform(58, 72)) * side
                ux, uy = math.sin(ang), -math.cos(ang)
                vx, vy = -uy, ux
                g = g0 * rnd.uniform(0.9, 1.08)
                col = (int(70 * g), int(118 * g), int(40 * g), 255)
                # Pinna outline: lobed edges (pinnules).
                m = 14
                left, right = [], []
                for k in range(m + 1):
                    f = k / m
                    w = L * 0.06 * math.sin(math.pi * min(1.0, f / 0.95)) ** 0.7 * (1.1 - 0.4 * f)
                    lobe = 0.55 + 0.9 * (0.5 + 0.5 * math.cos(f * m * math.pi))
                    cx, cy = px + ux * L * f, py + uy * L * f
                    left.append((cx + vx * w * lobe, cy + vy * w * lobe))
                    right.append((cx - vx * w * lobe, cy - vy * w * lobe))
                poly = left + right[::-1]
                dc.polygon(poly, fill=col)
                dn.polygon(poly, fill=ncol(side * 0.35 * ux, 0.25))
                dc.line([(px, py), (px + ux * L * 0.95, py + uy * L * 0.95)],
                        fill=(int(col[0] * 1.2), int(col[1] * 1.12), int(col[2] * 1.1), 255), width=2)
    rgb, a, n = draw_layer(size, paint)
    c.over(rgb, a, n)
    return c


def atlas(tiles, cols, rows, tile_px):
    """Packs canvases (any size) into a cols x rows atlas of tile_px tiles; returns the atlas canvas."""
    A = Canvas(cols * tile_px, rows * tile_px)
    for i, t in enumerate(tiles):
        k = t.w // tile_px
        rgb, a, n = t.rgb, t.a, t.n
        if k > 1:
            pre = np.dstack([rgb * a[..., None], a, n * a[..., None]])
            pre = pre.reshape(tile_px, k, tile_px, k, -1).mean(axis=(1, 3))
            a = pre[..., 3]
            safe = np.maximum(a, 1e-4)[..., None]
            rgb, n = pre[..., :3] / safe, pre[..., 4:7] / safe
        x0, y0 = (i % cols) * tile_px, (i // cols) * tile_px
        A.rgb[y0:y0 + tile_px, x0:x0 + tile_px] = rgb
        A.a[y0:y0 + tile_px, x0:x0 + tile_px] = a
        A.n[y0:y0 + tile_px, x0:x0 + tile_px] = n
    return A


def preview(name, alb):
    os.makedirs(PREV, exist_ok=True)
    h, w = alb.shape[:2]
    bg = np.ones((h, w, 3), np.float32) * np.array([0.72, 0.76, 0.82], np.float32)
    out = alb[..., :3] * alb[..., 3:4] + bg * (1 - alb[..., 3:4])
    Image.fromarray((out * 255).astype(np.uint8)).save(os.path.join(PREV, name + ".jpg"), quality=88)


def main():
    argv = sys.argv[1:]
    only = None
    for a in argv:
        if a.startswith("--only="):
            only = a.split("=", 1)[1].split(",")
    want = lambda k: only is None or k in only  # noqa: E731
    jobs = []
    if want("spruce"):
        jobs.append(("spruce3", [spruce_spray(s, 1024) for s in (101, 102, 103, 104)], 2, 2, 512))
    if want("pine"):
        jobs.append(("pine3", [pine_tuft(s, 1024) for s in (201, 202, 203, 204)], 2, 2, 512))
    if want("birch"):
        jobs.append(("birch3", [birch_twigs(s, 1024) for s in (301, 302, 303, 304)], 2, 2, 512))
    if want("ground"):
        kinds = ["grass", "grass_flowers", "hairgrass", "heather", "bilberry", "lingonberry", "fern", "sedge"]
        jobs.append(("ground3", [ground_tile(k, 400 + i, 512) for i, k in enumerate(kinds)], 4, 2, 512))
    if want("fern"):
        jobs.append(("fern3", [fern_frond(s, 1024) for s in (701, 702, 703, 704)], 2, 2, 512))
    if want("bush"):
        jobs.append(("bush3", [shrub_tile(k, 500 + i, 1024) for i, k in enumerate(["willow", "juniper", "rowan", "birch_scrub"])],
                     2, 2, 512))
    for name, tiles, cols, rows, px in jobs:
        A = atlas(tiles, cols, rows, px)
        alb = A.save(name)
        preview(name, alb)
        print("CARD", name, A.w, A.h)


if __name__ == "__main__":
    main()
