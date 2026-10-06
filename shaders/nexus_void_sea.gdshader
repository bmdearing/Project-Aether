shader_type spatial;
// The far "bottom" of the void: a dark plane with a slowly drifting web of
// faint blue cells, fading out with distance from the Nexus.
render_mode unshaded, shadows_disabled;

#include "res://shaders/nexus_common.gdshaderinc"

uniform vec4 color : source_color = vec4(0.12, 0.35, 1.0, 1.0);
uniform float energy = 0.35;
uniform float radius = 140.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz * 0.3 + vec2(TIME * 0.01, TIME * 0.006);
	vec3 v = nx_voronoi(p);
	vec3 v2 = nx_voronoi(p * 2.7 + 5.0);
	float web = (1.0 - smoothstep(0.0, 0.06, v.y)) * step(0.3, v.z);
	web += (1.0 - smoothstep(0.0, 0.05, v2.y)) * 0.4 * step(0.55, v2.z);
	float fade = 1.0 - smoothstep(radius * 0.3, radius, length(wp.xz));
	float pulse = 0.7 + 0.3 * sin(TIME * 0.5 + v.z * 20.0);
	ALBEDO = vec3(0.004, 0.008, 0.02) + color.rgb * web * energy * fade * pulse;
}
