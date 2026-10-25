"""RUS-01 AK-12 (6P70), RUS-02 AK-74M, RUS-04 RPK-74M and RUS-06 SVD (Russian Army configurations).

AK-74M: 943 mm / 700 mm folded, 415 mm barrel; black glass-filled polymer furniture (ribbed lower handguard, side-folding
solid stock), side scope rail, two-chamber muzzle brake, tangent rear sight. Proportions traced from the Commons photograph
references/ak74m/02 (right side, 1.50 mm per pixel): grip -> muzzle 0.657 m, grip -> butt 0.286 m.
AK-12 (6P70, 2020 production): 880-940 mm stock extended / 690 mm folded, 415 mm barrel (Rosoboronexport / FSVTS data);
railed dust cover with the rear sight at its back, one-piece railed handguard, telescopic side-folding stock, new muzzle
device, ergonomic grip, 5.45 magazine with the round-count windows.
RPK-74M: 1,060 mm / 845 mm folded, 590 mm barrel; AK-74M receiver with the heavier long barrel, bipod at the front sight
block, polymer side-folding RPK stock, 45-round magazine.
SVD: 1,225 mm, 620 mm barrel; classic laminated-wood furniture (thumbhole skeleton stock, ventilated handguard), PSO-1
4x24 scope on the left-side rail, slotted flash hider, 10-round magazine.
Weapon space: CHARACTER_STANDARD.md section 3 (origin at the grip, bore z = 0.074, +Y muzzle).
"""
import math

from mathutils import Vector

import wpn_lib as W
import wpn_nato_rifles as R
import wpn_nato_mg as MG
from wpn_lib import ALL, L0, L01, L12, L2, BORE_Z, rx, ry, rz, rounded_outline, arc

B = BORE_Z
PH = "Weapon_Phosphate"
PBk = "Weapon_PaintBlack"
PB = "Polymer_Black"
MB = "Metal_Black"


# ---------------------------------------------------------------------------- AK family pieces


def ak_receiver(p, y0=-0.050, y1=0.226, mag=(0.093, 0.153), rail=False, side_rail=True):
    """Stamped AK receiver: body with the magazine-well cut, trunnion rivets, the magazine
    catch, the dust cover (ribbed, or with a top rail on the AK-12), side scope rail."""
    zt, zb = B + 0.010, B - 0.050
    out = rounded_outline([(y0, zt - 0.006), (y0 + 0.004, zb + 0.010, 0.010), (mag[0] - 0.010, zb), (mag[0], zb), (mag[0], zb + 0.004), (mag[1], zb + 0.004),
                           (mag[1], zb), (y1 - 0.020, zb + 0.002), (y1, zb + 0.006), (y1, zt)], 0.002)
    p.prism(out, -0.0155, 0.0155, PH, ALL, bevel=0.0012)
    for s in (-1, 1):
        # magazine-well dimple and the trunnion rivets
        p.prism(rounded_outline([(mag[0] - 0.006, zb + 0.008), (mag[1] + 0.012, zb + 0.008), (mag[1] + 0.012, zb + 0.024), (mag[0] - 0.006, zb + 0.024)], 0.004),
                s * 0.0155, s * 0.0162, PH, L0, bevel=0.0006)
        for (yy, zz) in ((y1 - 0.012, zb + 0.014), (y1 - 0.012, zb + 0.030), (mag[0] - 0.020, zb + 0.012), (y0 + 0.012, zb + 0.024), (0.040, zb + 0.008),
                         (0.060, zb + 0.008), (y1 - 0.030, zb + 0.040)):
            p.cyl(0.0024, 0.0016, (s * 0.0160, yy, zz), PH, L0, axis=(1, 0, 0), segs=8)
    p.box((0.012, 0.010, 0.012), (0, mag[0] - 0.006, zb - 0.004), PH, L01, r=0.0015)            # magazine catch
    # dust cover: half-round top with the ribs / rail, the return-spring button at the back
    dc = [(y0 + 0.004, zt - 0.004), (y1 - 0.028, zt - 0.004), (y1 - 0.028, zt + 0.012), (y0 + 0.010, zt + 0.012)]
    p.prism(rounded_outline(dc, 0.003), -0.0150, 0.0150, PH, ALL, bevel=0.004, segs=3)
    if rail:
        p.rail(y0 + 0.010, y1 - 0.030, zt + 0.012, PBk, L01)
    else:
        for s in (-1, 1):
            for j in range(3):
                p.box((0.0016, 0.120, 0.0022), (s * 0.0120, 0.060, zt + 0.004 + j * 0.003), PH, L0, r=0.0004)
    p.box((0.008, 0.010, 0.008), (0, y0 + 0.006, zt + 0.010), PH, L0, r=0.0015)
    if side_rail:
        p.box((0.004, 0.140, 0.018), (-0.0170, 0.050, B - 0.020), PH, L01, r=0.001)
        for j in range(5):
            p.box((0.0016, 0.004, 0.019), (-0.0190, 0.000 + j * 0.026, B - 0.020), PH, L0, r=0.0003)


def ak_safety(p, y0=-0.030):
    """Big stamped safety / selector lever on the right side."""
    p.prism(rounded_outline([(y0, B - 0.008), (0.085, B - 0.012), (0.090, B - 0.004), (0.072, B + 0.002), (y0 + 0.004, B + 0.000)], 0.002), 0.0155, 0.0180, PH, ALL,
            bevel=0.0006)
    p.cyl(0.006, 0.004, (0.0175, y0 + 0.004, B - 0.004), PH, L01, axis=(1, 0, 0), segs=12)


def ak_bolt_carrier(w, y=0.150, k=1.0):
    bc = w.part("Bolt", pivot=(0.016, y, B - 0.004), axis="slide -y", note="bolt carrier with the charging handle (right)")
    bc.box((0.004, 0.090, 0.012), (0.0160, y - 0.040, B - 0.002), PH, L01, r=0.001)
    bc.cyl_between((0.016, y, B - 0.002), (0.034, y + 0.004, B - 0.002), 0.0045, PH, ALL, segs=10)
    bc.lathe([(0.0, 0.0), (0.0075, 0.002), (0.0080, 0.012), (0.0, 0.016)], (0.032, y + 0.004, B - 0.002), (1, 0.15, 0), PH, ALL, segs=14)
    return bc


def ak_trigger_guard(p, y0=0.012, y1=0.088):
    zb = B - 0.050
    p.tube([(0, y1, zb + 0.004), (0, y1 - 0.004, zb - 0.026), (0, y0 + 0.012, zb - 0.026), (0, y0, zb + 0.002)], 0.0030, PH, ALL, segs=6)
    p.box((0.010, y1 - y0 - 0.010, 0.003), (0, (y0 + y1) / 2, zb - 0.027), PH, L01, r=0.0008)


def ak_grip(p, mat=PB, ergonomic=False):
    if ergonomic:
        out = rounded_outline([(0.020, B - 0.034), (0.008, B - 0.034, 0.0), (-0.016, B - 0.034, 0.0), (-0.040, B - 0.120, 0.010), (-0.040, B - 0.150, 0.008),
                               (-0.010, B - 0.152, 0.006), (-0.004, B - 0.138, 0.008), (0.010, B - 0.100, 0.012), (0.018, B - 0.070, 0.008)], 0.004, n=4)
    else:
        out = rounded_outline([(0.020, B - 0.034, 0.0), (-0.016, B - 0.034, 0.0), (-0.020, B - 0.056, 0.006), (-0.040, B - 0.150, 0.008), (-0.010, B - 0.156, 0.008),
                               (0.012, B - 0.064, 0.006), (0.016, B - 0.052)], 0.004, n=4)
    p.prism(out, -0.0140, 0.0140, mat, ALL, bevel=0.0035, segs=3)
    if not ergonomic:
        # moulded grip panels: thin raised plates on both sides, following the grip's slant
        for sx in (-1, 1):
            p.prism(rounded_outline([(0.004, B - 0.068), (-0.016, B - 0.066), (-0.032, B - 0.136), (-0.014, B - 0.140)], 0.004), sx * 0.0140, sx * 0.0152, mat, L0,
                    bevel=0.0006)


def ak_barrel_group(p, y_front=0.610, hg_front=0.395, sight_y=0.555, brake="ak74", gas_tube=True, rail_hg=False, barrel_r=0.0095, gas_y=None):
    """Barrel, gas block / front sight block, lower handguard, gas tube with the upper
    handguard (or the AK-12 one-piece railed handguard), muzzle device."""
    gas_y = gas_y if gas_y is not None else sight_y - 0.090
    p.lathe([(0.0, 0.226), (barrel_r + 0.003, 0.226), (barrel_r + 0.003, 0.240), (barrel_r, 0.244), (barrel_r, y_front), (0.0, y_front)], (0, 0, B), (0, 1, 0), PBk, ALL,
            segs=18)
    if rail_hg:
        def ring(y, h=0.022):
            return [(x, y, B + zz) for x, zz in ((0.020, -0.030), (0.024, -0.018), (0.024, 0.030), (0.016, 0.040), (-0.016, 0.040), (-0.024, 0.030), (-0.024, -0.018),
                                                  (-0.020, -0.030))]
        p.loft([ring(0.228), ring(hg_front)], PB, ALL)
        p.rail(0.232, hg_front - 0.004, B + 0.040, PBk, L01)
        for s in (-1, 1):
            for j in range(4):
                p.cut(lambda t, s=s, j=j: t.prism(rounded_outline([(0.250 + j * 0.034, B - 0.006), (0.272 + j * 0.034, B - 0.006), (0.272 + j * 0.034, B + 0.004),
                                                                      (0.250 + j * 0.034, B + 0.004)], 0.004), s * 0.018, s * 0.030, PB, (0,), bevel=0))
            p.rail(0.300, hg_front - 0.010, B + 0.005 - 0.024 + 0.001, PBk, L0, rot=ry(90 * s))
        p.rail(0.300, hg_front - 0.010, B - 0.030 - 0.001, PBk, L0, rot=ry(180))
    else:
        # lower handguard (ribbed polymer) and the upper handguard over the gas tube
        p.prism(rounded_outline([(0.228, B + 0.012), (hg_front, B + 0.012), (hg_front - 0.006, B - 0.026, 0.008), (0.236, B - 0.032, 0.006)], 0.004), -0.0215, 0.0215,
                PB, ALL, bevel=0.004, segs=2)
        for sx in (-1, 1):                                                    # finger grooves along the lower edge
            for j in range(3):
                p.box((0.004, 0.026, 0.004), (sx * 0.0215, 0.262 + j * 0.044, B - 0.024), PB, L01, r=0.0015)
        for s in (-1, 1):
            for j in range(5):
                p.box((0.0016, 0.110, 0.0030), (s * 0.0218, (0.228 + hg_front) / 2, B + 0.004 - j * 0.0055), PB, L0, r=0.0005)
        p.lathe([(0.0, 0.226), (0.0150, 0.226), (0.0160, 0.240), (0.0160, hg_front - 0.080), (0.0130, hg_front - 0.066), (0.0, hg_front - 0.066)], (0, 0, B + 0.020),
                (0, 1, 0), PB, ALL, segs=18)
        p.box((0.030, 0.012, 0.016), (0, hg_front + 0.004, B - 0.010), PH, L01, r=0.002)        # handguard retainer
    if gas_tube:
        p.lathe([(0.0, hg_front - 0.070), (0.0095, hg_front - 0.070), (0.0095, gas_y), (0.0, gas_y)], (0, 0, B + 0.020), (0, 1, 0), PH, ALL, segs=14)
    # gas block with the bayonet lug, front sight block with the hooded post
    p.prism(rounded_outline([(gas_y - 0.010, B + 0.040), (gas_y + 0.026, B + 0.040), (gas_y + 0.026, B - 0.016), (gas_y - 0.006, B - 0.020)], 0.004), -0.013, 0.013,
            PH, ALL, bevel=0.0015)
    p.prism(rounded_outline([(sight_y - 0.012, B - 0.016), (sight_y + 0.016, B - 0.016), (sight_y + 0.016, B + 0.012), (sight_y + 0.006, B + 0.044),
                             (sight_y - 0.004, B + 0.044), (sight_y - 0.012, B + 0.012)], 0.003), -0.012, 0.012, PH, ALL, bevel=0.0012)
    p.cut(lambda t: t.prism(rounded_outline([(sight_y - 0.020, B + 0.022), (sight_y + 0.020, B + 0.022), (sight_y + 0.020, B + 0.038), (sight_y - 0.020, B + 0.038)],
                                            0.003), -0.007, 0.007, PH, (0,), bevel=0))
    p.cyl(0.0016, 0.018, (0, sight_y + 0.002, B + 0.030), PH, L0, segs=8)
    if brake == "ak74":
        p.lathe([(0.0, y_front - 0.006), (0.0118, y_front - 0.006), (0.0118, y_front + 0.050), (0.0108, y_front + 0.054), (0.0, y_front + 0.054)], (0, 0, B), (0, 1, 0),
                PH, ALL, segs=18)
        for (yy, w_) in ((y_front + 0.020, 0.010), (y_front + 0.038, 0.010)):
            p.cut(lambda t, yy=yy, w_=w_: t.box((0.040, w_, 0.010), (0, yy, B + 0.003), PH, (0,), r=0))
        p.box((0.006, 0.004, 0.006), (0.010, y_front + 0.010, B + 0.010), MB, L0, r=0.0008)
    elif brake == "ak12":
        p.lathe([(0.0, y_front - 0.006), (0.0125, y_front - 0.006), (0.0130, y_front + 0.010), (0.0130, y_front + 0.068), (0.0120, y_front + 0.072),
                 (0.0, y_front + 0.072)], (0, 0, B), (0, 1, 0), PBk, ALL, segs=20)
        for j in range(4):
            for s in (-1, 1):
                p.box((0.006, 0.006, 0.014), (s * 0.0128, y_front + 0.020 + j * 0.013, B), MB, L0, r=0.0008)
    elif brake == "rpk":
        p.lathe([(0.0, y_front - 0.004), (0.0110, y_front - 0.004), (0.0110, y_front + 0.040), (0.0, y_front + 0.040)], (0, 0, B), (0, 1, 0), PH, ALL, segs=16)
        for (yy) in (y_front + 0.016, y_front + 0.030):
            p.cut(lambda t, yy=yy: t.box((0.040, 0.008, 0.008), (0, yy, B + 0.003), PH, (0,), r=0))


def ak_rear_sight(p, y=0.215, z=B + 0.012):
    """Tangent rear-sight block on the front of the receiver (AK-74M / RPK)."""
    p.prism(rounded_outline([(y - 0.020, z - 0.004), (y + 0.012, z - 0.004), (y + 0.012, z + 0.016), (y - 0.016, z + 0.012)], 0.002), -0.014, 0.014, PH, ALL, bevel=0.0012)
    p.box((0.020, 0.060, 0.004), (0, y - 0.040, z + 0.010), PH, L01, r=0.0008, rot=rx(3))
    p.box((0.010, 0.010, 0.010), (0.004, y - 0.050, z + 0.014), PH, L0, r=0.0015)


def ak_mag_545(w, top, rounds=30, mat="Polymer_Plum", windows=False):
    """5.45x39 magazine (30 / 45 rounds), ribbed polymer, gently curved, origin at the magwell."""
    m = w.magazine(top)
    y0, z0 = top[0], top[2]
    L_ = 0.165 if rounds == 30 else 0.235
    depth = 0.062
    n = 10
    f, r = [], []
    for j in range(n + 1):
        t = j / n
        a = math.radians(32 * t)
        cy = y0 + math.sin(a) * L_ * 0.48 * t
        cz = z0 - L_ * t * math.cos(a * 0.6)
        f.append((cy + depth * 0.5 * math.cos(a), cz + depth * 0.5 * math.sin(a)))
        r.append((cy - depth * 0.5 * math.cos(a), cz - depth * 0.5 * math.sin(a)))
    out = f + list(reversed(r))
    m.prism(out, -0.0120, 0.0120, mat, ALL, bevel=0.0015)
    for s in (-1, 1):
        for frac in (0.30, 0.70):
            m.tube([(s * 0.0120, a[0] * (1 - frac) + b[0] * frac, a[1] * (1 - frac) + b[1] * frac) for a, b in zip(f[1:-1], r[1:-1])], 0.0014, mat, L0, segs=5)
        if windows:
            for j in (3, 6):
                c = ((f[j][0] + r[j][0]) / 2 - 0.006, (f[j][1] + r[j][1]) / 2)
                m.box((0.0012, 0.008, 0.010), (s * 0.0122, c[0], c[1]), "Lens_Tinted", L0, r=0.0008)
    fb, rb = f[-1], r[-1]
    m.prism(rounded_outline([(fb[0] + 0.004, fb[1] + 0.006), (fb[0] + 0.006, fb[1] - 0.006), (rb[0] - 0.004, rb[1] - 0.010), (rb[0] - 0.006, rb[1] + 0.004)], 0.003),
            -0.0136, 0.0136, mat, ALL, bevel=0.0015)
    m.box((0.008, 0.030, 0.006), (0, y0 + 0.004, z0 + 0.003), "Metal_Worn", L0, r=0.001)
    return m


def ak74_stock(w, y0=-0.050, pull=0.286, mat=PB, rpk=False):
    """AK-74M side-folding solid polymer stock (RPK: deeper club-foot shape)."""
    st = w.part("Stock", pivot=(-0.012, y0, B - 0.020), axis="z (folds left)", note="side-folding polymer stock")
    yb = -pull
    if rpk:
        out = rounded_outline([(y0, B + 0.010), (yb + 0.014, B + 0.002, 0.012), (yb, B - 0.012), (yb, B - 0.146, 0.010), (yb + 0.040, B - 0.150, 0.006),
                               (yb + 0.120, B - 0.098, 0.040), (y0 - 0.030, B - 0.058, 0.020), (y0, B - 0.044)], 0.006, n=5)
    else:
        out = rounded_outline([(y0, B + 0.010), (yb + 0.014, B + 0.000, 0.012), (yb, B - 0.014), (yb, B - 0.128, 0.010), (yb + 0.030, B - 0.132, 0.006),
                               (yb + 0.110, B - 0.090, 0.040), (y0 - 0.030, B - 0.052, 0.020), (y0, B - 0.042)], 0.006, n=5)
    st.prism(out, -0.0185, 0.0185, mat, ALL, bevel=0.005, segs=3)
    for sx in (-1, 1):                                                         # recessed (cored) side panels
        st.cut(lambda t, sx=sx: t.prism(rounded_outline([(y0 - 0.040, B - 0.006), (yb + 0.040, B - 0.014), (yb + 0.040, B - 0.090), (y0 - 0.090, B - 0.052)], 0.012,
                                                        n=4), sx * 0.0150, sx * 0.030, mat, (0,), bevel=0))
    st.box((0.036, 0.010, 0.136 if rpk else 0.116), (0, yb + 0.003, B - (0.076 if rpk else 0.064)), "Rubber_Black", L01, r=0.004)
    st.box((0.010, 0.030, 0.050), (-0.014, y0 - 0.010, B - 0.022), PH, L01, r=0.002)               # hinge block
    return st


def ak12_stock(w, y0=-0.050):
    """AK-12 telescopic, side-folding skeleton stock with the adjustable cheek rest and the
    rubber butt pad."""
    st = w.part("Stock", pivot=(-0.012, y0, B - 0.020), axis="z (folds left) + slide y", note="telescopic side-folding stock")
    st.box((0.026, 0.050, 0.060), (0, y0 - 0.022, B - 0.020), PB, ALL, r=0.004)
    for zz in (B - 0.002, B - 0.040):
        st.lathe([(0.0, y0 - 0.040), (0.0085, y0 - 0.040), (0.0085, y0 - 0.200), (0.0, y0 - 0.200)], (0, 0, zz), (0, 1, 0), PH, ALL, segs=14)
    yb = y0 - 0.240
    out = rounded_outline([(yb + 0.110, B + 0.020), (yb + 0.010, B + 0.024), (yb, B + 0.010), (yb, B - 0.110, 0.008), (yb + 0.030, B - 0.112), (yb + 0.110, B - 0.050)], 0.006,
                          n=4)
    st.prism(out, -0.016, 0.016, PB, ALL, bevel=0.003, segs=2)
    st.cut(lambda t: t.prism(rounded_outline([(yb + 0.080, B - 0.002), (yb + 0.022, B - 0.002), (yb + 0.022, B - 0.070), (yb + 0.070, B - 0.040)], 0.008), -0.03, 0.03, PB,
                             (0,), bevel=0))
    st.box((0.028, 0.110, 0.016), (0, yb + 0.070, B + 0.030), PB, L01, r=0.006)
    st.box((0.036, 0.012, 0.136), (0, yb - 0.004, B - 0.050), "Rubber_Black", ALL, r=0.004)
    for j in range(8):
        st.box((0.038, 0.002, 0.003), (0, yb - 0.011, B + 0.010 - j * 0.016), "Rubber_Black", L0, r=0.0006)
    return st


# ---------------------------------------------------------------------------- AK-74M


def ak74m():
    w = W.Weapon("weapon_ak74m", "AK-74M", "RU", "assault_rifle", "Kalashnikov AK-74M 5.45 mm assault rifle, black polymer furniture.")
    b = w.part("Body")
    ak_receiver(b)
    ak_safety(b)
    ak_grip(b)
    ak_trigger_guard(b)
    ak_rear_sight(b)
    ak_barrel_group(b, y_front=0.603, hg_front=0.395, sight_y=0.555, brake="ak74")
    ak_bolt_carrier(w)
    R.trigger(w, y=0.044)
    ak74_stock(w)
    ak_mag_545(w, (0.123, 0.0, B - 0.050), mat="Polymer_Plum")
    w.marker("ATT_Muzzle", (0, 0.657, B), note="muzzle brake face")
    w.marker("ATT_Optic", (-0.0190, 0.050, B - 0.020), note="side scope rail (left)")
    w.marker("GRIP_Main", (0, 0, 0), note="firing hand")
    w.marker("GRIP_Support", (0, 0.300, B - 0.020), note="support hand on the lower handguard")
    w.meta.update({"variant": "AK-74M (black polymer, plum 5.45 magazine)", "dimensions_m": {"overall": 0.943, "folded": 0.700, "barrel": 0.415},
                   "source": "assets/weapons/_references/ak74m/notes.md"})
    return w


# ---------------------------------------------------------------------------- AK-12


def ak12():
    w = W.Weapon("weapon_ak12", "AK-12 (6P70)", "RU", "assault_rifle",
                 "Kalashnikov AK-12 (6P70, 2020) 5.45 mm assault rifle: railed dust cover and handguard, telescopic side-folding stock.")
    b = w.part("Body")
    ak_receiver(b, rail=True, side_rail=False)
    ak_safety(b)
    ak_grip(b, ergonomic=True)
    ak_trigger_guard(b)
    ak_barrel_group(b, y_front=0.580, hg_front=0.420, sight_y=0.535, brake="ak12", rail_hg=True, gas_y=0.440)
    # rear sight at the back of the dust-cover rail (2020 production), front sight on the gas block
    b.box((0.022, 0.030, 0.014), (0, -0.020, B + 0.031), PBk, L01, r=0.002)
    b.lathe([(0.0030, -0.003), (0.0070, -0.003), (0.0070, 0.003), (0.0030, 0.003), (0.0030, -0.003)], (0, -0.020, B + 0.042), (0, 1, 0), MB, L0, segs=12)
    ak_bolt_carrier(w)
    R.trigger(w, y=0.044)
    ak12_stock(w)
    ak_mag_545(w, (0.123, 0.0, B - 0.050), mat="Polymer_Black", windows=True)
    w.marker("ATT_Muzzle", (0, 0.652, B), note="muzzle device face")
    w.marker("ATT_Optic", (0, 0.080, B + 0.031), note="dust-cover rail")
    w.marker("ATT_Underbarrel", (0, 0.360, B - 0.031), note="bottom handguard rail")
    w.marker("GRIP_Main", (0, 0, 0), note="firing hand")
    w.marker("GRIP_Support", (0, 0.320, B - 0.020), note="support hand on the handguard")
    w.meta.update({"variant": "AK-12 6P70 (2020 production)", "dimensions_m": {"overall": 0.94, "overall_min": 0.88, "folded": 0.690, "barrel": 0.415},
                   "source": "assets/weapons/_references/ak12/notes.md"})
    return w


# ---------------------------------------------------------------------------- RPK-74M


def rpk74m():
    w = W.Weapon("weapon_rpk74m", "RPK-74M", "RU", "lmg", "Kalashnikov RPK-74M 5.45 mm light machine gun: long heavy barrel, bipod, 45-round magazine.")
    b = w.part("Body")
    ak_receiver(b)
    ak_safety(b)
    ak_grip(b)
    ak_trigger_guard(b)
    ak_rear_sight(b)
    ak_barrel_group(b, y_front=0.740, hg_front=0.395, sight_y=0.700, brake="rpk", barrel_r=0.0110, gas_y=0.520)
    ak_bolt_carrier(w)
    R.trigger(w, y=0.044)
    ak74_stock(w, pull=0.280, rpk=True)
    ak_mag_545(w, (0.123, 0.0, B - 0.050), rounds=45, mat="Polymer_Plum")
    MG.bipod_deployed(w, 0.684, B - 0.020, leg=0.27, spread=18, splay_back=6)
    w.marker("ATT_Muzzle", (0, 0.780, B), note="muzzle face")
    w.marker("ATT_Optic", (-0.0190, 0.050, B - 0.020), note="side scope rail (left)")
    w.marker("GRIP_Main", (0, 0, 0), note="firing hand")
    w.marker("GRIP_Support", (0, 0.300, B - 0.020), note="support hand on the lower handguard")
    w.meta.update({"variant": "RPK-74M", "dimensions_m": {"overall": 1.06, "folded": 0.845, "barrel": 0.590}, "source": "assets/weapons/_references/rpk74m/notes.md"})
    return w


# ---------------------------------------------------------------------------- SVD + PSO-1


SVD_SIGHT = 0.078


def pso1(w, y, x_rail, z_mount):
    """PSO-1 4x24 scope on its side-rail bracket (left side of the receiver): body tube,
    elevation / windage drums, illumination housing, long rubber eyecup, sunshade."""
    zo = B + SVD_SIGHT
    xo = -0.012
    o = w.part("Optic", pivot=(x_rail, y, z_mount), axis="", note="PSO-1 scope on the side-rail bracket (removable)")
    prof = [(0.0, y - 0.230), (0.019, y - 0.230), (0.020, y - 0.200), (0.017, y - 0.185), (0.0130, y - 0.160), (0.0130, y + 0.060), (0.0150, y + 0.075),
            (0.0160, y + 0.140), (0.0, y + 0.140)]
    o.lathe(prof, (xo, 0, zo), (0, 1, 0), MB, ALL, segs=26)
    o.lathe([(0.0, y - 0.231), (0.0150, y - 0.231), (0.0150, y - 0.229), (0.0, y - 0.229)], (xo, 0, zo), (0, 1, 0), "Lens", L01, segs=22)
    o.lathe([(0.0, y + 0.139), (0.0120, y + 0.139), (0.0120, y + 0.141), (0.0, y + 0.141)], (xo, 0, zo), (0, 1, 0), "Lens", L01, segs=22)
    o.lathe([(0.0, y - 0.230), (0.0200, y - 0.230), (0.0210, y - 0.280), (0.0200, y - 0.290), (0.0160, y - 0.290), (0.0, y - 0.280)], (xo, 0, zo), (0, 1, 0),
            "Rubber_Black", L01, segs=22)
    o.box((0.034, 0.050, 0.030), (xo, y - 0.010, zo), MB, ALL, r=0.004)
    o.lathe([(0.0, 0.0), (0.0145, 0.0), (0.0150, 0.004), (0.0150, 0.018), (0.0, 0.020)], (xo, y - 0.010, zo + 0.014), (0, 0, 1), MB, L01, segs=22)
    o.lathe([(0.0, 0.0), (0.0130, 0.0), (0.0135, 0.004), (0.0135, 0.016), (0.0, 0.018)], (xo - 0.016, y - 0.010, zo), (-1, 0, 0), MB, L01, segs=20)
    o.box((0.012, 0.020, 0.016), (xo + 0.018, y - 0.040, zo - 0.004), MB, L0, r=0.002)                # illumination housing
    # bracket from the side rail up and over to the scope
    o.box((0.010, 0.100, 0.034), (x_rail - 0.004, y - 0.010, z_mount), MB, ALL, r=0.002)
    o.prism(rounded_outline([(y - 0.050, z_mount + 0.010), (y + 0.030, z_mount + 0.010), (y + 0.024, zo - 0.012), (y - 0.044, zo - 0.012)], 0.004), x_rail - 0.008,
            x_rail + 0.002, MB, ALL, bevel=0.0015)
    o.box((0.016, 0.020, 0.012), (x_rail - 0.008, y - 0.030, z_mount - 0.012), MB, L0, r=0.002)          # clamp lever
    return o


def svd():
    w = W.Weapon("weapon_svd", "SVD Dragunov", "RU", "dmr", "Dragunov SVD 7.62x54R designated marksman rifle, laminated wood furniture, PSO-1 scope.")
    WD = "Wood_Laminate"
    b = w.part("Body")
    ak_receiver(b, y0=-0.080, y1=0.200, mag=(0.070, 0.150), side_rail=False)
    ak_safety(b, y0=-0.060)
    ak_trigger_guard(b, 0.010, 0.070)
    b.box((0.004, 0.120, 0.022), (-0.0170, 0.040, B - 0.010), PH, L01, r=0.001)                         # PSO side rail
    # ventilated wooden handguard (two halves) and the gas tube / barrel
    b.prism(rounded_outline([(0.200, B - 0.030), (0.470, B - 0.024), (0.470, B + 0.026), (0.200, B + 0.032)], 0.010), -0.0210, 0.0210, WD, ALL, bevel=0.004, segs=2)
    for s in (-1, 1):
        for j in range(3):
            b.cut(lambda t, s=s, j=j: t.prism(rounded_outline([(0.240 + j * 0.070, B - 0.006), (0.290 + j * 0.070, B - 0.004), (0.290 + j * 0.070, B + 0.008),
                                                                  (0.240 + j * 0.070, B + 0.008)], 0.006), s * 0.010, s * 0.030, WD, (0,), bevel=0))
    for yy in (0.205, 0.465):
        b.lathe([(0.0225, -0.006), (0.0260, -0.006), (0.0260, 0.006), (0.0225, 0.006), (0.0225, -0.006)], (0, yy, B), (0, 1, 0), PH, L01, segs=18)
    b.lathe([(0.0, 0.200), (0.0110, 0.200), (0.0105, 0.700), (0.0095, 0.900), (0.0, 0.900)], (0, 0, B), (0, 1, 0), PBk, ALL, segs=18)
    b.prism(rounded_outline([(0.470, B + 0.040), (0.505, B + 0.040), (0.505, B - 0.018), (0.470, B - 0.020)], 0.004), -0.013, 0.013, PH, ALL, bevel=0.0015)
    b.prism(rounded_outline([(0.860, B - 0.014), (0.886, B - 0.014), (0.886, B + 0.012), (0.878, B + 0.050), (0.868, B + 0.050), (0.860, B + 0.012)], 0.003), -0.011, 0.011,
            PH, ALL, bevel=0.0012)
    b.cut(lambda t: t.prism(rounded_outline([(0.850, B + 0.022), (0.896, B + 0.022), (0.896, B + 0.042), (0.850, B + 0.042)], 0.003), -0.006, 0.006, PH, (0,), bevel=0))
    b.lathe([(0.0, 0.896), (0.0110, 0.896), (0.0110, 0.976), (0.0100, 0.980), (0.0, 0.980)], (0, 0, B), (0, 1, 0), PH, ALL, segs=18)
    for k in range(5):
        a = math.radians(72 * k + 90)
        b.box((0.0030, 0.050, 0.004), (math.cos(a) * 0.0105, 0.950, B + math.sin(a) * 0.0105), MB, L0, r=0.0004, rot=ry(-math.degrees(a)))
    ak_rear_sight(b, y=0.195)
    # thumbhole skeleton stock with the cheek rest (laminated wood) - part of the body (fixed)
    yb = -0.245
    out = rounded_outline([(-0.080, B + 0.008), (-0.110, B + 0.010), (yb + 0.040, B + 0.020, 0.010), (yb, B + 0.008, 0.010), (yb, B - 0.150, 0.010),
                           (yb + 0.040, B - 0.158, 0.012), (-0.056, B - 0.160, 0.010), (-0.022, B - 0.160, 0.008), (-0.010, B - 0.120),
                           (-0.030, B - 0.060), (-0.080, B - 0.050)], 0.006, n=4)
    b.prism(out, -0.0185, 0.0185, WD, ALL, bevel=0.004, segs=3)
    b.cut(lambda t: t.prism(rounded_outline([(-0.074, B - 0.024), (yb + 0.060, B - 0.014), (yb + 0.060, B - 0.118), (-0.064, B - 0.124)], 0.018, n=5), -0.03, 0.03, WD,
                            (0,), bevel=0))
    b.prism(rounded_outline([(-0.090, B + 0.010), (yb + 0.040, B + 0.020), (yb + 0.040, B + 0.046), (-0.100, B + 0.030)], 0.010), -0.0200, 0.0200, "Polymer_Black", L01,
            bevel=0.004)                                                                                 # detachable cheek rest
    b.box((0.040, 0.012, 0.166), (0, yb - 0.004, B - 0.070), "Weapon_Phosphate", L01, r=0.003)        # butt plate
    ak_bolt_carrier(w, y=0.120)
    R.trigger(w, y=0.040)
    m = w.magazine((0.110, 0.0, B - 0.050))
    m.prism(rounded_outline([(0.150, B - 0.050), (0.070, B - 0.050), (0.074, B - 0.140), (0.156, B - 0.136)], 0.004), -0.0150, 0.0150, PH, ALL, bevel=0.0015)
    for s in (-1, 1):
        for j in range(4):
            m.box((0.0012, 0.006, 0.060), (s * 0.0152, 0.086 + j * 0.018, B - 0.098), PH, L0, r=0.0008)
    pso1(w, 0.060, -0.020, B - 0.010)
    w.marker("ATT_Muzzle", (0, 0.980, B), note="flash hider face")
    w.marker("ATT_Optic", (-0.0190, 0.040, B - 0.010), note="Warsaw Pact side rail (PSO-1 fitted)")
    w.marker("GRIP_Main", (0, 0, 0), note="firing hand (thumbhole grip)")
    w.marker("GRIP_Support", (0, 0.300, B - 0.030), note="support hand under the handguard")
    w.fps = {"fps_hip": ((-0.16, -0.50, 0.27), (0.0, 1.0, -0.10)), "fps_ads": ((-0.012, -0.40, B + SVD_SIGHT), (0.0, 1.0, 0.0))}
    w.meta.update({"variant": "SVD (classic laminated wood, PSO-1)", "dimensions_m": {"overall": 1.225, "barrel": 0.620}, "sight_line_z": round(B + SVD_SIGHT, 3),
                   "source": "assets/weapons/_references/svd/notes.md"})
    return w


BUILDERS = {"ak12": ak12, "ak74m": ak74m, "rpk74m": rpk74m, "svd": svd}
