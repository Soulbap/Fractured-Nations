## GAMEPLAY-05 look of the game world: light, atmosphere and grading, applied in memory at game start to the world scene's
## WorldEnvironment and Sun (like RoadShoulders: the generated world scene and its manifest are untouched).
##
## Why: the generated scene left the post-processing at its defaults - no ambient occlusion (buildings, soldiers and trunks
## floated on the ground), saturated greens and yellows (the fields read as flat paint from the tactical view) and almost no
## distance haze (6e-5: a hill 5 km away was as clear as one at 500 m). The changes are small and natural: SSAO for ground
## contact, a slightly lower saturation and a little contrast, haze that grows over kilometres, a softer sky and a sun a
## touch warmer. Before / after: docs/gameplay05/ (GAMEPLAY-05 report). `--legacy-look` keeps the old look for comparison.
class_name WorldLook
extends RefCounted

## True once the look was applied (tests and the report read it).
static var active := false


static func apply(world: Node) -> void:
	active = false
	if "--legacy-look" in OS.get_cmdline_user_args():
		return
	var we := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment
	# Ground contact: screen-space ambient occlusion, medium radius (buildings, sandbags, soldiers' feet, tree bases).
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.5
	env.ssao_light_affect = 0.0
	# Grading: the terrain's colour map is strongly saturated; a little less colour and a little more contrast.
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.86
	env.adjustment_contrast = 1.06
	env.adjustment_brightness = 1.0
	# Atmosphere: haze that is felt over kilometres, tinted by the sky.
	env.fog_density = 0.00016
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.25
	env.fog_light_color = Color(0.72, 0.77, 0.83)
	var sky := env.sky.sky_material as ProceduralSkyMaterial if env.sky else null
	if sky:
		sky.sky_top_color = Color(0.36, 0.49, 0.66)
		sky.sky_horizon_color = Color(0.70, 0.74, 0.78)
	var sun := world.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.light_color = Color(1.0, 0.96, 0.9)
	_nordic_light(we, sun)
	# Ground: the two tints that cover most open land (meadow green, field yellow) were the loudest colours on screen; a
	# Nordic summer meadow is a muted green, a field / heath straw and heather brown.
	var terrain := world.get_node_or_null("Terrain3D") as Terrain3D
	if terrain and terrain.assets:
		for i in terrain.assets.get_texture_count():
			var t := terrain.assets.get_texture(i)
			if t and GROUND_TINTS.has(t.name):
				t.albedo_color = GROUND_TINTS[t.name]
	active = true


## WORLD-VISUALS-01 light: Nordic summer daylight that a forest can be walked in. The forest interiors were near black: the sun
## is blocked by the (now denser) crowns, the sky light alone was weak next to it, and SSAO darkened every card again. Real eyes
## (and cameras) adapt: a limited eye adaptation brightens shade up to ~2x and leaves open sunlit land where it was; AgX
## instead of ACES keeps greens from going neon and highlights from clipping; a little more sky light, softer SSAO, a bloom
## that only touches the sky and specular glints. `--legacy-look` keeps the GAMEPLAY-05 light.
static func _nordic_light(we: WorldEnvironment, sun: DirectionalLight3D) -> void:
	var env := we.environment
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.25
	env.ssao_intensity = 1.15
	env.ssao_power = 1.2
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.3
	env.adjustment_saturation = 0.92
	env.adjustment_contrast = 1.04
	var cam := CameraAttributesPractical.new()
	cam.auto_exposure_enabled = true
	cam.auto_exposure_scale = 0.4
	cam.auto_exposure_speed = 0.6
	cam.auto_exposure_min_sensitivity = 95.0
	cam.auto_exposure_max_sensitivity = 165.0
	we.camera_attributes = cam
	# Less haze than GAMEPLAY-05's 0.00016: with eye adaptation a high view over dark forest turned milky.
	env.fog_density = 0.00012
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.12
	# AgX desaturates the sky more than ACES did: a clearer northern summer blue.
	var sky := env.sky.sky_material as ProceduralSkyMaterial if env.sky else null
	if sky:
		sky.sky_top_color = Color(0.27, 0.44, 0.70)
		sky.sky_horizon_color = Color(0.64, 0.71, 0.80)
	if sun:
		sun.light_energy = 1.2
		sun.light_angular_distance = 0.6


## Terrain texture name -> albedo tint (the generated assets: Meadow 0.70 0.84 0.52, Field / heath 0.96 0.98 0.70).
const GROUND_TINTS := {
	"Meadow": Color(0.66, 0.76, 0.52),
	"Field / heath": Color(0.86, 0.84, 0.70),
}
