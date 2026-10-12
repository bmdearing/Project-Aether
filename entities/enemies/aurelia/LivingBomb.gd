extends Node3D
class_name LivingBomb
## Aurelia's Living Bomb, planted in a player a Fire Golem has knocked into
## the air: it rides them, a ring on the floor filling as the fuse burns,
## then explodes on them.

const FUSE := 3.0
const RADIUS := 2.5
const COLOR := Color(1.0, 0.45, 0.12)

var damage := 20.0
var source: Enemy
var _player: Player
var _ring: BossTelegraph
var _core: MeshInstance3D
var _age := 0.0
var _beep := 0.0

static func plant(player: Player, hit: float, from: Enemy) -> LivingBomb:
	var bomb := LivingBomb.new()
	bomb.damage = hit
	bomb.source = from
	bomb._player = player
	player.get_parent().add_child(bomb)
	bomb.global_position = player.global_position
	return bomb

func _ready() -> void:
	add_to_group("living_bomb")
	_ring = BossTelegraph.circle(self, global_position, RADIUS, FUSE, COLOR)
	# Embers circling the player's waist: what they see looking down.
	var orbit := SpellFx.emitter(self, 40, 0.6)
	orbit.position.y = 0.7
	orbit.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	orbit.emission_ring_axis = Vector3.UP
	orbit.emission_ring_radius = 0.8
	orbit.emission_ring_inner_radius = 0.6
	orbit.emission_ring_height = 0.1
	orbit.orbit_velocity_min = 1.2
	orbit.orbit_velocity_max = 1.6
	orbit.direction = Vector3.UP
	orbit.initial_velocity_min = 0.2
	orbit.initial_velocity_max = 0.6
	orbit.scale_amount_min = 0.08
	orbit.scale_amount_max = 0.18
	orbit.color_ramp = SpellFx.ramp(Color(1.0, 0.85, 0.5, 1.0), Color(COLOR, 0.9), 0.3)
	orbit.mesh = SpellFx.glow_quad()
	orbit.emitting = true
	# The seed itself, swelling as the fuse burns.
	_core = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.5
	_core.mesh = quad
	var mat := SpellFx.glow_material(COLOR, true, BaseMaterial3D.BILLBOARD_ENABLED)
	mat.vertex_color_use_as_albedo = false
	_core.material_override = mat
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.position.y = 0.7
	add_child(_core)

func _process(delta: float) -> void:
	_age += delta
	if not is_instance_valid(_player) or not _player.health.is_alive():
		queue_free()
		return
	global_position = _player.global_position
	if is_instance_valid(_ring):
		_ring.global_position = Vector3(global_position.x, global_position.y + BossTelegraph.FLOOR_LIFT, global_position.z)
	var f := clampf(_age / FUSE, 0.0, 1.0)
	_core.scale = Vector3.ONE * (1.0 + f * 2.0 + sin(_age * (8.0 + f * 20.0)) * 0.3)
	# Ticks quicken toward the blast.
	_beep -= delta
	if _beep <= 0.0:
		_beep = lerpf(0.6, 0.12, f)
		AureliaSfx.play("spears_launch", global_position, -10.0, 1.6 + f)
	if _age >= FUSE:
		_explode()

func _explode() -> void:
	var parent := get_parent()
	var at := global_position
	SpellFx.flash(parent, at + Vector3.UP, COLOR, 5.0, 0.3)
	SpellFx.light_pop(parent, at + Vector3.UP * 1.5, COLOR, 4.0, 7.0, 0.45)
	SpellFx.shockwave(parent, at + Vector3.UP * 0.05, RADIUS + 1.0, COLOR, 0.3)
	SpellFx.burst(parent, at + Vector3.UP * 0.8, COLOR, 60, Vector2(5, 11), 0.7, Vector2(0.12, 0.3), 180.0, 2.0)
	SpellFx.ground_mark(parent, at, RADIUS, SpellFx.Mark.SCORCH, Color(0.08, 0.05, 0.04, 0.8), COLOR, 4.0, 1.2)
	SmokePuff.spawn(parent, at, 1.6, Color(0.25, 0.2, 0.18))
	AureliaSfx.play("bomb_explode", at, 6.0, 0.8)
	AureliaSfx.play("fire_wall_cast", at, 0.0, 1.2)
	AureliaAilments.hit(_player, damage, Constants.DamageType.FIRE, source)
	queue_free()
