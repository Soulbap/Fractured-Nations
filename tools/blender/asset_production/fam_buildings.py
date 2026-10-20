"""Main military base buildings (ASSET-PRODUCTION-01).

Semi-permanent, 2020-2030 forward-base construction: CMU block, prefabricated panel and
steel portal-frame buildings on concrete pads, corrugated roofs, steel doors, split AC
units, floodlights. All freely placeable: front = +Y, origin on the ground at the
footprint centre, foundation skirts below z = 0 for terrain fitting, no required
neighbours. Interaction points (IP_*), vehicle points (VEH_*) and expansion attachment
points (ATT_*) are exported as nodes; see docs/ASSET-PRODUCTION-01_REPORT.md.
"""
import math

import ap_kit as K
from ap_kit import Frame

ALL = (0, 1, 2)
L01 = (0, 1)
L0 = (0,)
L2 = (2,)


def _structure(slope=6.0, gap=None, category="Buildings", ramps=None):
    s = {"category": category, "max_slope_deg": slope, "blocks_navigation": True}
    if gap is not None:
        s["max_ground_gap"] = gap
    if ramps:
        s["ramps_godot"] = ramps
    return s


# =============================================================================== 1 HQ


def hq_building(A):
    """Battalion/brigade headquarters: CMU block building 16 x 10 m on a raised
    concrete plinth, low-pitch gable roof, covered entrance porch, steel shutters,
    split AC units, satellite dish and antenna mast."""
    a = A.Asset("hq_building", "building", "Headquarters", "Buildings",
                "Headquarters / tactical operations centre: 16 x 10 m CMU block building on a 0.3 m concrete plinth, "
                "covered entrance, 2.0 m double door, satellite dish and antenna mast.")
    W, D = 16.0, 10.0
    x0, x1, y0, y1 = -W / 2, W / 2, -D / 2, D / 2
    fl = 0.30                 # plinth top / floor level
    eave = fl + 3.30
    # Plinth with porch apron in front, foundation skirt to -0.6.
    a.skirt(x0 - 0.6, y0 - 0.6, x1 + 0.6, y1 + 3.2, 0.6, "Concrete", top=fl)
    # Walls (solid block body) and a darker plinth course.
    a.box_between((x0, y0, fl), (x1, y1, eave), "Concrete_Block")
    a.box_between((x0 - 0.02, y0 - 0.02, fl), (x1 + 0.02, y1 + 0.02, fl + 0.25), "Concrete_Dark", L01)
    rise = K.gable_roof(a, x0, y0, x1, y1, eave, 12, overhang=0.5, mat="Roof_OD", wall_mat="Concrete_Block")
    front, back = Frame((0, y1, fl), 0), Frame((0, y0, fl), 180)
    left, right = Frame((x0, 0, fl), 90), Frame((x1, 0, fl), -90)
    # Entrance porch: flat canopy on four posts, double door, sign, lights.
    K.door(a, front, 0, w=2.0, h=2.20, double=True, leaf="Paint_OD", light=False)
    a.box_between((-3.2, y1 + 0.02, eave - 0.45), (3.2, y1 + 2.9, eave - 0.27), "Paint_OD", ALL)
    a.box_between((-3.25, y1 + 2.82, eave - 0.60), (3.25, y1 + 2.95, eave - 0.27), "Paint_Grey", L01)
    for px in (-3.0, 3.0):
        a.box((0.15, 0.15, eave - 0.45 - fl), (px, y1 + 2.75, (eave - 0.45 + fl) / 2), "Paint_OD", ALL)
    for lx in (-1.6, 1.6):
        a.box((0.40, 0.40, 0.03), (lx, y1 + 1.4, eave - 0.465), "Lamp", L0)
    front.sign(a, "plate_hq", 2.2, 1.65, 1.2, 0.6, back="Paint_Grey")
    K.steps(a, Frame((0, y1 + 3.2, 0), 0), 0, 4.0, fl, rails=False)
    # Windows with half-closed steel shutters.
    for wx in (-6.4, -4.0, 4.0, 6.4):
        K.window(a, front, wx, 1.55, 1.2, 1.0, bars=False, shutter=True)
        K.window(a, back, wx, 1.55, 1.2, 1.0, bars=True)
    for wx in (-2.5, 2.5):
        K.window(a, left, wx, 1.55, 1.0, 1.0, bars=True)
        K.window(a, right, wx, 1.55, 1.0, 1.0, bars=True)
    K.door(a, left, 0.6, leaf="Paint_OD")
    K.steps(a, Frame((x0, -0.6, 0), 90), 0, 1.4, fl, rails=False)
    K.door(a, back, 0.0, leaf="Paint_OD")
    K.steps(a, Frame((0, y0, 0), 180), 0, 1.4, fl, rails=False)
    # Services: AC units on the back, cable tray, floodlights, downpipes.
    for ax in (-6.0, -2.6, 2.6, 6.0):
        K.ac_unit(a, back, ax, 2.55)
    K.ac_unit(a, right, -2.0 + 4.0, 2.55)
    K.cable_tray(a, back, -7.5, 7.5, eave - 0.35)
    for F, xs in ((front, (-7.6, 7.6)), (back, (-7.6, 7.6))):
        for fx in xs:
            K.floodlight(a, F, fx, eave - 0.5)
            K.downpipe(a, F, fx + (0.3 if fx < 0 else -0.3), eave)
    # Roof equipment: satellite dish on a frame, ventilators; antenna mast at the east gable.
    zr = eave + 2.5 * math.tan(math.radians(12)) + 0.10          # roof surface 2.5 m in from the rear eave
    a.box((1.2, 1.2, 0.10), (-4.5, y0 + 2.5, zr + 0.35), "Steel_Galv", L01)
    for lx in (-0.5, 0.5):
        for ly in (-0.5, 0.5):
            a.box((0.06, 0.06, 0.45), (-4.5 + lx, y0 + 2.5 + ly, zr + 0.12), "Steel_Galv", L0)
    a.cyl(0.05, 0.05, 0.6, (-4.5, y0 + 2.5, zr + 0.7), "Steel_Galv", L01, segs=8)
    K.dish(a, -4.5, y0 + 2.5, zr + 1.15, 0.6, 160, 35)
    for vx in (-1.5, 1.5):
        a.cyl(0.18, 0.18, 0.35, (vx, 0, eave + rise + 0.25), "Steel_Galv", L01, segs=10)
        a.cyl(0.24, 0.24, 0.06, (vx, 0, eave + rise + 0.45), "Steel_Galv", L0, segs=10)
    mx = x1 + 0.35
    a.cyl(0.09, 0.05, 9.0, (mx, -2.5, 4.5), "Steel_Galv", L01, segs=8)
    for bz in (2.0, 3.4):
        a.box((0.45, 0.10, 0.10), (mx - 0.22, -2.5, bz), "Steel_Dark", L0)
    for k, ln in enumerate((2.2, 1.6, 1.0)):
        K.whip(a, mx + 0.25 * (k - 1), -2.5, 9.0, ln)
    a.cyl(0.03, 0.03, 9.0, (mx, -2.5, 4.5), "Steel_Galv", L2, segs=4)
    # Cable to the generator hook-up point.
    a.box((0.40, 0.25, 0.55), (x1 - 1.2, y0 - 0.15, fl + 0.6), "Paint_Grey", L01)
    a.col_between((x0, y0, -0.6), (x1, y1, eave + rise))
    a.col_between((x0 - 0.6, y0 - 0.6, -0.6), (x1 + 0.6, y1 + 3.2, fl))
    a.col_between((-3.25, y1, eave - 0.6), (3.25, y1 + 2.95, eave - 0.27))
    a.marker("IP_Entrance", (0, y1 + 4.2, 0), 180, "main entrance (double door)")
    a.marker("IP_Door_Side", (x0 - 1.8, -0.6, 0), -90, "side door")
    a.marker("IP_Door_Rear", (0, y0 - 1.8, 0), 0, "rear door")
    a.marker("IP_Power", (x1 - 1.2, y0 - 1.2, 0), 0, "generator / power hook-up")
    a.marker("ATT_Expansion_W", (x0 - 1.0, -2.0, 0), 90, "annex / container office attaches here (west)")
    a.marker("ATT_Expansion_E", (x1 + 1.0, 2.0, 0), -90, "annex / container office attaches here (east)")
    a.marker("ATT_Roof_Antenna", (4.5, y0 + 2.5, eave + 2.5 * math.tan(math.radians(12)) + 0.1), 0, "extra antenna on the roof")
    a.ao_height, a.ao_strength = 1.2, 0.35
    a.structure = _structure(6.0, 1.0)
    a.meta["function"] = {"role": "command", "floor_area_m2": W * D, "staff": 25}
    return a


# =============================================================================== 2 Barracks


def barracks(A):
    """Relocatable prefabricated barracks 24 x 7.2 m: insulated panel walls on block
    piers, gable roof, three entrances with steps and landings, AC unit per room."""
    a = A.Asset("barracks_block", "building", "Barracks", "Buildings",
                "Prefabricated barracks 24.0 x 7.2 m (8 rooms, 32 beds): sandwich-panel walls on block piers, floor 0.5 m, "
                "gable roof, doors at the front centre and both gable ends.")
    W, D = 24.0, 7.2
    x0, x1, y0, y1 = -W / 2, W / 2, -D / 2, D / 2
    fl = 0.50
    eave = fl + 2.80
    # Skirt panels (foundation) and pier blocks visible under the skirt at LOD0.
    a.skirt(x0, y0, x1, y1, 0.45, "Paint_Grey", top=fl)
    a.box_between((x0, y0, fl), (x1, y1, eave), "Paint_Tan")
    rise = K.gable_roof(a, x0, y0, x1, y1, eave, 15, overhang=0.45, mat="Roof_Tan", wall_mat="Paint_Tan")
    front, back = Frame((0, y1, fl), 0), Frame((0, y0, fl), 180)
    left, right = Frame((x0, 0, fl), 90), Frame((x1, 0, fl), -90)
    # Panel joints every 1.2 m.
    for i in range(1, int(W / 1.2)):
        x = x0 + i * 1.2
        for F, s in ((front, 1), (back, -1)):
            a.box((0.05, 0.02, eave - fl), (x, s * (y1 + 0.005), (eave + fl) / 2), "Paint_Grey", L0)
    for i in range(1, int(D / 1.2)):
        y = y0 + i * 1.2
        for s in (-1, 1):
            a.box((0.02, 0.05, eave - fl), (s * (x1 + 0.005), y, (eave + fl) / 2), "Paint_Grey", L0)
    a.box_between((x0 - 0.02, y0 - 0.02, eave - 0.12), (x1 + 0.02, y1 + 0.02, eave), "Paint_Grey", L01)
    # Front: centre door with landing, windows, AC units, sign.
    K.door(a, front, 0, leaf="Paint_Grey", canopy=1.0)
    K.steps(a, Frame((0, y1, 0), 0), 0, 1.6, fl, landing=1.0)
    front.sign(a, "plate_barracks", 2.1, 1.75, 1.2, 0.6, back="Paint_Grey")
    room_x = [x0 + 1.5 + i * 3.0 for i in range(8)]
    for i, wx in enumerate(room_x):
        if abs(wx) < 1.2:
            continue
        K.window(a, front, wx, 1.45, 1.0, 0.9, bars=False, frame="Paint_White")
        K.window(a, back, wx, 1.45, 1.0, 0.9, bars=False, frame="Paint_White")
        K.ac_unit(a, back, wx + 1.1, 0.95 + 0.0)
    for F, x in ((left, 0.0), (right, 0.0)):
        K.door(a, F, x, leaf="Paint_Grey", canopy=0.8)
        K.steps(a, Frame(F.p(x, 0, -fl), F.yaw), 0, 1.6, fl, landing=1.0)
        K.window(a, F, 2.3, 1.45, 0.8, 0.9, bars=False)
        K.window(a, F, -2.3, 1.45, 0.8, 0.9, bars=False)
    # Fire point by the main door, ridge vents, downpipes.
    a.box((0.30, 0.20, 0.55), (1.6, y1 + 0.10, fl + 1.1), "Paint_Red", L0)
    for vx in (-8.0, 0.0, 8.0):
        a.box((0.6, 0.6, 0.25), (vx, 0, eave + rise + 0.18), "Steel_Galv", L01)
        a.box((0.75, 0.75, 0.05), (vx, 0, eave + rise + 0.33), "Steel_Galv", L0)
    for fx in (x0 + 0.25, x1 - 0.25):
        K.downpipe(a, front, -fx, eave)
        K.downpipe(a, back, fx, eave)
    for F in (front, back):
        for fx in (-9.0, 9.0):
            K.wall_light(a, F, fx, eave - fl - 0.4)
    a.col_between((x0, y0, -0.45), (x1, y1, eave + rise))
    a.col_between((-0.8, y1, 0), (0.8, y1 + 1.0, fl))
    for s in (-1, 1):
        a.col_between((s * x1 if s > 0 else x0 - 1.0, -0.8, 0), (x1 + 1.0 if s > 0 else x0, 0.8, fl))
    a.marker("IP_Door_Front", (0, y1 + 2.4, 0), 180, "main door")
    a.marker("IP_Door_W", (x0 - 2.4, 0, 0), -90, "west gable door")
    a.marker("IP_Door_E", (x1 + 2.4, 0, 0), 90, "east gable door")
    a.marker("ATT_Expansion_N", (0, y0 - 3.0, 0), 0, "second barracks block / shower container behind")
    a.marker("ATT_Expansion_W", (x0 - 4.0, 0, 0), 90, "extension in line (west)")
    a.marker("ATT_Expansion_E", (x1 + 4.0, 0, 0), -90, "extension in line (east)")
    a.ao_height, a.ao_strength = 1.0, 0.35
    a.structure = _structure(6.0, 0.8)
    a.meta["function"] = {"role": "accommodation", "rooms": 8, "beds": 32}
    return a


# =============================================================================== 3 Supply depot


def supply_depot(A):
    """Steel portal-frame warehouse 20 x 14 m, 6 m eaves: corrugated cladding over a
    concrete upstand, covered loading dock with two dock doors (1.2 m dock height),
    a drive-in roller door for forklifts, skylights."""
    a = A.Asset("supply_depot", "building", "Supply Depot", "Buildings",
                "Supply warehouse 20 x 14 m, eaves 6.0 m: 12 m covered loading dock (1.2 m truck-bed height, two 3.0 x 3.6 m "
                "dock doors), 4.5 x 4.8 m drive-in roller door, personnel door, skylights.")
    W, D = 20.0, 14.0
    x0, x1, y0, y1 = -W / 2, W / 2, -D / 2, D / 2
    eave = 6.0
    a.skirt(x0 - 0.3, y0 - 0.3, x1 + 0.3, y1 + 0.3, 0.6, "Concrete", top=0.15)
    a.box_between((x0, y0, 0.15), (x1, y1, 0.75), "Concrete")
    a.box_between((x0 + 0.03, y0 + 0.03, 0.75), (x1 - 0.03, y1 - 0.03, eave), "Roof_Tan")
    rise = K.gable_roof(a, x0, y0, x1, y1, eave, 10, overhang=0.35, mat="Roof_Galv", wall_mat="Roof_Tan")
    # Skylight strips on both roof slopes.
    t = math.tan(math.radians(10))
    for sx in (-6.0, 0.0, 6.0):
        for s in (-1, 1):
            yy = s * 3.5
            zz = eave + (D / 2 - abs(yy)) * t + 0.11
            a.box((1.0, 3.0, 0.02), (sx, yy, zz), "Plastic_White", L01, rot=A.rot_x(-s * 10))
    # Corner trims and eave gutter.
    for cx in (x0, x1):
        for cy in (y0, y1):
            a.box((0.14, 0.14, eave - 0.75), (cx, cy, (eave + 0.75) / 2), "Paint_Tan", L01)
    for s in (-1, 1):
        a.box((W + 0.7, 0.16, 0.14), (0, s * (D / 2 + 0.40), eave - 0.07), "Paint_Grey", L01)
    front, back = Frame((0, y1, 0.0), 0), Frame((0, y0, 0.0), 180)
    left, right = Frame((x0, 0, 0.0), 90), Frame((x1, 0, 0.0), -90)
    # Loading dock (front, centred left of the drive-in door).
    dx0, dx1, dh, dd = -8.0, 4.0, 1.20, 3.0
    a.box_between((dx0, y1, -0.5), (dx1, y1 + dd, dh), "Concrete")
    a.box_between((dx0, y1 + dd - 0.06, dh - 0.10), (dx1, y1 + dd + 0.02, dh), "Steel_Dark", L01)
    dock_doors = (-5.0, 1.0)
    for i, ddx in enumerate(dock_doors):
        K.rollup(a, Frame((0, y1, dh), 0), -ddx, 3.0, 3.6)
        for s in (-1, 1):
            a.box((0.25, 0.12, 0.45), (ddx + s * 1.1, y1 + dd + 0.06, dh - 0.35), "Rubber", L01, bevel=0.02)
        a.box((2.0, 0.6, 0.02), (ddx, y1 + dd - 0.32, dh + 0.005), "Steel_Dark", L0)
    # Dock canopy (cantilever) and steps with railing at the west end of the dock.
    a.box_between((dx0 - 0.3, y1, 5.45), (dx1 + 0.3, y1 + dd + 0.6, 5.58), "Roof_Galv", ALL)
    for bx in (dx0, -2.0, dx1):
        a.tube([(bx, y1 + 0.05, 5.95), (bx, y1 + dd + 0.5, 5.6)], 0.04, "Steel_Dark", L0, segs=6)
    K.steps(a, Frame((dx0, y1 + 1.5, 0), 90), 0, 1.2, dh, landing=0.0)
    for k in range(5):
        x = dx0 + 0.2 + k * (dx1 - dx0 - 0.4) / 4
        a.cyl(0.02, 0.02, 1.0, (x, y1 + dd - 0.1, dh + 0.5), "Paint_Yellow", L0, segs=6)
    a.box_between((dx0 + 0.2, y1 + dd - 0.12, dh + 0.96), (dx0 + 4.0, y1 + dd - 0.08, dh + 1.0), "Paint_Yellow", L0)
    # Drive-in roller door (ground level) and personnel door.
    K.rollup(a, front, -7.0, 4.5, 4.8)          # world x = +7.0 (front frame: local x = -world x)
    front.sign(a, "plate_supply", -6.0, 5.40, 1.6, 0.8, back="Paint_Grey")
    # Rear / side: personnel doors, louvres, floodlights, downpipes.
    K.door(a, back, -3.0, leaf="Paint_OD")
    K.door(a, left, 0.0, leaf="Paint_OD")
    for F in (left, right):
        for lx in (-4.0, 4.0):
            F.sign(a, "vent_grille", lx, 4.6, 1.0, 0.8, y=0.02)
    for F in (front, back):
        for fx in (-9.4, 9.4):
            K.floodlight(a, F, fx, eave - 0.6)
            K.downpipe(a, F, fx + (0.4 if fx < 0 else -0.4), eave)
    a.col_between((x0, y0, -0.6), (x1, y1, eave + rise))
    a.col_between((dx0, y1, -0.5), (dx1, y1 + dd, dh))
    a.marker("IP_Dock_1", (dock_doors[0], y1 + dd - 0.8, dh), 180, "loading dock door 1 (on the dock)")
    a.marker("IP_Dock_2", (dock_doors[1], y1 + dd - 0.8, dh), 180, "loading dock door 2 (on the dock)")
    a.marker("VEH_Dock_1", (dock_doors[0], y1 + dd + 5.0, 0), 0, "truck reverses to here (rear to the dock)")
    a.marker("VEH_Dock_2", (dock_doors[1], y1 + dd + 5.0, 0), 0, "truck reverses to here (rear to the dock)")
    a.marker("IP_Forklift_Door", (7.0, y1 + 2.0, 0), 180, "drive-in door")
    a.marker("IP_Door", (x0 - 1.2, 0, 0), -90, "personnel door (west side)")
    a.marker("ATT_Yard_E", (x1 + 6.0, 0, 0), -90, "container / pallet storage yard (east)")
    a.marker("ATT_Expansion_W", (x0 - 1.0, 0, 0), 90, "second warehouse / tent store (west)")
    a.ao_height, a.ao_strength = 1.4, 0.35
    a.structure = _structure(5.0, 1.0)
    a.meta["function"] = {"role": "logistics", "storage_m2": W * D, "pallet_positions": 180, "dock_doors": 2}
    return a


# =============================================================================== 4 Vehicle depot


def vehicle_depot(A):
    """Motor pool maintenance hall 25 x 16 m, 6.5 m eaves: three 4.6 x 5.0 m vehicle
    bays (fits trucks and 8x8 APCs), lean-to workshop office, concrete apron with
    drainage channel and bay markings."""
    a = A.Asset("vehicle_depot", "building", "Vehicle Depot", "Buildings",
                "Motor pool maintenance hall 25 x 16 m, eaves 6.5 m: three vehicle bays with 4.6 x 5.0 m doors, "
                "4 m lean-to office/workshop on the west side, 6 m concrete apron with drain and bay lines.")
    W, D = 25.0, 16.0
    x0, x1, y0, y1 = -W / 2, W / 2, -D / 2, D / 2
    eave = 6.5
    ap = 6.0                     # apron depth in front
    ox0 = x0 - 4.0               # lean-to office
    a.skirt(ox0 - 0.2, y0 - 0.3, x1 + 0.3, y1 + 0.3, 0.6, "Concrete", top=0.12)
    a.box_between((x0, y1 + 0.3, -0.4), (x1, y1 + ap, 0.10), "Concrete")
    a.box_between((x0, y0, 0.12), (x1, y1, 1.0), "Concrete")
    a.box_between((x0 + 0.03, y0 + 0.03, 1.0), (x1 - 0.03, y1 - 0.03, eave), "Roof_OD")
    rise = K.gable_roof(a, x0, y0, x1, y1, eave, 12, overhang=0.4, mat="Roof_OD", wall_mat="Roof_OD")
    for cx in (x0, x1):
        for cy in (y0, y1):
            a.box((0.16, 0.16, eave - 1.0), (cx, cy, (eave + 1.0) / 2), "Paint_OD", L01)
    front, back = Frame((0, y1, 0.12), 0), Frame((0, y0, 0.12), 180)
    left, right = Frame((x0, 0, 0.12), 90), Frame((x1, 0, 0.12), -90)
    bays = (-8.0, 0.0, 8.0)
    for i, bx in enumerate(bays):
        K.rollup(a, front, -bx, 4.6, 5.0, curtain="Paint_Grey", housing="Paint_OD")
        # Bay number plates above the doors (bay 1 = west).
        front.sign(a, "lane_%d" % (i + 1), -bx, 6.0, 0.55, 0.55)
    # Apron: drainage channel with grating, yellow bay lines, wheel stops.
    a.box_between((x0 + 0.3, y1 + 1.2, 0.10), (x1 - 0.3, y1 + 1.5, 0.112), "Steel_Dark", L01)
    for lx in (-12.0, -4.0, 4.0, 12.0):
        a.box_between((lx - 0.06, y1 + 1.6, 0.10), (lx + 0.06, y1 + ap - 0.3, 0.106), "Paint_Yellow", L01)
    # Personnel door, side and rear details.
    K.door(a, front, -11.2, leaf="Paint_OD")     # world x = +11.2
    front.sign(a, "plate_motorpool", -4.0, eave - 0.7, 2.2, 1.1, back="Paint_Grey")
    K.door(a, back, 6.0, leaf="Paint_OD")
    K.door(a, right, 3.0, leaf="Paint_OD")
    for F in (right, back):
        for lx in (-5.0, 0.0, 5.0):
            if F is back and lx == 5.0:
                continue
            F.sign(a, "vent_grille", lx, 4.8, 1.2, 0.9, y=0.02)
    for F, xs in ((front, (-12.2, 12.2)), (back, (-12.2, 12.2))):
        for fx in xs:
            K.floodlight(a, F, fx, eave - 0.6)
            K.downpipe(a, F, fx + (0.4 if fx < 0 else -0.4), eave)
    # Exhaust extraction stacks and ridge ventilators.
    for sx in (-8.0, 0.0, 8.0):
        a.cyl(0.20, 0.20, 1.6, (sx, y0 + 3.5, eave + 2.0), "Steel_Galv", L01, segs=10)
        a.cyl(0.32, 0.32, 0.25, (sx, y0 + 3.5, eave + 2.85), "Steel_Galv", L0, segs=10)
    # Lean-to office / workshop on the west side.
    oh_lo, oh_hi = 3.2, 3.9
    a.box_between((ox0, y0 + 2.0, 0.12), (x0, y1 - 2.0, oh_lo), "Paint_OD")
    a.poly([(ox0 - 0.3, y0 + 1.7, oh_lo), (x0, y0 + 1.7, oh_hi), (x0, y1 - 1.7, oh_hi), (ox0 - 0.3, y1 - 1.7, oh_lo),
            (ox0 - 0.3, y0 + 1.7, oh_lo + 0.1), (x0, y0 + 1.7, oh_hi + 0.1), (x0, y1 - 1.7, oh_hi + 0.1), (ox0 - 0.3, y1 - 1.7, oh_lo + 0.1)],
           [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], "Roof_OD")
    a.poly([(ox0, y0 + 2.0, oh_lo), (x0, y0 + 2.0, oh_lo), (x0, y0 + 2.0, oh_hi)], [(0, 1, 2)], "Paint_OD")
    a.poly([(ox0, y1 - 2.0, oh_lo), (x0, y1 - 2.0, oh_hi), (x0, y1 - 2.0, oh_lo)], [(0, 1, 2)], "Paint_OD")
    of = Frame((ox0, 0, 0.12), 90)
    K.door(a, of, 0.0, leaf="Paint_Grey", canopy=0.9)
    K.window(a, of, -2.4, 1.5, 1.2, 1.0, bars=True)
    K.window(a, of, 2.4, 1.5, 1.2, 1.0, bars=True)
    K.ac_unit(a, Frame((ox0 + 2.0, y1 - 2.0, 0.12), 0), 0, 2.4)
    a.col_between((x0, y0, -0.6), (x1, y1, eave + rise))
    a.col_between((ox0, y0 + 2.0, -0.6), (x0, y1 - 2.0, oh_hi))
    for i, bx in enumerate(bays):
        a.marker("VEH_Bay_%d" % (i + 1), (bx, y1 + ap + 6.0, 0), 180, "vehicle waits here, faces the bay door")
        a.marker("IP_Bay_%d" % (i + 1), (bx - 3.0, y1 + 1.0, 0), 180, "bay door control")
    a.marker("IP_Office", (ox0 - 1.6, 0, 0), -90, "workshop office door")
    a.marker("IP_Door", (11.2, y1 + 1.0, 0), 180, "personnel door")
    a.marker("ATT_Repair_Bay_E", (x1 + 6.0, 4.0, 0), -90, "open repair shelter / wash point (east)")
    a.marker("ATT_Fuel_Point", (x1 + 8.0, y1 + 10.0, 0), 180, "vehicle fuel point")
    a.ao_height, a.ao_strength = 1.4, 0.35
    a.structure = _structure(5.0, 1.0)
    a.meta["function"] = {"role": "maintenance", "bays": 3, "bay_door_m": [4.6, 5.0], "max_vehicle": "8x8 APC / 6x6 truck"}
    return a


BUILDERS = {
    "hq_building": hq_building,
    "barracks_block": barracks,
    "supply_depot": supply_depot,
    "vehicle_depot": vehicle_depot,
}
