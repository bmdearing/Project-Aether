extends Node3D
class_name StormCloud
## Thunderstorm's cloud: a dark, churning puff layer over the player as wide
## as the spell's radius, lit from inside by flickers. It sits HEIGHT above
## the player, lower under a ceiling. PlayerAbilityCast._tick_thunderstorm()
## creates it, keeps it on the player and resizes it; bolts start from it.

const HEIGHT := 4.2
const CEILING_GAP := 0.7
const MIN_HEIGHT := 2.6

var _player: Node3D
var _radius := 4.0
var _puffs: CPUParticles3D
var _core: CPUParticles3D
var _flicker: OmniLight3D
var _flicker_timer := 0.0
var _height := HEIGHT
var _height_check := 0.0

func setup(player: Node3D, radius: float, color: Color) -> void:
	_player = player
	top_level = true
	_build(color)
	set_radius(radius)
	global_position = player.global_position + Vector3.UP * HEIGHT

func set_radius(radius: float) -> void:
	if is_equal_approx(radius, _radius) and _puffs:
		return
	_radius = radius
	if _puffs:
		_puffs.emission_box_extents = Vector3(radius * 0.75, 0.25, radius * 0.75)
		_puffs.amount = clampi(int(radius * 9.0), 24, 90)
		_core.emission_box_extents = Vector3(radius * 0.55, 0.15, radius * 0.55)

## A point inside the cloud for a bolt to leave from.
func bolt_origin() -> Vector3:
	var a := randf() * TAU
	var r := sqrt(randf()) * _radius * 0.6
	return global_position + Vector3(cos(a) * r, -0.2, sin(a) * r)

## Stops emitting and frees once the last puffs fade.
func dissipate() -> void:
	set_physics_process(false)
	_puffs.emitting = false
	_core.emitting = false
	_flicker.visible = false
	SpellFx.free_after(self, _puffs.lifetime)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		dissipate()
		return
	_height_check -= delta
	if _height_check <= 0.0:
		_height_check = 0.5
		_height = _clear_height()
	global_position = _player.global_position + Vector3.UP * _height
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		_flicker_timer = randf_range(0.25, 0.9)
		_flicker.position = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * _radius * 0.5
		_flicker.light_energy = randf_range(1.5, 3.0)
	_flicker.light_energy = maxf(_flicker.light_energy - delta * 12.0, 0.0)

func _clear_height() -> float:
	var from := _player.global_position + Vector3.UP * 1.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * (HEIGHT + CEILING_GAP - 1.5), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return HEIGHT
	return maxf((hit["position"] as Vector3).y - _player.global_position.y - CEILING_GAP, MIN_HEIGHT)

func _build(color: Color) -> void:
	_puffs = SpellFx.emitter(self, 40, 3.5)
	_puffs.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_puffs.direction = Vector3.RIGHT
	_puffs.spread = 180.0
	_puffs.flatness = 1.0
	_puffs.initial_velocity_min = 0.1
	_puffs.initial_velocity_max = 0.35
	_puffs.angular_velocity_min = -10.0
	_puffs.angular_velocity_max = 10.0
	_puffs.scale_amount_min = 1.4
	_puffs.scale_amount_max = 2.4
	_puffs.scale_amount_curve = SpellFx.curve(0.7, 1.0)
	_puffs.color_ramp = SpellFx.ramp(Color(0.16, 0.17, 0.22, 0.0), Color(0.2, 0.21, 0.27, 0.75), 0.3)
	var puff_quad := SpellFx.glow_quad(false)
	_puffs.mesh = puff_quad
	_puffs.preprocess = 2.0
	_puffs.emitting = true
	# Charged light moving through the underside.
	_core = SpellFx.emitter(self, 14, 0.8)
	_core.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_core.position.y = -0.25
	_core.scale_amount_min = 0.4
	_core.scale_amount_max = 0.9
	_core.color_ramp = SpellFx.ramp(Color(color, 0.0), Color(color.lightened(0.3), 0.35), 0.15)
	_core.mesh = SpellFx.glow_quad()
	_core.emitting = true
	_flicker = OmniLight3D.new()
	_flicker.light_color = color.lightened(0.4)
	_flicker.omni_range = 5.0
	_flicker.light_energy = 0.0
	_flicker.shadow_enabled = false
	add_child(_flicker)
