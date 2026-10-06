shader_type spatial;
// Memory Nexus floor. One shader for the walkable floor plane and the dais
// tiers. The walkable area is a signed-distance union of circles and
// capsules (set from MemoryNexus.gd, same shapes as the collision). Inside:
// two-tone marble parquet in diamonds with gold inlay rings. Toward the edge
// the floor breaks into Voronoi flakes with glowing blue borders that thin
// out into the void.

#include "res://shaders/nexus_common.gdshaderinc"

uniform sampler2D albedo_a : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D albedo_b : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float tile_size = 2.3;
uniform vec4 tint_a : source_color = vec4(0.78, 0.6, 0.44, 1.0);
uniform vec4 tint_b : source_color = vec4(1.25, 1.0, 0.78, 1.0);

// xy = centre (world xz), z = radius, w = 1 for gold inlay rings.
uniform vec4 circles[12];
uniform int circle_count = 0;
// xy = start, zw = end (world xz).
uniform vec4 capsules[8];
uniform int capsule_count = 0;
uniform float capsule_radius = 2.6;

uniform bool erosion = true;
uniform float erosion_width = 7.0;
uniform float flake_size = 0.55;
uniform vec4 glow_color : source_color = vec4(0.18, 0.48, 1.0, 1.0);
uniform float glow_energy = 3.0;
uniform vec4 gold : source_color = vec4(0.92, 0.7, 0.34, 1.0);

// Dais tiers: side faces get a gold trim band just below top_y.
uniform bool tier_mode = false;
uniform float top_y = 0.0;

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float sd_shapes(vec2 p) {
	float d = 1e5;
	for (int i = 0; i < 12; i++) {
		if (i >= circle_count) break;
		d = min(d, length(p - circles[i].xy) - circles[i].z);
	}
	for (int i = 0; i < 8; i++) {
		if (i >= capsule_count) break;
		vec2 a = capsules[i].xy;
		vec2 b = capsules[i].zw;
		vec2 pa = p - a;
		vec2 ba = b - a;
		float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
		d = min(d, length(pa - ba * h) - capsule_radius);
	}
	return d;
}

vec2 narrow_cell(vec2 uv, float salt, out vec2 cell_size) {
	vec2 cell = floor(uv);
	vec2 f = clamp(fract(uv), 0.004, 0.996);
	float index = nx_hash(cell + salt) < 0.5 ? 0.0 : 15.0;
	cell_size = vec2(0.25);
	return vec2((mod(index, 4.0) + f.x) * 0.25, (floor(index / 4.0) + f.y) * 0.25);
}

// Gold inlay: rings, spokes and a rim on circles flagged w = 1. Returns 0-1.
float inlay(vec2 p) {
	float g = 0.0;
	for (int i = 0; i < 12; i++) {
		if (i >= circle_count) break;
		vec4 c = circles[i];
		if (c.w < 0.5) continue;
		float d = length(p - c.xy);
		float r = c.z;
		if (d > r) continue;
		float w = 0.05;
		g = max(g, 1.0 - smoothstep(w, w + 0.03, abs(d - (r - 1.0))));
		g = max(g, 1.0 - smoothstep(w, w + 0.03, abs(d - (r - 1.4))));
		g = max(g, 1.0 - smoothstep(w, w + 0.03, abs(d - r * 0.52)));
		g = max(g, 1.0 - smoothstep(w * 1.4, w * 1.4 + 0.03, abs(d - r * 0.3)));
		if (d > r * 0.3 && d < r * 0.52) {
			float a = atan(p.y - c.y, p.x - c.x) / TAU * 24.0;
			float arc = abs(fract(a) - 0.5) / 24.0 * TAU * d;
			g = max(g, 1.0 - smoothstep(0.035, 0.065, arc));
		}
	}
	return g;
}

void fragment() {
	vec2 p = wp.xz;
	float sd = sd_shapes(p);
	float n = nx_fbm(p * 0.22);

	// Erosion: e < 0 is solid floor, 0..1 the flake band, > 1 the void.
	float e = (sd + (n - 0.5) * 2.0) / erosion_width;
	vec3 vor = vec3(1.0);
	if (erosion) {
		if (e > 1.0) discard;
		vor = nx_voronoi(p / flake_size);
		if (e > 0.0) {
			float flicker = 0.035 * sin(TIME * 0.6 + vor.z * 40.0);
			if (vor.z < pow(e, 0.7) * 1.05 + flicker) discard;
		}
	}

	// Two-tone diamond parquet: alternating marble on a 45-degree grid,
	// with dark grooves between the diamonds.
	float s = 2.2;
	vec2 q = vec2(p.x + p.y, p.x - p.y) / s;
	float parity = mod(floor(q.x) + floor(q.y), 2.0);
	float groove = min(abs(fract(q.x) - 0.5), abs(fract(q.y) - 0.5));
	groove = 1.0 - smoothstep(0.46, 0.49, groove);

	vec2 uv = p / tile_size;
	if (tier_mode && abs(wn.y) < 0.5) {
		uv = vec2(wp.x + wp.z, -wp.y) / tile_size;
		parity = 0.0;
		groove = 0.0;
	}
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec2 cs;
	vec2 ua = narrow_cell(uv, 0.0, cs);
	vec2 ub = narrow_cell(uv, 17.0, cs);
	vec3 col_a = textureGrad(albedo_a, ua, dx * cs, dy * cs).rgb * tint_a.rgb;
	vec3 col_b = textureGrad(albedo_b, ub, dx * cs, dy * cs).rgb * tint_b.rgb;
	vec3 nrm = mix(textureGrad(normal_a, ua, dx * cs, dy * cs).rgb, textureGrad(normal_b, ub, dx * cs, dy * cs).rgb, parity);
	vec3 col = mix(col_a, mix(col_a, col_b, 0.5), parity);
	col *= 0.85 + 0.3 * n;
	col *= 1.0 - groove * 0.55;

	float metal = 0.05;
	float rough = 0.55 - parity * 0.15;
	vec3 emit = vec3(0.0);

	float g = tier_mode && abs(wn.y) < 0.5
		? 1.0 - smoothstep(0.04, 0.07, abs(wp.y - (top_y - 0.07)))
		: inlay(p);
	if (g > 0.0) {
		col = mix(col, gold.rgb * (0.8 + 0.4 * n), g);
		metal = mix(metal, 0.9, g);
		rough = mix(rough, 0.28, g);
		emit += gold.rgb * g * 0.08;
	}

	if (erosion) {
		// Fine blue hairline cracks creeping in before the flakes start.
		float creep = smoothstep(-0.55, 0.0, e);
		vec3 hair = nx_voronoi(p / 1.9);
		float crack = (1.0 - smoothstep(0.0, 0.025, hair.y)) * creep * step(0.7, hair.z);
		emit += glow_color.rgb * crack * glow_energy * 0.5;

		if (e > 0.0) {
			float ee = clamp(e, 0.0, 1.0);
			float edge_w = mix(0.03, 0.1, ee);
			float border = 1.0 - smoothstep(0.0, edge_w, vor.y);
			col = mix(col, col * 0.18 + vec3(0.0, 0.02, 0.06), clamp(ee * 1.6, 0.0, 1.0));
			col = mix(col, vec3(0.01, 0.03, 0.09), border);
			float pulse = 0.85 + 0.15 * sin(TIME * 1.3 + vor.z * 25.0);
			emit += glow_color.rgb * border * glow_energy * smoothstep(0.0, 0.25, ee) * (0.25 + ee * 1.2) * pulse;
			if (nx_hash(vec2(vor.z * 91.0, 3.0)) > 0.9) {
				emit += glow_color.rgb * glow_energy * 0.18 * ee;
			}
			metal = mix(metal, 0.0, ee);
			rough = mix(rough, 0.8, ee);
		}
	}

	ALBEDO = col;
	NORMAL_MAP = nrm;
	METALLIC = metal;
	ROUGHNESS = rough;
	EMISSION = emit;
}
