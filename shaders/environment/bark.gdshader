// Tree stems and branches: tiling bark with normal map, same wind as the foliage.
// WORLD-VISUALS-01: optional second bark above a height of the mesh (Scots pine: thick grey plates at the base, thin orange
// flakes on the upper stem and the branches), with an irregular transition band; the height is part of the Blender material
// name (Bark_Pine3_s<metres>, tools/terrain_ref/import_env_assets.gd).
shader_type spatial;

#include "res://shaders/environment/wind.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;
uniform bool use_upper = false;
uniform sampler2D upper_albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D upper_normal_tex : hint_normal, filter_linear_mipmap;
uniform float split_y = 8.0;
uniform float split_soft = 2.5;

varying float v_height;

void vertex() {
	v_height = VERTEX.y;
	VERTEX += wind_offset(VERTEX, MODEL_MATRIX, TIME);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec3 alb = texture(albedo_tex, UV).rgb;
	vec3 nrm = texture(normal_tex, UV).rgb;
	if (use_upper) {
		// Flakes reach down in tongues: noise on the bark's own UV (u around the stem, v up).
		float n = vnoise(UV * vec2(3.0, 1.2)) * 0.65 + vnoise(UV * vec2(9.0, 4.0)) * 0.35;
		float w = smoothstep(split_y - split_soft, split_y + split_soft, v_height + (n - 0.5) * split_soft * 2.2);
		alb = mix(alb, texture(upper_albedo_tex, UV).rgb, w);
		nrm = mix(nrm, texture(upper_normal_tex, UV).rgb, w);
	}
	ALBEDO = alb * COLOR.rgb * tint;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 1.2;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.2;
}
