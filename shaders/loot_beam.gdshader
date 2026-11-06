shader_type spatial;
// Loot beam pillar: a Y-axis billboard quad whose cross-section is the soft
// flare's profile, brightest at the floor and fading upward, with faint
// bands drifting up it. Fades out when the camera is right on top of it.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 2.0;
uniform float core = 0.5;
uniform float band_speed = 0.35;
uniform sampler2D profile : hint_default_white, filter_linear, repeat_disable;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), MAIN_CAM_INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(MAIN_CAM_INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float t = 1.0 - UV.y;
	float across = texture(profile, vec2(UV.x, 0.5)).a;
	float rise = pow(1.0 - t, 1.6) * smoothstep(0.0, 0.02, t);
	float phase = MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 2.3;
	float bands = 0.78 + 0.22 * sin((t * 5.0 - TIME * band_speed + phase) * 6.2832);
	float hot = pow(across, 6.0) * core;
	float near = smoothstep(0.6, 2.2, length(VERTEX));
	ALBEDO = mix(color.rgb, vec3(1.0), hot) * energy;
	ALPHA = clamp(across * rise * bands * near * color.a, 0.0, 1.0);
}
