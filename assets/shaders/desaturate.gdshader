shader_type canvas_item;

// Drains colour from everything drawn beneath it (PlayerHUD's savage-blow flash).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(c, vec3(grey), amount), 1.0);
}
