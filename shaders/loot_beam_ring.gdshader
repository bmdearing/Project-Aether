shader_type spatial;
// Loot beam floor ring: the soft shockwave texture on a flat quad, growing
// from the beam's foot and fading out, over and over.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 1.5;
uniform float period = 2.2;
uniform float offset = 0.0;
uniform float start_scale = 0.2;
uniform sampler2D ring : hint_default_white, filter_linear, repeat_disable;

varying float v_k;

void vertex() {
	float phase = fract(MODEL_MATRIX[3].x * 0.37 + MODEL_MATRIX[3].z * 0.61);
	v_k = fract(TIME / period + offset + phase);
	VERTEX.xz *= mix(start_scale, 1.0, sqrt(v_k));
}

void fragment() {
	float fade = smoothstep(0.0, 0.08, v_k) * pow(1.0 - v_k, 1.4);
	ALBEDO = color.rgb * energy;
	ALPHA = clamp(texture(ring, UV).a * fade * color.a, 0.0, 1.0);
}
