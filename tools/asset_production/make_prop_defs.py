"""StructureDef resources for the ASSET-PRODUCTION-01 props the player can build.

WORLD-INTEGRATION-03. The asset pipeline writes StructureDefs for buildings and modules
(assets/military/defs/*.tres, from the "structure" block of each sidecar); props have no
such block because which of the 51 props are worth a construction-menu entry, how lines of
them behave (module length, how they sit on a slope, what they snap to) and where they go in
the menu are gameplay decisions. This script holds that table and writes
assets/military/defs/props/<id>.tres from the sidecar numbers (size, collision boxes). It
needs no Blender; run it from the project root after an asset rebuild:

    python tools/asset_production/make_prop_defs.py

Colour variants (tan generator, blue / rust containers), duplicates of the WORLD-BASE-01
set (HESCO cells, chain-link fence and gate, F-shape barrier), small decor (jerrycans,
ammunition cans, single sandbags, cones) and the road surface sections (painted roads are
the road system) are left out on purpose.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROPS = os.path.join(ROOT, "assets", "military", "props")
ROADS = os.path.join(ROOT, "assets", "military", "roads")
OUT = os.path.join(ROOT, "assets", "military", "defs", "props")

# id: menu category, display name (None = sidecar), options.
#   linear: module line; layout SPAN / CENTERED; fit LEVEL / STEP / PITCH / SHEAR;
#   group: connect group for line snapping; nav: blocks_navigation; walkable: no collision;
#   slope / gap: terrain limits; boxes: override of the sidecar collision boxes.
TABLE = {
    # Defences
    "t_wall": ("Defences", "T-wall blast wall", dict(linear=True, fit="STEP", group="twall", slope=12, gap=0.4)),
    "sandbag_wall_2m": ("Defences", "Sandbag wall", dict(linear=True, fit="PITCH", group="sandbag", slope=18, gap=0.35)),
    "sandbag_wall_low_2m": ("Defences", "Sandbag wall (low)", dict(linear=True, fit="PITCH", group="sandbag", slope=18, gap=0.35)),
    "water_barrier": ("Defences", "Water-filled barrier", dict(linear=True, fit="PITCH", group="water", slope=12, gap=0.25)),
    "mesh_fence_temporary": ("Defences", "Temporary mesh fence", dict(linear=True, fit="SHEAR", group="mesh_fence", slope=25, gap=0.5)),
    # Boom arm at 0.9 m is visual (vehicles stop at VEH_Stop later); only the post is solid.
    "boom_barrier": ("Defences", "Boom barrier", dict(nav=False, slope=6, gap=0.3, boxes=[[-0.2, 0.0, -0.2, 0.4, 1.1, 0.4]])),
    "guard_booth": ("Defences", None, dict(slope=8, gap=0.4)),
    # Logistics
    "iso_container_20_od": ("Logistics", "Container 20 ft", dict(slope=6, gap=0.35)),
    "iso_container_40_od": ("Logistics", "Container 40 ft", dict(slope=5, gap=0.4)),
    "fuel_tank_skid": ("Logistics", None, dict(slope=5, gap=0.3)),
    "supply_pallet": ("Logistics", None, dict(slope=10, gap=0.3)),
    "ammo_pallet": ("Logistics", None, dict(slope=10, gap=0.3)),
    "drum_pallet": ("Logistics", None, dict(slope=10, gap=0.3)),
    # Infrastructure
    "generator_60kw": ("Infrastructure", None, dict(slope=8, gap=0.3)),
    "light_pole": ("Infrastructure", None, dict(slope=15, gap=0.3)),
    "light_tower": ("Infrastructure", None, dict(slope=10, gap=0.3)),
    "radio_mast": ("Infrastructure", None, dict(slope=10, gap=0.5)),
    "tent_frame_6x4": ("Infrastructure", None, dict(slope=6, gap=0.4)),
    "tent_frame_10x6": ("Infrastructure", None, dict(slope=5, gap=0.4)),
    "camo_net_canopy": ("Infrastructure", None, dict(nav=False, walkable=True, slope=10, gap=0.8)),
    "field_toilet": ("Infrastructure", None, dict(slope=10, gap=0.3)),
    "sign_checkpoint": ("Infrastructure", None, dict(nav=False, walkable=True, slope=20, gap=0.3)),
    "sign_restricted": ("Infrastructure", None, dict(nav=False, walkable=True, slope=20, gap=0.3)),
    "sign_stop": ("Infrastructure", None, dict(nav=False, walkable=True, slope=20, gap=0.3)),
    "guardrail_4m": ("Infrastructure", "Guardrail", dict(linear=True, fit="PITCH", group="guardrail", slope=16, gap=0.5)),
    "road_delineator": ("Infrastructure", None, dict(nav=False, walkable=True, slope=25, gap=0.3)),
}


def g(v):
    return ("%.4f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def aabb(b):
    return "AABB(%s)" % ", ".join(g(float(x)) for x in b)


def module_length(meta):
    mod = meta.get("module") or {}
    if "length" in mod:
        return float(mod["length"])
    snaps = [m for m in meta.get("markers", []) if m["name"].startswith("SNAP_")]
    if len(snaps) == 2:
        return abs(float(snaps[0]["pos"][0]) - float(snaps[1]["pos"][0]))
    raise ValueError("%s: linear type without module length or two SNAP markers" % meta["id"])


def write(meta, category, name, opt):
    lo, hi = meta["bounds_min"], meta["bounds_max"]
    # Blender (x, y depth, z up) -> Godot size (width, height, depth); nothing below ground.
    size = [hi[0] - lo[0], hi[2] - max(lo[2], 0.0), hi[1] - lo[1]]
    linear = opt.get("linear", False)
    if linear:
        size[0] = module_length(meta)
    boxes = opt.get("boxes", meta.get("collision_boxes_godot", []))
    lines = [
        '[gd_resource type="Resource" script_class="StructureDef" load_steps=2 format=3]',
        "",
        '[ext_resource type="Script" path="res://scripts/construction/structure_def.gd" id="1_def"]',
        "",
        "[resource]",
        'script = ExtResource("1_def")',
        'id = &"%s"' % meta["id"],
        'display_name = "%s"' % (name or meta["display_name"]),
        'category = "%s"' % category,
        'description = "%s"' % meta["description"].replace('"', "'"),
        'mesh_path = "%s"' % meta["glb"] if "glb" in meta else 'mesh_path = "res://assets/military/%s/%s.glb"' % (
            "roads" if meta["family"] == "road" else "props", meta["id"]),
        "size = Vector3(%s, %s, %s)" % tuple(g(round(v, 3)) for v in size),
    ]
    if linear:
        lines += [
            "linear = true",
            "module_length = %s" % g(round(module_length(meta), 3)),
            "layout = %d" % (1 if opt.get("layout", "SPAN") == "CENTERED" else 0),
            "fit = %d" % ["LEVEL", "STEP", "PITCH", "SHEAR"].index(opt.get("fit", "LEVEL")),
            'connect_group = &"%s"' % opt.get("group", meta["id"]),
        ]
    lines += [
        "max_slope_deg = %s" % g(float(opt.get("slope", 8))),
        "max_ground_gap = %s" % g(float(opt.get("gap", 0.4))),
        "sink = %s" % g(float(opt.get("sink", 0.05))),
        "blocks_navigation = %s" % ("true" if opt.get("nav", True) else "false"),
    ]
    if opt.get("walkable"):
        lines.append("walkable = true")
    lines += [
        "collision_boxes = Array[AABB]([%s])" % ", ".join(aabb(b) for b in boxes),
        "ramps = Array[AABB]([])",
        "",
    ]
    with open(os.path.join(OUT, meta["id"] + ".tres"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def main():
    os.makedirs(OUT, exist_ok=True)
    written = []
    for asset_id, (category, name, opt) in TABLE.items():
        path = os.path.join(PROPS, asset_id + ".json")
        if not os.path.exists(path):
            path = os.path.join(ROADS, asset_id + ".json")
        with open(path, encoding="utf-8") as f:
            meta = json.load(f)
        write(meta, category, name, opt)
        written.append(asset_id)
    stale = [f for f in os.listdir(OUT) if f.endswith(".tres") and f[:-5] not in TABLE]
    for f in stale:
        os.remove(os.path.join(OUT, f))
    print("wrote %d prop StructureDefs to %s%s" % (len(written), os.path.relpath(OUT, ROOT),
                                                   ("; removed stale: %s" % stale) if stale else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
