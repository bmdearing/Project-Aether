shader_type spatial;
// Underside of a floating Nexus platform: dark rock veined with glowing blue
// cracks that brighten with depth, dissolving into flakes toward the tip.

#include "res://shaders/nexus_common.gdshaderinc"

uniform vec4 rock : source_color = vec4(0.11, 0.095, 0.1, 1.0);
uniform vec4 glow_color : source_color = vec4(0.18, 0.48, 1.0, 1.0);
uniform float glow_energy = 4.0;
uniform float top_y = 0.0;
uniform float depth = 8.0;

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float t = clamp((top_y - wp.y) / depth, 0.0, 1.0);  // 0 at the top, 1 at the tip
	vec2 sp = vec2(wp.x + wp.z * 0.7, wp.y * 1.6);
	vec3 vor = nx_voronoi(sp * 0.9);
	if (t > 0.55 && vor.z < (t - 0.55) * 2.4) discard;
	float n = nx_fbm(sp * 0.6);
	vec3 col = rock.rgb * (0.55 + 0.9 * n);
	vec3 strata = nx_voronoi(sp * vec2(0.35, 1.4));
	col *= 0.8 + 0.35 * smoothstep(0.0, 0.2, strata.y);
	float crack = 1.0 - smoothstep(0.0, mix(0.03, 0.12, t), vor.y);
	crack *= smoothstep(0.25, 0.7, nx_noise(sp * 0.4 + 3.0) + t * 0.6);
	float pulse = 0.8 + 0.2 * sin(TIME * 0.9 + vor.z * 30.0 + wp.y);
	ALBEDO = mix(col, vec3(0.01, 0.03, 0.08), crack);
	ROUGHNESS = 0.9;
	EMISSION = glow_color.rgb * crack * glow_energy * (0.25 + t * 1.2) * pulse;
}
