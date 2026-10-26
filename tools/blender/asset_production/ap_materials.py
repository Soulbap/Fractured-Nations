"""Shared material library of the ASSET-PRODUCTION-01 static assets (buildings, base
modules, props, road kit, vehicles).

One table drives both sides:
  * Blender: Principled materials for previews (texture x tint x vertex colour).
  * Godot: one StandardMaterial3D .tres per name in assets/military/materials/, written
    by write_godot_materials(). GLBs carry material NAMES only (no images); the import
    script tools/asset_lab/ap_post_import.gd swaps every surface for the library
    material of the same name, so all assets share these few materials and textures.

UVs are world-scale box projections: one UV unit = `tile` metres (ap_lib.box_uvs), so
textures keep their real-world size on every asset. Vertex colours carry baked ground
dirt / contact darkening and are multiplied into the albedo (vertex_color_use_as_albedo).

name: dict(alb, nrm, col (sRGB tint), rough, metal, ns (normal scale), tile (m), flags)
flags: "blend" alpha blend, "scissor" alpha test, "double" no culling, "emit" emissive,
       "keep_uv" faces keep authored UVs (atlases).
"""
import os

import char_lib as L

TEX_RES = "res://assets/military/textures/"
MAT_RES = "res://assets/military/materials/"


def _m(alb, nrm, col, rough, metal=0.0, ns=1.0, tile=1.0, flags=()):
    return {"alb": alb, "nrm": nrm, "col": col, "rough": rough, "metal": metal, "ns": ns, "tile": tile, "flags": set(flags)}


PAINT_TILE = 3.0
CONT_TILE = 2.24
ROOF_TILE = 2.432

MATERIALS = {
    # Painted steel (one greyscale texture, many tints).
    "Paint_OD":        _m("paint", "paint_normal", (0.30, 0.32, 0.23), 0.72, 0.15, 0.6, PAINT_TILE),
    "Paint_Green":     _m("paint", "paint_normal", (0.23, 0.27, 0.19), 0.70, 0.15, 0.6, PAINT_TILE),
    "Paint_Tan":       _m("paint", "paint_normal", (0.64, 0.57, 0.44), 0.74, 0.12, 0.6, PAINT_TILE),
    "Paint_Grey":      _m("paint", "paint_normal", (0.46, 0.47, 0.47), 0.66, 0.20, 0.6, PAINT_TILE),
    "Paint_White":     _m("paint", "paint_normal", (0.84, 0.84, 0.81), 0.62, 0.10, 0.6, PAINT_TILE),
    "Paint_Black":     _m("paint", "paint_normal", (0.07, 0.07, 0.07), 0.60, 0.20, 0.6, PAINT_TILE),
    "Paint_Yellow":    _m("paint", "paint_normal", (0.86, 0.66, 0.12), 0.60, 0.10, 0.6, PAINT_TILE),
    "Paint_Red":       _m("paint", "paint_normal", (0.62, 0.13, 0.10), 0.60, 0.10, 0.6, PAINT_TILE),
    "Paint_RoadWhite": _m("paint", None, (0.88, 0.88, 0.85), 0.75, 0.0, 1.0, PAINT_TILE),
    "Paint_RoadYellow": _m("paint", None, (0.90, 0.70, 0.15), 0.75, 0.0, 1.0, PAINT_TILE),
    # ISO container side walls (corrugated, 8 ribs per tile).
    "Container_OD":    _m("paint", "container_ribs_normal", (0.30, 0.32, 0.23), 0.72, 0.15, 1.0, CONT_TILE),
    "Container_Tan":   _m("paint", "container_ribs_normal", (0.62, 0.55, 0.42), 0.74, 0.12, 1.0, CONT_TILE),
    "Container_Blue":  _m("paint", "container_ribs_normal", (0.16, 0.26, 0.40), 0.68, 0.15, 1.0, CONT_TILE),
    "Container_Rust":  _m("paint", "container_ribs_normal", (0.46, 0.22, 0.14), 0.75, 0.15, 1.0, CONT_TILE),
    "Container_Grey":  _m("paint", "container_ribs_normal", (0.50, 0.51, 0.50), 0.68, 0.18, 1.0, CONT_TILE),
    "Container_White": _m("paint", "container_ribs_normal", (0.80, 0.80, 0.77), 0.64, 0.10, 1.0, CONT_TILE),
    # Corrugated roof sheet (bare galvanized and painted).
    "Roof_Galv":       _m("galvanized", "roof_sheet_normal", (0.74, 0.75, 0.74), 0.52, 0.60, 1.0, ROOF_TILE),
    "Roof_OD":         _m("paint", "roof_sheet_normal", (0.29, 0.31, 0.22), 0.70, 0.15, 1.0, ROOF_TILE),
    "Roof_Tan":        _m("paint", "roof_sheet_normal", (0.60, 0.54, 0.42), 0.72, 0.12, 1.0, ROOF_TILE),
    # Bare metal.
    "Steel_Galv":      _m("galvanized", "galvanized_normal", (0.78, 0.79, 0.78), 0.45, 0.85, 0.6, 1.0),
    "Steel_Dark":      _m("galvanized", "galvanized_normal", (0.20, 0.20, 0.20), 0.50, 0.80, 0.6, 1.0),
    # Masonry and ground surfaces.
    "Concrete":        _m("concrete", "concrete_normal", (1.0, 1.0, 1.0), 0.90, 0.0, 0.6, 3.0),
    "Concrete_Dark":   _m("concrete", "concrete_normal", (0.78, 0.77, 0.74), 0.92, 0.0, 0.6, 3.0),
    "Concrete_Block":  _m("cmu", "cmu_normal", (1.0, 1.0, 1.0), 0.92, 0.0, 0.8, 1.6),
    "Asphalt":         _m("asphalt", "asphalt_normal", (1.0, 1.0, 1.0), 0.88, 0.0, 0.7, 4.0),
    "Gravel":          _m("gravel", "gravel_normal", (1.0, 1.0, 1.0), 0.95, 0.0, 1.0, 2.0),
    "Gravel_Dark":     _m("gravel", "gravel_normal", (0.80, 0.78, 0.74), 0.95, 0.0, 1.0, 2.0),
    # AI-SQUAD-01: granite boulders (the gravel grain, grey with a cool cast, large tile so it reads as stone).
    "Rock":            _m("concrete", "concrete_normal", (0.62, 0.62, 0.60), 0.96, 0.0, 1.0, 2.2),
    "Dirt":            _m("dirt", "dirt_normal", (1.0, 1.0, 1.0), 0.97, 0.0, 1.0, 4.0),
    # Soft goods.
    "Canvas_OD":       _m("canvas", "canvas_normal", (0.34, 0.36, 0.26), 0.92, 0.0, 0.7, 2.0, ("double",)),
    "Canvas_Tan":      _m("canvas", "canvas_normal", (0.62, 0.56, 0.43), 0.92, 0.0, 0.7, 2.0, ("double",)),
    "Canvas_Green":    _m("canvas", "canvas_normal", (0.26, 0.30, 0.22), 0.92, 0.0, 0.7, 2.0, ("double",)),
    "Canvas_White":    _m("canvas", "canvas_normal", (0.80, 0.79, 0.74), 0.90, 0.0, 0.7, 2.0, ("double",)),
    "Sandbag":         _m("canvas", "canvas_normal", (0.60, 0.53, 0.39), 0.95, 0.0, 1.0, 1.0),
    "Sandbag_Green":   _m("canvas", "canvas_normal", (0.33, 0.35, 0.25), 0.95, 0.0, 1.0, 1.0),
    # WORLD-DETAIL-02: stretch film of wrapped round bales (glossy, faint weave of the overlapping wraps).
    "Wrap_White":      _m("canvas", "canvas_normal", (0.86, 0.87, 0.84), 0.38, 0.0, 0.35, 1.6),
    "Wrap_Green":      _m("canvas", "canvas_normal", (0.30, 0.38, 0.27), 0.40, 0.0, 0.35, 1.6),
    "Hesco_Liner":     _m("hesco_liner", "hesco_liner_normal", (1.0, 1.0, 1.0), 0.95, 0.0, 0.6, 0.608),
    "Hesco_Mesh":      _m("wire_mesh", None, (1.0, 1.0, 1.0), 0.55, 0.6, 1.0, 0.608, ("blend", "double")),
    "Chainlink":       _m("chainlink", None, (1.0, 1.0, 1.0), 0.50, 0.7, 1.0, 0.40, ("blend", "double")),
    "Camo_Net":        _m("camo_net", None, (1.0, 1.0, 1.0), 0.95, 0.0, 1.0, 2.0, ("scissor", "double")),
    # Timber.
    "Timber":          _m("wood", "wood_normal", (1.0, 1.0, 1.0), 0.85, 0.0, 0.8, 1.2),
    "Plywood":         _m("wood", "wood_normal", (1.18, 1.12, 1.02), 0.85, 0.0, 0.5, 1.2),
    "Timber_Dark":     _m("wood", "wood_normal", (0.62, 0.58, 0.52), 0.88, 0.0, 0.8, 1.2),
    # Small parts.
    # VEHICLE-ASSETS-01: NATO three-colour camouflage (green / brown / black, as on Norwegian
    # Army vehicles) painted into the texture itself (no tint), tile 7 m so a hull shows one or
    # two patterns; tyre rubber with the rubber texture (not folded into the palette).
    "Camo_NATO3":      _m("camo_nato3", "paint_normal", (1.0, 1.0, 1.0), 0.74, 0.12, 0.6, 7.0),
    "Tyre":            _m("rubber", "rubber_normal", (0.13, 0.13, 0.125), 0.90, 0.0, 1.0, 0.6),
    "Rubber":          _m("rubber", "rubber_normal", (0.09, 0.09, 0.09), 0.90, 0.0, 0.8, 0.5),
    "Plastic_Black":   _m("rubber", None, (0.06, 0.06, 0.06), 0.60, 0.0, 1.0, 0.5),
    "Plastic_White":   _m("rubber", None, (0.85, 0.85, 0.82), 0.55, 0.0, 1.0, 0.5),
    "Plastic_Orange":  _m("rubber", None, (0.85, 0.32, 0.06), 0.55, 0.0, 1.0, 0.5),
    "Plastic_OD":      _m("rubber", None, (0.27, 0.29, 0.21), 0.65, 0.0, 1.0, 0.5),
    "Glass":           _m(None, None, (0.05, 0.07, 0.08), 0.06, 0.2, 1.0, 1.0),
    # VEHICLE-ASSETS-01: see-through armoured glass of vehicle LOD0 (cabins have interiors);
    # the 4th colour component is the alpha (blend). LOD1/2 keep the opaque "Glass".
    "Glass_Vehicle":   _m(None, None, (0.16, 0.20, 0.21, 0.42), 0.04, 0.3, 1.0, 1.0, ("blend",)),
    "Lamp":            _m(None, None, (1.0, 0.95, 0.82), 0.30, 0.0, 1.0, 1.0, ("emit",)),
    "Reflector_Red":   _m(None, None, (0.75, 0.05, 0.03), 0.25, 0.0, 1.0, 1.0),
    # Atlases (authored UVs).
    "Signs":           _m("signs", None, (1.0, 1.0, 1.0), 0.55, 0.0, 1.0, 1.0, ("keep_uv",)),
    "Kit_Palette":     _m("palette", None, (1.0, 1.0, 1.0), 1.0, 1.0, 1.0, 1.0, ("keep_uv", "palette")),
}

# Small flat-coloured parts (hardware, glass, lamps, rubber, plastics, small painted
# parts) are folded into ONE material, Kit_Palette: a 256 px texture of 32 px swatches
# (albedo, roughness/metal in palette_orm G/B, emission). Faces of these materials get
# the swatch centre as UV at build time, so a building's small parts cost one surface.
PALETTE = ["Paint_Grey", "Paint_White", "Paint_Black", "Paint_Yellow", "Paint_Red", "Steel_Galv", "Steel_Dark",
           "Rubber", "Plastic_Black", "Plastic_White", "Plastic_Orange", "Plastic_OD", "Glass", "Lamp", "Reflector_Red"]
PAL_GRID = 8


def palette_uv(name):
    i = PALETTE.index(name)
    c, r = i % PAL_GRID, i // PAL_GRID
    return ((c + 0.5) / PAL_GRID, 1.0 - (r + 0.5) / PAL_GRID)


def build_palette(tex_dir, n=256):
    """Writes palette.png (sRGB albedo = tint x mean of the material's texture),
    palette_orm.png (R 1, G roughness, B metallic) and palette_emission.png."""
    import bpy
    import numpy as np
    alb = np.zeros((n, n, 3), np.float32)
    orm = np.zeros((n, n, 3), np.float32)
    emi = np.zeros((n, n, 3), np.float32)
    orm[..., 0] = 1.0
    orm[..., 1] = 0.8
    lin = lambda c: np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    srgb = lambda c: np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.maximum(c, 0), 1 / 2.4) - 0.055)
    means = {}
    for name in PALETTE:
        m = MATERIALS[name]
        tint = lin(np.array(m["col"], np.float32))
        if m["alb"]:
            if m["alb"] not in means:
                img = bpy.data.images.load(os.path.join(tex_dir, m["alb"] + ".png"))
                px = np.array(img.pixels[:], np.float32).reshape(-1, 4)[:, :3]   # linear (decoded sRGB)
                means[m["alb"]] = px.mean(axis=0)
                bpy.data.images.remove(img)
            tint = tint * means[m["alb"]]
        i = PALETTE.index(name)
        c, r = i % PAL_GRID, i // PAL_GRID
        s = n // PAL_GRID
        ys, xs = slice(r * s, (r + 1) * s), slice(c * s, (c + 1) * s)
        alb[ys, xs] = srgb(tint)
        orm[ys, xs, 1] = m["rough"]
        orm[ys, xs, 2] = m["metal"]
        if "emit" in m["flags"]:
            emi[ys, xs] = m["col"]
    L.save_png(os.path.join(tex_dir, "palette.png"), alb)
    L.save_png(os.path.join(tex_dir, "palette_orm.png"), orm)
    L.save_png(os.path.join(tex_dir, "palette_emission.png"), emi)


def tile_of(name):
    m = MATERIALS.get(name)
    return m["tile"] if m else 1.0


def keeps_uv(name):
    m = MATERIALS.get(name)
    return bool(m and "keep_uv" in m["flags"])


def blender_material(name, tex_dir):
    """Preview material: tint x texture x vertex colour, normal map, alpha as flagged."""
    import bpy
    m = MATERIALS[name]
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    if "palette" in m["flags"]:
        return _palette_blender(tex_dir)
    path = lambda k: os.path.join(tex_dir, k + ".png") if k else None
    alb = path(m["alb"])
    if alb and not os.path.exists(alb):
        alb = None
    nrm = path(m["nrm"])
    if nrm and not os.path.exists(nrm):
        nrm = None
    col = tuple(min(c, 1.0) for c in m["col"][:3])
    mat = L.pbr_material(name, col, m["rough"], m["metal"], albedo=alb, normal=nrm, normal_strength=m["ns"])
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    # Multiply the vertex colour (baked dirt) into whatever feeds the base colour.
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    src = bsdf.inputs["Base Color"].links[0].from_socket if bsdf.inputs["Base Color"].links else None
    if src is not None:
        nt.links.new(src, mix.inputs[6])
    else:
        mix.inputs[6].default_value = bsdf.inputs["Base Color"].default_value
    nt.links.new(vc.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    if "blend" in m["flags"] and not alb and len(m["col"]) > 3:
        bsdf.inputs["Alpha"].default_value = m["col"][3]
        mat.surface_render_method = "BLENDED"
    if ("blend" in m["flags"] or "scissor" in m["flags"]) and alb:
        tex = [n for n in nt.nodes if n.type == "TEX_IMAGE" and n.image and n.image.colorspace_settings.name == "sRGB"][0]
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        mat.surface_render_method = "DITHERED"
    if "emit" in m["flags"]:
        bsdf.inputs["Emission Color"].default_value = (*[L.srgb_to_linear(c) for c in col], 1.0)
        bsdf.inputs["Emission Strength"].default_value = 3.0
    mat.use_backface_culling = "double" not in m["flags"]
    return mat


def _palette_blender(tex_dir):
    import bpy
    mat = bpy.data.materials.new("Kit_Palette")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")

    def tex(fn, non_color):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = L.load_image(os.path.join(tex_dir, fn), non_color=non_color)
        t.interpolation = "Closest"
        return t
    a, o, e = tex("palette.png", False), tex("palette_orm.png", True), tex("palette_emission.png", False)
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(a.outputs["Color"], mix.inputs[6])
    nt.links.new(vc.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(o.outputs["Color"], sep.inputs[0])
    nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs[2], bsdf.inputs["Metallic"])
    nt.links.new(e.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 3.0
    return mat


PALETTE_TRES = """[gd_resource type="StandardMaterial3D" load_steps=4 format=3]

[ext_resource type="Texture2D" path="res://assets/military/textures/palette.png" id="1_alb"]
[ext_resource type="Texture2D" path="res://assets/military/textures/palette_orm.png" id="2_orm"]
[ext_resource type="Texture2D" path="res://assets/military/textures/palette_emission.png" id="3_emi"]

[resource]
resource_name = "Kit_Palette"
vertex_color_use_as_albedo = true
albedo_texture = ExtResource("1_alb")
metallic = 1.0
metallic_specular = 0.5
metallic_texture = ExtResource("2_orm")
metallic_texture_channel = 2
roughness = 1.0
roughness_texture = ExtResource("2_orm")
roughness_texture_channel = 1
emission_enabled = true
emission = Color(0, 0, 0, 1)
emission_energy_multiplier = 3.0
emission_texture = ExtResource("3_emi")
texture_filter = 0
"""


def _color(c):
    a = c[3] if len(c) > 3 else 1.0
    return "Color(%.4f, %.4f, %.4f, %.3f)" % (min(c[0], 1.0), min(c[1], 1.0), min(c[2], 1.0), a)


def godot_tres(name):
    """Text of the StandardMaterial3D resource for one library material."""
    m = MATERIALS[name]
    if "palette" in m["flags"]:
        return PALETTE_TRES
    ext = []
    lines = ['resource_name = "%s"' % name, "vertex_color_use_as_albedo = true", "albedo_color = " + _color(m["col"])]
    if m["alb"]:
        ext.append((TEX_RES + m["alb"] + ".png", "1_alb"))
        lines.append('albedo_texture = ExtResource("1_alb")')
    lines += ["roughness = %.3f" % m["rough"], "metallic = %.3f" % m["metal"]]
    if m["metal"] > 0:
        lines.append("metallic_specular = 0.5")
    if m["nrm"]:
        ext.append((TEX_RES + m["nrm"] + ".png", "2_nrm"))
        lines += ["normal_enabled = true", "normal_scale = %.3f" % m["ns"], 'normal_texture = ExtResource("2_nrm")']
    f = m["flags"]
    if "blend" in f:
        lines += ["transparency = 1", "depth_draw_mode = 1"]
    if "scissor" in f:
        lines += ["transparency = 2", "alpha_scissor_threshold = 0.5", "alpha_antialiasing_mode = 1"]
    if "double" in f:
        lines.append("cull_mode = 2")
    if "emit" in f:
        lines += ["emission_enabled = true", "emission = " + _color(m["col"]), "emission_energy_multiplier = 2.0"]
    lines.append("texture_filter = 5")
    head = '[gd_resource type="StandardMaterial3D" load_steps=%d format=3]\n\n' % (len(ext) + 1)
    for path, rid in ext:
        head += '[ext_resource type="Texture2D" path="%s" id="%s"]\n' % (path, rid)
    return head + ("\n" if ext else "") + "[resource]\n" + "\n".join(lines) + "\n"


TEX_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/normal_map={normal}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/size_limit=0
detect_3d/compress_to=0
"""


def write_godot_materials(mat_dir, tex_dir, names=None):
    """Writes the .tres library and, for textures without one, an .import file with
    explicit VRAM compression / mipmaps / normal-map flags (the materials are not
    seen by the importer's 3D detection until they are loaded)."""
    os.makedirs(mat_dir, exist_ok=True)
    for name in names or MATERIALS:
        with open(os.path.join(mat_dir, name + ".tres"), "w", encoding="utf-8") as f:
            f.write(godot_tres(name))
    for fn in os.listdir(tex_dir):
        if not fn.endswith(".png"):
            continue
        imp = os.path.join(tex_dir, fn + ".import")
        if os.path.exists(imp):
            continue
        txt = TEX_IMPORT.format(normal=1 if fn.endswith("_normal.png") else 2)
        if fn.startswith("palette"):
            # Flat swatches: lossless, no mipmaps (sampled at swatch centres, nearest).
            txt = txt.replace("compress/mode=2", "compress/mode=0").replace("mipmaps/generate=true", "mipmaps/generate=false")
        with open(imp, "w", encoding="utf-8") as f:
            f.write(txt)
