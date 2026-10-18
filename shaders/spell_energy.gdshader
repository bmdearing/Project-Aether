shader_type spatial;
// General energy body for spell meshes (crystals, orbs, shells): churning
// noise inside, a soft fresnel rim instead of a hard silhouette, white-hot
// where the churn is densest. `hud_clear` > 0 fades it near the camera and
// low on screen, for effects that orbit the player.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/spell_energy.gdshaderinc"

uniform vec3 color : source_color = vec3(0.6, 0.85, 1.0);
uniform float intensity = 2.0;
uniform float alpha = 1.0;
uniform float noise_scale = 3.0;
uniform float scroll = 0.6;
uniform float rim_power = 2.0;
// 0: rim-lit shell (see-through middle); 1: solid glowing body.
uniform float fill = 0.4;
uniform float hud_clear = 0.0;
uniform float seed = 0.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	float rim = e_fresnel(NORMAL, VIEW, rim_power);
	vec2 q = vec2(obj_pos.x + obj_pos.z, obj_pos.y) * noise_scale + seed;
	float churn = e_churn(q, TIME * scroll);
	float heat = clamp(churn * 0.7 + rim * 0.5, 0.0, 1.0);
	float body = mix(rim, 1.0, fill) * (0.45 + churn * 0.9);
	float a = clamp(body, 0.0, 1.0) * alpha;
	if (hud_clear > 0.0) {
		a *= e_hud_clear(VERTEX, SCREEN_UV, 0.3, 0.9);
	}
	ALBEDO = e_ramp(color, heat) * intensity * (0.5 + heat);
	ALPHA = a;
}
