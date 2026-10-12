extends Node3D
class_name ForbiddenFire
## Forbidden Fire: what an Entangled player hit by Aurelia's fire suffers.
## Amaterasu's black flame climbs the roots and burns DAMAGE_SHARE of the
## caster's hit every second for DURATION (Fire, as damage over time). A new
## trigger refreshes the burn rather than stacking it.

const DURATION := 4.0
const TICK := 0.5
## Per second, as a share of the source's ability hit.
const DAMAGE_SHARE := 0.8
const FLAME_SHADER := preload("res://shaders/black_flame.gdshader")
const VIOLET := Color(0.6, 0.15, 0.8)

var _player: Player
var _source: Node
var _per_tick := 0.0
var _left := DURATION
var _tick := TICK
var _flame: MeshInstance3D

static func ignite(p: Player, source: Node) -> void:
	var base := (source as Enemy).get_ability_base_damage() if source is Enemy else 20.0
	if p.status_effects:
		p.status_effects.apply_timed_effect("forbidden_fire", DURATION)
	for node in p.get_tree().get_nodes_in_group("forbidden_fire"):
		var burning := node as ForbiddenFire
		if burning._player == p:
			burning._left = DURATION
			burning._per_tick = maxf(burning._per_tick, base * DAMAGE_SHARE * TICK)
			return
	var fire := ForbiddenFire.new()
	fire._player = p
	fire._source = source
	fire._per_tick = base * DAMAGE_SHARE * TICK
	p.get_parent().add_child(fire)
	fire.global_position = p.global_position
	SpellFx.flash(fire.get_parent(), p.global_position + Vector3.UP, VIOLET, 4.0, 0.3)
	SmokePuff.spawn(fire.get_parent(), p.global_position, 1.0, Color(0.04, 0.0, 0.06))
	AureliaSfx.play("combo_forbidden_fire", p.global_position, 4.0)

func _ready() -> void:
	add_to_group("forbidden_fire")
	_flame = MeshInstance3D.new()
	_flame.mesh = SpellFx.tube(0.75, 0.35, 1.5, 8, 28, 0.8)
	var mat := ShaderMaterial.new()
	mat.shader = FLAME_SHADER
	mat.set_shader_parameter("tiles", 7.0)
	mat.set_shader_parameter("period", 7.0)
	mat.set_shader_parameter("fill", 0.34)
	_flame.material_override = mat
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flame)
	var embers := SpellFx.emitter(self, 30, 0.9)
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	embers.emission_ring_axis = Vector3.UP
	embers.emission_ring_radius = 0.8
	embers.emission_ring_inner_radius = 0.3
	embers.emission_ring_height = 0.1
	embers.direction = Vector3.UP
	embers.initial_velocity_min = 1.5
	embers.initial_velocity_max = 3.0
	embers.scale_amount_min = 0.06
	embers.scale_amount_max = 0.14
	embers.color_ramp = SpellFx.ramp(Color(0.05, 0.0, 0.08, 0.9), Color(0.03, 0.0, 0.05, 0.7), 0.3)
	embers.mesh = SpellFx.glow_quad(false)
	embers.emitting = true
	var light := OmniLight3D.new()
	light.light_color = VIOLET
	light.light_energy = 1.4
	light.omni_range = 4.0
	light.position.y = 1.0
	add_child(light)

func _process(delta: float) -> void:
	if not is_instance_valid(_player) or not _player.health.is_alive():
		queue_free()
		return
	global_position = _player.global_position
	_left -= delta
	_tick -= delta
	if _tick <= 0.0:
		_tick += TICK
		_player.take_damage(_per_tick * (1.0 - _player.get_dot_mitigation()), Constants.DamageType.FIRE, _source if is_instance_valid(_source) else null, Player.HitKind.DOT)
	if _left <= 0.0:
		set_process(false)
		var fade := create_tween()
		fade.tween_property(_flame, "scale", Vector3(1.0, 0.01, 1.0), 0.35)
		fade.tween_callback(queue_free)
