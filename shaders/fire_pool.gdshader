shader_type spatial;
// A pool of burning fire on the ground (Aurelia's fire pots), on a PlaneMesh
// 2 units wide: churning flame noise, hottest in the middle, with a ragged
// bright rim so its edge reads from first person.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 hot : source_color = vec3(1.0, 0.8, 0.4);
uniform vec3 mid : source_color = vec3(1.0, 0.38, 0.06);
uniform vec3 cool : source_color = vec3(0.4, 0.05, 0.01);
uniform float intensity = 1.0;
uniform float grow = 1.0;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	// Ragged edge that flickers.
	float edge = (0.82 + 0.12 * vnoise(vec2(a * 3.0, TIME * 1.5))) * grow;
	if (r > edge + 0.05) discard;
	vec2 q = p * 3.0;
	float n = vnoise(q + vec2(TIME * 0.7, -TIME * 0.9)) * 0.55 + vnoise(q * 2.1 - vec2(TIME * 1.3, TIME * 0.4)) * 0.3 + vnoise(q * 4.3 + TIME) * 0.15;
	float heat = clamp(n * 1.2 - r * 0.45 + 0.2, 0.0, 1.0);
	vec3 col = heat > 0.5 ? mix(mid, hot, (heat - 0.5) * 2.0) : mix(cool, mid, heat * 2.0);
	float rim = smoothstep(edge - 0.18, edge - 0.02, r) * (1.0 - smoothstep(edge - 0.02, edge + 0.05, r));
	col += mid * rim * 1.2;
	float fade = 1.0 - smoothstep(edge - 0.02, edge + 0.05, r);
	ALBEDO = col * intensity * (0.55 + heat * 0.7);
	ALPHA = clamp(fade * (0.6 + heat * 0.4), 0.0, 1.0);
}
