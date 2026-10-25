"""NATO-05 Glock 17 (Norwegian service pistol P80) and NATO-06 Accuracy International AXMC.

Glock 17: 202 mm long, 139 mm high (with magazine), 32-34 mm wide, 114 mm barrel. Modelled as the Gen 5 form
(no finger grooves, flared magwell, front slide serrations); the Norwegian P80 generation in service is not
documented in the sources found. Pistol weapon space: origin = grip centre where the hand closes, +Y muzzle,
bore at z = PISTOL_BORE (0.052).
AXMC: Accuracy International AX multi-calibre .338 Lapua Magnum, 27 in (686 mm) barrel, 1,280 mm stock extended /
1,030 mm folded (AI data via modernfirearms / IMFDB; no verified Norwegian configuration: documented NATO variant,
AI pale-green finish), Schmidt & Bender PM II 5-25x56, bipod, 10-round magazine. Rifle weapon space (bore 0.074).
"""
import math

from mathutils import Vector

import wpn_lib as W
import wpn_nato_rifles as R
import wpn_nato_mg as MG
from wpn_lib import ALL, L0, L01, L12, L2, BORE_Z, rx, ry, rounded_outline, arc

PB = "Polymer_Black"
MB = "Metal_Black"
AN = "Weapon_Anodized"
PH = "Weapon_Phosphate"
PISTOL_BORE = 0.052


# ---------------------------------------------------------------------------- Glock 17


def glock_17():
    w = W.Weapon("weapon_glock_17", "Glock 17", "NATO", "pistol",
                 "Glock 17 9 mm pistol (Norwegian service pistol P80), Gen 5 form.")
    z = PISTOL_BORE
    b = w.part("Body", note="frame (polymer)")
    # frame: dust cover with the accessory rail, trigger guard, raked grip with the flared magwell
    frame = rounded_outline([(0.122, z - 0.012), (0.122, z - 0.026, 0.004), (0.060, z - 0.030), (0.050, z - 0.046, 0.006), (0.054, z - 0.052, 0.004),
                             (0.020, z - 0.052, 0.006), (0.016, z - 0.040), (-0.002, z - 0.064, 0.004), (-0.022, -0.072, 0.004), (-0.050, -0.072, 0.004),
                             (-0.058, -0.064, 0.004), (-0.036, z - 0.030, 0.010), (-0.054, z - 0.016, 0.008), (-0.058, z - 0.012, 0.004),
                             (-0.050, z - 0.010)], 0.002, n=3)
    b.prism(frame, -0.0150, 0.0150, PB, ALL, bevel=0.0025, segs=3)
    # trigger-guard opening and the grip texture panels
    b.cut(lambda t: t.prism(rounded_outline([(0.048, z - 0.033), (0.050, z - 0.046), (0.022, z - 0.046), (0.020, z - 0.033)], 0.006), -0.03, 0.03, PB, (0,), bevel=0))
    for s in (-1, 1):
        b.prism(rounded_outline([(0.004, z - 0.050), (-0.034, z - 0.044), (-0.050, -0.062), (-0.016, -0.066)], 0.006), s * 0.0150, s * 0.0157, PB, L0, bevel=0.0007)
    b.rail(0.080, 0.118, z - 0.032, PB, L0, rot=ry(180), width=0.020)
    # Gen 5: flared magwell lip, slide stop (left), takedown tabs, ambidextrous mag release
    b.prism(rounded_outline([(-0.002, -0.058), (-0.052, -0.058), (-0.060, -0.070), (0.004, -0.070)], 0.003), -0.0165, 0.0165, PB, L01, bevel=0.0012)
    b.box((0.002, 0.026, 0.005), (-0.0155, 0.030, z - 0.016), MB, L01, r=0.0008)
    for s in (-1, 1):
        b.box((0.003, 0.006, 0.004), (s * 0.0155, 0.046, z - 0.016), MB, L0, r=0.0006)
        b.box((0.004, 0.006, 0.008), (s * 0.0150, 0.010, z - 0.036), PB, L0, r=0.0012)
    # slide (moves back): serrations front and rear, ejection port (right), sights, barrel hood, muzzle
    sl = w.part("Slide", pivot=(0, 0.0, z), axis="slide -y", note="slide (recoils / racks back)")
    so = rounded_outline([(-0.056, z - 0.012), (0.130, z - 0.012), (0.130, z + 0.012), (0.126, z + 0.016), (-0.052, z + 0.016), (-0.056, z + 0.012)], 0.0015)
    sl.prism(so, -0.0128, 0.0128, "Weapon_Phosphate", ALL, bevel=0.0018, segs=2)
    sl.prism(rounded_outline([(-0.050, z + 0.012), (0.124, z + 0.012), (0.122, z + 0.0175), (-0.048, z + 0.0175)], 0.002), -0.0100, 0.0100, "Weapon_Phosphate", ALL,
             bevel=0.002)
    for s in (-1, 1):
        for j in range(8):
            sl.box((0.0012, 0.0016, 0.024), (s * 0.0129, -0.046 + j * 0.0034, z + 0.001), "Weapon_Phosphate", L0, r=0.0)
            sl.box((0.0012, 0.0016, 0.024), (s * 0.0129, 0.098 + j * 0.0034, z + 0.001), "Weapon_Phosphate", L0, r=0.0)
    sl.cut(lambda t: t.box((0.012, 0.044, 0.012), (0.010, 0.030, z + 0.010), MB, (0,), r=0))
    sl.box((0.0120, 0.042, 0.0105), (0.0010, 0.030, z + 0.0055), "Metal_Worn", L0, r=0.0008)             # barrel hood in the port
    sl.box((0.0040, 0.006, 0.0050), (0, 0.122, z + 0.020), "Polymer_Black", L01, r=0.0008)               # front sight
    sl.prism(rounded_outline([(-0.048, z + 0.017), (-0.036, z + 0.017), (-0.040, z + 0.025), (-0.048, z + 0.025)], 0.001), -0.0080, 0.0080, PB, L01, bevel=0.0006)
    sl.box((0.0035, 0.012, 0.004), (0, -0.042, z + 0.025), MB, L0, r=0.0)                                # rear notch shadow
    sl.cyl(0.0058, 0.002, (0, 0.130, z), MB, L0, axis=(0, 1, 0), segs=14)                                # bore
    t = w.part("Trigger", pivot=(0, 0.034, z - 0.030), axis="x", note="safe-action trigger")
    t.prism(rounded_outline([(0.036, z - 0.030), (0.040, z - 0.030), (0.036, z - 0.044), (0.031, z - 0.046), (0.030, z - 0.040)], 0.0015), -0.003, 0.003, PB, L01,
            bevel=0.0005)
    m = w.magazine((-0.026, 0.0, z - 0.034))
    mo = rounded_outline([(-0.004, z - 0.036), (-0.040, z - 0.036), (-0.064, -0.074), (-0.026, -0.074)], 0.003)
    m.prism(mo, -0.0105, 0.0105, PB, ALL, bevel=0.001)
    m.prism(rounded_outline([(-0.022, -0.072), (-0.066, -0.072), (-0.067, -0.080), (-0.021, -0.080)], 0.003), -0.0130, 0.0130, PB, ALL, bevel=0.0015)
    w.marker("ATT_Muzzle", (0, 0.131, z), note="muzzle face")
    w.marker("ATT_RailUnder", (0, 0.100, z - 0.032), note="dust-cover rail (light)")
    w.marker("GRIP_Main", (0, 0, 0), note="firing hand")
    w.marker("GRIP_Support", (0.012, -0.010, -0.020), note="support hand wraps the firing hand")
    w.fps = {"fps_hip": ((-0.06, -0.42, 0.11), (0.0, 1.0, -0.12)), "fps_ads": ((0.0, -0.40, z + 0.022), (0.0, 1.0, 0.0))}
    w.meta.update({"variant": "Glock 17 Gen 5 form (Norwegian P80 = Glock 17)", "bore_z": z,
                   "dimensions_m": {"length": 0.202, "height": 0.139, "width": 0.034, "barrel": 0.114}, "source": "assets/weapons/_references/glock_17/notes.md"})
    return w


# ---------------------------------------------------------------------------- AXMC


def axmc():
    B = BORE_Z
    w = W.Weapon("weapon_axmc", "Accuracy International AXMC", "NATO", "sniper_rifle",
                 "Accuracy International AXMC .338 Lapua Magnum precision rifle, folding stock, Schmidt & Bender PM II, bipod.")
    G = "Polymer_Green"
    b = w.part("Body")
    # aluminium chassis with the action, pistol grip, magwell, trigger guard
    ch = rounded_outline([(-0.070, B - 0.020), (0.270, B - 0.020), (0.270, B - 0.046), (0.150, B - 0.052), (0.120, B - 0.098, 0.006), (0.050, B - 0.098, 0.006),
                          (0.040, B - 0.060), (0.010, B - 0.062), (-0.020, B - 0.070), (-0.070, B - 0.050)], 0.004)
    b.prism(ch, -0.026, 0.026, G, ALL, bevel=0.0025, segs=2)
    b.cut(lambda t: t.prism(rounded_outline([(0.040, B - 0.064), (0.034, B - 0.086), (0.002, B - 0.086), (0.004, B - 0.070)], 0.006), -0.04, 0.04, G, (0,), bevel=0))
    # action (round receiver) and the long top rail, bolt shroud
    b.lathe([(0.0, -0.090), (0.0175, -0.090), (0.0185, -0.080), (0.0185, 0.150), (0.0175, 0.160), (0.0, 0.160)], (0, 0, B + 0.002), (0, 1, 0), MB, ALL, segs=24)
    b.rail(-0.085, 0.420, B + 0.022, AN, L01, width=0.022)
    b.box((0.003, 0.090, 0.020), (0.0185, 0.050, B + 0.004), MB, L01, r=0.0008)                          # ejection port
    # AX handguard: octagonal tube with rails at 3/6/9 o'clock and lightening cuts
    def ring(y, h=0.030, c=0.010):
        return [(x, y, B + zz) for x, zz in ((h - c, -h), (h, -h + c), (h, h - c), (h - c, h), (-h + c, h), (-h, h - c), (-h, -h + c), (-h + c, -h))]
    b.loft([ring(0.150), ring(0.440)], G, ALL)
    for ang in (90, 180, 270):
        b.rail(0.170, 0.430, B + 0.029, AN, L0, rot=ry(ang))
    for s in (-1, 1):
        for j in range(5):
            b.cut(lambda t, s=s, j=j: t.prism(rounded_outline([(0.190 + j * 0.048, B - 0.008), (0.222 + j * 0.048, B - 0.008), (0.222 + j * 0.048, B + 0.010),
                                                                  (0.190 + j * 0.048, B + 0.010)], 0.006), s * 0.020, s * 0.040, G, (0,), bevel=0))
    # .338 barrel (heavy, fluted) and the muzzle brake
    b.lathe([(0.0, 0.440), (0.0125, 0.440), (0.0115, 0.600), (0.0105, 0.830), (0.0, 0.830)], (0, 0, B), (0, 1, 0), MB, ALL, segs=20)
    for j in range(6):
        a = math.radians(60 * j)
        b.box((0.0022, 0.140, 0.0030), (math.cos(a) * 0.0118, 0.520, B + math.sin(a) * 0.0118), MB, L0, r=0.0004, rot=ry(-math.degrees(a)))
    b.lathe([(0.0, 0.828), (0.0155, 0.828), (0.0155, 0.900), (0.0140, 0.905), (0.0, 0.905)], (0, 0, B), (0, 1, 0), MB, ALL, segs=20)
    for j in range(3):
        for s in (-1, 1):
            b.box((0.006, 0.010, 0.014), (s * 0.0150, 0.846 + j * 0.020, B), MB, L0, r=0.0008)
    R.pistol_grip(b, k=1.05, mat=G, hk=False)
    R.trigger(w, y=0.030)
    # bolt (separate: lifts and pulls back) with the big knob on the right
    bo = w.part("Bolt", pivot=(0.020, -0.020, B + 0.002), axis="y (lift) + slide -y", note="bolt handle")
    bo.cyl_between((0.016, -0.020, B + 0.002), (0.060, -0.030, B - 0.016), 0.0045, MB, ALL, segs=10)
    bo.lathe([(0.0, -0.006), (0.0100, -0.004), (0.0110, 0.006), (0.0, 0.012)], (0.064, -0.032, B - 0.020), (0.8, -0.2, -0.4), MB, ALL, segs=16)
    bo.lathe([(0.0, 0.0), (0.0150, 0.0), (0.0150, 0.020), (0.0, 0.020)], (0, -0.112, B + 0.002), (0, 1, 0), MB, L01, segs=18)
    # folding skeleton stock with the adjustable cheek piece and butt pad (separate: folds left)
    st = w.part("Stock", pivot=(-0.025, -0.072, B - 0.020), axis="z (folds left)", note="folding, adjustable skeleton stock")
    yb = -0.380
    so = rounded_outline([(-0.072, B - 0.004), (yb + 0.040, B - 0.004), (yb + 0.030, B - 0.120, 0.010), (yb + 0.090, B - 0.120, 0.008), (-0.180, B - 0.060, 0.020),
                          (-0.072, B - 0.060)], 0.006, n=4)
    st.prism(so, -0.016, 0.016, G, ALL, bevel=0.003, segs=2)
    st.cut(lambda t: t.prism(rounded_outline([(-0.110, B - 0.020), (yb + 0.090, B - 0.020), (yb + 0.090, B - 0.044), (-0.150, B - 0.044)], 0.006), -0.03, 0.03, G, (0,),
                             bevel=0))
    st.prism(rounded_outline([(-0.130, B + 0.012), (yb + 0.050, B + 0.012), (yb + 0.050, B + 0.034), (-0.140, B + 0.034)], 0.008), -0.018, 0.018, G, ALL, bevel=0.004, segs=2)
    for s in (-1, 1):
        st.cyl(0.004, 0.014, (s * 0.010, -0.240, B + 0.003), MB, L0, segs=8)
    st.prism(rounded_outline([(yb + 0.040, B + 0.040), (yb + 0.020, B + 0.040), (yb + 0.020, B - 0.130), (yb + 0.040, B - 0.130)], 0.008), -0.022, 0.022, "Rubber_Black", ALL,
             bevel=0.004)
    st.box((0.020, 0.030, 0.050), (0, yb + 0.080, B - 0.140), MB, L01, r=0.004)                        # monopod
    st.box((0.024, 0.060, 0.014), (-0.020, -0.090, B - 0.030), MB, L0, r=0.003)                        # hinge
    m = w.magazine((0.110, 0.0, B - 0.050))
    m.prism(rounded_outline([(0.152, B - 0.050), (0.068, B - 0.050), (0.068, B - 0.126), (0.152, B - 0.126)], 0.004), -0.0130, 0.0130, MB, ALL, bevel=0.0015)
    m.prism(rounded_outline([(0.154, B - 0.126), (0.066, B - 0.126), (0.066, B - 0.134), (0.154, B - 0.134)], 0.003), -0.0145, 0.0145, MB, ALL, bevel=0.0012)
    R.sb_pmii(w, 0.090, B + 0.022 + 0.0105, length=0.40, obj_r=0.034, tube_r=0.017)
    R.bipod_folded(w, 0.390, B - 0.030 - 0.010, length=0.22)
    w.marker("ATT_Optic", (0, 0.090, B + 0.0325), note="top rail (PM II fitted)")
    w.marker("ATT_Muzzle", (0, 0.905, B), note="muzzle brake face")
    w.marker("ATT_Underbarrel", (0, 0.390, B - 0.040), note="bottom rail (bipod fitted)")
    w.marker("GRIP_Main", (0, 0, 0), note="firing hand")
    w.marker("GRIP_Support", (0, -0.290, B - 0.100), note="support hand under the butt (prone)")
    w.meta.update({"variant": "Accuracy International AXMC .338 LM (AI pale green), 27 in barrel", "dimensions_m": {"overall": 1.28, "folded": 1.03, "barrel": 0.686},
                   "source": "assets/weapons/_references/axmc/notes.md"})
    return w


BUILDERS = {"glock_17": glock_17, "axmc": axmc}
