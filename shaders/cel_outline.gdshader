shader_type spatial;
// Cel-shading ink pass: a full-screen quad on the active camera that draws
// dark lines where the depth buffer jumps (silhouettes, ledges) or, on
// Forward+, where surface normals turn sharply (creases). Depth is tested
// in 1/z, which is linear across a flat surface in screen space, so floors
// seen at a grazing angle stay clean. Lines fade out with distance before
// fog would swallow them. Drawn at the lowest transparent priority so spell
// FX layer over the ink.
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, blend_mix;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;
#endif

uniform vec3 ink : source_color = vec3(0.025, 0.02, 0.018);
uniform float thickness = 1.05;         // sample offset in pixels at 1080p
uniform float depth_threshold = 0.035;   // relative 1/z curvature that starts a line
uniform float normal_threshold = 0.45;   // 1 - cos(angle) between neighbouring normals
uniform float fade_start = 25.0;
uniform float fade_end = 80.0;
uniform float strength = 1.0;
// The held weapon and arms sit inside arm's reach: thinner, fainter ink there.
uniform float near_end = 1.4;
uniform float near_thickness = 0.6;
uniform float near_strength = 0.3;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float view_z(vec2 uv, mat4 inv_proj) {
	float raw = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, raw) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
vec3 view_n(vec2 uv) {
	return normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0);
}
#endif

void fragment() {
	vec2 uv = SCREEN_UV;
	float zc = view_z(uv, INV_PROJECTION_MATRIX);
	float held = 1.0 - smoothstep(near_end * 0.6, near_end, zc);
	vec2 px = vec2(thickness * mix(1.0, near_thickness, held) * VIEWPORT_SIZE.y / 1080.0) / VIEWPORT_SIZE;
	vec2 ox = vec2(px.x, 0.0);
	vec2 oy = vec2(0.0, px.y);

	float zl = view_z(uv - ox, INV_PROJECTION_MATRIX);
	float zr = view_z(uv + ox, INV_PROJECTION_MATRIX);
	float zu = view_z(uv - oy, INV_PROJECTION_MATRIX);
	float zd = view_z(uv + oy, INV_PROJECTION_MATRIX);

	float wc = 1.0 / zc;
	float wl = 1.0 / zl;
	float wr = 1.0 / zr;
	float wu = 1.0 / zu;
	float wd = 1.0 / zd;
	float wmax = max(wc, max(max(wl, wr), max(wu, wd)));
	float curv = max(abs(wl + wr - 2.0 * wc), abs(wu + wd - 2.0 * wc)) / max(wmax, 1e-6);
	float edge = smoothstep(depth_threshold, depth_threshold * 2.0, curv);

	float znear = min(zc, min(min(zl, zr), min(zu, zd)));
	float fade = 1.0 - smoothstep(fade_start, fade_end, znear);
	fade *= mix(near_strength, 1.0, smoothstep(near_end * 0.6, near_end, znear));

#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	vec3 nc = view_n(uv);
	float turn = 1.0 - min(min(dot(nc, view_n(uv - ox)), dot(nc, view_n(uv + ox))),
			min(dot(nc, view_n(uv - oy)), dot(nc, view_n(uv + oy))));
	// Creases fade sooner than silhouettes: far crease lines are mostly noise.
	float crease_fade = 1.0 - smoothstep(fade_start * 0.5, fade_end * 0.5, znear);
	edge = max(edge, smoothstep(normal_threshold, normal_threshold + 0.25, turn) * crease_fade);
#endif

	ALBEDO = ink;
	ALPHA = clamp(edge * fade * strength, 0.0, 1.0);
}
