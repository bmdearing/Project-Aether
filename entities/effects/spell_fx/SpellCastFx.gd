class_name SpellCastFx
## Per-spell flourishes for spells whose cast is otherwise just the range
## ring (PlayerAbilityCast._play_range_effect / _flash_ring): what each one
## looks like on the ground and in the air, built from SpellFx parts.

const FROST := Color(0.6, 0.85, 1.0)
const ROT_DARK := Color(0.07, 0.03, 0.09, 0.75)
const ROT_GLOW := Color(0.55, 0.85, 0.35)
const SPARK := Color(1.0, 0.92, 0.45)
const WARCRY := Color(1.0, 0.75, 0.3)
const SHOUT := Color(0.95, 0.35, 0.2)
const PALE := Color(0.88, 0.95, 1.0)
const DUST := Color(0.45, 0.4, 0.35, 0.6)

## at: the spell's centre on the ground. caster: the player, for spells that
## play around them.
static func play(ability_id: String, parent: Node, at: Vector3, radius: float, color: Color) -> void:
	match ability_id:
		"ice_pulse":
			_ice_pulse(parent, at, radius)
		"entropic_decay":
			_entropic_decay(parent, at, radius, color)
		"static_discharge", "stormcall", "booming_blade":
			_crackle(parent, at, radius)
		"battle_cry":
			_battle_cry(parent, at, radius)
		"intimidating_shout":
			_intimidating_shout(parent, at, radius)
		"seismic_cry":
			_seismic_cry(parent, at, radius)
		"purge":
			_purge(parent, at)
		"blink":
			_blink(parent, at)
		"frost_armor":
			_frost_armor(parent, at)

static func _ice_pulse(parent: Node, at: Vector3, radius: float) -> void:
	SpellFx.ground_mark(parent, at, radius * 0.9, SpellFx.Mark.FROST, Color(0.7, 0.85, 0.95, 0.35), Color(0.85, 0.95, 1.0, 0.8), 3.0, 1.5)
	SpellFx.light_pop(parent, at + Vector3.UP, FROST, 2.5, radius * 1.4, 0.45)
	_outward_ring(parent, at, radius, Color(FROST, 0.55), 40, 0.45, Vector2(0.4, 0.9), false)
	SpellFx.shards(parent, at + Vector3.UP * 0.3, FROST.lightened(0.2), 18, Vector2(radius * 1.2, radius * 2.0), Vector2(0.05, 0.12), 0.6, 80.0)

static func _entropic_decay(parent: Node, at: Vector3, radius: float, color: Color) -> void:
	SpellFx.ground_mark(parent, at, radius * 0.95, SpellFx.Mark.ROT, ROT_DARK, ROT_GLOW, 4.5, 2.5)
	SpellFx.light_pop(parent, at + Vector3.UP, color.lightened(0.3), 1.8, radius * 1.3, 0.6)
	_outward_ring(parent, at, radius, Color(0.12, 0.05, 0.16, 0.8), 46, 0.6, Vector2(0.8, 1.6), false)
	# Spores drifting up off the rot.
	var spores := SpellFx.emitter(parent, 40, 2.2)
	spores.global_position = at + Vector3.UP * 0.1
	spores.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	spores.emission_sphere_radius = radius * 0.7
	spores.direction = Vector3.UP
	spores.spread = 25.0
	spores.initial_velocity_min = 0.3
	spores.initial_velocity_max = 0.9
	spores.scale_amount_min = 0.06
	spores.scale_amount_max = 0.14
	spores.color_ramp = SpellFx.ramp(Color(ROT_GLOW, 0.0), Color(ROT_GLOW.lerp(color.lightened(0.4), 0.5), 0.9), 0.3)
	spores.mesh = SpellFx.glow_quad()
	spores.one_shot = true
	spores.explosiveness = 0.6
	spores.emitting = true
	SpellFx.free_after(spores, 2.6)

static func _crackle(parent: Node, at: Vector3, radius: float) -> void:
	SpellFx.light_pop(parent, at + Vector3.UP, SPARK, 3.0, maxf(radius, 3.0) * 1.3, 0.25)
	SpellFx.burst(parent, at + Vector3.UP * 0.4, SPARK, 26, Vector2(4.0, 8.0), 0.3, Vector2(0.04, 0.09), 90.0, -9.0)
	SpellFx.ground_mark(parent, at, minf(radius, 3.0) * 0.6, SpellFx.Mark.CRACKS, Color(0.04, 0.04, 0.05, 0.5), SPARK, 2.0, 0.4)

static func _battle_cry(parent: Node, at: Vector3, radius: float) -> void:
	SpellFx.light_pop(parent, at + Vector3.UP * 1.2, WARCRY, 2.5, radius, 0.5)
	# Embers rising round the caster, kept below eye level.
	var embers := SpellFx.emitter(parent, 36, 1.1)
	embers.global_position = at + Vector3.UP * 0.1
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	embers.emission_ring_axis = Vector3.UP
	embers.emission_ring_radius = 1.4
	embers.emission_ring_inner_radius = 0.9
	embers.emission_ring_height = 0.1
	embers.direction = Vector3.UP
	embers.spread = 12.0
	embers.initial_velocity_min = 1.2
	embers.initial_velocity_max = 2.4
	embers.scale_amount_min = 0.06
	embers.scale_amount_max = 0.14
	embers.color_ramp = SpellFx.ramp(Color(WARCRY, 0.0), Color(WARCRY.lightened(0.3), 1.0))
	embers.mesh = SpellFx.glow_quad()
	embers.one_shot = true
	embers.explosiveness = 0.7
	embers.emitting = true
	SpellFx.free_after(embers, 1.5)
	_outward_ring(parent, at, radius, Color(WARCRY, 0.35), 30, 0.4, Vector2(0.15, 0.3), true)

static func _intimidating_shout(parent: Node, at: Vector3, radius: float) -> void:
	SpellFx.light_pop(parent, at + Vector3.UP, SHOUT, 1.6, radius, 0.4)
	_outward_ring(parent, at, radius, DUST, 34, 0.55, Vector2(0.6, 1.2), false)
	_outward_ring(parent, at, radius * 0.9, Color(SHOUT, 0.45), 24, 0.45, Vector2(0.15, 0.3), true)
	parent.get_tree().create_timer(0.12, false).timeout.connect(func() -> void:
		if is_instance_valid(parent):
			SpellFx.shockwave(parent, at, radius * 0.8, SHOUT, 0.4))

static func _seismic_cry(parent: Node, at: Vector3, radius: float) -> void:
	SpellFx.ground_mark(parent, at, radius * 0.75, SpellFx.Mark.CRACKS, Color(0.03, 0.025, 0.02, 0.85), Color(0.8, 0.35, 0.12, 0.7), 3.5, 0.35)
	_outward_ring(parent, at, radius, DUST, 44, 0.7, Vector2(0.7, 1.5), false)
	var rock := Color(0.3, 0.26, 0.22)
	var debris := SpellFx.shards(parent, at, rock, 22, Vector2(3.0, 6.0), Vector2(0.06, 0.16), 0.8, 60.0, false)
	debris.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	debris.emission_ring_axis = Vector3.UP
	debris.emission_ring_radius = radius * 0.6
	debris.emission_ring_inner_radius = 1.2
	debris.emission_ring_height = 0.05

static func _purge(parent: Node, at: Vector3) -> void:
	SpellFx.light_pop(parent, at + Vector3.UP * 1.2, PALE, 2.5, 6.0, 0.6)
	var motes := SpellFx.emitter(parent, 50, 1.2)
	motes.global_position = at
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	motes.emission_ring_axis = Vector3.UP
	motes.emission_ring_radius = 1.2
	motes.emission_ring_inner_radius = 0.6
	motes.emission_ring_height = 0.2
	motes.direction = Vector3.UP
	motes.spread = 5.0
	motes.initial_velocity_min = 2.5
	motes.initial_velocity_max = 4.0
	motes.tangential_accel_min = 1.0
	motes.tangential_accel_max = 2.0
	motes.scale_amount_min = 0.05
	motes.scale_amount_max = 0.12
	motes.color_ramp = SpellFx.ramp(Color(PALE, 0.0), Color(PALE, 1.0), 0.2)
	motes.mesh = SpellFx.glow_quad()
	motes.one_shot = true
	motes.explosiveness = 0.5
	motes.emitting = true
	SpellFx.free_after(motes, 1.6)

static func _blink(parent: Node, at: Vector3) -> void:
	var chest := at + Vector3.UP * 1.0
	SpellFx.flash(parent, chest, Color(PALE, 0.7), 2.2, 0.25)
	SpellFx.light_pop(parent, chest, PALE, 2.0, 5.0, 0.3)
	SpellFx.burst(parent, chest, PALE, 24, Vector2(2.0, 4.5), 0.4, Vector2(0.04, 0.1), 180.0, 0.0)

static func _frost_armor(parent: Node, at: Vector3) -> void:
	SpellFx.light_pop(parent, at + Vector3.UP, FROST, 2.0, 5.0, 0.4)
	_outward_ring(parent, at, 2.2, Color(FROST, 0.5), 24, 0.45, Vector2(0.3, 0.6), false)

## A puff ring racing outward along the ground with the shockwave: mist,
## dust or miasma (additive for light, mixed for dark).
static func _outward_ring(parent: Node, at: Vector3, radius: float, color: Color, amount: int, lifetime: float, size: Vector2, additive: bool) -> void:
	var p := SpellFx.emitter(parent, amount, lifetime)
	p.global_position = at + Vector3.UP * 0.25
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.6
	p.emission_ring_inner_radius = 0.3
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 5.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.5
	p.radial_accel_min = radius * 5.0
	p.radial_accel_max = radius * 6.5
	p.damping_min = radius * 1.5
	p.damping_max = radius * 2.0
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	p.scale_amount_curve = SpellFx.curve(0.5, 1.4)
	p.color_ramp = SpellFx.ramp(Color(color, 0.0), color, 0.15)
	p.mesh = SpellFx.glow_quad(additive)
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = true
	SpellFx.free_after(p, lifetime + 0.3)

## A light mist ring racing out from an impact.
static func mist_ring(parent: Node, at: Vector3, radius: float, color: Color) -> void:
	_outward_ring(parent, at, radius, color, 36, 0.55, Vector2(0.5, 1.1), true)
