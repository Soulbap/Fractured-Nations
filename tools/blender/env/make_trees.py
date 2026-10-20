"""Nordic trees and understorey for WORLD-TERRAIN-01 (Blender 5.2, run in background):

  blender -b --factory-startup --python tools/blender/env/make_trees.py -- [--only pine_a,spruce_a] [--no-preview]

For each asset: LOD0 (stem, branches, alpha-card foliage with vertex AO), an impostor
texture rendered from the LOD0, LOD1 (three crossed impostor cards), preview renders
(docs/terrain01/blender_previews/<asset>_v*.png), assets/environment/blender/<asset>.blend
and assets/environment/glb/<asset>.glb. Sizes are real-world metres; Godot scales instances
by 0.65-1.3.
"""
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
import fn_env_lib as L  # noqa: E402

TEX = os.path.join(REPO, "assets", "environment", "textures")
GLB = os.path.join(REPO, "assets", "environment", "glb")
BLEND = os.path.join(REPO, "assets", "environment", "blender")
PREV = os.path.join(REPO, "docs", "terrain01", "blender_previews")
L.set_tex_dir(TEX)


def mats():
    return {
        "pine_lower": L.image_material("Bark_PineLower", "bark_pine_lower_alb.png", "bark_pine_lower_nrm.png", roughness=0.95),
        "pine_upper": L.image_material("Bark_PineUpper", "bark_pine_upper_alb.png", "bark_pine_upper_nrm.png", roughness=0.9),
        "spruce_bark": L.image_material("Bark_Spruce", "bark_spruce_alb.png", "bark_spruce_nrm.png", roughness=0.95),
        "birch_bark": L.image_material("Bark_Birch", "bark_birch_alb.png", "bark_birch_nrm.png", roughness=0.8),
        "birch_base": L.image_material("Bark_BirchBase", "bark_birch_base_alb.png", "bark_birch_base_nrm.png", roughness=0.95),
        "pine_needles": L.image_material("Needles_Pine", "pine_tuft_alb.png", "pine_tuft_nrm.png", alpha=True, roughness=0.7),
        "spruce_needles": L.image_material("Needles_Spruce", "spruce_spray_alb.png", "spruce_spray_nrm.png", alpha=True, roughness=0.75),
        "birch_leaves": L.image_material("Leaves_Birch", "birch_twig_alb.png", "birch_twig_nrm.png", alpha=True, roughness=0.6),
        "juniper": L.image_material("Foliage_Juniper", "juniper_alb.png", "juniper_nrm.png", alpha=True, roughness=0.8),
        "willow": L.image_material("Leaves_Willow", "willow_alb.png", "willow_nrm.png", alpha=True, roughness=0.65),
        "fern": L.image_material("Leaves_Fern", "fern_alb.png", "fern_nrm.png", alpha=True, roughness=0.65),
    }


def bend(p0, d, length, up_bias, steps, rnd, droop=0.0):
    """Branch polyline from p0 along d, curving toward up (up_bias>0) or down (droop)."""
    pts = [p0]
    dirv = d.normalized()
    seg = length / steps
    for i in range(steps):
        dirv = (dirv + Vector((0, 0, up_bias - droop * (i + 1) / steps)) * (1.0 / steps)
                + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.5, 0.5))) * 0.08).normalized()
        pts.append(pts[-1] + dirv * seg)
    return pts


def trunk(mb, rnd, H, r0, mat_lower, mat_upper, split=0.4, lean=0.02, steps=14, flare=0.45, sides=12):
    """Stem with root flare and slight curvature; lower/upper bark materials split at
    split*H. Returns (points, radius function)."""
    lean_dir = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)).normalized()
    pts, rad = [], []
    for i in range(steps + 1):
        z = H * (i / steps) ** 1.0
        wob = Vector((math.sin(z * 0.37 + rnd.random() * 6), math.cos(z * 0.29 + rnd.random() * 6), 0)) * 0.05
        p = Vector((0, 0, z)) + lean_dir * (lean * z) + wob * (z / H)
        r = r0 * (1 - 0.92 * (z / H)) ** 0.9 + 0.012
        r *= 1 + flare * math.exp(-z / 0.5)
        pts.append(p)
        rad.append(r)
    zsplit = split * H
    k = max(1, min(steps - 1, int(round(split * steps))))
    circ = 2 * math.pi * r0
    u_rep = max(1, round(circ / 0.55))
    if mat_upper is None or mat_upper == mat_lower:
        mb.tube(pts, rad, sides, mat_lower, uv_u=u_rep, uv_v_m=0.55, cap=True)
    else:
        mb.tube(pts[:k + 1], rad[:k + 1], sides, mat_lower, uv_u=u_rep, uv_v_m=0.55, cap=False)
        mb.tube(pts[k:], rad[k:], sides, mat_upper, uv_u=u_rep, uv_v_m=0.55, cap=True)

    def at(z):
        f = max(0.0, min(1.0, z / H))
        i = min(steps - 1, int(f * steps))
        t = f * steps - i
        return pts[i].lerp(pts[i + 1], t), rad[i] + (rad[i + 1] - rad[i]) * t
    return at


def card_cluster(mb, center, dirv, mat, rnd, n, w, h, spread, up_bias, ao_center, crown_r, hang=False):
    """n crossed foliage cards around a branch end. Cards start a little behind the tip
    and extend along the (jittered) branch direction; hanging cards point down."""
    for k in range(n):
        d = dirv.normalized()
        yaw = rnd.uniform(-spread, spread)
        d = (Matrix.Rotation(yaw, 3, Vector((0, 0, 1))) @ d)
        if hang:
            up = (d * 0.25 + Vector((0, 0, -1))).normalized()
        else:
            up = (d * (1 - up_bias) + Vector((0, 0, 1)) * up_bias + Vector((0, 0, rnd.uniform(-0.15, 0.25)))).normalized()
        side = up.cross(Vector((0, 0, 1)))
        if side.length < 1e-3:
            side = Vector((1, 0, 0))
        side = (Matrix.Rotation(rnd.uniform(0, math.pi), 3, up) @ side.normalized())
        base = center - up * h * (0.25 if not hang else 0.05) + Vector((rnd.uniform(-0.2, 0.2), rnd.uniform(-0.2, 0.2), rnd.uniform(-0.1, 0.1)))
        radial = Vector((base.x - ao_center.x, base.y - ao_center.y, 0)).length / max(crown_r, 0.1)
        ao = 0.55 + 0.45 * min(1.0, radial)
        top = min(1.0, ao + 0.25)
        cb = (ao * 0.85, ao * 0.85, ao * 0.85)
        ct = (top, top, top)
        sw = w * rnd.uniform(0.8, 1.15)
        sh = h * rnd.uniform(0.85, 1.15)
        if hang:
            mb.card(base, up, side, sw, sh, mat, ct, cb)
            mb.card(base, up, up.cross(side), sw, sh, mat, ct, cb)
        else:
            mb.card(base, up, side, sw, sh, mat, cb, ct)
            mb.card(base, up, up.cross(side), sw * 0.9, sh, mat, cb, ct)


# ------------------------------------------------------------------ species
def make_pine(name, seed, H=20.0, crown=0.62, n_br=26, flat=False, M=None):
    rnd = random.Random(seed)
    mb = L.MeshBuilder(name + "_LOD0")
    r0 = H * 0.0135
    at = trunk(mb, rnd, H, r0, M["pine_lower"], M["pine_upper"], split=0.42, lean=0.015)
    z0 = H * crown
    crown_c = Vector((0, 0, (z0 + H) * 0.5))
    crown_r = H * (0.2 if not flat else 0.27)
    golden = math.radians(137.5)
    tips = []
    for i in range(n_br):
        f = (i + rnd.random() * 0.6) / n_br
        z = z0 + (H * 0.97 - z0) * f
        p, r = at(z)
        az = i * golden + rnd.uniform(-0.3, 0.3)
        if flat:
            ln = crown_r * (0.55 + 0.6 * f) * rnd.uniform(0.75, 1.1)
            el = math.radians(8 + 30 * f)
        else:
            ln = crown_r * (1.1 - 0.75 * f) * rnd.uniform(0.7, 1.15)
            el = math.radians(-5 + 50 * f + rnd.uniform(-8, 8))
        d = Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el)))
        pts = bend(p + d * r * 0.8, d, ln, 0.6 if not flat else 0.35, 4, rnd)
        br = max(0.03, r * 0.42)
        mb.tube(pts, [br * (1 - 0.75 * k / 4) for k in range(5)], 5, M["pine_upper"], uv_u=1, uv_v_m=0.6)
        tips.append((pts[-1], pts[-1] - pts[-2], 1.0))
        # Sub-branches toward the tip.
        for s in range(rnd.randint(1, 3)):
            k = rnd.randint(1, 3)
            q = pts[k]
            sd = (Matrix.Rotation(rnd.choice([-1, 1]) * rnd.uniform(0.5, 0.9), 3, Vector((0, 0, 1))) @ (pts[k + 1] - pts[k])).normalized()
            sd.z += 0.25
            sp = bend(q, sd, ln * rnd.uniform(0.35, 0.55), 0.5, 3, rnd)
            mb.tube(sp, [br * 0.5 * (1 - 0.7 * j / 3) for j in range(4)], 4, M["pine_upper"], uv_u=1, uv_v_m=0.6, cap=False)
            tips.append((sp[-1], sp[-1] - sp[-2], 0.8))
    # Leader at the top.
    p, r = at(H * 0.97)
    tips.append((p + Vector((0, 0, 0.3)), Vector((0, 0, 1)), 0.9))
    for (tp, d, s) in tips:
        n = 2
        card_cluster(mb, tp, d, M["pine_needles"], rnd, n, 2.4 * s, 2.4 * s, 0.8, 0.45, crown_c, crown_r)
        # One more clump behind the tip fills the branch toward the stem (main branches).
        for back_m, cnt in (((1.3, 1),) if s >= 1.0 else ()):
            back = tp - d.normalized() * back_m * s + Vector((0, 0, rnd.uniform(-0.2, 0.3)))
            card_cluster(mb, back, d, M["pine_needles"], rnd, cnt, 1.9 * s, 1.9 * s, 1.0, 0.5, crown_c, crown_r)
    # Dead branch stubs on the lower stem (self-pruned pine).
    for i in range(14):
        z = rnd.uniform(2.0, z0 - 0.5)
        p, r = at(z)
        az = rnd.random() * 2 * math.pi
        d = Vector((math.cos(az), math.sin(az), rnd.uniform(-0.25, 0.05))).normalized()
        ln = rnd.uniform(0.2, 0.9)
        mb.tube([p + d * r * 0.7, p + d * (r + ln)], [0.03, 0.008], 4, M["pine_upper"], uv_u=1, uv_v_m=0.6)
    return mb.finish(), crown_c, crown_r


def impostor_lod(name, lod0, crown_c, H, rnd_seed=0):
    """LOD1: three crossed vertical cards textured with an orthographic render of LOD0."""
    tex_name = name.lower() + "_impostor.png"
    path = os.path.join(TEX, tex_name)
    # Render width from the LOD0 horizontal extent.
    xs = [abs((lod0.matrix_world @ Vector(c)).x) for c in lod0.bound_box] + \
         [abs((lod0.matrix_world @ Vector(c)).y) for c in lod0.bound_box]
    half_w = max(xs) * 1.02
    top = max((lod0.matrix_world @ Vector(c)).z for c in lod0.bound_box)
    px = (512, int(512 * top / (2 * half_w) // 8 * 8))
    px = (512, max(256, min(1024, px[1])))
    w = top * px[0] / px[1]
    L.render_impostor([lod0], path, px=px, height=top, width=w)
    mat = L.image_material("Impostor_" + name, tex_name, None, alpha=True, roughness=0.9)
    # Top view for RTS/overhead cameras: a horizontal card at crown height.
    top_name = name.lower() + "_top_impostor.png"
    L.render_impostor_top([lod0], os.path.join(TEX, top_name), half_w)
    mat_top = L.image_material("Impostor_" + name + "_Top", top_name, None, alpha=True, roughness=0.9)
    mb = L.MeshBuilder(name + "_LOD1")
    for k in range(3):
        a = k * math.pi / 3
        side = Vector((math.cos(a), math.sin(a), 0))
        mb.card(Vector((0, 0, 0)), Vector((0, 0, 1)), side, w, top, mat, (0.85, 0.85, 0.85), (1, 1, 1))
    zc = crown_c.z + (top - crown_c.z) * 0.35
    s2 = half_w
    mb.face([Vector((-s2, -s2, zc)), Vector((s2, -s2, zc)), Vector((s2, s2, zc)), Vector((-s2, s2, zc))],
            [(0, 0), (1, 0), (1, 1), (0, 1)], mat_top, [(1, 1, 1)] * 4)
    ob = mb.finish(smooth=False)
    return ob


def make_spruce(name, seed, H=18.0, young=False, M=None):
    """Norway spruce: narrow cone, whorled branches drooping at the bottom and rising at
    the top, flat needle sprays; forest-grown trees carry dead twigs on the lower stem."""
    rnd = random.Random(seed)
    mb = L.MeshBuilder(name + "_LOD0")
    r0 = H * 0.017
    at = trunk(mb, rnd, H, r0, M["spruce_bark"], None, lean=0.008, flare=0.35)
    zb = 0.25 if young else H * 0.22
    lmax = H * (0.24 if young else 0.19)
    crown_c = Vector((0, 0, (zb + H) * 0.45))
    crown_r = lmax
    z = zb
    k = 0
    step = 0.32 if young else 0.48
    while z < H * 0.96:
        f = (z - zb) / (H - zb)
        p, r = at(z)
        nb = rnd.randint(5, 6)
        for b in range(nb):
            az = (b + rnd.uniform(-0.25, 0.25)) / nb * 2 * math.pi + k * 0.7
            ln = lmax * (1 - f) ** 0.85 * rnd.uniform(0.8, 1.1) + 0.3
            el = math.radians(-22 + 50 * f + rnd.uniform(-6, 6))
            d = Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el)))
            pts = bend(p + d * r * 0.8, d, ln, 0.15 * f, 3, rnd, droop=0.55 * (1 - f))
            mb.tube(pts, [max(0.02, r * 0.22) * (1 - 0.7 * j / 3) for j in range(4)], 4, M["spruce_bark"],
                    uv_u=1, uv_v_m=0.5, cap=False)
            ncard = max(2, int(ln / 1.05))
            for c in range(ncard):
                t = min(0.999, 0.25 + 0.75 * (c + rnd.random() * 0.5) / ncard)
                i = min(2, int(t * 3))
                q = pts[i].lerp(pts[i + 1], t * 3 - i)
                dirv = (pts[i + 1] - pts[i]).normalized()
                side = dirv.cross(Vector((0, 0, 1)))
                if side.length < 1e-3:
                    side = Vector((1, 0, 0))
                side.normalize()
                sz = (1.3 + 0.8 * (ln / lmax)) * rnd.uniform(0.85, 1.15)
                radial = Vector((q.x, q.y, 0)).length / max(crown_r, 0.1)
                ao = 0.5 + 0.5 * min(1.0, radial)
                cb = (ao * 0.8,) * 3
                ct = (min(1.0, ao + 0.2),) * 3
                # Flat spray plus a tilted one, both drooping slightly.
                up = (dirv + Vector((0, 0, -0.15 * (1 - f)))).normalized()
                mb.card(q - up * sz * 0.15, up, side, sz * 0.85, sz, M["spruce_needles"], cb, ct)
                if c % 2 == 0:
                    tilt = (Matrix.Rotation(math.radians(rnd.choice([-50, 50])), 3, up) @ side)
                    mb.card(q - up * sz * 0.15, up, tilt, sz * 0.75, sz * 0.9, M["spruce_needles"], cb, ct)
        k += 1
        z += step * rnd.uniform(0.85, 1.15)
    p, r = at(H * 0.96)
    mb.card(p, Vector((0, 0, 1)), Vector((1, 0, 0)), 0.7, 1.3, M["spruce_needles"])
    mb.card(p, Vector((0, 0, 1)), Vector((0, 1, 0)), 0.7, 1.3, M["spruce_needles"])
    if not young:
        for i in range(40):
            z = rnd.uniform(1.0, zb)
            p, r = at(z)
            az = rnd.random() * 2 * math.pi
            d = Vector((math.cos(az), math.sin(az), rnd.uniform(-0.4, 0.0))).normalized()
            mb.tube([p + d * r * 0.7, p + d * (r + rnd.uniform(0.3, 1.3))], [0.02, 0.005], 3, M["spruce_bark"],
                    uv_u=1, uv_v_m=0.5, col=(0.7, 0.7, 0.7))
    return mb.finish(), crown_c, crown_r


def make_birch(name, seed, H=16.0, stems=1, M=None):
    """Birch: slender white stems (dark fissured base), ascending branches with drooping
    twig curtains; multi-stem variant for edge and wet-ground birches."""
    mb = L.MeshBuilder(name + "_LOD0")
    crown_c = Vector((0, 0, H * 0.68))
    crown_r = H * 0.2
    for st in range(stems):
        sub = random.Random(seed * 7 + st)
        h = H * (1.0 if st == 0 else sub.uniform(0.75, 0.92))
        r0 = h * (0.012 if stems == 1 else 0.009)
        lean = 0.0 if stems == 1 else 0.07
        off = Vector((0, 0, 0))
        if stems > 1:
            a = st / stems * 2 * math.pi + sub.uniform(-0.3, 0.3)
            off = Vector((math.cos(a), math.sin(a), 0)) * 0.18
        at0 = trunk(mb, sub, h, r0, M["birch_base"], M["birch_bark"], split=0.07, lean=lean, flare=0.3, sides=10)

        def at(z, at0=at0, off=off):
            p, r = at0(z)
            return p + off, r
        nbr = 24 if stems == 1 else 14
        for i in range(nbr):
            f = (i + sub.random() * 0.7) / nbr
            z = h * (0.4 + 0.55 * f)
            p, r = at(z)
            az = i * math.radians(137.5) + sub.uniform(-0.3, 0.3)
            el = math.radians(38 + 22 * f + sub.uniform(-8, 8))
            d = Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el)))
            ln = h * 0.24 * (1 - 0.55 * f) * sub.uniform(0.8, 1.15)
            pts = bend(p + d * r * 0.8, d, ln, 0.1, 4, sub, droop=0.9)
            mb.tube(pts, [max(0.018, r * 0.35) * (1 - 0.75 * j / 4) for j in range(5)], 5, M["birch_bark"],
                    uv_u=1, uv_v_m=0.5, cap=False)
            for c in range(sub.randint(4, 6)):
                t = sub.uniform(0.25, 0.999)
                j = min(3, int(t * 4))
                q = pts[j].lerp(pts[j + 1], t * 4 - j) + Vector((0, 0, sub.uniform(0.0, 0.25)))
                card_cluster(mb, q, pts[j + 1] - pts[j], M["birch_leaves"], sub, 1, 1.9, 2.1, math.pi, 0.0,
                             crown_c, crown_r, hang=True)
        p, r = at(h * 0.97)
        card_cluster(mb, p + Vector((0, 0, 0.6)), Vector((0, 0, 1)), M["birch_leaves"], sub, 3, 1.1, 1.3, math.pi,
                     0.0, crown_c, crown_r, hang=True)
    return mb.finish(), crown_c, crown_r


def make_card_plant(name, seed, kind, M=None):
    """Juniper (columnar), willow shrub (dome) or fern (rosette) from crossed cards.
    Returns [LOD0, LOD1]; the far LOD is a sparser card set (no impostor needed)."""
    out = []
    for lod, frac in ((0, 1.0), (1, 0.35)):
        rnd = random.Random(seed)
        mb = L.MeshBuilder(name + "_LOD%d" % lod)
        if kind == "juniper":
            n = int(26 * frac) + 3
            for i in range(n):
                a = rnd.random() * 2 * math.pi
                z = rnd.uniform(0.0, 1.7)
                rr = 0.45 * (1 - z / 2.6)
                base = Vector((math.cos(a) * rr * 0.5, math.sin(a) * rr * 0.5, z))
                up = Vector((math.cos(a) * 0.25, math.sin(a) * 0.25, 1)).normalized()
                side = Vector((-math.sin(a), math.cos(a), 0))
                ao = 0.55 + 0.45 * z / 2.0
                mb.card(base, up, side, 0.7, 1.0, M["juniper"], (ao * 0.8,) * 3, (min(1.0, ao + 0.2),) * 3)
        elif kind == "willow":
            n = int(20 * frac) + 3
            for i in range(n):
                a = rnd.random() * 2 * math.pi
                tilt = rnd.uniform(0.25, 0.9)
                up = Vector((math.cos(a) * tilt, math.sin(a) * tilt, 1)).normalized()
                side = Vector((-math.sin(a), math.cos(a), 0))
                s = rnd.uniform(1.4, 2.0)
                mb.card(Vector((math.cos(a) * 0.15, math.sin(a) * 0.15, -0.05)), up, side, s * 0.9, s, M["willow"],
                        (0.6, 0.6, 0.6), (1, 1, 1))
        else:
            n = int(9 * frac) + 2
            for i in range(n):
                # Arching frond: steep inner half, outer half bending over toward the ground.
                a = i / n * 2 * math.pi + rnd.uniform(-0.2, 0.2)
                out_d = Vector((math.cos(a), math.sin(a), 0))
                up1 = (out_d * 0.55 + Vector((0, 0, 1.0))).normalized()
                up2 = (out_d * 1.0 + Vector((0, 0, -0.15))).normalized()
                side = Vector((-math.sin(a), math.cos(a), 0))
                s = rnd.uniform(0.75, 1.05)
                mid = up1 * s * 0.5
                mb.card(Vector((0, 0, 0)), up1, side, s * 0.5, s * 0.5, M["fern"], (0.6, 0.6, 0.6), (0.85, 0.85, 0.85),
                        uv=(0, 0, 1, 0.5))
                mb.card(mid, up2, side, s * 0.5, s * 0.5, M["fern"], (0.85, 0.85, 0.85), (1, 1, 1), uv=(0, 0.5, 1, 1))
        out.append(mb.finish())
    return out


def build(name, fn, kwargs, preview=True):
    L.clear_scene()
    M = mats()
    res = fn(name, M=M, **kwargs)
    if isinstance(res, list):
        lod0, lod1 = res
        L.foliage_normals(lod0, Vector((0, 0, 0.3)), 0.5)
    else:
        lod0, cc, cr = res
        L.foliage_normals(lod0, cc, 0.6)
        lod1 = impostor_lod(name, lod0, cc, kwargs.get("H", 10))
    lod1.location.x = 0
    if preview:
        L.setup_world(1.0)
        L.add_sun()
        g = L.ground_plane(600)
        lod1.hide_render = True
        L.render_views([lod0], os.path.join(PREV, name + "_lod0.png"), size=(800, 1000),
                       views=((30, 6), (120, 6), (30, 50)))
        lod1.hide_render = False
        lod0.hide_render = True
        L.render_views([lod1], os.path.join(PREV, name + "_lod1.png"), size=(800, 1000), views=((30, 6),))
        lod0.hide_render = False
        bpy.data.objects.remove(g, do_unlink=True)
        for ob in [o for o in bpy.data.objects if o.name.startswith("PreviewSun")]:
            bpy.data.objects.remove(ob, do_unlink=True)
    os.makedirs(BLEND, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, name + ".blend"))
    L.export_glb([lod0, lod1], os.path.join(GLB, name + ".glb"))
    print("ASSET", name, L.stats(lod0), L.stats(lod1))


ASSETS = {
    "pine_a": (make_pine, {"seed": 11, "H": 20.0, "crown": 0.6, "n_br": 32}),
    "pine_b": (make_pine, {"seed": 23, "H": 24.0, "crown": 0.72, "n_br": 22, "flat": True}),
    "spruce_a": (make_spruce, {"seed": 31, "H": 19.0}),
    "spruce_b": (make_spruce, {"seed": 37, "H": 7.5, "young": True}),
    "birch_a": (make_birch, {"seed": 41, "H": 16.0}),
    "birch_b": (make_birch, {"seed": 43, "H": 13.0, "stems": 3}),
    "juniper": (make_card_plant, {"seed": 51, "kind": "juniper"}),
    "shrub": (make_card_plant, {"seed": 53, "kind": "willow"}),
    "fern": (make_card_plant, {"seed": 55, "kind": "fern"}),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    preview = "--no-preview" not in argv
    for a in argv:
        if a.startswith("--only="):
            only = a.split("=", 1)[1].split(",")
    os.makedirs(PREV, exist_ok=True)
    for name, (fn, kw) in ASSETS.items():
        if only and name not in only:
            continue
        build(name, fn, kw, preview)


if __name__ == "__main__":
    main()
