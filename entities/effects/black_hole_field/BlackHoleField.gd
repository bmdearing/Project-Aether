extends Node3D
class_name BlackHoleField
## Black Hole: pulls enemies toward its centre and hits them every tick,
## each tick a fresh damage roll. All of the ability's damage comes from here.
##
## Visuals: a black event horizon hovering above the ground (black_hole.gdshader)
## inside a lens that bends the scene behind it (black_hole_lens), a tilted
## accretion disk (black_hole_disk), motes and streaks spiralling in from the
## edge of the pull, and a shadow vortex on the ground marking its reach
## (black_hole_vortex). It swells in on cast and collapses with a burst.

const DURATION := 2.5
const PULL_SPEED := 5.0  # m/s added toward the centre, strongest at the edge
const TICK_INTERVAL := 0.25

const CORE_SHADER := preload("res://shaders/black_hole.gdshader")
const LENS_SHADER := preload("res://shaders/black_hole_lens.gdshader")
const DISK_SHADER := preload("res://shaders/black_hole_disk.gdshader")
const VORTEX_SHADER := preload("res://shaders/black_hole_vortex.gdshader")
const CORE_HEIGHT := 1.2
const CORE_RADIUS := 0.45
const LENS_SCALE := 2.8
const DISK_INNER := 1.15
const DISK_OUTER := 4.0
const DISK_TILT := 0.6
const SWELL := 0.35
const COLLAPSE := 0.3
const MAX_INFLOW_RADIUS := 7.0
const LIGHT_ENERGY := 1.6

var _radius: float = 5.0
var _elapsed: float = 0.0
var _ticker: float = 0.0
var _ability: Ability
var _stat_sheet: StatSheet
var _source: Node
var _color: Color = Color(0.35, 0.15, 0.45)

@onready var core: MeshInstance3D = $Core

var _duration: float = DURATION
var _heart: Node3D
var _disk: MeshInstance3D
var _core_mat: ShaderMaterial
var _lens_mat: ShaderMaterial
var _disk_mat: ShaderMaterial
var _vortex_mat: ShaderMaterial
var _emitters: Array[CPUParticles3D] = []
var _light: OmniLight3D

func play(radius: float, color: Color, ability: Ability, stat_sheet: StatSheet, source: Node) -> void:
	_duration = DURATION * ability.get_duration_multiplier(stat_sheet)
	_radius = radius
	_ability = ability
	_stat_sheet = stat_sheet
	_source = source
	_color = color
	_build_visuals()

func _physics_process(delta: float) -> void:
	_elapsed += delta
	_animate()
	if _elapsed >= _duration:
		_burst()
		queue_free()
		return
	_ticker -= delta
	var should_tick := _ticker <= 0.0
	if should_tick:
		_ticker += TICK_INTERVAL
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		var to_center: Vector3 = global_position - enemy.global_position
		to_center.y = 0.0
		var dist := to_center.length()
		if dist - enemy.body_radius > _radius:
			continue
		# The dist<0.05 guard only matters for the pull math below (avoids
		# normalizing a near-zero vector) - an enemy pulled all the way to
		# the center should still keep taking damage, not go immune once
		# it arrives (caught by scratch_spells_test.gd: a same-position
		# enemy took zero damage across a full second of ticks).
		if dist >= 0.3:
			enemy.apply_pull(to_center.normalized() * PULL_SPEED * clampf(dist / 1.5, 0.3, 1.0))
		if should_tick and _ability and _stat_sheet:
			var hit := _ability.roll_damage(_stat_sheet)
			var damage: float = hit["final_damage"]
			enemy.take_damage(damage, _ability.damage_type)
			EventBus.damage_dealt.emit(_source, enemy, damage, _ability.damage_type, false, hit["is_critical"])

## ---- Visuals -----------------------------------------------------------------

func _build_visuals() -> void:
	var rim := _color.lightened(0.45)
	_heart = Node3D.new()
	_heart.position.y = CORE_HEIGHT
	add_child(_heart)

	core.reparent(_heart, false)
	core.position = Vector3.ZERO
	var sphere := SphereMesh.new()
	sphere.radius = CORE_RADIUS
	sphere.height = CORE_RADIUS * 2.0
	core.mesh = sphere
	_core_mat = ShaderMaterial.new()
	_core_mat.shader = CORE_SHADER
	_core_mat.set_shader_parameter("rim_color", rim)
	core.material_override = _core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var lens := MeshInstance3D.new()
	var lens_sphere := SphereMesh.new()
	lens_sphere.radius = CORE_RADIUS * LENS_SCALE
	lens_sphere.height = CORE_RADIUS * LENS_SCALE * 2.0
	lens.mesh = lens_sphere
	_lens_mat = ShaderMaterial.new()
	_lens_mat.shader = LENS_SHADER
	_lens_mat.set_shader_parameter("ring_color", rim)
	lens.material_override = _lens_mat
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_heart.add_child(lens)

	_disk = MeshInstance3D.new()
	_disk.mesh = _annulus(CORE_RADIUS * DISK_INNER, CORE_RADIUS * DISK_OUTER, 64)
	_disk.rotation = Vector3(DISK_TILT, 0.0, DISK_TILT * 0.4)
	_disk_mat = ShaderMaterial.new()
	_disk_mat.shader = DISK_SHADER
	_disk_mat.set_shader_parameter("hot", rim.lightened(0.5))
	_disk_mat.set_shader_parameter("cool", _color)
	_disk.material_override = _disk_mat
	_disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_heart.add_child(_disk)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * _radius * 2.0
	ground.mesh = plane
	ground.position.y = 0.04
	_vortex_mat = ShaderMaterial.new()
	_vortex_mat.shader = VORTEX_SHADER
	_vortex_mat.set_shader_parameter("tint", _color)
	ground.material_override = _vortex_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	_add_halo(rim)
	_add_inflow(rim)
	_heart.scale = Vector3.ONE * 0.05

## Soft violet glow behind the core and a dim light on the floor, so the
## hole reads in a dark room.
func _add_halo(rim: Color) -> void:
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * CORE_RADIUS * 7.0
	halo.mesh = quad
	var mat := _glow_material(Color(_color.lightened(0.15), 0.55))
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = false
	halo.material_override = mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_heart.add_child(halo)
	_light = OmniLight3D.new()
	_light.light_color = rim
	_light.light_energy = LIGHT_ENERGY
	_light.omni_range = minf(_radius, MAX_INFLOW_RADIUS)
	_heart.add_child(_light)

## Flat ring, UV.x around and UV.y inner -> outer, for the accretion disk.
func _annulus(inner: float, outer: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		var quad := [
			[Vector3(cos(a0) * inner, 0, sin(a0) * inner), Vector2(float(i) / segments, 0)],
			[Vector3(cos(a1) * inner, 0, sin(a1) * inner), Vector2(float(i + 1) / segments, 0)],
			[Vector3(cos(a1) * outer, 0, sin(a1) * outer), Vector2(float(i + 1) / segments, 1)],
			[Vector3(cos(a0) * outer, 0, sin(a0) * outer), Vector2(float(i) / segments, 1)],
		]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(quad[idx][1])
			st.set_normal(Vector3.UP)
			st.add_vertex(quad[idx][0])
	return st.commit()

## Motes swirling in from the edge of the pull, and bright streaks falling
## into the core.
func _add_inflow(rim: Color) -> void:
	var reach := minf(_radius, MAX_INFLOW_RADIUS)
	var motes := _ring_emitter(110, 1.1, reach * 0.95, reach * 0.6)
	motes.position.y = 0.6
	motes.emission_ring_height = 1.4
	motes.radial_accel_min = -reach * 2.2
	motes.radial_accel_max = -reach * 1.6
	motes.tangential_accel_min = 3.0
	motes.tangential_accel_max = 5.0
	motes.gravity = Vector3(0, 0.6, 0)
	motes.scale_amount_min = 0.25
	motes.scale_amount_max = 0.55
	motes.scale_amount_curve = _shrink_curve()
	motes.color_ramp = _ramp(Color(_color.lightened(0.2), 0.0), Color(rim, 0.9))
	var quad := QuadMesh.new()
	quad.material = _glow_material(Color.WHITE)
	motes.mesh = quad

	var streaks := _ring_emitter(28, 0.55, CORE_RADIUS * 4.0, CORE_RADIUS * 2.0)
	streaks.position.y = CORE_HEIGHT
	streaks.emission_ring_height = 0.6
	streaks.radial_accel_min = -30.0
	streaks.radial_accel_max = -22.0
	streaks.tangential_accel_min = 6.0
	streaks.tangential_accel_max = 10.0
	streaks.particle_flag_align_y = true
	streaks.scale_amount_curve = _shrink_curve()
	streaks.color_ramp = _ramp(Color(rim, 0.0), Color(rim.lightened(0.5), 1.0))
	var streak := BoxMesh.new()
	streak.size = Vector3(0.025, 0.35, 0.025)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	streak.material = mat
	streaks.mesh = streak

func _ring_emitter(amount: int, lifetime: float, outer: float, inner: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = outer
	p.emission_ring_inner_radius = inner
	p.direction = Vector3.UP
	p.spread = 10.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.3
	p.gravity = Vector3.ZERO
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	_emitters.append(p)
	return p

func _glow_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	mat.albedo_texture = GlowTexture.radial(Vector2(0.25, 0.6))
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	return mat

func _ramp(from: Color, peak: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, Color(peak, 0.0))
	g.add_point(0.6, peak)
	return g

func _shrink_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 1.0))
	c.add_point(Vector2(1, 0.2))
	return c

## Swells in with a slight overshoot, collapses at the end with the disk
## flaring as it goes.
func _animate() -> void:
	if _heart == null:
		return
	var left := _duration - _elapsed
	var size: float
	if _elapsed < SWELL:
		var t := _elapsed / SWELL
		size = sin(t * PI * 0.5) * (1.0 + 0.25 * sin(t * PI))
	elif left < COLLAPSE:
		size = clampf(left / COLLAPSE, 0.0, 1.0)
		size *= size
	else:
		size = 1.0 + sin(_elapsed * 6.0) * 0.03
	_heart.scale = Vector3.ONE * maxf(size, 0.01)
	var flare := 1.0 + (1.0 - clampf(left / COLLAPSE, 0.0, 1.0)) * 2.5
	_disk_mat.set_shader_parameter("intensity", flare * 1.8)
	_core_mat.set_shader_parameter("glow", flare)
	var fade := clampf(minf(_elapsed / SWELL, left / COLLAPSE), 0.0, 1.0)
	_vortex_mat.set_shader_parameter("fade", fade)
	_lens_mat.set_shader_parameter("fade", fade)
	if _light:
		_light.light_energy = LIGHT_ENERGY * fade * flare
	_disk.rotate_object_local(Vector3.UP, 0.02)
	if left < COLLAPSE:
		for p in _emitters:
			p.emitting = false

## The collapse: a flash and a ring of sparks thrown outward. Lives on after
## the field frees itself.
func _burst() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var burst := Node3D.new()
	parent.add_child(burst)
	burst.global_position = global_position + Vector3.UP * CORE_HEIGHT
	var rim := _color.lightened(0.45)
	var sparks := CPUParticles3D.new()
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = 40
	sparks.lifetime = 0.55
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	sparks.gravity = Vector3.ZERO
	sparks.initial_velocity_min = 5.0
	sparks.initial_velocity_max = 9.0
	sparks.damping_min = 8.0
	sparks.damping_max = 12.0
	sparks.scale_amount_min = 0.12
	sparks.scale_amount_max = 0.25
	sparks.scale_amount_curve = _shrink_curve()
	sparks.color_ramp = _ramp(Color(rim.lightened(0.6), 1.0), Color(rim, 0.8))
	var quad := QuadMesh.new()
	quad.material = _glow_material(Color.WHITE)
	sparks.mesh = quad
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.add_child(sparks)
	sparks.emitting = true
	var flash := MeshInstance3D.new()
	var flash_quad := QuadMesh.new()
	flash_quad.size = Vector2.ONE * 3.0
	flash.mesh = flash_quad
	var flash_mat := _glow_material(Color(rim.lightened(0.4), 0.9))
	flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_mat.vertex_color_use_as_albedo = false
	flash.material_override = flash_mat
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.add_child(flash)
	var tween := burst.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 1.8, 0.25).from(Vector3.ONE * 0.2)
	tween.tween_property(flash_mat, "albedo_color:a", 0.0, 0.25)
	tween.chain().tween_interval(0.4)
	tween.chain().tween_callback(burst.queue_free)
