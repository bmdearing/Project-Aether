shader_type canvas_item;
// A glass capsule filled left to right with glowing liquid (ResidueBar).
// fill 0-1; the surface ripples, a shimmer band drifts, bubbles rise.

uniform float fill : hint_range(0.0, 1.0) = 0.5;
uniform vec4 liquid_color : source_color = vec4(0.9, 0.55, 0.2, 1.0);
uniform vec4 glass_color : source_color = vec4(0.05, 0.05, 0.07, 0.85);
uniform vec4 rim_color : source_color = vec4(0.85, 0.7, 0.4, 1.0);
// The control's size in pixels, so the capsule keeps round ends.
uniform vec2 rect_size = vec2(220.0, 22.0);
// Brief brighten when the pool changes (ResidueBar sets it, then fades it).
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

float lattice_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536)) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n >> 8u) * (1.0 / 16777215.0);
}

// Distance to a horizontal capsule filling the rect (negative inside).
float capsule_sdf(vec2 p, vec2 size) {
	float r = size.y * 0.5;
	vec2 a = vec2(r, r);
	vec2 b = vec2(max(size.x - r, r), r);
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

// Bubbles: one per lattice cell, rising and wrapping, only inside the liquid.
float bubbles(vec2 p, float cell) {
	vec2 g = vec2(p.x / cell, p.y / cell + TIME * 0.9);
	vec2 id = floor(g);
	vec2 f = fract(g);
	float seed = lattice_hash(id);
	if (seed > 0.35) {
		return 0.0;
	}
	vec2 c = vec2(0.3 + 0.4 * lattice_hash(id + vec2(7.0, 3.0)), 0.5);
	float r = 0.12 + 0.12 * lattice_hash(id + vec2(2.0, 9.0));
	float d = length(f - c);
	return smoothstep(r, r - 0.06, d) - smoothstep(r - 0.08, r - 0.14, d) * 0.6;
}

void fragment() {
	vec2 size = rect_size;
	vec2 p = UV * size;
	float d = capsule_sdf(p, size);
	float aa = max(fwidth(d), 0.75);
	float inside = 1.0 - smoothstep(-aa, aa, d);
	if (inside <= 0.0) {
		discard;
	}
	float r = size.y * 0.5;
	// Liquid surface: a wavy vertical edge at the fill level.
	float level = mix(0.0, size.x, clamp(fill, 0.0, 1.0));
	float wave = sin(p.y * 0.45 + TIME * 3.0) * 1.4 + sin(p.y * 0.9 - TIME * 4.7) * 0.7;
	float edge = level + (fill > 0.001 && fill < 0.999 ? wave : 0.0);
	float liquid = fill <= 0.001 ? 0.0 : 1.0 - smoothstep(edge - 1.0, edge + 1.0, p.x);

	// Glass: dark, with a faint top highlight.
	float vy = UV.y;
	vec3 col = glass_color.rgb * (0.8 + 0.4 * (1.0 - vy));
	float alpha = glass_color.a;

	// Liquid: deeper at the bottom, brighter at the top, a drifting shimmer.
	vec3 deep = liquid_color.rgb * 0.45;
	vec3 bright = liquid_color.rgb * 1.35;
	vec3 lc = mix(bright, deep, smoothstep(0.1, 1.0, vy));
	float shimmer = smoothstep(0.92, 1.0, sin((p.x - p.y * 1.5) * 0.08 - TIME * 1.6));
	lc += liquid_color.rgb * shimmer * 0.35;
	lc += vec3(1.0) * bubbles(p, max(r * 0.9, 4.0)) * 0.35;
	// Glow line at the surface.
	float surface = smoothstep(3.0, 0.0, abs(p.x - edge)) * step(0.001, fill) * step(fill, 0.999);
	lc += liquid_color.rgb * surface * 0.9;
	lc *= 1.0 + pulse * 0.6;
	col = mix(col, lc, liquid);
	alpha = mix(alpha, 1.0, liquid);

	// Glass sheen across the top third.
	float sheen = smoothstep(0.38, 0.15, vy) * smoothstep(0.02, 0.12, vy);
	col += vec3(1.0) * sheen * 0.12;

	// Rim.
	float rim = 1.0 - smoothstep(0.0, 1.6, abs(d + 0.9));
	col = mix(col, rim_color.rgb, rim * 0.9);
	alpha = max(alpha, rim);

	COLOR = vec4(col, alpha * inside);
}
