"""WORLD-SETTLEMENT-01: hand-made prototype of Haugen (village around the Fv nord-sentrum /
Lv haugen junction, world x -1600, z -4400).

Not a generator: the local roads are a few control points laid along the terrain (5 m contours of
tools/settlement_proto/look.py), the buildings are placed along those roads by hand (road,
distance along it, side, setback) or as farm yards. This script only turns that into world data:
splined road centre lines on the terrain, building positions, heights and yaw, plus checks
(grade, slope under the buildings, overlaps, distance to the roads).

Run with Blender's Python (numpy):  design_haugen.py  ->  worlds/settlement_proto/haugen.json
"""
import json
import math
import sys

import numpy as np

SRC = "worlds/ref_20km/source/"
OUT = "worlds/settlement_proto/haugen.json"
N, SP, HALF = 10240, 1.953125, 10000.0
H = np.memmap(SRC + "height.r32", dtype=np.float32, mode="r", shape=(N, N))

HOUSE, BARN, SHED = 16, 17, 18
RADIUS = {HOUSE: 9.0, BARN: 13.0, SHED: 4.5}
# House colours (white, ochre, Falu red, pale blue) - index into the builder's tints.
TINTS = [[1, 1, 1], [1.0, 0.86, 0.52], [0.95, 0.45, 0.36], [0.82, 0.86, 0.9], [0.93, 0.93, 0.88]]


def height(x, z):
    fx, fz = (x + HALF) / SP, (z + HALF) / SP
    i, j = int(fx), int(fz)
    tx, tz = fx - i, fz - j
    a = H[j, i] * (1 - tx) + H[j, i + 1] * tx
    b = H[j + 1, i] * (1 - tx) + H[j + 1, i + 1] * tx
    return float(a * (1 - tz) + b * tz)


def catmull(ctrl, step=4.0):
    P = [np.array(p, dtype=np.float64) for p in ctrl]
    P = [P[0] * 2 - P[1]] + P + [P[-1] * 2 - P[-2]]
    out = []
    for k in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[k - 1], P[k], P[k + 1], P[k + 2]
        n = max(2, int(np.linalg.norm(p2 - p1) / step))
        for s in range(n):
            t = s / n
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-2])
    return np.array(out)


# --- Local roads ---------------------------------------------------------------------------------
# The Fv vertex each road leaves from is taken from roads.json (first control point snaps to it).
# class: "local" = narrow asphalt village road, "track" = gravel farm road. No through grid: every
# road ends at a yard or a turning place, only Haugvegen has a short loop back to the Fv.
ROADS = [
    # Village road: leaves the Fv's west arm where both lie at ground level (east of the junction the
    # Fv runs on a fill), climbs gently along the west side of the bowl and ends at the upper houses.
    {"name": "Haugvegen", "class": "local", "lane_m": 4.6, "lanes": 1, "shoulder_m": 0.5, "paint": "asphalt",
     "snap": "Fv nord-sentrum", "ctrl": [(-1659, -4302), (-1664, -4340), (-1664, -4385), (-1656, -4430),
                                         (-1650, -4470), (-1656, -4510), (-1670, -4548), (-1682, -4578)]},
    # Dead-end branch down into the middle of the bowl (a few houses, turning place at the end).
    {"name": "Bakkeli", "class": "local", "lane_m": 4.0, "lanes": 1, "shoulder_m": 0.4, "paint": "asphalt",
     "snap": "Haugvegen", "ctrl": [(-1656, -4430), (-1626, -4442), (-1598, -4458), (-1574, -4478)]},
    # Forest track from the end of Haugvegen to Nordre Haugen (the farm on the north fields).
    {"name": "Nordre Haugen gardsveg", "class": "track", "lane_m": 3.4, "lanes": 1, "shoulder_m": 0.5, "paint": "gravel",
     "snap": "Haugvegen", "ctrl": [(-1682, -4578), (-1694, -4620), (-1700, -4665), (-1704, -4712),
                                   (-1716, -4760), (-1732, -4796)]},
    # Farm road east over the fields to Austre Haugen and on to Haugen ovre.
    {"name": "Austre Haugen gardsveg", "class": "track", "lane_m": 3.4, "lanes": 1, "shoulder_m": 0.5, "paint": "gravel",
     "snap": "Fv nord-sentrum", "ctrl": [(-1468, -4243), (-1430, -4280), (-1402, -4330), (-1386, -4384),
                                         (-1382, -4440), (-1370, -4500), (-1352, -4552)]},
    # Short farm road west off Haugvegen to Vestre Haugen under the wooded ridge.
    {"name": "Vestre Haugen gardsveg", "class": "track", "lane_m": 3.4, "lanes": 1, "shoulder_m": 0.5, "paint": "gravel",
     "snap": "Haugvegen", "ctrl": [(-1664, -4385), (-1700, -4396), (-1736, -4404)]},
    # Yard road off Lv haugen to the sawmill / workshop south of the junction.
    {"name": "Sagvegen", "class": "track", "lane_m": 3.6, "lanes": 1, "shoulder_m": 0.6, "paint": "gravel",
     "snap": "Lv haugen", "ctrl": [(-1644, -4266), (-1616, -4248), (-1588, -4240)]},
]

# --- Buildings -----------------------------------------------------------------------------------
# Along a road: mesh, road, metres along, side (+1 left/-1 right of travel), setback (m from the
# centre line), extra yaw (deg), tint. In a yard: mesh, x, z, extra yaw (deg; None = long side to
# the nearest road), tint.
B = []
def along(mesh, road, s, side, setback, yaw=0.0, tint=0):
    B.append({"mesh": mesh, "road": road, "s": s, "side": side, "setback": setback, "yaw": yaw, "tint": tint})
def at(mesh, x, z, yaw=None, tint=0, extra=0.0):
    B.append({"mesh": mesh, "x": x, "z": z, "yaw_deg": yaw, "extra": extra, "tint": tint})

# Centre at the junction and the mouth of Haugvegen: shop (barn body), a few houses, a shed.
at(BARN, -1622, -4402, None, 4)          # landhandel
at(HOUSE, -1698, -4334, None, 2)
at(HOUSE, -1700, -4366, None, 0, 6)
at(SHED, -1690, -4300, None, 0, 90)
at(HOUSE, -1556, -4296, None, 1)
at(HOUSE, -1526, -4280, None, 0, -8)
# Haugvegen: a loose row up the bowl, then the cluster at its end.
along(HOUSE, "Haugvegen", 150, 1, 18, 4, 3)
along(HOUSE, "Haugvegen", 196, -1, 17, -6, 0)
along(HOUSE, "Haugvegen", 232, 1, 16, 3, 1)
along(HOUSE, "Haugvegen", 262, -1, 18, 80, 0)
along(HOUSE, "Haugvegen", 286, 1, 17, -10, 2)
along(SHED, "Haugvegen", 248, -1, 30, 30, 0)
# Bakkeli: three houses down the slope, the last one at the turning place.
along(HOUSE, "Bakkeli", 34, 1, 15, 0, 4)
along(HOUSE, "Bakkeli", 62, -1, 16, 10, 0)
along(HOUSE, "Bakkeli", 96, 1, 18, -14, 3)
# Lv haugen south: two roadside houses; the sawmill yard (two big sheds and a small one).
along(HOUSE, "Lv haugen", 150, 1, 18, 0, 0)
along(HOUSE, "Lv haugen", 205, -1, 19, 8, 2)
along(BARN, "Sagvegen", 44, 1, 22, 0, 4)
along(BARN, "Sagvegen", 50, -1, 24, 90, 4)
along(SHED, "Sagvegen", 22, -1, 16, 0, 0)
# Fv south-east: scattered houses where the road leaves the village.
along(HOUSE, "Fv nord-sentrum", 260, -1, 19, 0, 0)
along(HOUSE, "Fv nord-sentrum", 330, 1, 22, 15, 2)
# Farms: house, barn and a shed or two round a yard at the end of their road.
at(HOUSE, -1772, -4416, 8.0, 0)      # Vestre Haugen
at(BARN, -1748, -4440, 98.0, 2)
at(SHED, -1770, -4384, 20.0, 0)
at(HOUSE, -1410, -4400, -15.0, 0)    # Austre Haugen
at(BARN, -1352, -4408, 75.0, 2)
at(SHED, -1408, -4432, -10.0, 0)
at(HOUSE, -1326, -4566, 30.0, 1)     # Haugen ovre
at(BARN, -1346, -4592, 120.0, 2)
at(HOUSE, -1752, -4816, 70.0, 0)     # Nordre Haugen
at(BARN, -1712, -4830, -20.0, 2)
at(SHED, -1768, -4786, 60.0, 0)


def main():
    roads_json = json.load(open(SRC + "roads.json", encoding="utf-8"))
    world = {r["name"]: r for r in roads_json["roads"]}
    lines = {}   # name -> (N,2) centre line
    for name in ("Fv nord-sentrum", "Lv haugen"):
        P = np.array([[p[0], p[2]] for p in world[name]["points"]])
        lines[name] = P
    removed = ["Haugen gate 1", "Haugen gate 2"]
    out_roads = []
    ok = True
    for rd in ROADS:
        ctrl = list(rd["ctrl"])
        base = lines[rd["snap"]]
        d = np.hypot(base[:, 0] - ctrl[0][0], base[:, 1] - ctrl[0][1])
        k = int(np.argmin(d))
        ctrl[0] = tuple(base[k])
        if d[k] > 12:
            print("WARN %s starts %.1f m from %s" % (rd["name"], d[k], rd["snap"]))
        P = catmull(ctrl, 4.0)
        y = np.array([height(x, z) for x, z in P])
        # Light smoothing of the profile (no terrain change: the road follows the ground).
        ys = np.convolve(np.pad(y, 2, mode="edge"), np.ones(5) / 5, mode="valid")
        seg = np.hypot(*np.diff(P, axis=0).T)
        grade = np.abs(np.diff(ys)) / np.maximum(seg, 0.1)
        L = float(seg.sum())
        print("%-26s %5.0f m  max grade %4.1f %% at %.0f m  mean %4.1f %%" % (rd["name"], L, grade.max() * 100, seg[:int(np.argmax(grade))].sum(), grade.mean() * 100))
        lines[rd["name"]] = P
        out_roads.append({"name": rd["name"], "class": rd["class"], "mesh": False, "lane_m": rd["lane_m"],
                          "lanes": rd["lanes"], "shoulder_m": rd["shoulder_m"], "paint": rd["paint"],
                          "points": [[round(float(x), 2), round(float(h) + 0.02, 2), round(float(z), 2)]
                                     for (x, z), h in zip(P, ys)],
                          "bridges": [], "culverts": [], "length_m": round(L, 1)})

    def road_frame(name, s):
        P = lines[name]
        seg = np.hypot(*np.diff(P, axis=0).T)
        acc = np.concatenate([[0], np.cumsum(seg)])
        if s < 0:  # negative: measured backwards from the Fv vertex nearest the junction
            j = int(np.argmin(np.hypot(P[:, 0] + 1596, P[:, 1] + 4376)))
            s = acc[j] + s
        elif name == "Fv nord-sentrum":
            j = int(np.argmin(np.hypot(P[:, 0] + 1596, P[:, 1] + 4376)))
            s = acc[j] + s
        i = int(np.clip(np.searchsorted(acc, s) - 1, 0, len(P) - 2))
        t = (s - acc[i]) / max(seg[i], 1e-6)
        p = P[i] + (P[i + 1] - P[i]) * t
        tan = (P[i + 1] - P[i]) / max(seg[i], 1e-6)
        return p, tan

    def dist_to_roads(x, z):
        best = 1e9
        for name, P in lines.items():
            if name in removed:
                continue
            best = min(best, float(np.min(np.hypot(P[:, 0] - x, P[:, 1] - z))))
        return best

    blds = []
    for b in B:
        if "road" in b:
            p, tan = road_frame(b["road"], b["s"])
            nrm = np.array([-tan[1], tan[0]]) * b["side"]
            q = p + nrm * b["setback"]
            # Long axis parallel to the road (the builder's convention: yaw from the road normal).
            away = -nrm
            yaw = math.atan2(away[0], away[1]) + math.radians(b["yaw"])
            x, z = float(q[0]), float(q[1])
        elif b["yaw_deg"] is None:
            # Long side to the nearest road (the builder's convention).
            x, z = b["x"], b["z"]
            best = None
            for name, P in lines.items():
                if name in removed:
                    continue
                d = np.hypot(P[:, 0] - x, P[:, 1] - z)
                k = int(np.argmin(d))
                if best is None or d[k] < best[0]:
                    best = (d[k], P[k])
            away = np.array([x, z]) - best[1]
            away /= max(np.linalg.norm(away), 1e-6)
            yaw = math.atan2(away[0], away[1]) + math.radians(b["extra"])
        else:
            x, z, yaw = b["x"], b["z"], math.radians(b["yaw_deg"])
        r = RADIUS[b["mesh"]]
        hs = [height(x + dx, z + dz) for dx in (-r * 0.6, 0, r * 0.6) for dz in (-r * 0.6, 0, r * 0.6)]
        drop = max(hs) - min(hs)
        dr = dist_to_roads(x, z)
        flag = ""
        if drop > r * 0.25:
            flag += " STEEP(%.1f m)" % drop
        if dr < r * 0.55 + 3.0:
            flag += " ON-ROAD(%.1f)" % dr
        for o in blds:
            if math.hypot(o["x"] - x, o["z"] - z) < (RADIUS[o["mesh"]] + r) * 0.7:
                flag += " OVERLAP"
        if flag:
            ok = False
            print("bld %d mesh %d at %.0f %.0f:%s" % (len(blds), b["mesh"], x, z, flag))
        blds.append({"mesh": b["mesh"], "x": round(x, 2), "z": round(z, 2),
                     "y": round(height(x, z) - 0.05 - min(drop * 0.35, 0.8), 2),
                     "yaw": round(yaw, 4), "color": TINTS[b["tint"]]})
    data = {"_comment": "WORLD-SETTLEMENT-01 Haugen prototype (tools/settlement_proto/design_haugen.py). "
                        "Applied only with --settlement-proto=haugen.",
            "name": "Haugen", "center": [-1600.0, -4400.0],
            # Old settlement buildings, mailboxes and garden trees inside this radius are removed.
            "clear_radius_m": 215.0,
            "remove_roads": removed, "roads": out_roads, "buildings": blds}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
    print("%d roads, %d buildings -> %s %s" % (len(out_roads), len(blds), OUT, "" if ok else "(with warnings)"))


if __name__ == "__main__":
    main()
