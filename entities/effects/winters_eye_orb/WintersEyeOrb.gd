extends Node3D
class_name WintersEyeOrb
## Winter's Eye ("26 - Ability Staging Ground": "A slow-moving orb of
## frozen energy launched toward a target area. Continuously fires a
## spiral of icicles at nearby enemies as it travels. Detonates at end of
## duration, dealing burst Cold damage. Applies Chill on icicle hits.")
##
## "Icicles" are approximated as periodic proximity damage+Chill ticks to
## enemies near the orb's CURRENT position while it travels, not literal
## spawned sub-projectiles - a scoped-down interpretation given the size
## of everything else in this pass, not a doc-accuracy compromise (the
## doc doesn't specify icicles as separate physical projectiles either,
## just "fires... at nearby enemies").

const TRAVEL_SPEED := 3.5
const ICICLE_TICK_INTERVAL := 0.3
const ICICLE_RADIUS := 3.0
const ICICLE_DAMAGE_PERCENT := 0.2
const MAX_LIFETIME := 6.0  # safety net if travel somehow never reaches _target

var _target: Vector3
var _ability: Ability
var _stat_sheet: StatSheet
var _source: Node
var _icicle_ticker: float = 0.0
var _elapsed: float = 0.0
var _detonated: bool = false

@onready var mesh: MeshInstance3D = $MeshInstance3D

func play(_radius: float, color: Color, ability: Ability, stat_sheet: StatSheet, source: Node, target: Vector3) -> void:
	_target = target
	_ability = ability
	_stat_sheet = stat_sheet
	_source = source
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color.lightened(0.3)
	mesh.material_override = mat

func _physics_process(delta: float) -> void:
	if _detonated:
		return
	_elapsed += delta
	var to_target: Vector3 = _target - global_position
	var dist := to_target.length()
	if dist < 0.3 or _elapsed >= MAX_LIFETIME:
		_detonate()
		return
	global_position += to_target.normalized() * min(TRAVEL_SPEED * delta, dist)

	_icicle_ticker -= delta
	if _icicle_ticker <= 0.0:
		_icicle_ticker += ICICLE_TICK_INTERVAL
		_fire_icicles()

func _fire_icicles() -> void:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		if global_position.distance_to(enemy.global_position) > ICICLE_RADIUS:
			continue
		var hit := _ability.roll_damage(_stat_sheet)
		var damage: float = hit["final_damage"] * ICICLE_DAMAGE_PERCENT
		enemy.take_damage(damage, _ability.damage_type)
		EventBus.damage_dealt.emit(_source, enemy, damage, _ability.damage_type, false, hit["is_critical"])
		enemy.status_effects.apply_effect("chill", _source)

func _detonate() -> void:
	_detonated = true
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		if global_position.distance_to(enemy.global_position) > _ability.radius:
			continue
		var hit := _ability.roll_damage(_stat_sheet)
		var damage: float = hit["final_damage"]
		enemy.take_damage(damage, _ability.damage_type)
		EventBus.damage_dealt.emit(_source, enemy, damage, _ability.damage_type, false, hit["is_critical"])
	queue_free()
