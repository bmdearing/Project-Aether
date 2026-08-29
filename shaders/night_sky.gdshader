shader_type spatial;
render_mode unshaded, depth_draw_never, fog_disabled;
// Applied to a skydome sphere (flip_faces=true) surrounding the scene -
// a vertical gradient + procedural hashed stars + a moon + drifting
// cloud cover, no textures. flash_intensity is pulsed from script on
// thunder. Clouds occlude stars/moon underneath them, same as real cloud
// cover would.

uniform vec3 sky_top_color : source_color = vec3(0.01, 0.01, 0.03);
uniform vec3 sky_horizon_color : source_color = vec3(0.05, 0.07, 0.12);
uniform vec3 star_color : source_color = vec3(1.0, 1.0, 0.95);
uniform float star_density : hint_range(50.0, 400.0) = 180.0;
uniform float star_twinkle_speed : hint_range(0.0, 5.0) = 1.5;

// MainMenuBackground.gd places the camera at a near-flat forward look
// (a slight downward tilt) - this direction sits comfortably inside
// that view, up and slightly right of center, above the mountain line.
uniform vec3 moon_direction = vec3(0.2, 0.2, -0.95);
uniform vec3 moon_color : source_color = vec3(0.9, 0.91, 0.96);
uniform float moon_size : hint_range(0.001, 0.05) = 0.014;

uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_speed : hint_range(0.0, 0.2) = 0.015;
uniform float cloud_scale : hint_range(1.0, 20.0) = 4.0;
uniform vec3 cloud_color : source_color = vec3(0.12, 0.13, 0.17);
uniform vec3 cloud_lit_color : source_color = vec3(0.28, 0.29, 0.34);

uniform float flash_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color : source_color = vec3(0.85, 0.88, 1.0);

varying vec3 world_dir;

void vertex() {
	world_dir = normalize(VERTEX);
}

// Cheap hashes, no texture lookups needed.
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float cloud_fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amp;
		p *= 2.0;
		amp *= 0.5;
	}
	return total;
}

void fragment() {
	vec3 dir = normalize(world_dir);
	// Above the horizon: fade up from sky_horizon_color to sky_top_color.
	// Below it (looking down past the mountains, where this scene has no
	// ground geometry at all): fade quickly to black instead of reusing
	// the lighter horizon tone, or the "empty" area under the mountains
	// reads as a lit-up band rather than darkness.
	vec3 sky_color;
	if (dir.y >= 0.0) {
		sky_color = mix(sky_horizon_color, sky_top_color, pow(dir.y, 0.5));
	} else {
		sky_color = mix(sky_horizon_color, vec3(0.0), pow(-dir.y, 0.35));
	}

	// Gnomonic-ish projection of the view direction onto a grid - stretches
	// a little near the horizon, acceptable for a stylized sky.
	vec2 sky_uv = dir.xz / (abs(dir.y) + 0.15);

	vec2 star_uv = sky_uv * star_density;
	vec2 star_cell = floor(star_uv);
	float star = hash21(star_cell);
	float twinkle = 0.5 + 0.5 * sin(TIME * star_twinkle_speed + star * 20.0);
	float star_mask = step(0.995, star) * twinkle * clamp(dir.y, 0.0, 1.0);

	// Moon: a hard disc plus a soft glow falloff around a fixed direction.
	float moon_dot = dot(dir, normalize(moon_direction));
	float moon_disc = smoothstep(1.0 - moon_size, 1.0 - moon_size * 0.4, moon_dot);
	float moon_glow = smoothstep(1.0 - moon_size * 12.0, 1.0, moon_dot) * 0.25;
	float moon_mask = moon_disc + moon_glow;

	// Clouds drift slowly across the sky_uv plane; coverage thresholds the
	// fbm so higher values mean thicker, denser cloud, not just more cells.
	vec2 cloud_uv = sky_uv * cloud_scale * 0.02 + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
	float cloud_n = cloud_fbm(cloud_uv);
	float cloud_density = smoothstep(1.0 - cloud_coverage, 1.0, cloud_n) * clamp(dir.y * 3.0, 0.0, 1.0);
	// Clouds nearer the moon catch a little of its light on their edges.
	vec3 lit_cloud = mix(cloud_color, cloud_lit_color, moon_disc + moon_glow * 2.0);

	sky_color += star_color * star_mask * (1.0 - cloud_density);
	sky_color += moon_color * moon_mask * (1.0 - cloud_density * 0.9);
	sky_color = mix(sky_color, lit_cloud, cloud_density);

	sky_color = mix(sky_color, flash_color, flash_intensity * clamp(dir.y * 0.5 + 0.6, 0.0, 1.0));

	ALBEDO = sky_color;
}
