shader_type spatial;
// Rotating rune circle on a flat quad: rings, ticks and a band of blocky
// glyphs, the outer and inner bands turning opposite ways.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/nexus_common.gdshaderinc"

uniform vec4 color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform float energy = 2.0;
uniform float speed = 0.05;

float ring(float r, float at, float w) {
	return 1.0 - smoothstep(w * 0.5, w, abs(r - at));
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	if (r > 1.0) discard;
	float a = atan(c.y, c.x) / TAU + 0.5;
	float v = 0.0;
	v += ring(r, 0.97, 0.02) + ring(r, 0.9, 0.012) + ring(r, 0.62, 0.012) + ring(r, 0.56, 0.02) + ring(r, 0.25, 0.015);
	// Outer glyph band.
	float ao = fract(a + TIME * speed);
	if (r > 0.65 && r < 0.87) {
		float seg = floor(ao * 36.0);
		float fy = (r - 0.65) / 0.22;
		vec2 cell = vec2(floor(fract(ao * 36.0) * 3.0), floor(fy * 4.0));
		float on = step(0.45, nx_hash(vec2(seg, 0.0) + cell * 7.3));
		vec2 local = vec2(fract(fract(ao * 36.0) * 3.0), fract(fy * 4.0));
		float block = step(0.15, local.x) * step(local.x, 0.85) * step(0.15, local.y) * step(local.y, 0.85);
		v += on * block * 0.8 * step(0.12, fract(ao * 36.0)) * step(fract(ao * 36.0), 0.88);
	}
	// Ticks between the inner rings.
	float ai = fract(a - TIME * speed * 1.7);
	if (r > 0.3 && r < 0.53) {
		float tick = 1.0 - smoothstep(0.08, 0.14, abs(fract(ai * 48.0) - 0.5) * 2.0 * (r * 3.0));
		v += tick * 0.5 * step(0.5, nx_hash(vec2(floor(ai * 48.0), 2.0)));
	}
	// Star in the middle.
	float star = abs(cos(atan(c.y, c.x) * 3.0 + TIME * speed * 6.0));
	v += (1.0 - smoothstep(0.0, 0.03, abs(r - 0.18 * (0.6 + 0.4 * star)))) * step(r, 0.25);
	float pulse = 0.8 + 0.2 * sin(TIME * 2.0);
	ALBEDO = color.rgb * v * energy * pulse * (1.0 - smoothstep(0.9, 1.0, r) * 0.3);
}
