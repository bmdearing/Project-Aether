extends Area3D
class_name GoldPickup
## A Gold drop, collected on touch (same convention as LootPickup.gd).
## Shows a coin pile sized by amount resting on the floor; falls back to a
## spinning coin if the pile models are missing. Spawned by Enemy.gd on
## death and by chests.

const ROTATE_SPEED := 3.0
const BOB_SPEED := 2.5
const BOB_HEIGHT := 0.1
const COIN_COLOR := Color(0.95, 0.8, 0.25)
## Pile model by amount: the first threshold the amount is under, else large.
const PILE_THRESHOLDS := [[10, "gold_tiny"], [50, "gold_small"], [200, "gold_medium"]]

@export var amount: int = 0

@onready var mesh: MeshInstance3D = $MeshInstance3D

var _time: float = 0.0
var _pile: Node3D
var _settled := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var key := "gold_large"
	for step: Array in PILE_THRESHOLDS:
		if amount < int(step[0]):
			key = step[1]
			break
	_pile = LootPickup.item_model(key)
	if _pile:
		mesh.visible = false
		_pile.rotation.y = randf() * TAU
		_pile.scale = Vector3.ONE * float(LootPickup.ITEM_DROP_SCALE["gold"])
		_pile.position.y = -LootPickup.DEFAULT_HOVER
		add_child(_pile)
		# Fully metallic gold mirrors dark rooms and reads black.
		var gold := WeaponModelLibrary._flat(COIN_COLOR, 0.35, 0.45)
		for node in _pile.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		LootPickup._recolor(_pile, "gold", gold)
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COIN_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat

## The pile drops onto the floor once the spawner has set the position; the
## fallback coin spins and bobs.
func _process(delta: float) -> void:
	if _pile:
		if not _settled:
			_settled = true
			var from := global_position + Vector3.UP * 0.1
			var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * LootPickup.FLOOR_PROBE, 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if hit:
				_pile.global_position.y = (hit["position"] as Vector3).y
		return
	_time += delta
	mesh.rotate_y(ROTATE_SPEED * delta)
	mesh.position.y = sin(_time * BOB_SPEED) * BOB_HEIGHT

func _on_body_entered(body: Node3D) -> void:
	if amount <= 0 or not (body is Player):
		return
	GameState.gold += amount
	EventBus.gold_picked_up.emit(amount)
	queue_free()
