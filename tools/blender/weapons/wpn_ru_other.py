"""RUS-03 PKP Pecheneg and RUS-05 MP-443 Grach (Russian Army).

PKP Pecheneg (6P41): 7.62x54R general-purpose machine gun, 1,200 mm, 658 mm heavy fluted barrel inside the forced-air
cooling shroud with the carrying handle on top, bipod at the front of the shroud, skeleton butt stock, feed cover with
the rear sight, belt from the right, 100-round box under the receiver (TsNIITochMash / Degtyarev data, Commons photos).
MP-443 Grach (PYa, Yarygin): 9x19 mm service pistol, 198 x 140 x 38 mm, 112 mm barrel; steel slide with the external
hammer, polymer-frame (later production) form with the ambidextrous safety and the square trigger guard.
Weapon space: CHARACTER_STANDARD.md section 3 (origin at the grip, bore z = 0.074, +Y muzzle).
"""
import math

from mathutils import Vector

import wpn_lib as W
import wpn_nato_rifles as R
import wpn_nato_mg as MG
import wpn_ru_rifles as AK
from wpn_lib import ALL, L0, L01, L12, L2, BORE_Z, rx, ry, rounded_outline

B = BORE_Z
PH = "Weapon_Phosphate"
PBk = "Weapon_PaintBlack"
PB = "Polymer_Black"
MB = "Metal_Black"


# ---------------------------------------------------------------------------- PKP Pecheneg


def pkp_pecheneg():
    w = W.Weapon("weapon_pkp_pecheneg", "PKP Pecheneg", "RU", "gpmg",
                 "PKP Pecheneg 7.62x54R general-purpose machine gun: cooling shroud with carry handle, bipod at the muzzle end, 100-round box.")
    b = w.part("Body")
    yr, yf = -0.100, 0.300
    zt, zb = B + 0.030, B - 0.054
    hw = 0.024
    # stamped receiver with the rivets, trunnion block, the right-hand feed opening
    b.prism(rounded_outline([(yr, zb + 0.014), (yr + 0.012, zb), (yf, zb), (yf, zt - 0.004), (yr + 0.016, zt - 0.004), (yr, zt - 0.016)], 0.003), -hw, hw, PH, ALL,
            bevel=0.0015)
    b.prism(rounded_outline([(yf - 0.060, zb + 0.004), (yf + 0.014, zb + 0.004), (yf + 0.014, zt - 0.006), (yf - 0.060, zt - 0.006)], 0.004), -hw - 0.003, hw + 0.003, PH,
            ALL, bevel=0.0015)
    for s in (-1, 1):
        b.box((0.003, yf - yr - 0.10, 0.006), (s * (hw + 0.001), (yf + yr) / 2 - 0.02, zb + 0.016), PH, L01, r=0.001)
        for j in range(8):
            b.cyl(0.0026, 0.002, (s * (hw + 0.002), yr + 0.030 + j * 0.044, zb + 0.032), PH, L0, axis=(1, 0, 0), segs=8)
    b.box((0.006, 0.070, 0.030), (hw + 0.002, 0.150, B - 0.004), MB, L01, r=0.002)                    # feed opening (right)
    b.box((0.008, 0.050, 0.020), (-hw - 0.003, 0.150, B - 0.004), PH, L01, r=0.002)                  # link ejection port cover (left)
    # feed cover with the rear sight leaf and the latch
    fc = w.part("FeedCover", pivot=(0, yr + 0.020, zt), axis="x (opens upward)", note="feed cover")
    fc.prism(rounded_outline([(yr + 0.010, zt - 0.006), (0.200, zt - 0.006), (0.206, zt + 0.004), (0.196, zt + 0.014), (yr + 0.030, zt + 0.014), (yr + 0.010, zt + 0.006)],
                             0.004), -hw + 0.002, hw - 0.002, PH, ALL, bevel=0.0015)
    fc.box((0.034, 0.014, 0.010), (0, yr + 0.020, zt + 0.012), PH, L01, r=0.002)
    b.prism(rounded_outline([(0.210, zt - 0.006), (0.270, zt - 0.006), (0.270, zt + 0.016), (0.226, zt + 0.012)], 0.002), -0.012, 0.012, PH, ALL, bevel=0.001)
    b.box((0.018, 0.070, 0.004), (0, 0.226, zt + 0.016), PH, L01, r=0.0008, rot=rx(2))
    # forced-air cooling shroud over the fluted barrel, slots, carry handle on top
    y_sh = 0.770
    b.lathe([(0.0, yf), (0.0270, yf), (0.0270, y_sh - 0.010), (0.0240, y_sh), (0.0, y_sh)], (0, 0, B), (0, 1, 0), PBk, ALL, segs=24)
    for j in range(7):
        yy = yf + 0.050 + j * 0.060
        for ang in (35, 145, 215, 325):
            a = math.radians(ang)
            b.box((0.0020, 0.036, 0.010), (math.cos(a) * 0.0268, yy, B + math.sin(a) * 0.0268), MB, L0, r=0.0008, rot=ry(-ang + 90))
    for yy in (yf + 0.010, 0.560, y_sh - 0.016):
        b.lathe([(0.0265, -0.007), (0.0295, -0.007), (0.0295, 0.007), (0.0265, 0.007), (0.0265, -0.007)], (0, yy, B), (0, 1, 0), PH, L01, segs=24)
    b.prism(rounded_outline([(0.415, B + 0.020), (0.430, B + 0.020), (0.445, B + 0.088), (0.585, B + 0.088), (0.600, B + 0.020), (0.615, B + 0.020), (0.598, B + 0.102),
                             (0.432, B + 0.102)], 0.010), -0.008, 0.008, PB, ALL, bevel=0.002)
    # gas cylinder under the shroud, gas block, front sight on the muzzle end, flash hider
    b.lathe([(0.0, yf), (0.0110, yf), (0.0110, 0.640), (0.0, 0.640)], (0, 0, B - 0.040), (0, 1, 0), PH, ALL, segs=14)
    b.box((0.026, 0.034, 0.050), (0, 0.650, B - 0.022), PH, ALL, r=0.004)
    b.lathe([(0.0, y_sh), (0.0140, y_sh), (0.0140, 0.790), (0.0120, 0.795), (0.0120, 0.835), (0.0, 0.835)], (0, 0, B), (0, 1, 0), PH, ALL, segs=18)
    b.prism(rounded_outline([(0.775, B + 0.010), (0.800, B + 0.010), (0.800, B + 0.046), (0.792, B + 0.068), (0.783, B + 0.068), (0.775, B + 0.046)], 0.003), -0.011, 0.011,
            PH, ALL, bevel=0.0012)
    b.cut(lambda t: t.prism(rounded_outline([(0.765, B + 0.044), (0.810, B + 0.044), (0.810, B + 0.064), (0.765, B + 0.064)], 0.003), -0.006, 0.006, PH, (0,), bevel=0))
    b.cyl(0.0016, 0.020, (0, 0.788, B + 0.054), PH, L0, segs=8)
    b.lathe([(0.0, 0.835), (0.0130, 0.835), (0.0130, 0.900), (0.0115, 0.905), (0.0, 0.905)], (0, 0, B), (0, 1, 0), PH, ALL, segs=18)
    for k in range(4):
        a = math.radians(90 * k + 45)
        b.box((0.0030, 0.040, 0.004), (math.cos(a) * 0.0124, 0.878, B + math.sin(a) * 0.0124), MB, L0, r=0.0004, rot=ry(-math.degrees(a)))
    # pistol grip, trigger guard, trigger housing
    b.prism(rounded_outline([(0.060, zb + 0.004), (-0.040, zb + 0.004), (-0.040, zb - 0.014), (0.060, zb - 0.014)], 0.004), -0.016, 0.016, PH, ALL, bevel=0.0012)
    AK.ak_grip(b)
    b.tube([(0, 0.060, zb - 0.012), (0, 0.068, zb - 0.040), (0, 0.020, zb - 0.044), (0, 0.006, zb - 0.020)], 0.0032, PH, ALL, segs=6)
    R.trigger(w, y=0.034)
    # skeleton butt stock (black polymer)
    st = w.part("Stock", pivot=(0, yr, B), axis="", note="skeleton butt stock")
    yb = -0.300
    out = rounded_outline([(yr + 0.004, zt - 0.008), (yr - 0.060, B + 0.010, 0.020), (yb + 0.020, B + 0.006, 0.010), (yb, B - 0.004, 0.008), (yb, B - 0.128, 0.010),
                           (yb + 0.040, B - 0.132, 0.010), (yr - 0.060, zb - 0.010, 0.030), (yr + 0.004, zb + 0.006)], 0.008, n=4)
    st.prism(out, -0.0185, 0.0185, PB, ALL, bevel=0.004, segs=3)
    st.cut(lambda t: t.prism(rounded_outline([(yr - 0.040, B - 0.012), (yb + 0.030, B - 0.016), (yb + 0.030, B - 0.104), (yr - 0.080, B - 0.052)], 0.014, n=4), -0.03,
                             0.03, PB, (0,), bevel=0))
    st.box((0.040, 0.010, 0.130), (0, yb - 0.002, B - 0.066), PH, L01, r=0.003)
    # cocking handle (right, low), bipod at the shroud's front, belt into the right side, 100-round box
    ch = w.part("ChargingHandle", pivot=(hw + 0.006, 0.250, B - 0.034), axis="slide -y", note="cocking handle (right side)")
    ch.box((0.010, 0.024, 0.014), (hw + 0.006, 0.250, B - 0.034), PH, ALL, r=0.002)
    ch.cyl(0.0065, 0.022, (hw + 0.020, 0.250, B - 0.034), PH, ALL, axis=(1, 0, 0), segs=12)
    MG.bipod_deployed(w, 0.745, B - 0.030, leg=0.34, spread=20, splay_back=4)
    MG.belt(w, (hw + 0.010, 0.150, B - 0.012), n=6, side=1)
    m = w.magazine((0.030, 0.140, zb - 0.010), note="100-round belt box (clips under the receiver)")
    m.box((0.050, 0.180, 0.016), (0.012, 0.140, zb - 0.012), PH, ALL, r=0.003)
    m.box((0.090, 0.200, 0.150), (0.030, 0.140, zb - 0.094), "Polymer_Green", ALL, r=0.006)
    for s in (-1, 1):
        m.box((0.004, 0.170, 0.010), (0.030 + s * 0.046, 0.140, zb - 0.040), "Polymer_Green", L0, r=0.002)
        m.box((0.004, 0.170, 0.010), (0.030 + s * 0.046, 0.140, zb - 0.150), "Polymer_Green", L0, r=0.002)
    m.box((0.080, 0.030, 0.012), (0.030, 0.140, zb - 0.010), PH, L0, r=0.002)
    m.tube([(0.004, 0.080, zb - 0.028), (0.030, 0.090, zb - 0.006), (0.056, 0.080, zb - 0.028)], 0.003, PH, L01, segs=5)
    w.marker("ATT_Muzzle", (0, 0.905, B), note="flash hider face")
    w.marker("ATT_Optic", (-hw - 0.004, 0.100, B), note="Warsaw Pact side rail (left)")
    w.marker("GRIP_Main", (0, 0, 0), note="firing hand")
    w.marker("GRIP_Support", (0, 0.500, B + 0.095), note="carry handle (assault fire)")
    w.meta.update({"variant": "PKP Pecheneg 6P41 (infantry, bipod at the muzzle end)", "dimensions_m": {"overall": 1.20, "barrel": 0.658},
                   "source": "assets/weapons/_references/pkp_pecheneg/notes.md"})
    return w


# ---------------------------------------------------------------------------- MP-443 Grach


def mp443():
    z = 0.052
    w = W.Weapon("weapon_mp443", "MP-443 Grach", "RU", "pistol", "MP-443 Grach (PYa) 9 mm service pistol, steel slide, external hammer.")
    b = w.part("Body", note="frame")
    frame = rounded_outline([(0.126, z - 0.012), (0.126, z - 0.028, 0.004), (0.064, z - 0.030), (0.058, z - 0.054, 0.004), (0.020, z - 0.054, 0.004), (0.016, z - 0.040),
                             (-0.004, z - 0.064, 0.004), (-0.024, -0.078, 0.004), (-0.054, -0.078, 0.004), (-0.060, -0.068, 0.004), (-0.040, z - 0.030, 0.010),
                             (-0.056, z - 0.016, 0.008), (-0.060, z - 0.012, 0.004), (-0.050, z - 0.010)], 0.002, n=3)
    b.prism(frame, -0.0160, 0.0160, PB, ALL, bevel=0.0025, segs=3)
    b.cut(lambda t: t.prism(rounded_outline([(0.052, z - 0.033), (0.052, z - 0.048), (0.022, z - 0.048), (0.020, z - 0.033)], 0.004), -0.03, 0.03, PB, (0,), bevel=0))
    for s in (-1, 1):
        b.prism(rounded_outline([(0.000, z - 0.052), (-0.036, z - 0.046), (-0.054, -0.068), (-0.020, -0.072)], 0.006), s * 0.0160, s * 0.0170, PB, L01, bevel=0.0008)
        for j in range(5):
            b.box((0.0016, 0.026, 0.0020), (s * 0.0172, -0.026 - j * 0.0040, z - 0.060 - j * 0.0130), PB, L0, r=0.0004, rot=rx(-18))
        b.prism(rounded_outline([(-0.054, z + 0.004), (-0.030, z + 0.004), (-0.030, z + 0.014), (-0.050, z + 0.016)], 0.002), s * 0.0160, s * 0.0185, MB, L01,
                bevel=0.0006)                                                              # ambidextrous safety lever
    b.box((0.002, 0.026, 0.006), (-0.0165, 0.030, z - 0.016), MB, L01, r=0.0008)           # slide stop
    b.box((0.012, 0.010, 0.010), (0, -0.002, z - 0.040), MB, L0, r=0.002)                  # magazine catch
    # steel slide: blocky, flat top, rear serrations, ejection port, sights
    sl = w.part("Slide", pivot=(0, 0.0, z), axis="slide -y", note="slide (recoils / racks back)")
    so = rounded_outline([(-0.054, z - 0.012), (0.138, z - 0.012), (0.138, z + 0.010), (0.132, z + 0.018), (-0.050, z + 0.018), (-0.054, z + 0.012)], 0.0015)
    sl.prism(so, -0.0140, 0.0140, PBk, ALL, bevel=0.0018, segs=2)
    for s in (-1, 1):
        for j in range(9):
            sl.box((0.0012, 0.0018, 0.020), (s * 0.0141, -0.048 + j * 0.0036, z + 0.003), PBk, L0, r=0.0)
    sl.cut(lambda t: t.box((0.014, 0.046, 0.012), (0.011, 0.032, z + 0.012), MB, (0,), r=0))
    sl.box((0.0130, 0.044, 0.0100), (0.0010, 0.032, z + 0.0080), "Metal_Worn", L0, r=0.0008)
    sl.box((0.0040, 0.008, 0.0055), (0, 0.128, z + 0.021), PBk, L01, r=0.0008)
    sl.prism(rounded_outline([(-0.048, z + 0.018), (-0.034, z + 0.018), (-0.038, z + 0.026), (-0.048, z + 0.026)], 0.001), -0.0090, 0.0090, PBk, L01, bevel=0.0006)
    sl.box((0.0035, 0.012, 0.004), (0, -0.042, z + 0.026), MB, L0, r=0.0)
    sl.cyl(0.0058, 0.002, (0, 0.138, z), MB, L0, axis=(0, 1, 0), segs=14)
    h = w.part("Hammer", pivot=(0, -0.052, z - 0.004), axis="x (cocks back)", note="external hammer (down)")
    h.prism(rounded_outline([(-0.050, z - 0.008), (-0.056, z - 0.008), (-0.064, z + 0.012), (-0.058, z + 0.016), (-0.052, z + 0.006)], 0.0015), -0.004, 0.004, MB, ALL,
            bevel=0.0006)
    t = w.part("Trigger", pivot=(0, 0.036, z - 0.030), axis="x", note="DA/SA trigger")
    t.prism(rounded_outline([(0.038, z - 0.030), (0.043, z - 0.030), (0.039, z - 0.046), (0.032, z - 0.049), (0.031, z - 0.042)], 0.0015), -0.003, 0.003, MB, L01,
            bevel=0.0005)
    m = w.magazine((-0.028, 0.0, z - 0.034))
    m.prism(rounded_outline([(-0.004, z - 0.036), (-0.042, z - 0.036), (-0.068, -0.080), (-0.028, -0.080)], 0.003), -0.0110, 0.0110, "Metal_Worn", ALL, bevel=0.001)
    m.prism(rounded_outline([(-0.024, -0.078), (-0.070, -0.078), (-0.071, -0.086), (-0.023, -0.086)], 0.003), -0.0140, 0.0140, PB, ALL, bevel=0.0015)
    w.marker("ATT_Muzzle", (0, 0.139, z), note="muzzle face")
    w.marker("GRIP_Main", (0, 0, 0), note="firing hand")
    w.marker("GRIP_Support", (0.012, -0.010, -0.020), note="support hand wraps the firing hand")
    w.fps = {"fps_hip": ((-0.06, -0.42, 0.11), (0.0, 1.0, -0.12)), "fps_ads": ((0.0, -0.40, z + 0.024), (0.0, 1.0, 0.0))}
    w.meta.update({"variant": "MP-443 Grach (PYa), polymer-frame form", "bore_z": z, "dimensions_m": {"length": 0.198, "height": 0.140, "width": 0.038, "barrel": 0.112},
                   "source": "assets/weapons/_references/mp443/notes.md"})
    return w


BUILDERS = {"pkp_pecheneg": pkp_pecheneg, "mp443": mp443}
