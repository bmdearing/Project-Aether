class_name MdxFx
## Shared helpers for MdxEffect: .fx.json loading, track sampling and the
## generated layer/particle shaders. Track encoding is documented in
## tools/mdx_pipeline/mdx_fx.js.

enum ParticleFilter { BLEND, ADDITIVE, MODULATE, MODULATE_2X, ALPHA_KEY }
enum LayerFilter { NONE, TRANSPARENT, BLEND, ADDITIVE, ADD_ALPHA, MODULATE, MODULATE_2X }

const ALPHA_KEY_CUT := 0.83   # war3-model's DISCARD_ALPHA_KEY_LEVEL
const TRANSPARENT_CUT := 0.75

static var _data: Dictionary = {}
static var _shaders: Dictionary = {}

static func load_data(path: String) -> Dictionary:
	if _data.has(path):
		return _data[path]
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("MdxFx: can't read %s" % path)
		return {}
	var fx: Dictionary = parsed
	_pack(fx)
	_data[path] = fx
	return fx

## Sample lists -> PackedFloat32Array once, so per-frame sampling stays cheap.
static func _pack(value: Variant) -> void:
	if value is Dictionary:
		var d: Dictionary = value
		if d.has("n"):
			if d.has("v"):
				d["v"] = PackedFloat32Array(d["v"])
			else:
				var packed: Array[PackedFloat32Array] = []
				for s: Array in d["seq"]:
					packed.append(PackedFloat32Array(s))
				d["seq"] = packed
			return
		for key: Variant in d:
			_pack(d[key])
	elif value is Array:
		for item: Variant in value:
			_pack(item)

## Value of a scalar track at t seconds into sequence seq.
static func scalar(track: Variant, seq: int, t: float, hz: float) -> float:
	if track is Dictionary:
		return _sample(track, seq, t, hz, 0)
	if track is Array:
		return float((track as Array)[0])
	return float(track)

static func vector(track: Variant, seq: int, t: float, hz: float, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for c in n:
		if track is Dictionary:
			out[c] = _sample(track, seq, t, hz, c)
		elif track is Array:
			out[c] = float((track as Array)[c])
		else:
			out[c] = float(track)
	return out

static func is_animated(track: Variant) -> bool:
	return track is Dictionary or track is Array

static func _sample(d: Dictionary, seq: int, t: float, hz: float, c: int) -> float:
	var n: int = int(d["n"])
	var values: PackedFloat32Array
	var pos: float
	if d.has("v"):
		values = d["v"]
		var length: float = float(d["global"])
		pos = (fmod(t, length) if length > 0.0 else 0.0) * hz
	else:
		values = (d["seq"] as Array)[seq]
		pos = t * hz
	var count: int = int(values.size() / float(n))
	if count == 0:
		return 0.0
	var i: int = clampi(int(pos), 0, count - 1)
	var j: int = mini(i + 1, count - 1)
	var f: float = clampf(pos - float(i), 0.0, 1.0)
	return lerpf(values[i * n + c], values[j * n + c], f)

static func max_value(track: Variant) -> float:
	if not track is Dictionary:
		return scalar(track, 0, 0.0, 1.0)
	var d: Dictionary = track
	var top := 0.0
	if d.has("v"):
		for x: float in (d["v"] as PackedFloat32Array):
			top = maxf(top, x)
	else:
		for s: PackedFloat32Array in d["seq"]:
			for x: float in s:
				top = maxf(top, x)
	return top

## shape: "billboard" (camera-facing head), "xy" (flat ground quad) or "tail"
## (stretched along velocity).
static func particle_shader(filter: int, shape: String) -> Shader:
	var key := "p_%d_%s" % [filter, shape]
	if _shaders.has(key):
		return _shaders[key]
	var blend := "blend_mix"
	var output := "ALBEDO = c.rgb;\n\tALPHA = c.a;"
	match filter:
		ParticleFilter.ADDITIVE:
			blend = "blend_add, fog_disabled"
		ParticleFilter.ALPHA_KEY:
			blend = "blend_add, fog_disabled"
			output = "if (c.a < %.2f) {\n\t\tdiscard;\n\t}\n\t%s" % [ALPHA_KEY_CUT, output]
		ParticleFilter.MODULATE:
			blend = "blend_mul"
			output = "ALBEDO = mix(vec3(1.0), c.rgb, c.a);"
		ParticleFilter.MODULATE_2X:
			blend = "blend_mul"
			output = "ALBEDO = mix(vec3(0.5), c.rgb, c.a) * 2.0;"
	var corner := "center + (INV_VIEW_MATRIX[0].xyz * corner.x + INV_VIEW_MATRIX[1].xyz * corner.y) * size"
	var uv := "UV"
	if shape == "xy":
		corner = "center + vec3(corner.x * cos(spawn.z) - corner.y * sin(spawn.z), 0.0, -(corner.x * sin(spawn.z) + corner.y * cos(spawn.z))) * size"
	elif shape == "tail":
		corner = "center + tail_side(center, vel, CAMERA_POSITION_WORLD, INV_VIEW_MATRIX[0].xyz) * corner.x * size - vel * tail_length * (0.5 - 0.5 * corner.y)"
		uv = "UV.yx"
	var shader := Shader.new()
	shader.code = PARTICLE_TEMPLATE.replace("{BLEND}", blend).replace("{CORNER}", corner) \
		.replace("{UV}", uv).replace("{OUTPUT}", output)
	_shaders[key] = shader
	return shader

static func layer_shader(filter: int, two_sided: bool) -> Shader:
	var key := "l_%d_%s" % [filter, two_sided]
	if _shaders.has(key):
		return _shaders[key]
	var modes := "depth_draw_never, blend_mix"
	var output := "ALBEDO = c.rgb;\n\tALPHA = c.a;"
	match filter:
		LayerFilter.NONE:
			modes = "depth_draw_opaque, blend_mix"
			output = "if (tint.a < %.2f) {\n\t\tdiscard;\n\t}\n\tALBEDO = c.rgb;" % TRANSPARENT_CUT
		LayerFilter.TRANSPARENT:
			modes = "depth_draw_opaque, blend_mix"
			output += "\n\tALPHA_SCISSOR_THRESHOLD = %.2f;" % TRANSPARENT_CUT
		LayerFilter.ADDITIVE:
			# WC3 adds src * src (SRC_COLOR, ONE): dark texels drop out.
			modes = "depth_draw_never, blend_add, fog_disabled"
			output = "ALBEDO = c.rgb * c.rgb;\n\tALPHA = c.a;"
		LayerFilter.ADD_ALPHA:
			modes = "depth_draw_never, blend_add, fog_disabled"
		LayerFilter.MODULATE:
			modes = "depth_draw_never, blend_mul"
			output = "ALBEDO = mix(vec3(1.0), c.rgb, c.a);"
		LayerFilter.MODULATE_2X:
			modes = "depth_draw_never, blend_mul"
			output = "ALBEDO = mix(vec3(0.5), c.rgb, c.a) * 2.0;"
	var shader := Shader.new()
	shader.code = LAYER_TEMPLATE.replace("{CULL}", "cull_disabled" if two_sided else "cull_back") \
		.replace("{MODES}", modes).replace("{OUTPUT}", output)
	_shaders[key] = shader
	return shader

## Instance data (see MdxFxEmitter): origin = spawn position, basis.x = spawn
## velocity, basis.y = (spawn time, gravity, quad angle). Motion, size, color
## and atlas frame follow war3-model's ParticlesController: ballistic flight,
## then two linear segments split at time_mid.
const PARTICLE_TEMPLATE := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, skip_vertex_transform, {BLEND};

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float now;
uniform float lifespan = 1.0;
uniform float time_mid = 0.5;
uniform vec4 color0 : source_color = vec4(1.0);
uniform vec4 color1 : source_color = vec4(1.0);
uniform vec4 color2 : source_color = vec4(1.0);
uniform vec3 scaling = vec3(1.0);
uniform vec4 uv_anim;
uniform vec2 grid = vec2(1.0);
uniform float tail_length = 1.0;
uniform float size_scale = 1.0;
uniform vec3 anchor;
uniform mat4 space_xform = mat4(1.0);

varying vec4 v_color;
varying vec2 v_uv;

vec3 tail_side(vec3 center, vec3 vel, vec3 cam, vec3 fallback) {
	vec3 side = cross(vel, cam - center);
	return dot(side, side) > 1e-10 ? normalize(side) : fallback;
}

void vertex() {
	vec3 spawn = MODEL_MATRIX[1].xyz;
	float age = now - spawn.x;
	if (age < 0.0 || age >= lifespan) {
		VERTEX = vec3(0.0, 0.0, 1.0);
		v_color = vec4(0.0);
		v_uv = vec2(0.0);
	} else {
		float life_t = age / lifespan;
		bool first = life_t < time_mid;
		float t = first ? life_t / max(time_mid, 0.0001) : (life_t - time_mid) / max(1.0 - time_mid, 0.0001);
		float size = (first ? mix(scaling.x, scaling.y, t) : mix(scaling.y, scaling.z, t)) * size_scale;
		v_color = first ? mix(color0, color1, t) : mix(color1, color2, t);
		vec3 pos = MODEL_MATRIX[3].xyz - anchor + MODEL_MATRIX[0].xyz * age + vec3(0.0, -0.5 * spawn.y * age * age, 0.0);
		vec3 vel = mat3(space_xform) * (MODEL_MATRIX[0].xyz + vec3(0.0, -spawn.y * age, 0.0));
		vec3 center = (space_xform * vec4(pos, 1.0)).xyz;
		vec2 corner = VERTEX.xy * 2.0;
		vec3 world = {CORNER};
		vec2 frames = first ? uv_anim.xy : uv_anim.zw;
		float frame = round(mix(frames.x, frames.y, t));
		v_uv = (vec2(mod(frame, grid.x), floor(frame / grid.x)) + {UV}) / grid;
		VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	}
}

void fragment() {
	vec4 c = texture(tex, v_uv) * v_color;
	{OUTPUT}
}
"""

const LAYER_TEMPLATE := """shader_type spatial;
render_mode unshaded, {CULL}, {MODES};

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 uv_offset;

void fragment() {
	vec4 c = texture(tex, UV + uv_offset) * tint;
	{OUTPUT}
}
"""
