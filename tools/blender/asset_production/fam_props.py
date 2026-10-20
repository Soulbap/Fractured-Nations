"""Military infrastructure and props (ASSET-PRODUCTION-01).

Modular, freely placeable pieces with real dimensions. Lengths are multiples of common
modules where it matters (HESCO 1.06/1.37 m cells, 3.0 m fences and barriers, 20/40 ft
ISO containers) so layouts line up without stretching.

Each builder takes the ap_lib module (A) and returns an A.Asset. Front = +Y.
"""
import math

from mathutils import Vector

import ap_signs as S

FT20 = 6.058
FT40 = 12.192
ISO_W = 2.438
ISO_H = 2.591


# =============================================================================== containers


def iso_container(A, aid, length, mat, name):
    """ISO 1CC/1AA dry container: corrugated walls (normal map), frame rails and posts,
    corner castings, double doors with four locking bars at the front (+Y)."""
    a = A.Asset(aid, "prop", name, "Containers",
                "%s ISO dry freight container (%.3f x %.3f x %.3f m), doors at the front." % (name.split(" ")[0], length, ISO_W, ISO_H))
    W, Lg, H = ISO_W, length, ISO_H
    hw, hl = W / 2, Lg / 2
    paint = {"Container_OD": "Paint_OD", "Container_Tan": "Paint_Tan", "Container_Blue": "Paint_Grey",
             "Container_Rust": "Paint_Red", "Container_Grey": "Paint_Grey", "Container_White": "Paint_White"}[mat]
    cc = (0.162, 0.178, 0.118)
    # Corner castings (LOD0); posts run the full height on LOD1/2.
    for sx in (-1, 1):
        for sy in (-1, 1):
            for z in (cc[2] / 2, H - cc[2] / 2):
                a.box(cc, (sx * (hw - cc[0] / 2), sy * (hl - cc[1] / 2), z), "Steel_Dark", A.L0, bevel=0.006)
                # Aperture recesses on the long side and the end.
                a.box((0.004, 0.11, 0.06), (sx * (hw + 0.001), sy * (hl - cc[1] / 2), z), "Paint_Black", A.L0)
            a.box((0.15, 0.15, H - 2 * cc[2]), (sx * (hw - 0.075), sy * (hl - 0.09), H / 2), paint, A.L0, bevel=0.01)
            a.box((0.15, 0.17, H), (sx * (hw - 0.075), sy * (hl - 0.085), H / 2), paint, (1,))
    # Bottom and top side rails.
    rl = Lg - 2 * cc[1]
    for sx in (-1, 1):
        a.box((0.10, rl, 0.16), (sx * (hw - 0.05), 0, 0.08), paint, A.L01, bevel=0.008)
        a.box((0.07, rl, 0.10), (sx * (hw - 0.035), 0, H - 0.05), paint, A.L01, bevel=0.008)
        # Forklift pockets (20 ft only).
        if length < 7:
            for y in (-1.025, 1.025):
                a.box((0.004, 0.36, 0.10), (sx * (hw + 0.001), y, 0.07), "Paint_Black", A.L0)
    # Corrugated side walls and the closed end, roof panel.
    a.box((0.03, rl, H - 0.26), (-(hw - 0.045), 0, 0.16 + (H - 0.26) / 2), mat, A.L01)
    a.box((0.03, rl, H - 0.26), (hw - 0.045, 0, 0.16 + (H - 0.26) / 2), mat, A.L01)
    a.box((W - 0.30, 0.03, H - 0.26), (0, -(hl - 0.05), 0.16 + (H - 0.26) / 2), mat, A.L01)
    a.box((W - 0.14, rl, 0.03), (0, 0, H - 0.04), mat, A.L01)
    # Front end: header, sill, two door leaves, locking gear.
    a.box((W - 0.30, 0.16, 0.20), (0, hl - 0.08, H - 0.10), paint, A.L01, bevel=0.01)
    a.box((W - 0.30, 0.16, 0.16), (0, hl - 0.08, 0.08), paint, A.L01, bevel=0.01)
    dw = (W - 0.30) / 2 - 0.006
    dy = hl - 0.035
    for sx in (-1, 1):
        a.box((dw, 0.05, H - 0.36), (sx * (dw / 2 + 0.003), dy, H / 2), mat, A.L01)
        # Door edge frames.
        a.box((0.05, 0.06, H - 0.36), (sx * (dw - 0.022), dy + 0.005, H / 2), paint, A.L0)
        a.box((dw, 0.06, 0.05), (sx * (dw / 2 + 0.003), dy + 0.005, H - 0.205), paint, A.L0)
        a.box((dw, 0.06, 0.05), (sx * (dw / 2 + 0.003), dy + 0.005, 0.205), paint, A.L0)
        # Hinges on the outer edge.
        for z in (0.40, 1.0, 1.6, 2.2):
            a.box((0.06, 0.05, 0.10), (sx * (hw - 0.17), dy + 0.04, z), "Steel_Dark", A.L0)
        # Two locking bars per leaf, cam keepers, handles.
        for bx in (0.18, 0.58):
            x = sx * (0.003 + bx)
            a.cyl(0.0135, 0.0135, H - 0.20, (x, dy + 0.055, H / 2), "Steel_Galv", A.L0, segs=8)
            a.box((0.03, 0.03, H - 0.20), (x, dy + 0.05, H / 2), "Steel_Galv", (1,))
            for z in (0.17, H - 0.17):
                a.box((0.07, 0.05, 0.06), (x, dy + 0.05, z), "Steel_Dark", A.L0, bevel=0.008)
            a.box((0.025, 0.035, 0.30), (x + sx * 0.03, dy + 0.085, 1.05), "Steel_Galv", A.L0, rot=A.rot_y(sx * 75), bevel=0.006)
            a.box((0.06, 0.03, 0.05), (x + sx * 0.12, dy + 0.06, 1.01), "Steel_Dark", A.L0)
    # LOD2: one box with the painted door decal.
    a.box((W, Lg, H), (0, 0, H / 2), mat, A.L2)
    a.sign(A.RECT01, (0, hl + 0.003, H / 2), (-1, 0, 0), (0, 0, 1), W - 0.02, H - 0.02, S.rect("container_doors"), lods=A.L2)
    a.col_box((W, Lg, H), (0, 0, H / 2))
    a.marker("IP_Doors", (0, hl + 0.9, 0), 180, "stand here to open / load the doors")
    a.marker("ATT_Stack", (0, 0, H), 0, "next container stacks here (castings align)")
    a.ao_height, a.ao_strength = 0.9, 0.30
    a.meta["module"] = {"length": round(Lg, 3), "width": W, "height": H}
    return a


BUILDERS = {
    "iso_container_20_od": lambda A: iso_container(A, "iso_container_20_od", FT20, "Container_OD", "20 ft container (olive)"),
}
