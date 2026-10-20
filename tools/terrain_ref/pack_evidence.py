"""Packs the visual evidence for the repository: one JPG sheet per asset from the
Blender preview renders (all views + LOD1), and JPG copies of the PNG iteration sheets.
  python pack_evidence.py
"""
import glob
import os
import sys

import OpenImageIO as oiio

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
PREV = os.path.join(REPO, "docs", "terrain01", "blender_previews")
ITER = os.path.join(REPO, "docs", "terrain01", "iterations")


def load_rgb(path, h):
    b = oiio.ImageBuf(path)
    s = b.spec()
    w = int(s.width * h / s.height)
    r = oiio.ImageBufAlgo.resize(b, roi=oiio.ROI(0, w, 0, h, 0, 1, 0, s.nchannels))
    if s.nchannels == 4:
        bg = oiio.ImageBuf(oiio.ImageSpec(w, h, 4, oiio.FLOAT))
        oiio.ImageBufAlgo.fill(bg, (0.6, 0.65, 0.7, 1))
        r = oiio.ImageBufAlgo.over(r, bg)
    return oiio.ImageBufAlgo.channels(r, (0, 1, 2))


def sheet(files, out, h=420):
    bufs = [load_rgb(f, h) for f in files]
    W = sum(b.spec().width for b in bufs) + 4 * (len(bufs) - 1)
    c = oiio.ImageBuf(oiio.ImageSpec(W, h, 3, oiio.UINT8))
    oiio.ImageBufAlgo.fill(c, (0.05, 0.05, 0.05))
    x = 0
    for b in bufs:
        oiio.ImageBufAlgo.paste(c, x, 0, 0, 0, b)
        x += b.spec().width + 4
    c.specmod().attribute("Compression", "jpeg:88")
    c.write(out)


def main():
    assets = sorted({os.path.basename(f).split("_lod")[0] for f in glob.glob(os.path.join(PREV, "*_lod0_v0.png"))})
    for a in assets:
        files = sorted(glob.glob(os.path.join(PREV, a + "_lod0_v*.png"))) + sorted(glob.glob(os.path.join(PREV, a + "_lod1_v*.png")))
        sheet(files, os.path.join(PREV, a + ".jpg"))
        for f in files:
            os.remove(f)
        print("sheet", a, len(files))
    for f in glob.glob(os.path.join(PREV, "sheet_*.png")) + glob.glob(os.path.join(ITER, "*.png")):
        b = oiio.ImageBuf(f)
        b = oiio.ImageBufAlgo.channels(b, (0, 1, 2)) if b.spec().nchannels > 3 else b
        out = f[:-4] + ".jpg"
        b.specmod().attribute("Compression", "jpeg:88")
        b.write(out)
        os.remove(f)
        print("jpg", os.path.basename(out))


if __name__ == "__main__":
    sys.exit(main())
