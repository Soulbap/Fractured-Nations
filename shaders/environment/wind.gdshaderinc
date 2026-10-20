// Shared wind sway for the WORLD-TERRAIN-01 vegetation (bark, foliage and impostors use
// the same function so branches and leaves move together). Model space, Y up; the sway
// grows with height above the asset origin. Per-instance phase from the instance origin.
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.1;
uniform float sway_height = 14.0;
uniform vec2 wind_dir = vec2(0.8, 0.45);

vec3 wind_offset(vec3 vertex, mat4 model, float time) {
	float h = clamp(vertex.y / sway_height, 0.0, 1.4);
	float phase = dot(model[3].xz, vec2(0.071, 0.113));
	float s = sin(time * wind_speed + phase) * 0.65 + sin(time * wind_speed * 2.31 + phase * 1.7 + vertex.x * 0.4) * 0.35;
	vec2 d = normalize(wind_dir);
	return vec3(d.x, 0.0, d.y) * s * wind_strength * h * h;
}
