extends Node3D
class_name InfernoPillar
## Inferno's cast VFX: a column of fire bursts out of the ground at the cast
## point (spell_flame.gdshader on two tubes: a wide tapering blaze and a hot
## inner core), roars briefly and gutters out, leaving a scorch with cooling
## embers. A flash, light and embers sell the eruption; a ring marks the
## real reach, which is wider than the column. Purely visual, same
## damage-timing note as CometImpact.

const FLAME_SHADER := preload("res://shaders/spell_flame.gdshader")
const HEIGHT := 3.0
const RISE := 0.12
const HOLD := 0.45
const FADE := 0.4
const FIRE := Color(1.0, 0.45, 0.1)
const EMBER := Color(1.0, 0.6, 0.2)
const SMOKE := Color(0.08, 0.06, 0.05, 0.55)

func play(radius: float, _color: Color) -> void:
	var column_r := clampf(radius * 0.3, 0.5, 1.4)
	var height := HEIGHT * clampf(column_r / 1.2, 0.6, 1.0)
	var parent := get_parent()
	var at := global_position
	SpellFx.shockwave(parent, at, radius, FIRE, 0.4)
	SpellFx.ground_mark(parent, at, maxf(column_r * 1.9, radius * 0.6), SpellFx.Mark.SCORCH, Color(0.04, 0.03, 0.02, 0.75), Color(1.0, 0.4, 0.08, 1.0), 4.0, 2.0)
	SpellFx.flash(parent, at + Vector3.UP * 0.6, Color(1.0, 0.6, 0.25, 0.9), column_r * 4.0, 0.3)
	SpellFx.light_pop(parent, at + Vector3.UP * 1.2, FIRE, 4.0, radius * 1.2, RISE + HOLD + FADE)
	SpellFx.burst(parent, at + Vector3.UP * 0.3, EMBER, 30, Vector2(3.0, 7.0), 0.7, Vector2(0.05, 0.12), 50.0, -2.0)

	var mats: Array[ShaderMaterial] = []
	mats.append(_flame(column_r, column_r * 0.85, height, 6.0, 0.9))
	mats.append(_flame(column_r * 0.5, column_r * 0.35, height * 0.85, 4.0, 0.8))
	_embers(column_r, height)
	_smoke(column_r, height)

	scale = Vector3(1.0, 0.05, 1.0)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, RISE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(HOLD)
	tween.tween_method(func(b: float) -> void:
		for m in mats:
			m.set_shader_parameter("burn", b), 1.0, 0.0, FADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_interval(0.6)
	tween.tween_callback(queue_free)

func _flame(base_r: float, top_r: float, height: float, tiles: float, intensity: float) -> ShaderMaterial:
	var mi := MeshInstance3D.new()
	mi.mesh = SpellFx.tube(base_r, top_r, height, 14, 32, 0.8)
	var mat := ShaderMaterial.new()
	mat.shader = FLAME_SHADER
	mat.set_shader_parameter("tiles", tiles)
	mat.set_shader_parameter("period", tiles)
	mat.set_shader_parameter("intensity", intensity)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mat

func _embers(column_r: float, height: float) -> void:
	var p := SpellFx.emitter(self, 40, 1.3)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = column_r * 0.8
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = height * 0.8
	p.initial_velocity_max = height * 1.5
	p.damping_min = 1.0
	p.damping_max = 2.5
	p.tangential_accel_min = -2.0
	p.tangential_accel_max = 2.0
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.1
	p.color_ramp = SpellFx.ramp(Color(EMBER.lightened(0.4), 1.0), Color(EMBER, 1.0), 0.3)
	p.mesh = SpellFx.glow_quad()
	p.local_coords = false
	p.emitting = true
	get_tree().create_timer(RISE + HOLD, false).timeout.connect(func() -> void: p.emitting = false)

func _smoke(column_r: float, height: float) -> void:
	var p := SpellFx.emitter(self, 14, 1.6)
	p.position.y = height * 0.75
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = column_r * 0.6
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.scale_amount_min = column_r * 0.9
	p.scale_amount_max = column_r * 1.6
	p.scale_amount_curve = SpellFx.curve(0.5, 1.5)
	p.color_ramp = SpellFx.ramp(Color(SMOKE, 0.0), SMOKE, 0.3)
	p.mesh = SpellFx.glow_quad(false)
	p.local_coords = false
	p.emitting = true
	get_tree().create_timer(RISE + HOLD + FADE * 0.5, false).timeout.connect(func() -> void: p.emitting = false)
