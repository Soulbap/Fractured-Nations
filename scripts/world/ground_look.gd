## VISUAL-02 ground: the reference world's terrain is drawn with shaders/world/terrain_visual02.gdshader (Terrain3D's default
## shader plus colour-map softening, macro variation of open ground, distant forest canopy and rock weathering), applied in
## memory at game start like WorldLook (the generated terrain material and the world manifest are untouched).
##
## Why: from the tactical camera the colour map's field parcels and forest outlines were straight lines of flat colour, large
## meadows one uniform green, and beyond the ~1 km where tree meshes are drawn a forest became bare floor texture (from above a
## hard square edge of trees). The shader fixes all four with texture lookups only. `--legacy-ground` keeps the old shader.
class_name GroundLook
extends RefCounted

const SHADER := "res://shaders/world/terrain_visual02.gdshader"

## True once the ground shader was applied (tests and the report read it).
static var active := false


static func apply(world: Node) -> void:
	active = false
	if "--legacy-ground" in OS.get_cmdline_user_args():
		return
	var terrain := world.get_node_or_null("Terrain3D") as Terrain3D
	if terrain == null or terrain.material == null:
		return
	_swap_textures(terrain)
	var mat := terrain.material
	mat.shader_override = load(SHADER) as Shader
	mat.shader_override_enabled = true
	var noise := noise_texture()
	mat.set_shader_param(&"v2_noise", noise)
	if textures_v3:
		# The scanned forest floor is litter-brown; seen from above it shows between the tree tops: canopy colour from nearer.
		mat.set_shader_param(&"canopy_start", 150.0)
		mat.set_shader_param(&"canopy_end", 700.0)
	# The grass tufts follow the same ground colour (shaders/environment/grass_tuft.gdshader).
	var grass := world.get_node_or_null("Grass") as GrassLayer
	if grass:
		# WORLD-VISUALS-01 road verges: the ground shader follows the grass layer's road mask, also after later edits.
		var set_mask := func(tex: Texture2D, origin: Vector2, size_m: float) -> void:
			mat.set_shader_param(&"road_mask", tex)
			mat.set_shader_param(&"road_mask_origin", origin)
			mat.set_shader_param(&"road_mask_size_m", size_m)
			mat.set_shader_param(&"verge_enabled", true)
		grass.mask_applied.connect(set_mask)
		if grass.get_process_param(&"mask_enabled"):
			set_mask.call(grass.get_process_param(&"exclusion_mask"), grass.get_process_param(&"mask_origin"),
				grass.get_process_param(&"mask_size_m"))
	if grass and grass.mesh_material_override is ShaderMaterial:
		var gm := grass.mesh_material_override as ShaderMaterial
		gm.set_shader_parameter(&"v2_noise", noise)
		gm.set_shader_parameter(&"ground_match", 1.0)
		# WORLD-VISUALS-01: eight ground plants (grass, flowers, hair-grass, heather, bilberry, lingonberry, fern, sedge) by
		# ground type instead of one grass tuft and one dwarf shrub.
		var atlas := load("res://assets/environment/textures/ground3_alb.png") as Texture2D
		if atlas:
			gm.set_shader_parameter(&"plant_atlas", atlas)
			gm.set_shader_parameter(&"plant_atlas_normal", load("res://assets/environment/textures/ground3_nrm.png"))
			gm.set_shader_parameter(&"use_atlas", true)
			# Warmer than the tuft default: under the blue sky light the drawn plants otherwise read grey-blue.
			gm.set_shader_parameter(&"tint", Color(1.04, 1.02, 0.8))
			# The old tuft texture was dark and got a 1.7x gain to match the ground; the drawn plants are already as bright.
			gm.set_shader_parameter(&"tuft_gain", 1.1)
			grass.set_process_param(&"plant_types", true)
	active = true


## WORLD-VISUALS-01 ground set: terrain texture name -> [file stem in assets/terrain/textures/, uv scale (1 / metres per tile),
## albedo tint (calibrated so the mean colour of each surface stays near the old one: the map's colour map multiplies
## it)]. Made from CC0 scans by tools/blender/env/make_surfaces_v3.py (2.5-3 m per tile instead of the 9 m stretch of
## the old textures); all the same size because Terrain3D builds texture arrays. Swapped in memory: the world's
## terrain_assets.tres and the manifest stay as they are.
const TEXTURES_V3 := {
	"Meadow": ["v3_meadow", 0.34, Color(1.0, 1.25, 0.85)],
	"Rock": ["v3_rock", 0.16, Color(1.5, 1.48, 1.6)],
	"Dirt": ["v3_dirt", 0.38, Color(1.15, 1.1, 1.1)],
	"Field / heath": ["v3_heath", 0.3, Color(1.9, 2.35, 2.0)],
	"Forest floor": ["v3_forest", 0.3, Color(1.6, 1.55, 1.5)],
	"Gravel": ["v3_gravel", 0.42, Color(1.1, 1.08, 0.95)],
	"Bog": ["v3_bog", 0.3, Color(2.0, 2.4, 3.0)],
	"Asphalt": ["v3_asphalt", 0.25, Color(1.0, 1.0, 1.0)],
}
const TEX_DIR := "res://assets/terrain/textures/"

## True once the WORLD-VISUALS-01 textures replaced the generated ones (`--legacy-ground` keeps the old set).
static var textures_v3 := false


static func _swap_textures(terrain: Terrain3D) -> void:
	textures_v3 = false
	if terrain.assets == null:
		return
	# A fresh copy of the world's asset file, handed to the terrain as a new set. In a running game Terrain3D frees the source
	# textures once the arrays are built (free_editor_textures) and reloads the asset file on any change, which would drop
	# these replacements: switched off first (the 2048 px sources then stay in memory, ~90 MB).
	var path := terrain.assets.resource_path
	var assets := (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) if path != "" else null) as Terrain3DAssets
	if assets == null:
		push_warning("GroundLook: terrain assets have no file, keeping the generated textures")
		return
	for i in assets.get_texture_count():
		var t := assets.get_texture(i)
		if t == null or not TEXTURES_V3.has(t.name):
			continue
		var e: Array = TEXTURES_V3[t.name]
		var alb := load(TEX_DIR + e[0] + "_alb_ht.png") as Texture2D
		var nrm := load(TEX_DIR + e[0] + "_nrm_rgh.png") as Texture2D
		if alb == null or nrm == null:
			push_warning("GroundLook: missing %s textures, keeping the generated set" % e[0])
			return
		t.albedo_texture = alb
		t.normal_texture = nrm
		t.uv_scale = e[1]
		t.albedo_color = e[2]
		t.detiling_rotation = 0.35
		t.detiling_shift = 0.25
	terrain.free_editor_textures = false
	terrain.assets = assets
	textures_v3 = true


## The one noise texture of the ground shader (fbm, seamless, sampled at several scales).
static func noise_texture() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = 3031
	n.frequency = 0.008
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.normalize = true
	t.generate_mipmaps = true
	t.noise = n
	return t
