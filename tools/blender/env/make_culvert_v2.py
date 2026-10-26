"""WORLD-DETAIL-02 culvert end (stikkrenne) for the road crossings of ref_20km (Blender 5.2, background):

  blender -b --factory-startup --python tools/blender/env/make_culvert_v2.py -- [--no-preview]

Replaces the VISUAL-02 culvert of make_structures.py (a pipe in a free-standing dry-stone headwall, which stood up beside the
road like a block). A Norwegian road culvert is a corrugated steel pipe under the fill whose end stands 0.75 m out of the
foot of the slope (slightly mitred: a terrain cannot have a hole), with a few stones set round the outlet against scour. The pipe runs 4.5 m back
under the fill so the ground hides it wherever the slope is steeper or flatter.

Frame (as the old asset; ReferenceWorldBuilder / CulvertSeat place it): origin on the ground at the mouth's invert, the mouth
facing -Y (Godot +Z: away from the road), the pipe running +Y (towards the road). Material Bld_RoofSheet (corrugated
galvanised steel, shaders/environment/building.gdshader) for the pipe, the moss-rock scans for the stones.
Export: assets/environment/glb/culvert.glb (LOD0 / LOD1) -> tools/terrain_ref/import_env_assets.gd -- --only=culvert.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fn_env_lib as L  # noqa: E402
import make_props_v3 as P  # noqa: E402
import make_cover_v1 as C  # noqa: E402

PREV = os.path.join(P.REPO, "docs", "world_detail02", "blender")
R_OUT = 0.44      # 0.8 m bore + corrugation
R_IN = 0.40
LENGTH = 4.5      # back under the fill
MITRE = 0.4       # the mitre: 0.4 m back per metre up
PROUD = 0.75      # the invert of the mouth stands this far out from the foot of the fill (a terrain cannot have a hole)
AXIS_Z = R_OUT - 0.07   # invert a little below the origin (the bed of the ditch)


def _pipe_material():
    m = bpy.data.materials.get("Bld_RoofSheet") or bpy.data.materials.new("Bld_RoofSheet")
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.43, 0.43, 1)
    return m


def _pipe(name, segs, rings_back):
    """The pipe: outer and inner wall, the mitred rim between them at the mouth, open at the buried end (never seen)."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    zb = AXIS_Z - R_OUT

    def ring(r, y_back):
        vs = []
        for i in range(segs):
            t = i / segs * math.tau
            x, z = r * math.cos(t), AXIS_Z + r * math.sin(t)
            # Mitre: the end plane leans back with the fill slope from the invert.
            y0 = -PROUD + (z - zb) * MITRE if y_back == 0.0 else y_back
            vs.append(bm.verts.new((x, y0, z)))
        return vs

    def band(a, b, flip, u_scale):
        for i in range(segs):
            j = (i + 1) % segs
            q = [a[i], a[j], b[j], b[i]]
            if flip:
                q.reverse()
            f = bm.faces.new(q)
            for lp in f.loops:
                ang = math.atan2(lp.vert.co.z - AXIS_Z, lp.vert.co.x)
                # Corrugations run round the pipe: the sheet's ribs (along its V) across the pipe's length.
                lp[uv].uv = (lp.vert.co.y / 2.0, (ang % math.tau) * R_OUT / 2.0 * u_scale)
    outer = [ring(R_OUT, 0.0)] + [ring(R_OUT, LENGTH * k / rings_back) for k in range(1, rings_back + 1)]
    inner = [ring(R_IN, 0.0)] + [ring(R_IN, LENGTH * k / rings_back) for k in range(1, rings_back + 1)]
    # The first ring of each wall is the mitred end (ring(..., 0.0)); the others are square cuts further back.
    for k in range(rings_back):
        band(outer[k], outer[k + 1], True, 1.0)
        band(inner[k], inner[k + 1], False, 1.0)
    band(outer[0], inner[0], False, 1.0)
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(_pipe_material())
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def build(name):
    P.clear()
    rng = random.Random(8080)
    pipe0 = _pipe(name + "_pipe0", 24, 3)
    pipe1 = _pipe(name + "_pipe1", 12, 1)
    # Stones: an apron in front of the mouth (the outlet channel kept clear down its middle) and a few set in the slope
    # beside the pipe end.
    palette = []
    for src, oname in C.ROCK_PALETTE:
        ob, dims = C._stone(rng, src, oname)
        ob.hide_render = True
        palette.append((ob, dims))
    mat = palette[0][0].data.materials[0]
    for ob, _ in palette:
        ob.data.materials.clear()
        ob.data.materials.append(mat)
    stones = []
    spots = []
    for k in range(16):
        y = -PROUD - rng.uniform(0.1, 1.6)
        x = rng.uniform(-1.4, 1.4)
        if abs(x) < 0.3 + 0.1 * (-y):
            x = math.copysign(0.3 + 0.1 * (-y) + rng.uniform(0.05, 0.4), x if x != 0 else 1.0)
        spots.append((x, y, 0.0, rng.uniform(0.22, 0.42)))
    for side in (-1, 1):
        for k in range(3):
            y = rng.uniform(-PROUD, 0.6)
            spots.append((side * (R_OUT + rng.uniform(0.1, 0.4)), y, max(0.0, y) / 1.5, rng.uniform(0.25, 0.45)))
    for (x, y, z, size) in spots:
        src, dims = palette[rng.randrange(len(palette))]
        ob = src.copy()
        ob.data = src.data.copy()
        bpy.context.scene.collection.objects.link(ob)
        ob.hide_render = False
        s = size / max(dims.x, dims.y, 1e-3)
        ob.scale = (s, s * rng.uniform(0.85, 1.15), s * rng.uniform(0.6, 0.9))
        ob.rotation_euler = (rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), rng.uniform(0, math.tau))
        # Set into the ground: 40 % of the stone below it.
        ob.location = (x, y, z - dims.z * ob.scale.z * 0.4)
        C._apply(ob)
        stones.append(ob)
    for ob, _ in palette:
        bpy.data.objects.remove(ob, do_unlink=True)
    lod0 = C._join([pipe0] + stones, name + "_LOD0")
    # LOD1: the coarse pipe and every other stone as a low ico sphere.
    lod1_stones = []
    for (x, y, z, size) in spots[::2]:
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=size * 0.5, location=(x, y, z))
        st = bpy.context.active_object
        st.scale = (1.0, 1.0, 0.55)
        C._apply(st)
        st.data.materials.append(mat)
        lod1_stones.append(st)
    lod1 = C._join([pipe1] + lod1_stones, name + "_LOD1")
    return lod0, lod1


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    name = "culvert"
    lod0, lod1 = build(name)
    st0, st1 = L.stats(lod0), L.stats(lod1)
    os.makedirs(PREV, exist_ok=True)
    if "--no-preview" not in argv:
        lod1.hide_render = True
        P.preview(lod0, os.path.join(PREV, name + "_pv.png"))
        lod1.hide_render = False
    for src in ("rock_moss_set_02",):
        P.scan_textures(src)
    P.relink_images()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(P.BLEND, name + "_v2.blend"), compress=True)
    P.export([lod0, lod1], os.path.join(P.GLB, name + ".glb"))
    print("CULVERT", st0, st1)


if __name__ == "__main__":
    main()
