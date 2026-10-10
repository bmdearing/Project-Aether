shader_type spatial;
// Ground under Black Hole (a plane, UV 0..1 across the pull radius): spiral
// arms of shadow winding into the centre, a darkened pit beneath the core
// and a faint rim marking how far the pull reaches.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.35, 0.15, 0.45);
uniform float arms = 4.0;
uniform float spin = 1.2;
uniform float fade = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float spiral = sin(a * arms + log(r + 0.02) * 6.0 + TIME * spin * 3.0);
	float arm = smoothstep(0.1, 0.9, spiral * 0.5 + 0.5);
	float inside = 1.0 - smoothstep(0.88, 1.0, r);
	float pit = 1.0 - smoothstep(0.0, 0.45, r);
	float rim = exp(-pow((r - 0.95) * 22.0, 2.0));
	vec3 col = mix(vec3(0.0), tint * 1.3, arm * 0.7);
	col += tint * rim * 1.4;
	ALBEDO = col;
	ALPHA = clamp((arm * 0.5 * smoothstep(0.0, 0.6, r) + pit * 0.7) * inside + rim * 0.6, 0.0, 1.0) * fade;
}
