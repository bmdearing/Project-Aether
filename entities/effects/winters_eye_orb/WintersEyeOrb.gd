extends Node3D
class_name WintersEyeOrb
## Winter's Eye ("26 - Ability Staging Ground": "A slow-moving orb of
## frozen energy launched toward a target area. Continuously fires a
## spiral of icicles at nearby enemies as it travels. Detonates at end of
## duration, dealing burst Cold damage. Applies Chill on icicle hits.")
##
## "Shards" are approximated as periodic proximity damage+Chill ticks to
## enemies near the orb's CURRENT position while it travels, not literal
## spawned sub-projectiles - a scoped-down interpretation given the size
## of everything else in this pass, not a doc-accuracy compromise (the
## doc doesn't specify shards as separate physical projectiles either,
## just "fires... at nearby enemies").
##
## Patch v3.8b: faster/shorter/wider-reaching per the brief's own new
## constants (was TRAVEL_SPEED 3.5/ICICLE_RADIUS 3.0/MAX_LIFETIME 6.0,
## unbounded hits per tick) - also caps each tick to the MAX_SHARDS_PER_
## TICK nearest enemies instead of hitting every enemy in radius at once,
## and spins the mesh while traveling for a visible "spiral" read.

const ORB_SPEED := 8.0
const SHARD_INTERVAL := 0.3
const SHARD_RADIUS := 6.0
const MAX_SHARDS_PER_TICK := 3
const ICICLE_DAMAGE_PERCENT := 0.2
const MAX_DURATION := 3.0  # also a safety net if travel somehow never reaches _target
const SPIN_SPEED := 12.0  # rad/s, purely cosmetic

var _target: Vector3
var _ability: Ability
var _stat_sheet: StatSheet
var _source: Node
var _shard_ticker: float = 0.0
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
	if dist < 0.3 or _elapsed >= MAX_DURATION:
		_detonate()
		return
	global_position += to_target.normalized() * min(ORB_SPEED * delta, dist)
	mesh.rotate_y(SPIN_SPEED * delta)

	_shard_ticker -= delta
	if _shard_ticker <= 0.0:
		_shard_ticker += SHARD_INTERVAL
		_fire_shards()

func _fire_shards() -> void:
	var candidates: Array[Enemy] = []
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		if global_position.distance_to(enemy.global_position) <= SHARD_RADIUS:
			candidates.append(enemy)
	candidates.sort_custom(func(a: Enemy, b: Enemy): return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position))
	for enemy in candidates.slice(0, MAX_SHARDS_PER_TICK):
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
