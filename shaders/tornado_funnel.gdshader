shader_type spatial;
// Tornado funnel shell (a lathed tube, UV.x around, UV.y bottom 0 -> top 1).
// Streaks of wind spiral upward; the funnel sways like a serpent, the sway
// growing with height so the base stays planted.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(0.78, 0.76, 0.72);
uniform vec3 dark : source_color = vec3(0.32, 0.3, 0.28);
uniform float opacity = 0.6;
uniform float twist = 2.2;      // turns of the spiral bottom to top
uniform float spin = 0.9;       // streak scroll speed around the funnel
uniform float rise = 0.6;       // streak scroll speed upward
uniform float sway = 0.45;
uniform float fade = 1.0;       // 0..1, for spawning in and dying out

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Tileable around the funnel: x wraps every `period`.
float vnoise(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float i0 = mod(i.x, period);
	float i1 = mod(i.x + 1.0, period);
	return mix(mix(h21(vec2(i0, i.y)), h21(vec2(i1, i.y)), f.x), mix(h21(vec2(i0, i.y + 1.0)), h21(vec2(i1, i.y + 1.0)), f.x), f.y);
}

void vertex() {
	float t = UV.y;
	VERTEX.x += sin(TIME * 1.4 + t * 3.2) * sway * t * t;
	VERTEX.z += cos(TIME * 1.1 + t * 2.6) * sway * 0.7 * t * t;
}

void fragment() {
	float t = UV.y;
	float u = UV.x + t * twist - TIME * spin;
	float v = t * 3.0 - TIME * rise;
	float streak = vnoise(vec2(u * 8.0, v * 2.0), 8.0) * 0.6 + vnoise(vec2(u * 16.0, v * 5.0), 16.0) * 0.4;
	streak = smoothstep(0.35, 0.85, streak);
	float bands = 0.5 + 0.5 * sin((u * 6.0 + v * 0.5 + vnoise(vec2(u * 4.0, v), 4.0) * 1.5) * TAU);
	float ends = smoothstep(0.0, 0.18, t) * smoothstep(1.0, 0.7, t);
	// View-facing edges of the shell read denser, like a real funnel wall.
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = (streak * 0.7 + bands * 0.12 + 0.25) * ends * (0.55 + rim * 0.8) * opacity * fade;
	ALBEDO = mix(dark, color, streak * 0.8 + t * 0.2);
	ALPHA = clamp(a, 0.0, 1.0);
}
