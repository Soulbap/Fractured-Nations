"""Assembles the in-game frame sequences of the VISUAL-03 Godot test (<dir>/rec/<tag>_NNN.png) into GIFs
(<dir>/gif/<tag>.gif, 640 px wide, 64-colour palette) and deletes the frames afterwards with --clean.
    python tools/visual03/make_godot_gifs.py docs/visual03/godot [--clean]
"""
import glob
import os
import re
import shutil
import sys

from PIL import Image

d = sys.argv[1]
groups = {}
for p in glob.glob(os.path.join(d, "rec", "*.png")):
    m = re.match(r"(.+)_(\d{3})\.png$", os.path.basename(p))
    if m:
        groups.setdefault(m.group(1), []).append(p)
os.makedirs(os.path.join(d, "gif"), exist_ok=True)
# e_6_fire_0..3 belong together
merged = {}
for tag, ps in groups.items():
    key = re.sub(r"_fire_\d$", "_fire", tag)
    merged.setdefault(key, []).extend(sorted(ps))
for tag, ps in sorted(merged.items()):
    frames = []
    for p in ps:
        im = Image.open(p).convert("RGB")
        frames.append(im.resize((im.width * 2 // 3, im.height * 2 // 3), Image.LANCZOS))
    pal = frames[len(frames) // 2].quantize(colors=64, method=Image.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
    out = os.path.join(d, "gif", tag + ".gif")
    q[0].save(out, save_all=True, append_images=q[1:], loop=0, optimize=True, duration=66)
    print(tag, len(frames), os.path.getsize(out) // 1024, "KB")
if "--clean" in sys.argv:
    shutil.rmtree(os.path.join(d, "rec"))
