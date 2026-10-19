"""Shared helpers for the FRACTURED NATIONS Blender -> Godot asset pipeline.

Run inside Blender (interactive or --background). Conventions used by every asset:
  - 1 Blender unit = 1 m, model stands on z = 0 with its origin at the feet / ground
    contact point, and it FACES +Y in Blender. The glTF exporter maps Blender +Y to
    glTF -Z, which is Godot's forward, so the asset faces forward in Godot untouched.
  - Materials are flat Principled BSDF colours (no textures); Godot keeps the material
    names, and UnitVisuals recolours "Uniform"/"Hull" and "Patch" per faction.
  - Everything is joined into one mesh object per asset so Godot imports one
    MeshInstance3D with one surface per material (and generates LODs on import).
"""
import math
import os

import bpy
from mathutils import Vector

_MATS = {}


def clear_scene():
    """Removes every object, mesh, material, image and light of the current file."""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.lights, bpy.data.cameras):
        for block in list(coll):
            if block.users == 0:
                coll.remove(block)
    _MATS.clear()


def material(name, rgb, roughness=0.85, metallic=0.0):
    """Principled material with a flat base colour (sRGB floats 0..1)."""
    if name in _MATS:
        return _MATS[name]
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    mat.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    _MATS[name] = mat
    return mat


def _finish(obj, name, mat, bevel):
    obj.name = name
    obj.data.name = name
    if mat is not None:
        obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(40)
    return obj


def box(name, size, loc, mat, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.scale = (size[0], size[1], size[2])
    bpy.ops.object.transform_apply(scale=True)
    return _finish(obj, name, mat, bevel)


def cylinder(name, radius, depth, loc, mat, rot=(0, 0, 0), verts=12, bevel=0.0, r2=None):
    """Cylinder along local Z (tapered when r2 is given: radius at -Z end, r2 at +Z end)."""
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=r2, depth=depth, location=loc, rotation=rot)
    obj = bpy.context.active_object
    return _finish(obj, name, mat, bevel)


def sphere(name, radius, loc, mat, scale=(1, 1, 1), segments=16, rings=10):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius, location=loc)
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return _finish(obj, name, mat, 0.0)


def limb(name, p0, p1, r0, r1, mat, verts=10):
    """Tapered cylinder from point p0 (radius r0) to p1 (radius r1)."""
    p0 = Vector(p0)
    p1 = Vector(p1)
    d = p1 - p0
    length = d.length
    mid = (p0 + p1) * 0.5
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r0, radius2=r1, depth=length, location=mid)
    obj = bpy.context.active_object
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = d.to_track_quat("Z", "Y")
    bpy.ops.object.transform_apply(rotation=True)
    return _finish(obj, name, mat, 0.0)


def cut_below(obj, z):
    """Deletes the part of a mesh below world z (e.g. helmet bowl from a sphere)."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    mw = obj.matrix_world
    geom = [v for v in bm.verts if (mw @ v.co).z < z]
    bmesh.ops.delete(bm, geom=geom, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()


def join(objects, name):
    """Joins objects into one mesh named `name` with its origin at the world origin."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.convert(target="MESH")  # applies modifiers (bevels)
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    smooth_by_angle(obj, 38.0)
    return obj


def smooth_by_angle(obj, degrees):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(degrees))
    except AttributeError:
        try:
            bpy.ops.object.shade_smooth_by_angle(angle=math.radians(degrees))
        except AttributeError:
            bpy.ops.object.shade_smooth()


def stats(obj):
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    dims = obj.dimensions
    return {"name": obj.name, "vertices": len(obj.data.vertices), "triangles": tris,
            "dimensions_m": [round(dims.x, 3), round(dims.y, 3), round(dims.z, 3)],
            "materials": [m.name for m in obj.data.materials]}


def export_glb(obj, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT", export_normals=True,
                              export_texcoords=True, export_animations=False, export_skins=False,
                              export_cameras=False, export_lights=False)
    return os.path.getsize(path)


def save_blend(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)


def preview(obj, path, width=900, height=1000, azimuth_deg=35.0, elevation_deg=12.0, distance=None, lookat_z=None):
    """Renders a 3/4 view of `obj` with a sun and a soft sky to `path` (PNG)."""
    scene = bpy.context.scene
    dims = obj.dimensions
    target = Vector((0, 0, lookat_z if lookat_z is not None else dims.z * 0.5))
    if distance is None:
        distance = max(dims.x, dims.y, dims.z) * 2.3
    az = math.radians(azimuth_deg)
    el = math.radians(elevation_deg)
    # Camera in front (+Y side) of the model, rotated by azimuth.
    cam_pos = target + Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el))) * distance
    cam = bpy.data.objects.get("PreviewCamera")
    if cam is None:
        cam_data = bpy.data.cameras.new("PreviewCamera")
        cam = bpy.data.objects.new("PreviewCamera", cam_data)
        scene.collection.objects.link(cam)
    cam.location = cam_pos
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (target - cam_pos).to_track_quat("-Z", "Y")
    cam.data.lens = 50
    scene.camera = cam
    sun = bpy.data.objects.get("PreviewSun")
    if sun is None:
        sun_data = bpy.data.lights.new("PreviewSun", "SUN")
        sun = bpy.data.objects.new("PreviewSun", sun_data)
        scene.collection.objects.link(sun)
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), math.radians(-15), math.radians(35))
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.55, 0.62, 0.72, 1.0)
        bg.inputs[1].default_value = 0.6
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    return path


def remove_preview_rig():
    for n in ("PreviewCamera", "PreviewSun"):
        o = bpy.data.objects.get(n)
        if o:
            bpy.data.objects.remove(o, do_unlink=True)
