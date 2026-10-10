shader_type spatial;
// Black Hole's accretion disk (a flat annulus, UV.x around 0..1, UV.y
// inner 0 -> outer 1): streaks spiral inward, spinning faster near the
// core, hot pale light at the inner edge cooling to deep violet outside.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 hot : source_color = vec3(0.95, 0.85, 1.0);
uniform vec3 cool : source_color = vec3(0.35, 0.12, 0.6);
uniform float spin = 0.6;
uniform float intensity = 1.0;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float i0 = mod(i.x, period);
	float i1 = mod(i.x + 1.0, period);
	return mix(mix(h21(vec2(i0, i.y)), h21(vec2(i1, i.y)), f.x), mix(h21(vec2(i0, i.y + 1.0)), h21(vec2(i1, i.y + 1.0)), f.x), f.y);
}

void fragment() {
	float r = UV.y;
	// Inner rings orbit faster; the r offset winds the streaks into a spiral.
	float u = UV.x + TIME * spin / (0.35 + r) + r * 0.6;
	float streak = vnoise(vec2(u * 12.0, r * 6.0 - TIME * 1.5), 12.0) * 0.65 + vnoise(vec2(u * 28.0, r * 14.0), 28.0) * 0.35;
	streak = smoothstep(0.3, 0.9, streak);
	float edges = smoothstep(0.0, 0.12, r) * (1.0 - smoothstep(0.55, 1.0, r));
	float heat = 1.0 - smoothstep(0.0, 0.6, r);
	vec3 col = mix(cool, hot, heat * heat);
	ALBEDO = col * (streak * 1.4 + heat * 0.5) * edges * intensity;
}
