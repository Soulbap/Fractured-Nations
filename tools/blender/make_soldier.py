"""Builds the placeholder-free infantry soldier for WORLD-CORE-01.

Modern infantry in a low-ready stance: helmet, plate carrier with pouches, assault
pack, carbine held at chest height, faction patches on both upper arms. About 1.78 m
tall, origin at the feet, facing +Y (Godot -Z). Run inside Blender:

    exec(open(r"<repo>/tools/blender/make_soldier.py").read())

Writes assets/units/soldier.glb and assets/units/blender/soldier.blend (REPO below),
plus preview renders into PREVIEW_DIR when set.
"""
import importlib.util
import math
import os
import sys

REPO = globals().get("REPO", r"C:\Users\Hafnor\Desktop\Game Dev\fractured-nations")
PREVIEW_DIR = globals().get("PREVIEW_DIR", None)
EXPORT = globals().get("EXPORT", True)

_spec = importlib.util.spec_from_file_location("fn_blender_lib", os.path.join(REPO, "tools", "blender", "fn_blender_lib.py"))
lib = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lib)

lib.clear_scene()

UNIFORM = lib.material("Uniform", (0.26, 0.31, 0.20), 0.92)
VEST = lib.material("Vest", (0.36, 0.29, 0.20), 0.9)
SKIN = lib.material("Skin", (0.76, 0.58, 0.46), 0.75)
GEAR = lib.material("Gear", (0.16, 0.16, 0.15), 0.8)
WEAPON = lib.material("Weapon", (0.07, 0.07, 0.075), 0.55, 0.3)
BOOTS = lib.material("Boots", (0.22, 0.16, 0.11), 0.85)
PATCH = lib.material("Patch", (0.3, 0.55, 1.0), 0.6)

parts = []

# Legs and boots
for side in (-1, 1):
    x = 0.11 * side
    parts.append(lib.box("Boot", (0.12, 0.29, 0.11), (x, 0.03, 0.055), BOOTS, bevel=0.012))
    parts.append(lib.limb("Shin", (x, 0.0, 0.12), (x, 0.0, 0.56), 0.065, 0.085, UNIFORM))
    parts.append(lib.sphere("Knee", 0.075, (x, 0.02, 0.56), UNIFORM, scale=(1.0, 0.9, 1.0), segments=12, rings=8))
    parts.append(lib.limb("Thigh", (x, 0.0, 0.55), (x * 0.95, -0.01, 0.98), 0.09, 0.115, UNIFORM))
    # Thigh cargo pocket
    parts.append(lib.box("Pocket", (0.03, 0.11, 0.13), (x * 1.9, 0.0, 0.75), UNIFORM, bevel=0.006))

# Pelvis, belt, torso
parts.append(lib.box("Pelvis", (0.34, 0.25, 0.22), (0, 0, 1.06), UNIFORM, bevel=0.035))
parts.append(lib.box("Belt", (0.39, 0.27, 0.05), (0, 0, 1.16), GEAR, bevel=0.008))
parts.append(lib.box("Torso", (0.40, 0.24, 0.46), (0, 0, 1.40), UNIFORM, bevel=0.035))
parts.append(lib.box("Collar", (0.18, 0.14, 0.05), (0, -0.01, 1.64), UNIFORM, bevel=0.01))

# Plate carrier with front pouches and a magazine panel
parts.append(lib.box("Carrier", (0.42, 0.31, 0.34), (0, 0.0, 1.41), VEST, bevel=0.02))
for i, px in enumerate((-0.12, 0.0, 0.12)):
    parts.append(lib.box("Pouch", (0.085, 0.07, 0.15), (px, 0.185, 1.35), VEST, bevel=0.008))
parts.append(lib.box("AdminPouch", (0.22, 0.04, 0.08), (0, 0.17, 1.52), VEST, bevel=0.006))
# Shoulder straps
for side in (-1, 1):
    parts.append(lib.box("Strap", (0.07, 0.25, 0.04), (0.14 * side, 0.0, 1.60), VEST, bevel=0.006))
# Assault pack and radio on the back
parts.append(lib.box("Pack", (0.32, 0.16, 0.36), (0, -0.22, 1.37), VEST, bevel=0.02))
parts.append(lib.box("Radio", (0.09, 0.06, 0.18), (0.12, -0.32, 1.48), GEAR, bevel=0.006))
parts.append(lib.cylinder("Antenna", 0.005, 0.30, (0.12, -0.32, 1.70), GEAR, verts=6))

# Neck, head, helmet (modern ballistic helmet: no brim, covers down to the ears)
parts.append(lib.cylinder("Neck", 0.055, 0.10, (0, 0.0, 1.66), SKIN, verts=10))
parts.append(lib.sphere("Head", 0.10, (0, 0.0, 1.755), SKIN, scale=(0.95, 1.0, 1.12)))
helmet = lib.sphere("Helmet", 0.135, (0, 0.0, 1.775), UNIFORM, scale=(1.0, 1.08, 0.9), segments=20, rings=12)
lib.cut_below(helmet, 1.715)
parts.append(helmet)
for side in (-1, 1):
    parts.append(lib.box("EarCover", (0.03, 0.09, 0.07), (0.125 * side, 0.0, 1.73), UNIFORM, bevel=0.008))
parts.append(lib.box("NVGMount", (0.05, 0.035, 0.045), (0, 0.145, 1.84), GEAR, bevel=0.005))
parts.append(lib.box("ChinStrap", (0.20, 0.035, 0.025), (0, 0.0, 1.70), GEAR))

# Rifle (carbine) in local +Y, tilted down a little and held in front of the chest
rifle_rot = (math.radians(-10), 0, 0)
rifle_pos = (0.03, 0.30, 1.30)


def rifle_part(name, size, off, mat, bevel=0.0, rot=(0, 0, 0)):
    from mathutils import Euler, Vector
    rot_e = Euler(rifle_rot)
    loc = Vector(rifle_pos) + rot_e.to_matrix() @ Vector(off)
    r = (rifle_rot[0] + rot[0], rifle_rot[1] + rot[1], rifle_rot[2] + rot[2])
    return lib.box(name, size, loc, mat, rot=r, bevel=bevel)


parts.append(rifle_part("Receiver", (0.05, 0.28, 0.075), (0, 0.0, 0.0), WEAPON, bevel=0.006))
parts.append(rifle_part("Handguard", (0.045, 0.26, 0.055), (0, 0.27, 0.005), WEAPON, bevel=0.006))
parts.append(rifle_part("Stock", (0.045, 0.24, 0.06), (0, -0.25, -0.005), WEAPON, bevel=0.006))
parts.append(rifle_part("Grip", (0.03, 0.045, 0.11), (0, -0.04, -0.085), WEAPON, bevel=0.004, rot=(math.radians(15), 0, 0)))
parts.append(rifle_part("Magazine", (0.03, 0.065, 0.17), (0, 0.07, -0.11), WEAPON, bevel=0.004, rot=(math.radians(-8), 0, 0)))
parts.append(rifle_part("Optic", (0.035, 0.10, 0.05), (0, 0.0, 0.06), WEAPON, bevel=0.004))
parts.append(rifle_part("Rail", (0.04, 0.44, 0.012), (0, 0.17, 0.042), WEAPON))
from mathutils import Euler, Vector
_barrel_loc = Vector(rifle_pos) + Euler(rifle_rot).to_matrix() @ Vector((0, 0.49, 0.008))
parts.append(lib.cylinder("Barrel", 0.011, 0.20, _barrel_loc, WEAPON, rot=(math.radians(90 - 10), 0, 0), verts=8))

# Arms holding the rifle: shoulders -> elbows -> hands near grip / handguard
grip_hand = Vector(rifle_pos) + Euler(rifle_rot).to_matrix() @ Vector((0.0, -0.04, -0.10))
front_hand = Vector(rifle_pos) + Euler(rifle_rot).to_matrix() @ Vector((0.0, 0.25, -0.03))
shoulder_r = Vector((0.235, 0.0, 1.57))
shoulder_l = Vector((-0.235, 0.0, 1.57))
elbow_r = Vector((0.27, 0.10, 1.33))
elbow_l = Vector((-0.26, 0.17, 1.36))
for name, s, e, h in (("R", shoulder_r, elbow_r, grip_hand), ("L", shoulder_l, elbow_l, front_hand)):
    parts.append(lib.sphere("Shoulder" + name, 0.065, s, UNIFORM, segments=12, rings=8))
    parts.append(lib.limb("UpperArm" + name, s, e, 0.058, 0.05, UNIFORM))
    parts.append(lib.sphere("Elbow" + name, 0.05, e, UNIFORM, segments=10, rings=7))
    parts.append(lib.limb("Forearm" + name, e, h, 0.05, 0.04, UNIFORM))
    parts.append(lib.box("Hand" + name, (0.07, 0.09, 0.06), h, GEAR, bevel=0.01))
    # Faction patch on the outer upper arm
    side = 1 if name == "R" else -1
    mid = (s + e) * 0.5
    parts.append(lib.box("Patch" + name, (0.014, 0.065, 0.065), (mid.x + 0.058 * side, mid.y, mid.z + 0.02), PATCH, bevel=0.003))

soldier = lib.join(parts, "Soldier")
result = lib.stats(soldier)

if PREVIEW_DIR:
    result["preview_front"] = lib.preview(soldier, os.path.join(PREVIEW_DIR, "soldier_front.png"), azimuth_deg=35, elevation_deg=10)
    result["preview_back"] = lib.preview(soldier, os.path.join(PREVIEW_DIR, "soldier_back.png"), azimuth_deg=200, elevation_deg=14)
    lib.remove_preview_rig()

if EXPORT:
    result["glb_bytes"] = lib.export_glb(soldier, os.path.join(REPO, "assets", "units", "soldier.glb"))
    lib.save_blend(os.path.join(REPO, "assets", "units", "blender", "soldier.blend"))
