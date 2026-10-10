extends Node3D
class_name MdxEffect
## Plays a Warcraft III spell effect converted by tools/mdx_pipeline/mdx_fx.js:
## the effect's animated geosets (its .glb, with WC3 blend modes, alpha and UV
## animation applied from the sidecar) plus its particle emitters
## (MdxFxEmitter). Scale the node to resize the whole effect.

signal finished

@export_file("*.json") var fx_path: String = ""
## Sequence to play; empty plays the first one.
@export var sequence: String = ""
@export var loop: bool = false
@export var speed_scale: float = 1.0
## Seconds skipped at the start (WC3 effects often open with a lead-in).
@export var start_time: float = 0.0
@export var autoplay: bool = true
@export var free_when_finished: bool = true

## Skinned effect meshes scale their bones far past the rest-pose AABB (local, WC3 units).
const CULL_MARGIN := 1000.0

var _fx: Dictionary = {}
var _hz: float = 30.0
var _seq: int = 0
var _length: float = 0.0
var _time: float = 0.0
var _prev_time: float = -1.0
var _clock: float = 0.0
var _running: bool = false
var _anim: AnimationPlayer
var _layers: Array[Dictionary] = []  # {material, geoset, layer}
var _emitters: Array[MdxFxEmitter] = []

func _ready() -> void:
	set_process(false)
	if autoplay and not fx_path.is_empty():
		play()

func play(sequence_name: String = "") -> void:
	if not sequence_name.is_empty():
		sequence = sequence_name
	if _fx.is_empty():
		_setup()
		if _fx.is_empty():
			return
	var sequences: Array = _fx["sequences"]
	_seq = 0
	for i in sequences.size():
		if String((sequences[i] as Dictionary)["name"]).to_lower() == sequence.to_lower():
			_seq = i
	var s: Dictionary = sequences[_seq]
	_length = (float(s["end"]) - float(s["start"])) / 1000.0
	_time = minf(start_time, _length)
	_prev_time = -1.0
	_running = true
	if _anim and _anim.has_animation(String(s["name"])):
		_anim.speed_scale = speed_scale
		_anim.play(String(s["name"]))
		_anim.seek(_time, true)
	_update_layers()
	set_process(true)

func _setup() -> void:
	_fx = MdxFx.load_data(fx_path)
	if _fx.is_empty():
		return
	var dir := fx_path.get_base_dir() + "/"
	_hz = float(_fx["sample_hz"])
	if _fx["model"] != null:
		var model := (load(dir + String(_fx["model"])) as PackedScene).instantiate() as Node3D
		add_child(model)
		_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		for g: Dictionary in _fx["geosets"]:
			var mesh := model.find_child("Geoset_%d" % int(g["index"]), true, false) as MeshInstance3D
			if mesh:
				_setup_geoset(mesh, g, dir)
	for e: Dictionary in _fx["emitters"]:
		_emitters.append(MdxFxEmitter.new(e, _texture(dir, e["texture"]), self, _hz))

func _setup_geoset(mesh: MeshInstance3D, g: Dictionary, dir: String) -> void:
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.extra_cull_margin = CULL_MARGIN
	var previous: ShaderMaterial = null
	for layer: Dictionary in g["layers"]:
		var tex := _texture(dir, layer["texture"])
		if tex == null:
			continue  # an untextured effect card would render as a solid sheet
		var mat := ShaderMaterial.new()
		mat.shader = MdxFx.layer_shader(int(layer["filter"]), bool(layer["two_sided"]))
		mat.set_shader_parameter("tex", tex)
		if previous:
			previous.next_pass = mat
		else:
			mesh.material_override = mat
		previous = mat
		_layers.append({"material": mat, "geoset": g, "layer": layer})
	mesh.visible = previous != null

func _texture(dir: String, file: Variant) -> Texture2D:
	if file == null:
		return null
	var path := String(file)
	return load(path if path.begins_with("res://") else dir + path) as Texture2D

func _process(delta: float) -> void:
	var dt := delta * speed_scale
	_clock += dt
	if _running:
		_time = minf(_time + dt, _length)
	for e in _emitters:
		e.update(_seq, _time, _prev_time, dt, _clock, global_transform, _running)
	if not _running:
		for e in _emitters:
			if e.is_alive(_clock):
				return
		finished.emit()
		if free_when_finished:
			queue_free()
		else:
			set_process(false)
		return
	_prev_time = _time
	_update_layers()
	if _time >= _length:
		if loop:
			_time = 0.0
			_prev_time = -1.0
			if _anim and _anim.current_animation != "":
				_anim.seek(0.0, true)
		else:
			_running = false

func _update_layers() -> void:
	for entry in _layers:
		var g: Dictionary = entry["geoset"]
		var layer: Dictionary = entry["layer"]
		var mat: ShaderMaterial = entry["material"]
		var color := MdxFx.vector(g["color"], _seq, _time, _hz, 3)
		var alpha := MdxFx.scalar(g["alpha"], _seq, _time, _hz) * MdxFx.scalar(layer["alpha"], _seq, _time, _hz)
		mat.set_shader_parameter("tint", Color(color[0], color[1], color[2], alpha))
		if MdxFx.is_animated(layer["uv"]):
			var uv := MdxFx.vector(layer["uv"], _seq, _time, _hz, 2)
			mat.set_shader_parameter("uv_offset", Vector2(uv[0], uv[1]))
