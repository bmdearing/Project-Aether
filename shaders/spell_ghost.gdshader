shader_type spatial;
// Spectral body (Wraith): see-through with a glowing rim, wisps streaming
// down its surface, and a tattered hem that frays away at the bottom
// (`tatter` > 0; UV.y 0 = hem, 1 = top on tubes).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.45, 0.86, 1.0);
uniform float opacity = 1.0;
uniform float tatter = 0.0;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p, float wrap) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float i0 = mod(i.x, wrap);
	float i1 = mod(i.x + 1.0, wrap);
	return mix(mix(h21(vec2(i0, i.y)), h21(vec2(i1, i.y)), f.x), mix(h21(vec2(i0, i.y + 1.0)), h21(vec2(i1, i.y + 1.0)), f.x), f.y);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, 2.2);
	float wisp = vnoise(vec2(UV.x * 8.0, UV.y * 3.0 + TIME * 0.9), 8.0);
	float a = (0.03 + rim * 0.6 + wisp * 0.12) * opacity;
	if (tatter > 0.0) {
		float fray = vnoise(vec2(UV.x * 10.0, TIME * 0.7), 10.0);
		a *= smoothstep(0.0, tatter, UV.y - (fray - 0.5) * tatter * 0.8);
	}
	ALBEDO = color * (0.5 + rim * 0.9 + wisp * 0.3);
	ALPHA = clamp(a, 0.0, 1.0);
}
