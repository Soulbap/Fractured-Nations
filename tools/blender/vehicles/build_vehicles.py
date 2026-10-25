"""VEHICLE-ASSETS-01 build entry point: the Norwegian / NATO vehicle pack.

Background Blender (reproducible, never touches an open scene):
    blender -b --factory-startup --python tools/blender/vehicles/build_vehicles.py -- [options]

Options:
    --only ID[,ID]    vehicles to build (default: all registered)
    --export          GLB + JSON sidecar (+ .import with the library post-import script) into
                      assets/military/vehicles/<id>/
    --save-blend      keep the built scene as assets/military/blender/vehicles/<id>.blend (editable source;
                      the folder is .gdignore'd like the other library .blend files)
    --previews DIR    Eevee renders (front 3/4, rear 3/4, side, elevated 3/4) + Workbench clay sheet
    --details         also the per-vehicle close-ups the builder defines (running gear, turret, rotor head)
    --lods            a LOD0 / LOD1 / LOD2 strip per vehicle (with --previews)
    --qa              BLENDER-SKILLS-01 gate (ap_qa) on every LOD0 part mesh
    --list            print the registered ids

Same library as the static assets (ap_lib / ap_materials / ap_textures, post-import
tools/asset_lab/ap_post_import.gd); vehicles add moving parts (ap_vehicle.Part).
"""
import importlib
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
for p in (HERE, os.path.join(HERE, "..", "asset_production"), os.path.join(HERE, "..", "character")):
    if p not in sys.path:
        sys.path.insert(0, p)

import bpy  # noqa: E402

import char_lib as L  # noqa: E402
import ap_textures as T  # noqa: E402
import ap_materials as AM  # noqa: E402
import ap_lib as A  # noqa: E402
import ap_vehicle as V  # noqa: E402
import veh_kit as K  # noqa: E402

MODULES = ["veh_iveco_lmv", "veh_patria_6x6", "veh_cv9030n", "veh_scania", "veh_leopard_2a8", "veh_nh90"]
OUT = os.path.join(REPO, "assets", "military", "vehicles")
TEX_DIR = os.path.join(REPO, "assets", "military", "textures")
MAT_DIR = os.path.join(REPO, "assets", "military", "materials")
BLEND_DIR = os.path.join(REPO, "assets", "military", "blender", "vehicles")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"only": None, "export": False, "save-blend": False, "previews": None, "details": False, "lods": False, "qa": False, "list": False}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--only", "--previews"):
            o[a[2:]] = argv[i + 1]
            i += 1
        elif a[2:] in o:
            o[a[2:]] = True
        i += 1
    return o


def registry():
    reg = {}
    for name in MODULES:
        try:
            mod = importlib.import_module(name)
        except ImportError as e:
            if name not in str(e):
                raise
            continue
        importlib.reload(mod)
        for vid, fn in mod.BUILDERS.items():
            reg[vid] = (mod, fn)
    return reg


def qa_vehicle(veh):
    import ap_qa as Q
    importlib.reload(Q)
    res = {"pass": True, "parts": {}}
    for n, p in veh.parts.items():
        if veh._is_template(n) and not any(q.source == n for q in veh.parts.values()):
            continue
        if p.source is not None or p.objs[0] is None:
            continue
        p.a.objs = p.objs
        p.a.qa = dict(veh.qa)
        r = Q.check_asset(p.a)
        res["parts"][n] = {"pass": r["pass"], "errors": r["errors"], "warnings": r["warnings"][:6]}
        res["pass"] = res["pass"] and r["pass"]
    return res


def main():
    t0 = time.time()
    o = parse_args()
    for m in (L, T, AM, A, V, K):
        importlib.reload(m)
    reg = registry()
    if o["list"]:
        print("FNVEHICLES", json.dumps(sorted(reg)))
        return
    only = set(o["only"].split(",")) if o["only"] else None
    if not os.path.exists(os.path.join(TEX_DIR, "camo_nato3.png")):
        T.camo_nato3(TEX_DIR)
    log = {}
    for vid, (mod, fn) in reg.items():
        if only is not None and vid not in only:
            continue
        t = time.time()
        L.clear_scene()
        coll = L.collection("Vehicle_" + vid)
        veh = fn()
        veh.build(coll, TEX_DIR)
        entry = {"tris": [veh.tris(i) for i in A.ALL], "objects": [len(veh.lod_objects(i)) for i in A.ALL],
                 "materials": veh.materials(0)}
        out_dir = os.path.join(OUT, vid)
        if o["qa"]:
            entry["qa"] = qa_vehicle(veh)
        if o["save-blend"]:
            os.makedirs(BLEND_DIR, exist_ok=True)
            bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND_DIR, vid + ".blend"), copy=True, compress=True)
        if o["export"]:
            meta = veh.export(out_dir, coll)
            if o["qa"]:
                meta["qa"] = entry["qa"]
                with open(os.path.join(out_dir, vid + ".json"), "w", encoding="utf-8") as f:
                    json.dump(meta, f, indent=1)
            entry["size"] = meta["size_above_ground"]
            entry["glb_bytes"] = meta["glb_bytes"]
        if o["previews"]:
            d = os.path.abspath(o["previews"])
            os.makedirs(d, exist_ok=True)
            r = V.render_previews(veh, d, TEX_DIR)
            entry["previews"] = [r["sheet"], r["clay"]]
            if o["details"] and hasattr(mod, "DETAILS"):
                for name, args in mod.DETAILS.get(vid, {}).items():
                    entry.setdefault("details", []).append(V.render_detail(veh, d, TEX_DIR, name, *args))
            if o["lods"]:
                shots = []
                for i in A.ALL:
                    shots += V.render_previews(veh, d, TEX_DIR, res=(800, 560), views=[("lod%d" % i, 38, 12, 1.05, 0.42, 50)],
                                               tag="%s_tmp" % vid, lod=i, clay=False)["views"]
                tmp = os.path.join(d, "%s_tmp_render.jpg" % vid)
                if os.path.exists(tmp):
                    os.remove(tmp)
                entry["lods"] = A.sheet(shots, os.path.join(d, "%s_lods.jpg" % vid), 3)
        entry["seconds"] = round(time.time() - t, 1)
        log[vid] = entry
        print("FNVEHICLE", vid, json.dumps(entry), flush=True)
    if o["export"]:
        AM.write_godot_materials(MAT_DIR, TEX_DIR, names=["Camo_NATO3", "Tyre", "Glass_Vehicle"])
    print("FNBUILD", json.dumps({"t_total": round(time.time() - t0, 1)}))


if __name__ == "__main__" or True:
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.stdout.flush()
        os._exit(1)
