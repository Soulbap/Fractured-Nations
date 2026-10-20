"""Road-related visual assets (ASSET-PRODUCTION-01): surface sections, roadside
dressing, culvert and a small bridge.

These are ASSETS and MATERIALS only. The gameplay branch owns road generation, terrain
integration and navigation (addons/road-generator); nothing here generates or snaps
roads. The 10 m straight sections document the recommended cross-sections and show the
surface materials (Asphalt, Gravel, Dirt, road paint) at their real tile sizes; the
road generator can use the same materials and profiles. Roads run along Y.

Cross-sections (left to right, metres):
  asphalt: ditch 2.0 | gravel shoulder 1.0 | 2 x 3.5 lanes (2.5 % crossfall) | shoulder 1.0 | ditch 2.0  -> 13.0
  gravel:  ditch 1.5 | 5.5 gravel carriageway (3 % crown) | ditch 1.5                                  -> 8.5
  dirt:    3.5 track with two wheel ruts and a raised centre strip                                     -> 3.5
"""
import math

from ap_kit import Frame

ALL = (0, 1, 2)
L01 = (0, 1)
L0 = (0,)
L12 = (1, 2)


def _strip(a, x0, x1, z0, z1, mat, L=10.0, lods=ALL):
    """One sloped strip of the cross-section, extruded along Y from -L/2 to L/2."""
    a.poly([(x0, -L / 2, z0), (x1, -L / 2, z1), (x1, L / 2, z1), (x0, L / 2, z0)], [(0, 1, 2, 3)], mat, lods)


def road_asphalt(A):
    a = A.Asset("road_asphalt_10m", "road", "Asphalt road section 10 m", "Roads",
                "Two-lane asphalt road, 10 m straight section: 7.0 m carriageway (2.5 % crossfall), 1.0 m gravel shoulders, "
                "2.0 m V-ditches 0.5 m deep, centre dashes (3 m / 6 m) and edge lines.")
    L = 10.0
    crown = 3.5 * 0.025
    _strip(a, -6.5, -5.5, 0.0, -0.45, "Dirt")
    _strip(a, -5.5, -4.5, -0.45, 0.02, "Dirt")
    _strip(a, -4.5, -3.5, 0.02, 0.06, "Gravel")
    _strip(a, -3.5, 0.0, 0.06, 0.06 + crown, "Asphalt")
    _strip(a, 0.0, 3.5, 0.06 + crown, 0.06, "Asphalt")
    _strip(a, 3.5, 4.5, 0.06, 0.02, "Gravel")
    _strip(a, 4.5, 5.5, 0.02, -0.45, "Dirt")
    _strip(a, 5.5, 6.5, -0.45, 0.0, "Dirt")
    # Skirt below the outer edges (hides gaps to the terrain) and the asphalt edge face.
    for sx in (-1, 1):
        a.poly([(sx * 6.5, -L / 2, 0.0), (sx * 6.5, L / 2, 0.0), (sx * 6.5, L / 2, -0.6), (sx * 6.5, -L / 2, -0.6)][::(1 if sx > 0 else -1)],
               [(0, 1, 2, 3)], "Dirt", ALL)
    # Markings: centre dashes 3 m long every 9 m (one in this section), edge lines 0.15 m.
    zc = 0.06 + crown + 0.004
    a.box((0.12, 3.0, 0.004), (0, -1.5, zc), "Paint_RoadWhite", L01)
    for sx in (-1, 1):
        x = sx * 3.30
        z = 0.06 + crown * (1 - 3.30 / 3.5) + 0.004
        a.box((0.15, L, 0.004), (x, 0, z), "Paint_RoadWhite", L01)
    a.col_box((13.0, L, 0.3), (0, 0, -0.1))
    a.marker("SNAP_S", (0, -L / 2, 0), 180, "section joins here (south)")
    a.marker("SNAP_N", (0, L / 2, 0), 0, "section joins here (north)")
    a.lod_ranges = [[0, 80], [80, 300], [300, 2000]]
    a.meta["profile"] = {"carriageway_m": 7.0, "lane_m": 3.5, "shoulder_m": 1.0, "ditch_m": 2.0, "ditch_depth_m": 0.5, "crossfall": 0.025}
    return a


def road_gravel(A):
    a = A.Asset("road_gravel_10m", "road", "Gravel road section 10 m", "Roads",
                "Gravel road, 10 m straight section: 5.5 m crowned carriageway (3 %), 1.5 m ditches 0.35 m deep.")
    L = 10.0
    crown = 2.75 * 0.03
    _strip(a, -4.25, -3.5, 0.0, -0.32, "Dirt")
    _strip(a, -3.5, -2.75, -0.32, 0.03, "Dirt")
    _strip(a, -2.75, 0.0, 0.03, 0.03 + crown, "Gravel")
    _strip(a, 0.0, 2.75, 0.03 + crown, 0.03, "Gravel")
    _strip(a, 2.75, 3.5, 0.03, -0.32, "Dirt")
    _strip(a, 3.5, 4.25, -0.32, 0.0, "Dirt")
    for sx in (-1, 1):
        a.poly([(sx * 4.25, -L / 2, 0.0), (sx * 4.25, L / 2, 0.0), (sx * 4.25, L / 2, -0.5), (sx * 4.25, -L / 2, -0.5)][::(1 if sx > 0 else -1)],
               [(0, 1, 2, 3)], "Dirt", ALL)
    # Loose gravel windrows along the edges (LOD0 only).
    for sx in (-1, 1):
        a.prism([(-0.15, 0.0), (0.15, 0.0), (0.0, 0.04)], (sx * 2.55, -L / 2, 0.035), (sx * 2.55, L / 2, 0.035), "Gravel_Dark", L0)
    a.col_box((8.5, L, 0.3), (0, 0, -0.12))
    a.marker("SNAP_S", (0, -L / 2, 0), 180)
    a.marker("SNAP_N", (0, L / 2, 0), 0)
    a.lod_ranges = [[0, 70], [70, 260], [260, 1500]]
    a.meta["profile"] = {"carriageway_m": 5.5, "ditch_m": 1.5, "ditch_depth_m": 0.35, "crown": 0.03}
    return a


def road_dirt(A):
    a = A.Asset("road_dirt_10m", "road", "Dirt track section 10 m", "Roads",
                "Dirt track, 10 m straight section: 3.5 m wide, two 0.45 m wheel ruts 0.06 m deep at 1.9 m track, raised centre strip.")
    L = 10.0
    prof = [(-1.75, 0.02), (-1.40, 0.0), (-1.18, -0.05), (-0.72, -0.05), (-0.50, 0.01), (0.50, 0.01),
            (0.72, -0.05), (1.18, -0.05), (1.40, 0.0), (1.75, 0.02)]
    for (x0, z0), (x1, z1) in zip(prof[:-1], prof[1:]):
        _strip(a, x0, x1, z0 + 0.03, z1 + 0.03, "Dirt")
    for sx in (-1, 1):
        a.poly([(sx * 1.75, -L / 2, 0.05), (sx * 1.75, L / 2, 0.05), (sx * 1.75, L / 2, -0.4), (sx * 1.75, -L / 2, -0.4)][::(1 if sx > 0 else -1)],
               [(0, 1, 2, 3)], "Dirt", ALL)
    a.box((0.9, L, 0.01), (0, 0, 0.045), "Gravel_Dark", L0)
    a.col_box((3.5, L, 0.2), (0, 0, -0.07))
    a.marker("SNAP_S", (0, -L / 2, 0), 180)
    a.marker("SNAP_N", (0, L / 2, 0), 0)
    a.lod_ranges = [[0, 60], [60, 220], [220, 1200]]
    a.meta["profile"] = {"width_m": 3.5, "track_m": 1.9, "rut_m": 0.45, "rut_depth_m": 0.06}
    return a


def guardrail(A, aid="guardrail_4m", end=False):
    """W-beam steel guardrail: 4 m module, posts every 2 m (1.0 m driven), beam at
    0.55-0.75 m with blockouts. end=True: flared terminal buried into the ground."""
    a = A.Asset(aid, "road", "Guardrail %s" % ("end terminal" if end else "4 m"), "Roads",
                "W-beam guardrail %s, rail centre 0.65 m, posts C100 every 2 m driven 1.0 m." % ("terminal (4 m flare to the ground)" if end else "module 4.0 m"))
    L = 4.0
    prof = [(-0.0, 0.55), (0.04, 0.585), (0.0, 0.62), (0.04, 0.655), (0.0, 0.69), (0.04, 0.725), (0.0, 0.75)]
    rail = [(y, z) for y, z in prof]
    for x in ((-L / 2, 0.0) if not end else (-L / 2, 0.0, L / 2 - 0.2)):
        a.box((0.10, 0.10, 1.75), (x, 0.0, -0.125), "Steel_Galv", ALL)
        a.box((0.10, 0.15, 0.30), (x, 0.12, 0.65), "Steel_Galv", L01)
    if not end:
        verts = []
        for (dy, z) in rail:
            verts.append((-L / 2, 0.20 + dy, z))
            verts.append((L / 2, 0.20 + dy, z))
        faces = [(2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2) for i in range(len(rail) - 1)]
        a.poly(verts, faces, "Steel_Galv", ALL)
        a.poly(verts, [f[::-1] for f in faces], "Steel_Galv", ALL)
    else:
        n = 8
        verts = []
        for k in range(n + 1):
            t = k / n
            x = -L / 2 + t * L
            zdrop = 0.75 * max(0.0, (t - 0.5) * 2) ** 1.2
            yout = 0.20 + 0.8 * max(0.0, (t - 0.5) * 2) ** 2
            for (dy, z) in rail:
                verts.append((x, yout + dy, z - zdrop))
        m = len(rail)
        faces = [(k * m + i, (k + 1) * m + i, (k + 1) * m + i + 1, k * m + i + 1) for k in range(n) for i in range(m - 1)]
        a.poly(verts, faces, "Steel_Galv", ALL)
        a.poly(verts, [f[::-1] for f in faces], "Steel_Galv", ALL)
    a.col_box((L, 0.30, 0.8), (0, 0.15, 0.4))
    a.marker("SNAP_W", (-L / 2, 0, 0), 90)
    if not end:
        a.marker("SNAP_E", (L / 2, 0, 0), -90)
    a.foundation = 1.0
    a.lod_ranges = [[0, 50], [50, 200], [200, 900]]
    return a


def delineator(A):
    a = A.Asset("road_delineator", "road", "Delineator post", "Roads", "Roadside delineator post 1.0 m, black band and red reflector.")
    a.box((0.10, 0.14, 1.3), (0, 0, 0.35), "Plastic_White", ALL, bevel=0.01)
    a.box((0.105, 0.145, 0.22), (0, 0, 0.82), "Plastic_Black", L01)
    a.box((0.04, 0.005, 0.10), (0, 0.073, 0.82), "Reflector_Red", L0)
    a.col_box((0.1, 0.14, 1.0), (0, 0, 0.5))
    a.foundation = 0.3
    a.lod_ranges = [[0, 25], [25, 70], [70, 200]]
    return a


def culvert(A):
    """Road culvert: 1.0 m concrete pipe 9 m long with headwalls and wing walls at both
    ends (openings face +-Y across the road, which runs along X here)."""
    a = A.Asset("road_culvert", "road", "Culvert with headwalls", "Roads",
                "Concrete pipe culvert, 1.0 m bore, 9 m long under the road, headwalls 2.4 x 1.4 m with wing walls at both ends.")
    Lp = 9.0
    r = 0.5
    a.cyl(r + 0.10, r + 0.10, Lp, (0, 0, r - 0.2), "Concrete", (1, 2), axis=(0, 1, 0), segs=16)
    # Pipe as an open tube (inside visible through the openings).
    ring_o = [((r + 0.1) * math.cos(2 * math.pi * k / 20), (r + 0.1) * math.sin(2 * math.pi * k / 20) + r - 0.2) for k in range(20)]
    ring_i = [(r * math.cos(2 * math.pi * k / 20), r * math.sin(2 * math.pi * k / 20) + r - 0.2) for k in range(20)]
    a.loft([[(x, y, z) for x, z in ring_o] for y in (-Lp / 2, Lp / 2)], "Concrete", L0, closed=True, cap=False)
    a.loft([[(x, y, z) for x, z in ring_i] for y in (Lp / 2, -Lp / 2)], "Concrete_Dark", L0, closed=True, cap=False)
    for sy in (-1, 1):
        y = sy * Lp / 2
        verts = []
        for (xo, zo), (xi, zi) in zip(ring_o, ring_i):
            verts += [(xo, y, zo), (xi, y, zi)]
        faces = [(2 * k, 2 * ((k + 1) % 20), 2 * ((k + 1) % 20) + 1, 2 * k + 1)[::(1 if sy > 0 else -1)] for k in range(20)]
        a.poly(verts, faces, "Concrete", L0)
        # Headwall around the opening and wing walls.
        a.box((0.9, 0.25, 1.4), (-0.75 - 0.0, y + sy * 0.12, 0.5), "Concrete", ALL)
        a.box((0.9, 0.25, 1.4), (0.75, y + sy * 0.12, 0.5), "Concrete", ALL)
        a.box((0.6, 0.25, 0.30), (0, y + sy * 0.12, 1.05), "Concrete", ALL)
        for sx in (-1, 1):
            a.prism([(-0.12, 0.0), (0.12, 0.0), (0.12, 0.45), (-0.12, 1.2)], (sx * 1.2, y, -0.2), (sx * 1.6, y + sy * 1.2, -0.2), "Concrete", ALL)
        a.box((1.0, 1.4, 0.06), (0, y + sy * 0.8, -0.22), "Concrete_Dark", L01)
    a.col_box((2.4, 0.25, 1.4), (0, -Lp / 2 - 0.12, 0.5))
    a.col_box((2.4, 0.25, 1.4), (0, Lp / 2 + 0.12, 0.5))
    a.foundation = 0.3
    a.lod_ranges = [[0, 50], [50, 200], [200, 900]]
    a.meta["bore_m"] = 1.0
    return a


def bridge_small(A):
    """Small road bridge: 12 m single span, 7.5 m deck (2 x 3.25 m lanes + kerbs),
    four precast beams on concrete abutments, steel parapet railings. Road along Y."""
    a = A.Asset("bridge_small", "road", "Small road bridge 12 m", "Roads",
                "Single-span concrete road bridge: 12 m span, 7.5 m deck, 0.9 m deep beams, abutments 3 m high with wing walls, "
                "1.1 m steel parapets. Deck top at 0.0 m; the gap below goes to -3.0 m.")
    span, wd = 12.0, 7.5
    a.box_between((-wd / 2, -span / 2 - 1.0, -0.25), (wd / 2, span / 2 + 1.0, 0.0), "Concrete")
    a.box_between((-3.25, -span / 2 - 1.0, 0.0), (3.25, span / 2 + 1.0, 0.012), "Asphalt", ALL)
    for sx in (-1, 1):
        a.box_between((sx * 3.25 if sx > 0 else -wd / 2, -span / 2 - 1.0, 0.0), (wd / 2 if sx > 0 else -3.25, span / 2 + 1.0, 0.20), "Concrete_Dark")
    for k in range(4):
        x = -2.7 + k * 1.8
        a.box_between((x - 0.3, -span / 2 - 0.9, -1.15), (x + 0.3, span / 2 + 0.9, -0.25), "Concrete", ALL)
    for sy in (-1, 1):
        y = sy * (span / 2 + 0.6)
        a.box_between((-wd / 2 - 0.3, y - 0.8, -3.0), (wd / 2 + 0.3, y + 0.8, -1.15), "Concrete", ALL)
        for sx in (-1, 1):
            a.box_between((sx * (wd / 2) - (0.3 if sx > 0 else 0.0), y + (0.0 if sy > 0 else -3.0), -3.0),
                          (sx * (wd / 2) + (0.0 if sx > 0 else 0.3), y + (3.0 if sy > 0 else 0.0), 0.2), "Concrete", ALL)
    for sx in (-1, 1):
        x = sx * (wd / 2 - 0.15)
        for k in range(9):
            y = -span / 2 - 0.8 + k * (span + 1.6) / 8
            a.box((0.08, 0.08, 1.1), (x, y, 0.75), "Steel_Galv", L01)
        for z in (0.75, 1.25):
            a.box((0.06, span + 1.8, 0.10), (x, 0, z), "Steel_Galv", L01)
    a.col_box((wd, span + 2.0, 0.25), (0, 0, -0.125))
    for sx in (-1, 1):
        a.col_box((0.3, span + 2.0, 1.3), (sx * (wd / 2 - 0.15), 0, 0.65))
    a.marker("SNAP_S", (0, -span / 2 - 1.0, 0), 180, "road joins (south)")
    a.marker("SNAP_N", (0, span / 2 + 1.0, 0), 0, "road joins (north)")
    a.lod_ranges = [[0, 80], [80, 300], [300, 2000]]
    a.meta["span_m"] = span
    a.meta["deck_width_m"] = wd
    return a


BUILDERS = {
    "road_asphalt_10m": road_asphalt,
    "road_gravel_10m": road_gravel,
    "road_dirt_10m": road_dirt,
    "guardrail_4m": guardrail,
    "guardrail_end": lambda A: guardrail(A, "guardrail_end", True),
    "road_delineator": delineator,
    "road_culvert": culvert,
    "bridge_small": bridge_small,
}
