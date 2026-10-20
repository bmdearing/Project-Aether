shader_type spatial;
render_mode unshaded, shadows_disabled;
// Portal ring: energy pulses running round the torus over a steady glow.
// TorusMesh UV.x runs round the ring, UV.y round the tube.

uniform vec3 color : source_color = vec3(0.35, 0.65, 1.0);
uniform float energy = 1.5;
uniform float pulse_speed = 0.6;
uniform float pulses = 5.0;

void fragment() {
	float along = UV.x;
	// Two counter-running trains of pulses.
	float a = fract(along * pulses - TIME * pulse_speed);
	float b = fract(along * pulses * 0.6 + TIME * pulse_speed * 0.7);
	float pulse = pow(1.0 - abs(a * 2.0 - 1.0), 6.0) + pow(1.0 - abs(b * 2.0 - 1.0), 8.0) * 0.6;
	// The inner face (toward the portal) glows hottest.
	float inner = 0.5 + 0.5 * cos(UV.y * 6.2832);
	vec3 base = color * (0.55 + 0.45 * inner);
	vec3 hot = mix(color, vec3(1.0), 0.6);
	ALBEDO = (base + hot * pulse) * energy;
}
