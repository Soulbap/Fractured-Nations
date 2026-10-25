"""WORLD-VISUALS-01 rocks, deadwood and ferns from the CC0 scans (Blender 5.2, background):

  blender -b --factory-startup --python tools/blender/env/make_props_v3.py -- [--only boulder_a,stump] [--no-preview]

For each library id the variants are scan meshes (Poly Haven, CC0; assets/environment/source/polyhaven/, fetched by
fetch_polyhaven.py) decimated to a game budget (LOD0 / LOD1), scaled to the size of the old asset of that id (its GLB is read
first, so the library colliders - boulders, outcrops - stay valid for every variant), sunk into the ground by a share of their
height (rocks lie in the soil, not on it) and exported to assets/environment/glb/<asset>[_v<k>].glb with one "Scan_<source>"
material each (albedo / normal / ORM textures copied next to the GLB by the exporter; tools/terrain_ref/import_env_assets.gd
binds them to shaders/environment/scan_prop.gdshader).

  boulder_a  3  large granite blocks (rock_moss_set_01, boulder_01)      id 9   collider sphere
  boulder_b  3  medium blocks (rock_moss_set_02)                          id 10  collider sphere
  outcrop    3  bedrock slabs (rock_moss_set_01, flattened)               id 12  collider sphere
  rocks_small 12 small stone clusters (rock_moss_set_02, rock_07, rock_09, stone_01)  id 11
  stump      3  decayed stumps (tree_stump_01/02) and a sawn clear-cut stump (pine_roots base)  id 14
  log        3  dead trunks (dead_tree_trunk, dead_tree_trunk_02) and a slash pile (dry_branches_medium_01) id 13
(Ferns: make_trees_v3.py - the fern_02 scan has no alpha, its fronds are opaque strips.)
"""
import json
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

SRC = os.path.join(REPO, "assets", "environment", "source", "polyhaven")
GLB = os.path.join(REPO, "assets", "environment", "glb")
BLEND = os.path.join(REPO, "assets", "environment", "blender")
PREV = os.path.join(REPO, "docs", "world_visuals01", "blender")
TEX = os.path.join(REPO, "assets", "environment", "textures")
L.set_tex_dir(TEX)

# asset -> (old GLB for the target size, budget LOD0 / LOD1 tris, sink share of height, variants)
# variant: list of parts (source id, object name, offset (x, y) in target-size units, scale share, yaw deg)
PROPS = {
    "boulder_a": ("boulder_a", (1800, 220), 0.18, [
        [("rock_moss_set_01", "rock_moss_set_01_rock01", (0, 0), 1.0, 0)],
        [("rock_moss_set_01", "rock_moss_set_01_rock04", (0, 0), 1.0, 40)],
        [("rock_moss_set_02", "rock_moss_set_02_rock10", (0, 0), 1.0, 160)],
    ]),
    "boulder_b": ("boulder_b", (1400, 180), 0.2, [
        [("rock_moss_set_02", "rock_moss_set_02_rock11", (0, 0), 1.0, 0)],
        [("rock_moss_set_02", "rock_moss_set_02_rock13", (0, 0), 1.0, 70)],
        [("rock_moss_set_02", "rock_moss_set_02_rock07", (0, 0), 1.0, 20),
         ("rock_moss_set_02", "rock_moss_set_02_rock08", (0.45, 0.25), 0.5, 120)],
    ]),
    "outcrop": ("outcrop", (2400, 300), 0.45, [
        [("rock_moss_set_01", "rock_moss_set_01_rock02", (0, 0), 1.0, 0),
         ("rock_moss_set_01", "rock_moss_set_01_rock03", (0.42, -0.2), 0.55, 50)],
        [("rock_moss_set_01", "rock_moss_set_01_rock05", (0, 0), 1.0, 90),
         ("rock_moss_set_01", "rock_moss_set_01_rock06", (-0.4, 0.15), 0.6, 10)],
        [("rock_moss_set_01", "rock_moss_set_01_rock06", (0, 0), 1.0, 200)],
    ]),
    "rocks_small": ("rocks_small", (900, 120), 0.3, [  # parts at ~half the old footprint: no collider, stays low
        [("rock_moss_set_02", "rock_moss_set_02_rock%02d" % (7 + (k % 7)), (0, 0), 0.5, k * 37),
         ("rock_moss_set_02", "rock_moss_set_02_rock%02d" % (7 + ((k + 3) % 7)), (0.3, 0.12 * (k % 3 - 1)), 0.3, k * 71),
         (("rock_07", "rock_07") if k % 2 else ("stone_01", "stone_01")) + ((-0.28, 0.2), 0.2, k * 13)]
        if k < 7 else
        [("rock_07", "rock_07", (0, 0), 0.5, k * 41), ("rock_09", "rock_09_LOD0", (0.25, -0.2), 0.28, k * 29),
         ("stone_01", "stone_01", (-0.22, 0.22), 0.22, k * 17)] + ([("rock_moss_set_02", "rock_moss_set_02_rock%02d" % (7 + k % 7),
                                                                     (0.05, 0.3), 0.35, k * 11)] if k % 2 else [])
        for k in range(12)
    ]),
    "stump": ("stump", (1500, 200), 0.05, [
        [("tree_stump_01", "tree_stump_01", (0, 0), 1.0, 0)],
        [("tree_stump_02", "tree_stump_02", (0, 0), 1.0, 0)],
        [("tree_stump_01", "tree_stump_01", (0, 0), 0.8, 120)],
    ]),
    "log": ("log", (1600, 200), 0.12, [
        [("dead_tree_trunk", "dead_tree_trunk", (0, 0), 1.0, 0)],
        [("dead_tree_trunk_02", "dead_tree_trunk_02", (0, 0), 1.0, 0)],
        [("dry_branches_medium_01", "dry_branches_medium_01_a", (0, 0), 0.4, 0),
         ("dry_branches_medium_01", "dry_branches_medium_01_b", (0.05, 0.08), 0.35, 40),
         ("dry_branches_medium_01", "dry_branches_medium_01_c", (-0.06, -0.04), 0.33, -30),
         ("dry_branches_medium_01", "dry_branches_medium_01_a", (0.02, -0.1), 0.3, 95)],
    ]),
}


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_gltf(aid):
    d = os.path.join(SRC, aid)
    g = [f for f in os.listdir(d) if f.endswith(".gltf")][0]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(d, g))
    return [o for o in bpy.data.objects if o not in before]


def world_bounds(objs):
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for ob in objs:
        if ob.type != "MESH":
            continue
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
            mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    return mn, mx


OLD_GLB = os.path.join(REPO, "assets", "environment", "source", "old_glb")


def old_size(asset):
    """LOD0 bounds of the old (WORLD-TERRAIN-01) asset: the target size of every variant. Read from a copy taken out of git
    before the first build (`git show <rev>:assets/environment/glb/<asset>.glb`), since the build overwrites <asset>.glb."""
    clear()
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OLD_GLB, asset + ".glb"))
    objs = [o for o in bpy.data.objects if o not in before and o.type == "MESH" and "LOD0" in o.name]
    mn, mx = world_bounds(objs)
    return mx - mn


def take(aid, name):
    """A single scan object as a standalone mesh object with transforms applied (copied out of the import)."""
    objs = import_gltf(aid)
    src = next(o for o in objs if o.name == name or o.name.startswith(name))
    src.data = src.data.copy()  # glTF instancing can share the mesh: modifiers only apply to single-user data
    if src.data.shape_keys:
        src.shape_key_clear()
    bpy.ops.object.select_all(action="DESELECT")
    src.select_set(True)
    bpy.context.view_layer.objects.active = src
    # Unparent with transform, apply.
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in objs:
        if o is not src:
            bpy.data.objects.remove(o, do_unlink=True)
    return src


def decimate(ob, tris):
    cur = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if cur <= tris:
        return
    m = ob.modifiers.new("dec", "DECIMATE")
    m.ratio = max(0.002, tris / cur)
    m.use_collapse_triangulate = True
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=m.name)
    after = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if after > tris * 1.5:
        print("DECIMATE WARNING", ob.name, cur, "->", after)


def rename_material(ob, aid):
    for i, m in enumerate(ob.data.materials):
        if m and not m.name.startswith("Scan_"):
            m.name = "Scan_" + aid


def build_variant(name, parts, target, budget, sink):
    """Parts placed by offsets in units of the target footprint, scaled together so the group matches the target size."""
    clear()
    pieces = []
    for (aid, oname, off, share, yaw) in parts:
        ob = take(aid, oname)
        rename_material(ob, aid)
        mn, mx = world_bounds([ob])
        # Centre on its footprint, base on z=0.
        ob.location -= Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mn.z))
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
        pieces.append((ob, off, share, yaw))
    # Group scale from the main piece: horizontal size to the target footprint.
    main = pieces[0][0]
    mn, mx = world_bounds([main])
    foot = max(mx.x - mn.x, mx.y - mn.y)
    t_foot = max(target.x, target.y)
    s_main = t_foot / max(foot, 1e-3)
    # Do not let a tall source become taller than ~1.4x the old height (collider sphere).
    h = (mx.z - mn.z) * s_main
    if h > target.z * 1.4:
        s_main *= target.z * 1.4 / h
    for (ob, off, share, yaw) in pieces:
        if ob is main:
            ob.scale = Vector((s_main * share,) * 3)
        else:
            mn2, mx2 = world_bounds([ob])
            f2 = max(mx2.x - mn2.x, mx2.y - mn2.y)
            k = t_foot * share / max(f2, 1e-3)
            ob.scale = Vector((k, k, k))
        ob.rotation_euler = (0, 0, math.radians(yaw))
        ob.location = Vector((off[0] * t_foot, off[1] * t_foot, 0))
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Join.
    bpy.ops.object.select_all(action="DESELECT")
    for (ob, _, _, _) in pieces:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = main
    if len(pieces) > 1:
        bpy.ops.object.join()
    ob = main
    mn, mx = world_bounds([ob])
    ob.location -= Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mn.z + (mx.z - mn.z) * sink))
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ob.name = name + "_LOD0"
    ob.data.name = name + "_LOD0"
    lod1 = ob.copy()
    lod1.data = ob.data.copy()
    bpy.context.scene.collection.objects.link(lod1)
    lod1.name = name + "_LOD1"
    lod1.data.name = name + "_LOD1"
    decimate(ob, budget[0])
    decimate(lod1, budget[1])
    for o in (ob, lod1):
        for p in o.data.polygons:
            p.use_smooth = True
    return ob, lod1


def scan_textures(aid, size=1024):
    """One shared texture set per scan: assets/environment/textures/scan_<aid>_{alb,nrm,orm}.png (1K)."""
    d = os.path.join(SRC, aid, "textures")
    for kind, tag in (("diff", "alb"), ("nor_gl", "nrm"), ("arm", "orm")):
        out = os.path.join(TEX, "scan_%s_%s.png" % (aid, tag))
        if os.path.exists(out):
            continue
        f = [x for x in os.listdir(d) if kind in x]
        if not f:
            continue
        im = bpy.data.images.load(os.path.join(d, f[0]))
        if tag != "alb":
            im.colorspace_settings.name = "Non-Color"
        im.scale(size, size)
        im.filepath_raw = out
        im.file_format = "PNG"
        im.save()
        bpy.data.images.remove(im)


def export(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_texcoords=True, export_normals=True, export_materials="EXPORT",
                              export_image_format="NONE")


def relink_images():
    """The glTF importer packs the scans' 2K maps into the .blend (~20 MB per asset): point every image at the shared 1K scan
    texture of the project instead and drop the packed copy, so the saved .blend stays small and still shows the material."""
    tags = {"diff": "alb", "nor_gl": "nrm", "rough": "orm", "arm": "orm"}
    for img in list(bpy.data.images):
        if img.packed_file is None:
            continue
        name = img.name.rsplit(".", 1)[0]
        for kind, tag in tags.items():
            if name.endswith("_" + kind):
                aid = name[: -len(kind) - 1]
                path = os.path.join(TEX, "scan_%s_%s.png" % (aid, tag))
                if os.path.exists(path):
                    img.unpack(method="REMOVE")
                    img.filepath = bpy.path.relpath(path)
                break


def preview(ob, path):
    L.setup_world(1.0)
    L.add_sun(rot=(math.radians(48), 0, math.radians(30)), energy=3.5)
    g = L.ground_plane(60, (0.22, 0.24, 0.14))
    L.render_views([ob], path, size=(600, 450), views=((30, 18),))
    bpy.data.objects.remove(g, do_unlink=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    previews = "--no-preview" not in argv
    for a in argv:
        if a.startswith("--only="):
            only = a.split("=", 1)[1].split(",")
    os.makedirs(PREV, exist_ok=True)
    os.makedirs(BLEND, exist_ok=True)
    report = {}
    for asset, (old, budget, sink, variants) in PROPS.items():
        if only and asset not in only:
            continue
        target = old_size(old)
        report[asset] = {"target": [round(v, 2) for v in target], "variants": []}
        for k, parts in enumerate(variants):
            name = asset if k == 0 else "%s_v%d" % (asset, k)
            lod0, lod1 = build_variant(name, parts, target, budget, sink)
            mn, mx = world_bounds([lod0])
            st0, st1 = L.stats(lod0), L.stats(lod1)
            report[asset]["variants"].append({"asset": name, "size": [round(v, 2) for v in (mx - mn)], "lod0": st0["tris"],
                                              "lod1": st1["tris"]})
            if previews:
                lod1.hide_render = True
                preview(lod0, os.path.join(PREV, name + "_pv.png"))
                lod1.hide_render = False
            for part in parts:
                scan_textures(part[0])
            relink_images()
            bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, name + ".blend"), compress=True)
            export([lod0, lod1], os.path.join(GLB, name + ".glb"))
            print("ASSET", name, st0, st1, [round(v, 2) for v in (mx - mn)], "target", [round(v, 2) for v in target])
    with open(os.path.join(GLB, "_props_v3_report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1)


if __name__ == "__main__":
    main()
