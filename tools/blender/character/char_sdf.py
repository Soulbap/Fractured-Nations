"""Signed-distance modelling for organic character parts (body, head, garments, soft gear).

Shapes are numpy functions of a point grid (P = (X, Y, Z) arrays, metres, character space)
returning signed distance (negative inside). They are combined with smooth unions, turned
into an OpenVDB density grid (bundled `openvdb` module) and meshed with Blender's
Volume to Mesh modifier, then decimated to a game budget. Fully deterministic.
"""
import os
import tempfile

import bpy
import numpy as np
import openvdb as vdb

F = np.float32


class Grid:
    def __init__(self, lo, hi, voxel):
        self.voxel = voxel
        self.lo = np.array(lo, dtype=np.float64)
        n = np.ceil((np.array(hi) - self.lo) / voxel).astype(int) + 1
        self.shape = tuple(n)
        xs = [F(self.lo[i] + np.arange(n[i]) * voxel) for i in range(3)]
        self.X, self.Y, self.Z = np.meshgrid(xs[0], xs[1], xs[2], indexing="ij")

    @property
    def P(self):
        return self.X, self.Y, self.Z


# ---------------------------------------------------------------------------- primitives


def length3(x, y, z):
    return np.sqrt(x * x + y * y + z * z)


def sphere(P, c, r):
    X, Y, Z = P
    return length3(X - c[0], Y - c[1], Z - c[2]) - r


def ellipsoid(P, c, r, rot=None):
    X, Y, Z = _local(P, c, rot)
    k0 = length3(X / r[0], Y / r[1], Z / r[2])
    k1 = length3(X / (r[0] * r[0]), Y / (r[1] * r[1]), Z / (r[2] * r[2]))
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)


def round_cone(P, a, b, r1, r2):
    """Capsule from a (radius r1) to b (radius r2), exact (Inigo Quilez)."""
    X, Y, Z = P
    a = np.array(a, dtype=F)
    b = np.array(b, dtype=F)
    ba = b - a
    l2 = float(ba.dot(ba))
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    px, py, pz = X - a[0], Y - a[1], Z - a[2]
    y = px * ba[0] + py * ba[1] + pz * ba[2]
    z = y - l2
    qx, qy, qz = px * l2 - ba[0] * y, py * l2 - ba[1] * y, pz * l2 - ba[2] * y
    x2 = qx * qx + qy * qy + qz * qz
    y2 = y * y * l2
    z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    out = np.where(np.sign(z) * a2 * z2 > k, np.sqrt(x2 + z2) * il2 - r2,
                   np.where(np.sign(y) * a2 * y2 < k, np.sqrt(x2 + y2) * il2 - r1,
                            (np.sqrt(x2 * a2 * il2) + y * rr) * il2 - r1))
    return out.astype(F)


def capsule(P, a, b, r):
    return round_cone(P, a, b, r, r)


def box(P, c, half, radius=0.0, rot=None):
    """Rounded box: half extents include the rounding radius."""
    X, Y, Z = _local(P, c, rot)
    qx = np.abs(X) - (half[0] - radius)
    qy = np.abs(Y) - (half[1] - radius)
    qz = np.abs(Z) - (half[2] - radius)
    outside = length3(np.maximum(qx, 0), np.maximum(qy, 0), np.maximum(qz, 0))
    inside = np.minimum(np.maximum(qx, np.maximum(qy, qz)), 0)
    return outside + inside - radius


def cylinder(P, c, axis, r, half_h, rot=None):
    X, Y, Z = _local(P, c, rot)
    if axis == "x":
        rad, ax = np.sqrt(Y * Y + Z * Z), X
    elif axis == "y":
        rad, ax = np.sqrt(X * X + Z * Z), Y
    else:
        rad, ax = np.sqrt(X * X + Y * Y), Z
    dx = rad - r
    dy = np.abs(ax) - half_h
    return np.minimum(np.maximum(dx, dy), 0) + length3(np.maximum(dx, 0), np.maximum(dy, 0), 0 * dx)


def plane(P, point, normal):
    """Half-space: negative on the side the normal points away from (inside below the plane)."""
    X, Y, Z = P
    n = np.array(normal, dtype=F)
    n = n / np.linalg.norm(n)
    return (X - point[0]) * n[0] + (Y - point[1]) * n[1] + (Z - point[2]) * n[2]


def _local(P, c, rot):
    X, Y, Z = P
    x, y, z = X - c[0], Y - c[1], Z - c[2]
    if rot is None:
        return x, y, z
    m = np.array(rot, dtype=F)  # rows = local axes in world space
    return (x * m[0][0] + y * m[0][1] + z * m[0][2],
            x * m[1][0] + y * m[1][1] + z * m[1][2],
            x * m[2][0] + y * m[2][1] + z * m[2][2])


def rot_from_axes(right, fwd, up):
    """Rows = local x, y, z axes in world space (for box/ellipsoid rot=)."""
    return [list(right), list(fwd), list(up)]


# ---------------------------------------------------------------------------- operators


def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return (b * (1 - h) + a * h - k * h * (1 - h)).astype(F)


def smax(a, b, k):
    return -smin(-a, -b, k)


def union(*ds, k=0.0):
    out = ds[0]
    for d in ds[1:]:
        out = smin(out, d, k)
    return out


def subtract(a, b, k=0.0):
    return smax(a, -b, k)


def intersect(a, b, k=0.0):
    return smax(a, b, k)


def smooth01(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def noise3(P, scale, seed, octaves=3):
    """Cheap smooth 3D value noise (sum of random sinusoids), ~[-1, 1]."""
    X, Y, Z = P
    rng = np.random.default_rng(seed)
    out = np.zeros_like(X)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        f = (2 ** o) / scale
        for _ in range(4):
            d = rng.normal(size=3)
            d /= np.linalg.norm(d)
            ph = rng.uniform(0, 6.283)
            out += amp * np.sin((X * d[0] + Y * d[1] + Z * d[2]) * f * 6.283 + ph)
            tot += amp
        amp *= 0.5
    return (out / tot * 2.0).astype(F)


# ---------------------------------------------------------------------------- meshing


def to_mesh(grid, sdf, name, coll, adaptivity=0.0):
    """Meshes the zero level of `sdf` (array on grid) into a new mesh object."""
    dens = np.clip(-sdf, -0.05, 0.05).astype(np.float32)
    # Border voxels outside so the surface closes inside the grid.
    dens[0, :, :] = dens[-1, :, :] = -0.05
    dens[:, 0, :] = dens[:, -1, :] = -0.05
    dens[:, :, 0] = dens[:, :, -1] = -0.05
    g = vdb.FloatGrid(-0.05)
    g.copyFromArray(dens, ijk=(0, 0, 0), tolerance=0.0)
    v = grid.voxel
    lo = grid.lo
    g.transform = vdb.createLinearTransform(matrix=[[v, 0, 0, 0], [0, v, 0, 0], [0, 0, v, 0], [lo[0], lo[1], lo[2], 1]])
    g.name = "density"
    g.gridClass = vdb.GridClass.FOG_VOLUME
    path = os.path.join(tempfile.gettempdir(), f"fn_sdf_{name}_{os.getpid()}.vdb")
    vdb.write(path, grids=[g])
    vol = bpy.data.volumes.new(name + "_vol")
    vol.filepath = path
    vol.grids.load()
    vobj = bpy.data.objects.new(name + "_vol", vol)
    coll.objects.link(vobj)
    me = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, me)
    coll.objects.link(obj)
    mod = obj.modifiers.new("V2M", "VOLUME_TO_MESH")
    mod.object = vobj
    mod.grid_name = "density"
    mod.resolution_mode = "GRID"
    mod.threshold = 0.0
    mod.adaptivity = adaptivity
    mod.use_smooth_shade = True
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    new_me = bpy.data.meshes.new_from_object(ev)
    obj.modifiers.clear()
    obj.data = new_me
    bpy.data.meshes.remove(me)
    new_me.name = name
    bpy.data.objects.remove(vobj, do_unlink=True)
    bpy.data.volumes.remove(vol)
    try:
        os.remove(path)
    except OSError:
        pass
    return obj


def decimate(obj, target_tris):
    import char_lib as L
    tris = L.tri_count(obj)
    if tris <= target_tris:
        return obj
    L.activate(obj)
    m = obj.modifiers.new("Dec", "DECIMATE")
    m.ratio = target_tris / tris
    m.use_collapse_triangulate = True
    bpy.ops.object.modifier_move_to_index(modifier=m.name, index=0)
    bpy.ops.object.modifier_apply(modifier=m.name)
    return obj


def mesh_sdf(lo, hi, voxel, fn, name, coll, target_tris=None):
    """Convenience: build grid, evaluate fn(P) -> sdf, mesh, decimate."""
    g = Grid(lo, hi, voxel)
    d = fn(g.P)
    obj = to_mesh(g, d, name, coll)
    if target_tris:
        decimate(obj, target_tris)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj
