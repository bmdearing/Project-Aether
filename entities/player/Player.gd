extends CharacterBody3D
class_name Player
## True first-person controller. Camera lives in the Head node; a
## WeaponSocket under the camera is where a viewmodel (hands + weapon mesh)
## will attach once art exists. Melee weight (Pillar 2) is communicated
## through camera shake / animation / hitstop on the viewmodel, NOT through
## seeing the player's body swing - there isn't one, by design.

@export var move_speed: float = 6.0
@export var sprint_speed: float = 9.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0035
@export var max_look_up_deg: float = 89.0
@export var stat_sheet: StatSheet
@export var equipped_weapon: Weapon

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_socket: Node3D = $Head/Camera3D/WeaponSocket
@onready var health: HealthComponent = $HealthComponent
@onready var ward: WardComponent = $WardComponent
@onready var parry_handler: ParryRiposteHandler = $ParryRiposteHandler

var fate_board: FateBoard
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	if stat_sheet == null:
		stat_sheet = StatSheet.new()
	fate_board = FateBoard.new()
	GameState.player_stat_sheet = stat_sheet
	GameState.fate_board = fate_board
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		var clamped_x: float = clamp(head.rotation.x, deg_to_rad(-max_look_up_deg), deg_to_rad(max_look_up_deg))
		head.rotation.x = clamped_x

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var speed := sprint_speed if Input.is_action_pressed("sprint") else move_speed
	# Movement is relative to where the body (not the camera pitch) is facing,
	# so looking up/down doesn't tilt movement into the floor or sky.
	var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed

	move_and_slide()

	if Input.is_action_just_pressed("parry"):
		parry_handler.start_parry_window()
