shader_type canvas_item;
// Animated, color-shifting Slate background (user reference image,
// 2026-08-30: "slates have a background texture that moves and the color
// changes based on the type of Slate"). Deliberately breaks from this
// project's usual no-shader placeholder-art convention (see StatOrb.gd's
// header) since per-pixel motion is the actual content being asked for,
// not just a static color - a CPU _draw() loop redrawing hand-rolled
// noise across every occupied cell every frame would be both slower and
// far more code than a GPU fragment shader doing the same thing.
//
// cell_data is a GRID_SIZE x GRID_SIZE RGBA8 texture FateBoardGrid.gd
// rebuilds only when placements actually change (not every frame/hover
// move) - alpha 0 = empty cell (discarded, grid lines show through from
// the Control drawn on top), alpha 1 = occupied, RGB = that Slate's
// Constants.DAMAGE_TYPE_COLOR. No external noise texture exists in this
// project, so noise/fbm below are hand-rolled hash-based value noise -
// standard technique, not doc-sourced (this whole visual is user-
// directed, not doc content).

uniform sampler2D cell_data : filter_nearest;
uniform float grid_size = 32.0;
uniform float scroll_speed = 0.12;

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

float fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		total += amp * value_noise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return total;
}

void fragment() {
	vec4 cell = texture(cell_data, UV);
	if (cell.a < 0.5) {
		discard;
	}

	vec2 cell_id = floor(UV * grid_size);
	vec2 cell_uv = fract(UV * grid_size);
	// Per-cell phase offset so a run of same-tag Slates doesn't scroll as
	// one flat blob - each cell's nebula drifts on its own cycle.
	float phase = hash21(cell_id) * 20.0;
	vec2 flow_a = vec2(TIME * scroll_speed + phase, -TIME * scroll_speed * 0.7 + phase);
	vec2 flow_b = vec2(-TIME * scroll_speed * 0.5 - phase, TIME * scroll_speed * 0.9 - phase);

	float n1 = fbm(cell_uv * 3.2 + flow_a);
	float n2 = fbm(cell_uv * 5.0 + flow_b);
	float nebula = clamp(mix(n1, n2, 0.5), 0.0, 1.0);

	vec3 base = cell.rgb;
	vec3 shade = base * (0.5 + 0.75 * nebula);

	// Soft per-cell vignette so individual tiles read distinctly even
	// when several of the same tag sit edge to edge.
	float edge_dist = min(min(cell_uv.x, 1.0 - cell_uv.x), min(cell_uv.y, 1.0 - cell_uv.y));
	shade *= mix(0.55, 1.0, smoothstep(0.0, 0.18, edge_dist));

	// Sparse twinkling stars, per user reference image's starfield.
	vec2 star_grid = cell_uv * 8.0 + cell_id * 3.7;
	vec2 star_cell = floor(star_grid);
	float star_seed = hash21(star_cell + cell_id);
	float star_present = step(0.93, star_seed);
	float twinkle = 0.5 + 0.5 * sin(TIME * 2.5 + star_seed * 60.0);
	vec2 star_local = fract(star_grid) - 0.5;
	float star_shape = 1.0 - smoothstep(0.0, 0.28, length(star_local));
	float star = star_present * twinkle * star_shape;

	vec3 color = shade + vec3(star * 0.9);
	COLOR = vec4(color, 1.0);
}
