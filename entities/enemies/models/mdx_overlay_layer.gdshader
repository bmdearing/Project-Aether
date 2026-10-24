shader_type spatial;
// An upper layer of a classic WC3 material (tools/build_mdx_wrappers.gd),
// drawn as a next pass over the geoset's base layer. uv_scroll is the
// layer's texture animation in UV/sec.
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

uniform sampler2D layer_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scroll = vec2(0.0);
uniform float layer_alpha = 1.0;
uniform vec2 uv_scale = vec2(1.0);

void fragment() {
	vec4 c = texture(layer_texture, UV * uv_scale + uv_scroll * TIME);
	ALBEDO = c.rgb;
	ALPHA = c.a * layer_alpha;
}
