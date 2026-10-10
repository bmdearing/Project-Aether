shader_type spatial;
// A motion streak on a cone of height `length` centred on its origin, narrow
// tail at +Y: brightest at the head (-Y), fading along the tail and at the
// view-grazing edges.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.6, 0.85, 1.0);
uniform float intensity = 1.5;
uniform float length = 3.0;

varying float along;

void vertex() {
	along = clamp(0.5 - VERTEX.y / length, 0.0, 1.0);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = mix(color, vec3(1.0), along * along * 0.5) * intensity;
	ALPHA = along * along * smoothstep(0.0, 0.6, facing);
}
