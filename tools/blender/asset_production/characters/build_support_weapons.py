"""GAMEPLAY-02: infantry support weapons on the CHARACTER-01 weapon contract.

  lmg            Minimi-para-class 5.56 mm light machine gun (original asset): long receiver with a hinged feed
                 cover and top rail, 100-round soft box magazine on the left of the magwell, short heavy barrel
                 with carrying handle and gas tube, folded bipod, collapsible stock. Weapon space as every rifle
                 (docs/CHARACTER_STANDARD.md section 3): origin = pistol-grip centre, +Y muzzle, +Z up, bore at
                 z = BORE_Z, GRIP_Support at (0, 0.165, BORE_Z) on the handguard, ATT_Muzzle at the flash hider.
  lmg_ammo_box   200-round hard ammunition box carried on the machine gunner's left hip (ATT_Hip_L).
  grenade        M67-class fragmentation grenade (the thrown grenade of the effects; origin at its centre).
  launcher       M72-class light anti-structure rocket launcher in weapon space (origin at the grip, +Y muzzle): what
                 first person holds when the secondary weapon is raised (WeaponDef.viewmodel_scene).
  launcher_back  the same tube carried diagonally across the back, behind the pack (ATT_Back), for the grenadier loadouts
                 NATO_gren / RU_gren / CN_gren (the faction rifleman plus the launcher).

Machine-gunner loadouts (NATO_mg, RU_mg, CN_mg) are the faction rifleman loadouts with the rifle, foregrip and laser
replaced by the LMG and the ammunition box (the faction optic sits on the LMG's rail) (InfantryRole "machine_gunner", loadout suffix "mg").

Background Blender:
    blender -b --factory-startup --python tools/blender/asset_production/characters/build_support_weapons.py -- [options]
Options:
    --export          GLBs into assets/characters/infantry/weapons|parts/, equipment .tres, mg loadouts, .blend source
    --previews DIR    weapon turntable sheet and the NATO body holding it in the Idle pose (hand placement check)
"""
import importlib
import json
import math
import os
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
CHAR = os.path.abspath(os.path.join(HERE, "..", "..", "character"))
AP = os.path.abspath(os.path.join(HERE, ".."))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
for p in (HERE, AP, CHAR):
    if p not in sys.path:
        sys.path.insert(0, p)

import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import char_lib as L  # noqa: E402
import char_skeleton as S  # noqa: E402
import char_body as B  # noqa: E402
import char_textures as T  # noqa: E402
import char_materials as M  # noqa: E402
import char_weapon as W  # noqa: E402
import char_anim as A  # noqa: E402
import char_export as E  # noqa: E402
import fac_weapons as FW  # noqa: E402

for _m in (L, S, B, T, M, W, A, E, FW):
    importlib.reload(_m)

INF = os.path.join(REPO, "assets", "characters", "infantry")
LOADOUT_DIR = os.path.join(INF, "loadouts")
BORE_Z = W.BORE_Z
RIGID = 1

# key: (attach, slot, sub-folder)
PIECES = {
    "lmg": ("ATT_Weapon", "weapon", "weapons"),
    "lmg_ammo_box": ("ATT_Hip_L", "hip", "parts"),
    "grenade": ("", "item", "weapons"),
    "launcher": ("", "item", "weapons"),
    "launcher_back": ("ATT_Back", "back_weapon", "parts"),
}
LMG_MOUNTS = {"ATT_Optic": (0, 0.000, FW.OPTIC_Z), "ATT_Underbarrel": (0, 0.300, BORE_Z - 0.040),
              "ATT_RailRight": (0.032, 0.190, BORE_Z), "ATT_Muzzle": (0, 0.640, BORE_Z)}
# Pieces of the rifleman loadouts the machine gunner does not carry (the faction optic moves to the LMG's rail: the
# first-person sight line is the same for every weapon).
RIFLE_ITEMS = ("nato_rifle", "ru_rifle", "cn_rifle", "foregrip", "laser")
GREN_LOADOUTS = {"NATO_gren": ("NATO_rifleman", "NATO grenadier (carbine, grenades, M72-class launcher on the back)"),
                 "RU_gren": ("RU_rifleman", "Russian grenadier (rifle, grenades, M72-class launcher on the back)"),
                 "CN_gren": ("CN_rifleman", "Chinese grenadier (rifle, grenades, M72-class launcher on the back)")}
MG_LOADOUTS = {"NATO_mg": ("NATO_rifleman", "NATO machine gunner (Minimi-class LMG, plate carrier)"),
               "RU_mg": ("RU_rifleman", "Russian machine gunner (Minimi-class LMG, 6B45-class armour)"),
               "CN_mg": ("CN_rifleman", "Chinese machine gunner (Minimi-class LMG, Type 21 kit)")}


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"export": False, "previews": None}
    i = 0
    while i < len(argv):
        if argv[i] == "--previews":
            o["previews"] = argv[i + 1]
            i += 1
        elif argv[i] == "--export":
            o["export"] = True
        i += 1
    return o


def rx(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


def build_lmg(coll, mats):
    w = FW.WB(mats, ["Metal_Black", "Polymer_Black", "Metal_Worn", "Polymer_OD"])
    z = BORE_Z
    # Lower receiver / trigger group with the pistol grip at the origin.
    w.box((0.040, 0.120, 0.040), (0, 0.000, z - 0.050), "Metal_Black", 0.004)
    w.box((0.006, 0.062, 0.006), (0, 0.020, z - 0.088), "Metal_Black", 0.002)                 # trigger guard
    w.box((0.006, 0.006, 0.024), (0, 0.050, z - 0.078), "Metal_Black", 0.002)
    w.box((0.004, 0.008, 0.020), (0, 0.022, z - 0.070), "Metal_Worn", 0.0015, rot=rx(15))    # trigger
    w.box((0.030, 0.042, 0.108), (0, -0.004, -0.004), "Polymer_Black", 0.009, rot=rx(-20), segs=2)  # pistol grip
    w.box((0.032, 0.048, 0.010), (0, -0.022, -0.058), "Polymer_Black", 0.004, rot=rx(-20))
    # Upper receiver: long box with ejection port, cocking handle on the right, feed cover with rail on top.
    w.box((0.052, 0.300, 0.060), (0, 0.040, z + 0.002), "Metal_Black", 0.005)
    w.box((0.004, 0.090, 0.026), (0.027, 0.020, z - 0.004), "Metal_Worn", 0.002)              # port
    w.box((0.018, 0.020, 0.012), (0.034, 0.110, z + 0.006), "Metal_Black", 0.003)             # cocking handle
    w.box((0.056, 0.160, 0.014), (0, 0.010, z + 0.029), "Metal_Black", 0.004)                 # feed cover
    w.box((0.010, 0.020, 0.010), (0.030, -0.060, z + 0.030), "Metal_Worn", 0.002)             # cover latch
    FW.rail(w, -0.068, 0.088, z + 0.036)                                                      # top at the optic mount
    # Feed tray on the left, the 100-round soft box magazine hanging under it.
    w.box((0.040, 0.050, 0.028), (-0.042, 0.050, z - 0.010), "Metal_Black", 0.003)
    w.box((0.070, 0.105, 0.112), (-0.034, 0.055, z - 0.100), "Polymer_OD", 0.012, segs=2)
    w.box((0.072, 0.020, 0.016), (-0.034, 0.055, z - 0.150), "Polymer_Black", 0.004)          # pouch bottom strap
    for i in range(4):                                                                        # belt links at the tray
        w.box((0.010, 0.010, 0.008), (-0.050 + i * 0.010, 0.050, z + 0.014), "Metal_Worn", 0.002)
    # Handguard (support hand at y = 0.165) and the gas tube under the barrel.
    w.box((0.050, 0.150, 0.048), (0, 0.255, z - 0.012), "Polymer_Black", 0.010, segs=2)
    for i in range(6):
        w.box((0.052, 0.006, 0.040), (0, 0.195 + i * 0.024, z - 0.012), "Polymer_Black", 0.002)
    w.cyl(0.0085, 0.0085, 0.180, (0, 0.400, z - 0.030), "Metal_Black")                        # gas tube
    w.box((0.026, 0.026, 0.040), (0, 0.480, z - 0.018), "Metal_Black", 0.004)                 # gas block
    # Barrel, carrying handle, front sight and flash hider.
    w.cyl(0.0120, 0.0120, 0.300, (0, 0.440, z), "Metal_Black", segs=14)
    w.box((0.010, 0.070, 0.010), (0, 0.300, z + 0.060), "Polymer_Black", 0.004)               # carrying handle grip
    w.box((0.008, 0.012, 0.050), (0, 0.270, z + 0.035), "Metal_Black", 0.002)
    w.box((0.008, 0.012, 0.050), (0, 0.330, z + 0.035), "Metal_Black", 0.002)
    w.box((0.014, 0.010, 0.040), (0, 0.585, z + 0.028), "Metal_Black", 0.002)                 # front sight post
    w.cyl(0.0140, 0.0135, 0.050, (0, 0.615, z), "Metal_Black", segs=14)
    for i in range(4):
        a = math.radians(i * 90 + 45)
        w.box((0.004, 0.032, 0.005), (0.0135 * math.cos(a), 0.622, z + 0.0135 * math.sin(a)), "Metal_Worn", 0.001)
    # Folded bipod under the barrel.
    for sx in (-1, 1):
        w.cyl(0.0055, 0.0055, 0.210, (sx * 0.012, 0.430, z - 0.050), "Metal_Black", segs=8)
        w.box((0.012, 0.020, 0.010), (sx * 0.012, 0.330, z - 0.050), "Polymer_Black", 0.003)  # feet
    w.box((0.040, 0.026, 0.020), (0, 0.540, z - 0.040), "Metal_Black", 0.004)                 # bipod yoke
    # Collapsible stock on a tube.
    w.cyl(0.0160, 0.0160, 0.150, (0, -0.180, z - 0.004), "Metal_Black")
    by = -W.STOCK_PULL - 0.010
    w.box((0.040, 0.120, 0.052), (0, by + 0.080, z - 0.006), "Polymer_Black", 0.010, segs=2)
    w.box((0.036, 0.090, 0.060), (0, by + 0.055, z - 0.054), "Polymer_Black", 0.010, rot=rx(12), segs=2)
    w.box((0.042, 0.018, 0.134), (0, by + 0.006, z - 0.034), "Polymer_Black", 0.008, segs=2)  # butt plate
    w.box((0.006, 0.040, 0.008), (0, by + 0.070, z - 0.094), "Metal_Worn", 0.002)             # sling loop
    return w.obj("LMG", coll)


def build_grenade(coll, mats):
    """M67-class fragmentation grenade: 64 mm body, fuze with spoon and pin ring (origin at the centre)."""
    w = FW.WB(mats, ["Polymer_OD", "Metal_Worn", "Metal_Black"])
    w._set(L.bm_sphere(w.bm, 0.032, Vector((0, 0, 0)), scale=(1.0, 1.0, 1.05), segs=14, rings=9), "Polymer_OD")
    w.cyl(0.011, 0.011, 0.020, (0, 0, 0.040), "Metal_Worn", axis=(0, 0, 1), segs=10)          # fuze body
    w.box((0.012, 0.060, 0.006), (0, -0.018, 0.040), "Metal_Worn", 0.002, rot=rx(-55))       # spoon
    w.cyl(0.010, 0.010, 0.002, (0.016, 0, 0.044), "Metal_Black", axis=(1, 0, 0), segs=10)    # pin ring
    return w.obj("Grenade", coll)


LAUNCHER_Z = 0.090


def build_launcher(coll, mats):
    """Light disposable anti-structure rocket launcher (M72-class original): extended OD tube 0.88 m, end caps, pop-up
    sights, firing mechanism with the trigger bar on top, a pistol grip at the origin; the tube axis LAUNCHER_Z above it."""
    w = FW.WB(mats, ["Helmet_Shell", "Polymer_Black", "Metal_Worn", "Metal_Black"])
    z = LAUNCHER_Z
    w.cyl(0.033, 0.033, 0.880, (0, 0.200, z), "Helmet_Shell", segs=16)                       # tube (olive drab)
    w.cyl(0.036, 0.036, 0.040, (0, 0.630, z), "Polymer_Black", segs=16)                      # muzzle band
    w.cyl(0.036, 0.036, 0.050, (0, -0.230, z), "Polymer_Black", segs=16)                     # rear band
    w.box((0.030, 0.060, 0.050), (0, 0.000, z - 0.050), "Polymer_Black", 0.006)              # grip housing
    w.box((0.026, 0.040, 0.080), (0, 0.000, -0.010), "Polymer_Black", 0.008, rot=rx(-12))    # grip
    w.box((0.010, 0.050, 0.012), (0, 0.040, z + 0.040), "Metal_Black", 0.002)                # trigger bar
    w.box((0.004, 0.012, 0.030), (0, 0.380, z + 0.045), "Metal_Black", 0.001)                # front sight
    w.box((0.020, 0.008, 0.026), (0, -0.120, z + 0.045), "Metal_Black", 0.001)               # rear sight
    for y in (-0.150, 0.300):
        w.box((0.072, 0.010, 0.012), (0, y, z), "Metal_Worn", 0.002)                         # sling swivels
    return w.obj("Launcher", coll)


def launcher_mounts(coll, weapon):
    out = []
    for name, pos in (("ATT_Muzzle", (0, 0.650, LAUNCHER_Z)), ("ATT_Optic", (0, -0.120, LAUNCHER_Z + 0.035))):
        e = bpy.data.objects.new(name, None)
        e.empty_display_size = 0.02
        e.location = pos
        coll.objects.link(e)
        e.parent = weapon
        out.append(e)
    return out


def launcher_on_back(arm, launcher, coll):
    """A copy of the launcher mesh carried diagonally across the back behind the pack, in ATT_Back bone space."""
    o = launcher.copy()
    o.data = launcher.data.copy()
    o.name = "LauncherBack"
    coll.objects.link(o)
    o.parent = None
    # World (rest pose): the body faces +Y, so the back is -Y; the tube runs from the right hip up to the left shoulder.
    world = Matrix.Translation((0.0, -0.33, 1.12)) @ Matrix.Rotation(math.radians(-58), 4, "Y") @ Matrix.Rotation(math.radians(90), 4, "X") \
        @ Matrix.Translation((0, -0.200, -LAUNCHER_Z))
    o.data.transform(world)
    att = arm.data.bones["ATT_Back"].matrix_local
    o.data.transform(att.inverted())
    o.matrix_world = Matrix.Identity(4)
    place(arm, o, "ATT_Back")
    return o


def build_ammo_box(coll, mats):
    """Hard 200-round box: 0.08 x 0.16 x 0.11 m, its belt clip against the hip (x across the body, y forward, z up)."""
    w = FW.WB(mats, ["Polymer_OD", "Polymer_Black", "Metal_Worn", "Webbing_RangerGreen"])
    cx = 0.030  # towards the body: the clip side touches the belt
    w.box((0.078, 0.155, 0.100), (cx, 0, -0.050), "Polymer_OD", 0.009, segs=2)
    w.box((0.082, 0.160, 0.014), (cx, 0, 0.006), "Polymer_Black", 0.004)                       # lid
    w.box((0.016, 0.034, 0.010), (cx - 0.042, 0, 0.000), "Metal_Worn", 0.002)                  # latch (outer side)
    w.box((0.012, 0.070, 0.010), (cx, 0, 0.017), "Polymer_Black", 0.003)                       # handle
    w.box((0.010, 0.050, 0.070), (cx + 0.044, 0, -0.030), "Webbing_RangerGreen", 0.003)        # belt clip
    for i in range(3):
        w.box((0.080, 0.005, 0.080), (cx, -0.055 + i * 0.055, -0.055), "Polymer_OD", 0.002)    # ribs
    return w.obj("LMGAmmoBox", coll)


def lmg_mounts(coll, weapon):
    out = []
    for name, pos in LMG_MOUNTS.items():
        e = bpy.data.objects.new(name, None)
        e.empty_display_size = 0.02
        e.location = pos
        coll.objects.link(e)
        e.parent = weapon
        out.append(e)
    axis, palm, thumb, grip = W.support_frame()
    e = bpy.data.objects.new("GRIP_Support", None)
    e.empty_display_size = 0.03
    m = Matrix((axis.cross(-palm).normalized(), axis, -palm)).transposed().to_4x4()
    m.translation = grip
    e.matrix_world = m
    coll.objects.link(e)
    e.parent = weapon
    out.append(e)
    return out


def stage_body():
    """The soldier's body and skeleton (char_body, VISUAL-03), for the previews: the hands must close on the grips. The
    textures go to a temp dir so the committed ones stay untouched."""
    tmp = tempfile.mkdtemp(prefix="fn_sw_")
    tex = T.build_all(tmp)
    tex["skin_v03"] = os.path.join(INF, "textures", "skin_head_v03_albedo.png")
    mats = M.build(tex)
    res = B.build(L.collection("Body"), mats)
    res["weight_ref"].hide_set(True)
    res["weight_ref"].hide_render = True
    return res["arm"], mats, list(res["pieces"].values())


def place(arm, o, bone):
    o.parent = arm
    o.parent_type = "BONE"
    o.parent_bone = bone
    o.matrix_world = arm.matrix_world @ arm.data.bones[bone].matrix_local


def previews(outdir, arm, lmg, box, nade, tube):
    import ap_lib
    os.makedirs(outdir, exist_ok=True)
    L.setup_render((760, 760))
    bpy.context.scene.render.image_settings.file_format = "JPEG"
    A.setup_controls(arm)
    acts = A.author_and_bake(arm, only=["Idle"])
    A.remove_controls(arm)
    arm.animation_data.action = acts["Idle"]
    bpy.context.scene.frame_set(0)
    shots = []
    for name, tgt, d, az, el in (("front", (0, 0.05, 1.05), 2.6, 20, 6), ("side", (0.1, 0.2, 1.15), 1.4, 80, 8),
                                 ("hands", (0.05, 0.30, 1.18), 0.9, 55, 14), ("hip", (-0.15, 0.0, 1.0), 0.9, 120, 10)):
        shots.append(L.render_view(os.path.join(outdir, "lmg_held_%s.jpg" % name), tgt, d, az, el, lens=55, frame=0))
    ap_lib.sheet(shots, os.path.join(outdir, "lmg_held.jpg"), 4)
    # The weapon alone at the origin.
    arm.animation_data.action = None
    for o in bpy.data.objects:
        if o.type == "MESH" and o not in (lmg,) and o.name != "PreviewGround":
            o.hide_render = True
    saved = (lmg.parent, lmg.parent_type, lmg.parent_bone, lmg.matrix_world.copy())
    lmg.parent = None
    lmg.matrix_world = Matrix.Translation((0, 0, 0.6))
    shots = []
    for name, az, el in (("l", 90, 8), ("r", 270, 8), ("q", 40, 25), ("top", 0, 80)):
        shots.append(L.render_view(os.path.join(outdir, "lmg_%s.jpg" % name), (0, 0.17, 0.6), 1.9, az, el, lens=55))
    lmg.hide_render = True
    box.hide_render = False
    bsaved = (box.parent, box.parent_type, box.parent_bone, box.matrix_world.copy())
    box.parent = None
    box.matrix_world = Matrix.Translation((0, 0, 0.6))
    shots.append(L.render_view(os.path.join(outdir, "lmg_ammo_box.jpg"), (0, 0, 0.55), 0.6, 35, 25, lens=55))
    ap_lib.sheet(shots, os.path.join(outdir, "lmg_turntable.jpg"), 5)
    box.hide_render = True
    shots = []
    for o, at, d in ((nade, (0, 0, 0.6), 0.35), (tube, (0, 0.2, 0.6), 1.5)):
        o.hide_render = False
        o.matrix_world = Matrix.Translation((0, 0, 0.6))
        for name, az, el in (("a", 60, 20), ("b", 250, 15)):
            shots.append(L.render_view(os.path.join(outdir, "%s_%s.jpg" % (o.name, name)), at, d, az, el, lens=55))
        o.hide_render = True
    ap_lib.sheet(shots, os.path.join(outdir, "grenade_launcher.jpg"), 4)
    lmg.hide_render = False
    lmg.parent, lmg.parent_type, lmg.parent_bone = saved[0], saved[1], saved[2]
    lmg.matrix_world = saved[3]
    box.parent, box.parent_type, box.parent_bone = bsaved[0], bsaved[1], bsaved[2]
    box.matrix_world = bsaved[3]


def write_equipment(key, attach, slot, glb_res):
    path = os.path.join(INF, "equipment", key + ".tres")
    txt = ('[gd_resource type="Resource" script_class="InfantryEquipment" load_steps=3 format=3]\n\n'
           '[ext_resource type="Script" path="res://scripts/characters/infantry_equipment.gd" id="1_eq"]\n'
           '[ext_resource type="PackedScene" path="%s" id="2_scene"]\n\n'
           '[resource]\nscript = ExtResource("1_eq")\nid = "%s"\nscene = ExtResource("2_scene")\nmode = %d\n'
           'attach = "%s"\nslot = "%s"\nhides_body = PackedStringArray()\n') % (glb_res, key, RIGID, attach, slot)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(txt)


def write_mg_loadouts():
    """NATO_mg / RU_mg / CN_mg: the faction rifleman's items minus the rifle and its accessories, plus the LMG and box;
    NATO_gren / RU_gren / CN_gren: the faction rifleman plus the launcher on the back."""
    import re
    todo = [(lo, src, display, True) for lo, (src, display) in MG_LOADOUTS.items()]
    todo += [(lo, src, display, False) for lo, (src, display) in GREN_LOADOUTS.items()]
    for lo, src, display, mg in todo:
        with open(os.path.join(LOADOUT_DIR, src + ".tres"), encoding="utf-8") as f:
            txt = f.read()
        paths = re.findall(r'\[ext_resource type="Resource" path="([^"]+)" id="[^"]+"\]', txt)
        if mg:
            keep = [p for p in paths if os.path.splitext(os.path.basename(p))[0] not in RIFLE_ITEMS]
            keep += ["res://assets/characters/infantry/equipment/lmg.tres", "res://assets/characters/infantry/equipment/lmg_ammo_box.tres"]
        else:
            keep = paths + ["res://assets/characters/infantry/equipment/launcher_back.tres"]
        lines = ['[gd_resource type="Resource" script_class="InfantryLoadout" load_steps=%d format=3]\n' % (len(keep) + 3),
                 '[ext_resource type="Script" path="res://scripts/characters/infantry_loadout.gd" id="1_lo"]',
                 '[ext_resource type="Script" path="res://scripts/characters/infantry_equipment.gd" id="2_eq"]']
        ids = []
        for i, p in enumerate(keep):
            k = "%d_%s" % (i + 3, os.path.splitext(os.path.basename(p))[0])
            ids.append(k)
            lines.append('[ext_resource type="Resource" path="%s" id="%s"]' % (p, k))
        lines += ["", "[resource]", 'script = ExtResource("1_lo")', 'id = "%s"' % lo, 'display_name = "%s"' % display,
                  'items = Array[ExtResource("2_eq")]([%s])' % ", ".join('ExtResource("%s")' % k for k in ids), ""]
        with open(os.path.join(LOADOUT_DIR, lo + ".tres"), "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines))


def main():
    t0 = time.time()
    o = parse_args()
    L.clear_scene()
    arm, mats, body = stage_body()
    coll = L.collection("SupportWeapons")
    lmg = build_lmg(coll, mats)
    M.apply_box_uvs(lmg)
    mounts = lmg_mounts(coll, lmg)
    place(arm, lmg, "ATT_Weapon")
    box = build_ammo_box(coll, mats)
    M.apply_box_uvs(box)
    place(arm, box, "ATT_Hip_L")
    nade = build_grenade(coll, mats)
    M.apply_box_uvs(nade)
    tube = build_launcher(coll, mats)
    M.apply_box_uvs(tube)
    tube_mounts = launcher_mounts(coll, tube)
    back = launcher_on_back(arm, tube, coll)
    nade.hide_render = True
    tube.hide_render = True
    log = {"tris": {"lmg": L.tri_count(lmg), "lmg_ammo_box": L.tri_count(box), "grenade": L.tri_count(nade), "launcher": L.tri_count(tube)}}
    if o["previews"]:
        previews(os.path.abspath(o["previews"]), arm, lmg, box, nade, tube)
    if o["export"]:
        lod_coll = L.collection("LODs")
        out = {}
        for key, obj, extra in (("lmg", lmg, mounts), ("lmg_ammo_box", box, []), ("grenade", nade, []), ("launcher", tube, tube_mounts),
                                ("launcher_back", back, [])):
            attach, slot, sub = PIECES[key]
            path = os.path.join(INF, sub, key + ".glb")
            size, tris = E.export_rigid(obj, key, path, lod_coll, extra)
            if attach:
                write_equipment(key, attach, slot, "res://assets/characters/infantry/%s/%s.glb" % (sub, key))
            out[key] = {"bytes": size, "lod_tris": tris}
        write_mg_loadouts()
        log["export"] = out
        blend = os.path.join(INF, "blender", "support_weapons.blend")
        for ob in lod_coll.objects:
            ob.hide_set(True)
            ob.hide_render = True
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
    log["t_total"] = round(time.time() - t0, 1)
    print("FNSW", json.dumps(log))


if __name__ == "__main__" or True:
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.stdout.flush()
        os._exit(1)
