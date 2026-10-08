extends Node3D
class_name CaltropsField
## Caltrops: hits everything in the field every tick for DURATION seconds
## (a fresh damage roll each tick) and refreshes "slow", which expires
## shortly after an enemy steps out.

const DURATION := 5.0
const TICK_INTERVAL := 0.5
const TICK_DAMAGE_PERCENT := 0.3  # each tick = 30% of a fresh damage roll

var _radius: float = 4.0
var _ability: Ability
var _stat_sheet: StatSheet
var _source: Node
var _elapsed: float = 0.0
var _ticker: float = 0.0

@onready var patch: MeshInstance3D = $Patch

var _duration: float = DURATION
var _patch_mat: StandardMaterial3D
var _spike_mat: StandardMaterial3D

const SPIKES_PER_SQ_M := 1.6
const FADE_TIME := 0.5

func play(radius: float, color: Color, ability: Ability, stat_sheet: StatSheet, source: Node) -> void:
	_duration = DURATION * ability.get_duration_multiplier(stat_sheet)
	_radius = radius
	_ability = ability
	_stat_sheet = stat_sheet
	_source = source
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var c := color
	c.a = 0.18
	mat.albedo_color = c
	patch.material_override = mat
	patch.scale = Vector3(radius, 1.0, radius)
	_patch_mat = mat
	_scatter_spikes(radius)

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
		mm.set_instance_transform(i, Transform3D(basis, Vector3(cos(a) * r, 0.07, sin(a) * r)))
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
	if _patch_mat and fade < 1.0:
		_patch_mat.albedo_color.a = 0.18 * fade
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
		var hit := _ability.roll_damage(_stat_sheet)
		var damage: float = hit["final_damage"] * TICK_DAMAGE_PERCENT
		enemy.take_damage(damage, Constants.DamageType.PIERCING)
		EventBus.damage_dealt.emit(_source, enemy, damage, Constants.DamageType.PIERCING, false, hit["is_critical"])
		enemy.status_effects.apply_effect("slow", _source)
