shader_type spatial;
render_mode unshaded;
// Dark lake for the title screen: a shimmering moon path toward the
// camera, rain ripples, and lightning reflected as a flash.

uniform vec3 deep : source_color = vec3(0.008, 0.012, 0.025);
uniform vec3 far_tint : source_color = vec3(0.04, 0.05, 0.085);
uniform vec3 moon_color : source_color = vec3(0.8, 0.85, 1.0);
uniform float moon_x = 60.0;
uniform float path_width = 14.0;
uniform float flash = 0.0;
uniform vec3 cam_pos = vec3(0.0, 6.0, 25.0);

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

// Expanding ring per grid cell, restarting at a random phase: rain hits.
float ripples(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float r = 0.0;
	float t = fract(TIME * 0.9 + h21(cell));
	vec2 o = vec2(h21(cell + 1.3), h21(cell + 7.7)) - 0.5;
	float d = length(f - o * 0.6);
	r = (1.0 - smoothstep(0.0, 0.04, abs(d - t * 0.45))) * (1.0 - t);
	return r;
}

void fragment() {
	float dist = length(wp.xz - cam_pos.xz);
	vec3 col = mix(deep, far_tint, smoothstep(10.0, 140.0, dist));
	// The moon path narrows toward the camera and glitters.
	float t = clamp((cam_pos.z - wp.z) / 160.0, 0.0, 1.0);
	float centre = mix(cam_pos.x, moon_x, t);
	float width = mix(1.5, path_width * 0.7, t);
	float path = exp(-pow((wp.x - centre) / width, 2.0));
	float g1 = vnoise(vec2(wp.x * 3.5, wp.z * 12.0 + TIME * 1.3));
	float g2 = vnoise(vec2(wp.x * 7.0 - TIME * 0.6, wp.z * 22.0));
	float glitter = smoothstep(0.62, 0.95, g1 * g2 * 2.4);
	col += moon_color * path * (0.08 + glitter * 1.6) * (0.25 + t * 0.9);
	float rip = ripples(wp.xz * 0.9) + ripples(wp.xz * 1.7 + 11.0) * 0.6;
	col += vec3(0.25, 0.3, 0.4) * rip * 0.25 * (1.0 - smoothstep(20.0, 70.0, dist));
	col += vec3(0.5, 0.55, 0.75) * flash * (0.25 + path);
	ALBEDO = col;
}
