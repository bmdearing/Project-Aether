extends Area3D
class_name PiercingBolt
## Straight-line bolt that pierces, hitting each enemy once (_hit_enemies).
## Player-cast only.

@export var speed: float = 22.0
@export var lifetime: float = 2.0

var damage_amount: float = 0.0
var damage_type: Constants.DamageType = Constants.DamageType.KINETIC
var source: Node
var is_critical: bool = false
var ability: Ability  # rolls its statuses on each enemy hit

## Thunder Sweep: travels flat along the ground, riding over slopes and
## stopping only at walls; max_distance > 0 ends the bolt after that far.
var follow_ground: bool = false
var max_distance: float = 0.0

var _hit_enemies: Array[Enemy] = []
var _travelled: float = 0.0

const GROUND_OFFSET := 0.3
const WALL_NORMAL_Y := 0.6

@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	if mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Constants.DAMAGE_TYPE_COLOR.get(damage_type, Color.WHITE).lightened(0.25)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = mat

## Moves by ray-checked steps: enemies along the step are hit (so a fast
## bolt can't skip past one between frames), walls and floors stop it.
func _physics_process(delta: float) -> void:
	var step := -global_transform.basis.z * speed * delta
	if follow_ground:
		step.y = 0.0
	var space := get_world_3d().direct_space_state
	var from := global_position
	var exclude: Array[RID] = []
	if not is_instance_valid(source):
		source = null  # the shooter left (scene change, death); hits still land, unattributed
	if source is CollisionObject3D:
		exclude.append(source.get_rid())
	for i in 8:
		var query := PhysicsRayQueryParameters3D.create(from, from + step, 1)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var collider: Object = hit["collider"]
		if collider is Enemy:
			_hit(collider)
		elif collider is StaticBody3D and not (follow_ground and hit["normal"].y > WALL_NORMAL_Y):
			queue_free()
			return
		exclude.append(hit["rid"])
	global_position = from + step
	if follow_ground:
		_snap_to_ground(space)
	_travelled += step.length()
	if max_distance > 0.0 and _travelled >= max_distance:
		queue_free()

func _snap_to_ground(space: PhysicsDirectSpaceState3D) -> void:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, global_position + Vector3.DOWN * 3.0, 1)
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit and hit["collider"] is StaticBody3D:
		global_position.y = hit["position"].y + GROUND_OFFSET

func _on_body_entered(body: Node3D) -> void:
	var enemy := body as Enemy
	if enemy:
		_hit(enemy)

func _hit(enemy: Enemy) -> void:
	if _hit_enemies.has(enemy) or not enemy.health.is_alive():
		return
	_hit_enemies.append(enemy)
	enemy.take_damage(damage_amount, damage_type)
	if enemy.stance:
		enemy.stance.apply_attack_stance_damage(damage_amount, damage_type)
	EventBus.damage_dealt.emit(source, enemy, damage_amount, damage_type, false, is_critical)
	if ability:
		ability.apply_statuses(enemy, source, damage_amount)
