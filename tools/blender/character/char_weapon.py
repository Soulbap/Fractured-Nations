"""Original 5.56 mm carbine ("FN-C1") and accessories (CHARACTER-01).

Proportions from photographs of the Norwegian HK416N family (14.5" barrel, quad-rail
handguard, collapsible stock, curved polymer magazine, Aimpoint-style red dot), built as
an original asset.

Weapon space (Blender): origin = centre of the pistol grip where the firing hand closes
(this point goes to the skeleton's ATT_Weapon), +Y = muzzle direction, +Z = up, bore
axis at z = BORE_Z. Accessory mount points are empties exported as glTF nodes:
  ATT_Optic       top rail, rear of the handguard joint
  ATT_Underbarrel bottom rail, front third
  ATT_RailRight   right rail, front
  ATT_Muzzle      muzzle face
  GRIP_Support    support-hand pose (Y = hand axis, Z = back of hand), for animation/IK
A detachable magazine is its own child object (split_magazine), exported as <weapon>_Mag_LOD*: the game hangs it on the
ATT_Magazine bone, which the reload clip moves with the support hand.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import char_lib as L

BORE_Z = 0.074
STOCK_PULL = 0.282          # grip centre -> butt plate (collapsed two positions for armour)

MOUNTS = {
    "ATT_Optic": Vector((0, 0.020, BORE_Z + 0.040)),
    "ATT_Underbarrel": Vector((0, 0.320, BORE_Z - 0.026)),
    "ATT_RailRight": Vector((0.026, 0.330, BORE_Z)),
    "ATT_Muzzle": Vector((0, 0.560, BORE_Z)),
}


def support_frame():
    """Support (left) hand on the handguard: palm under-left, fingers wrapping over the
    right side, thumb along the left. Returns (axis, palm, thumb, grip point) in weapon space."""
    axis = Vector((0.50, 0.84, 0.20)).normalized()
    palm = Vector((0.40, -0.05, 0.92))
    palm = (palm - axis * palm.dot(axis)).normalized()
    thumb = palm.cross(axis).normalized()         # left-hand convention (char_skeleton)
    grip = Vector((0.0, 0.165, BORE_Z))
    return axis, palm, thumb, grip


def _rb(bm, size, c, r=0.003, rot=None, mat=0, segs=1):
    vs = L.rounded_box(bm, size, Vector(c), r, rot=rot, segs=segs)
    for f in {f for v in bm.verts for f in v.link_faces}:
        pass
    return vs


def _set_mat(bm, verts, mat):
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = mat


def build_carbine(coll, mats):
    M_RX, M_POLY, M_METAL, M_WORN = 0, 1, 2, 3
    bm = bmesh.new()

    def box(size, c, r=0.003, mat=M_RX, rot=None, segs=1):
        _set_mat(bm, L.rounded_box(bm, size, Vector(c), r, rot=rot, segs=segs), mat)

    def cyl(r1, r2, depth, c, axis=(0, 1, 0), mat=M_METAL, segs=12):
        _set_mat(bm, L.bm_cyl(bm, r1, r2, depth, Vector(c), axis=axis, segs=segs), mat)

    rx = lambda deg: Matrix.Rotation(math.radians(deg), 3, "X")
    z = BORE_Z
    # Lower receiver + magwell + trigger guard.
    box((0.031, 0.190, 0.040), (0, -0.002, z - 0.044), 0.004)
    box((0.034, 0.068, 0.062), (0, 0.070, z - 0.060), 0.004, rot=rx(-4))
    box((0.006, 0.060, 0.006), (0, 0.030, z - 0.083), 0.002)
    box((0.006, 0.006, 0.022), (0, 0.058, z - 0.073), 0.002)
    box((0.004, 0.008, 0.020), (0, 0.032, z - 0.066), 0.0015, mat=M_METAL, rot=rx(15))      # trigger
    box((0.012, 0.010, 0.006), (0.017, -0.005, z - 0.040), 0.002, mat=M_METAL)              # selector
    box((0.012, 0.010, 0.006), (-0.017, -0.005, z - 0.040), 0.002, mat=M_METAL)
    # Upper receiver with forward assist, ejection port, charging handle.
    box((0.033, 0.205, 0.052), (0, 0.000, z + 0.004), 0.004)
    box((0.004, 0.070, 0.022), (0.0175, 0.020, z + 0.002), 0.002, mat=M_METAL)              # port / dust cover
    cyl(0.009, 0.008, 0.035, (0.020, -0.050, z + 0.012), axis=(0, 1, 0.2), mat=M_RX, segs=10)
    box((0.040, 0.014, 0.010), (0, -0.108, z + 0.024), 0.003)
    box((0.006, 0.020, 0.012), (0.022, 0.000, z + 0.026), 0.002, mat=M_METAL)              # brass deflector
    # Top Picatinny rail over receiver and handguard, with cross slots.
    box((0.022, 0.600, 0.008), (0, 0.192, z + 0.034), 0.0015)
    for i in range(52):
        box((0.023, 0.0045, 0.003), (0, -0.098 + i * 0.0115, z + 0.0395), 0.0008)
    # Quad-rail handguard.
    box((0.050, 0.290, 0.050), (0, 0.250, z), 0.008)
    for ang in (90, 180, 270):
        rot = Matrix.Rotation(math.radians(ang), 3, "Y")
        off = rot @ Vector((0, 0, 0.029))
        _set_mat(bm, L.rounded_box(bm, (0.020, 0.270, 0.007), Vector((0, 0.255, z)) + off, 0.0015, rot=rot, segs=1), M_RX)
        for i in range(0, 22):
            _set_mat(bm, L.rounded_box(bm, (0.021, 0.0045, 0.003), Vector((0, 0.135 + i * 0.0115, z)) + rot @ Vector((0, 0, 0.0335)),
                                       0.0008, rot=rot, segs=1), M_RX)
    # Barrel, gas block, front sight (folded) and flash hider.
    cyl(0.0095, 0.0095, 0.090, (0, 0.440, z), mat=M_METAL)
    cyl(0.0125, 0.0125, 0.020, (0, 0.405, z), mat=M_METAL)
    cyl(0.0120, 0.0115, 0.058, (0, 0.512, z), mat=M_METAL, segs=14)
    for i in range(6):
        a = math.radians(i * 60)
        box((0.003, 0.034, 0.004), (0.0115 * math.cos(a), 0.518, z + 0.0115 * math.sin(a)), 0.001, mat=M_RX)
    box((0.020, 0.030, 0.012), (0, 0.375, z + 0.044), 0.003)
    box((0.020, 0.030, 0.012), (0, -0.080, z + 0.044), 0.003)
    # Pistol grip (stippled polymer), origin at its centre.
    box((0.029, 0.040, 0.105), (0, -0.002, -0.004), 0.009, mat=M_POLY, rot=rx(-20), segs=2)
    box((0.031, 0.046, 0.010), (0, -0.020, -0.056), 0.004, mat=M_POLY, rot=rx(-20))
    # Buffer tube and stock.
    cyl(0.0155, 0.0155, 0.175, (0, -0.190, z), mat=M_RX)
    by = -STOCK_PULL
    box((0.038, 0.130, 0.050), (0, by + 0.085, z - 0.002), 0.010, mat=M_POLY, segs=2)        # stock body over the tube
    box((0.036, 0.100, 0.060), (0, by + 0.060, z - 0.050), 0.010, mat=M_POLY, rot=rx(12), segs=2)
    box((0.032, 0.040, 0.024), (0, by + 0.110, z + 0.026), 0.008, mat=M_POLY)                # cheek weld
    box((0.040, 0.018, 0.128), (0, by + 0.008, z - 0.030), 0.008, mat=M_POLY, segs=2)        # butt plate
    box((0.006, 0.040, 0.008), (0, by + 0.070, z - 0.088), 0.002, mat=M_METAL)               # sling loop
    # Curved polymer magazine: four segments along an arc.
    mag_top = Vector((0, 0.073, z - 0.075))
    n0 = len(bm.verts)
    for i in range(5):
        ang = -4 - i * 4.0
        c = mag_top + Vector((0, 0.004 + i * 0.0055, -0.016 - i * 0.032))
        box((0.024, 0.064 - i * 0.0015, 0.036), c, 0.004, mat=M_POLY, rot=rx(ang))
    box((0.028, 0.064, 0.010), mag_top + Vector((0, 0.030, -0.175)), 0.004, mat=M_POLY, rot=rx(-22))
    mag_verts = range(n0, len(bm.verts))
    me_obj = L.new_object("Carbine", bm, coll, [mats["Metal_Black"], mats["Polymer_Black"], mats["Metal_Worn"], mats["Metal_Worn"]])
    me_obj.data.materials[0] = mats["Metal_Black"]
    for p in me_obj.data.polygons:
        p.use_smooth = True
    L.shade_smooth(me_obj, 35)
    split_magazine(me_obj, mag_verts, mag_top)
    return me_obj


MAG_TOP = Vector((0, 0.073, BORE_Z - 0.075))     # carbine magwell (magazine origin)


def split_magazine(weapon, verts, top=MAG_TOP):
    """Moves the vertices `verts` (indices, whole loose parts: the magazine as it was built) of `weapon` into a child
    object (origin at `top`, the magwell) marked fn_magazine, which export_rigid writes as <weapon>_Mag_LOD*."""
    keep = set(verts)
    if not keep:
        return None
    top = Vector(top)
    bm = bmesh.new()
    bm.from_mesh(weapon.data)
    mb = bm.copy()
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index in keep], context="VERTS")
    bm.to_mesh(weapon.data)
    bm.free()
    mb.verts.ensure_lookup_table()
    bmesh.ops.delete(mb, geom=[v for v in mb.verts if v.index not in keep], context="VERTS")
    for v in mb.verts:
        v.co -= top
    me = bpy.data.meshes.new(weapon.name + "_Mag")
    mb.to_mesh(me)
    mb.free()
    for m in weapon.data.materials:
        me.materials.append(m)
    mag = bpy.data.objects.new(weapon.name + "_Mag", me)
    for c in weapon.users_collection:
        c.objects.link(mag)
    mag.parent = weapon
    mag.matrix_parent_inverse = Matrix.Identity(4)
    mag.location = top
    mag["fn_magazine"] = True
    for p in me.polygons:
        p.use_smooth = True
    return mag


def mount_empties(coll, weapon):
    out = []
    for name, pos in MOUNTS.items():
        e = bpy.data.objects.new(name, None)
        e.empty_display_size = 0.02
        e.location = pos
        coll.objects.link(e)
        e.parent = weapon
        out.append(e)
    axis, palm, thumb, grip = support_frame()
    e = bpy.data.objects.new("GRIP_Support", None)
    e.empty_display_size = 0.03
    m = Matrix((axis.cross(-palm).normalized(), axis, -palm)).transposed().to_4x4()
    m.translation = grip
    e.matrix_world = m
    coll.objects.link(e)
    e.parent = weapon
    out.append(e)
    return out


def build_red_dot(coll, mats):
    """Aimpoint-style tube sight on a QD mount. Origin = rail mount point (ATT_Optic)."""
    bm = bmesh.new()
    _set_mat(bm, L.rounded_box(bm, (0.026, 0.040, 0.016), Vector((0, 0, 0.008)), 0.003, segs=1), 0)
    _set_mat(bm, L.rounded_box(bm, (0.018, 0.030, 0.024), Vector((0, 0, 0.026)), 0.003, segs=1), 0)
    _set_mat(bm, L.bm_cyl(bm, 0.0205, 0.0205, 0.110, Vector((0, 0.0, 0.058)), axis=(0, 1, 0), segs=20), 0)
    _set_mat(bm, L.bm_cyl(bm, 0.0225, 0.0225, 0.014, Vector((0, 0.049, 0.058)), axis=(0, 1, 0), segs=20), 0)
    _set_mat(bm, L.bm_cyl(bm, 0.0225, 0.0225, 0.014, Vector((0, -0.049, 0.058)), axis=(0, 1, 0), segs=20), 0)
    _set_mat(bm, L.rounded_box(bm, (0.014, 0.018, 0.012), Vector((0, 0.0, 0.082)), 0.004, segs=1), 0)        # elevation turret
    _set_mat(bm, L.rounded_box(bm, (0.012, 0.018, 0.014), Vector((0.024, 0.0, 0.058)), 0.004, segs=1), 0)    # windage / battery
    _set_mat(bm, L.bm_cyl(bm, 0.0185, 0.0185, 0.002, Vector((0, 0.0565, 0.058)), axis=(0, 1, 0), segs=20), 1)
    _set_mat(bm, L.bm_cyl(bm, 0.0185, 0.0185, 0.002, Vector((0, -0.0565, 0.058)), axis=(0, 1, 0), segs=20), 1)
    o = L.new_object("Optic_RedDot", bm, coll, [mats["Metal_Black"], mats["Lens"]])
    L.shade_smooth(o, 35)
    return o


def build_foregrip(coll, mats):
    """Vertical fore grip. Origin = bottom rail mount (ATT_Underbarrel)."""
    bm = bmesh.new()
    _set_mat(bm, L.rounded_box(bm, (0.024, 0.040, 0.014), Vector((0, 0, -0.007)), 0.003, segs=1), 0)
    _set_mat(bm, L.bm_cyl(bm, 0.0150, 0.0140, 0.085, Vector((0, -0.004, -0.055)), axis=(0, -0.15, 1), segs=14), 0)
    _set_mat(bm, L.bm_cyl(bm, 0.0160, 0.0160, 0.008, Vector((0, -0.010, -0.097)), axis=(0, -0.15, 1), segs=14), 0)
    o = L.new_object("Foregrip", bm, coll, [mats["Polymer_Black"]])
    L.shade_smooth(o, 35)
    return o


def build_laser(coll, mats):
    """PEQ-style aiming laser box. Origin = right rail mount (ATT_RailRight)."""
    bm = bmesh.new()
    _set_mat(bm, L.rounded_box(bm, (0.012, 0.030, 0.016), Vector((0.006, 0, 0)), 0.003, segs=1), 0)
    _set_mat(bm, L.rounded_box(bm, (0.032, 0.085, 0.036), Vector((0.028, 0, 0.004)), 0.005, segs=2), 0)
    _set_mat(bm, L.bm_cyl(bm, 0.008, 0.008, 0.006, Vector((0.022, 0.043, 0.010)), axis=(0, 1, 0), segs=10), 1)
    _set_mat(bm, L.bm_cyl(bm, 0.006, 0.006, 0.006, Vector((0.036, 0.043, -0.002)), axis=(0, 1, 0), segs=10), 1)
    o = L.new_object("Laser", bm, coll, [mats["Polymer_OD"], mats["Lens"]])
    L.shade_smooth(o, 35)
    return o
