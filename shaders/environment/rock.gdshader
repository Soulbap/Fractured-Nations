// Boulders, outcrops and stones: world-space triplanar rock (project CC0 Rock023) with
// pale lichen patches and moss on upward-facing surfaces. COLOR = baked AO x instance tint.
shader_type spatial;

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform float rock_scale = 0.35;
uniform float moss_scale = 0.5;
uniform vec3 rock_tint : source_color = vec3(0.78, 0.77, 0.74);
uniform vec3 lichen_color : source_color = vec3(0.70, 0.72, 0.62);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.55;
uniform float lichen_amount : hint_range(0.0, 1.0) = 0.45;

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tri_w(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

// Separate helpers per sampler kind (Godot requires matching sampler hints per call site).
vec4 triplanar_color(sampler2D t, vec3 p, vec3 n, float s) {
	vec3 w = tri_w(n);
	return texture(t, p.zy * s) * w.x + texture(t, p.xz * s) * w.y + texture(t, p.xy * s) * w.z;
}

vec3 triplanar_normal(vec3 p, vec3 n, float s) {
	vec3 w = tri_w(n);
	return (texture(rock_normal, p.zy * s) * w.x + texture(rock_normal, p.xz * s) * w.y + texture(rock_normal, p.xy * s) * w.z).rgb;
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
	vec3 n = normalize(w_nrm);
	vec3 rock = triplanar_color(rock_albedo, w_pos, n, rock_scale).rgb * rock_tint;
	float ln = vnoise(w_pos.xz * 1.7 + w_pos.y * 0.9) * 0.6 + vnoise(w_pos.xz * 6.0 - w_pos.y * 3.0) * 0.4;
	float lichen = smoothstep(0.55, 0.7, ln) * lichen_amount;
	vec3 col = mix(rock, lichen_color * (0.85 + 0.3 * ln), lichen);
	float mn = vnoise(w_pos.xz * 0.9) * 0.7 + vnoise(w_pos.xz * 4.0) * 0.3;
	float moss = smoothstep(0.45, 0.85, n.y + (mn - 0.5) * 0.6) * moss_amount;
	vec3 moss_c = triplanar_color(moss_albedo, w_pos, n, moss_scale).rgb * vec3(0.75, 0.9, 0.55);
	col = mix(col, moss_c, moss);
	ALBEDO = col * COLOR.rgb;
	NORMAL_MAP = triplanar_normal(w_pos, n, rock_scale);
	NORMAL_MAP_DEPTH = mix(1.0, 0.3, moss);
	ROUGHNESS = mix(0.82, 0.95, moss);
	SPECULAR = 0.3;
}
