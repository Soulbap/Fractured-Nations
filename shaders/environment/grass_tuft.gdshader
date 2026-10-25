// Textured grass tuft for the camera-local particle grass (reference worlds).
// Same wind/particle data contract as shaders/vegetation/grass_blade.gdshader (derived
// from Terrain3D extras/particle_example, MIT), but the mesh is a set of crossed cards with
// an alpha-tested tuft texture instead of a tapered ribbon. COLOR carries the Terrain3D
// colour map tint (forests darker, fields yellower).
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled;

uniform sampler2D tuft_tex : source_color, filter_linear_mipmap, repeat_disable;
// Under the canopy (dark colour-map tint) the tufts become dwarf shrubs (blueberry,
// lingonberry) instead of meadow grass.
uniform sampler2D forest_tex : source_color, filter_linear_mipmap, repeat_disable;
// WORLD-VISUALS-01: the ground plant atlas (4 x 2 tiles, tools/blender/env/make_cards_v3.py); the particle shader puts the
// tile index in the integer part of INSTANCE_CUSTOM.g (plant_types). Without it the two textures above are used as before.
uniform sampler2D plant_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D plant_atlas_normal : hint_normal, filter_linear_mipmap, repeat_disable;
uniform bool use_atlas = false;
// Per tile: how much of the ground colour tint it takes (flowers and berries keep their colour better).
uniform float atlas_tint = 0.45;
// Meadow grass tiles (0 - 2) are darker than the open ground they must match at the edge of the grass ring.
uniform float atlas_grass_gain = 1.4;
uniform float forest_lum_lo = 0.42;
uniform float forest_lum_hi = 0.62;
uniform vec2 wind_direction = vec2(1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.6;
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.45;
// VISUAL-02: the same colour-map treatment and open-ground macro variation as shaders/world/terrain_visual02.gdshader, so
// the tufts keep the colour of the ground they stand on (otherwise the edge of the grass ring shows). GroundLook sets
// v2_noise; without it (legacy ground) ground_match is 0.
uniform highp sampler2D v2_noise : filter_linear_mipmap, repeat_enable;
uniform float ground_match = 0.0;
uniform float cm_contrast = 0.86;
uniform float cm_saturation = 0.80;
uniform vec3 cm_pivot = vec3(0.78, 0.80, 0.68);
uniform vec3 open_dry : source_color = vec3(1.07, 1.02, 0.84);
uniform vec3 open_lush : source_color = vec3(0.88, 0.98, 0.88);
uniform float open_region_m = 2600.0;
uniform float open_patch_m = 290.0;
uniform float open_clump_m = 37.0;
uniform float open_saturation = 0.74;
uniform float tuft_gain = 1.7;

varying vec4 data;
varying float v_tile;
// The ground colour depends only on the instance (its origin and colour-map tint): computed once per vertex.
varying vec3 v_ground;

void vertex() {
	// Mesh spans y = -0.45 .. 0.55 (position_offset lifts the base onto the ground).
	data[2] = clamp(VERTEX.y + 0.45, 0.0, 1.0);
	data[2] *= data[2];
	data.rg = vec2(INSTANCE_CUSTOM.r, fract(INSTANCE_CUSTOM.g));
	v_tile = floor(INSTANCE_CUSTOM.g);
	vec3 w_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 v_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz;
	vec3 cmc = COLOR.rgb;
	if (ground_match > 0.0) {
		vec3 c2 = cm_pivot + (cmc - cm_pivot) * cm_contrast;
		c2 = mix(vec3(dot(c2, vec3(0.299, 0.587, 0.114))), c2, cm_saturation);
		vec3 ov = mix(open_lush, open_dry, smoothstep(0.32, 0.68, textureLod(v2_noise, v_world / open_region_m, 0.0).r));
		ov *= mix(vec3(0.91, 0.95, 0.92), vec3(1.06, 1.03, 0.95), smoothstep(0.25, 0.75, textureLod(v2_noise, v_world / open_patch_m + vec2(0.37, 0.11), 0.0).r));
		ov *= 0.93 + 0.14 * textureLod(v2_noise, v_world / open_clump_m + vec2(0.71, 0.53), 0.0).r;
		cmc = mix(cmc, c2 * ov, ground_match);
	}
	v_ground = cmc;
	float scale = pow(INSTANCE_CUSTOM[3] * INSTANCE_CUSTOM[3], 0.707);
	float force = INSTANCE_CUSTOM[2] * data[2] * scale;
	force = pow(max(force, 0.0), 0.707);
	float lateral = sin(TIME * 2.0 * (1.0 + data.r + data.g)) * 0.25 * (1.0 - INSTANCE_CUSTOM[2]);
	vec2 direction = normalize(wind_direction);
	w_vertex.xz -= (vec2(-direction.y, direction.x) * lateral + direction) * force * 0.6;
	w_vertex.y -= INSTANCE_CUSTOM[2] * force * data[2] * 0.4;
	VERTEX = (VIEW_MATRIX * vec4(w_vertex, 1.0)).xyz;
	NORMAL = MODELVIEW_NORMAL_MATRIX * NORMAL;
	BINORMAL = MODELVIEW_NORMAL_MATRIX * BINORMAL;
	TANGENT = MODELVIEW_NORMAL_MATRIX * TANGENT;
}

void fragment() {
	float lum = dot(COLOR.rgb, vec3(0.3, 0.5, 0.2));
	float forest = 1.0 - smoothstep(forest_lum_lo, forest_lum_hi, lum);
	vec4 t;
	float tint_k = tint_strength;
	if (use_atlas) {
		float tile = clamp(v_tile, 0.0, 7.0);
		vec2 tuv = (clamp(UV, vec2(0.004), vec2(0.996)) + vec2(mod(tile, 4.0), floor(tile / 4.0))) * vec2(0.25, 0.5);
		t = texture(plant_atlas, tuv);
		t.rgb *= tile < 2.5 ? atlas_grass_gain : 1.0;
		tint_k = atlas_tint;
	} else {
		t = forest > 0.5 ? texture(forest_tex, UV) : texture(tuft_tex, UV);
	}
	ALBEDO = t.rgb * tint * (0.85 + 0.3 * data.r);
	vec3 cmc = v_ground;
	ALBEDO *= mix(vec3(1.0), pow(cmc, vec3(2.2)) * 1.6, tint_k);
	if (ground_match > 0.0) {
		vec3 g = mix(vec3(dot(ALBEDO, vec3(0.299, 0.587, 0.114))), ALBEDO, mix(1.0, open_saturation, ground_match));
		ALBEDO = g * mix(1.0, tuft_gain, ground_match);
	}
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	// Soft, upward-facing normal: tufts light like a meadow, not like flat cards.
	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, up_view, 0.6));
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
	BACKLIGHT = ALBEDO * 0.4;
}
