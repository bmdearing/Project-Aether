shader_type spatial;
// Pale family doodads: chalky bone-white with soft mottling, optional lumps
// pushed into the mesh (never out, so the mesh AABB still holds), and
// clustered pits projected from all three axes in world space.

uniform vec4 albedo : source_color = vec4(0.9, 0.87, 0.8, 1.0);
uniform vec4 mottle : source_color = vec4(0.72, 0.68, 0.6, 1.0);
uniform float mottle_scale = 1.6;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
// Inward displacement in metres and its noise frequency (object space).
uniform float lump = 0.0;
uniform float lump_freq = 1.2;

#include "res://shaders/pale_pits.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_normal;

float hash3(vec3 p) {
	p = fract(p * vec3(127.1, 311.7, 74.7));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

float lump_at(vec3 p) {
	return noise3(p * lump_freq) * 0.65 + noise3(p * lump_freq * 2.3 + 5.0) * 0.35;
}

void vertex() {
	if (lump > 0.0) {
		// Displace along the normal, then rebuild the normal from two nearby
		// displaced points so the lumps shade.
		vec3 n = normalize(NORMAL);
		vec3 t = normalize(cross(n, abs(n.y) < 0.99 ? vec3(0, 1, 0) : vec3(1, 0, 0)));
		vec3 b = cross(n, t);
		float e = 0.05;
		vec3 p0 = VERTEX - n * lump * lump_at(VERTEX);
		vec3 pt = VERTEX + t * e - n * lump * lump_at(VERTEX + t * e);
		vec3 pb = VERTEX + b * e - n * lump * lump_at(VERTEX + b * e);
		VERTEX = p0;
		NORMAL = normalize(cross(pt - p0, pb - p0));
		if (dot(NORMAL, n) < 0.0) {
			NORMAL = -NORMAL;
		}
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = abs(world_normal);
	w = pow(w, vec3(4.0));
	w /= w.x + w.y + w.z;
	float m = noise3(world_pos * mottle_scale) * 0.6 + noise3(world_pos * mottle_scale * 3.1) * 0.4;
	vec3 col = mix(mottle.rgb, albedo.rgb, smoothstep(0.25, 0.75, m));
	float ao = 1.0;
	if (pit_amount > 0.0) {
		// One pit pattern per projection axis, blended by facing.
		// Each plane's coordinates are world axes, so its tilt bends the
		// normal along those axes directly.
		float hole = 0.0;
		float rim = 0.0;
		vec3 bend = vec3(0.0);
		vec2 tilt;
		float h;
		float r;
		pale_pits(world_pos.zy, pit_amount, h, r, tilt);
		hole += h * w.x;
		rim += r * w.x;
		bend += vec3(0.0, tilt.y, tilt.x) * w.x;
		pale_pits(world_pos.xz, pit_amount, h, r, tilt);
		hole += h * w.y;
		rim += r * w.y;
		bend += vec3(tilt.x, 0.0, tilt.y) * w.y;
		pale_pits(world_pos.xy, pit_amount, h, r, tilt);
		hole += h * w.z;
		rim += r * w.z;
		bend += vec3(tilt.x, tilt.y, 0.0) * w.z;
		col = pale_pit_albedo(col, hole, rim);
		ao = 1.0 - hole * 0.8;
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bend * 1.4, 0.0)).xyz);
	}
	ALBEDO = col;
	ROUGHNESS = roughness;
	AO = ao;
}
