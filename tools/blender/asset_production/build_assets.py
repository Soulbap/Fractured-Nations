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
    --qa             BLENDER-SKILLS-01 review gate on LOD0 (ap_qa: z-fighting, detached parts,
                     normals, topology, UVs, budget); results into the sidecar ("qa") when
                     exporting and into --qa-report (default benchmarks/asset01/qa_report.json)
    --qa-strict      exit 1 when any asset fails the gate
    --qa-baseline P  with --qa-strict: fail only on findings that are new against this
                     recorded report (benchmarks/asset01/qa_baseline.json = the known backlog)
    --qa-sheets DIR  also render a random-colour review sheet per asset into DIR
    --qa-report P    where the run's QA summary is written
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

FAMILY_MODULES = {"building": ["fam_buildings"], "module": ["fam_modules"], "prop": ["fam_props", "fam_props_logistics", "fam_props_tactical"],
                  "road": ["fam_roads"], "vehicle": ["fam_vehicles"]}
FAMILY_DIRS = {"building": "buildings", "module": "modules", "prop": "props", "road": "roads", "vehicle": "vehicles"}

OUT = os.path.join(REPO, "assets", "military")
TEX_DIR = os.path.join(OUT, "textures")
MAT_DIR = os.path.join(OUT, "materials")
DEF_DIR = os.path.join(OUT, "defs")
BLEND_DIR = os.path.join(OUT, "blender")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"family": None, "only": None, "textures": False, "export": False, "previews": None, "lods": False, "list": False,
         "qa": False, "qa-strict": False, "qa-sheets": None, "qa-report": os.path.join(REPO, "benchmarks", "asset01", "qa_report.json"),
         "qa-baseline": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--family", "--only", "--previews", "--qa-sheets", "--qa-report", "--qa-baseline"):
            o[a[2:]] = argv[i + 1]
            i += 1
        elif a[2:] in o:
            o[a[2:]] = True
        i += 1
    if o["qa-strict"] or o["qa-sheets"]:
        o["qa"] = True
    return o


def registry():
    reg = {}
    for fam, names in FAMILY_MODULES.items():
        for mod_name in names:
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
    if o["textures"] or not os.path.exists(os.path.join(TEX_DIR, "palette.png")):
        AM.build_palette(TEX_DIR)
    log = {"assets": {}}
    metas = []
    qa_report = {"assets": {}, "failed": [], "new_findings": {}, "check": None}
    baseline = {}
    if o["qa"]:
        import ap_qa as Q
        importlib.reload(Q)
        qa_report["check"] = dict(Q.CHECK)
        if o["qa-baseline"] and os.path.exists(o["qa-baseline"]):
            with open(o["qa-baseline"], encoding="utf-8") as f:
                baseline = json.load(f).get("assets", {})
            qa_report["baseline"] = o["qa-baseline"]
    for aid, fam, fn in todo:
        t = time.time()
        L.clear_scene()
        coll = L.collection("Asset")
        asset = fn(A)
        asset.build(coll, TEX_DIR)
        entry = {"tris": [L.tri_count(x) if x else 0 for x in asset.objs]}
        qa = None
        if o["qa"]:
            qa = Q.check_asset(asset, o["qa-sheets"])
            qa_report["assets"][aid] = qa
            if not qa["pass"]:
                qa_report["failed"].append(aid)
            new = Q.new_findings(qa, baseline.get(aid)) if baseline else qa["errors"]
            if new:
                qa_report["new_findings"][aid] = new
            entry["qa"] = {"pass": qa["pass"], "errors": len(qa["errors"]), "new": len(new), "warnings": len(qa["warnings"]),
                           "over_budget": qa["stats"].get("over_budget", [])}
        if o["export"]:
            meta = asset.export(os.path.join(OUT, FAMILY_DIRS[fam]), coll)
            metas.append(meta)
            if fam in ("building", "module") and asset.structure is not None:
                A.write_structure_def(meta, DEF_DIR, "res://assets/military/%s/%s.glb" % (FAMILY_DIRS[fam], aid))
            entry["size"] = meta["size_above_ground"]
            if qa is not None:
                # The gate's verdict travels with the asset (sidecar), like its other numbers.
                sidecar = os.path.join(OUT, FAMILY_DIRS[fam], aid + ".json")
                with open(sidecar, encoding="utf-8") as f:
                    side = json.load(f)
                side["qa"] = {k: qa[k] for k in ("pass", "errors", "warnings", "accepted", "eps", "tol")}
                side["qa"]["over_budget"] = qa["stats"].get("over_budget", [])
                with open(sidecar, "w", encoding="utf-8") as f:
                    json.dump(side, f, indent=1)
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
    if o["qa"]:
        qa_report["checked"] = len(qa_report["assets"])
        os.makedirs(os.path.dirname(o["qa-report"]), exist_ok=True)
        with open(o["qa-report"], "w", encoding="utf-8") as f:
            json.dump(qa_report, f, indent=1)
        log["qa"] = {"checked": qa_report["checked"], "failed": qa_report["failed"], "new_findings": sorted(qa_report["new_findings"]),
                     "report": o["qa-report"]}
    log["t_total"] = round(time.time() - t0, 1)
    print("FNBUILD", json.dumps(log))
    # Strict: with a baseline, only new defects fail the build (the backlog is tracked, not
    # re-reported); without one, any failing asset does.
    if o["qa-strict"] and (qa_report["new_findings"] if baseline else qa_report["failed"]):
        sys.exit(1)



if __name__ == "__main__" or True:
    # Blender exits with code 0 on a Python exception; make failures visible to scripts.
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.stdout.flush()
        os._exit(1)
