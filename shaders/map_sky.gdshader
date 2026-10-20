shader_type sky;
// Map and arena sky (SkyBuilder): a horizon gradient, a sun (or moon) disk
// with a glow, a drifting cloud layer, and optional stars, aurora and a
// swirling vortex overhead. The sun follows the scene's first directional
// light when it lights the sky, else sun_direction.

uniform vec3 zenith_color : source_color = vec3(0.18, 0.36, 0.72);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.74, 0.86);
uniform vec3 ground_color : source_color = vec3(0.2, 0.2, 0.22);
uniform float horizon_curve = 0.35;
uniform float brightness = 1.0;

// false: the sun sits at sun_direction even when a directional light lights the sky.
uniform bool follow_light = true;
uniform vec3 sun_direction = vec3(0.3, 0.6, -0.7);
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.75);
uniform float sun_size = 0.025;
uniform float sun_energy = 6.0;
uniform float sun_glow = 0.35;
uniform float sun_glow_tightness = 6.0;

uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.55, 0.6, 0.7);
uniform float cloud_cover = 0.45;
uniform float cloud_softness = 0.25;
uniform float cloud_scale = 1.2;
uniform float cloud_speed = 0.01;
uniform float cloud_opacity = 0.9;

uniform float star_amount = 0.0;
uniform vec3 aurora_color : source_color = vec3(0.3, 1.0, 0.7);
uniform float aurora_amount = 0.0;
uniform vec3 vortex_color : source_color = vec3(1.0, 0.25, 0.1);
uniform float vortex_amount = 0.0;

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
	for (int i = 0; i < 5; i++) {
		total += amp * noise(p);
		p = p * 2.07 + vec2(3.1, 1.7);
		amp *= 0.5;
	}
	return total;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	bool use_light = follow_light && LIGHT0_ENABLED;
	vec3 sun = use_light ? normalize(LIGHT0_DIRECTION) : normalize(sun_direction);
	vec3 sun_tint = use_light ? mix(sun_color, LIGHT0_COLOR, 0.35) : sun_color;

	// Gradient: ground below, horizon band, zenith above.
	float up = dir.y;
	vec3 col;
	if (up >= 0.0) {
		col = mix(horizon_color, zenith_color, pow(clamp(up, 0.0, 1.0), horizon_curve));
	} else {
		col = mix(horizon_color, ground_color, clamp(-up * 6.0, 0.0, 1.0));
	}

	float sun_dot = max(dot(dir, sun), 0.0);
	// Glow around the sun, warming the horizon on its side.
	col += sun_tint * sun_glow * pow(sun_dot, sun_glow_tightness);
	col += sun_tint * sun_glow * 0.35 * pow(sun_dot, 2.0) * (1.0 - clamp(up * 3.0, 0.0, 1.0));

	// Stars, fading out toward the horizon.
	if (star_amount > 0.0 && up > 0.0) {
		vec2 sp = vec2(atan(dir.x, dir.z) * 90.0, asin(clamp(up, -1.0, 1.0)) * 90.0);
		vec2 cell = floor(sp);
		float h = lattice_hash(cell + vec2(17.0, 3.0));
		vec2 off = vec2(lattice_hash(cell + vec2(5.0, 9.0)), lattice_hash(cell + vec2(11.0, 2.0))) - 0.5;
		float d = length(fract(sp) - 0.5 - off * 0.6);
		float twinkle = 0.6 + 0.4 * sin(TIME * (1.0 + h * 3.0) + h * 40.0);
		float star = step(0.965, h) * (1.0 - smoothstep(0.0, 0.12 + 0.1 * step(0.993, h), d)) * twinkle;
		col += vec3(0.85, 0.9, 1.0) * star * star_amount * smoothstep(0.0, 0.25, up);
	}

	// Aurora: soft curtains in a band across the upper sky.
	if (aurora_amount > 0.0 && up > 0.0) {
		vec2 ap = dir.xz / (up + 0.25);
		float wave = fbm(vec2(ap.x * 0.8 + TIME * 0.02, ap.y * 0.25));
		float band = (ap.y * 0.35 + wave - 0.75) * 7.0;
		float curtain = exp(-band * band);
		float streaks = pow(noise(vec2(ap.x * 14.0 + TIME * 0.15, 0.5)), 2.0) * 1.6;
		col += aurora_color * curtain * streaks * aurora_amount * smoothstep(0.1, 0.45, up);
	}

	// Vortex: a slow swirl of glowing cloud round the zenith.
	if (vortex_amount > 0.0 && up > 0.0) {
		vec2 vp = dir.xz / (up + 0.05);
		float r = length(vp);
		float a = atan(vp.y, vp.x);
		float swirl = a + r * 1.6 - TIME * 0.08;
		vec2 swirl_uv = vec2(cos(swirl), sin(swirl)) * r;
		float arms = fbm(swirl_uv * 1.3 + vec2(TIME * 0.01));
		float eye = smoothstep(0.35, 0.0, r);
		float ring = smoothstep(0.2, 0.7, arms) * smoothstep(3.5, 0.6, r);
		col = mix(col, vortex_color, ring * vortex_amount * 0.6);
		col = mix(col, vec3(0.0), eye * vortex_amount);
		col += vortex_color * 1.8 * smoothstep(0.08, 0.0, abs(r - 0.42)) * vortex_amount;
	}

	// Sun or moon disk, behind the clouds.
	float disk = smoothstep(cos(sun_size), cos(sun_size * 0.85), dot(dir, sun));
	col = mix(col, sun_tint * sun_energy, disk);

	// Clouds: noise on a plane above the camera, thinning at the horizon.
	if (cloud_cover > 0.0 && up > 0.0) {
		vec2 cp = dir.xz / (up + 0.12) * cloud_scale;
		vec2 drift = vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
		float shape = fbm(cp + drift);
		float detail = fbm(cp * 2.6 - drift * 1.7);
		float threshold = 0.72 - cloud_cover * 0.45;
		float density = smoothstep(threshold, threshold + cloud_softness, shape * 0.7 + detail * 0.3);
		// Lit from the sun side, darker in thick middles.
		float lit = 0.55 + 0.45 * pow(sun_dot, 4.0);
		vec3 cloud = mix(cloud_shade, cloud_color, clamp(lit - density * 0.35 + 0.2, 0.0, 1.0));
		cloud += sun_tint * pow(sun_dot, 10.0) * 0.8 * (1.0 - density);
		float fade = smoothstep(0.0, 0.18, up);
		col = mix(col, cloud, density * cloud_opacity * fade);
	}

	COLOR = col * brightness;
}
