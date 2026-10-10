extends Node3D
class_name WintersEyeOrb
## Winter's Eye: an orb that travels to the target, hovers, and detonates
## when its duration ends. Each volley fires icicle shards at the
## MAX_SHARDS_PER_TICK nearest enemies; they hit on arrival.

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

@onready var mesh: MeshInstance3D = $MeshInstance3D

func play(_radius: float, color: Color, ability: Ability, stat_sheet: StatSheet, source: Node, target: Vector3) -> void:
	_target = target
	_ability = ability
	_stat_sheet = stat_sheet
	_source = source
	_color = color
	_duration = MAX_DURATION * ability.get_duration_multiplier(stat_sheet)
	_build_visuals()

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
		if enemy.distance_to_body(global_position) <= SHARD_RADIUS:
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
	shard.mesh = _icicle_mesh()
	shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(shard)
	shard.global_position = start
	var aim := enemy.global_position + Vector3.UP
	if start.distance_to(aim) > 0.05:
		shard.look_at(aim, Vector3.UP)
		shard.rotate_object_local(Vector3.RIGHT, -PI * 0.5)  # prism tip (+Y) leads
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
	_ability.apply_statuses(enemy, _source, damage)

func _detonate() -> void:
	_detonated = true
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		if enemy.distance_to_body(global_position) > _ability.get_radius(_stat_sheet):
			continue
		var hit := _ability.roll_damage(_stat_sheet)
		var damage: float = hit["final_damage"] * DETONATE_MULTIPLIER
		enemy.take_damage(damage, _ability.damage_type)
		EventBus.damage_dealt.emit(_source, enemy, damage, _ability.damage_type, false, hit["is_critical"])
		_ability.apply_statuses(enemy, _source, damage)
	_detonation_fx(_ability.get_radius(_stat_sheet))
	queue_free()

## ---- Visuals -----------------------------------------------------------------

const ICE := Color(0.6, 0.85, 1.0)
const ICE_CORE := Color(0.85, 0.96, 1.0)
const ORBIT_SHARDS := 3

static var _icicle: PrismMesh

## A glowing eye of ice: bright core in a cold halo, shards orbiting it,
## frost mist shed as it travels and a light.
func _build_visuals() -> void:
	var core := StandardMaterial3D.new()
	core.albedo_color = Color(0.55, 0.8, 1.0)
	core.emission_enabled = true
	core.emission = Color(0.4, 0.7, 1.0)
	core.emission_energy_multiplier = 0.8
	core.rim_enabled = true
	core.rim = 1.0
	core.roughness = 0.2
	mesh.material_override = core
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 1.8
	halo.mesh = quad
	var halo_mat := SpellFx.glow_material(Color(ICE, 0.7), true, BaseMaterial3D.BILLBOARD_ENABLED)
	halo_mat.vertex_color_use_as_albedo = false
	halo.material_override = halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	for i in ORBIT_SHARDS:
		var shard := MeshInstance3D.new()
		shard.mesh = _icicle_mesh()
		var a := TAU * i / ORBIT_SHARDS
		shard.position = Vector3(cos(a), 0.0, sin(a)) * 0.55
		shard.rotation = Vector3(0.4, -a, 0.0)
		shard.scale = Vector3.ONE * 0.7
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.add_child(shard)  # the orb mesh spins, carrying them round
	var mist := SpellFx.emitter(self, 40, 0.9)
	mist.local_coords = false
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	mist.emission_sphere_radius = 0.35
	mist.direction = Vector3.DOWN
	mist.spread = 60.0
	mist.initial_velocity_min = 0.2
	mist.initial_velocity_max = 0.6
	mist.scale_amount_min = 0.25
	mist.scale_amount_max = 0.5
	mist.scale_amount_curve = SpellFx.curve(0.6, 1.4)
	mist.color_ramp = SpellFx.ramp(Color(ICE, 0.0), Color(ICE, 0.35), 0.2)
	mist.mesh = SpellFx.glow_quad()
	mist.emitting = true
	var light := OmniLight3D.new()
	light.light_color = ICE
	light.light_energy = 1.6
	light.omni_range = 4.0
	add_child(light)

## A pointed shard of glowing ice along -Z, shared by every icicle.
func _icicle_mesh() -> PrismMesh:
	if _icicle == null:
		_icicle = PrismMesh.new()
		_icicle.size = Vector3(0.1, 0.6, 0.1)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = ICE_CORE
		_icicle.material = mat
	return _icicle

func _detonation_fx(radius: float) -> void:
	var parent := get_parent()
	var ground := Vector3(global_position.x, _target.y, global_position.z)
	SpellFx.shockwave(parent, ground, radius, ICE, 0.4)
	SpellFx.flash(parent, global_position, Color(ICE_CORE, 1.0), 3.0, 0.25)
	SpellFx.light_pop(parent, global_position, ICE, 5.0, radius * 1.4, 0.5)
	SpellFx.shards(parent, global_position, ICE_CORE, 22, Vector2(4.0, 8.0), Vector2(0.06, 0.15), 0.8, 180.0)
	SpellFx.ground_mark(parent, ground, radius * 0.8, SpellFx.Mark.FROST, Color(0.7, 0.85, 0.95, 0.35), Color(0.85, 0.95, 1.0, 0.8), 3.0, 1.5)
	SpellCastFx.mist_ring(parent, ground, radius, Color(ICE, 0.5))
