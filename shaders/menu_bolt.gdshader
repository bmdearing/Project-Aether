shader_type spatial;
// Lightning bolt: flat additive quads, brighter at the core of each segment.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.85, 0.9, 1.0, 1.0);
uniform float intensity = 0.0;

void fragment() {
	ALBEDO = color.rgb * intensity * 6.0;
}
