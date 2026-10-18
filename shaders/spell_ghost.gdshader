shader_type spatial;
// Spectral body (Wraith): see-through with a glowing rim, churning wisps
// streaming down its surface, and a tattered hem that frays away at the
// bottom (`tatter` > 0; UV.y 0 = hem, 1 = top on tubes). Fades right at the
// camera so a wraith at the player's side doesn't cover the view.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/spell_energy.gdshaderinc"

uniform vec3 color : source_color = vec3(0.45, 0.86, 1.0);
uniform float opacity = 1.0;
uniform float tatter = 0.0;
uniform float intensity = 1.5;

void fragment() {
	float rim = e_fresnel(NORMAL, VIEW, 2.2);
	float wisp = e_noise_wrap(vec2(UV.x * 8.0, UV.y * 3.0 + TIME * 0.9), 8.0);
	float churn = e_churn(vec2(UV.x * 5.0, UV.y * 4.0 + TIME * 0.6), TIME * 0.4);
	float a = (0.02 + rim * 0.6 + wisp * 0.08 + smoothstep(0.35, 0.85, churn) * 0.3) * opacity;
	if (tatter > 0.0) {
		float fray = e_noise_wrap(vec2(UV.x * 10.0, TIME * 0.7), 10.0);
		a *= smoothstep(0.0, tatter, UV.y - (fray - 0.5) * tatter * 0.8);
	}
	float heat = clamp(rim * 0.9 + churn * 0.3, 0.0, 1.0);
	ALBEDO = e_ramp(color, heat) * intensity * (0.5 + rim * 0.9 + wisp * 0.3);
	ALPHA = clamp(a, 0.0, 1.0) * e_hud_clear(VERTEX, SCREEN_UV, 0.6, 2.0);
}
