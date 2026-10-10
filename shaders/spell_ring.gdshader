shader_type spatial;
// Expanding ground shockwave (a plane, UV 0..1 across). A soft bright front
// at `progress` (fraction of the plane's half-size) with a wobbling edge and
// streaked texture, trailing a faint wake back to the centre.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform float progress = 0.0;
uniform float width = 0.05;
uniform float alpha = 1.0;
uniform float wake = 0.35;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float wobble = (sin(a * 7.0 + TIME * 3.0) * 0.6 + sin(a * 13.0 - TIME * 5.0) * 0.4) * width * 0.3;
	float d = r - progress + wobble;
	float front = exp(-(d * d) / (width * width));
	float behind = step(d, 0.0) * smoothstep(-progress, 0.0, d);
	float streak = 0.88 + 0.12 * sin(a * 31.0 + r * 30.0 - TIME * 4.0);
	float inside = 1.0 - smoothstep(0.97, 1.0, r);
	ALBEDO = color.rgb * (front * 1.8 * streak + behind * behind * 0.5);
	ALPHA = clamp(front + behind * behind * wake, 0.0, 1.0) * alpha * color.a * inside;
}
