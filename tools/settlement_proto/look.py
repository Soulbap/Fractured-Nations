"""WORLD-SETTLEMENT-01 analysis preview: terrain texture, hillshade, 5 m contours, 100 m grid,
world roads (red primary, yellow secondary, cyan street) and an optional prototype patch (white).
Run with Blender's Python (numpy + OpenImageIO): look.py cx cz radius out.png [patch.json]"""
import json, sys
import numpy as np
import OpenImageIO as oiio

SRC = "worlds/ref_20km/source/"
N, SP, HALF = 10240, 1.953125, 10000.0
cx, cz, R = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3])
out = sys.argv[4]
H = np.memmap(SRC + "height.r32", dtype=np.float32, mode="r", shape=(N, N))
C = np.memmap(SRC + "control.r32", dtype=np.uint32, mode="r", shape=(N, N))
i0 = int((cx - R + HALF) / SP)
j0 = int((cz - R + HALF) / SP)
n = int(2 * R / SP)
h = np.array(H[j0:j0 + n, i0:i0 + n], dtype=np.float64)
c = np.array(C[j0:j0 + n, i0:i0 + n])
gz, gx = np.gradient(h, SP)
shade = np.clip(0.75 + (gx - gz) * 1.5, 0.3, 1.1)
base = c >> 27
pal = {0: (125, 160, 80), 1: (130, 130, 130), 2: (150, 120, 80), 3: (190, 175, 100), 4: (40, 75, 35),
       5: (160, 150, 135), 6: (90, 100, 60), 7: (30, 30, 35)}
img = np.zeros(h.shape + (3,), np.float64)
for k, col in pal.items():
    img[base == k] = col
img *= shade[..., None]
cont = np.floor(h / 5)
edge = (cont != np.roll(cont, 1, 0)) | (cont != np.roll(cont, 1, 1))
img[edge] *= 0.55
X0, Z0 = i0 * SP - HALF, j0 * SP - HALF
for k in range(n):
    x = X0 + k * SP
    if abs(x / 100 - round(x / 100)) * 100 < SP / 2:
        img[:, k] = img[:, k] * 0.5 + 60
        img[k, :] = img[k, :] * 0.5 + 60
def line(pts, col, w=1):
    for a, b in zip(pts[:-1], pts[1:]):
        L = max(1, int(np.hypot(b[0] - a[0], b[1] - a[1]) / (SP * 0.5)))
        for t in np.linspace(0, 1, L + 1):
            x = (a[0] + (b[0] - a[0]) * t - X0) / SP
            z = (a[1] + (b[1] - a[1]) * t - Z0) / SP
            xi, zi = int(x), int(z)
            if w <= xi < n - w and w <= zi < n - w:
                img[zi - w:zi + w + 1, xi - w:xi + w + 1] = col
roads = json.load(open(SRC + "roads.json", encoding="utf-8"))
for r in roads["roads"]:
    col = {"primary": (255, 40, 40), "secondary": (255, 210, 0), "street": (0, 220, 255)}.get(r["class"], (255, 0, 255))
    line([(p[0], p[2]) for p in r["points"]], col, 1)
if len(sys.argv) > 5:
    P = json.load(open(sys.argv[5], encoding="utf-8"))
    for r in P.get("roads", []):
        line([(p[0], p[2]) for p in r["points"]], (255, 255, 255), 1)
    for b in P.get("buildings", []):
        line([(b["x"] - 4, b["z"]), (b["x"] + 4, b["z"])], {16: (255, 120, 200), 17: (200, 60, 30), 18: (240, 240, 0)}[b["mesh"]], 3)
arr = np.clip(img, 0, 255).astype(np.uint8)
up = int(sys.argv[6]) if len(sys.argv) > 6 else 2
arr = np.ascontiguousarray(arr.repeat(up, 0).repeat(up, 1))
spec = oiio.ImageSpec(n * up, n * up, 3, oiio.UINT8)
o = oiio.ImageOutput.create(out)
o.open(out, spec)
o.write_image(arr)
o.close()
print("origin", X0, Z0, "px", SP, "size", n, "h", h.min(), h.max())
