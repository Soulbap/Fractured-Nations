"""Builds the generic military transport vehicle for WORLD-CORE-01.

A 4x4 light tactical truck (crew cab, flat cargo bed with a canvas-style cover frame,
roof rack, bull bar, spare wheel, mirrors, antenna). About 5.6 m long, 2.4 m wide,
2.45 m high, origin at ground level under the chassis center, facing +Y (Godot -Z).
Hull colour is the faction uniform colour in Godot ("Hull" material), the "Patch"
material on both doors takes the faction colour. Run inside Blender:

    exec(open(r"<repo>/tools/blender/make_vehicle.py").read())
"""
import importlib.util
import math
import os

REPO = globals().get("REPO", r"C:\Users\Hafnor\Desktop\Game Dev\fractured-nations")
PREVIEW_DIR = globals().get("PREVIEW_DIR", None)
EXPORT = globals().get("EXPORT", True)

_spec = importlib.util.spec_from_file_location("fn_blender_lib", os.path.join(REPO, "tools", "blender", "fn_blender_lib.py"))
lib = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lib)

lib.clear_scene()

HULL = lib.material("Hull", (0.27, 0.31, 0.21), 0.85)
GLASS = lib.material("Glass", (0.12, 0.16, 0.19), 0.15, 0.2)
TIRE = lib.material("Tire", (0.06, 0.06, 0.06), 0.95)
RIM = lib.material("Rim", (0.25, 0.25, 0.24), 0.6, 0.6)
GEAR = lib.material("Gear", (0.14, 0.14, 0.13), 0.8)
CANVAS = lib.material("Canvas", (0.30, 0.30, 0.22), 0.95)
PATCH = lib.material("Patch", (0.3, 0.55, 1.0), 0.6)
LIGHT = lib.material("Light", (0.9, 0.9, 0.8), 0.3)

parts = []
W = 2.3      # body width
L = 5.6      # overall length
# Chassis / frame
parts.append(lib.box("Frame", (1.9, 4.6, 0.25), (0, 0.0, 0.62), GEAR, bevel=0.02))
# Hood and front fenders (front is +Y)
parts.append(lib.box("Hood", (W, 1.45, 0.62), (0, 1.95, 1.21), HULL, bevel=0.05))
parts.append(lib.box("HoodTop", (W * 0.9, 1.2, 0.08), (0, 1.95, 1.55), HULL, bevel=0.03))
parts.append(lib.box("Grille", (1.6, 0.08, 0.5), (0, 2.68, 1.17), GEAR, bevel=0.01))
parts.append(lib.box("BullBar", (2.1, 0.12, 0.7), (0, 2.85, 0.95), GEAR, bevel=0.03))
for side in (-1, 1):
    parts.append(lib.box("Headlight", (0.22, 0.05, 0.18), (0.75 * side, 2.73, 1.38), LIGHT, bevel=0.01))
# Crew cab
parts.append(lib.box("CabLower", (W, 1.9, 0.7), (0, 0.45, 1.25), HULL, bevel=0.05))
parts.append(lib.box("CabUpper", (W * 0.96, 1.75, 0.85), (0, 0.40, 2.0), HULL, bevel=0.05))
parts.append(lib.box("Windshield", (W * 0.84, 0.05, 0.6), (0, 1.26, 2.02), GLASS, rot=(math.radians(-18), 0, 0)))
for side in (-1, 1):
    parts.append(lib.box("SideWindow", (0.04, 0.6, 0.5), (W * 0.48 * side, 0.55, 2.08), GLASS))
    parts.append(lib.box("SideWindowRear", (0.04, 0.5, 0.5), (W * 0.48 * side, -0.15, 2.08), GLASS))
    parts.append(lib.box("DoorLine", (0.02, 0.03, 1.3), (W * 0.5 * side, 0.2, 1.55), GEAR))
    parts.append(lib.box("Patch", (0.03, 0.42, 0.26), (W * 0.505 * side, 0.55, 1.45), PATCH, bevel=0.005))
    parts.append(lib.box("Mirror", (0.22, 0.08, 0.25), (W * 0.58 * side, 1.25, 1.95), GEAR, bevel=0.01))
    parts.append(lib.box("MirrorArm", (0.2, 0.03, 0.03), (W * 0.52 * side, 1.25, 1.9), GEAR))
    parts.append(lib.box("Step", (0.3, 1.5, 0.06), (W * 0.52 * side, 0.4, 0.8), GEAR, bevel=0.01))
parts.append(lib.box("RoofRack", (W * 0.9, 1.5, 0.08), (0, 0.4, 2.47), GEAR, bevel=0.01))
parts.append(lib.cylinder("Antenna", 0.012, 1.2, (-0.95, -0.35, 3.0), GEAR, verts=6))
# Cargo bed with a covered frame
parts.append(lib.box("Bed", (W, 2.3, 0.5), (0, -1.7, 1.15), HULL, bevel=0.04))
parts.append(lib.box("BedCover", (W * 0.94, 2.2, 0.9), (0, -1.7, 1.85), CANVAS, bevel=0.08))
parts.append(lib.box("Tailgate", (W * 0.9, 0.06, 0.45), (0, -2.83, 1.18), HULL, bevel=0.01))
parts.append(lib.box("RearBumper", (2.2, 0.15, 0.25), (0, -2.9, 0.75), GEAR, bevel=0.02))
parts.append(lib.cylinder("SpareWheel", 0.47, 0.32, (0, -2.98, 1.65), TIRE, rot=(math.radians(90), 0, 0), verts=18))
parts.append(lib.cylinder("SpareRim", 0.26, 0.34, (0, -2.98, 1.65), RIM, rot=(math.radians(90), 0, 0), verts=12))
for side in (-1, 1):
    parts.append(lib.box("JerryCan", (0.18, 0.35, 0.45), (0.85 * side, -2.95, 1.45), GEAR, bevel=0.01))
# Wheels: 4 big tires with rims, wheel radius 0.5 m, ground contact at z = 0
for y in (1.85, -1.75):
    for side in (-1, 1):
        x = 1.06 * side
        parts.append(lib.cylinder("Tire", 0.5, 0.36, (x, y, 0.5), TIRE, rot=(0, math.radians(90), 0), verts=20))
        parts.append(lib.cylinder("Rim", 0.28, 0.38, (x, y, 0.5), RIM, rot=(0, math.radians(90), 0), verts=12))
        parts.append(lib.cylinder("Hub", 0.09, 0.42, (x, y, 0.5), GEAR, rot=(0, math.radians(90), 0), verts=8))
    parts.append(lib.cylinder("Axle", 0.07, 1.9, (0, y, 0.5), GEAR, rot=(0, math.radians(90), 0), verts=8))
# Wheel arches
for y in (1.85, -1.75):
    for side in (-1, 1):
        parts.append(lib.box("Arch", (0.16, 1.3, 0.35), (1.12 * side, y, 0.98), HULL, bevel=0.04))

vehicle = lib.join(parts, "Vehicle")
result = lib.stats(vehicle)

if PREVIEW_DIR:
    result["preview_front"] = lib.preview(vehicle, os.path.join(PREVIEW_DIR, "vehicle_front.png"), azimuth_deg=40, elevation_deg=14, width=1100, height=800)
    result["preview_back"] = lib.preview(vehicle, os.path.join(PREVIEW_DIR, "vehicle_back.png"), azimuth_deg=215, elevation_deg=18, width=1100, height=800)
    lib.remove_preview_rig()

if EXPORT:
    result["glb_bytes"] = lib.export_glb(vehicle, os.path.join(REPO, "assets", "units", "vehicle_transport.glb"))
    lib.save_blend(os.path.join(REPO, "assets", "units", "blender", "vehicle_transport.blend"))
