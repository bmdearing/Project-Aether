shader_type spatial;
// Gravitational lens around Black Hole's core (a sphere a few times the
// core's size): the scene behind is dragged toward the centre, strongest
// just outside the core and fading to nothing at the shell's silhouette,
// with a faint bright ring where the bending peaks.
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.06;
uniform vec3 ring_color : source_color = vec3(0.7, 0.5, 1.0);
uniform float fade = 1.0;

void fragment() {
	vec3 n = normalize(NORMAL);
	float facing = clamp(dot(n, normalize(VIEW)), 0.0, 1.0);
	// facing 0 at the silhouette, 1 at the middle (hidden behind the core).
	float bend = smoothstep(0.0, 0.85, facing);
	vec2 inward = -vec2(n.x, -n.y);
	vec2 uv = SCREEN_UV + inward * bend * bend * strength * fade;
	vec3 col = textureLod(screen, uv, 0.0).rgb;
	float ring = exp(-pow((facing - 0.55) * 7.0, 2.0));
	col = col * (1.0 - 0.35 * bend * fade) + ring_color * ring * 0.35 * fade;
	ALBEDO = col;
	ALPHA = smoothstep(0.0, 0.08, facing);
}
