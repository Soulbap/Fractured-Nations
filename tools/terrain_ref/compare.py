"""Side-by-side comparison of the reference map frame and a generated/captured top-down image.

  python compare.py <reference.png> <generated.png> <out.png> [size]
The reference frame (0..20 km) is cropped from the reference picture using the tick
positions measured on it (x 47..912 px, y 980..92 px for 0..20 km).
"""
import sys
import OpenImageIO as oiio

REF_FRAME = (47, 92, 912, 980)  # x0, y0 (20 km north), x1 (20 km east), y1 (0 km)


def main():
    ref, gen, out = sys.argv[1:4]
    size = int(sys.argv[4]) if len(sys.argv) > 4 else 900
    rb = oiio.ImageBuf(ref)
    x0, y0, x1, y1 = REF_FRAME
    rc = oiio.ImageBufAlgo.cut(rb, oiio.ROI(x0, x1, y0, y1))
    rr = oiio.ImageBufAlgo.resize(rc, roi=oiio.ROI(0, size, 0, size, 0, 1, 0, 3))
    gb = oiio.ImageBuf(gen)
    gs = gb.spec()
    gc = oiio.ImageBufAlgo.channels(gb, (0, 1, 2)) if gs.nchannels > 3 else gb
    gr = oiio.ImageBufAlgo.resize(gc, roi=oiio.ROI(0, size, 0, size, 0, 1, 0, 3))
    canvas = oiio.ImageBuf(oiio.ImageSpec(size * 2 + 12, size, 3, oiio.UINT8))
    oiio.ImageBufAlgo.fill(canvas, (0.05, 0.07, 0.1))
    oiio.ImageBufAlgo.paste(canvas, 0, 0, 0, 0, rr)
    oiio.ImageBufAlgo.paste(canvas, size + 12, 0, 0, 0, gr)
    # 2 km grid lines on both halves.
    for k in range(1, 10):
        p = int(k * size / 10)
        for xo in (0, size + 12):
            oiio.ImageBufAlgo.fill(canvas, (1, 1, 1), oiio.ROI(xo + p, xo + p + 1, 0, size))
            oiio.ImageBufAlgo.fill(canvas, (1, 1, 1), oiio.ROI(xo, xo + size, p, p + 1))
    canvas.write(out)


if __name__ == "__main__":
    main()
