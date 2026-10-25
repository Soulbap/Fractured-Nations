"""VEH-04 Scania XT 6x6 military cargo truck (Scania "New Truck Generation" G-cab on the XT
off-road chassis), Danish / Dutch Army configuration with a dropside cargo body and canvas
cover.

Selection (documented in notes.md): Norway's own Scania fleet (Scania 3-series / 113 / 143
trucks bought 1986-1997, including 6x6 hook-lift trucks) has been replaced by Rheinmetall MAN
HX / TGS; no current Norwegian Scania military contract was found. The modern Scania military
truck that is documented in the Nordic / NATO neighbourhood is the Scania XT of the Danish Army
(DALO framework, ~900 trucks incl. 6x6 / 8x8 cargo) and the Dutch Army (Gryphus / XT). The
designation used here is the plain "Scania XT 6x6 (G-cab) cargo" - no invented model code.

Dimensions used (estimates from photographs and Scania XT 6x6 data): length 8.9 m, width
2.55 m, cab roof 3.25 m, wheelbase 4.5 m to the tandem centre, tandem spacing 1.40 m, tyres
395/85 R20 (diameter ~1.20 m).
"""
import math

import ap_lib as A
import ap_vehicle as V
import veh_kit as K

ALL, L01, L0, L12, L2 = A.ALL, A.L01, A.L0, A.L12, A.L2

ID = "scania_military"
PAINT = "Paint_Green"

LEN = 8.90
YF, YR = LEN / 2, -LEN / 2
AXLES = [3.00, -0.80, -2.20]
R_TYRE = 0.60
W_TYRE = 0.395
R_RIM = 0.254
TRACK = 2.06
CAB_F = 4.30          # cab front face (bottom)
CAB_R = 2.30          # cab back wall
CAB_FLOOR = 1.42
CAB_ROOF = 3.25
CAB_HW = 1.17
FRAME_Z = (0.98, 1.26)
BODY_F = 2.12         # cargo body front
BED_Z = 1.42


def cab_side_outline():
    """Side profile of the cab (y, z): bottom front, up the front face (slight slope), the
    windscreen, roof, back wall."""
    return [(CAB_F + 0.05, 0.95), (CAB_F + 0.12, 1.30), (CAB_F + 0.10, 2.00), (CAB_F + 0.02, 2.05), (CAB_F - 0.12, 2.95),
            (CAB_F - 0.20, 3.10), (CAB_F - 0.35, CAB_ROOF), (CAB_R + 0.08, CAB_ROOF), (CAB_R, CAB_ROOF - 0.08), (CAB_R, CAB_FLOOR - 0.10),
            (CAB_R + 0.25, 0.95)]


def build():
    veh = V.VehicleAsset(ID, "Scania XT 6x6 military truck", "Logistics vehicle",
                         "Scania XT 6x6 military cargo truck (G-cab, dropside body with canvas cover), Danish / Dutch Army configuration.")
    b = veh.part("Body", note="cab and chassis")
    sh = veh.shell("Body")
    # ------------------------------------------------------------ cab shell (side extrusion + rounded corners)
    with V.bevel(sh, 0.06, lods=(0, 1), segs=2):
        V.extrude_x(sh, cab_side_outline(), -CAB_HW, CAB_HW, PAINT, ALL)
    # cab interior: floor at the cab floor, behind the dashboard / windscreen
    def cav(top):
        return [(0.0, CAB_FLOOR + 0.05), (CAB_HW - 0.07, CAB_FLOOR + 0.05), (CAB_HW - 0.07, top - 0.10), (CAB_HW - 0.17, top), (0.0, top)]
    K.cavity(sh, [(CAB_F - 0.02, cav(2.05)), (CAB_F - 0.24, cav(CAB_ROOF - 0.08)), (CAB_R + 0.07, cav(CAB_ROOF - 0.08))], "Paint_Grey")
    # front grille panels, badge band, lower grille, corner hex grilles (XT front)
    yfront = CAB_F + 0.115
    with V.bevel(b, 0.01):
        b.box((1.60, 0.06, 0.30), (0, yfront, 1.78), PAINT, L01)
        b.box((1.40, 0.06, 0.24), (0, yfront, 1.47), PAINT, L01)
    for zc, w, h in ((1.78, 1.34, 0.18), (1.47, 1.20, 0.14), (1.17, 1.20, 0.12)):
        b.box((w, 0.03, h), (0, yfront + 0.025, zc), "Paint_Black", L01)
        for k in range(int(w / 0.06)):
            b.box((0.02, 0.035, h - 0.02), (-w / 2 + 0.03 + k * 0.06, yfront + 0.03, zc), PAINT, L0)
    for s in (-1, 1):
        b.box((0.30, 0.03, 0.22), (s * 0.80, yfront + 0.005, 1.95), "Paint_Black", L01, rot=A.rot_z(-s * 4))
    b.box((0.70, 0.02, 0.10), (0, yfront + 0.04, 1.97), "Paint_Black", L0)             # SCANIA lettering band
    # windscreen, side windows, wipers, sun visor
    def ws_y(z):
        return CAB_F + 0.02 - 0.14 * (z - 2.05) / 0.90
    K.window(b, [(-1.02, ws_y(2.12), 2.12), (1.02, ws_y(2.12), 2.12), (0.98, ws_y(2.90), 2.90), (-0.98, ws_y(2.90), 2.90)],
             (0, 1, 0.15), frame=0.05, proud=0.02, cut=sh, depth=0.25)
    for x in (-0.45, 0.45):
        b.box((0.75, 0.02, 0.02), (x, CAB_F + 0.035, 2.12), "Paint_Black", L0, rot=A.rot_z(5))
    with V.bevel(b, 0.01):
        b.box((2.20, 0.25, 0.05), (0, CAB_F - 0.14, 3.05), PAINT, L01, rot=A.rot_x(10))
    # ------------------------------------------------------------ doors
    for tag, s in (("L", -1), ("R", 1)):
        d = veh.part("Door_" + tag, parent="Body", pivot=(s * (CAB_HW + 0.01), CAB_F - 0.10, 2.0), axis="z", note="cab door, hinge at the front")
        x = s * (CAB_HW + 0.02)
        ds = veh.shell("Door_" + tag)
        K.opening(sh, [(s * CAB_HW, CAB_F - 0.16, 1.36), (s * CAB_HW, CAB_R + 0.74, 1.36), (s * CAB_HW, CAB_R + 0.74, 2.90),
                       (s * CAB_HW, CAB_F - 0.28, 2.90), (s * CAB_HW, CAB_F - 0.16, 2.12)], (s, 0, 0), depth=0.30, out=0.12, interior="Paint_Grey")
        with V.bevel(ds, 0.012):
            V.plate(ds, [(x, CAB_F - 0.12, 1.30), (x, CAB_R + 0.70, 1.30), (x, CAB_R + 0.70, 2.95), (x, CAB_F - 0.25, 2.95), (x, CAB_F - 0.12, 2.10)],
                    0.03, PAINT, ALL)
        K.window(d, [(x, CAB_F - 0.20, 2.12), (x, CAB_R + 0.78, 2.12), (x, CAB_R + 0.78, 2.85), (x, CAB_F - 0.30, 2.85)], (s, 0, 0), frame=0.04,
                 proud=0.03, cut=ds, depth=0.10)
        V.handle(d, (s * (CAB_HW + 0.07), CAB_R + 0.85, 1.95), (s * (CAB_HW + 0.07), CAB_R + 1.05, 1.95), 0.04, (s, 0, 0), lods=L01)
        # rear quarter window in the cab side, behind the door
        K.window(b, [(s * (CAB_HW + 0.002), CAB_R + 0.60, 2.20), (s * (CAB_HW + 0.002), CAB_R + 0.20, 2.20),
                     (s * (CAB_HW + 0.002), CAB_R + 0.20, 2.80), (s * (CAB_HW + 0.002), CAB_R + 0.60, 2.80)], (s, 0, 0), frame=0.03, proud=0.015,
                 cut=sh, depth=0.20)
        # steps (three) and grab handle
        for k, z in enumerate((0.62, 0.98, 1.30)):
            b.box((0.28, 0.42, 0.04), (s * (CAB_HW - 0.10 + 0.03 * k), CAB_F - 0.65, z), "Paint_Black", L01)
            b.box((0.03, 0.42, 0.18), (s * (CAB_HW + 0.03), CAB_F - 0.65, z - 0.08), PAINT, L0)
        b.tube([(s * (CAB_HW + 0.04), CAB_R + 0.12, 1.55), (s * (CAB_HW + 0.08), CAB_R + 0.12, 1.60), (s * (CAB_HW + 0.08), CAB_R + 0.12, 2.75),
                (s * (CAB_HW + 0.04), CAB_R + 0.12, 2.80)], 0.016, "Steel_Dark", L01, segs=6)
        # mirrors: main + wide-angle on arms
        K.mirror(b, (s * (CAB_HW + 0.02), CAB_F - 0.20, 2.80), (s * (CAB_HW + 0.30), CAB_F - 0.05, 2.70), size=(0.05, 0.22, 0.38))
        K.mirror(b, (s * (CAB_HW + 0.02), CAB_F - 0.20, 2.35), (s * (CAB_HW + 0.30), CAB_F - 0.05, 2.25), size=(0.05, 0.20, 0.20))
        # headlights / fog / indicators in the bumper corners
        K.lamp(b, (s * 0.92, YF - 0.08, 1.30), (0, 1, 0), lods=L01, square=True, w=0.30, h=0.15, depth=0.06)
        K.lamp(b, (s * 0.92, YF - 0.06, 1.05), (0, 1, 0), r=0.05, depth=0.04, lods=L0)
        K.lamp(b, (s * 1.12, YF - 0.20, 1.30), (s, 0.4, 0), lods=L0, square=True, w=0.06, h=0.06, lens="Plastic_Orange", depth=0.03)
        K.shackle(b, (s * 0.55, YF + 0.05, 0.82), axis=(1, 0, 0), r=0.07)
        # roof marker lights
        b.box((0.08, 0.04, 0.04), (s * 1.00, CAB_F - 0.36, CAB_ROOF + 0.02), "Plastic_Orange", L0)
    # bumper (XT: steel, protruding, with skid plate and tow pin)
    with V.bevel(b, 0.015):
        b.box((2.40, 0.30, 0.42), (0, YF - 0.13, 1.12), PAINT, ALL)
        b.box((1.40, 0.70, 0.04), (0, YF - 0.40, 0.72), "Paint_Black", L01, rot=A.rot_x(12))   # skid plate
    for s in (-1, 1):
        b.box((0.06, 0.08, 0.30), (s * 0.43, YF - 0.62, 0.84), "Paint_Black", L0)                 # skid plate hangers
    b.box((0.30, 0.20, 0.16), (0, YF + 0.02, 0.90), "Paint_Black", L0)
    b.box((0.40, 0.02, 0.10), (0, YF + 0.025, 1.18), "Paint_Yellow", L0)
    # cab roof: beacon, antenna, rack
    b.cyl(0.08, 0.08, 0.14, (0.0, CAB_R + 0.50, CAB_ROOF + 0.07), "Plastic_Orange", L01, segs=12)
    K.antenna(b, (-0.85, CAB_R + 0.25, CAB_ROOF), 1.2)
    b.tube([(-1.0, CAB_R + 0.20, CAB_ROOF), (-1.0, CAB_R + 0.20, CAB_ROOF + 0.12), (1.0, CAB_R + 0.20, CAB_ROOF + 0.12), (1.0, CAB_R + 0.20, CAB_ROOF)],
           0.02, "Paint_Black", L0, segs=6)
    # ------------------------------------------------------------ chassis, tanks, axles
    for s in (-1, 1):
        b.box((0.10, LEN - 0.40, FRAME_Z[1] - FRAME_Z[0]), (s * 0.43, -0.10, sum(FRAME_Z) / 2), "Paint_Black", ALL)
    for y in (3.6, 1.8, 0.0, -1.5, -3.0, -4.1):
        b.box((0.86, 0.08, 0.20), (0, y, FRAME_Z[0] + 0.10), "Paint_Black", L01)
    b.cyl(0.30, 0.30, 1.05, (-0.80, 1.35, 0.92), PAINT, L01, axis=(0, 1, 0), segs=20)       # fuel tank (left)
    for yy in (0.95, 1.75):
        b.box((0.66, 0.04, 0.66), (-0.80, yy, 0.92), "Paint_Black", L0)
    with V.bevel(b, 0.01):
        b.box((0.55, 0.70, 0.50), (0.75, 1.45, 0.98), PAINT, L01)                            # battery / tool box (right)
    for s in (-1, 1):
        b.cyl(0.11, 0.11, 0.70, (s * 0.72, 0.35, 0.90), "Paint_Black", L0, axis=(0, 1, 0), segs=12)   # air tanks
        for yy in (0.15, 0.55):
            b.box((0.26, 0.04, 0.04), (s * 0.58, yy, 0.98), "Paint_Black", L0)                       # tank straps to the rail
    # spare wheel behind the cab
    K.wheel_template(veh, "WheelScania", R_TYRE, W_TYRE, R_RIM, lugs=24, style="xzl", rim_mat=PAINT, nuts=10, beadlock=False)
    veh.instance("SpareWheel", "WheelScania", parent=None, pivot=(0.0, CAB_R - 0.30, FRAME_Z[1] + R_TYRE + 0.05), yaw=90.0, axis="",
                 note="spare wheel (static)")
    b.box((1.00, 0.10, 1.30), (0.0, CAB_R - 0.55, FRAME_Z[1] + 0.65), "Paint_Black", L01)
    # axles, springs, diff housings
    for i, yc in enumerate(AXLES):
        b.cyl_between((-TRACK / 2 + 0.25, yc, R_TYRE), (TRACK / 2 - 0.25, yc, R_TYRE), 0.08, "Paint_Black", L01, segs=10)
        b.sphere(0.24, (0, yc, R_TYRE), "Paint_Black", L01, segs=12, rings=8)
        for s in (-1, 1):
            for k in range(5):
                b.box((0.10, 1.30 - k * 0.18, 0.025), (s * 0.43, yc, FRAME_Z[0] - 0.05 - k * 0.028), "Steel_Dark", L0)   # leaf springs
    b.cyl_between((0, AXLES[0] - 0.05, R_TYRE), (0, AXLES[1] + 0.05, R_TYRE), 0.05, "Steel_Dark", L0, segs=8)          # prop shaft
    # mudguards over the front and tandem wheels
    for s in (-1, 1):
        K.arch_flare(b, AXLES[0], R_TYRE, R_TYRE + 0.10, 15, 165, s * (TRACK / 2 - 0.22), s * (TRACK / 2 + 0.22), 0.025, "Paint_Black", L01)
        b.box((0.46, 2.40, 0.03), (s * TRACK / 2, (AXLES[1] + AXLES[2]) / 2, 2 * R_TYRE + 0.12), "Paint_Black", L01)
        b.box((TRACK / 2 - 0.48, 0.06, 0.05), (s * (0.48 + (TRACK / 2 - 0.48) / 2), (AXLES[1] + AXLES[2]) / 2, 2 * R_TYRE + 0.12),
              "Paint_Black", L0)                                                                   # mudguard bracket
        b.box((0.46, 0.03, 0.40), (s * TRACK / 2, AXLES[2] - 0.80, 0.55), "Rubber", L01)     # mud flaps
        b.box((TRACK / 2 - 0.48, 0.05, 0.05), (s * (0.48 + (TRACK / 2 - 0.48) / 2), AXLES[2] - 0.80, 0.76), "Paint_Black", L0)
        b.box((0.05, 0.05, 0.40), (s * TRACK / 2, AXLES[2] - 0.80, 0.94), "Paint_Black", L0)
        K.lamp(b, (s * 1.05, YR + 0.05, 0.95), (0, -1, 0), lods=L01, square=True, w=0.30, h=0.10, lens="Reflector_Red", depth=0.05)
    b.box((2.10, 0.10, 0.12), (0, YR + 0.10, 0.62), "Paint_Black", L01)                     # rear underrun bar
    for s in (-1, 1):
        b.box((0.08, 0.10, FRAME_Z[0] - 0.62), (s * 0.43, YR + 0.10, (FRAME_Z[0] + 0.62) / 2), "Paint_Black", L01)   # underrun brackets
        b.box((0.62, 0.06, 0.06), (s * 0.80, YR + 0.10, 0.95), "Paint_Black", L01)                                  # lamp bar
    K.towing_pintle(b, (0, YR + 0.05, 0.85))
    # ------------------------------------------------------------ cargo body (separate component)
    c = veh.part("CargoBody", parent="Body", pivot=(0.0, (BODY_F + YR) / 2, BED_Z), axis="", note="dropside cargo body with canvas cover (separable)")
    blen = BODY_F - YR - 0.02
    yc = (BODY_F + YR) / 2
    with V.bevel(c, 0.012):
        c.box((2.50, blen, 0.12), (0, yc, BED_Z), PAINT, ALL)                                 # bed
        c.box((2.50, 0.08, 1.10), (0, BODY_F - 0.04, BED_Z + 0.60), PAINT, ALL)               # headboard
        for s in (-1, 1):
            for k in range(3):
                y0 = BODY_F - 0.06 - k * (blen - 0.06) / 3
                c.box((0.05, (blen - 0.06) / 3 - 0.03, 0.55), (s * 1.235, y0 - (blen - 0.06) / 6, BED_Z + 0.33), PAINT, ALL)   # dropsides
        c.box((2.40, 0.05, 0.55), (0, YR + 0.03, BED_Z + 0.33), PAINT, ALL)                  # tailgate
    for s in (-1, 1):
        for k in range(4):
            y0 = BODY_F - 0.06 - k * (blen - 0.06) / 3
            c.box((0.08, 0.08, 0.60), (s * 1.24, y0, BED_Z + 0.33), "Paint_Black", L0)
        for k in range(8):
            c.box((0.04, 0.10, 0.05), (s * 1.27, BODY_F - 0.40 - k * 0.78, BED_Z + 0.08), "Steel_Dark", L0)   # rope hooks
        c.box((0.06, blen - 0.2, 0.10), (s * 1.18, yc, BED_Z - 0.10), "Paint_Black", L01)                  # sub-frame
    # canvas cover over bows (rounded roof edges), rope ties
    with V.bevel(c, 0.10, lods=(0, 1), segs=2):
        c.box((2.52, blen - 0.04, 1.62), (0, yc - 0.01, BED_Z + 0.62 + 0.81), "Canvas_OD", ALL)
    for k in range(6):
        y = BODY_F - 0.6 - k * (blen - 0.8) / 5
        c.box((2.56, 0.03, 0.02), (0, y, BED_Z + 2.24), "Canvas_OD", L0)
        for s in (-1, 1):
            c.box((0.02, 0.03, 1.20), (s * 1.275, y, BED_Z + 1.25), "Canvas_OD", L0)
    c.box((2.0, 0.02, 1.0), (0, YR - 0.005, BED_Z + 1.30), "Canvas_Green", L0)             # rear flap
    # ------------------------------------------------------------ wheels
    K.wheels(veh, "WheelScania", AXLES, TRACK, R_TYRE, steer=(1,))
    # ------------------------------------------------------------ interior
    b.box((2.10, 0.45, 0.35), (0, CAB_F - 0.35, 2.00), "Plastic_Black", L0)
    for s in (-1, 1):
        b.box((0.55, 0.55, 0.15), (s * 0.55, CAB_F - 1.15, 1.75), "Canvas_Green", L0)
        b.box((0.55, 0.12, 0.75), (s * 0.55, CAB_F - 1.45, 2.15), "Canvas_Green", L0)
    sw = veh.part("SteeringWheel", parent="Body", pivot=(-0.55, CAB_F - 0.62, 2.30), axis="column", note="steering wheel")
    V.revolve(sw, [(0.21, -0.015), (0.23, 0.0), (0.21, 0.015), (0.19, 0.0), (0.21, -0.015)], (-0.55, CAB_F - 0.62, 2.30), (0, 0.5, 0.85),
              "Plastic_Black", L0, segs=16)
    # ------------------------------------------------------------ collision, markers, metadata
    veh.col_between((-CAB_HW, CAB_R, 0.95), (CAB_HW, YF, CAB_ROOF))
    veh.col_between((-1.25, YR, BED_Z - 0.10), (1.25, BODY_F, BED_Z + 2.25))
    veh.col_between((-1.15, YR, 0.55), (1.15, YF, BED_Z - 0.10))
    for tag, s in (("L", -1), ("R", 1)):
        veh.marker("DOOR_" + tag, (s * (CAB_HW + 0.8), CAB_F - 0.8, 0.0), yaw=90 if s < 0 else -90, note="cab door")
        veh.marker("SEAT_%s" % ("DRIVER" if s < 0 else "CODRIVER"), (s * 0.55, CAB_F - 1.15, 1.90))
    veh.marker("CARGO_BED", (0.0, yc, BED_Z + 0.06), note="cargo floor centre")
    veh.marker("DOOR_REAR", (0.0, YR - 1.0, 0.0), note="tailgate / loading point")
    veh.marker("TOW_REAR", (0.0, YR - 0.05, 0.85))
    veh.meta.update({
        "reference": "Scania XT 6x6 G-cab military cargo truck (Danish / Dutch Army configuration)",
        "dimensions_m": {"length": LEN, "width": 2.55, "cab_roof": CAB_ROOF, "axles_y": AXLES, "wheelbase_to_tandem": 4.5,
                         "tandem": 1.40, "tyre": "395/85 R20, d %.2f" % (2 * R_TYRE), "cargo_bed": [2.50, round(blen, 2)]},
        "paint": PAINT,
    })
    veh.qa = {"tol": 0.06}
    return veh


BUILDERS = {ID: build}
DETAILS = {ID: {
    "cab": ((0.0, CAB_F - 0.8, 2.0), 6.0, 35, 10, 50),
    "chassis": ((-1.2, 0.0, 0.9), 6.5, 75, 6, 50),
}}
