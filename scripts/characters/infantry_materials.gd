## Shared material library for the infantry character set (CHARACTER-01).
##
## Every glTF piece arrives with material NAMES only (no embedded images); this library
## maps each name to one StandardMaterial3D that all pieces and all soldiers share, so a
## platoon costs a handful of materials and texture uploads. The table mirrors
## tools/blender/character/char_materials.py (same names, same sRGB colours). UVs are
## world-scale box projections authored in Blender, so uv1_scale stays 1.
##
## Faction variation: "Camo_M23" resolves to the faction's camouflage (North: Nordic
## woodland M23-style, South: arid variant of the same pattern family) and "Patch" takes
## the faction colour. Add a faction camo by adding a texture and an entry to FACTION_CAMO.
class_name InfantryMaterials
extends RefCounted

const TEX := "res://assets/characters/infantry/textures/"

## name: [albedo colour (sRGB), roughness, metallic, albedo texture, normal texture, normal scale]
const TABLE := {
	"Camo_M23": [Color(1, 1, 1), 0.88, 0.0, "camo_m23_albedo.png", "fabric_ripstop_normal.png", 0.6],
	"Camo_Arid": [Color(1, 1, 1), 0.88, 0.0, "camo_arid_albedo.png", "fabric_ripstop_normal.png", 0.6],
	"Fabric_RangerGreen": [Color(0.36, 0.38, 0.28), 0.90, 0.0, "", "fabric_ripstop_normal.png", 0.6],
	"Webbing_RangerGreen": [Color(0.33, 0.35, 0.26), 0.86, 0.0, "webbing_pals_albedo.png", "webbing_pals_normal.png", 1.0],
	"Webbing_Coyote": [Color(0.55, 0.46, 0.33), 0.86, 0.0, "webbing_pals_albedo.png", "webbing_pals_normal.png", 1.0],
	"Cordura_RangerGreen": [Color(0.33, 0.35, 0.26), 0.88, 0.0, "", "cordura_normal.png", 0.8],
	"Cordura_Coyote": [Color(0.56, 0.47, 0.34), 0.88, 0.0, "", "cordura_normal.png", 0.8],
	"Strap_Black": [Color(0.07, 0.07, 0.07), 0.80, 0.0, "", "cordura_normal.png", 0.6],
	"Glove_Coyote": [Color(0.58, 0.49, 0.36), 0.82, 0.0, "", "cordura_normal.png", 0.7],
	"Boot_Leather": [Color(0.075, 0.068, 0.062), 0.55, 0.0, "leather_albedo.png", "leather_normal.png", 0.8],
	"Boot_Sole": [Color(0.04, 0.04, 0.04), 0.90, 0.0, "", "", 1.0],
	"Helmet_Shell": [Color(0.30, 0.32, 0.25), 0.78, 0.0, "polymer_albedo.png", "polymer_normal.png", 0.6],
	"Polymer_Black": [Color(0.05, 0.05, 0.052), 0.62, 0.0, "polymer_albedo.png", "polymer_normal.png", 0.7],
	"Polymer_OD": [Color(0.18, 0.19, 0.15), 0.70, 0.0, "polymer_albedo.png", "polymer_normal.png", 0.7],
	"Metal_Black": [Color(0.045, 0.045, 0.048), 0.42, 0.85, "polymer_albedo.png", "polymer_normal.png", 0.5],
	"Metal_Worn": [Color(0.30, 0.30, 0.31), 0.35, 1.0, "polymer_albedo.png", "polymer_normal.png", 0.5],
	"Lens": [Color(0.02, 0.025, 0.03), 0.05, 0.3, "", "", 1.0],
	"Lens_Tinted": [Color(0.30, 0.22, 0.10), 0.05, 0.5, "", "", 1.0],
	"Patch": [Color(0.30, 0.55, 1.0), 0.60, 0.0, "", "", 1.0],
	"Rubber_Black": [Color(0.035, 0.035, 0.035), 0.85, 0.0, "", "", 1.0],
	"Skin": [Color(1, 1, 1), 0.60, 0.0, "skin_head_albedo.png", "", 1.0],
	"SkinBody": [Color(0.76, 0.58, 0.47), 0.60, 0.0, "", "", 1.0],
	"Eye": [Color(0.80, 0.77, 0.72), 0.20, 0.0, "", "", 1.0],
	"Iris": [Color(0.10, 0.12, 0.13), 0.10, 0.0, "", "", 1.0],
	# ASSET-PRODUCTION-01 faction families (fixed per family, not swapped by faction id).
	"Camo_NATO": [Color(1, 1, 1), 0.88, 0.0, "camo_nato_albedo.png", "fabric_ripstop_normal.png", 0.6],
	"Camo_EMR": [Color(1, 1, 1), 0.88, 0.0, "camo_emr_albedo.png", "fabric_ripstop_normal.png", 0.6],
	"Camo_Type21": [Color(1, 1, 1), 0.88, 0.0, "camo_type21_albedo.png", "fabric_ripstop_normal.png", 0.6],
	"Fabric_Coyote": [Color(0.55, 0.47, 0.35), 0.90, 0.0, "", "fabric_ripstop_normal.png", 0.6],
	"Polymer_Tan": [Color(0.62, 0.53, 0.38), 0.68, 0.0, "polymer_albedo.png", "polymer_normal.png", 0.7],
	"Polymer_Plum": [Color(0.32, 0.14, 0.12), 0.60, 0.0, "polymer_albedo.png", "polymer_normal.png", 0.7],
}

## Camouflage per faction index (WorldState faction ids). Unknown factions use M23.
const FACTION_CAMO := ["Camo_M23", "Camo_Arid"]

static var _cache := {}
static var _proxy_material: StandardMaterial3D


## Shared material for a glTF material name, resolved for a faction.
static func get_material(mat_name: String, faction: int) -> Material:
	var key := mat_name
	if mat_name == "Camo_M23":
		key = FACTION_CAMO[faction] if faction >= 0 and faction < FACTION_CAMO.size() else mat_name
	elif mat_name == "Patch":
		key = "Patch_%d" % faction
	if _cache.has(key):
		return _cache[key]
	var m := _build(key, faction)
	_cache[key] = m
	return m


## Average albedo of a material (texture mean x colour), used to bake the single-material
## vertex-coloured proxy mesh for far RTS views.
static func average_albedo(mat_name: String, faction: int) -> Color:
	var m := get_material(mat_name, faction) as StandardMaterial3D
	if m == null:
		return Color(0.4, 0.4, 0.35)
	var c := m.albedo_color
	if m.albedo_texture:
		var img := m.albedo_texture.get_image()
		if img:
			if img.is_compressed():
				img = img.duplicate()
				img.decompress()
			img.resize(8, 8, Image.INTERPOLATE_BILINEAR)
			var acc := Color(0, 0, 0)
			for y in 8:
				for x in 8:
					acc += img.get_pixel(x, y)
			c *= acc / 64.0
	return c


static func proxy_material() -> StandardMaterial3D:
	if _proxy_material == null:
		_proxy_material = StandardMaterial3D.new()
		_proxy_material.resource_name = "InfantryProxy"
		_proxy_material.vertex_color_use_as_albedo = true
		_proxy_material.vertex_color_is_srgb = true
		_proxy_material.roughness = 0.9
	return _proxy_material


static func _build(key: String, faction: int) -> Material:
	var src := key
	if key.begins_with("Patch_"):
		src = "Patch"
	var row: Array = TABLE.get(src, [Color(0.5, 0.5, 0.5), 0.8, 0.0, "", "", 1.0])
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.albedo_color = row[0]
	m.roughness = row[1]
	m.metallic = row[2]
	if row[3] != "":
		m.albedo_texture = load(TEX + row[3])
	if row[4] != "":
		m.normal_enabled = true
		m.normal_texture = load(TEX + row[4])
		m.normal_scale = row[5]
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if key.begins_with("Patch_"):
		m.albedo_color = WorldState.faction_color(faction)
	return m
