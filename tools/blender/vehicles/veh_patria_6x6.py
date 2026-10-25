"""VEH-02 Patria 6x6 (CAVS), armoured personnel carrier - Finnish / Latvian / Swedish CAVS
hull with the Kongsberg Protector RS4 of the Norwegian command configuration.

Reference: assets/military/vehicles/_references/patria_6x6/ (notes.md, manifest.json).
Dimensions used (Patria / Wikipedia): length 7.5 m, width 2.9 m, height over hull 2.5 m;
axle spacing ~1.55 m (estimated from photographs: tyre gap ~0.3 m at 14.00 R20 tyres,
diameter ~1.24 m), front overhang ~3.0 m (bow), rear overhang ~1.4 m (estimates).
"""
import math

import ap_lib as A
import ap_vehicle as V
import veh_kit as K

ALL, L01, L0, L12, L2 = A.ALL, A.L01, A.L0, A.L12, A.L2

ID = "patria_6x6"
PAINT = "Camo_NATO3"

LEN = 7.5
YF, YR = LEN / 2, -LEN / 2
AXLES = [0.75, -0.80, -2.35]
R_TYRE = 0.62
W_TYRE = 0.37
R_RIM = 0.254
TRACK = 2.48
HW = 1.42
ROOF = 2.30
CAB_ROOF = 2.46
CAB_F = 2.02       # windscreen base
CAB_T = 1.55       # windscreen top
CAB_R = 0.92       # cab rear wall


def hull_prof(top, side_top=None, crease=1.30, hw=HW, keel=0.48):
    st = side_top if side_top is not None else top - 0.18
    return [(0.0, keel), (0.60, keel + 0.02), (1.02, crease - 0.02), (hw, crease), (hw, st), (hw - 0.14, top), (0.0, top)]


def build():
    veh = V.VehicleAsset(ID, "Patria 6x6 APC", "Armoured personnel carrier",
                         "Patria 6x6 (CAVS) armoured personnel carrier with Kongsberg Protector RS4 (Norwegian command configuration).")
    b = veh.part("Body", note="hull")
    sh = veh.shell("Body")

    # ------------------------------------------------------------ hull: V belly, sponsons, wedge bow
    with V.bevel(sh, 0.03, lods=(0, 1)):
        st = [
            (YF, [(0.0, 1.15), (0.45, 1.15), (0.80, 1.21), (1.00, 1.23), (1.00, 1.27), (0.92, 1.29), (0.0, 1.29)]),
            (YF - 0.20, [(0.0, 1.00), (0.50, 1.00), (0.90, 1.18), (1.14, 1.22), (1.14, 1.34), (1.04, 1.38), (0.0, 1.38)]),
            (2.70, [(0.0, 0.64), (0.60, 0.66), (1.00, 1.28), (1.36, 1.30), (1.36, 1.66), (1.24, 1.72), (0.0, 1.72)]),
            (CAB_F, hull_prof(1.98, 1.90)),
            (CAB_R + 0.03, hull_prof(1.98, 1.90)),
            (CAB_R + 0.02, hull_prof(ROOF)),
            (YR + 0.10, hull_prof(ROOF)),
            (YR, hull_prof(ROOF - 0.06, ROOF - 0.20, 1.32, HW - 0.05, 0.60)),
        ]
        V.hull_loft(sh, st, PAINT, ALL)
    # ------------------------------------------------------------ cab (full width, raked windscreen)
    def cab_half(top):
        return [(0.0, 1.94), (HW - 0.02, 1.94), (HW, 2.00), (HW - 0.06, top - 0.10), (HW - 0.18, top), (0.0, top + 0.01)]
    with V.bevel(sh, 0.025, lods=(0, 1)):
        V.hull_loft(sh, [(CAB_F + 0.02, cab_half(2.02)), (CAB_T, cab_half(CAB_ROOF)), (CAB_R, cab_half(CAB_ROOF))], PAINT, ALL)
    # interior: cab and troop compartment as one volume above the V floor
    def cav(top):
        return [(0.0, 0.82), (0.72, 0.82), (1.00, 1.36), (HW - 0.08, 1.38), (HW - 0.08, top - 0.12), (HW - 0.22, top), (0.0, top)]
    K.cavity(sh, [(CAB_F - 0.12, cav(2.08)), (CAB_T - 0.10, cav(CAB_ROOF - 0.08)), (CAB_R + 0.02, cav(CAB_ROOF - 0.08)),
                  (CAB_R - 0.02, cav(ROOF - 0.08)), (YR + 0.12, cav(ROOF - 0.08))], "Paint_White")
    # windscreen: three armoured panes, side windows of the doors
    def ws(t, x):
        y = CAB_F + 0.02 + (CAB_T - CAB_F - 0.02) * t
        z = 2.02 + (CAB_ROOF - 2.02) * t
        return (x, y, z)
    for x0, x1 in ((-1.18, -0.42), (-0.36, 0.36), (0.42, 1.18)):
        K.window(b, [ws(0.15, x0), ws(0.15, x1), ws(0.88, x1), ws(0.88, x0)], (0, 1, 0.9), frame=0.045, cut=sh, depth=0.25)
    # wipers parked at the base
    for x in (-0.80, 0.0, 0.80):
        b.box((0.42, 0.02, 0.02), (x, CAB_F - 0.02, 2.08), "Paint_Black", L0, rot=A.rot_z(6))
    # cab doors (separate parts), hinge at the front edge
    for tag, s in (("FL", -1), ("FR", 1)):
        d = veh.part("Door_" + tag, parent="Body", pivot=(s * (HW + 0.02), 1.88, 1.9), axis="z", note="cab door, hinge at the front edge")
        x = s * (HW + 0.025)
        ds = veh.shell("Door_" + tag)
        with V.bevel(ds, 0.012):
            V.plate(ds, [(x, 1.90, 1.36), (x, 0.98, 1.36), (x, 0.98, 2.30), (x, 1.62, 2.30), (x, 1.90, 2.02)], 0.035, PAINT, ALL)
        K.window(d, [(x, 1.70, 1.80), (x, 1.12, 1.80), (x, 1.12, 2.20), (x, 1.52, 2.20), (x, 1.70, 2.02)], (s, 0, 0), frame=0.04, proud=0.03,
                 cut=ds, depth=0.10)
        K.opening(sh, [(s * HW, 1.86, 1.42), (s * HW, 1.02, 1.42), (s * HW, 1.02, 2.26), (s * HW, 1.60, 2.26), (s * HW, 1.86, 2.04)], (s, 0, 0),
                  depth=0.30, out=0.12)
        V.handle(d, (s * (HW + 0.06), 1.05, 1.65), (s * (HW + 0.06), 1.05, 1.45), 0.05, (s, 0, 0), lods=L01)
        for zh in (1.50, 2.10):
            d.box((0.06, 0.07, 0.12), (s * (HW + 0.06), 1.86, zh), "Paint_Black", L0)
        # grab rail around the door (photos: tubular rail from the step to the roof)
        d.tube([(s * (HW + 0.06), 0.96, 1.40), (s * (HW + 0.10), 0.94, 1.45), (s * (HW + 0.10), 0.94, 2.25), (s * (HW + 0.06), 0.96, 2.30)],
               0.016, "Paint_Black", L01, segs=6)
        V.bolts(d, [(x + s * 0.035, yy, zz) for yy in (1.80, 1.05) for zz in (1.45, 1.70)], (1, 0, 0))
    # ------------------------------------------------------------ bow details
    for s in (-1, 1):
        # headlight boxes in the bow corners (photos: recessed lamp + guard above the front wheel)
        with V.bevel(b, 0.01):
            b.box((0.28, 0.24, 0.22), (s * 1.14, 2.55, 1.12), PAINT, L01)
        K.lamp(b, (s * 1.14, 2.68, 1.12), (0, 1, 0), r=0.08, depth=0.05, housing="Paint_Black")
        V.slats(b, s * 1.02, s * 1.26 if s > 0 else -1.02, 1.22, 1.30, 2.69, 4, 0.03, 0.012, "Paint_Black", L0, vertical=False, tilt=0) if s > 0 else \
            V.slats(b, -1.26, -1.02, 1.22, 1.30, 2.69, 4, 0.03, 0.012, "Paint_Black", L0, vertical=False, tilt=0)
        K.tow_eye(b, (s * 0.70, YF - 0.12, 1.05), (0, 1, 0))
        K.shackle(b, (s * 0.70, YF - 0.05, 0.98), axis=(1, 0, 0), r=0.07)
        K.mirror(b, (s * (HW - 0.02), CAB_F + 0.05, 2.0), (s * (HW + 0.32), CAB_F + 0.25, 2.25), size=(0.05, 0.26, 0.34))
        b.tube([(s * (HW - 0.02), CAB_F + 0.05, 2.0), (s * (HW + 0.32), CAB_F + 0.25, 2.06)], 0.014, "Steel_Dark", L01, segs=6)
        K.lamp(b, (s * 1.0, YF - 0.12, 1.36), (0, 0.5, 1), lods=L0, square=True, w=0.10, h=0.05, lens="Plastic_Orange", depth=0.03)
    b.box((0.40, 0.02, 0.11), (0, YF - 0.13, 1.33), "Paint_Yellow", L0, rot=A.rot_x(-60))
    # trim vane / splash plate folded on the upper glacis
    with V.bevel(b, 0.01):
        b.box((2.10, 0.70, 0.04), (0, 3.06, 1.62), PAINT, L01, rot=A.rot_x(-27))
    for x in (-0.9, 0.9):
        b.box((0.08, 0.10, 0.10), (x, 2.78, 1.76), "Paint_Black", L0)
    # cab roof: periscope blocks, commander's hatch, antennas, smoke dischargers on the cab sides
    for x in (-0.9, -0.3, 0.3, 0.9):
        b.box((0.22, 0.10, 0.08), (x, CAB_T - 0.05, CAB_ROOF + 0.04), "Paint_Black", L0)
        b.box((0.20, 0.02, 0.05), (x, CAB_T + 0.005, CAB_ROOF + 0.045), "Glass", L0)
    hc = veh.part("Hatch_Cab", parent="Body", pivot=(0.55, 0.98, CAB_ROOF + 0.02), axis="x", note="cab roof hatch, hinge at the rear edge")
    with V.bevel(hc, 0.015):
        hc.cyl(0.36, 0.36, 0.06, (0.55, 1.30, CAB_ROOF + 0.04), PAINT, ALL, segs=24)
    K.opening(sh, [(0.55 + 0.30 * math.cos(2 * math.pi * k / 16), 1.30 + 0.30 * math.sin(2 * math.pi * k / 16), CAB_ROOF) for k in range(16)],
              (0, 0, 1), depth=0.25, out=0.10)
    hc.box((0.10, 0.08, 0.08), (0.55, 1.62, CAB_ROOF + 0.07), "Paint_Black", L0)
    for s in (-1, 1):
        K.smoke_launchers(b, (s * (HW - 0.10), 1.20, CAB_ROOF - 0.02), (s * 0.8, 0.6, 0), n=3, spread_deg=14, elev=40, mat=PAINT)
        K.antenna(b, (s * 1.10, CAB_R - 0.10, CAB_ROOF), 1.4)
    # ------------------------------------------------------------ roof: RWS, engine grille, hatches, stowage
    K.protector_rws(veh, "RWS", "Body", (0.0, -0.55, ROOF + 0.02), gun="m2")
    with V.bevel(b, 0.01):
        b.box((0.80, 0.70, 0.06), (0.60, 0.40, ROOF + 0.03), PAINT, L01)
    for k in range(7):
        b.box((0.66, 0.035, 0.03), (0.60, 0.12 + k * 0.095, ROOF + 0.07), "Paint_Black", L0, rot=A.rot_x(30))
    for tag, s in (("L", -1), ("R", 1)):
        h = veh.part("Hatch_" + tag, parent="Body", pivot=(s * 1.02, -2.55, ROOF + 0.03), axis="y", note="troop roof hatch, hinge at the outer edge")
        with V.bevel(h, 0.015):
            h.box((0.82, 1.00, 0.06), (s * 0.58, -2.55, ROOF + 0.04), PAINT, ALL)
        K.opening(sh, [(s * 0.22, -2.98, ROOF), (s * 0.94, -2.98, ROOF), (s * 0.94, -2.12, ROOF), (s * 0.22, -2.12, ROOF)], (0, 0, 1), depth=0.25, out=0.10)
        for yy in (-2.85, -2.25):
            h.box((0.08, 0.10, 0.06), (s * 0.98, yy, ROOF + 0.08), "Paint_Black", L0)
        V.handle(h, (s * 0.30, -2.70, ROOF + 0.07), (s * 0.30, -2.40, ROOF + 0.07), 0.05, (0, 0, 1), lods=L0)
    with V.bevel(b, 0.012):
        b.box((0.95, 0.65, 0.42), (-0.85, -1.70, ROOF + 0.21), PAINT, L01)       # roof stowage box (rear left)
    for yy in (-1.55, -1.85):
        b.box((0.10, 0.06, 0.06), (-1.34, yy, ROOF + 0.30), "Paint_Black", L0)
    # ------------------------------------------------------------ sides: stowage frames with chains, steps, details
    for s in (-1, 1):
        x = s * (HW + 0.015)
        with V.bevel(b, 0.008):
            b.box((0.05, 1.70, 0.50), (x + s * 0.02, -2.35, 1.92), PAINT, L01)
        for k in range(4):
            for z in (1.80, 2.00):
                b.box((0.02, 0.30, 0.06), (x + s * 0.05, -3.00 + k * 0.42, z), "Paint_Black", L0)
        # snow chains hanging on the frame in sagging bundles (photos): several strands per bundle
        for k in range(3):
            y0 = -3.02 + k * 0.52
            for j in range(4):
                sag = 0.20 + 0.05 * j
                dx = s * (0.06 + 0.012 * j)
                pts = [(x + dx, y0 + 0.40 * q / 8, 2.02 - sag * math.sin(math.pi * q / 8) - 0.02 * j) for q in range(9)]
                b.tube(pts, 0.018, "Steel_Dark", L0, segs=5)
            b.tube([(x + s * 0.07, y0 + 0.05, 1.98), (x + s * 0.09, y0 + 0.2, 1.80), (x + s * 0.08, y0 + 0.35, 1.98)], 0.035, "Steel_Dark", (1,), segs=6)   # LOD1 stand-in
        # side armour bolts / lifting eyes / tail lamps / fuel filler
        V.bolts(b, [(x + s * 0.01, yy, zz) for yy in (-0.2, -1.2, -3.2) for zz in (1.45, 2.1)], (1, 0, 0), r=0.018)
        b.box((0.06, 0.10, 0.14), (s * (HW - 0.10), YR + 0.35, ROOF + 0.05), "Paint_Black", L0)
        K.lamp(b, (s * (HW - 0.18), YR - 0.02, 1.62), (0, -1, 0), lods=L0, square=True, w=0.18, h=0.08, lens="Reflector_Red", depth=0.04)
        K.lamp(b, (s * (HW + 0.01), -0.05, 1.42), (s, 0, 0), lods=L0, square=True, w=0.06, h=0.04, lens="Plastic_Orange", depth=0.03)
        # step plates on the front wheel station (to reach the cab doors)
        b.box((0.22, 0.40, 0.03), (s * (HW - 0.05), 1.55, 1.285), "Paint_Black", L0)
        # wheel station suspension: arms + dampers behind the wheels
        for i, yc in enumerate(AXLES):
            b.box((0.42, 0.14, 0.08), (s * 0.95, yc + 0.10, 0.58), "Paint_Black", L01)
            b.box((0.38, 0.10, 0.06), (s * 0.92, yc - 0.10, 0.92), "Paint_Black", L0)
            b.cyl_between((s * 0.90, yc + 0.20, 0.60), (s * 0.80, yc + 0.22, 1.20), 0.045, "Steel_Dark", L0, segs=8)
            b.cyl_between((s * 0.70, yc, 0.62), (s * 1.10, yc, R_TYRE), 0.05, "Steel_Dark", L0, segs=8)
    # ------------------------------------------------------------ rear: door, lamps, tow
    rd = veh.part("Door_Rear", parent="Body", pivot=(0.62, YR - 0.02, 1.6), axis="z", note="rear troop door, hinge on the right")
    rds = veh.shell("Door_Rear")
    with V.bevel(rds, 0.015):
        V.plate(rds, [(0.60, YR - 0.03, 0.92), (-0.60, YR - 0.03, 0.92), (-0.60, YR - 0.03, 2.12), (0.60, YR - 0.03, 2.12)], 0.05, PAINT, ALL)
    K.window(rd, [(-0.18, YR - 0.08, 1.80), (0.18, YR - 0.08, 1.80), (0.18, YR - 0.08, 1.98), (-0.18, YR - 0.08, 1.98)], (0, -1, 0), frame=0.03,
             cut=rds, depth=0.12)
    K.opening(sh, [(0.54, YR + 0.06, 0.98), (-0.54, YR + 0.06, 0.98), (-0.54, YR + 0.06, 2.06), (0.54, YR + 0.06, 2.06)], (0, -1, 0), depth=0.30, out=0.20)
    # interior: driver / commander seats and panel, troop seats along both walls, racks
    b.box((2.2, 0.35, 0.30), (0, CAB_F - 0.30, 1.85), "Plastic_Black", L0)
    for s in (-1, 1):
        b.box((0.50, 0.50, 0.12), (s * 0.60, 1.40, 1.30), "Canvas_Green", L0)
        b.box((0.50, 0.12, 0.70), (s * 0.60, 1.12, 1.68), "Canvas_Green", L0)
        for k in range(5):
            y = 0.30 - k * 0.62
            b.box((0.45, 0.50, 0.10), (s * 0.95, y, 1.42), "Canvas_Green", L0)
            b.box((0.10, 0.50, 0.65), (s * 1.24, y, 1.78), "Canvas_Green", L0)
        b.box((0.20, 3.2, 0.20), (s * 1.20, -1.2, 2.05), "Paint_OD", L0)          # overhead stowage
    b.cyl(0.32, 0.32, 0.25, (0.0, -0.55, ROOF - 0.20), "Paint_Grey", L0, segs=16)     # RWS basket
    V.handle(rd, (-0.45, YR - 0.08, 1.55), (-0.45, YR - 0.08, 1.30), 0.05, (0, -1, 0), lods=L01)
    for zh in (1.10, 1.95):
        rd.box((0.08, 0.08, 0.16), (0.64, YR - 0.08, zh), "Paint_Black", L0)
    for s in (-1, 1):
        K.tow_eye(b, (s * 0.95, YR + 0.02, 1.0), (0, -1, 0))
        b.box((0.22, 0.24, 0.05), (s * 0.95, YR + 0.05, 0.86), "Paint_Black", L0)   # rear step
    K.towing_pintle(b, (0, YR - 0.05, 0.85))
    b.box((0.30, 0.02, 0.10), (-0.95, YR - 0.03, 1.30), "Paint_Yellow", L0)
    # ------------------------------------------------------------ wheels
    K.wheel_template(veh, "WheelPatria", R_TYRE, W_TYRE, R_RIM, lugs=26, style="xzl", rim_mat="Paint_Green", nuts=10, beadlock=True)
    K.wheels(veh, "WheelPatria", AXLES, TRACK, R_TYRE, steer=(1, 2))
    # ------------------------------------------------------------ collision, markers, metadata
    veh.col_between((-HW, YR, 0.48), (HW, CAB_F, ROOF))
    veh.col_between((-1.1, CAB_F, 0.9), (1.1, YF, 1.8))
    veh.col_between((-HW, CAB_R, ROOF), (HW, CAB_F, CAB_ROOF))
    veh.col_between((-0.5, -1.1, ROOF), (0.5, 0.0, ROOF + 0.85))
    veh.marker("DOOR_REAR", (0.0, YR - 0.9, 0.0), note="rear troop door")
    veh.marker("DOOR_FL", (-(HW + 0.7), 1.4, 0.0), yaw=90, note="driver door")
    veh.marker("DOOR_FR", (HW + 0.7, 1.4, 0.0), yaw=-90, note="commander door")
    veh.marker("SEAT_DRIVER", (-0.55, 1.45, 1.55))
    veh.marker("SEAT_COMMANDER", (0.55, 1.45, 1.55))
    for k in range(5):
        for s in (-1, 1):
            veh.marker("SEAT_%d" % (k * 2 + (1 if s < 0 else 2)), (s * 0.70, -0.6 - k * 0.6, 1.20), yaw=-90 * s, note="troop seat")
    veh.marker("TOW_REAR", (0.0, YR - 0.15, 0.85))
    veh.meta.update({
        "reference": "Patria 6x6 (CAVS); RWS: Kongsberg Protector RS4 (Norwegian command variant)",
        "dimensions_m": {"length": LEN, "width": round(2 * HW, 2), "hull_roof": ROOF, "cab_roof": CAB_ROOF,
                         "axles_y": AXLES, "axle_spacing_est": 1.55, "track_est": TRACK, "tyre": "14.00 R20 class, d %.2f" % (2 * R_TYRE)},
        "paint": "Camo_NATO3",
    })
    veh.qa = {"tol": 0.06}
    return veh


BUILDERS = {ID: build}
DETAILS = {ID: {
    "bow": ((0.0, 2.6, 1.4), 5.0, 30, 12, 50),
    "wheels": ((-HW, -0.8, 0.7), 5.5, 72, 6, 50),
}}
