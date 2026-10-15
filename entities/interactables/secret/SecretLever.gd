extends Node3D
class_name SecretLever
## A wall lever: walk up and press E to throw it. It springs back after a
## moment, so it can be thrown again.

signal pulled

const RESET_SEC := 1.2
const STONE := Color(0.3, 0.28, 0.26)
const BRASS := Color(0.85, 0.66, 0.3)

var _player_in_range := false
var _handle: Node3D
var _prompt: Label3D
var _busy := false

func _ready() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 1.2, 0.3)
	shape.shape = box
	shape.position.y = 0.6
	body.add_child(shape)
	body.add_child(_box(Vector3(0.5, 1.2, 0.3), Vector3(0, 0.6, 0), STONE))
	_handle = Node3D.new()
	_handle.position = Vector3(0, 1.0, 0.18)
	_handle.rotation_degrees.x = -40.0
	add_child(_handle)
	_handle.add_child(_box(Vector3(0.07, 0.6, 0.07), Vector3(0, 0.3, 0), BRASS))
	_handle.add_child(_box(Vector3(0.16, 0.12, 0.16), Vector3(0, 0.62, 0), BRASS))
	var glow := OmniLight3D.new()
	glow.light_color = BRASS
	glow.light_energy = 0.8
	glow.omni_range = 2.5
	glow.position = Vector3(0, 1.4, 0.4)
	add_child(glow)
	_prompt = Label3D.new()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.font_size = 40
	_prompt.outline_size = 8
	_prompt.position.y = 1.9
	_prompt.text = "Press E to pull"
	_prompt.visible = false
	add_child(_prompt)
	var area := Area3D.new()
	area.monitorable = false
	var reach := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.0
	reach.shape = sphere
	reach.position.y = 1.0
	area.add_child(reach)
	add_child(area)
	area.body_entered.connect(func(b: Node3D):
		if b is Player:
			_player_in_range = true
			GameSettings.refresh_interact_prompt(_prompt)
			_prompt.visible = not _busy)
	area.body_exited.connect(func(b: Node3D):
		if b is Player:
			_player_in_range = false
			_prompt.visible = false)

func _box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	mesh.material_override = mat
	return mesh

func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and not _busy and event.is_action_pressed("interact") and not AetherStyle.menu_open(get_tree()):
		get_viewport().set_input_as_handled()
		pull()

func pull() -> void:
	if _busy:
		return
	_busy = true
	_prompt.visible = false
	pulled.emit()
	var tween := create_tween()
	tween.tween_property(_handle, "rotation_degrees:x", 40.0, 0.15).set_trans(Tween.TRANS_BACK)
	tween.tween_interval(RESET_SEC)
	tween.tween_property(_handle, "rotation_degrees:x", -40.0, 0.4)
	tween.tween_callback(func():
		_busy = false
		_prompt.visible = _player_in_range)
