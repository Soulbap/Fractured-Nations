"""Encodes the in-game frame sequences of the VISUAL-03 Godot test (<dir>/rec/<tag>_NNN.png) into H.264 MP4s
(<dir>/video/<tag>.mp4, 15 fps) with Blender's bundled FFmpeg (no separate FFmpeg install needed).
    blender -b --factory-startup --python tools/visual03/encode_mp4.py -- docs/visual03/godot [--clean]
"""
import glob
import os
import re
import shutil
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
d = os.path.abspath(argv[0])
groups = {}
for p in glob.glob(os.path.join(d, "rec", "*.png")):
    m = re.match(r"(.+)_(\d{3})\.png$", os.path.basename(p))
    if m:
        key = re.sub(r"_fire_\d$", "_fire", m.group(1))
        groups.setdefault(key, []).append(p)
os.makedirs(os.path.join(d, "video"), exist_ok=True)
for tag, ps in sorted(groups.items()):
    ps.sort()
    sc = bpy.data.scenes.new("enc_" + tag)
    sc.sequence_editor_create()
    first = ps[0]
    strip = sc.sequence_editor.strips.new_image("seq", first, 1, 1) if hasattr(sc.sequence_editor, "strips") else \
        sc.sequence_editor.sequences.new_image("seq", first, 1, 1)
    for p in ps[1:]:
        strip.elements.append(os.path.basename(p))
    w, h = bpy.data.images.load(first).size
    sc.render.resolution_x, sc.render.resolution_y = w - w % 2, h - h % 2
    sc.render.resolution_percentage = 100
    sc.render.fps = 15
    sc.frame_start, sc.frame_end = 1, len(ps)
    if hasattr(sc.render.image_settings, "media_type"):      # Blender 5: video output is its own media type
        sc.render.image_settings.media_type = "VIDEO"
    sc.render.image_settings.file_format = "FFMPEG"
    sc.render.ffmpeg.format = "MPEG4"
    sc.render.ffmpeg.codec = "H264"
    sc.render.ffmpeg.constant_rate_factor = "LOW"
    sc.render.filepath = os.path.join(d, "video", tag + ".mp4")
    bpy.ops.render.render(animation=True, scene=sc.name)
    print("MP4", tag, len(ps), os.path.getsize(sc.render.filepath) // 1024, "KB")
if "--clean" in argv:
    shutil.rmtree(os.path.join(d, "rec"))
os._exit(0)
