"""CHARACTER-01 build entry point: regenerates the whole infantry character set.

Background (reproducible, recommended):
    blender -b --factory-startup --python tools/blender/character/build_infantry.py -- [options]
Interactive Blender (MCP / Text editor):
    ARGS = ["--previews", "C:/tmp/prev"]; HERE = r"<repo>/tools/blender/character"
    exec(open(HERE + "/build_infantry.py").read())

Options:
    --previews DIR   render Blender preview images into DIR
    --export         write GLBs into assets/characters/infantry/ and the .blend source
    --stage NAME     stop after a stage: body | uniform | gear | anim (default: everything)
"""
import importlib
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else globals().get("HERE")
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import bpy  # noqa: E402

import char_lib as L  # noqa: E402
import char_skeleton as S  # noqa: E402
import char_sdf as D  # noqa: E402
import char_body as B  # noqa: E402
import char_textures as T  # noqa: E402
import char_materials as M  # noqa: E402
import char_uniform as U  # noqa: E402

MODULES = [L, S, D, B, T, M, U]
for _name in ("char_gear", "char_weapon", "char_anim", "char_export"):
    try:
        MODULES.append(importlib.import_module(_name))
    except ImportError:
        pass
for _m in MODULES:
    importlib.reload(_m)

ASSET_DIR = os.path.join(REPO, "assets", "characters", "infantry")
TEX_DIR = os.path.join(ASSET_DIR, "textures")
BLEND_PATH = os.path.join(ASSET_DIR, "blender", "infantry.blend")


def parse_args():
    argv = globals().get("ARGS")
    if argv is None:
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"previews": None, "export": False, "stage": "all", "only": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--previews", "--stage", "--only"):
            opts[a[2:]] = argv[i + 1]
            i += 1
        elif a == "--export":
            opts["export"] = True
        i += 1
    return opts


class Build:
    """Holds everything the stages create, so later stages and previews can find it."""

    def __init__(self):
        self.log = {}
        self.pieces = {}      # piece id -> object (LOD0, in character space)
        self.rigid = {}       # piece id -> (object, attach bone)


def stage_body(b):
    tex = T.build_all(TEX_DIR)
    tex["skin"] = os.path.join(TEX_DIR, "skin_head_albedo.png")
    B.make_skin_texture(tex["skin"])
    b.tex = tex
    b.mats = M.build(tex)
    b.coll_body = L.collection("Body")
    b.coll_ref = L.collection("Reference")
    b.arm = S.build_armature(L.collection("Rig"))
    body = B.build_body(b.coll_body)
    body.data.materials.append(b.mats["SkinBody"])
    L.parent_to_armature(body, b.arm, auto=True)
    hands = B.build_hands(b.coll_body)
    hands.data.materials.append(b.mats["SkinBody"])
    L.parent_to_armature(hands, b.arm, auto=True)
    # Weight reference for garments: full body + hands, weights only, never exported.
    ref = L.join([_dup(body, b.coll_ref), _dup(hands, b.coll_ref)], "WeightRef")
    ref.hide_render = True
    b.weight_ref = ref
    parts = B.split_regions(body, b.coll_body)
    parts["Hands"] = hands
    for name, p in parts.items():
        M.apply_box_uvs(p)
        b.pieces["body_" + name.lower()] = p
    head = B.build_head(b.coll_body, b.mats["Skin"], b.mats["Eye"], b.mats["Iris"])
    _weight_head(head, b.arm)
    b.pieces["body_head"] = head
    b.log["body_tris"] = {k: L.tri_count(v) for k, v in b.pieces.items()}


def _dup(obj, coll):
    o = obj.copy()
    o.data = obj.data.copy()
    coll.objects.link(o)
    return o


def _weight_head(head, arm):
    head.vertex_groups.clear()
    gh = head.vertex_groups.new(name="Head")
    gn = head.vertex_groups.new(name="Neck")
    gu = head.vertex_groups.new(name="UpperChest")
    for v in head.data.vertices:
        z = v.co.z
        if z >= 1.60:
            gh.add([v.index], 1.0, "REPLACE")
        elif z >= 1.53:
            t = (z - 1.53) / 0.07
            gh.add([v.index], t, "REPLACE")
            gn.add([v.index], 1 - t, "REPLACE")
        else:
            t = max(0.0, (z - 1.47) / 0.06)
            gn.add([v.index], t, "REPLACE")
            gu.add([v.index], 1 - t, "REPLACE")
    L._add_armature_mod(head, arm)


def stage_uniform(b):
    coll = L.collection("Uniform_M23")
    uni = U.build_uniform(coll, b.mats)
    for k, o in uni.items():
        M.apply_box_uvs(o)
        L.transfer_weights(o, b.weight_ref, b.arm, smooth_iters=2)
        b.pieces["uniform_" + k] = o
    b.log["uniform_tris"] = {k: L.tri_count(o) for k, o in uni.items()}


# Loadouts as built here (mirrors assets/characters/infantry/loadouts/*.tres in Godot).
LOADOUTS = {
    "A_standard": ["uniform_jacket", "uniform_trousers", "uniform_boots", "uniform_gloves", "body_head",
                   "helmet_covered", "eyepro", "vest_standard", "belt_standard", "pack_assault",
                   "carbine", "optic_reddot", "foregrip"],
    "B_heavy": ["uniform_jacket", "uniform_trousers", "uniform_boots", "uniform_gloves", "body_head",
                "helmet_bare", "eyepro", "vest_heavy", "belt_heavy", "pack_ruck",
                "carbine", "optic_reddot", "foregrip", "laser"],
}
# Rigid pieces: attachment bone (or weapon mount) they ride on.
RIGID = {"helmet_covered": "ATT_Head", "helmet_bare": "ATT_Head", "eyepro": "ATT_Head",
         "pack_assault": "ATT_Back", "pack_ruck": "ATT_Back", "carbine": "ATT_Weapon",
         "optic_reddot": "weapon:ATT_Optic", "foregrip": "weapon:ATT_Underbarrel", "laser": "weapon:ATT_RailRight"}


def stage_gear(b):
    import char_gear as G
    import char_weapon as W
    coll = L.collection("Gear")
    mk = {
        "vest_standard": lambda: G.build_vest(coll, b.mats, "standard"),
        "vest_heavy": lambda: G.build_vest(coll, b.mats, "heavy"),
        "belt_standard": lambda: G.build_belt(coll, b.mats, "standard"),
        "belt_heavy": lambda: G.build_belt(coll, b.mats, "heavy"),
        "pack_assault": lambda: G.build_pack(coll, b.mats, "assault"),
        "pack_ruck": lambda: G.build_pack(coll, b.mats, "ruck"),
        "helmet_covered": lambda: G.build_helmet(coll, b.mats, "covered"),
        "helmet_bare": lambda: G.build_helmet(coll, b.mats, "bare"),
        "eyepro": lambda: G.build_eyepro(coll, b.mats),
    }
    for key, fn in mk.items():
        t = time.time()
        o = fn()
        M.apply_box_uvs(o)
        b.pieces[key] = o
        b.log.setdefault("gear_seconds", {})[key] = round(time.time() - t, 1)
        if key in RIGID:
            _make_rigid(b, key, o)
        else:
            L.transfer_weights(o, b.weight_ref, b.arm, smooth_iters=4)
    wcoll = L.collection("Weapon")
    b.weapon = W.build_carbine(wcoll, b.mats)
    M.apply_box_uvs(b.weapon)
    b.pieces["carbine"] = b.weapon
    b.mounts = {e.name: e for e in W.mount_empties(wcoll, b.weapon)}
    for key, fn, mount in (("optic_reddot", W.build_red_dot, "ATT_Optic"), ("foregrip", W.build_foregrip, "ATT_Underbarrel"),
                           ("laser", W.build_laser, "ATT_RailRight")):
        o = fn(wcoll, b.mats)
        M.apply_box_uvs(o)
        o.parent = b.weapon
        o.location = W.MOUNTS[mount]
        b.pieces[key] = o
    _place_on_bone(b, b.weapon, "ATT_Weapon", weapon_space=True)
    b.log["gear_tris"] = {k: L.tri_count(b.pieces[k]) for k in list(mk) + ["carbine", "optic_reddot", "foregrip", "laser"]}


def _make_rigid(b, key, obj):
    """Moves a piece built in character space into its attachment space (origin at the
    attachment point, axes = character axes) and parents it to that bone."""
    from mathutils import Matrix
    bone = RIGID[key]
    att = b.arm.data.bones[bone].matrix_local
    obj.data.transform(att.inverted())
    obj.matrix_world = Matrix.Identity(4)
    _place_on_bone(b, obj, bone)


def _place_on_bone(b, obj, bone, weapon_space=False):
    want = b.arm.matrix_world @ b.arm.data.bones[bone].matrix_local
    obj.parent = b.arm
    obj.parent_type = "BONE"
    obj.parent_bone = bone
    obj.matrix_world = want


def show_loadout(b, name):
    keep = set(LOADOUTS[name])
    for k, o in b.pieces.items():
        vis = k in keep
        o.hide_render = not vis
        o.hide_set(not vis)
    hide_body_under(b)


def hide_body_under(b, uniform=True):
    for k in ("body_torso", "body_arms", "body_legs", "body_feet", "body_hands"):
        o = b.pieces.get(k)
        if o:
            o.hide_render = uniform
            o.hide_set(uniform)


def preview_sheet(b, outdir, tag, target=(0, 0, 0.93), dist=3.4, frame=None):
    L.setup_render((700, 1000))
    shots = []
    for name, az in (("front", 0), ("q34", 35), ("side", 90), ("back", 180), ("q34b", 225)):
        shots.append(L.render_view(os.path.join(outdir, f"{tag}_{name}.png"), target, dist, az, 6, lens=50, frame=frame))
    L.contact_sheet(shots, os.path.join(outdir, f"{tag}_sheet.png"), 5)


def preview_closeups(b, outdir, tag):
    L.setup_render((800, 800))
    shots = []
    for name, tgt, d, az, el in (("head", (0, 0.02, 1.66), 0.9, 25, 4), ("chest", (0, 0.05, 1.25), 1.3, 30, 8),
                                 ("legs", (0, 0, 0.45), 1.5, 30, 10), ("weapon", (0.05, 0.35, 1.15), 0.9, 55, 12),
                                 ("back", (0, -0.1, 1.2), 1.6, 200, 10)):
        shots.append(L.render_view(os.path.join(outdir, f"{tag}_cu_{name}.png"), tgt, d, az, el, lens=60))
    L.contact_sheet(shots, os.path.join(outdir, f"{tag}_closeups.png"), 5)


def main():
    t0 = time.time()
    opts = parse_args()
    b = Build()
    L.clear_scene()
    stage_body(b)
    b.log["t_body"] = round(time.time() - t0, 1)
    if opts["stage"] == "body":
        if opts["previews"]:
            preview_sheet(b, opts["previews"], "body")
        print("FNBUILD", json.dumps(b.log))
        return
    stage_uniform(b)
    hide_body_under(b)
    b.log["t_uniform"] = round(time.time() - t0, 1)
    if opts["stage"] == "uniform":
        if opts["previews"]:
            preview_sheet(b, opts["previews"], "uniform")
            preview_closeups(b, opts["previews"], "uniform")
        print("FNBUILD", json.dumps(b.log))
        return
    stage_gear(b)
    b.log["t_gear"] = round(time.time() - t0, 1)
    if opts["stage"] == "gear":
        if opts["previews"]:
            for name in LOADOUTS:
                show_loadout(b, name)
                preview_sheet(b, opts["previews"], "gear_" + name)
                preview_closeups(b, opts["previews"], "gear_" + name)
        print("FNBUILD", json.dumps(b.log))
        return
    import char_anim as A
    A.setup_controls(b.arm)
    b.actions = A.author_and_bake(b.arm, only=opts["only"].split(",") if opts["only"] else None)
    A.remove_controls(b.arm)
    b.log["anim_check"] = A.measure(b.arm, b.actions)
    b.log["t_anim"] = round(time.time() - t0, 1)
    if opts["previews"]:
        preview_poses(b, opts["previews"])
    if opts["export"]:
        stage_export(b)
    b.log["t_total"] = round(time.time() - t0, 1)
    print("FNBUILD", json.dumps(b.log))
    if opts["export"]:
        with open(os.path.join(ASSET_DIR, "build_log.json"), "w", encoding="utf-8") as f:
            json.dump(b.log, f, indent=1)


SKINNED_PIECES = ["uniform_jacket", "uniform_trousers", "uniform_boots", "uniform_gloves",
                  "vest_standard", "vest_heavy", "belt_standard", "belt_heavy"]
RIGID_PIECES = ["helmet_covered", "helmet_bare", "eyepro", "pack_assault", "pack_ruck"]
WEAPON_PIECES = ["carbine", "optic_reddot", "foregrip", "laser"]


def stage_export(b):
    import char_anim as A
    import char_export as E
    lod_coll = L.collection("LODs")
    for o in b.pieces.values():
        o.hide_set(False)
    out = {}
    body = [b.pieces[k] for k in ("body_head", "body_torso", "body_arms", "body_hands", "body_legs", "body_feet")]
    size, names = E.export_rig(b.arm, body, os.path.join(ASSET_DIR, "rig", "infantry_rig.glb"), lod_coll)
    out["rig"] = {"bytes": size, "meshes": names, "clips": sorted(b.actions)}
    for k in SKINNED_PIECES:
        size, tris = E.export_skinned(b.arm, b.pieces[k], k, os.path.join(ASSET_DIR, "parts", k + ".glb"), lod_coll)
        out[k] = {"bytes": size, "lod_tris": tris}
    for k in RIGID_PIECES:
        size, tris = E.export_rigid(b.pieces[k], k, os.path.join(ASSET_DIR, "parts", k + ".glb"), lod_coll)
        out[k] = {"bytes": size, "lod_tris": tris}
    for k in WEAPON_PIECES:
        extra = list(b.mounts.values()) if k == "carbine" else []
        size, tris = E.export_rigid(b.pieces[k], k, os.path.join(ASSET_DIR, "weapons", k + ".glb"), lod_coll, extra)
        out[k] = {"bytes": size, "lod_tris": tris}
    A.write_meta(os.path.join(ASSET_DIR, "animation_meta.json"), b.actions)
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    open(os.path.join(os.path.dirname(BLEND_PATH), ".gdignore"), "w").close()
    for o in lod_coll.objects:
        o.hide_set(True)
        o.hide_render = True
    bpy.context.preferences.filepaths.save_version = 0      # no .blend1 backups
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH, compress=True)
    b.log["export"] = out


POSE_SHOTS = (("Idle", 0.0), ("Walk_F", 0.0), ("Run_F", 0.25), ("Sprint_F", 0.0), ("Crouch_Idle", 0.0), ("Run_L", 0.25))


def preview_poses(b, outdir):
    """Renders both loadouts in key poses of the baked clips."""
    for name in LOADOUTS:
        show_loadout(b, name)
        b.arm.animation_data.action = b.actions.get("Idle")
        bpy.context.scene.frame_set(0)
        preview_sheet(b, outdir, f"idle_{name}", target=(0, 0.05, 0.93), frame=0)
        preview_closeups(b, outdir, f"idle_{name}")
    L.setup_render((560, 860))
    for name in LOADOUTS:
        show_loadout(b, name)
        shots = []
        for clip, frac in POSE_SHOTS:
            act = b.actions.get(clip)
            if act is None:
                continue
            b.arm.animation_data.action = act
            f = int(act["fn_frames"] * frac)
            for az in (20, 90):
                shots.append(L.render_view(os.path.join(outdir, f"pose_{name}_{clip}_{az}.png"), (0, 0.1, 0.92), 2.9, az, 6, lens=50, frame=f))
        L.contact_sheet(shots, os.path.join(outdir, f"pose_{name}_sheet.png"), 6)
    b.arm.animation_data.action = None


main()
