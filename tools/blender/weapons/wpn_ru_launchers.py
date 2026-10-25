"""RUS-07 RPG-7V2 with PGO-7 and a PG-7V grenade, RUS-08 RPG-26 Aglen (Russian Army).

RPG-7V2: 40 mm launcher tube, 950 mm, 6.3 kg (Bazalt data); wooden heat shield, firing grip and front grip, rear blast
cone (venturi), folding iron sights, PGO-7V3 2.7x optic on the left-side bracket. Loaded with the PG-7V (85 mm HEAT
warhead with the nose fuze, the stabiliser tube inside the launcher). Origin = firing grip, tube axis at z = RPG7_Z.
RPG-26: 72.5 mm one-shot launcher, 770 mm, 2.9 kg (Bazalt data); green glass-fibre tube with end caps, cocking and
firing mechanism on top, folding front and rear sights, sling. Origin = support of the firing hand under the tube
behind the mechanism; tube axis at z = RPG26_Z.
"""
import math

from mathutils import Vector

import wpn_lib as W
import wpn_nato_rifles as R
from wpn_lib import ALL, L0, L01, L12, L2, rx, ry, rounded_outline

MB = "Metal_Black"
PBk = "Weapon_PaintBlack"
PB = "Polymer_Black"
WD = "Wood_Laminate"
GR = "Launcher_Green"
RPG7_Z = 0.110
RPG26_Z = 0.046


# ---------------------------------------------------------------------------- RPG-7V2


def rpg7():
    z = RPG7_Z
    w = W.Weapon("weapon_rpg7", "RPG-7V2", "RU", "launcher", "RPG-7V2 40 mm reusable launcher with the PGO-7 optic, loaded with a PG-7V grenade.")
    b = w.part("Body")
    y0, y1 = -0.560, 0.390
    # launcher tube, breech section, blast cone
    b.lathe([(0.0200, -0.200), (0.0255, -0.200), (0.0255, y1 - 0.012), (0.0270, y1 - 0.008), (0.0270, y1), (0.0200, y1), (0.0200, -0.200)], (0, 0, z), (0, 1, 0), PBk, ALL,
            segs=28)
    cone = [(0.0200, -0.190), (0.0300, -0.190), (0.0320, -0.260), (0.0300, -0.300), (0.0300, -0.360), (0.0420, y0 + 0.090), (0.0560, y0 + 0.020), (0.0580, y0),
            (0.0520, y0), (0.0500, y0 + 0.020), (0.0360, y0 + 0.090), (0.0240, -0.360), (0.0240, -0.300), (0.0200, -0.260), (0.0200, -0.190)]
    b.lathe(cone, (0, 0, z), (0, 1, 0), PBk, ALL, segs=28)
    for yy in (-0.300, -0.215):
        b.lathe([(0.0300, -0.006), (0.0345, -0.006), (0.0345, 0.006), (0.0300, 0.006), (0.0300, -0.006)], (0, yy, z), (0, 1, 0), MB, L01, segs=24)
    # wooden heat shield: two half shells with the bands
    b.lathe([(0.0255, -0.140), (0.0360, -0.140), (0.0380, -0.120), (0.0380, 0.200), (0.0360, 0.220), (0.0255, 0.220), (0.0255, -0.140)], (0, 0, z), (0, 1, 0), WD, ALL,
            segs=28)
    for s in (-1, 1):
        b.box((0.0016, 0.330, 0.004), (s * 0.0378, 0.040, z), MB, L0, r=0.0005)
    for yy in (-0.120, 0.200):
        b.lathe([(0.0380, -0.008), (0.0400, -0.008), (0.0400, 0.008), (0.0380, 0.008), (0.0380, -0.008)], (0, yy, z), (0, 1, 0), MB, L01, segs=28)
    # firing grip with the trigger group and the hammer housing, front grip
    b.prism(rounded_outline([(-0.040, z - 0.030), (0.060, z - 0.030), (0.060, z - 0.088), (-0.040, z - 0.088)], 0.006), -0.017, 0.017, MB, ALL, bevel=0.0015)
    R.pistol_grip(b, k=1.05, mat=PB, hk=False)
    b.tube([(0, 0.044, z - 0.062), (0, 0.052, z - 0.096), (0, 0.010, z - 0.100), (0, -0.002, z - 0.080)], 0.0035, MB, ALL, segs=6)
    R.trigger(w, y=0.024)
    fg = w.part("Foregrip", pivot=(0, 0.160, z - 0.036), axis="", note="front grip")
    fg.box((0.030, 0.040, 0.020), (0, 0.160, z - 0.040), MB, ALL, r=0.003)
    fg.prism(rounded_outline([(0.176, z - 0.046), (0.146, z - 0.046), (0.136, z - 0.150, 0.008), (0.166, z - 0.154, 0.008), (0.182, z - 0.060)], 0.004, n=4), -0.0145,
             0.0145, PB, ALL, bevel=0.0035, segs=3)
    # iron sights: folding front post at the muzzle end, rear leaf over the grip
    b.prism(rounded_outline([(y1 - 0.060, z + 0.024), (y1 - 0.030, z + 0.024), (y1 - 0.034, z + 0.064), (y1 - 0.046, z + 0.064)], 0.003), -0.006, 0.006, MB, ALL,
            bevel=0.001)
    b.box((0.024, 0.040, 0.010), (0, y1 - 0.046, z + 0.026), MB, L01, r=0.002)
    b.box((0.022, 0.030, 0.010), (0, 0.000, z + 0.040), MB, L01, r=0.002)
    b.box((0.018, 0.006, 0.030), (0, 0.006, z + 0.056), MB, L01, r=0.001, rot=rx(-15))
    # PGO-7 bracket and optic (left)
    b.box((0.012, 0.080, 0.030), (-0.040, 0.000, z + 0.006), MB, ALL, r=0.002)
    o = w.part("Optic", pivot=(-0.046, 0.000, z + 0.020), axis="", note="PGO-7V3 optic (removable)")
    xo, zo = -0.064, z + 0.058
    o.box((0.020, 0.060, 0.050), (-0.050, 0.000, z + 0.030), MB, ALL, r=0.003)
    o.box((0.040, 0.110, 0.050), (xo, 0.000, zo), MB, ALL, r=0.008)
    o.lathe([(0.0, 0.050), (0.0170, 0.050), (0.0175, 0.090), (0.0, 0.090)], (xo, 0, zo + 0.004), (0, 1, 0), MB, ALL, segs=20)
    o.lathe([(0.0, 0.089), (0.0140, 0.089), (0.0140, 0.091), (0.0, 0.091)], (xo, 0, zo + 0.004), (0, 1, 0), "Lens", L01, segs=18)
    o.lathe([(0.0, -0.050), (0.0150, -0.050), (0.0170, -0.110), (0.0160, -0.118), (0.0, -0.112)], (xo, 0, zo + 0.006), (0, 1, 0), "Rubber_Black", ALL, segs=20)
    o.lathe([(0.0, 0.0), (0.012, 0.0), (0.012, 0.016), (0.0, 0.018)], (xo, 0.010, zo + 0.024), (0, 0, 1), MB, L01, segs=16)
    o.lathe([(0.0, 0.0), (0.011, 0.0), (0.011, 0.014), (0.0, 0.016)], (xo - 0.020, 0.010, zo), (-1, 0, 0), MB, L01, segs=16)
    # PG-7V grenade: stabiliser tube in the launcher, warhead cone, nose fuze
    g = w.part("Grenade", pivot=(0, y1, z), axis="slide y (loaded from the muzzle)", note="PG-7V HEAT grenade (loaded)")
    gy = y1 + 0.020
    prof = [(0.0, y1 - 0.060), (0.0195, y1 - 0.060), (0.0195, gy), (0.0300, gy + 0.010), (0.0380, gy + 0.060), (0.0425, gy + 0.090), (0.0425, gy + 0.170),
            (0.0360, gy + 0.200), (0.0200, gy + 0.300), (0.0110, gy + 0.340), (0.0100, gy + 0.380), (0.0060, gy + 0.392), (0.0, gy + 0.394)]
    g.lathe(prof, (0, 0, z), (0, 1, 0), "Launcher_OD", ALL, segs=28)
    g.lathe([(0.0420, -0.020), (0.0430, -0.020), (0.0430, 0.020), (0.0420, 0.020), (0.0420, -0.020)], (0, gy + 0.130, z), (0, 1, 0), MB, L01, segs=28)
    g.lathe([(0.0108, -0.012), (0.0112, -0.012), (0.0112, 0.010), (0.0108, 0.010), (0.0108, -0.012)], (0, gy + 0.370, z), (0, 1, 0), "Metal_Worn", L0, segs=14)
    # sling swivels
    for yy in (-0.120, 0.300):
        b.tube([(0.024, yy - 0.010, z - 0.020), (0.034, yy, z - 0.034), (0.024, yy + 0.010, z - 0.020)], 0.0025, MB, L01, segs=5)
    w.marker("ATT_Muzzle", (0, y1, z), note="launcher muzzle (grenade seated ahead of it)")
    w.marker("ATT_Breech", (0, y0, z), note="blast cone exit (back-blast)")
    w.marker("ATT_Optic", (-0.046, 0.000, z + 0.020), note="PGO-7 bracket (left)")
    w.marker("GRIP_Main", (0, 0, 0), note="firing hand")
    w.marker("GRIP_Support", (0, 0.160, z - 0.100), note="support hand on the front grip")
    w.marker("ATT_Shoulder", (0, -0.080, z), note="shoulder contact on the heat shield")
    w.fps = {"fps_hip": ((-0.18, -0.48, z + 0.14), (0.08, 1.0, -0.12)), "fps_ads": ((xo, -0.28, zo + 0.006), (0.0, 1.0, 0.0))}
    w.meta.update({"variant": "RPG-7V2 + PGO-7V3, PG-7V loaded", "bore_z": z, "dimensions_m": {"launcher": round(y1 - y0, 3), "calibre_tube": 0.040,
                   "grenade_calibre": 0.085}, "source": "assets/weapons/_references/rpg7/notes.md"})
    return w


# ---------------------------------------------------------------------------- RPG-26


def rpg26():
    z = RPG26_Z
    w = W.Weapon("weapon_rpg26", "RPG-26 Aglen", "RU", "launcher_disposable", "RPG-26 72.5 mm one-shot anti-tank launcher, sights raised, ready to fire.")
    b = w.part("Body")
    y0, y1 = -0.330, 0.440
    r = 0.0363
    b.lathe([(r - 0.003, y0), (r, y0), (r, y1), (r - 0.003, y1), (r - 0.003, y0)], (0, 0, z), (0, 1, 0), GR, ALL, segs=30)
    for (yy, ln) in ((y0 + 0.012, 0.024), (y1 - 0.012, 0.024)):
        b.lathe([(r - 0.002, -ln / 2), (r + 0.004, -ln / 2), (r + 0.004, ln / 2), (r - 0.002, ln / 2), (r - 0.002, -ln / 2)], (0, yy, z), (0, 1, 0), "Rubber_Black", ALL,
                segs=30)
    for yy in (-0.120, 0.200):
        b.lathe([(r - 0.001, -0.010), (r + 0.0015, -0.010), (r + 0.0015, 0.010), (r - 0.001, 0.010), (r - 0.001, -0.010)], (0, yy, z), (0, 1, 0), GR, L01, segs=30)
    b.lathe([(0.0, y1 - 0.030), (r - 0.003, y1 - 0.030), (r - 0.003, y1 - 0.026), (0.0, y1 - 0.026)], (0, 0, z), (0, 1, 0), PBk, L0, segs=24)
    # firing mechanism on top: housing, cocking lever, trigger button, safety pin with ring
    zt = z + r
    b.prism(rounded_outline([(-0.070, zt - 0.006), (0.080, zt - 0.006), (0.086, zt + 0.010), (0.060, zt + 0.024), (-0.060, zt + 0.024), (-0.074, zt + 0.010)], 0.006),
            -0.020, 0.020, GR, ALL, bevel=0.003)
    b.box((0.014, 0.060, 0.010), (0, -0.010, zt + 0.028), PB, ALL, r=0.003)
    b.box((0.018, 0.018, 0.012), (0, 0.050, zt + 0.030), "Rubber_Black", ALL, r=0.004)
    b.tube([(0.020, 0.030, zt + 0.010), (0.034, 0.030, zt + 0.004), (0.040, 0.040, zt - 0.010), (0.034, 0.050, zt - 0.020), (0.026, 0.040, zt - 0.010)], 0.0016,
           "Metal_Worn", L01, segs=5)
    # rear sight (raised peep) and front sight frame (raised)
    rs = w.part("RearSight", pivot=(0, -0.180, zt), axis="x (flips up)", note="rear sight (raised)")
    rs.box((0.026, 0.024, 0.010), (0, -0.180, zt + 0.004), GR, ALL, r=0.003)
    rs.box((0.024, 0.006, 0.040), (0, -0.180, zt + 0.028), GR, ALL, r=0.002)
    rs.lathe([(0.0020, -0.003), (0.0055, -0.003), (0.0055, 0.003), (0.0020, 0.003), (0.0020, -0.003)], (0, -0.180, zt + 0.040), (0, 1, 0), MB, L0, segs=12)
    fs = w.part("FrontSight", pivot=(0, 0.360, zt), axis="x (flips up)", note="front sight frame (raised)")
    fs.box((0.032, 0.026, 0.008), (0, 0.360, zt + 0.002), GR, ALL, r=0.002)
    fs.prism(rounded_outline([(0.356, zt + 0.004), (0.364, zt + 0.004), (0.364, zt + 0.060), (0.356, zt + 0.060)], 0.002), -0.020, 0.020, GR, ALL, bevel=0.001)
    fs.cut(lambda t: t.box((0.030, 0.030, 0.040), (0, 0.360, zt + 0.034), GR, (0,), r=0.002))
    fs.box((0.004, 0.004, 0.018), (0, 0.360, zt + 0.040), PB, L01, r=0.0)
    # sling
    b.tube([(0.038, y0 + 0.040, z - 0.004), (0.056, y0 + 0.090, z - 0.050), (0.056, y1 - 0.090, z - 0.050), (0.038, y1 - 0.040, z - 0.004)], 0.006, "Strap_Black", L01,
           segs=6)
    w.marker("ATT_Muzzle", (0, y1, z), note="front opening (72.5 mm)")
    w.marker("ATT_Breech", (0, y0, z), note="rear opening (back-blast)")
    w.marker("GRIP_Main", (0, 0, 0), note="firing hand under the mechanism")
    w.marker("GRIP_Support", (0, 0.250, z - 0.040), note="support hand under the front of the tube")
    w.marker("ATT_Shoulder", (0, -0.150, z), note="shoulder contact")
    w.fps = {"fps_hip": ((-0.18, -0.50, z + 0.14), (0.06, 1.0, -0.10)), "fps_ads": ((0.0, -0.32, zt + 0.040), (0.0, 1.0, 0.0))}
    w.meta.update({"variant": "RPG-26 Aglen (ready)", "bore_z": z, "dimensions_m": {"length": round(y1 - y0, 3), "calibre": 0.0725},
                   "source": "assets/weapons/_references/rpg26/notes.md"})
    return w


BUILDERS = {"rpg7": rpg7, "rpg26": rpg26}
