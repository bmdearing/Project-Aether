shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;
// Portal face: a vortex of energy spiralling into a dark core, inside an
// oval that matches the ring. UV (0..1) spans the quad; the oval fills it.

uniform vec3 color : source_color = vec3(0.35, 0.65, 1.0);
uniform float energy = 1.6;
uniform float swirl_speed = 0.35;
uniform float inflow_speed = 0.25;
uniform float arms = 3.0;

float lattice_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536)) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n >> 8u) * (1.0 / 16777215.0);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(lattice_hash(i), lattice_hash(i + vec2(1.0, 0.0)), u.x),
		mix(lattice_hash(i + vec2(0.0, 1.0)), lattice_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		total += amp * noise(p);
		p = p * 2.1 + vec2(4.3, 1.9);
		amp *= 0.5;
	}
	return total;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	// Polar coordinates that wind inward over time: log radius makes the
	// spiral arms tighten toward the core.
	float depth = -log(max(r, 0.02));
	float t = TIME;
	vec2 spiral = vec2(a * arms / 6.2832 + depth * 0.6 - t * swirl_speed, depth - t * inflow_speed);
	float bands = fbm(vec2(spiral.x * 4.0, spiral.y * 2.5));
	float streaks = pow(noise(vec2(spiral.x * 18.0, spiral.y * 1.5)), 3.0);
	float swirl = smoothstep(0.35, 0.85, bands) + streaks * 0.8;

	// Bright toward the rim, a dark core that the energy drains into.
	float rim = smoothstep(0.55, 1.0, r);
	float core = smoothstep(0.0, 0.35, r);
	vec3 deep = color * 0.15;
	vec3 hot = mix(color, vec3(1.0), 0.45);
	vec3 col = mix(deep, color, swirl) * core;
	col += hot * pow(rim, 3.0) * 0.9;
	col += hot * smoothstep(0.08, 0.0, abs(r - 0.18)) * 0.35 * (0.6 + 0.4 * sin(t * 3.0));

	float edge_fade = 1.0 - smoothstep(0.93, 1.0, r);
	ALBEDO = col * energy * edge_fade;
	ALPHA = edge_fade;
}
