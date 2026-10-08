extends Node3D
class_name SparkCrawler
## Spark ground crawler. Re-targets the nearest enemy every frame and turns
## toward it at TURN_SPEED; wanders when nothing is within SEEK_RADIUS. Can
## hit the same enemy repeatedly, at most once per HIT_INTERVAL.

const MOVE_SPEED := 5.0
const TURN_SPEED := 3.0  # rad/s
const SEEK_RADIUS := 12.0
const LIFETIME := 4.0
const HIT_INTERVAL := 0.15
const HIT_RADIUS := 0.7
const WANDER_INTERVAL := 0.4
const WANDER_TURN_RANGE := 1.2  # max radians of random turn per wander tick

var heading: Vector3 = Vector3.FORWARD
var ability: Ability
var stat_sheet: StatSheet
var source: Node
var damage_multiplier: float = 1.0

var _hit_timers: Dictionary = {}  # Enemy -> float seconds remaining before it can be hit again
var _wander_timer: float = 0.0
var _wander_target: Vector3 = Vector3.FORWARD

@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	get_tree().create_timer(LIFETIME).timeout.connect(queue_free)
	if mesh and ability:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mesh.material_override = mat

func _physics_process(delta: float) -> void:
	for enemy in _hit_timers.keys():
		_hit_timers[enemy] = max(0.0, _hit_timers[enemy] - delta)

	var target := _find_nearest_enemy()
	var desired: Vector3 = heading
	if target:
		var to_target: Vector3 = target.global_position - global_position
		to_target.y = 0.0
		if to_target.length() > 0.05:
			desired = to_target.normalized()
	else:
		desired = _tick_wander(delta)
	heading = heading.lerp(desired, TURN_SPEED * delta).normalized()

	global_position += heading * MOVE_SPEED * delta
	if heading.length() > 0.01:
		look_at(global_position + heading, Vector3.UP)

	if ability == null or stat_sheet == null:
		return
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		if enemy.distance_to_body(global_position) > HIT_RADIUS:
			continue
		if _hit_timers.get(enemy, 0.0) > 0.0:
			continue
		_hit_timers[enemy] = HIT_INTERVAL
		var hit := ability.roll_damage(stat_sheet)
		var damage: float = hit["final_damage"] * damage_multiplier
		enemy.take_damage(damage, ability.damage_type)
		if enemy.stance:
			enemy.stance.apply_attack_stance_damage(damage, ability.damage_type)
		EventBus.damage_dealt.emit(source, enemy, damage, ability.damage_type, false, hit["is_critical"])
		ability.apply_statuses(enemy, source, damage)

func _find_nearest_enemy() -> Enemy:
	var nearest: Enemy = null
	var nearest_dist := SEEK_RADIUS
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	return nearest

## Picks a new random heading every WANDER_INTERVAL.
func _tick_wander(delta: float) -> Vector3:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = WANDER_INTERVAL
		var turn := randf_range(-WANDER_TURN_RANGE, WANDER_TURN_RANGE)
		_wander_target = heading.rotated(Vector3.UP, turn).normalized()
	return _wander_target
