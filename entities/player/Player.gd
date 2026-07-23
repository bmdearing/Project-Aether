extends CharacterBody2D
class_name Player
## Vertical slice player: movement + component wiring only. Animation,
## hitboxes, and input-driven combat are left as TODOs for the first
## Claude Code implementation pass - this establishes the composition
## pattern other entities should follow.

@export var move_speed: float = 220.0
@export var stat_sheet: StatSheet
@export var equipped_weapon: Weapon

@onready var health: HealthComponent = $HealthComponent
@onready var ward: WardComponent = $WardComponent
@onready var parry_handler: ParryRiposteHandler = $ParryRiposteHandler

var fate_board: FateBoard

func _ready() -> void:
	if stat_sheet == null:
		stat_sheet = StatSheet.new()
	fate_board = FateBoard.new()
	GameState.player_stat_sheet = stat_sheet
	GameState.fate_board = fate_board

func _physics_process(_delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir * move_speed
	move_and_slide()

	if Input.is_action_just_pressed("parry"):
		parry_handler.start_parry_window()
