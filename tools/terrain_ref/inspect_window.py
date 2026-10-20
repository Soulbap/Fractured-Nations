"""Hillshade + control preview of a window of the generated full-resolution maps.

  python inspect_window.py <source_dir> <x_km> <y_km> <size_km> <out.png>
"""
import os
import sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate import write_png, to_u8  # noqa: E402

PAL = np.array([[0.45, 0.58, 0.28], [0.55, 0.54, 0.52], [0.45, 0.36, 0.25], [0.78, 0.70, 0.40],
                [0.22, 0.26, 0.15], [0.62, 0.60, 0.55], [0.48, 0.45, 0.28]])


def main():
    src, xk, yk, sk, out = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), sys.argv[5]
    N = 10240
    sp = 20000.0 / N
    h = np.memmap(os.path.join(src, "height.r32"), dtype="<f4", mode="r", shape=(N, N))
    c = np.memmap(os.path.join(src, "control.r32"), dtype="<u4", mode="r", shape=(N, N))
    c0 = int((xk - sk / 2) * 1000 / sp)
    r0 = int((20 - yk - sk / 2) * 1000 / sp)
    n = int(sk * 1000 / sp)
    hw = np.array(h[r0:r0 + n, c0:c0 + n])
    cw = np.array(c[r0:r0 + n, c0:c0 + n])
    gy, gx = np.gradient(hw, sp)
    shade = np.clip((0.55 * gx - 0.55 * gy + 0.63) / np.sqrt(gx * gx + gy * gy + 1), 0, 1)
    base = (cw >> 27) & 31
    over = (cw >> 22) & 31
    bl = ((cw >> 14) & 255) / 255.0
    col = PAL[np.clip(base, 0, 6)] * (1 - bl[..., None]) + PAL[np.clip(over, 0, 6)] * bl[..., None]
    img = col * (0.3 + 0.9 * shade[..., None])
    write_png(out, to_u8(np.clip(img, 0, 1)))
    print("height %.1f..%.1f" % (hw.min(), hw.max()))


if __name__ == "__main__":
    main()
