shader_type spatial;
// A blade sweep on an arc sector (UV.x across the arc 0..1, UV.y inner 0 ->
// outer 1): a bright leading edge travels across with `sweep` 0 -> 1,
// leaving a fading trail, brightest toward the outer edge like a blade tip.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.45, 0.86, 1.0);
uniform float sweep = 0.0;
uniform float reverse = 0.0;
uniform float alpha = 1.0;

void fragment() {
	float x = reverse > 0.5 ? 1.0 - UV.x : UV.x;
	float d = sweep * 1.15 - x;
	float trail = d >= 0.0 ? exp(-d * 4.5) : 0.0;
	float front = exp(-pow(d * 22.0, 2.0));
	float blade = 0.3 + pow(UV.y, 2.0) * 1.2;
	float edge = smoothstep(0.0, 0.2, UV.y) * (1.0 - smoothstep(0.9, 1.0, UV.y));
	ALBEDO = color * (trail * 1.8 + front * 3.5) * blade;
	ALPHA = clamp((trail * 0.8 + front) * edge * blade, 0.0, 1.0) * alpha;
}
