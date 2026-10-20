"""The shared infantry material set. Names are the contract with Godot: the loader
(scripts/characters/infantry_materials.gd) maps each glTF material name to one shared
StandardMaterial3D, so every piece and every soldier uses the same few materials.

name: (base colour sRGB, roughness, metallic, albedo key, normal key, normal strength, uv tile m)
"""
import char_lib as L
import char_textures as T

MATERIALS = {
    "Camo_M23":            ((1.00, 1.00, 1.00), 0.88, 0.0, "camo", "ripstop_n", 0.3, T.TILE_FABRIC_M),
    "Fabric_RangerGreen":  ((0.36, 0.38, 0.28), 0.90, 0.0, None, "ripstop_n", 0.6, T.TILE_FABRIC_M),
    "Webbing_RangerGreen": ((0.33, 0.35, 0.26), 0.86, 0.0, "pals", "pals_n", 1.0, T.TILE_WEBBING_M),
    "Webbing_Coyote":      ((0.55, 0.46, 0.33), 0.86, 0.0, "pals", "pals_n", 1.0, T.TILE_WEBBING_M),
    "Cordura_RangerGreen": ((0.33, 0.35, 0.26), 0.88, 0.0, None, "cordura_n", 0.8, T.TILE_WEBBING_M),
    "Cordura_Coyote":      ((0.56, 0.47, 0.34), 0.88, 0.0, None, "cordura_n", 0.8, T.TILE_WEBBING_M),
    "Strap_Black":         ((0.07, 0.07, 0.07), 0.80, 0.0, None, "cordura_n", 0.6, T.TILE_WEBBING_M),
    "Glove_Coyote":        ((0.58, 0.49, 0.36), 0.82, 0.0, None, "cordura_n", 0.7, 0.15),
    "Boot_Leather":        ((0.075, 0.068, 0.062), 0.55, 0.0, "leather", "leather_n", 0.8, 0.25),
    "Boot_Sole":           ((0.04, 0.04, 0.04), 0.90, 0.0, None, None, 1.0, 0.25),
    "Helmet_Shell":        ((0.30, 0.32, 0.25), 0.78, 0.0, "polymer", "polymer_n", 0.6, T.TILE_HARD_M),
    "Polymer_Black":       ((0.050, 0.050, 0.052), 0.62, 0.0, "polymer", "polymer_n", 0.7, T.TILE_HARD_M),
    "Polymer_OD":          ((0.18, 0.19, 0.15), 0.70, 0.0, "polymer", "polymer_n", 0.7, T.TILE_HARD_M),
    "Metal_Black":         ((0.045, 0.045, 0.048), 0.42, 0.85, "polymer", "polymer_n", 0.5, T.TILE_HARD_M),
    "Metal_Worn":          ((0.30, 0.30, 0.31), 0.35, 1.0, "polymer", "polymer_n", 0.5, T.TILE_HARD_M),
    "Lens":                ((0.02, 0.025, 0.03), 0.05, 0.3, None, None, 1.0, 1.0),
    "Lens_Tinted":         ((0.30, 0.22, 0.10), 0.05, 0.5, None, None, 1.0, 1.0),
    "Patch":               ((0.30, 0.55, 1.00), 0.60, 0.0, None, None, 1.0, 1.0),
    "Rubber_Black":        ((0.035, 0.035, 0.035), 0.85, 0.0, None, None, 1.0, 1.0),
    "Skin":                ((1.00, 1.00, 1.00), 0.60, 0.0, "skin", None, 1.0, 1.0),
    "SkinBody":            ((0.76, 0.58, 0.47), 0.60, 0.0, None, None, 1.0, 1.0),
    "Eye":                 ((0.80, 0.77, 0.72), 0.20, 0.0, None, None, 1.0, 1.0),
    "Iris":                ((0.10, 0.12, 0.13), 0.10, 0.0, None, None, 1.0, 1.0),
}


def build(tex):
    out = {}
    for name, (col, rough, metal, alb, nrm, ns, _) in MATERIALS.items():
        out[name] = L.pbr_material(name, col, rough, metal, albedo=tex.get(alb) if alb else None,
                                   normal=tex.get(nrm) if nrm else None, normal_strength=ns)
    return out


def tile_of(name):
    return MATERIALS.get(name, (None, 0, 0, None, None, 1, 0.5))[6]


def apply_box_uvs(obj):
    """Box-projects each material's faces at that material's tile size."""
    import math
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    tiles = [tile_of(m.name) if m else 0.5 for m in me.materials]
    for p in me.polygons:
        t = tiles[p.material_index] if p.material_index < len(tiles) else 0.5
        if me.materials and me.materials[p.material_index] and me.materials[p.material_index].name in ("Skin",):
            continue
        n = p.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if ax == 0:
                u, v = co.y * math.copysign(1, n.x), co.z
            elif ax == 1:
                u, v = -co.x * math.copysign(1, n.y), co.z
            else:
                u, v = co.x, co.y * math.copysign(1, n.z)
            uv[li].uv = (u / t, v / t)
