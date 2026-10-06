shader_type spatial;
render_mode unshaded, fog_disabled, cull_front;
// Title-screen storm sky on an inside-out sphere: deep night gradient,
// stars in the gaps, a haloed moon with surface detail and soft beams, and
// layered domain-warped storm clouds with silver moonlit edges. flash /
// flash_dir light the clouds from inside where lightning strikes.

uniform vec3 zenith : source_color = vec3(0.004, 0.006, 0.016);
uniform vec3 horizon : source_color = vec3(0.035, 0.045, 0.075);
uniform vec3 moon_dir = vec3(0.32, 0.2, -0.93);
uniform vec3 moon_color : source_color = vec3(0.92, 0.94, 1.0);
uniform float moon_radius = 0.035;
uniform float cloud_speed = 0.006;
uniform float flash = 0.0;
uniform vec3 flash_dir = vec3(0.2, 0.15, -0.97);

varying vec3 dir;

void vertex() {
	dir = normalize(VERTEX);
}

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 6; i++) {
		v += vnoise(p) * a;
		p = rot * p * 2.02 + 3.1;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec3 d = normalize(dir);
	float up = clamp(d.y, -0.2, 1.0);
	vec3 col = mix(horizon, zenith, pow(smoothstep(-0.05, 0.7, up), 0.7));

	// Stars, only high up and where clouds are thin.
	vec2 sp = d.xz / max(d.y + 0.25, 0.05) * 90.0;
	vec2 cell = floor(sp);
	vec2 jitter = vec2(h21(cell + 3.1), h21(cell + 8.4)) * 0.6 + 0.2;
	float star = step(0.993, h21(cell)) * (1.0 - smoothstep(0.02, 0.09, length(fract(sp) - jitter)));
	star *= 0.6 + 0.4 * sin(TIME * (1.0 + h21(cell + 7.0) * 3.0) + h21(cell) * 40.0);
	star *= smoothstep(0.08, 0.35, up);

	// Moon disc with maria, halo and soft beams.
	vec3 md = normalize(moon_dir);
	float cosang = dot(d, md);
	float ang = acos(clamp(cosang, -1.0, 1.0));
	vec3 tangent = normalize(cross(md, vec3(0, 1, 0)));
	vec3 bitan = cross(tangent, md);
	vec2 mp = vec2(dot(d, tangent), dot(d, bitan)) / moon_radius;
	float disc = 1.0 - smoothstep(0.96, 1.0, length(mp));
	float maria = fbm(mp * 2.2 + 4.0);
	vec3 moon = moon_color * (0.78 + 0.35 * smoothstep(0.35, 0.65, maria)) * (1.0 - 0.25 * smoothstep(0.4, 1.0, length(mp)));
	float halo = exp(-ang * 9.0) * 0.55 + exp(-ang * 30.0) * 0.6;
	float beam_angle = atan(mp.y, mp.x);
	float beams = pow(abs(sin(beam_angle * 7.0 + TIME * 0.03)), 24.0) * exp(-ang * 7.0) * 0.045;

	// Storm clouds: two warped layers drifting at different speeds.
	vec2 cp = d.xz / max(d.y + 0.18, 0.04);
	vec2 drift = vec2(TIME * cloud_speed, TIME * cloud_speed * 0.35);
	vec2 warp = vec2(fbm(cp * 0.35 + drift), fbm(cp * 0.35 - drift + 5.2));
	float c1 = fbm(cp * 0.45 + warp * 1.6 + drift * 2.0);
	float c2 = fbm(cp * 1.1 + warp * 0.8 + drift * 3.5 + 9.0);
	float density = smoothstep(0.42, 0.78, c1 * 0.75 + c2 * 0.35);
	density *= smoothstep(-0.12, 0.08, up);
	float density_near_moon = smoothstep(0.38, 0.7, c1 * 0.75 + c2 * 0.35);

	// Thin cloud edges close to the moon catch silver light.
	float moon_glow = exp(-ang * 2.2);
	float edge = density * (1.0 - smoothstep(0.35, 0.9, density));
	vec3 cloud_dark = vec3(0.045, 0.05, 0.07);
	vec3 cloud_lit = vec3(0.55, 0.6, 0.72);
	vec3 cloud = mix(cloud_dark, cloud_lit, clamp(edge * 2.2 * moon_glow + moon_glow * 0.15, 0.0, 1.0));
	cloud += vec3(0.02, 0.025, 0.04) * c2;

	// Lightning lights the clouds from inside around the strike.
	float fa = acos(clamp(dot(d, normalize(flash_dir)), -1.0, 1.0));
	vec3 lightning = vec3(0.75, 0.8, 1.0) * flash * (exp(-fa * 2.5) * 1.6 + 0.25);

	vec3 sky = col + vec3(star) * (1.0 - density) * 0.9;
	sky += moon_color * (halo + beams) * (1.0 - density_near_moon * 0.6) * 0.5;
	sky = mix(sky, moon, disc * (1.0 - density_near_moon * 0.85));
	sky = mix(sky, cloud, density);
	sky += lightning * (0.35 + density * 1.2);
	ALBEDO = sky;
}
