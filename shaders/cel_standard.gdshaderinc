// Cel twin of a BaseMaterial3D, built by CelShading. The generated shader
// sets render_mode and these defines, then includes this file:
// TEX_HINTS (sampler filter/repeat), VCOL, VCOL_SRGB, CEL_NORMAL,
// CEL_EMISSION (+ CEL_EMISSION_MUL), SCISSOR.

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, hint_default_white, TEX_HINTS;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform float specular = 0.5;
#ifdef CEL_NORMAL
uniform sampler2D texture_normal : hint_normal, TEX_HINTS;
uniform float normal_scale = 1.0;
#endif
#ifdef CEL_EMISSION
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 1.0;
#ifdef CEL_EMISSION_MUL
uniform sampler2D texture_emission : source_color, hint_default_white, TEX_HINTS;
#else
uniform sampler2D texture_emission : source_color, hint_default_black, TEX_HINTS;
#endif
#endif
#ifdef SCISSOR
uniform float alpha_scissor_threshold = 0.5;
#endif

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
#ifdef VCOL_SRGB
	COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
#endif
}

void fragment() {
	vec4 tex = texture(texture_albedo, UV);
#ifdef VCOL
	tex *= COLOR;
#endif
	ALBEDO = albedo.rgb * tex.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;
#ifdef CEL_NORMAL
	NORMAL_MAP = texture(texture_normal, UV).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
#endif
#ifdef CEL_EMISSION
#ifdef CEL_EMISSION_MUL
	EMISSION = emission.rgb * texture(texture_emission, UV).rgb * emission_energy;
#else
	EMISSION = (emission.rgb + texture(texture_emission, UV).rgb) * emission_energy;
#endif
#endif
#ifdef SCISSOR
	ALPHA = albedo.a * tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
#endif
}

// Shadow, a soft half-lit band, then full light. Edges are a little soft
// so the bands don't alias.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = 0.6 * smoothstep(-0.06, 0.06, ndl) + 0.4 * smoothstep(0.32, 0.46, ndl);
	DIFFUSE_LIGHT += band * ATTENUATION * LIGHT_COLOR / PI;
}
