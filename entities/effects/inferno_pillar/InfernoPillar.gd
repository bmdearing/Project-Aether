extends Node3D
class_name InfernoPillar
## Inferno's cast VFX: a column of fire erupts from the ground at the
## cast point (scales up fast, holds, fades while overshooting slightly
## taller), plus embers drifting upward. Purely visual, same damage-
## timing note as CometImpact.

const PILLAR_HEIGHT := 4.5
const RISE_DURATION := 0.15
const HOLD_DURATION := 0.35
const FADE_DURATION := 0.3
const EMBER_COUNT := 24

@onready var pillar: MeshInstance3D = $Pillar

func play(radius: float, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var fire_color := color
	fire_color.a = 0.8
	mat.albedo_color = fire_color
	pillar.material_override = mat

	var pillar_radius: float = clamp(radius * 0.35, 0.5, 2.0)
	pillar.scale = Vector3(pillar_radius, 0.01, pillar_radius)

	_spawn_embers(color)

	var tween := create_tween()
	tween.tween_property(pillar, "scale:y", PILLAR_HEIGHT, RISE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(HOLD_DURATION)
	tween.tween_property(mat, "albedo_color:a", 0.0, FADE_DURATION)
	tween.parallel().tween_property(pillar, "scale:y", PILLAR_HEIGHT * 1.3, FADE_DURATION)
	tween.tween_callback(queue_free)

func _spawn_embers(color: Color) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.amount = EMBER_COUNT
	particles.lifetime = 0.9
	particles.explosiveness = 0.4
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 20.0
	particles.gravity = Vector3(0, 1.5, 0)
	particles.initial_velocity_min = 1.5
	particles.initial_velocity_max = 3.5
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color.lightened(0.5)
	var ember_mesh := BoxMesh.new()
	ember_mesh.size = Vector3(0.05, 0.05, 0.05)
	ember_mesh.material = mat
	particles.mesh = ember_mesh
	add_child(particles)
	particles.emitting = true
