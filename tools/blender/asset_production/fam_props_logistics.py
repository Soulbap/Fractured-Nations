"""Military infrastructure props, part 2: logistics and equipment (ASSET-PRODUCTION-01).

Pallets, crates, ammunition, fuel (jerrycans, drums, tank skid), generators, lighting,
radio mast, tents, road and base signs, camouflage net canopy, IBC tank, field toilet.
Real dimensions (EUR pallet 1.2 x 0.8 m, NATO jerrycan, 200 l drum, M2A1 ammo can ...).
Front = +Y, origin on the ground.
"""
import math

import ap_kit as K
import ap_signs as S
from ap_kit import Frame

ALL = (0, 1, 2)
L01 = (0, 1)
L0 = (0,)
L12 = (1, 2)
L2 = (2,)
TINY = [[0, 15], [15, 40], [40, 90]]
SMALL = [[0, 20], [20, 60], [60, 160]]
MEDIUM = [[0, 30], [30, 100], [100, 400]]


# =============================================================================== pallets


def _pallet(a, cx=0.0, cy=0.0, z0=0.0, lods=ALL):
    """EUR pallet 1.20 x 0.80 x 0.144 m: 5 top boards, 3 stringer boards, 9 blocks, 3
    bottom boards. LOD1/2 collapse to one slab."""
    for i in range(5):
        y = cy - 0.4 + 0.05 + i * (0.7 / 4)
        a.box((1.2, 0.10, 0.022), (cx, y, z0 + 0.133), "Timber", L0)
    for y in (cy - 0.35, cy, cy + 0.35):
        a.box((1.2, 0.10, 0.022), (cx, y, z0 + 0.111), "Timber", L0)
        for x in (cx - 0.55, cx, cx + 0.55):
            a.box((0.10, 0.10, 0.078), (x, y, z0 + 0.061), "Timber_Dark", L0)
        a.box((1.2, 0.10, 0.022), (cx, y, z0 + 0.011), "Timber", L0)
    a.box((1.2, 0.8, 0.144), (cx, cy, z0 + 0.072), "Timber", tuple(l for l in lods if l > 0))


def pallet(A):
    a = A.Asset("pallet_euro", "prop", "EUR pallet", "Logistics", "EUR / EPAL pallet 1.20 x 0.80 x 0.144 m.")
    _pallet(a)
    a.col_box((1.2, 0.8, 0.144), (0, 0, 0.072))
    a.lod_ranges = SMALL
    return a


def _crate(a, c, size, mat_panel="Plywood", mat_frame="Timber", lods=ALL, stencil=False):
    """Wooden crate with corner battens and two bands."""
    sx, sy, sz = size
    cx, cy, cz = c
    a.box(size, (cx, cy, cz + sz / 2), mat_panel, lods)
    for dx in (-1, 1):
        for dy in (-1, 1):
            a.box((0.05, 0.05, sz + 0.01), (cx + dx * (sx / 2 - 0.02), cy + dy * (sy / 2 - 0.02), cz + sz / 2), mat_frame, L0)
    for z in (0.15 * sz, 0.85 * sz):
        a.box((sx + 0.012, sy + 0.012, 0.05), (cx, cy, cz + z), mat_frame, L0)


def supply_crate_stack(A):
    """Palletised supply load: four wooden crates on a EUR pallet, strapped."""
    a = A.Asset("supply_pallet", "prop", "Supply pallet", "Logistics", "EUR pallet with four strapped wooden supply crates (1.2 x 0.8 x 1.1 m).")
    _pallet(a)
    for i, (x, y) in enumerate(((-0.3, -0.2), (0.3, -0.2), (-0.3, 0.2), (0.3, 0.2))):
        _crate(a, (x, y, 0.144), (0.58, 0.38, 0.45), lods=(0, 1))
    _crate(a, (0, 0, 0.594), (1.0, 0.70, 0.45), lods=(0, 1))
    a.box((1.2, 0.8, 0.90), (0, 0, 0.594), "Plywood", L2)
    for x in (-0.25, 0.25):
        a.box((0.05, 0.82, 0.005), (x, 0, 1.046), "Paint_Black", L0)
        for sy in (-1, 1):
            a.box((0.05, 0.005, 0.90), (x, sy * 0.405, 0.6), "Paint_Black", L0)
    a.col_box((1.2, 0.8, 1.05), (0, 0, 0.525))
    a.marker("IP_Forks", (0, 1.5, 0), 180, "forklift / pallet jack entry side")
    a.lod_ranges = SMALL
    return a


def crate_large(A):
    a = A.Asset("crate_large", "prop", "Wooden crate (large)", "Logistics", "Wooden equipment crate 1.20 x 0.80 x 0.80 m on skids.")
    for y in (-0.3, 0.3):
        a.box((1.2, 0.10, 0.10), (0, y, 0.05), "Timber_Dark", ALL)
    _crate(a, (0, 0, 0.10), (1.2, 0.8, 0.80))
    a.sign([(0, 0), (1, 0), (1, 1), (0, 1)], (0, 0.405, 0.52), (-1, 0, 0), (0, 0, 1), 0.5, 0.25, S.rect("number_plate"), lods=L0)
    a.col_box((1.2, 0.8, 0.9), (0, 0, 0.45))
    a.lod_ranges = SMALL
    return a


# =============================================================================== ammunition


def ammo_can(A):
    """M2A1-type 50 cal ammunition can 0.305 x 0.155 x 0.19 m (+ handle)."""
    a = A.Asset("ammo_can", "prop", "Ammunition can", "Ammunition", "Steel ammunition can (M2A1 type) 0.305 x 0.155 x 0.19 m.")
    a.box((0.305, 0.155, 0.17), (0, 0, 0.085), "Paint_OD", ALL, bevel=0.006)
    a.box((0.31, 0.16, 0.025), (0, 0, 0.18), "Paint_OD", L01, bevel=0.004)
    a.box((0.12, 0.02, 0.012), (0, 0, 0.198), "Steel_Dark", L0)
    a.box((0.03, 0.02, 0.06), (0.135, 0, 0.16), "Steel_Dark", L0)
    a.col_box((0.31, 0.16, 0.2), (0, 0, 0.1))
    a.lod_ranges = TINY
    return a


def ammo_box_wood(A):
    """Wooden ammunition box (rifle cartridges / grenades) 0.60 x 0.30 x 0.25 m, painted
    olive, rope handles."""
    a = A.Asset("ammo_box_wood", "prop", "Ammunition box (wooden)", "Ammunition", "Painted wooden ammunition box 0.60 x 0.30 x 0.25 m with rope handles.")
    _crate(a, (0, 0, 0), (0.60, 0.30, 0.25), mat_panel="Paint_OD", mat_frame="Paint_OD")
    for sx in (-1, 1):
        a.tube([(sx * 0.302, -0.06, 0.16), (sx * 0.33, 0.0, 0.14), (sx * 0.302, 0.06, 0.16)], 0.008, "Canvas_Tan", L0, segs=5)
    a.sign([(0, 0), (1, 0), (1, 1), (0, 1)], (0, 0.152, 0.13), (-1, 0, 0), (0, 0, 1), 0.16, 0.16, S.rect("explosive"), lods=L0)
    a.col_box((0.6, 0.3, 0.25), (0, 0, 0.125))
    a.lod_ranges = TINY
    return a


def ammo_pallet(A):
    a = A.Asset("ammo_pallet", "prop", "Ammunition pallet", "Ammunition", "EUR pallet with 3 x 4 x 2 wooden ammunition boxes, strapped (1.2 x 0.8 x 0.66 m).")
    _pallet(a)
    for k in range(2):
        for i in range(2):
            for j in range(2):
                _crate(a, (-0.3 + i * 0.6, -0.2 + j * 0.4 + 0.0, 0.144 + k * 0.255), (0.58, 0.38, 0.25), "Paint_OD", "Paint_OD", lods=(0, 1))
    a.box((1.2, 0.8, 0.51), (0, 0, 0.144 + 0.255), "Paint_OD", L2)
    for x in (-0.3, 0.3):
        for sy in (-1, 1):
            a.box((0.05, 0.005, 0.52), (x, sy * 0.405, 0.40), "Paint_Black", L0)
    a.sign([(0, 0), (1, 0), (1, 1), (0, 1)], (0.3, 0.408, 0.40), (-1, 0, 0), (0, 0, 1), 0.2, 0.2, S.rect("explosive"), lods=L01)
    a.col_box((1.2, 0.8, 0.66), (0, 0, 0.33))
    a.lod_ranges = SMALL
    return a


# =============================================================================== fuel


def jerrycan(A):
    """NATO 20 l jerrycan 0.345 x 0.165 x 0.47 m: X-pressing, triple handle, spout."""
    a = A.Asset("jerrycan", "prop", "Jerrycan 20 l", "Fuel", "NATO pattern 20 l steel jerrycan 0.345 x 0.165 x 0.47 m.")
    a.box((0.345, 0.165, 0.43), (0, 0, 0.215), "Paint_Green", ALL, bevel=0.012)
    for sy in (-1, 1):
        a.box((0.40, 0.012, 0.025), (0, sy * 0.083, 0.215), "Paint_Green", L0, rot=A.rot_y(48))
        a.box((0.40, 0.012, 0.025), (0, sy * 0.083, 0.215), "Paint_Green", L0, rot=A.rot_y(-48))
    for x in (-0.09, 0.0, 0.09):
        a.box((0.025, 0.06, 0.04), (x, 0, 0.45), "Paint_Green", L0)
    a.box((0.30, 0.06, 0.012), (0, 0, 0.474), "Paint_Green", L0)
    a.cyl(0.025, 0.025, 0.05, (0.13, 0, 0.45), "Steel_Dark", L0, axis=(0.7, 0, 0.7), segs=8)
    a.col_box((0.345, 0.165, 0.47), (0, 0, 0.235))
    a.lod_ranges = TINY
    return a


def fuel_drum(A, aid="fuel_drum", mat="Paint_Green", name="Fuel drum 200 l"):
    """Steel 200 l drum, diameter 0.585 m, height 0.88 m: two rolling hoops, chimes, bungs."""
    a = A.Asset(aid, "prop", name, "Fuel", "Steel 200 l drum, diameter 0.585 m, height 0.88 m.")
    a.cyl(0.2925, 0.2925, 0.88, (0, 0, 0.44), mat, ALL, segs=24)
    for z in (0.29, 0.59):
        a.cyl(0.299, 0.299, 0.03, (0, 0, z), mat, L01, segs=24)
    for z in (0.01, 0.87):
        a.cyl(0.300, 0.300, 0.02, (0, 0, z), mat, L0, segs=24)
    a.cyl(0.03, 0.03, 0.02, (0.17, 0.05, 0.885), "Steel_Dark", L0, segs=8)
    a.cyl(0.02, 0.02, 0.02, (-0.17, 0.05, 0.885), "Steel_Dark", L0, segs=8)
    a.col_box((0.6, 0.6, 0.88), (0, 0, 0.44))
    a.lod_ranges = SMALL
    return a


def drum_pallet(A):
    a = A.Asset("drum_pallet", "prop", "Fuel drums on pallet", "Fuel", "Four 200 l drums on a 1.2 x 1.2 m pallet with a hazard placard.")
    a.box((1.22, 1.22, 0.144), (0, 0, 0.072), "Timber", ALL)
    for i, (x, y) in enumerate(((-0.3, -0.3), (0.3, -0.3), (-0.3, 0.3), (0.3, 0.3))):
        mat = "Paint_Green" if i != 2 else "Paint_Red"
        a.cyl(0.2925, 0.2925, 0.88, (x, y, 0.584), mat, ALL, segs=20)
        for z in (0.29, 0.59):
            a.cyl(0.299, 0.299, 0.03, (x, y, 0.144 + z), mat, L0, segs=20)
    a.sign([(0, 0), (1, 0), (1, 1), (0, 1)], (0, 0.612, 0.30), (-1, 0, 0), (0, 0, 1), 0.25, 0.25, S.rect("flammable"), lods=L01)
    a.col_box((1.22, 1.22, 1.03), (0, 0, 0.515))
    a.lod_ranges = SMALL
    return a


def fuel_tank_skid(A):
    """10 000 l skid-mounted fuel tank 4.2 x 2.0 m: horizontal tank on saddles with a
    catwalk ladder, dispenser pump cabinet, hose reel, placards and earth spike."""
    a = A.Asset("fuel_tank_skid", "prop", "Fuel tank 10 000 l", "Fuel",
                "Skid-mounted 10 000 l fuel tank (diameter 1.8 m, 4.2 m long) with dispensing pump, hose reel and hazard placards.")
    a.box((4.4, 2.0, 0.20), (0, 0, 0.10), "Steel_Dark", ALL)
    for x in (-1.4, 1.4):
        a.box((0.25, 1.7, 0.55), (x, 0, 0.45), "Paint_OD", L01)
    a.cyl(0.9, 0.9, 4.0, (0, 0, 1.25), "Paint_OD", ALL, axis=(1, 0, 0), segs=24)
    for sx in (-1, 1):
        a.cyl(0.92, 0.92, 0.06, (sx * 2.0, 0, 1.25), "Paint_OD", L0, axis=(1, 0, 0), segs=24)
    a.cyl(0.25, 0.25, 0.12, (0.8, 0, 2.16), "Paint_OD", L01, segs=14)
    a.cyl(0.05, 0.05, 0.4, (-1.0, 0, 2.30), "Steel_Galv", L0, segs=8)
    # Ladder and top handrail.
    for sy in (-0.2, 0.2):
        a.cyl_between((-2.3, sy + 0.95, 0.2), (-1.9, sy + 0.95, 2.2), 0.02, "Steel_Galv", L0, segs=6)
    for k in range(6):
        t = (k + 0.5) / 6
        a.cyl_between((-2.3 + 0.4 * t, 0.75, 0.2 + 2.0 * t), (-2.3 + 0.4 * t, 1.15, 0.2 + 2.0 * t), 0.015, "Steel_Galv", L0, segs=5)
    for sy in (-0.35, 0.35):
        a.cyl(0.02, 0.02, 2.6, (0.0, sy, 3.0), "Paint_Yellow", L0, axis=(1, 0, 0), segs=6)
        for x in (-1.2, 0.0, 1.2):
            a.cyl(0.02, 0.02, 0.9, (x, sy, 2.6), "Paint_Yellow", L0, segs=6)
    # Pump cabinet, hose reel, placards.
    a.box((0.8, 0.6, 1.1), (1.9, 0.85, 0.75), "Paint_Grey", L01, bevel=0.02)
    a.sign([(0, 0), (1, 0), (1, 1), (0, 1)], (1.9, 1.152, 0.9), (-1, 0, 0), (0, 0, 1), 0.4, 0.4, S.rect("gauge_dial"), lods=L0)
    a.cyl(0.35, 0.35, 0.30, (1.0, 1.05, 0.65), "Plastic_Black", L01, axis=(0, 1, 0), segs=16)
    for sx in (-1, 1):
        a.sign([(0, 0), (1, 0), (1, 1), (0, 1)], (sx * 1.0, 0.905, 1.4), (-1, 0, 0), (0, 0, 1), 0.45, 0.45, S.rect("flammable"), lods=L01)
    a.sign([(0, 0), (1, 0), (1, 1), (0, 1)], (0, -0.905, 1.4), (1, 0, 0), (0, 0, 1), 0.45, 0.45, S.rect("no_smoking"), lods=L01)
    a.col_box((4.4, 2.0, 2.2), (0, 0, 1.1))
    a.marker("IP_Dispense", (1.9, 1.8, 0), 180, "fuel dispensing point")
    a.marker("VEH_Refuel", (0, 5.0, 0), 180, "vehicle refuels here")
    a.lod_ranges = MEDIUM
    a.meta["capacity_l"] = 10000
    return a


# =============================================================================== power and light


def generator_skid(A, aid="generator_60kw", mat="Paint_OD", name="Generator 60 kW"):
    """Skid-mounted 60 kW diesel generator in a sound-attenuated enclosure 2.6 x 1.1 x 1.5 m:
    louvres, service doors, control panel, exhaust stack, lifting eyes, fuel base tank."""
    a = A.Asset(aid, "prop", name, "Power", "Skid-mounted 60 kW diesel generator set, enclosure 2.6 x 1.1 x 1.5 m on a base fuel tank.")
    a.box((2.7, 1.15, 0.30), (0, 0, 0.15), "Steel_Dark", ALL)
    a.box((2.6, 1.10, 1.25), (0, 0, 0.925), mat, ALL, bevel=0.02)
    a.box((2.62, 1.12, 0.06), (0, 0, 1.58), mat, L01)
    for sy, yaw in ((1, 0), (-1, 180)):
        F = Frame((0, sy * 0.55, 0.30), yaw)
        F.sign(a, "vent_grille", -0.85 * sy, 0.65, 0.6, 0.7, y=0.006, lods=L01)
        F.sign(a, "vent_grille", 0.85 * sy, 0.65, 0.6, 0.7, y=0.006, lods=L01)
        for x in (-0.3, 0.3):
            F.box(a, (0.02, 0.02, 0.05), x, 0.01, 0.65, "Steel_Dark", L0)
    Fx = Frame((1.3, 0, 0.30), -90)
    Fx.sign(a, "gauge_dial", -0.25, 0.75, 0.3, 0.3, lods=L0)
    Fx.box(a, (0.5, 0.02, 0.4), 0.2, 0.01, 0.75, "Paint_Black", L0)
    a.cyl(0.06, 0.06, 0.5, (-0.9, 0.25, 1.85), "Steel_Dark", L01, segs=10)
    a.cyl(0.07, 0.07, 0.06, (-0.9, 0.25, 2.1), "Steel_Dark", L0, segs=10)
    for x in (-1.0, 1.0):
        a.tube([(x - 0.06, 0, 1.6), (x, 0, 1.68), (x + 0.06, 0, 1.6)], 0.015, "Steel_Dark", L0, segs=5)
    a.col_box((2.7, 1.15, 1.6), (0, 0, 0.8))
    a.marker("IP_Panel", (2.0, 0, 0), 90, "control panel / power outlet")
    a.lod_ranges = MEDIUM
    a.meta["power_kw"] = 60
    return a


def light_tower(A):
    """Mobile light tower on a single-axle trailer: outriggers down, 9 m mast raised,
    4 LED floodlights, generator cabinet."""
    a = A.Asset("light_tower", "prop", "Mobile light tower", "Power", "Trailer light tower 2.6 x 1.4 m, mast raised to 9.0 m, four LED floodlights.")
    a.box((2.4, 1.3, 1.2), (0, 0, 0.95), "Paint_Yellow", ALL, bevel=0.03)
    a.box((2.2, 1.0, 0.12), (0, 0, 0.32), "Steel_Dark", L01)
    for sy in (-1, 1):
        a.cyl(0.30, 0.30, 0.20, (0, sy * 0.72, 0.30), "Rubber", ALL, axis=(0, 1, 0), segs=14)
        a.cyl(0.18, 0.18, 0.21, (0, sy * 0.72, 0.30), "Steel_Dark", L0, axis=(0, 1, 0), segs=10)
    a.box((1.3, 0.08, 0.08), (1.8, 0, 0.45), "Steel_Dark", L01)
    for sx in (-1, 1):
        for sy in (-1, 1):
            a.cyl_between((sx * 1.0, sy * 0.6, 0.6), (sx * 1.35, sy * 1.1, 0.05), 0.04, "Paint_Yellow", L01, segs=6)
            a.box((0.18, 0.18, 0.03), (sx * 1.35, sy * 1.1, 0.02), "Steel_Dark", L0)
    a.cyl(0.08, 0.05, 7.6, (-0.8, 0, 5.3), "Steel_Galv", ALL, segs=10)
    a.box((1.4, 0.10, 0.10), (-0.8, 0, 9.05), "Steel_Dark", L01)
    for x in (-0.55, -0.2):
        for s in (-1, 1):
            xx = -0.8 + s * (0.35 if x == -0.55 else 0.12) * 2
            a.box((0.32, 0.12, 0.26), (xx, 0.08, 9.2 if x == -0.55 else 8.9), "Paint_Grey", L01, rot=A.rot_x(-15))
            a.box((0.28, 0.01, 0.22), (xx, 0.145, 9.2 if x == -0.55 else 8.9), "Lamp", L01, rot=A.rot_x(-15))
    a.col_box((2.4, 1.3, 1.5), (0, 0, 0.75))
    a.col_box((0.2, 0.2, 7.6), (-0.8, 0, 5.3))
    a.lod_ranges = [[0, 40], [40, 160], [160, 1200]]
    return a


def light_pole(A):
    """8 m street light pole on a concrete footing with an LED head."""
    a = A.Asset("light_pole", "prop", "Light pole 8 m", "Power", "Galvanized 8 m light pole on a concrete footing, 1.2 m arm with LED luminaire.")
    a.cyl(0.25, 0.25, 0.50, (0, 0, 0.0), "Concrete", ALL, segs=12)
    a.box((0.30, 0.30, 0.02), (0, 0, 0.26), "Steel_Galv", L0)
    a.cyl(0.085, 0.045, 7.8, (0, 0, 4.15), "Steel_Galv", ALL, segs=10)
    a.cyl_between((0, 0, 7.9), (0, 1.2, 8.1), 0.03, "Steel_Galv", L01, segs=6)
    a.box((0.25, 0.55, 0.08), (0, 1.35, 8.08), "Paint_Grey", L01, bevel=0.02)
    a.box((0.20, 0.45, 0.01), (0, 1.35, 8.035), "Lamp", L01)
    a.box((0.10, 0.12, 0.30), (0, 0.09, 1.0), "Paint_Grey", L0)
    a.col_box((0.2, 0.2, 8.0), (0, 0, 4.0))
    a.foundation = 0.25
    a.lod_ranges = [[0, 40], [40, 160], [160, 1200]]
    return a


def radio_mast(A):
    """12 m telescopic radio mast: three sections on a tripod base, two guy levels,
    whip antennas and a feed cable."""
    a = A.Asset("radio_mast", "prop", "Telescopic radio mast 12 m", "Communications",
                "Field telescopic mast 12 m (three sections) on a tripod, guyed at 6 and 11 m, three whip antennas.")
    for i, (r, z0, z1) in enumerate(((0.06, 0.0, 5.0), (0.045, 4.8, 8.8), (0.032, 8.6, 12.0))):
        a.cyl(r, r, z1 - z0, (0, 0, (z0 + z1) / 2), "Paint_OD", ALL, segs=10)
    for k in range(3):
        ang = math.radians(90 + 120 * k)
        a.cyl_between((0, 0, 0.9), (0.9 * math.cos(ang), 0.9 * math.sin(ang), 0.02), 0.025, "Paint_OD", L01, segs=6)
    for z, rad in ((6.0, 4.5), (11.0, 6.5)):
        K.guy_wires(a, 0, 0, z, rad, 3, 30.0)
    for k, ln in enumerate((2.4, 1.6, 1.2)):
        ang = math.radians(120 * k)
        a.cyl_between((0, 0, 11.9), (0.35 * math.cos(ang), 0.35 * math.sin(ang), 11.95), 0.012, "Steel_Dark", L0, segs=5)
        K.whip(a, 0.35 * math.cos(ang), 0.35 * math.sin(ang), 11.95, ln)
    a.tube([(0.05, 0, 11.8), (0.08, 0.02, 6.0), (0.3, 0.3, 0.05), (1.5, 0.8, 0.02)], 0.01, "Plastic_Black", L0, segs=5)
    a.col_box((0.2, 0.2, 12.0), (0, 0, 6.0))
    a.lod_ranges = [[0, 50], [50, 200], [200, 1500]]
    return a


# =============================================================================== shelters


def tent(A, aid, W, D, name, mat="Canvas_OD"):
    """Frame tent (ridge along Y): canvas roof and walls, end doors with a rolled flap,
    side windows with flaps, guy lines and stakes."""
    a = A.Asset(aid, "prop", name, "Shelter", "Military frame tent %.1f x %.1f m, eaves 1.8 m, ridge %.1f m." % (W, D, 1.8 + W / 2 * 0.45))
    eave = 1.8
    rise = W / 2 * 0.45
    a.box_between((-W / 2, -D / 2, 0.0), (W / 2, D / 2, eave), mat)
    prof = [(-W / 2 - 0.25, -0.10), (0, rise), (W / 2 + 0.25, -0.10), (W / 2 + 0.25, -0.07), (0, rise + 0.03), (-W / 2 - 0.25, -0.07)]
    a.prism(prof, (0, -D / 2 - 0.15, eave), (0, D / 2 + 0.15, eave), mat)
    a.prism([(-W / 2, 0), (W / 2, 0), (0, rise)], (0, -D / 2, eave), (0, D / 2, eave), mat)
    for sy, yaw in ((1, 0), (-1, 180)):
        F = Frame((0, sy * D / 2, 0), yaw)
        F.box(a, (1.4, 0.02, 1.9), 0, 0.012, 0.95, "Paint_Black", L01)
        F.cyl(a, 0.10, 1.5, 0, 0.12, 2.0, mat, "x", L0, segs=10)
    for x, yaw in ((W / 2, -90), (-W / 2, 90)):
        F = Frame((x, 0, 0), yaw)
        for wx in [-(D / 4), D / 4]:
            F.box(a, (0.8, 0.015, 0.5), wx, 0.01, 1.25, "Glass", L0)
            F.cyl(a, 0.06, 0.9, wx, 0.06, 1.55, mat, "x", L0, segs=8)
    # Guy lines and stakes along both sides.
    for sx in (-1, 1):
        for y in [(-D / 2) + i * D / 3 for i in range(4)]:
            a.tube([(sx * (W / 2 + 0.25), y, eave - 0.10), (sx * (W / 2 + 1.3), y, 0.02)], 0.006, "Canvas_Tan", L0, segs=4, cap=False)
            a.cyl(0.015, 0.015, 0.25, (sx * (W / 2 + 1.3), y, 0.05), "Steel_Dark", L0, segs=5)
    a.col_box((W, D, eave + rise), (0, 0, (eave + rise) / 2))
    a.marker("IP_Door_N", (0, D / 2 + 1.2, 0), 180)
    a.marker("IP_Door_S", (0, -D / 2 - 1.2, 0), 0)
    a.lod_ranges = MEDIUM
    a.structure = {"category": "Shelter", "max_slope_deg": 8.0, "max_ground_gap": 0.3, "blocks_navigation": True}
    return a


def camo_net_canopy(A):
    """Garnished camouflage net 8 x 8 m on four corner poles and a central spreader."""
    a = A.Asset("camo_net_canopy", "prop", "Camouflage net canopy", "Shelter", "Woodland camouflage net 8 x 8 m on four 2.6 m poles and a 3.2 m centre pole.")
    n = 8
    S8 = 8.0
    verts, faces = [], []
    for j in range(n + 1):
        for i in range(n + 1):
            x = -S8 / 2 + i * S8 / n
            y = -S8 / 2 + j * S8 / n
            r = max(abs(x), abs(y)) / (S8 / 2)
            z = 3.2 - 0.6 * r ** 1.3 - 0.15 * math.sin(i * 1.7 + j * 2.3) * (1 - r)
            verts.append((x, y, z))
    for j in range(n):
        for i in range(n):
            k = j * (n + 1) + i
            faces.append((k, k + 1, k + n + 2, k + n + 1))
    a.poly(verts, faces, "Camo_Net", ALL)
    for sx in (-1, 1):
        for sy in (-1, 1):
            a.cyl(0.025, 0.025, 2.6, (sx * 3.9, sy * 3.9, 1.3), "Steel_Dark", L01, segs=6)
            a.tube([(sx * 3.95, sy * 3.95, 2.55), (sx * 5.0, sy * 5.0, 0.02)], 0.005, "Canvas_Tan", L0, segs=4, cap=False)
    a.cyl(0.03, 0.03, 3.2, (0, 0, 1.6), "Steel_Dark", L01, segs=6)
    a.marker("ATT_Under", (0, 0, 0), 0, "vehicle / equipment parks under the net")
    a.lod_ranges = MEDIUM
    return a


def ibc_tank(A):
    a = A.Asset("ibc_tank", "prop", "IBC water tank 1000 l", "Logistics", "1000 l intermediate bulk container 1.2 x 1.0 x 1.16 m (water).")
    a.box((1.2, 1.0, 0.15), (0, 0, 0.075), "Steel_Dark", ALL)
    a.box((1.12, 0.94, 0.95), (0, 0, 0.64), "Plastic_White", ALL, bevel=0.05)
    for x in (-0.6, -0.3, 0.0, 0.3, 0.6):
        for sy in (-1, 1):
            a.cyl(0.01, 0.01, 1.0, (x, sy * 0.5, 0.65), "Steel_Galv", L0, segs=4)
    for z in (0.4, 0.8, 1.15):
        for sy in (-1, 1):
            a.cyl(0.01, 0.01, 1.2, (0, sy * 0.5, z), "Steel_Galv", L0, axis=(1, 0, 0), segs=4)
        for sx in (-1, 1):
            a.cyl(0.01, 0.01, 1.0, (sx * 0.6, 0, z), "Steel_Galv", L0, axis=(0, 1, 0), segs=4)
    a.cyl(0.08, 0.08, 0.05, (0, 0, 1.14), "Plastic_Black", L0, segs=10)
    a.cyl(0.04, 0.04, 0.12, (0, 0.52, 0.22), "Plastic_Black", L0, axis=(0, 1, 0), segs=8)
    a.col_box((1.2, 1.0, 1.16), (0, 0, 0.58))
    a.lod_ranges = SMALL
    return a


def field_toilet(A):
    a = A.Asset("field_toilet", "prop", "Field toilet", "Shelter", "Portable toilet cabin 1.1 x 1.1 x 2.3 m.")
    a.box((1.1, 1.1, 0.12), (0, 0, 0.06), "Plastic_OD", ALL)
    a.box((1.06, 1.06, 2.05), (0, 0, 1.145), "Plastic_OD", ALL, bevel=0.03)
    a.box((1.12, 1.12, 0.12), (0, 0, 2.22), "Plastic_White", L01, bevel=0.03)
    F = Frame((0, 0.53, 0.12), 0)
    F.box(a, (0.80, 0.03, 1.90), 0, 0.01, 1.02, "Plastic_OD", L01)
    F.box(a, (0.10, 0.03, 0.04), 0.3, 0.035, 1.05, "Plastic_Black", L0)
    a.cyl(0.05, 0.05, 0.4, (-0.35, -0.35, 2.45), "Plastic_Black", L0, segs=8)
    a.col_box((1.1, 1.1, 2.3), (0, 0, 1.15))
    a.marker("IP_Door", (0, 1.2, 0), 180)
    a.lod_ranges = SMALL
    return a


# =============================================================================== signs


def road_sign(A, aid, sign, name, shape="circle", size=0.6, h=2.2):
    """Road / base sign on a galvanized post (plate front +Y)."""
    a = A.Asset(aid, "prop", name, "Signs", "%s on a 60 mm galvanized post, plate %.2f m, lower edge %.1f m." % (name, size, h - size / 2))
    a.cyl(0.03, 0.03, h + 0.5, (0, 0, (h - 0.5) / 2), "Steel_Galv", ALL, segs=8)
    pts = {"circle": A.circle01(24), "rect": A.RECT01, "oct": A.ngon01(8, math.pi / 8), "tri": A.TRI_UP01,
           "tri_down": A.TRI_DOWN01, "diamond": A.ngon01(4, math.pi / 2), "wide": A.RECT01}[shape]
    w = size * (2.0 if shape == "wide" else 1.0)
    if shape == "wide":
        pts = A.RECT01
    hh = size
    a.sign(pts, (0, 0.04, h), (-1, 0, 0), (0, 0, 1), w, hh, S.rect(sign), lods=ALL, back_mat="Steel_Galv", thick=0.012)
    for z in (h - hh * 0.3, h + hh * 0.3):
        a.box((0.06, 0.03, 0.04), (0, 0.02, z), "Steel_Galv", L0)
    a.col_box((0.08, 0.08, h), (0, 0, h / 2))
    a.foundation = 0.5
    a.lod_ranges = SMALL
    return a


BUILDERS = {
    "pallet_euro": pallet,
    "supply_pallet": supply_crate_stack,
    "crate_large": crate_large,
    "ammo_can": ammo_can,
    "ammo_box_wood": ammo_box_wood,
    "ammo_pallet": ammo_pallet,
    "jerrycan": jerrycan,
    "fuel_drum": fuel_drum,
    "fuel_drum_red": lambda A: fuel_drum(A, "fuel_drum_red", "Paint_Red", "Fuel drum 200 l (red)"),
    "drum_pallet": drum_pallet,
    "fuel_tank_skid": fuel_tank_skid,
    "generator_60kw": generator_skid,
    "generator_60kw_tan": lambda A: generator_skid(A, "generator_60kw_tan", "Paint_Tan", "Generator 60 kW (tan)"),
    "light_tower": light_tower,
    "light_pole": light_pole,
    "radio_mast": radio_mast,
    "tent_frame_6x4": lambda A: tent(A, "tent_frame_6x4", 4.5, 6.0, "Frame tent 6 x 4.5 m"),
    "tent_frame_10x6": lambda A: tent(A, "tent_frame_10x6", 6.0, 10.0, "Frame tent 10 x 6 m", "Canvas_Tan"),
    "camo_net_canopy": camo_net_canopy,
    "ibc_tank": ibc_tank,
    "field_toilet": field_toilet,
    "sign_stop": lambda A: road_sign(A, "sign_stop", "stop", "Stop sign", "oct", 0.75),
    "sign_yield": lambda A: road_sign(A, "sign_yield", "yield", "Give way sign", "tri_down", 0.9),
    "sign_no_entry": lambda A: road_sign(A, "sign_no_entry", "no_entry", "No entry sign", "circle", 0.6),
    "sign_speed_30": lambda A: road_sign(A, "sign_speed_30", "speed_30", "Speed limit 30", "circle", 0.6),
    "sign_speed_15": lambda A: road_sign(A, "sign_speed_15", "speed_15", "Speed limit 15", "circle", 0.6),
    "sign_warning": lambda A: road_sign(A, "sign_warning", "warning", "Danger sign", "tri", 0.9),
    "sign_restricted": lambda A: road_sign(A, "sign_restricted", "restricted", "Restricted area sign", "wide", 0.6),
    "sign_checkpoint": lambda A: road_sign(A, "sign_checkpoint", "checkpoint", "Checkpoint sign", "wide", 0.7),
}
