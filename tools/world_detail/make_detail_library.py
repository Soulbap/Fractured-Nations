"""WORLD-DETAIL-02: adds the man-made cover and yard kit to the vegetation library as ids 31-49 and writes the kit table the
placement layer reads.

    python tools/world_detail/make_detail_library.py

The kit is the static asset library's GLBs (assets/military/props|roads/*.glb: the new civilian props of
tools/blender/asset_production/fam_props_civil.py and existing military / road props). Each id's collider is the union of its
variants' collision boxes from their sidecars (`collision_boxes_godot`); several boxes or an off-centre box become per-variant
`parts` (VegetationMeshDef.boxes_of), so every reader - LineOfFire, InstanceColliderStreamer, StructureManager, AreaNavigation,
CombatBrain cover search - sees the solid shape. Ids marked `solid: False` (picket fence, guardrail, chain-link, signs) are
drawn only: thin boards and rails neither stop bullets nor are cover.

Writes:
  assets/environment/nordic_library.tres   sub-resources Resource_wd2_<id> (replaced on every run) + the meshes list
  assets/environment/detail_kit.json       id -> name, footprint half length / depth, height, solid (DetailLayer)
"""
import json
import math
import os
import re

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LIB = os.path.join(REPO, "assets", "environment", "nordic_library.tres")
KIT = os.path.join(REPO, "assets", "environment", "detail_kit.json")

# id: (name, [glb paths relative to assets/military], solid, max_range)
KIT_IDS = {
    31: ("Round bales", ["props/round_bales_white", "props/round_bales_green"], True, 800),
    32: ("Firewood stack", ["props/firewood_stack"], True, 600),
    33: ("Garden wall", ["props/garden_wall_concrete", "props/garden_wall_stone"], True, 700),
    34: ("Picket fence", ["props/picket_fence"], False, 260),
    35: ("Concrete blocks", ["props/concrete_blocks"], True, 700),
    36: ("Concrete pipes", ["props/concrete_pipes"], True, 700),
    37: ("Skip container", ["props/skip_green", "props/skip_yellow"], True, 700),
    38: ("Transformer kiosk", ["props/transformer_kiosk"], True, 900),
    39: ("Pallets and materials", ["props/material_stack"], True, 700),
    40: ("Concrete barrier", ["props/jersey_barrier"], True, 800),
    41: ("HESCO line", ["props/hesco_mil1_5"], True, 1200),
    42: ("Sandbag wall", ["props/sandbag_wall_2m", "props/sandbag_wall_green_2m"], True, 700),
    43: ("T-wall", ["props/t_wall"], True, 1000),
    44: ("Container 20 ft", ["props/iso_container_20_rust", "props/iso_container_20_blue"], True, 1200),
    45: ("Container 20 ft (military)", ["props/iso_container_20_od", "props/iso_container_20_tan"], True, 1200),
    46: ("Guardrail", ["roads/guardrail_4m"], False, 400),
    47: ("Chain-link fence", ["props/chainlink_fence"], False, 400),
    48: ("Yard goods", ["props/ibc_tank", "props/drum_pallet", "props/supply_pallet", "props/crate_large"], True, 400),
    49: ("Log barricade", ["props/log_barricade"], True, 600),
}


def sidecar(rel):
    with open(os.path.join(REPO, "assets", "military", rel + ".json"), encoding="utf-8") as f:
        return json.load(f)


def boxes(rel):
    """[centre x, centre z, half x, height, half z] per collision box (Godot frame, base on the origin)."""
    out = []
    for b in sidecar(rel).get("collision_boxes_godot", []):
        x0, y0, z0, sx, sy, sz = b
        out.append([x0 + sx / 2, z0 + sz / 2, sx / 2, y0 + sy, sz / 2])
    return out


def main():
    subs, kit = [], {}
    for mid, (name, glbs, solid, max_r) in KIT_IDS.items():
        side = sidecar(glbs[0])
        ranges = side.get("lod_ranges") or [[0, 40], [40, 140], [140, max_r]]
        per_var = [boxes(g) for g in glbs]
        bx = [b for v in per_var for b in v]
        # The id's box: symmetric about the origin, holding every variant's boxes.
        hx = max((abs(b[0]) + b[2] for b in bx), default=0.0)
        hz = max((abs(b[1]) + b[4] for b in bx), default=0.0)
        h = max((b[3] for b in bx), default=0.0)
        sizes = [sidecar(g)["size_above_ground"] for g in glbs]
        foot_x = max(hx, max(s[0] for s in sizes) / 2)
        foot_z = max(hz, max(s[1] for s in sizes) / 2)
        lines = ['[sub_resource type="Resource" id="Resource_wd2_%d"]' % mid, 'script = ExtResource("1_xbpqk")', "id = %d" % mid,
                 'name = "%s"' % name, 'scene = ExtResource("wd2_%s")' % os.path.basename(glbs[0]),
                 "near_range = %.1f" % ranges[0][1], "mid_range = %.1f" % ranges[1][1], "max_range = %.1f" % max_r]
        if solid and bx:
            lines.append("collider = Vector3(2, %.3f, 0)" % math.hypot(hx, hz))
            lines.append("box = Vector3(%.3f, %.3f, %.3f)" % (hx, h, hz))
            # Per-variant parts where one centred box would misstate the solid (several boxes, an off-centre box, or
            # variants of different size).
            exact = all(len(v) == 1 and abs(v[0][0]) < 0.02 and abs(v[0][1]) < 0.02 and abs(v[0][2] - hx) < 0.03
                        and abs(v[0][4] - hz) < 0.03 and abs(v[0][3] - h) < 0.03 for v in per_var)
            if not exact:
                parts = []
                for v in per_var:
                    vals = []
                    for b in v:
                        vals += [2.0, b[0], b[1], b[2], b[3], b[4]]
                    parts.append("PackedFloat32Array(%s)" % ", ".join("%.3f" % x for x in vals))
                lines.append("parts = Array[PackedFloat32Array]([%s])" % ", ".join(parts))
        if len(glbs) > 1:
            lines.append("variants = Array[PackedScene]([%s])" % ", ".join('ExtResource("wd2_%s")' % os.path.basename(g) for g in glbs[1:]))
        subs.append("\n".join(lines))
        kit[str(mid)] = {"name": name, "foot": [round(foot_x, 3), round(foot_z, 3)], "height": round(max(h, max(s[2] for s in sizes)), 3),
                         "solid": solid, "glb": glbs}
    with open(LIB, encoding="utf-8") as f:
        txt = f.read()
    # Drop an earlier run's entries.
    txt = re.sub(r'\[ext_resource type="PackedScene" path="[^"]*" id="wd2_[^"]*"\]\n', "", txt)
    txt = re.sub(r'\[sub_resource type="Resource" id="Resource_wd2_\d+"\]\n(?:[^\[\n][^\n]*\n)*\n?', "", txt)
    txt = re.sub(r', SubResource\("Resource_wd2_\d+"\)', "", txt)
    ext = "".join('[ext_resource type="PackedScene" path="res://assets/military/%s.glb" id="wd2_%s"]\n' % (g, os.path.basename(g))
                  for _, glbs, _, _ in KIT_IDS.values() for g in glbs)
    first_sub = txt.index("[sub_resource")
    txt = txt[:first_sub] + ext + "\n" + txt[first_sub:]
    res = txt.index("\n[resource]")
    txt = txt[:res] + "\n" + "\n\n".join(subs) + "\n" + txt[res:]
    ids = ", ".join('SubResource("Resource_wd2_%d")' % mid for mid in KIT_IDS)
    txt = re.sub(r'(meshes = Array\[ExtResource\("1_xbpqk"\)\]\(\[.*?)\]\)', lambda m: m.group(1) + ", " + ids + "])", txt, count=1, flags=re.S)
    txt = txt.replace("\n\n\n[", "\n\n[")
    with open(LIB, "w", encoding="utf-8", newline="\n") as f:
        f.write(txt)
    with open(KIT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(kit, f, indent=1)
    print("WD2 library ids", list(KIT_IDS), "->", LIB)


if __name__ == "__main__":
    main()
