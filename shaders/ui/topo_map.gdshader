// UI-UX-03 tactical map: the world as a military topographic sheet, drawn on the GPU from the world's own data (MapTopo).
//   height   Terrain3D's height maps (in memory, with the settlement, shoulder and relief edits), 256 px per 2 km region
//   veg      vegetation.png  R forest density, A wetness
//   info     info.png        R rockiness, G fields, B settlement, A water
//   terr     territory: one channel per faction (1 = held), linearly filtered, so its 0.5 crossing is a smooth border
// Paper tint by height, cultivated and wooded areas in the classic topo colours, a soft hillshade, contour lines whose interval
// follows the zoom (thin minor, darker every fifth, faded where they would crowd), water, and territory as a light tint with
// a firm border line. Everything is computed per pixel: no CPU work when the map pans or zooms.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D veg_tex : filter_linear, repeat_disable;
uniform sampler2D info_tex : filter_linear, repeat_disable;
uniform sampler2D terr_tex : filter_linear, repeat_disable;
uniform vec2 height_range = vec2(0.0, 1000.0);
uniform float world_size = 20000.0;
uniform vec2 height_texel = vec2(0.000390625);
uniform float interval = 20.0;
uniform float relief = 1.0;
uniform float contours = 1.0;
uniform float territory = 1.0;
uniform float terr_fill = 0.13;
uniform vec4 fac0 : source_color = vec4(0.3, 0.5, 0.9, 1.0);
uniform vec4 fac1 : source_color = vec4(0.9, 0.5, 0.3, 1.0);
uniform vec4 fac2 : source_color = vec4(0.3, 0.8, 0.5, 1.0);
uniform vec4 fac3 : source_color = vec4(0.8, 0.8, 0.8, 1.0);

const vec3 PAPER_LOW = vec3(0.905, 0.893, 0.824);
const vec3 PAPER_HIGH = vec3(0.862, 0.828, 0.742);
const vec3 ALPINE = vec3(0.885, 0.880, 0.860);
const vec3 FIELD = vec3(0.935, 0.915, 0.790);
const vec3 FOREST = vec3(0.640, 0.760, 0.575);
const vec3 FOREST_DENSE = vec3(0.545, 0.690, 0.490);
const vec3 BUILT = vec3(0.850, 0.800, 0.770);
const vec3 ROCK = vec3(0.800, 0.785, 0.760);
const vec3 WATER = vec3(0.600, 0.765, 0.875);
const vec3 CONTOUR = vec3(0.560, 0.390, 0.230);

float h_at(vec2 uv) {
	return texture(height_tex, uv).r;
}

// Anti-aliased line on the iso-lines of v (spacing 1), about w px wide; faded where neighbouring lines come closer than ~4 px.
float iso(float v, float w) {
	float fw = max(fwidth(v), 1e-5);
	float d = abs(fract(v + 0.5) - 0.5) / fw;
	float line = 1.0 - smoothstep(w * 0.5 - 0.5, w * 0.5 + 0.5, d);
	return line * (1.0 - smoothstep(0.16, 0.30, fw));
}

float border(float f) {
	float fw = max(fwidth(f), 1e-4);
	float d = abs(f - 0.5) / fw;
	return 1.0 - smoothstep(0.6, 1.6, d);
}

void fragment() {
	vec2 uv = UV;
	float h = h_at(uv);
	float m_per_texel = world_size * height_texel.x;
	float hx = h_at(uv + vec2(height_texel.x, 0.0)) - h_at(uv - vec2(height_texel.x, 0.0));
	float hz = h_at(uv + vec2(0.0, height_texel.y)) - h_at(uv - vec2(0.0, height_texel.y));
	vec3 n = normalize(vec3(-hx, 2.0 * m_per_texel, -hz));
	// Light from the north-west, high: the cartographic convention.
	float shade = dot(n, normalize(vec3(-0.7, 1.1, -0.9)));
	float t = clamp((h - height_range.x) / max(height_range.y - height_range.x, 1.0), 0.0, 1.0);
	vec3 col = mix(PAPER_LOW, PAPER_HIGH, smoothstep(0.15, 0.85, t));
	vec4 veg = texture(veg_tex, uv);
	vec4 info = texture(info_tex, uv);
	col = mix(col, ALPINE, smoothstep(0.82, 0.97, t) * (1.0 - veg.r));
	col = mix(col, FIELD, smoothstep(0.3, 0.7, info.g) * 0.7);
	col = mix(col, ROCK, smoothstep(0.35, 0.8, info.r) * 0.55);
	float forest = smoothstep(0.22, 0.42, veg.r);
	col = mix(col, mix(FOREST, FOREST_DENSE, smoothstep(0.55, 0.9, veg.r)), forest * 0.92);
	col = mix(col, BUILT, smoothstep(0.35, 0.7, info.b) * 0.45);
	// Hillshade: multiplied in softly, never darker than a mid tone.
	float hs = clamp(0.62 + 0.55 * shade, 0.55, 1.12);
	col *= mix(1.0, hs, relief);
	// Wet ground: a faint blue-green.
	col = mix(col, vec3(0.70, 0.80, 0.78), smoothstep(0.55, 0.9, veg.a) * 0.25 * (1.0 - forest));
	// Contours (none on water).
	float water = smoothstep(0.45, 0.6, info.a);
	float minor = iso(h / interval, 1.0);
	float major = iso(h / (interval * 5.0), 1.8);
	float c_a = max(minor * 0.32, major * 0.62) * contours * (1.0 - water);
	col = mix(col, CONTOUR, c_a);
	col = mix(col, WATER, water);
	// Territory: a light tint inside, a firm line on the border.
	if (territory > 0.0) {
		vec4 tf = texture(terr_tex, uv);
		vec4 cols[4] = vec4[4](fac0, fac1, fac2, fac3);
		for (int i = 0; i < 4; i++) {
			float f = tf[i];
			float inside = smoothstep(0.45, 0.55, f);
			col = mix(col, cols[i].rgb, inside * terr_fill * territory);
			col = mix(col, cols[i].rgb * 0.75, border(f) * 0.85 * territory);
		}
	}
	COLOR = vec4(col, 1.0);
}
