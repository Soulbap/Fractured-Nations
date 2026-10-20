// Tree stems and branches: tiling bark with normal map, same wind as the foliage.
shader_type spatial;

#include "res://shaders/environment/wind.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;

void vertex() {
	VERTEX += wind_offset(VERTEX, MODEL_MATRIX, TIME);
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * COLOR.rgb * tint;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 1.2;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.2;
}
