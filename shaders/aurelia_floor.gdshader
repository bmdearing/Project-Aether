shader_type spatial;
// Aurelia's arena floor: dark polished slate cut into a wheel - spokes every
// `spoke_deg` and concentric rings - so the Earth Wheel's wedges read
// against it, with a faint rune band of frost-blue light near the rim.
// UV is the disc's PlaneMesh UV (2*radius wide, centred).
render_mode diffuse_burley, specular_schlick_ggx;

uniform float radius = 26.0;
uniform float spoke_deg = 15.0;
uniform float ring_step = 4.0;
uniform vec3 stone : source_color = vec3(0.075, 0.07, 0.09);
uniform vec3 stone_light : source_color = vec3(0.14, 0.13, 0.16);
uniform vec3 inlay : source_color = vec3(0.55, 0.45, 0.28);
uniform vec3 rune : source_color = vec3(0.35, 0.75, 1.0);

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
	if (dist > radius) discard;
	float a = degrees(atan(p.x, p.y));
	float n = vnoise(p * 0.8) * 0.6 + vnoise(p * 3.1) * 0.4;
	vec3 col = mix(stone, stone_light, n * 0.7);
	// Spokes and rings as thin gold inlay, in metres so they stay even.
	float spoke_m = abs(mod(a + spoke_deg * 0.5, spoke_deg) - spoke_deg * 0.5) * 0.01745 * dist;
	float spoke = (1.0 - smoothstep(0.03, 0.07, spoke_m)) * step(3.0, dist);
	float ring = 1.0 - smoothstep(0.03, 0.08, abs(mod(dist + ring_step * 0.5, ring_step) - ring_step * 0.5));
	float lines = max(spoke, ring) * step(dist, radius - 3.5) + (1.0 - smoothstep(0.04, 0.09, abs(dist - (radius - 0.3))));
	col = mix(col, inlay, lines * 0.75);
	// Rune band: two thin rings with a row of dashes between them.
	float rd = abs(dist - (radius - 2.2));
	float rings = 1.0 - smoothstep(0.03, 0.07, abs(rd - 0.45));
	float dash = step(0.35, fract(a / 4.0)) * step(fract(a / 4.0), 0.85) * (1.0 - smoothstep(0.12, 0.18, rd));
	float band = max(rings, dash);
	float glyph = 1.0;
	float pulse = 0.65 + 0.35 * sin(TIME * 1.1 + a * 0.05);
	ALBEDO = col;
	EMISSION = rune * band * glyph * pulse * 1.4 + inlay * lines * 0.08;
	ROUGHNESS = mix(0.35, 0.7, n);
	METALLIC = lines * 0.6;
}
