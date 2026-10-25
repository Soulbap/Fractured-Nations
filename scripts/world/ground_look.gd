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
	var mat := terrain.material
	mat.shader_override = load(SHADER) as Shader
	mat.shader_override_enabled = true
	var noise := noise_texture()
	mat.set_shader_param(&"v2_noise", noise)
	# The grass tufts follow the same ground colour (shaders/environment/grass_tuft.gdshader).
	var grass := world.get_node_or_null("Grass") as GrassLayer
	if grass and grass.mesh_material_override is ShaderMaterial:
		var gm := grass.mesh_material_override as ShaderMaterial
		gm.set_shader_parameter(&"v2_noise", noise)
		gm.set_shader_parameter(&"ground_match", 1.0)
	active = true


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
