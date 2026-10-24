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
import ap_signs as S
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


# =============================================================================== 5 Medical station


def medical_station(A):
    """Role 1 medical station: arched-frame field hospital tent 6.1 x 12 m with an end
    vestibule, attached white medical container, red-cross panels, ambulance bay."""
    a = A.Asset("medical_station", "building", "Medical Station", "Buildings",
                "Role 1 aid station: 6.1 x 12 m arched treatment tent with vestibule, 20 ft medical container, "
                "covered ambulance drop-off, red-cross markings.")
    W, D, ridge = 6.1, 12.0, 3.2
    import math as m
    # Floor platform (duckboard) as foundation.
    a.skirt(-W / 2 - 0.2, -D / 2, W / 2 + 0.2, D / 2 + 2.0, 0.3, "Timber_Dark", top=0.12)
    # Arched tent: superellipse cross-section lofted along Y, canvas, closed ends.
    # Superellipse arch (n = 3): near-vertical low walls rounding into the roof.
    prof = []
    n = 16
    for i in range(n + 1):
        t = m.pi * i / n
        c, s_ = m.cos(t), m.sin(t)
        prof.append((W / 2 * m.copysign(abs(c) ** (2 / 3), c), 0.12 + (ridge - 0.12) * abs(s_) ** (2 / 3)))
    verts, faces = [], []
    k = len(prof)
    for y in (-D / 2, D / 2):
        verts += [(x, y, z) for x, z in prof]
    for i in range(k - 1):
        faces.append((i, i + 1, k + i + 1, k + i))
    a.poly(verts, faces, "Canvas_Tan")
    for y, flip in ((-D / 2, True), (D / 2, False)):
        end = [(x, y, z) for x, z in prof]
        a.poly(end, [tuple(range(k))[::-1] if not flip else tuple(range(k))], "Canvas_Tan")
    # Frame arches every 2 m (visible ribs) and ridge line.
    for i in range(7):
        y = -D / 2 + i * D / 6
        a.tube([(x * 1.01, y, z * 1.005 + 0.01) for x, z in prof], 0.025, "Canvas_Tan", (0,), segs=5, cap=False)
    # Vestibule (entrance) at the front with a door flap.
    vw, vd, vh = 2.6, 2.0, 2.4
    a.box_between((-vw / 2, D / 2, 0.12), (vw / 2, D / 2 + vd, vh), "Canvas_Tan")
    a.prism([(-vw / 2 - 0.1, 0), (vw / 2 + 0.1, 0), (0, 0.45)], (0, D / 2, vh), (0, D / 2 + vd + 0.1, vh), "Canvas_Tan")
    F = Frame((0, D / 2 + vd, 0.12), 0)
    F.box(a, (1.4, 0.02, 2.0), 0, 0.01, 1.0, "Canvas_OD", L01)
    F.sign(a, "medical_cross", 0, 2.75 - 0.12, 0.6, 0.6, y=0.02)
    # Red cross panels on both sides of the arch and on the roof.
    for x, yaw in ((W / 2 + 0.01, -90), (-(W / 2 + 0.01), 90)):
        Frame((x, 0, 0), yaw).sign(a, "medical_cross", 0, 1.5, 1.6, 1.6, y=0.0)
    a.quad_uv([(-1.2, -1.2, ridge + 0.13), (1.2, -1.2, ridge + 0.13), (1.2, 1.2, ridge + 0.13), (-1.2, 1.2, ridge + 0.13)],
              S.rect("medical_cross"), "Signs", ALL)
    # Medical container on the east side, connected by a short canvas tunnel.
    cx = W / 2 + 2.6
    a.box_between((cx - 1.22, -4.5, 0.15), (cx + 1.22, 1.56, 2.74), "Container_White")
    a.box_between((cx - 1.25, -4.53, 0.0), (cx + 1.25, 1.59, 0.15), "Steel_Dark", L01)
    Frame((cx + 1.22, -1.5, 0.15), -90).sign(a, "medical_cross", 0, 1.4, 1.2, 1.2, y=0.01)
    Frame((cx, 1.56, 0.15), 0).sign(a, "plate_medical", 0, 1.9, 1.6, 0.8, y=0.01)
    K.door(a, Frame((cx, 1.56, 0.15), 0), -0.5, leaf="Paint_White", light=True)
    K.ac_unit(a, Frame((cx + 1.22, -3.5, 0.15), -90), 0, 1.9)
    a.box_between((W / 2 - 0.1, -2.6, 0.12), (cx - 1.22, -0.6, 2.2), "Canvas_Tan")
    # Ambulance drop-off canopy in front.
    a.box_between((-3.5, D / 2 + vd + 0.5, 3.0), (3.5, D / 2 + vd + 5.5, 3.1), "Canvas_White", ALL)
    for px in (-3.4, 3.4):
        for py in (D / 2 + vd + 0.6, D / 2 + vd + 5.4):
            a.cyl(0.04, 0.04, 3.0, (px, py, 1.5), "Steel_Galv", L01, segs=6)
    a.col_between((-W / 2, -D / 2, -0.3), (W / 2, D / 2, ridge))
    a.col_between((-vw / 2, D / 2, 0), (vw / 2, D / 2 + vd, vh))
    a.col_between((cx - 1.22, -4.5, 0), (cx + 1.22, 1.56, 2.74))
    a.marker("IP_Entrance", (0, D / 2 + vd + 1.0, 0), 180, "patient entrance")
    a.marker("VEH_Ambulance", (0, D / 2 + vd + 3.0, 0), 90, "ambulance stops under the canopy")
    a.marker("IP_Container", (cx - 0.5, 2.6, 0), 180, "medical supply container")
    a.marker("ATT_Expansion_W", (-W / 2 - 3.5, 0, 0), 90, "second ward tent (west)")
    a.marker("ATT_Helipad", (0, D / 2 + 25.0, 0), 180, "casualty evacuation landing site")
    a.ao_height, a.ao_strength = 0.8, 0.30
    a.structure = _structure(6.0, 0.5)
    a.meta["function"] = {"role": "medical", "beds": 8, "treatment_bays": 2}
    return a


# =============================================================================== 6 Guard tower


def guard_tower_steel(A):
    """Prefabricated steel guard tower: armoured 2.6 x 2.6 m cabin with slit windows on
    a 4.5 m braced frame, external stair with landing, searchlight, sandbagged base."""
    a = A.Asset("guard_tower_steel", "building", "Guard Tower", "Defences",
                "Steel watchtower: 2.6 x 2.6 m armoured cabin, floor at 4.5 m, 360 deg open firing band above a breastwork, "
                "searchlight, external stair, sandbag ring at the base.")
    c, fl = 2.6, 4.5
    for sx in (-1, 1):
        for sy in (-1, 1):
            a.box((0.6, 0.6, 0.3), (sx * 1.1, sy * 1.1, 0.0), "Concrete", ALL)
            a.box((0.16, 0.16, fl), (sx * 1.1, sy * 1.1, fl / 2), "Paint_OD", ALL)
    for z0, z1 in ((0.4, 2.4), (2.4, 4.3)):
        for sy in (-1, 1):
            a.cyl_between((-1.1, sy * 1.1, z0), (1.1, sy * 1.1, z1), 0.035, "Paint_OD", L01, segs=6)
            a.cyl_between((sy * 1.1, -1.1, z0), (sy * 1.1, 1.1, z1), 0.035, "Paint_OD", L01, segs=6)
        a.box((2.4, 0.08, 0.08), (0, 1.1, z1), "Paint_OD", L01)
        a.box((2.4, 0.08, 0.08), (0, -1.1, z1), "Paint_OD", L01)
    a.box((c + 0.4, c + 0.4, 0.15), (0, 0, fl), "Steel_Dark", ALL)
    # GAMEPLAY-01C: armoured breastwork to 1.05 m, an open firing band to 1.85 m (a standing sentry's eye is at 1.6 m),
    # the upper wall and roof above; corner posts and mullions frame the band.
    tw = 0.08
    for k in range(4):
        F = Frame(Frame((0, 0, 0), 90 * k).p(0, c / 2 - tw / 2, fl), 90 * k)
        F.box(a, (c - tw, tw, 0.98), -tw / 2, 0.0, 0.56, "Paint_OD", ALL)     # pinwheel: the walls meet without overlap
        F.box(a, (c - tw, tw, 0.50), -tw / 2, 0.0, 2.10, "Paint_OD", ALL)
        F.box(a, (c + 0.06, 0.16, 0.06), 0, 0.03, 1.07, "Steel_Dark", L01)   # firing sill
        for x in (-0.65, 0.65):
            F.box(a, (0.10, 0.12, 0.8), x, 0.0, 1.45, "Paint_OD", L01)
    for sx in (-1, 1):
        for sy in (-1, 1):
            a.box((0.12, 0.12, 0.8), (sx * (c / 2 - 0.06), sy * (c / 2 - 0.06), fl + 1.45), "Paint_OD", ALL)
    a.box_between((-c / 2, -c / 2, fl + 0.02), (c / 2, c / 2, fl + 0.08), "Steel_Dark", L01)
    a.box_between((-c / 2 - 0.35, -c / 2 - 0.35, fl + 2.35), (c / 2 + 0.35, c / 2 + 0.35, fl + 2.50), "Paint_OD")
    a.cyl(0.18, 0.15, 0.25, (0.9, 0.9, fl + 2.7), "Paint_Black", L01, axis=(0, 1, 0.3), segs=12)
    a.cyl(0.16, 0.16, 0.01, (0.9, 1.03, fl + 2.74), "Lamp", L0, axis=(0, 1, 0.3), segs=12)
    K.whip(a, -0.9, -0.9, fl + 2.5, 1.8)
    # Stair along the west side, landing at mid height, door at the back.
    run = 3.2
    for k in range(13):
        t = (k + 0.5) / 13
        a.box((0.9, 0.24, 0.04), (-c / 2 - 0.55, 1.6 - t * run, 0.15 + t * (fl - 0.15)), "Steel_Dark", L01)
    for sx in (-c / 2 - 0.1, -c / 2 - 1.0):
        a.cyl_between((sx, 1.6, 0.05), (sx, 1.6 - run, fl), 0.03, "Paint_OD", L01, segs=6)
        a.cyl_between((sx, 1.6, 1.0), (sx, 1.6 - run, fl + 1.0), 0.02, "Paint_Yellow", L0, segs=6)
    K.door(a, Frame((0, -c / 2, fl + 0.07), 180), 0.6, w=0.8, h=2.0, leaf="Paint_OD", light=False)
    # Sandbag ring at the base.
    import random
    rnd = random.Random(7)
    for k in range(4):
        for i in range(10):
            ang = (i + 0.5 * (k % 2)) * 2 * math.pi / 10
            r = 2.3
            a.box((0.6, 0.32, 0.13), (r * math.cos(ang), r * math.sin(ang), 0.07 + k * 0.12), "Sandbag", L0,
                  rot=A.rot_z(math.degrees(ang) + 90 + rnd.uniform(-4, 4)), bevel=0.03, segs=1)
    a.cyl(2.3, 2.3, 0.5, (0, 0, 0.25), "Sandbag", (1, 2), segs=10, cap=True)
    a.col_between((-1.2, -1.2, -0.3), (1.2, 1.2, fl))
    # GAMEPLAY-01C: floor, four breastwork walls (to fl + 1.05), roof and upper wall (from fl + 1.85).
    a.col_between((-c / 2 - 0.2, -c / 2 - 0.2, fl - 0.08), (c / 2 + 0.2, c / 2 + 0.2, fl + 0.07))
    a.col_between((-c / 2, c / 2 - tw, fl + 0.07), (c / 2, c / 2, fl + 1.05))
    a.col_between((-c / 2, -c / 2, fl + 0.07), (c / 2, -c / 2 + tw, fl + 1.05))
    a.col_between((-c / 2, -c / 2 + tw, fl + 0.07), (-c / 2 + tw, c / 2 - tw, fl + 1.05))
    a.col_between((c / 2 - tw, -c / 2 + tw, fl + 0.07), (c / 2, c / 2 - tw, fl + 1.05))
    a.col_between((-c / 2 - 0.2, -c / 2 - 0.2, fl + 1.85), (c / 2 + 0.2, c / 2 + 0.2, fl + 2.5))
    a.marker("IP_Stair", (-c / 2 - 0.55, 2.4, 0), 180, "foot of the stair")
    a.marker("IP_Observer", (0, 0.4, fl + 0.07), 0, "sentry position in the cabin")
    a.marker("DEF_Sentry_1", (-0.55, 0.55, fl + 0.07), 45.8, "slot 0 (DefenceDefs guard_tower_steel), faces front-left")
    a.marker("DEF_Sentry_2", (0.55, -0.55, fl + 0.07), -134.6, "slot 1, faces back-right")
    a.marker("ATT_Searchlight", (0.9, 0.9, fl + 2.7), 0)
    a.foundation = 0.3
    a.ao_height, a.ao_strength = 0.6, 0.30
    a.structure = _structure(10.0, 0.6, "Defences")
    return a


# =============================================================================== 7 Bunker


def bunker(A):
    """Bunker / fighting position: half-buried reinforced-concrete box 4 x 4 m with 0.4 m
    walls, three firing slits, sandbag cover on the roof, entrance trench at the back."""
    a = A.Asset("bunker_fighting", "building", "Bunker / Fighting Position", "Defences",
                "Reinforced-concrete bunker 4.0 x 4.0 x 1.6 m above ground (0.6 m below), firing slits front and sides, "
                "sandbag roof cover, rear entrance with sandbag walls.")
    W, D, H = 4.0, 4.0, 1.6
    a.box_between((-W / 2, -D / 2, -0.6), (W / 2, D / 2, H), "Concrete_Dark")
    a.box_between((-W / 2 - 0.2, -D / 2 - 0.2, H), (W / 2 + 0.2, D / 2 + 0.2, H + 0.25), "Concrete")
    for k, (yaw, w) in enumerate(((0, 1.8), (90, 1.0), (-90, 1.0))):
        F = Frame(Frame((0, 0, 0), yaw).p(0, (D if yaw == 0 else W) / 2, 0), yaw)
        F.box(a, (w, 0.06, 0.22), 0, 0.0, 1.20, "Paint_Black", ALL)
        F.box(a, (w + 0.3, 0.12, 0.08), 0, 0.05, 1.36, "Concrete", L01)
    # Sandbag cover on the roof (two layers), earth splayed around the base.
    import random
    rnd = random.Random(3)
    for k in range(2):
        for i in range(7):
            for j in range(7):
                if rnd.random() < 0.08:
                    continue
                x = -2.0 + (i + 0.5) * 4.0 / 7 + (0.15 if k else 0)
                y = -2.0 + (j + 0.5) * 4.0 / 7
                a.box((0.58, 0.32, 0.13), (x, y, H + 0.32 + k * 0.12), "Sandbag", L0, rot=A.rot_z(rnd.uniform(-8, 8) + (90 if k else 0)), bevel=0.03, segs=1)
    a.box_between((-W / 2, -D / 2, H + 0.25), (W / 2, D / 2, H + 0.52), "Sandbag", (1, 2), bevel=0.03)
    # Earth bank piled against the front and side walls (below the firing slits).
    for yaw in (0, 90, -90):
        F = Frame(Frame((0, 0, 0), yaw).p(0, 2.0, 0), yaw)
        a.prism([(-2.4, 0.0), (2.4, 0.0), (2.0, 0.85), (-2.0, 0.85)], F.p(0, 0.0, -0.05), F.p(0, 1.2, -0.05), "Dirt", ALL)
    # Rear entrance: opening in the back wall + sandbag-lined approach.
    Fb = Frame((0, -D / 2, 0), 180)
    Fb.box(a, (0.9, 0.05, 1.5), 0, 0.0, 0.7, "Paint_Black", ALL)
    for sx in (-0.75, 0.75):
        for k in range(8):
            a.box((0.32, 0.6, 0.13), (sx, -D / 2 - 1.0, 0.07 + k * 0.12), "Sandbag", L0, bevel=0.03, segs=1)
        a.box((0.32, 1.8, 0.95), (sx, -D / 2 - 1.0, 0.48), "Sandbag", (1, 2))
    a.col_between((-W / 2, -D / 2, -0.6), (W / 2, D / 2, H + 0.5))
    a.marker("IP_Entrance", (0, -D / 2 - 2.2, 0), 0, "rear entrance")
    a.marker("IP_FiringPort_Front", (0, D / 2 - 0.6, 0.0), 0, "rifleman at the front slit (floor at 0.0 m)")
    a.marker("IP_FiringPort_W", (-W / 2 + 0.6, 0, 0.0), 90)
    a.marker("IP_FiringPort_E", (W / 2 - 0.6, 0, 0.0), -90)
    a.foundation = 0.6
    a.ao_height, a.ao_strength = 0.7, 0.35
    a.structure = _structure(8.0, 0.8, "Defences")
    return a


# =============================================================================== 8 Communications station


def comms_station(A):
    """Communications station: shelter container with equipment racks, 18 m guyed
    lattice mast with panel and dish antennas, satellite terminal, generator pad."""
    a = A.Asset("comms_station", "building", "Communications Station", "Buildings",
                "Signals site: 20 ft equipment shelter (A/C, cable entry), 18 m guyed lattice mast with dishes and whips, "
                "2.4 m satellite terminal, generator pad.")
    # Gravel pad.
    a.box_between((-7.0, -6.0, -0.05), (7.0, 6.0, 0.06), "Gravel", ALL)
    sx0, sy0 = -3.5, 1.0
    a.box_between((sx0 - 3.03, sy0 - 1.22, 0.30), (sx0 + 3.03, sy0 + 1.22, 2.89), "Container_OD")
    for x in (sx0 - 2.6, sx0 + 2.6):
        for y in (sy0 - 0.9, sy0 + 0.9):
            a.box((0.3, 0.3, 0.32), (x, y, 0.15), "Concrete", ALL)
    Fs = Frame((sx0, sy0 - 1.22, 0.30), 180)
    K.door(a, Fs, 1.5, leaf="Paint_OD")
    K.steps(a, Frame((sx0 - 1.5, sy0 - 1.22, 0), 180), 0, 1.0, 0.30, rails=False)
    K.ac_unit(a, Frame((sx0 + 3.03, sy0, 0.30), -90), 0, 1.6)
    Frame((sx0, sy0 + 1.22, 0.30), 0).sign(a, "plate_comms", 0, 1.8, 1.4, 0.7, y=0.01)
    a.box((0.5, 0.25, 0.6), (sx0 + 2.7, sy0 + 1.35, 1.5), "Paint_Grey", L01)
    # Mast with cable ladder to the shelter.
    mx, my = 3.0, 1.5
    K.lattice_mast(a, mx, my, 18.0, 0.55)
    for z, r in ((9.0, 7.0), (17.0, 9.5)):
        K.guy_wires(a, mx, my, z, r, 3, 20.0)
    for yaw, z in ((30, 16.5), (150, 16.5), (270, 16.5)):
        x = mx + 0.5 * math.cos(math.radians(yaw))
        y = my + 0.5 * math.sin(math.radians(yaw))
        a.box((0.32, 0.08, 1.4), (x, y, z), "Plastic_White", L01, rot=A.rot_z(yaw + 90))
    K.dish(a, mx, my + 0.5, 13.0, 0.6, 0, 5)
    K.dish(a, mx - 0.5, my, 11.0, 0.45, 100, 3)
    for k, ln in enumerate((3.0, 2.0)):
        K.whip(a, mx + 0.15 * (k - 0.5), my, 18.0, ln)
    a.tube([(mx, my, 3.0), (mx - 0.5, my - 0.2, 2.6), (sx0 + 3.03, sy0, 2.4)], 0.03, "Plastic_Black", L0, segs=5)
    # Satellite terminal on a ground frame.
    a.box((1.6, 1.6, 0.15), (-3.0, -3.5, 0.1), "Steel_Galv", L01)
    a.cyl(0.08, 0.08, 1.2, (-3.0, -3.5, 0.75), "Steel_Galv", L01, segs=8)
    K.dish(a, -3.0, -3.2, 1.6, 1.2, 160, 40)
    # Generator pad.
    a.box_between((3.5, -4.5, 0.06), (6.5, -2.5, 0.18), "Concrete", ALL)
    a.col_between((sx0 - 3.03, sy0 - 1.22, 0), (sx0 + 3.03, sy0 + 1.22, 2.89))
    a.col_box((0.7, 0.7, 18.0), (mx, my, 9.0))
    a.col_box((1.6, 1.6, 2.4), (-3.0, -3.5, 1.2))
    a.marker("IP_Shelter_Door", (sx0 + 1.5, sy0 - 2.6, 0), 0, "shelter door")
    a.marker("ATT_Generator", (5.0, -3.5, 0.18), 0, "generator set stands on this pad")
    a.marker("ATT_Mast_Top", (mx, my, 18.0), 0, "antenna mounting at the top of the mast")
    a.lod_ranges = [[0, 80], [80, 300], [300, 2500]]
    a.ao_height, a.ao_strength = 0.8, 0.30
    a.structure = _structure(6.0, 0.6)
    a.meta["function"] = {"role": "communications", "mast_m": 18}
    return a


# =============================================================================== 9 Training facility


def training_facility(A):
    """Training facility: prefabricated classroom building 14 x 8 m with a covered
    outdoor briefing area (benches, map board) and a flag-free sign mast."""
    a = A.Asset("training_facility", "building", "Training Facility", "Buildings",
                "Training centre: 14 x 8 m classroom building (two classrooms, 40 seats) on a plinth, 6 x 8 m covered "
                "briefing area with benches and a map board.")
    W, D = 14.0, 8.0
    x0, x1, y0, y1 = -W / 2, W / 2, -D / 2, D / 2
    fl = 0.3
    eave = fl + 3.0
    a.skirt(x0 - 0.3, y0 - 0.3, x1 + 6.6, y1 + 0.3, 0.5, "Concrete", top=fl)
    a.box_between((x0, y0, fl), (x1, y1, eave), "Concrete_Block")
    rise = K.gable_roof(a, x0, y0, x1, y1, eave, 12, overhang=0.45, mat="Roof_Tan", wall_mat="Concrete_Block")
    front, back = Frame((0, y1, fl), 0), Frame((0, y0, fl), 180)
    K.door(a, front, 3.5, leaf="Paint_Grey", canopy=1.0)
    K.door(a, front, -3.5, leaf="Paint_Grey", canopy=1.0)
    front.sign(a, "plate_training", 0, 2.2, 1.6, 0.8, back="Paint_Grey")
    for wx in (-5.6, -1.5, 1.5, 5.6):
        K.window(a, front, wx, 1.6, 1.4, 1.1, bars=False)
        K.window(a, back, wx, 1.6, 1.4, 1.1, bars=False)
        K.ac_unit(a, back, wx + 0.9, 0.9)
    for F, xs in ((front, (-6.8, 6.8)), (back, (-6.8, 6.8))):
        for fx in xs:
            K.downpipe(a, F, fx, eave)
    # Covered briefing area east of the building.
    bx0, bx1 = x1, x1 + 6.3
    a.box_between((bx0, y0, eave - 0.05), (bx1, y1, eave + 0.07), "Roof_Tan", ALL)
    for px in (bx0 + 3.0, bx1 - 0.15):
        for py in (y0 + 0.15, y1 - 0.15):
            a.box((0.15, 0.15, eave - fl), (px, py, (eave + fl) / 2), "Paint_Grey", ALL)
    for r in range(3):
        y = y0 + 1.6 + r * 1.6
        a.box((4.0, 0.35, 0.05), (bx0 + 3.4, y, fl + 0.45), "Timber", L01)
        for lx in (-1.7, 1.7):
            a.box((0.06, 0.30, 0.45), (bx0 + 3.4 + lx, y, fl + 0.22), "Steel_Dark", L0)
    a.box((0.08, 2.4, 1.4), (bx1 - 0.5, 0, fl + 1.6), "Paint_White", L01)
    a.box((0.06, 0.06, 0.9), (bx1 - 0.5, -1.1, fl + 0.45), "Steel_Dark", L0)
    a.box((0.06, 0.06, 0.9), (bx1 - 0.5, 1.1, fl + 0.45), "Steel_Dark", L0)
    a.col_between((x0, y0, -0.5), (x1, y1, eave + rise))
    a.col_between((x0 - 0.3, y0 - 0.3, -0.5), (bx1 + 0.3, y1 + 0.3, fl))
    a.col_between((bx0, y0, eave - 0.05), (bx1, y1, eave + 0.07))
    a.marker("IP_Classroom_1", (3.5, y1 + 2.0, 0), 180)
    a.marker("IP_Classroom_2", (-3.5, y1 + 2.0, 0), 180)
    a.marker("IP_Briefing", (bx0 + 3.4, 0, fl), 90, "instructor position at the map board")
    a.marker("ATT_Range_Access", (bx1 + 4.0, 0, 0), -90, "path to ranges / training areas")
    a.ao_height, a.ao_strength = 1.0, 0.35
    a.structure = _structure(6.0, 0.8)
    a.meta["function"] = {"role": "training", "seats": 40, "classrooms": 2}
    return a


BUILDERS.update({
    "medical_station": medical_station,
    "guard_tower_steel": guard_tower_steel,
    "bunker_fighting": bunker,
    "comms_station": comms_station,
    "training_facility": training_facility,
})
