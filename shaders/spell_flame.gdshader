shader_type spatial;
// Flames on a lathed tube (Inferno) or a sheet (Flame Wall): UV.x around /
// along, UV.y bottom 0 -> top 1. Noise tongues scroll upward and taper with
// height; dense parts burn hot (white-yellow), edges cool to deep red.
// `burn` 1 = full blaze, 0 = guttered out.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 hot : source_color = vec3(1.0, 0.78, 0.38);
uniform vec3 mid : source_color = vec3(1.0, 0.42, 0.08);
uniform vec3 cool : source_color = vec3(0.45, 0.06, 0.02);
uniform float burn = 1.0;
uniform float intensity = 1.0;
uniform float scroll = 1.7;
uniform float tiles = 3.0;     // noise cells around / along UV.x
uniform float period = 0.0;    // > 0: noise wraps every `period` cells (closed tube)
uniform float sway = 0.12;
uniform float edge_soft = 0.35; // fades where a tube grazes the view, so it reads as volume
uniform float end_fade = 0.0;  // > 0: fade the ends of a stretched tube (|local x| from end_fade to 1)
uniform float fill = 0.32;     // how much of the surface burns; lower = separate tongues

varying float local_x;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p, float wrap) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float i0 = wrap > 0.0 ? mod(i.x, wrap) : i.x;
	float i1 = wrap > 0.0 ? mod(i.x + 1.0, wrap) : i.x + 1.0;
	return mix(mix(h21(vec2(i0, i.y)), h21(vec2(i1, i.y)), f.x), mix(h21(vec2(i0, i.y + 1.0)), h21(vec2(i1, i.y + 1.0)), f.x), f.y);
}

void vertex() {
	float t = UV.y;
	local_x = VERTEX.x;
	VERTEX.x += sin(TIME * 3.1 + t * 4.0 + VERTEX.z) * sway * t;
	VERTEX.z += cos(TIME * 2.7 + t * 3.0 + VERTEX.x) * sway * t;
}

void fragment() {
	float y = UV.y;
	vec2 q = vec2(UV.x * tiles, y * 2.2 - TIME * scroll);
	float n = vnoise(q, period) * 0.55 + vnoise(q * 2.0 + vec2(0.0, -TIME * scroll), period * 2.0) * 0.3 + vnoise(q * 4.0, period * 4.0) * 0.15;
	float tall = vnoise(vec2(UV.x * tiles * 0.5 + 17.0, TIME * 0.6), period * 0.5);
	float shape = n * 1.25 - y * (1.35 - tall * 0.6) + fill + (burn - 1.0) * 0.9;
	float body = smoothstep(0.0, 0.3, shape);
	float heat = clamp(shape * 1.6, 0.0, 1.0);
	vec3 col = heat > 0.5 ? mix(mid, hot, (heat - 0.5) * 2.0) : mix(cool, mid, heat * 2.0);
	float base = smoothstep(0.0, 0.08, y) * (1.0 - smoothstep(0.7, 1.0, y));
	if (end_fade > 0.0) {
		base *= 1.0 - smoothstep(end_fade, 1.0, abs(local_x));
	}
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = col * intensity * (0.6 + heat * 0.6);
	ALPHA = clamp(body * base * smoothstep(0.0, edge_soft, facing) * 0.85, 0.0, 1.0);
}
