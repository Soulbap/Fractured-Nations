"""WORLD-COVER-01 natural cover assets (Blender 5.2, background), built on the WORLD-VISUALS-01 scan prop pipeline:

  blender -b --factory-startup --python tools/blender/env/make_cover_v1.py -- [--only=cover_boulder,cover_log] [--no-preview]

Every asset is sized for infantry cover and has one collider every variant fits inside (the library entry in
assets/environment/nordic_library.tres, WORLD-COVER-01 ids 24-30; the box of a box collider is listed here as BOX and checked
against the built variants in the report):

  cover_boulder    3  large granite blocks, ~1.5 m above ground       id 24  sphere r 1.15
  cover_rockgroup  3  clusters of 3-4 blocks in a row, 0.6-0.8 m (partial cover)         id 25  box
  cover_ridge      2  low bedrock ridges, 0.9-1.0 m                      id 26  box
  cover_log        2  thick fallen spruce trunks, ~0.7 m              id 27  box
  cover_rootplate  2  wind-thrown trees: root plate on end + trunk    id 28  box (the plate)
  stone_wall       2  dry stone field walls, 6 m, ~0.9 m              id 29  box
  timber_stack     2  stacked spruce logs at a track side, ~1.0 m     id 30  box

Scans: Poly Haven (CC0, assets/environment/source/polyhaven, fetched by fetch_polyhaven.py). Exports to
assets/environment/glb/<asset>[_v<k>].glb (LOD0 / LOD1), .blend sources to assets/environment/blender/, previews to
docs/world_cover01/blender/. Godot: tools/terrain_ref/import_env_assets.gd -- --only=<assets>.
Axes: Blender X = the asset's long axis (Godot local x), Blender Y = depth (Godot local z), Z = up.
"""
import json
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fn_env_lib as L  # noqa: E402
import make_props_v3 as P  # noqa: E402

PREV = os.path.join(P.REPO, "docs", "world_cover01", "blender")
REPORT = os.path.join(P.GLB, "_cover_v1_report.json")

# asset -> (target size x / y / z (m, before sinking), budget LOD0 / LOD1, sink share, variants) for scan groups; variant parts as
# in make_props_v3 (source, object, offset in target-footprint units, share, yaw).
SCAN_GROUPS = {
    "cover_rockgroup": ((3.6, 1.6, 1.2), (2400, 300), 0.16, [
        [("rock_moss_set_02", "rock_moss_set_02_rock11", (-0.14, 0.0), 0.46, 10),
         ("rock_moss_set_02", "rock_moss_set_02_rock13", (0.06, 0.02), 0.44, 80),
         ("rock_moss_set_02", "rock_moss_set_02_rock10", (0.24, -0.02), 0.36, 140)],
        [("rock_moss_set_01", "rock_moss_set_01_rock04", (-0.12, 0.0), 0.5, 0),
         ("rock_moss_set_02", "rock_moss_set_02_rock07", (0.1, -0.02), 0.42, 60),
         ("rock_moss_set_02", "rock_moss_set_02_rock12", (0.26, 0.03), 0.32, 200)],
        [("rock_moss_set_01", "rock_moss_set_01_rock01", (-0.12, 0.0), 0.42, 0),
         ("rock_moss_set_02", "rock_moss_set_02_rock11", (0.08, 0.02), 0.44, 110),
         ("rock_moss_set_02", "rock_moss_set_02_rock13", (0.26, -0.03), 0.3, 300)],
    ]),
    "cover_ridge": ((6.4, 2.4, 1.6), (2600, 320), 0.3, [
        [("rock_moss_set_01", "rock_moss_set_01_rock02", (-0.13, 0.0), 0.6, 0),
         ("rock_moss_set_01", "rock_moss_set_01_rock05", (0.12, 0.02), 0.58, 180),
         ("rock_moss_set_01", "rock_moss_set_01_rock03", (0.32, -0.03), 0.32, 70)],
        [("rock_moss_set_01", "rock_moss_set_01_rock05", (-0.1, 0.0), 0.6, 0),
         ("rock_moss_set_01", "rock_moss_set_01_rock06", (0.15, 0.02), 0.56, 160),
         ("rock_moss_set_01", "rock_moss_set_01_rock02", (-0.34, -0.03), 0.3, 20)],
    ]),
}
# Collider boxes (Godot local: half length x, height above the origin, half depth z) and spheres, per library id.
COLLIDERS = {
    "cover_boulder": {"id": 24, "sphere": 1.15},
    "cover_rockgroup": {"id": 25, "box": (1.35, 0.85, 0.78)},
    "cover_ridge": {"id": 26, "box": (2.75, 1.1, 1.9)},
    "cover_log": {"id": 27, "box": (3.7, 0.68, 0.38)},
    "cover_rootplate": {"id": 28, "box": (0.55, 2.45, 1.6)},
    "stone_wall": {"id": 29, "box": (3.0, 0.85, 0.4)},
    "timber_stack": {"id": 30, "box": (2.05, 1.0, 0.8)},
}


def _join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = objs[0]
    ob.name = name
    ob.data.name = name
    return ob


def _apply(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def _lods(ob, name, budget):
    ob.name = name + "_LOD0"
    ob.data.name = name + "_LOD0"
    lod1 = ob.copy()
    lod1.data = ob.data.copy()
    bpy.context.scene.collection.objects.link(lod1)
    lod1.name = name + "_LOD1"
    lod1.data.name = name + "_LOD1"
    P.decimate(ob, budget[0])
    P.decimate(lod1, budget[1])
    for o in (ob, lod1):
        for p in o.data.polygons:
            p.use_smooth = True
    return ob, lod1


def _ground(ob, sink):
    """Centre on the footprint, base on z = 0, then sunk by a share of the height (rocks lie in the soil)."""
    mn, mx = P.world_bounds([ob])
    ob.location -= Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mn.z + (mx.z - mn.z) * sink))
    _apply(ob)


BOULDERS = [("rock_moss_set_01", "rock_moss_set_01_rock04", 30), ("rock_moss_set_01", "rock_moss_set_01_rock01", 200),
            ("rock_moss_set_02", "rock_moss_set_02_rock13", 110)]


def build_boulder(name, k):
    """A large mossy granite block (the same scans as the world's boulders) scaled by height, not footprint: about 1.45 m
    above the ground once sunk (a crouched soldier's head stays below its top), the footprint at most 3 m."""
    P.clear()
    src, oname, yaw = BOULDERS[k]
    ob = P.take(src, oname)
    P.rename_material(ob, src)
    mn, mx = P.world_bounds([ob])
    ob.location -= Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mn.z))
    ob.rotation_euler = (0, 0, math.radians(yaw))
    _apply(ob)
    mn, mx = P.world_bounds([ob])
    sink = 0.14
    s = min(1.45 / ((mx.z - mn.z) * (1.0 - sink)), 3.0 / max(mx.x - mn.x, mx.y - mn.y))
    ob.scale = (s, s, s)
    _apply(ob)
    _ground(ob, sink)
    return _lods(ob, name, (2200, 260))


def build_log(name, k):
    """A thick fallen spruce: the dead_tree_trunk scan stretched to 7.4 m (0.7 m thick), lying along X, a little sunk."""
    P.clear()
    ob = P.take("dead_tree_trunk", "dead_tree_trunk")
    P.rename_material(ob, "dead_tree_trunk")
    mn, mx = P.world_bounds([ob])
    ob.location -= Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mn.z))
    _apply(ob)
    s = (7.4 if k == 0 else 6.6) / (mx.x - mn.x)
    ob.scale = (s, s * (1.0 if k == 0 else 1.08), s * (1.0 if k == 0 else 1.08))
    ob.rotation_euler = (math.radians(1.5 if k == 0 else -2.0), 0, math.radians(0 if k == 0 else 180))
    _apply(ob)
    _ground(ob, 0.12)
    return _lods(ob, name, (2000, 260))


def _soil_material():
    """The root plate's soil: the dirt surface scan as a Scan_ material (scan_prop shader in Godot)."""
    m = bpy.data.materials.get("Scan_dirt") or bpy.data.materials.new("Scan_dirt")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    d = os.path.join(P.SRC, "dirt")
    f = [x for x in os.listdir(d) if "diff" in x] if os.path.isdir(d) else []
    if f:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(os.path.join(d, f[0]))
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (0.24, 0.18, 0.12, 1)
    return m


def build_rootplate(name, k):
    """A wind-thrown spruce: the torn-up root plate stands on end (a disk of soil about 2.6 m wide and 2.3 m high with the
    root_cluster_01 roots on its face) and the trunk runs from its middle down to the ground along +X. The plate is the cover:
    the collider box round the origin."""
    P.clear()
    rng = random.Random(6100 + k)
    # Soil disk, roughened.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=20, radius=1.0, location=(0, 0, 1.15))
    disk = bpy.context.active_object
    disk.scale = (0.32, 1.3 if k == 0 else 1.2, 1.18 if k == 0 else 1.08)
    _apply(disk)
    # A torn, ragged rim: each rim vertex pulled in or out.
    for v in disk.data.vertices:
        r2 = math.hypot(v.co.y, v.co.z - 1.15)
        if r2 > 0.6:
            f = rng.uniform(0.8, 1.15)
            v.co.y *= f
            v.co.z = 1.15 + (v.co.z - 1.15) * f
    _apply(disk)
    tex = bpy.data.textures.new("rp_noise_%d" % k, "CLOUDS")
    tex.noise_scale = 0.32
    tex.noise_depth = 3
    dm = disk.modifiers.new("disp", "DISPLACE")
    dm.texture = tex
    dm.strength = 0.42
    dm.mid_level = 0.5
    bpy.ops.object.modifier_apply(modifier=dm.name)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.uv.cube_project(cube_size=1.2)
    bpy.ops.object.mode_set(mode="OBJECT")
    disk.data.materials.append(_soil_material())
    # Stones the plate tore out of the ground.
    pebbles = []
    for k2 in range(5):
        st, dims = _stone(rng, *ROCK_PALETTE[rng.randrange(len(ROCK_PALETTE))])
        sc = rng.uniform(0.18, 0.34) / max(dims.x, dims.y, 1e-3)
        st.scale = (sc, sc, sc)
        a2 = rng.uniform(0, math.tau)
        rr2 = rng.uniform(0.2, 0.9)
        st.location = (-0.32, math.cos(a2) * rr2, 1.15 + math.sin(a2) * rr2 * 0.9)
        st.rotation_euler = (rng.uniform(0, 3), rng.uniform(0, 3), rng.uniform(0, 3))
        _apply(st)
        pebbles.append(st)
    # Torn roots on the underside (the face away from the trunk, -X) and round the rim: tapered spruce roots sticking out of
    # the soil, the thick ones near the centre, thin broken ones at the edge (bark of the trunk scan).
    trunk_mat = None
    roots = []
    for r_i in range(44):
        a = rng.uniform(0, math.tau)
        rr = rng.uniform(0.1, 1.05)
        base = Vector((-0.2, math.cos(a) * rr * 1.15, 1.15 + math.sin(a) * rr * 1.0))
        out = Vector((-rng.uniform(0.5, 1.0), math.cos(a) * rng.uniform(0.2, 0.8), math.sin(a) * rng.uniform(0.1, 0.7))).normalized()
        length = rng.uniform(0.6, 1.6) * (1.25 - rr * 0.5)
        rad = rng.uniform(0.06, 0.18) * (1.35 - rr * 0.6)
        bpy.ops.mesh.primitive_cone_add(vertices=7, radius1=rad, radius2=rad * 0.15, depth=length,
                                        location=base + out * length * 0.5)
        ob = bpy.context.active_object
        # A root crooks: subdivide along its length and bend it sideways and down with its distance from the plate.
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.subdivide(number_cuts=4)
        bpy.ops.object.mode_set(mode="OBJECT")
        bend = Vector((rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), 0.0))
        for v in ob.data.vertices:
            t = v.co.z / length + 0.5
            v.co += bend * (t * t) * length * 0.45 + Vector((0, 0, 0)) * t
            v.co.x += math.sin(t * 7.0 + r_i) * rad * 0.6
        ob.rotation_euler = Vector((0, 0, 1)).rotation_difference(out).to_euler()
        _apply(ob)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project()
        bpy.ops.object.mode_set(mode="OBJECT")
        roots.append(ob)
    # Trunk from the plate's middle to the ground.
    trunk = P.take("dead_tree_trunk", "dead_tree_trunk")
    P.rename_material(trunk, "dead_tree_trunk")
    P.decimate(trunk, 700)
    tmn, tmx = P.world_bounds([trunk])
    trunk.location -= Vector((tmn.x, (tmn.y + tmx.y) * 0.5, (tmn.z + tmx.z) * 0.5))
    _apply(trunk)
    length = 6.4 if k == 0 else 5.6
    ts = length / (tmx.x - tmn.x)
    trunk.scale = (ts, ts * 1.7, ts * 1.7)
    _apply(trunk)
    trunk.rotation_euler = (0, math.atan2(0.8, length), math.radians(rng.uniform(-6, 6)))
    trunk.location = (0.18, 0.0, 1.0)
    _apply(trunk)
    for ob in roots:
        ob.data.materials.append(trunk.data.materials[0])
    ob = _join([disk, trunk] + roots + pebbles, name)
    mn, mx = P.world_bounds([ob])
    ob.location.z -= max(mn.z, 0.0) + 0.08
    _apply(ob)
    return _lods(ob, name, (6500, 900))


def _stone(rng, src, oname):
    ob = P.take(src, oname)
    P.rename_material(ob, src)
    P.decimate(ob, 140)  # once per palette stone (a joined wall decimated at once loses its stones)
    mn, mx = P.world_bounds([ob])
    ob.location -= Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mn.z))
    _apply(ob)
    return ob, mx - mn


def soil_textures():
    """dirt is a surface scan (maps in its own folder, no textures/ subfolder): the same 1K scan_<id>_* set as
    the props' scans, for the Godot importer."""
    d = os.path.join(P.SRC, "dirt")
    for kind, tag in (("diff", "alb"), ("nor_gl", "nrm"), ("arm", "orm")):
        out = os.path.join(P.TEX, "scan_dirt_%s.png" % tag)
        if os.path.exists(out):
            continue
        f = [x for x in os.listdir(d) if kind in x]
        if not f:
            continue
        im = bpy.data.images.load(os.path.join(d, f[0]))
        if tag != "alb":
            im.colorspace_settings.name = "Non-Color"
        im.scale(1024, 1024)
        im.filepath_raw = out
        im.file_format = "PNG"
        im.save()
        bpy.data.images.remove(im)


ROCK_PALETTE = [("rock_moss_set_02", "rock_moss_set_02_rock%02d" % n) for n in (7, 8, 9, 10, 11, 12, 13)]


def build_wall(name, k):
    """A Scandinavian dry stone field wall (steingard): rounded mossy field stones (the closed granite scans, each decimated
    once to a game budget and then copied) in two to three courses on a wider base, 5.9 m long, about 0.9 m high and 0.8 m
    deep, the top ragged. One material: the copies share the palette's."""
    P.clear()
    rng = random.Random(4100 + k)
    palette = []
    for src, oname in ROCK_PALETTE:
        ob, dims = _stone(rng, src, oname)
        ob.hide_render = True
        palette.append((ob, dims))
    mat = palette[0][0].data.materials[0]
    for ob, _ in palette:
        ob.data.materials.clear()
        ob.data.materials.append(mat)
    stones = []
    x = -2.75
    while x < 2.8:
        for course, (z0, size, sides) in enumerate([(0.0, 0.5, (-0.2, 0.2)), (0.36, 0.44, (-0.1, 0.12)), (0.66, 0.36, (0.0,))]):
            if course == 2 and (rng.random() < 0.3 or abs(x) > 2.45):
                continue
            for side in sides:
                src, dims = palette[rng.randrange(len(palette))]
                ob = src.copy()
                bpy.context.scene.collection.objects.link(ob)
                ob.hide_render = False
                s = size * rng.uniform(0.85, 1.2) / max(dims.x, dims.y, 1e-3)
                ob.scale = (s, s * rng.uniform(0.9, 1.15), s * rng.uniform(0.8, 1.1))
                ob.rotation_euler = (rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(0, math.tau))
                ob.location = (x + rng.uniform(-0.05, 0.05), side + rng.uniform(-0.04, 0.04), z0 + rng.uniform(-0.03, 0.03))
                ob.data = ob.data.copy()
                _apply(ob)
                stones.append(ob)
        x += 0.42 + rng.uniform(-0.04, 0.05)
    for ob, _ in palette:
        bpy.data.objects.remove(ob, do_unlink=True)
    ob = _join(stones, name)
    _ground(ob, 0.08)
    mn, mx = P.world_bounds([ob])
    ob.scale = (5.9 / (mx.x - mn.x), 1.0, 1.0)
    _apply(ob)
    return _lods(ob, name, (12000, 2400))


def _bark_material():
    m = bpy.data.materials.get("Bark_Log3") or bpy.data.materials.new("Bark_Log3")
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.32, 0.25, 0.19, 1)
    e = bpy.data.materials.get("Wood_EndGrain") or bpy.data.materials.new("Wood_EndGrain")
    e.use_nodes = True
    e.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.74, 0.6, 0.42, 1)
    return m, e


def build_timber(name, k):
    """Felled spruce stacked at a forest track for collection: rows of 4 m logs (0.24-0.32 m thick), 5 - 4 - 3 (- 2), with
    pale cut ends; bark on the sides (Bark_Log3 -> the project's log bark shader), end grain flat."""
    P.clear()
    rng = random.Random(5200 + k)
    bark, end = _bark_material()
    logs = []
    rows = [5, 4, 3, 2] if k == 0 else [6, 5, 4]
    z = 0.0
    for r, n in enumerate(rows):
        d = 0.29
        y0 = -(n - 1) * d * 0.5
        for j in range(n):
            dia = rng.uniform(0.24, 0.32)
            bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=dia * 0.5, depth=4.0 + rng.uniform(-0.15, 0.15),
                                                location=(rng.uniform(-0.12, 0.12), y0 + j * d, z + dia * 0.5),
                                                rotation=(0, math.radians(90 + rng.uniform(-1.5, 1.5)), math.radians(rng.uniform(-2, 2))))
            ob = bpy.context.active_object
            # A real log tapers and is not round: thicker butt end, a little oval, rings slightly off.
            taper = rng.uniform(0.82, 0.92)
            flip = 1 if rng.random() < 0.5 else -1
            for v in ob.data.vertices:
                t = (v.co.z / max(ob.dimensions.z, 1e-3) + 0.5) if flip > 0 else (0.5 - v.co.z / max(ob.dimensions.z, 1e-3))
                k = 1.0 - (1.0 - taper) * t
                v.co.x *= k * rng.uniform(0.97, 1.03)
                v.co.y *= k * 0.94
            ob.data.materials.append(bark)
            ob.data.materials.append(end)
            for p in ob.data.polygons:
                p.material_index = 1 if len(p.vertices) > 4 else 0
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.uv.cylinder_project()
            bpy.ops.object.mode_set(mode="OBJECT")
            logs.append(ob)
        z += 0.26
    ob = _join(logs, name)
    _ground(ob, 0.0)
    return _lods(ob, name, (1200, 300))


CUSTOM = {"cover_boulder": (build_boulder, 3), "cover_log": (build_log, 2), "cover_rootplate": (build_rootplate, 2), "stone_wall": (build_wall, 2),
          "timber_stack": (build_timber, 2)}


def check_collider(asset, lod0):
    """The variant must lie inside its collider (Godot frame: x = length, y = up, z = depth)."""
    c = COLLIDERS[asset]
    mn, mx = P.world_bounds([lod0])
    size = mx - mn
    if "sphere" in c:
        r = c["sphere"]
        return {"fits": max(size.x, size.y) * 0.5 <= r * 1.35 and mx.z <= r * 1.3 + 0.15, "size": [round(v, 2) for v in size]}
    hx, h, hz = c["box"]
    fits = max(-mn.x, mx.x) <= hx * 1.08 + 0.05 and max(-mn.y, mx.y) <= hz * 1.15 + 0.05 and mx.z <= h * 1.12 + 0.05
    if asset == "cover_rootplate":
        fits = mx.z <= h * 1.15 + 0.1 and max(-mn.y, mx.y) <= hz * 1.15 + 0.05
    return {"fits": fits, "size": [round(v, 2) for v in size], "max_z": round(mx.z, 2)}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    previews = "--no-preview" not in argv
    for a in argv:
        if a.startswith("--only="):
            only = a.split("=", 1)[1].split(",")
    os.makedirs(PREV, exist_ok=True)
    os.makedirs(P.BLEND, exist_ok=True)
    report = json.load(open(REPORT, encoding="utf-8")) if os.path.exists(REPORT) else {}
    jobs = []
    for asset, (target, budget, sink, variants) in SCAN_GROUPS.items():
        for k, parts in enumerate(variants):
            jobs.append((asset, k, lambda n, kk, parts=parts, target=target, budget=budget, sink=sink:
                         P.build_variant(n, parts, Vector(target), budget, sink), [p[0] for p in parts]))
    for asset, (fn, n) in CUSTOM.items():
        srcs = {"cover_boulder": [b[0] for b in BOULDERS], "cover_log": ["dead_tree_trunk"],
                "cover_rootplate": ["dead_tree_trunk", "dirt", "rock_moss_set_02"],
                "stone_wall": ["rock_moss_set_02"], "timber_stack": []}[asset]
        for k in range(n):
            jobs.append((asset, k, fn, srcs))
    for asset, k, fn, srcs in jobs:
        if only and asset not in only:
            continue
        name = asset if k == 0 else "%s_v%d" % (asset, k)
        lod0, lod1 = fn(name, k)
        st0, st1 = L.stats(lod0), L.stats(lod1)
        chk = check_collider(asset, lod0)
        report.setdefault(asset, {"collider": COLLIDERS[asset], "variants": {}})
        report[asset]["collider"] = COLLIDERS[asset]
        report[asset]["variants"][name] = {"lod0": st0["tris"], "lod1": st1["tris"], **chk}
        if previews:
            lod1.hide_render = True
            P.preview(lod0, os.path.join(PREV, name + "_pv.png"))
            lod1.hide_render = False
        for src in srcs:
            if src == "dirt":
                soil_textures()
            else:
                P.scan_textures(src)
        P.relink_images()
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(P.BLEND, name + ".blend"), compress=True)
        P.export([lod0, lod1], os.path.join(P.GLB, name + ".glb"))
        print("COVER", name, st0, st1, chk)
    with open(REPORT, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1)


if __name__ == "__main__":
    main()
