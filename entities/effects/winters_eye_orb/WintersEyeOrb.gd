extends Node3D
class_name WintersEyeOrb
## Winter's Eye ("26 - Ability Staging Ground": "A slow-moving orb of
## frozen energy launched toward a target area. Continuously fires a
## spiral of icicles at nearby enemies as it travels. Detonates at end of
## duration, dealing burst Cold damage. Applies Chill on icicle hits.")
##
## Icicles are real shards that fly from points circling the orb to the
## nearest enemies (MAX_SHARDS_PER_TICK per volley) and hit on arrival. It
## travels to the target, hovers, and detonates when its duration ends.
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
const ICICLE_DAMAGE_PERCENT := 0.35
const MAX_DURATION := 3.0  # also a safety net if travel somehow never reaches _target
const SPIN_SPEED := 12.0  # rad/s, purely cosmetic

var _target: Vector3
var _ability: Ability
var _stat_sheet: StatSheet
var _source: Node
var _shard_ticker: float = 0.0
var _elapsed: float = 0.0
var _detonated: bool = false
var _duration: float = MAX_DURATION
var _color: Color = Color.WHITE
var _spiral_angle: float = 0.0

const ICICLE_FLIGHT := 0.14
const SPIRAL_STEP := 2.4  # radians between consecutive icicle launch points
const DETONATE_MULTIPLIER := 2.0
const RANGE_EFFECT_SCENE := preload("res://entities/effects/ability_range_effect/AbilityRangeEffect.tscn")

@onready var mesh: MeshInstance3D = $MeshInstance3D

func play(_radius: float, color: Color, ability: Ability, stat_sheet: StatSheet, source: Node, target: Vector3) -> void:
	_target = target
	_ability = ability
	_stat_sheet = stat_sheet
	_source = source
	_color = color
	_duration = MAX_DURATION * ability.get_duration_multiplier(stat_sheet)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color.lightened(0.3)
	mesh.material_override = mat

func _physics_process(delta: float) -> void:
	if _detonated:
		return
	_elapsed += delta
	if _elapsed >= _duration:
		_detonate()
		return
	# Travels to the target, then hovers there until its duration ends.
	var to_target: Vector3 = _target - global_position
	var dist := to_target.length()
	if dist > 0.05:
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
		_launch_icicle(enemy)

## An icicle leaves from a point circling the orb (successive launches walk
## round it, reading as a spiral) and flies to the enemy; it hits on arrival.
func _launch_icicle(enemy: Enemy) -> void:
	_spiral_angle += SPIRAL_STEP
	var start := global_position + Vector3(cos(_spiral_angle), 0.25 * sin(_spiral_angle * 0.5), sin(_spiral_angle)) * 0.5
	var shard := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.07, 0.07, 0.55)
	shard.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _color.lightened(0.55)
	shard.material_override = mat
	shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(shard)
	shard.global_position = start
	var aim := enemy.global_position + Vector3.UP
	if start.distance_to(aim) > 0.05:
		shard.look_at(aim, Vector3.UP)
	var tween := shard.create_tween()
	tween.tween_property(shard, "global_position", aim, ICICLE_FLIGHT)
	tween.tween_callback(_icicle_hit.bind(enemy))
	tween.tween_callback(shard.queue_free)

func _icicle_hit(enemy: Enemy) -> void:
	if not is_instance_valid(enemy) or not enemy.health.is_alive() or _ability == null:
		return
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
		if global_position.distance_to(enemy.global_position) > _ability.get_radius(_stat_sheet):
			continue
		var hit := _ability.roll_damage(_stat_sheet)
		var damage: float = hit["final_damage"] * DETONATE_MULTIPLIER
		enemy.take_damage(damage, _ability.damage_type)
		EventBus.damage_dealt.emit(_source, enemy, damage, _ability.damage_type, false, hit["is_critical"])
		enemy.status_effects.apply_effect("chill", _source)
	var ring: AbilityRangeEffect = RANGE_EFFECT_SCENE.instantiate()
	get_parent().add_child(ring)
	ring.global_position = Vector3(global_position.x, _target.y + 0.05, global_position.z)
	ring.play(_ability.get_radius(_stat_sheet), _color.lightened(0.3))
	queue_free()
