class_name BossFx
## Spell visuals and sounds for boss abilities (BossBrain and the Pinnacle
## bosses), built from SpellFx parts and coloured by damage type: a charge
## at the hand while an ability winds up, an element-specific impact where
## it lands, auras on hazard pools, charge trails, summon gates, pull
## vortices and the phase roar. Sounds come from SoundLib's boss_* slots.
## Everything spawned here frees itself or rides a node that does.

const ENTROPIC := Constants.DamageType.ENTROPIC

static func color_of(damage_type: int) -> Color:
	return Constants.DAMAGE_TYPE_COLOR.get(damage_type, Color(1.0, 0.35, 0.2))

## Ability colours read on dark floors: the darker types are lifted.
static func glow_of(damage_type: int) -> Color:
	match damage_type:
		ENTROPIC: return Color(0.78, 0.42, 1.0)
		Constants.DamageType.FIRE: return Color(1.0, 0.45, 0.15)
		Constants.DamageType.KINETIC, Constants.DamageType.PIERCING: return Color(0.95, 0.8, 0.55)
	return color_of(damage_type).lightened(0.15)

static func sound(stream: AudioStream, at: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	AudioManager.play_at(stream, at, volume_db, pitch)

static func pick(arr: Array[AudioStream]) -> AudioStream:
	return SoundLib.pick_random(arr)

static func cast_sound(damage_type: int) -> AudioStream:
	return pick(SoundLib.library.boss_void_cast if damage_type == ENTROPIC else SoundLib.library.boss_spell_cast)

static func impact_sound(damage_type: int) -> AudioStream:
	var lib := SoundLib.library
	match damage_type:
		Constants.DamageType.FIRE: return pick(lib.boss_fire)
		Constants.DamageType.COLD: return pick(lib.boss_frost)
		Constants.DamageType.LIGHTNING: return pick(lib.boss_shock)
		ENTROPIC: return pick(lib.boss_void_burst)
	return pick(lib.boss_heavy_impact)

## ---- Wind-up --------------------------------------------------------------

## A glow gathering at the caster's hand over `seconds`, motes drawn into it,
## then a pop as the spell leaves.
static func charge(caster: Node3D, at: Vector3, damage_type: int, seconds: float, with_sound: bool = true) -> void:
	if seconds <= 0.05 or not caster.is_inside_tree():
		return
	var color := glow_of(damage_type)
	var root := Node3D.new()
	caster.add_child(root)
	root.global_position = at
	var orb := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.9
	orb.mesh = quad
	var mat := SpellFx.glow_material(color, true, BaseMaterial3D.BILLBOARD_ENABLED)
	mat.vertex_color_use_as_albedo = false
	orb.material_override = mat
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(orb)
	var motes := SpellFx.emitter(root, 28, 0.55)
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	motes.emission_sphere_radius = 1.4
	motes.radial_accel_min = -9.0
	motes.radial_accel_max = -6.0
	motes.scale_amount_min = 0.05
	motes.scale_amount_max = 0.12
	motes.color_ramp = SpellFx.ramp(Color(color, 0.0), Color(color.lightened(0.4), 1.0), 0.5)
	motes.mesh = SpellFx.glow_quad()
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.0
	light.omni_range = 4.0
	root.add_child(light)
	var tween := root.create_tween().set_parallel(true)
	tween.tween_property(orb, "scale", Vector3.ONE * 1.6, seconds).from(Vector3.ONE * 0.2)
	tween.tween_property(light, "light_energy", 2.5, seconds)
	tween.chain().tween_callback(func() -> void:
		if root.is_inside_tree():
			SpellFx.flash(caster.get_parent(), root.global_position, color, 2.2, 0.2)
		root.queue_free())
	if with_sound:
		sound(cast_sound(damage_type), at, -4.0)

## ---- Impacts --------------------------------------------------------------

## Where a ground ability lands: a ring, a flash, light, and the element's
## own debris and ground mark.
static func impact(parent: Node, at: Vector3, radius: float, damage_type: int, loud: bool = true) -> void:
	var color := glow_of(damage_type)
	var mid := at + Vector3.UP * 0.6
	SpellFx.shockwave(parent, at + Vector3.UP * 0.05, radius, color, 0.35)
	SpellFx.flash(parent, mid, color, minf(radius * 1.2, 6.0), 0.25)
	SpellFx.light_pop(parent, at + Vector3.UP * 1.5, color, 3.0, radius + 3.0, 0.4)
	var scale := clampf(radius / 3.0, 0.6, 2.0)
	match damage_type:
		Constants.DamageType.FIRE:
			SpellFx.burst(parent, mid, color, int(30 * scale), Vector2(3, 8), 0.7, Vector2(0.1, 0.24), 70.0, 2.0)
			SpellFx.ground_mark(parent, at, radius, SpellFx.Mark.SCORCH, Color(0.08, 0.05, 0.04, 0.8), Color(1.0, 0.45, 0.1), 4.0, 1.2)
			SmokePuff.spawn(parent, at, scale, Color(0.25, 0.22, 0.2))
		Constants.DamageType.COLD:
			SpellFx.shards(parent, mid, Color(0.75, 0.92, 1.0), int(16 * scale), Vector2(3, 7))
			SpellFx.ground_mark(parent, at, radius, SpellFx.Mark.FROST, Color(0.7, 0.85, 0.95, 0.6), Color(0.85, 0.97, 1.0), 4.0, 1.5)
			SpellCastFx.mist_ring(parent, at, radius, Color(0.8, 0.9, 1.0))
		Constants.DamageType.LIGHTNING:
			LightningArc.spawn(parent, at + Vector3(randf_range(-1, 1), 12.0, randf_range(-1, 1)), at, color, 2.0)
			SpellFx.burst(parent, mid, color, int(24 * scale), Vector2(4, 9), 0.35, Vector2(0.04, 0.1), 160.0, -10.0)
			SpellFx.ground_mark(parent, at, radius, SpellFx.Mark.CRACKS, Color(0.1, 0.1, 0.12, 0.6), color, 2.5, 0.5)
		ENTROPIC:
			_void_burst(parent, at, radius, color)
		_:
			SpellFx.shards(parent, mid, Color(0.45, 0.4, 0.35), int(14 * scale), Vector2(3, 6), Vector2(0.08, 0.2), 0.8, 60.0, false)
			SpellFx.ground_mark(parent, at, radius, SpellFx.Mark.CRACKS, Color(0.12, 0.1, 0.08, 0.7), color, 3.0, 0.4)
			SmokePuff.spawn(parent, at, scale, Color(0.55, 0.5, 0.42))
	if loud:
		sound(impact_sound(damage_type), at, 0.0)
		if radius >= 4.0:
			sound(pick(SoundLib.library.boss_heavy_impact), at, -6.0, 0.85)

## The void tears open and snaps shut: dark motes pulled in, then flung out.
static func _void_burst(parent: Node, at: Vector3, radius: float, color: Color) -> void:
	var mid := at + Vector3.UP * 0.8
	var inward := SpellFx.emitter(parent, 36, 0.4)
	inward.global_position = mid
	inward.one_shot = true
	inward.explosiveness = 0.8
	inward.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	inward.emission_sphere_radius = radius
	inward.radial_accel_min = -radius * 14.0
	inward.radial_accel_max = -radius * 10.0
	inward.scale_amount_min = 0.12
	inward.scale_amount_max = 0.3
	inward.color_ramp = SpellFx.ramp(Color(color, 0.0), Color(color.lightened(0.3), 1.0), 0.4)
	inward.mesh = SpellFx.glow_quad()
	inward.emitting = true
	SpellFx.free_after(inward, 0.8)
	SpellFx.burst(parent, mid, color, 30, Vector2(4, 9), 0.6, Vector2(0.1, 0.25), 180.0, 0.0)
	SpellFx.ground_mark(parent, at, radius, SpellFx.Mark.ROT, Color(0.06, 0.02, 0.1, 0.85), color, 4.0, 1.5)
	SmokePuff.spawn(parent, at, clampf(radius / 3.0, 0.6, 2.0), Color(0.12, 0.05, 0.18))

## ---- Lingering ------------------------------------------------------------

## A hazard pool's look while it lasts, parented to its marker (freed with it).
static func hazard_aura(marker: Node3D, radius: float, damage_type: int) -> void:
	var color := glow_of(damage_type)
	var p := SpellFx.emitter(marker, int(clampf(radius * radius * 3.0, 20, 90)), 1.4)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius * 0.9
	p.emission_ring_inner_radius = 0.0
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 12.0
	p.mesh = SpellFx.glow_quad(damage_type != ENTROPIC)
	match damage_type:
		Constants.DamageType.FIRE:
			p.initial_velocity_min = 1.2
			p.initial_velocity_max = 2.6
			p.scale_amount_min = 0.35
			p.scale_amount_max = 0.7
			p.scale_amount_curve = SpellFx.curve(1.0, 0.1)
			p.color_ramp = SpellFx.ramp(Color(1.0, 0.85, 0.4, 0.0), Color(1.0, 0.4, 0.1, 0.9), 0.2)
		ENTROPIC:
			p.initial_velocity_min = 0.4
			p.initial_velocity_max = 1.2
			p.tangential_accel_min = 2.0
			p.tangential_accel_max = 3.0
			p.scale_amount_min = 0.3
			p.scale_amount_max = 0.6
			p.color_ramp = SpellFx.ramp(Color(0.05, 0.0, 0.08, 0.0), Color(0.18, 0.05, 0.28, 0.8), 0.3)
			var sparks := SpellFx.emitter(marker, 16, 1.0)
			sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			sparks.emission_ring_axis = Vector3.UP
			sparks.emission_ring_radius = radius * 0.85
			sparks.emission_ring_inner_radius = 0.0
			sparks.emission_ring_height = 0.1
			sparks.direction = Vector3.UP
			sparks.initial_velocity_min = 0.6
			sparks.initial_velocity_max = 1.6
			sparks.scale_amount_min = 0.05
			sparks.scale_amount_max = 0.1
			sparks.color_ramp = SpellFx.ramp(Color(color, 0.0), Color(color.lightened(0.3), 1.0))
			sparks.mesh = SpellFx.glow_quad()
		_:
			p.initial_velocity_min = 0.3
			p.initial_velocity_max = 0.9
			p.scale_amount_min = 0.2
			p.scale_amount_max = 0.45
			p.color_ramp = SpellFx.ramp(Color(color, 0.0), Color(color, 0.6), 0.3)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.2
	light.omni_range = minf(radius + 2.0, SpellFx.MAX_LIGHT_RANGE)
	light.position = Vector3.UP * 1.0
	marker.add_child(light)

## Sparks streaming off a charging boss; ends after `seconds`.
static func trail(body: Node3D, damage_type: int, seconds: float) -> void:
	var color := glow_of(damage_type)
	var p := SpellFx.emitter(body, 60, 0.45)
	p.local_coords = false
	p.position = Vector3.UP * 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.35
	p.color_ramp = SpellFx.ramp(Color(color.lightened(0.4), 0.9), Color(color, 0.6), 0.2)
	p.mesh = SpellFx.glow_quad()
	body.get_tree().create_timer(seconds, false).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.emitting = false
			SpellFx.free_after(p, 0.5))
	sound(pick(SoundLib.library.boss_whoosh), body.global_position, 0.0, 0.8)

## A gate opening where a summoned unit steps through.
static func summon_gate(parent: Node, at: Vector3, damage_type: int) -> void:
	var color := glow_of(damage_type)
	SpellFx.shockwave(parent, at + Vector3.UP * 0.05, 1.8, color, 0.5)
	SpellFx.flash(parent, at + Vector3.UP * 1.0, color, 3.0, 0.4)
	var column := SpellFx.emitter(parent, 40, 0.8)
	column.global_position = at
	column.one_shot = true
	column.explosiveness = 0.6
	column.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	column.emission_ring_axis = Vector3.UP
	column.emission_ring_radius = 0.9
	column.emission_ring_inner_radius = 0.6
	column.emission_ring_height = 0.1
	column.direction = Vector3.UP
	column.spread = 5.0
	column.initial_velocity_min = 3.0
	column.initial_velocity_max = 5.0
	column.scale_amount_min = 0.1
	column.scale_amount_max = 0.25
	column.color_ramp = SpellFx.ramp(Color(color.lightened(0.5), 1.0), Color(color, 0.8), 0.2)
	column.mesh = SpellFx.glow_quad()
	column.emitting = true
	SpellFx.free_after(column, 1.2)
	SmokePuff.spawn(parent, at, 0.8, Color(color.darkened(0.6), 1.0))
	sound(pick(SoundLib.library.boss_summon), at, -3.0)

## Motes spiralling into the pull's centre over `seconds`.
static func vortex(parent: Node, center: Vector3, radius: float, damage_type: int, seconds: float) -> void:
	var color := glow_of(damage_type)
	var p := SpellFx.emitter(parent, int(clampf(radius * 10.0, 40, 140)), 1.1)
	p.global_position = center + Vector3.UP * 0.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.8
	p.emission_ring_height = 1.0
	p.radial_accel_min = -radius * 2.0
	p.radial_accel_max = -radius * 1.4
	p.tangential_accel_min = 4.0
	p.tangential_accel_max = 6.0
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.4
	p.color_ramp = SpellFx.ramp(Color(color, 0.0), Color(color.lightened(0.2), 0.9), 0.5)
	p.mesh = SpellFx.glow_quad()
	parent.get_tree().create_timer(seconds, false).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.emitting = false
			SpellFx.free_after(p, 1.2))
	sound(pick(SoundLib.library.boss_void_cast if damage_type == ENTROPIC else SoundLib.library.boss_whoosh), center, 0.0, 0.7)

## Entering a new phase: a ring of force, a flare and the boss's roar.
static func phase_roar(boss: Node3D, damage_type: int, roar: AudioStream) -> void:
	var parent := boss.get_parent()
	var color := glow_of(damage_type)
	var at := boss.global_position
	SpellFx.shockwave(parent, at + Vector3.UP * 0.05, 9.0, color, 0.8)
	SpellFx.flash(parent, at + Vector3.UP * 1.6, color, 6.0, 0.5)
	SpellFx.light_pop(parent, at + Vector3.UP * 2.0, color, 5.0, 7.0, 1.2)
	SpellFx.burst(parent, at + Vector3.UP * 1.2, color, 60, Vector2(6, 12), 0.9, Vector2(0.12, 0.3), 100.0, -2.0)
	SmokePuff.spawn(parent, at, 1.6, Color(color.darkened(0.5), 1.0))
	sound(roar, at, 3.0)

## A boss bolt or volley shot: a bigger glow and a short trail.
static func dress_bolt(projectile: Node3D, damage_type: int) -> void:
	var color := glow_of(damage_type)
	var glow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.7
	glow.mesh = quad
	var mat := SpellFx.glow_material(color, true, BaseMaterial3D.BILLBOARD_ENABLED)
	mat.vertex_color_use_as_albedo = false
	glow.material_override = mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	projectile.add_child(glow)
	var tail := SpellFx.emitter(projectile, 24, 0.3)
	tail.local_coords = false
	tail.scale_amount_min = 0.12
	tail.scale_amount_max = 0.25
	tail.scale_amount_curve = SpellFx.curve(1.0, 0.0)
	tail.color_ramp = SpellFx.ramp(Color(color.lightened(0.3), 0.9), Color(color, 0.5), 0.1)
	tail.mesh = SpellFx.glow_quad()
