extends Node3D
class_name CometImpact

## Fired when the falling mass lands - damage is dealt then, not on cast.
signal impacted
## Comet's cast VFX: a glowing mass of ice streaks down from above trailing
## frost, and smashes into the ground at the cast point: a flash, shards and
## spikes of ice bursting up, a ring of mist, the shockwave and a frost mark
## left behind. Molten Core's Fire variant burns instead (embers, scorch).

const FALL_HEIGHT := 9.0
const FALL_DURATION := 0.32
const FALL_SLANT := 3.0
const SPIKE_COUNT := 7
const STREAK_LENGTH := 3.2
const STREAK_SHADER := preload("res://shaders/spell_streak.gdshader")

@onready var ball: MeshInstance3D = $Ball

var fall_duration: float = FALL_DURATION
var _fire := false
var _core: Color
var _glow: Color
var _trail: CPUParticles3D
var _streak: MeshInstance3D
var _streak_back := Vector3.UP
var _radius := 0.0
var _fall_time := 0.0
var _falling := false

func play(radius: float, color: Color) -> void:
	_fire = color.r > color.b
	_core = Color(1.0, 0.55, 0.2) if _fire else Color(0.45, 0.72, 1.0)
	_glow = Color(1.0, 0.4, 0.1) if _fire else Color(0.55, 0.8, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _core
	mat.emission_enabled = true
	mat.emission = _core
	mat.emission_energy_multiplier = 0.7
	mat.rim_enabled = true
	mat.rim = 1.0
	ball.material_override = mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 2.4
	halo.mesh = quad
	var halo_mat := SpellFx.glow_material(Color(_glow, 0.8), true, BaseMaterial3D.BILLBOARD_ENABLED)
	halo_mat.vertex_color_use_as_albedo = false
	halo.material_override = halo_mat
	ball.add_child(halo)
	_trail = _make_trail()
	_add_streak(Vector3(FALL_SLANT, FALL_HEIGHT, -FALL_SLANT * 0.5).normalized())

	# Comes in at a slant so the streak reads from the player's eye line.
	_radius = radius
	_falling = true
	ball.visible = true
	_place_ball(0.0)

## A tapered glow trailing back up the fall path; frame-rate proof, unlike
## particles at this speed.
func _add_streak(back: Vector3) -> void:
	var streak := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.32
	cone.height = STREAK_LENGTH
	cone.radial_segments = 12
	cone.rings = 1
	streak.mesh = cone
	var mat := ShaderMaterial.new()
	mat.shader = STREAK_SHADER
	mat.set_shader_parameter("length", STREAK_LENGTH)
	mat.set_shader_parameter("color", _glow)
	streak.material_override = mat
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(streak)
	streak.top_level = true
	_streak = streak
	_streak_back = back

## Frost (or embers) shed behind the falling mass, left hanging in the air.
func _make_trail() -> CPUParticles3D:
	var p := SpellFx.emitter(ball, 60, 0.5)
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.6
	p.scale_amount_curve = SpellFx.curve(1.0, 0.2)
	p.color_ramp = SpellFx.ramp(Color(_core.lightened(0.4), 0.9), Color(_glow, 0.6), 0.2)
	p.mesh = SpellFx.glow_quad()
	p.emitting = true
	return p

func _on_impact(radius: float) -> void:
	ball.visible = false
	_streak.queue_free()
	_trail.emitting = false
	impacted.emit()
	AudioManager.play_at(SoundLib.pick_random(SoundLib.library.explosion), global_position)
	var parent := get_parent()
	var at := global_position
	SpellFx.shockwave(parent, at, radius, _glow, 0.4)
	SpellFx.flash(parent, at + Vector3.UP * 0.5, Color(_core.lightened(0.3), 1.0), 3.5, 0.25)
	SpellFx.light_pop(parent, at + Vector3.UP, _glow, 5.0, radius * 1.5, 0.5)
	if _fire:
		SpellFx.ground_mark(parent, at, radius * 0.7, SpellFx.Mark.SCORCH, Color(0.04, 0.03, 0.02, 0.75), Color(1.0, 0.4, 0.08), 3.5, 1.6)
		SpellFx.burst(parent, at + Vector3.UP * 0.3, _core, 40, Vector2(4.0, 9.0), 0.8, Vector2(0.06, 0.14), 70.0, -6.0)
	else:
		SpellFx.ground_mark(parent, at, radius * 0.75, SpellFx.Mark.FROST, Color(0.7, 0.85, 0.95, 0.4), Color(0.85, 0.95, 1.0, 0.8), 3.5, 1.6)
		SpellFx.shards(parent, at + Vector3.UP * 0.3, _core, 18, Vector2(4.0, 8.0), Vector2(0.07, 0.18), 0.8, 65.0)
		_spikes(radius)
	SpellCastFx.mist_ring(parent, at, radius, Color(_core, 0.55))
	get_tree().create_timer(1.2, true, false, true).timeout.connect(queue_free)

## Ice spikes punching up out of the impact and sinking back.
func _spikes(radius: float) -> void:
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.35, 1.2, 0.35)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.9, 1.0, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.5, 0.7)
	mat.roughness = 0.15
	mat.rim_enabled = true
	mesh.material = mat
	for i in SPIKE_COUNT:
		var spike := MeshInstance3D.new()
		spike.mesh = mesh
		spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * (i + randf() * 0.5) / SPIKE_COUNT
		var d := randf_range(0.3, 0.75) * minf(radius, 3.0)
		add_child(spike)
		spike.position = Vector3(cos(a) * d, 0.0, sin(a) * d)
		spike.rotation = Vector3(sin(a) * 0.5, randf() * TAU, -cos(a) * 0.5)
		var size := randf_range(0.6, 1.2)
		spike.scale = Vector3.ONE * 0.01
		var tween := spike.create_tween()
		tween.tween_property(spike, "scale", Vector3.ONE * size, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_interval(0.45)
		tween.tween_property(spike, "position:y", -0.8 * size, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

## The fall is driven here (not by a tween) so the streak never lags the ball.
func _process(delta: float) -> void:
	if not _falling:
		return
	_fall_time += delta
	var t := clampf(_fall_time / fall_duration, 0.0, 1.0)
	_place_ball(t)
	if t >= 1.0:
		_falling = false
		_on_impact(_radius)

func _place_ball(t: float) -> void:
	var start := Vector3(FALL_SLANT, FALL_HEIGHT, -FALL_SLANT * 0.5)
	ball.position = start.lerp(Vector3(0, 0.2, 0), t * t)
	ball.rotation = Vector3(4.0, 2.0, 1.0) * t
	if is_instance_valid(_streak):
		# The cone's narrow top points back up the path; its head sits on the ball.
		_streak.global_transform.basis = _align_y(_streak_back)
		_streak.global_position = ball.global_position + _streak_back * STREAK_LENGTH * 0.5

## A basis whose +Y points along dir.
static func _align_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
