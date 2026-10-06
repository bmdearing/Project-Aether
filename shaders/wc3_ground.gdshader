shader_type spatial;
// Warcraft III terrain sheets mapped by world position. A "wide" sheet
// (2048x1024) holds 16 interchangeable full tiles in its right half; a
// "narrow" one (1024x1024) is a transition sheet whose cells 0 and 15 are
// full. Each world cell picks one tile by hash so the ground doesn't visibly
// repeat. Layer B is blended in as noise patches. Walls (wall_mode) project
// along their facing axis instead of from above.

uniform sampler2D albedo_a : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_a : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool wide_a = true;

uniform sampler2D albedo_b : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_b : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool wide_b = true;
uniform float b_amount : hint_range(0.0, 1.0) = 0.0;
uniform float b_patch_size = 9.0;

uniform float tile_size = 2.3;   // metres per WC3 terrain cell (128 units at the units' 0.018 scale)
uniform bool wall_mode = false;
uniform vec4 tint : source_color = vec4(1.0);

varying vec3 world_pos;
varying vec3 world_normal;

const float CELL_INSET = 0.004;  // keeps mip filtering from bleeding the neighbouring atlas cell

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Atlas UV of the tile this world cell uses, plus the atlas size of one cell
// (for texture gradients).
vec2 atlas_uv(vec2 uv, bool wide, float salt, out vec2 cell_size) {
	vec2 cell = floor(uv);
	vec2 f = clamp(fract(uv), CELL_INSET, 1.0 - CELL_INSET);
	float h = hash(cell + salt);
	int index;
	if (wide) {
		index = int(h * 16.0);
		cell_size = vec2(0.125, 0.25);
		return vec2(0.5 + (float(index % 4) + f.x) * 0.125, (float(index / 4) + f.y) * 0.25);
	}
	index = h < 0.5 ? 0 : 15;
	cell_size = vec2(0.25);
	return vec2((float(index % 4) + f.x) * 0.25, (float(index / 4) + f.y) * 0.25);
}

void fragment() {
	vec2 uv;
	if (wall_mode) {
		vec3 n = abs(world_normal);
		if (n.y > 0.5) {
			uv = world_pos.xz;  // wall tops
		} else {
			uv = (n.x > n.z ? world_pos.zy : world_pos.xy) * vec2(1.0, -1.0);
		}
	} else {
		uv = world_pos.xz;
	}
	uv /= tile_size;
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);

	vec2 size_a;
	vec2 ua = atlas_uv(uv, wide_a, 0.0, size_a);
	vec3 col = textureGrad(albedo_a, ua, dx * size_a, dy * size_a).rgb;
	vec3 nrm = textureGrad(normal_a, ua, dx * size_a, dy * size_a).rgb;
	vec3 orm = textureGrad(orm_a, ua, dx * size_a, dy * size_a).rgb;

	if (b_amount > 0.0) {
		vec2 patch_p = (wall_mode ? uv * tile_size : world_pos.xz) / b_patch_size;
		float mask = smoothstep(1.0 - b_amount - 0.08, 1.0 - b_amount + 0.08, value_noise(patch_p));
		if (mask > 0.0) {
			vec2 size_b;
			vec2 ub = atlas_uv(uv, wide_b, 17.0, size_b);
			col = mix(col, textureGrad(albedo_b, ub, dx * size_b, dy * size_b).rgb, mask);
			nrm = mix(nrm, textureGrad(normal_b, ub, dx * size_b, dy * size_b).rgb, mask);
			orm = mix(orm, textureGrad(orm_b, ub, dx * size_b, dy * size_b).rgb, mask);
		}
	}

	ALBEDO = col * tint.rgb;
	NORMAL_MAP = nrm;
	AO = orm.r;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
}
