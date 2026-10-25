"""VISUAL-03: stills of the dressed soldier in chosen clip frames (aim / reload checks), the weapon's detachable magazine on
the ATT_Magazine bone as in the game.
    blender -b assets/characters/infantry/blender/infantry.blend --python tools/visual03/pose_stills.py -- OUT_DIR Clip:frame[,Clip:frame...]
Writes OUT_DIR/<clip>_<frame>_<view>.png for the views front, right, left, a close-up of the head and rifle and two of the hands.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "blender", "character"))
import bpy  # noqa: E402

import char_lib as L  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(argv[0])
SHOTS = [(a.split(":")[0], int(a.split(":")[1])) for a in argv[1].split(",")]
KEEP = ("uniform_jacket", "uniform_trousers", "uniform_boots", "uniform_gloves", "Char_Head", "helmet_covered", "eyepro",
        "vest_heavy", "belt_standard", "pack_assault", "carbine", "optic_reddot", "foregrip", "carbine_Mag")


def main():
    os.makedirs(OUT, exist_ok=True)
    arm = bpy.data.objects["InfantryRig"]
    for o in bpy.data.objects:
        if o.type == "MESH":
            base = o.name.rsplit("_LOD", 1)[0]
            o.hide_render = not ((o.name.endswith("_LOD0") or "_LOD" not in o.name) and base in KEEP)
    mag = bpy.data.objects.get("carbine_Mag_LOD0")
    if mag:
        # with ATT_Magazine on ATT_Weapon (identity) the magazine keeps its place relative to the bone it moves to
        arm.animation_data.action = None
        pm = arm.pose.bones["ATT_Magazine"]
        pm.location, pm.rotation_mode, pm.rotation_quaternion = (0, 0, 0), "QUATERNION", (1, 0, 0, 0)
        bpy.context.view_layer.update()
        m = mag.matrix_world.copy()
        mag.parent = arm
        mag.parent_type = "BONE"
        mag.parent_bone = "ATT_Magazine"
        mag.matrix_world = m
    L.setup_render((700, 800))
    sc = bpy.context.scene
    for clip, f in SHOTS:
        arm.animation_data.action = bpy.data.actions[clip]
        sc.frame_set(f)
        for view, target, dist, az, el in (("front", (0, 0, 1.25), 2.2, 0, 4), ("right", (0, 0, 1.25), 2.2, 90, 4),
                                           ("left", (0, 0, 1.25), 2.2, -90, 4), ("face", (0.05, 0.25, 1.5), 0.9, 40, 6),
                                           ("hands_l", (0.0, 0.25, 1.1), 1.1, -40, 12), ("hands_r", (0.0, 0.25, 1.1), 1.1, 50, 12)):
            L.render_view(os.path.join(OUT, "%s_%03d_%s.png" % (clip, f, view)), target, dist, az, el, lens=50)


try:
    main()
except Exception:
    import traceback
    traceback.print_exc()
    sys.stdout.flush()
    os._exit(1)
os._exit(0)
