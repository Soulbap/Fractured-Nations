"""Vehicle visual prototypes (ASSET-PRODUCTION-01). No driving logic, physics, combat or
logistics: meshes, materials, LODs and attachment points only.

  truck_6x6   modern 6x6 logistics truck (HX-class): 8.7 x 2.55 x 3.3 m, cab-forward
              armour-ready cab, dropside cargo bed with tarpaulin over bows, 1.25 m tyres.
  apc_8x8     modern 8x8 wheeled APC (Boxer / Patria AMV class): 7.9 x 2.99 x 2.4 m hull,
              sloped glacis, remote weapon station, rear ramp, 1.2 m tyres.

Front = +Y. Wheels are part of the body mesh for the prototype; WHEEL_* markers give
each wheel centre (marker x = track side, metadata wheel radius/width), so a vehicle
implementation can replace them with the separate wheel assets (wheel_truck, wheel_apc)
and drive suspension from SUSP_* markers. Doors (DOOR_*), seats (SEAT_*), cargo
(CARGO_*), tow and weapon points are markers as well.
"""
import math

from ap_kit import Frame

ALL = (0, 1, 2)
L01 = (0, 1)
L0 = (0,)
L12 = (1, 2)
L2 = (2,)


def _wheel(a, x, y, r, w, hub_mat="Paint_Green", lods=ALL, side=1):
    """Tyre with tread blocks (LOD0), rim and hub. Axis along X."""
    a.cyl(r, r, w, (x, y, r), "Rubber", lods, axis=(1, 0, 0), segs=24)
    a.cyl(r * 0.92, r * 0.92, w + 0.01, (x, y, r), "Rubber", L0, axis=(1, 0, 0), segs=24)
    for k in range(18):
        ang = 2 * math.pi * k / 18
        a.box((w * 0.9, 0.09, 0.05), (x, y + (r + 0.005) * math.cos(ang), r + (r + 0.005) * math.sin(ang)), "Rubber", L0,
              rot=__import__("mathutils").Matrix.Rotation(-ang, 3, "X"))
    a.cyl(r * 0.55, r * 0.55, 0.04, (x + side * (w / 2), y, r), hub_mat, L01, axis=(1, 0, 0), segs=16)
    a.cyl(r * 0.18, r * 0.18, 0.10, (x + side * (w / 2 + 0.03), y, r), "Steel_Dark", L0, axis=(1, 0, 0), segs=10)


def truck_6x6(A):
    a = A.Asset("truck_6x6", "vehicle", "Logistics truck 6x6", "Vehicles",
                "Modern 6x6 military logistics truck (HX-class): 8.7 x 2.55 x 3.3 m, cab-forward cab, dropside cargo bed "
                "6.1 x 2.45 m with tarpaulin, 1.25 m tyres. Visual prototype.")
    W, r, tw = 2.55, 0.625, 0.40
    track = W / 2 - tw / 2 - 0.02
    axles = (2.75, -0.95, -2.40)
    # Chassis frame and underside.
    for sx in (-0.45, 0.45):
        a.box((0.12, 8.0, 0.30), (sx, -0.1, 1.00), "Paint_Black", L01)
    a.box((1.0, 7.8, 0.25), (0, -0.1, 0.95), "Paint_Black", L2)
    # Cab: lower body, upper cab with windscreen, roof hatch, grille, bumper, mirrors.
    a.box((W, 2.15, 1.15), (0, 3.15, 1.75), "Paint_Green", ALL, bevel=0.05)
    a.box((W - 0.06, 2.0, 1.05), (0, 3.05, 2.85), "Paint_Green", ALL, bevel=0.06)

    a.poly([(-1.15, 4.08, 2.45), (1.15, 4.08, 2.45), (1.10, 3.95, 3.25), (-1.10, 3.95, 3.25)], [(0, 1, 2, 3)][::-1], "Glass", ALL)
    for sx in (-1, 1):
        a.box((0.02, 1.2, 0.65), (sx * (W / 2 - 0.02), 3.1, 2.90), "Glass", L01)
        a.box((0.06, 0.35, 0.45), (sx * (W / 2 + 0.35), 3.85, 2.75), "Paint_Black", L0)
        a.cyl(0.02, 0.02, 0.35, (sx * (W / 2 + 0.17), 3.85, 2.75), "Steel_Dark", L0, axis=(1, 0, 0), segs=5)
        # Door outlines, handles, steps.
        a.box((0.01, 1.0, 1.55), (sx * (W / 2 + 0.002), 3.05, 2.30), "Paint_Black", L0)
        a.box((0.03, 0.15, 0.04), (sx * (W / 2 + 0.02), 2.70, 2.35), "Steel_Dark", L0)
        for z in (0.75, 1.15):
            a.box((0.35, 0.50, 0.04), (sx * (W / 2 - 0.10), 2.55, z), "Steel_Galv", L0)
        a.box((0.25, 0.25, 0.15), (sx * 0.95, 4.27, 1.35), "Lamp", L0)
    a.box((W, 0.25, 0.35), (0, 4.20, 1.05), "Paint_Black", L01, bevel=0.03)
    a.box((1.6, 0.04, 0.60), (0, 4.24, 1.70), "Paint_Black", L01)
    a.box((0.80, 0.80, 0.10), (0.4, 2.9, 3.40), "Paint_Green", L01)
    a.cyl(0.07, 0.07, 1.4, (-W / 2 + 0.15, 2.0, 2.9), "Steel_Dark", L01, segs=8)
    # Cargo bed with dropsides, tarpaulin over bows, toolbox, fuel tank, spare wheel.
    a.box((W, 6.1, 0.15), (0, -1.0, 1.32), "Paint_Green", ALL)
    for sx in (-1, 1):
        a.box((0.05, 6.1, 0.55), (sx * (W / 2 - 0.025), -1.0, 1.67), "Paint_Green", L01)
    a.box((W, 0.05, 0.55), (0, -4.05, 1.67), "Paint_Green", L01)
    prof = []
    for k in range(13):
        t = math.pi * k / 12
        prof.append((math.cos(t) * (W / 2), 1.95 + 0.95 * (math.sin(t) ** 0.5)))
    prof = [(W / 2, 1.90)] + prof + [(-W / 2, 1.90)]
    a.prism(prof, (0, 2.0, 0), (0, -4.05, 0), "Canvas_OD", ALL)
    for y in (-3.0, -1.5, 0.0, 1.5):
        a.tube([(x * 1.005, y, z + 0.005) for x, z in prof[1:-1]], 0.02, "Canvas_OD", L0, segs=4, cap=False)
    for sx in (-1, 1):
        a.box((0.04, 6.0, 0.03), (sx * (W / 2 + 0.01), -1.0, 1.95), "Paint_Black", L0)
    a.box((0.55, 1.2, 0.55), (W / 2 - 0.35, 0.8, 0.70), "Paint_Green", L01, bevel=0.03)
    a.cyl(0.30, 0.30, 1.0, (-W / 2 + 0.35, 0.85, 0.75), "Paint_Green", L01, axis=(0, 1, 0), segs=14)
    a.box((0.10, 0.25, 0.20), (0, -4.15, 0.95), "Steel_Dark", L0)
    for sx in (-1, 1):
        a.box((0.20, 0.05, 0.12), (sx * 1.0, -4.10, 1.15), "Reflector_Red", L0)
    a.sign([(0, 0), (1, 0), (1, 1), (0, 1)], (0, 4.33, 1.05), (-1, 0, 0), (0, 0, 1), 0.52, 0.12, __import__("ap_signs").rect("number_plate"), lods=L0)
    # Wheels and mudguards.
    for y in axles:
        for sx in (-1, 1):
            _wheel(a, sx * track, y, r, tw, side=sx)
            a.box((tw + 0.12, 1.45, 0.05), (sx * track, y, 2 * r + 0.10), "Paint_Black", L01)
    a.col_box((W, 2.2, 2.3), (0, 3.15, 2.25))
    a.col_box((W, 6.1, 2.0), (0, -1.0, 1.9))
    for i, y in enumerate(axles):
        for sx, s in ((-1, "L"), (1, "R")):
            a.marker("WHEEL_%d%s" % (i + 1, s), (sx * track, y, r), 0, "wheel centre, r=%.3f m, width %.2f m" % (r, tw))
            a.marker("SUSP_%d%s" % (i + 1, s), (sx * (track - 0.30), y, r + 0.45), 0, "suspension top mount")
    a.marker("DOOR_L", (-W / 2 - 0.05, 3.05, 1.6), 90, "driver door (left-hand drive)")
    a.marker("DOOR_R", (W / 2 + 0.05, 3.05, 1.6), -90, "co-driver door")
    a.marker("SEAT_Driver", (-0.55, 2.8, 2.25), 0)
    a.marker("SEAT_CoDriver", (0.55, 2.8, 2.25), 0)
    a.marker("SEAT_Hatch", (0.4, 2.9, 3.0), 0, "roof hatch / ring mount position")
    a.marker("CARGO_Bed", (0, -1.0, 1.40), 0, "cargo bed floor centre, 6.1 x 2.45 m, payload 10 t (8 pallets)")
    a.marker("CARGO_Rear", (0, -4.6, 0), 180, "loading point behind the tailgate")
    a.marker("TOW_Rear", (0, -4.20, 0.95), 180)
    a.lod_ranges = [[0, 40], [40, 160], [160, 1500]]
    a.ao_height, a.ao_strength = 1.4, 0.35
    a.meta["vehicle"] = {"length_m": 8.7, "width_m": W, "height_m": 3.3, "wheel_radius_m": r, "wheel_width_m": tw,
                         "axles_y": list(axles), "track_m": round(2 * track, 3), "payload_t": 10, "crew": 2}
    return a


def apc_8x8(A):
    a = A.Asset("apc_8x8", "vehicle", "Wheeled APC 8x8", "Vehicles",
                "Modern 8x8 wheeled armoured personnel carrier (Boxer / Patria AMV class): hull 7.9 x 2.99 x 2.4 m, "
                "sloped glacis, remote weapon station, rear ramp, 8 seats + crew 3. Visual prototype.")
    W, r, tw = 2.99, 0.60, 0.40
    track = W / 2 - tw / 2 - 0.12
    axles = (2.55, 1.10, -1.10, -2.55)
    zb = 0.55
    # Hull: lower hull (V-shaped belly), sloped sides above the wheels, glacis, roof.
    prof = [(-0.70, zb), (0.70, zb), (W / 2 - 0.20, zb + 0.45), (W / 2, zb + 0.95), (W / 2 - 0.25, zb + 1.85),
            (-(W / 2 - 0.25), zb + 1.85), (-W / 2, zb + 0.95), (-(W / 2 - 0.20), zb + 0.45)]
    a.prism(prof, (0, -3.95, 0), (0, 3.0, 0), "Paint_Green", ALL)
    # Sloped glacis: the hull section narrows and drops toward a low nose at y = 3.95.
    ring_a = [(x, 3.0, z) for x, z in prof]
    ring_b = [(x * 0.94, 3.95, zb + 0.25 + (z - zb) * 0.42) for x, z in prof]
    a.loft([ring_a, ring_b], "Paint_Green", ALL, closed=True, cap=True)
    # Roof details: driver hatch with periscopes (front left), commander hatch, RWS.
    zr = zb + 1.85
    a.cyl(0.32, 0.32, 0.08, (-0.75, 1.9, zr + 0.04), "Paint_Green", L01, segs=16)
    for k in range(3):
        a.box((0.10, 0.06, 0.08), (-0.95 + k * 0.2, 2.18, zr + 0.06), "Glass", L0)
    a.cyl(0.35, 0.35, 0.10, (0.6, 0.2, zr + 0.05), "Paint_Green", L01, segs=16)
    for k in range(6):
        ang = 2 * math.pi * k / 6
        a.box((0.08, 0.06, 0.09), (0.6 + 0.38 * math.cos(ang), 0.2 + 0.38 * math.sin(ang), zr + 0.12), "Glass", L0)
    # Remote weapon station: base, cradle, MG, sight box.
    a.cyl(0.40, 0.42, 0.30, (-0.2, -0.3, zr + 0.15), "Paint_Green", ALL, segs=16)
    a.box((0.55, 0.70, 0.35), (-0.2, -0.25, zr + 0.48), "Paint_Green", L01, bevel=0.03)
    a.box((0.30, 0.25, 0.30), (0.20, -0.05, zr + 0.55), "Paint_Green", L01, bevel=0.02)
    a.box((0.20, 0.02, 0.15), (0.20, 0.075, zr + 0.58), "Glass", L0)
    a.cyl(0.03, 0.025, 1.20, (-0.30, 0.55, zr + 0.52), "Steel_Dark", L01, axis=(0, 1, 0), segs=8)
    a.box((0.14, 0.60, 0.16), (-0.30, -0.05, zr + 0.52), "Steel_Dark", L01)
    a.box((0.25, 0.30, 0.20), (-0.55, -0.25, zr + 0.40), "Paint_Green", L0)
    # Smoke grenade dischargers, antennas, stowage, lights.
    for sx in (-1, 1):
        for k in range(4):
            a.cyl(0.04, 0.04, 0.20, (sx * (W / 2 - 0.45), 1.45 - k * 0.11, zr + 0.12), "Paint_Green", L0, axis=(sx * 0.4, 0.6, 0.7), segs=8)
        a.cyl(0.012, 0.004, 2.4, (sx * 1.05, -3.4, zr + 1.2), "Plastic_Black", L0, segs=5)
        a.box((0.20, 2.8, 0.30), (sx * (W / 2 + 0.04), -1.4, zb + 1.30), "Paint_Green", L01, bevel=0.02)
        a.box((0.18, 0.06, 0.10), (sx * 1.15, 3.70, zb + 0.95), "Lamp", L0)
        a.box((0.18, 0.04, 0.10), (sx * 1.25, -3.97, zb + 1.20), "Reflector_Red", L0)
    a.cyl(0.05, 0.05, 2.4, (0, 3.5, zb + 0.8), "Paint_Black", L0, axis=(1, 0, 0), segs=8)
    # Rear ramp outline, exhaust, tow hooks.
    a.box((1.6, 0.03, 1.6), (0, -3.97, zb + 1.00), "Paint_Black", L0)
    a.box((1.5, 0.04, 1.5), (0, -3.99, zb + 1.00), "Paint_Green", L01)
    for sx in (-1, 1):
        a.box((0.12, 0.15, 0.10), (sx * 0.9, 3.90, zb + 0.30), "Steel_Dark", L0)
    a.box((0.25, 0.10, 0.25), (W / 2 - 0.3, -2.0, zb + 1.60), "Paint_Black", L0)
    # Wheels.
    for y in axles:
        for sx in (-1, 1):
            _wheel(a, sx * track, y, r, tw, side=sx)
    a.col_box((W, 7.9, 1.9), (0, -0.0, zb + 0.95))
    a.col_box((1.0, 1.0, 0.8), (-0.2, -0.3, zr + 0.4))
    for i, y in enumerate(axles):
        for sx, s in ((-1, "L"), (1, "R")):
            a.marker("WHEEL_%d%s" % (i + 1, s), (sx * track, y, r), 0, "wheel centre, r=%.2f m, width %.2f m" % (r, tw))
            a.marker("SUSP_%d%s" % (i + 1, s), (sx * (track - 0.35), y, r + 0.40), 0, "suspension top mount")
    a.marker("DOOR_Ramp", (0, -4.0, zb + 0.2), 180, "rear ramp (hinge at the bottom), troops dismount here")
    a.marker("DOOR_Driver", (-0.75, 1.9, zr + 0.1), 0, "driver hatch")
    a.marker("DOOR_Commander", (0.6, 0.2, zr + 0.1), 0, "commander hatch")
    a.marker("SEAT_Driver", (-0.75, 1.9, zb + 0.85), 0)
    a.marker("SEAT_Commander", (0.6, 0.2, zb + 0.95), 0)
    a.marker("SEAT_Gunner", (0.2, -0.1, zb + 0.95), 0, "RWS operator station")
    for k in range(8):
        sx = -1 if k % 2 == 0 else 1
        a.marker("SEAT_Troop_%d" % (k + 1), (sx * 0.85, -1.0 - (k // 2) * 0.65, zb + 0.75), -sx * 90, "troop seat, faces inward")
    a.marker("WEAPON_RWS", (-0.30, 1.15, zr + 0.52), 0, "RWS muzzle (12.7 mm MG)")
    a.marker("TOW_Front", (0, 3.95, zb + 0.30), 0)
    a.lod_ranges = [[0, 40], [40, 160], [160, 1500]]
    a.ao_height, a.ao_strength = 1.2, 0.35
    a.meta["vehicle"] = {"length_m": 7.9, "width_m": W, "height_m": round(zr + 0.8, 2), "wheel_radius_m": r,
                         "wheel_width_m": tw, "axles_y": list(axles), "track_m": round(2 * track, 3), "crew": 3, "troops": 8}
    return a


def wheel_asset(A, aid, r, w, name):
    a = A.Asset(aid, "vehicle", name, "Vehicles", "Separate wheel (tyre, rim, hub) for vehicle implementations: radius %.3f m, width %.2f m. "
                "Origin at the wheel centre; axle along X." % (r, w))
    _wheel(a, 0, 0, r, w, side=1)
    a.lod_ranges = [[0, 40], [40, 160], [160, 800]]
    a.meta["wheel"] = {"radius_m": r, "width_m": w}
    # Wheel modelled standing on the ground; marker at its centre for mounting.
    a.marker("AXLE", (0, 0, r), 0, "wheel centre / axle")
    return a


BUILDERS = {
    "truck_6x6": truck_6x6,
    "apc_8x8": apc_8x8,
    "wheel_truck": lambda A: wheel_asset(A, "wheel_truck", 0.625, 0.40, "Truck wheel 14.00R20"),
    "wheel_apc": lambda A: wheel_asset(A, "wheel_apc", 0.60, 0.40, "APC wheel"),
}
