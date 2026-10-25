"""Writes stills from MP4 previews (for looking at them as images): <out>/<clip>_<k>.png at 4 evenly spaced frames,
rendered through Blender's sequencer.
    blender -b --factory-startup --python tools/visual03/mp4_frames.py -- IN_DIR OUT_DIR [clip,clip]
"""
import os
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = os.path.abspath(argv[0]), os.path.abspath(argv[1])
only = argv[2].split(",") if len(argv) > 2 else None
os.makedirs(out, exist_ok=True)
for f in sorted(os.listdir(src)):
    if not f.endswith(".mp4") or (only and f[:-4] not in only):
        continue
    sc = bpy.data.scenes.new("x_" + f)
    sc.sequence_editor_create()
    seq = sc.sequence_editor.strips if hasattr(sc.sequence_editor, "strips") else sc.sequence_editor.sequences
    st = seq.new_movie("m", os.path.join(src, f), 1, 1)
    n = st.frame_final_duration
    sc.render.resolution_x, sc.render.resolution_y = st.elements[0].orig_width, st.elements[0].orig_height
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    for k, fr in enumerate((1, n // 4, n // 2, 3 * n // 4)):
        sc.frame_set(max(1, fr))
        sc.render.filepath = os.path.join(out, "%s_%d.png" % (f[:-4], k))
        bpy.ops.render.render(write_still=True, scene=sc.name)
    bpy.data.scenes.remove(sc)
os._exit(0)
