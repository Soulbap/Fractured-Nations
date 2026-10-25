"""WEAPON-ASSETS-01 build entry point: the NATO / Russian weapon pack on the CHARACTER-01 weapon contract.

Background Blender (reproducible, never touches an open scene):
    blender -b --factory-startup --python tools/blender/weapons/build_weapons.py -- [options]

Options:
    --only ID[,ID]   weapons to build (ids without the weapon_ prefix: hk416, ak12, ...)
    --export         GLB + JSON sidecar into assets/weapons/<faction>/<id>/, InfantryEquipment .tres
                     (assets/weapons/<faction>/<id>/weapon_<id>.tres), the new library textures
    --save-blend     editable source assets/weapons/<faction>/<id>/source/weapon_<id>.blend (.gdignore'd)
    --previews DIR   left, right, front 3/4, rear 3/4, first-person hip and first-person aim views
                     (+ a LOD0/1/2 strip and a clay sheet) per weapon
    --list           print the registered ids
"""
import importlib
import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
CHAR = os.path.join(HERE, "..", "character")
for p in (HERE, CHAR):
    if p not in sys.path:
        sys.path.insert(0, p)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import char_lib as L  # noqa: E402
import char_materials as CM  # noqa: E402
import char_textures as CT  # noqa: E402
import wpn_lib as W  # noqa: E402

MODULES = ["wpn_nato_rifles", "wpn_nato_mg", "wpn_nato_other", "wpn_nato_launchers", "wpn_ru_rifles", "wpn_ru_other", "wpn_ru_launchers"]
OUT = os.path.join(REPO, "assets", "weapons")
TEX_DIR = os.path.join(REPO, "assets", "characters", "infantry", "textures")

# Weapon finishes added to the CHARACTER-01 library (same rows in scripts/characters/infantry_materials.gd).
WEAPON_MATERIALS = {
    "Weapon_Anodized":  ((0.052, 0.052, 0.055), 0.48, 0.60, "polymer", "polymer_n", 0.35, CT.TILE_HARD_M),
    "Weapon_Phosphate": ((0.080, 0.080, 0.076), 0.60, 0.65, "polymer", "polymer_n", 0.45, CT.TILE_HARD_M),
    "Weapon_PaintBlack": ((0.036, 0.036, 0.038), 0.46, 0.25, "polymer", "polymer_n", 0.30, CT.TILE_HARD_M),
    "Polymer_Tan":      ((0.62, 0.53, 0.38), 0.68, 0.0, "polymer", "polymer_n", 0.7, CT.TILE_HARD_M),
    "Polymer_Plum":     ((0.32, 0.14, 0.12), 0.60, 0.0, "polymer", "polymer_n", 0.7, CT.TILE_HARD_M),
    "Polymer_Green":    ((0.27, 0.30, 0.22), 0.66, 0.0, "polymer", "polymer_n", 0.6, CT.TILE_HARD_M),
    "Wood_Laminate":    ((1.00, 1.00, 1.00), 0.62, 0.0, "wood", "wood_n", 0.5, 0.30),
    "Launcher_OD":      ((0.20, 0.215, 0.15), 0.72, 0.0, "polymer", "polymer_n", 0.45, CT.TILE_HARD_M),
    "Launcher_Green":   ((0.21, 0.26, 0.17), 0.62, 0.05, "polymer", "polymer_n", 0.40, CT.TILE_HARD_M),
    "Composite_Dark":   ((0.070, 0.074, 0.068), 0.52, 0.10, "polymer", "polymer_n", 0.50, CT.TILE_HARD_M),
}
for k, v in WEAPON_MATERIALS.items():
    CM.MATERIALS.setdefault(k, v)

FPS_VIEWS = {
    # weapon-space camera offset from the grip (Blender axes) for the Viewmodel's HIP / ADS
    # placements (scripts/combat/viewmodel.gd: HIP (0.16, -0.27, -0.50), ADS (0, -0.172, -0.36)).
    "fps_hip": (Vector((-0.16, -0.50, 0.27)), Vector((0.0, 1.0, -0.10))),
    "fps_ads": (Vector((0.0, -0.36, 0.172)), Vector((0.0, 1.0, 0.0))),
}


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"only": None, "export": False, "save-blend": False, "previews": None, "list": False}
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
        for wid, fn in mod.BUILDERS.items():
            reg[wid] = fn
    return reg


def wood_textures(tex_dir):
    """Birch-laminate albedo (light / dark plies, varnish tone) and a faint grain normal map,
    tile 0.30 m, grain along U (the weapon's Y on side faces)."""
    import numpy as np
    alb_p = os.path.join(tex_dir, "wood_laminate_albedo.png")
    nrm_p = os.path.join(tex_dir, "wood_normal.png")
    if os.path.exists(alb_p) and os.path.exists(nrm_p):
        return alb_p, nrm_p
    n = 512
    rng = np.random.default_rng(71)
    y = np.arange(n)[:, None] / n
    x = np.arange(n)[None, :] / n
    warp = L.fbm(n, 64, 3, 72) * 0.06
    plies = 0.5 + 0.5 * np.sin((y + warp) * 2 * math.pi * 26)
    grain = L.fbm(n, 6, 4, 73)
    streak = np.repeat(rng.random((n, 1)), n, axis=1) * 0.25
    t = 0.55 * plies + 0.30 * grain + 0.15 * streak
    c0 = np.array((0.42, 0.24, 0.12))
    c1 = np.array((0.62, 0.40, 0.22))
    alb = c0[None, None, :] * (1 - t[..., None]) + c1[None, None, :] * t[..., None]
    L.save_png(alb_p, alb)
    L.save_png(nrm_p, L.normal_from_height(0.6 * grain + 0.3 * plies, 0.6))
    return alb_p, nrm_p


def materials(tex):
    mats = CM.build(tex)
    for name, (col, rough, metal, alb, nrm, ns, _) in WEAPON_MATERIALS.items():
        mats[name] = L.pbr_material(name, col, rough, metal, albedo=tex.get(alb) if alb else None,
                                    normal=tex.get(nrm) if nrm else None, normal_strength=ns)
    return mats


def write_equipment(w, out_dir, faction_dir):
    """InfantryEquipment resource: the weapon as a loadout piece on ATT_Weapon (rigid)."""
    res = "res://assets/weapons/%s/%s/%s.glb" % (faction_dir, w.wid.replace("weapon_", ""), w.wid)
    txt = ('[gd_resource type="Resource" script_class="InfantryEquipment" load_steps=3 format=3]\n\n'
           '[ext_resource type="Script" path="res://scripts/characters/infantry_equipment.gd" id="1_eq"]\n'
           '[ext_resource type="PackedScene" path="%s" id="2_scene"]\n\n'
           '[resource]\nscript = ExtResource("1_eq")\nid = "%s"\nscene = ExtResource("2_scene")\nmode = 1\n'
           'attach = "ATT_Weapon"\nslot = "weapon"\nhides_body = PackedStringArray()\n') % (res, w.wid)
    # ASSET-INTEGRATION-01: the hold (aiming eye, support hand) from the gameplay data's table, so a new export keeps it.
    holds_path = os.path.join(os.path.dirname(__file__), "..", "..", "asset_integration", "weapon_holds.json")
    if os.path.exists(holds_path):
        with open(holds_path, encoding="utf-8") as hf:
            hold = json.load(hf).get(w.wid)
        for k in ("aim_eye", "support_grip", "hold_shift") if hold else ():
            txt += "%s = Vector3(%s)\n" % (k, ", ".join(repr(float(x)) for x in hold[k]))
    with open(os.path.join(out_dir, w.wid + ".tres"), "w", encoding="utf-8") as f:
        f.write(txt)


# ---------------------------------------------------------------------------- previews


def setup_studio(res):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.eevee.taa_render_samples = 48
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Base Contrast"
    world = bpy.data.worlds.get("WStudio") or bpy.data.worlds.new("WStudio")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.36, 0.38, 0.40, 1)
    bg.inputs["Strength"].default_value = 0.45
    sc.world = world
    for name, energy, rot, size in (("Key", 380, (55, 0, 140), 1.2), ("Fill", 120, (70, 0, -40), 2.0), ("Rim", 260, (110, 0, 20), 0.8)):
        o = bpy.data.objects.get("L_" + name)
        if o is None:
            o = bpy.data.objects.new("L_" + name, bpy.data.lights.new("L_" + name, "AREA"))
            sc.collection.objects.link(o)
        o.data.energy = energy
        o.data.size = size
        r = [math.radians(a) for a in rot]
        o.rotation_euler = r
        d = Vector((0, 0, 1))
        d.rotate(o.rotation_euler)
        o.location = d * 3.0
    cam = bpy.data.objects.get("PrevCam")
    if cam is None:
        cam = bpy.data.objects.new("PrevCam", bpy.data.cameras.new("PrevCam"))
        sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def shoot(cam, path, pos, target, lens=50, ortho=None):
    cam.location = Vector(pos)
    d = Vector(target) - Vector(pos)
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = d.to_track_quat("-Z", "Y")
    cam.data.type = "ORTHO" if ortho else "PERSP"
    if ortho:
        cam.data.ortho_scale = ortho
    cam.data.lens = lens
    cam.data.clip_start = 0.01
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def previews(w, d):
    """Six views of LOD0 + LOD strip + clay. Returns sheet paths."""
    res = (1280, 720)
    cam = setup_studio(res)
    st = bpy.context.scene.render.image_settings
    st.file_format = "JPEG"
    st.quality = 92
    for i in W.ALL:
        for o in w.lod_objects(i):
            o.hide_render = i != 0
    lo, hi = w.bounds(0)
    c = (lo + hi) / 2
    L_ = max((hi - lo).y, (hi - lo).z * 16 / 9, 0.15)
    shots = []
    dist = L_ * 1.25
    for name, pos in (("left", c + Vector((-dist, 0, 0))), ("right", c + Vector((dist, 0, 0))),
                      ("front34", c + Vector((dist * 0.65, dist * 0.75, dist * 0.30))), ("rear34", c + Vector((-dist * 0.60, -dist * 0.80, dist * 0.35)))):
        ortho = L_ * 1.08 if name in ("left", "right") else None
        shots.append(shoot(cam, os.path.join(d, "%s_%s.jpg" % (w.wid, name)), pos, c, lens=50, ortho=ortho))
    for name, (off, fwd) in FPS_VIEWS.items():
        aim = getattr(w, "fps", {}).get(name)
        o_, f_ = (Vector(aim[0]), Vector(aim[1])) if aim else (off, fwd)
        shots.append(shoot(cam, os.path.join(d, "%s_%s.jpg" % (w.wid, name)), o_, o_ + f_, lens=24))
    sheet = W.sheet(shots, os.path.join(d, "%s_sheet.jpg" % w.wid), 2, delete=False)
    # LOD strip (same front 3/4)
    strip = []
    for i in W.ALL:
        for j in W.ALL:
            for o in w.lod_objects(j):
                o.hide_render = j != i
        strip.append(shoot(cam, os.path.join(d, "%s_lodtmp%d.jpg" % (w.wid, i)), c + Vector((dist * 0.65, dist * 0.75, dist * 0.30)), c, lens=50))
    lods = W.sheet(strip, os.path.join(d, "%s_lods.jpg" % w.wid), 3, delete=True)
    # clay (Workbench, cavity) for reading the geometry
    for o in w.lod_objects(0):
        o.hide_render = False
    for i in (1, 2):
        for o in w.lod_objects(i):
            o.hide_render = True
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "SINGLE"
    sh.single_color = (0.62, 0.62, 0.60)
    sh.show_cavity = True
    sh.cavity_type = "BOTH"
    clay = []
    for name, pos in (("cl_left", c + Vector((-dist, 0, 0))), ("cl_front34", c + Vector((dist * 0.65, dist * 0.75, dist * 0.30)))):
        clay.append(shoot(cam, os.path.join(d, "%s_%s.jpg" % (w.wid, name)), pos, c, lens=50, ortho=L_ * 1.08 if name == "cl_left" else None))
    clay_sheet = W.sheet(clay, os.path.join(d, "%s_clay.jpg" % w.wid), 2, delete=True)
    sc.render.engine = "BLENDER_EEVEE"
    return [sheet, lods, clay_sheet]


def main():
    t0 = time.time()
    o = parse_args()
    for m in (L, CM, CT, W):
        importlib.reload(m)
    for k, v in WEAPON_MATERIALS.items():
        CM.MATERIALS.setdefault(k, v)
    reg = registry()
    if o["list"]:
        print("FNWEAPONS", json.dumps(sorted(reg)))
        return
    tex = {k: os.path.join(TEX_DIR, v) for k, v in {"polymer": "polymer_albedo.png", "polymer_n": "polymer_normal.png"}.items()}
    tex["wood"], tex["wood_n"] = wood_textures(TEX_DIR)
    only = set(o["only"].split(",")) if o["only"] else None
    for wid, fn in reg.items():
        if only is not None and wid not in only:
            continue
        t = time.time()
        L.clear_scene()
        coll = L.collection("Weapon_" + wid)
        mats = materials(tex)
        w = fn()
        w.build(coll, mats)
        fdir = "nato" if w.faction == "NATO" else "russian"
        out_dir = os.path.join(OUT, fdir, wid)
        entry = {"tris": [w.tris(i) for i in W.ALL], "objects": [len(w.lod_objects(i)) for i in W.ALL], "materials": w.materials()}
        if o["save-blend"]:
            sd = os.path.join(out_dir, "source")
            os.makedirs(sd, exist_ok=True)
            open(os.path.join(sd, ".gdignore"), "a").close()
            bpy.ops.wm.save_as_mainfile(filepath=os.path.join(sd, w.wid + ".blend"), copy=True, compress=True)
        if o["export"]:
            meta = w.export(out_dir)
            write_equipment(w, out_dir, fdir)
            entry["size_m"] = [meta["length_m"], meta["height_m"], meta["width_m"]]
        if o["previews"]:
            d = os.path.abspath(o["previews"])
            os.makedirs(d, exist_ok=True)
            entry["previews"] = previews(w, d)
        entry["seconds"] = round(time.time() - t, 1)
        print("FNWEAPON", wid, json.dumps(entry), flush=True)
    print("FNBUILD", json.dumps({"t_total": round(time.time() - t0, 1)}))


if __name__ == "__main__" or True:
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.stdout.flush()
        os._exit(1)
