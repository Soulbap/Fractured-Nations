"""GAMEPLAY-04C: the expanded infantry arsenal on the CHARACTER-01 weapon contract (original assets).

  dmr             SR-25-class 7.62 mm designated marksman rifle: long upper with a full-length top rail, 20-round straight
                  magazine, long free-float handguard, heavy barrel with muzzle brake, folded bipod, adjustable stock and a
                  fixed 3-9x scope whose axis lies on the first-person sight line of every rifle (OPTIC_Z + SIGHT_H), so the
                  marksman loadouts carry no faction optic.
  gpmg            M240-class 7.62 mm general-purpose machine gun: long receiver with top cover and rail (the faction optic
                  sits on it, as on the LMG), 100-round soft box, long barrel with carrying handle, folded bipod, fixed stock.
  gl40            M320-class standalone 40 mm grenade launcher in weapon space (origin at the grip, +Y muzzle): what first
                  person holds when the secondary weapon is raised (WeaponDef.viewmodel_scene).
  gl40_hip        the same launcher hanging muzzle-down on the right hip (ATT_Hip_R), for the 40 mm grenadier loadouts.
  recoilless      Carl-Gustaf-class 84 mm recoilless rifle in weapon space (origin at the rear grip, +Y muzzle).
  recoilless_back the same tube across the back (ATT_Back), for the anti-structure gunner loadouts.

Weapon space as every rifle (docs/CHARACTER_STANDARD.md section 3): origin = pistol-grip centre, +Y muzzle, +Z up, bore at
z = BORE_Z, GRIP_Support at the handguard, ATT_Muzzle at the muzzle. The compact carbine of GAMEPLAY-04 is the CHARACTER-01
carbine (equipment/carbine.tres), reused.

Loadouts written (faction rifleman items as the base, faction looks kept): <F>_carbine (rifle -> carbine), <F>_dmr (rifle and
faction optic -> DMR), <F>_hmg (rifle -> GPMG + ammunition box), <F>_gl (+ 40 mm launcher on the hip), <F>_at (+ recoilless on
the back), for F in NATO, RU, CN (InfantryRole loadout suffixes carbine, dmr, hmg, gl, at).

Background Blender:
    blender -b --factory-startup --python tools/blender/asset_production/characters/build_gameplay04_weapons.py -- [options]
Options:
    --export          GLBs into assets/characters/infantry/weapons|parts/, equipment .tres, loadouts, .blend source
    --previews DIR    turntable sheets of every weapon and the NATO body holding the DMR and the GPMG in the Idle pose
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
PIECES = {
    "dmr": ("ATT_Weapon", "weapon", "weapons"),
    "gpmg": ("ATT_Weapon", "weapon", "weapons"),
    "gl40": ("", "item", "weapons"),
    "gl40_hip": ("ATT_Hip_R", "hip_r", "parts"),
    "recoilless": ("", "item", "weapons"),
    "recoilless_back": ("ATT_Back", "back_weapon", "parts"),
}
FACTIONS = {"NATO": ("nato_rifle", "nato_optic", "NATO"), "RU": ("ru_rifle", "ru_optic", "Russian"), "CN": ("cn_rifle", "cn_optic", "Chinese")}
RIFLE_ACC = ("foregrip", "laser")
EQ = "res://assets/characters/infantry/equipment/%s.tres"
SCOPE_AXIS = FW.OPTIC_Z + FW.SIGHT_H


def rx(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"export": False, "previews": None}
    for i, a in enumerate(argv):
        if a == "--previews":
            o["previews"] = argv[i + 1]
        elif a == "--export":
            o["export"] = True
    return o


def stage_body():
    """The CHARACTER-01 body and skeleton (as build_support_weapons.stage_body: the hands must close on the grips)."""
    tmp = tempfile.mkdtemp(prefix="fn_g4w_")
    tex = T.build_all(tmp)
    tex["skin"] = os.path.join(tmp, "skin_head_albedo.png")
    B.make_skin_texture(tex["skin"])
    mats = M.build(tex)
    arm = S.build_armature(L.collection("Rig"))
    coll = L.collection("Body")
    body = B.build_body(coll)
    body.data.materials.append(mats["SkinBody"])
    L.parent_to_armature(body, arm, auto=True)
    hands = B.build_hands(coll)
    hands.data.materials.append(mats["SkinBody"])
    L.parent_to_armature(hands, arm, auto=True)
    head = B.build_head(coll, mats["Skin"], mats["Eye"], mats["Iris"])
    head.vertex_groups.clear()
    vg = head.vertex_groups.new(name="Head")
    vg.add(list(range(len(head.data.vertices))), 1.0, "REPLACE")
    L._add_armature_mod(head, arm)
    return arm, mats, [body, hands, head]


def place(arm, o, bone):
    o.parent = arm
    o.parent_type = "BONE"
    o.parent_bone = bone
    o.matrix_world = arm.matrix_world @ arm.data.bones[bone].matrix_local


def write_equipment(key, attach, slot, glb_res):
    path = os.path.join(INF, "equipment", key + ".tres")
    txt = ('[gd_resource type="Resource" script_class="InfantryEquipment" load_steps=3 format=3]\n\n'
           '[ext_resource type="Script" path="res://scripts/characters/infantry_equipment.gd" id="1_eq"]\n'
           '[ext_resource type="PackedScene" path="%s" id="2_scene"]\n\n'
           '[resource]\nscript = ExtResource("1_eq")\nid = "%s"\nscene = ExtResource("2_scene")\nmode = %d\n'
           'attach = "%s"\nslot = "%s"\nhides_body = PackedStringArray()\n') % (glb_res, key, RIGID, attach, slot)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(txt)


def mounts(coll, weapon, table, support=True):
    out = []
    for name, pos in table.items():
        e = bpy.data.objects.new(name, None)
        e.empty_display_size = 0.02
        e.location = pos
        coll.objects.link(e)
        e.parent = weapon
        out.append(e)
    if support:
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


def build_dmr(coll, mats):
    w = FW.WB(mats, ["Metal_Black", "Polymer_Black", "Metal_Worn", "Lens"])
    z = BORE_Z
    # Lower receiver, magwell and the 20-round straight magazine, trigger group, pistol grip at the origin.
    w.box((0.034, 0.200, 0.044), (0, 0.000, z - 0.046), "Metal_Black", 0.004)
    w.box((0.040, 0.078, 0.060), (0, 0.072, z - 0.064), "Metal_Black", 0.005)
    w.box((0.032, 0.070, 0.120), (0, 0.075, z - 0.150), "Metal_Black", 0.004)                     # straight magazine
    w.box((0.036, 0.074, 0.012), (0, 0.075, z - 0.213), "Polymer_Black", 0.003)
    w.box((0.006, 0.060, 0.006), (0, 0.030, z - 0.086), "Metal_Black", 0.002)
    w.box((0.004, 0.008, 0.020), (0, 0.032, z - 0.068), "Metal_Worn", 0.0015, rot=rx(15))
    w.box((0.030, 0.042, 0.106), (0, -0.002, -0.004), "Polymer_Black", 0.010, rot=rx(-20), segs=2)
    w.box((0.032, 0.048, 0.010), (0, -0.020, -0.056), "Polymer_Black", 0.004, rot=rx(-20))
    # Upper receiver with a full-length rail, ejection port, charging handle.
    w.box((0.036, 0.230, 0.056), (0, 0.004, z + 0.004), "Metal_Black", 0.004)
    w.box((0.004, 0.080, 0.022), (0.019, 0.020, z + 0.002), "Metal_Worn", 0.002)
    w.box((0.046, 0.014, 0.010), (0, -0.118, z + 0.026), "Metal_Black", 0.003)
    FW.rail(w, -0.110, 0.560, z + 0.034)
    # Long free-float handguard, heavy barrel, muzzle brake.
    w.box((0.050, 0.380, 0.054), (0, 0.320, z - 0.002), "Metal_Black", 0.012, segs=2)
    for sx in (-1, 1):
        for i in range(8):
            w.box((0.004, 0.030, 0.008), (sx * 0.0245, 0.160 + i * 0.044, z - 0.004), "Polymer_Black", 0.0015)
    w.cyl(0.0110, 0.0110, 0.190, (0, 0.600, z), "Metal_Black", segs=14)
    w.box((0.030, 0.060, 0.026), (0, 0.720, z), "Metal_Black", 0.004)                              # muzzle brake
    for i in range(3):
        w.box((0.032, 0.006, 0.020), (0, 0.700 + i * 0.016, z), "Metal_Worn", 0.001)
    # Folded bipod under the handguard.
    for sx in (-1, 1):
        w.cyl(0.0050, 0.0050, 0.190, (sx * 0.012, 0.410, z - 0.040), "Metal_Black", segs=8)
    w.box((0.040, 0.024, 0.018), (0, 0.500, z - 0.034), "Metal_Black", 0.004)
    # Adjustable precision stock with cheek riser.
    w.cyl(0.0155, 0.0155, 0.180, (0, -0.195, z), "Metal_Black")
    by = -W.STOCK_PULL - 0.020
    w.box((0.042, 0.160, 0.052), (0, by + 0.095, z - 0.004), "Polymer_Black", 0.012, segs=2)
    w.box((0.034, 0.110, 0.024), (0, by + 0.085, z + 0.030), "Polymer_Black", 0.008)               # cheek riser
    w.box((0.038, 0.110, 0.070), (0, by + 0.060, z - 0.056), "Polymer_Black", 0.012, rot=rx(14), segs=2)
    w.box((0.044, 0.022, 0.140), (0, by + 0.010, z - 0.034), "Polymer_Black", 0.008, segs=2)
    # 3-9x scope in rings on the rail; its axis is the sight line of every rifle optic.
    h = SCOPE_AXIS
    for y in (-0.030, 0.070):
        w.box((0.024, 0.016, h - (z + 0.034) + 0.004), (0, y, (h + z + 0.034) / 2), "Metal_Black", 0.003)
    w.cyl(0.0150, 0.0150, 0.170, (0, 0.020, h), "Metal_Black", segs=18)
    w.cyl(0.0240, 0.0160, 0.060, (0, 0.130, h), "Metal_Black", segs=18)                             # objective bell
    w.cyl(0.0205, 0.0160, 0.050, (0, -0.090, h), "Metal_Black", segs=18)                            # ocular
    w.cyl(0.0110, 0.0110, 0.030, (0, 0.020, h + 0.020), "Metal_Black", axis=(0, 0, 1), segs=12)     # turrets
    w.cyl(0.0110, 0.0110, 0.030, (0.020, 0.020, h), "Metal_Black", axis=(1, 0, 0), segs=12)
    w.cyl(0.0220, 0.0220, 0.002, (0, 0.161, h), "Lens", segs=18)
    w.cyl(0.0185, 0.0185, 0.002, (0, -0.116, h), "Lens", segs=18)
    return w.obj("DMR", coll)


DMR_MOUNTS = {"ATT_Optic": (0, 0.020, FW.OPTIC_Z), "ATT_Underbarrel": (0, 0.330, BORE_Z - 0.035),
              "ATT_RailRight": (0.032, 0.380, BORE_Z), "ATT_Muzzle": (0, 0.752, BORE_Z)}


def build_gpmg(coll, mats):
    w = FW.WB(mats, ["Metal_Black", "Polymer_Black", "Metal_Worn", "Polymer_OD"])
    z = BORE_Z
    # Trigger group and pistol grip at the origin.
    w.box((0.044, 0.130, 0.044), (0, 0.000, z - 0.054), "Metal_Black", 0.004)
    w.box((0.006, 0.066, 0.006), (0, 0.022, z - 0.094), "Metal_Black", 0.002)
    w.box((0.004, 0.008, 0.020), (0, 0.024, z - 0.076), "Metal_Worn", 0.0015, rot=rx(15))
    w.box((0.032, 0.044, 0.110), (0, -0.004, -0.006), "Polymer_Black", 0.009, rot=rx(-20), segs=2)
    # Long, tall receiver with the top cover, rail, cocking handle on the right, feed tray and the soft box on the left.
    w.box((0.060, 0.400, 0.074), (0, 0.090, z + 0.004), "Metal_Black", 0.005)
    w.box((0.064, 0.200, 0.016), (0, 0.040, z + 0.040), "Metal_Black", 0.004)
    FW.rail(w, -0.060, 0.120, z + 0.051)
    w.box((0.020, 0.024, 0.014), (0.038, 0.170, z + 0.000), "Metal_Black", 0.003)
    w.box((0.044, 0.056, 0.030), (-0.050, 0.060, z - 0.004), "Metal_Black", 0.003)
    w.box((0.080, 0.120, 0.120), (-0.040, 0.060, z - 0.104), "Polymer_OD", 0.012, segs=2)
    for i in range(5):
        w.box((0.010, 0.010, 0.009), (-0.064 + i * 0.010, 0.060, z + 0.016), "Metal_Worn", 0.002)
    # Heat shield / handguard, gas cylinder, long barrel, carrying handle, front sight, flash hider.
    w.box((0.050, 0.120, 0.050), (0, 0.350, z - 0.014), "Metal_Black", 0.008)
    w.cyl(0.0110, 0.0110, 0.320, (0, 0.500, z - 0.036), "Metal_Black")
    w.cyl(0.0135, 0.0135, 0.420, (0, 0.580, z), "Metal_Black", segs=14)
    w.box((0.012, 0.090, 0.012), (0, 0.440, z + 0.068), "Polymer_Black", 0.004)
    w.box((0.010, 0.014, 0.060), (0, 0.400, z + 0.038), "Metal_Black", 0.002)
    w.box((0.010, 0.014, 0.060), (0, 0.480, z + 0.038), "Metal_Black", 0.002)
    w.box((0.014, 0.010, 0.044), (0, 0.760, z + 0.030), "Metal_Black", 0.002)
    w.cyl(0.0170, 0.0150, 0.070, (0, 0.815, z), "Metal_Black", segs=14)
    # Folded bipod at the gas block.
    for sx in (-1, 1):
        w.cyl(0.0060, 0.0060, 0.240, (sx * 0.014, 0.560, z - 0.060), "Metal_Black", segs=8)
        w.box((0.012, 0.022, 0.010), (sx * 0.014, 0.445, z - 0.060), "Polymer_Black", 0.003)
    w.box((0.046, 0.030, 0.024), (0, 0.690, z - 0.046), "Metal_Black", 0.004)
    # Fixed skeleton stock with buffer.
    by = -W.STOCK_PULL - 0.020
    w.box((0.044, 0.200, 0.050), (0, by + 0.130, z - 0.006), "Polymer_Black", 0.010, segs=2)
    w.box((0.040, 0.130, 0.070), (0, by + 0.070, z - 0.056), "Polymer_Black", 0.010, rot=rx(12), segs=2)
    w.box((0.046, 0.022, 0.140), (0, by + 0.010, z - 0.036), "Polymer_Black", 0.008, segs=2)
    return w.obj("GPMG", coll)


GPMG_MOUNTS = {"ATT_Optic": (0, 0.030, FW.OPTIC_Z + 0.017), "ATT_Underbarrel": (0, 0.350, BORE_Z - 0.045),
               "ATT_RailRight": (0.036, 0.200, BORE_Z), "ATT_Muzzle": (0, 0.850, BORE_Z)}

GL_Z = 0.070


def build_gl40(coll, mats):
    """M320-class standalone 40 mm launcher: pistol grip at the origin, a fat 30 cm barrel on a side-swinging breech, leaf
    sight on the left, the barrel axis GL_Z above the grip."""
    w = FW.WB(mats, ["Polymer_Black", "Metal_Black", "Metal_Worn", "Polymer_OD"])
    z = GL_Z
    w.box((0.034, 0.170, 0.050), (0, 0.040, z - 0.040), "Polymer_Black", 0.008, segs=2)          # receiver / frame
    w.box((0.030, 0.042, 0.100), (0, -0.002, -0.006), "Polymer_Black", 0.010, rot=rx(-18), segs=2)
    w.box((0.006, 0.050, 0.006), (0, 0.030, z - 0.076), "Polymer_Black", 0.002)                  # trigger guard
    w.box((0.004, 0.008, 0.018), (0, 0.030, z - 0.062), "Metal_Worn", 0.0015, rot=rx(15))
    w.cyl(0.0260, 0.0260, 0.300, (0, 0.150, z), "Polymer_OD", segs=18)                           # barrel
    w.cyl(0.0280, 0.0280, 0.030, (0, 0.290, z), "Polymer_Black", segs=18)                        # muzzle band
    w.cyl(0.0280, 0.0280, 0.040, (0, 0.020, z), "Metal_Black", segs=18)                          # breech
    w.box((0.010, 0.040, 0.030), (-0.034, 0.080, z + 0.010), "Metal_Black", 0.002)               # leaf sight (left)
    w.box((0.004, 0.010, 0.040), (-0.040, 0.090, z + 0.040), "Metal_Worn", 0.001)
    w.box((0.026, 0.060, 0.030), (0, -0.080, z - 0.020), "Polymer_Black", 0.006)                 # stock stub
    w.box((0.030, 0.020, 0.090), (0, -0.115, z - 0.030), "Polymer_Black", 0.006)
    return w.obj("GL40", coll)


RL_Z = 0.110


def build_recoilless(coll, mats):
    """84 mm recoilless rifle: a 1.07 m tube with the venturi at the rear, shoulder pad and rear pistol grip (origin), front
    grip under the tube, optical sight on the left, the tube axis RL_Z above the grip."""
    w = FW.WB(mats, ["Metal_Black", "Polymer_Black", "Metal_Worn", "Helmet_Shell", "Lens"])
    z = RL_Z
    w.cyl(0.0500, 0.0500, 0.780, (0, 0.230, z), "Helmet_Shell", segs=20)                         # tube
    w.cyl(0.0560, 0.0560, 0.040, (0, 0.600, z), "Metal_Black", segs=20)                          # muzzle band
    w.cyl(0.0560, 0.0680, 0.180, (0, -0.240, z), "Metal_Black", segs=20)                         # venturi
    w.cyl(0.0560, 0.0560, 0.050, (0, -0.120, z), "Metal_Worn", segs=20)                          # breech ring
    w.box((0.050, 0.080, 0.050), (0, 0.000, z - 0.060), "Polymer_Black", 0.008)                  # rear grip housing
    w.box((0.030, 0.042, 0.100), (0, 0.000, -0.010), "Polymer_Black", 0.009, rot=rx(-14), segs=2)  # rear pistol grip
    w.box((0.030, 0.040, 0.090), (0, 0.250, z - 0.090), "Polymer_Black", 0.009, rot=rx(-6))       # front grip
    w.box((0.090, 0.160, 0.030), (0, -0.030, z - 0.058), "Polymer_Black", 0.010)                 # shoulder pad
    w.box((0.030, 0.120, 0.040), (-0.070, 0.060, z + 0.010), "Metal_Black", 0.006)               # optical sight (left)
    w.cyl(0.0140, 0.0140, 0.002, (-0.070, 0.121, z + 0.010), "Lens", segs=14)
    w.box((0.050, 0.012, 0.010), (-0.040, 0.060, z + 0.010), "Metal_Black", 0.002)
    return w.obj("Recoilless", coll)


def on_hip(arm, gl, coll):
    """The 40 mm launcher hanging muzzle-down on the right hip, in ATT_Hip_R bone space (rest pose: the body faces +Y)."""
    o = gl.copy()
    o.data = gl.data.copy()
    o.name = "GL40Hip"
    coll.objects.link(o)
    o.parent = None
    hip = arm.data.bones["ATT_Hip_R"].matrix_local
    out = 1.0 if hip.translation.x >= 0.0 else -1.0  # away from the body's centre line
    world = Matrix.Translation(hip.translation + Vector((out * 0.055, 0.030, -0.040))) @ Matrix.Rotation(math.radians(-100), 4, "X")         @ Matrix.Translation((0, -0.060, -GL_Z))
    o.data.transform(world)
    o.data.transform(hip.inverted())
    o.matrix_world = Matrix.Identity(4)
    place(arm, o, "ATT_Hip_R")
    return o


def on_back(arm, tube, coll):
    """The recoilless rifle across the back behind the pack (ATT_Back), right hip up to the left shoulder."""
    o = tube.copy()
    o.data = tube.data.copy()
    o.name = "RecoillessBack"
    coll.objects.link(o)
    o.parent = None
    world = Matrix.Translation((0.0, -0.36, 1.12)) @ Matrix.Rotation(math.radians(-58), 4, "Y") @ Matrix.Rotation(math.radians(90), 4, "X") \
        @ Matrix.Translation((0, -0.180, -RL_Z))
    o.data.transform(world)
    att = arm.data.bones["ATT_Back"].matrix_local
    o.data.transform(att.inverted())
    o.matrix_world = Matrix.Identity(4)
    place(arm, o, "ATT_Back")
    return o


def previews(outdir, arm, held, loose):
    import ap_lib
    os.makedirs(outdir, exist_ok=True)
    L.setup_render((760, 760))
    bpy.context.scene.render.image_settings.file_format = "JPEG"
    A.setup_controls(arm)
    acts = A.author_and_bake(arm, only=["Idle"])
    A.remove_controls(arm)
    arm.animation_data.action = acts["Idle"]
    bpy.context.scene.frame_set(0)
    # Each held weapon in turn on the body (hands on its grip and handguard), the hip and back pieces shown with it.
    for key, obj in held.items():
        for o in held.values():
            o.hide_render = o is not obj
        shots = []
        for name, tgt, d, az, el in (("front", (0, 0.05, 1.05), 2.6, 20, 6), ("side", (0.1, 0.2, 1.15), 1.6, 80, 8),
                                     ("hands", (0.05, 0.30, 1.18), 0.9, 55, 14), ("back", (0, -0.1, 1.1), 2.0, 200, 10)):
            shots.append(L.render_view(os.path.join(outdir, "%s_held_%s.jpg" % (key, name)), tgt, d, az, el, lens=55, frame=0))
        ap_lib.sheet(shots, os.path.join(outdir, "%s_held.jpg" % key), 4)
    arm.animation_data.action = None
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.hide_render = True
    # Every weapon alone at the origin.
    shots = []
    for key, obj in list(held.items()) + list(loose.items()):
        saved = (obj.parent, obj.parent_type, obj.parent_bone, obj.matrix_world.copy())
        obj.parent = None
        obj.matrix_world = Matrix.Translation((0, 0, 0.6))
        obj.hide_render = False
        for name, az, el in (("l", 90, 8), ("q", 40, 25)):
            shots.append(L.render_view(os.path.join(outdir, "%s_%s.jpg" % (key, name)), (0, 0.2, 0.6), 2.0, az, el, lens=55))
        obj.hide_render = True
        obj.parent, obj.parent_type, obj.parent_bone = saved[0], saved[1], saved[2]
        obj.matrix_world = saved[3]
    ap_lib.sheet(shots, os.path.join(outdir, "weapons_turntable.jpg"), 4)


def write_loadouts():
    import re
    for fam, (rifle, optic, nation) in FACTIONS.items():
        with open(os.path.join(LOADOUT_DIR, fam + "_rifleman.tres"), encoding="utf-8") as f:
            txt = f.read()
        paths = re.findall(r'\[ext_resource type="Resource" path="([^"]+)" id="[^"]+"\]', txt)
        base = lambda p: os.path.splitext(os.path.basename(p))[0]  # noqa: E731
        no_rifle = [p for p in paths if base(p) not in (rifle,) + RIFLE_ACC]
        table = {
            "carbine": (no_rifle + [EQ % "carbine"], "%s rifleman (compact carbine)" % nation),
            "dmr": ([p for p in no_rifle if base(p) not in (optic, "optic_reddot")] + [EQ % "dmr"], "%s designated marksman (7.62 DMR, 3-9x scope)" % nation),
            "hmg": (no_rifle + [EQ % "gpmg", EQ % "lmg_ammo_box"], "%s heavy machine gunner (7.62 GPMG)" % nation),
            "gl": (paths + [EQ % "gl40_hip"], "%s grenadier (rifle, 40 mm grenade launcher)" % nation),
            "at": (paths + [EQ % "recoilless_back"], "%s anti-structure gunner (rifle, 84 mm recoilless rifle)" % nation),
        }
        for suffix, (keep, display) in table.items():
            lo = "%s_%s" % (fam, suffix)
            lines = ['[gd_resource type="Resource" script_class="InfantryLoadout" load_steps=%d format=3]\n' % (len(keep) + 3),
                     '[ext_resource type="Script" path="res://scripts/characters/infantry_loadout.gd" id="1_lo"]',
                     '[ext_resource type="Script" path="res://scripts/characters/infantry_equipment.gd" id="2_eq"]']
            ids = []
            for i, p in enumerate(keep):
                k = "%d_%s" % (i + 3, base(p))
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
    coll = L.collection("Gameplay04Weapons")
    dmr = build_dmr(coll, mats)
    gpmg = build_gpmg(coll, mats)
    gl = build_gl40(coll, mats)
    rr = build_recoilless(coll, mats)
    for ob in (dmr, gpmg, gl, rr):
        M.apply_box_uvs(ob)
    dmr_m = mounts(coll, dmr, DMR_MOUNTS)
    gpmg_m = mounts(coll, gpmg, GPMG_MOUNTS)
    gl_m = mounts(coll, gl, {"ATT_Muzzle": (0, 0.305, GL_Z), "ATT_Optic": (-0.034, 0.080, GL_Z + 0.040)}, support=False)
    rr_m = mounts(coll, rr, {"ATT_Muzzle": (0, 0.620, RL_Z), "ATT_Optic": (-0.070, 0.000, RL_Z + 0.010)}, support=False)
    place(arm, dmr, "ATT_Weapon")
    place(arm, gpmg, "ATT_Weapon")
    hip = on_hip(arm, gl, coll)
    back = on_back(arm, rr, coll)
    gl.hide_render = True
    rr.hide_render = True
    log = {"tris": {"dmr": L.tri_count(dmr), "gpmg": L.tri_count(gpmg), "gl40": L.tri_count(gl), "recoilless": L.tri_count(rr)}}
    if o["previews"]:
        previews(os.path.abspath(o["previews"]), arm, {"dmr": dmr, "gpmg": gpmg}, {"gl40": gl, "recoilless": rr, "gl40_hip": hip, "recoilless_back": back})
    if o["export"]:
        lod_coll = L.collection("LODs")
        out = {}
        for key, obj, extra in (("dmr", dmr, dmr_m), ("gpmg", gpmg, gpmg_m), ("gl40", gl, gl_m), ("gl40_hip", hip, []),
                                ("recoilless", rr, rr_m), ("recoilless_back", back, [])):
            attach, slot, sub = PIECES[key]
            path = os.path.join(INF, sub, key + ".glb")
            size, tris = E.export_rigid(obj, key, path, lod_coll, extra)
            if attach:
                write_equipment(key, attach, slot, "res://assets/characters/infantry/%s/%s.glb" % (sub, key))
            out[key] = {"bytes": size, "lod_tris": tris}
        write_loadouts()
        log["export"] = out
        blend = os.path.join(INF, "blender", "gameplay04_weapons.blend")
        for ob in lod_coll.objects:
            ob.hide_set(True)
            ob.hide_render = True
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
    log["t_total"] = round(time.time() - t0, 1)
    print("FNG4W", json.dumps(log))


if __name__ == "__main__" or True:
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.stdout.flush()
        os._exit(1)
