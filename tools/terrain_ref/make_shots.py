"""Picks FPS/RTS screenshot stations from the generated world data (deterministic) and
writes tools/terrain_ref/shots_ref03.json for capture.gd.

  python make_shots.py <source_dir> <out_json>
"""
import json
import math
import os
import sys

import numpy as np
import OpenImageIO as oiio


def load(path):
    cfg = oiio.ImageSpec()
    cfg.attribute("oiio:UnassociatedAlpha", 1)
    return oiio.ImageBuf(path, 0, 0, cfg).get_pixels(oiio.FLOAT)


def main():
    src, out = sys.argv[1], sys.argv[2]
    veg = load(os.path.join(src, "vegetation.png"))
    info = load(os.path.join(src, "info.png"))
    R = veg.shape[0]
    pk = 20.0 / R
    h = np.load(os.path.join(src, "macro_height.npy"))
    gy, gx = np.gradient(h, pk * 1000)
    slope = np.degrees(np.arctan(np.hypot(gx, gy)))
    roads = json.load(open(os.path.join(src, "roads.json"), encoding="utf-8"))["roads"]
    sites = json.load(open(os.path.join(src, "sites.json"), encoding="utf-8"))
    rng = np.random.default_rng(7)

    def km(r, c):
        return [round(c * pk, 3), round(20 - r * pk, 3)]

    def pick(mask, n=1, min_sep=80):
        ys, xs = np.nonzero(mask)
        if len(ys) == 0:
            return []
        order = rng.permutation(len(ys))
        res = []
        for i in order:
            p = (ys[i], xs[i])
            if all(abs(p[0] - q[0]) + abs(p[1] - q[1]) > min_sep for q in res):
                res.append(p)
            if len(res) >= n:
                break
        return res

    inner = np.zeros(veg.shape[:2], dtype=bool)
    inner[100:-100, 100:-100] = True
    forest, pine, birch, wet = veg[..., 0], veg[..., 1], veg[..., 2], veg[..., 3]
    rock, field, settle, water = info[..., 0], info[..., 1], info[..., 2], info[..., 3]
    shots = []

    def add(name, ref, height, yaw=None, look=None, pitch=-4.0, fov=70.0):
        s = {"name": name, "ref_km": ref, "height": height, "fov": fov}
        if look is not None:
            s["look_km"] = look
            s["look_up"] = 2.0 if height < 5 else 0.0
        else:
            s["yaw_deg"] = yaw
            s["pitch_deg"] = pitch
        shots.append(s)

    cats = [
        ("fps_pine_forest", (forest > 0.85) & (pine > 0.6) & (slope < 10) & inner),
        ("fps_spruce_forest", (forest > 0.85) & (pine < 0.25) & (birch < 0.25) & (slope < 10) & inner),
        ("fps_birch_wetland", (forest > 0.4) & (birch > 0.45) & (slope < 6) & inner),
        ("fps_forest_edge_meadow", (forest > 0.2) & (forest < 0.45) & (slope < 6) & (field < 0.5) & inner),
        ("fps_rocky_hill", (rock > 0.6) & (slope > 8) & (slope < 22) & (h < 700) & inner),
    ]
    for name, m in cats:
        for (r, c) in pick(m, 1):
            add(name, km(r, c), 1.7, yaw=float(rng.uniform(0, 360)))
    # Field edge looking over a village.
    for st in sites["settlements"]:
        if st["name"] in ("Østby", "Moen"):
            x = (st["pos"][0] + 10000) / 1000
            y = (10000 - st["pos"][2]) / 1000
            add("fps_village_" + st["name"].lower().replace("ø", "o"), [x + 0.35, y - 0.25], 1.7, look=[x, y])
    # Bridge over the river (first river bridge of a paved road), from the bank.
    for rd in roads:
        if rd["mesh"] and rd["bridges"]:
            a, b = rd["bridges"][0]
            p = rd["points"][(a + b) // 2]
            x = (p[0] + 10000) / 1000
            y = (10000 - p[2]) / 1000
            add("fps_river_bridge", [x + 0.07, y + 0.05], 2.5, look=[x, y])
            add("rts_150m_bridge", [x + 0.12, y - 0.1], 150, look=[x, y])
            break
    # Lake shore (Storvatnet) and the massif pass.
    add("fps_lake_shore", [4.45, 2.55], 1.7, look=[3.2, 2.5])
    add("fps_massif_pass", [18.6, 16.1], 1.8, look=[17.3, 17.6])
    add("rts_150m_town", [9.6, 11.2], 150, look=[9.1, 11.8])
    add("rts_150m_forest_road", [5.2, 13.6], 150, look=[4.6, 13.2])
    add("rts_600m_center", [11.0, 9.6], 600, look=[9.6, 11.6])
    add("rts_600m_massif", [15.0, 14.0], 600, look=[17.5, 17.5])
    add("rts_600m_lakes", [6.5, 5.0], 600, look=[3.2, 3.0])
    add("rts_1500m_overview", [12.0, 4.0], 1500, look=[10.0, 11.0])
    with open(out, "w", encoding="utf-8") as fp:
        json.dump(shots, fp, indent=1, ensure_ascii=False)
    print("\n".join("%s %s" % (s["name"], s["ref_km"]) for s in shots))


if __name__ == "__main__":
    main()
