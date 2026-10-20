"""Rocks and deadwood for WORLD-TERRAIN-01 (Blender 5.2, background):

  blender -b --factory-startup --python tools/blender/env/make_rocks.py -- [--only boulder_a] [--no-preview]

Boulders (glacial erratics), stone clusters and a glacially rounded bedrock outcrop
("svaberg"), plus fallen logs and stumps. Rock surfaces get their look in Godot from
shaders/environment/rock.gdshader (triplanar rock, lichen, moss on top); the mesh carries
the shape and a baked cavity/AO vertex colour.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fn_env_lib as L  # noqa: E402
from make_trees import BLEND, GLB, PREV, TEX  # noqa: E402

L.set_tex_dir(TEX)


def rock_preview_material(name):
    """Blender-side stand-in for the Godot rock shader (grey rock, moss on top) so the
    previews show the intended read; Godot replaces it by name (Rock_*)."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], sep.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.7
    ramp.color_ramp.elements[0].color = (0.42, 0.41, 0.39, 1)
    ramp.color_ramp.elements[1].position = 0.97
    ramp.color_ramp.elements[1].color = (0.22, 0.30, 0.12, 1)
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(ramp.outputs["Color"], mix.inputs[6])
    nt.links.new(vc.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    return mat


def displaced_rock(name, seed, size, squash, sub, rough=0.35, facet=0.0, sink=0.25, mat=None):
    """Icosphere displaced with layered noise: rounded glacial block with a few flatter
    facets (fracture planes), flattened underside, sunk by `sink` of its height."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    off = Vector((rnd.uniform(0, 100), rnd.uniform(0, 100), rnd.uniform(0, 100)))
    planes = [Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.2, 1))).normalized() for _ in range(7)]
    for v in bm.verts:
        p = v.co.copy()
        n1 = noise.noise(p * 1.1 + off)
        n2 = noise.noise(p * 3.0 + off * 1.7)
        n3 = noise.noise(p * 7.0 + off * 2.3)
        r = 1.0 + rough * (0.62 * n1 + 0.3 * n2 + 0.08 * n3)
        q = p * r
        # Fracture facets: clip against a few planes (blocky gneiss look).
        for pl in planes:
            d = q.dot(pl) - (0.66 + 0.12 * ((hash(tuple(pl)) % 100) / 100.0))
            if d > 0 and facet > 0:
                q -= pl * d * facet
        v.co = Vector((q.x * size[0], q.y * size[1], q.z * size[2] * squash))
    zmin = min(v.co.z for v in bm.verts)
    zmax = max(v.co.z for v in bm.verts)
    h = zmax - zmin
    for v in bm.verts:
        v.co.z -= zmin + h * sink
        if v.co.z < -h * sink * 0.6:
            v.co.z = -h * sink * 0.6 + (v.co.z + h * sink * 0.6) * 0.2
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    # Cavity AO: darker where the surface folds inward and near the ground.
    col = bm.loops.layers.color.new("Col")
    uv = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        for lp in f.loops:
            v = lp.vert
            conc = 0.0
            for e in v.link_edges:
                o = e.other_vert(v)
                conc += (o.co - v.co).normalized().dot(v.normal)
            conc /= max(1, len(v.link_edges))
            ground = min(1.0, max(0.0, (v.co.z + 0.2) / 0.8))
            a = max(0.35, min(1.0, 0.9 - conc * 1.6)) * (0.6 + 0.4 * ground)
            lp[col] = (a, a, a, 1.0)
            lp[uv].uv = (v.co.x * 0.25, v.co.y * 0.25 + v.co.z * 0.25)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    if mat:
        me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def make_boulder(name, seed, size, M):
    mat = rock_preview_material("Rock_Boulder")
    lod0 = displaced_rock(name + "_LOD0", seed, size, 0.85, 4, rough=0.3, facet=0.75, sink=0.2, mat=mat)
    lod1 = displaced_rock(name + "_LOD1", seed, size, 0.85, 2, rough=0.3, facet=0.75, sink=0.2, mat=mat)
    return [lod0, lod1]


def make_outcrop(name, seed, M):
    """Glacially rounded bedrock: a broad low dome with stoss/lee asymmetry and joints."""
    rnd = random.Random(seed)
    mat = rock_preview_material("Rock_Outcrop")
    objs = []
    for lod, (nx, ny) in enumerate(((40, 28), (12, 9))):
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=nx, y_segments=ny, size=1.0)
        off = Vector((rnd.uniform(0, 50), rnd.uniform(0, 50), 0))
        for v in bm.verts:
            x, y = v.co.x * 9.0, v.co.y * 6.0
            r = math.sqrt((v.co.x) ** 2 + (v.co.y * 1.1) ** 2)
            dome = max(0.0, 1.0 - r * r) ** 0.8
            asym = 1.0 + 0.35 * v.co.x  # steeper lee side
            jn = noise.noise(Vector((x * 0.35, y * 0.35, 0)) + off)
            joint = abs(noise.noise(Vector((x * 0.15, y * 0.6, 3)) + off))
            z = 2.6 * dome * asym * (0.8 + 0.25 * jn) - 0.35 * (joint < 0.06) * dome
            v.co = Vector((x, y, z - 0.7))
        me = bpy.data.meshes.new(name + "_LOD%d" % lod)
        bm.normal_update()
        col = bm.loops.layers.color.new("Col")
        bm.loops.layers.uv.new("UVMap")
        for f in bm.faces:
            for lp in f.loops:
                a = 0.75 + 0.25 * max(0.0, min(1.0, lp.vert.co.z / 1.5))
                lp[col] = (a, a, a, 1)
        bm.to_mesh(me)
        bm.free()
        for p in me.polygons:
            p.use_smooth = True
        me.materials.append(mat)
        ob = bpy.data.objects.new(name + "_LOD%d" % lod, me)
        bpy.context.scene.collection.objects.link(ob)
        objs.append(ob)
    return objs


def make_stones(name, seed, M):
    rnd = random.Random(seed)
    mat = rock_preview_material("Rock_Small")
    out = []
    for lod, sub in ((0, 2), (1, 1)):
        parts = []
        for k in range(6):
            s = rnd.uniform(0.15, 0.45)
            ob = displaced_rock("tmp%d" % k, seed * 10 + k, (s * rnd.uniform(1.0, 1.5), s, s), 0.7, sub,
                                rough=0.3, facet=0.4, sink=0.3, mat=mat)
            ob.location = (rnd.uniform(-1.2, 1.2), rnd.uniform(-1.2, 1.2), 0)
            ob.rotation_euler.z = rnd.uniform(0, 6.3)
            parts.append(ob)
        rnd.seed(seed)
        bpy.ops.object.select_all(action="DESELECT")
        for ob in parts:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.ops.object.join()
        j = bpy.context.active_object
        j.name = name + "_LOD%d" % lod
        j.data.name = j.name
        out.append(j)
    return out


def make_log(name, seed, M):
    rnd = random.Random(seed)
    bark = L.image_material("Bark_Log", "bark_spruce_alb.png", "bark_spruce_nrm.png", roughness=0.95)
    wood = L.image_material("Wood_End", "wood_end_alb.png", None, roughness=0.9)
    out = []
    length = 7.0
    r0 = 0.24
    for lod, (sides, steps) in enumerate(((10, 8), (5, 3))):
        mb = L.MeshBuilder(name + "_LOD%d" % lod)
        pts = []
        rad = []
        for i in range(steps + 1):
            t = i / steps
            pts.append(Vector((-length / 2 + length * t, 0.08 * math.sin(t * 3 + seed), r0 * (1 - 0.35 * t) * 0.85)))
            rad.append(r0 * (1 - 0.45 * t))
        mb.tube(pts, rad, sides, bark, uv_u=2, uv_v_m=0.55, cap=False, col=(0.8, 0.8, 0.8))
        # End caps with end grain.
        for end, sgn in ((0, -1), (steps, 1)):
            c = pts[end]
            ring = []
            for k in range(sides):
                a = 2 * math.pi * k / sides * (-sgn)
                ring.append(c + Vector((0, math.cos(a), math.sin(a))) * rad[end])
            mb.face(ring, [(0.5 + 0.5 * math.cos(2 * math.pi * k / sides), 0.5 + 0.5 * math.sin(2 * math.pi * k / sides))
                           for k in range(sides)], wood)
        if lod == 0:
            # Broken branch stubs.
            for k in range(7):
                t = rnd.uniform(0.15, 0.95)
                base = Vector((-length / 2 + length * t, 0, r0 * 0.85 * (1 - 0.35 * t)))
                a = rnd.uniform(0, 2 * math.pi)
                d = Vector((rnd.uniform(-0.3, 0.3), math.cos(a), math.sin(a))).normalized()
                mb.tube([base, base + d * (r0 + rnd.uniform(0.15, 0.6))], [0.05, 0.015], 4, bark, uv_u=1, uv_v_m=0.4,
                        col=(0.7, 0.7, 0.7))
        out.append(mb.finish())
    return out


def make_stump(name, seed, M):
    rnd = random.Random(seed)
    bark = L.image_material("Bark_Log", "bark_spruce_alb.png", "bark_spruce_nrm.png", roughness=0.95)
    wood = L.image_material("Wood_End", "wood_end_alb.png", None, roughness=0.9)
    out = []
    for lod, sides in enumerate((12, 6)):
        mb = L.MeshBuilder(name + "_LOD%d" % lod)
        h = 0.45
        r = 0.3
        pts = [Vector((0, 0, -0.1)), Vector((0, 0, 0.12)), Vector((0, 0, h))]
        mb.tube(pts, [r * 1.45, r * 1.08, r], sides, bark, uv_u=2, uv_v_m=0.5, cap=False, col=(0.75, 0.75, 0.75),
                col_end=(1, 1, 1))
        top = []
        uvs = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            top.append(Vector((math.cos(a) * r, math.sin(a) * r, h + 0.03 * math.sin(a * 3 + seed))))
            uvs.append((0.5 + 0.5 * math.cos(a), 0.5 + 0.5 * math.sin(a)))
        mb.face(top, uvs, wood)
        if lod == 0:
            for k in range(4):
                a = rnd.uniform(0, 2 * math.pi)
                d = Vector((math.cos(a), math.sin(a), -0.25)).normalized()
                b = Vector((math.cos(a) * r * 0.9, math.sin(a) * r * 0.9, 0.05))
                mb.tube([b, b + d * 0.35, b + d * 0.7 + Vector((0, 0, -0.2))], [0.13, 0.09, 0.05], 5, bark,
                        uv_u=1, uv_v_m=0.5, col=(0.7, 0.7, 0.7))
        out.append(mb.finish())
    return out


ASSETS = {
    "boulder_a": (make_boulder, {"seed": 5, "size": (1.4, 1.1, 1.0)}),
    "boulder_b": (make_boulder, {"seed": 17, "size": (1.0, 0.9, 1.1)}),
    "outcrop": (make_outcrop, {"seed": 3}),
    "rocks_small": (make_stones, {"seed": 7}),
    "log": (make_log, {"seed": 2}),
    "stump": (make_stump, {"seed": 4}),
}


def build(name, fn, kw, preview):
    L.clear_scene()
    objs = fn(name, M=None, **kw)
    if preview:
        L.setup_world(1.0)
        L.add_sun()
        g = L.ground_plane(200)
        objs[1].hide_render = True
        L.render_views([objs[0]], os.path.join(PREV, name + "_lod0.png"), size=(900, 700),
                       views=((30, 18), (150, 18), (60, 60)))
        objs[1].hide_render = False
        objs[0].hide_render = True
        L.render_views([objs[1]], os.path.join(PREV, name + "_lod1.png"), size=(900, 700), views=((30, 18),))
        objs[0].hide_render = False
        bpy.data.objects.remove(g, do_unlink=True)
        for ob in [o for o in bpy.data.objects if o.name.startswith("PreviewSun")]:
            bpy.data.objects.remove(ob, do_unlink=True)
    os.makedirs(BLEND, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, name + ".blend"))
    L.export_glb(objs, os.path.join(GLB, name + ".glb"))
    print("ASSET", name, [L.stats(o) for o in objs])


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    preview = "--no-preview" not in argv
    for a in argv:
        if a.startswith("--only="):
            only = a.split("=", 1)[1].split(",")
    for name, (fn, kw) in ASSETS.items():
        if only and name not in only:
            continue
        build(name, fn, kw, preview)


if __name__ == "__main__":
    main()
