shader_type spatial;
// Expanding ground shockwave (a plane, UV 0..1 across). A bright front at
// `progress` (fraction of the plane's half-size) with a wobbling, torn edge
// of churning energy, white-hot where it is densest, trailing a faint wake
// back to the centre. Fades near the camera and low on screen, so a ring
// round the caster doesn't cover the bottom of the view and the HUD.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/spell_energy.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0);
uniform float progress = 0.0;
uniform float width = 0.05;
uniform float alpha = 1.0;
uniform float wake = 0.35;
uniform float intensity = 1.3;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	// Angular noise coordinate that wraps round the ring.
	vec2 polar = vec2(a / 6.2831853 * 24.0, r * 6.0 - TIME * 1.5);
	float churn = e_noise_wrap(polar, 24.0) * 0.6 + e_noise_wrap(polar * vec2(2.0, 2.3) + vec2(0.0, TIME * 2.0), 48.0) * 0.4;
	float wobble = (sin(a * 7.0 + TIME * 3.0) * 0.6 + sin(a * 13.0 - TIME * 5.0) * 0.4) * width * 0.3 + (churn - 0.5) * width * 1.2;
	float d = r - progress + wobble;
	float front = exp(-(d * d) / (width * width));
	float behind = step(d, 0.0) * smoothstep(-progress, 0.0, d);
	float torn = smoothstep(0.2, 0.7, churn);
	float inside = 1.0 - smoothstep(0.97, 1.0, r);
	float heat = clamp(front * (0.4 + churn * 0.8), 0.0, 1.0);
	ALBEDO = e_ramp(color.rgb, heat) * intensity * (front * (0.6 + torn * 0.9) + behind * behind * (0.3 + churn * 0.4));
	ALPHA = clamp(front * (0.5 + torn * 0.5) + behind * behind * wake * churn, 0.0, 1.0) * alpha * color.a * inside
		* e_hud_clear(VERTEX, SCREEN_UV, 1.8, 4.0);
}
