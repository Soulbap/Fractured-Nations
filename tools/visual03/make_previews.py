"""Assembles the motion preview frames rendered by v03_proto.py (<dir>/_tmp/<clip>_<view>_NNN.png) into
<dir>/<clip>.gif (the views side by side, looping, real time) and an 8-frame contact sheet per view,
<dir>/<clip>_<view>_sheet.jpg.
    python tools/visual03/make_previews.py docs/visual03/proto
"""
import glob
import json
import os
import re
import sys

from PIL import Image

d = sys.argv[1]
meta = json.load(open(os.path.join(d, "proto_motion.json"), encoding="utf-8"))
groups = {}
for p in glob.glob(os.path.join(d, "_tmp", "*.png")):
    m = re.match(r"(.+)_(\w+?)_(\d{3})\.png$", os.path.basename(p))
    if m:
        groups.setdefault((m.group(1), m.group(2)), []).append(p)
for (clip, view), ps in sorted(groups.items()):
    ps.sort()
    period = meta.get(clip, {}).get("period_s", 1.0)
    per_frame_ms = int(round(period / 32 * 1000))
    ims = [Image.open(p).convert("RGB") for p in ps]
    n = 8
    w, h = ims[0].size
    sheet = Image.new("RGB", (w * n, h))
    for i in range(n):
        sheet.paste(ims[int(i * 32 / n)], (i * w, 0))
    sheet.save(os.path.join(d, f"{clip}_{view}_sheet.jpg"), quality=88)
    print(clip, view, len(ims), per_frame_ms, "ms/frame")
# One GIF per clip with the three views side by side, 60 % size, shared 96-colour palette (keeps the repo small).
for clip in sorted({c for c, _ in groups}):
    views = [v for v in ("side", "front", "q34") if (clip, v) in groups]
    seqs = [sorted(groups[(clip, v)]) for v in views]
    period = meta.get(clip, {}).get("period_s", 1.0)
    frames = []
    for i in range(len(seqs[0])):
        row = [Image.open(sq[i]).convert("RGB") for sq in seqs]
        w, h = row[0].size
        img = Image.new("RGB", (w * len(row), h))
        for k, im in enumerate(row):
            img.paste(im, (k * w, 0))
        img = img.resize((int(img.width * 0.6), int(img.height * 0.6)), Image.LANCZOS)
        frames.append(img)
    pal = frames[0].quantize(colors=96, method=Image.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
    q[0].save(os.path.join(d, f"{clip}.gif"), save_all=True, append_images=q[1:], loop=0, optimize=True,
              duration=int(round(period / 32 * 1000)))
    print(clip, "gif", os.path.getsize(os.path.join(d, f"{clip}.gif")) // 1024, "KB")
