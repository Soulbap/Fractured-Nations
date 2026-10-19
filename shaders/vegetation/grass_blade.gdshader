// Grass blade surface for the camera-local particle grass.
// Derived from Terrain3D extras/particle_example/grass.gdshader
// (Copyright © 2023-2026 Cory Petkovsek, Roope Palmroos, and Contributors, MIT).
// FRACTURED NATIONS: base color uniform; COLOR carries the Terrain3D color map tint.

shader_type spatial;

render_mode skip_vertex_transform, cull_disabled, blend_mix;

uniform vec2 wind_direction = vec2(1.0, 1.0);
uniform vec3 base_color : source_color = vec3(0.21, 0.24, 0.06);
uniform vec3 tip_color : source_color = vec3(0.40, 0.42, 0.14);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.5;

varying vec4 data;

void vertex() {
	data[2] = (VERTEX.y + 0.55);
	data[2] *= data[2];
	VERTEX.xz *= (1.0 - data[2]);

	COLOR = mix(COLOR, vec4(1.0), smoothstep(0.9, 1.0, data[2]));
	COLOR *= INSTANCE_CUSTOM[3] < 0.35 ? 1. : mix(1.0, 0.75, smoothstep(0.35, 0.0, data[2]));
	data.rg = INSTANCE_CUSTOM.rg;

	vec3 w_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float scale = pow(INSTANCE_CUSTOM[3] * INSTANCE_CUSTOM[3], 0.707);
	float force = INSTANCE_CUSTOM[2] * data[2] * scale;
	force -= fract(force * 256.0) * force * 0.05;
	force = pow(force, 0.707);

	float lateral_wobble = sin(TIME * 2.0 * (1.0 + data.r + data.g)) * 0.25 * (1.0 - INSTANCE_CUSTOM[2]);
	vec2 direction = normalize(wind_direction);
	w_vertex.xz -= (vec2(-direction.y, direction.x) * lateral_wobble + direction) * force;
	w_vertex.y -= INSTANCE_CUSTOM[2] * force * data[2];
	data[3] = force;

	VERTEX = (VIEW_MATRIX * vec4(w_vertex, 1.0)).xyz;
	NORMAL = MODELVIEW_NORMAL_MATRIX * NORMAL;
	BINORMAL = MODELVIEW_NORMAL_MATRIX * BINORMAL;
	TANGENT = MODELVIEW_NORMAL_MATRIX * TANGENT;
}

void fragment() {
	ALBEDO = mix(base_color, tip_color, data[2]);
	ALBEDO.rg *= (data.rg * 0.3 + 0.9);
	// Terrain color map tint at half strength: under the forest tint the blades darken
	// with the ground but stay readable.
	ALBEDO *= mix(vec3(1.0), pow(COLOR.rgb, vec3(2.2)), tint_strength);
	float spec_rough = clamp(max(data[2], data[3]), 0., 1.);
	ROUGHNESS = 1. - spec_rough;
	SPECULAR = clamp(spec_rough * 0.25, 0., .15);
	BACKLIGHT = vec3(0.33);
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = pow(ALBEDO, vec3(0.4));
	#endif
}
