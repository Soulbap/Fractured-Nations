"""WORLD-VISUALS-01 trees, saplings and bushes (Blender 5.2, background):

  blender -b --factory-startup --python tools/blender/env/make_trees_v3.py -- [--only spruce_a,pine_a] [--no-preview]

Every library tree id gets a set of variants (variant 0 keeps the old asset name, so the library's scene path stays):

  spruce_a  6  mature Norway spruce: narrow / broad / forest-grown with a dead lower stem / open-grown to the ground /
               drooping comb branches / leaning edge tree               (id 3, collider unchanged)
  spruce_b  3  young spruce, branches to the ground                     (id 4)
  spruce_s  2  spruce sapling shapes                                     (id 22, no collider)
  pine_a    3  middle-aged Scots pine, rounded crown                     (id 1)
  pine_b    3  old Scots pine, flat crown high on a long clear stem      (id 2)
  birch_a   3  single-stem birch, weeping twigs                          (id 5)
  birch_b   2  multi-stem birch (wet ground, edges)                      (id 6)
  birch_s   2  birch sapling shapes                                      (id 23, no collider)
  juniper   3  columnar / spreading / broken juniper                     (id 7)
  shrub     5  sallow, rowan sapling, birch scrub, mixed scrub, low scrub (id 8)
  fern      4  fern clumps of arching frond strips (fern3 atlas)        (id 15)

Foliage is alpha cards with the WORLD-VISUALS-01 atlases (make_cards_v3.py: spruce3, pine3, birch3, bush3); bark from the
CC0 scans (make_surfaces_v3.py). Trunk base radius per id is the old one (the colliders stay valid for every variant).

Per asset the LOD0 (geometry) goes to assets/environment/glb/<asset>[_v<k>].glb; LOD1 (far) exists once per id: three crossed
cards + a top card, drawn by shaders/environment/impostor_v3.gdshader from an atlas of all variants' side renders
(<id-asset>_imp3.png, 3 x 2 tiles) and top renders (<id-asset>_imp3_top.png); variant sizes in <asset>_variants.json.
Previews: docs/world_visuals01/blender/<asset>_v<k>.png (ground level and from above), lineups per species.
"""
import json
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
import fn_env_lib as L  # noqa: E402

TEX = os.path.join(REPO, "assets", "environment", "textures")
GLB = os.path.join(REPO, "assets", "environment", "glb")
BLEND = os.path.join(REPO, "assets", "environment", "blender")
PREV = os.path.join(REPO, "docs", "world_visuals01", "blender")
L.set_tex_dir(TEX)

UP = Vector((0, 0, 1))


def mats():
    return {
        "spruce_bark": L.image_material("Bark_Spruce3", "bark_spruce3_alb.png", "bark_spruce3_nrm.png", roughness=0.92),
        "birch_bark": L.image_material("Bark_Birch", "bark_birch_alb.png", "bark_birch_nrm.png", roughness=0.8),
        "dead": L.image_material("Bark_Log3", "bark_log3_alb.png", "bark_log3_nrm.png", roughness=0.95),
        "spruce": L.image_material("Needles_Spruce3", "spruce3_alb.png", "spruce3_nrm.png", alpha=True, roughness=0.75),
        "pine": L.image_material("Needles_Pine3", "pine3_alb.png", "pine3_nrm.png", alpha=True, roughness=0.72),
        "birch": L.image_material("Leaves_Birch3", "birch3_alb.png", "birch3_nrm.png", alpha=True, roughness=0.6),
        "bush": L.image_material("Foliage_Bush3", "bush3_alb.png", "bush3_nrm.png", alpha=True, roughness=0.7),
        "fern": L.image_material("Leaves_Fern3", "fern3_alb.png", "fern3_nrm.png", alpha=True, roughness=0.65),
    }


def split_bark(kind, split_m):
    """Bark with a second texture above split_m (mesh metres): Scots pine grey plates -> orange flakes; birch dark fissured
    base -> white. The split height is part of the material name (the Godot import reads it)."""
    name = "Bark_%s3_s%.1f" % (kind, split_m)
    if kind == "Pine":
        return L.image_material(name, "bark_pine3_lower_alb.png", "bark_pine3_lower_nrm.png", roughness=0.92)
    return L.image_material(name, "bark_birch_base3_alb.png", "bark_birch_base3_nrm.png", roughness=0.92)


def tile_uv(i, cols=2, rows=2):
    c, r = i % cols, (i // cols) % rows
    u0, u1 = c / cols, (c + 1) / cols
    v1 = 1.0 - r / rows
    v0 = 1.0 - (r + 1) / rows
    return (u0 + 0.004, v0 + 0.004, u1 - 0.004, v1 - 0.004)


def bend(p0, d, length, up_bias, steps, rnd, droop=0.0, jitter=0.08):
    pts = [p0]
    dirv = d.normalized()
    seg = length / steps
    for i in range(steps):
        dirv = (dirv + Vector((0, 0, up_bias - droop * (i + 1) / steps)) * (1.0 / steps)
                + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.5, 0.5))) * jitter).normalized()
        pts.append(pts[-1] + dirv * seg)
    return pts


def lerp_pts(pts, t):
    n = len(pts) - 1
    f = min(max(t, 0.0), 0.9999) * n
    i = int(f)
    return pts[i].lerp(pts[i + 1], f - i), (pts[i + 1] - pts[i]).normalized()


def trunk(mb, rnd, H, r0, mat, steps=16, flare=0.4, lean=0.0, lean_dir=None, sides=12, wobble=0.04, top_r=0.012,
          uv_v_m=1.2, mat2=None, split_k=None):
    """Stem with root flare, taper, slight sinuosity. Returns at(z) -> (point, radius)."""
    lean_dir = lean_dir or Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)).normalized()
    ph1, ph2 = rnd.random() * 6, rnd.random() * 6
    pts, rad = [], []
    for i in range(steps + 1):
        z = H * i / steps
        wob = Vector((math.sin(z * 0.41 + ph1), math.cos(z * 0.33 + ph2), 0)) * wobble * (z / H)
        p = Vector((0, 0, z)) + lean_dir * (lean * z * z / H) + wob
        r = r0 * (1 - 0.94 * (z / H)) ** 0.85 + top_r
        r *= 1 + flare * math.exp(-z / 0.45)
        pts.append(p)
        rad.append(r)
    circ = 2 * math.pi * r0
    u_rep = max(1, round(circ / 0.6))
    mb.tube(pts, rad, sides, mat, uv_u=u_rep, uv_v_m=uv_v_m, cap=True, col=(0.8, 0.8, 0.8), col_end=(1, 1, 1))

    def at(z):
        f = max(0.0, min(1.0, z / H))
        i = min(steps - 1, int(f * steps))
        t = f * steps - i
        return pts[i].lerp(pts[i + 1], t), rad[i] + (rad[i + 1] - rad[i]) * t
    return at


def ao_col(p, crown_c, crown_r, lo=0.6):
    radial = Vector((p.x - crown_c.x, p.y - crown_c.y, 0)).length / max(crown_r, 0.1)
    vert = max(0.0, min(1.0, (p.z - (crown_c.z - crown_r * 2)) / (crown_r * 4)))
    a = lo + (1 - lo) * min(1.0, 0.6 * radial + 0.4 * vert)
    return (a, a, a)


def spray(mb, mat, rnd, base, dirv, length, roll_deg, crown_c, crown_r, tiles=4, cross=True, width_k=0.8):
    """A branch-end card lying along dirv (texture base at `base`), rolled about its axis; optional crossing card."""
    d = dirv.normalized()
    side = d.cross(UP)
    if side.length < 1e-3:
        side = Vector((1, 0, 0))
    side.normalize()
    roll = math.radians(roll_deg)
    s1 = Matrix.Rotation(roll, 3, d) @ side
    uv = tile_uv(rnd.randrange(tiles))
    cb = ao_col(base, crown_c, crown_r)
    ct = ao_col(base + d * length, crown_c, crown_r)
    ct = tuple(min(1.0, c + 0.12) for c in ct)
    mb.card(base, d, s1, length * width_k, length, mat, cb, ct, uv=uv)
    if cross:
        s2 = Matrix.Rotation(roll + math.radians(rnd.choice([-1, 1]) * rnd.uniform(55, 80)), 3, d) @ side
        mb.card(base, d, s2, length * width_k * 0.85, length * 0.95, mat, cb, ct, uv=tile_uv(rnd.randrange(tiles)))


# ------------------------------------------------------------------ Norway spruce
def make_spruce(name, M, seed, H=19.0, r0=0.30, base_frac=0.18, lmax_k=0.2, droop=0.5, dead_frac=0.0, lean=0.0,
                young=False, density=1.0, narrow=0.0):
    rnd = random.Random(seed)
    mb = L.MeshBuilder(name + "_LOD0")
    at = trunk(mb, rnd, H, r0, M["spruce_bark"], flare=0.35, lean=lean, sides=10 if not young else 7,
               wobble=0.03, uv_v_m=1.0)
    zb = H * base_frac
    lmax = H * lmax_k
    crown_c = Vector((0, 0, zb + (H - zb) * 0.4))
    crown_r = lmax
    z = zb
    k = 0
    step = (0.27 if young else 0.36) / density
    while z < H * 0.95:
        f = (z - zb) / max(H - zb, 0.1)
        p, r = at(z)
        nb = rnd.randint(5, 7)
        # Crown profile: spire at the top, broad at the base, a little irregular whorl to whorl.
        prof = (1 - f) ** (0.95 + narrow * 0.6) * (1.0 - narrow * 0.35)
        for b in range(nb):
            if rnd.random() < 0.12 * (1 - f):
                continue  # a lost branch: gaps in the crown
            az = (b + rnd.uniform(-0.3, 0.3)) / nb * 2 * math.pi + k * 0.9
            ln = (lmax * prof + 0.25) * rnd.uniform(0.75, 1.15)
            el = math.radians(-18 * droop * (1 - f) + 38 * f + rnd.uniform(-7, 7))
            d = Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el)))
            # Comb habit: the branch sags in the middle and turns up at the tip.
            pts = bend(p + d * r * 0.8, d, ln, 0.35 + 0.4 * f, 4, rnd, droop=droop * 1.2 * (1 - f))
            mb.tube(pts, [max(0.016, r * 0.2) * (1 - 0.75 * j / 4) for j in range(5)], 4, M["spruce_bark"],
                    uv_u=1, uv_v_m=0.5, cap=False)
            nspr = max(1, int(round(ln / 0.55 * density)))
            for c in range(nspr):
                t = 0.15 + 0.85 * (c + rnd.uniform(0.0, 0.6)) / nspr
                q, dd = lerp_pts(pts, t)
                sl = (1.1 + 1.0 * min(1.0, ln / max(lmax, 0.5))) * rnd.uniform(0.85, 1.15)
                sl = min(sl, ln * (1.2 - t) + 0.6)
                spray(mb, M["spruce"], rnd, q - dd * sl * 0.15, (dd + Vector((0, 0, 0.05))), sl,
                      rnd.uniform(-25, 25), crown_c, crown_r, cross=(c % 2 == 1))
                # Comb branchlets hanging from the primary branch (the curtain look of Norway spruce).
                if rnd.random() < 0.4 * (1 - 0.6 * f) * droop + 0.1:
                    hl = rnd.uniform(0.6, 1.1) * (0.6 + 0.4 * min(1.0, ln / max(lmax, 0.5)))
                    hang = (Vector((0, 0, -1)) + dd * 0.35).normalized()
                    side = dd.cross(UP)
                    if side.length < 1e-3:
                        side = Vector((1, 0, 0))
                    side.normalize()
                    cb = ao_col(q, crown_c, crown_r)
                    mb.card(q + hang * hl, -hang, side, hl * 0.9, hl, M["spruce"], (cb[0] * 0.85,) * 3, cb,
                            uv=tile_uv(rnd.randrange(4)))
            # Spray at the tip pointing outward.
            tip, td = pts[-1], (pts[-1] - pts[-2]).normalized()
            spray(mb, M["spruce"], rnd, tip - td * 0.35, td, rnd.uniform(0.9, 1.3) * (0.7 + 0.3 * prof), rnd.uniform(-20, 20),
                  crown_c, crown_r, cross=True)
        k += 1
        z += step * rnd.uniform(0.8, 1.2)
    # Leader.
    p, r = at(H * 0.95)
    for a in (0, 90):
        side = Matrix.Rotation(math.radians(a + rnd.uniform(-10, 10)), 3, UP) @ Vector((1, 0, 0))
        mb.card(p - Vector((0, 0, 0.3)), UP, side, 0.9, 1.7, M["spruce"], (0.9,) * 3, (1, 1, 1), uv=tile_uv(rnd.randrange(4)))
    # Dead lower branches (forest-grown trees self-prune slowly: dry twigs on the stem).
    if dead_frac > 0:
        for i in range(int(36 * dead_frac)):
            z = rnd.uniform(0.8, zb)
            p, r = at(z)
            az = rnd.random() * 2 * math.pi
            d = Vector((math.cos(az), math.sin(az), rnd.uniform(-0.7, -0.2))).normalized()
            ln = rnd.uniform(0.12, 0.6) * (1 - z / (zb + 1))
            mb.tube([p + d * r * 0.7, p + d * (r + ln)], [0.022, 0.006], 3, M["dead"], uv_u=1, uv_v_m=0.5,
                    col=(0.6, 0.6, 0.6))
    return mb.finish(), crown_c, crown_r


# ------------------------------------------------------------------ Scots pine
def make_pine(name, M, seed, H=20.0, r0=0.28, crown=0.6, flat=False, n_br=26, lean=0.0, split=None, sparse=0.0):
    rnd = random.Random(seed)
    mb = L.MeshBuilder(name + "_LOD0")
    split = split or H * (0.45 if not flat else 0.55)
    bark = split_bark("Pine", split)
    at = trunk(mb, rnd, H * 0.97, r0, bark, flare=0.4, lean=lean, sides=12, wobble=0.07, uv_v_m=1.4)
    z0 = H * crown
    crown_c = Vector((0, 0, (z0 + H) * 0.5))
    crown_r = H * (0.19 if not flat else 0.25)
    golden = math.radians(137.5)
    for i in range(n_br):
        if rnd.random() < sparse:
            continue
        f = (i + rnd.random() * 0.6) / n_br
        z = z0 + (H * 0.95 - z0) * f
        p, r = at(z)
        az = i * golden + rnd.uniform(-0.4, 0.4)
        if flat:
            ln = crown_r * (0.7 + 0.5 * math.sin(math.pi * f)) * rnd.uniform(0.75, 1.15)
            el = math.radians(5 + 25 * f + rnd.uniform(-8, 8))
        else:
            ln = crown_r * (1.15 - 0.7 * f) * rnd.uniform(0.7, 1.15)
            el = math.radians(-2 + 45 * f + rnd.uniform(-10, 10))
        d = Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el)))
        pts = bend(p + d * r * 0.8, d, ln, 0.55 if not flat else 0.3, 4, rnd, jitter=0.14)
        br = max(0.03, r * 0.45)
        mb.tube(pts, [br * (1 - 0.75 * j / 4) for j in range(5)], 5, bark, uv_u=1, uv_v_m=0.7)
        ends = [(pts[-1], (pts[-1] - pts[-2]).normalized(), 1.0)]
        for s in range(rnd.randint(3, 5)):
            kk = rnd.randint(1, 3)
            q = pts[kk]
            sd = (Matrix.Rotation(rnd.choice([-1, 1]) * rnd.uniform(0.5, 1.0), 3, UP) @ (pts[kk + 1] - pts[kk])).normalized()
            sd.z += 0.3
            sp = bend(q, sd, ln * rnd.uniform(0.35, 0.55), 0.6, 3, rnd, jitter=0.15)
            mb.tube(sp, [br * 0.45 * (1 - 0.7 * j / 3) for j in range(4)], 4, bark, uv_u=1, uv_v_m=0.7, cap=False)
            ends.append((sp[-1], (sp[-1] - sp[-2]).normalized(), 0.8))
        for (tp, td, sc) in ends:
            # Tufts turn upward at the branch ends (pine3 card base at the branch).
            up = (td * 0.45 + UP * 0.55).normalized()
            for c in range(3):
                ln_c = rnd.uniform(1.8, 2.5) * sc
                spray(mb, M["pine"], rnd, tp - td * 0.4 - up * 0.2, up, ln_c, rnd.uniform(0, 180), crown_c, crown_r,
                      cross=(c < 2), width_k=1.0)
            back = tp - td * 1.2 * sc
            spray(mb, M["pine"], rnd, back, (td * 0.6 + UP * 0.4).normalized(), rnd.uniform(1.5, 2.0) * sc,
                  rnd.uniform(0, 180), crown_c, crown_r, cross=True, width_k=1.0)
    p, r = at(H * 0.95)
    spray(mb, M["pine"], rnd, p, UP, 1.6, 0, crown_c, crown_r, cross=True, width_k=1.0)
    # Branch stubs on the clear stem (self-pruned).
    for i in range(16):
        z = rnd.uniform(2.0, z0 - 0.5)
        p, r = at(z)
        az = rnd.random() * 2 * math.pi
        d = Vector((math.cos(az), math.sin(az), rnd.uniform(-0.2, 0.1))).normalized()
        mb.tube([p + d * r * 0.7, p + d * (r + rnd.uniform(0.15, 0.7))], [0.03, 0.008], 4, M["dead"], uv_u=1, uv_v_m=0.6)
    return mb.finish(), crown_c, crown_r


# ------------------------------------------------------------------ birch
def make_birch(name, M, seed, H=16.0, r0=0.17, stems=1, lean=0.0, split=1.6, weep=1.0, n_br=24):
    mb = L.MeshBuilder(name + "_LOD0")
    bark_low = split_bark("Birch", split)
    crown_c = Vector((0, 0, H * 0.66))
    crown_r = H * 0.2
    for st in range(stems):
        sub = random.Random(seed * 7 + st)
        h = H * (1.0 if st == 0 else sub.uniform(0.72, 0.9))
        rr = r0 if stems == 1 else r0 * (0.75 if st == 0 else 0.6)
        off = Vector((0, 0, 0))
        ld = None
        ln_ = lean
        if stems > 1:
            a = st / stems * 2 * math.pi + sub.uniform(-0.3, 0.3)
            off = Vector((math.cos(a), math.sin(a), 0)) * 0.16
            ld = Vector((math.cos(a), math.sin(a), 0))
            ln_ = lean + 0.08
        # Two materials: dark fissured base up to `split`, white above (birch bark texture), a short overlap.
        at0 = trunk(mb, sub, h, rr, M["birch_bark"], flare=0.3, lean=ln_, lean_dir=ld, sides=10, wobble=0.06, uv_v_m=1.0)
        at_low = trunk(mb, random.Random(seed * 7 + st), min(split, h * 0.3) + 0.15, rr * 1.035, bark_low, steps=4,
                       flare=0.33, lean=ln_ * 0.05, lean_dir=ld, sides=10, wobble=0.0, top_r=rr * 0.7, uv_v_m=1.0)

        def at(z, at0=at0, off=off):
            p, r = at0(z)
            return p + off, r
        nb = n_br if stems == 1 else n_br // 2 + 2
        for i in range(nb):
            f = (i + sub.random() * 0.7) / nb
            z = h * (0.38 + 0.57 * f)
            p, r = at(z)
            az = i * math.radians(137.5) + sub.uniform(-0.4, 0.4)
            el = math.radians(40 + 25 * f + sub.uniform(-10, 10))
            d = Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el)))
            ln = h * 0.25 * (1 - 0.5 * f) * sub.uniform(0.75, 1.2)
            pts = bend(p + d * r * 0.8, d, ln, 0.05, 4, sub, droop=0.9 * weep, jitter=0.12)
            mb.tube(pts, [max(0.015, r * 0.33) * (1 - 0.75 * j / 4) for j in range(5)], 5, M["birch_bark"],
                    uv_u=1, uv_v_m=0.5, cap=False)
            for c in range(sub.randint(3, 5)):
                t = sub.uniform(0.25, 1.0)
                q, dd = lerp_pts(pts, t)
                # Hanging twig curtain: card "up" points down from the branch (texture base at the top = card top).
                hang = (Vector((0, 0, -1)) + dd * 0.25 * (1 - weep)).normalized()
                L_ = sub.uniform(1.3, 2.0) * (0.75 + 0.25 * weep)
                side = Matrix.Rotation(sub.uniform(0, math.pi), 3, UP) @ Vector((1, 0, 0))
                top = q + Vector((0, 0, 0.15))
                cb = ao_col(q, crown_c, crown_r, 0.55)
                uv = tile_uv(sub.randrange(4))
                # Texture top (v1) at the branch: base of the card at the lower end, pointing up.
                mb.card(top + hang * L_, -hang, side, L_ * 0.8, L_, M["birch"], cb, tuple(min(1, x + 0.1) for x in cb), uv=uv)
                mb.card(top + hang * L_, -hang, Matrix.Rotation(math.radians(80), 3, UP) @ side, L_ * 0.7, L_ * 0.95,
                        M["birch"], cb, cb, uv=tile_uv(sub.randrange(4)))
        p, r = at(h * 0.97)
        for a in (0, 70, 140):
            side = Matrix.Rotation(math.radians(a), 3, UP) @ Vector((1, 0, 0))
            mb.card(p - Vector((0, 0, 1.1)), UP, side, 1.5, 1.8, M["birch"], (0.85,) * 3, (1, 1, 1), uv=tile_uv(sub.randrange(4)))
    return mb.finish(), crown_c, crown_r


# ------------------------------------------------------------------ bushes (side-view cards, bush3 atlas)
def make_bush(name, M, seed, kind, H=1.8, W=1.6, n=10):
    """Crossed upright cards around the centre; tile by kind (0 sallow, 1 juniper, 2 rowan, 3 birch scrub)."""
    rnd = random.Random(seed)
    out = []
    tiles = {"sallow": [0], "juniper": [1], "rowan": [2], "scrub": [3], "mixed": [0, 2, 3]}[kind]
    for lod, frac in ((0, 1.0), (1, 0.4)):
        mb = L.MeshBuilder(name + "_LOD%d" % lod)
        cnt = max(3, int(n * frac))
        for i in range(cnt):
            a = (i / cnt) * math.pi + rnd.uniform(-0.25, 0.25)
            side = Vector((math.cos(a), math.sin(a), 0))
            off = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)) * W * 0.18
            tilt = Vector((rnd.uniform(-0.15, 0.15), rnd.uniform(-0.15, 0.15), 1)).normalized()
            h = H * rnd.uniform(0.75, 1.1)
            w = W * rnd.uniform(0.8, 1.15) if kind != "juniper" else W * rnd.uniform(0.5, 0.7)
            ao = 0.55 + 0.1 * rnd.random()
            mb.card(off - Vector((0, 0, 0.05)), tilt, side, w, h, M["bush"], (ao,) * 3, (1, 1, 1),
                    uv=tile_uv(rnd.choice(tiles)))
        ob = mb.finish()
        out.append(ob)
    return out


# ------------------------------------------------------------------ ferns (fern3 atlas, arching frond strips)
def make_fern(name, M, seed, n=(7, 10), L_=(0.7, 1.0), spread=1.0):
    rnd = random.Random(seed)
    out = []
    for lod, segs in ((0, 4), (1, 2)):
        rr = random.Random(seed)
        mb = L.MeshBuilder(name + "_LOD%d" % lod)
        cnt = rr.randint(*n)
        for i in range(cnt):
            az = i / cnt * 2 * math.pi + rr.uniform(-0.25, 0.25)
            out_d = Vector((math.cos(az), math.sin(az), 0))
            side = Vector((-math.sin(az), math.cos(az), 0))
            length = rr.uniform(*L_)
            rise = rr.uniform(0.9, 1.4)  # steep at the base, arching over
            u0, v0, u1, v1 = tile_uv(rr.randrange(4))
            pts = []
            for k in range(segs + 1):
                t = k / segs
                a = math.radians(70 * rise) * (1 - t) - math.radians(25) * t * spread
                pts.append(Vector((0, 0, 0.02)))
            p = Vector((0, 0, 0.02))
            seg = length / segs
            pts = [p.copy()]
            for k in range(segs):
                t = (k + 0.5) / segs
                el = math.radians(68 * rise * (1 - t) - 30 * t * t * spread)
                d = out_d * math.cos(el) + UP * math.sin(el)
                p = p + d * seg
                pts.append(p.copy())
            roll = Matrix.Rotation(rr.uniform(-0.35, 0.35), 3, out_d) @ side
            w = length * 0.62
            for k in range(segs):
                a, b = pts[k], pts[k + 1]
                va, vb = v0 + (v1 - v0) * k / segs, v0 + (v1 - v0) * (k + 1) / segs
                wa = w * (0.55 + 0.45 * math.sin(math.pi * min(1.0, (k / segs) / 0.9 + 0.1)))
                wb = w * (0.55 + 0.45 * math.sin(math.pi * min(1.0, ((k + 1) / segs) / 0.9 + 0.1)))
                ca = 0.6 + 0.4 * k / segs
                cb = 0.6 + 0.4 * (k + 1) / segs
                mb.face([a - roll * wa * 0.5, a + roll * wa * 0.5, b + roll * wb * 0.5, b - roll * wb * 0.5],
                        [(u0, va), (u1, va), (u1, vb), (u0, vb)], M["fern"], [(ca,) * 3, (ca,) * 3, (cb,) * 3, (cb,) * 3])
        out.append(mb.finish())
    return out


# ------------------------------------------------------------------ mid LOD
def mid_lod(ob, name, keep=0.35, grow=1.45, seed=0, twig_area=0.0):
    """LOD1 between the full tree and the impostor: the same stem and branches, a random `keep` share of the foliage cards,
    each enlarged about its centre by `grow` so the crown keeps its cover; dead twigs dropped. Built from LOD0 itself, so the
    silhouette does not jump at the switch. Bark faces smaller than twig_area (m2: the thin branch tubes under the sprays)
    are dropped too."""
    import bmesh
    rnd = random.Random(seed)
    lod1 = ob.copy()
    lod1.data = ob.data.copy()
    lod1.name = name + "_LOD1"
    lod1.data.name = name + "_LOD1"
    bpy.context.scene.collection.objects.link(lod1)
    bm = bmesh.new()
    bm.from_mesh(lod1.data)
    mats_ = lod1.data.materials
    drop = []
    for f in bm.faces:
        mn = mats_[f.material_index].name if f.material_index < len(mats_) else ""
        if mn.startswith(("Needles", "Leaves", "Foliage")):
            if rnd.random() > keep:
                drop.append(f)
            else:
                c = f.calc_center_median()
                for v in f.verts:
                    v.co = c + (v.co - c) * grow
        elif mn.startswith("Bark_Log"):
            drop.append(f)
        elif mn.startswith("Bark") and f.calc_area() < twig_area:
            drop.append(f)
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(lod1.data)
    bm.free()
    return lod1


# ------------------------------------------------------------------ impostors
def render_tile(ob, path, px, height, width, top=False, half_w=None):
    if top:
        L.render_impostor_top([ob], path, half_w, px=px[0])
    else:
        L.render_impostor([ob], path, px=px, height=height, width=width)


def img_np(path):
    im = bpy.data.images.load(path, check_existing=False)
    w, h = im.size
    a = np.empty(w * h * 4, np.float32)
    im.pixels.foreach_get(a)
    bpy.data.images.remove(im)
    return a.reshape(h, w, 4)


def save_np(arr, path):
    h, w = arr.shape[:2]
    im = bpy.data.images.new("tmp_atlas", w, h, alpha=True)
    im.pixels.foreach_set(arr.astype(np.float32).ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)


def bleed_np(rgba, iters=24):
    """Colour into transparent texels by repeated neighbour averaging (keeps mip edges from going dark)."""
    rgb = rgba[..., :3].copy()
    a = rgba[..., 3]
    known = a > 0.05
    for _ in range(iters):
        if known.all():
            break
        acc = np.zeros_like(rgb)
        cnt = np.zeros(a.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh_k = np.roll(known, (dy, dx), axis=(0, 1))
            sh_c = np.roll(rgb, (dy, dx), axis=(0, 1))
            acc += sh_c * sh_k[..., None]
            cnt += sh_k
        grow = (~known) & (cnt > 0)
        rgb[grow] = acc[grow] / cnt[grow][..., None]
        known = known | grow
    out = rgba.copy()
    out[..., :3] = rgb
    return out


def impostor_mesh(base, w, h, half_w, crown_z):  # noqa: D401 - far LOD (LOD2 once the mid LOD exists)
    """Variant 0's far LOD geometry: three crossed side cards (UV 0..1, the shader maps them into the atlas tile) + a top
    card at crown height."""
    mat = L.flat_material("Impostor3_" + base, (0.3, 0.4, 0.25))
    mat_top = L.flat_material("Impostor3_" + base + "_Top", (0.3, 0.4, 0.25))
    mb = L.MeshBuilder(base + "_LOD1")
    for k in range(3):
        a = k * math.pi / 3
        s = Vector((math.cos(a), math.sin(a), 0))
        mb.card(Vector((0, 0, 0)), UP, s, w, h, mat, (1, 1, 1), (1, 1, 1))
    s2 = half_w
    mb.face([Vector((-s2, -s2, crown_z)), Vector((s2, -s2, crown_z)), Vector((s2, s2, crown_z)), Vector((-s2, s2, crown_z))],
            [(0, 0), (1, 0), (1, 1), (0, 1)], mat_top, [(1, 1, 1)] * 4)
    return mb.finish(smooth=False)


def dims(ob):
    """(card width, card height, crown half-width) of the impostor: the side tiles are 1:2, so the card is as tall as the
    tree or twice its width, whichever is larger (a broad tree is not cropped; the base stays at the bottom)."""
    xs = [abs((ob.matrix_world @ Vector(c)).x) for c in ob.bound_box] + [abs((ob.matrix_world @ Vector(c)).y) for c in ob.bound_box]
    half_w = max(xs) * 1.02
    top = max((ob.matrix_world @ Vector(c)).z for c in ob.bound_box)
    h = max(top, 4 * half_w)
    return h * 0.5, h, half_w


# ------------------------------------------------------------------ species table
SPECIES = {
    # base asset: (builder, [kwargs per variant])  - variant 0 keeps the old file name.
    "spruce_a": (make_spruce, [
        dict(seed=301, H=19.0, base_frac=0.2, lmax_k=0.19, droop=0.55, dead_frac=0.6),
        dict(seed=302, H=21.0, base_frac=0.28, lmax_k=0.15, droop=0.4, dead_frac=1.0, narrow=0.6),
        dict(seed=303, H=17.0, base_frac=0.06, lmax_k=0.23, droop=0.7, dead_frac=0.0),
        dict(seed=304, H=22.0, base_frac=0.35, lmax_k=0.17, droop=0.8, dead_frac=1.0),
        dict(seed=305, H=18.0, base_frac=0.16, lmax_k=0.21, droop=0.95, dead_frac=0.4, density=1.15),
        dict(seed=306, H=19.5, base_frac=0.22, lmax_k=0.18, droop=0.5, dead_frac=0.7, lean=0.05, narrow=0.3),
    ]),
    "spruce_b": (make_spruce, [
        dict(seed=311, H=7.5, r0=0.13, base_frac=0.03, lmax_k=0.26, droop=0.4, young=True, density=0.75),
        dict(seed=312, H=8.0, r0=0.13, base_frac=0.05, lmax_k=0.22, droop=0.3, young=True, narrow=0.4, density=0.7),
        dict(seed=313, H=6.8, r0=0.13, base_frac=0.02, lmax_k=0.3, droop=0.6, young=True, density=0.85),
    ]),
    "spruce_s": (make_spruce, [
        dict(seed=321, H=7.5, r0=0.12, base_frac=0.02, lmax_k=0.28, droop=0.3, young=True, density=0.5),
        dict(seed=322, H=7.0, r0=0.12, base_frac=0.04, lmax_k=0.24, droop=0.5, young=True, narrow=0.3, density=0.45),
    ]),
    "pine_a": (make_pine, [
        dict(seed=401, H=20.0, r0=0.28, crown=0.58, n_br=30),
        dict(seed=402, H=18.0, r0=0.28, crown=0.5, n_br=34, lean=0.04),
        dict(seed=403, H=21.0, r0=0.28, crown=0.64, n_br=26, sparse=0.15),
    ]),
    "pine_b": (make_pine, [
        dict(seed=411, H=24.0, r0=0.32, crown=0.66, flat=True, n_br=32),
        dict(seed=412, H=22.0, r0=0.32, crown=0.62, flat=True, n_br=36, lean=0.06),
        dict(seed=413, H=25.0, r0=0.32, crown=0.7, flat=True, n_br=28, sparse=0.1),
    ]),
    "birch_a": (make_birch, [
        dict(seed=501, H=16.0, r0=0.17, split=0.9),
        dict(seed=502, H=17.5, r0=0.17, split=1.2, weep=1.2, n_br=26),
        dict(seed=503, H=14.5, r0=0.17, split=0.6, weep=0.7, lean=0.05),
    ]),
    "birch_b": (make_birch, [
        dict(seed=511, H=13.0, r0=0.17, stems=3, split=0.6),
        dict(seed=512, H=12.0, r0=0.17, stems=2, split=0.7, weep=0.8),
    ]),
    "birch_s": (make_birch, [
        dict(seed=521, H=13.0, r0=0.12, stems=1, split=0.4, n_br=16),
        dict(seed=522, H=12.0, r0=0.12, stems=2, split=0.3, n_br=16, weep=0.6),
    ]),
}
FERNS = {
    "fern": [dict(seed=701, n=(8, 11), L_=(0.75, 1.05)), dict(seed=702, n=(6, 8), L_=(0.9, 1.25), spread=1.3),
             dict(seed=703, n=(9, 12), L_=(0.55, 0.8)), dict(seed=704, n=(5, 7), L_=(0.6, 0.9), spread=0.6)],
}
BUSHES = {
    "juniper": [dict(seed=601, kind="juniper", H=2.2, W=1.0, n=12), dict(seed=602, kind="juniper", H=1.4, W=1.6, n=10),
                dict(seed=603, kind="juniper", H=2.8, W=0.9, n=10)],
    "shrub": [dict(seed=611, kind="sallow", H=2.2, W=2.0, n=10), dict(seed=612, kind="rowan", H=2.6, W=1.6, n=8),
              dict(seed=613, kind="scrub", H=2.0, W=2.2, n=10), dict(seed=614, kind="mixed", H=1.7, W=1.8, n=12),
              dict(seed=615, kind="scrub", H=1.3, W=1.6, n=9)],
}


# Mid LOD: bark faces below this area (m2) are dropped (spruce branches vanish under the sprays; pine and birch keep the
# main limbs that show through their open crowns).
TWIG_AREA = {"spruce_a": 0.06, "spruce_b": 0.03, "spruce_s": 0.03, "pine_a": 0.012, "pine_b": 0.012, "birch_a": 0.006,
             "birch_b": 0.006, "birch_s": 0.006}


def asset_name(base, k):
    return base if k == 0 else "%s_v%d" % (base, k)


def preview(ob, path, ground=True):
    L.setup_world(1.0)
    L.add_sun(rot=(math.radians(48), 0, math.radians(30)), energy=3.5)
    g = L.ground_plane(400, (0.22, 0.24, 0.14)) if ground else None
    L.render_views([ob], path, size=(700, 900), views=((30, 4), (30, 60)))
    if g:
        bpy.data.objects.remove(g, do_unlink=True)


def build_species(base, fn, variants, previews):
    out = []
    stats = []
    for k, kw in enumerate(variants):
        L.clear_scene()
        M = mats()
        name = asset_name(base, k)
        ob, cc, cr = fn(name, M, **kw)
        L.foliage_normals(ob, cc, 0.6)
        w, h, hw = dims(ob)
        out.append((name, w, h, hw, cc.z))
        st = L.stats(ob)
        stats.append(st)
        if previews:
            preview(ob, os.path.join(PREV, name + "_pv.png"))
        os.makedirs(BLEND, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, name + ".blend"))
        mid = mid_lod(ob, name, seed=kw["seed"], twig_area=TWIG_AREA.get(base, 0.0))
        stats[-1]["mid_tris"] = L.stats(mid)["tris"]
        objs = [ob, mid]
        if k == 0:
            lod2 = impostor_mesh(base, w, h, hw, cc.z + (h - cc.z) * 0.35)
            lod2.name = base + "_LOD2"
            objs.append(lod2)
        L.export_glb(objs, os.path.join(GLB, name + ".glb"), "NAMES")
        print("ASSET", name, st)
    # Impostor atlas from re-built variants (one scene at a time).
    obs_dims = []
    rects = []
    for k, kw in enumerate(variants):
        L.clear_scene()
        M = mats()
        ob, cc, cr = fn(asset_name(base, k) + "_imp", M, **kw)
        name, w, h, hw, cz = out[k]
        rects += impostor_atlas_single(base, k, ob, w, h, hw)
    compose_atlas(base, len(variants))
    with open(os.path.join(GLB, base + "_variants.json"), "w", encoding="utf-8") as f:
        json.dump({"base": base, "variants": [{"asset": o[0], "w": o[1], "h": o[2], "half_w": o[3], "crown_z": o[4]}
                                              for o in out], "rects": rects, "stats": stats}, f, indent=1)


def impostor_atlas_single(base, k, ob, w, h, hw):
    TW, TH, TT = 512, 1024, 512
    side_p = os.path.join(TEX, "_imp_%s_%d.png" % (base, k))
    top_p = os.path.join(TEX, "_imptop_%s_%d.png" % (base, k))
    render_tile(ob, side_p, (TW, TH), h, w)
    render_tile(ob, top_p, (TT, TT), h, w, top=True, half_w=hw)
    c, r = k % 3, k // 3
    return [{"u0": c / 3, "v0": r / 2, "du": 1 / 3, "dv": 1 / 2, "w": w, "h": h, "half_w": hw}]


def compose_atlas(base, n):
    cols, rows = 3, 2
    TW, TH, TT = 512, 1024, 512
    side = np.zeros((rows * TH, cols * TW, 4), np.float32)
    topa = np.zeros((rows * TT, cols * TT, 4), np.float32)
    for k in range(n):
        c, r = k % cols, k // cols
        sp = os.path.join(TEX, "_imp_%s_%d.png" % (base, k))
        tp = os.path.join(TEX, "_imptop_%s_%d.png" % (base, k))
        side[(rows - 1 - r) * TH:(rows - r) * TH, c * TW:(c + 1) * TW] = img_np(sp)
        topa[(rows - 1 - r) * TT:(rows - r) * TT, c * TT:(c + 1) * TT] = img_np(tp)
        os.remove(sp)
        os.remove(tp)
    save_np(bleed_np(side), os.path.join(TEX, base + "_imp3.png"))
    save_np(bleed_np(topa), os.path.join(TEX, base + "_imp3_top.png"))


def build_bushes(base, variants, previews):
    for k, kw in enumerate(variants):
        L.clear_scene()
        M = mats()
        name = asset_name(base, k)
        lod0, lod1 = make_bush(name, M, **kw)
        L.foliage_normals(lod0, Vector((0, 0, kw["H"] * 0.5)), 0.55)
        if previews:
            lod1.hide_render = True
            preview(lod0, os.path.join(PREV, name + "_pv.png"))
            lod1.hide_render = False
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, name + ".blend"))
        L.export_glb([lod0, lod1], os.path.join(GLB, name + ".glb"), "NAMES")
        print("ASSET", name, L.stats(lod0), L.stats(lod1))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    previews = "--no-preview" not in argv
    for a in argv:
        if a.startswith("--only="):
            only = a.split("=", 1)[1].split(",")
    os.makedirs(PREV, exist_ok=True)
    for base, (fn, variants) in SPECIES.items():
        if only and base not in only:
            continue
        build_species(base, fn, variants, previews)
    for base, variants in BUSHES.items():
        if only and base not in only:
            continue
        build_bushes(base, variants, previews)
    for base, variants in FERNS.items():
        if only and base not in only:
            continue
        for k, kw in enumerate(variants):
            L.clear_scene()
            M = mats()
            name = asset_name(base, k)
            lod0, lod1 = make_fern(name, M, **kw)
            L.foliage_normals(lod0, Vector((0, 0, 0.0)), 0.5)
            if previews:
                lod1.hide_render = True
                preview(lod0, os.path.join(PREV, name + "_pv.png"))
                lod1.hide_render = False
            bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, name + ".blend"))
            L.export_glb([lod0, lod1], os.path.join(GLB, name + ".glb"), "NAMES")
            print("ASSET", name, L.stats(lod0), L.stats(lod1))


if __name__ == "__main__":
    main()
