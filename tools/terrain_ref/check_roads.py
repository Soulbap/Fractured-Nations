"""Road network sanity check: parallel overlaps (> 100 m within 8 m of another road) and
crossings of paved roads away from junctions. python check_roads.py <source_dir>"""
import json
import os
import sys
from collections import defaultdict

import numpy as np

src = sys.argv[1]
data = json.load(open(os.path.join(src, "roads.json"), encoding="utf-8"))
roads = data["roads"]
J = np.array([[j[0], j[2]] for j in data.get("junctions", [])]) if data.get("junctions") else np.zeros((0, 2))
P = [np.array([[p[0], p[2]] for p in r["points"]]) for r in roads]
ends = np.array([e for A in P for e in (A[0], A[-1])])
ov = defaultdict(float)
cross = []
for i in range(len(roads)):
    for j in range(i + 1, len(roads)):
        A, B = P[i], P[j]
        for k in range(0, len(A), 3):
            d = np.hypot(B[:, 0] - A[k, 0], B[:, 1] - A[k, 1])
            m = int(np.argmin(d))
            if d[m] < 8:
                dj = np.min(np.hypot(ends[:, 0] - A[k, 0], ends[:, 1] - A[k, 1]))
                if len(J):
                    dj = min(dj, np.min(np.hypot(J[:, 0] - A[k, 0], J[:, 1] - A[k, 1])))
                if dj > 60:
                    ov[(roads[i]["name"], roads[j]["name"])] += 30
                    if roads[i]["mesh"] and roads[j]["mesh"]:
                        cross.append((roads[i]["name"], roads[j]["name"], round((A[k, 0] + 10000) / 1000, 2), round((10000 - A[k, 1]) / 1000, 2)))
print("overlaps / crossings away from junctions (m):")
for k, v in sorted(ov.items(), key=lambda x: -x[1]):
    print("  ", k, int(v))
seen = set()
print("paved crossings without junction:")
for c in cross:
    key = (c[0], c[1], round(c[2], 1), round(c[3], 1))
    if key not in seen:
        seen.add(key)
        print("  ", c)
