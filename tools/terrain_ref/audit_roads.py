"""Road network audit (WORLD-PLAYTEST-01) on a generated world's source data.

    python audit_roads.py <source_dir> [--json out.json]

Checks every road of roads.json against water.json and the full-resolution height.r32
(when present; otherwise the macro heights):
  - water: road points inside the river channel or a lake outside a bridge span;
  - bridges: both ends on dry ground, road continues on both sides, deck clearance above
    the water, span covers the channel;
  - connectivity: every road end meets another road (or the map edge / a dead-end
    destination listed in DEAD_ENDS_OK); height step where roads meet;
  - geometry for vehicles: steepest grade over 20 m, tightest curve radius, carriageway
    width, per road class;
  - terrain fit (unpaved roads and streets are terrain paint): road profile vs ground.
Paved roads are Road Generator meshes whose terrain is flattened in Godot; their fit is
checked in the built world by tools/terrain_ref/audit_roads_godot.gd.
Exit code 1 when an error-level finding exists.
"""
import json
import math
import os
import sys

import numpy as np

# Vehicle-oriented limits per class: max grade (rise/run, over 20 m), min curve radius (m),
# min carriageway width (m). Track/local/street are single-vehicle-width roads.
LIMITS = {
    "primary": {"grade": 0.08, "radius": 45.0, "width": 6.5},
    "secondary": {"grade": 0.10, "radius": 35.0, "width": 5.5},
    "local": {"grade": 0.12, "radius": 22.0, "width": 4.0},
    "track": {"grade": 0.15, "radius": 15.0, "width": 3.5},
    "street": {"grade": 0.13, "radius": 0.0, "width": 4.0},
}
EDGE_M = 60.0          # a road ending this close to the map edge leaves the map
MEET_M = 10.0          # a road end within this distance of another road is connected
FIT_TOL_M = 0.6        # unpaved road profile vs ground


def main():
    src = sys.argv[1]
    out_json = sys.argv[sys.argv.index("--json") + 1] if "--json" in sys.argv else None
    rj = json.load(open(os.path.join(src, "roads.json"), encoding="utf-8"))
    wj = json.load(open(os.path.join(src, "water.json"), encoding="utf-8"))
    roads = rj["roads"]
    N = 10240
    hpath = os.path.join(src, "height.r32")
    if os.path.exists(hpath) and os.path.getsize(hpath) == N * N * 4:
        H = np.memmap(hpath, dtype="<f4", mode="r", shape=(N, N))
    else:
        H = np.load(os.path.join(src, "macro_height.npy"))
        N = H.shape[0]
    sp = 20000.0 / N

    def ground(x, z):
        i = np.clip(np.round((np.asarray(z) + 10000.0) / sp).astype(int), 0, N - 1)
        j = np.clip(np.round((np.asarray(x) + 10000.0) / sp).astype(int), 0, N - 1)
        return np.asarray(H[i, j], dtype=np.float64)

    RP = np.array(wj["river"]["points"])
    RW = (np.array(wj["river"]["width"]) - 6.0) * 0.5  # channel half width (mesh adds 6 m)
    RL = np.array(wj["river"]["level"])
    lakes = [(np.array(l["outline"]), l["level"], l["name"]) for l in wj["lakes"]]

    def river_info(x, z):
        """distance to the centre line, channel half width and water level (nearest point)."""
        d = np.hypot(RP[:, 0][None, :] - x[:, None], RP[:, 1][None, :] - z[:, None])
        k = np.argmin(d, axis=1)
        return d[np.arange(len(x)), k], RW[k], RL[k]

    def in_poly(px, pz, poly):
        inside = np.zeros(len(px), dtype=bool)
        x0, z0 = poly[:, 0], poly[:, 1]
        x1, z1 = np.roll(x0, -1), np.roll(z0, -1)
        for a, b, c, d in zip(x0, z0, x1, z1):
            cond = ((b > pz) != (d > pz)) & (px < (c - a) * (pz - b) / (d - b + 1e-12) + a)
            inside ^= cond
        return inside

    findings = []

    def add(level, road, kind, msg, pos=None):
        findings.append({"level": level, "road": road, "kind": kind, "msg": msg,
                         "pos": None if pos is None else [round(float(pos[0]), 1), round(float(pos[1]), 1)]})

    P = [np.array(r["points"], dtype=np.float64) for r in roads]
    total = 0.0
    per_class = {}
    for r, A in zip(roads, P):
        name, cls = r["name"], r["class"]
        lim = LIMITS[cls]
        x, y, z = A[:, 0], A[:, 1], A[:, 2]
        seg = np.hypot(np.diff(x), np.diff(z))
        L = float(seg.sum())
        total += L
        per_class[cls] = per_class.get(cls, 0.0) + L
        s = np.concatenate([[0.0], np.cumsum(seg)])
        in_bridge = np.zeros(len(A), dtype=bool)
        for a, b in r["bridges"]:
            in_bridge[a:b + 1] = True
        # Width.
        width = float(r["lane_m"]) * float(r["lanes"])
        if width < lim["width"]:
            add("warn", name, "width", "carriageway %.1f m < %.1f m for vehicles" % (width, lim["width"]))
        # Water.
        dr, hw, lvl = river_info(x, z)
        wet = (dr < hw) & ~in_bridge
        if wet.any():
            k = int(np.argmax(wet))
            add("error", name, "water", "%d points in the river channel outside a bridge" % int(wet.sum()), (x[k], z[k]))
        for poly, llvl, lname in lakes:
            inl = in_poly(x, z, poly)
            if inl.any():
                k = int(np.argmax(inl))
                add("error", name, "water", "%d points inside lake %s" % (int(inl.sum()), lname), (x[k], z[k]))
        # Bridges.
        for a, b in r["bridges"]:
            pa, pb = A[a], A[b]
            span = math.hypot(pb[0] - pa[0], pb[2] - pa[2])
            mid = (pa + pb) * 0.5
            dm, hwm, lm = river_info(np.array([mid[0]]), np.array([mid[2]]))
            ends_d, ends_hw, _ = river_info(np.array([pa[0], pb[0]]), np.array([pa[2], pb[2]]))
            if (ends_d < ends_hw + 2.0).any():
                add("error", name, "bridge", "bridge end in the channel (span %.0f m)" % span, mid[[0, 2]])
            if a < 3 or b > len(A) - 4:
                add("error", name, "bridge", "road does not continue on both sides of the bridge", mid[[0, 2]])
            clear = min(pa[1], pb[1]) - lm[0]
            if clear < 4.0:
                add("error", name, "bridge", "deck only %.1f m above the water" % clear, mid[[0, 2]])
            if span < 2.0 * hwm[0]:
                add("error", name, "bridge", "span %.0f m shorter than the channel %.0f m" % (span, 2 * hwm[0]), mid[[0, 2]])
        # Grade over 20 m.
        if L > 25.0:
            si = np.arange(0.0, L, 20.0)
            yi = np.interp(si, s, y)
            g = np.abs(np.diff(yi)) / 20.0
            k = int(np.argmax(g))
            if g[k] > lim["grade"] + 0.01:
                p = np.interp(si[k], s, x), np.interp(si[k], s, z)
                add("warn", name, "grade", "grade %.1f%% > %.0f%%" % (g[k] * 100, lim["grade"] * 100), p)
        # Curve radius (circumradius of points 20 m apart).
        if lim["radius"] > 0 and L > 45.0:
            si = np.arange(0.0, L, 20.0)
            xi, zi = np.interp(si, s, x), np.interp(si, s, z)
            q = np.stack([xi, zi], axis=1)
            a_ = np.linalg.norm(q[1:-1] - q[:-2], axis=1)
            b_ = np.linalg.norm(q[2:] - q[1:-1], axis=1)
            c_ = np.linalg.norm(q[2:] - q[:-2], axis=1)
            cross = np.abs((q[1:-1, 0] - q[:-2, 0]) * (q[2:, 1] - q[:-2, 1]) - (q[1:-1, 1] - q[:-2, 1]) * (q[2:, 0] - q[:-2, 0]))
            rad = np.where(cross > 1e-6, a_ * b_ * c_ / (2.0 * cross + 1e-12), np.inf)
            k = int(np.argmin(rad))
            if rad[k] < lim["radius"]:
                add("warn", name, "curve", "curve radius %.0f m < %.0f m" % (rad[k], lim["radius"]), q[k + 1])
        # Terrain fit of painted roads.
        if not r["mesh"]:
            gr = ground(x, z)
            diff = np.abs(gr - y)
            diff[in_bridge] = 0.0
            k = int(np.argmax(diff))
            if diff[k] > FIT_TOL_M:
                add("error" if diff[k] > 2.0 else "warn", name, "fit",
                    "profile %.1f m %s the ground" % (diff[k], "above" if y[k] > gr[k] else "below"), (x[k], z[k]))

    # Connectivity: each road end must meet another road or leave the map.
    for i, (r, A) in enumerate(zip(roads, P)):
        for end in (0, -1):
            e = A[end]
            if max(abs(e[0]), abs(e[2])) > 10000.0 - EDGE_M:
                continue
            best, best_h, best_name = np.inf, None, None
            for j, B in enumerate(P):
                if j == i:
                    continue
                d = np.hypot(B[:, 0] - e[0], B[:, 2] - e[2])
                k = int(np.argmin(d))
                if d[k] < best:
                    best, best_h, best_name = d[k], B[k, 1], roads[j]["name"]
            if best > MEET_M:
                lvl = "info" if r["class"] in ("street", "track", "local") else "warn"
                add(lvl, r["name"], "dead_end", "%s end meets no road (nearest %.0f m)" % ("start" if end == 0 else "end", best), e[[0, 2]])
            elif abs(best_h - e[1]) > 0.75:
                add("warn", r["name"], "junction", "height step %.1f m to %s" % (abs(best_h - e[1]), best_name), e[[0, 2]])

    errors = [f for f in findings if f["level"] == "error"]
    summary = {"roads": len(roads), "length_km": round(total / 1000.0, 1),
               "length_km_by_class": {k: round(v / 1000.0, 1) for k, v in per_class.items()},
               "bridges": sum(len(r["bridges"]) for r in roads),
               "culverts": sum(len(r.get("culverts", [])) for r in roads),
               "errors": len(errors), "warnings": sum(1 for f in findings if f["level"] == "warn"),
               "infos": sum(1 for f in findings if f["level"] == "info")}
    print(json.dumps(summary, ensure_ascii=False))
    for f in findings:
        print("  %-5s %-8s %-24s %s %s" % (f["level"], f["kind"], f["road"], f["msg"], f["pos"] or ""))
    if out_json:
        with open(out_json, "w", encoding="utf-8") as fp:
            json.dump({"summary": summary, "findings": findings}, fp, ensure_ascii=False, indent=1)
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
