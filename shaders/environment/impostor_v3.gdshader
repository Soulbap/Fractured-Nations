// WORLD-VISUALS-01 far LOD of a tree id with several variants: one mesh (three crossed side cards + a top card, built for
// variant 0) for every instance of the id, so a far cell stays one draw call. The variant of an instance comes from the
// instance colour's alpha ((v + 0.5) / 8, written by VegetationStreamer._split_variants with the same position hash that
// picks the near mesh); the shader scales the cards to that variant's size and samples its tile of the atlas
// (tools/blender/env/make_trees_v3.py renders the tiles: side views 3 x 2, top views 3 x 2).
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

#include "res://shaders/environment/wind.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tint : source_color = vec3(0.72, 0.74, 0.70);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform float translucency : hint_range(0.0, 1.0) = 0.2;
uniform float normal_up_blend : hint_range(0.0, 1.0) = 0.45;
uniform float edge_fade : hint_range(0.0, 1.0) = 0.0;
uniform bool is_top = false;
// Per variant: atlas rect (u0, v0, du, dv) and size relative to variant 0 (width, height, crown half-width).
uniform vec4 var_rect[8];
uniform vec3 var_scale[8];
uniform int var_count = 1;

varying vec4 v_rect;

void vertex() {
	int v = clamp(int(COLOR.a * 8.0), 0, max(var_count - 1, 0));
	vec3 k = var_scale[v];
	if (is_top) {
		VERTEX.xz *= k.z;
	} else {
		VERTEX.xz *= k.x;
	}
	VERTEX.y *= k.y;
	v_rect = var_rect[v];
	VERTEX += wind_offset(VERTEX, MODEL_MATRIX, TIME);
}

void fragment() {
	vec2 uv = v_rect.xy + clamp(UV, vec2(0.002), vec2(0.998)) * v_rect.zw;
	vec4 a = texture(albedo_tex, uv);
	ALBEDO = a.rgb * COLOR.rgb * tint;
	ALPHA = a.a;
	if (edge_fade > 0.0) {
		ALPHA *= smoothstep(edge_fade, edge_fade + 0.15, abs(dot(normalize(NORMAL), VIEW)));
	}
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, up_view, normal_up_blend));
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	BACKLIGHT = ALBEDO * translucency;
}
