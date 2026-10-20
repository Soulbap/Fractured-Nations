"""ASSET-PRODUCTION-01 build entry point for the static asset library.

Background Blender (reproducible, never touches an open scene):
    blender -b --factory-startup --python tools/blender/asset_production/build_assets.py -- [options]

Options:
    --family F[,F]   building | module | prop | road | vehicle (default: all)
    --only ID[,ID]   only these asset ids
    --textures       regenerate the shared textures (assets/military/textures)
    --export         write GLB + JSON (+ StructureDef for buildings/modules) + Godot materials
    --previews DIR   Blender preview renders (contact sheet per asset) into DIR
    --lods           also render a LOD0/LOD1/LOD2 strip per asset (with --previews)
    --list           print the registered asset ids and exit
"""
import importlib
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
for p in (HERE, os.path.join(HERE, "..", "character")):
    if p not in sys.path:
        sys.path.insert(0, p)

import bpy  # noqa: E402

import char_lib as L  # noqa: E402
import ap_textures as T  # noqa: E402
import ap_materials as AM  # noqa: E402
import ap_lib as A  # noqa: E402

FAMILY_MODULES = {"building": "fam_buildings", "module": "fam_modules", "prop": "fam_props",
                  "road": "fam_roads", "vehicle": "fam_vehicles"}
FAMILY_DIRS = {"building": "buildings", "module": "modules", "prop": "props", "road": "roads", "vehicle": "vehicles"}

OUT = os.path.join(REPO, "assets", "military")
TEX_DIR = os.path.join(OUT, "textures")
MAT_DIR = os.path.join(OUT, "materials")
DEF_DIR = os.path.join(OUT, "defs")
BLEND_DIR = os.path.join(OUT, "blender")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"family": None, "only": None, "textures": False, "export": False, "previews": None, "lods": False, "list": False}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--family", "--only", "--previews"):
            o[a[2:]] = argv[i + 1]
            i += 1
        elif a[2:] in o:
            o[a[2:]] = True
        i += 1
    return o


def registry():
    reg = {}
    for fam, mod_name in FAMILY_MODULES.items():
        try:
            mod = importlib.import_module(mod_name)
        except ImportError as e:
            if mod_name not in str(e):
                raise
            continue
        importlib.reload(mod)
        for aid, fn in mod.BUILDERS.items():
            reg[aid] = (fam, fn)
    return reg


def update_catalog(metas):
    path = os.path.join(OUT, "catalog.json")
    cat = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            cat = json.load(f)
    for m in metas:
        cat[m["id"]] = {k: m[k] for k in ("family", "display_name", "category", "size_above_ground", "footprint_xy",
                                          "tris", "surfaces", "materials", "glb_bytes")}
        cat[m["id"]]["glb"] = "res://assets/military/%s/%s.glb" % (FAMILY_DIRS[m["family"]], m["id"])
    with open(path, "w", encoding="utf-8") as f:
        json.dump(dict(sorted(cat.items())), f, indent=1)


def main():
    t0 = time.time()
    o = parse_args()
    for m in (L, T, AM, A):
        importlib.reload(m)
    reg = registry()
    if o["list"]:
        print("FNASSETS", json.dumps({k: v[0] for k, v in reg.items()}))
        return
    fams = set(o["family"].split(",")) if o["family"] else set(FAMILY_MODULES)
    only = set(o["only"].split(",")) if o["only"] else None
    todo = [(aid, fam, fn) for aid, (fam, fn) in reg.items() if fam in fams and (only is None or aid in only)]
    if o["textures"] or not os.path.exists(os.path.join(TEX_DIR, "paint.png")):
        T.build_all(TEX_DIR)
        import ap_signs
        importlib.reload(ap_signs)
        ap_signs.build(TEX_DIR)
    log = {"assets": {}}
    metas = []
    for aid, fam, fn in todo:
        t = time.time()
        L.clear_scene()
        coll = L.collection("Asset")
        asset = fn(A)
        asset.build(coll, TEX_DIR)
        entry = {"tris": [L.tri_count(x) if x else 0 for x in asset.objs]}
        if o["export"]:
            meta = asset.export(os.path.join(OUT, FAMILY_DIRS[fam]), coll)
            metas.append(meta)
            if fam in ("building", "module") and asset.structure is not None:
                A.write_structure_def(meta, DEF_DIR, "res://assets/military/%s/%s.glb" % (FAMILY_DIRS[fam], aid))
            entry["size"] = meta["size_above_ground"]
        if o["previews"]:
            d = os.path.abspath(o["previews"])
            os.makedirs(d, exist_ok=True)
            shots = A.render_asset(asset, d, TEX_DIR)
            A.sheet(shots, os.path.join(d, aid + ".jpg"), 2)
            if o["lods"]:
                A.render_lod_strip(asset, d, TEX_DIR)
        entry["seconds"] = round(time.time() - t, 1)
        log["assets"][aid] = entry
        print("FNASSET", aid, json.dumps(entry), flush=True)
    if o["export"]:
        AM.write_godot_materials(MAT_DIR, TEX_DIR)
        if metas:
            update_catalog(metas)
    log["t_total"] = round(time.time() - t0, 1)
    print("FNBUILD", json.dumps(log))


main()
