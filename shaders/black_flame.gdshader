shader_type spatial;
// Black flames on a lathed tube (Amaterasu's creeping wall) or a sheet: the
// same tongues as spell_flame, but mixed rather than added so the fire can
// be black, with a violet heat glow at its roots and edges.
// UV.x around / along, UV.y bottom 0 -> top 1.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 core : source_color = vec3(0.01, 0.0, 0.02);
uniform vec3 rim : source_color = vec3(0.5, 0.08, 0.62);
uniform float scroll = 1.3;
uniform float tiles = 24.0;
uniform float period = 24.0;
uniform float sway = 0.1;
uniform float fill = 0.3;
uniform float opacity = 1.0;

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
	VERTEX.x += sin(TIME * 2.3 + t * 4.0 + VERTEX.z) * sway * t;
	VERTEX.z += cos(TIME * 2.1 + t * 3.0 + VERTEX.x) * sway * t;
}

void fragment() {
	float y = UV.y;
	vec2 q = vec2(UV.x * tiles, y * 2.0 - TIME * scroll);
	float n = vnoise(q, period) * 0.55 + vnoise(q * 2.0 + vec2(0.0, -TIME * scroll), period * 2.0) * 0.3 + vnoise(q * 4.0, period * 4.0) * 0.15;
	float tall = vnoise(vec2(UV.x * tiles * 0.5 + 9.0, TIME * 0.5), period * 0.5);
	float shape = n * 1.25 - y * (1.3 - tall * 0.6) + fill;
	float body = smoothstep(0.0, 0.25, shape);
	float inner = smoothstep(0.12, 0.45, shape);
	// Dark heart, violet where the tongues thin out and at the roots.
	vec3 col = mix(rim, core, inner);
	col += rim * (1.0 - smoothstep(0.0, 0.18, y)) * 0.6;
	float base = smoothstep(0.0, 0.06, y) * (1.0 - smoothstep(0.75, 1.0, y));
	ALBEDO = col;
	ALPHA = clamp(body * base * opacity, 0.0, 1.0);
}
