"""VEH-03 CV9030N Mk IIIb, Norwegian infantry fighting vehicle (BAE Hagglunds CV90, 30 mm
Bushmaster II, Soucy composite rubber tracks, Kongsberg Protector RWS on the turret,
bolted add-on armour on the sides).

Reference: assets/military/vehicles/_references/cv9030n/ (notes.md, manifest.json).
Dimensions used: hull length 6.55 m, width 3.2 m over the add-on armour, height to the turret
roof 2.7 m (published Mk III figures); seven road wheels per side, front drive sprocket, rear
idler (CV90 layout); road wheel diameter ~0.62 m, track width 0.533 m, two return rollers
per side (hidden by the skirts; estimate).
"""
import math

import ap_lib as A
import ap_vehicle as V
import veh_kit as K

ALL, L01, L0, L12, L2 = A.ALL, A.L01, A.L0, A.L12, A.L2

ID = "cv9030n"
PAINT = "Camo_NATO3"

LEN = 6.55
YF, YR = LEN / 2, -LEN / 2
HW_LOW = 0.95        # hull between the tracks
HW_SP = 1.52         # sponson / top of the track
HW_ARM = 1.62        # add-on armour face
TRACK_X = 1.25
TRACK_W = 0.533
RW_R = 0.31
RW_Y = [2.12 - 0.68 * k for k in range(7)]
SPROCKET = (2.80, 0.78, 0.29)
IDLER = (-2.88, 0.56, 0.28)
ROLLERS = [(1.30, 0.94, 0.075), (-0.75, 0.94, 0.075)]
RING = (0.0, 0.25, 1.78)


def hull_half(bottom, top, sp_top=None):
    st = sp_top if sp_top is not None else top - 0.07
    return [(0.0, bottom), (HW_LOW, bottom), (HW_LOW, 1.05), (HW_SP, 1.07), (HW_SP, st), (HW_SP - 0.08, top), (0.0, top)]


def build():
    veh = V.VehicleAsset(ID, "CV9030N Mk IIIb (Norwegian Army)", "Infantry fighting vehicle",
                         "CV9030N Mk IIIb IFV with 30 mm Bushmaster II, Kongsberg Protector RWS and Soucy rubber tracks.")
    b = veh.part("Body", note="hull")
    sh = veh.shell("Body")
    # ------------------------------------------------------------ hull
    with V.bevel(sh, 0.025, lods=(0, 1)):
        st = [
            (YF, [(0.0, 0.96), (HW_LOW, 0.96), (HW_LOW, 1.03), (HW_SP, 1.05), (HW_SP, 1.10), (HW_SP - 0.06, 1.12), (0.0, 1.12)]),
            (2.55, hull_half(0.45, 1.44, 1.38)),
            (2.15, hull_half(0.45, 1.58)),
            (1.10, hull_half(0.45, 1.64)),
            (0.80, hull_half(0.45, 1.74)),
            (-0.70, hull_half(0.45, 1.84)),
            (YR + 0.10, hull_half(0.45, 1.84)),
            (YR, hull_half(0.55, 1.78, 1.70)),
        ]
        V.hull_loft(sh, st, PAINT, ALL)
    # troop compartment (rear) and driver's station (front left), opened by the rear door and hatches
    def cav(top):
        return [(0.0, 0.70), (HW_LOW - 0.08, 0.70), (HW_LOW - 0.08, 1.12), (HW_SP - 0.10, 1.15), (HW_SP - 0.10, top - 0.08), (HW_SP - 0.22, top),
                (0.0, top)]
    K.cavity(sh, [(-0.35, cav(1.76)), (YR + 0.12, cav(1.76))], "Paint_White")

    def driver(tmp):
        tmp.box((0.70, 0.95, 0.75), (-0.55, 1.95, 1.18), "Paint_White", (0,))
    veh.cut(sh, driver, "Paint_White")
    K.opening(sh, [(-0.55 + 0.25 * math.cos(2 * math.pi * k / 16), 1.88 + 0.25 * math.sin(2 * math.pi * k / 16), 1.62) for k in range(16)],
              (0, 0, 1), depth=0.20, out=0.15)
    # engine deck grilles (front right), driver's hatch and periscopes (front left)
    for k in range(9):
        b.box((0.80, 0.045, 0.03), (0.55, 2.40 - k * 0.11, 1.53 + k * 0.012), "Paint_Black", L0, rot=A.rot_x(-8))
    with V.bevel(b, 0.01):
        b.box((0.95, 1.10, 0.03), (0.55, 1.98, 1.53), PAINT, L01, rot=A.rot_x(-8))
    dh = veh.part("Hatch_Driver", parent="Body", pivot=(-0.55, 1.62, 1.66), axis="z", note="driver hatch (swings)")
    with V.bevel(dh, 0.012):
        dh.cyl(0.30, 0.30, 0.05, (-0.55, 1.88, 1.66), PAINT, ALL, segs=20)
    for k in range(3):
        b.box((0.16, 0.08, 0.10), (-0.85 + k * 0.30, 2.25, 1.55), "Paint_Black", L0, rot=A.rot_x(-8))
        b.box((0.14, 0.01, 0.06), (-0.85 + k * 0.30, 2.30, 1.56), "Glass", L0, rot=A.rot_x(-8))
    # front: lights, tow hooks, number plate, splash board
    for s in (-1, 1):
        K.lamp(b, (s * 1.35, 3.00, 1.18), (0, 1, 0), lods=L01, square=True, w=0.14, h=0.08, depth=0.08, housing="Paint_Black")
        K.tow_eye(b, (s * 0.65, YF - 0.05, 0.92), (0, 1, 0))
        K.shackle(b, (s * 0.65, YF - 0.02, 0.84), axis=(1, 0, 0), r=0.07)
        b.box((0.05, 0.60, 0.30), (s * (HW_SP - 0.02), 2.95, 1.05), PAINT, L01)      # front mudguard cheeks over the sprocket
    b.box((0.40, 0.02, 0.10), (0.0, YF - 0.06, 1.06), "Paint_Yellow", L0, rot=A.rot_x(-20))
    with V.bevel(b, 0.012):
        b.box((2.0, 0.08, 0.30), (0.0, 2.95, 1.30), PAINT, L01, rot=A.rot_x(-60))     # add-on wedge armour on the nose
    # ------------------------------------------------------------ add-on side armour (bolted modules) and stowage
    for s in (-1, 1):
        x = s * (HW_ARM - 0.04)
        for k, (y0, y1) in enumerate(((2.60, 1.45), (1.40, 0.25), (0.20, -0.95), (-1.00, -2.15), (-2.20, -3.15))):
            with V.bevel(b, 0.015):
                b.box((0.10, y0 - y1 - 0.03, 0.80), (x, (y0 + y1) / 2, 1.17), PAINT, ALL)
            V.bolts(b, [(x + s * 0.05, yy, zz) for yy in (y0 - 0.12, y1 + 0.12) for zz in (0.88, 1.17, 1.46)], (1, 0, 0), r=0.02, h=0.015)
            b.box((0.02, 0.10, 0.05), (x + s * 0.055, (y0 + y1) / 2, 1.50), "Paint_Black", L0)
        # rear stowage bins on the sponsons
        with V.bevel(b, 0.012):
            b.box((0.62, 1.30, 0.42), (s * 1.18, -2.45, 2.05), PAINT, L01)
        b.box((0.03, 1.10, 0.03), (s * 1.50, -2.45, 2.20), "Paint_Black", L0)
        # rear lights and steps
        K.lamp(b, (s * 1.20, YR - 0.02, 1.55), (0, -1, 0), lods=L0, square=True, w=0.16, h=0.08, lens="Reflector_Red", depth=0.04)
        b.box((0.30, 0.20, 0.04), (s * 0.85, YR - 0.05, 0.75), "Paint_Black", L0)
        K.antenna(b, (s * 1.25, -1.55, 1.84), 1.6)
        # swing arms (trailing arms) from the hull to every road wheel
        for y in RW_Y:
            b.box((0.30, 0.42, 0.10), (s * (HW_LOW + 0.10), y + 0.20, RW_R + 0.12), "Paint_Black", L01, rot=A.rot_x(15))
            b.cyl((0.09), 0.09, 0.08, (s * (HW_LOW + 0.04), y + 0.40, RW_R + 0.18), "Steel_Dark", L0, axis=(1, 0, 0), segs=10)
    # ------------------------------------------------------------ roof: troop hatches, rear door
    for tag, s in (("L", -1), ("R", 1)):
        h = veh.part("Hatch_" + tag, parent="Body", pivot=(s * 0.95, -1.75, 1.86), axis="y", note="troop roof hatch")
        with V.bevel(h, 0.012):
            h.box((0.80, 1.05, 0.05), (s * 0.52, -1.75, 1.87), PAINT, ALL)
        K.opening(sh, [(s * 0.18, -2.22, 1.84), (s * 0.88, -2.22, 1.84), (s * 0.88, -1.28, 1.84), (s * 0.18, -1.28, 1.84)], (0, 0, 1), depth=0.20, out=0.10)
        V.handle(h, (s * 0.25, -1.95, 1.90), (s * 0.25, -1.55, 1.90), 0.05, (0, 0, 1), lods=L0)
    rd = veh.part("Door_Rear", parent="Body", pivot=(0.62, YR - 0.03, 1.2), axis="z", note="rear troop door, hinge on the right")
    rds = veh.shell("Door_Rear")
    with V.bevel(rds, 0.015):
        V.plate(rds, [(0.60, YR - 0.04, 0.62), (-0.62, YR - 0.04, 0.62), (-0.62, YR - 0.04, 1.70), (0.60, YR - 0.04, 1.70)], 0.06, PAINT, ALL)
    K.window(rd, [(-0.15, YR - 0.10, 1.40), (0.15, YR - 0.10, 1.40), (0.15, YR - 0.10, 1.56), (-0.15, YR - 0.10, 1.56)], (0, -1, 0), frame=0.03,
             cut=rds, depth=0.12)
    K.opening(sh, [(0.54, YR, 0.70), (-0.56, YR, 0.70), (-0.56, YR, 1.62), (0.54, YR, 1.62)], (0, -1, 0), depth=0.35, out=0.15)
    # troop seats (four a side, facing inwards), ammunition racks
    for s in (-1, 1):
        for k in range(4):
            b.box((0.42, 0.46, 0.10), (s * 0.70, -0.75 - k * 0.55, 1.05), "Canvas_Green", L0)
            b.box((0.10, 0.46, 0.55), (s * 0.94, -0.75 - k * 0.55, 1.38), "Canvas_Green", L0)
    b.box((0.40, 1.80, 0.30), (0.0, -1.55, 0.86), "Paint_OD", L0)
    V.handle(rd, (-0.45, YR - 0.10, 1.25), (-0.45, YR - 0.10, 1.00), 0.05, (0, -1, 0), lods=L01)
    for zh in (0.85, 1.50):
        rd.box((0.09, 0.08, 0.16), (0.64, YR - 0.10, zh), "Paint_Black", L0)
    K.towing_pintle(b, (0.0, YR - 0.04, 0.70))
    # ------------------------------------------------------------ running gear
    rw = K.road_wheel_template(veh, "RoadWheelCV90", RW_R, 0.46, gap=0.09, rim_mat="Paint_Green")
    sp = K.sprocket_template(veh, "SprocketCV90", SPROCKET[2], 0.46, 12, mat="Paint_Green")
    idl = K.road_wheel_template(veh, "IdlerCV90", IDLER[2], 0.42, gap=0.09, rim_mat="Paint_Green", tyre_mat="Steel_Dark")
    ro = veh.part("RollerCV90", local=True, note="template")
    ro.a.ao_strength = 0.0
    V.revolve(ro, [(0.0, -0.10), (0.075, -0.10), (0.075, 0.10), (0.0, 0.10)], (0, 0, 0), (1, 0, 0), "Rubber", ALL, segs=16, smooth=False)
    for side, s in (("L", -1), ("R", 1)):
        K.running_gear(veh, side, s * TRACK_X, RW_Y, RW_R, SPROCKET, IDLER, ROLLERS, TRACK_W, 0.125, link="rubber",
                       rw_template="RoadWheelCV90", sp_template="SprocketCV90", id_template="IdlerCV90", ro_template="RollerCV90")
    # ------------------------------------------------------------ turret
    t = veh.part("Turret", parent="Body", pivot=RING, axis="z", note="turret yaw (ring centre)")
    ts = veh.shell("Turret")
    with V.bevel(ts, 0.02, lods=(0, 1)):
        tst = [
            (1.42, [(0.0, 1.82), (0.62, 1.82), (0.70, 2.18), (0.62, 2.30), (0.36, 2.36), (0.0, 2.36)]),
            (1.05, [(0.0, 1.80), (1.02, 1.80), (1.10, 2.24), (1.04, 2.52), (0.70, 2.62), (0.0, 2.62)]),
            (-0.55, [(0.0, 1.80), (1.08, 1.80), (1.14, 2.24), (1.08, 2.52), (0.72, 2.62), (0.0, 2.62)]),
            (-1.15, [(0.0, 1.98), (0.98, 1.98), (1.04, 2.24), (0.98, 2.50), (0.68, 2.56), (0.0, 2.56)]),
            (-1.26, [(0.0, 2.06), (0.88, 2.06), (0.92, 2.24), (0.88, 2.44), (0.62, 2.50), (0.0, 2.50)]),
        ]
        V.hull_loft(ts, tst, PAINT, ALL)
    K.cavity(ts, [(0.95, [(0.0, 1.70), (0.90, 1.70), (0.98, 2.22), (0.92, 2.48), (0.62, 2.55), (0.0, 2.55)]),
                  (-0.95, [(0.0, 1.70), (0.95, 1.70), (1.02, 2.22), (0.96, 2.48), (0.64, 2.55), (0.0, 2.55)])], "Paint_White")
    K.opening(ts, [(0.45 + 0.25 * math.cos(2 * math.pi * k / 16), -0.20 + 0.25 * math.sin(2 * math.pi * k / 16), 2.62) for k in range(16)],
              (0, 0, 1), depth=0.25, out=0.20)
    for x in (-0.45, 0.45):
        t.box((0.40, 0.40, 0.10), (x, -0.25, 1.95), "Canvas_Green", L0)
        t.box((0.40, 0.10, 0.45), (x, -0.48, 2.20), "Canvas_Green", L0)
        t.cyl(1.05, 1.08, 0.10, (RING[0], RING[1], RING[2] + 0.02), PAINT, L01, segs=32)
    # turret side armour modules + bolts, bustle basket, smoke dischargers
    for s in (-1, 1):
        with V.bevel(t, 0.012):
            t.box((0.08, 1.30, 0.38), (s * 1.16, 0.30, 2.20), PAINT, L01, rot=A.rot_y(s * 8))
        V.bolts(t, [(s * 1.21, yy, zz) for yy in (-0.25, 0.30, 0.85) for zz in (2.08, 2.32)], (1, 0, 0), r=0.018)
        K.smoke_launchers(t, (s * 0.95, 1.00, 2.48), (s * 0.7, 0.7, 0), n=4, spread_deg=10, elev=30, mat=PAINT)
        t.tube([(s * 0.95, -1.15, 2.20), (s * 1.00, -1.55, 2.22), (s * 1.00, -1.55, 2.55), (s * 0.95, -1.20, 2.56)], 0.018, "Paint_Black", L01, segs=6)
    t.tube([(-1.00, -1.55, 2.22), (1.00, -1.55, 2.22)], 0.018, "Paint_Black", L01, segs=6)
    t.tube([(-1.00, -1.55, 2.55), (1.00, -1.55, 2.55)], 0.018, "Paint_Black", L01, segs=6)
    t.box((1.90, 0.32, 0.20), (0.0, -1.38, 2.32), "Canvas_Green", L0, bevel=0.03)
    # commander's panoramic sight (right) and gunner's sight (left), cupola, hatches
    with V.bevel(t, 0.01):
        t.box((0.28, 0.30, 0.32), (0.55, 0.55, 2.76), PAINT, L01)
        t.box((0.30, 0.34, 0.26), (-0.60, 0.80, 2.71), PAINT, L01)
        t.cyl(0.36, 0.38, 0.12, (0.45, -0.20, 2.66), PAINT, L01, segs=20)
    t.box((0.20, 0.02, 0.16), (0.55, 0.705, 2.80), "Glass", L0)
    t.box((0.22, 0.02, 0.12), (-0.60, 0.975, 2.73), "Glass", L0)
    for k in range(6):
        a = 2 * math.pi * k / 6
        t.box((0.10, 0.06, 0.07), (0.45 + 0.32 * math.cos(a), -0.20 + 0.32 * math.sin(a), 2.73), "Paint_Black", L0, rot=A.rot_z(math.degrees(a) + 90))
    hcm = veh.part("Hatch_Commander", parent="Turret", pivot=(0.45, -0.48, 2.73), axis="x", note="commander hatch")
    with V.bevel(hcm, 0.012):
        hcm.cyl(0.30, 0.30, 0.05, (0.45, -0.20, 2.74), PAINT, ALL, segs=20)
    K.antenna(t, (-0.75, -0.95, 2.60), 1.8)
    K.antenna(t, (0.85, -0.95, 2.60), 1.4)
    K.protector_rws(veh, "RWS", "Turret", (-0.40, -0.35, 2.62), gun="m2", scale=0.9)
    # ------------------------------------------------------------ gun (30 mm Bushmaster II) + mantlet
    g = veh.part("Gun", parent="Turret", pivot=(0.0, 1.30, 2.12), axis="x", note="gun elevation (trunnions)")
    with V.bevel(g, 0.012):
        g.box((0.50, 0.40, 0.38), (0.0, 1.45, 2.12), PAINT, ALL)
    V.revolve(g, [(0.085, 1.62), (0.085, 2.35), (0.06, 2.42), (0.048, 2.45), (0.048, 3.95), (0.058, 3.98), (0.058, 4.22),
                  (0.048, 4.24)], (0, 0, 2.12), (0, 1, 0), "Paint_Black", ALL, segs=14, smooth=True, cap1=True)
    V.revolve(g, [(0.038, 1.66), (0.038, 2.0)], (0.22, 0, 2.06), (0, 1, 0), "Paint_Black", L0, segs=8, cap1=True)   # coax
    for k in range(6):
        g.box((0.02, 0.022, 0.03), (0.0, 4.02 + k * 0.035, 2.12 + 0.06), "Steel_Dark", L0)
    # ------------------------------------------------------------ collision, markers, metadata
    veh.col_between((-HW_ARM, YR, 0.40), (HW_ARM, YF, 1.62))
    veh.col_between((-HW_SP, YR, 1.62), (HW_SP, 0.9, 1.84))
    veh.col_between((-1.15, -1.3, 1.80), (1.15, 1.45, 2.62))
    veh.marker("DOOR_REAR", (0.0, YR - 1.0, 0.0), note="rear troop door")
    veh.marker("SEAT_DRIVER", (-0.55, 1.90, 1.0))
    veh.marker("SEAT_COMMANDER", (0.45, -0.2, 1.75))
    veh.marker("SEAT_GUNNER", (-0.45, -0.1, 1.75))
    for k in range(4):
        for s in (-1, 1):
            veh.marker("SEAT_%d" % (k * 2 + (1 if s < 0 else 2)), (s * 0.55, -1.1 - k * 0.5, 1.0), yaw=-90 * s, note="troop seat")
    veh.meta.update({
        "reference": "CV9030N Mk IIIb (Norway), Soucy rubber tracks, Protector RWS",
        "dimensions_m": {"hull_length": LEN, "width": round(2 * HW_ARM, 2), "turret_roof": 2.62, "road_wheel_d": 2 * RW_R,
                         "track_width": TRACK_W, "track_centres": 2 * TRACK_X},
        "paint": "Camo_NATO3",
    })
    veh.qa = {"tol": 0.06}
    return veh


BUILDERS = {ID: build}
DETAILS = {ID: {
    "running_gear": ((-HW_ARM, 0.0, 0.7), 4.6, 75, 6, 50),
    "turret": ((0.0, 0.2, 2.4), 5.0, 40, 22, 50),
}}
