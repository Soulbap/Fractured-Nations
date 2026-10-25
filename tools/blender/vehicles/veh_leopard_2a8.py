"""VEH-05 Leopard 2A8 NOR, Norwegian main battle tank (KNDS, 54 ordered 2023, first delivered
April 2026): 2A8 hull and turret (arrowhead wedge armour, 120 mm L55A1, EuroTrophy APS),
Norwegian lightweight side skirts with containers for winter grousers.

Reference: assets/military/vehicles/_references/leopard_2a8_nor/ (notes.md, manifest.json).
Dimensions used (milmag.pl / army-technology): hull 8.05 m, 11.17 m with the gun forward,
width 3.8 m, turret roof 2.72 m, 3.13 m to the commander's periscope. Running gear per
Leopard 2: 7 dual road wheels (~0.70 m), front idler, rear sprocket, 4 return rollers,
635 mm double-pin tracks. The remote weapon station type of the Norwegian tanks is not
confirmed in the sources found: a Protector-type RWS on the loader's side stands in for the
German FLW 200 and is marked as an estimate.
"""
import math

from mathutils import Vector

import ap_lib as A
import ap_vehicle as V
import veh_kit as K

ALL, L01, L0, L12, L2 = A.ALL, A.L01, A.L0, A.L12, A.L2

ID = "leopard_2a8_nor"
PAINT = "Camo_NATO3"

LEN = 8.05
YF, YR = LEN / 2, -LEN / 2
HW_LOW = 1.18
HW_SP = 1.80
HW_SKIRT = 1.90
DECK = 1.76
TRACK_X = 1.53
TRACK_W = 0.635
RW_R = 0.35
RW_Y = [2.62 - 0.84 * k for k in range(7)]
IDLER = (3.48, 0.66, 0.32)
SPROCKET = (-3.38, 0.72, 0.33)
ROLLERS = [(2.18, 1.10, 0.09), (0.85, 1.10, 0.09), (-0.50, 1.10, 0.09), (-1.85, 1.10, 0.09)]
RING = (0.0, 0.25, DECK)
MUZZLE_Y = 11.17 - LEN / 2


def hull_half(bottom, top, sp_top=None):
    st = sp_top if sp_top is not None else top - 0.05
    return [(0.0, bottom), (HW_LOW, bottom), (HW_LOW, 1.07), (HW_SP, 1.10), (HW_SP, st), (HW_SP - 0.06, top), (0.0, top)]


def turret_layers():
    """Plan outlines (right half, front centre -> rear centre) of the 2A8 turret at several
    heights: arrowhead wedges either side of the mantlet, vertical sides, bustle."""
    def lay(z, s_tip, y_tip, x_c, y_c, x_s, y_back, x_b, y_b, y_end, y_rec):
        return (z, [(0.0, y_rec), (0.44, y_tip), (x_c, y_c), (x_s, y_c - 0.18), (x_s, y_back), (x_b, y_b), (x_b - 0.25, y_end), (0.0, y_end - 0.02)])
    return [
        lay(1.84, 0, 2.55, 1.58, 1.40, 1.64, -1.20, 1.52, -1.90, -2.08, 2.25),
        lay(2.30, 0, 3.02, 1.76, 1.58, 1.80, -1.32, 1.66, -2.06, -2.30, 2.62),
        lay(2.64, 0, 2.70, 1.70, 1.42, 1.76, -1.32, 1.62, -2.02, -2.26, 2.40),
        lay(2.72, 0, 2.52, 1.62, 1.34, 1.68, -1.30, 1.56, -1.98, -2.20, 2.30),
    ]


def build():
    veh = V.VehicleAsset(ID, "Leopard 2A8 NOR", "Main battle tank",
                         "Leopard 2A8 NOR main battle tank (Norway): 120 mm L55A1, EuroTrophy APS, lightweight Norwegian skirts.")
    b = veh.part("Body", note="hull")
    sh = veh.shell("Body")
    # ------------------------------------------------------------ hull
    with V.bevel(sh, 0.025, lods=(0, 1)):
        st = [
            (YF, [(0.0, 0.98), (HW_LOW, 0.98), (HW_LOW, 1.05), (HW_SP, 1.07), (HW_SP, 1.22), (HW_SP - 0.05, 1.25), (0.0, 1.25)]),
            (3.62, hull_half(0.52, 1.50, 1.46)),
            (3.10, hull_half(0.50, 1.70)),
            (2.60, hull_half(0.50, DECK)),
            (YR + 0.12, hull_half(0.50, DECK)),
            (YR, hull_half(0.70, DECK - 0.06, DECK - 0.12)),
        ]
        V.hull_loft(sh, st, PAINT, ALL)

    def driver(tmp):
        tmp.box((0.80, 1.00, 0.80), (-0.62, 2.40, 1.30), "Paint_White", (0,))
    veh.cut(sh, driver, "Paint_White")
    K.opening(sh, [(-0.88, 2.30, DECK), (-0.36, 2.30, DECK), (-0.36, 2.80, DECK), (-0.88, 2.80, DECK)], (0, 0, 1), depth=0.20, out=0.15)
    # add-on glacis armour module (2A7/2A8) and the driver's station
    with V.bevel(b, 0.02):
        b.loft([[(-1.15, 3.95, 1.26), (1.15, 3.95, 1.26), (1.15, 3.95, 1.33), (-1.15, 3.95, 1.33)],
                [(-1.25, 2.95, 1.73), (1.25, 2.95, 1.73), (1.25, 2.95, 1.83), (-1.25, 2.95, 1.83)]], PAINT, ALL, closed=True, cap=True, recalc=True)
    dh = veh.part("Hatch_Driver", parent="Body", pivot=(-0.62, 2.55, 1.84), axis="z", note="driver hatch (lifts and swings)")
    with V.bevel(dh, 0.012):
        dh.box((0.62, 0.62, 0.05), (-0.62, 2.55, 1.85), PAINT, ALL)
    for k in range(3):
        b.box((0.18, 0.07, 0.09), (-0.90 + k * 0.28, 2.88, 1.84), "Paint_Black", L0)
        b.box((0.15, 0.01, 0.06), (-0.90 + k * 0.28, 2.915, 1.845), "Glass", L0)
    # front fenders with headlight guards, tow hooks, plates
    for s in (-1, 1):
        with V.bevel(b, 0.012):
            b.box((0.62, 0.70, 0.05), (s * 1.55, 3.70, 1.22), PAINT, L01, rot=A.rot_x(-8))
        b.box((0.24, 0.20, 0.20), (s * 1.48, 3.62, 1.36), "Paint_Black", L01)
        K.lamp(b, (s * 1.48, 3.73, 1.36), (0, 1, 0), lods=L0, square=True, w=0.15, h=0.10, depth=0.03)
        K.tow_eye(b, (s * 0.85, YF - 0.04, 0.96), (0, 1, 0))
        K.shackle(b, (s * 0.85, YF + 0.02, 0.88), axis=(1, 0, 0), r=0.08)
    b.box((0.42, 0.02, 0.11), (0.0, YF + 0.005, 1.10), "Paint_Yellow", L0)
    # ------------------------------------------------------------ Norwegian lightweight skirts + grouser containers
    for s in (-1, 1):
        x = s * HW_SKIRT
        segs = [(3.80, 2.70), (2.65, 1.40), (1.35, 0.10), (0.05, -1.20), (-1.25, -2.50), (-2.55, -3.70)]
        for k, (y0, y1) in enumerate(segs):
            th = 0.10 if k == 0 else 0.05
            with V.bevel(b, 0.012):
                b.box((th, y0 - y1 - 0.03, 0.72), (x - s * th / 2, (y0 + y1) / 2, 1.38 if k else 1.30), PAINT, ALL)
            V.bolts(b, [(x + s * 0.005, yy, 1.62) for yy in (y0 - 0.15, y1 + 0.15)], (1, 0, 0), r=0.02)
            b.box((0.02, 0.18, 0.04), (x + s * 0.005, (y0 + y1) / 2, 1.08), "Paint_Black", L0)
        # winter grouser containers on the rear fenders
        for yc in (-1.85, -2.95):
            with V.bevel(b, 0.012):
                b.box((0.42, 0.95, 0.30), (s * 1.55, yc, DECK + 0.15), PAINT, L01)
            b.box((0.44, 0.04, 0.04), (s * 1.55, yc, DECK + 0.31), "Paint_Black", L0)
    # ------------------------------------------------------------ engine deck: grilles, access, rear plate
    with V.bevel(b, 0.01):
        b.box((2.30, 2.40, 0.05), (0.0, -2.55, DECK + 0.025), PAINT, L01)
    for k in range(16):
        b.box((2.10, 0.06, 0.035), (0.0, -1.55 - k * 0.135, DECK + 0.06), "Paint_Black", L0)
    for s in (-1, 1):
        V.handle(b, (s * 0.80, -1.40, DECK + 0.06), (s * 0.40, -1.40, DECK + 0.06), 0.06, (0, 0, 1), lods=L0)
        K.lamp(b, (s * 1.45, YR - 0.02, 1.45), (0, -1, 0), lods=L0, square=True, w=0.18, h=0.10, lens="Reflector_Red", depth=0.05)
        K.tow_eye(b, (s * 0.95, YR - 0.02, 0.95), (0, -1, 0))
        # exhaust louvres on the rear plate
        x0, x1 = sorted((s * 0.25, s * 1.15))
        V.slats(b, x0, x1, 1.10, 1.55, YR - 0.03, 7, 0.04, 0.03, "Paint_Black", L0,
                vertical=False, tilt=30)
        b.tube([(s * 1.20, -3.40, DECK + 0.05), (s * 0.20, -3.55, DECK + 0.05)], 0.025, "Steel_Dark", L0, segs=6)   # tow cables
    b.box((0.40, 0.25, 0.30), (0.0, YR + 0.12, 1.35), "Paint_Black", L0)          # infantry phone box
    # ------------------------------------------------------------ running gear (Diehl 570 double-pin steel track)
    K.road_wheel_template(veh, "RoadWheelLeo", RW_R, 0.56, gap=0.11, rim_mat="Paint_Green")
    K.road_wheel_template(veh, "IdlerLeo", IDLER[2], 0.50, gap=0.11, rim_mat="Paint_Green", tyre_mat="Steel_Dark")
    K.sprocket_template(veh, "SprocketLeo", SPROCKET[2], 0.56, 11, mat="Paint_Green")
    ro = veh.part("RollerLeo", local=True, note="template")
    ro.a.ao_strength = 0.0
    V.revolve(ro, [(0.0, -0.13), (0.09, -0.13), (0.09, -0.02), (0.07, -0.02), (0.07, 0.02), (0.09, 0.02), (0.09, 0.13), (0.0, 0.13)],
              (0, 0, 0), (1, 0, 0), "Rubber", ALL, segs=16, smooth=False)
    for side, s in (("L", -1), ("R", 1)):
        K.running_gear(veh, side, s * TRACK_X, RW_Y, RW_R, SPROCKET, IDLER, ROLLERS, TRACK_W, 0.184, link="steel",
                       rw_template="RoadWheelLeo", sp_template="SprocketLeo", id_template="IdlerLeo", ro_template="RollerLeo")
        for y in RW_Y:
            b.box((0.30, 0.50, 0.11), (s * (HW_LOW + 0.10), y - 0.24, RW_R + 0.16), "Paint_Black", L01, rot=A.rot_x(-14))
            b.cyl(0.10, 0.10, 0.10, (s * (HW_LOW + 0.04), y - 0.48, RW_R + 0.23), "Steel_Dark", L0, axis=(1, 0, 0), segs=10)
    # ------------------------------------------------------------ turret
    t = veh.part("Turret", parent="Body", pivot=RING, axis="z", note="turret yaw (ring centre)")
    ts = veh.shell("Turret")
    with V.bevel(ts, 0.02, lods=(0, 1)):
        V.plan_loft(ts, turret_layers(), PAINT, ALL)

    def turret_room(tmp):
        tmp.box((2.60, 2.80, 0.70), (0.0, -0.30, 2.25), "Paint_White", (0,))
    veh.cut(ts, turret_room, "Paint_White")
    for x in (-0.62, 0.62):
        K.opening(ts, [(x - 0.28, -1.12, 2.72), (x + 0.28, -1.12, 2.72), (x + 0.28, -0.64, 2.72), (x - 0.28, -0.64, 2.72)], (0, 0, 1), depth=0.25, out=0.20)
        t.box((0.42, 0.42, 0.10), (x, -0.85, 2.00), "Canvas_Green", L0)
        t.box((0.42, 0.10, 0.45), (x, -1.08, 2.25), "Canvas_Green", L0)
    t.box((0.50, 1.30, 0.50), (0.0, -0.10, 2.20), "Paint_OD", L0)          # gun breech / recoil guard
    t.cyl(1.20, 1.24, 0.10, (RING[0], RING[1], DECK + 0.04), "Paint_Black", L01, segs=32)
    # roof: gunner's main sight (front right), commander's PERI (rear right), hatches, crosswind sensor
    with V.bevel(t, 0.012):
        t.box((0.55, 0.62, 0.30), (0.95, 1.05, 2.86), PAINT, L01)
        t.cyl(0.24, 0.26, 0.22, (0.78, -0.55, 2.83), PAINT, L01, segs=18)
        t.box((0.42, 0.40, 0.26), (0.78, -0.55, 3.00), PAINT, L01)
    t.box((0.40, 0.02, 0.20), (0.95, 1.365, 2.88), "Glass", L0)
    t.box((0.26, 0.02, 0.16), (0.78, -0.345, 3.02), "Glass", L0)
    t.box((0.30, 0.02, 0.12), (0.78, -0.765, 3.02), "Glass", L0)
    hcm = veh.part("Hatch_Commander", parent="Turret", pivot=(0.62, -1.15, 2.74), axis="x", note="commander hatch")
    with V.bevel(hcm, 0.012):
        hcm.box((0.70, 0.62, 0.05), (0.62, -0.88, 2.75), PAINT, ALL)
    hld = veh.part("Hatch_Loader", parent="Turret", pivot=(-0.62, -1.20, 2.74), axis="x", note="loader hatch")
    with V.bevel(hld, 0.012):
        hld.box((0.70, 0.66, 0.05), (-0.62, -0.88, 2.75), PAINT, ALL)
    t.cyl(0.03, 0.03, 0.50, (-0.20, -1.95, 2.97), "Paint_Black", L0, segs=6)      # crosswind sensor mast
    t.box((0.10, 0.14, 0.08), (-0.20, -1.95, 3.24), "Paint_Black", L0)
    K.antenna(t, (-1.30, -1.85, 2.72), 2.0)
    K.antenna(t, (1.30, -1.85, 2.72), 1.6)
    # side stowage boxes, bustle basket, smoke dischargers
    for s in (-1, 1):
        with V.bevel(t, 0.012):
            t.box((0.30, 1.45, 0.45), (s * 1.92, -1.05, 2.35), PAINT, L01)
        for row, zz in enumerate((2.58, 2.44)):
            K.smoke_launchers(t, (s * 1.62, 1.12 - row * 0.05, zz), (s * 0.55, 0.85, 0), n=4, spread_deg=9, elev=22, mat="Paint_Black", tube_r=0.04, length=0.22)
    for k in range(3):
        t.tube([(-1.45, -2.30, 2.20 + k * 0.18), (1.45, -2.30, 2.20 + k * 0.18)], 0.016, "Paint_Black", L0, segs=5)
    for x in (-1.45, -0.5, 0.5, 1.45):
        t.tube([(x, -2.20, 2.10), (x, -2.60, 2.12), (x, -2.60, 2.58), (x, -2.22, 2.60)], 0.016, "Paint_Black", L01, segs=5)
    t.box((2.70, 0.38, 0.32), (0.0, -2.42, 2.30), "Canvas_Green", L0, bevel=0.04)
    # ------------------------------------------------------------ EuroTrophy: launchers on the turret sides, radar panels
    for s in (-1, 1):
        with V.bevel(t, 0.01):
            t.box((0.34, 0.50, 0.42), (s * 2.00, 0.05, 2.48), PAINT, L01)      # launcher housing
            t.box((0.24, 0.30, 0.14), (s * 1.88, 0.05, 2.70), PAINT, L01)
        t.cyl(0.16, 0.16, 0.06, (s * 2.18, 0.05, 2.50), "Paint_Black", L0, axis=(1, 0, 0), segs=16)
        # radar panels: front-facing on the wedge corners, rear-facing on the bustle corners
        for q in ([(s * 1.38, 1.98, 2.36), (s * 1.70, 1.66, 2.36), (s * 1.70, 1.66, 2.70), (s * 1.38, 1.98, 2.70)],
                  [(s * 1.52, -2.04, 2.36), (s * 1.18, -2.26, 2.36), (s * 1.18, -2.26, 2.66), (s * 1.52, -2.04, 2.66)]):
            V.plate(t, q, 0.06, PAINT, L01)
            qv = [Vector(v) for v in q]
            c = sum(qv, Vector()) / 4
            n = (qv[1] - qv[0]).cross(qv[2] - qv[1]).normalized()
            if n.dot(c - Vector((0, c.y, c.z))) < 0:
                n = -n
            V.plate(t, [tuple(c + (v - c) * 0.78 + n * 0.012) for v in qv], 0.02, "Paint_Black", L0)     # radar window
    # ------------------------------------------------------------ RWS (estimate: Protector-type on the loader's side)
    K.protector_rws(veh, "RWS", "Turret", (-0.80, 0.30, 2.72), gun="m2", scale=0.95)
    # ------------------------------------------------------------ gun: 120 mm L55A1 with thermal sleeve, fume extractor, MRS
    g = veh.part("Gun", parent="Turret", pivot=(0.0, 2.10, 2.30), axis="x", note="gun elevation (trunnions)")
    with V.bevel(g, 0.015):
        g.box((0.86, 0.80, 0.58), (0.0, 2.62, 2.30), PAINT, ALL)                    # mantlet
    prof = [(0.21, 3.00), (0.21, 3.10), (0.16, 3.16), (0.14, 3.20), (0.14, 4.30), (0.20, 4.42), (0.20, 5.10), (0.14, 5.22),
            (0.125, 5.25), (0.125, 6.10), (0.120, 6.14), (0.120, MUZZLE_Y - 0.12), (0.135, MUZZLE_Y - 0.08), (0.135, MUZZLE_Y)]
    V.revolve(g, prof, (0, 0, 2.30), (0, 1, 0), PAINT, ALL, segs=20, smooth=True, cap1=True)
    for y in (3.70, 5.70):
        V.ring_band(g, 0.14, 0.152, y, y + 0.05, (0, 0, 2.30), (0, 1, 0), "Paint_Black", L0, segs=20)
    g.box((0.10, 0.12, 0.12), (0.0, MUZZLE_Y - 0.10, 2.48), "Paint_Black", L0)       # muzzle reference sensor
    g.cyl(0.04, 0.04, 0.06, (0.0, MUZZLE_Y - 0.03, 2.30), "Paint_Black", L0, axis=(0, 1, 0), segs=12)
    V.revolve(g, [(0.035, 3.00), (0.035, 3.12)], (0.30, 0, 2.38), (0, 1, 0), "Paint_Black", L0, segs=8, cap1=True)   # coax
    # ------------------------------------------------------------ collision, markers, metadata
    veh.col_between((-HW_SKIRT, YR, 0.45), (HW_SKIRT, YF, DECK))
    veh.col_between((-1.80, -2.3, DECK), (1.80, 2.0, 2.72))
    veh.col_between((-0.45, 2.0, 2.0), (0.45, 3.0, 2.60))
    veh.marker("SEAT_DRIVER", (-0.62, 2.55, 1.20))
    veh.marker("SEAT_COMMANDER", (0.62, -0.88, 2.10))
    veh.marker("SEAT_GUNNER", (0.70, 0.40, 1.90))
    veh.marker("SEAT_LOADER", (-0.62, -0.88, 1.90))
    veh.marker("WEAPON_MUZZLE", (0.0, MUZZLE_Y, 2.30), note="120 mm muzzle at 0 deg elevation")
    veh.meta.update({
        "reference": "Leopard 2A8 NOR (KNDS / Norway 2026); RWS type unconfirmed (estimate)",
        "dimensions_m": {"hull_length": LEN, "length_gun_forward": round(MUZZLE_Y - YR, 2), "width": round(2 * HW_SKIRT + 0.2, 2),
                         "turret_roof": 2.72, "periscope": 3.13, "road_wheel_d": 2 * RW_R, "track_width": TRACK_W},
        "paint": "Camo_NATO3 (the first NOR tanks were delivered without camouflage; NATO three-colour as on Norwegian Leopard 2A4NO)",
    })
    veh.qa = {"tol": 0.06}
    return veh


BUILDERS = {ID: build}
DETAILS = {ID: {
    "running_gear": ((-HW_SKIRT, 0.0, 0.8), 5.5, 75, 6, 50),
    "turret": ((0.0, 0.5, 2.6), 6.0, 30, 25, 50),
}}
