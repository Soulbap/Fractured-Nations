"""NATO-01 HK416N and NATO-02 HK417 (Norwegian Army configurations).

HK416N: Norway's standard rifle since 2008 (HK416 with 16.5" / 419 mm barrel, quad-rail handguard,
Aimpoint CompM4 red dot, vertical fore grip, HK steel magazine, HK telescopic stock). Proportions traced
from the Commons photograph of an HK416N (left side, references/hk416/01): 0.78 mm per pixel for the
0.98 m overall length (stock in a middle position).
HK417: 7.62 mm designated marksman rifle, 16" (406 mm) barrel, longer rail, 20-round 7.62 magazine,
Schmidt & Bender PM II scope (as on the Norwegian HK417 photographs), folded bipod.

Weapon space: docs/CHARACTER_STANDARD.md section 3 (origin = grip where the hand closes, bore at
z = 0.074, +Y muzzle).
"""
import math

from mathutils import Vector

import wpn_lib as W
from wpn_lib import ALL, L0, L01, L12, L2, BORE_Z, rx, ry, rounded_outline, arc

B = BORE_Z
AN = "Weapon_Anodized"
PH = "Weapon_Phosphate"
PB = "Polymer_Black"
MB = "Metal_Black"


# ---------------------------------------------------------------------------- AR family pieces


def lower_receiver(p, k=1.0, mag_front=0.207, mag_rear=0.128, rear=-0.045):
    """Lower receiver: body over the magwell and trigger, flared magwell, pivot / takedown
    lugs, trigger-guard loop, selector, magazine release, bolt catch. k scales 5.56 -> 7.62."""
    z_top = B - 0.020 * k
    z_bot = B - 0.058 * k
    out = rounded_outline([
        (rear, z_top), (mag_front + 0.010, z_top), (mag_front + 0.012, z_bot + 0.004, 0.004), (mag_front - 0.004, z_bot - 0.012, 0.006),
        (mag_rear - 0.004, z_bot - 0.014, 0.004), (mag_rear - 0.010, z_bot - 0.002), (0.045, z_bot - 0.002), (0.012, z_bot + 0.006),
        (-0.010, z_bot + 0.014), (rear + 0.010, z_bot + 0.020), (rear, z_bot + 0.032)], 0.003)
    p.prism(out, -0.0158 * k, 0.0158 * k, AN, ALL, bevel=0.0012)
    # magwell flare at the bottom
    p.prism(rounded_outline([(mag_front + 0.006, z_bot - 0.004), (mag_front + 0.004, z_bot - 0.016), (mag_rear - 0.006, z_bot - 0.018),
                             (mag_rear - 0.004, z_bot - 0.004)], 0.002), -0.0172 * k, 0.0172 * k, AN, L01, bevel=0.001)
    # trigger guard loop (HK: enlarged, integral)
    p.tube([(0, mag_rear - 0.012, z_bot - 0.004), (0, mag_rear - 0.020, z_bot - 0.028), (0, 0.030, z_bot - 0.030), (0, 0.012, z_bot - 0.010)],
           0.0035 * k, AN, ALL, segs=6)
    # selector (both sides), mag release (right), bolt catch (left), pivot / takedown pins
    for s in (-1, 1):
        p.cyl(0.0050, 0.003, (s * 0.0175 * k, 0.012, B - 0.033), MB, L01, axis=(1, 0, 0), segs=14)
        p.box((0.003, 0.016, 0.005), (s * 0.0195 * k, 0.008, B - 0.030), MB, L0, rot=rx(-30), r=0.0008)
        p.cyl(0.0026, 0.0012, (s * 0.0164 * k, mag_front + 0.004, B - 0.026), AN, L0, axis=(1, 0, 0), segs=10)
        p.cyl(0.0026, 0.0012, (s * 0.0164 * k, -0.030, B - 0.026), AN, L0, axis=(1, 0, 0), segs=10)
    p.box((0.004, 0.012, 0.010), (0.0175 * k, mag_rear - 0.010, B - 0.040), MB, L01, r=0.001)
    p.box((0.004, 0.026, 0.008), (-0.0170 * k, mag_rear + 0.020, B - 0.031), MB, L01, r=0.001)


def upper_receiver(p, front=0.226, rear=-0.012, k=1.0):
    """Flat-top upper: body, top rail, ejection port with the dust cover, forward assist,
    brass deflector, charging-handle slot."""
    zt = B + 0.032 * k - 0.008          # rail top lands on ATT_Optic z = B + 0.040 (CHARACTER_STANDARD)
    zb = B - 0.020 * k
    out = rounded_outline([(rear, zb), (front, zb), (front, zt), (rear + 0.006, zt), (rear, zt - 0.010)], 0.002)
    p.prism(out, -0.0160 * k, 0.0160 * k, AN, ALL, bevel=0.0012)
    # side bulges along the bolt carrier (the receiver is round-sided under the rail)
    p.prism(rounded_outline([(rear + 0.020, B - 0.012), (front - 0.020, B - 0.012), (front - 0.020, B + 0.012), (rear + 0.020, B + 0.012)], 0.004),
            -0.0175 * k, 0.0175 * k, AN, L01, bevel=0.002)
    p.rail(rear + 0.004, front, zt, AN, L01, width=0.0212)
    # ejection port + dust cover on the right
    p.box((0.003, 0.070 * k, 0.017), (0.0180 * k, 0.058, B + 0.002), MB, L01, r=0.0006)
    p.box((0.0012, 0.064 * k, 0.012), (0.0198 * k, 0.058, B + 0.003), "Metal_Worn", L0, r=0.0003)       # bolt carrier through the port
    # forward assist and brass deflector
    p.cyl(0.0068, 0.030, (0.0195 * k, 0.010, B + 0.012), AN, ALL, axis=(0.35, -1, 0.15), segs=14)
    p.cyl(0.0075, 0.006, (0.0245 * k, -0.004, B + 0.014), MB, L0, axis=(0.35, -1, 0.15), segs=14)
    p.prism(rounded_outline([(0.010, B + 0.000), (0.030, B + 0.000), (0.024, B + 0.020), (0.012, B + 0.020)], 0.003), 0.017 * k, 0.026 * k, AN, L01,
            bevel=0.001)


def charging_handle(w, rear=-0.012, k=1.0):
    ch = w.part("ChargingHandle", pivot=(0, rear, B + 0.012 * k), axis="slide -y", note="charging handle (pulls back)")
    ch.box((0.010, 0.050, 0.008), (0, rear - 0.006, B + 0.012 * k), AN, ALL, r=0.0015)
    ch.prism(rounded_outline([(rear - 0.040, B + 0.006), (rear - 0.022, B + 0.006), (rear - 0.022, B + 0.018), (rear - 0.040, B + 0.018)], 0.003),
             -0.022 * k, 0.022 * k, AN, ALL, bevel=0.0012)
    ch.box((0.010, 0.012, 0.006), (-0.020 * k, rear - 0.034, B + 0.014), AN, L0, r=0.0015)          # ambidextrous latch
    return ch


def trigger(w, y=0.045, k=1.0):
    t = w.part("Trigger", pivot=(0, y + 0.006, B - 0.036 * k), axis="x", note="trigger (pivots about X)")
    t.prism(rounded_outline([(y + 0.004, B - 0.036 * k), (y + 0.010, B - 0.036 * k), (y + 0.006, B - 0.052 * k), (y - 0.002, B - 0.064 * k),
                             (y - 0.004, B - 0.060 * k), (y + 0.002, B - 0.048 * k)], 0.002), -0.0035, 0.0035, MB, L01, bevel=0.0007)
    return t


def pistol_grip(p, k=1.0, mat=PB, hk=True):
    """Ergonomic polymer pistol grip, raked 20 deg, finger groove and stippled sides (HK grip)."""
    # top edge buried 6 mm in the lower receiver (whose underside rises towards the rear)
    out = rounded_outline([(0.026, 0.004), (0.014, 0.030, 0.002), (-0.020, 0.030, 0.004), (-0.030, 0.008, 0.012), (-0.048, -0.050, 0.010),
                           (-0.048, -0.068, 0.006), (-0.022, -0.070, 0.006), (-0.016, -0.058, 0.008), (-0.002, -0.028, 0.010), (0.008, -0.018, 0.008),
                           (0.012, -0.008, 0.006)], 0.004, n=4)
    p.prism(out, -0.0150 * k, 0.0150 * k, mat, ALL, bevel=0.0035, segs=3)
    if hk:
        p.prism(rounded_outline([(-0.046, -0.060), (-0.020, -0.062), (-0.018, -0.074), (-0.048, -0.072)], 0.004), -0.0165 * k, 0.0165 * k, mat, L01,
                bevel=0.002)
        for s in (-1, 1):   # stippled panels
            p.prism(rounded_outline([(-0.006, -0.006), (-0.026, 0.000), (-0.040, -0.048), (-0.022, -0.052)], 0.004), s * 0.0150 * k,
                    s * 0.0158 * k, mat, L0, bevel=0.0006)


def buffer_tube(p, y0=-0.030, y1=-0.205, r=0.0155):
    p.lathe([(0.0, y0), (r, y0), (r, y1 + 0.004), (r - 0.002, y1), (0.0, y1)], (0, 0, B), (0, 1, 0), AN, ALL, segs=20)
    p.lathe([(0.0, y0 + 0.006), (r + 0.004, y0 + 0.006), (r + 0.004, y0 - 0.010), (0.0, y0 - 0.010)], (0, 0, B), (0, 1, 0), AN, L01, segs=20)   # castle nut
    for k in range(6):
        p.box((0.004, 0.0035, 0.008), (0, y0 - 0.002, B + r + 0.003), MB, L0, rot=ry(60 * k), r=0.0006)


def hk_stock(w, pull=0.276, k=1.0, mat=PB):
    """HK slim-line / E2-class telescopic stock: body over the tube, cheek riser, release
    lever, ribbed rubber butt pad. Separate part (slides along the buffer tube)."""
    st = w.part("Stock", pivot=(0, -0.150, B), axis="slide y", note="telescopic stock (slides along the buffer tube)")
    yb = -pull
    out = rounded_outline([
        (yb + 0.020, B + 0.034, 0.010), (yb + 0.150, B + 0.026, 0.010), (yb + 0.175, B + 0.012, 0.008), (yb + 0.172, B - 0.014, 0.006),
        (yb + 0.120, B - 0.026), (yb + 0.045, B - 0.100, 0.010), (yb + 0.010, B - 0.110, 0.008), (yb + 0.004, B - 0.020)], 0.006, n=4)
    st.prism(out, -0.0205 * k, 0.0205 * k, mat, ALL, bevel=0.003, segs=3)
    for s in (-1, 1):   # recessed side panels with ribs
        st.prism(rounded_outline([(yb + 0.050, B - 0.020), (yb + 0.120, B - 0.020), (yb + 0.050, B - 0.085)], 0.006), s * 0.0205 * k, s * 0.0212 * k, mat,
                 L0, bevel=0.0006)
        for j in range(6):
            st.box((0.0016, 0.004, 0.044), (s * 0.0214 * k, yb + 0.060 + j * 0.009, B - 0.045), mat, L0, r=0.0005, rot=rx(-38))
    # butt pad
    st.prism(rounded_outline([(yb + 0.004, B + 0.040), (yb + 0.022, B + 0.040), (yb + 0.022, B - 0.118), (yb + 0.004, B - 0.118)], 0.006), -0.022 * k,
             0.022 * k, "Rubber_Black", ALL, bevel=0.003)
    for j in range(10):
        st.box((0.046 * k, 0.003, 0.0035), (0, yb + 0.002, B + 0.030 - j * 0.015), "Rubber_Black", L0, r=0.0008)
    # release lever under the tube, sling loop at the back
    st.box((0.010, 0.040, 0.006), (0, yb + 0.130, B - 0.024), MB, L0, r=0.0015)
    st.tube([(0.006, yb + 0.050, B + 0.030), (0.016, yb + 0.060, B + 0.042), (0.016, yb + 0.080, B + 0.042), (0.006, yb + 0.090, B + 0.030)], 0.0025, MB, L0)
    return st


def quad_rail(p, y0, y1, half=0.0255, chamfer=0.007, vents=True):
    """HK quad-rail handguard (rail interface system): octagonal tube with four rails."""
    def ring(y):
        h, c = half, chamfer
        return [(x, y, B + z) for x, z in ((h - c, -h), (h, -h + c), (h, h - c), (h - c, h), (-h + c, h), (-h, h - c), (-h, -h + c), (-h + c, -h))]
    p.loft([ring(y0), ring(y1)], AN, ALL)
    p.loft([[(x * 1.06, y0 - 0.006, z0) for x, _, z0 in ring(y0)], [(x * 1.06, y0 + 0.004, z0) for x, _, z0 in ring(y0)]], AN, L01)   # barrel-nut ring
    for ang in (0, 90, 180, 270):
        p.rail(y0 + 0.006, y1, B + half - 0.001 - 0.0005, AN, L01, rot=ry(ang))
    if vents:
        for s in (-1, 1):
            for j in range(6):
                y = y0 + 0.030 + j * (y1 - y0 - 0.06) / 5
                p.cyl(0.0042, 0.003, (s * (half + 0.0002), y, B - 0.012), MB, L0, axis=(1, 0, 0), segs=10)


def barrel(p, y0, y1, r=0.0095, segs=16):
    p.lathe([(0.0, y0), (r, y0), (r, y1), (0.0, y1)], (0, 0, B), (0, 1, 0), PH, ALL, segs=segs)


def flash_hider_hk(p, y0, length=0.058, r=0.0112):
    p.lathe([(0.0, y0), (r, y0), (r, y0 + length - 0.004), (r - 0.002, y0 + length), (0.0, y0 + length)], (0, 0, B), (0, 1, 0), PH, ALL, segs=18)
    for k in range(6):
        a = math.radians(30 + 60 * k)
        p.box((0.0024, length * 0.62, 0.0030), (math.cos(a) * (r - 0.0008), y0 + length * 0.62, B + math.sin(a) * (r - 0.0008)), MB, L0, r=0.0004,
              rot=ry(-math.degrees(a)))


def folding_sight(p, y, z, front=True):
    """HK diopter / front post flip sight, standing up on the rail."""
    p.box((0.020, 0.018, 0.010), (0, y, z + 0.005), AN, L01, r=0.0015)
    if front:
        p.prism(rounded_outline([(y - 0.004, z + 0.008), (y + 0.004, z + 0.008), (y + 0.003, z + 0.036), (y - 0.003, z + 0.036)], 0.0015), -0.006, 0.006,
                AN, L01, bevel=0.0008)
        p.box((0.0018, 0.003, 0.010), (0, y, z + 0.040), MB, L0, r=0.0003)
        for s in (-1, 1):
            p.box((0.0025, 0.006, 0.014), (s * 0.0060, y, z + 0.040), AN, L0, r=0.0004)
    else:
        p.prism(rounded_outline([(y - 0.004, z + 0.008), (y + 0.005, z + 0.008), (y + 0.004, z + 0.030), (y - 0.004, z + 0.030)], 0.002), -0.012, 0.012,
                AN, L01, bevel=0.0008)
        p.lathe([(0.0035, -0.002), (0.0080, -0.002), (0.0080, 0.002), (0.0035, 0.002), (0.0035, -0.002)], (0, y, z + 0.026), (0, 1, 0), MB, L0, segs=14)


def aimpoint_compm4(w, y, z_rail, parent=None):
    """Aimpoint CompM4 in a QD mount on the rail: 38 mm body, flip caps (open), battery
    knob on the right, windage / elevation caps. Axis at the first-person sight line
    (rail top + 0.058, CHARACTER_STANDARD)."""
    zo = z_rail + 0.058
    o = w.part("Optic", pivot=(0, y, z_rail), parent=parent, axis="", note="Aimpoint CompM4 on a QD mount (removable)")
    o.lathe([(0.0, y - 0.064), (0.0170, y - 0.064), (0.0195, y - 0.056), (0.0195, y + 0.046), (0.0210, y + 0.052), (0.0210, y + 0.064), (0.0, y + 0.064)],
            (0, 0, zo), (0, 1, 0), MB, ALL, segs=28)
    o.lathe([(0.0, y + 0.062), (0.0168, y + 0.062), (0.0168, y + 0.0645), (0.0, y + 0.0645)], (0, 0, zo), (0, 1, 0), "Lens", L01, segs=24)
    o.lathe([(0.0, y - 0.0662), (0.0148, y - 0.0662), (0.0148, y - 0.0640), (0.0, y - 0.0640)], (0, 0, zo), (0, 1, 0), "Lens", L01, segs=24)
    # battery housing (right) and the two adjustment caps on top
    o.cyl(0.0105, 0.030, (0.026, y - 0.006, zo - 0.004), MB, ALL, axis=(1, 0, 0), segs=18)
    o.cyl(0.0115, 0.006, (0.042, y - 0.006, zo - 0.004), MB, L01, axis=(1, 0, 0), segs=18)
    for k in range(16):
        a = 2 * math.pi * k / 16
        o.box((0.006, 0.0018, 0.0018), (0.042, y - 0.006 + 0.0116 * math.cos(a), zo - 0.004 + 0.0116 * math.sin(a)), MB, L0, r=0.0003)
    o.cyl(0.0085, 0.012, (0, y - 0.008, zo + 0.024), MB, L01, segs=16)
    o.cyl(0.0065, 0.010, (0, y + 0.014, zo + 0.022), MB, L0, segs=14)
    # flip caps standing open (front cap up and forward, rear cap folded left)
    for yy, sgn in ((y + 0.066, 1), (y - 0.068, -1)):
        o.box((0.008, 0.008, 0.008), (0, yy, zo + 0.021), "Rubber_Black", L01, r=0.0015)                      # cap hinge on the ring
        o.lathe([(0.0, -0.003), (0.020, -0.003), (0.020, 0.003), (0.0, 0.003)], (0, yy + sgn * 0.004, zo + 0.042), (0, 0.25 * sgn, 1), "Rubber_Black", L01, segs=18)
    # QD mount: base on the rail, spacer up to the ring, throw lever
    o.box((0.026, 0.050, 0.010), (0, y, z_rail + 0.005), MB, ALL, r=0.0015)
    o.prism(rounded_outline([(y - 0.020, z_rail + 0.008), (y + 0.020, z_rail + 0.008), (y + 0.014, zo - 0.016), (y - 0.014, zo - 0.016)], 0.003), -0.010, 0.010,
            MB, ALL, bevel=0.0012)
    o.lathe([(0.0205, -0.012), (0.0240, -0.012), (0.0240, 0.012), (0.0205, 0.012), (0.0205, -0.012)], (0, y, zo), (0, 1, 0), MB, L01, segs=28)
    o.box((0.006, 0.028, 0.006), (-0.016, y + 0.002, z_rail + 0.006), MB, L01, r=0.0015, rot=rx(6))
    o.cyl(0.004, 0.010, (-0.016, y + 0.018, z_rail + 0.008), MB, L0, axis=(1, 0, 0), segs=10)
    return o


def vertical_grip(w, y, z_rail_bottom):
    g = w.part("Foregrip", pivot=(0, y, z_rail_bottom), axis="", note="vertical fore grip on the bottom rail (removable)")
    g.box((0.026, 0.034, 0.012), (0, y, z_rail_bottom - 0.006), MB, ALL, r=0.0018)
    g.lathe([(0.0, z_rail_bottom - 0.012), (0.0145, z_rail_bottom - 0.012), (0.0150, z_rail_bottom - 0.040), (0.0140, z_rail_bottom - 0.095),
             (0.0160, z_rail_bottom - 0.105), (0.0150, z_rail_bottom - 0.112), (0.0, z_rail_bottom - 0.112)], (0, y, 0), (0, 0, 1), PB, ALL, segs=20)
    for k in range(5):
        g.lathe([(0.0152, -0.003), (0.0158, 0.0), (0.0152, 0.003), (0.0145, 0.0), (0.0152, -0.003)], (0, y, z_rail_bottom - 0.050 - k * 0.010), (0, 0, 1),
                PB, L0, segs=20)
    return g


def hk_steel_mag(w, top, rounds=30, k=1.0, curve=12.0):
    """HK steel magazine (5.56: curved, 30 rounds; 7.62: straighter, 20 rounds): body with the
    stiffening ribs, floor plate, feed lips. Origin = the magwell top."""
    m = w.magazine(top)
    y0, z0 = top[0], top[2]
    length = (0.172 if rounds == 30 else 0.120) * k
    depth = 0.062 * k
    pts_f, pts_r = [], []
    n = 8
    for j in range(n + 1):
        t = j / n
        a = math.radians(curve * t)
        zz = z0 - length * t
        yy = y0 - math.sin(a) * length * 0.55 * t
        pts_f.append((yy + depth * 0.5 * math.cos(a), zz + depth * 0.5 * math.sin(a) * 0.3))
        pts_r.append((yy - depth * 0.5 * math.cos(a), zz - depth * 0.5 * math.sin(a) * 0.3))
    out = pts_f + list(reversed(pts_r))
    hw = 0.0118 * k
    m.prism(out, -hw, hw, PH, ALL, bevel=0.0012)
    for s in (-1, 1):   # ribs pressed into the sides
        for frac in (0.25, 0.50, 0.75):
            ff = [pts_f[j] for j in range(1, n)]
            rr = [pts_r[j] for j in range(1, n)]
            mid = [(f[0] * (1 - frac) + r[0] * frac, f[1] * (1 - frac) + r[1] * frac) for f, r in zip(ff, rr)]
            m.tube([(s * hw, yy, zz) for yy, zz in mid], 0.0016, PH, L0, segs=5)
    fb = pts_f[-1]
    rb = pts_r[-1]
    m.prism(rounded_outline([(fb[0] + 0.004, fb[1] + 0.004), (fb[0] + 0.006, fb[1] - 0.010), (rb[0] - 0.006, rb[1] - 0.010), (rb[0] - 0.004, rb[1] + 0.004)],
                            0.003), -hw - 0.0018, hw + 0.0018, PB, ALL, bevel=0.0015)
    m.box((0.010 * k, depth * 0.7, 0.004), (0, y0 - 0.002, z0 + 0.002), "Metal_Worn", L0, r=0.001)       # top round / follower
    return m


# ---------------------------------------------------------------------------- HK416N


def hk416():
    w = W.Weapon("weapon_hk416", "HK416N", "NATO", "assault_rifle",
                 "Heckler & Koch HK416N, Norwegian Army standard rifle: 16.5 in barrel, quad rail, Aimpoint CompM4, vertical grip.")
    b = w.part("Body")
    lower_receiver(b)
    upper_receiver(b)
    pistol_grip(b)
    buffer_tube(b)
    quad_rail(b, 0.226, 0.505)
    barrel(b, 0.505, 0.672)
    b.lathe([(0.0, 0.640), (0.0128, 0.640), (0.0128, 0.652), (0.0, 0.652)], (0, 0, B), (0, 1, 0), PH, L01, segs=16)   # sling / bayonet ring
    b.box((0.008, 0.024, 0.014), (0, 0.646, B - 0.018), PH, L01, r=0.0015)                                       # bayonet lug
    flash_hider_hk(b, 0.672, 0.056)
    folding_sight(b, 0.488, B + 0.0345, front=True)
    folding_sight(b, 0.002, B + 0.040, front=False)
    # sling swivel points (front of the rail, receiver end plate)
    b.tube([(0.010, 0.240, B - 0.022), (0.022, 0.244, B - 0.030), (0.022, 0.256, B - 0.030), (0.010, 0.260, B - 0.022)], 0.0022, MB, L0)
    charging_handle(w)
    trigger(w)
    hk_stock(w)
    hk_steel_mag(w, (0.168, 0.0, B - 0.072))
    aimpoint_compm4(w, 0.120, B + 0.040)
    vertical_grip(w, 0.320, B - 0.0255 - 0.011)
    w.marker("ATT_Optic", (0, 0.120, B + 0.040), note="top rail optic mount (CompM4 fitted)")
    w.marker("ATT_Muzzle", (0, 0.728, B), note="muzzle face")
    w.marker("ATT_Underbarrel", (0, 0.320, B - 0.037), note="bottom rail (fore grip fitted)")
    w.marker("ATT_RailRight", (0.037, 0.420, B), note="right rail (laser / light)")
    w.marker("GRIP_Main", (0, 0, 0), note="firing hand")
    w.marker("GRIP_Support", (0, 0.320, B - 0.080), rot=[0, 0, 0], note="support hand on the vertical grip")
    w.meta.update({"variant": "HK416N (Norway)", "dimensions_m": {"overall_mid_stock": 0.98, "barrel": 0.419, "receiver_width": 0.032},
                   "source": "assets/weapons/_references/hk416/notes.md"})
    return w


# ---------------------------------------------------------------------------- HK417


def sb_pmii(w, y, z_rail, length=0.36, obj_r=0.030, tube_r=0.017):
    """Schmidt & Bender PM II class scope in a one-piece mount: 34 mm tube, objective bell,
    ocular, turrets (elevation, windage, parallax), throw-lever mount."""
    zo = z_rail + 0.058
    o = w.part("Optic", pivot=(0, y, z_rail), axis="", note="Schmidt & Bender PM II scope in a one-piece mount (removable)")
    y0, y1 = y - length * 0.45, y + length * 0.55
    prof = [(0.0, y0), (0.0200, y0), (0.0205, y0 + 0.010), (0.0215, y0 + 0.030), (0.0190, y0 + 0.040), (0.0185, y0 + 0.075), (tube_r, y0 + 0.090),
            (tube_r, y1 - 0.120), (obj_r - 0.004, y1 - 0.075), (obj_r, y1 - 0.055), (obj_r, y1 - 0.004), (obj_r - 0.002, y1), (0.0, y1)]
    o.lathe(prof, (0, 0, zo), (0, 1, 0), MB, ALL, segs=32)
    o.lathe([(0.0, y1 - 0.001), (obj_r - 0.004, y1 - 0.001), (obj_r - 0.004, y1 + 0.001), (0.0, y1 + 0.001)], (0, 0, zo), (0, 1, 0), "Lens", L01, segs=28)
    o.lathe([(0.0, y0 - 0.001), (0.0160, y0 - 0.001), (0.0160, y0 + 0.001), (0.0, y0 + 0.001)], (0, 0, zo), (0, 1, 0), "Lens", L01, segs=24)
    tc = y - 0.010
    o.box((0.044, 0.046, 0.034), (0, tc, zo), MB, ALL, r=0.006)                                   # turret saddle
    o.lathe([(0.0, 0.0), (0.0160, 0.0), (0.0165, 0.004), (0.0165, 0.022), (0.0150, 0.026), (0.0, 0.026)], (0, tc, zo + 0.016), (0, 0, 1), MB, L01, segs=24)
    o.lathe([(0.0, 0.0), (0.0140, 0.0), (0.0145, 0.004), (0.0145, 0.018), (0.0130, 0.022), (0.0, 0.022)], (0.022, tc, zo), (1, 0, 0), MB, L01, segs=22)
    o.lathe([(0.0, 0.0), (0.0130, 0.0), (0.0130, 0.016), (0.0, 0.016)], (-0.022, tc, zo), (-1, 0, 0), MB, L01, segs=22)
    for k in range(24):
        a = 2 * math.pi * k / 24
        o.box((0.0020, 0.0020, 0.016), (0.0166 * math.cos(a), tc + 0.0166 * math.sin(a), zo + 0.030), MB, L0, r=0.0003)
    # one-piece cantilever mount with two rings
    o.box((0.024, 0.150, 0.010), (0, y + 0.010, z_rail + 0.005), MB, ALL, r=0.0015)
    for yy in (y - 0.045, y + 0.065):
        o.prism(rounded_outline([(yy - 0.010, z_rail + 0.008), (yy + 0.010, z_rail + 0.008), (yy + 0.010, zo - tube_r), (yy - 0.010, zo - tube_r)], 0.002),
                -0.012, 0.012, MB, ALL, bevel=0.001)
        o.lathe([(tube_r, -0.010), (tube_r + 0.0045, -0.010), (tube_r + 0.0045, 0.010), (tube_r, 0.010), (tube_r, -0.010)], (0, yy, zo), (0, 1, 0), MB, L01,
                segs=28)
        o.box((0.006, 0.018, 0.006), (-0.016, yy, z_rail + 0.006), MB, L0, r=0.0015)
    return o


def bipod_folded(w, y, z_rail_bottom, length=0.20, name="Bipod"):
    """Harris-style folding bipod on the bottom rail, legs folded forward."""
    bp = w.part(name, pivot=(0, y, z_rail_bottom), axis="x (legs fold)", note="folding bipod (legs folded forward)")
    bp.box((0.040, 0.034, 0.016), (0, y, z_rail_bottom - 0.010), MB, ALL, r=0.002)
    for s in (-1, 1):
        bp.cyl(0.006, length, (s * 0.017, y + length / 2 + 0.010, z_rail_bottom - 0.020), MB, ALL, axis=(0, 1, 0), segs=12)
        bp.cyl(0.0045, 0.050, (s * 0.017, y + length + 0.035, z_rail_bottom - 0.020), "Metal_Worn", L01, axis=(0, 1, 0), segs=10)
        bp.lathe([(0.0, 0.0), (0.0070, 0.0), (0.0055, 0.012), (0.0, 0.012)], (s * 0.017, y + length + 0.060, z_rail_bottom - 0.020), (0, 1, 0), "Rubber_Black",
                 L01, segs=12)
    return bp


def hk417():
    w = W.Weapon("weapon_hk417", "HK417", "NATO", "dmr",
                 "Heckler & Koch HK417 7.62 mm designated marksman rifle, 16 in barrel, Schmidt & Bender scope (Norwegian configuration).")
    k = 1.12
    b = w.part("Body")
    lower_receiver(b, k=k, mag_front=0.215, mag_rear=0.118, rear=-0.050)
    upper_receiver(b, front=0.240, k=k)
    pistol_grip(b, k=1.0)
    buffer_tube(b, y1=-0.215)
    quad_rail(b, 0.240, 0.560, half=0.0275)
    barrel(b, 0.560, 0.700, r=0.0110)
    b.lathe([(0.0, 0.700), (0.0135, 0.700), (0.0135, 0.712), (0.0128, 0.716), (0.0128, 0.752), (0.0, 0.752)], (0, 0, B), (0, 1, 0), PH, ALL, segs=18)
    for kk in range(4):                                                       # muzzle brake ports
        for s in (-1, 1):
            b.box((0.004, 0.006, 0.010), (s * 0.0128, 0.722 + kk * 0.008, B), MB, L0, r=0.0006)
    folding_sight(b, 0.545, B + 0.0375, front=True)
    folding_sight(b, 0.002, B + 0.0435, front=False)
    charging_handle(w, k=k)
    trigger(w)
    st = hk_stock(w, pull=0.300, k=1.05)
    m = hk_steel_mag(w, (0.166, 0.0, B - 0.080), rounds=20, k=1.18, curve=3.0)
    sb_pmii(w, 0.090, B + 0.040 + 0.0035)
    bipod_folded(w, 0.430, B - 0.0275 - 0.011)
    w.marker("ATT_Optic", (0, 0.090, B + 0.0435), note="top rail optic mount (PM II fitted)")
    w.marker("ATT_Muzzle", (0, 0.752, B), note="muzzle face")
    w.marker("ATT_Underbarrel", (0, 0.430, B - 0.039), note="bottom rail (bipod fitted)")
    w.marker("GRIP_Main", (0, 0, 0), note="firing hand")
    w.marker("GRIP_Support", (0, 0.300, B - 0.020), note="support hand under the handguard")
    w.meta.update({"variant": "HK417 16 in (Norwegian DMR configuration)", "dimensions_m": {"overall": 1.03, "barrel": 0.406},
                   "source": "assets/weapons/_references/hk417/notes.md"})
    return w


BUILDERS = {"hk416": hk416, "hk417": hk417}
