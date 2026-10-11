// Clustered pits for the Pale family: groups of round holes, big in the
// middle of a cluster and shrinking toward its edge, with a raised lip.
// p is in metres on whatever plane the caller projects onto.

uniform float pit_amount : hint_range(0.0, 1.0) = 0.0;  // share of the surface covered by clusters
uniform float pit_scale = 0.6;                          // metres between neighbouring pits
uniform vec4 pit_color : source_color = vec4(0.09, 0.06, 0.055, 1.0);
// 0..1 setting that tones every pit down (Settings > Reduce hole patterns).
global uniform float pale_pit_strength;

float pit_hash(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

vec2 pit_hash2(vec2 p) {
	return vec2(pit_hash(p), pit_hash(p + 19.19));
}

float pit_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(pit_hash(i), pit_hash(i + vec2(1.0, 0.0)), f.x),
		mix(pit_hash(i + vec2(0.0, 1.0)), pit_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// One octave of pits. hole: 0 outside, up to 1 at the bottom of a pit.
// rim: the raised lip around it. tilt: which way the surface leans (2D).
void pit_layer(vec2 p, float spacing, float salt, float cluster_scale, float amount, inout float hole, inout float rim, inout vec2 tilt) {
	vec2 q = p / spacing;
	vec2 cell = floor(q);
	float best = 1e9;
	float best_r = 0.0;
	vec2 best_d = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			vec2 centre = c + 0.15 + 0.7 * pit_hash2(c + salt);
			// Cluster strength at this pit, so neighbours shrink together.
			float m = pit_noise(centre * spacing / cluster_scale + salt);
			m = smoothstep(1.0 - amount - 0.12, 1.0 - amount + 0.18, m);
			if (m <= 0.02 || pit_hash(c + salt + 7.7) > 0.35 + m) {
				continue;
			}
			float r = mix(0.12, 0.4, m) * (0.75 + 0.35 * pit_hash(c + salt + 3.3));
			vec2 d = q - centre;
			float dist = length(d) / r;
			if (dist < best) {
				best = dist;
				best_r = r;
				best_d = d;
			}
		}
	}
	if (best > 1.35) {
		return;
	}
	vec2 dir = best_d / max(length(best_d), 1e-4);
	if (best < 1.0) {
		float h = sqrt(1.0 - best * best);
		if (h > hole) {
			hole = h;
			tilt = -dir * best * 0.9;
		}
	} else {
		float lip = 1.0 - abs(best - 1.12) / 0.23;
		if (lip > rim) {
			rim = lip;
			if (hole <= 0.0) {
				tilt = dir * lip * 0.5;
			}
		}
	}
}

// Both octaves: the main pits and a finer scatter of small ones between them.
void pale_pits(vec2 p, float amount, out float hole, out float rim, out vec2 tilt) {
	hole = 0.0;
	rim = 0.0;
	tilt = vec2(0.0);
	amount *= pale_pit_strength;
	if (amount <= 0.0) {
		return;
	}
	pit_layer(p, pit_scale, 0.0, pit_scale * 9.0, amount, hole, rim, tilt);
	pit_layer(p, pit_scale * 0.42, 31.0, pit_scale * 9.0, amount * 0.85, hole, rim, tilt);
	float s = pale_pit_strength;
	hole *= s;
	rim *= s;
	tilt *= s;
}

// Darkens the pit interior toward pit_color and lightens the lip.
vec3 pale_pit_albedo(vec3 col, float hole, float rim) {
	col = mix(col, col * 1.12 + 0.03, rim * 0.5);
	return mix(col, pit_color.rgb, pow(hole, 0.55));
}
