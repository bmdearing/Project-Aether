shader_type canvas_item;
// Fate Board background: every placed Slate is its own nebula (a glowing
// cloud in its tag colour, brightest in its interior, wisping out toward its
// edges, shaped by its own seed) drifting on a dark star field.
//
// cell_data is a GRID_SIZE x GRID_SIZE RGBA8 texture FateBoardGrid.gd
// rebuilds when placements change: alpha 0 = empty cell, alpha >= 0.5 =
// occupied, with alpha 0.5-1.0 carrying that placement's seed (so two
// same-tag Slates side by side still read as two clouds); RGB = the Slate's
// Constants.DAMAGE_TYPE_COLOR.

uniform sampler2D cell_data : filter_nearest;
uniform float grid_size = 32.0;
uniform float scroll_speed = 0.06;
uniform vec4 field_color : source_color = vec4(0.02, 0.025, 0.05, 0.72);
uniform vec4 line_color : source_color = vec4(0.86, 0.71, 0.42, 0.13);

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
	for (int i = 0; i < 5; i++) {
		total += amp * value_noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		amp *= 0.5;
	}
	return total;
}

vec4 cell_at(vec2 cell_id) {
	return texture(cell_data, (cell_id + 0.5) / grid_size);
}

bool same_slate(vec4 a, vec4 b) {
	return b.a >= 0.5 && distance(a.rgb, b.rgb) < 0.01 && abs(a.a - b.a) < 0.003;
}

// Stars: sparse, twinkling, a few brighter ones.
float stars(vec2 board_pos, float density, float seed) {
	vec2 grid = board_pos * density;
	vec2 id = floor(grid);
	float h = hash21(id + seed);
	float present = step(0.94, h);
	vec2 jitter = vec2(hash21(id + 3.1), hash21(id + 7.7)) - 0.5;
	float d = length(fract(grid) - 0.5 - jitter * 0.5);
	float twinkle = 0.55 + 0.45 * sin(TIME * (1.5 + h * 3.0) + h * 60.0);
	return present * twinkle * (1.0 - smoothstep(0.0, 0.16 + 0.12 * step(0.985, h), d));
}

void fragment() {
	vec2 board_pos = UV * grid_size;
	vec2 cell_id = floor(board_pos);
	vec2 cell_uv = fract(board_pos);
	vec4 cell = cell_at(cell_id);

	if (cell.a < 0.5) {
		// Empty board: a dim star field with the grid lines on top.
		vec3 field = field_color.rgb + vec3(0.03, 0.035, 0.06) * fbm(board_pos * 0.35 + TIME * 0.01);
		field += vec3(0.75, 0.8, 1.0) * stars(board_pos, 3.0, 0.0) * 0.45;
		vec2 px = fwidth(board_pos);
		vec2 edge = min(cell_uv, 1.0 - cell_uv) / max(px, vec2(1e-4));
		float line = 1.0 - smoothstep(0.0, 1.0, min(edge.x, edge.y));
		vec3 col = mix(field, line_color.rgb, line * line_color.a * 2.5);
		COLOR = vec4(col, max(field_color.a, line * line_color.a));
	} else {
		float seed = (cell.a - 0.5) * 2.0;
		vec2 offset = vec2(seed * 173.0, seed * 91.0);

		// How deep inside its Slate this point is: same-slate coverage of
		// the surrounding 5x5 cells, weighted toward the nearest ones.
		float cover = 0.0;
		float total = 0.0;
		for (int dx = -2; dx <= 2; dx++) {
			for (int dy = -2; dy <= 2; dy++) {
				vec2 o = vec2(float(dx), float(dy));
				vec2 c = cell_id + o + 0.5;
				float w = 1.0 / (1.0 + dot(board_pos - c, board_pos - c));
				total += w;
				if (same_slate(cell, cell_at(cell_id + o))) {
					cover += w;
				}
			}
		}
		float depth = clamp(cover / total, 0.0, 1.0);

		// Swirling cloud: domain-warped noise unique to this Slate.
		vec2 p = board_pos * 0.9 + offset;
		vec2 drift = vec2(TIME * scroll_speed, -TIME * scroll_speed * 0.6);
		vec2 warp = vec2(fbm(p + drift), fbm(p + vec2(5.2, 1.3) - drift));
		float cloud = fbm(p * 1.4 + warp * 2.2 + drift * 0.5);
		float wisps = fbm(p * 3.1 - warp * 1.5);

		// Dense near the middle of the Slate, thinning to wisps at its rim.
		float body = smoothstep(0.25, 0.95, depth * 0.85 + cloud * 0.55);
		float density = clamp(body * (0.55 + 0.75 * cloud) + wisps * 0.25 * depth, 0.0, 1.4);

		// Two tones per nebula: the tag colour and a hue-shifted companion.
		vec3 base = cell.rgb;
		vec3 companion = mix(base.gbr, vec3(1.0) - base * 0.4, 0.35 + 0.3 * seed);
		vec3 tint = mix(base, companion, smoothstep(0.35, 0.8, wisps) * 0.45);
		vec3 core_glow = mix(tint, vec3(1.0, 0.97, 0.9), smoothstep(0.85, 1.25, density) * 0.6);

		vec3 dark = field_color.rgb * 1.4 + base * 0.06;
		vec3 col = mix(dark, core_glow, clamp(density, 0.0, 1.0));
		col += core_glow * pow(max(density - 0.8, 0.0), 2.0) * 0.8;

		// Stars seen through the nebula, brighter where it is thin.
		col += vec3(0.9, 0.92, 1.0) * stars(board_pos, 4.0, seed * 31.0) * (1.0 - 0.6 * density);

		// The Slate's outer rim: a faint lit edge so its shape stays readable.
		float edge_dist = 1.0;
		if (!same_slate(cell, cell_at(cell_id + vec2(-1.0, 0.0)))) edge_dist = min(edge_dist, cell_uv.x);
		if (!same_slate(cell, cell_at(cell_id + vec2(1.0, 0.0)))) edge_dist = min(edge_dist, 1.0 - cell_uv.x);
		if (!same_slate(cell, cell_at(cell_id + vec2(0.0, -1.0)))) edge_dist = min(edge_dist, cell_uv.y);
		if (!same_slate(cell, cell_at(cell_id + vec2(0.0, 1.0)))) edge_dist = min(edge_dist, 1.0 - cell_uv.y);
		col = mix(col, base * 1.2 + 0.1, (1.0 - smoothstep(0.0, 0.07, edge_dist)) * 0.55);
		col *= mix(0.7, 1.0, smoothstep(0.0, 0.2, edge_dist));

		COLOR = vec4(col, 1.0);
	}
}
