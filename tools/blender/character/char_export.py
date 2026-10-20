"""GLB export for the infantry set (CHARACTER-01).

Output (assets/characters/infantry/):
  rig/infantry_rig.glb     skeleton + base body regions (+LODs) + every animation clip
  parts/<piece>.glb        one equipment piece: <piece>_LOD0/1/2 meshes. Skinned pieces
                           carry a copy of the skeleton for their skin binds (the Godot
                           loader re-targets them onto the character's Skeleton3D by bone
                           name); rigid pieces are plain meshes with the origin at their
                           attachment point.
  weapons/<piece>.glb      weapon / accessories, origin at the grip / mount point; the
                           carbine carries ATT_* and GRIP_Support nodes.
Images are not embedded: Godot replaces every material by the shared library material of
the same name (scripts/characters/infantry_materials.gd).
"""
import os

import bpy
from mathutils import Matrix

import char_lib as L

LOD_RATIOS = (1.0, 0.30, 0.065)
LOD_MIN_TRIS = (0, 200, 60)


def make_lods(obj, coll):
    """Returns [LOD0, LOD1, LOD2] copies of obj (LOD0 is the original, renamed)."""
    base = obj.name
    tris = L.tri_count(obj)
    out = [obj]
    for i, r in enumerate(LOD_RATIOS[1:], start=1):
        ratio = max(r, min(1.0, LOD_MIN_TRIS[i] / max(tris, 1)))
        lod = L.make_lod(obj, ratio, f"{base}_LOD{i}", coll)
        lod.parent = obj.parent
        lod.parent_type = obj.parent_type
        lod.parent_bone = obj.parent_bone
        lod.matrix_world = obj.matrix_world.copy()
        out.append(lod)
    obj.name = f"{base}_LOD0"
    obj.data.name = obj.name
    return out


def _export(path, objs, animations=False, skins=True):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.hide_set(False)
        o.hide_viewport = False
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=False, export_yup=True,
              export_materials="EXPORT", export_image_format="NONE", export_normals=True, export_texcoords=True,
              export_tangents=True, export_skins=skins, export_def_bones=True, export_animations=animations,
              export_cameras=False, export_lights=False, export_extras=True)
    if animations:
        kw.update(export_animation_mode="ACTIONS", export_force_sampling=True, export_frame_step=1,
                  export_optimize_animation_size=False, export_anim_slide_to_zero=False,
                  export_bake_animation=False, export_reset_pose_bones=True)
    bpy.ops.export_scene.gltf(**kw)
    return os.path.getsize(path)


def export_rig(arm, body_pieces, path, coll):
    objs = [arm]
    for o in body_pieces:
        objs += make_lods(o, coll)
    return _export(path, objs, animations=True), [o.name for o in objs[1:]]


def export_skinned(arm, obj, name, path, coll):
    obj.name = name
    lods = make_lods(obj, coll)
    act = arm.animation_data.action if arm.animation_data else None
    if arm.animation_data:
        arm.animation_data.action = None
    size = _export(path, [arm] + lods)
    if act:
        arm.animation_data.action = act
    return size, [L.tri_count(o) for o in lods]


def export_rigid(obj, name, path, coll, extra_children=()):
    """Temporarily unparents obj to the origin (its mesh is already in attachment space)."""
    saved = (obj.parent, obj.parent_type, obj.parent_bone, obj.matrix_world.copy())
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)
    obj.name = name
    lods = make_lods(obj, coll)
    for l in lods[1:]:
        l.parent = None
        l.matrix_world = Matrix.Identity(4)
    size = _export(path, lods + list(extra_children), skins=False)
    obj.parent, obj.parent_type, obj.parent_bone = saved[0], saved[1], saved[2]
    obj.matrix_world = saved[3]
    for l in lods[1:]:
        l.parent, l.parent_type, l.parent_bone = saved[0], saved[1], saved[2]
        l.matrix_world = saved[3]
        l.hide_render = True
        l.hide_set(True)
    return size, [L.tri_count(o) for o in lods]
