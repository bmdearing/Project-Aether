extends Node3D
class_name CaltropsField
## Caltrops: hits everything in the field every tick for DURATION seconds
## (a fresh damage roll each tick) and refreshes "slow", which expires
## shortly after an enemy steps out.

const DURATION := 5.0
const TICK_INTERVAL := 0.5
const TICK_DAMAGE_PERCENT := 0.3  # each tick = 30% of a fresh damage roll
## Overlapping fields share a per-enemy cooldown (HitCooldown).
const HIT_INTERVAL := 0.15

var _radius: float = 4.0
var _ability: Ability
var _stat_sheet: StatSheet
var _source: Node
var _elapsed: float = 0.0
var _ticker: float = 0.0

@onready var patch: MeshInstance3D = $Patch

var _duration: float = DURATION
var _rim_mat: ShaderMaterial
var _drops: Array[Transform3D] = []
var _multimesh: MultiMesh
var _spike_mat: StandardMaterial3D

const SPIKES_PER_SQ_M := 1.6
const FADE_TIME := 0.5

func play(radius: float, color: Color, ability: Ability, stat_sheet: StatSheet, source: Node) -> void:
	_duration = DURATION * ability.get_duration_multiplier(stat_sheet)
	_radius = radius
	_ability = ability
	_stat_sheet = stat_sheet
	_source = source
	_add_rim(radius)
	_scatter_spikes(radius)
	var parent := get_parent()
	SpellFx.shockwave(parent, global_position, radius, STEEL, 0.3)
	SpellCastFx.mist_ring(parent, global_position, radius, Color(0.45, 0.4, 0.35, 0.35))

## Small four-sided spikes strewn at random over the field.
func _scatter_spikes(radius: float) -> void:
	var spike := CylinderMesh.new()
	spike.top_radius = 0.0
	spike.bottom_radius = 0.07
	spike.height = 0.16
	spike.radial_segments = 4
	spike.rings = 1
	_spike_mat = StandardMaterial3D.new()
	_spike_mat.albedo_color = Color(0.55, 0.55, 0.6)
	_spike_mat.metallic = 0.8
	_spike_mat.roughness = 0.35
	_spike_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spike.material = _spike_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = spike
	mm.instance_count = int(PI * radius * radius * SPIKES_PER_SQ_M)
	for i in mm.instance_count:
		var r := radius * sqrt(randf())
		var a := randf() * TAU
		var basis := Basis.from_euler(Vector3(randf_range(-0.5, 0.5), randf() * TAU, randf_range(-0.5, 0.5)))
		var rest := Transform3D(basis, Vector3(cos(a) * r, 0.07, sin(a) * r))
		_drops.append(rest)
		mm.set_instance_transform(i, rest.translated(Vector3.UP * DROP_HEIGHT))
	_multimesh = mm
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _duration:
		queue_free()
		return
	var fade := clampf((_duration - _elapsed) / FADE_TIME, 0.0, 1.0)
	_drop_in()
	if _rim_mat and fade < 1.0:
		_rim_mat.set_shader_parameter("alpha", RIM_ALPHA * fade)
		_spike_mat.albedo_color.a = fade
	_ticker -= delta
	if _ticker > 0.0:
		return
	_ticker += TICK_INTERVAL
	if _ability == null or _stat_sheet == null:
		return
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		if enemy.distance_to_body(global_position) > _radius:
			continue
		if not HitCooldown.try_hit(&"caltrops", enemy, HIT_INTERVAL):
			continue
		var hit := _ability.roll_damage(_stat_sheet)
		var damage: float = hit["final_damage"] * TICK_DAMAGE_PERCENT
		enemy.take_damage(damage, Constants.DamageType.PIERCING)
		EventBus.damage_dealt.emit(_source, enemy, damage, Constants.DamageType.PIERCING, false, hit["is_critical"])
		enemy.status_effects.apply_effect("slow", _source)

## ---- Visuals -----------------------------------------------------------------

const RING_SHADER := preload("res://shaders/spell_ring.gdshader")
const STEEL := Color(0.75, 0.78, 0.85)
const RIM_ALPHA := 0.16
const DROP_HEIGHT := 1.2
const DROP_TIME := 0.25
const DROP_STAGGER := 0.25

## A faint steel rim marking the strewn area (the ring shader held still).
func _add_rim(radius: float) -> void:
	patch.visible = false
	var rim := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0 * 1.08
	rim.mesh = plane
	rim.position.y = 0.04
	_rim_mat = ShaderMaterial.new()
	_rim_mat.shader = RING_SHADER
	_rim_mat.set_shader_parameter("color", Color(0.55, 0.58, 0.65, 1.0))
	_rim_mat.set_shader_parameter("progress", 1.0 / 1.08)
	_rim_mat.set_shader_parameter("width", clampf(0.12 / radius, 0.01, 0.06))
	_rim_mat.set_shader_parameter("wake", 0.08)
	_rim_mat.set_shader_parameter("alpha", RIM_ALPHA)
	rim.material_override = _rim_mat
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)

## The spikes rain in over the first moments, each landing with a small
## bounce and a glint where it strikes.
func _drop_in() -> void:
	if _multimesh == null or _elapsed > DROP_TIME + DROP_STAGGER + 0.1:
		return
	for i in _drops.size():
		var start := DROP_STAGGER * float(i) / _drops.size()
		var t := clampf((_elapsed - start) / DROP_TIME, 0.0, 1.0)
		var fall := 1.0 - t * t
		var bounce := 0.0
		if t >= 1.0:
			var since := _elapsed - start - DROP_TIME
			bounce = maxf(0.0, sin(clampf(since / 0.12, 0.0, 1.0) * PI)) * 0.06
		_multimesh.set_instance_transform(i, _drops[i].translated(Vector3.UP * (fall * DROP_HEIGHT + bounce)))
	if _elapsed >= DROP_TIME and _elapsed - get_physics_process_delta_time() < DROP_TIME:
		SpellFx.burst(get_parent(), global_position + Vector3.UP * 0.1, STEEL, 20, Vector2(1.0, 3.0), 0.3, Vector2(0.03, 0.06), 70.0, -6.0).emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
