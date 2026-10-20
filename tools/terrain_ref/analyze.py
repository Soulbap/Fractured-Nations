"""Playability measurements of a generated reference world (WORLD-TERRAIN-01).

Reads the generator output (height.r32, vegetation.png, info.png, roads.json, water.json)
and writes playability.json + playability_regions.png next to it. All numbers are measured
on the actual data that is imported into Terrain3D.

  python analyze.py <source_dir> [--layout layout.json]

Definitions
  slope          : from the 1.953 m heightmap, averaged to 7.8 m cells
  usable land    : slope <= 8 deg, not water; "open" additionally forest density < 0.3
  large site     : 400 x 400 m square, >= 92 % usable land (non-overlapping, greedy)
  small site     : 100 x 100 m square, >= 95 % usable land (non-overlapping, greedy)
  road graph     : all roads, nodes at road ends and shared junctions (within 12 m)
"""
import heapq
import json
import math
import os
import sys

import numpy as np
import OpenImageIO as oiio

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate import write_png, to_u8  # noqa: E402

REGIONS = [  # name, centre (km, reference frame)
    ("Nordvest-skogen", (3.5, 16.5)),
    ("Nordfjellet", (17.5, 17.0)),
    ("Sentraldalen", (10.0, 11.0)),
    ("Innsjø-vest", (3.5, 6.0)),
    ("Sørøst-åsene", (16.0, 4.5)),
    ("Øst-sletta", (15.5, 10.8)),
]


def load_png(path):
    # Straight (unassociated) alpha: the maps use alpha as data, not coverage.
    cfg = oiio.ImageSpec()
    cfg.attribute("oiio:UnassociatedAlpha", 1)
    b = oiio.ImageBuf(path, 0, 0, cfg)
    return b.get_pixels(oiio.FLOAT)


def box_mean(a, r):
    """Mean over a (2r+1)^2 window (edge-clamped) via summed area table."""
    p = np.pad(a, r + 1, mode="edge").astype(np.float64)
    s = p.cumsum(0).cumsum(1)
    n = 2 * r + 1
    out = s[n:, n:] - s[:-n, n:] - s[n:, :-n] + s[:-n, :-n]
    return (out / (n * n))[:a.shape[0], :a.shape[1]]


def greedy_sites(score, ok, r):
    """Non-overlapping site centres where ok, best score first."""
    ys, xs = np.nonzero(ok)
    order = np.argsort(-score[ys, xs])
    taken = np.zeros(ok.shape, dtype=bool)
    sites = []
    for i in order:
        y, x = ys[i], xs[i]
        if taken[y, x]:
            continue
        sites.append((y, x))
        taken[max(0, y - 2 * r):y + 2 * r + 1, max(0, x - 2 * r):x + 2 * r + 1] = True
    return sites


def main():
    src = sys.argv[1]
    N = 10240
    size_m = 20000.0
    sp = size_m / N
    h = np.memmap(os.path.join(src, "height.r32"), dtype="<f4", mode="r", shape=(N, N))
    f = 4
    C = N // f
    cell = sp * f
    hc = np.asarray(h).reshape(C, f, C, f).mean(axis=(1, 3))
    gy, gx = np.gradient(hc, cell)
    slope = np.degrees(np.arctan(np.hypot(gx, gy)))
    veg = load_png(os.path.join(src, "vegetation.png"))
    info = load_png(os.path.join(src, "info.png"))
    # Upsample 2048 maps to the 2560 analysis grid (nearest).
    idx = (np.arange(C) * veg.shape[0] / C).astype(int)
    forest = veg[idx][:, idx, 0]
    water_near = info[idx][:, idx, 3]
    water = water_near > 0.5
    usable = (slope <= 8.0) & ~water
    open_usable = usable & (forest < 0.3)
    km2 = cell * cell / 1e6
    total = C * C * km2
    bins = [0, 3, 5, 8, 12, 15, 20, 25, 30, 35, 45, 90]
    hist, _ = np.histogram(slope, bins=bins)
    stats = {
        "map_km2": round(total, 1),
        "height_m": {"min": round(float(hc.min()), 1), "max": round(float(hc.max()), 1),
                     "mean": round(float(hc.mean()), 1)},
        "slope_share_pct": {"%d-%d" % (bins[i], bins[i + 1]): round(100.0 * hist[i] / slope.size, 2)
                            for i in range(len(hist))},
        "slope_mean_deg": round(float(slope.mean()), 2),
        "water_km2": round(float(water.sum()) * km2, 2),
        "water_pct": round(100.0 * float(water.mean()), 2),
        "forest_pct": round(100.0 * float((forest > 0.4).mean()), 1),
        "usable_km2": round(float(usable.sum()) * km2, 1),
        "usable_pct": round(100.0 * float(usable.mean()), 1),
        "open_usable_km2": round(float(open_usable.sum()) * km2, 1),
        "traversable_vehicle_pct": round(100.0 * float(((slope <= 20) & ~water).mean()), 1),
        "traversable_infantry_pct": round(100.0 * float(((slope <= 35) & ~water).mean()), 1),
    }
    u = usable.astype(np.float32)
    r_big = int(200 / cell)
    r_small = int(50 / cell)
    big_score = box_mean(u, r_big)
    small_score = box_mean(u, r_small)
    big = greedy_sites(big_score, big_score >= 0.92, r_big)
    small = greedy_sites(small_score, small_score >= 0.95, r_small)
    stats["large_sites_400m"] = len(big)
    stats["small_sites_100m"] = len(small)

    # Regions (Voronoi of the region centres).
    yy, xx = np.mgrid[0:C, 0:C]
    xk = xx * cell / 1000.0
    yk = 20.0 - yy * cell / 1000.0
    d = np.stack([np.hypot(xk - c[0], yk - c[1]) for _, c in REGIONS])
    reg = np.argmin(d, axis=0)

    # Road graph.
    all_roads = json.load(open(os.path.join(src, "roads.json"), encoding="utf-8"))["roads"]
    # Town streets are local grids, not part of the regional network.
    roads = [r for r in all_roads if r["class"] != "street"]
    ends = []
    for r in roads:
        for p in (r["points"][0], r["points"][-1]):
            ends.append((p[0], p[2]))
    nodes = []

    def node_of(x, z):
        for i, (a, b) in enumerate(nodes):
            if math.hypot(a - x, b - z) < 12.0:
                return i
        nodes.append((x, z))
        return len(nodes) - 1
    for e in ends:
        node_of(*e)
    edges = []
    road_len = {}
    for ri, r in enumerate(roads):
        pts = r["points"]
        cuts = []
        for k, p in enumerate(pts):
            for ni, (a, b) in enumerate(nodes):
                if math.hypot(a - p[0], b - p[2]) < 12.0:
                    if not cuts or cuts[-1][1] != ni:
                        cuts.append((k, ni))
        for (k0, n0), (k1, n1) in zip(cuts[:-1], cuts[1:]):
            if n0 == n1:
                continue
            ln = sum(math.hypot(pts[k + 1][0] - pts[k][0], pts[k + 1][2] - pts[k][2]) for k in range(k0, k1))
            edges.append((n0, n1, ln, ri))
        road_len[r["class"]] = road_len.get(r["class"], 0.0) + r["length_m"]
    for r in all_roads:
        if r["class"] == "street":
            road_len["street"] = road_len.get("street", 0.0) + r["length_m"]
    adj = {i: [] for i in range(len(nodes))}
    for ei, (a, b, ln, ri) in enumerate(edges):
        adj[a].append((b, ei))
        adj[b].append((a, ei))
    # Components.
    comp = [-1] * len(nodes)
    nc = 0
    for s in range(len(nodes)):
        if comp[s] >= 0:
            continue
        st = [s]
        comp[s] = nc
        while st:
            v = st.pop()
            for w, _ in adj[v]:
                if comp[w] < 0:
                    comp[w] = nc
                    st.append(w)
        nc += 1
    # Graph bridges (edges whose removal disconnects): Tarjan.
    tin = [0] * len(nodes)
    low = [0] * len(nodes)
    seen = [False] * len(nodes)
    timer = [0]
    bridges = []
    sys.setrecursionlimit(100000)

    def dfs(v, pe):
        seen[v] = True
        timer[0] += 1
        tin[v] = low[v] = timer[0]
        for w, ei in adj[v]:
            if ei == pe:
                continue
            if seen[w]:
                low[v] = min(low[v], tin[w])
            else:
                dfs(w, ei)
                low[v] = min(low[v], low[w])
                if low[w] > tin[v]:
                    bridges.append(ei)
    for v in range(len(nodes)):
        if not seen[v]:
            dfs(v, -1)
    # Edge-disjoint routes between regions (unit-capacity max-flow between the road nodes
    # nearest to each region centre).
    def nearest_node(ck):
        """Nearest road junction (degree >= 3) to a region centre: its local hub."""
        x = ck[0] * 1000 - 10000
        z = 10000 - ck[1] * 1000
        hubs = [i for i in range(len(nodes)) if len(adj[i]) >= 3] or list(range(len(nodes)))
        return min(hubs, key=lambda i: math.hypot(nodes[i][0] - x, nodes[i][1] - z))

    def max_flow(s, t):
        used = set()
        flow = 0
        while True:
            prev = {s: None}
            q = [s]
            while q and t not in prev:
                v = q.pop(0)
                for w, ei in adj[v]:
                    key = (ei, v, w)
                    if w not in prev and (ei, v, w) not in used:
                        # Residual: an edge used in direction w->v can be used v->w (cancel).
                        if (ei, w, v) in used or (ei, v, w) not in used:
                            prev[w] = (v, ei)
                            q.append(w)
            if t not in prev:
                return flow
            w = t
            while prev[w] is not None:
                v, ei = prev[w]
                if (ei, w, v) in used:
                    used.discard((ei, w, v))
                else:
                    used.add((ei, v, w))
                w = v
            flow += 1
            if flow >= 6:
                return flow
    rn = [nearest_node(c) for _, c in REGIONS]
    routes = {}
    for i in range(len(REGIONS)):
        for j in range(i + 1, len(REGIONS)):
            routes["%s - %s" % (REGIONS[i][0], REGIONS[j][0])] = max_flow(rn[i], rn[j])
    total_bridges = sum(len(r["bridges"]) for r in roads)
    stats["roads"] = {
        "length_km": {k: round(v / 1000.0, 1) for k, v in road_len.items()},
        "total_km": round(sum(road_len.values()) / 1000.0, 1),
        "graph_nodes": len(nodes),
        "graph_edges": len(edges),
        "components": nc,
        "component_roads": [sorted({roads[e[3]]["name"] for e in edges if comp[e[0]] == k}) for k in range(nc)],
        "graph_bridges": len(bridges),
        "graph_bridge_names": sorted({roads[edges[e][3]]["name"] for e in bridges}),
        "river_bridges": total_bridges,
        "edge_disjoint_routes_between_regions": routes,
        "min_routes_between_regions": min(routes.values()) if routes else 0,
    }
    # Road density per region and per-region land stats.
    road_cells = np.zeros((C, C), dtype=bool)
    for r in all_roads:
        for p in r["points"]:
            cx = int((p[0] + 10000) / cell)
            cz = int((p[2] + 10000) / cell)
            if 0 <= cx < C and 0 <= cz < C:
                road_cells[cz, cx] = True
    stats["regions"] = []
    for i, (name, c) in enumerate(REGIONS):
        m = reg == i
        area = float(m.sum()) * km2
        nb = sum(1 for (y, x) in big if reg[y, x] == i)
        ns = sum(1 for (y, x) in small if reg[y, x] == i)
        stats["regions"].append({
            "name": name, "area_km2": round(area, 1),
            "mean_height_m": round(float(hc[m].mean()), 0),
            "max_height_m": round(float(hc[m].max()), 0),
            "usable_pct": round(100.0 * float(usable[m].mean()), 1),
            "open_usable_km2": round(float(open_usable[m].sum()) * km2, 1),
            "forest_pct": round(100.0 * float((forest[m] > 0.4).mean()), 1),
            "water_pct": round(100.0 * float(water[m].mean()), 2),
            "slope_mean_deg": round(float(slope[m].mean()), 1),
            "large_sites": nb, "small_sites": ns,
            "road_km_approx": round(float(road_cells[m].sum()) * cell / 1000.0, 1),
        })
    with open(os.path.join(src, "playability.json"), "w", encoding="utf-8") as fp:
        json.dump(stats, fp, indent=1, ensure_ascii=False)
    # Map: usable land (light), steep (dark), water (blue), regions (tinted borders),
    # large sites (red squares), small sites (orange dots).
    img = np.zeros((C, C, 3))
    img[:] = np.array([0.35, 0.33, 0.30])
    img[usable] = np.array([0.80, 0.82, 0.62])
    img[open_usable] = np.array([0.93, 0.92, 0.70])
    img[slope > 20] = np.array([0.20, 0.18, 0.17])
    img[water] = np.array([0.20, 0.40, 0.70])
    edge = np.zeros((C, C), dtype=bool)
    edge[1:, :] |= reg[1:, :] != reg[:-1, :]
    edge[:, 1:] |= reg[:, 1:] != reg[:, :-1]
    img[edge] = np.array([0.1, 0.1, 0.1])
    img[road_cells] = np.array([0.55, 0.15, 0.1])
    for (y, x) in small:
        img[max(0, y - 2):y + 3, max(0, x - 2):x + 3] = np.array([1.0, 0.6, 0.1])
    for (y, x) in big:
        rr = r_big
        img[max(0, y - rr):y + rr, max(0, x - rr):min(C, x - rr + 3)] = np.array([0.9, 0.1, 0.1])
        img[max(0, y - rr):y + rr, max(0, x + rr - 3):min(C, x + rr)] = np.array([0.9, 0.1, 0.1])
        img[max(0, y - rr):min(C, y - rr + 3), max(0, x - rr):x + rr] = np.array([0.9, 0.1, 0.1])
        img[max(0, y + rr - 3):min(C, y + rr), max(0, x - rr):x + rr] = np.array([0.9, 0.1, 0.1])
    write_png(os.path.join(src, "playability_map.png"), to_u8(img)[::2, ::2])
    print(json.dumps(stats, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
