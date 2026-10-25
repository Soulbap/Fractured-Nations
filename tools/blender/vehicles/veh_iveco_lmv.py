"""VEH-01 Iveco LMV, Norwegian Army configuration (Forsvaret "LAV"; Protector RS4 RWS on the
roof as on the Norwegian vehicles of the 2010s-2020s).

Reference: assets/military/vehicles/_references/iveco_lmv/ (notes.md, manifest.json).
Dimensions used (Iveco data / Wikipedia, see notes): length 4.87 m, body width 2.00 m
(2.05 m over the flares), roof 2.05 m, wheelbase 3.20 m, track ~1.72 m (estimated from
photos), tyres 335/80 R20 (diameter 1.04 m), ground clearance ~0.47 m.
"""
import math

import ap_lib as A
import ap_vehicle as V
import veh_kit as K

ALL, L01, L0, L12, L2 = A.ALL, A.L01, A.L0, A.L12, A.L2

ID = "iveco_lmv"
PAINT = "Paint_Green"

LEN = 4.87
YF, YR = LEN / 2, -LEN / 2
WB = 3.20
YA1 = 1.68
YA2 = YA1 - WB
TRACK = 1.72
R_TYRE = 0.52
W_TYRE = 0.335
R_RIM = 0.254
HW = 0.99           # body half width at the belt
BELT = 1.38         # bottom of the side windows / top of the lower body
ROOF = 2.05
CABIN_F = 1.02      # windscreen base (y)
CABIN_T = 0.62      # windscreen top (y)
ROOF_R = -2.33      # rear end of the roof


def lower_outline(bottom_cut=True):
    """Closed side outline (y, z) of the lower body: front bottom, up the nose, back over the
    bonnet and the belt line, down the rear, then forward along the bottom with the wheel
    arches cut out (bottom_cut) or with a flat floor (the core between the wheels)."""
    top = [(YF - 0.02, 0.60), (YF, 0.86), (YF - 0.03, 1.20), (YF - 0.10, 1.25), (1.60, 1.32), (CABIN_F + 0.02, 1.37), (CABIN_F - 0.02, BELT),
           (YR + 0.06, BELT), (YR, BELT - 0.04), (YR, 0.62)]
    if not bottom_cut:
        return top + [(YR + 0.15, 0.58), (YF - 0.15, 0.58)]
    ra = 0.63
    bottom = [(YR + 0.20, 0.62)]
    bottom += K.arc_pts(YA2, 0.50, ra, 172, 8, 14)          # rear arch, rear end over the top to the front end
    bottom += [(YA2 + 0.66, 0.66), (YA1 - 0.66, 0.66)]
    bottom += K.arc_pts(YA1, 0.50, ra, 172, 8, 14)
    bottom += [(YF - 0.15, 0.62)]
    return top + bottom


def cabin_half(y, top_z, belt=BELT + 0.0):
    """Half cross-section of the cabin (above the belt) with tumblehome."""
    return [(0.0, belt - 0.02), (HW - 0.01, belt - 0.02), (HW, belt + 0.03), (HW - 0.05, belt + (top_z - belt) * 0.85),
            (HW - 0.12, top_z - 0.01), (HW - 0.18, top_z), (0.0, top_z + 0.01)]


def side_x(z):
    """x of the cabin side (tumblehome) at height z."""
    t = (z - (BELT + 0.03)) / ((ROOF - BELT) * 0.85 - 0.03)
    return HW - 0.05 * max(0.0, min(1.0, t))


def build():
    veh = V.VehicleAsset(ID, "Iveco LMV (Norwegian Army)", "Light tactical vehicle",
                         "Iveco Light Multirole Vehicle, Norwegian Army configuration with Kongsberg Protector RS4 RWS.")
    b = veh.part("Body", note="hull / body")
    sh = veh.shell("Body")

    # ------------------------------------------------------------ lower body
    with V.bevel(sh, 0.03, lods=(0, 1)):
        side = lower_outline(True)
        V.extrude_x(sh, side, HW - 0.36, HW, PAINT, ALL)
        V.extrude_x(sh, side, -HW, -HW + 0.36, PAINT, ALL)
        core = lower_outline(False)
        V.extrude_x(sh, core, -HW + 0.34, HW - 0.34, PAINT, ALL)
    # ------------------------------------------------------------ cabin with raked windscreen
    with V.bevel(sh, 0.025, lods=(0, 1)):
        st = [(CABIN_F, cabin_half(CABIN_F, BELT + 0.05)),
              (CABIN_T, cabin_half(CABIN_T, ROOF)),
              (ROOF_R + 0.05, cabin_half(ROOF_R, ROOF)),
              (ROOF_R - 0.04, cabin_half(ROOF_R, ROOF - 0.06))]
        V.hull_loft(sh, st, PAINT, ALL)
    # crew cell: the interior volume (floor 0.78 m, wheel housings left in the lower corners)
    def cav(top):
        return [(0.0, 0.78), (0.58, 0.78), (0.58, 1.20), (HW - 0.07, 1.22), (HW - 0.07, BELT + 0.05),
                (side_x(top - 0.15) - 0.07, top - 0.15), (HW - 0.27, top), (0.0, top)]
    K.cavity(sh, [(CABIN_F - 0.08, cav(1.50)), (CABIN_T - 0.05, cav(ROOF - 0.07)), (ROOF_R + 0.04, cav(ROOF - 0.07))], "Paint_Grey")
    # bonnet centre panel (raised) and the cowl
    with V.bevel(b, 0.012):
        b.box((1.10, 1.20, 0.03), (0, 1.80, 1.31), PAINT, L01, rot=A.rot_x(-3.5))
    b.box((1.70, 0.10, 0.06), (0, CABIN_F + 0.07, 1.39), "Paint_Black", L0)

    # ------------------------------------------------------------ windows
    wf = [(HW - 0.14, CABIN_F - 0.03, BELT + 0.08), (-(HW - 0.14), CABIN_F - 0.03, BELT + 0.08),
          (-(HW - 0.19), CABIN_T + 0.05, ROOF - 0.08), ((HW - 0.19), CABIN_T + 0.05, ROOF - 0.08)]
    K.window(b, wf, (0, 1, 0.6), frame=0.05, proud=0.03, cut=sh)
    for s in (-1, 1):
        b.box((0.45, 0.02, 0.02), (s * 0.30, CABIN_F - 0.06, BELT + 0.10), "Paint_Black", L0, rot=A.rot_z(s * 8))
    # rear compartment side panel (no window on the Norwegian LAV), antenna mount cross plate
    for s in (-1, 1):
        x = s * (HW + 0.004)
        b.box((0.012, 0.36, 0.30), (x, -1.80, 1.62), PAINT, L0, bevel=0.01)

    # ------------------------------------------------------------ doors (separate parts)
    doors = [("FL", -1, 0.96, -0.08), ("FR", 1, 0.96, -0.08), ("RL", -1, -0.13, -1.12), ("RR", 1, -0.13, -1.12)]
    for tag, s, y0, y1 in doors:
        d = veh.part("Door_" + tag, parent="Body", pivot=(s * (HW + 0.01), y0 - 0.02, 1.2), axis="z",
                     note="door, hinge at the front edge")
        ds = veh.shell("Door_" + tag)
        z0, z1 = 0.70, BELT
        xo = s * (HW + 0.02)
        zt = ROOF - 0.10
        yw0 = y0
        if tag[0] == "F":
            yw0 = min(y0, CABIN_F - 0.10 - (zt - BELT) * (CABIN_F - CABIN_T) / (ROOF - BELT) * 0.9)
        # the rear doors are cut around the rear wheel arch
        lower = [(xo, y0, z0), (xo, y1, z0), (xo, y1, z1 + 0.02), (xo, y0, z1 + 0.02)] if tag[0] == "F" else             [(xo, y0, z0), (xo, -0.84, z0), (xo, -0.96, 1.17), (xo, y1, 1.17), (xo, y1, z1 + 0.02), (xo, y0, z1 + 0.02)]
        with V.bevel(ds, 0.012):
            V.plate(ds, lower, 0.03, PAINT, ALL)
            xb, xt = s * (side_x(BELT + 0.02) + 0.02), s * (side_x(zt) + 0.02)
            V.plate(ds, [(xb, y0, BELT + 0.02), (xb, y1, BELT + 0.02), (xt, y1, zt), (xt, yw0, zt)], 0.03, PAINT, ALL)
        # the door opening in the body behind it
        xs = s * HW
        if tag[0] == "F":
            op = [(xs, y0 - 0.03, 0.76), (xs, y1 + 0.03, 0.76), (xs, y1 + 0.03, zt - 0.03), (xs, yw0 + 0.03, zt - 0.03), (xs, y0 - 0.03, BELT + 0.04)]
        else:
            op = [(xs, y0 - 0.03, 0.76), (xs, -0.83, 0.76), (xs, -0.95, 1.20), (xs, y1 + 0.03, 1.20), (xs, y1 + 0.03, zt - 0.03), (xs, y0 - 0.03, zt - 0.03)]
        K.opening(sh, op, (s, 0, 0), depth=0.48, out=0.12, interior="Paint_Grey")
        wy0, wy1 = (y0 - 0.10, y1 + 0.08) if tag[0] == "F" else (y0 - 0.08, y1 + 0.10)
        K.window(d, [(s * (side_x(BELT + 0.10) + 0.035), wy0, BELT + 0.10), (s * (side_x(BELT + 0.10) + 0.035), wy1, BELT + 0.10),
                     (s * (side_x(zt - 0.06) + 0.035), wy1, zt - 0.06),
                     (s * (side_x(zt - 0.06) + 0.035), wy0 - (0.25 if tag[0] == "F" else 0.0), zt - 0.06)],
                 (s, 0, 0), frame=0.04, proud=0.035, cut=ds, depth=0.10)
        # handle, lock and the two hinges
        yh = y1 + 0.14
        V.handle(d, (s * (HW + 0.05), yh + 0.10, 1.13), (s * (HW + 0.05), yh - 0.06, 1.13), 0.04, (s, 0, 0), r=0.013, lods=L01)
        d.cyl(0.018, 0.018, 0.02, (s * (HW + 0.055), yh + 0.18, 1.13), "Steel_Dark", L0, axis=(1, 0, 0), segs=8)
        for zh in (0.85, 1.28):
            d.box((0.05, 0.06, 0.10), (s * (HW + 0.045), y0 + 0.01, zh), "Paint_Black", L0)
        # armour bolts along the door frame
        V.bolts(d, [(s * (HW + 0.05), y, z) for y in (y0 - 0.06, y1 + 0.06) for z in (0.78, 1.0, 1.24)
                    if tag[0] == "F" or y > -0.84 or z > 1.17], (1, 0, 0))

    # ------------------------------------------------------------ rear door
    rd = veh.part("Door_Rear", parent="Body", pivot=(0.62, YR - 0.01, 1.3), axis="z", note="rear door, hinge on the right")
    rds = veh.shell("Door_Rear")
    with V.bevel(rds, 0.012):
        V.plate(rds, [(0.62, YR - 0.025, 0.72), (-0.62, YR - 0.025, 0.72), (-0.62, YR - 0.025, 1.90), (0.62, YR - 0.025, 1.90)], 0.03, PAINT, ALL)
    K.opening(sh, [(0.56, YR, 0.80), (-0.56, YR, 0.80), (-0.56, YR, 1.84), (0.56, YR, 1.84)], (0, -1, 0), depth=0.30, out=0.10, interior="Paint_Grey")
    for zz in (0.95, 1.35, 1.70):
        rd.box((0.30, 0.03, 0.025), (0.0, YR - 0.05, zz), "Paint_Black", L0)
    V.handle(rd, (-0.48, YR - 0.05, 1.25), (-0.48, YR - 0.05, 1.05), 0.05, (0, -1, 0), lods=L01)
    for zh in (0.90, 1.70):
        rd.box((0.06, 0.06, 0.12), (0.64, YR - 0.05, zh), "Paint_Black", L0)

    # ------------------------------------------------------------ front: grille, lamps, bumper
    yf = YF + 0.005
    for s in (-1, 1):
        x0, x1 = (0.08, 0.40) if s > 0 else (-0.40, -0.08)
        b.box((x1 - x0, 0.04, 0.24), ((x0 + x1) / 2, YF - 0.012, 1.03), "Paint_Black", L01)
        V.slats(b, x0 + 0.01, x1 - 0.01, 0.92, 1.14, YF + 0.01, 7, 0.03, 0.018, PAINT, L0, vertical=True, tilt=0)
        K.lamp(b, (s * 0.72, YF + 0.01, 0.98), (0, 1, 0), r=0.085, depth=0.05, housing=PAINT)
        K.lamp(b, (s * 0.55, YF + 0.01, 0.92), (0, 1, 0), r=0.045, depth=0.04, housing="Paint_Black")
        K.lamp(b, (s * 0.80, YF - 0.01, 1.16), (0, 1, 0), lods=L0, square=True, w=0.07, h=0.04, lens="Plastic_Orange", depth=0.04)
        # recovery eyes
        K.tow_eye(b, (s * 0.62, YF + 0.10, 0.66), (0, 1, 0))
        K.antenna(b, (s * 0.88, YF - 0.20, 1.27), 1.5 if s > 0 else 1.1)
    b.box((0.30, 0.02, 0.08), (0, YF + 0.01, 1.20), "Paint_Black", L0)          # IVECO badge plate
    b.box((0.36, 0.02, 0.10), (0, YF + 0.02, 0.86), "Paint_Yellow", L0)         # Norwegian military plate
    with V.bevel(b, 0.015):
        b.box((1.96, 0.18, 0.20), (0, YF + 0.07, 0.68), PAINT, ALL)              # bumper
        b.box((0.60, 0.16, 0.18), (0, YF + 0.14, 0.70), "Paint_Black", L01)      # winch housing
    b.cyl(0.07, 0.07, 0.40, (0, YF + 0.16, 0.70), "Steel_Dark", L0, axis=(1, 0, 0), segs=12)

    # ------------------------------------------------------------ roof: hatch ring, light bar, snorkel, rails
    with V.bevel(b, 0.01):
        b.cyl(0.45, 0.47, 0.06, (0, -0.25, ROOF + 0.04), PAINT, L01, segs=28)
        b.box((1.40, 0.14, 0.10), (0, CABIN_T - 0.02, ROOF + 0.06), PAINT, L01)
    for k in range(8):
        x = -0.56 + k * 0.16
        K.lamp(b, (x, CABIN_T + 0.06, ROOF + 0.08), (0, 1, 0), r=0.035, depth=0.06, housing="Paint_Black", lods=L0)
    for s in (-1, 1):
        b.tube([(s * 0.78, -0.95, ROOF + 0.01), (s * 0.80, -0.95, ROOF + 0.10), (s * 0.80, ROOF_R + 0.20, ROOF + 0.10), (s * 0.78, ROOF_R + 0.20, ROOF + 0.01)],
               0.02, "Paint_Black", L01, segs=6)
        K.antenna(b, (s * 0.80, ROOF_R + 0.12, ROOF + 0.01), 1.6)
    # snorkel up the right A-pillar
    sn = [(HW + 0.07, 1.30, 1.33), (HW + 0.08, CABIN_F - 0.05, BELT + 0.05), (HW + 0.04, CABIN_T + 0.10, ROOF - 0.10), (HW - 0.02, CABIN_T + 0.02, ROOF + 0.10)]
    b.tube(sn, 0.075, "Paint_Black", L01, segs=12)
    b.cyl(0.11, 0.09, 0.14, (HW - 0.02, CABIN_T + 0.02, ROOF + 0.20), "Paint_Black", L01, segs=12)
    b.cyl(0.13, 0.13, 0.03, (HW - 0.02, CABIN_T + 0.02, ROOF + 0.28), "Paint_Black", L0, segs=12)

    # ------------------------------------------------------------ mirrors, flares, steps
    for s in (-1, 1):
        K.mirror(b, (s * (HW + 0.02), CABIN_F - 0.08, BELT + 0.12), (s * (HW + 0.22), CABIN_F + 0.02, BELT + 0.36), size=(0.04, 0.22, 0.30))
        for yc in (YA1, YA2):
            K.arch_flare(b, yc, 0.50, 0.63, 10, 170, s * (HW - 0.02), s * (HW + 0.07), 0.07, "Rubber", L01)
        # tubular side steps under the doors
        x = s * (HW + 0.02)
        b.tube([(x, YA1 - 0.70, 0.62), (s * (HW + 0.10), YA1 - 0.78, 0.50), (s * (HW + 0.10), YA2 + 0.80, 0.50), (x, YA2 + 0.72, 0.62)],
               0.025, "Paint_Black", L01, segs=8)
        b.box((0.12, 1.30, 0.03), (s * (HW + 0.08), (YA1 + YA2) / 2, 0.51), "Paint_Black", L0)
        # rear lamp clusters in the bumper corners
        K.lamp(b, (s * 0.68, YR - 0.02, 0.90), (0, -1, 0), lods=L0, square=True, w=0.22, h=0.08, lens="Reflector_Red", depth=0.05)
        b.box((0.30, 0.02, 0.06), (s * 0.68, YR - 0.02, 1.02), "Paint_Yellow", L0)
        b.box((0.30, 0.02, 0.36), (s * 0.70, YR - 0.05, 0.44), "Rubber", L01)      # mud flaps
        K.shackle(b, (s * 0.30, YR - 0.08, 0.66), axis=(0, 1, 0))
    with V.bevel(b, 0.015):
        b.box((1.96, 0.16, 0.22), (0, YR - 0.06, 0.70), PAINT, ALL)              # rear bumper
    K.towing_pintle(b, (0, YR - 0.18, 0.64))

    # ------------------------------------------------------------ underbody: V plate, suspension, axles
    b.loft([[(-0.62, YA1 - 0.55, 0.60), (0.62, YA1 - 0.55, 0.60), (0.0, YA1 - 0.55, 0.50)],
            [(-0.62, YA2 + 0.55, 0.60), (0.62, YA2 + 0.55, 0.60), (0.0, YA2 + 0.55, 0.50)]], "Paint_Black", ALL, closed=True, cap=True, recalc=True)
    for yc in (YA1, YA2):
        b.box((0.60, 0.40, 0.30), (0, yc, 0.52), "Steel_Dark", L01)              # differential / gearbox
        for s in (-1, 1):
            b.box((0.55, 0.10, 0.06), (s * 0.55, yc + 0.12, 0.45), "Paint_Black", L01)   # lower wishbone
            b.box((0.48, 0.08, 0.05), (s * 0.52, yc - 0.10, 0.70), "Paint_Black", L0)    # upper wishbone
            K.coil_spring(b, (s * 0.58, yc + 0.02, 0.50), (s * 0.55, yc + 0.02, 1.00), 0.07)
            b.cyl_between((s * 0.58, yc + 0.02, 0.48), (s * 0.55, yc + 0.02, 1.02), 0.025, "Steel_Dark", L0, segs=8)
            b.cyl_between((0, yc, 0.52), (s * 0.80, yc, R_TYRE), 0.035, "Steel_Dark", L0, segs=8)   # drive shaft
    b.cyl_between((0, YA1 - 0.2, 0.55), (0, YA2 + 0.2, 0.55), 0.04, "Steel_Dark", L0, segs=8)
    b.cyl_between((0.45, YA2 - 0.3, 0.58), (0.50, YR - 0.05, 0.56), 0.04, "Steel_Dark", L0, segs=8)          # exhaust

    # ------------------------------------------------------------ interior (seen through the glass)
    b.box((1.70, 0.40, 0.30), (0, CABIN_F - 0.18, BELT - 0.02), "Plastic_Black", L0)
    for s in (-1, 1):
        for yy in (0.25, -0.75):
            b.box((0.50, 0.50, 0.12), (s * 0.45, yy, 0.98), "Canvas_Green", L0)
            b.box((0.50, 0.10, 0.62), (s * 0.45, yy - 0.26, 1.30), "Canvas_Green", L0, rot=A.rot_x(-10))
    for s in (-1, 1):
        b.box((0.42, 1.00, 0.10), (s * 0.40, -1.75, 0.98), "Canvas_Green", L0)      # rear compartment benches
        b.box((0.06, 1.00, 0.55), (s * 0.60, -1.75, 1.30), "Canvas_Green", L0)
        b.box((0.30, 0.40, 0.45), (s * 0.30, -0.20, 1.40), "Paint_OD", L0)          # radio racks between the seats
    b.cyl(0.24, 0.24, 0.30, (0.0, -0.25, ROOF - 0.20), "Paint_Grey", L0, segs=16)    # RWS feed-through
    b.box((1.70, 0.12, 0.10), (0, CABIN_F - 0.20, BELT + 0.12), "Plastic_Black", L0)  # dash top / screens
    for x in (-0.45, 0.05, 0.45):
        b.box((0.22, 0.03, 0.16), (x, CABIN_F - 0.26, BELT + 0.24), "Glass", L0, rot=A.rot_x(20))
    sw = veh.part("SteeringWheel", parent="Body", pivot=(-0.45, CABIN_F - 0.42, 1.48), axis="column", note="steering wheel (rotates about the column)")
    V.revolve(sw, [(0.17, -0.015), (0.19, 0.0), (0.17, 0.015), (0.15, 0.0), (0.17, -0.015)], (-0.45, CABIN_F - 0.42, 1.48),
              (0, 0.6, 0.8), "Plastic_Black", L0, segs=16)
    sw.cyl_between((-0.45, CABIN_F - 0.42, 1.48), (-0.45, CABIN_F - 0.20, 1.20), 0.025, "Plastic_Black", L0, segs=6)
    for k in range(3):
        a = math.radians(90 + 120 * k)
        sw.cyl_between((-0.45, CABIN_F - 0.42, 1.48), (-0.45 + 0.17 * math.cos(a), CABIN_F - 0.42 - 0.6 * 0.17 * math.sin(a) * 0.8,
                                                         1.48 + 0.8 * 0.17 * math.sin(a) * 0.6), 0.012, "Plastic_Black", L0, segs=5)

    # ------------------------------------------------------------ wheels
    K.wheel_template(veh, "WheelLMV", R_TYRE, W_TYRE, R_RIM, lugs=24, style="xzl", rim_mat=PAINT, nuts=8, beadlock=True)
    K.wheels(veh, "WheelLMV", [YA1, YA2], TRACK, R_TYRE, parent=None, steer=(1,))

    # ------------------------------------------------------------ remote weapon station
    K.protector_rws(veh, "RWS", "Body", (0.0, -0.25, ROOF + 0.07), gun="m2", scale=0.92)

    # ------------------------------------------------------------ collision, markers, metadata
    veh.col_between((-HW, YR - 0.15, 0.55), (HW, YF + 0.15, BELT))
    veh.col_between((-HW + 0.05, ROOF_R, BELT), (HW - 0.05, CABIN_T, ROOF))
    veh.col_between((-0.45, -0.75, ROOF), (0.45, 0.30, ROOF + 0.65))
    for tag, s, yy in (("FL", -1, 0.55), ("FR", 1, 0.55), ("RL", -1, -0.55), ("RR", 1, -0.55)):
        veh.marker("DOOR_" + tag, (s * (HW + 0.6), yy, 0.0), yaw=90 if s < 0 else -90, note="stand point outside the door")
    veh.marker("DOOR_REAR", (0.0, YR - 0.7, 0.0), yaw=0, note="rear door")
    for i, (x, y) in enumerate(((-0.45, 0.25), (0.45, 0.25), (-0.45, -0.75), (0.45, -0.75)), 1):
        veh.marker("SEAT_%d" % i, (x, y, 1.05), note="driver" if i == 1 else ("commander" if i == 2 else "passenger"))
    veh.marker("SEAT_GUNNER", (0.0, -0.25, 1.05), note="RWS operator (inside)")
    veh.marker("TOW_REAR", (0.0, YR - 0.25, 0.64), note="towing pintle")
    veh.meta.update({
        "reference": "Iveco LMV, Norwegian Army (LAV) with Kongsberg Protector RS4",
        "dimensions_m": {"length": LEN, "width_body": round(2 * HW, 2), "roof": ROOF, "wheelbase": WB, "track_est": TRACK,
                         "tyre": "335/80 R20, d %.2f" % (2 * R_TYRE)},
        "paint": "Paint_Green (faction paint swaps Paint_Green)",
    })
    veh.qa = {"tol": 0.06}
    return veh


BUILDERS = {ID: build}
DETAILS = {ID: {
    "wheel": ((-HW, YA1, 0.6), 3.0, 65, 8, 50),
    "roof": ((0.0, -0.2, ROOF + 0.3), 3.6, 150, 30, 50),
}}
