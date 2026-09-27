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

// True if the neighboring cell at `offset` (in cells) holds the same Slate
// color - i.e. this edge is interior to a Slate (or a same-tag neighbor,
// which FateBoardGrid._draw_walls() still separates with a wall line).
bool same_neighbor(vec2 cell_id, vec2 offset, vec3 rgb) {
	vec4 n = texture(cell_data, (cell_id + offset + 0.5) / grid_size);
	return n.a >= 0.5 && distance(n.rgb, rgb) < 0.01;
}

void fragment() {
	vec4 cell = texture(cell_data, UV);
	if (cell.a < 0.5) {
		discard;
	}

	// v4.10: noise and stars are sampled in board-space coordinates (not
	// per-cell local UV with a per-cell phase), so the nebula flows
	// continuously across a Slate's cells instead of showing a seam - the
	// "grid lines inside a Slate".
	vec2 board_pos = UV * grid_size;
	vec2 cell_id = floor(board_pos);
	vec2 cell_uv = fract(board_pos);
	vec2 flow_a = vec2(TIME * scroll_speed, -TIME * scroll_speed * 0.7);
	vec2 flow_b = vec2(-TIME * scroll_speed * 0.5, TIME * scroll_speed * 0.9);

	float n1 = fbm(board_pos * 3.2 + flow_a);
	float n2 = fbm(board_pos * 5.0 + flow_b);
	float nebula = clamp(mix(n1, n2, 0.5), 0.0, 1.0);

	vec3 base = cell.rgb;
	vec3 shade = base * (0.5 + 0.75 * nebula);

	// Soft vignette on the Slate's OUTER border only - edges shared with a
	// same-colored neighbor get none, so a Slate reads as one shape.
	float edge_dist = 1.0;
	if (!same_neighbor(cell_id, vec2(-1.0, 0.0), base)) edge_dist = min(edge_dist, cell_uv.x);
	if (!same_neighbor(cell_id, vec2(1.0, 0.0), base)) edge_dist = min(edge_dist, 1.0 - cell_uv.x);
	if (!same_neighbor(cell_id, vec2(0.0, -1.0), base)) edge_dist = min(edge_dist, cell_uv.y);
	if (!same_neighbor(cell_id, vec2(0.0, 1.0), base)) edge_dist = min(edge_dist, 1.0 - cell_uv.y);
	shade *= mix(0.55, 1.0, smoothstep(0.0, 0.18, edge_dist));

	// Sparse twinkling stars, per user reference image's starfield.
	vec2 star_grid = board_pos * 8.0;
	vec2 star_cell = floor(star_grid);
	float star_seed = hash21(star_cell);
	float star_present = step(0.93, star_seed);
	float twinkle = 0.5 + 0.5 * sin(TIME * 2.5 + star_seed * 60.0);
	vec2 star_local = fract(star_grid) - 0.5;
	float star_shape = 1.0 - smoothstep(0.0, 0.28, length(star_local));
	float star = star_present * twinkle * star_shape;

	vec3 color = shade + vec3(star * 0.9);
	COLOR = vec4(color, 1.0);
}
