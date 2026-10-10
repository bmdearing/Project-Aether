class_name MdxFxEmitter
extends RefCounted
## One ParticleEmitter2 of an MdxEffect. The script only spawns: each particle
## is written once into a ring of MultiMesh instances and MdxFx's particle
## shader works out its position, size, color and atlas frame from that.
## Instance layout: origin = spawn position, basis.x = velocity,
## basis.y = (spawn time, gravity, quad angle). Spawn rules follow
## war3-model's ParticlesController.createParticle().

const MAX_PARTICLES := 512
const DEAD_TIME := -1.0e9
const AABB_HALF := 40.0

var lifespan: float = 1.0

var _data: Dictionary
var _hz: float
var _multimesh := MultiMesh.new()
var _instances: Array[MultiMeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _next: int = 0
var _carry: float = 0.0
var _last_spawn: float = DEAD_TIME
var _anchored: bool = false
var _anchor := Vector3.ZERO
var _model_space: bool
var _pivot: Vector3

func _init(data: Dictionary, texture: Texture2D, parent: Node3D, hz: float) -> void:
	_data = data
	_hz = hz
	lifespan = maxf(float(data["lifespan"]), 0.01)
	_model_space = bool(data["model_space"])
	var p: Array = data["pivot"]
	_pivot = Vector3(p[0], p[1], p[2])

	var peak := MdxFx.max_value(data["emission"]) * lifespan
	if data["bursts"] != null:
		for seq_bursts: Array in data["bursts"]:
			for burst: Array in seq_bursts:
				peak = maxf(peak, float(burst[1]))
	var capacity := clampi(ceili(peak * 1.25) + 4, 8, MAX_PARTICLES)
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = QuadMesh.new()
	_multimesh.instance_count = capacity
	var dead := Transform3D(Basis(Vector3.ZERO, Vector3(DEAD_TIME, 0.0, 0.0), Vector3.ZERO), Vector3.ZERO)
	for i in capacity:
		_multimesh.set_instance_transform(i, dead)

	var shapes: Array[String] = []
	if bool(data["head"]):
		shapes.append("xy" if bool(data["xy_quad"]) else "billboard")
	if bool(data["tail"]):
		shapes.append("tail")
	var colors: Array = data["colors"]
	var scaling: Array = data["scaling"]
	for shape in shapes:
		var mat := ShaderMaterial.new()
		mat.shader = MdxFx.particle_shader(int(data["filter"]), shape)
		mat.render_priority = clampi(int(data["priority"]), Material.RENDER_PRIORITY_MIN, Material.RENDER_PRIORITY_MAX)
		mat.set_shader_parameter("tex", texture)
		mat.set_shader_parameter("lifespan", lifespan)
		mat.set_shader_parameter("time_mid", float(data["time_mid"]))
		for i in 3:
			var c: Array = colors[i]
			mat.set_shader_parameter("color%d" % i, Color(c[0], c[1], c[2], c[3]))
		mat.set_shader_parameter("scaling", Vector3(scaling[0], scaling[1], scaling[2]))
		var uv: Array = data["uv_tail"] if shape == "tail" else data["uv_head"]
		mat.set_shader_parameter("uv_anim", Vector4(uv[0], uv[1], uv[2], uv[3]))
		mat.set_shader_parameter("grid", Vector2(float(data["columns"]), float(data["rows"])))
		mat.set_shader_parameter("tail_length", float(data["tail_length"]))
		_materials.append(mat)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%s" % [String(data["name"]), shape]
		mmi.multimesh = _multimesh
		mmi.material_override = mat
		mmi.top_level = true
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3.ONE * -AABB_HALF, Vector3.ONE * AABB_HALF * 2.0)
		parent.add_child(mmi)
		_instances.append(mmi)

## Spawns for the step that ended at t (seconds into sequence seq) and
## advances the shared particle clock. prev_t < 0 on a sequence's first step.
func update(seq: int, t: float, prev_t: float, dt: float, clock: float, xform: Transform3D, emitting: bool) -> void:
	if not _anchored or _model_space:
		_set_anchor(xform)
	if emitting and MdxFx.scalar(_data["visibility"], seq, t, _hz) > 0.0:
		if _data["bursts"] != null:
			for burst: Array in (_data["bursts"] as Array)[seq]:
				var at := float(burst[0])
				if at > prev_t and at <= t:
					for i in int(burst[1]):
						_spawn(seq, t, clock, xform)
		else:
			_carry += MdxFx.scalar(_data["emission"], seq, t, _hz) * dt
			while _carry >= 1.0:
				_carry -= 1.0
				_spawn(seq, t, clock, xform)
	var size_scale := _uniform_scale(xform)
	for mat in _materials:
		mat.set_shader_parameter("now", clock)
		mat.set_shader_parameter("size_scale", size_scale)
		mat.set_shader_parameter("anchor", _anchor)
		mat.set_shader_parameter("space_xform", Projection(xform if _model_space else Transform3D(Basis(), _anchor)))

func is_alive(clock: float) -> bool:
	return clock - _last_spawn < lifespan

## World-space particles keep the spot the effect started at; model-space ones
## follow the effect every frame.
func _set_anchor(xform: Transform3D) -> void:
	_anchored = true
	_anchor = xform.origin
	for mmi in _instances:
		mmi.global_transform = Transform3D(Basis(), _anchor)

func _spawn(seq: int, t: float, clock: float, xform: Transform3D) -> void:
	var m := _matrix(seq, t)
	var width := MdxFx.scalar(_data["width"], seq, t, _hz)
	var length := MdxFx.scalar(_data["length"], seq, t, _hz)
	var speed := MdxFx.scalar(_data["speed"], seq, t, _hz)
	var variation := MdxFx.scalar(_data["variation"], seq, t, _hz)
	var latitude := deg_to_rad(MdxFx.scalar(_data["latitude"], seq, t, _hz))
	var gravity := MdxFx.scalar(_data["gravity"], seq, t, _hz)
	# WC3 local (x, y) area on the emitter plane is Godot (x, -z).
	var pos := m * (_pivot + Vector3(randf_range(-width, width), 0.0, -randf_range(-length, length)))
	if variation > 0.0:
		speed *= 1.0 + randf_range(-variation, variation)
	var tilt := randf_range(0.0, latitude)
	var angle := randf() * TAU
	var vx := 0.0 if bool(_data["line_emitter"]) else speed * sin(tilt) * cos(angle)
	var vel := m.basis * Vector3(vx, speed * cos(tilt), -speed * sin(tilt) * sin(angle))
	if not _model_space:
		pos = xform * pos - _anchor
		vel = xform.basis * vel
		gravity *= _uniform_scale(xform)
	_multimesh.set_instance_transform(_next, Transform3D(Basis(vel, Vector3(clock, gravity, angle), Vector3.ZERO), pos))
	_next = (_next + 1) % _multimesh.instance_count
	_last_spawn = clock

func _matrix(seq: int, t: float) -> Transform3D:
	var v := MdxFx.vector(_data["matrix"], seq, t, _hz, 12)
	return Transform3D(Basis(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]), Vector3(v[6], v[7], v[8])), Vector3(v[9], v[10], v[11]))

static func _uniform_scale(xform: Transform3D) -> float:
	var s := xform.basis.get_scale()
	return (absf(s.x) + absf(s.y) + absf(s.z)) / 3.0
