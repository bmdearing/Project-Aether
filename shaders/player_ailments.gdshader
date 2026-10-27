shader_type canvas_item;
// Screen-edge looks for ailments on the player (AilmentOverlay): flames
// licking up from the bottom (Ignite), frost creeping in from the edges
// (Chill/Freeze), crackling flicker (Shock), a pulsing red rim (Bleed) and a
// slow violet swirl (Esoteric ailments). Each strength runs 0-1.

uniform float ignite = 0.0;
uniform float chill = 0.0;
uniform float shock = 0.0;
uniform float bleed = 0.0;
uniform float esoteric = 0.0;
uniform float aspect = 1.7778;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	// Distance to the nearest screen edge, in screen heights.
	float e = min(min(uv.x, 1.0 - uv.x) * aspect, min(uv.y, 1.0 - uv.y));
	vec3 rgb = vec3(0.0);
	float a = 0.0;

	if (ignite > 0.0) {
		float n = noise(vec2(uv.x * aspect * 7.0, uv.y * 5.0 + TIME * 3.0));
		float height = 0.22 * ignite + n * 0.12;
		float flame = (1.0 - smoothstep(0.0, height, 1.0 - uv.y)) * ignite;
		flame = max(flame, (1.0 - smoothstep(0.0, 0.1 + n * 0.05, e)) * ignite * 0.5);
		vec3 col = mix(vec3(1.0, 0.25, 0.05), vec3(1.0, 0.75, 0.2), n);
		rgb += col * flame * 0.8;
		a = max(a, flame * 0.75);
	}
	if (chill > 0.0) {
		float n = noise(uv * vec2(aspect, 1.0) * 26.0) * 0.6 + noise(uv * vec2(aspect, 1.0) * 70.0) * 0.4;
		float reach = 0.06 + 0.16 * chill;
		float frost = 1.0 - smoothstep(reach * 0.5, reach, e + (n - 0.5) * 0.08);
		float glint = step(0.93, noise(uv * vec2(aspect, 1.0) * 120.0 + floor(TIME * 2.0))) * frost;
		rgb += vec3(0.75, 0.92, 1.0) * (frost * 0.55 + glint * 0.6);
		a = max(a, frost * 0.6 * clamp(chill * 1.3, 0.0, 1.0));
	}
	if (shock > 0.0) {
		float beat = step(0.7, hash(vec2(floor(TIME * 16.0), 3.1)));
		float crackle = 1.0 - smoothstep(0.0, 0.025, abs(noise(vec2(uv.x * aspect * 10.0, uv.y * 10.0 + floor(TIME * 12.0))) - 0.5));
		float rim = 1.0 - smoothstep(0.0, 0.14, e);
		float s = rim * (0.35 + beat * 0.65) * shock + crackle * rim * shock * 0.8;
		rgb += vec3(0.8, 0.82, 1.0) * s;
		a = max(a, s * 0.7);
	}
	if (bleed > 0.0) {
		float pulse = 0.55 + 0.45 * sin(TIME * 5.0);
		float rim = 1.0 - smoothstep(0.0, 0.16, e);
		float b = rim * pulse * bleed;
		rgb += vec3(0.7, 0.02, 0.02) * b;
		a = max(a, b * 0.7);
	}
	if (esoteric > 0.0) {
		vec2 c = (uv - 0.5) * vec2(aspect, 1.0);
		float ang = atan(c.y, c.x);
		float swirl = 0.5 + 0.5 * sin(ang * 5.0 + length(c) * 12.0 - TIME * 2.0);
		float rim = 1.0 - smoothstep(0.0, 0.15, e);
		float s = rim * (0.5 + swirl * 0.5) * esoteric;
		rgb += vec3(0.65, 0.35, 1.0) * s;
		a = max(a, s * 0.6);
	}
	COLOR = vec4(clamp(rgb / max(a, 0.001), 0.0, 1.0), clamp(a, 0.0, 0.85));
}
