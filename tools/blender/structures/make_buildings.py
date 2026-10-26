"""Buildings of the WORLD-BASE-01 construction set.

  barracks         containerized housing unit (CHU): 20 ft accommodation container on
                   block piers, door with steel steps, two windows, split A/C, lamp
  command_post     expandable 20 ft ISO shelter (TOC cell): olive container on levelling
                   jacks, side extension, ECU A/C units, steps, telescopic antenna mast
  supply_storage   K-span corrugated steel arch building on a concrete pad, end wall
                   with roll-up door and personnel door
  vehicle_shelter  steel frame maintenance shelter with an olive fabric cover, open front
                   with the door rolled up
  guard_tower      timber tower: braced 4 m legs, plywood fighting position with
                   sandbags, corrugated roof on posts, stairs at the back

Dimensions and collision boxes match scripts/construction/structure_catalog.gd
(Blender +Y = Godot -Z = front). Every building has a foundation skirt reaching below
the ground by the catalog's max_ground_gap, because the game sets buildings at the
highest ground point of their footprint. References are listed in
docs/WORLD-BASE-01_REPORT.md. Run inside Blender:

    exec(open(r"<repo>/tools/blender/structures/make_buildings.py").read())
"""
import importlib.util
import math
import os

REPO = globals().get("REPO", r"C:\\Users\\Hafnor\\Desktop\\Game Dev\\fractured-nations")
PREVIEW_DIR = globals().get("PREVIEW_DIR", os.path.join(REPO, "assets", "structures", "previews"))
EXPORT = globals().get("EXPORT", True)
ONLY = globals().get("ONLY", None)


def _load(name, rel):
    spec = importlib.util.spec_from_file_location(name, os.path.join(REPO, *rel))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


lib = _load("fn_blender_lib", ("tools", "blender", "fn_blender_lib.py"))
sl = _load("fn_structures_lib", ("tools", "blender", "fn_structures_lib.py"))
import bpy  # noqa: E402

sl.set_texture_dir(os.path.join(REPO, "assets", "structures", "textures"))

R90 = math.radians(90)


# --- Shared materials ------------------------------------------------------------------

def mats():
    m = {}
    rib = sl.tex_corrugation_normal("rib_container", n=512, ribs=8, max_slope=1.2, profile="trapezoid")
    m["tan_wall"] = sl.textured("TanPanel", sl.tex_painted("paint_tan", (0.62, 0.55, 0.41), seed=61, grime=0.25), 2.24, roughness=0.7, metallic=0.15, normal=rib, normal_strength=0.8)
    m["tan"] = sl.textured("TanSteel", sl.tex_painted("paint_tan_flat", (0.58, 0.51, 0.39), seed=62, grime=0.2, chips=0.04), 2.0, roughness=0.65, metallic=0.2)
    m["od_wall"] = sl.textured("OliveShelter", sl.tex_painted("paint_od", (0.24, 0.26, 0.18), seed=63, grime=0.25, chips=0.03), 2.24, roughness=0.7, metallic=0.15, normal=rib, normal_strength=0.6)
    m["od"] = sl.textured("OliveSteel", sl.tex_painted("paint_od_flat", (0.23, 0.25, 0.18), seed=64, grime=0.2, chips=0.05), 2.0, roughness=0.6, metallic=0.25)
    m["dark"] = sl.flat("DarkSteel", (0.12, 0.12, 0.11), roughness=0.7, metallic=0.5)
    m["galv"] = sl.textured("Galvanized", sl.tex_painted("galvanized", (0.62, 0.64, 0.63), seed=41, grime=0.18), 0.5, roughness=0.45, metallic=0.75)
    m["concrete"] = sl.textured("Concrete", sl.tex_concrete("pad_concrete", color=(0.6, 0.59, 0.56), seed=65), 2.0, roughness=0.95)
    m["glass"] = sl.flat("Glass", (0.10, 0.13, 0.15), roughness=0.08, metallic=0.4)
    m["white"] = sl.textured("UnitWhite", sl.tex_painted("paint_white", (0.78, 0.77, 0.72), seed=66, grime=0.2), 0.8, roughness=0.5)
    m["rubber"] = sl.flat("Rubber", (0.05, 0.05, 0.05), roughness=0.9)
    m["lamp"] = sl.flat("Lamp", (0.95, 0.92, 0.8), roughness=0.3)
    m["wood"] = sl.textured("Timber", sl.tex_wood("timber", (0.55, 0.43, 0.29), seed=67), 1.5, roughness=0.85)
    m["ply"] = sl.textured("Plywood", sl.tex_wood("plywood", (0.62, 0.50, 0.34), seed=68, grain=60), 1.2, roughness=0.85)
    m["bag"] = sl.textured("Sandbag", sl.tex_sandbag("sandbag", (0.56, 0.50, 0.37), seed=69), 0.6, roughness=0.95)
    m["fabric"] = sl.textured("ShelterFabric", sl.tex_fabric("shelter_fabric", (0.34, 0.36, 0.26), seed=70, weave_px=3, dirt=0.14), 3.0, roughness=0.9, double_sided=True)
    # The arch's K-span seams are geometry; no normal map (it would be projected across the curve).
    m["kspan"] = sl.textured("KSpanSteel", sl.tex_painted("paint_kspan", (0.6, 0.57, 0.47), seed=71, grime=0.3), 3.0, roughness=0.75, metallic=0.1)
    m["roofsheet"] = sl.textured("RoofSheet", sl.tex_painted("roof_sheet", (0.46, 0.47, 0.45), seed=72, grime=0.35), 2.28, roughness=0.55, metallic=0.6, normal=sl.tex_corrugation_normal("rib_roof", n=512, ribs=15, max_slope=1.0), normal_strength=1.0)
    m["kspan_end"] = sl.textured("KSpanEnd", sl.tex_painted("paint_kspan_end", (0.56, 0.53, 0.43), seed=73, grime=0.3), 2.4, roughness=0.6, metallic=0.3,
                                 normal=sl.tex_corrugation_normal("rib_end", n=512, ribs=12, max_slope=1.1, profile="trapezoid"), normal_strength=1.0, double_sided=True)
    m["camo"] = sl.textured("CamoNet", sl.tex_camo_net("camo_net"), 3.0, roughness=0.95, alpha=True, double_sided=True)
    return m


def camo_net(parts, m, x0, x1, y0, y1, z_top, clear, drop, sag=0.2, nx=18, ny=16):
    """Camouflage net as a canopy: flat-ish over the footprint rectangle (x0..x1, y0..y1)
    at z_top, falling `drop` metres over `clear` metres outside it to poles at the four
    corners. Never lower than z_top over the footprint, so it cannot cut the walls."""
    ex0, ex1, ey0, ey1 = x0 - clear, x1 + clear, y0 - clear, y1 + clear
    verts, faces = [], []
    for j in range(ny + 1):
        for i in range(nx + 1):
            x = ex0 + (ex1 - ex0) * i / nx
            y = ey0 + (ey1 - ey0) * j / ny
            dx = max(x0 - x, 0.0, x - x1)
            dy = max(y0 - y, 0.0, y - y1)
            d = min(math.hypot(dx, dy) / clear, 1.0)
            z = z_top - drop * d ** 1.4
            # Gentle sag between supports and a few wrinkles.
            z -= sag * math.sin(math.pi * i / nx) * math.sin(math.pi * j / ny) * (d * 0.8)
            z += 0.05 * math.sin(5.0 * x + 2.0 * y) * math.sin(3.0 * y - x)
            verts.append((x, y, z))
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces.append((a, a + 1, a + nx + 2, a + nx + 1))
    parts.append(sl.mesh_from("CamoNet", verts, faces, m["camo"]))
    for x in (ex0, ex1):
        for y in (ey0, ey1):
            parts.append(lib.limb("NetPole", (x, y, -0.2), (x, y, z_top - drop + 0.05), 0.025, 0.025, m["dark"], verts=5))
    # Spreader poles that hold the canopy above the roof.
    for x in (x0 + 1.0, x1 - 1.0):
        parts.append(lib.limb("Spreader", (x, (y0 + y1) / 2, z_top - 0.55), (x, (y0 + y1) / 2, z_top - 0.02), 0.03, 0.03, m["dark"], verts=5))


def container(parts, m, wall, frame, x_len, y_dep, z0, height):
    """ISO container shell: corrugated walls, frame rails, corner castings."""
    hx, hy = x_len / 2, y_dep / 2
    parts.append(lib.box("Shell", (x_len - 0.04, y_dep - 0.04, height - 0.1), (0, 0, z0 + height / 2), wall))
    # Bottom and top side rails, corner posts.
    for y in (-hy + 0.04, hy - 0.04):
        parts.append(lib.box("RailB", (x_len, 0.1, 0.16), (0, y, z0 + 0.08), frame, bevel=0.01))
        parts.append(lib.box("RailT", (x_len, 0.1, 0.1), (0, y, z0 + height - 0.05), frame, bevel=0.01))
    for x in (-hx + 0.06, hx - 0.06):
        for y in (-hy + 0.06, hy - 0.06):
            parts.append(lib.box("CornerPost", (0.13, 0.13, height), (x, y, z0 + height / 2), frame, bevel=0.01))
            for z in (z0 + 0.06, z0 + height - 0.06):
                parts.append(lib.box("Casting", (0.18, 0.17, 0.12), (x, y, z), m["dark"], bevel=0.01))
    for x in (-hx + 0.04, hx - 0.04):
        parts.append(lib.box("EndRailB", (0.1, y_dep, 0.16), (x, 0, z0 + 0.08), frame))
        parts.append(lib.box("EndRailT", (0.1, y_dep, 0.1), (x, 0, z0 + height - 0.05), frame))
    parts.append(lib.box("Roof", (x_len - 0.1, y_dep - 0.1, 0.04), (0, 0, z0 + height - 0.02), frame))


def steps(parts, m, x, y_front, z_top, width, depth_dir=1, n=3, mat=None):
    """Steel steps from the ground to z_top in front of y_front (depth_dir = +1: toward +Y)."""
    mat = mat or m["galv"]
    rise = z_top / (n + 1)
    run = 0.28
    for i in range(n + 1):
        z = z_top - i * rise
        y = y_front + depth_dir * (0.15 + i * run)
        parts.append(lib.box("Tread", (width, run + 0.02, 0.04), (x, y, z - 0.02), mat))
    for s in (-1, 1):
        y0 = y_front + depth_dir * 0.02
        y1 = y_front + depth_dir * (0.15 + (n + 0.5) * run)
        parts.append(lib.limb("Stringer", (x + s * width / 2, y0, z_top), (x + s * width / 2, y1, -0.3), 0.025, 0.025, mat, verts=4))
        parts.append(lib.limb("Rail", (x + s * width / 2, y0, z_top + 0.9), (x + s * width / 2, y1, 0.9), 0.02, 0.02, mat, verts=6))
        parts.append(lib.limb("RailPost", (x + s * width / 2, y1, -0.1), (x + s * width / 2, y1, 0.9), 0.02, 0.02, mat, verts=6))


def finish(parts, name, ao_h=0.8, ao=0.35):
    obj = lib.join(parts, name)
    sl.box_uv(obj)
    sl.ground_ao(obj, height=ao_h, strength=ao)
    return obj


# --- Barracks (CHU) --------------------------------------------------------------------

def make_barracks():
    lib.clear_scene()
    m = mats()
    parts = []
    z0 = 0.32   # floor of the container above the ground
    L, D, Hc = 6.06, 2.44, 2.59
    # Block piers (reaching 0.9 m into the ground for uneven sites).
    for x in (-2.7, 0.0, 2.7):
        for y in (-0.95, 0.95):
            parts.append(lib.box("Pier", (0.4, 0.2, z0 + 0.9), (x, y, (z0 - 0.9) / 2), m["concrete"], bevel=0.01))
    container(parts, m, m["tan_wall"], m["tan"], L, D, z0, Hc)
    fy = D / 2   # front (+Y)
    # Door with frame, handle and a small canopy.
    dx = -1.6
    parts.append(lib.box("DoorFrame", (1.04, 0.06, 2.1), (dx, fy + 0.0, z0 + 1.1), m["tan"], bevel=0.01))
    parts.append(lib.box("Door", (0.9, 0.05, 2.0), (dx, fy + 0.02, z0 + 1.06), m["white"], bevel=0.005))
    parts.append(lib.box("Handle", (0.12, 0.05, 0.03), (dx + 0.3, fy + 0.06, z0 + 1.05), m["dark"]))
    parts.append(lib.box("Canopy", (1.3, 0.45, 0.05), (dx, fy + 0.22, z0 + 2.3), m["tan"], bevel=0.01))
    parts.append(lib.box("Lamp", (0.2, 0.1, 0.12), (dx + 0.75, fy + 0.06, z0 + 2.15), m["lamp"], bevel=0.01))
    steps(parts, m, dx, fy, z0, 1.0, depth_dir=1, n=1)
    # Windows with frames and security bars.
    for wx in (0.2, 1.9):
        parts.append(lib.box("WinFrame", (0.86, 0.06, 0.86), (wx, fy, z0 + 1.45), m["white"], bevel=0.01))
        parts.append(lib.box("Glass", (0.74, 0.07, 0.74), (wx, fy + 0.005, z0 + 1.45), m["glass"]))
        for k in range(-2, 3):
            parts.append(lib.limb("Bar", (wx + k * 0.15, fy + 0.07, z0 + 1.05), (wx + k * 0.15, fy + 0.07, z0 + 1.85), 0.01, 0.01, m["dark"], verts=4))
    # Split A/C: outdoor unit on a wall bracket under the right window, indoor pipe cover.
    parts.append(lib.box("ACUnit", (0.8, 0.3, 0.55), (2.45, fy + 0.25, z0 + 0.45), m["white"], bevel=0.02))
    parts.append(lib.cylinder("ACFan", 0.2, 0.02, (2.35, fy + 0.41, z0 + 0.45), m["dark"], rot=(R90, 0, 0), verts=16))
    parts.append(lib.box("ACBracket", (0.7, 0.32, 0.04), (2.45, fy + 0.2, z0 + 0.16), m["galv"]))
    parts.append(lib.box("PipeCover", (0.08, 0.06, 0.9), (2.82, fy + 0.04, z0 + 1.1), m["white"]))
    # Electrical box and cable on the end wall.
    parts.append(lib.box("ElecBox", (0.06, 0.4, 0.5), (L / 2 + 0.03, -0.5, z0 + 1.5), m["od"], bevel=0.01))
    parts.append(lib.limb("Cable", (L / 2 + 0.06, -0.5, z0 + 1.25), (L / 2 + 0.3, -0.5, -0.2), 0.02, 0.02, m["rubber"], verts=4))
    # Roof vent.
    parts.append(lib.box("Vent", (0.4, 0.4, 0.18), (-0.5, -0.4, z0 + Hc + 0.09), m["galv"], bevel=0.02))
    return finish(parts, "barracks", ao_h=0.9, ao=0.4)


# --- Command post (expandable shelter) -------------------------------------------------

def make_command_post():
    lib.clear_scene()
    m = mats()
    parts = []
    z0 = 0.42
    L, D, Hc = 6.06, 2.44, 2.44
    cy = 0.1 + D / 2   # main container centered at +Y (front), extension behind it
    # Levelling jacks with base plates (reach 1.0 m below for uneven sites).
    for x in (-2.85, 2.85):
        for y in (cy - D / 2 + 0.15, cy + D / 2 - 0.15, -1.75):
            parts.append(lib.box("Jack", (0.14, 0.14, z0 + 1.0), (x, y, (z0 - 1.0) / 2), m["dark"]))
            parts.append(lib.box("JackPlate", (0.3, 0.3, 0.03), (x, y, 0.01), m["galv"]))
    # Main shelter.
    shell = []
    container(shell, m, m["od_wall"], m["od"], L, D, z0, Hc)
    for o in shell:
        o.location.y += cy
    parts += shell
    # Expansion: lower box behind the main shelter (walls fold out of the container).
    ext_d = 2.05
    ey = 0.1 - ext_d / 2
    eh = 2.2
    parts.append(lib.box("Extension", (L - 0.3, ext_d, eh), (0, ey, z0 + eh / 2), m["od_wall"], bevel=0.02))
    parts.append(lib.box("ExtRoof", (L - 0.2, ext_d + 0.08, 0.06), (0, ey, z0 + eh + 0.03), m["od"], bevel=0.01))
    parts.append(lib.box("ExtSeal", (L - 0.25, 0.08, eh), (0, 0.1, z0 + eh / 2), m["rubber"]))
    # Door at the back of the extension with steps (Godot +Z).
    by = ey - ext_d / 2
    parts.append(lib.box("DoorFrame", (1.0, 0.06, 2.0), (0, by - 0.01, z0 + 1.0), m["od"], bevel=0.01))
    parts.append(lib.box("Door", (0.86, 0.05, 1.92), (0, by - 0.03, z0 + 0.98), m["od"], bevel=0.005))
    parts.append(lib.box("Handle", (0.12, 0.05, 0.03), (0.3, by - 0.07, z0 + 1.0), m["dark"]))
    steps(parts, m, 0, by, z0, 1.1, depth_dir=-1, n=1)
    # Two environmental control units on the right end wall, duct to the shelter.
    for k, y in enumerate((cy - 0.55, cy + 0.55)):
        parts.append(lib.box("ECU", (0.65, 0.75, 0.95), (L / 2 + 0.36, y, z0 + 0.62), m["od"], bevel=0.03))
        parts.append(lib.box("ECUGrille", (0.02, 0.6, 0.5), (L / 2 + 0.69, y, z0 + 0.7), m["dark"]))
    parts.append(lib.box("ECUStand", (0.7, 1.9, 0.08), (L / 2 + 0.36, cy, z0 + 0.1), m["dark"]))
    # Telescopic antenna mast on the front-left corner, guy wires, whips and a sector dish.
    mx, my = -L / 2 + 0.35, cy + D / 2 + 0.18
    parts.append(lib.box("MastBracket", (0.3, 0.3, 0.2), (mx, my, z0 + 2.0), m["dark"]))
    segs = [(0.07, 2.2), (0.055, 1.8)]
    z = z0 + 0.4
    for r, h in segs:
        parts.append(lib.cylinder("Mast", r, h, (mx, my, z + h / 2), m["od"], verts=10))
        z += h - 0.15
    top = z + 0.15
    parts.append(lib.box("MastHead", (0.5, 0.08, 0.06), (mx, my, top), m["dark"]))
    for dx in (-0.22, 0.22):
        parts.append(lib.cylinder("Whip", 0.008, 1.6, (mx + dx, my, top + 0.8), m["dark"], verts=4))
    parts.append(lib.cylinder("Dish", 0.28, 0.08, (mx, my - 0.12, top - 0.6), m["white"], rot=(R90, 0, 0), verts=16))
    for gx, gy in ((-2.6, 1.8), (2.4, 2.2), (-2.2, -2.6)):
        parts.append(lib.limb("Guy", (mx, my, top - 0.3), (mx + gx, my + gy, -0.05), 0.004, 0.004, m["dark"], verts=3))
    # Cable reel and a small generator-style power box beside the steps.
    parts.append(lib.box("PowerBox", (0.8, 0.5, 0.7), (-2.2, by - 0.5, 0.35), m["od"], bevel=0.03))
    parts.append(lib.cylinder("Reel", 0.28, 0.25, (-1.3, by - 0.45, 0.28), m["rubber"], rot=(0, R90, 0), verts=14))
    # Camouflage net over the shelter on four poles (ridge above the roof).
    camo_net(parts, m, -L / 2 - 0.1, L / 2 + 0.8, -2.15, cy + D / 2 + 0.1, z0 + Hc + 0.6, 1.8, 1.4)
    # Roof walkway plates and a beacon.
    parts.append(lib.box("Walkway", (2.0, 0.6, 0.03), (0.8, cy, z0 + Hc + 0.02), m["galv"]))
    parts.append(lib.cylinder("Beacon", 0.07, 0.12, (2.5, cy + 0.8, z0 + Hc + 0.08), m["lamp"], verts=10))
    return finish(parts, "command_post", ao_h=0.9, ao=0.4)


# --- Supply storage (K-span) -----------------------------------------------------------

def make_supply_storage():
    lib.clear_scene()
    m = mats()
    parts = []
    W, Lg, Hr = 10.0, 14.0, 5.2
    slab = 0.12
    # Concrete pad with a deep skirt (slopes up to 1.2 m under the footprint).
    parts.append(lib.box("Pad", (W + 0.6, Lg + 0.6, 1.3 + slab), (0, 0, (slab - 1.3) / 2), m["concrete"], bevel=0.03))
    # Arch: half-ellipse profile with K-span seams every 0.6 m along the length (geometry).
    nseg = 28
    pitch = 0.6
    nrib = int(Lg / pitch)
    verts, faces, uvs = [], [], []
    ys = []
    for i in range(nrib + 1):
        y0 = -Lg / 2 + i * pitch
        ys += [(y0, 0.0), (y0 + 0.04, -0.03), (y0 + pitch - 0.04, -0.03)] if i < nrib else [(y0, 0.0)]
    a_half = W / 2 - 0.15
    for (y, inset) in ys:
        for k in range(nseg + 1):
            t = math.pi * k / nseg
            x = -math.cos(t) * (a_half + inset)
            z = slab + math.sin(t) * (Hr - slab + inset)
            verts.append((x, y, z))
    cols = nseg + 1
    arc = []
    for k in range(cols):
        t = math.pi * k / nseg
        arc.append(t)
    for j in range(len(ys) - 1):
        for k in range(nseg):
            a = j * cols + k
            faces.append((a, a + 1, a + cols + 1, a + cols))
    obj = sl.mesh_from("Arch", verts, faces, m["kspan"])
    parts.append(obj)
    # Footing curbs along both sides.
    for s in (-1, 1):
        parts.append(lib.box("Curb", (0.45, Lg, 0.32), (s * (W / 2 - 0.12), 0, slab + 0.16), m["concrete"], bevel=0.02))
    # End walls: vertical corrugated sheets inside the arch outline (ellipse polygon).
    for s, door in ((1, True), (-1, False)):
        y = s * (Lg / 2 - 0.02)
        ev = [(0.0, y, slab)]
        for k in range(nseg + 1):
            t = math.pi * k / nseg
            ev.append((-math.cos(t) * a_half, y, slab + math.sin(t) * (Hr - slab)))
        ef = [(0, k + 1, k + 2) if s > 0 else (0, k + 2, k + 1) for k in range(nseg)]
        parts.append(sl.mesh_from("EndWall", ev, ef, m["kspan_end"]))
        if door:
            # Roll-up door (3.8 x 4.0) with frame and drum housing, personnel door.
            parts.append(lib.box("DoorFrame", (4.2, 0.18, 4.25), (0.3, y + 0.06, slab + 2.12), m["tan"], bevel=0.02))
            parts.append(lib.box("RollDoor", (3.8, 0.12, 4.0), (0.3, y + 0.1, slab + 2.0), m["galv"]))
            for k in range(14):
                parts.append(lib.box("Slat", (3.8, 0.02, 0.025), (0.3, y + 0.165, slab + 0.15 + k * 0.28), m["dark"]))
            parts.append(lib.box("Drum", (4.1, 0.45, 0.45), (0.3, y + 0.25, slab + 4.45), m["tan"], bevel=0.03))
            parts.append(lib.box("PDoorFrame", (1.05, 0.12, 2.15), (-3.0, y + 0.05, slab + 1.07), m["tan"], bevel=0.01))
            parts.append(lib.box("PDoor", (0.9, 0.1, 2.03), (-3.0, y + 0.08, slab + 1.02), m["tan"], bevel=0.005))
            parts.append(lib.box("Sign", (0.8, 0.03, 0.45), (-3.0, y + 0.12, slab + 2.6), m["white"]))
            parts.append(lib.box("Lamp", (0.3, 0.15, 0.12), (0.3, y + 0.2, slab + 4.85), m["lamp"], bevel=0.01))
            # Pallets with crates in front of the door (supply look from the air).
            for k, (px, py) in enumerate(((3.6, y + 1.4), (3.6, y + 2.7), (-3.6, y + 1.6))):
                parts.append(lib.box("Pallet", (1.2, 1.0, 0.14), (px, py, slab + 0.07), m["wood"]))
                parts.append(lib.box("Crate", (1.1, 0.9, 0.7 + 0.25 * (k % 2)), (px, py, slab + 0.14 + (0.7 + 0.25 * (k % 2)) / 2), m["od"], bevel=0.02))
        else:
            parts.append(lib.box("Vent", (0.8, 0.12, 0.5), (0, y - 0.05, Hr - 1.3), m["dark"], bevel=0.01))
    return finish(parts, "supply_storage", ao_h=1.2, ao=0.35)


# --- Vehicle shelter (frame + fabric) --------------------------------------------------

def make_vehicle_shelter():
    lib.clear_scene()
    m = mats()
    parts = []
    W, Lg, Hw, Hr = 8.2, 12.2, 3.4, 5.5
    hx, hy = W / 2, Lg / 2
    # Steel frames every 2.44 m: legs, rafters, ridge, purlins at the eaves.
    frames = [-hy + 0.05 + i * (Lg - 0.1) / 5 for i in range(6)]
    for y in frames:
        for s in (-1, 1):
            parts.append(lib.box("Leg", (0.1, 0.1, Hw + 0.9), (s * (hx - 0.05), y, (Hw - 0.9) / 2), m["galv"]))
            parts.append(lib.limb("Rafter", (s * (hx - 0.05), y, Hw), (0, y, Hr), 0.05, 0.05, m["galv"], verts=4))
            parts.append(lib.box("BasePlate", (0.3, 0.3, 0.02), (s * (hx - 0.05), y, 0.01), m["dark"]))
    for s in (-1, 1):
        parts.append(lib.box("Eave", (0.08, Lg, 0.08), (s * (hx - 0.05), 0, Hw), m["galv"]))
    parts.append(lib.box("Ridge", (0.08, Lg, 0.08), (0, 0, Hr), m["galv"]))
    # Fabric: side walls, gable roof, back wall + back gable, front gable (open below).
    f = m["fabric"]
    ins = 0.03
    def quad(name, a, b, c, d):
        parts.append(sl.mesh_from(name, [a, b, c, d], [(0, 1, 2, 3)], f))
    zb = -0.8
    for s in (-1, 1):
        x = s * (hx + ins)
        quad("Wall", (x, -hy, zb), (x, hy, zb), (x, hy, Hw), (x, -hy, Hw))
        quad("Roof", (s * (hx + 0.12), -hy - 0.1, Hw - 0.08), (s * (hx + 0.12), hy + 0.1, Hw - 0.08), (0, hy + 0.1, Hr + 0.07), (0, -hy - 0.1, Hr + 0.07))
    yb = -hy - ins
    quad("Back", (-hx, yb, zb), (hx, yb, zb), (hx, yb, Hw), (-hx, yb, Hw))
    parts.append(sl.mesh_from("BackGable", [(-hx, yb, Hw), (hx, yb, Hw), (0, yb, Hr)], [(0, 1, 2)], f))
    yf = hy + ins
    parts.append(sl.mesh_from("FrontGable", [(-hx, yf, Hw), (hx, yf, Hw), (0, yf, Hr)], [(0, 2, 1)], f))
    # Rolled-up front door under the eave, straps; wall seams (darker fabric strips).
    parts.append(lib.cylinder("DoorRoll", 0.18, W - 0.3, (0, yf + 0.18, Hw - 0.12), f, rot=(0, R90, 0), verts=12))
    for x in (-2.5, 2.5):
        parts.append(lib.box("Strap", (0.06, 0.02, 0.5), (x, yf + 0.37, Hw - 0.2), m["rubber"]))
    for y in frames[1:-1]:
        for s in (-1, 1):
            parts.append(lib.box("Seam", (0.02, 0.06, Hw + 0.6), (s * (hx + 0.05), y, (Hw - 0.6) / 2), m["od"]))
    # Ground stakes and tie-downs along the sides.
    for y in frames:
        for s in (-1, 1):
            parts.append(lib.limb("Tie", (s * (hx + 0.05), y, 1.0), (s * (hx + 0.9), y, -0.05), 0.012, 0.012, m["rubber"], verts=4))
            parts.append(lib.cylinder("Stake", 0.025, 0.4, (s * (hx + 0.9), y, 0.1), m["dark"], verts=5))
    # Work light and a tool chest inside at the back.
    parts.append(lib.box("ToolChest", (1.2, 0.6, 1.0), (2.8, -hy + 0.6, 0.5), m["od"], bevel=0.02))
    parts.append(lib.box("Bench", (2.2, 0.7, 0.9), (0.2, -hy + 0.5, 0.45), m["wood"], bevel=0.01))
    parts.append(lib.box("WorkLight", (0.5, 0.2, 0.08), (0, 0, Hr - 0.25), m["lamp"]))
    return finish(parts, "vehicle_shelter", ao_h=1.0, ao=0.3)


# --- Guard tower ------------------------------------------------------------------------

_bag_rnd = None


def sandbag(parts, x, y, z, along_x, mat):
    """WORLD-DETAIL-02: one filled bag from tools/blender/sandbag_geo.py (a pillow with a folded end, as in the reference
    photographs) instead of a bevelled box."""
    global _bag_rnd
    import random
    G = _load("sandbag_geo", ("tools", "blender", "sandbag_geo.py"))
    if _bag_rnd is None:
        _bag_rnd = random.Random(384)
    rnd = _bag_rnd
    v, f = G.pillow((0.60, 0.32, 0.15), 1 if rnd.random() < 0.5 else -1, rnd)
    v = G.placed(v, (x, y, z), (0.0 if along_x else 90.0) + rnd.uniform(-3.0, 3.0), (rnd.uniform(-2, 2), rnd.uniform(-1.5, 1.5)))
    me = bpy.data.meshes.new("Bag")
    me.from_pydata(v, [], f)
    me.update()
    for p in me.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new("Bag", me)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    parts.append(obj)


def make_guard_tower():
    lib.clear_scene()
    m = mats()
    parts = []
    P = 4.0     # platform top
    half = 1.7
    leg = 1.4
    # Legs into the ground (uneven sites), concrete footings.
    for x in (-leg, leg):
        for y in (-leg, leg):
            parts.append(lib.box("Leg", (0.16, 0.16, P + 0.95), (x, y, (P - 0.95) / 2), m["wood"]))
            parts.append(lib.box("Footing", (0.45, 0.45, 0.25), (x, y, 0.05), m["concrete"], bevel=0.02))
    # X-bracing on all four sides at two levels.
    for (a, b) in (((-leg, -leg), (leg, -leg)), ((-leg, leg), (leg, leg)), ((-leg, -leg), (-leg, leg)), ((leg, -leg), (leg, leg))):
        for z0, z1 in ((0.3, 2.0), (2.0, 3.7)):
            parts.append(lib.limb("Brace", (a[0], a[1], z0), (b[0], b[1], z1), 0.04, 0.04, m["wood"], verts=4))
            parts.append(lib.limb("Brace", (a[0], a[1], z1), (b[0], b[1], z0), 0.04, 0.04, m["wood"], verts=4))
        parts.append(lib.limb("Girt", (a[0], a[1], 2.0), (b[0], b[1], 2.0), 0.05, 0.05, m["wood"], verts=4))
    # Platform: beams and plywood deck.
    for y in (-leg, 0, leg):
        parts.append(lib.box("Joist", (2 * half, 0.1, 0.2), (0, y, P - 0.2), m["wood"]))
    parts.append(lib.box("Deck", (2 * half, 2 * half, 0.05), (0, 0, P - 0.06), m["ply"]))
    # Parapet: plywood walls 1.1 m (opening at the back right for the stairs), sandbags on top.
    wall_h = 1.1
    t = 0.05
    walls = [((0, half - t / 2), (2 * half, t)), ((-half + t / 2, 0), (t, 2 * half)), ((half - t / 2, 0), (t, 2 * half)),
             ((-half + 1.05, -half + t / 2), (2.1, t))]   # back wall: x -1.7..0.4 (opening 0.4..1.7)
    for (cx, cy), (sx, sy) in walls:
        parts.append(lib.box("Parapet", (sx, sy, wall_h), (cx, cy, P + wall_h / 2), m["ply"]))
    zb = P + wall_h + 0.075
    for k in range(6):
        x = -half + 0.29 + k * 0.58
        sandbag(parts, x, half - 0.16, zb, True, m["bag"])
        sandbag(parts, x + 0.29 * (1 if k < 5 else 0), half - 0.16, zb + 0.14, True, m["bag"])
    for k in range(6):
        y = -half + 0.29 + k * 0.58
        for x in (-half + 0.16, half - 0.16):
            sandbag(parts, x, y, zb, False, m["bag"])
            if k < 5:
                sandbag(parts, x, y + 0.29, zb + 0.14, False, m["bag"])
    for k in range(3):
        sandbag(parts, -half + 0.29 + k * 0.58, -half + 0.16, zb, True, m["bag"])
    # Roof posts, beams and a corrugated roof sloping to the back.
    for x in (-half + 0.06, half - 0.06):
        for y in (-half + 0.06, half - 0.06):
            parts.append(lib.box("RoofPost", (0.1, 0.1, 2.5), (x, y, P + 1.25), m["wood"]))
    parts.append(lib.box("Beam", (2 * half + 0.3, 0.12, 0.15), (0, half - 0.06, P + 2.55), m["wood"]))
    parts.append(lib.box("Beam", (2 * half + 0.3, 0.12, 0.15), (0, -half + 0.06, P + 2.4), m["wood"]))
    roof = lib.box("Roof", (2 * half + 0.5, 2 * half + 0.5, 0.04), (0, 0, P + 2.55), m["roofsheet"])
    roof.rotation_euler = (math.atan2(0.15, 2 * half), 0, 0)
    parts.append(roof)
    # Searchlight on the front rail.
    parts.append(lib.cylinder("Searchlight", 0.14, 0.25, (0.9, half - 0.05, P + wall_h + 0.45), m["dark"], rot=(R90, 0, 0), verts=12))
    parts.append(lib.cylinder("Lens", 0.12, 0.02, (0.9, half + 0.08, P + wall_h + 0.45), m["lamp"], rot=(R90, 0, 0), verts=12))
    # Stairs at the back right: from the ground at y = -6.1 to the deck edge at y = -1.7.
    x0, x1 = 0.45, 1.45
    y_top, y_bot = -half, -6.1
    n = 14
    for i in range(n):
        f = (i + 0.5) / n
        y = y_top + (y_bot - y_top) * f
        z = P * (1 - f)
        parts.append(lib.box("Tread", (x1 - x0, 0.26, 0.04), ((x0 + x1) / 2, y, z), m["wood"]))
    for x in (x0, x1):
        parts.append(lib.limb("Stringer", (x, y_top, P), (x, y_bot, -0.05), 0.04, 0.04, m["wood"], verts=4))
        parts.append(lib.limb("Handrail", (x, y_top, P + 0.95), (x, y_bot, 0.95), 0.025, 0.025, m["wood"], verts=4))
        parts.append(lib.box("RailPost", (0.06, 0.06, 1.0), (x, y_bot + 0.1, 0.5), m["wood"]))
    parts.append(lib.box("StairPost", (0.12, 0.12, P), (x1, -3.9, P / 2 - 0.6), m["wood"]))
    return finish(parts, "guard_tower", ao_h=1.0, ao=0.3)


def run():
    results = {}
    jobs = (("barracks", make_barracks, [("persp", 35, 15, 11.0), ("back", 210, 18, 11.0)]),
            ("command_post", make_command_post, [("persp", 30, 16, 15.0, 2.0), ("back", 200, 18, 14.0, 2.0)]),
            ("supply_storage", make_supply_storage, [("persp", 30, 14, 26.0), ("back", 200, 20, 26.0)]),
            ("vehicle_shelter", make_vehicle_shelter, [("persp", 25, 12, 24.0), ("back", 210, 20, 24.0)]),
            ("guard_tower", make_guard_tower, [("persp", 30, 12, 16.0), ("back", 200, 14, 16.0)]))
    for name, fn, views in jobs:
        if ONLY and name not in ONLY:
            continue
        obj = fn()
        r = lib.stats(obj)
        if PREVIEW_DIR:
            r["previews"] = sl.preview_set(lib, obj, os.path.join(PREVIEW_DIR, name), views)
            sl.top_view(obj, os.path.join(PREVIEW_DIR, name + "_top.png"))
            lib.remove_preview_rig()
        if EXPORT:
            r["glb_bytes"] = lib.export_glb(obj, os.path.join(REPO, "assets", "structures", name + ".glb"))
            lib.save_blend(os.path.join(REPO, "assets", "structures", "blender", name + ".blend"))
        results[name] = r
    return results


result = run()
