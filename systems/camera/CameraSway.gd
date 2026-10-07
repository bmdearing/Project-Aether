extends Node
class_name CameraSway
## First-person camera feel, child of the player's Camera3D: roll/pitch lag
## behind mouse movement, a walking bob, a landing dip, and kick() impulses
## from melee swings and hits. Kept off Camera3D.position on
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
@export var kick_return_speed: float = 14.0
@export var land_dip_per_speed: float = 0.012  # meters of camera dip per m/s of landing speed
@export var max_land_dip: float = 0.14

var _mouse_delta: Vector2 = Vector2.ZERO
var _target_rotation: Vector3 = Vector3.ZERO
var _current_rotation: Vector3 = Vector3.ZERO
var _bob_time: float = 0.0
## Additive (pitch, yaw, roll) impulse from hits and swings, eased back to zero.
var _kick: Vector3 = Vector3.ZERO
var _land_dip: float = 0.0
var _was_on_floor: bool = true
var _last_fall_speed: float = 0.0
var _camera: Camera3D
var _player: Player

func _ready() -> void:
	_camera = get_parent() as Camera3D
	_player = get_tree().get_first_node_in_group("player") as Player

func kick(amount: Vector3) -> void:
	_kick += amount

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
	_kick = _kick.lerp(Vector3.ZERO, clamp(kick_return_speed * delta, 0.0, 1.0))
	_camera.rotation.z = _current_rotation.z + _kick.z
	_camera.rotation.x = _current_rotation.x + _kick.x
	_camera.rotation.y = _kick.y

	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		return
	var on_floor := _player.is_on_floor()
	if on_floor and not _was_on_floor:
		_land_dip = minf(_last_fall_speed * land_dip_per_speed, max_land_dip)
	_was_on_floor = on_floor
	_last_fall_speed = maxf(-_player.velocity.y, 0.0)
	_land_dip = lerpf(_land_dip, 0.0, clamp(kick_return_speed * 0.6 * delta, 0.0, 1.0))

	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	if speed > 0.5 and on_floor:
		_bob_time += delta * bob_speed * clampf(speed / 6.0, 0.6, 1.5)
		_camera.v_offset = sin(_bob_time) * bob_amount - _land_dip
		_camera.h_offset = cos(_bob_time * 0.5) * bob_amount * 0.5
	else:
		_bob_time = 0.0
		var t: float = clamp(return_speed * delta, 0.0, 1.0)
		_camera.v_offset = lerpf(_camera.v_offset + _land_dip, 0.0, t) - _land_dip
		_camera.h_offset = lerpf(_camera.h_offset, 0.0, t)
