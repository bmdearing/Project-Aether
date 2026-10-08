extends Area3D
class_name GoldPickup
## Visible Gold drop, replacing the old instant "Gold silently appears
## in your pocket the moment the enemy dies" grant - user-requested
## ("gold drops"). Auto-pickup on touch, same convention as
## LootPickup.gd (placeholder art: a small spinning coin, no real art).
## Spawned by Enemy.gd on death instead of directly incrementing
## GameState.gold.

const ROTATE_SPEED := 3.0
const BOB_SPEED := 2.5
const BOB_HEIGHT := 0.1
const COIN_COLOR := Color(0.95, 0.8, 0.25)

@export var amount: int = 0

@onready var mesh: MeshInstance3D = $MeshInstance3D

var _time: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COIN_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat

## Only the coin spins and bobs; the pickup stays where it was put.
func _process(delta: float) -> void:
	_time += delta
	mesh.rotate_y(ROTATE_SPEED * delta)
	mesh.position.y = sin(_time * BOB_SPEED) * BOB_HEIGHT

func _on_body_entered(body: Node3D) -> void:
	if amount <= 0 or not (body is Player):
		return
	GameState.gold += amount
	EventBus.gold_picked_up.emit(amount)
	queue_free()
