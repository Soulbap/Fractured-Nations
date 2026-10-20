"""Grid contact sheet: python grid_sheet.py out.jpg cols cell_w a.jpg b.jpg ..."""
import sys
import OpenImageIO as oiio

out, cols, cw = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
files = sys.argv[4:]
bufs = []
for f in files:
    b = oiio.ImageBuf(f)
    s = b.spec()
    ch = int(s.height * cw / s.width)
    bufs.append(oiio.ImageBufAlgo.channels(oiio.ImageBufAlgo.resize(b, roi=oiio.ROI(0, cw, 0, ch, 0, 1, 0, s.nchannels)), (0, 1, 2)))
chh = max(b.spec().height for b in bufs)
rows = (len(bufs) + cols - 1) // cols
c = oiio.ImageBuf(oiio.ImageSpec(cols * cw + (cols - 1) * 6, rows * chh + (rows - 1) * 6, 3, oiio.UINT8))
oiio.ImageBufAlgo.fill(c, (0.05, 0.05, 0.05))
for i, b in enumerate(bufs):
    oiio.ImageBufAlgo.paste(c, (i % cols) * (cw + 6), (i // cols) * (chh + 6), 0, 0, b)
c.write(out)
