"""MakeHuman part of the shared infantry body (VISUAL-03): the MakeHuman base mesh (MPFB 2, CC0 output) with the
game-engine rig renamed to the shared infantry skeleton (Godot SkeletonProfileHumanoid names, CHARACTER_STANDARD §2).
char_body.py turns it into the game body (reference rest pose, regions, head, eyes).

Needs the MPFB extension installed in the user's Blender (extensions repo user_default, module
bl_ext.user_default.mpfb, version 2.0.18 used for VISUAL-03). Everything is generated from the parameters
below, nothing is hand-edited.
"""
import math

import bpy
from mathutils import Vector

MPFB = "bl_ext.user_default.mpfb"

# MakeHuman macro sliders (0..1). Young adult male infantryman: lean, athletic, average proportions.
# age 0.5 = 25 years; muscle/weight 0.5 = average. Stature is scaled to STATURE afterwards.
MACRO = {"gender": 1.0, "age": 0.5, "muscle": 0.62, "weight": 0.46, "proportions": 0.55, "height": 0.6,
         "cupsize": 0.5, "firmness": 0.5, "race": {"caucasian": 0.8, "african": 0.1, "asian": 0.1}}
STATURE = 1.80
# Detail targets on top of the macros. MakeHuman's average adult arm is ~10 cm short of the anthropometric
# references (fingertips at 0.44 H standing instead of ~0.38 H, upper arm 0.27 m instead of ~0.33 m), which left the
# support hand unable to reach a rifle's handguard: lengthen upper arm and forearm.
DETAIL_TARGETS = {"arms/measure-upperarm-length-incr": 1.0, "arms/measure-lowerarm-length-incr": 0.15}

# MPFB game_engine rig -> shared skeleton names.
RENAME = {
    "Root": "Root", "pelvis": "Hips", "spine_01": "Spine", "spine_02": "Chest", "spine_03": "UpperChest",
    "neck_01": "Neck", "head": "Head",
}
for _s, _S in (("l", "Left"), ("r", "Right")):
    RENAME.update({
        f"clavicle_{_s}": _S + "Shoulder", f"upperarm_{_s}": _S + "UpperArm", f"lowerarm_{_s}": _S + "LowerArm",
        f"hand_{_s}": _S + "Hand", f"thigh_{_s}": _S + "UpperLeg", f"calf_{_s}": _S + "LowerLeg",
        f"foot_{_s}": _S + "Foot", f"ball_{_s}": _S + "Toes",
        f"thumb_01_{_s}": _S + "ThumbMetacarpal", f"thumb_02_{_s}": _S + "ThumbProximal", f"thumb_03_{_s}": _S + "ThumbDistal",
    })
    for _f, _F in (("index", "Index"), ("middle", "Middle"), ("ring", "Ring"), ("pinky", "Little")):
        for _i, _seg in ((1, "Proximal"), (2, "Intermediate"), (3, "Distal")):
            RENAME[f"{_f}_0{_i}_{_s}"] = _S + _F + _seg


def enable_mpfb():
    import addon_utils
    if not addon_utils.check(MPFB)[1]:
        bpy.ops.preferences.addon_enable(module=MPFB)
    import importlib
    hs = importlib.import_module(MPFB + ".services.humanservice").HumanService
    ts = importlib.import_module(MPFB + ".services.targetservice").TargetService
    return hs, ts


def build_human(macro=None):
    """Returns (armature, body). Body: shape keys baked, helpers removed, scaled to STATURE, feet on z=0,
    facing +Y (MakeHuman faces -Y; the whole rig is turned 180 degrees and applied)."""
    HS, TS = enable_mpfb()
    # detailed_helpers: the rig is fitted to the joint-* helper cube groups (without them MPFB silently uses the
    # default body's joint positions). feet_on_ground=False: fit first, move after.
    body = HS.create_human(mask_helpers=True, detailed_helpers=True, extra_vertex_groups=True, feet_on_ground=False,
                           scale=0.1, macro_detail_dict=macro or MACRO)
    import os
    from importlib import import_module
    LS = import_module(MPFB + ".services.locationservice").LocationService
    for t, w in DETAIL_TARGETS.items():
        TS.load_target(body, os.path.join(LS.get_mpfb_data("targets"), t + ".target.gz"), weight=w)
    # Bake the targets first: the rig is fitted to the joint helper cubes of the mesh basis.
    TS.bake_targets(body)
    arm = HS.add_builtin_rig(body, "game_engine", import_weights=True)
    # The eyeball helpers become their own object (char_body builds the eyes from them); the rest of the helper
    # geometry is dropped (the mask modifier only hides it).
    import bmesh
    eyes = None
    gi_e = [body.vertex_groups[n].index for n in ("helper-l-eye", "helper-r-eye") if n in body.vertex_groups]
    if gi_e:
        bm = bmesh.new()
        bm.from_mesh(body.data)
        dl = bm.verts.layers.deform.verify()
        side_of = {}
        for v in bm.verts:
            for k, gi in enumerate(gi_e):
                if gi in v[dl] and v[dl][gi] > 0.5:
                    side_of[v.index] = k
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in side_of], context="VERTS")
        me = bpy.data.meshes.new("EyeHelpers")
        bm.to_mesh(me)
        bm.free()
        eyes = bpy.data.objects.new("EyeHelpers", me)
        body.users_collection[0].objects.link(eyes)
        eyes.parent = arm
    keep = body.vertex_groups.get("body")
    if keep is not None:
        bm = bmesh.new()
        bm.from_mesh(body.data)
        dl = bm.verts.layers.deform.verify()
        gi = keep.index
        kill = [v for v in bm.verts if gi not in v[dl] or v[dl][gi] < 0.5]
        bmesh.ops.delete(bm, geom=kill, context="VERTS")
        bm.to_mesh(body.data)
        bm.free()
    for m in list(body.modifiers):
        if m.type == "MASK":
            body.modifiers.remove(m)
    # Rename bones and vertex groups to the shared skeleton.
    for b in arm.data.bones:
        if b.name in RENAME:
            b.name = RENAME[b.name]
    for g in body.vertex_groups:
        if g.name in RENAME:
            g.name = RENAME[g.name]
    # Scale to stature and turn to face +Y (rotation applied, so rest data is in character space).
    zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
    s = STATURE / (max(zs) - min(zs))
    arm.scale = (s, s, s)
    arm.rotation_euler = (0, 0, math.pi)
    bpy.context.view_layer.update()
    for o in bpy.context.selected_objects:
        o.select_set(False)
    arm.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if eyes:
        eyes.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    arm.name, arm.data.name = "InfantryRig", "InfantryRig"
    body.name, body.data.name = "Char_Body", "Char_Body"
    zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
    if abs(min(zs)) > 1e-4:
        arm.location.z -= min(zs)
        bpy.context.view_layer.update()
        for o in bpy.context.selected_objects:
            o.select_set(False)
        arm.select_set(True)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
        body.select_set(True)
        if eyes:
            eyes.select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    return arm, body, eyes


def joint_table(arm):
    """World positions of the main joints (rest), for the report and proportion checks."""
    mw = arm.matrix_world
    out = {}
    for n in ("Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg",
              "LeftFoot", "LeftToes", "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand"):
        b = arm.data.bones.get(n)
        if b:
            out[n] = [round(c, 4) for c in mw @ b.head_local]
    return out
