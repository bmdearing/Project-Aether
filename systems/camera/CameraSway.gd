extends Node
class_name CameraSway
## First-person camera feel, child of the player's Camera3D: roll/pitch lag
## behind mouse movement, plus a walking bob. Kept off Camera3D.position on
## purpose - PlayerMeleeAttack's hit shake tweens that property from a value
## it captures when the shake starts, so writing it here every frame would
## fight the tween. Bob uses the camera's own v_offset/h_offset instead, and
## sway uses rotation (which nothing else touches on the Camera3D itself -
## pitch lives on the Head node).

@export var sway_amount: float = 0.003     # radians of roll per pixel of mouse movement
@export var sway_speed: float = 8.0
@export var bob_amount: float = 0.025      # meters of vertical camera offset
@export var bob_speed: float = 12.0
@export var return_speed: float = 6.0
@export var max_sway: float = 0.06         # clamp on roll/pitch, radians

var _mouse_delta: Vector2 = Vector2.ZERO
var _target_rotation: Vector3 = Vector3.ZERO
var _current_rotation: Vector3 = Vector3.ZERO
var _bob_time: float = 0.0
var _camera: Camera3D
var _player: Player

func _ready() -> void:
	_camera = get_parent() as Camera3D
	_player = get_tree().get_first_node_in_group("player") as Player

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_delta += event.relative

func _process(delta: float) -> void:
	if _camera == null:
		return
	_target_rotation.z = clamp(-_mouse_delta.x * sway_amount, -max_sway, max_sway)
	_target_rotation.x = clamp(-_mouse_delta.y * sway_amount * 0.5, -max_sway, max_sway)
	_mouse_delta = Vector2.ZERO
	_current_rotation = _current_rotation.lerp(_target_rotation, clamp(sway_speed * delta, 0.0, 1.0))
	_camera.rotation.z = _current_rotation.z
	_camera.rotation.x = _current_rotation.x

	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		return
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	if speed > 0.5 and _player.is_on_floor():
		_bob_time += delta * bob_speed
		_camera.v_offset = sin(_bob_time) * bob_amount
		_camera.h_offset = cos(_bob_time * 0.5) * bob_amount * 0.5
	else:
		_bob_time = 0.0
		var t: float = clamp(return_speed * delta, 0.0, 1.0)
		_camera.v_offset = lerpf(_camera.v_offset, 0.0, t)
		_camera.h_offset = lerpf(_camera.h_offset, 0.0, t)
