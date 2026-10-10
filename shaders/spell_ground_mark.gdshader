shader_type spatial;
// A spell's mark left on the ground (a plane, UV 0..1 across): a ragged
// noisy patch of `base` with a `glow` accent that cools off first, then the
// whole mark fades. pattern: 0 scorch (blotchy, glowing embers), 1 frost
// (radial crystal streaks), 2 rot (pooled blotches), 3 cracks (fissures
// radiating from the centre).
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 base : source_color = vec4(0.05, 0.04, 0.03, 0.7);
uniform vec4 glow : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform int pattern = 0;
uniform float heat = 1.0;    // accent strength, tweened down
uniform float alpha = 1.0;   // whole mark, tweened down at the end
uniform float seed = 0.0;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * a;
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float n = fbm(p * 3.0 + seed);
	float shape = 1.0 - smoothstep(0.45, 0.95, r + (n - 0.5) * 0.45);
	float accent = 0.0;
	float density = 1.0;
	if (pattern == 0) {
		accent = smoothstep(0.62, 0.8, fbm(p * 7.0 + 3.1)) * (1.0 - r);
		density = 0.6 + n * 0.5;
	} else if (pattern == 1) {
		float rays = pow(abs(sin(a * 11.0 + n * 3.0)), 18.0) + pow(abs(sin(a * 7.0 - n * 2.0)), 24.0);
		accent = clamp(rays * smoothstep(0.35, 0.7, fbm(vec2(a * 3.0, r * 5.0) + 2.0)) * (1.0 - r * 0.8) + smoothstep(0.6, 0.75, n) * 0.5, 0.0, 1.0);
		density = 0.5 + n * 0.4;
	} else if (pattern == 2) {
		density = smoothstep(0.35, 0.65, fbm(p * 4.0 + 7.7)) * 0.8 + 0.25;
		accent = smoothstep(0.52, 0.8, fbm(p * 4.5 - 1.3)) * 0.6;
	} else {
		float crack = 1.0 - smoothstep(0.0, 0.06, abs(sin(a * 6.0 + fbm(p * 5.0) * 4.0)) * (0.6 + r));
		accent = crack * (1.0 - r * 0.6);
		density = 0.35 + crack * 0.6;
	}
	vec3 col = mix(base.rgb, glow.rgb, accent * heat);
	ALBEDO = col * (1.0 + accent * heat * 1.5);
	ALPHA = clamp(shape * (base.a * density + accent * heat * glow.a), 0.0, 1.0) * alpha;
}
