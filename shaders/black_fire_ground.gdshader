shader_type spatial;
// Amaterasu: ground the black fire has taken, on a disc PlaneMesh 2*radius
// wide. Inside `safe_radius` it's clear; beyond it the floor is charred black
// with crawling violet-crimson embers, brightest along the creeping edge.
// Mixed, not added: an additive pass can't draw black.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float radius = 22.0;
uniform float safe_radius = 22.0;
uniform vec3 char_color : source_color = vec3(0.015, 0.008, 0.02);
uniform vec3 ember : source_color = vec3(0.55, 0.08, 0.6);
uniform vec3 edge_color : source_color = vec3(0.85, 0.25, 0.95);

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
	vec2 p = (UV - 0.5) * 2.0 * radius;
	float dist = length(p);
	if (dist > radius + 2.0) discard;
	float n = vnoise(p * 0.6 + vec2(0.0, -TIME * 0.4)) * 0.6 + vnoise(p * 1.7 - TIME * 0.7) * 0.4;
	// A ragged, flickering edge rather than a clean circle.
	float edge = safe_radius + (n - 0.5) * 1.4;
	float burnt = smoothstep(edge - 0.3, edge + 0.6, dist);
	if (burnt <= 0.001) discard;
	float glow_n = vnoise(p * 1.1 + vec2(TIME * 0.5, -TIME * 0.7)) * 0.7 + vnoise(p * 2.6 - TIME * 0.4) * 0.3;
	float embers = smoothstep(0.55, 0.85, glow_n) * (0.6 + 0.4 * sin(TIME * 4.0 + p.x));
	float front = 1.0 - smoothstep(0.0, 1.8, dist - edge);
	vec3 col = char_color;
	col = mix(col, ember, embers * 0.8);
	col = mix(col, edge_color, front * (0.55 + 0.45 * n));
	ALBEDO = col;
	ALPHA = clamp(burnt * (0.86 + front * 0.1), 0.0, 1.0);
}
