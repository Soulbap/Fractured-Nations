"""VISUAL-03 Blender previews of the dressed soldier with the rifle: every clip rendered with the character travelling at
the clip's speed over a 1 m checker floor (camera follows; planted feet must stand still on the checker), side and
three-quarter views side by side, encoded to MP4 with Blender's FFmpeg.
    blender -b assets/characters/infantry/blender/infantry.blend --python tools/visual03/blender_previews.py -- OUT_DIR [--only Walk_F,...]
"""
import json
import math
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "blender", "character"))
import bpy  # noqa: E402

import char_lib as L  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(argv[0])
ONLY = argv[argv.index("--only") + 1].split(",") if "--only" in argv else None
META = json.load(open(os.path.join(HERE, "..", "..", "assets", "characters", "infantry", "animation_meta.json"), encoding="utf-8"))
CLIPS = ["Idle", "Ready_Idle", "Walk_F", "Brisk_F", "Jog_F", "Run_F", "Sprint_F", "Walk_B", "Walk_L", "CrouchWalk_F",
         "Crouch_Idle", "Turn_L", "Aim", "Fire", "Reload"]
KEEP = ("uniform_jacket", "uniform_trousers", "uniform_boots", "uniform_gloves", "Char_Head", "helmet_covered", "eyepro",
        "vest_standard", "belt_standard", "pack_assault", "carbine", "optic_reddot", "foregrip", "carbine_Mag")
TMP = os.path.join(OUT, "_frames")


def show():
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        base = o.name.rsplit("_LOD", 1)[0]
        vis = (o.name.endswith("_LOD0") and base in KEEP) or o.name == "Char_Head_LOD0"
        o.hide_render = not vis


def checker():
    import bmesh
    g = bpy.data.objects.get("PreviewGround")
    if g:
        bpy.data.objects.remove(g, do_unlink=True)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=40)
    me = bpy.data.meshes.new("GridGround")
    bm.to_mesh(me)
    ob = bpy.data.objects.new("PreviewGround", me)
    bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.new("GridMat")
    mat.use_nodes = True
    nt = mat.node_tree
    chk = nt.nodes.new("ShaderNodeTexChecker")
    chk.inputs["Scale"].default_value = 40.0
    chk.inputs["Color1"].default_value = (0.20, 0.19, 0.17, 1)
    chk.inputs["Color2"].default_value = (0.32, 0.30, 0.27, 1)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(tc.outputs["Generated"], chk.inputs["Vector"])
    nt.links.new(chk.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    me.materials.append(mat)


def encode(tag, frames, fps):
    sc = bpy.data.scenes.new("enc_" + tag)
    sc.sequence_editor_create()
    seq = sc.sequence_editor.strips if hasattr(sc.sequence_editor, "strips") else sc.sequence_editor.sequences
    st = seq.new_image("seq", frames[0], 1, 1)
    for p in frames[1:]:
        st.elements.append(os.path.basename(p))
    sc.render.resolution_x, sc.render.resolution_y = 840, 620
    sc.render.resolution_percentage = 100
    sc.render.fps = fps
    sc.frame_start, sc.frame_end = 1, len(frames)
    if hasattr(sc.render.image_settings, "media_type"):
        sc.render.image_settings.media_type = "VIDEO"
    sc.render.image_settings.file_format = "FFMPEG"
    sc.render.ffmpeg.format = "MPEG4"
    sc.render.ffmpeg.codec = "H264"
    sc.render.ffmpeg.constant_rate_factor = "MEDIUM"
    sc.render.filepath = os.path.join(OUT, tag + ".mp4")
    bpy.ops.render.render(animation=True, scene=sc.name)
    bpy.data.scenes.remove(sc)


def main():
    os.makedirs(TMP, exist_ok=True)
    arm = bpy.data.objects["InfantryRig"]
    show()
    # the detachable magazine rides on ATT_Magazine, as in the game
    mag = bpy.data.objects.get("carbine_Mag_LOD0")
    if mag:
        # with ATT_Magazine on ATT_Weapon (identity) the magazine keeps its place relative to the bone it moves to
        if arm.animation_data:
            arm.animation_data.action = None
        pm = arm.pose.bones["ATT_Magazine"]
        pm.location, pm.rotation_mode, pm.rotation_quaternion = (0, 0, 0), "QUATERNION", (1, 0, 0, 0)
        bpy.context.view_layer.update()
        m = mag.matrix_world.copy()
        mag.parent, mag.parent_type, mag.parent_bone = arm, "BONE", "ATT_Magazine"
        mag.matrix_world = m
    L.setup_render((420, 620))
    checker()
    sc = bpy.context.scene
    sc.render.image_settings.file_format = "PNG"
    gait = META.get("clip_meta", {})
    for clip in CLIPS:
        if ONLY and clip not in ONLY:
            continue
        act = bpy.data.actions.get(clip)
        if act is None:
            continue
        arm.animation_data.action = act
        frames = int(act.frame_range[1] - act.frame_range[0])
        m = gait.get(clip, {})
        speed = float(m.get("speed", 0.0)) if clip not in ("Turn_L", "Turn_R") else 0.0
        if clip == "Sprint_F":
            speed = float(gait.get("Run_F", {}).get("speed", 4.4))
        d = m.get("dir", [0, 1])
        period = float(m.get("period", frames / 30.0))
        if clip in ("Idle", "Ready_Idle", "Aim", "Crouch_Idle"):
            frames = min(frames, 90)
        cycles = 2 if frames <= 40 else 1
        dt = period / max(1, int(act.frame_range[1] - act.frame_range[0])) if speed > 0 else 1.0 / 30.0
        out = []
        for i in range(frames * cycles):
            sc.frame_set(i % frames)
            x, y = d[0] * speed * dt * i, d[1] * speed * dt * i
            arm.location = (x, y, 0)
            bpy.context.view_layer.update()
            row = []
            for v, az in (("side", 90), ("q34", 35)):
                p = os.path.join(TMP, "%s_%s_%03d.png" % (clip, v, i))
                L.render_view(p, (x, y, 0.95), 3.3, az, 6, lens=45)
                row.append(p)
            # side and three-quarter next to each other
            a = bpy.data.images.load(row[0])
            b = bpy.data.images.load(row[1])
            import numpy as np
            pa = np.array(a.pixels[:]).reshape(a.size[1], a.size[0], 4)
            pb = np.array(b.pixels[:]).reshape(b.size[1], b.size[0], 4)
            img = bpy.data.images.new("pair", a.size[0] * 2, a.size[1])
            img.pixels.foreach_set(np.concatenate([pa, pb], axis=1).astype(np.float32).ravel())
            fp = os.path.join(TMP, "%s_pair_%03d.png" % (clip, i))
            img.filepath_raw = fp
            img.file_format = "PNG"
            img.save()
            for im in (a, b, img):
                bpy.data.images.remove(im)
            out.append(fp)
        arm.location = (0, 0, 0)
        fps = round(frames / period) if speed > 0 and period > 0 else 30
        encode(clip, out, max(10, min(60, fps)))
        print("PREVIEW", clip, len(out), "fps", fps)
    shutil.rmtree(TMP)


try:
    main()
except Exception:
    import traceback
    traceback.print_exc()
    sys.stdout.flush()
    os._exit(1)
os._exit(0)
