shader_type spatial;
render_mode unshaded, cull_disabled;
// A mountain layer for the title screen: a flat ridge strip (UV.y 0 at the
// crest, 1 at the base). Rock striations, a moonlit rim along the crest
// that is brightest toward the moon's side, and mist pooling at the base.

uniform vec3 rock : source_color = vec3(0.05, 0.055, 0.08);
uniform vec3 rim_color : source_color = vec3(0.55, 0.6, 0.78);
uniform vec3 mist_color : source_color = vec3(0.07, 0.085, 0.13);
uniform float rim_strength = 0.6;
uniform float mist_amount = 0.6;
uniform float moon_x = 60.0;
uniform float flash = 0.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float n = vnoise(vec2(wp.x * 0.08, wp.y * 0.02)) * 0.6 + vnoise(vec2(wp.x * 0.4, wp.y * 0.08)) * 0.4;
	float streak = vnoise(vec2(wp.x * 0.9, wp.y * 0.05));
	vec3 col = rock * (0.7 + 0.6 * n) * (0.85 + 0.3 * streak);
	float side = exp(-abs(wp.x - moon_x) * 0.012);
	float rim = (1.0 - smoothstep(0.0, 0.03, UV.y)) * rim_strength * (0.12 + side) * (0.4 + 0.9 * streak);
	col += rim_color * rim;
	col = mix(col, mist_color, smoothstep(0.35, 1.0, UV.y) * mist_amount);
	col += vec3(0.6, 0.65, 0.85) * flash * (0.35 + rim * 1.5);
	ALBEDO = col;
}
