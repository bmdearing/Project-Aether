shader_type spatial;
render_mode unshaded, fog_disabled, cull_front, shadows_disabled;
// Memory Nexus sky: deep space around the void. A wide nebula band arcs
// across the whole sphere (blue, violet and teal gas with dark dust lanes
// and bright cores), a second smaller violet cloud, and stars that crowd
// into the band. 3D noise on the view direction, so there are no seams.

uniform vec3 base_color : source_color = vec3(0.004, 0.006, 0.018);
uniform vec3 band_normal = vec3(0.35, 0.82, 0.45);
uniform float band_width = 0.42;
uniform vec3 color_a : source_color = vec3(0.12, 0.3, 1.0);
uniform vec3 color_b : source_color = vec3(0.55, 0.22, 0.95);
uniform vec3 color_c : source_color = vec3(0.1, 0.75, 0.85);
uniform float intensity = 0.8;
uniform vec3 cloud2_dir = vec3(-0.6, 0.25, -0.75);
uniform float drift = 0.004;

varying vec3 dir;

void vertex() {
	dir = normalize(VERTEX);
}

float h31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		v += noise3(p) * a;
		p = p * 2.03 + vec3(1.7, 9.2, 3.4);
		a *= 0.5;
	}
	return v;
}

float stars(vec3 d, float scale, float threshold) {
	vec3 p = d * scale;
	vec3 cell = floor(p);
	float h = h31(cell);
	if (h < threshold) return 0.0;
	vec3 centre = cell + 0.5 + (vec3(h31(cell + 3.1), h31(cell + 7.7), h31(cell + 1.3)) - 0.5) * 0.7;
	float dist = length(p - centre);
	return (1.0 - smoothstep(0.0, 0.12, dist)) * (0.5 + 0.5 * h31(cell + 5.5));
}

void fragment() {
	vec3 d = normalize(dir);
	vec3 t = vec3(TIME * drift, 0.0, TIME * drift * 0.6);

	// Main band: distance from a tilted great circle, broken up by noise.
	float off = dot(d, normalize(band_normal));
	vec3 warp = vec3(fbm3(d * 2.0 + t), fbm3(d * 2.0 + 7.3 - t), fbm3(d * 2.0 + 13.1));
	float band = exp(-pow((off + (warp.x - 0.5) * 0.35) / band_width, 2.0));
	float gas = fbm3(d * 3.2 + warp * 1.8 + t * 2.0);
	float fine = fbm3(d * 9.0 + warp * 2.5);
	float neb = smoothstep(0.3, 0.85, gas * 0.8 + fine * 0.35) * band;
	// Dark dust lanes along the band's spine.
	float dust = smoothstep(0.45, 0.75, fbm3(d * 5.5 + warp * 3.0 + 21.0)) * exp(-pow(off / (band_width * 0.35), 2.0));
	neb *= 1.0 - dust * 0.85;

	float hue = fbm3(d * 1.6 + 40.0 + warp);
	vec3 gas_col = mix(color_a, color_b, smoothstep(0.35, 0.7, hue));
	gas_col = mix(gas_col, color_c, smoothstep(0.55, 0.8, fbm3(d * 2.4 + 70.0)) * 0.7);
	vec3 col = base_color + gas_col * neb * 0.55;
	// Bright cores where the gas is densest.
	col += mix(gas_col, vec3(0.85, 0.9, 1.0), 0.45) * pow(neb, 3.0) * 1.4;

	// A second, smaller violet cloud.
	float c2 = exp(-pow(acos(clamp(dot(d, normalize(cloud2_dir)), -1.0, 1.0)) / 0.45, 2.0));
	float c2gas = smoothstep(0.35, 0.8, fbm3(d * 4.0 + warp * 2.0 + 90.0)) * c2;
	col += color_b * c2gas * 0.45 + vec3(0.9, 0.6, 1.0) * pow(c2gas, 3.0) * 0.8;

	// Stars: a sparse field everywhere, many more inside the band.
	float s = stars(d, 160.0, 0.985) + stars(d, 320.0, 0.993) * 0.7;
	s += stars(d, 420.0, 0.965) * band * 0.8;
	float twinkle = 0.75 + 0.25 * sin(TIME * 2.0 + h31(floor(d * 160.0)) * 50.0);
	col += vec3(0.85, 0.9, 1.0) * s * twinkle * (1.0 - dust * 0.8);

	ALBEDO = col * intensity;
}
