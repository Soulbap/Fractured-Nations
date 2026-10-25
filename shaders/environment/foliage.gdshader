// Alpha-tested foliage cards (needles, leaves) and far-LOD impostor cards.
// COLOR = baked vertex AO (from Blender) x per-instance tint (VegetationStreamer colours).
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

#include "res://shaders/environment/wind.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform bool use_normal_tex = true;
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.42;
uniform float translucency : hint_range(0.0, 1.0) = 0.35;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.78;
uniform float flutter = 0.015;
// Impostors: bend the card normals toward "up" so the flat cards light like a volume.
uniform float normal_up_blend : hint_range(0.0, 1.0) = 0.0;
// GAMEPLAY-05: cards seen this close to edge-on are not drawn (0 = off). The horizontal top card of an impostor seen from the
// side drew as a thin black line across the canopy of every distant tree; the impostors' top materials set ~0.3.
uniform float edge_fade : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	VERTEX += wind_offset(VERTEX, MODEL_MATRIX, TIME);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += NORMAL * sin(TIME * 5.3 + wp.x * 1.3 + wp.z * 0.9 + wp.y) * flutter;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	ALBEDO = a.rgb * COLOR.rgb * tint;
	ALPHA = a.a;
	if (edge_fade > 0.0) {
		ALPHA *= smoothstep(edge_fade, edge_fade + 0.15, abs(dot(normalize(NORMAL), VIEW)));
	}
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	if (use_normal_tex) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 0.8;
	}
	if (normal_up_blend > 0.0) {
		vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		NORMAL = normalize(mix(NORMAL, up_view, normal_up_blend));
	}
	ROUGHNESS = roughness_value;
	SPECULAR = 0.25;
	BACKLIGHT = ALBEDO * translucency;
}
