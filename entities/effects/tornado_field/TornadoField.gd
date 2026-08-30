extends Node3D
class_name TornadoField
## Tornado (Physical/Kinetic, user request 2026-08-30): "One cast makes a
## tornado that moves and hits enemies while they're in the area." Unlike
## every other ground effect in this project (Caltrops/Flame Wall/Black
## Hole), this one doesn't sit still - it drifts across the arena for its
## whole lifetime. Follow-up request (2026-08-30): "it wants to go up
## into enemies and not just wander randomly" - so movement is a seek
## toward the nearest living enemy within SEEK_RADIUS (steered gradually
## via STEER_RATE rather than snapping instantly, so it still reads as a
## drifting funnel rather than a homing missile), falling back to a
## slower random wander only while nothing is in range. Capped at
## TORNADO_MAX_ACTIVE concurrently by PlayerAbilityCast (see its own
## _try_cast() gate) - this scene just adds itself to the "tornado_field"
## group so that check has something to count.

const DURATION := 6.0
const TICK_INTERVAL := 0.4
const TICK_DAMAGE_PERCENT := 0.35
const MOVE_SPEED := 2.6
const SEEK_RADIUS := 14.0
const STEER_RATE := 4.0  # radians/sec heading can turn toward its target
const WANDER_REDIRECT_INTERVAL := 1.5

var _radius: float = 3.0
var _ability: Ability
var _stat_sheet: StatSheet
var _source: Node
var _elapsed: float = 0.0
var _ticker: float = 0.0
var _wander_timer: float = 0.0
var _heading: Vector3 = Vector3.FORWARD

@onready var funnel: MeshInstance3D = $Funnel

func play(radius: float, color: Color, ability: Ability, stat_sheet: StatSheet, source: Node) -> void:
	_radius = radius
	_ability = ability
	_stat_sheet = stat_sheet
	_source = source
	_pick_new_wander_heading()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var c := color
	c.a = 0.55
	mat.albedo_color = c
	funnel.material_override = mat
	funnel.scale = Vector3(radius, 1.0, radius)
	add_to_group("tornado_field")

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return

	_steer(delta)
	global_position += _heading * MOVE_SPEED * delta
	rotate_y(delta * 3.0)

	_ticker -= delta
	if _ticker > 0.0:
		return
	_ticker += TICK_INTERVAL
	if _ability == null or _stat_sheet == null:
		return
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		if global_position.distance_to(enemy.global_position) > _radius:
			continue
		var hit := _ability.roll_damage(_stat_sheet)
		var damage: float = hit["final_damage"] * TICK_DAMAGE_PERCENT
		enemy.take_damage(damage, _ability.damage_type)
		if enemy.stance:
			enemy.stance.apply_attack_stance_damage(damage, _ability.damage_type)
		EventBus.damage_dealt.emit(_source, enemy, damage, _ability.damage_type, false, hit["is_critical"])
		for effect_id in _ability.applies_status_effects:
			enemy.status_effects.apply_effect(effect_id, _source, damage)

## Nearest living enemy within SEEK_RADIUS steers the heading; otherwise
## falls back to a slower periodic random redirect so it still covers
## ground while hunting for a new target.
func _steer(delta: float) -> void:
	var target := _find_nearest_enemy()
	var desired: Vector3 = _heading
	if target:
		var to_target: Vector3 = target.global_position - global_position
		to_target.y = 0.0
		if to_target.length() > 0.05:
			desired = to_target.normalized()
	else:
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_pick_new_wander_heading()
		desired = _heading

	var current_angle := atan2(_heading.x, _heading.z)
	var desired_angle := atan2(desired.x, desired.z)
	var delta_angle := wrapf(desired_angle - current_angle, -PI, PI)
	var max_turn := STEER_RATE * delta
	current_angle += clamp(delta_angle, -max_turn, max_turn)
	_heading = Vector3(sin(current_angle), 0.0, cos(current_angle))

func _pick_new_wander_heading() -> void:
	_wander_timer = WANDER_REDIRECT_INTERVAL
	var angle := randf() * TAU
	_heading = Vector3(sin(angle), 0.0, cos(angle))

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
