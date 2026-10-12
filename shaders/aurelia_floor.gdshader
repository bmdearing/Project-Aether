shader_type spatial;
// Aurelia's arena floor: black obsidian veined with violet fel light, cut
// into a wheel (spokes and rings, so the Earth Wheel's wedges read), with
// a Warcraft III demon seal glowing under the hub and a ring of demon
// sigils near the rim. UV is the disc's PlaneMesh UV (2*radius wide).
render_mode diffuse_burley, specular_schlick_ggx;

uniform float radius = 26.0;
uniform float spoke_deg = 15.0;
uniform float ring_step = 4.0;
uniform vec3 stone : source_color = vec3(0.03, 0.02, 0.045);
uniform vec3 stone_light : source_color = vec3(0.09, 0.06, 0.12);
uniform vec3 inlay : source_color = vec3(0.45, 0.2, 0.65);
uniform vec3 fel : source_color = vec3(0.7, 0.2, 1.0);
uniform float seal_radius = 6.5;
uniform float sigil_radius = 22.6;
uniform float sigil_size = 2.2;
uniform int sigils = 16;
uniform sampler2D seal : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D rune_a : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D rune_b : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D rune_c : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D rune_d : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D rune_e : source_color, filter_linear_mipmap, repeat_disable;

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

// Thin bright cracks: where two noise bands meet.
float veins(vec2 p) {
	float n = vnoise(p * 0.45) * 0.65 + vnoise(p * 1.3) * 0.35;
	return 1.0 - smoothstep(0.0, 0.035, abs(n - 0.5));
}

float sigil(int k, vec2 uv) {
	int i = k % 5;
	if (i == 0) return texture(rune_a, uv).r;
	if (i == 1) return texture(rune_b, uv).r;
	if (i == 2) return texture(rune_c, uv).r;
	if (i == 3) return texture(rune_d, uv).r;
	return texture(rune_e, uv).r;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * radius;
	float dist = length(p);
	if (dist > radius) discard;
	float a = atan(p.x, p.y);
	float n = vnoise(p * 0.8) * 0.6 + vnoise(p * 3.1) * 0.4;
	vec3 col = mix(stone, stone_light, n * 0.6);
	float pulse = 0.6 + 0.4 * sin(TIME * 1.3);
	vec3 glow = vec3(0.0);
	// Fel veins in the stone, slowly breathing.
	float v = veins(p) * step(seal_radius + 0.5, dist);
	glow += fel * v * (0.35 + 0.25 * sin(TIME * 0.9 + dist * 0.4));
	// Spokes and rings as dark violet inlay, in metres so they stay even.
	float deg = degrees(a);
	float spoke_m = abs(mod(deg + spoke_deg * 0.5, spoke_deg) - spoke_deg * 0.5) * 0.01745 * dist;
	float spoke = (1.0 - smoothstep(0.03, 0.07, spoke_m)) * step(seal_radius, dist);
	float ring = 1.0 - smoothstep(0.03, 0.08, abs(mod(dist + ring_step * 0.5, ring_step) - ring_step * 0.5));
	float lines = max(spoke, ring) * step(dist, sigil_radius - 1.6) + (1.0 - smoothstep(0.04, 0.09, abs(dist - (radius - 0.3))));
	col = mix(col, inlay * 0.5, lines * 0.8);
	glow += inlay * lines * 0.25;
	// The demon seal under the hub, turning slowly.
	if (dist < seal_radius) {
		float ca = cos(TIME * 0.08);
		float sa = sin(TIME * 0.08);
		vec2 q = mat2(vec2(ca, -sa), vec2(sa, ca)) * p / (seal_radius * 2.0) + 0.5;
		float s = texture(seal, q).r;
		float edge = 1.0 - smoothstep(seal_radius - 1.0, seal_radius, dist);
		glow += fel * s * (0.45 + 0.2 * pulse) * edge;
		col = mix(col, fel * 0.15, s * edge);
	}
	// A ring of sigils near the rim, each upright toward the centre.
	float slot = TAU / float(sigils);
	float k = floor((a + PI) / slot);
	float local_a = (a + PI) - (k + 0.5) * slot;
	vec2 sp = vec2(local_a * dist, dist - sigil_radius) / sigil_size + 0.5;
	if (sp.x > 0.0 && sp.x < 1.0 && sp.y > 0.0 && sp.y < 1.0) {
		float s = sigil(int(k), vec2(sp.x, 1.0 - sp.y));
		float flicker = 0.7 + 0.3 * sin(TIME * 2.0 + k * 1.7);
		glow += fel * s * 0.9 * flicker;
		col = mix(col, fel * 0.12, s);
	}
	// Faint guide rings either side of the sigils.
	float guide = (1.0 - smoothstep(0.03, 0.07, abs(dist - (sigil_radius - sigil_size * 0.62)))) + (1.0 - smoothstep(0.03, 0.07, abs(dist - (sigil_radius + sigil_size * 0.62))));
	glow += fel * guide * 0.6 * pulse;
	ALBEDO = col;
	EMISSION = glow;
	ROUGHNESS = mix(0.18, 0.45, n);
	METALLIC = 0.25;
}
