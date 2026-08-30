shader_type canvas_item;
// User direction (2026-08-30): "Make the gradient for experience mostly
// yellow/gold/orange. It should look dynamic and move with visible stars
// in the bar when its filled." Replaces the old static 6-stop rainbow
// GradientTexture1D. PlayerHUD's fill_clip Control (unchanged) already
// reveals only the filled portion of whatever this draws via
// clip_contents, so the stars/motion drawn here automatically only show
// up within the filled part - no extra masking needed on top of that.
// Breaks from the project's usual no-shader placeholder-art convention
// for the same reason slate_nebula.gdshader does: motion is the actual
// content being asked for.

uniform float time_scale = 0.25;

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

void fragment() {
	vec3 gold = vec3(1.0, 0.82, 0.25);
	vec3 amber = vec3(1.0, 0.65, 0.1);
	vec3 deep_orange = vec3(0.95, 0.42, 0.05);
	float drift = sin(TIME * time_scale + UV.x * 3.0) * 0.5 + 0.5;
	vec3 base = mix(mix(gold, amber, UV.x), deep_orange, drift * 0.5);

	// A soft highlight band sweeping across for the "dynamic and move" motion.
	float sweep = fract(UV.x - TIME * time_scale * 1.5);
	float highlight = smoothstep(0.15, 0.0, abs(sweep - 0.5)) * 0.35;
	vec3 color = base + vec3(highlight);

	// Slow-drifting cloud texture so the fill isn't a flat blend.
	float n = value_noise(UV * vec2(24.0, 4.0) + vec2(TIME * time_scale * 2.0, 0.0));
	color *= 0.85 + 0.3 * n;

	// Twinkling stars.
	vec2 star_grid = UV * vec2(48.0, 6.0);
	vec2 star_cell = floor(star_grid);
	float star_seed = hash21(star_cell);
	float star_present = step(0.9, star_seed);
	float twinkle = 0.5 + 0.5 * sin(TIME * 3.0 + star_seed * 80.0);
	vec2 star_local = fract(star_grid) - 0.5;
	float star_shape = 1.0 - smoothstep(0.0, 0.35, length(star_local));
	color += vec3(star_present * twinkle * star_shape);

	COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}
