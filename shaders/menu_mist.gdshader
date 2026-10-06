shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// A soft drifting bank of mist on a quad, brightened by lightning.

uniform vec3 color : source_color = vec3(0.32, 0.36, 0.48);
uniform float opacity = 0.28;
uniform float speed = 0.01;
uniform float flash = 0.0;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * vec2(6.0, 1.5) + vec2(TIME * speed * 10.0, 0.0);
	float n = vnoise(p) * 0.55 + vnoise(p * 2.3 + 4.0) * 0.3 + vnoise(p * 5.1 - TIME * 0.05) * 0.15;
	float band = smoothstep(0.0, 0.45, UV.y) * smoothstep(1.0, 0.55, UV.y);
	float edge = smoothstep(0.0, 0.15, UV.x) * smoothstep(1.0, 0.85, UV.x);
	ALBEDO = color + vec3(0.5, 0.55, 0.7) * flash;
	ALPHA = clamp(smoothstep(0.35, 0.8, n) * band * edge * opacity * (1.0 + flash * 1.5), 0.0, 1.0);
}
