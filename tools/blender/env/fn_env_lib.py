"""Helpers for the WORLD-TERRAIN-01 environment assets (Blender 5.2, bpy + bmesh).

Conventions (same as tools/blender/fn_blender_lib.py): 1 unit = 1 m, Z up, origin at the
ground contact point, one object per LOD named <Asset>_LOD<n>. Materials use image textures
from assets/environment/textures so the glTF export carries them; the Godot import script
(tools/terrain_ref/import_env_assets.gd) replaces them with project materials by name.

Geometry is built with bmesh from explicit parameters and a seeded random generator, so
every asset is reproducible from its script.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

TEX_DIR = ""


def set_tex_dir(path):
    global TEX_DIR
    TEX_DIR = path


def clear_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.lights, bpy.data.cameras,
                 bpy.data.worlds):
        for block in list(coll):
            if block.users == 0:
                coll.remove(block)


# ------------------------------------------------------------------ materials
def image_material(name, albedo, normal=None, alpha=False, roughness=0.85, color=(1, 1, 1)):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(TEX_DIR, albedo), check_existing=True)
    if color != (1, 1, 1):
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs[7].default_value = (color[0], color[1], color[2], 1.0)
        nt.links.new(tex.outputs["Color"], mix.inputs[6])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    else:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        try:
            mat.blend_method = "CLIP"
        except Exception:
            pass
        mat.use_backface_culling = False
        try:
            mat.surface_render_method = "DITHERED"
        except Exception:
            pass
    if normal:
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt_ = nt.nodes.new("ShaderNodeTexImage")
        img = bpy.data.images.load(os.path.join(TEX_DIR, normal), check_existing=True)
        img.colorspace_settings.name = "Non-Color"
        nt_.image = img
        nt.links.new(nt_.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def flat_material(name, rgb, roughness=0.85, metallic=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    mat.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    return mat


# ------------------------------------------------------------------ mesh building
class MeshBuilder:
    """Accumulates geometry per material slot in one bmesh, with UVs and vertex colours."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.col = self.bm.loops.layers.color.new("Col")
        self.mats = []

    def slot(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def face(self, verts, uvs, mat, cols=None):
        vs = [self.bm.verts.new(v) for v in verts]
        f = self.bm.faces.new(vs)
        f.material_index = self.slot(mat)
        for i, loop in enumerate(f.loops):
            loop[self.uv].uv = uvs[i]
            c = cols[i] if cols else (1, 1, 1)
            loop[self.col] = (c[0], c[1], c[2], 1.0)
        return f

    def tube(self, pts, radii, sides, mat, uv_u=1.0, uv_v_m=2.0, v0=0.0, cap=True, col=(1, 1, 1),
             col_end=None, twist=0.0):
        """Tapered tube along pts (list of Vector) with per-point radii. UV: u around
        (uv_u repeats), v = distance / uv_v_m (bark texture height in metres)."""
        n = len(pts)
        rings = []
        # Parallel-transport frame.
        t0 = (pts[1] - pts[0]).normalized()
        ref = Vector((0, 0, 1)) if abs(t0.z) < 0.9 else Vector((1, 0, 0))
        nrm = t0.cross(ref).normalized()
        dist = v0
        prev_t = t0
        for i in range(n):
            if i == 0:
                t = t0
            elif i == n - 1:
                t = (pts[i] - pts[i - 1]).normalized()
            else:
                t = (pts[i + 1] - pts[i - 1]).normalized()
            # Rotate normal to stay perpendicular.
            axis = prev_t.cross(t)
            if axis.length > 1e-6:
                ang = prev_t.angle(t)
                nrm = (Matrix.Rotation(ang, 3, axis.normalized()) @ nrm).normalized()
            prev_t = t
            bin_ = t.cross(nrm).normalized()
            if i > 0:
                dist += (pts[i] - pts[i - 1]).length
            ring = []
            for k in range(sides + 1):
                a = 2 * math.pi * k / sides + twist * i
                d = nrm * math.cos(a) + bin_ * math.sin(a)
                ring.append((pts[i] + d * radii[i], (k / sides * uv_u, dist / uv_v_m)))
            rings.append(ring)
        cA = col
        cB = col_end or col
        for i in range(n - 1):
            ci = [cA[j] + (cB[j] - cA[j]) * i / (n - 1) for j in range(3)]
            cj = [cA[j] + (cB[j] - cA[j]) * (i + 1) / (n - 1) for j in range(3)]
            for k in range(sides):
                a, b = rings[i][k], rings[i][k + 1]
                c, d = rings[i + 1][k + 1], rings[i + 1][k]
                self.face([a[0], b[0], c[0], d[0]], [a[1], b[1], c[1], d[1]], mat, [ci, ci, cj, cj])
        if cap and radii[-1] > 0.004:
            ring = rings[-1][:-1]
            self.face([p[0] for p in ring], [(0.5 + 0.5 * math.cos(2 * math.pi * k / sides),
                                              0.5 + 0.5 * math.sin(2 * math.pi * k / sides)) for k in range(sides)],
                      mat, [cB] * sides)

    def card(self, base, up, side, width, height, mat, col=(1, 1, 1), col_top=None, uv=(0, 0, 1, 1)):
        """Quad from base (bottom centre) extending along `up` by height, `side` by width."""
        up = up.normalized() * height
        sd = side.normalized() * width * 0.5
        p0 = base - sd
        p1 = base + sd
        p2 = base + sd + up
        p3 = base - sd + up
        ct = col_top or col
        u0, v0, u1, v1 = uv
        self.face([p0, p1, p2, p3], [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], mat, [col, col, ct, ct])

    def finish(self, smooth=True):
        me = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        if smooth:
            for p in me.polygons:
                p.use_smooth = True
        return ob


def foliage_normals(ob, center, blend=0.65):
    """Bends the normals of alpha cards toward 'away from the crown centre' so the crown
    shades like a volume instead of flat planes (custom split normals, exported)."""
    me = ob.data
    normals = []
    for loop in me.loops:
        v = me.vertices[loop.vertex_index].co
        poly_n = None
        normals.append(loop)
    custom = []
    for poly in me.polygons:
        mat = me.materials[poly.material_index]
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            if mat and mat.name.startswith(("Needles", "Leaves", "Foliage")):
                radial = (v - center)
                radial.z *= 0.6
                n = (poly.normal * (1 - blend) + radial.normalized() * blend).normalized()
            else:
                n = me.loops[li].normal.copy() if hasattr(me.loops[li], "normal") else poly.normal
            custom.append(n)
    me.normals_split_custom_set(custom)


# ------------------------------------------------------------------ rendering / export
def setup_world(strength=1.0, color=(0.62, 0.70, 0.82)):
    w = bpy.data.worlds.get("PreviewWorld") or bpy.data.worlds.new("PreviewWorld")
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (color[0], color[1], color[2], 1)
    bg.inputs["Strength"].default_value = strength
    bpy.context.scene.world = w


def add_sun(rot=(math.radians(50), 0, math.radians(35)), energy=3.0):
    for ob in [o for o in bpy.data.objects if o.name.startswith("PreviewSun")]:
        bpy.data.objects.remove(ob, do_unlink=True)
    sun = bpy.data.lights.new("PreviewSun", "SUN")
    sun.energy = energy
    sun.angle = math.radians(3)
    ob = bpy.data.objects.new("PreviewSun", sun)
    ob.rotation_euler = rot
    bpy.context.scene.collection.objects.link(ob)
    return ob


def ground_plane(size=40, rgb=(0.28, 0.30, 0.18)):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
    ob = bpy.context.active_object
    ob.name = "PreviewGround"
    ob.data.materials.append(flat_material("PreviewGroundMat", rgb, 1.0))
    return ob


def render_views(objs, out_path, size=(900, 1000), views=((35, 8), (125, 8), (35, 55)), height=None, engine="BLENDER_EEVEE"):
    """Renders the objects from several azimuth/elevation pairs side by side into one PNG."""
    sc = bpy.context.scene
    sc.render.engine = engine
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "AgX" if "AgX" in [v for v in ("AgX",)] else "Standard"
    try:
        sc.eevee.taa_render_samples = 32
    except Exception:
        pass
    # Bounds.
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for ob in objs:
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
            mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    center = (mn + mx) * 0.5
    ext = (mx - mn).length
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam_data.lens = 50
    tmp = []
    for i, (az, el) in enumerate(views):
        a = math.radians(az)
        e = math.radians(el)
        d = ext * 1.45
        pos = center + Vector((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e))) * d
        cam.location = pos
        cam.rotation_euler = (center - pos).to_track_quat("-Z", "Y").to_euler()
        p = out_path.replace(".png", "_v%d.png" % i)
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        tmp.append(p)
    bpy.data.objects.remove(cam, do_unlink=True)
    return tmp


def render_impostor(objs, out_path, px=(512, 1024), height=None, width=None, azimuth=0.0):
    """Orthographic, flat-lit albedo render of the asset from the side with transparent
    background: the texture of the far-LOD cross cards. Returns (width_m, height_m)."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.film_transparent = True
    sc.render.resolution_x, sc.render.resolution_y = px
    sc.render.image_settings.color_mode = "RGBA"
    sc.display_settings.display_device = "sRGB"
    sc.view_settings.view_transform = "Standard"
    try:
        sc.display.render_aa = "16"
    except Exception:
        pass
    mx_z = max((ob.matrix_world @ Vector(c)).z for ob in objs for c in ob.bound_box)
    h = height or mx_z
    w = width or h * px[0] / px[1]
    cam_data = bpy.data.cameras.new("ImpCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = max(h, w)
    cam = bpy.data.objects.new("ImpCam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    a = math.radians(azimuth)
    cam.location = Vector((math.sin(a) * -60, math.cos(a) * -60, h * 0.5))
    cam.rotation_euler = (Vector((0, 0, h * 0.5)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    sc.render.film_transparent = False
    return w, h


def render_impostor_top(objs, out_path, half_w, px=512):
    """Orthographic flat-lit albedo render looking straight down (top-view impostor)."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = px
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    cam_data = bpy.data.cameras.new("ImpTopCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = half_w * 2.0
    cam_data.clip_end = 500.0
    cam = bpy.data.objects.new("ImpTopCam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.location = Vector((0, 0, 200))
    cam.rotation_euler = (0, 0, 0)
    sc.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    sc.render.film_transparent = False


def export_glb(objs, path, materials="EXPORT"):
    """materials: EXPORT (with images) or NAMES (materials without images - the Godot import binds project textures by
    material name; glTF's own PLACEHOLDER mode drops the names)."""
    images = "NONE" if materials == "NAMES" else "AUTO"
    materials = "EXPORT" if materials == "NAMES" else materials
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_texcoords=True, export_normals=True,
                              export_vertex_color="ACTIVE", export_all_vertex_colors=False,
                              export_materials=materials, export_image_format=images)


def stats(ob):
    me = ob.data
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    return {"name": ob.name, "verts": len(me.vertices), "tris": tris}
