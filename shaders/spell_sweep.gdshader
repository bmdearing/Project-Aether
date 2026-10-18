shader_type spatial;
// A blade sweep on an arc sector (UV.x across the arc 0..1, UV.y inner 0 ->
// outer 1): a bright leading edge travels across with `sweep` 0 -> 1,
// leaving a trail that tears into wisps. Streaks of churning energy run
// along the arc, white-hot at the blade's outer edge, coloured inside.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/spell_energy.gdshaderinc"

uniform vec3 color : source_color = vec3(0.45, 0.86, 1.0);
uniform float sweep = 0.0;
uniform float reverse = 0.0;
uniform float alpha = 1.0;
uniform float intensity = 2.2;

void fragment() {
	float x = reverse > 0.5 ? 1.0 - UV.x : UV.x;
	float d = sweep * 1.15 - x;
	// Streaks stretched along the arc, scrolling with the swing.
	vec2 q = vec2(x * 3.0 - TIME * 2.0, UV.y * 7.0);
	float streak = e_churn(q, TIME * 1.5);
	float tear = e_fbm(vec2(x * 6.0 + d * 4.0, UV.y * 4.0 + TIME));
	float trail = d >= 0.0 ? exp(-d * 4.0) : 0.0;
	// The trail frays from the inner edge as it ages.
	trail *= smoothstep(0.0, 0.35, UV.y + tear * 0.6 - d * 0.9);
	float blade = pow(UV.y, 1.6);
	float df = d + (tear - 0.5) * 0.12 + (1.0 - UV.y) * 0.06;
	float front = exp(-pow(df * 11.0, 2.0)) * (0.35 + blade * 0.9) * (0.6 + streak * 0.6);
	float edge = smoothstep(0.0, 0.25, UV.y + (tear - 0.5) * 0.2) * (1.0 - smoothstep(0.82, 1.0, UV.y + (tear - 0.5) * 0.15)) * smoothstep(0.0, 0.08, x) * (1.0 - smoothstep(0.9, 1.0, x));
	float heat = clamp(blade * 0.7 + front * 0.6 + streak * 0.35 - (1.0 - trail) * 0.2, 0.0, 1.0);
	float body = (trail * (0.35 + streak * 0.9) + front * 1.4) * (0.35 + blade * 1.1);
	ALBEDO = e_ramp(color, heat) * intensity * (0.6 + heat);
	ALPHA = clamp(body * edge, 0.0, 1.0) * alpha * e_hud_clear(VERTEX, SCREEN_UV, 0.6, 1.6);
}
