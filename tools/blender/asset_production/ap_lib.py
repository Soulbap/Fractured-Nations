"""ASSET-PRODUCTION-01 builder for static assets (Blender 5.2, bpy + bmesh + numpy).

Conventions (same as the WORLD-BASE-01 / CHARACTER-01 pipeline, docs/ASSET_STANDARD.md):
  * 1 unit = 1 m, Z up, the asset's FRONT faces +Y (glTF/Godot -Z), origin on the ground
    at the footprint centre. Foundations reach below z = 0 (terrain fitting skirt).
  * Authored LODs: every primitive is added to the LOD levels it belongs to (default all
    three). Small details go to LOD0 only, medium parts to LOD0+1, and simplified stand-ins
    to LOD1/2 only, so distant levels drop parts instead of melting boxes by decimation.
  * One mesh per LOD, one surface per library material (ap_materials), world-scale box UVs,
    vertex colours with baked ground dirt.
  * Collision: a few boxes, exported as `COL_<n>-convcolonly` (Godot makes static convex
    shapes from them) and written to the metadata as Godot-space AABBs.
  * Markers: empties exported as glTF nodes (`IP_*` interaction points, `ATT_*` expansion
    attachment points, `SNAP_*` alignment points, `VEH_*` vehicle points).

The GLB contains <id>_LOD0 (first), <id>_LOD1, <id>_LOD2, the collision meshes and the
markers. A JSON sidecar holds dimensions, footprint, triangle and surface counts, LOD
ranges, markers and collision boxes.
"""
import json
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

import ap_materials as AM
import char_lib as L

ALL = (0, 1, 2)
L01 = (0, 1)
L0 = (0,)
L12 = (1, 2)
L2 = (2,)

# Default visibility ranges per LOD (metres, begin/end), per family; overridable per asset.
LOD_RANGES = {
    "building": [(0, 70), (70, 280), (280, 2000)],
    "module": [(0, 60), (60, 240), (240, 1600)],
    "prop": [(0, 35), (35, 120), (120, 600)],
    "road": [(0, 60), (60, 250), (250, 1500)],
    "vehicle": [(0, 40), (40, 160), (160, 1500)],
}


def rot_z(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Z")


def rot_x(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


def rot_y(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Y")


def _faces_of(verts):
    return {f for v in verts for f in v.link_faces}


class Asset:
    """Collects geometry per LOD level, collision boxes, markers and metadata."""

    def __init__(self, asset_id, family, display_name, category="", description=""):
        self.id = asset_id
        self.family = family
        self.display_name = display_name
        self.category = category
        self.description = description
        self.bms = {i: bmesh.new() for i in ALL}
        self.slots = {i: [] for i in ALL}
        self.uv_faces = {i: {} for i in ALL}     # authored UVs: face -> [(u, v) per loop]
        self.cols = []
        self.markers = []
        self.meta = {}
        self.lod_ranges = [list(r) for r in LOD_RANGES[family]]
        self.ao_height = 0.8
        self.ao_strength = 0.35
        self.foundation = 0.0
        self.structure = None      # StructureDef hints (buildings / modules)

    # ------------------------------------------------------------------ primitives

    def _slot(self, lod, mat):
        s = self.slots[lod]
        if mat not in s:
            s.append(mat)
        return s.index(mat)

    def box(self, size, center, mat, lods=ALL, rot=None, bevel=0.0, segs=1):
        for i in lods:
            bm, idx = self.bms[i], self._slot(i, mat)
            if bevel > 0 and (i == 0 or (i == 1 and bevel >= 0.02)):
                L.rounded_box(bm, size, Vector(center), bevel, mat=idx, rot=rot, segs=segs if i == 0 else 1)
            else:
                L.bm_box(bm, size, Vector(center), mat=idx, rot=rot)

    def box_between(self, lo, hi, mat, lods=ALL, bevel=0.0):
        lo, hi = Vector(lo), Vector(hi)
        self.box(tuple(hi - lo), tuple((lo + hi) / 2), mat, lods, bevel=bevel)

    def cyl(self, r1, r2, depth, center, mat, lods=ALL, axis=(0, 0, 1), segs=12, cap=True):
        for i in lods:
            s = segs if i == 0 else max(6, segs // (2 if i == 1 else 3))
            L.bm_cyl(self.bms[i], r1, r2, depth, Vector(center), axis=axis, segs=s, mat=self._slot(i, mat), cap=cap)

    def cyl_between(self, a, b, r, mat, lods=ALL, segs=10, r2=None):
        a, b = Vector(a), Vector(b)
        d = b - a
        self.cyl(r, r if r2 is None else r2, d.length, tuple((a + b) / 2), mat, lods, axis=tuple(d.normalized()), segs=segs)

    def sphere(self, r, center, mat, lods=ALL, scale=(1, 1, 1), segs=16, rings=10):
        for i in lods:
            k = 1 if i == 0 else (2 if i == 1 else 3)
            L.bm_sphere(self.bms[i], r, Vector(center), scale=scale, segs=max(6, segs // k), rings=max(4, rings // k), mat=self._slot(i, mat))

    def tube(self, pts, radii, mat, lods=ALL, segs=8, cap=True, flat=1.0):
        if not isinstance(radii, (list, tuple)):
            radii = [radii] * len(pts)
        for i in lods:
            s = segs if i == 0 else max(4, segs // 2)
            L.tube_along(self.bms[i], pts, radii, segs=s, mat=self._slot(i, mat), cap=cap, flat=flat)

    def prism(self, profile, start, end, mat, lods=ALL, up=(0, 0, 1), cap=True, smooth=False):
        """Extrudes a closed 2D profile [(u, v)] from start to end. u runs along
        side = dir x up, v along up (projected perpendicular to the direction)."""
        a, b = Vector(start), Vector(end)
        d = (b - a).normalized()
        upv = Vector(up)
        upv = (upv - d * upv.dot(d)).normalized()
        side = d.cross(upv).normalized()
        for i in lods:
            bm, idx = self.bms[i], self._slot(i, mat)
            r0 = [bm.verts.new(a + side * u + upv * v) for u, v in profile]
            r1 = [bm.verts.new(b + side * u + upv * v) for u, v in profile]
            n = len(profile)
            faces = []
            for k in range(n):
                faces.append(bm.faces.new((r0[k], r0[(k + 1) % n], r1[(k + 1) % n], r1[k])))
            if cap:
                faces.append(bm.faces.new(list(reversed(r0))))
                faces.append(bm.faces.new(r1))
            for f in faces:
                f.material_index = idx
                f.smooth = smooth
            bmesh.ops.recalc_face_normals(bm, faces=faces)

    def loft(self, rings, mat, lods=ALL, closed=True, cap=True, smooth=False, flip=False, recalc=False):
        """Faces between consecutive rings of 3D points (same count per ring). Face
        orientation follows the ring order (flip reverses it); recalc asks bmesh to
        orient the faces (only reliable on closed, non-degenerate shapes)."""
        for i in lods:
            bm, idx = self.bms[i], self._slot(i, mat)
            vr = [[bm.verts.new(Vector(p)) for p in r] for r in rings]
            n = len(rings[0])
            faces = []
            for a, b in zip(vr[:-1], vr[1:]):
                for k in range(n if closed else n - 1):
                    faces.append(bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k])))
            if cap and closed:
                faces.append(bm.faces.new(list(reversed(vr[0]))))
                faces.append(bm.faces.new(vr[-1]))
            for f in faces:
                f.material_index = idx
                f.smooth = smooth
                if flip:
                    f.normal_flip()
            if recalc:
                bmesh.ops.recalc_face_normals(bm, faces=faces)

    def poly(self, verts, faces, mat, lods=ALL, uvs=None, smooth=False):
        """Raw polygons. uvs: optional per-face list of per-loop (u, v) (authored UVs)."""
        for i in lods:
            bm, idx = self.bms[i], self._slot(i, mat)
            vs = [bm.verts.new(Vector(p)) for p in verts]
            for fi, f in enumerate(faces):
                face = bm.faces.new([vs[k] for k in f])
                face.material_index = idx
                face.smooth = smooth
                if uvs is not None:
                    self.uv_faces[i][face] = uvs[fi]

    def quad_uv(self, corners, uv_rect, mat="Signs", lods=ALL, double=False):
        """A textured quad (4 corners CCW seen from the front) mapped to an atlas rect
        (u0, v0, u1, v1). double: adds the back face mapped the same way."""
        u0, v0, u1, v1 = uv_rect
        uv = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
        self.poly(corners, [(0, 1, 2, 3)], mat, lods, uvs=[uv])
        if double:
            self.poly(list(reversed(corners)), [(0, 1, 2, 3)], mat, lods, uvs=[list(reversed(uv))])

    def sign(self, pts01, origin, right, up, w, h, uv_rect, mat="Signs", lods=ALL, back_mat=None, thick=0.0):
        """A flat sign of size w x h: pts01 is its outline in [0, 1]^2 (CCW seen from the
        front, (0, 0) bottom-left), mapped onto atlas rect uv_rect. The face looks along
        right x up. back_mat: optional plain back face (e.g. galvanized) offset by thick."""
        o, r, u = Vector(origin), Vector(right).normalized(), Vector(up).normalized()
        u0, v0, u1, v1 = uv_rect
        verts = [o + r * ((x - 0.5) * w) + u * ((y - 0.5) * h) for x, y in pts01]
        uvs = [(u0 + (u1 - u0) * x, v0 + (v1 - v0) * y) for x, y in pts01]
        self.poly([tuple(v) for v in verts], [tuple(range(len(verts)))], mat, lods, uvs=[uvs])
        if back_mat:
            n = r.cross(u).normalized()
            back = [tuple(v - n * thick) for v in reversed(verts)]
            self.poly(back, [tuple(range(len(back)))], back_mat, lods)
            if thick > 0:
                k = len(verts)
                for i in range(k):
                    a, b = verts[i], verts[(i + 1) % k]
                    self.poly([tuple(b), tuple(a), tuple(a - n * thick), tuple(b - n * thick)], [(0, 1, 2, 3)], back_mat, lods)

    # ------------------------------------------------------------------ data

    def col_box(self, size, center, yaw=0.0):
        self.cols.append((tuple(size), tuple(center), float(yaw)))

    def col_between(self, lo, hi):
        lo, hi = Vector(lo), Vector(hi)
        self.col_box(tuple(hi - lo), tuple((lo + hi) / 2))

    def marker(self, name, pos, yaw=0.0, note=""):
        self.markers.append({"name": name, "pos": [round(c, 4) for c in pos], "yaw": yaw, "note": note})

    def skirt(self, x0, y0, x1, y1, depth, mat="Concrete", top=0.05, lods=ALL):
        """Foundation / skirt reaching below the ground (hides the terrain-fit gap)."""
        self.foundation = max(self.foundation, depth)
        self.box_between((x0, y0, -depth), (x1, y1, top), mat, lods)

    # ------------------------------------------------------------------ build

    # Area share below which a material is merged into the dominant one, per LOD.
    MERGE_SHARE = (0.0, 0.015, 0.08)

    def _consolidate(self, i):
        """Folds palette materials into Kit_Palette (UV = swatch centre) and, on LOD1/2,
        merges materials with a small area share into the largest material."""
        bm = self.bms[i]
        names = self.slots[i]
        auth = self.uv_faces[i]
        area = {}
        for f in bm.faces:
            nm = names[f.material_index]
            if nm in AM.PALETTE:
                auth[f] = [AM.palette_uv(nm)] * len(f.loops)
                nm = "Kit_Palette"
            area[nm] = area.get(nm, 0.0) + f.calc_area()
        total = sum(area.values()) or 1.0
        merge = {}
        if self.MERGE_SHARE[i] > 0:
            textured = [k for k in area if not AM.keeps_uv(k)]
            if textured:
                main = max(textured, key=lambda k: area[k])
                for k in textured:
                    if k != main and area[k] / total < self.MERGE_SHARE[i]:
                        merge[k] = main
        new = []
        for f in bm.faces:
            nm = names[f.material_index]
            nm = "Kit_Palette" if nm in AM.PALETTE else merge.get(nm, nm)
            if nm not in new:
                new.append(nm)
            f.material_index = new.index(nm)
        self.slots[i] = new

    @staticmethod
    def _orient_closed_islands(bm):
        """BLENDER-SKILLS-01: every closed (watertight) connected part gets outward-facing,
        consistently wound faces. Primitives are built from many small shells (boxes, lofts,
        prisms, roofs) whose winding depended on the construction frame; the QA gate found
        inside-out shells in half the library. Open parts (signs, decals, single sheets) are
        left alone: their facing is authored."""
        bm.verts.ensure_lookup_table()
        parent = list(range(len(bm.verts)))

        def find(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i
        for e in bm.edges:
            a, b = find(e.verts[0].index), find(e.verts[1].index)
            if a != b:
                parent[a] = b
        open_islands = {find(e.verts[0].index) for e in bm.edges if len(e.link_faces) != 2}
        faces = [f for f in bm.faces if find(f.verts[0].index) not in open_islands]
        if faces:
            bmesh.ops.recalc_face_normals(bm, faces=faces)

    def build(self, coll, tex_dir):
        objs = []
        for i in ALL:
            bm = self.bms[i]
            if bm.faces:
                self._orient_closed_islands(bm)
        for i in ALL:
            bm = self.bms[i]
            if not bm.faces:
                objs.append(None)
                continue
            self._consolidate(i)
            uvl = bm.loops.layers.uv.new("UVMap")
            col = bm.loops.layers.color.new("Col")
            names = self.slots[i]
            auth = self.uv_faces[i]
            zmin = min(v.co.z for v in bm.verts)
            for f in bm.faces:
                mname = names[f.material_index] if f.material_index < len(names) else ""
                if f in auth and f.is_valid:
                    for li, loop in enumerate(f.loops):
                        loop[uvl].uv = auth[f][li % len(auth[f])]
                else:
                    t = AM.tile_of(mname)
                    n = f.normal
                    ax = max(range(3), key=lambda k: abs(n[k]))
                    for loop in f.loops:
                        co = loop.vert.co
                        if ax == 0:
                            u, v = co.y * (1 if n.x > 0 else -1), co.z
                        elif ax == 1:
                            u, v = co.x * (-1 if n.y > 0 else 1), co.z
                        else:
                            u, v = co.x, co.y * (1 if n.z > 0 else -1)
                        loop[uvl].uv = (u / t, v / t)
                for loop in f.loops:
                    z = max(loop.vert.co.z, 0.0)
                    k = 1.0 - self.ao_strength * (1.0 - min(z / self.ao_height, 1.0)) ** 1.6
                    loop[col] = (k, k * 0.985, k * 0.96, 1.0)
            name = "%s_LOD%d" % (self.id, i)
            obj = L.new_object(name, bm, coll, [AM.blender_material(m, tex_dir) for m in names])
            obj.data.color_attributes.active_color_name = "Col"
            obj.data.color_attributes.render_color_index = obj.data.color_attributes.active_color_index
            L.shade_smooth(obj, 32)
            objs.append(obj)
        self.objs = objs
        return objs

    # ------------------------------------------------------------------ export

    def export(self, out_dir, coll):
        os.makedirs(out_dir, exist_ok=True)
        extra = []
        for k, (size, c, yaw) in enumerate(self.cols):
            bm = bmesh.new()
            L.bm_box(bm, size, Vector(c), rot=rot_z(yaw) if yaw else None)
            o = L.new_object("COL_%d-convcolonly" % k, bm, coll)
            extra.append(o)
        for m in self.markers:
            e = bpy.data.objects.new(m["name"], None)
            e.empty_display_size = 0.25
            e.location = m["pos"]
            e.rotation_euler = (0, 0, math.radians(m["yaw"]))
            coll.objects.link(e)
            extra.append(e)
        lods = [o for o in self.objs if o is not None]
        path = os.path.join(out_dir, self.id + ".glb")
        bpy.ops.object.select_all(action="DESELECT")
        for o in lods + extra:
            o.hide_set(False)
            o.select_set(True)
        bpy.context.view_layer.objects.active = lods[0]
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True, export_materials="EXPORT", export_image_format="NONE",
                                  export_normals=True, export_texcoords=True, export_tangents=True,
                                  export_vertex_color="NAME", export_vertex_color_name="Col", export_all_vertex_colors=False,
                                  export_animations=False, export_cameras=False, export_lights=False,
                                  export_extras=False, export_skins=False)
        for o in extra:
            bpy.data.objects.remove(o, do_unlink=True)
        meta = self.metadata()
        with open(os.path.join(out_dir, self.id + ".json"), "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=1)
        write_glb_import(path)
        meta["glb_bytes"] = os.path.getsize(path)
        return meta

    def bounds(self, lod=0):
        o = self.objs[lod]
        vs = [o.matrix_world @ v.co for v in o.data.vertices]
        lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
        hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
        return lo, hi

    def metadata(self):
        lo, hi = self.bounds(0)
        above = Vector((lo.x, lo.y, max(lo.z, 0.0)))
        tris = [L.tri_count(o) if o else 0 for o in self.objs]
        surf = [len(o.data.materials) if o else 0 for o in self.objs]
        mats = sorted({m.name for o in self.objs if o for m in o.data.materials})
        fp = self.meta.get("footprint") or [round(lo.x, 3), round(lo.y, 3), round(hi.x, 3), round(hi.y, 3)]
        return {
            "id": self.id, "family": self.family, "display_name": self.display_name, "category": self.category,
            "description": self.description,
            "bounds_min": [round(c, 3) for c in lo], "bounds_max": [round(c, 3) for c in hi],
            "size_above_ground": [round(hi.x - lo.x, 3), round(hi.y - lo.y, 3), round(hi.z - above.z, 3)],
            "footprint_xy": fp, "foundation_depth": round(self.foundation, 3),
            "tris": tris, "surfaces": surf, "materials": mats, "lod_ranges": self.lod_ranges,
            "collision_boxes_godot": [box_to_godot(s, c, y) for s, c, y in self.cols],
            "markers": self.markers, "structure": self.structure, **{k: v for k, v in self.meta.items() if k != "footprint"},
        }


def box_to_godot(size, center, yaw=0.0):
    """Blender box (size, centre, yaw about Z) -> Godot AABB [x, y, z, sx, sy, sz] of its
    axis-aligned bounds (Blender (x, y, z) = Godot (x, z, -y))."""
    sx, sy, sz = size
    if yaw:
        a = math.radians(yaw)
        sx, sy = abs(sx * math.cos(a)) + abs(sy * math.sin(a)), abs(sx * math.sin(a)) + abs(sy * math.cos(a))
    cx, cy, cz = center
    return [round(cx - sx / 2, 4), round(cz - sz / 2, 4), round(-cy - sy / 2, 4), round(sx, 4), round(sz, 4), round(sy, 4)]


POST_IMPORT = "res://tools/asset_lab/ap_post_import.gd"

GLB_IMPORT = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=false
import_script/path="{script}"
materials/extract=0
_subresources={{}}
gltf/naming_version=2
gltf/embedded_image_handling=1
"""


def write_glb_import(glb_path):
    """New GLBs get an .import that runs the library post-import script; existing
    .import files only get the script path patched (keeps their uid)."""
    imp = glb_path + ".import"
    if os.path.exists(imp):
        with open(imp, encoding="utf-8") as f:
            txt = f.read()
        lines = [('import_script/path="%s"' % POST_IMPORT) if ln.startswith("import_script/path=") else ln for ln in txt.split("\n")]
        txt = "\n".join(lines)
    else:
        txt = GLB_IMPORT.format(script=POST_IMPORT)
    with open(imp, "w", encoding="utf-8") as f:
        f.write(txt)


# ---------------------------------------------------------------------- StructureDef data


def write_structure_def(meta, def_dir, glb_res_path):
    """A StructureDef .tres (scripts/construction/structure_def.gd) with the asset's
    numbers, so the construction system can register the asset as data. Writing it does
    not register it anywhere; see docs/ASSET-PRODUCTION-01_REPORT.md (integration)."""
    s = meta.get("structure") or {}
    lo, hi = meta["bounds_min"], meta["bounds_max"]
    size = (hi[0] - lo[0], hi[2] - max(lo[2], 0), hi[1] - lo[1])
    boxes = meta["collision_boxes_godot"]
    os.makedirs(def_dir, exist_ok=True)
    aabbs = ", ".join("AABB(%g, %g, %g, %g, %g, %g)" % tuple(b) for b in boxes)
    ramps = ", ".join("AABB(%g, %g, %g, %g, %g, %g)" % tuple(b) for b in s.get("ramps_godot", []))
    txt = ('[gd_resource type="Resource" script_class="StructureDef" load_steps=2 format=3]\n\n'
           '[ext_resource type="Script" path="res://scripts/construction/structure_def.gd" id="1_def"]\n\n'
           "[resource]\nscript = ExtResource(\"1_def\")\n"
           'id = &"%s"\ndisplay_name = "%s"\ncategory = "%s"\ndescription = "%s"\nmesh_path = "%s"\n'
           "size = Vector3(%g, %g, %g)\nmax_slope_deg = %g\nmax_ground_gap = %g\nsink = %g\nblocks_navigation = %s\n%s"
           "collision_boxes = Array[AABB]([%s])\nramps = Array[AABB]([%s])\n") % (
        meta["id"], meta["display_name"], s.get("category", meta["category"] or "Buildings"),
        meta["description"].replace('"', "'"), glb_res_path, round(size[0], 3), round(size[1], 3), round(size[2], 3),
        s.get("max_slope_deg", 7.0), s.get("max_ground_gap", round(meta["foundation_depth"] * 2, 2) or 0.4),
        s.get("sink", 0.05), "true" if s.get("blocks_navigation", True) else "false",
        # WORLD-INTEGRATION-03: no collision body / nav obstacle at all (pads, wire, tyre runs).
        "walkable = true\n" if s.get("walkable") else "", aabbs, ramps)
    with open(os.path.join(def_dir, meta["id"] + ".tres"), "w", encoding="utf-8") as f:
        f.write(txt)


# ---------------------------------------------------------------------- previews


def preview_ground(size, tex_dir):
    g = bpy.data.objects.get("PreviewGround")
    if g:
        bpy.data.objects.remove(g, do_unlink=True)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=size / 2)
    g = L.new_object("PreviewGround", bm, bpy.context.scene.collection, [AM.blender_material("Dirt", tex_dir)])
    uv = g.data.uv_layers.new(name="UVMap")
    for li, loop in enumerate(g.data.loops):
        co = g.data.vertices[loop.vertex_index].co
        uv.data[li].uv = (co.x / 4.0, co.y / 4.0)
    col = g.data.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for d in col.data:
        d.color = (1, 1, 1, 1)
    g.location.z = -0.002
    return g


def render_asset(asset, out_dir, tex_dir, views=None, res=(960, 720), lod=0, tag=None):
    """Renders a set of views of one LOD. views: [(suffix, azimuth, elevation, dist_factor, target_z_factor)]."""
    L.setup_render(res, samples=24)
    use_jpeg()
    sc = bpy.context.scene
    sc.view_settings.look = "AgX - Base Contrast"
    old = bpy.data.objects.get("PreviewGround")
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    for i, o in enumerate(asset.objs):
        if o:
            o.hide_render = i != lod
            o.hide_set(i != lod)
    lo, hi = asset.bounds(lod)
    lo.z = max(lo.z, 0.0)
    ext = hi - lo
    radius = max(ext.length * 0.5, 0.3)
    preview_ground(max(radius * 10, 20), tex_dir)
    centre = (lo + hi) / 2
    views = views or [("q34", 35, 22, 1.0, 0.45), ("back", 215, 18, 1.0, 0.45), ("low", 70, 4, 0.75, 0.35), ("top", 0, 88, 1.15, 0.0)]
    paths = []
    for suffix, az, el, df, tz in views:
        t = Vector((centre.x, centre.y, lo.z + ext.z * tz))
        dist = radius / math.tan(math.radians(17)) * df
        p = os.path.join(out_dir, "%s_%s.jpg" % (tag or asset.id, suffix))
        L.render_view(p, tuple(t), dist, az, el, lens=50)
        paths.append(p)
    for o in asset.objs:
        if o:
            o.hide_render = False
            o.hide_set(False)
    return paths


def render_lod_strip(asset, out_dir, tex_dir, res=(640, 560)):
    """LOD0 / LOD1 / LOD2 from the same three-quarter view, side by side."""
    shots = []
    for i, o in enumerate(asset.objs):
        if o is None:
            continue
        shots += render_asset(asset, out_dir, tex_dir, views=[("lod%d" % i, 35, 22, 1.0, 0.45)], res=res, lod=i)
    return sheet(shots, os.path.join(out_dir, "%s_lods.jpg" % asset.id), len(shots))


def use_jpeg(quality=90):
    st = bpy.context.scene.render.image_settings
    st.file_format = "JPEG"
    st.quality = quality


def sheet(paths, out, cols, delete=True, quality=88):
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
        r = rows - 1 - r                 # Blender pixel rows start at the bottom
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


def circle01(n=24):
    return [(0.5 + 0.5 * math.cos(2 * math.pi * k / n), 0.5 + 0.5 * math.sin(2 * math.pi * k / n)) for k in range(n)]


def ngon01(n, rot=0.0):
    return [(0.5 + 0.5 * math.cos(rot + 2 * math.pi * k / n), 0.5 + 0.5 * math.sin(rot + 2 * math.pi * k / n)) for k in range(n)]


RECT01 = [(0, 0), (1, 0), (1, 1), (0, 1)]
TRI_DOWN01 = [(0.5, 0.02), (0.98, 0.89), (0.02, 0.89)]
TRI_UP01 = [(0.03, 0.12), (0.97, 0.12), (0.5, 0.95)]
