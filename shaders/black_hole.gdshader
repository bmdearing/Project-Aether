shader_type spatial;
// Black Hole's event horizon (a sphere): pitch black with a thin flickering
// rim where the view grazes its edge.
render_mode unshaded, cull_back, shadows_disabled;

uniform vec3 rim_color : source_color = vec3(0.62, 0.36, 0.9);
uniform float rim_power = 4.0;
uniform float glow = 1.0;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	ALBEDO = rim_color * rim * 2.5 * glow * (0.85 + 0.15 * sin(TIME * 9.0));
}
