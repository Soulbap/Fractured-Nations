"""Infrastructure and rural props for WORLD-TERRAIN-01 (Blender 5.2, background):

  blender -b --factory-startup --python tools/blender/env/make_structures.py -- [--only bridge_concrete]

Bridges are modules placed and scaled along each river crossing by ReferenceWorldBuilder:
  bridge_concrete : 12 m long, 10 m wide county-road deck (concrete slab, edge beams,
                    galvanised W-beam guard rail), Godot forward = -Z = Blender +Y
  bridge_pier     : concrete wall pier, top 1.4 m under the deck
  bridge_timber   : 6 m long, 4.6 m wide timber deck for tracks
Rural props: house (white/yellow timber house), barn (Falu-red låve with ramp), shed,
road_post (brøytestikk), mailbox, fence (skigard section, 4 m).
Flat colours + baked vertex AO; Godot keeps the colours (StandardMaterial3D) and tints
instances (house colour variants).
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fn_env_lib as L  # noqa: E402
from make_trees import BLEND, GLB, PREV, TEX  # noqa: E402

L.set_tex_dir(TEX)


class Boxer:
    """Box/prism builder into one MeshBuilder with flat shading and simple AO."""

    def __init__(self, name):
        self.mb = L.MeshBuilder(name)

    def box(self, c, size, mat, ao_bottom=0.75, rot_z=0.0, top_scale=1.0):
        cx, cy, cz = c
        sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
        R = Matrix.Rotation(rot_z, 3, "Z")
        p = [Vector((x * sx * (top_scale if z > 0 else 1), y * sy, z * sz)) for z in (-1, 1) for y in (-1, 1) for x in (-1, 1)]
        p = [R @ v + Vector((cx, cy, cz)) for v in p]
        faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        for f in faces:
            vs = [p[i] for i in f]
            cols = [(ao_bottom,) * 3 if i < 4 else (1, 1, 1) for i in f]
            # Box-mapped UVs (1 unit = 1 m).
            n = (vs[1] - vs[0]).cross(vs[2] - vs[0]).normalized()
            if abs(n.z) > 0.7:
                uvs = [(v.x, v.y) for v in vs]
            elif abs(n.x) > 0.7:
                uvs = [(v.y, v.z) for v in vs]
            else:
                uvs = [(v.x, v.z) for v in vs]
            self.mb.face(vs, uvs, mat, cols)

    def prism_roof(self, c, length, width, rise, mat, overhang=0.4, thick=0.2, rot_z=0.0):
        """Gable roof along local Y: two sloped slabs."""
        R = Matrix.Rotation(rot_z, 3, "Z")
        cx, cy, cz = c
        hl = length / 2 + overhang
        hw = width / 2 + overhang
        ridge = Vector((0, 0, rise))
        for side in (-1, 1):
            e0 = Vector((side * hw, -hl, -overhang * rise / (width / 2)))
            e1 = Vector((side * hw, hl, -overhang * rise / (width / 2)))
            r0 = Vector((0, -hl, rise))
            r1 = Vector((0, hl, rise))
            quad = [e0, e1, r1, r0] if side > 0 else [e1, e0, r0, r1]
            quad = [R @ q + Vector((cx, cy, cz)) for q in quad]
            self.mb.face(quad, [(0, 0), (length, 0), (length, 3), (0, 3)], mat, [(0.8,) * 3, (0.8,) * 3, (1, 1, 1), (1, 1, 1)])
            under = [q - Vector((0, 0, thick)) for q in reversed(quad)]
            self.mb.face(under, [(0, 0), (1, 0), (1, 1), (0, 1)], mat, [(0.5,) * 3] * 4)
        # Gable triangles.
        for end in (-1, 1):
            tri = [Vector((-width / 2, end * length / 2, 0)), Vector((width / 2, end * length / 2, 0)), Vector((0, end * length / 2, rise))]
            if end < 0:
                tri.reverse()
            tri = [R @ t + Vector((cx, cy, cz)) for t in tri]
            self.gable.append(tri)

    def finish(self):
        return self.mb.finish(smooth=False)


def M_():
    return {
        "concrete": L.flat_material("Concrete", (0.42, 0.41, 0.39), 0.9),
        "steel": L.flat_material("Steel_Galvanised", (0.62, 0.64, 0.66), 0.45, 0.7),
        "wood": L.flat_material("Wood_Weathered", (0.40, 0.34, 0.27), 0.9),
        "plank": L.flat_material("Wood_Planks", (0.36, 0.30, 0.24), 0.9),
        "red": L.flat_material("Paint_FaluRed", (0.42, 0.10, 0.07), 0.85),
        "white": L.flat_material("Paint_White", (0.86, 0.85, 0.80), 0.8),
        "roof": L.flat_material("Roof_Dark", (0.16, 0.16, 0.17), 0.75),
        "roof_tile": L.flat_material("Roof_Tile", (0.33, 0.15, 0.10), 0.8),
        "glass": L.flat_material("Glass_Dark", (0.06, 0.07, 0.08), 0.15),
        "orange": L.flat_material("Paint_Orange", (0.85, 0.35, 0.08), 0.6),
        "black": L.flat_material("Paint_Black", (0.05, 0.05, 0.05), 0.6),
        "green": L.flat_material("Paint_Green", (0.14, 0.28, 0.16), 0.6),
        "stone": L.flat_material("Stone_Foundation", (0.45, 0.44, 0.42), 0.9),
    }


def bridge_concrete(name, M, lod):
    b = Boxer(name + "_LOD%d" % lod)
    W, Lm = 10.0, 12.0
    b.box((0, 0, -0.35), (W, Lm, 0.7), M["concrete"])
    for s in (-1, 1):
        b.box((s * (W / 2 - 0.25), 0, 0.12), (0.5, Lm, 0.35), M["concrete"], 0.85)
        b.box((s * 2.6, 0, -1.15), (0.9, Lm, 1.0), M["concrete"], 0.6)
        if lod == 0:
            for k in range(6):
                y = -Lm / 2 + 1.0 + k * 2.0
                b.box((s * (W / 2 - 0.35), y, 0.62), (0.1, 0.12, 0.75), M["steel"], 0.8)
            b.box((s * (W / 2 - 0.42), 0, 0.82), (0.06, Lm, 0.32), M["steel"], 0.9)
            b.box((s * (W / 2 - 0.42), 0, 0.58), (0.04, Lm, 0.06), M["steel"], 0.9)
        else:
            b.box((s * (W / 2 - 0.42), 0, 0.7), (0.08, Lm, 0.5), M["steel"], 0.9)
    return b.finish()


def bridge_pier(name, M, lod):
    b = Boxer(name + "_LOD%d" % lod)
    b.box((0, 0, -1.65 - 6.0), (7.5, 1.1, 12.0), M["concrete"], 0.5)
    b.box((0, 0, -1.75), (8.6, 1.5, 0.3), M["concrete"], 0.8)
    return b.finish()


def bridge_timber(name, M, lod):
    rnd = random.Random(5)
    b = Boxer(name + "_LOD%d" % lod)
    W, Lm = 4.6, 6.0
    if lod == 0:
        n = 20
        for k in range(n):
            y = -Lm / 2 + (k + 0.5) * Lm / n
            b.box((rnd.uniform(-0.03, 0.03), y, -0.06), (W, Lm / n * 0.92, 0.12), M["plank"], 0.85)
    else:
        b.box((0, 0, -0.06), (W, Lm, 0.12), M["plank"], 0.85)
    for x in (-1.6, -0.5, 0.5, 1.6):
        b.box((x, 0, -0.42), (0.35, Lm, 0.6), M["wood"], 0.6)
    for s in (-1, 1):
        b.box((s * (W / 2 - 0.1), 0, 0.9), (0.14, Lm, 0.14), M["wood"])
        for y in (-Lm / 2 + 0.3, 0, Lm / 2 - 0.3):
            b.box((s * (W / 2 - 0.1), y, 0.45), (0.16, 0.16, 0.95), M["wood"], 0.8)
    return b.finish()


def _windows(b, M, cx, cy, wall_len, wall_axis, side, z, count, w=1.0, h=1.2, depth=0.06):
    """Window frames + glass on one wall (axis 'x' or 'y', side +-1)."""
    for k in range(count):
        t = (k + 0.5) / count - 0.5
        if wall_axis == "y":
            c = (cx + side * depth, cy + t * wall_len, z)
            b.box(c, (0.1, w + 0.18, h + 0.18), M["white"], 0.95)
            b.box((c[0] + side * 0.03, c[1], c[2]), (0.06, w, h), M["glass"], 1.0)
        else:
            c = (cx + t * wall_len, cy + side * depth, z)
            b.box(c, (w + 0.18, 0.1, h + 0.18), M["white"], 0.95)
            b.box((c[0], c[1] + side * 0.03, c[2]), (w, 0.06, h), M["glass"], 1.0)


def gable_building(name, M, lod, L_, W_, H_, rise, wall, roof, trim, windows, door=True, ramp=False):
    b = Boxer(name + "_LOD%d" % lod)
    b.gable = []
    b.box((0, 0, -0.25), (W_ + 0.3, L_ + 0.3, 0.6), M["stone"], 0.7)
    b.box((0, 0, H_ / 2), (W_, L_, H_), wall, 0.7)
    b.prism_roof((0, 0, H_), L_, W_, rise, roof, overhang=0.45)
    for tri in b.gable:
        b.mb.face(tri, [(0, 0), (1, 0), (0.5, 1)], wall, [(1, 1, 1)] * 3)
    if lod == 0:
        # Corner boards.
        for sx in (-1, 1):
            for sy in (-1, 1):
                b.box((sx * W_ / 2, sy * L_ / 2, H_ / 2), (0.22, 0.22, H_), trim, 0.9)
        for side in (-1, 1):
            for fl, z in enumerate([1.6, 4.3][: int(windows[1])]):
                _windows(b, M, side * W_ / 2, 0, L_ * 0.8, "y", side, z, int(windows[0]))
        if door:
            b.box((0, -L_ / 2 - 0.05, 1.1), (1.1, 0.12, 2.2), trim, 0.9)
            b.box((0, -L_ / 2 - 0.08, 1.05), (0.9, 0.06, 2.0), M["wood"], 0.9)
        if ramp:
            # Barn bridge (låvebru): earth ramp + timber deck to the upper floor.
            top = H_ * 0.42
            x0, x1, hw = W_ / 2, W_ / 2 + 7.0, 2.2
            deck = [Vector((x1, -hw, 0.0)), Vector((x1, hw, 0.0)), Vector((x0, hw, top)), Vector((x0, -hw, top))]
            b.mb.face(deck, [(0, 0), (4, 0), (4, 7), (0, 7)], M["plank"], [(0.85,) * 3] * 4)
            for s in (-1, 1):
                side = [Vector((x1, s * hw, 0.0)), Vector((x0, s * hw, top)), Vector((x0, s * hw, -0.3)), Vector((x1, s * hw, -0.3))]
                if s < 0:
                    side.reverse()
                b.mb.face(side, [(0, 0), (7, 0), (7, 1), (0, 1)], M["stone"], [(0.7,) * 3] * 4)
            b.box((x0 + 0.06, 0, top + 1.5), (0.15, 3.4, 3.0), M["wood"], 0.9)
        # Chimney.
        if not ramp:
            b.box((W_ * 0.15, L_ * 0.2, H_ + rise * 0.8), (0.6, 0.6, 2.0), M["stone"], 0.8)
    return b.finish()


def house(name, M, lod):
    return gable_building(name, M, lod, 11.0, 7.5, 5.6, 3.0, M["white"], M["roof_tile"], M["white"], (4, 2))


def barn(name, M, lod):
    return gable_building(name, M, lod, 20.0, 10.0, 6.0, 4.6, M["red"], M["roof"], M["white"], (5, 1),
                          door=True, ramp=True)


def shed(name, M, lod):
    return gable_building(name, M, lod, 4.5, 3.2, 2.4, 1.4, M["red"], M["roof"], M["white"], (1, 1))


def culvert(name, M, lod):
    """Corrugated steel culvert end (1.0 m) set in a dry-stone headwall; Godot places one
    on each side of the road fill, facing outward (-Y here = away from the road)."""
    b = Boxer(name + "_LOD%d" % lod)
    sides = 16 if lod == 0 else 8
    r = 0.5
    mb = b.mb
    pts = [Vector((0, -1.2, r)), Vector((0, 1.0, r))]
    mb.tube(pts, [r, r], sides, M["steel"], uv_u=4, uv_v_m=0.3, cap=False, col=(0.7, 0.7, 0.7))
    pts_in = [Vector((0, 1.0, r)), Vector((0, -1.2, r))]
    mb.tube(pts_in, [r * 0.95, r * 0.95], sides, M["steel"], uv_u=4, uv_v_m=0.3, cap=False, col=(0.25, 0.25, 0.25))
    # Dry-stone headwall around the pipe mouth (y = -1.2 .. -0.8), stones 0.3-0.5 m.
    rnd = random.Random(3)
    if lod == 0:
        for row in range(4):
            z = 0.17 + row * 0.33
            x = -1.5 + (0.22 if row % 2 else 0.0)
            while x < 1.5:
                w = rnd.uniform(0.32, 0.5)
                cx = x + w / 2
                if math.hypot(cx, z - r) > r + 0.12:
                    b.box((cx, -1.0, z), (w - 0.03, 0.45, 0.3), M["stone"], 0.65)
                x += w
    else:
        for sx in (-1, 1):
            b.box((sx * 1.05, -1.0, 0.65), (0.9, 0.45, 1.3), M["stone"], 0.65)
        b.box((0, -1.0, 1.2), (1.2, 0.45, 0.25), M["stone"], 0.65)
    return b.finish()


def road_post(name, M, lod):
    b = Boxer(name + "_LOD%d" % lod)
    b.box((0, 0, 1.0), (0.04, 0.04, 2.0), M["orange"] if lod == 0 else M["orange"], 0.9)
    b.box((0, 0, 1.85), (0.05, 0.05, 0.25), M["black"], 1.0)
    return b.finish()


def mailbox(name, M, lod):
    b = Boxer(name + "_LOD%d" % lod)
    b.box((0, 0, 0.55), (0.08, 0.08, 1.1), M["wood"], 0.8)
    b.box((0, 0.05, 1.18), (0.32, 0.45, 0.28), M["green"], 0.9)
    return b.finish()


def fence(name, M, lod):
    """Skigard: pairs of upright poles with slanted rails, 4 m section along Y."""
    rnd = random.Random(9)
    b = Boxer(name + "_LOD%d" % lod)
    for y in (-2.0, 0.0, 2.0):
        for x in (-0.12, 0.12):
            b.box((x, y, 0.65), (0.07, 0.07, 1.3), M["wood"], 0.7)
    n = 9 if lod == 0 else 3
    for k in range(n):
        y = -2.0 + (k + 0.5) * 4.0 / n
        mb = b.mb
        p0 = Vector((0, y - 0.9, 0.15))
        p1 = Vector((0, y + 0.9, 1.15))
        mb.tube([p0, p1], [0.04, 0.035], 4, M["wood"], uv_u=1, uv_v_m=1.0, col=(0.85, 0.85, 0.85))
    return b.finish()


ASSETS = {
    "bridge_concrete": bridge_concrete,
    "bridge_pier": bridge_pier,
    "bridge_timber": bridge_timber,
    "house": house,
    "barn": barn,
    "shed": shed,
    "culvert": culvert,
    "road_post": road_post,
    "mailbox": mailbox,
    "fence": fence,
}


def build(name, fn, preview):
    L.clear_scene()
    M = M_()
    objs = [fn(name, M, 0), fn(name, M, 1)]
    if preview:
        L.setup_world(1.0)
        L.add_sun()
        g = L.ground_plane(400, (0.30, 0.33, 0.20))
        if name.startswith("bridge"):
            g.location.z = -3.0
        objs[1].hide_render = True
        L.render_views([objs[0]], os.path.join(PREV, name + "_lod0.png"), size=(900, 650),
                       views=((35, 20), (215, 15), (60, 55)))
        objs[1].hide_render = False
        bpy.data.objects.remove(g, do_unlink=True)
    os.makedirs(BLEND, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, name + ".blend"))
    L.export_glb(objs, os.path.join(GLB, name + ".glb"))
    print("ASSET", name, [L.stats(o) for o in objs])


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    for a in argv:
        if a.startswith("--only="):
            only = a.split("=", 1)[1].split(",")
    for name, fn in ASSETS.items():
        if only and name not in only:
            continue
        build(name, fn, "--no-preview" not in argv)


if __name__ == "__main__":
    main()
