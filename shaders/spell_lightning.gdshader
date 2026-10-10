shader_type spatial;
// Lightning ribbon (UV.x across 0..1, centre 0.5): a white-hot core inside a
// soft coloured glow, flickering.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.9, 0.85, 0.3);
uniform float alpha = 1.0;
uniform float core_width = 0.12;

void fragment() {
	float d = abs(UV.x - 0.5) * 2.0;
	float core = 1.0 - smoothstep(core_width * 0.5, core_width, d);
	float glow = pow(1.0 - d, 2.5);
	float flicker = 0.8 + 0.2 * sin(TIME * 60.0 + UV.y * 20.0);
	ALBEDO = mix(color, vec3(1.0), core) * (core * 1.8 + glow * 0.9) * flicker;
	ALPHA = clamp(core + glow * 0.7, 0.0, 1.0) * alpha;
}
