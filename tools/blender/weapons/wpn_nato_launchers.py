"""NATO-07 Carl-Gustaf M4 and NATO-08 M72 LAW (Nammo M72 EC Mk1), Norwegian Army.

Carl-Gustaf M4 (Saab; Norwegian framework agreement January 2021): 84 mm recoilless rifle, under 1,000 mm and under
7 kg (Saab data): carbon-fibre wrapped barrel (black) with the OD steel liner ends, rear venturi with the conical
blast flare, rear firing grip and shoulder rest, front grip, carry handle, top-left sight rail with a fire-control
sight, folding bipod. Exterior only. Launcher space: origin = firing (pistol) grip, +Y = muzzle, tube axis at z = TUBE_Z.
M72 EC Mk1: Nammo (made under licence at Raufoss since 1966), 66 mm, 780 mm carried / 980 mm extended, 3.4 kg (Nammo
data). Modelled extended and ready: OD outer (rear) tube, inner (front) tube, trigger housing with the rubber trigger
bar, folding front sight frame and rear peep sight, end covers removed, sling. Origin = where the firing hand sits on
the trigger housing; tube axis at z = M72_TUBE_Z.
"""
import math

from mathutils import Vector

import wpn_lib as W
import wpn_nato_rifles as R
import wpn_nato_mg as MG
from wpn_lib import ALL, L0, L01, L12, L2, rx, ry, rounded_outline

OD = "Launcher_OD"
CF = "Composite_Dark"
MB = "Metal_Black"
PB = "Polymer_Black"
TUBE_Z = 0.120
M72_TUBE_Z = 0.045


# ---------------------------------------------------------------------------- Carl-Gustaf M4


def carl_gustaf_m4():
    w = W.Weapon("weapon_carl_gustaf_m4", "Carl-Gustaf M4", "NATO", "recoilless",
                 "Saab Carl-Gustaf M4 84 mm recoilless rifle (Norwegian Army, 2021 framework).")
    z = TUBE_Z
    b = w.part("Body")
    y0, y1 = -0.430, 0.555
    # barrel: carbon-fibre body, steel liner bands, muzzle ring, venturi + conical blast flare
    b.lathe([(0.0, y0 + 0.200), (0.052, y0 + 0.200), (0.052, y1 - 0.120), (0.0, y1 - 0.120)], (0, 0, z), (0, 1, 0), CF, ALL, segs=32)
    b.lathe([(0.044, y1 - 0.130), (0.054, y1 - 0.130), (0.056, y1 - 0.040), (0.062, y1 - 0.030), (0.062, y1), (0.044, y1), (0.044, y1 - 0.130)], (0, 0, z), (0, 1, 0), OD,
            ALL, segs=32)
    for yy in (y0 + 0.260, 0.020, 0.300):
        b.lathe([(0.0515, -0.010), (0.0555, -0.008), (0.0555, 0.008), (0.0515, 0.010), (0.0515, -0.010)], (0, yy, z), (0, 1, 0), OD, L01, segs=32)
    vent = [(0.042, y0 + 0.210), (0.054, y0 + 0.210), (0.056, y0 + 0.150), (0.064, y0 + 0.110), (0.080, y0 + 0.040), (0.088, y0), (0.080, y0), (0.072, y0 + 0.040),
            (0.050, y0 + 0.120), (0.042, y0 + 0.150), (0.042, y0 + 0.210)]
    b.lathe(vent, (0, 0, z), (0, 1, 0), OD, ALL, segs=32)
    b.lathe([(0.0, y1 - 0.010), (0.044, y1 - 0.010), (0.044, y1 - 0.006), (0.0, y1 - 0.006)], (0, 0, z), (0, 1, 0), "Metal_Black", L0, segs=24)   # bore shadow (rifling)
    for k in range(24):                                                     # rifling grooves seen in the muzzle
        a = 2 * math.pi * k / 24
        b.box((0.0025, 0.030, 0.0025), (math.cos(a) * 0.0425, y1 - 0.020, z + math.sin(a) * 0.0425), MB, L0, r=0.0, rot=ry(-math.degrees(a)))
    # rear firing grip with the trigger group, shoulder rest under the tube behind it
    b.box((0.034, 0.090, 0.040), (0, 0.000, z - 0.066), OD, ALL, r=0.006)
    R.pistol_grip(b, k=1.1, hk=False)
    b.tube([(0, 0.038, z - 0.086), (0, 0.040, z - 0.112), (0, 0.006, z - 0.114), (0, -0.004, z - 0.092)], 0.004, OD, ALL, segs=6)
    sh = rounded_outline([(-0.060, z - 0.050), (-0.260, z - 0.050), (-0.272, z - 0.070), (-0.270, z - 0.150, 0.010), (-0.220, z - 0.152), (-0.120, z - 0.090, 0.020),
                          (-0.060, z - 0.086)], 0.008, n=4)
    b.prism(sh, -0.022, 0.022, PB, ALL, bevel=0.004, segs=3)
    b.box((0.046, 0.016, 0.110), (0, -0.270, z - 0.106), "Rubber_Black", L01, r=0.004)
    # front grip (folding) and carry handle
    fg = w.part("Foregrip", pivot=(0, 0.200, z - 0.052), axis="x (folds forward)", note="front grip")
    fg.box((0.032, 0.040, 0.020), (0, 0.200, z - 0.058), OD, ALL, r=0.004)
    fg.lathe([(0.0, 0.0), (0.0155, 0.0), (0.0160, -0.020), (0.0150, -0.090), (0.0165, -0.100), (0.0, -0.104)], (0, 0.200, z - 0.066), (0, 0, 1), PB, ALL, segs=18)
    b.prism(rounded_outline([(0.110, z + 0.050), (0.124, z + 0.050), (0.120, z + 0.108), (-0.020, z + 0.108), (-0.024, z + 0.050), (-0.010, z + 0.050),
                             (-0.006, z + 0.094), (0.106, z + 0.094)], 0.008), -0.009, 0.009, OD, ALL, bevel=0.002)
    # sight rail on the left with a fire-control sight, iron sights
    b.box((0.030, 0.200, 0.020), (-0.066, 0.060, z + 0.030), OD, ALL, r=0.003)
    b.rail(-0.020, 0.150, z + 0.040, "Weapon_Anodized", L01, x=-0.066)
    o = w.part("Optic", pivot=(-0.066, 0.060, z + 0.050), axis="", note="fire-control sight (removable)")
    o.box((0.058, 0.110, 0.060), (-0.068, 0.060, z + 0.084), MB, ALL, r=0.008)
    o.box((0.040, 0.004, 0.036), (-0.068, 0.116, z + 0.090), "Lens", L01, r=0.002)
    o.box((0.036, 0.004, 0.030), (-0.068, 0.004, z + 0.090), "Lens", L01, r=0.002)
    for k in range(3):
        o.box((0.006, 0.010, 0.012), (-0.098, 0.040 + k * 0.016, z + 0.090), MB, L0, r=0.0015)
    o.box((0.020, 0.040, 0.012), (-0.068, 0.060, z + 0.056), MB, ALL, r=0.002)
    b.box((0.004, 0.012, 0.030), (-0.066, 0.420, z + 0.064), OD, L01, r=0.001)                       # folding front sight
    MG.bipod_deployed(w, 0.330, z - 0.050, leg=0.20, spread=26, splay_back=-10)
    w.marker("ATT_Muzzle", (0, y1, z), note="muzzle face (84 mm)")
    w.marker("ATT_Breech", (0, y0, z), note="venturi exit (back-blast)")
    w.marker("ATT_Optic", (-0.066, 0.060, z + 0.050), note="sight rail")
    w.marker("GRIP_Main", (0, 0, 0), note="firing hand")
    w.marker("GRIP_Support", (0, 0.200, z - 0.100), note="support hand on the front grip")
    w.marker("ATT_Shoulder", (0, -0.150, z), note="shoulder contact (tube on the shoulder)")
    # launcher on the right shoulder, the eye behind the sight on the left of the tube
    w.fps = {"fps_hip": ((-0.20, -0.48, z + 0.16), (0.08, 1.0, -0.12)), "fps_ads": ((-0.068, -0.26, z + 0.092), (0.0, 1.0, 0.0))}
    w.meta.update({"variant": "Carl-Gustaf M4 (Norway)", "bore_z": z, "dimensions_m": {"length": round(y1 - y0, 3), "calibre": 0.084},
                   "source": "assets/weapons/_references/carl_gustaf_m4/notes.md"})
    return w


# ---------------------------------------------------------------------------- M72 EC Mk1


def m72_law():
    w = W.Weapon("weapon_m72_law", "M72 EC Mk1 LAW", "NATO", "launcher_disposable",
                 "Nammo M72 EC Mk1 66 mm light anti-armour weapon (made at Raufoss), extended and ready to fire.")
    z = M72_TUBE_Z
    b = w.part("Body", note="outer (rear) tube with the trigger housing")
    y0, yj = -0.300, 0.250                       # rear end, joint of the two tubes
    b.lathe([(0.0390, y0), (0.0415, y0), (0.0415, yj), (0.0390, yj), (0.0390, y0)], (0, 0, z), (0, 1, 0), OD, ALL, segs=28)
    b.lathe([(0.0405, y0 - 0.004), (0.0440, y0 - 0.004), (0.0440, y0 + 0.020), (0.0405, y0 + 0.020), (0.0405, y0 - 0.004)], (0, 0, z), (0, 1, 0), OD, L01, segs=28)
    b.lathe([(0.0405, yj - 0.020), (0.0440, yj - 0.020), (0.0440, yj + 0.004), (0.0405, yj + 0.004), (0.0405, yj - 0.020)], (0, 0, z), (0, 1, 0), OD, L01, segs=28)
    # yellow ammunition band (HEAT, as on the Nordic EC photographs) and the stencil panel
    b.lathe([(0.0416, -0.040), (0.0419, -0.040), (0.0419, 0.020), (0.0416, 0.020), (0.0416, -0.040)], (0, 0, z), (0, 1, 0), "Polymer_Tan", L01, segs=28)
    # trigger housing (top) with the rubber trigger bar, safety handle, rear peep sight
    b.prism(rounded_outline([(-0.040, z + 0.036), (0.060, z + 0.036), (0.066, z + 0.052), (0.000, z + 0.062), (-0.046, z + 0.052)], 0.006), -0.020, 0.020, OD, ALL,
            bevel=0.003)
    b.box((0.016, 0.044, 0.010), (0, 0.020, z + 0.064), "Rubber_Black", ALL, r=0.004)
    b.box((0.010, 0.026, 0.012), (0.024, -0.020, z + 0.048), PB, L01, r=0.002)
    rs = w.part("RearSight", pivot=(0, -0.236, z + 0.042), axis="x (flips up)", note="rear peep sight (raised)")
    rs.box((0.030, 0.026, 0.012), (0, -0.236, z + 0.046), OD, ALL, r=0.003)
    rs.box((0.026, 0.006, 0.040), (0, -0.236, z + 0.070), OD, ALL, r=0.002)
    rs.lathe([(0.0020, -0.003), (0.0055, -0.003), (0.0055, 0.003), (0.0020, 0.003), (0.0020, -0.003)], (0, -0.236, z + 0.082), (0, 1, 0), MB, L0, segs=12)
    # inner (front) tube, extended, with the front sight frame and the front cover removed
    ft = w.part("FrontTube", pivot=(0, yj, z), axis="slide -y (telescopes in)", note="inner tube, extended")
    y1 = yj + 0.430
    ft.lathe([(0.0350, yj - 0.200), (0.0375, yj - 0.200), (0.0375, y1 - 0.030), (0.0395, y1 - 0.020), (0.0395, y1), (0.0350, y1), (0.0350, yj - 0.200)], (0, 0, z),
             (0, 1, 0), OD, ALL, segs=28)
    ft.lathe([(0.0, y1 - 0.040), (0.0350, y1 - 0.040), (0.0350, y1 - 0.036), (0.0, y1 - 0.036)], (0, 0, z), (0, 1, 0), "Weapon_PaintBlack", L0, segs=24)  # warhead seen in the tube
    fs = w.part("FrontSight", pivot=(0, y1 - 0.060, z + 0.038), parent="FrontTube", axis="x (flips up)", note="front sight frame (raised)")
    fs.box((0.034, 0.030, 0.008), (0, y1 - 0.060, z + 0.040), OD, ALL, r=0.002)
    fs.prism(rounded_outline([(y1 - 0.064, z + 0.042), (y1 - 0.056, z + 0.042), (y1 - 0.056, z + 0.104), (y1 - 0.064, z + 0.104)], 0.002), -0.022, 0.022, OD, ALL,
             bevel=0.001)
    fs.box((0.040, 0.004, 0.056), (0, y1 - 0.060, z + 0.074), "Lens", L01, r=0.0)       # graticule window
    for k in range(4):
        fs.box((0.024, 0.0045, 0.0010), (0, y1 - 0.0618, z + 0.060 + k * 0.012), "Polymer_Black", L0, r=0.0)
    # sling
    b.tube([(0.042, y0 + 0.030, z - 0.006), (0.060, y0 + 0.080, z - 0.050), (0.060, yj - 0.060, z - 0.050), (0.042, yj - 0.030, z - 0.006)], 0.006, "Strap_Black", L01,
           segs=6)
    w.marker("ATT_Muzzle", (0, y1, z), note="front tube mouth (66 mm)")
    w.marker("ATT_Breech", (0, y0, z), note="rear opening (back-blast)")
    w.marker("GRIP_Main", (0, 0, 0), note="firing hand on the trigger housing")
    w.marker("GRIP_Support", (0, 0.300, z - 0.040), note="support hand under the front tube")
    w.marker("ATT_Shoulder", (0, -0.120, z), note="shoulder contact")
    w.fps = {"fps_hip": ((-0.18, -0.50, z + 0.14), (0.06, 1.0, -0.10)), "fps_ads": ((0.0, -0.34, z + 0.082), (0.0, 1.0, 0.0))}
    w.meta.update({"variant": "Nammo M72 EC Mk1 (extended)", "bore_z": z, "dimensions_m": {"extended": round(y1 - y0, 3), "carried": 0.78, "calibre": 0.066},
                   "source": "assets/weapons/_references/m72_law/notes.md"})
    return w


BUILDERS = {"carl_gustaf_m4": carl_gustaf_m4, "m72_law": m72_law}
