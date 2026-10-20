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
uniform float forest_lum_lo = 0.42;
uniform float forest_lum_hi = 0.62;
uniform vec2 wind_direction = vec2(1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.6;
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.45;

varying vec4 data;

void vertex() {
	// Mesh spans y = -0.45 .. 0.55 (position_offset lifts the base onto the ground).
	data[2] = clamp(VERTEX.y + 0.45, 0.0, 1.0);
	data[2] *= data[2];
	data.rg = INSTANCE_CUSTOM.rg;
	vec3 w_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
	vec4 t = forest > 0.5 ? texture(forest_tex, UV) : texture(tuft_tex, UV);
	ALBEDO = t.rgb * tint * (0.85 + 0.3 * data.r);
	ALBEDO *= mix(vec3(1.0), pow(COLOR.rgb, vec3(2.2)) * 1.6, tint_strength);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	// Soft, upward-facing normal: tufts light like a meadow, not like flat cards.
	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, up_view, 0.6));
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
	BACKLIGHT = ALBEDO * 0.4;
}
