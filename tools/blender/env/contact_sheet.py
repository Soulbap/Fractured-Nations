"""Joins preview PNGs side by side (height-normalised) into one sheet.
  python contact_sheet.py out.png a.png b.png ... [--h=500]"""
import sys
import OpenImageIO as oiio

args = [a for a in sys.argv[1:] if not a.startswith("--")]
h = 500
for a in sys.argv[1:]:
    if a.startswith("--h="):
        h = int(a[4:])
out, files = args[0], args[1:]
bufs = []
for f in files:
    b = oiio.ImageBuf(f)
    s = b.spec()
    w = int(s.width * h / s.height)
    r = oiio.ImageBufAlgo.resize(b, roi=oiio.ROI(0, w, 0, h, 0, 1, 0, s.nchannels))
    if s.nchannels == 4:
        bg = oiio.ImageBuf(oiio.ImageSpec(w, h, 4, oiio.FLOAT))
        oiio.ImageBufAlgo.fill(bg, (0.6, 0.65, 0.7, 1))
        r = oiio.ImageBufAlgo.over(r, bg)
    bufs.append(oiio.ImageBufAlgo.channels(r, (0, 1, 2)))
W = sum(b.spec().width for b in bufs)
c = oiio.ImageBuf(oiio.ImageSpec(W, h, 3, oiio.UINT8))
x = 0
for b in bufs:
    oiio.ImageBufAlgo.paste(c, x, 0, 0, 0, b)
    x += b.spec().width
c.write(out)
