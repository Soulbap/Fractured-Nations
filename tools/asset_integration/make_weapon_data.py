"""ASSET-INTEGRATION-01: gameplay data for the 16 WEAPON-ASSETS-01 weapons (no asset is rebuilt).

Writes, from the tables below:
  * the hold of each weapon piece into its InfantryEquipment (assets/weapons/<fac>/<id>/weapon_<id>.tres): aim_eye (sight
    line x / height and the eye's distance behind the grip, weapon space, Godot axes), support_grip, hold_shift;
    tools/asset_integration/weapon_holds.json carries the same table for build_weapons.write_equipment;
  * a WeaponDef per weapon (assets/combat/weapons/<id>.tres), copied from the existing class it belongs to (rifle,
    carbine, dmr, lmg, gpmg, launcher, recoilless) with the weapon's own magazine, rate and sight numbers; never
    procurable (no procure_* / development entry: the New Game economy does not know them);
  * a development role per weapon (assets/combat/roles/dev/dev_<id>.tres, not listed by the equipment screen);
  * a loadout per weapon and faction family (assets/characters/infantry/loadouts/<FAM>_w_<id>.tres): the family's
    rifleman with the weapon in the hands instead of the rifle and its accessories.

    python tools/asset_integration/make_weapon_data.py
Sight heights: Blender builders (fps_ads cameras, PM II / PSO-1 / launcher sight constants) and, for iron sights,
tools/asset_integration/sight_profile.gd (top-of-geometry profile along the bore).
"""
import json
import os
import re

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

# id: (faction dir, display name, template WeaponDef, overrides, aim_eye (x, y, z back), support_grip or None, primary?)
# Overrides are WeaponDef fields (GDScript literals).
WEAPONS = {
    "hk416": ("nato", "HK416N 5.56", "rifle", {"magazine_size": 30, "reserve_start": 150, "rounds_per_minute": 850.0,
              "ads_fov": 42.0}, (0.0, 0.172, 0.24), None, True),
    "hk417": ("nato", "HK417 7.62", "dmr", {"magazine_size": 20, "reserve_start": 100, "rounds_per_minute": 300.0,
              "ads_fov": 14.0}, (0.0, 0.1755, 0.24), None, True),
    "fn_minimi": ("nato", "FN Minimi 7.62 Mk3", "lmg", {"magazine_size": 100, "reserve_start": 300, "rounds_per_minute": 700.0,
                  "damage": 44.0, "ads_fov": 42.0}, (0.0, 0.156, 0.24), None, True),
    "fn_mag": ("nato", "FN MAG 7.62", "gpmg", {"magazine_size": 100, "reserve_start": 300, "rounds_per_minute": 750.0,
               "ads_fov": 42.0}, (0.0, 0.143, 0.24), (0.0, 0.040, -0.30), True),
    "glock_17": ("nato", "Glock 17 (P80) 9 mm", "carbine", {"magazine_size": 17, "reserve_start": 51, "rounds_per_minute": 450.0,
                 "allow_auto": "false", "default_mode": 0, "reload_time": 1.6, "damage": 24.0, "falloff_start": 25.0,
                 "falloff_end": 60.0, "min_damage_fraction": 0.5, "max_range": 120.0, "effective_range": 50.0,
                 "spread_base_deg": 0.25, "spread_moving_deg": 0.9, "aim_time_s": 0.3, "ai_engage_m": 60.0,
                 "recoil_pitch_deg": 1.1, "recoil_yaw_deg": 0.45, "viewmodel_kick": 0.7, "ads_fov": 55.0},
                 (0.0, 0.074, 0.45), (-0.030, -0.035, 0.020), True),
    "axmc": ("nato", "AI AXMC .338", "dmr", {"magazine_size": 10, "reserve_start": 40, "rounds_per_minute": 45.0,
             "reload_time": 3.4, "damage": 95.0, "falloff_start": 600.0, "falloff_end": 1400.0, "min_damage_fraction": 0.8,
             "max_range": 1600.0, "effective_range": 1200.0, "spread_base_deg": 0.012, "aim_time_s": 2.2,
             "ai_engage_m": 900.0, "optic_sight_m": 900.0, "aim_mult": 0.3, "recoil_pitch_deg": 2.4,
             "viewmodel_kick": 1.8, "ads_fov": 8.0}, (0.0, 0.1645, 0.24), (0.0, 0.034, -0.30), True),
    "carl_gustaf_m4": ("nato", "Carl-Gustaf M4 84 mm", "recoilless", {"reserve_start": 3}, (-0.068, 0.204, 0.26), None, False),
    "m72_law": ("nato", "M72 EC Mk1 66 mm", "launcher", {"reserve_start": 0, "max_range": 220.0, "effective_range": 150.0},
                (0.0, 0.127, 0.34), None, False),
    "ak12": ("russian", "AK-12 5.45", "rifle", {"magazine_size": 30, "reserve_start": 150, "rounds_per_minute": 700.0,
             "ads_fov": 45.0}, (0.0, 0.124, 0.24), None, True),
    "ak74m": ("russian", "AK-74M 5.45", "rifle", {"magazine_size": 30, "reserve_start": 150, "rounds_per_minute": 650.0,
              "spread_base_deg": 0.08, "ads_fov": 48.0}, (0.0, 0.114, 0.24), None, True),
    "rpk74m": ("russian", "RPK-74M 5.45", "lmg", {"magazine_size": 45, "reserve_start": 270, "rounds_per_minute": 600.0,
               "reload_time": 3.0, "ads_fov": 48.0}, (0.0, 0.114, 0.24), None, True),
    "svd": ("russian", "SVD 7.62x54R", "dmr", {"magazine_size": 10, "reserve_start": 60, "rounds_per_minute": 240.0,
            "damage": 62.0, "ads_fov": 10.0}, (-0.012, 0.152, 0.33), None, True),
    "pkp_pecheneg": ("russian", "PKP Pecheneg 7.62x54R", "gpmg", {"magazine_size": 100, "reserve_start": 300,
                     "rounds_per_minute": 650.0, "ads_fov": 42.0}, (0.0, 0.132, 0.24), (0.0, 0.045, -0.32), True),
    "mp443": ("russian", "MP-443 Grach 9 mm", "carbine", {"magazine_size": 18, "reserve_start": 54, "rounds_per_minute": 400.0,
              "allow_auto": "false", "default_mode": 0, "reload_time": 1.7, "damage": 24.0, "falloff_start": 25.0,
              "falloff_end": 60.0, "min_damage_fraction": 0.5, "max_range": 120.0, "effective_range": 50.0,
              "spread_base_deg": 0.27, "spread_moving_deg": 0.9, "aim_time_s": 0.3, "ai_engage_m": 60.0,
              "recoil_pitch_deg": 1.2, "recoil_yaw_deg": 0.5, "viewmodel_kick": 0.7, "ads_fov": 55.0},
              (0.0, 0.076, 0.45), (-0.030, -0.035, 0.020), True),
    "rpg7": ("russian", "RPG-7V2 (PG-7V)", "launcher", {"reserve_start": 2, "reload_time": 5.0, "max_range": 330.0,
             "effective_range": 250.0}, (-0.064, 0.174, 0.28), None, False),
    "rpg26": ("russian", "RPG-26 Aglen 72.5 mm", "launcher", {"reserve_start": 0, "max_range": 250.0, "effective_range": 180.0},
              (0.0, 0.1223, 0.32), None, False),
}
# Launchers are secondary weapons: the dev role carries the family's named rifle with them, rounds = tubes / rockets.
LAUNCHER_ROUNDS = {"carl_gustaf_m4": 4, "m72_law": 1, "rpg7": 3, "rpg26": 1}
LAUNCHER_RIFLE = {"nato": "hk416", "russian": "ak12"}
FAMILIES = {"NATO": "NATO_rifleman", "RU": "RU_rifleman", "CN": "CN_rifleman"}
SHORT = {"hk416": "416", "hk417": "417", "fn_minimi": "MIN", "fn_mag": "MAG", "glock_17": "P80", "axmc": "AX",
         "carl_gustaf_m4": "CG", "m72_law": "M72", "ak12": "AK12", "ak74m": "AK74", "rpk74m": "RPK", "svd": "SVD",
         "pkp_pecheneg": "PKP", "mp443": "MP443", "rpg7": "RPG7", "rpg26": "RPG26"}
DROP = ("procure_cost", "procure_ammo", "procure_facility", "needs_discovery")


def path(*p):
    return os.path.join(ROOT, *p)


def vec(v):
    return "Vector3(%s, %s, %s)" % tuple(repr(float(x)) for x in v)


def piece_res(wid):
    fac = WEAPONS[wid][0]
    return "res://assets/weapons/%s/%s/weapon_%s.tres" % (fac, wid, wid)


def set_field(txt, key, value):
    line = "%s = %s" % (key, value)
    if re.search(r"^%s = .*$" % re.escape(key), txt, re.M):
        return re.sub(r"^%s = .*$" % re.escape(key), line, txt, flags=re.M)
    return txt.rstrip("\n") + "\n" + line + "\n"


def write_holds():
    holds = {}
    for wid, (fac, _, _, _, eye, support, _) in WEAPONS.items():
        holds["weapon_" + wid] = {"aim_eye": list(eye), "support_grip": list(support) if support else [0.0, 0.0, 0.0],
                                  "hold_shift": [0.0, 0.0, 0.0]}
        p = path("assets", "weapons", fac, wid, "weapon_%s.tres" % wid)
        txt = open(p, encoding="utf-8").read()
        h = holds["weapon_" + wid]
        for k in ("aim_eye", "support_grip", "hold_shift"):
            txt = set_field(txt, k, vec(h[k]))
        open(p, "w", encoding="utf-8", newline="\n").write(txt)
    with open(path("tools", "asset_integration", "weapon_holds.json"), "w", encoding="utf-8") as f:
        json.dump(holds, f, indent=1)


def write_weapon_defs():
    os.makedirs(path("assets", "combat", "weapons"), exist_ok=True)
    for wid, (fac, name, tmpl, over, _, _, primary) in WEAPONS.items():
        txt = open(path("assets", "combat", tmpl + ".tres"), encoding="utf-8").read()
        txt = "\n".join(l for l in txt.split("\n") if not l.split(" = ")[0] in DROP) + "\n"
        txt = set_field(txt, "id", '&"%s"' % wid)
        txt = set_field(txt, "display_name", '"%s"' % name)
        for k, v in over.items():
            txt = set_field(txt, k, v if isinstance(v, str) else repr(v))
        if not primary:
            glb = "res://assets/weapons/%s/%s/weapon_%s.glb" % (fac, wid, wid)
            txt = re.sub(r'(\[ext_resource type="PackedScene" path=")[^"]+(" id="2_vm"\])', r"\g<1>%s\g<2>" % glb, txt)
            txt = txt.replace('id="2_vm"]\n', 'id="2_vm"]\n[ext_resource type="Resource" path="%s" id="3_piece"]\n' % piece_res(wid), 1)
            txt = re.sub(r"load_steps=\d+", "load_steps=4", txt)
            txt = set_field(txt, "held_piece", 'ExtResource("3_piece")')
        open(path("assets", "combat", "weapons", wid + ".tres"), "w", encoding="utf-8", newline="\n").write(txt)


def write_roles():
    os.makedirs(path("assets", "combat", "roles", "dev"), exist_ok=True)
    for wid, (fac, name, _, _, _, _, primary) in WEAPONS.items():
        weapon = wid if primary else LAUNCHER_RIFLE[fac]
        sec = "" if primary else wid
        txt = ('[gd_resource type="Resource" script_class="InfantryRole" format=3]\n\n'
               '[ext_resource type="Script" path="res://scripts/combat/infantry_role.gd" id="1_role"]\n\n'
               '[resource]\nscript = ExtResource("1_role")\nid = &"dev_%s"\ndisplay_name = "%s (development armoury)"\n'
               'short = "%s"\nweapon_id = &"%s"\nloadout_suffix = "w_%s"\ngrenades = 2\nsecondary_id = &"%s"\n'
               'secondary_rounds = %d\n') % (wid, name, SHORT[wid], weapon, weapon, sec, LAUNCHER_ROUNDS.get(wid, 0))
        open(path("assets", "combat", "roles", "dev", "dev_%s.tres" % wid), "w", encoding="utf-8", newline="\n").write(txt)


def write_loadouts():
    lo_dir = path("assets", "characters", "infantry", "loadouts")
    for fam, base in FAMILIES.items():
        src = open(os.path.join(lo_dir, base + ".tres"), encoding="utf-8").read()
        ext = dict(re.findall(r'\[ext_resource type="Resource" path="([^"]+)" id="([^"]+)"\]', src))
        items = re.search(r"items = Array\[ExtResource\(\"2_eq\"\)\]\(\[(.*)\]\)", src).group(1)
        order = re.findall(r'ExtResource\("([^"]+)"\)', items)
        by_id = {v: k for k, v in ext.items()}
        keep = []
        for rid in order:
            p = by_id[rid]
            body = open(path(*p.replace("res://", "").split("/")), encoding="utf-8").read()
            slot = re.search(r'^slot = "([^"]*)"', body, re.M)
            if slot and slot.group(1).startswith("weapon"):
                continue
            keep.append(p)
        for wid, (fac, name, _, _, _, _, primary) in WEAPONS.items():
            if not primary:
                continue
            pieces = keep + [piece_res(wid)]
            lines = ['[gd_resource type="Resource" script_class="InfantryLoadout" load_steps=%d format=3]\n' % (len(pieces) + 3),
                     '[ext_resource type="Script" path="res://scripts/characters/infantry_loadout.gd" id="1_lo"]',
                     '[ext_resource type="Script" path="res://scripts/characters/infantry_equipment.gd" id="2_eq"]']
            refs = []
            for i, p in enumerate(pieces):
                rid = "%d_%s" % (i + 3, os.path.basename(p).replace(".tres", ""))
                lines.append('[ext_resource type="Resource" path="%s" id="%s"]' % (p, rid))
                refs.append('ExtResource("%s")' % rid)
            lines += ["", "[resource]", 'script = ExtResource("1_lo")', 'id = "%s_w_%s"' % (fam, wid),
                      'display_name = "%s rifleman with the %s (development armoury)"' % (fam, name),
                      'items = Array[ExtResource("2_eq")]([%s])' % ", ".join(refs), ""]
            open(os.path.join(lo_dir, "%s_w_%s.tres" % (fam, wid)), "w", encoding="utf-8", newline="\n").write("\n".join(lines))


if __name__ == "__main__":
    write_holds()
    write_weapon_defs()
    write_roles()
    write_loadouts()
    print("weapons:", len(WEAPONS), "loadouts:", sum(1 for w in WEAPONS.values() if w[6]) * len(FAMILIES))
