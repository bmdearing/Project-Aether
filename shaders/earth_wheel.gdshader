shader_type spatial;
// Aurelia's Earth Wheel on a flat disc (PlaneMesh 2*radius wide, centred on
// the arena). Everything outside the safe wedges and outside the hub is
// about to quake: it glows hotter as `charge` runs 0 -> 1, with a timer ring
// sweeping out from the hub. `strike` 1 flashes the quake itself. Wedge
// angles are measured like atan2(x, z) in the arena's local space.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float radius = 22.0;
uniform float hub_radius = 3.0;
uniform vec4 wedges = vec4(0.0);
uniform int wedge_count = 2;
uniform float wedge_half = 0.2;
uniform float charge = 0.0;
uniform float strike = 0.0;
uniform float alpha = 1.0;
uniform vec3 danger : source_color = vec3(0.95, 0.42, 0.12);
uniform vec3 hot : source_color = vec3(1.0, 0.86, 0.55);
uniform vec3 safe : source_color = vec3(0.55, 0.95, 1.0);

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float cracks(vec2 uv) {
	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 n = vec2(float(x), float(y));
			vec2 pt = n + vec2(h21(cell + n), h21(cell + n + 17.0)) - f;
			float d = dot(pt, pt);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return 1.0 - smoothstep(0.0, 0.08, sqrt(d2) - sqrt(d1));
}

float wedge_dist(float a) {
	float best = 10.0;
	for (int i = 0; i < 4; i++) {
		if (i >= wedge_count) break;
		float d = abs(mod(a - wedges[i] + PI, TAU) - PI);
		best = min(best, d);
	}
	return best;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * radius;
	float dist = length(p);
	if (dist > radius) discard;
	float a = atan(p.x, p.y);
	float wd = wedge_dist(a);
	// Angular distance -> metres along the arc, so wedge edges stay crisp.
	float edge_m = (wd - wedge_half) * max(dist, 0.5);
	bool in_wedge = wd < wedge_half && dist > hub_radius;
	vec3 col;
	float a_out;
	if (in_wedge) {
		float rim = 1.0 - smoothstep(0.0, 0.35, -edge_m);
		float pulse = 0.5 + 0.5 * sin(TIME * 6.0);
		col = safe;
		a_out = 0.08 + rim * (0.55 + 0.25 * pulse);
	} else {
		float k = cracks(p * 0.35);
		float sweep = 1.0 - smoothstep(0.0, 1.2, abs(dist - mix(hub_radius, radius, charge)));
		float heat = charge * charge;
		col = mix(danger, hot, k * heat + sweep * 0.6);
		a_out = 0.12 + 0.33 * heat + k * 0.4 * heat + sweep * 0.35;
		// The wedge's outline from the danger side.
		float rim = 1.0 - smoothstep(0.0, 0.25, edge_m);
		if (dist > hub_radius) {
			col = mix(col, safe, rim * 0.8);
			a_out = max(a_out, rim * 0.8);
		}
		col = mix(col, vec3(1.0, 0.95, 0.85), strike);
		a_out = mix(a_out, 0.9, strike);
	}
	a_out *= 1.0 - smoothstep(radius - 0.6, radius, dist);
	ALBEDO = col;
	ALPHA = clamp(a_out * alpha, 0.0, 1.0);
}
