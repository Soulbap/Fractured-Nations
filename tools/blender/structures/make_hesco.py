"""HESCO barrier cells for WORLD-BASE-01 (MIL1-type and MIL7-type from one recipe).

References (docs/WORLD-BASE-01_REPORT.md): galvanized welded mesh (76 mm squares) on
the outside, tan non-woven geotextile liner behind it, coil-spring hinge joints at the
cell corners, sand/gravel fill a few centimetres below the rim, slightly mounded and
darker; the liner shows above the fill. Cells stand vertical and step on slopes.

One cell per GLB, origin at the ground center, cell length along +X (the line
direction in Godot), a buried skirt down to -SKIRT so stepped cells on uneven ground
never show a gap. Run inside Blender:

    exec(open(r"<repo>/tools/blender/structures/make_hesco.py").read())
"""
import importlib.util
import math
import os

REPO = globals().get("REPO", r"C:\\Users\\Hafnor\\Desktop\\Game Dev\\fractured-nations")
PREVIEW_DIR = globals().get("PREVIEW_DIR", os.path.join(REPO, "assets", "structures", "previews"))
EXPORT = globals().get("EXPORT", True)


def _load(name, rel):
    spec = importlib.util.spec_from_file_location(name, os.path.join(REPO, *rel))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


lib = _load("fn_blender_lib", ("tools", "blender", "fn_blender_lib.py"))
sl = _load("fn_structures_lib", ("tools", "blender", "fn_structures_lib.py"))
import bpy  # noqa: E402

sl.set_texture_dir(os.path.join(REPO, "assets", "structures", "textures"))


def materials():
    geo = sl.textured("Geotextile", sl.tex_hesco_liner("hesco_geotextile", (0.68, 0.57, 0.39), seed=21), 0.61, roughness=0.95, double_sided=True)
    mesh = sl.textured("HescoMesh", sl.tex_grid_mesh("hesco_mesh", color=(0.55, 0.55, 0.52), cells=8, wire_px=5), 0.61, roughness=0.6, metallic=0.5, alpha=True, double_sided=True)
    fill_img = sl.tex_concrete("hesco_fill", color=(0.52, 0.45, 0.33), n=512, seed=23)
    fill = sl.textured("Fill", fill_img, 1.2, roughness=1.0)
    coil = sl.flat("Coil", (0.30, 0.31, 0.30), roughness=0.6, metallic=0.6)
    return geo, mesh, fill, coil


def build(name, cell, height, skirt):
    lib.clear_scene()
    geo, mesh, fill, coil = materials()
    h = cell * 0.5
    parts = []
    inset = 0.025
    # Liner: open-top box (sides only) slightly inside the mesh, subdivided and bulged a
    # little between the corners like a filled bag.
    n = 6
    verts, faces = [], []
    def side(p0, du, dv, nu, nv, outward, bulge):
        base = len(verts)
        for j in range(nv + 1):
            for i in range(nu + 1):
                u = i / nu
                v = j / nv
                b = bulge * math.sin(math.pi * u) * (0.35 + 0.65 * math.sin(math.pi * min(v * 1.1, 1.0)))
                p = [p0[k] + du[k] * u + dv[k] * v + outward[k] * b for k in range(3)]
                verts.append(p)
        for j in range(nv):
            for i in range(nu):
                a = base + j * (nu + 1) + i
                faces.append((a, a + 1, a + nu + 2, a + nu + 1))
    s = h - inset
    z0, z1 = -skirt, height - 0.01
    side((-s, -s, z0), (2 * s, 0, 0), (0, 0, z1 - z0), n, 4, (0, -1, 0), 0.018 * cell)
    side((s, -s, z0), (0, 2 * s, 0), (0, 0, z1 - z0), n, 4, (1, 0, 0), 0.018 * cell)
    side((s, s, z0), (-2 * s, 0, 0), (0, 0, z1 - z0), n, 4, (0, 1, 0), 0.018 * cell)
    side((-s, s, z0), (0, -2 * s, 0), (0, 0, z1 - z0), n, 4, (-1, 0, 0), 0.018 * cell)
    parts.append(sl.mesh_from("Liner", verts, faces, geo))
    # Inner liner band above the fill (seen from above), facing inward.
    fz = height - 0.07
    s2 = s - 0.01
    iv = [(-s2, -s2, fz - 0.05), (s2, -s2, fz - 0.05), (s2, s2, fz - 0.05), (-s2, s2, fz - 0.05),
          (-s2, -s2, z1), (s2, -s2, z1), (s2, s2, z1), (-s2, s2, z1)]
    parts.append(sl.mesh_from("LinerInner", iv, [(0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)], geo))
    # Fill: mounded sand surface.
    m = 6
    fv, ff = [], []
    for j in range(m + 1):
        for i in range(m + 1):
            x = -s2 + 2 * s2 * i / m
            y = -s2 + 2 * s2 * j / m
            mound = 0.05 * cell * math.sin(math.pi * i / m) * math.sin(math.pi * j / m)
            fv.append((x, y, fz + mound))
    for j in range(m):
        for i in range(m):
            a = j * (m + 1) + i
            ff.append((a, a + 1, a + m + 2, a + m + 1))
    parts.append(sl.mesh_from("Fill", fv, ff, fill))
    # Welded mesh: four outer faces (double sided in Godot), from the skirt to the rim.
    mz0, mz1 = -skirt, height
    mv = [(-h, -h, mz0), (h, -h, mz0), (h, h, mz0), (-h, h, mz0), (-h, -h, mz1), (h, -h, mz1), (h, h, mz1), (-h, h, mz1)]
    parts.append(sl.mesh_from("Mesh", mv, [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], mesh))
    # Top rim wire and coil hinges at the four corners.
    for (x, y) in ((-h, -h), (h, -h), (h, h), (-h, h)):
        parts.append(lib.cylinder("Coil", 0.012, mz1 - mz0, (x, y, (mz0 + mz1) * 0.5), coil, verts=6))
    for (a, b, rot) in (((0, -h, height), 2 * h, (0, math.radians(90), 0)), ((0, h, height), 2 * h, (0, math.radians(90), 0)),
                        ((-h, 0, height), 2 * h, (math.radians(90), 0, 0)), ((h, 0, height), 2 * h, (math.radians(90), 0, 0))):
        parts.append(lib.cylinder("Rim", 0.008, b, a, coil, rot=rot, verts=5))
    obj = lib.join(parts, name)
    # join() welds duplicate verts; the liner seams are separate walls anyway.
    sl.box_uv(obj)
    sl.ground_ao(obj, height=0.55 * height, strength=0.45)
    return obj


def run():
    results = {}
    for name, cell, height, skirt in (("hesco", 1.06, 1.37, 0.35), ("hesco_tall", 2.13, 2.21, 0.45)):
        obj = build(name, cell, height, skirt)
        r = lib.stats(obj)
        if PREVIEW_DIR:
            base = os.path.join(PREVIEW_DIR, name)
            r["previews"] = sl.preview_set(lib, obj, base, [("persp", 35, 18, None), ("low", 15, 4, cell * 2.6), ("high", 210, 45, None)])
            r["top"] = sl.top_view(obj, base + "_top.png")
            lib.remove_preview_rig()
        if EXPORT:
            r["glb_bytes"] = lib.export_glb(obj, os.path.join(REPO, "assets", "structures", name + ".glb"))
            lib.save_blend(os.path.join(REPO, "assets", "structures", "blender", name + ".blend"))
        results[name] = r
    return results


result = run()
