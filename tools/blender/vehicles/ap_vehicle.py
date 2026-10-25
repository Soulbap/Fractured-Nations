"""VEHICLE-ASSETS-01: articulated vehicle assets on top of the ASSET-PRODUCTION-01 library.

A static library asset (ap_lib.Asset) is one mesh per LOD. A vehicle needs parts that move:
wheels that spin and steer, turrets, guns, doors, hatches, rotors. VehicleAsset is a set of
Parts; every Part *is* an ap_lib.Asset (same primitives, authored LODs, shared library
materials, Kit_Palette folding, world-scale box UVs, baked dirt vertex colours) with a pivot
and a parent part. Geometry is authored in vehicle space (metres, Z up, front +Y, origin on
the ground at the footprint centre) and moved under its pivot at build time, so UVs and
dirt are continuous across parts and a part rotates about its real hinge / axle / ring.

GLB layout (one per vehicle, Blender +Y front = Godot -Z):

    Body_LOD0 / _LOD1 / _LOD2               hull meshes at the vehicle origin
    Turret            (Node3D at the ring centre, yaw about +Z / Godot +Y)
        Turret_LOD0..2
        Gun           (Node3D at the trunnions, pitch about +X)
            Gun_LOD0..2
    Wheel_L1          (Node3D at the wheel centre; spin about +X, steer about +Z)
        Wheel_L1_LOD0..2   (instances share one mesh per LOD)
    COL_<n>-convcolonly    simplified collision boxes (not the render mesh)
    WHEEL_* / SEAT_* / DOOR_* / ... markers (ASSET_STANDARD section 2)

The sidecar <id>.json lists every part with its parent, pivot (Godot space), rotation
axis hint and triangle counts per LOD, plus the usual library numbers.
"""
import json
import math
import os
from contextlib import contextmanager

import bmesh
import bpy
from mathutils import Matrix, Vector

import ap_lib as A
import ap_materials as AM
import char_lib as L

ALL, L01, L0, L12, L2 = A.ALL, A.L01, A.L0, A.L12, A.L2

# Parts whose far LOD adds draw calls but no silhouette: the shell / track band / body cover them
# from 180 m on (doors and hatches sit flush, road wheels are inside the band).
NO_FAR_LOD = ("Door", "Hatch", "SteeringWheel", "RoadWheel", "Sprocket", "Idler", "Roller", "Ramp", "SpareWheel", "RWS_Gun")

# Vehicles are seen at FPS range and from the RTS camera: more detail stays on LOD0 than for
# props, and LOD1 still carries wheels / running gear (sidecar per asset may override).
VEHICLE_LOD_RANGES = [(0, 45), (45, 180), (180, 2000)]


class Part:
    """One rigid piece of a vehicle: an ap_lib.Asset plus its pivot and parent."""

    def __init__(self, veh, name, parent, pivot, axis, note):
        self.veh = veh
        self.name = name
        self.parent = parent
        self.pivot = Vector(pivot)
        self.axis = axis          # rotation axis hint for the sidecar ("x" spin / pitch, "z" yaw, ...)
        self.note = note
        self.a = A.Asset(name, "vehicle", name)
        self.a.lod_ranges = [list(r) for r in veh.lod_ranges]
        self.a.ao_height = veh.ao_height
        self.a.ao_strength = veh.ao_strength
        self.source = None        # instance of another part's meshes (wheels)
        self.inst_rot = 0.0       # instance yaw (deg) about the pivot, e.g. 180 for left wheels
        self.objs = [None, None, None]
        self.empty = None
        self.local = False        # geometry authored around (0, 0, 0) = the pivot

    def __getattr__(self, k):
        # Forward the primitive API (box, cyl, loft, prism, tube, ...) to the Asset.
        return getattr(self.__dict__["a"], k)


class VehicleAsset:
    def __init__(self, vid, display_name, category, description):
        self.id = vid
        self.display_name = display_name
        self.category = category
        self.description = description
        self.lod_ranges = [list(r) for r in VEHICLE_LOD_RANGES]
        self.ao_height = 1.2
        self.ao_strength = 0.30
        self.parts = {}
        self.order = []
        self.cols = []
        self.markers = []
        self.meta = {}
        self.qa = {}
        self.cuts = {}            # part name -> [(builder, interior swatch)]
        self.merges = []          # (shell part, part it is joined into)

    # ------------------------------------------------------------------ parts

    def part(self, name, parent=None, pivot=(0, 0, 0), axis="", note="", local=False):
        p = Part(self, name, parent, pivot, axis, note)
        p.local = local
        self.parts[name] = p
        self.order.append(name)
        return p

    def instance(self, name, source, parent=None, pivot=(0, 0, 0), yaw=0.0, axis="x", note=""):
        """A part that reuses another (local) part's meshes, e.g. every wheel of an axle set."""
        p = Part(self, name, parent, pivot, axis, note)
        p.source = source
        p.inst_rot = yaw
        p.local = True
        self.parts[name] = p
        self.order.append(name)
        return p

    def shell(self, into="Body"):
        """A part for the closed outer shell of `into` that gets boolean cuts (cabin cavity,
        window and door openings) on LOD0 and is then joined into `into`. Detail geometry
        stays on `into` so the cuts never touch frames, glass or fittings."""
        host = self.parts[into]
        p = self.part(into + "_Shell", parent=host.parent, pivot=tuple(host.pivot), axis="", note="shell")
        self.merges.append((p.name, into))
        return p

    def cut(self, part, builder, interior="Paint_White"):
        """Boolean-subtract a closed solid from `part`'s LOD0. builder(tmp) adds the solid with
        the usual shape helpers (tmp behaves like a Part, LOD0 only). The new inner faces get the
        palette swatch `interior` (cabin walls)."""
        self.cuts.setdefault(part.name, []).append((builder, interior))

    def col_box(self, size, center, yaw=0.0):
        self.cols.append((tuple(size), tuple(center), float(yaw)))

    def col_between(self, lo, hi):
        lo, hi = Vector(lo), Vector(hi)
        self.col_box(tuple(hi - lo), tuple((lo + hi) / 2))

    def marker(self, name, pos, yaw=0.0, note=""):
        self.markers.append({"name": name, "pos": [round(c, 4) for c in pos], "yaw": yaw, "note": note})

    # ------------------------------------------------------------------ build

    def build(self, coll, tex_dir):
        for name in self.order:
            p = self.parts[name]
            if p.source is None:
                p.objs = p.a.build(coll, tex_dir)
                if name in self.cuts and p.objs[0] is not None:
                    _apply_cuts(p.objs[0], self.cuts[name], coll, tex_dir)
        for name in self.order:
            p = self.parts[name]
            if p.source is None and name.startswith(NO_FAR_LOD) and p.objs[2] is not None:
                bpy.data.objects.remove(p.objs[2], do_unlink=True)
                p.objs[2] = None
        for src, dst in self.merges:
            sp, dp = self.parts[src], self.parts[dst]
            for i in ALL:
                if sp.objs[i] is None:
                    continue
                if dp.objs[i] is None:
                    dp.objs[i] = sp.objs[i]
                    dp.objs[i].name = "%s_LOD%d" % (dst, i)
                    continue
                bpy.ops.object.select_all(action="DESELECT")
                sp.objs[i].select_set(True)
                dp.objs[i].select_set(True)
                bpy.context.view_layer.objects.active = dp.objs[i]
                bpy.ops.object.join()
            del self.parts[src]
            self.order.remove(src)
        for name in self.order:
            p = self.parts[name]
            if p.source is None:
                for o in p.objs:
                    if o is None:
                        continue
                    _weighted_normals(o)
                    if not p.local:
                        o.data.transform(Matrix.Translation(-p.pivot))
        for name in self.order:
            p = self.parts[name]
            e = bpy.data.objects.new(name, None)
            e.empty_display_size = 0.3
            coll.objects.link(e)
            p.empty = e
        for name in self.order:
            p = self.parts[name]
            par = self.parts[p.parent] if p.parent else None
            p.empty.location = p.pivot - (par.pivot if par else Vector())
            p.empty.rotation_euler = (0, 0, math.radians(p.inst_rot))
            if par:
                p.empty.parent = par.empty
            if p.source is not None:
                src = self.parts[p.source]
                p.objs = []
                for i, so in enumerate(src.objs):
                    if so is None:
                        p.objs.append(None)
                        continue
                    o = bpy.data.objects.new("%s_LOD%d" % (name, i), so.data)
                    coll.objects.link(o)
                    p.objs.append(o)
        for name in self.order:
            p = self.parts[name]
            for o in p.objs:
                if o is not None:
                    o.parent = p.empty
                    o.location = (0, 0, 0)
        # The source of instanced wheels is a template, not a part of the vehicle.
        for name in list(self.order):
            p = self.parts[name]
            if p.local and p.source is None and any(q.source == name for q in self.parts.values()) and p.note == "template":
                for o in p.objs:
                    if o is not None:
                        o.hide_render = True
                        o.hide_set(True)
        bpy.context.view_layer.update()
        self.objs = [o for n in self.order for o in self.parts[n].objs if o is not None and not self._is_template(n)]

    def _is_template(self, name):
        return self.parts[name].note == "template"

    def lod_objects(self, lod):
        return [p.objs[lod] for n, p in self.parts.items() if not self._is_template(n) and p.objs[lod] is not None]

    # ------------------------------------------------------------------ stats

    def tris(self, lod):
        return sum(L.tri_count(o) for o in self.lod_objects(lod))

    def materials(self, lod=None):
        lods = [lod] if lod is not None else ALL
        names = set()
        for i in lods:
            for o in self.lod_objects(i):
                names |= {m.name for m in o.data.materials}
        return sorted(names)

    def bounds(self, lod=0):
        lo = Vector((1e9, 1e9, 1e9))
        hi = Vector((-1e9, -1e9, -1e9))
        for o in self.lod_objects(lod):
            for v in o.data.vertices:
                w = o.matrix_world @ v.co
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
        return lo, hi

    # ------------------------------------------------------------------ export

    def export(self, out_dir, coll):
        os.makedirs(out_dir, exist_ok=True)
        extra = []
        for k, (size, c, yaw) in enumerate(self.cols):
            bm = bmesh.new()
            L.bm_box(bm, size, Vector(c), rot=A.rot_z(yaw) if yaw else None)
            extra.append(L.new_object("COL_%d-convcolonly" % k, bm, coll))
        for m in self.markers:
            e = bpy.data.objects.new(m["name"], None)
            e.empty_display_size = 0.2
            e.location = m["pos"]
            e.rotation_euler = (0, 0, math.radians(m["yaw"]))
            coll.objects.link(e)
            extra.append(e)
        path = os.path.join(out_dir, self.id + ".glb")
        bpy.ops.object.select_all(action="DESELECT")
        sel = []
        for n in self.order:
            if self._is_template(n):
                continue
            p = self.parts[n]
            sel.append(p.empty)
            sel += [o for o in p.objs if o is not None]
        sel += extra
        for o in sel:
            o.hide_set(False)
            o.hide_render = False
            o.select_set(True)
        bpy.context.view_layer.objects.active = sel[0]
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True, export_materials="EXPORT", export_image_format="NONE",
                                  export_normals=True, export_texcoords=True, export_tangents=True,
                                  export_vertex_color="NAME", export_vertex_color_name="Col", export_all_vertex_colors=False,
                                  export_animations=False, export_cameras=False, export_lights=False,
                                  export_extras=False, export_skins=False)
        for o in extra:
            bpy.data.objects.remove(o, do_unlink=True)
        meta = self.metadata()
        meta["glb_bytes"] = os.path.getsize(path)
        with open(os.path.join(out_dir, self.id + ".json"), "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=1)
        A.write_glb_import(path)
        return meta

    def metadata(self):
        lo, hi = self.bounds(0)
        parts = []
        for n in self.order:
            if self._is_template(n):
                continue
            p = self.parts[n]
            pv = p.pivot
            parts.append({
                "name": n, "parent": p.parent or "", "pivot_godot": [round(pv.x, 4), round(pv.z, 4), round(-pv.y, 4)],
                "axis": p.axis, "note": p.note if p.note != "template" else "",
                "instance_of": p.source or "", "tris": [L.tri_count(o) if o else 0 for o in p.objs],
            })
        return {
            "id": self.id, "family": "vehicle", "display_name": self.display_name, "category": self.category,
            "description": self.description,
            "bounds_min": [round(c, 3) for c in lo], "bounds_max": [round(c, 3) for c in hi],
            "size_above_ground": [round(hi.x - lo.x, 3), round(hi.y - lo.y, 3), round(hi.z - max(lo.z, 0.0), 3)],
            "footprint_xy": [round(lo.x, 3), round(lo.y, 3), round(hi.x, 3), round(hi.y, 3)],
            "tris": [self.tris(i) for i in ALL],
            "surfaces": [sum(len(o.data.materials) for o in self.lod_objects(i)) for i in ALL],
            "draw_objects": [len(self.lod_objects(i)) for i in ALL],
            "materials": self.materials(), "lod_ranges": self.lod_ranges,
            "collision_boxes_godot": [A.box_to_godot(s, c, y) for s, c, y in self.cols],
            "markers": self.markers, "parts": parts, **self.meta,
        }


class _CutTmp:
    """Part stand-in for cut builders: the shape helpers write into tmp.a.bms[0]."""

    def __init__(self):
        self.a = A.Asset("cut", "vehicle", "cut")

    def __getattr__(self, k):
        return getattr(self.__dict__["a"], k)


def _apply_cuts(obj, cuts, coll, tex_dir):
    """Exact boolean differences on one LOD0 object, one cutter at a time (cutters may
    overlap each other), then the new inner faces get the interior palette swatch, a little
    darker vertex colour (no sun inside) and sharp shading."""
    pal = AM.blender_material("Kit_Palette", tex_dir)
    swatch = {}
    for k, (builder, interior) in enumerate(cuts):
        tmp = _CutTmp()
        builder(tmp)
        bm = tmp.a.bms[0]
        if not bm.faces:
            continue
        A.Asset._orient_closed_islands(bm)
        for f in bm.faces:
            f.material_index = 0
        cutter = L.new_object("CUT_%d" % k, bm, coll, [pal])
        # The exact solver occasionally collapses a shell on a near-degenerate configuration:
        # check the result (volume, face count) and retry with other settings before giving up.
        keep = obj.data.copy()
        vol0 = _volume(obj)
        ok = False
        for solver, self_x, holes, nudge in (("EXACT", True, True, 0.0), ("EXACT", True, False, 0.0007), ("EXACT", False, False, 0.0013),
                                             ("FLOAT", False, False, 0.0)):
            if nudge:
                cutter.location = (nudge, -nudge * 0.7, nudge * 0.4)
            mod = obj.modifiers.new("Cut%d" % k, "BOOLEAN")
            mod.operation = "DIFFERENCE"
            mod.solver = solver
            mod.object = cutter
            if solver == "EXACT":
                # The shell is several overlapping closed solids (slabs, lofts): self-intersection
                # mode resolves them as one volume before subtracting.
                mod.use_self = self_x
                mod.use_hole_tolerant = holes
            try:
                mod.material_mode = "TRANSFER"
            except Exception:
                pass
            L.activate(obj)
            bpy.ops.object.modifier_apply(modifier=mod.name)
            vol1 = _volume(obj)
            # a cavity removes most of the volume; a collapse removes the faces as well
            if len(obj.data.polygons) >= 0.6 * len(keep.polygons) and vol1 > 0.04 * vol0:
                ok = True
                break
            obj.data = keep.copy()
        if not ok:
            obj.data = keep
            print("FNWARN cut %d on %s failed with every solver; skipped" % (k, obj.name))
        else:
            bpy.data.meshes.remove(keep)
        bpy.data.objects.remove(cutter, do_unlink=True)
        swatch[interior] = True
    # Booleans can leave islands with mixed winding: re-orient the closed shell outwards.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bmesh.ops.dissolve_degenerate(bm, dist=0.0005, edges=list(bm.edges))
    bm.to_mesh(obj.data)
    bm.free()
    me = obj.data
    names = [m.name if m else "" for m in me.materials]
    if "Kit_Palette" not in names:
        return
    pi = names.index("Kit_Palette")
    uv = me.uv_layers.get("UVMap")
    col = me.color_attributes.get("Col")
    target = AM.palette_uv(next(iter(swatch)) if swatch else "Paint_White")
    for poly in me.polygons:
        if poly.material_index != pi:
            continue
        poly.use_smooth = False
        for li in poly.loop_indices:
            if uv:
                uv.data[li].uv = target
            if col is not None and col.domain == "CORNER":
                col.data[li].color = (0.78, 0.78, 0.76, 1.0)


def _volume(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    v = abs(bm.calc_volume(signed=False))
    bm.free()
    return v


def _weighted_normals(o):
    """Face-area weighted normals with the auto-smooth sharp edges kept: flat armour plates
    stay flat right up to their bevels instead of shading across the whole panel."""
    L.activate(o)
    m = o.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    m.keep_sharp = True
    m.weight = 50
    try:
        bpy.ops.object.modifier_apply(modifier=m.name)
    except Exception:
        o.modifiers.remove(m)


# ---------------------------------------------------------------------------- bevels


@contextmanager
def bevel(p, width=0.012, angle=28.0, lods=(0,), segs=1):
    """Bevels the sharp edges of everything built inside the block (on the given LODs):
    armour plates and boxes catch a highlight on their edges instead of meeting in a
    razor line. Only the new geometry is touched."""
    before = {i: set(p.a.bms[i].faces) for i in lods}
    yield
    lim = math.radians(angle)
    for i in lods:
        bm = p.a.bms[i]
        new = [f for f in bm.faces if f not in before[i]]
        if not new:
            continue
        mats = {f.material_index for f in new}
        newset = set(new)
        edges = set()
        for f in new:
            for e in f.edges:
                lf = e.link_faces
                if len(lf) == 2 and lf[0] in newset and lf[1] in newset and lf[0].normal.angle(lf[1].normal, 0) > lim:
                    edges.add(e)
        if not edges:
            continue
        mat = next(iter(mats)) if len(mats) == 1 else None
        res = bmesh.ops.bevel(bm, geom=list(edges), offset=width, segments=segs, profile=0.5, affect="EDGES",
                              clamp_overlap=True, harden_normals=False)
        if mat is not None:
            for f in res.get("faces", []):
                f.material_index = mat


# ---------------------------------------------------------------------------- shapes


def mirror_ring(half, y):
    """Full cross-section ring from a half profile [(x, z)] that runs from the bottom centre
    (x = 0) around the right side to the top centre (x = 0). Points with x = 0 are shared."""
    right = [Vector((x, y, z)) for x, z in half]
    left = [Vector((-x, y, z)) for x, z in reversed(half)]
    if half[0][0] == 0:
        left = left[:-1]
    if half[-1][0] == 0:
        left = left[1:]
    return right + left


def hull_loft(p, stations, mat, lods=ALL, smooth=False):
    """Armoured hull / body from cross-sections along Y: stations = [(y, half_profile)],
    every half profile with the same number of points. Closed and capped."""
    rings = [[tuple(v) for v in mirror_ring(h, y)] for y, h in stations]
    p.a.loft(rings, mat, lods, closed=True, cap=True, smooth=smooth, recalc=True)


def round_half(w, z0, z1, n=2.6, pts=10, xc=0.0, belly=1.0):
    """Half cross-section of a rounded body (superellipse, exponent n: 2 = ellipse, larger =
    squarer): width w, from z0 to z1, bottom centre -> right side -> top centre (x >= 0).
    belly < 1 flattens the lower half."""
    out = []
    zc, hz = (z0 + z1) / 2, (z1 - z0) / 2
    for k in range(pts + 1):
        a = -math.pi / 2 + math.pi * k / pts
        c, s = math.cos(a), math.sin(a)
        x = xc + (w / 2) * (abs(c) ** (2 / n))
        z = zc + hz * math.copysign(abs(s) ** (2 / n), s) * (belly if s < 0 else 1.0)
        out.append((0.0 if k in (0, pts) else round(x, 5), z))
    return out


def round_ring(xc, y, w, z0, z1, n=2.6, pts=16):
    """Full closed superellipse ring (x, y, z) centred on x = xc at station y."""
    zc, hx, hz = (z0 + z1) / 2, w / 2, (z1 - z0) / 2
    ring = []
    for k in range(pts):
        a = 2 * math.pi * k / pts
        c, s = math.cos(a), math.sin(a)
        ring.append((xc + hx * math.copysign(abs(c) ** (2 / n), c), y, zc + hz * math.copysign(abs(s) ** (2 / n), s)))
    return ring


def pod_loft(p, xc, stations, mat, lods=ALL, n=2.6, pts=16, smooth=True):
    """Streamlined pod (sponson, engine cowling, fairing): stations [(y, w, z0, z1)]."""
    p.a.loft([round_ring(xc, y, w, z0, z1, n, pts) for y, w, z0, z1 in stations], mat, lods, closed=True, cap=True, smooth=smooth, recalc=True)


def plan_loft(p, layers, mat, lods=ALL, smooth=False):
    """Solid from plan-view outlines stacked in Z (turrets, wedge armour): layers =
    [(z, half_outline)] where half_outline [(x, y)] runs from the front centre (x = 0) around
    the right side to the rear centre (x = 0); it is mirrored to the left. Closed and capped."""
    rings = []
    for z, half in layers:
        right = [(x, y, z) for x, y in half]
        left = [(-x, y, z) for x, y in reversed(half)]
        if half[0][0] == 0:
            left = left[:-1]
        if half[-1][0] == 0:
            left = left[1:]
        rings.append(right + left)
    p.a.loft(rings, mat, lods, closed=True, cap=True, smooth=smooth, recalc=True)


def side_loft(p, stations, mat, lods=ALL, smooth=False):
    """Body from side profiles along X (for shapes defined in the side view): stations =
    [(x, [(y, z), ...])] closed outlines, same point count each. Closed and capped."""
    rings = [[(x, y, z) for y, z in prof] for x, prof in stations]
    p.a.loft(rings, mat, lods, closed=True, cap=True, smooth=smooth, recalc=True)


def extrude_x(p, outline, x0, x1, mat, lods=ALL):
    """Closed side-view outline [(y, z)] extruded across X from x0 to x1."""
    side_loft(p, [(x0, outline), (x1, outline)], mat, lods)


def revolve(p, profile, center, axis, mat, lods=ALL, segs=24, smooth=True, cap0=False, cap1=False, phase=0.0, flip=False):
    """Lathe: profile [(r, t)] (radius, position along the axis) swept around `axis` through
    `center` (tyres, rims, hubs, barrels, masts). A profile whose last point repeats the first
    is a closed section (a solid ring); r = 0 at an end closes it with a pole; cap0 / cap1 close
    an end ring with a flat disc. Closed results get outward normals from bmesh; an open
    surface faces away from the axis (flip reverses it)."""
    ax = Vector(axis).normalized()
    ref = Vector((0, 0, 1)) if abs(ax.z) < 0.9 else Vector((1, 0, 0))
    u = ax.cross(ref).normalized()
    w = ax.cross(u).normalized()
    c = Vector(center)
    loop = len(profile) > 2 and abs(profile[0][0] - profile[-1][0]) < 1e-9 and abs(profile[0][1] - profile[-1][1]) < 1e-9
    prof = profile[:-1] if loop else profile
    for i in lods:
        s = segs if i == 0 else max(8, segs // (2 if i == 1 else 4))
        bm, idx = p.a.bms[i], p.a._slot(i, mat)
        rings = []
        for r, t in prof:
            if r < 1e-6:
                rings.append(bm.verts.new(c + ax * t))
                continue
            ring = []
            for k in range(s):
                a = phase + 2 * math.pi * k / s
                ring.append(bm.verts.new(c + ax * t + (u * math.cos(a) + w * math.sin(a)) * r))
            rings.append(ring)
        pairs = list(zip(rings[:-1], rings[1:])) + ([(rings[-1], rings[0])] if loop else [])
        faces = []
        for ra, rb in pairs:
            pa, pb = not isinstance(ra, list), not isinstance(rb, list)
            if pa and pb:
                continue
            for k in range(s):
                if pa:
                    faces.append(bm.faces.new((ra, rb[(k + 1) % s], rb[k])))
                elif pb:
                    faces.append(bm.faces.new((ra[k], ra[(k + 1) % s], rb)))
                else:
                    faces.append(bm.faces.new((ra[k], ra[(k + 1) % s], rb[(k + 1) % s], rb[k])))
        first_closed = loop or not isinstance(rings[0], list) or cap0
        last_closed = loop or not isinstance(rings[-1], list) or cap1
        if not loop and cap0 and isinstance(rings[0], list):
            faces.append(bm.faces.new(list(reversed(rings[0]))))
        if not loop and cap1 and isinstance(rings[-1], list):
            faces.append(bm.faces.new(rings[-1]))
        for f in faces:
            f.material_index = idx
            f.smooth = smooth
        if not faces:
            continue
        if first_closed and last_closed:
            bmesh.ops.recalc_face_normals(bm, faces=faces)
        else:
            out = 0.0
            for f in faces:
                m = f.calc_center_median() - c
                radial = m - ax * m.dot(ax)
                out += f.normal.dot(radial) * f.calc_area()
            if (out < 0) != flip:
                bmesh.ops.reverse_faces(bm, faces=faces)


def ring_band(p, r_in, r_out, t0, t1, center, axis, mat, lods=ALL, segs=24):
    """Closed annular solid (hub ring, flange, tyre bead)."""
    revolve(p, [(r_in, t0), (r_out, t0), (r_out, t1), (r_in, t1), (r_in, t0)], center, axis, mat, lods, segs, smooth=False)


def disc(p, profile, thick, center, axis, mat, lods=ALL, segs=24, smooth=False):
    """A dished disc / hub as a closed solid: the outer surface `profile` [(r, t)] (from the
    rim inwards) and the same surface `thick` behind it along -axis."""
    back = [(r, t - thick) for r, t in reversed(profile)]
    revolve(p, list(profile) + back + [profile[0]], center, axis, mat, lods, segs, smooth)


def plate(p, corners, thick, mat, lods=ALL):
    """A flat plate from 4+ coplanar corners (CCW seen from outside) with a thickness."""
    cs = [Vector(c) for c in corners]
    n = (cs[1] - cs[0]).cross(cs[2] - cs[1]).normalized()
    outer = [tuple(c) for c in cs]
    inner = [tuple(c - n * thick) for c in cs]
    k = len(cs)
    for i in lods:
        bm, idx = p.a.bms[i], p.a._slot(i, mat)
        vo = [bm.verts.new(c) for c in outer]
        vi = [bm.verts.new(c) for c in inner]
        fs = [bm.faces.new(vo), bm.faces.new(list(reversed(vi)))]
        for j in range(k):
            fs.append(bm.faces.new((vo[(j + 1) % k], vo[j], vi[j], vi[(j + 1) % k])))
        for f in fs:
            f.material_index = idx
        bmesh.ops.recalc_face_normals(bm, faces=fs)


def slats(p, x0, x1, z0, z1, y, n, depth, thick, mat, lods=L0, vertical=True, frame_mat=None, tilt=35.0):
    """Louvre grille in the plane y (front/back), n slats, optional frame."""
    if vertical:
        w = (x1 - x0) / n
        for k in range(n):
            cx = x0 + w * (k + 0.5)
            p.a.box((thick, depth, z1 - z0), (cx, y, (z0 + z1) / 2), mat, lods, rot=A.rot_z(tilt))
    else:
        h = (z1 - z0) / n
        for k in range(n):
            cz = z0 + h * (k + 0.5)
            p.a.box((x1 - x0, depth, thick), ((x0 + x1) / 2, y, cz), mat, lods, rot=A.rot_x(-tilt))
    if frame_mat:
        t = thick * 1.5
        p.a.box((x1 - x0 + 2 * t, depth, t), ((x0 + x1) / 2, y, z1 + t / 2), frame_mat, lods)
        p.a.box((x1 - x0 + 2 * t, depth, t), ((x0 + x1) / 2, y, z0 - t / 2), frame_mat, lods)
        p.a.box((t, depth, z1 - z0), (x0 - t / 2, y, (z0 + z1) / 2), frame_mat, lods)
        p.a.box((t, depth, z1 - z0), (x1 + t / 2, y, (z0 + z1) / 2), frame_mat, lods)


def bolts(p, pts, axis, r=0.012, h=0.012, mat="Steel_Dark", lods=L0, segs=6):
    for c in pts:
        p.a.cyl(r, r, h, c, mat, lods, axis=axis, segs=segs)


def handle(p, a, b, standoff, normal, r=0.012, mat="Steel_Dark", lods=L01):
    """A grab handle: a bar from a to b standing `standoff` off the surface along normal."""
    a, b, n = Vector(a), Vector(b), Vector(normal).normalized() * standoff
    p.a.tube([tuple(a), tuple(a + n), tuple(b + n), tuple(b)], r, mat, lods, segs=6, cap=True)


# ---------------------------------------------------------------------------- previews

PREVIEW_VIEWS = [
    # suffix, azimuth (0 = in front), elevation, distance factor, target height factor, lens
    ("front34", 38, 12, 1.05, 0.42, 50),
    ("rear34", 218, 12, 1.05, 0.42, 50),
    ("side", 90, 2, 1.25, 0.42, 85),
    ("top34", 35, 38, 1.15, 0.30, 50),
]


def render_previews(veh, out_dir, tex_dir, res=(1280, 800), views=None, tag=None, lod=0, clay=True):
    """Eevee renders (library materials, sun + sky) from the brief's four views and a
    Workbench clay sheet (cavity + outline, no textures) for reading the geometry."""
    L.setup_render(res, samples=32)
    A.use_jpeg(92)
    sc = bpy.context.scene
    sc.view_settings.look = "AgX - Base Contrast"
    for n, p in veh.parts.items():
        for i, o in enumerate(p.objs):
            if o is not None:
                hide = i != lod or veh._is_template(n)
                o.hide_render = hide
                o.hide_set(hide)
    lo, hi = veh.bounds(lod)
    lo.z = max(lo.z, 0.0)
    ext = hi - lo
    radius = max(ext.length * 0.5, 0.5)
    A.preview_ground(max(radius * 12, 40), tex_dir)
    centre = (lo + hi) / 2
    tag = tag or veh.id
    out = []
    for suffix, az, el, df, tz, lens in (views or PREVIEW_VIEWS):
        t = Vector((centre.x, centre.y, lo.z + ext.z * tz))
        fov = 2 * math.atan(18.0 / lens)
        dist = radius / math.sin(fov * 0.5) * df * 0.92
        path = os.path.join(out_dir, "%s_%s.jpg" % (tag, suffix))
        L.render_view(path, tuple(t), dist, az, el, lens=lens)
        out.append(path)
    sheet = A.sheet(out, os.path.join(out_dir, "%s_render.jpg" % tag), 2, delete=False)
    clay_sheet = None
    if clay:
        eng = sc.render.engine
        sc.render.engine = "BLENDER_WORKBENCH"
        sh = sc.display.shading
        sh.light = "STUDIO"
        sh.color_type = "SINGLE"
        sh.single_color = (0.62, 0.62, 0.60)
        sh.show_cavity = True
        sh.cavity_type = "BOTH"
        sh.show_object_outline = False
        sh.show_shadows = True
        cl = []
        for suffix, az, el, df, tz, lens in (views or PREVIEW_VIEWS):
            t = Vector((centre.x, centre.y, lo.z + ext.z * tz))
            fov = 2 * math.atan(18.0 / lens)
            dist = radius / math.sin(fov * 0.5) * df * 0.92
            path = os.path.join(out_dir, "%s_clay_%s.jpg" % (tag, suffix))
            L.render_view(path, tuple(t), dist, az, el, lens=lens)
            cl.append(path)
        clay_sheet = A.sheet(cl, os.path.join(out_dir, "%s_clay.jpg" % tag), 2, delete=True)
        sc.render.engine = eng
    for n, p in veh.parts.items():
        for o in p.objs:
            if o is not None and not veh._is_template(n):
                o.hide_render = False
                o.hide_set(False)
    return {"views": out, "sheet": sheet, "clay": clay_sheet}


def render_detail(veh, out_dir, tex_dir, name, target, dist, az, el, lens=50, res=(1280, 800)):
    """One close-up (running gear, turret, rotor head) of LOD0 for inspection."""
    L.setup_render(res, samples=32)
    A.use_jpeg(92)
    for n, p in veh.parts.items():
        for i, o in enumerate(p.objs):
            if o is not None:
                hide = i != 0 or veh._is_template(n)
                o.hide_render = hide
                o.hide_set(hide)
    path = os.path.join(out_dir, "%s_detail_%s.jpg" % (veh.id, name))
    L.render_view(path, tuple(target), dist, az, el, lens=lens)
    return path
