"""NATO-03 FN Minimi 7.62 Mk3 and NATO-04 FN MAG (Norwegian Army machine guns).

Minimi 7.62 Mk3: Norway's light machine gun from 2021-22 (FMA framework for up to 4,000 guns): 502 mm barrel,
1,000 mm stock extended / 865 mm collapsed, Mk3 telescopic stock, railed feed cover, railed handguard,
folding carry handle, bipod, 100-round soft pouch.
FN MAG (MAG 58): 1,263 mm, 630 mm barrel, on Norwegian vehicles / weapon stations and as infantry GPMG. Proportions
traced from the Commons photograph references/fn_mag/01 (left side): grip -> muzzle 0.89 m, receiver 0.51 m,
grip -> butt 0.365 m.

Weapon space: CHARACTER_STANDARD.md section 3 (origin at the grip, bore at z = 0.074, +Y muzzle).
"""
import math

from mathutils import Vector

import wpn_lib as W
import wpn_nato_rifles as R
from wpn_lib import ALL, L0, L01, L12, L2, BORE_Z, rx, ry, rounded_outline

B = BORE_Z
PH = "Weapon_Phosphate"
AN = "Weapon_Anodized"
PB = "Polymer_Black"
MB = "Metal_Black"


def bipod_deployed(w, y, z, leg=0.32, spread=22.0, splay_back=8.0, name="Bipod", feet="Rubber_Black"):
    """Two-leg bipod deployed: yoke at (0, y, z), legs down and out, telescoping lower
    sections, feet. Separate part (pivots about X to fold)."""
    bp = w.part(name, pivot=(0, y, z), axis="x (legs fold forward)", note="bipod, deployed")
    bp.box((0.036, 0.030, 0.026), (0, y, z - 0.008), MB, ALL, r=0.003)
    for s in (-1, 1):
        a = math.radians(spread)
        top = Vector((s * 0.014, y, z - 0.018))
        d = Vector((s * math.sin(a), math.sin(math.radians(splay_back)), -math.cos(a))).normalized()
        mid = top + d * leg * 0.55
        foot = top + d * leg
        bp.cyl_between(tuple(top), tuple(mid), 0.0075, MB, ALL, segs=12)
        bp.cyl_between(tuple(mid - d * 0.02), tuple(foot), 0.0058, "Metal_Worn", ALL, segs=10)
        bp.cyl(0.0095, 0.012, tuple(mid), MB, L01, axis=tuple(d), segs=12)
        bp.lathe([(0.0, 0.0), (0.016, 0.0), (0.012, 0.010), (0.0, 0.012)], tuple(foot), (0, 0, 1), feet, L01, segs=12)
    return bp


def belt(w, start, n=7, pitch=0.0125, side=-1, sag=0.6, name="Belt"):
    """A short hanging belt of 7.62 rounds (links + brass) from the feed tray on the left."""
    bl = w.part(name, pivot=start, axis="", note="ammunition belt stub")
    p = Vector(start)
    d = Vector((side * 0.6, 0, -0.8)).normalized()
    for k in range(n):
        q = p + d * (k * pitch) + Vector((0, 0, -sag * 0.002 * k * k))
        bl.cyl(0.0060, 0.050, tuple(q + Vector((0, 0.004, 0))), "Metal_Worn", L01, axis=(0, 1, 0), segs=8)
        bl.lathe([(0.0, 0.0), (0.0040, 0.0), (0.0022, 0.016), (0.0, 0.020)], tuple(q + Vector((0, 0.029, 0))), (0, 1, 0), "Metal_Worn", L0, segs=8)
        bl.box((0.014, 0.010, 0.012), tuple(q + Vector((0, -0.010, 0))), MB, L0, r=0.001)
    return bl


# ---------------------------------------------------------------------------- FN MAG


def fn_mag():
    w = W.Weapon("weapon_fn_mag", "FN MAG", "NATO", "gpmg",
                 "FN MAG 7.62 mm general-purpose machine gun (Norwegian Army: vehicles, weapon stations, infantry).")
    b = w.part("Body")
    yf, yr = 0.400, -0.110
    zt, zb = B + 0.036, B - 0.066
    hw = 0.028
    # receiver: riveted steel box with the side reinforcing ribs, trunnion block at the front
    b.prism(rounded_outline([(yr, zb + 0.012), (yr + 0.010, zb), (yf, zb), (yf, zt - 0.004), (yr + 0.020, zt - 0.004), (yr, zt - 0.014)], 0.003), -hw, hw, PH, ALL,
            bevel=0.0015)
    b.prism(rounded_outline([(yf - 0.070, zb + 0.004), (yf + 0.012, zb + 0.004), (yf + 0.012, zt - 0.008), (yf - 0.070, zt - 0.008)], 0.004), -hw - 0.004, hw + 0.004, PH,
            ALL, bevel=0.0015)
    for s in (-1, 1):
        b.box((0.004, yf - yr - 0.08, 0.008), (s * (hw + 0.001), (yf + yr) / 2 - 0.01, zb + 0.018), PH, L01, r=0.0012)
        for j in range(9):
            b.cyl(0.0028, 0.002, (s * (hw + 0.002), yr + 0.040 + j * 0.052, zb + 0.040), PH, L0, axis=(1, 0, 0), segs=8)
        b.cyl(0.0045, 0.004, (s * (hw + 0.002), yf - 0.040, B - 0.010), PH, L0, axis=(1, 0, 0), segs=10)
    # feed tray + top cover with the feed-cover latch, rear sight leaf
    fc = w.part("FeedCover", pivot=(0, yr + 0.030, zt), axis="x (opens upward)", note="top cover / feed cover")
    fc.prism(rounded_outline([(yr + 0.020, zt - 0.006), (0.220, zt - 0.006), (0.226, zt + 0.006), (0.216, zt + 0.018), (yr + 0.040, zt + 0.018), (yr + 0.020, zt + 0.010)],
                             0.004), -hw + 0.002, hw - 0.002, PH, ALL, bevel=0.0015)
    fc.box((0.050, 0.020, 0.012), (0, 0.205, zt + 0.018), PH, L01, r=0.002)
    fc.box((0.020, 0.040, 0.028), (0, yr + 0.050, zt + 0.030), PH, L01, r=0.002)               # rear sight leaf (folded down)
    b.box((0.050, 0.090, 0.010), (-0.004, 0.170, zt - 0.010), "Metal_Worn", L01, r=0.0015)    # feed tray edge
    b.box((0.016, 0.060, 0.030), (-hw - 0.004, 0.170, B + 0.002), PH, L01, r=0.002)           # feed chute (left)
    # barrel, barrel nut, gas cylinder + regulator, front sight, flash hider
    R.barrel(b, yf, 0.840, r=0.0125, segs=18)
    b.lathe([(0.0, yf), (0.0200, yf), (0.0200, yf + 0.050), (0.0150, yf + 0.060), (0.0, yf + 0.060)], (0, 0, B), (0, 1, 0), PH, ALL, segs=20)
    b.lathe([(0.0, yf), (0.0110, yf), (0.0110, 0.700), (0.0, 0.700)], (0, 0, B - 0.042), (0, 1, 0), PH, ALL, segs=16)
    b.box((0.030, 0.040, 0.060), (0, 0.712, B - 0.020), PH, ALL, r=0.004)                    # gas block / regulator
    b.cyl(0.010, 0.050, (0.018, 0.712, B - 0.040), PH, L01, axis=(1, 0, 0), segs=12)
    b.prism(rounded_outline([(0.835, B), (0.850, B), (0.848, B + 0.060), (0.836, B + 0.060)], 0.002), -0.004, 0.004, PH, ALL, bevel=0.0008)   # front sight post
    for s in (-1, 1):
        b.box((0.004, 0.018, 0.040), (s * 0.010, 0.842, B + 0.034), PH, L0, r=0.001)
    b.lathe([(0.0, 0.840), (0.0145, 0.840), (0.0145, 0.888), (0.0130, 0.893), (0.0, 0.893)], (0, 0, B), (0, 1, 0), PH, ALL, segs=18)
    for kk in range(5):
        a = math.radians(72 * kk)
        b.box((0.0030, 0.034, 0.004), (math.cos(a) * 0.0138, 0.872, B + math.sin(a) * 0.0138), MB, L0, r=0.0004, rot=ry(-math.degrees(a)))
    # carrying handle on the barrel just ahead of the receiver (folded back over the cover)
    b.lathe([(0.0, 0.0), (0.0150, 0.0), (0.0150, 0.024), (0.0, 0.024)], (0, yf + 0.030, B), (0, 1, 0), PH, L01, segs=16)
    b.prism(rounded_outline([(yf + 0.040, B + 0.012), (yf + 0.050, B + 0.012), (yf - 0.120, zt + 0.040), (yf - 0.175, zt + 0.042), (yf - 0.180, zt + 0.030),
                             (yf - 0.125, zt + 0.028)], 0.006), -0.006, 0.006, PB, ALL, bevel=0.002)
    # pistol grip, trigger guard, trigger housing
    b.prism(rounded_outline([(0.050, zb + 0.004), (-0.050, zb + 0.004), (-0.050, zb - 0.016), (0.050, zb - 0.016)], 0.004), -0.016, 0.016, PH, ALL, bevel=0.0012)
    R.pistol_grip(b, k=1.05, hk=False)
    b.tube([(0, 0.050, zb - 0.014), (0, 0.062, zb - 0.040), (0, 0.020, zb - 0.044), (0, 0.006, zb - 0.020)], 0.0035, PH, ALL, segs=6)
    R.trigger(w, y=0.032)
    # butt stock (polymer, MAG 58 shape): long wrist from the receiver back plate down to the butt plate
    st = w.part("Stock", pivot=(0, yr, B), axis="", note="butt stock (removable)")
    out = rounded_outline([(yr + 0.004, zt - 0.008), (yr - 0.090, B + 0.010, 0.020), (-0.330, B + 0.006, 0.010), (-0.362, B + 0.012, 0.006), (-0.365, B - 0.118, 0.010),
                           (-0.320, B - 0.124, 0.012), (-0.220, B - 0.070, 0.030), (yr - 0.020, zb + 0.006), (yr + 0.004, zb + 0.006)], 0.008, n=4)
    st.prism(out, -0.020, 0.020, PB, ALL, bevel=0.004, segs=3)
    for s in (-1, 1):
        for j in range(6):
            st.box((0.0016, 0.006, 0.040), (s * 0.0205, -0.330 + j * 0.010, B - 0.070), PB, L0, r=0.0005, rot=rx(-10))
    st.box((0.044, 0.010, 0.120), (0, -0.367, B - 0.055), "Rubber_Black", ALL, r=0.004)
    st.tube([(0.020, -0.300, B - 0.110), (0.030, -0.300, B - 0.122), (0.030, -0.270, B - 0.122), (0.020, -0.268, B - 0.100)], 0.0025, MB, L0)
    # cocking handle (right), bipod, belt stub
    ch = w.part("ChargingHandle", pivot=(hw + 0.006, 0.180, B), axis="slide -y", note="cocking handle (right side)")
    ch.box((0.010, 0.024, 0.016), (hw + 0.006, 0.180, B), PH, ALL, r=0.002)
    ch.cyl(0.006, 0.020, (hw + 0.020, 0.180, B), PH, ALL, axis=(1, 0, 0), segs=12)
    bipod_deployed(w, 0.690, B - 0.052, leg=0.34)
    belt(w, (-hw - 0.010, 0.170, B - 0.012))
    w.marker("ATT_Muzzle", (0, 0.893, B), note="muzzle face")
    w.marker("ATT_Optic", (0, 0.060, zt + 0.018), note="top of the feed cover (no rail on the standard MAG)")
    w.marker("GRIP_Main", (0, 0, 0), note="firing hand")
    w.marker("GRIP_Support", (0, -0.250, B - 0.090), note="support hand over the butt (bipod firing)")
    w.meta.update({"variant": "FN MAG (MAG 58) infantry configuration with bipod and butt stock", "dimensions_m": {"overall": 1.263, "barrel": 0.630},
                   "source": "assets/weapons/_references/fn_mag/notes.md"})
    return w


# ---------------------------------------------------------------------------- Minimi 7.62 Mk3


def fn_minimi():
    w = W.Weapon("weapon_fn_minimi", "FN Minimi 7.62 Mk3", "NATO", "lmg",
                 "FN Minimi 7.62 Mk3 light machine gun (Norwegian Army from 2022): telescopic stock, railed feed cover and handguard, bipod.")
    b = w.part("Body")
    yf, yr = 0.250, -0.150
    zt, zb = B + 0.032, B - 0.058
    hw = 0.026
    # receiver: stamped steel box with the ribbed sides, front trunnion, ejection port (right)
    b.prism(rounded_outline([(yr, zb + 0.010), (yr + 0.010, zb), (yf, zb), (yf, zt - 0.006), (yr + 0.010, zt - 0.006), (yr, zt - 0.014)], 0.003), -hw, hw, PH, ALL,
            bevel=0.0015)
    for s in (-1, 1):
        b.box((0.003, yf - yr - 0.06, 0.006), (s * (hw + 0.0008), (yf + yr) / 2, zb + 0.016), PH, L01, r=0.001)
        b.box((0.003, yf - yr - 0.06, 0.006), (s * (hw + 0.0008), (yf + yr) / 2, zt - 0.020), PH, L01, r=0.001)
        for j in range(7):
            b.cyl(0.0026, 0.002, (s * (hw + 0.0015), yr + 0.030 + j * 0.055, B - 0.004), PH, L0, axis=(1, 0, 0), segs=8)
    b.box((0.003, 0.080, 0.020), (hw + 0.0006, 0.060, zb + 0.030), MB, L01, r=0.0008)          # ejection port
    # feed cover with the long top rail and the rear sight (Mk3), feed tray
    fc = w.part("FeedCover", pivot=(0, yr + 0.040, zt), axis="x (opens upward)", note="feed cover with top rail")
    fc.prism(rounded_outline([(yr + 0.030, zt - 0.008), (0.180, zt - 0.008), (0.186, zt + 0.004), (0.176, zt + 0.016), (yr + 0.040, zt + 0.016)], 0.004),
             -hw + 0.002, hw - 0.002, PH, ALL, bevel=0.0015)
    fc.rail(yr + 0.040, 0.176, zt + 0.016, AN, L01)
    fc.box((0.024, 0.030, 0.024), (0, yr + 0.060, zt + 0.036), AN, L01, r=0.002)              # Mk3 rear sight
    fc.lathe([(0.0030, -0.002), (0.0070, -0.002), (0.0070, 0.002), (0.0030, 0.002), (0.0030, -0.002)], (0, yr + 0.060, zt + 0.046), (0, 1, 0), MB, L0, segs=12)
    # barrel group: barrel, gas block, railed handguard with holes, front sight, flash hider, carry handle
    R.barrel(b, yf, 0.620, r=0.0115, segs=18)
    b.lathe([(0.0, yf), (0.0170, yf), (0.0170, yf + 0.040), (0.0, yf + 0.040)], (0, 0, B), (0, 1, 0), PH, ALL, segs=20)
    hg = [(yf + 0.010, B - 0.012), (0.470, B - 0.012), (0.470, B - 0.072), (yf + 0.010, B - 0.072)]
    b.prism(rounded_outline(hg, 0.006), -0.026, 0.026, PB, ALL, bevel=0.002)
    for s in (-1, 1):
        for j in range(5):
            b.cyl(0.0055, 0.003, (s * 0.0262, yf + 0.045 + j * 0.040, B - 0.042), MB, L0, axis=(1, 0, 0), segs=10)
        b.rail(yf + 0.030, 0.450, B - 0.042 - 0.0262 + 0.001, AN, L0, rot=ry(90 * s))
    b.rail(yf + 0.020, 0.460, B - 0.075, AN, L01, rot=ry(180))
    b.box((0.030, 0.040, 0.050), (0, 0.495, B - 0.022), PH, ALL, r=0.004)                    # gas block
    b.lathe([(0.0, 0.470), (0.0100, 0.470), (0.0100, 0.520), (0.0, 0.520)], (0, 0, B - 0.040), (0, 1, 0), PH, L01, segs=12)
    b.prism(rounded_outline([(0.600, B), (0.612, B), (0.611, B + 0.048), (0.601, B + 0.048)], 0.002), -0.004, 0.004, PH, ALL, bevel=0.0008)
    b.lathe([(0.0, 0.620), (0.0135, 0.620), (0.0135, 0.660), (0.0120, 0.664), (0.0, 0.664)], (0, 0, B), (0, 1, 0), PH, ALL, segs=18)
    for kk in range(5):
        a = math.radians(72 * kk)
        b.box((0.0028, 0.026, 0.004), (math.cos(a) * 0.0128, 0.648, B + math.sin(a) * 0.0128), MB, L0, r=0.0004, rot=ry(-math.degrees(a)))
    b.lathe([(0.0, 0.0), (0.0140, 0.0), (0.0140, 0.020), (0.0, 0.020)], (0, 0.300, B), (0, 1, 0), PH, L01, segs=16)
    b.prism(rounded_outline([(0.300, B + 0.010), (0.312, B + 0.010), (0.340, B + 0.060), (0.230, B + 0.075), (0.226, B + 0.064), (0.326, B + 0.052)], 0.006), -0.020, -0.010,
            PB, ALL, bevel=0.002)
    # trigger group + pistol grip + trigger guard
    b.prism(rounded_outline([(0.060, zb + 0.004), (-0.040, zb + 0.004), (-0.040, zb - 0.014), (0.060, zb - 0.014)], 0.004), -0.016, 0.016, PH, ALL, bevel=0.0012)
    R.pistol_grip(b, k=1.05, hk=False)
    b.tube([(0, 0.060, zb - 0.012), (0, 0.070, zb - 0.040), (0, 0.020, zb - 0.044), (0, 0.006, zb - 0.020)], 0.0035, PH, ALL, segs=6)
    R.trigger(w, y=0.034)
    # Mk3 telescopic stock with cheek riser
    st = w.part("Stock", pivot=(0, yr, B), axis="slide y", note="Mk3 telescopic stock")
    st.lathe([(0.0, yr), (0.016, yr), (0.016, yr - 0.120), (0.0, yr - 0.120)], (0, 0, B - 0.010), (0, 1, 0), AN, ALL, segs=18)
    out = rounded_outline([(-0.230, B + 0.030, 0.010), (-0.330, B + 0.030, 0.010), (-0.338, B + 0.010), (-0.338, B - 0.110, 0.010), (-0.300, B - 0.112, 0.012),
                           (-0.235, B - 0.040, 0.020), (-0.220, B - 0.028)], 0.006, n=4)
    st.prism(out, -0.020, 0.020, PB, ALL, bevel=0.004, segs=3)
    st.box((0.026, 0.080, 0.016), (0, -0.280, B + 0.040), PB, L01, r=0.006)                  # cheek riser
    st.box((0.044, 0.010, 0.132), (0, -0.341, B - 0.040), "Rubber_Black", ALL, r=0.004)
    # charging handle (right), bipod, 100-round soft pouch under the receiver
    ch = w.part("ChargingHandle", pivot=(hw + 0.006, 0.140, B - 0.020), axis="slide -y", note="cocking handle (right side)")
    ch.box((0.010, 0.020, 0.012), (hw + 0.006, 0.140, B - 0.020), PH, ALL, r=0.002)
    ch.cyl(0.0055, 0.018, (hw + 0.018, 0.140, B - 0.020), PB, ALL, axis=(1, 0, 0), segs=12)
    bipod_deployed(w, 0.490, B - 0.072, leg=0.30)
    pouch = w.part("AmmoPouch", pivot=(-0.010, 0.080, zb), axis="", note="100-round soft pouch (removable)")
    pouch.prism(rounded_outline([(0.130, zb - 0.002), (0.020, zb - 0.002), (0.016, zb - 0.110), (0.140, zb - 0.110)], 0.020, n=4), -0.060, 0.010, "Cordura_RangerGreen",
                ALL, bevel=0.010, segs=3)
    pouch.box((0.074, 0.010, 0.020), (-0.025, 0.130, zb - 0.060), "Strap_Black", L0, r=0.002)
    belt(w, (-hw - 0.006, 0.120, B - 0.010), n=4)
    w.marker("ATT_Muzzle", (0, 0.664, B), note="muzzle face")
    w.marker("ATT_Optic", (0, 0.000, zt + 0.024), note="feed-cover rail")
    w.marker("GRIP_Main", (0, 0, 0), note="firing hand")
    w.marker("GRIP_Support", (0, 0.360, B - 0.060), note="support hand on the handguard")
    w.meta.update({"variant": "FN Minimi 7.62 Mk3 (Norway)", "dimensions_m": {"overall": 1.000, "barrel": 0.502, "collapsed": 0.865},
                   "source": "assets/weapons/_references/fn_minimi/notes.md"})
    return w


BUILDERS = {"fn_minimi": fn_minimi, "fn_mag": fn_mag}
