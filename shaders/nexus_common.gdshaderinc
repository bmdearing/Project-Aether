// Shared noise for the Memory Nexus shaders.

float nx_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 nx_hash2(vec2 p) {
	return vec2(nx_hash(p), nx_hash(p + 19.19));
}

float nx_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(nx_hash(i), nx_hash(i + vec2(1.0, 0.0)), f.x),
		mix(nx_hash(i + vec2(0.0, 1.0)), nx_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float nx_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += nx_noise(p) * a;
		p = p * 2.03 + 7.1;
		a *= 0.5;
	}
	return v;
}

// x = distance to nearest cell point, y = distance to the cell border
// (F2 - F1, 0 on an edge), z = a stable random id for the cell.
vec3 nx_voronoi(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	vec2 best = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = nx_hash2(n + g) * 0.85 + 0.075;
			float d = length(g + o - f);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				best = n + g;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec3(f1, f2 - f1, nx_hash(best + 3.7));
}
