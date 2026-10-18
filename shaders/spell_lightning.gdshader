shader_type spatial;
// Lightning ribbon (UV.x across 0..1, centre 0.5; UV.y along the bolt): a
// white-hot core that wavers inside a soft coloured glow, with noisy pulses
// racing down its length and a hard per-frame flicker.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/spell_energy.gdshaderinc"

uniform vec3 color : source_color = vec3(0.9, 0.85, 0.3);
uniform float alpha = 1.0;
uniform float core_width = 0.16;
uniform float intensity = 2.0;
uniform float seed = 0.0;
// > 0: fade near the camera and low on screen (small arcs at the player's feet).
uniform float hud_clear = 0.0;
// Calmer settings for steady threads: 0 flicker, slow waver.
uniform float flicker_amount = 0.35;
uniform float wave_speed = 25.0;

void fragment() {
	float wave = (e_noise(vec2(UV.y * 14.0 + seed, TIME * wave_speed)) - 0.5) * 0.35;
	float d = abs(UV.x - 0.5 + wave * (1.0 - core_width)) * 2.0;
	float core = 1.0 - smoothstep(core_width * 0.4, core_width, d);
	float glow = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	float pulse = e_noise(vec2(UV.y * 6.0 - TIME * 30.0, seed));
	float flicker = 1.0 - flicker_amount + flicker_amount * step(0.35, e_hash(vec2(floor(TIME * 24.0), seed)));
	vec3 col = mix(color, vec3(1.0), core * 0.6);
	ALBEDO = col * (core * 1.6 + glow * (0.5 + pulse * 0.6)) * intensity * flicker;
	float a = clamp(core + glow * 0.75, 0.0, 1.0) * alpha;
	if (hud_clear > 0.0) {
		a *= e_hud_clear(VERTEX, SCREEN_UV, 0.8, 2.5);
	}
	ALPHA = a;
}
