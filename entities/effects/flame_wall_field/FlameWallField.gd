extends Node3D
class_name FlameWallField
## Flame Wall: Ignites each enemy once per pass through it
## (_ignited_this_pass), and separately hits everything inside every tick.
## Oriented perpendicular to the caster; width comes from the radius.

const DURATION := 6.0
const TICK_INTERVAL := 0.5
const SCORCH_CHANCE_PER_TICK := 0.35
const TICK_DAMAGE_PERCENT := 0.25
const WALL_HEIGHT := 2.2
const WALL_THICKNESS := 0.6

var _half_width: float = 2.5
var _ability: Ability
var _stat_sheet: StatSheet
var _source: Node
var _elapsed: float = 0.0
var _ticker: float = 0.0
var _inside: Array[Enemy] = []

@onready var area: Area3D = $Area3D

var _duration: float = DURATION

func play(radius: float, color: Color, ability: Ability, stat_sheet: StatSheet, source: Node, caster_position: Vector3) -> void:
	_duration = DURATION * ability.get_duration_multiplier(stat_sheet)
	_half_width = max(radius, 1.5)
	_ability = ability
	_stat_sheet = stat_sheet
	_source = source

	# look_at() points local -Z at the target, which puts local X (the
	# box's WIDTH axis) perpendicular to the caster direction - exactly
	# the "wall standing between caster and target" orientation wanted.
	var flat_caster_pos := Vector3(caster_position.x, global_position.y, caster_position.z)
	if global_position.distance_to(flat_caster_pos) > 0.01:
		look_at(flat_caster_pos, Vector3.UP)

	# Own copy: the scene's shape resource is shared by every wall.
	var shape := BoxShape3D.new()
	shape.size = Vector3(_half_width * 2.0, WALL_HEIGHT, WALL_THICKNESS)
	var collider := area.get_node("CollisionShape3D") as CollisionShape3D
	collider.shape = shape
	collider.position = Vector3(0, WALL_HEIGHT * 0.5, 0)
	_build_visuals(color)

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	area.monitoring = true

func _on_body_entered(body: Node3D) -> void:
	var enemy := body as Enemy
	if enemy == null or _inside.has(enemy):
		return
	_inside.append(enemy)
	# Ignite's burn is a share of the hit that caused it, so roll one.
	var hit := _ability.roll_damage(_stat_sheet)
	_ability.apply_statuses(enemy, _source, hit["final_damage"])

func _on_body_exited(body: Node3D) -> void:
	var enemy := body as Enemy
	if enemy:
		_inside.erase(enemy)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	_animate()
	if _elapsed >= _duration:
		queue_free()
		return
	_ticker -= delta
	if _ticker > 0.0:
		return
	_ticker += TICK_INTERVAL
	if _ability == null or _stat_sheet == null:
		return
	for enemy in _inside.duplicate():
		if not is_instance_valid(enemy):
			_inside.erase(enemy)
			continue
		var hit := _ability.roll_damage(_stat_sheet)
		var damage: float = hit["final_damage"] * TICK_DAMAGE_PERCENT
		enemy.take_damage(damage, _ability.damage_type)
		EventBus.damage_dealt.emit(_source, enemy, damage, _ability.damage_type, false, hit["is_critical"])
		# Standing in the fire builds Scorch.
		enemy.status_effects.try_apply("scorch", _source, 0.0, SCORCH_CHANCE_PER_TICK)

## ---- Visuals -----------------------------------------------------------------

const FLAME_SHADER := preload("res://shaders/spell_flame.gdshader")
const RISE := 0.25
const GUTTER := 0.5
## Fire palette, and Frost Wall's cold one: hot, mid, cool, ember light.
const FIRE := [Color(1.0, 0.78, 0.38), Color(1.0, 0.42, 0.08), Color(0.45, 0.06, 0.02), Color(1.0, 0.5, 0.15)]
const FROST := [Color(0.85, 0.97, 1.0), Color(0.35, 0.7, 1.0), Color(0.05, 0.15, 0.45), Color(0.5, 0.8, 1.0)]

var _flames: Node3D
var _flame_mats: Array[ShaderMaterial] = []
var _emitters: Array[CPUParticles3D] = []
var _light: OmniLight3D

## An elliptical tube of flame (deep enough to read from any angle), a
## glowing ember line on the ground, rising embers and smoke, and a light.
func _build_visuals(color: Color) -> void:
	var palette: Array = FROST if color.b > color.r else FIRE
	_flames = Node3D.new()
	add_child(_flames)
	for layer in 2:
		var mi := MeshInstance3D.new()
		var depth := WALL_THICKNESS * (0.5 if layer == 0 else 0.25)
		mi.mesh = SpellFx.tube(1.0, 0.85, WALL_HEIGHT * (1.0 if layer == 0 else 0.75), 10, 48, 1.0)
		mi.scale = Vector3(_half_width, 1.0, depth)
		var mat := ShaderMaterial.new()
		mat.shader = FLAME_SHADER
		mat.set_shader_parameter("hot", palette[0])
		mat.set_shader_parameter("mid", palette[1])
		mat.set_shader_parameter("cool", palette[2])
		var tiles := roundf(_half_width * 4.0)
		mat.set_shader_parameter("tiles", tiles)
		mat.set_shader_parameter("period", tiles)
		mat.set_shader_parameter("intensity", 0.75 if layer == 0 else 0.6)
		mat.set_shader_parameter("sway", 0.06)
		mat.set_shader_parameter("edge_soft", 0.2)
		mat.set_shader_parameter("end_fade", 0.5)
		mat.set_shader_parameter("fill", 0.18)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flames.add_child(mi)
		_flame_mats.append(mat)
	_flames.scale = Vector3(1.0, 0.05, 1.0)

	var line := SpellFx.ground_mark(self, global_position, 1.0, SpellFx.Mark.SCORCH, Color(0.04, 0.03, 0.02, 0.7), Color(palette[3], 1.0), _duration + GUTTER, _duration)
	line.scale = Vector3(_half_width * 1.1, 1.0, WALL_THICKNESS * 1.6)
	line.rotation = Vector3.ZERO

	var embers := SpellFx.emitter(self, int(18 * _half_width), 1.2)
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	embers.emission_box_extents = Vector3(_half_width, 0.2, WALL_THICKNESS * 0.4)
	embers.position.y = 0.4
	embers.direction = Vector3.UP
	embers.spread = 20.0
	embers.initial_velocity_min = 1.5
	embers.initial_velocity_max = 3.0
	embers.tangential_accel_min = -1.0
	embers.tangential_accel_max = 1.0
	embers.scale_amount_min = 0.04
	embers.scale_amount_max = 0.09
	embers.color_ramp = SpellFx.ramp(Color(palette[0], 1.0), Color(palette[3], 1.0), 0.3)
	embers.mesh = SpellFx.glow_quad()
	embers.emitting = true
	_emitters.append(embers)

	var smoke := SpellFx.emitter(self, int(5 * _half_width), 1.8)
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	smoke.emission_box_extents = Vector3(_half_width * 0.9, 0.1, 0.1)
	smoke.position.y = WALL_HEIGHT * 0.85
	smoke.direction = Vector3.UP
	smoke.spread = 15.0
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 1.2
	smoke.scale_amount_min = 0.7
	smoke.scale_amount_max = 1.3
	smoke.scale_amount_curve = SpellFx.curve(0.5, 1.5)
	var smoke_color := Color(0.06, 0.05, 0.05, 0.45) if palette == FIRE else Color(0.75, 0.85, 0.95, 0.25)
	smoke.color_ramp = SpellFx.ramp(Color(smoke_color, 0.0), smoke_color, 0.3)
	smoke.mesh = SpellFx.glow_quad(false)
	smoke.emitting = true
	_emitters.append(smoke)

	_light = OmniLight3D.new()
	_light.light_color = palette[3]
	_light.omni_range = minf(_half_width * 2.0 + 2.0, SpellFx.MAX_LIGHT_RANGE)
	_light.position.y = 1.0
	add_child(_light)

## Rises out of the ground, flickers while it burns, gutters out at the end.
func _animate() -> void:
	if _flames == null:
		return
	var left := _duration - _elapsed
	_flames.scale.y = ease(clampf(_elapsed / RISE, 0.0, 1.0), 0.3)
	var burn := clampf(left / GUTTER, 0.0, 1.0)
	for mat in _flame_mats:
		mat.set_shader_parameter("burn", burn)
	_light.light_energy = (3.4 + sin(_elapsed * 17.0) * 0.3 + sin(_elapsed * 7.3) * 0.25) * burn * _flames.scale.y
	if left < GUTTER:
		for p in _emitters:
			p.emitting = false
