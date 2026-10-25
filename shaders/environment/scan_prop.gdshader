// WORLD-VISUALS-01 rocks, stumps and logs made from CC0 scans (tools/blender/env/make_props_v3.py): the scan's albedo,
// normal and ORM (ambient occlusion, roughness, metal) maps, a colour grade (the scanned sandstone becomes grey Nordic
// granite / gneiss), moss on faces turned to the sky and pale crustose lichen patches. COLOR = per-instance tint.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform float saturation : hint_range(0.0, 1.5) = 1.0;
uniform vec3 grade : source_color = vec3(1.0);
uniform float brightness = 1.0;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 moss_color : source_color = vec3(0.30, 0.36, 0.14);
uniform float lichen_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 lichen_color : source_color = vec3(0.72, 0.74, 0.64);

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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
	vec3 c = texture(albedo_tex, UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation) * grade * brightness;
	vec3 orm = texture(orm_tex, UV).rgb;
	vec3 n = normalize(w_nrm);
	float n1 = vnoise(w_pos.xz * 1.3 + w_pos.y * 0.7) * 0.6 + vnoise(w_pos.xz * 5.0 - w_pos.y * 2.0) * 0.4;
	float lichen = smoothstep(0.58, 0.72, n1) * lichen_amount;
	c = mix(c, lichen_color * (0.85 + 0.3 * n1), lichen);
	float mn = vnoise(w_pos.xz * 0.8) * 0.6 + vnoise(w_pos.xz * 3.5) * 0.4;
	float moss = smoothstep(0.5, 0.85, n.y + (mn - 0.5) * 0.7) * moss_amount;
	c = mix(c, moss_color * (0.75 + 0.5 * vnoise(w_pos.xz * 9.0)), moss);
	ALBEDO = c * COLOR.rgb;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.3;
	ROUGHNESS = mix(orm.g, 0.95, moss);
	METALLIC = 0.0;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = mix(1.0, 0.4, moss);
	SPECULAR = 0.35;
}
