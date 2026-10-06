shader_type spatial;
// Soft additive light shaft rising out of the void (a QuadMesh, uv.y along it).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/nexus_common.gdshaderinc"

uniform vec4 color : source_color = vec4(0.25, 0.5, 1.0, 1.0);
uniform float energy = 1.2;
uniform float scroll_speed = 0.06;

void fragment() {
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float body = pow(across, 5.0);
	float ends = smoothstep(0.0, 0.45, UV.y) * smoothstep(1.0, 0.6, UV.y);
	float streaks = nx_noise(vec2(UV.x * 14.0, UV.y * 2.5 + TIME * scroll_speed * 10.0));
	streaks = mix(0.45, 1.0, streaks) * mix(0.7, 1.0, nx_noise(vec2(UV.x * 40.0, TIME * 0.2)));
	ALBEDO = color.rgb * energy * body * ends * streaks;
}
