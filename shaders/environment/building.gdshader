// VISUAL-02 settlement buildings and fences (assets built by tools/blender/env/make_structures.py, textures from
// make_building_textures.py). The MultiMesh instance colour (the settlement layer's paint: white, cream, yellow, red ochre,
// pale blue) reaches the shader as COLOR (the meshes' vertex colours are white); tint_strength says how much of it a
// material takes: siding and doors take it, roofs, stone, glass and trim do not. base_color is the material's own paint
// (Falu red on barns and sheds). AO and a little dirt come from the height above the ground (origin on the ground).
shader_type spatial;
// Double-sided like the flat-colour materials before (a few kit faces are wound inward); Godot flips back-face normals.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 base_color : source_color = vec3(1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float normal_depth = 1.0;
uniform float ao_height = 1.4;
uniform float ao_min = 0.7;
uniform float dirt = 0.35;
// Fence rails: the grain of bld_wood_grey runs along U; tubes run their length along V.
uniform bool swap_uv = false;

varying float v_height;

void vertex() {
	v_height = VERTEX.y;
}

void fragment() {
	vec2 uv = swap_uv ? UV.yx : UV;
	vec3 tex = texture(albedo_tex, uv).rgb;
	vec3 tint = mix(vec3(1.0), COLOR.rgb, tint_strength);
	vec3 a = tex * base_color * tint;
	float ao = mix(ao_min, 1.0, smoothstep(0.0, ao_height, v_height));
	a *= ao;
	a = mix(a, a * vec3(0.78, 0.72, 0.62), dirt * (1.0 - smoothstep(0.05, 0.9, v_height)));
	ALBEDO = a;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = roughness;
	SPECULAR = 0.2;
}
