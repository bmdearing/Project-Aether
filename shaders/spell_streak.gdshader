shader_type spatial;
// A motion streak on a cone of height `length` centred on its origin, narrow
// tail at +Y: white-hot at the head (-Y), churning energy streaming back
// along the tail and tearing apart, soft where the cone grazes the view.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/spell_energy.gdshaderinc"

uniform vec3 color : source_color = vec3(0.6, 0.85, 1.0);
uniform float intensity = 2.2;
uniform float length = 3.0;

varying float along;

void vertex() {
	along = clamp(0.5 - VERTEX.y / length, 0.0, 1.0);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	// UV.x runs round the cone; streaks race back down the tail.
	float churn = e_churn(vec2(UV.x * 6.0, along * 4.0 + TIME * 9.0), TIME * 2.0);
	float tail = along * along;
	float torn = smoothstep(0.15, 0.6, churn + along * 0.5);
	float heat = clamp(along * 0.8 + churn * 0.4, 0.0, 1.0);
	ALBEDO = e_ramp(color, heat) * intensity * (0.5 + heat);
	ALPHA = clamp(tail * torn * (0.6 + churn * 0.6), 0.0, 1.0) * smoothstep(0.0, 0.6, facing) * e_hud_clear(VERTEX, SCREEN_UV, 1.0, 3.0);
}
