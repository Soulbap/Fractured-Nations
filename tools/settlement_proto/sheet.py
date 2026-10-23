"""WORLD-SETTLEMENT-02 review sheet: one map tile per settlement (texture, hillshade, 5 m contours, 100 m grid,
world roads red/yellow/magenta, removed streets cyan, new roads white, buildings: house pink, barn red, shed yellow).
Run with Blender's Python:  sheet.py out_prefix [name,name,...]"""
import json
import sys

import numpy as np
import OpenImageIO as oiio

SRC = "worlds/ref_20km/source/"
N, SP, HALF = 10240, 1.953125, 10000.0
H = np.memmap(SRC + "height.r32", dtype=np.float32, mode="r", shape=(N, N))
C = np.memmap(SRC + "control.r32", dtype=np.uint32, mode="r", shape=(N, N))
L = json.load(open("worlds/settlements/ref_20km.json", encoding="utf-8"))
W = json.load(open(SRC + "roads.json", encoding="utf-8"))
PAL = {0: (125, 160, 80), 1: (130, 130, 130), 2: (150, 120, 80), 3: (190, 175, 100), 4: (40, 75, 35),
       5: (160, 150, 135), 6: (90, 100, 60), 7: (30, 30, 35)}
TILE = 600


def tile(cx, cz, R):
    i0, j0 = int((cx - R + HALF) / SP), int((cz - R + HALF) / SP)
    n = int(2 * R / SP)
    h = np.array(H[j0:j0 + n, i0:i0 + n], dtype=np.float64)
    c = np.array(C[j0:j0 + n, i0:i0 + n])
    gz, gx = np.gradient(h, SP)
    img = np.zeros(h.shape + (3,))
    for k, col in PAL.items():
        img[(c >> 27) == k] = col
    img *= np.clip(0.75 + (gx - gz) * 1.5, 0.3, 1.1)[..., None]
    cont = np.floor(h / 5)
    img[(cont != np.roll(cont, 1, 0)) | (cont != np.roll(cont, 1, 1))] *= 0.6
    # resample to TILE px
    idx = (np.arange(TILE) * n / TILE).astype(int)
    img = img[idx][:, idx]
    s = TILE / (2 * R)
    X0, Z0 = cx - R, cz - R
    for k in range(TILE):
        if abs(((X0 + k / s) / 100) % 1) < 0.5 / s / 100 * 2:
            img[:, k] = img[:, k] * 0.6 + 50
        if abs(((Z0 + k / s) / 100) % 1) < 0.5 / s / 100 * 2:
            img[k, :] = img[k, :] * 0.6 + 50

    def line(pts, col, w):
        for a, b in zip(pts[:-1], pts[1:]):
            m = max(1, int(np.hypot(b[0] - a[0], b[1] - a[1]) * s))
            for t in np.linspace(0, 1, m + 1):
                x = int((a[0] + (b[0] - a[0]) * t - X0) * s)
                z = int((a[1] + (b[1] - a[1]) * t - Z0) * s)
                if w <= x < TILE - w and w <= z < TILE - w:
                    img[z - w:z + w + 1, x - w:x + w + 1] = col
    rm = set(L["remove_roads"])
    for r in W["roads"]:
        col = (0, 200, 255) if r["name"] in rm else {"primary": (255, 40, 40), "secondary": (255, 210, 0)}.get(r["class"], (230, 0, 230))
        line([(p[0], p[2]) for p in r["points"]], col, 0 if r["name"] in rm else 1)
    for r in L["roads"]:
        line([(p[0], p[2]) for p in r["points"]], (255, 255, 255), 1)
    for b in L["buildings"]:
        rr = {16: 9, 17: 13, 18: 4.5}[b["mesh"]] * 0.7
        line([(b["x"] - rr, b["z"]), (b["x"] + rr, b["z"])], {16: (255, 120, 200), 17: (220, 50, 30), 18: (240, 240, 0)}[b["mesh"]], 2)
    return np.clip(img, 0, 255).astype(np.uint8)


def main():
    out = sys.argv[1]
    only = sys.argv[2].split(",") if len(sys.argv) > 2 else None
    sites = [s for s in L["sites"] if only is None or s["name"] in only]
    cols = 4
    for page in range(0, len(sites), 12):
        part = sites[page:page + 12]
        rows = (len(part) + cols - 1) // cols
        sheet = np.zeros((rows * TILE, cols * TILE, 3), np.uint8)
        for k, s in enumerate(part):
            R = max(380.0, s["radius_m"] * 2.4)
            sheet[(k // cols) * TILE:(k // cols + 1) * TILE, (k % cols) * TILE:(k % cols + 1) * TILE] = tile(s["center"][0], s["center"][1], R)
            print(page // 12, k, s["name"], s["type"], "R=%d" % R)
        o = oiio.ImageOutput.create(out + "_%d.png" % (page // 12))
        o.open(out + "_%d.png" % (page // 12), oiio.ImageSpec(cols * TILE, rows * TILE, 3, oiio.UINT8))
        o.write_image(np.ascontiguousarray(sheet))
        o.close()


if __name__ == "__main__":
    main()
