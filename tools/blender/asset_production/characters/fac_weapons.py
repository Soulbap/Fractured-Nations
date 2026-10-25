"""Faction rifles and optics (ASSET-PRODUCTION-01), original assets built from photo
proportions of the real families:
  rifle_nato  HK416A5-class 5.56 mm carbine: 14.5" barrel, slim M-LOK handguard, tan
              furniture, ribbed polymer magazine; optic_nato: 1-4x combat scope (Specter
              DR class) on a QD mount.
  rifle_ru    AK-12 (2020) class 5.45 mm rifle: stamped receiver with railed dust cover,
              long railed handguard over the gas tube, front-sight gas block, long
              muzzle brake, telescoping side-folding stock, plum polymer magazine;
              optic_ru: square-window reflex sight (1P87 / Valday class).
  rifle_cn    QBZ-191 class 5.8 mm rifle: blocky upper with a full-length rail, flared
              magwell, long handguard, telescoping stock with cheek riser, OD furniture;
              optic_cn: 3x prism sight (QMK-191 class) with a top accessory rail.

Weapon space contract (docs/CHARACTER_STANDARD.md section 3), shared by all weapons so
the one animation set fits: origin = pistol-grip centre, +Y muzzle, +Z up, bore axis at
z = 0.074, GRIP_Support at (0, 0.165, 0.074) with the standard support-hand frame,
ATT_Optic at z = 0.114 (optic axes 0.058 above their mount = the first-person sight
line, scripts/combat/viewmodel.gd). Optic housings crossing the sight line use
Metal_Black and glass uses Lens (the viewmodel cuts the bore of Metal_Black faces).
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import char_lib as L
import char_weapon as W

BORE_Z = W.BORE_Z
OPTIC_Z = BORE_Z + 0.040
SIGHT_H = 0.058


def rx(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


class WB:
    """Small bmesh helper with named material slots."""

    def __init__(self, mats, names):
        self.bm = bmesh.new()
        self.names = names
        self.mats = mats

    def _set(self, verts, mat):
        idx = self.names.index(mat)
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index = idx

    def box(self, size, c, mat, r=0.003, rot=None, segs=1):
        self._set(L.rounded_box(self.bm, size, Vector(c), r, rot=rot, segs=segs), mat)

    def cyl(self, r1, r2, depth, c, mat, axis=(0, 1, 0), segs=12):
        self._set(L.bm_cyl(self.bm, r1, r2, depth, Vector(c), axis=axis, segs=segs), mat)

    def obj(self, name, coll, smooth=35):
        o = L.new_object(name, self.bm, coll, [self.mats[n] for n in self.names])
        for p in o.data.polygons:
            p.use_smooth = True
        L.shade_smooth(o, smooth)
        if getattr(self, "mag", None):
            W.split_magazine(o, range(*self.mag[:2]), self.mag[2])
        return o

    def magazine(self, top, build):
        """Builds the detachable magazine (build() adds its parts) as its own object, origin `top`."""
        n0 = len(self.bm.verts)
        build()
        self.mag = (n0, len(self.bm.verts), top)


def rail(w, y0, y1, z, mat="Metal_Black", top=True):
    """Picatinny rail with cross slots along Y (top rail when top=True)."""
    w.box((0.022, y1 - y0, 0.008), (0, (y0 + y1) / 2, z), mat, 0.0015)
    n = int((y1 - y0) / 0.0105)
    for i in range(n):
        w.box((0.023, 0.0045, 0.003), (0, y0 + 0.005 + i * 0.0105, z + 0.0055), mat, 0.0008)


def mag_curve(w, top, segs, seg_h, depth, width, angle_step, mat, ribs=False, start_angle=-4.0):
    """Curved magazine as a chain of tilted boxes from the magwell down/forward."""
    c = Vector(top)
    ang = start_angle
    for i in range(segs):
        w.box((width, depth, seg_h + 0.004), c, mat, 0.004, rot=rx(-ang))
        if ribs and i % 2 == 0:
            w.box((width + 0.003, depth * 0.9, 0.006), c, mat, 0.002, rot=rx(-ang))
        step = Vector((0, math.sin(math.radians(-ang)) * seg_h, -math.cos(math.radians(-ang)) * seg_h))
        c = c + step
        ang -= angle_step
    w.box((width + 0.004, depth + 0.004, 0.012), c + Vector((0, 0, seg_h * 0.3)), mat, 0.004, rot=rx(-(ang + angle_step)))


# ============================================================================ NATO


def build_rifle_nato(coll, mats):
    w = WB(mats, ["Metal_Black", "Polymer_Tan", "Metal_Worn", "Polymer_Black"])
    z = BORE_Z
    # Lower receiver, flared magwell, trigger guard, controls.
    w.box((0.031, 0.190, 0.040), (0, -0.002, z - 0.044), "Metal_Black", 0.004)
    w.box((0.036, 0.070, 0.064), (0, 0.071, z - 0.060), "Metal_Black", 0.005, rot=rx(-4))
    w.box((0.040, 0.074, 0.012), (0, 0.072, z - 0.094), "Metal_Black", 0.004, rot=rx(-4))
    w.box((0.006, 0.060, 0.006), (0, 0.030, z - 0.083), "Metal_Black", 0.002)
    w.box((0.004, 0.008, 0.020), (0, 0.032, z - 0.066), "Metal_Worn", 0.0015, rot=rx(15))
    for sx in (-1, 1):
        w.box((0.012, 0.012, 0.006), (sx * 0.017, -0.006, z - 0.040), "Metal_Worn", 0.002)
        w.box((0.006, 0.016, 0.010), (sx * 0.0185, 0.040, z - 0.050), "Metal_Black", 0.002)       # ambi mag release
    # Upper receiver (HK piston upper), ejection port, charging handle.
    w.box((0.034, 0.210, 0.054), (0, 0.002, z + 0.004), "Metal_Black", 0.004)
    w.box((0.004, 0.070, 0.022), (0.018, 0.020, z + 0.002), "Metal_Worn", 0.002)
    w.box((0.044, 0.014, 0.010), (0, -0.110, z + 0.024), "Metal_Black", 0.003)
    rail(w, -0.105, 0.470, z + 0.034)
    # Slim M-LOK handguard (octagonal-ish) with slot rows, bottom rail section.
    w.box((0.046, 0.300, 0.050), (0, 0.262, z - 0.002), "Metal_Black", 0.012, segs=2)
    for sx in (-1, 1):
        for i in range(6):
            w.box((0.004, 0.030, 0.008), (sx * 0.0225, 0.150 + i * 0.045, z - 0.004), "Polymer_Black", 0.0015)
    w.box((0.020, 0.070, 0.007), (0, 0.330, z - 0.029), "Metal_Black", 0.0015)
    # Barrel, gas block under the rail, flash hider.
    w.cyl(0.0095, 0.0095, 0.095, (0, 0.455, z), "Metal_Black")
    w.cyl(0.0125, 0.0115, 0.060, (0, 0.530, z), "Metal_Worn", segs=14)
    for i in range(4):
        a = math.radians(45 + i * 90)
        w.box((0.003, 0.036, 0.004), (0.0118 * math.cos(a), 0.535, z + 0.0118 * math.sin(a)), "Metal_Black", 0.001)
    # Flip-up sights (folded).
    w.box((0.020, 0.034, 0.012), (0, 0.440, z + 0.044), "Metal_Black", 0.003)
    w.box((0.020, 0.030, 0.012), (0, -0.085, z + 0.044), "Metal_Black", 0.003)
    # Tan pistol grip with palm swell, slim-line stock on the buffer tube.
    w.box((0.030, 0.042, 0.106), (0, -0.002, -0.004), "Polymer_Tan", 0.010, rot=rx(-20), segs=2)
    w.box((0.032, 0.048, 0.010), (0, -0.020, -0.056), "Polymer_Tan", 0.004, rot=rx(-20))
    w.cyl(0.0155, 0.0155, 0.175, (0, -0.190, z), "Metal_Black")
    by = -W.STOCK_PULL
    w.box((0.040, 0.140, 0.050), (0, by + 0.090, z - 0.002), "Polymer_Tan", 0.012, segs=2)
    w.box((0.036, 0.100, 0.064), (0, by + 0.060, z - 0.052), "Polymer_Tan", 0.012, rot=rx(14), segs=2)
    w.box((0.042, 0.020, 0.135), (0, by + 0.010, z - 0.032), "Polymer_Black", 0.008, segs=2)
    w.box((0.006, 0.040, 0.008), (0.022, by + 0.070, z - 0.010), "Metal_Black", 0.002)
    # Tan ribbed polymer magazine (straighter than an AK magazine).
    w.magazine((0, 0.074, z - 0.090), lambda: mag_curve(w, (0, 0.074, z - 0.090), 5, 0.034, 0.064, 0.025, 2.5, "Polymer_Tan", ribs=True))
    return w.obj("Rifle_NATO", coll)


def build_optic_nato(coll, mats):
    """1-4x combat scope on a QD mount; axis 0.058 above the mount point."""
    w = WB(mats, ["Metal_Black", "Lens", "Polymer_Black"])
    h = SIGHT_H
    w.box((0.026, 0.050, 0.014), (0, 0.0, 0.007), "Metal_Black", 0.003)
    for y in (-0.018, 0.018):
        w.box((0.020, 0.012, 0.030), (0, y, 0.026), "Metal_Black", 0.003)
        w.box((0.006, 0.010, 0.020), (0.016, y, 0.012), "Polymer_Black", 0.002)          # QD levers
    # Main body: squared tube with a raised top, objective bell, ocular.
    w.box((0.040, 0.110, 0.040), (0, 0.000, h), "Metal_Black", 0.010, segs=2)
    w.cyl(0.0225, 0.0240, 0.040, (0, 0.074, h), "Metal_Black", segs=20)
    w.cyl(0.0210, 0.0200, 0.034, (0, -0.072, h), "Metal_Black", segs=20)
    w.box((0.016, 0.040, 0.012), (0, 0.000, h + 0.026), "Metal_Black", 0.003)           # mode lever housing
    w.cyl(0.010, 0.010, 0.020, (0.024, 0.010, h), "Metal_Black", axis=(1, 0, 0), segs=12)
    w.cyl(0.0205, 0.0205, 0.002, (0, 0.0945, h), "Lens", segs=20)
    w.cyl(0.0185, 0.0185, 0.002, (0, -0.0895, h), "Lens", segs=20)
    return w.obj("Optic_NATO", coll)


# ============================================================================ RU


def build_rifle_ru(coll, mats):
    w = WB(mats, ["Metal_Black", "Polymer_Black", "Metal_Worn", "Polymer_Plum"])
    z = BORE_Z
    # Stamped receiver (lower part) with trigger guard, large right-side selector.
    w.box((0.032, 0.240, 0.046), (0, 0.010, z - 0.018), "Metal_Black", 0.003)
    w.box((0.034, 0.020, 0.040), (0, 0.120, z - 0.018), "Metal_Black", 0.003)
    w.box((0.006, 0.075, 0.006), (0, 0.020, z - 0.072), "Metal_Black", 0.002)
    w.box((0.006, 0.006, 0.030), (0, 0.055, z - 0.058), "Metal_Black", 0.002)
    w.box((0.004, 0.008, 0.020), (0, 0.025, z - 0.050), "Metal_Worn", 0.0015, rot=rx(15))
    w.box((0.003, 0.120, 0.016), (0.0175, -0.010, z + 0.000), "Metal_Black", 0.002, rot=rx(-3))   # selector lever
    w.box((0.003, 0.030, 0.028), (0.0175, 0.042, z + 0.002), "Metal_Black", 0.002)
    # Railed, hinged dust cover (top of the rail at the optic mount height).
    w.box((0.030, 0.230, 0.034), (0, 0.010, z + 0.016), "Metal_Black", 0.010, segs=2)
    rail(w, -0.090, 0.110, z + 0.034)
    # Bolt-carrier charging handle (right) and rear diopter sight.
    w.box((0.024, 0.016, 0.012), (0.026, 0.075, z + 0.010), "Metal_Worn", 0.004)
    w.box((0.020, 0.024, 0.024), (0, -0.098, z + 0.034), "Metal_Black", 0.003)
    # Plum curved magazine (strong AK curve) and magwell.
    w.box((0.030, 0.072, 0.014), (0, 0.072, z - 0.046), "Metal_Black", 0.003)
    w.magazine((0, 0.074, z - 0.068), lambda: mag_curve(w, (0, 0.074, z - 0.068), 6, 0.032, 0.070, 0.024, 6.0, "Polymer_Plum", ribs=True, start_angle=-2.0))
    # Ergonomic pistol grip (angled).
    w.box((0.030, 0.044, 0.110), (0, -0.012, -0.010), "Polymer_Black", 0.010, rot=rx(-22), segs=2)
    w.box((0.032, 0.048, 0.010), (0, -0.032, -0.062), "Polymer_Black", 0.004, rot=rx(-22))
    # Long railed handguard over the gas tube; top rail continues the receiver rail.
    w.box((0.050, 0.260, 0.064), (0, 0.270, z + 0.010), "Polymer_Black", 0.012, segs=2)
    rail(w, 0.145, 0.395, z + 0.044)
    w.box((0.020, 0.090, 0.007), (0, 0.320, z - 0.026), "Metal_Black", 0.0015)
    for sx in (-1, 1):
        for i in range(5):
            w.box((0.004, 0.030, 0.010), (sx * 0.0245, 0.170 + i * 0.048, z + 0.004), "Metal_Black", 0.0015)
    # Gas block with the triangular front-sight tower, barrel, long slotted muzzle brake.
    w.box((0.030, 0.040, 0.044), (0, 0.420, z + 0.012), "Metal_Black", 0.004)
    w.box((0.014, 0.020, 0.040), (0, 0.426, z + 0.050), "Metal_Black", 0.003, rot=rx(-10))
    w.cyl(0.0095, 0.0095, 0.080, (0, 0.470, z), "Metal_Black")
    w.cyl(0.0125, 0.0125, 0.085, (0, 0.545, z), "Metal_Black", segs=14)
    for i in range(3):
        w.box((0.027, 0.008, 0.008), (0, 0.522 + i * 0.020, z + 0.004), "Polymer_Black", 0.002)
    # Telescoping, side-folding stock: tube, cheek riser, butt, hinge block.
    w.box((0.034, 0.030, 0.040), (0, -0.126, z - 0.006), "Metal_Black", 0.006)
    w.cyl(0.015, 0.015, 0.120, (0, -0.195, z - 0.002), "Metal_Black")
    by = -0.300
    w.box((0.038, 0.130, 0.046), (0, by + 0.075, z + 0.004), "Polymer_Black", 0.012, segs=2)
    w.box((0.030, 0.090, 0.022), (0, by + 0.090, z + 0.032), "Polymer_Black", 0.008)
    w.box((0.034, 0.090, 0.070), (0, by + 0.050, z - 0.046), "Polymer_Black", 0.012, rot=rx(10), segs=2)
    w.box((0.040, 0.020, 0.140), (0, by + 0.006, z - 0.030), "Polymer_Black", 0.008, segs=2)
    return w.obj("Rifle_RU", coll)


def build_optic_ru(coll, mats):
    """Square-window reflex sight: low base, open hood with a tinted window."""
    w = WB(mats, ["Metal_Black", "Lens"])
    h = SIGHT_H
    w.box((0.028, 0.072, 0.016), (0, 0.0, 0.008), "Metal_Black", 0.003)
    w.box((0.030, 0.050, 0.018), (0, -0.008, 0.024), "Metal_Black", 0.004)
    # Hood: four bars around the window, inner half-size 0.020 (outside the viewmodel cut radius).
    s = 0.020
    t = 0.007
    for sx in (-1, 1):
        w.box((t, 0.040, 2 * s + 2 * t), (sx * (s + t / 2), 0.012, h), "Metal_Black", 0.002)
    w.box((2 * s + 2 * t, 0.040, t), (0, 0.012, h + s + t / 2), "Metal_Black", 0.002)
    w.box((2 * s + 2 * t, 0.040, h - s - 0.024), (0, 0.012, 0.024 + (h - s - 0.024) / 2 + 0.008), "Metal_Black", 0.002)
    w.box((2 * s, 0.003, 2 * s), (0, 0.030, h), "Lens", 0.001)
    w.box((0.012, 0.022, 0.014), (s + t + 0.006, -0.008, h - 0.008), "Metal_Black", 0.003)    # brightness knob
    return w.obj("Optic_RU", coll)


# ============================================================================ CN


def build_rifle_cn(coll, mats):
    w = WB(mats, ["Metal_Black", "Polymer_OD", "Metal_Worn", "Polymer_Black"])
    z = BORE_Z
    # Lower receiver with integrated guard and strongly flared magwell.
    w.box((0.032, 0.180, 0.040), (0, 0.000, z - 0.044), "Metal_Black", 0.004)
    w.box((0.038, 0.074, 0.060), (0, 0.072, z - 0.060), "Metal_Black", 0.006, rot=rx(-3))
    w.box((0.046, 0.082, 0.016), (0, 0.070, z - 0.092), "Metal_Black", 0.005, rot=rx(-3))
    w.box((0.008, 0.066, 0.010), (0, 0.028, z - 0.082), "Metal_Black", 0.003)
    w.box((0.004, 0.008, 0.020), (0, 0.030, z - 0.066), "Metal_Worn", 0.0015, rot=rx(15))
    for sx in (-1, 1):
        w.box((0.014, 0.012, 0.007), (sx * 0.018, -0.004, z - 0.040), "Metal_Worn", 0.002)
        w.box((0.006, 0.020, 0.012), (sx * 0.020, 0.045, z - 0.048), "Metal_Black", 0.002)
    # Blocky upper with a sloped front step, left-side charging handle, ejection port.
    w.box((0.036, 0.230, 0.060), (0, 0.010, z + 0.004), "Metal_Black", 0.006)
    w.box((0.036, 0.040, 0.040), (0, 0.130, z + 0.010), "Metal_Black", 0.010, rot=rx(18))
    w.box((0.016, 0.022, 0.012), (-0.026, 0.100, z + 0.018), "Metal_Worn", 0.004)
    w.box((0.004, 0.062, 0.022), (0.019, 0.010, z + 0.000), "Metal_Worn", 0.002)
    rail(w, -0.100, 0.440, z + 0.034)
    # Long handguard, rounded, slot rows, bottom rail section.
    w.box((0.048, 0.290, 0.054), (0, 0.290, z - 0.002), "Metal_Black", 0.016, segs=2)
    for sx in (-1, 1):
        for i in range(5):
            w.box((0.004, 0.034, 0.008), (sx * 0.0235, 0.175 + i * 0.052, z - 0.006), "Polymer_Black", 0.0015)
    w.box((0.020, 0.080, 0.007), (0, 0.325, z - 0.031), "Metal_Black", 0.0015)
    # Barrel and birdcage muzzle device.
    w.cyl(0.0095, 0.0095, 0.070, (0, 0.465, z), "Metal_Black")
    w.cyl(0.0120, 0.0120, 0.058, (0, 0.528, z), "Metal_Worn", segs=14)
    for i in range(6):
        a = math.radians(i * 60 + 30)
        w.box((0.003, 0.030, 0.004), (0.0115 * math.cos(a), 0.532, z + 0.0115 * math.sin(a)), "Metal_Black", 0.001)
    # OD pistol grip and angular telescoping stock with cheek riser.
    w.box((0.031, 0.044, 0.108), (0, -0.004, -0.006), "Polymer_OD", 0.010, rot=rx(-18), segs=2)
    w.box((0.033, 0.050, 0.010), (0, -0.022, -0.058), "Polymer_OD", 0.004, rot=rx(-18))
    w.cyl(0.016, 0.016, 0.170, (0, -0.185, z), "Metal_Black")
    by = -0.292
    w.box((0.042, 0.150, 0.054), (0, by + 0.090, z - 0.002), "Polymer_OD", 0.010, segs=2)
    w.box((0.034, 0.110, 0.026), (0, by + 0.090, z + 0.036), "Polymer_OD", 0.008)
    w.box((0.038, 0.110, 0.074), (0, by + 0.060, z - 0.056), "Polymer_OD", 0.010, rot=rx(16), segs=2)
    w.box((0.044, 0.020, 0.150), (0, by + 0.008, z - 0.036), "Polymer_Black", 0.008, segs=2)
    # 5.8 mm magazine: gentle curve, ribbed.
    w.magazine((0, 0.074, z - 0.092), lambda: mag_curve(w, (0, 0.074, z - 0.092), 5, 0.034, 0.066, 0.026, 3.0, "Polymer_Black", ribs=True))
    return w.obj("Rifle_CN", coll)


def build_optic_cn(coll, mats):
    """3x prism sight with integral mount and a small top rail."""
    w = WB(mats, ["Metal_Black", "Lens"])
    h = SIGHT_H
    w.box((0.028, 0.060, 0.014), (0, 0.0, 0.007), "Metal_Black", 0.003)
    w.box((0.024, 0.044, 0.024), (0, 0.0, 0.026), "Metal_Black", 0.004)
    w.box((0.044, 0.090, 0.044), (0, 0.004, h), "Metal_Black", 0.008, segs=2)
    w.cyl(0.0215, 0.0215, 0.030, (0, 0.060, h), "Metal_Black", segs=18)
    w.cyl(0.0200, 0.0200, 0.024, (0, -0.054, h), "Metal_Black", segs=18)
    w.box((0.018, 0.060, 0.006), (0, 0.004, h + 0.026), "Metal_Black", 0.0015)
    w.cyl(0.0195, 0.0195, 0.002, (0, 0.0755, h), "Lens", segs=18)
    w.cyl(0.0185, 0.0185, 0.002, (0, -0.0665, h), "Lens", segs=18)
    return w.obj("Optic_CN", coll)


# ============================================================================ mounts

MOUNTS = {
    "rifle_nato": {"ATT_Optic": (0, 0.040, OPTIC_Z), "ATT_Underbarrel": (0, 0.330, BORE_Z - 0.033),
                   "ATT_RailRight": (0.030, 0.360, BORE_Z), "ATT_Muzzle": (0, 0.560, BORE_Z)},
    "rifle_ru": {"ATT_Optic": (0, 0.010, OPTIC_Z), "ATT_Underbarrel": (0, 0.320, BORE_Z - 0.030),
                 "ATT_RailRight": (0.030, 0.330, BORE_Z + 0.008), "ATT_Muzzle": (0, 0.588, BORE_Z)},
    "rifle_cn": {"ATT_Optic": (0, 0.040, OPTIC_Z), "ATT_Underbarrel": (0, 0.325, BORE_Z - 0.035),
                 "ATT_RailRight": (0.030, 0.360, BORE_Z), "ATT_Muzzle": (0, 0.557, BORE_Z)},
}


def mount_empties(coll, weapon, key):
    out = []
    for name, pos in MOUNTS[key].items():
        e = bpy.data.objects.new(name, None)
        e.empty_display_size = 0.02
        e.location = pos
        coll.objects.link(e)
        e.parent = weapon
        out.append(e)
    axis, palm, thumb, grip = W.support_frame()
    e = bpy.data.objects.new("GRIP_Support", None)
    e.empty_display_size = 0.03
    m = Matrix((axis.cross(-palm).normalized(), axis, -palm)).transposed().to_4x4()
    m.translation = grip
    e.matrix_world = m
    coll.objects.link(e)
    e.parent = weapon
    out.append(e)
    return out
