extends Node3D
class_name SunExplosion
## The Fiery Sun hitting the ground (Ataras._sun_blast()): a white-hot flash,
## a fireball that swells and burns off, a column of fire rolling up into a
## smoke plume, three shockwaves racing across the arena, flying sand and
## embers, a scorch left behind and a camera shake. Only the look.

const FLAME_SHADER := preload("res://shaders/spell_flame.gdshader")
const WHITE := Color(1.0, 0.95, 0.8)
const FIRE := Color(1.0, 0.45, 0.12)
const DEEP := Color(0.85, 0.18, 0.04)
const SAND := Color(0.82, 0.66, 0.42)
const SMOKE := Color(0.12, 0.09, 0.07, 0.55)
const FIREBALL_R := 9.0
const COLUMN_HEIGHT := 16.0

static func spawn(parent: Node, at: Vector3, arena_radius: float) -> SunExplosion:
	var fx := SunExplosion.new()
	parent.add_child(fx)
	fx.global_position = at
	fx.play(arena_radius)
	return fx

func play(arena_radius: float) -> void:
	var parent := get_parent()
	var at := global_position
	SpellFx.flash(parent, at + Vector3.UP * 3.0, WHITE, 34.0, 0.35)
	SpellFx.flash(parent, at + Vector3.UP * 5.0, FIRE, 60.0, 1.1)
	SpellFx.light_pop(parent, at + Vector3.UP * 4.0, FIRE, 14.0, 45.0, 1.6)
	SpellFx.ground_mark(parent, at, arena_radius * 0.55, SpellFx.Mark.SCORCH, Color(0.05, 0.03, 0.02, 0.8), Color(1.0, 0.4, 0.08, 1.0), 9.0, 4.0)
	_shockwaves(parent, at, arena_radius)
	_fireball(FIREBALL_R, WHITE, 0.35, 0.7)
	_fireball(FIREBALL_R * 1.35, FIRE, 0.5, 1.3)
	_column()
	_flames()
	_embers()
	_debris()
	_smoke()
	_shake_player(at, arena_radius)
	SpellFx.free_after(self, 6.0)

func _shockwaves(parent: Node, at: Vector3, radius: float) -> void:
	SpellFx.shockwave(parent, at + Vector3.UP * 0.1, radius, WHITE, 0.45)
	var timer := get_tree().create_timer(0.15, false)
	timer.timeout.connect(func() -> void: SpellFx.shockwave(parent, at + Vector3.UP * 0.15, radius, FIRE, 0.9))
	get_tree().create_timer(0.4, false).timeout.connect(func() -> void: SpellFx.shockwave(parent, at + Vector3.UP * 0.2, radius, SAND, 1.6))

## An additive sphere that swells to `radius` and fades.
func _fireball(radius: float, color: Color, grow: float, fade: float) -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.albedo_color = Color(color, 0.85)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = Vector3.UP * radius * 0.25
	mi.scale = Vector3.ONE * AtarasSun.RADIUS
	var tween := mi.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mi, "scale", Vector3(1.0, 0.7, 1.0) * radius, grow).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, fade).set_delay(grow * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(mi.queue_free)

## A wide fire column that shoots up out of the fireball and gutters out.
func _column() -> void:
	var mats: Array[ShaderMaterial] = []
	for spec in [[6.0, 9.0, COLUMN_HEIGHT, 7.0, 1.0], [3.0, 4.5, COLUMN_HEIGHT * 0.8, 5.0, 1.2]]:
		var mi := MeshInstance3D.new()
		mi.mesh = SpellFx.tube(spec[0], spec[1], spec[2], 16, 40, 0.7)
		var mat := ShaderMaterial.new()
		mat.shader = FLAME_SHADER
		mat.set_shader_parameter("tiles", spec[3])
		mat.set_shader_parameter("period", spec[3])
		mat.set_shader_parameter("intensity", spec[4])
		mat.set_shader_parameter("fill", 0.45)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mats.append(mat)
		mi.scale = Vector3(0.6, 0.05, 0.6)
		var rise := mi.create_tween()
		rise.tween_property(mi, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tween := create_tween()
	tween.tween_interval(0.9)
	tween.tween_method(func(b: float) -> void:
		for m in mats:
			m.set_shader_parameter("burn", b), 1.0, 0.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

## Fire thrown out in every direction from the impact.
func _flames() -> void:
	var p := SpellFx.emitter(self, 180, 1.1)
	p.one_shot = true
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 2.5
	p.direction = Vector3.UP
	p.spread = 95.0
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 26.0
	p.damping_min = 6.0
	p.damping_max = 12.0
	p.gravity = Vector3(0, 2.0, 0)
	p.scale_amount_min = 1.4
	p.scale_amount_max = 3.2
	p.scale_amount_curve = SpellFx.curve(1.0, 0.2)
	p.color_ramp = SpellFx.ramp(Color(WHITE, 1.0), Color(FIRE, 0.9), 0.2)
	p.mesh = SpellFx.glow_quad()
	p.local_coords = false
	p.emitting = true

func _embers() -> void:
	var p := SpellFx.emitter(self, 140, 3.0)
	p.one_shot = true
	p.explosiveness = 0.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 4.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 20.0
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.gravity = Vector3(0, -2.5, 0)
	p.tangential_accel_min = -3.0
	p.tangential_accel_max = 3.0
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.25
	p.color_ramp = SpellFx.ramp(Color(1.0, 0.9, 0.6, 1.0), Color(FIRE, 1.0), 0.3)
	p.mesh = SpellFx.glow_quad()
	p.local_coords = false
	p.emitting = true

## Sand and stone chunks flung low across the floor.
func _debris() -> void:
	SpellFx.shards(self, global_position + Vector3.UP * 0.5, SAND, 70, Vector2(10, 24), Vector2(0.15, 0.4), 1.4, 75.0, false)
	var dust := SpellFx.emitter(self, 60, 2.2)
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	dust.emission_ring_axis = Vector3.UP
	dust.emission_ring_radius = 3.0
	dust.emission_ring_inner_radius = 1.0
	dust.emission_ring_height = 0.3
	dust.direction = Vector3(1, 0.15, 0)
	dust.spread = 180.0
	dust.flatness = 0.9
	dust.initial_velocity_min = 12.0
	dust.initial_velocity_max = 22.0
	dust.damping_min = 6.0
	dust.damping_max = 9.0
	dust.scale_amount_min = 2.0
	dust.scale_amount_max = 4.0
	dust.scale_amount_curve = SpellFx.curve(0.5, 1.0)
	dust.color_ramp = SpellFx.ramp(Color(SAND, 0.0), Color(SAND, 0.45), 0.15)
	dust.mesh = SpellFx.glow_quad(false)
	dust.local_coords = false
	dust.emitting = true

## A dark plume rolling up where the column was.
func _smoke() -> void:
	var p := SpellFx.emitter(self, 40, 4.5)
	p.one_shot = true
	p.explosiveness = 0.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 4.0
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 9.0
	p.damping_min = 0.8
	p.damping_max = 1.6
	p.scale_amount_min = 4.0
	p.scale_amount_max = 7.0
	p.scale_amount_curve = SpellFx.curve(0.4, 1.0)
	p.color_ramp = SpellFx.ramp(Color(SMOKE, 0.0), SMOKE, 0.25)
	p.mesh = SpellFx.glow_quad(false)
	p.local_coords = false
	p.emitting = false
	get_tree().create_timer(0.5, false).timeout.connect(func() -> void: p.emitting = true)

func _shake_player(at: Vector3, radius: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	var sway := player.camera.get_node_or_null("CameraSway") as CameraSway
	if sway:
		var closeness := clampf(1.0 - player.global_position.distance_to(at) / (radius * 2.0), 0.35, 1.0)
		sway.shake(0.045 * closeness, 1.1)
