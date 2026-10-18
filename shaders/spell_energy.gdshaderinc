// Shared "energy" look for spell effects: value noise and fbm to churn
// inside a shape, a soft fresnel edge, a white-hot core fading to a coloured
// rim, and fades that keep an effect off the HUD. Colours come out above 1.0
// on purpose so the per-style glow (threshold 1.0-1.8) blooms them.

float e_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float e_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(e_hash(i), e_hash(i + vec2(1.0, 0.0)), f.x), mix(e_hash(i + vec2(0.0, 1.0)), e_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Noise that wraps every `wrap` cells along x (closed tubes, shells).
float e_noise_wrap(vec2 p, float wrap) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float i0 = mod(i.x, wrap);
	float i1 = mod(i.x + 1.0, wrap);
	return mix(mix(e_hash(vec2(i0, i.y)), e_hash(vec2(i1, i.y)), f.x), mix(e_hash(vec2(i0, i.y + 1.0)), e_hash(vec2(i1, i.y + 1.0)), f.x), f.y);
}

float e_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += e_noise(p) * a;
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// Churning energy: two fbm layers drifting against each other, 0..1,
// with bright filaments where they cross.
float e_churn(vec2 p, float t) {
	float a = e_fbm(p + vec2(t * 0.6, -t));
	float b = e_fbm(p * 1.7 - vec2(t * 0.9, t * 0.4) + a * 1.5);
	return clamp(b * 1.25 - 0.1, 0.0, 1.0);
}

// 0 face-on .. 1 grazing.
float e_fresnel(vec3 normal, vec3 view, float power) {
	return pow(1.0 - abs(dot(normalize(normal), normalize(view))), power);
}

// heat 0..1: coloured rim (dimmer) -> colour -> white-hot core.
vec3 e_ramp(vec3 color, float heat) {
	vec3 rim = color * 0.55;
	vec3 hot = mix(color, vec3(1.0), 0.75);
	return heat < 0.5 ? mix(rim, color, heat * 2.0) : mix(color, hot, (heat - 0.5) * 2.0);
}

// Fades a fragment that sits low on screen (behind the HUD) or right in
// front of the camera. Pass VERTEX (view space) and SCREEN_UV.
float e_hud_clear(vec3 view_pos, vec2 screen_uv, float near_start, float near_end) {
	float near = smoothstep(near_start, near_end, length(view_pos));
	float low = 1.0 - smoothstep(0.68, 0.88, screen_uv.y);
	return near * low;
}
