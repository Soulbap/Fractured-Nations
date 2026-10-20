"""Shared helpers for the CHARACTER-01 infantry pipeline (Blender 5.2, bpy + numpy).

Conventions (see docs/CHARACTER_STANDARD.md):
  - 1 unit = 1 m, Z up, the character FACES +Y and stands on z = 0 at the origin.
    The character's LEFT side is -X. glTF export maps Blender +Y to Godot -Z (forward).
  - Every mesh is built in place on the rest pose (A-pose) in character space.
  - Textures are generated with numpy, written as PNG into assets/characters/infantry/textures,
    and shared between pieces through a small set of named materials.
"""
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

# --------------------------------------------------------------------------------------
# Scene


def clear_scene():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.lights, bpy.data.cameras,
                 bpy.data.armatures, bpy.data.actions, bpy.data.node_groups, bpy.data.curves):
        for block in list(coll):
            coll.remove(block)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)


def collection(name, parent=None):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(c)
    return c


def link(obj, coll):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    coll.objects.link(obj)
    return obj


def activate(obj):
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


# --------------------------------------------------------------------------------------
# Mesh building with bmesh


def new_object(name, bm, coll, mats=()):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    coll.objects.link(obj)
    for m in mats:
        me.materials.append(m)
    return obj


def bm_from(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    return bm


def bm_box(bm, size, center, mat=0, rot=None):
    """Adds a box (size xyz) to bm, optionally rotated (Matrix 3x3). Returns its verts."""
    r = bmesh.ops.create_cube(bm, size=1.0)
    vs = r["verts"]
    m = Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    if rot is not None:
        m = rot.to_4x4() @ m
    m = Matrix.Translation(center) @ m
    bmesh.ops.transform(bm, matrix=m, verts=vs)
    for f in {f for v in vs for f in v.link_faces}:
        f.material_index = mat
    return vs


def bm_cyl(bm, r1, r2, depth, center, axis=(0, 0, 1), segs=12, mat=0, cap=True):
    res = bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=depth)
    vs = res["verts"]
    rot = Vector((0, 0, 1)).rotation_difference(Vector(axis).normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(center) @ rot, verts=vs)
    for f in {f for v in vs for f in v.link_faces}:
        f.material_index = mat
    return vs


def bm_sphere(bm, radius, center, scale=(1, 1, 1), segs=16, rings=10, mat=0):
    res = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius)
    vs = res["verts"]
    m = Matrix.Translation(center) @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
    bmesh.ops.transform(bm, matrix=m, verts=vs)
    for f in {f for v in vs for f in v.link_faces}:
        f.material_index = mat
    return vs


def rounded_box(bm, size, center, radius, mat=0, rot=None, segs=2):
    """Box with bevelled edges (radius in m)."""
    before = set(bm.faces)
    vs = bm_box(bm, size, center, mat, rot)
    edges = list({e for v in vs for e in v.link_edges})
    bmesh.ops.bevel(bm, geom=edges + vs, offset=radius, segments=segs, profile=0.5, affect="EDGES", clamp_overlap=True)
    new = [f for f in bm.faces if f not in before]
    for f in new:
        f.material_index = mat
    return list({v for f in new for v in f.verts})


def tube_along(bm, points, radii, segs=10, mat=0, cap=True, flat=1.0, up=Vector((0, 0, 1))):
    """Lofted tube through points with per-point radius (radii scalar or (rx, ry))."""
    rings = []
    n = len(points)
    for i, p in enumerate(points):
        p = Vector(p)
        d = (Vector(points[min(i + 1, n - 1)]) - Vector(points[max(i - 1, 0)])).normalized()
        side = d.cross(up)
        if side.length < 1e-4:
            side = d.cross(Vector((0, 1, 0)))
        side.normalize()
        upv = side.cross(d).normalized()
        r = radii[i]
        rx, ry = (r, r * flat) if not isinstance(r, (tuple, list)) else r
        ring = []
        for s in range(segs):
            a = 2 * math.pi * s / segs
            ring.append(bm.verts.new(p + side * math.cos(a) * rx + upv * math.sin(a) * ry))
        rings.append(ring)
    faces = []
    for i in range(n - 1):
        for s in range(segs):
            a, b = rings[i][s], rings[i][(s + 1) % segs]
            c, d2 = rings[i + 1][(s + 1) % segs], rings[i + 1][s]
            faces.append(bm.faces.new((a, b, c, d2)))
    if cap:
        faces.append(bm.faces.new(list(reversed(rings[0]))))
        faces.append(bm.faces.new(rings[-1]))
    for f in faces:
        f.material_index = mat
    return [v for r in rings for v in r]


def shade_smooth(obj, angle_deg=40.0):
    for p in obj.data.polygons:
        p.use_smooth = True
    try:
        activate(obj)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle_deg), keep_sharp_edges=True)
    except Exception:
        pass


def apply_modifiers(obj):
    activate(obj)
    for m in list(obj.modifiers):
        if m.type == "ARMATURE":
            continue
        bpy.ops.object.modifier_apply(modifier=m.name)


def add_subsurf(obj, levels=1):
    m = obj.modifiers.new("Subsurf", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    return m


def join(objs, name):
    activate(objs[0])
    for o in objs[1:]:
        o.select_set(True)
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = name
    o.data.name = name
    return o


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def displace_verts(obj, fn, mask=None):
    """fn(co: Vector) -> Vector offset, applied to all (or masked) vertices."""
    me = obj.data
    for v in me.vertices:
        if mask is None or mask(v.co):
            v.co = v.co + fn(v.co.copy())
    me.update()


# --------------------------------------------------------------------------------------
# UVs


def box_uv(obj, tile_m=0.75, rotate_by_normal=True, layer=None):
    """World-scale box projection: 1 UV unit = tile_m metres. Good for tileable fabric/camo."""
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    mw = obj.matrix_world
    nm = mw.to_3x3().inverted().transposed()
    for p in me.polygons:
        n = (nm @ p.normal).normalized()
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in p.loop_indices:
            co = mw @ me.vertices[me.loops[li].vertex_index].co
            if ax == 0:
                u, v = co.y * math.copysign(1, n.x), co.z
            elif ax == 1:
                u, v = -co.x * math.copysign(1, n.y), co.z
            else:
                u, v = co.x, co.y * math.copysign(1, n.z)
            uv[li].uv = (u / tile_m, v / tile_m)


def cylinder_uv(obj, axis_center=(0, 0), tile_m=0.75):
    """Cylindrical projection around Z (for torso/legs garments): seam at the back."""
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    for p in me.polygons:
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            a = math.atan2(co.x - axis_center[0], co.y - axis_center[1])
            uv[li].uv = (a * 0.16 / tile_m, co.z / tile_m)


# --------------------------------------------------------------------------------------
# Textures (numpy) and materials


def _fft_noise(n, scale_px, seed, aniso=(1.0, 1.0)):
    """Tileable band-limited noise in [0,1] (gaussian filtered white noise via FFT)."""
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((n, n))
    fy = np.fft.fftfreq(n)[:, None] * aniso[1]
    fx = np.fft.fftfreq(n)[None, :] * aniso[0]
    sigma = 1.0 / max(scale_px, 1e-3)
    filt = np.exp(-(fx ** 2 + fy ** 2) / (2 * (sigma * 0.5) ** 2))
    r = np.real(np.fft.ifft2(np.fft.fft2(w) * filt))
    r = (r - r.min()) / (r.max() - r.min() + 1e-9)
    return r


def fbm(n, base_px, octaves, seed, gain=0.5, aniso=(1.0, 1.0)):
    acc = np.zeros((n, n))
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        acc += amp * _fft_noise(n, base_px / (2 ** o), seed + o * 17, aniso)
        tot += amp
        amp *= gain
    return acc / tot


def save_png(path, rgb, alpha=None):
    """rgb: HxWx3 float 0..1 (sRGB-encoded values). Row 0 = top of the image."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    h, w = rgb.shape[:2]
    name = os.path.basename(path)
    img = bpy.data.images.get(name)
    if img is not None:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name, w, h, alpha=alpha is not None)
    a = alpha if alpha is not None else np.ones((h, w))
    px = np.dstack([np.clip(rgb, 0, 1), np.clip(a, 0, 1)])[::-1].astype(np.float32)
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


def normal_from_height(h, strength):
    """Tileable tangent-space normal map (OpenGL convention, +Y up) from a height field."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(h, 1, axis=0) - np.roll(h, -1, axis=0)) * 0.5 * strength
    nz = np.ones_like(h)
    l = np.sqrt(dx * dx + dy * dy + nz * nz)
    n = np.dstack([-dx / l, -dy / l, nz / l])
    return n * 0.5 + 0.5


def load_image(path, non_color=False):
    name = os.path.basename(path)
    img = bpy.data.images.get(name)
    if img is None:
        img = bpy.data.images.load(path)
    img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    return img


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def pbr_material(name, color=(0.5, 0.5, 0.5), roughness=0.8, metallic=0.0, albedo=None, normal=None,
                 normal_strength=1.0, rough_map=None, alpha=None, emission=None):
    """Principled material; image paths are optional. Godot reads base colour, normal,
    roughness and metallic from the glTF; the loader replaces them with shared .tres
    materials of the same name anyway (see scripts/characters/infantry_materials.gd)."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    color = tuple(srgb_to_linear(c) for c in color)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    mat.diffuse_color = (*color, 1.0)
    if albedo:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = load_image(albedo)
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs[6].default_value = (*color, 1.0)
        nt.links.new(tex.outputs["Color"], mix.inputs[7])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    if normal:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = load_image(normal, non_color=True)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = normal_strength
        nt.links.new(tex.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if alpha is not None:
        bsdf.inputs["Alpha"].default_value = alpha
        mat.surface_render_method = "BLENDED"
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.0
    mat["fn_roughness"] = roughness
    return mat


# --------------------------------------------------------------------------------------
# Skinning helpers


def parent_to_armature(obj, arm, auto=True):
    activate(obj)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO" if auto else "ARMATURE_NAME")


def bind_rigid(obj, arm, bone):
    """Skins every vertex of obj 100% to one bone (rigid pieces that are still skinned)."""
    obj.vertex_groups.clear()
    vg = obj.vertex_groups.new(name=bone)
    vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    _add_armature_mod(obj, arm)


def _add_armature_mod(obj, arm):
    obj.parent = arm
    obj.matrix_parent_inverse = arm.matrix_world.inverted()
    for m in list(obj.modifiers):
        if m.type == "ARMATURE":
            obj.modifiers.remove(m)
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm


def transfer_weights(target, source, arm, max_dist=0.35, smooth_iters=0):
    """Copies vertex-group weights from the closest point of `source` (nearest face, interpolated)."""
    target.vertex_groups.clear()
    for vg in source.vertex_groups:
        target.vertex_groups.new(name=vg.name)
    activate(target)
    dt = target.modifiers.new("DT", "DATA_TRANSFER")
    dt.object = source
    dt.use_object_transform = True
    dt.use_vert_data = True
    dt.data_types_verts = {"VGROUP_WEIGHTS"}
    dt.vert_mapping = "POLYINTERP_NEAREST"
    dt.layers_vgroup_select_src = "ALL"
    dt.layers_vgroup_select_dst = "NAME"
    bpy.ops.object.datalayer_transfer(modifier=dt.name) if False else None
    bpy.ops.object.modifier_apply(modifier=dt.name)
    if smooth_iters:
        bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
        bpy.ops.object.vertex_group_smooth(group_select_mode="ALL", factor=0.5, repeat=smooth_iters)
        bpy.ops.object.mode_set(mode="OBJECT")
    limit_and_normalize(target)
    _add_armature_mod(target, arm)


def limit_and_normalize(obj, limit=4):
    activate(obj)
    if not obj.vertex_groups:
        return
    bpy.ops.object.vertex_group_clean(group_select_mode="ALL", limit=0.01)
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=limit)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)


def remove_empty_groups(obj):
    used = set()
    for v in obj.data.vertices:
        for g in v.groups:
            if g.weight > 0.0:
                used.add(g.group)
    for vg in list(obj.vertex_groups):
        if vg.index not in used:
            obj.vertex_groups.remove(vg)


# --------------------------------------------------------------------------------------
# Decimation for LODs


def make_lod(obj, ratio, name, coll):
    """Copies obj (mesh + weights + armature modifier) and collapses it to `ratio`."""
    new = obj.copy()
    new.data = obj.data.copy()
    new.name = name
    new.data.name = name
    coll.objects.link(new)
    if ratio < 0.999:
        activate(new)
        mods = [m for m in new.modifiers if m.type == "ARMATURE"]
        d = new.modifiers.new("Decimate", "DECIMATE")
        d.ratio = ratio
        d.use_collapse_triangulate = True
        d.use_symmetry = False
        # Modifier order: decimate must run before the armature modifier when applied.
        bpy.ops.object.modifier_move_to_index(modifier=d.name, index=0)
        bpy.ops.object.modifier_apply(modifier=d.name)
        del mods
    return new


# --------------------------------------------------------------------------------------
# Preview rendering


def setup_render(res=(900, 1100), samples=32):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    try:
        sc.eevee.taa_render_samples = samples
        sc.eevee.use_shadows = True
    except Exception:
        pass
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    world = bpy.data.worlds.get("PreviewWorld") or bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.42, 0.47, 0.52, 1)
    bg.inputs["Strength"].default_value = 0.55
    sc.world = world
    sun = bpy.data.objects.get("PreviewSun")
    if sun is None:
        sun = bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", "SUN"))
        sc.collection.objects.link(sun)
    sun.data.energy = 4.0
    sun.data.angle = math.radians(3)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(150))
    fill = bpy.data.objects.get("PreviewFill")
    if fill is None:
        fill = bpy.data.objects.new("PreviewFill", bpy.data.lights.new("PreviewFill", "SUN"))
        sc.collection.objects.link(fill)
    fill.data.energy = 1.0
    fill.rotation_euler = (math.radians(60), 0, math.radians(-30))
    ground = bpy.data.objects.get("PreviewGround")
    if ground is None:
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=6)
        ground = new_object("PreviewGround", bm, sc.collection,
                            [pbr_material("PreviewGroundMat", (0.33, 0.31, 0.27), 0.95)])


def render_view(path, target, distance, azimuth_deg, elevation_deg, lens=55, res=None, frame=None):
    sc = bpy.context.scene
    if res:
        sc.render.resolution_x, sc.render.resolution_y = res
    if frame is not None:
        sc.frame_set(frame)
    cam = bpy.data.objects.get("PreviewCam")
    if cam is None:
        cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
        sc.collection.objects.link(cam)
    t = Vector(target)
    az, el = math.radians(azimuth_deg), math.radians(elevation_deg)
    # azimuth 0 = in front of the character (+Y), 90 = character's left (-X)... measured CCW from +Y.
    pos = t + Vector((-math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el))) * distance
    cam.location = pos
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (t - pos).to_track_quat("-Z", "Y")
    cam.data.lens = lens
    cam.data.clip_start = 0.02
    sc.camera = cam
    sc.render.filepath = path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    return path


def contact_sheet(paths, out, cols):
    """Packs equally sized PNG renders into one image (numpy) for quick inspection."""
    imgs = []
    for p in paths:
        im = bpy.data.images.load(p)
        w, h = im.size
        a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, :3]
        imgs.append(a)
        bpy.data.images.remove(im)
    h, w = imgs[0].shape[:2]
    rows = (len(imgs) + cols - 1) // cols
    sheet = np.ones((rows * h, cols * w, 3)) * 0.2
    for i, a in enumerate(imgs):
        r, c = divmod(i, cols)
        sheet[r * h:(r + 1) * h, c * w:(c + 1) * w] = a[:h, :w]
    return save_png(out, sheet)


# Leg-influence fade for jackets: the hem follows the pelvis, not the thighs.
JACKET_LEG_FADE = (0.74, 0.98, 0.05)


def limit_leg_weights(obj, z_lo=0.80, z_hi=1.00, centre_drop=0.05):
    """Fades the thigh bones' influence out above the hip joints and gives it to Hips:
    full leg weight below z_lo, none above z_hi (smoothstep). Near the body's midline
    (crotch / tailbone) the band is lowered by centre_drop so the crotch does not bulge
    when both thighs flex. Automatic weights let the UpperLeg bones drive the belly and
    waist (up to ~90 % at belt height), which collapsed the waist and flapped the jacket
    hem whenever the legs flexed."""
    hips = obj.vertex_groups.get("Hips")
    legs = [g for g in obj.vertex_groups if g.name in ("LeftUpperLeg", "RightUpperLeg")]
    if hips is None or not legs:
        return
    idx = {g.index: g for g in legs}
    for v in obj.data.vertices:
        c = min(abs(v.co.x) / 0.12, 1.0)
        lo = z_lo - centre_drop * (1.0 - c)
        hi = z_hi - centre_drop * (1.0 - c)
        t = min(max((v.co.z - lo) / (hi - lo), 0.0), 1.0)
        keep = 1.0 - t * t * (3 - 2 * t)
        if keep >= 0.999:
            continue
        moved = 0.0
        for g in v.groups:
            if g.group in idx:
                w = g.weight
                idx[g.group].add([v.index], w * keep, "REPLACE")
                moved += w * (1.0 - keep)
        if moved > 0:
            cur = 0.0
            for g in v.groups:
                if g.group == hips.index:
                    cur = g.weight
            hips.add([v.index], cur + moved, "REPLACE")
