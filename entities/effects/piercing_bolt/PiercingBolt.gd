extends Area3D
class_name PiercingBolt
## Straight-line traveling bolt that PIERCES - unlike entities/projectile/
## Projectile.gd (which queue_free()s on its first hit, shared with
## ordinary ranged weapon fire), this keeps traveling through its whole
## lifetime, damaging every NEW enemy it touches once each (tracked in
## _hit_enemies so a wide/slow bolt can't tick the same enemy twice while
## overlapping it). User request (2026-08-30): Cinder Lance and Thunder
## Javelin both "should pierce" / "work like Cinder Lance."
##
## Player-only for now (no enemy caster uses this) - source is always the
## casting Player, aimed from the camera along its forward direction.

@export var speed: float = 22.0
@export var lifetime: float = 2.0

var damage_amount: float = 0.0
var damage_type: Constants.DamageType = Constants.DamageType.KINETIC
var source: Node
var is_critical: bool = false
var applies_status_effects: Array[String] = []

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
	if source is CollisionObject3D:
		exclude.append(source.get_rid())
	for i in 8:
		var query := PhysicsRayQueryParameters3D.create(from, from + step)
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
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, global_position + Vector3.DOWN * 3.0)
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
	for effect_id in applies_status_effects:
		enemy.status_effects.apply_effect(effect_id, source, damage_amount)
