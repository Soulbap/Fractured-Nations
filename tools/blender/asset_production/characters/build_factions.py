"""ASSET-PRODUCTION-01: faction infantry families (NATO, RU, CN) on the CHARACTER-01 rig.

Reuses the CHARACTER-01 modules unchanged (skeleton, body, uniform cut, weight transfer,
LOD export) and adds faction pieces: uniforms in faction camouflage (+ cut details),
helmets, body armour / carriers, packs, rifles and optics. The shared rig, animation
clips, boots, gloves, eyewear, foregrip and laser are NOT re-exported; the faction
pieces are compatible with them by construction.

Background Blender:
    blender -b --factory-startup --python tools/blender/asset_production/characters/build_factions.py -- [options]
Options:
    --export          write GLBs into assets/characters/infantry/factions/<fac>/ and equipment .tres
    --previews DIR    renders (A-pose and baked Idle pose) of every family into DIR
    --only F[,F]      nato | ru | cn
    --root DIR        asset root (default assets/characters/infantry): a scratch root keeps the shipped files untouched
                      (trial builds); it reuses the shipped rifles and optics (they live in weapon space).
"""
import importlib
import json
import os
import sys
import tempfile
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
CHAR = os.path.abspath(os.path.join(HERE, "..", "..", "character"))
AP = os.path.abspath(os.path.join(HERE, ".."))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
for p in (HERE, AP, CHAR):
    if p not in sys.path:
        sys.path.insert(0, p)

import bpy  # noqa: E402
from mathutils import Matrix  # noqa: E402

import char_lib as L  # noqa: E402
import char_skeleton as S  # noqa: E402
import char_sdf as D  # noqa: E402
import char_body as B  # noqa: E402
import char_textures as T  # noqa: E402
import char_materials as M  # noqa: E402
import char_uniform as U  # noqa: E402
import char_gear as G  # noqa: E402
import char_weapon as W  # noqa: E402
import char_anim as A  # noqa: E402
import char_export as E  # noqa: E402
import fac_textures as FT  # noqa: E402
import fac_gear as FG  # noqa: E402
import fac_weapons as FW  # noqa: E402

for _m in (L, S, D, B, T, M, U, G, W, A, E, FT, FG, FW):
    importlib.reload(_m)

INF = os.path.join(REPO, "assets", "characters", "infantry")
ROOT = INF
TEX_DIR = os.path.join(INF, "textures")
OUT = os.path.join(INF, "factions")
LOADOUT_DIR = os.path.join(INF, "loadouts")


def set_root(root):
    """Writes parts, equipment and loadouts under another root (trial builds)."""
    global ROOT, OUT, LOADOUT_DIR
    ROOT = os.path.join(REPO, root) if not os.path.isabs(root) else root
    OUT = os.path.join(ROOT, "factions")
    LOADOUT_DIR = os.path.join(ROOT, "loadouts")
    os.makedirs(LOADOUT_DIR, exist_ok=True)

# New shared library materials (mirrored in scripts/characters/infantry_materials.gd).
NEW_MATERIALS = {
    "Camo_NATO":    ((1.00, 1.00, 1.00), 0.88, 0.0, "camo_nato", "ripstop_n", 0.3, T.TILE_FABRIC_M),
    "Camo_EMR":     ((1.00, 1.00, 1.00), 0.88, 0.0, "camo_emr", "ripstop_n", 0.3, T.TILE_FABRIC_M),
    "Camo_Type21":  ((1.00, 1.00, 1.00), 0.88, 0.0, "camo_type21", "ripstop_n", 0.3, T.TILE_FABRIC_M),
    "Fabric_Coyote": ((0.55, 0.47, 0.35), 0.90, 0.0, None, "ripstop_n", 0.6, T.TILE_FABRIC_M),
    "Polymer_Tan":  ((0.62, 0.53, 0.38), 0.68, 0.0, "polymer", "polymer_n", 0.7, T.TILE_HARD_M),
    "Polymer_Plum": ((0.32, 0.14, 0.12), 0.60, 0.0, "polymer", "polymer_n", 0.7, T.TILE_HARD_M),
}
M.MATERIALS.update(NEW_MATERIALS)

FAMILIES = {
    "nato": {"name": "NATO", "camo": "Camo_NATO", "display": "NATO rifleman (HK416-class carbine, plate carrier)"},
    "ru": {"name": "RU", "camo": "Camo_EMR", "display": "Russian rifleman (AK-12-class rifle, 6B45-class armour)"},
    "cn": {"name": "CN", "camo": "Camo_Type21", "display": "Chinese rifleman (QBZ-191-class rifle, Type 21 kit)"},
}

# piece id -> (mode, attach, slot, hides_body)
SKINNED, RIGID = 0, 1
PIECES = {
    "nato_jacket": (SKINNED, "", "uniform", ["Torso", "Arms"]),
    "nato_trousers": (SKINNED, "", "uniform_legs", ["Legs"]),
    "nato_helmet": (RIGID, "ATT_Head", "head", []),
    "nato_vest": (SKINNED, "", "chest", []),
    "nato_rifle": (RIGID, "ATT_Weapon", "weapon", []),
    "nato_optic": (RIGID, "weapon:ATT_Optic", "weapon_optic", []),
    "ru_jacket": (SKINNED, "", "uniform", ["Torso", "Arms"]),
    "ru_trousers": (SKINNED, "", "uniform_legs", ["Legs"]),
    "ru_helmet": (RIGID, "ATT_Head", "head", []),
    "ru_armor": (SKINNED, "", "chest", []),
    "ru_rifle": (RIGID, "ATT_Weapon", "weapon", []),
    "ru_optic": (RIGID, "weapon:ATT_Optic", "weapon_optic", []),
    "cn_jacket": (SKINNED, "", "uniform", ["Torso", "Arms"]),
    "cn_trousers": (SKINNED, "", "uniform_legs", ["Legs"]),
    "cn_helmet": (RIGID, "ATT_Head", "head", []),
    "cn_vest": (SKINNED, "", "chest", []),
    "cn_pack": (RIGID, "ATT_Back", "back", []),
    "cn_rifle": (RIGID, "ATT_Weapon", "weapon", []),
    "cn_optic": (RIGID, "weapon:ATT_Optic", "weapon_optic", []),
}

# Loadouts: faction pieces + shared CHARACTER-01 pieces (boots, gloves, eyewear, belt,
# pack, foregrip, laser) referenced from assets/characters/infantry/equipment/.
LOADOUTS = {
    "NATO_rifleman": ["nato_jacket", "nato_trousers", "uniform_boots", "uniform_gloves", "nato_helmet", "eyepro",
                      "nato_vest", "belt_standard", "pack_assault", "nato_rifle", "nato_optic", "foregrip", "laser"],
    "RU_rifleman": ["ru_jacket", "ru_trousers", "uniform_boots", "uniform_gloves", "ru_helmet", "ru_armor",
                    "ru_rifle", "ru_optic"],
    "CN_rifleman": ["cn_jacket", "cn_trousers", "uniform_boots", "uniform_gloves", "cn_helmet", "cn_vest",
                    "cn_pack", "cn_rifle", "cn_optic", "foregrip"],
}
DISPLAY = {"NATO_rifleman": FAMILIES["nato"]["display"], "RU_rifleman": FAMILIES["ru"]["display"],
           "CN_rifleman": FAMILIES["cn"]["display"]}


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"export": False, "previews": None, "only": None, "root": None}
    i = 0
    while i < len(argv):
        if argv[i] in ("--previews", "--only", "--root"):
            o[argv[i][2:]] = argv[i + 1]
            i += 1
        elif argv[i] == "--export":
            o["export"] = True
        i += 1
    return o


class Build:
    def __init__(self):
        self.log = {}
        self.pieces = {}
        self.preview_only = {}


def stage_body(b):
    """The shared body (char_body, VISUAL-03); the CHARACTER-01 textures are regenerated into a temp dir (previews
    only) so the committed ones stay untouched."""
    tmp = tempfile.mkdtemp(prefix="fn_fac_")
    tex = T.build_all(tmp)
    tex["skin_v03"] = os.path.join(TEX_DIR, "skin_head_v03_albedo.png")
    tex.update(FT.build(TEX_DIR))
    b.tex = tex
    b.mats = M.build(tex)
    coll = L.collection("Body")
    res = B.build(coll, b.mats)
    b.arm = res["arm"]
    b.weight_ref = res["weight_ref"]
    b.weight_ref.hide_set(True)
    for k, o in res["pieces"].items():
        if k == "body_head":
            b.preview_only["body_head"] = o
        else:
            o.hide_render = True
            o.hide_set(True)
    # Shared boots and gloves, for previews only (exported by build_infantry).
    sh = L.collection("Shared")
    for key, fn in (("uniform_boots", U.build_boots), ("uniform_gloves", U.build_gloves)):
        o = fn(sh, b.mats)
        B.to_body_space(o)
        M.apply_box_uvs(o)
        L.transfer_weights(o, b.weight_ref, b.arm, smooth_iters=2)
        b.preview_only[key] = o


def _skin(b, key, o, smooth=2):
    B.to_body_space(o)
    M.apply_box_uvs(o)
    L.transfer_weights(o, b.weight_ref, b.arm, smooth_iters=smooth)
    b.pieces[key] = o


def _head_to_body_space(o):
    """B.to_body_space for head pieces: B.unwarp_z (np.interp) clamps every height above the reference HeadTop knot
    to the body's crown, which pressed the top ~35 mm of the helmets onto one plane (flat crown). Above the last knot
    the last segment's slope is extended instead."""
    new, ref = B._WARP_NEW, B._WARP_REF
    slope = (new[-1] - new[-2]) / (ref[-1] - ref[-2])
    me = o.data
    co = np.empty(len(me.vertices) * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    z = co[:, 2]
    co[:, 2] = np.where(z > ref[-1], new[-1] + (z - ref[-1]) * slope, B.unwarp_z(z))
    me.vertices.foreach_set("co", co.ravel())
    me.update()


def _rigid(b, key, o, bone):
    if bone == "ATT_Head":
        o.data.transform(B.head_fit_matrix())
        _head_to_body_space(o)
    else:
        B.to_body_space(o)
    M.apply_box_uvs(o)
    att = b.arm.data.bones[bone].matrix_local
    o.data.transform(att.inverted())
    o.matrix_world = Matrix.Identity(4)
    _place(b, o, bone)
    b.pieces[key] = o


def _place(b, o, bone):
    want = b.arm.matrix_world @ b.arm.data.bones[bone].matrix_local
    o.parent = b.arm
    o.parent_type = "BONE"
    o.parent_bone = bone
    o.matrix_world = want


def stage_uniforms(b, fams):
    for fac in fams:
        t = time.time()
        coll = L.collection("Uniform_" + fac)
        mats = dict(b.mats)
        mats["Camo_M23"] = b.mats[FAMILIES[fac]["camo"]]
        jacket = U.build_jacket(coll, mats)
        if fac == "nato":
            FG.nato_shirt_split(jacket, b.mats)
        trousers = U.build_trousers(coll, mats)
        if fac == "ru":
            pads = FG.ru_kneepads(coll, b.mats)
            trousers = L.join([trousers, pads], "RU_trousers")
        _skin(b, fac + "_jacket", jacket)
        L.limit_leg_weights(jacket, *B.leg_fade(L.JACKET_LEG_FADE))
        _skin(b, fac + "_trousers", trousers)
        b.log.setdefault("uniform_seconds", {})[fac] = round(time.time() - t, 1)


def stage_gear(b, fams):
    for fac in fams:
        t = time.time()
        coll = L.collection("Gear_" + fac)
        _rigid(b, fac + "_helmet", FG.build_helmet(coll, b.mats, fac), "ATT_Head")
        if fac == "nato":
            _skin(b, "nato_vest", FG.build_nato_vest(coll, b.mats), smooth=4)
        elif fac == "ru":
            _skin(b, "ru_armor", FG.build_ru_armor(coll, b.mats), smooth=4)
        else:
            _skin(b, "cn_vest", FG.build_cn_vest(coll, b.mats), smooth=4)
            _rigid(b, "cn_pack", FG.build_cn_pack(coll, b.mats), "ATT_Back")
        b.log.setdefault("gear_seconds", {})[fac] = round(time.time() - t, 1)
    # Shared pieces used by the loadouts (previews only).
    sh = L.collection("SharedGear")
    o = G.build_eyepro(sh, b.mats)
    M.apply_box_uvs(o)
    _rigid(b, "eyepro", o, "ATT_Head")
    b.preview_only["eyepro"] = b.pieces.pop("eyepro")
    o = G.build_belt(sh, b.mats, "standard")
    _skin(b, "belt_standard", o, smooth=4)
    b.preview_only["belt_standard"] = b.pieces.pop("belt_standard")
    o = G.build_pack(sh, b.mats, "assault")
    _rigid(b, "pack_assault", o, "ATT_Back")
    b.preview_only["pack_assault"] = b.pieces.pop("pack_assault")


def stage_weapons(b, fams):
    b.mounts = {}
    builders = {"nato": (FW.build_rifle_nato, FW.build_optic_nato), "ru": (FW.build_rifle_ru, FW.build_optic_ru),
                "cn": (FW.build_rifle_cn, FW.build_optic_cn)}
    for fac in fams:
        coll = L.collection("Weapon_" + fac)
        rb, ob = builders[fac]
        rifle = rb(coll, b.mats)
        M.apply_box_uvs(rifle)
        key = "rifle_" + fac
        b.mounts[fac] = {e.name: e for e in FW.mount_empties(coll, rifle, key)}
        optic = ob(coll, b.mats)
        M.apply_box_uvs(optic)
        optic.parent = rifle
        optic.location = FW.MOUNTS[key]["ATT_Optic"]
        b.pieces[fac + "_rifle"] = rifle
        b.pieces[fac + "_optic"] = optic
        for name, fn, mount in (("foregrip", W.build_foregrip, "ATT_Underbarrel"), ("laser", W.build_laser, "ATT_RailRight")):
            o = fn(coll, b.mats)
            M.apply_box_uvs(o)
            o.parent = rifle
            o.location = FW.MOUNTS[key][mount]
            b.preview_only["%s@%s" % (name, fac)] = o
        _place(b, rifle, "ATT_Weapon")
    b.log["weapon_tris"] = {k: L.tri_count(b.pieces[k]) for k in b.pieces if k.endswith(("_rifle", "_optic"))}


def show(b, loadout):
    fac = loadout.split("_")[0].lower()
    keep = set(LOADOUTS[loadout]) | {"body_head"}
    allobjs = dict(b.pieces)
    allobjs.update(b.preview_only)
    for k, o in allobjs.items():
        base = k.split("@")[0]
        vis = base in keep and ("@" not in k or k.endswith("@" + fac))
        o.hide_render = not vis
        o.hide_set(not vis)


def previews(b, outdir, fams, tag):
    os.makedirs(outdir, exist_ok=True)
    for lo in LOADOUTS:
        if lo.split("_")[0].lower() not in fams:
            continue
        show(b, lo)
        L.setup_render((620, 900))
        bpy.context.scene.render.image_settings.file_format = "JPEG"
        shots = []
        for name, az in (("front", 0), ("q34", 35), ("side", 90), ("back", 180), ("q34b", 225)):
            shots.append(L.render_view(os.path.join(outdir, "%s_%s_%s.jpg" % (tag, lo, name)), (0, 0.05, 0.93), 3.4, az, 6, lens=50, frame=0))
        import ap_lib
        ap_lib.sheet(shots, os.path.join(outdir, "%s_%s.jpg" % (tag, lo)), 5)
        L.setup_render((760, 760))
        bpy.context.scene.render.image_settings.file_format = "JPEG"
        shots = []
        for name, tgt, d, az, el in (("head", (0, 0.02, 1.68), 0.9, 25, 4), ("chest", (0, 0.05, 1.22), 1.3, 30, 8),
                                     ("weapon", (0.05, 0.35, 1.15), 1.0, 55, 12), ("back", (0, -0.1, 1.2), 1.6, 200, 10)):
            shots.append(L.render_view(os.path.join(outdir, "%s_%s_cu_%s.jpg" % (tag, lo, name)), tgt, d, az, el, lens=60, frame=0))
        ap_lib.sheet(shots, os.path.join(outdir, "%s_%s_closeups.jpg" % (tag, lo)), 4)


def write_equipment(key, glb_res, path):
    mode, attach, slot, hides = PIECES[key]
    hb = ", ".join('"%s"' % h for h in hides)
    txt = ('[gd_resource type="Resource" script_class="InfantryEquipment" load_steps=3 format=3]\n\n'
           '[ext_resource type="Script" path="res://scripts/characters/infantry_equipment.gd" id="1_eq"]\n'
           '[ext_resource type="PackedScene" path="%s" id="2_scene"]\n\n'
           '[resource]\nscript = ExtResource("1_eq")\nid = "%s"\nscene = ExtResource("2_scene")\nmode = %d\n'
           'attach = "%s"\nslot = "%s"\nhides_body = PackedStringArray(%s)\n') % (glb_res, key, mode, attach, slot, hb)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(txt)


def _res(path):
    return "res://" + os.path.relpath(path, REPO).replace(os.sep, "/")


def _canonical():
    return os.path.normpath(ROOT) == os.path.normpath(os.path.join(REPO, "assets", "characters", "infantry"))


def equipment_res(key):
    """Equipment of this root when it was built here, else the canonical one (shared pieces, weapons)."""
    if key in PIECES:
        fac = key.split("_")[0]
        mine = os.path.join(OUT, fac, "equipment", key + ".tres")
        canon = os.path.join(INF, "factions", fac, "equipment", key + ".tres")
    else:
        mine = os.path.join(ROOT, "equipment", key + ".tres")
        canon = os.path.join(INF, "equipment", key + ".tres")
    return _res(mine if os.path.exists(mine) else canon)


def write_loadout(lo):
    items = LOADOUTS[lo]
    lines = ['[gd_resource type="Resource" script_class="InfantryLoadout" load_steps=%d format=3]\n' % (len(items) + 3),
             '[ext_resource type="Script" path="res://scripts/characters/infantry_loadout.gd" id="1_lo"]',
             '[ext_resource type="Script" path="res://scripts/characters/infantry_equipment.gd" id="2_eq"]']
    for i, k in enumerate(items):
        lines.append('[ext_resource type="Resource" path="%s" id="%d_%s"]' % (equipment_res(k), i + 3, k))
    refs = ", ".join('ExtResource("%d_%s")' % (i + 3, k) for i, k in enumerate(items))
    lines += ["", "[resource]", 'script = ExtResource("1_lo")', 'id = "%s"' % lo, 'display_name = "%s"' % DISPLAY[lo],
              'items = Array[ExtResource("2_eq")]([%s])' % refs, ""]
    with open(os.path.join(LOADOUT_DIR, lo + ".tres"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


TEX_IMPORT_TEMPLATE = os.path.join(TEX_DIR, "camo_m23_albedo.png.import")


def write_texture_imports():
    """Copies the CHARACTER-01 camo import settings (VRAM, mipmaps) for the new camos."""
    with open(TEX_IMPORT_TEMPLATE, encoding="utf-8") as f:
        tpl = f.read()
    params = tpl[tpl.index("[params]"):]
    for name in ("camo_nato_albedo.png", "camo_emr_albedo.png", "camo_type21_albedo.png"):
        imp = os.path.join(TEX_DIR, name + ".import")
        if not os.path.exists(imp):
            with open(imp, "w", encoding="utf-8", newline="\n") as f:
                f.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n' + params)


def stage_export(b, fams):
    lod_coll = L.collection("LODs")
    out = {}
    for o in list(b.pieces.values()) + list(b.preview_only.values()):
        o.hide_set(False)
    for key, (mode, attach, slot, hides) in PIECES.items():
        fac = key.split("_")[0]
        if fac not in fams:
            continue
        sub = "weapons" if slot.startswith("weapon") else "parts"
        if sub == "weapons" and not _canonical():
            continue                       # staging reuses the canonical rifles / optics
        path = os.path.join(OUT, fac, sub, key + ".glb")
        obj = b.pieces[key]
        if mode == SKINNED:
            size, tris = E.export_skinned(b.arm, obj, key, path, lod_coll)
        else:
            extra = []
            if key.endswith("_rifle"):
                # Every rifle has mount empties with the same names and Blender suffixes
                # duplicates (.001). Park all of them under neutral names and create fresh
                # empties with the exact contract names for this export only.
                for ms in b.mounts.values():
                    for e in ms.values():
                        e.name = "hold_mount"
                extra = FW.mount_empties(L.collection("ExportMounts"), obj, "rifle_" + fac)
                bad = [e.name for e in extra if "." in e.name]
                assert not bad, "mount names not exact: %s" % bad
            # Accessories parented to the rifle must not ride along into the rifle GLB (its magazine does).
            kids = [c for c in obj.children if c.type == "MESH" and not c.get("fn_magazine")]
            saved = [(c, c.parent, c.matrix_world.copy()) for c in kids]
            for c in kids:
                c.parent = None
            size, tris = E.export_rigid(obj, key, path, lod_coll, extra)
            for c, p, mw in saved:
                c.parent = p
                c.matrix_world = mw
            if key.endswith("_rifle"):
                for e in extra:
                    bpy.data.objects.remove(e, do_unlink=True)
        glb_res = _res(path)
        write_equipment(key, glb_res, os.path.join(OUT, fac, "equipment", key + ".tres"))
        out[key] = {"bytes": size, "lod_tris": tris}
    for lo in LOADOUTS:
        if lo.split("_")[0].lower() in fams:
            write_loadout(lo)
    if _canonical():
        write_texture_imports()
    b.log["export"] = out
    blend = os.path.join(OUT, "blender", "factions.blend")
    os.makedirs(os.path.dirname(blend), exist_ok=True)
    open(os.path.join(os.path.dirname(blend), ".gdignore"), "w").close()
    for o in lod_coll.objects:
        o.hide_set(True)
        o.hide_render = True
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)


def main():
    t0 = time.time()
    o = parse_args()
    if o["root"]:
        set_root(o["root"])
    fams = o["only"].split(",") if o["only"] else list(FAMILIES)
    b = Build()
    L.clear_scene()
    stage_body(b)
    b.log["t_body"] = round(time.time() - t0, 1)
    stage_uniforms(b, fams)
    b.log["t_uniform"] = round(time.time() - t0, 1)
    stage_gear(b, fams)
    stage_weapons(b, fams)
    b.log["t_gear"] = round(time.time() - t0, 1)
    b.log["tris"] = {k: L.tri_count(v) for k, v in b.pieces.items()}
    if o["previews"]:
        o["previews"] = os.path.abspath(o["previews"])
        previews(b, o["previews"], fams, "apose")
        # Idle pose from the shared clip generator: checks that both hands sit on the
        # faction weapons (same grip / support-grip contract as the carbine).
        b.actions, _, _ = A.build_clips(b.arm, b.weight_ref, only=["Idle"])
        b.arm.animation_data.action = b.actions["Idle"]
        bpy.context.scene.frame_set(0)
        previews(b, o["previews"], fams, "idle")
        b.arm.animation_data.action = None
        for pb in b.arm.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
        bpy.context.scene.frame_set(0)
    if o["export"]:
        stage_export(b, fams)
    b.log["t_total"] = round(time.time() - t0, 1)
    print("FNFAC", json.dumps(b.log))
    if o["export"]:
        with open(os.path.join(OUT, "build_log.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(b.log, f, indent=1)



if __name__ == "__main__" or True:
    # Blender exits with code 0 on a Python exception; make failures visible to scripts.
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.stdout.flush()
        os._exit(1)
