// River and lake surface for reference worlds (WORLD-TERRAIN-01).
// Depth-tinted, alpha by water depth (shallow banks fade into the terrain), two scrolling
// normal maps; rivers flow along UV.x (the ribbon is built with UV.x = distance / 20 m).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.07, 0.18, 0.25);
uniform vec3 shallow_color : source_color = vec3(0.14, 0.22, 0.20);
uniform float depth_scale = 3.5;
uniform float edge_fade_m = 0.9;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float flow_speed = 0.0;
uniform float wind_speed = 0.02;
uniform float normal_strength = 0.55;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

void fragment() {
	vec2 uv = UV;
	vec2 flow = vec2(flow_speed * TIME * 0.05, 0.0);
	vec2 wind = vec2(wind_speed, wind_speed * 0.6) * TIME;
	vec3 na = texture(normal_a, uv * 1.7 - flow - wind).rgb;
	vec3 nb = texture(normal_b, uv * 4.3 - flow * 1.6 + wind.yx * 1.3).rgb;
	NORMAL_MAP = normalize(mix(na, nb, 0.45));
	NORMAL_MAP_DEPTH = normal_strength;

	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float water_depth = max(VERTEX.z - view.z, 0.0);
	// Convert view-space distance to approximate vertical depth.
	float d = water_depth * clamp(abs(dot(normalize(VERTEX), VIEW)), 0.15, 1.0);

	float t = clamp(d / depth_scale, 0.0, 1.0);
	ALBEDO = mix(shallow_color, deep_color, t);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.55;
	ALPHA = clamp(d / edge_fade_m, 0.0, 1.0) * mix(0.75, 0.97, t);
}
