"""Chain-link fence module, fence gate and F-shape concrete barrier (WORLD-BASE-01).

References (docs/WORLD-BASE-01_REPORT.md):
  - Chain-link security fence: galvanized line posts (~60 mm) every 3 m, top rail,
    bottom tension wire, 50 mm diamond mesh 2.4 m high, Y-shaped outrigger arms on each
    post with barbed wire strands and a concertina coil in the Y.
  - Gate: two 4" terminal posts 4.2 m apart, two welded tube leaves with chain-link
    infill and a diagonal brace, drop rod; modelled standing open (soldiers path through).
  - F-shape / Jersey concrete barrier: 3.0 m long, 0.81 m high, 0.61 m base, 75 mm
    vertical toe, 55° then 84° faces, two forklift slots, steel connection loops.

Fence module: length along +X, posts at both ends; the end post is 2 % thinner so the
next module's start post encloses it (no z-fighting at joints and corners). Origins on
the ground at the module center. Run inside Blender:

    exec(open(r"<repo>/tools/blender/structures/make_fence_barriers.py").read())
"""
import importlib.util
import math
import os

REPO = globals().get("REPO", r"C:\\Users\\Hafnor\\Desktop\\Game Dev\\fractured-nations")
PREVIEW_DIR = globals().get("PREVIEW_DIR", os.path.join(REPO, "assets", "structures", "previews"))
EXPORT = globals().get("EXPORT", True)
ONLY = globals().get("ONLY", None)


def _load(name, rel):
    spec = importlib.util.spec_from_file_location(name, os.path.join(REPO, *rel))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


lib = _load("fn_blender_lib", ("tools", "blender", "fn_blender_lib.py"))
sl = _load("fn_structures_lib", ("tools", "blender", "fn_structures_lib.py"))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

sl.set_texture_dir(os.path.join(REPO, "assets", "structures", "textures"))

H = 2.4          # fabric height
L = 3.0          # post spacing / module length
POST_R = 0.03


def fence_materials():
    galv = sl.textured("Galvanized", sl.tex_painted("galvanized", (0.62, 0.64, 0.63), seed=41, grime=0.18), 0.5, roughness=0.45, metallic=0.75)
    link = sl.textured("ChainLink", sl.tex_chainlink("chainlink"), 0.4, roughness=0.5, metallic=0.7, alpha=True, double_sided=True)
    wire = sl.flat("Wire", (0.42, 0.43, 0.42), roughness=0.65, metallic=0.6)
    return galv, link, wire


def concertina(parts, x0, x1, center, radius, loops, mat):
    """Low-poly concertina coil (helix tube, 3 sides) from x0 to x1 around center (y, z)."""
    seg = 10
    n = int(loops * seg)
    verts, faces = [], []
    tube_r = 0.006
    for i in range(n + 1):
        t = i / n
        a = 2 * math.pi * loops * t
        x = x0 + (x1 - x0) * t + 0.04 * math.sin(a * 0.5)
        c = Vector((x, center[0] + radius * math.cos(a), center[1] + radius * math.sin(a)))
        nrm = Vector((0, math.cos(a), math.sin(a)))
        tan = Vector((1, 0, 0)).cross(nrm)
        for k in range(3):
            b = 2 * math.pi * k / 3
            verts.append(tuple(c + (nrm * math.cos(b) + tan * math.sin(b)) * tube_r))
    for i in range(n):
        for k in range(3):
            a = i * 3 + k
            b = i * 3 + (k + 1) % 3
            faces.append((a, b, b + 3, a + 3))
    parts.append(sl.mesh_from("Concertina", verts, faces, mat))


def post_with_arms(parts, x, r, galv, wire, with_coil_side=True):
    parts.append(lib.cylinder("Post", r, H + 0.35, (x, 0, (H + 0.35) * 0.5 - 0.3), galv, verts=10))
    parts.append(lib.cylinder("Cap", r * 1.25, 0.05, (x, 0, H + 0.07), galv, verts=10))
    # Y-arm: two 0.5 m arms at 45° from the post top.
    for side in (-1, 1):
        p0 = (x, 0, H + 0.05)
        p1 = (x, side * 0.35, H + 0.05 + 0.38)
        parts.append(lib.limb("Arm", p0, p1, 0.016, 0.014, galv, verts=6))


def make_fence():
    lib.clear_scene()
    galv, link, wire = fence_materials()
    parts = []
    post_with_arms(parts, -L / 2, POST_R, galv, wire)
    post_with_arms(parts, L / 2, POST_R * 0.98, galv, wire)
    # Top rail and bottom tension wire.
    parts.append(lib.limb("TopRail", (-L / 2, 0.035, H - 0.05), (L / 2, 0.035, H - 0.05), 0.02, 0.02, galv, verts=8))
    parts.append(lib.limb("Tension", (-L / 2, 0.03, 0.06), (L / 2, 0.03, 0.06), 0.004, 0.004, wire, verts=4))
    # Barbed wire strands on both arms (3 per side) and a concertina coil in the Y.
    for side in (-1, 1):
        for k in (1, 2, 3):
            t = k / 3.2
            y = side * 0.35 * t
            z = H + 0.05 + 0.38 * t
            parts.append(lib.limb("Barb", (-L / 2, y, z), (L / 2, y, z), 0.004, 0.004, wire, verts=3))
    concertina(parts, -L / 2, L / 2, (0.0, H + 0.36), 0.22, 17, wire)
    # Chain-link fabric: one double-sided plane from the ground to the top rail.
    v = [(-L / 2, 0.03, -0.05), (L / 2, 0.03, -0.05), (L / 2, 0.03, H - 0.03), (-L / 2, 0.03, H - 0.03)]
    parts.append(sl.mesh_from("Fabric", v, [(0, 1, 2, 3)], link))
    obj = lib.join(parts, "fence")
    sl.box_uv(obj)
    sl.ground_ao(obj, height=0.5, strength=0.35)
    return obj


def make_gate():
    lib.clear_scene()
    galv, link, wire = fence_materials()
    parts = []
    half = 2.1
    for side in (-1, 1):
        x = side * half
        parts.append(lib.cylinder("GatePost", 0.05, H + 0.6, (x, 0, (H + 0.6) * 0.5 - 0.35), galv, verts=12))
        parts.append(lib.cylinder("GateCap", 0.062, 0.06, (x, 0, H + 0.27), galv, verts=12))
        for s2 in (-1, 1):
            parts.append(lib.limb("GateArm", (x, 0, H + 0.2), (x, s2 * 0.35, H + 0.58), 0.016, 0.014, galv, verts=6))
        # Leaf, swung open 100° outward (toward -Y, the gate's front), hinged at the post.
        w = 1.95
        hinge = Vector((x - side * 0.07, 0, 0))
        # Leaf axis from the hinge: toward the opening when closed (-side * X), rotated 100° about Z.
        closed = Vector((-side, 0, 0))
        rot = math.radians(-100) * side
        axis = Vector((closed.x * math.cos(rot) - closed.y * math.sin(rot), closed.x * math.sin(rot) + closed.y * math.cos(rot), 0))
        z0, z1 = 0.08, H - 0.05
        a = hinge
        b = hinge + axis * w
        for z in (z0, z1, (z0 + z1) * 0.5):
            parts.append(lib.limb("LeafRail", (a.x, a.y, z), (b.x, b.y, z), 0.022, 0.022, galv, verts=8))
        for p in (a, b):
            parts.append(lib.limb("LeafStile", (p.x, p.y, z0), (p.x, p.y, z1), 0.024, 0.024, galv, verts=8))
        parts.append(lib.limb("Brace", (a.x, a.y, z0), (b.x, b.y, z1), 0.014, 0.014, galv, verts=6))
        nrm = Vector((-axis.y, axis.x, 0)) * 0.01
        v = [tuple(a + nrm + Vector((0, 0, z0))), tuple(b + nrm + Vector((0, 0, z0))), tuple(b + nrm + Vector((0, 0, z1))), tuple(a + nrm + Vector((0, 0, z1)))]
        parts.append(sl.mesh_from("LeafFabric", v, [(0, 1, 2, 3)], link))
        for hz in (0.3, H - 0.3):
            parts.append(lib.cylinder("Hinge", 0.035, 0.12, (x - side * 0.05, 0, hz), galv, verts=8))
        parts.append(lib.limb("DropRod", (b.x, b.y, -0.05), (b.x, b.y, 1.2), 0.008, 0.008, galv, verts=4))
    # Concertina between the post tops is left out (vehicles pass); a small sign plate.
    obj = lib.join(parts, "fence_gate")
    sl.box_uv(obj)
    sl.ground_ao(obj, height=0.5, strength=0.3)
    return obj


def make_concrete_barrier():
    lib.clear_scene()
    conc = sl.textured("Concrete", sl.tex_concrete("barrier_concrete", color=(0.64, 0.63, 0.6), seed=51), 1.6, roughness=0.92)
    steel = sl.flat("Steel", (0.28, 0.27, 0.25), roughness=0.7, metallic=0.6)
    hw = [0.305, 0.305, 0.13, 0.085, 0.075]
    zz = [-0.12, 0.075, 0.33, 0.78, 0.81]
    # Profile ring (y, z) around the cross-section, extruded along X with chamfered ends.
    ring = [(-hw[i], zz[i]) for i in range(len(zz))] + [(hw[i], zz[i]) for i in reversed(range(len(zz)))]
    xs = [-1.5, -1.48, 1.48, 1.5]
    insets = [0.02, 0.0, 0.0, 0.02]
    verts, faces = [], []
    for xi, x in enumerate(xs):
        for (y, z) in ring:
            s = 1.0 - insets[xi] / max(abs(y), 0.05) if abs(y) > 0.05 else 1.0
            verts.append((x, y * s, z - (insets[xi] if z > 0.7 else 0.0)))
    nr = len(ring)
    for xi in range(len(xs) - 1):
        for k in range(nr):
            a = xi * nr + k
            b = xi * nr + (k + 1) % nr
            faces.append((a, b, b + nr, a + nr))
    faces.append(tuple(reversed(range(nr))))
    faces.append(tuple(range((len(xs) - 1) * nr, len(xs) * nr)))
    body = sl.mesh_from("Barrier", verts, faces, conc)
    # Forklift slots through the toe.
    for x in (-0.75, 0.75):
        cut = lib.box("Slot", (0.32, 0.8, 0.11), (x, 0, 0.055), conc)
        mod = body.modifiers.new("Slot", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = cut
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cut, do_unlink=True)
    parts = [body]
    # Connection loops at the ends and two lifting eyes on top.
    for x in (-1.52, 1.52):
        for z in (0.2, 0.6):
            parts.append(lib.limb("Loop", (x, 0, z), (x, 0, z + 0.06), 0.03, 0.03, steel, verts=6))
    for x in (-0.9, 0.9):
        parts.append(lib.box("Eye", (0.08, 0.02, 0.06), (x, 0, 0.83), steel))
    obj = lib.join(parts, "concrete_barrier")
    sl.box_uv(obj)
    sl.ground_ao(obj, height=0.4, strength=0.4)
    return obj


def run():
    results = {}
    jobs = (("fence", make_fence, [("persp", 30, 15, 7.5), ("low", 10, 4, 4.0), ("top", 200, 50, 8.0)]),
            ("fence_gate", make_gate, [("persp", 25, 15, 9.0), ("back", 200, 20, 9.0)]),
            ("concrete_barrier", make_concrete_barrier, [("persp", 30, 18, 5.0), ("low", 80, 6, 4.0), ("end", 120, 25, 4.0)]))
    for name, fn, views in jobs:
        if ONLY and name not in ONLY:
            continue
        obj = fn()
        r = lib.stats(obj)
        if PREVIEW_DIR:
            r["previews"] = sl.preview_set(lib, obj, os.path.join(PREVIEW_DIR, name), views)
            sl.top_view(obj, os.path.join(PREVIEW_DIR, name + "_top.png"))
            lib.remove_preview_rig()
        if EXPORT:
            r["glb_bytes"] = lib.export_glb(obj, os.path.join(REPO, "assets", "structures", name + ".glb"))
            lib.save_blend(os.path.join(REPO, "assets", "structures", "blender", name + ".blend"))
        results[name] = r
    return results


result = run()
