shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.5;
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	float dist = length(UV - vec2(0.5));
	float vignette = smoothstep(inner_radius, inner_radius + 0.4, dist);
	COLOR = vec4(vignette_color.rgb, vignette * intensity);
}
