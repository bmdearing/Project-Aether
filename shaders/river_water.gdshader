shader_type spatial;
// Flowing water for rivers and streams (WaterBuilder). UV.x runs along the
// flow in metres, UV.y across the channel (0..1); the banks fade out and two
// noise layers scroll downstream for ripples and glints.
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.07, 0.2, 0.24, 0.86);
uniform vec4 shallow_color : source_color = vec4(0.22, 0.42, 0.4, 0.62);
uniform float depth = 1.0; // 1 = river, 0 = shallow stream or ford
uniform float flow_speed = 0.6;
uniform float ripple_scale = 0.35;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 flow = vec2(UV.x * ripple_scale - TIME * flow_speed * ripple_scale, UV.y * 2.0);
	float n1 = noise(flow * 3.0);
	float n2 = noise(flow * 7.0 + vec2(TIME * 0.21, 3.7));
	float ripple = n1 * 0.6 + n2 * 0.4;
	float edge = smoothstep(0.0, 0.18, UV.y) * smoothstep(1.0, 0.82, UV.y);
	float centre = mix(0.35, 1.0, edge) * depth;
	vec4 water = mix(shallow_color, deep_color, centre);
	ALBEDO = water.rgb + vec3(pow(ripple, 6.0) * 0.6);
	ALPHA = water.a * mix(0.55, 1.0, edge);
	ROUGHNESS = 0.08 + ripple * 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	// Ripples tilt the normal a little so the sun catches them.
	NORMAL_MAP = normalize(vec3(n1 - 0.5, n2 - 0.5, 2.5)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
}
