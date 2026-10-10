extends CPUParticles3D
class_name SmokePuff
## A one-shot burst of grey smoke that drifts up and fades, then frees
## itself. SmokePuff.spawn(parent, at) is all a caller needs.

const LIFETIME := 1.1

static func spawn(parent: Node, at: Vector3, puff_scale: float = 1.0, tint: Color = Color(0.55, 0.55, 0.6)) -> SmokePuff:
	var puff := SmokePuff.new()
	puff.scale_amount_min = 0.9 * puff_scale
	puff.scale_amount_max = 1.6 * puff_scale
	puff.color = tint
	parent.add_child(puff)
	puff.global_position = at + Vector3(0, 0.6, 0)
	puff.emitting = true
	puff.get_tree().create_timer(LIFETIME + 0.3).timeout.connect(puff.queue_free)
	return puff

func _init() -> void:
	one_shot = true
	explosiveness = 0.9
	amount = 24
	lifetime = LIFETIME
	emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	emission_sphere_radius = 0.6
	direction = Vector3.UP
	spread = 70.0
	initial_velocity_min = 0.6
	initial_velocity_max = 1.8
	gravity = Vector3(0, 0.6, 0)
	damping_min = 1.5
	damping_max = 2.5
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.75))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = GlowTexture.radial()
	quad.material = mat
	mesh = quad
