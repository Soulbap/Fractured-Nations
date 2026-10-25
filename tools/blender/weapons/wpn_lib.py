"""WEAPON-ASSETS-01: weapon assets on the CHARACTER-01 weapon contract.

Weapon space (docs/CHARACTER_STANDARD.md section 3): metres, origin = centre of the pistol grip
where the firing hand closes (launchers: their firing grip), +Y = muzzle, +Z = up, bore axis
of rifles at z = BORE_Z. Mount / reference nodes are empties exported as glTF nodes:

    ATT_Optic        optic mount (rail) - the character mounts loadout optics here
    ATT_Muzzle       muzzle face: first-person flash and tracer start
    ATT_Underbarrel  / ATT_RailRight where the weapon has such rails
    GRIP_Main        firing-hand grip (= origin, Y = hand axis)
    GRIP_Support     support-hand pose (Y = hand axis, Z = back of hand)
    ATT_Magazine     magwell (= origin of the detachable magazine)

Meshes (names are the contract with the Godot loaders, `<wid>` = stable id, e.g. weapon_hk416):

    <wid>_LOD0/1/2          the main body (receiver, barrel, furniture, fixed sights)
    <wid>_Mag_LOD0/1/2      detachable magazine (hung on ATT_Magazine by InfantryCharacter)
    <wid>_<Part>_LOD0/1/2   moving / separable parts (Bolt, ChargingHandle, Trigger, Stock,
                            Bipod, Optic, FeedCover, ...) under their pivot node PIV_<Part>

LOD0 is the first-person / close model, LOD1 the world model (soldiers at 12-28 m, loot on the
ground) and LOD2 the distance silhouette; all three are authored (small parts are left out,
segment counts drop), never decimated. Materials are names from the CHARACTER-01 library
(char_materials.MATERIALS / InfantryMaterials.TABLE); UVs are world-scale box projections.
"""
import json
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

import char_lib as L
import char_materials as CM

ALL = (0, 1, 2)
L01 = (0, 1)
L0 = (0,)
L12 = (1, 2)
L2 = (2,)
BORE_Z = 0.074


def rx(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


def ry(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Y")


def rz(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Z")


class Part:
    """Geometry of one object, per LOD: bmesh + material slot list."""

    def __init__(self, w, name, pivot, parent, axis, note):
        self.w = w
        self.name = name
        self.pivot = Vector(pivot)
        self.parent = parent
        self.axis = axis
        self.note = note
        self.bms = {i: bmesh.new() for i in ALL}
        self.slots = {i: [] for i in ALL}
        self.cuts = []
        self.objs = [None, None, None]

    def _slot(self, i, mat):
        s = self.slots[i]
        if mat not in s:
            s.append(mat)
        return s.index(mat)

    def _bevel_new(self, i, before, width, segs, angle=30.0):
        bm = self.bms[i]
        new = [f for f in bm.faces if f not in before]
        if not new or width <= 0:
            return
        newset = set(new)
        mats = {f.material_index for f in new}
        lim = math.radians(angle)
        edges = [e for f in new for e in f.edges
                 if len(e.link_faces) == 2 and e.link_faces[0] in newset and e.link_faces[1] in newset
                 and e.link_faces[0].normal.angle(e.link_faces[1].normal, 0) > lim]
        if not edges:
            return
        res = bmesh.ops.bevel(bm, geom=list(set(edges)), offset=width, segments=segs, profile=0.5, affect="EDGES",
                              clamp_overlap=True)
        if len(mats) == 1:
            m = next(iter(mats))
            for f in res.get("faces", []):
                f.material_index = m

    # ------------------------------------------------------------------ primitives

    def prism(self, outline, x0, x1, mat, lods=ALL, bevel=0.0015, segs=2, rot=None, origin=(0, 0, 0)):
        """Side-view outline [(y, z)] (closed, either winding) extruded across X from x0 to x1:
        receivers, grips, stocks, magazines, handguards. Sharp edges are bevelled (LOD0: `segs`
        segments, LOD1: one, LOD2: none). rot / origin place it (rotation about origin)."""
        o = Vector(origin)
        for i in lods:
            bm, idx = self.bms[i], self._slot(i, mat)
            before = set(bm.faces)
            pts = outline if i < 2 or len(outline) <= 12 else outline[::2]

            def P(x, y, z):
                v = Vector((x, y, z))
                return (rot @ (v - o) + o) if rot is not None else v
            a = [bm.verts.new(P(x0, y, z)) for y, z in pts]
            b = [bm.verts.new(P(x1, y, z)) for y, z in pts]
            n = len(pts)
            fs = [bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k])) for k in range(n)]
            fs += [bm.faces.new(list(reversed(a))), bm.faces.new(b)]
            for f in fs:
                f.material_index = idx
            bmesh.ops.recalc_face_normals(bm, faces=fs)
            if i < 2 and bevel > 0:
                self._bevel_new(i, before, bevel if i == 0 else bevel * 1.5, segs if i == 0 else 1)

    def box(self, size, c, mat, lods=ALL, r=0.0012, rot=None, segs=2):
        for i in lods:
            bm, idx = self.bms[i], self._slot(i, mat)
            before = set(bm.faces)
            vs = L.bm_box(bm, size, Vector(c), mat=idx, rot=rot)
            if i < 2 and r > 0 and min(size) > 2.5 * r:
                self._bevel_new(i, before, r if i == 0 else r * 1.3, segs if i == 0 else 1)

    def box_between(self, lo, hi, mat, lods=ALL, r=0.0012):
        lo, hi = Vector(lo), Vector(hi)
        self.box(tuple(hi - lo), tuple((lo + hi) / 2), mat, lods, r)

    def cyl(self, r, length, c, mat, lods=ALL, axis=(0, 1, 0), segs=16, r2=None, bevel=0.0):
        for i in lods:
            s = segs if i == 0 else max(6, segs // (2 if i == 1 else 3))
            bm, idx = self.bms[i], self._slot(i, mat)
            before = set(bm.faces)
            L.bm_cyl(bm, r, r if r2 is None else r2, length, Vector(c), axis=axis, segs=s, mat=idx)
            if i == 0 and bevel > 0:
                self._bevel_new(i, before, bevel, 1, angle=50)

    def cyl_between(self, a, b, r, mat, lods=ALL, segs=12, r2=None):
        a, b = Vector(a), Vector(b)
        d = b - a
        self.cyl(r, d.length, tuple((a + b) / 2), mat, lods, axis=tuple(d.normalized()), segs=segs, r2=r2)

    def lathe(self, profile, c, axis, mat, lods=ALL, segs=24, smooth=True, phase=0.0):
        """Closed lathe: profile [(r, t)] along `axis` through c, r = 0 ends make poles; a profile
        whose last point repeats the first is a ring section (tubes with a bore)."""
        ax = Vector(axis).normalized()
        ref = Vector((0, 0, 1)) if abs(ax.z) < 0.9 else Vector((1, 0, 0))
        u = ax.cross(ref).normalized()
        wv = ax.cross(u).normalized()
        cc = Vector(c)
        loop = len(profile) > 2 and profile[0] == profile[-1]
        prof = profile[:-1] if loop else profile
        for i in lods:
            s = segs if i == 0 else max(6, segs // (2 if i == 1 else 3))
            bm, idx = self.bms[i], self._slot(i, mat)
            rings = []
            for r, t in prof:
                if r < 1e-7:
                    rings.append(bm.verts.new(cc + ax * t))
                    continue
                rings.append([bm.verts.new(cc + ax * t + (u * math.cos(phase + 2 * math.pi * k / s) + wv * math.sin(phase + 2 * math.pi * k / s)) * r)
                              for k in range(s)])
            pairs = list(zip(rings[:-1], rings[1:])) + ([(rings[-1], rings[0])] if loop else [])
            fs = []
            for ra, rb in pairs:
                pa, pb = not isinstance(ra, list), not isinstance(rb, list)
                if pa and pb:
                    continue
                for k in range(s):
                    if pa:
                        fs.append(bm.faces.new((ra, rb[(k + 1) % s], rb[k])))
                    elif pb:
                        fs.append(bm.faces.new((ra[k], ra[(k + 1) % s], rb)))
                    else:
                        fs.append(bm.faces.new((ra[k], ra[(k + 1) % s], rb[(k + 1) % s], rb[k])))
            if not loop:
                if isinstance(rings[0], list):
                    fs.append(bm.faces.new(list(reversed(rings[0]))))
                if isinstance(rings[-1], list):
                    fs.append(bm.faces.new(rings[-1]))
            for f in fs:
                f.material_index = idx
                f.smooth = smooth
            bmesh.ops.recalc_face_normals(bm, faces=fs)

    def tube(self, pts, r, mat, lods=ALL, segs=8):
        for i in lods:
            s = segs if i == 0 else max(4, segs // 2)
            L.tube_along(self.bms[i], [Vector(p) for p in pts], [r] * len(pts), segs=s, mat=self._slot(i, mat), cap=True)

    def loft(self, rings, mat, lods=ALL, smooth=False):
        """Closed, capped solid through rings of 3D points (same count each)."""
        for i in lods:
            bm, idx = self.bms[i], self._slot(i, mat)
            vr = [[bm.verts.new(Vector(p)) for p in r] for r in rings]
            n = len(rings[0])
            fs = []
            for a, b in zip(vr[:-1], vr[1:]):
                for k in range(n):
                    fs.append(bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k])))
            fs += [bm.faces.new(list(reversed(vr[0]))), bm.faces.new(vr[-1])]
            for f in fs:
                f.material_index = idx
                f.smooth = smooth
            bmesh.ops.recalc_face_normals(bm, faces=fs)

    def rail(self, y0, y1, z, mat="Weapon_Anodized", lods=L01, x=0.0, rot=None, width=0.0212, slots=True):
        """MIL-STD-1913 Picatinny rail on top (rot rotates about the bore axis for side / bottom
        rails): base, dovetail crown, recoil slots every 10.0 mm (LOD0)."""
        L_ = y1 - y0
        cy = (y0 + y1) / 2

        def place(c):
            v = Vector(c)
            if rot is not None:
                v = rot @ (v - Vector((0, v.y, BORE_Z))) + Vector((0, v.y, BORE_Z))
            return tuple(v)
        self.box((width * 0.75, L_, 0.0045), place((x, cy, z + 0.00225)), mat, lods, r=0.0006, rot=rot)
        self.box((width, L_, 0.0035), place((x, cy, z + 0.0062)), mat, lods, r=0.0008, rot=rot)
        if slots:
            n = int(L_ / 0.010)
            for k in range(n):
                y = y0 + 0.005 + k * 0.010 + (L_ - n * 0.010) / 2
                self.box((width + 0.0004, 0.0052, 0.0028), place((x, y, z + 0.0075)), mat, L0, r=0.0004, rot=rot)

    def screw(self, c, normal, r=0.0022, mat="Metal_Black", lods=L0):
        n = Vector(normal).normalized()
        self.cyl(r, 0.0012, tuple(Vector(c) + n * 0.0004), mat, lods, axis=tuple(n), segs=8)

    def cut(self, builder):
        """Boolean-subtract a closed solid from this part's LOD0 (and LOD1 if builder accepts lod)."""
        self.cuts.append(builder)


class _Tmp:
    def __init__(self, w):
        self.p = Part(w, "cut", (0, 0, 0), None, "", "")

    def __getattr__(self, k):
        return getattr(self.__dict__["p"], k)


class Weapon:
    def __init__(self, wid, display, faction, kind, description=""):
        self.wid = wid
        self.display = display
        self.faction = faction
        self.kind = kind
        self.description = description
        self.parts = {}
        self.order = []
        self.markers = []
        self.meta = {}
        self.mag = None

    def part(self, name="Body", pivot=(0, 0, 0), parent=None, axis="", note=""):
        p = Part(self, name, pivot, parent, axis, note)
        self.parts[name] = p
        self.order.append(name)
        return p

    def magazine(self, top, note="detachable magazine"):
        """The detachable magazine part (origin = magwell `top`)."""
        p = self.part("Mag", pivot=top, axis="", note=note)
        self.mag = p
        return p

    def marker(self, name, pos, rot=None, note=""):
        self.markers.append({"name": name, "pos": [round(c, 5) for c in pos], "rot": rot or [0, 0, 0], "note": note})

    # ------------------------------------------------------------------ build

    def mesh_name(self, part, lod):
        if part == "Body":
            return "%s_LOD%d" % (self.wid, lod)
        return "%s_%s_LOD%d" % (self.wid, part, lod)

    def build(self, coll, mats):
        self.coll = coll
        for name in self.order:
            p = self.parts[name]
            for i in ALL:
                bm = p.bms[i]
                if not bm.faces:
                    continue
                me = bpy.data.meshes.new(self.mesh_name(name, i))
                bm.to_mesh(me)
                bm.free()
                o = bpy.data.objects.new(self.mesh_name(name, i), me)
                coll.objects.link(o)
                for m in p.slots[i]:
                    me.materials.append(mats[m])
                if i == 0 and p.cuts:
                    _apply_cuts(o, p, coll, mats)
                CM.apply_box_uvs(o)
                for poly in me.polygons:
                    poly.use_smooth = True
                L.shade_smooth(o, 32)
                _weighted_normals(o)
                o.data.transform(Matrix.Translation(-p.pivot))
                p.objs[i] = o
        self.empties = {}
        for name in self.order:
            p = self.parts[name]
            if name == "Body":
                continue
            e = bpy.data.objects.new("PIV_" + name if name != "Mag" else "ATT_Magazine", None)
            e.empty_display_size = 0.02
            coll.objects.link(e)
            e.location = p.pivot - (self.parts[p.parent].pivot if p.parent else Vector())
            self.empties[name] = e
        for name in self.order:
            p = self.parts[name]
            if p.parent and name in self.empties:
                self.empties[name].parent = self.empties[p.parent]
            for o in p.objs:
                if o is not None and name in self.empties:
                    o.parent = self.empties[name]
                    o.location = (0, 0, 0)
        bpy.context.view_layer.update()

    def lod_objects(self, lod):
        return [p.objs[lod] for p in self.parts.values() if p.objs[lod] is not None]

    def tris(self, lod):
        return sum(L.tri_count(o) for o in self.lod_objects(lod))

    def materials(self):
        return sorted({m.name for i in ALL for o in self.lod_objects(i) for m in o.data.materials if m is not None})

    def bounds(self, lod=0):
        lo = Vector((1e9, 1e9, 1e9))
        hi = -lo
        for o in self.lod_objects(lod):
            for v in o.data.vertices:
                w = o.matrix_world @ v.co
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
        return lo, hi

    # ------------------------------------------------------------------ export

    def export(self, out_dir):
        os.makedirs(out_dir, exist_ok=True)
        extra = []
        for m in self.markers:
            e = bpy.data.objects.new(m["name"], None)
            e.empty_display_size = 0.02
            e.location = m["pos"]
            e.rotation_mode = "XYZ"
            e.rotation_euler = [math.radians(a) for a in m["rot"]]
            self.coll.objects.link(e)
            extra.append(e)
        objs = [o for i in ALL for o in self.lod_objects(i)] + list(self.empties.values()) + extra
        path = os.path.join(out_dir, self.wid + ".glb")
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.hide_set(False)
            o.hide_render = False
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False, export_yup=True,
                                  export_materials="EXPORT", export_image_format="NONE", export_normals=True, export_texcoords=True,
                                  export_tangents=True, export_skins=False, export_animations=False, export_cameras=False,
                                  export_lights=False, export_extras=False)
        for e in extra:
            bpy.data.objects.remove(e, do_unlink=True)
        meta = self.metadata()
        meta["glb_bytes"] = os.path.getsize(path)
        with open(os.path.join(out_dir, self.wid + ".json"), "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=1)
        return meta

    def metadata(self):
        lo, hi = self.bounds(0)
        parts = []
        for n in self.order:
            p = self.parts[n]
            pv = p.pivot
            parts.append({"name": n, "node": "" if n == "Body" else ("ATT_Magazine" if n == "Mag" else "PIV_" + n),
                          "parent": p.parent or "", "pivot_godot": [round(pv.x, 5), round(pv.z, 5), round(-pv.y, 5)],
                          "axis": p.axis, "note": p.note, "tris": [L.tri_count(o) if o else 0 for o in p.objs]})
        mk = [{"name": m["name"], "pos_godot": [m["pos"][0], m["pos"][2], -m["pos"][1]], "note": m["note"]} for m in self.markers]
        return {"id": self.wid, "display_name": self.display, "faction": self.faction, "kind": self.kind, "description": self.description,
                "bounds_min": [round(c, 4) for c in lo], "bounds_max": [round(c, 4) for c in hi],
                "length_m": round(hi.y - lo.y, 4), "height_m": round(hi.z - lo.z, 4), "width_m": round(hi.x - lo.x, 4),
                "tris": [self.tris(i) for i in ALL], "objects": [len(self.lod_objects(i)) for i in ALL],
                "materials": self.materials(), "parts": parts, "markers": mk, **self.meta}


def _apply_cuts(obj, part, coll, mats):
    for k, builder in enumerate(part.cuts):
        tmp = _Tmp(part.w)
        builder(tmp)
        bm = tmp.p.bms[0]
        if not bm.faces:
            continue
        for f in bm.faces:
            f.material_index = 0          # the cut walls take the part's first material
        me = bpy.data.meshes.new("CUT")
        bm.to_mesh(me)
        cutter = bpy.data.objects.new("CUT_%d" % k, me)
        coll.objects.link(cutter)
        keep = obj.data.copy()
        ok = False
        for self_x, holes in ((False, False), (True, False), (True, True)):
            mod = obj.modifiers.new("Cut", "BOOLEAN")
            mod.operation = "DIFFERENCE"
            mod.solver = "EXACT"
            mod.object = cutter
            mod.use_self = self_x
            mod.use_hole_tolerant = holes
            try:
                mod.material_mode = "INDEX"
            except Exception:
                pass
            L.activate(obj)
            bpy.ops.object.modifier_apply(modifier=mod.name)
            if len(obj.data.polygons) >= 0.7 * len(keep.polygons):
                ok = True
                break
            obj.data = keep.copy()
        if not ok:
            obj.data = keep
            print("FNWARN cut %d on %s failed" % (k, obj.name))
        bpy.data.objects.remove(cutter, do_unlink=True)


def _weighted_normals(o):
    L.activate(o)
    m = o.modifiers.new("WN", "WEIGHTED_NORMAL")
    m.keep_sharp = True
    m.weight = 50
    try:
        bpy.ops.object.modifier_apply(modifier=m.name)
    except Exception:
        o.modifiers.remove(m)


# ---------------------------------------------------------------------------- outline helpers


def rounded_outline(pts, r, n=3):
    """Rounds the corners of a closed polygon [(y, z)] with radius r (n points per corner);
    a per-corner radius can be given as a third tuple element."""
    out = []
    k = len(pts)
    for i in range(k):
        p0, p1, p2 = Vector(pts[i - 1][:2]), Vector(pts[i][:2]), Vector(pts[(i + 1) % k][:2])
        rr = pts[i][2] if len(pts[i]) > 2 else r
        if rr <= 0:
            out.append(tuple(p1))
            continue
        d0, d1 = (p0 - p1), (p2 - p1)
        l0, l1 = d0.length, d1.length
        if l0 < 1e-6 or l1 < 1e-6:
            out.append(tuple(p1))
            continue
        d0.normalize()
        d1.normalize()
        rr = min(rr, l0 * 0.45, l1 * 0.45)
        a = p1 + d0 * rr
        b = p1 + d1 * rr
        for j in range(n + 1):
            t = j / n
            q = a.lerp(p1, t).lerp(p1.lerp(b, t), t)      # quadratic Bezier corner
            out.append((q.x, q.y))
    return out


def arc(cy, cz, r, a0, a1, n):
    return [(cy + r * math.cos(math.radians(a0 + (a1 - a0) * k / n)), cz + r * math.sin(math.radians(a0 + (a1 - a0) * k / n))) for k in range(n + 1)]


def sheet(paths, out, cols, delete=True, quality=90):
    """Packs equally sized renders into one JPEG contact sheet."""
    import numpy as np
    imgs = []
    for p in paths:
        im = bpy.data.images.load(p)
        w, h = im.size
        imgs.append(np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4))
        bpy.data.images.remove(im)
    h, w = imgs[0].shape[:2]
    rows = (len(imgs) + cols - 1) // cols
    px = np.ones((rows * h, cols * w, 4), np.float32) * 0.2
    px[..., 3] = 1.0
    for i, a in enumerate(imgs):
        r, c = divmod(i, cols)
        r = rows - 1 - r
        px[r * h:(r + 1) * h, c * w:(c + 1) * w] = a[:h, :w]
    img = bpy.data.images.new(os.path.basename(out), cols * w, rows * h)
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = out
    img.file_format = "JPEG"
    img.save(quality=quality)
    bpy.data.images.remove(img)
    if delete:
        for p in paths:
            if p != out and os.path.exists(p):
                os.remove(p)
    return out
