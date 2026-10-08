extends Node3D
class_name ElementComet
## A glowing shard thrown from one of the Lord of the Elements' orbs, arcing
## onto an ability's target so it lands as the ground telegraph fills.

const SIZE := 0.25
const ARC_HEIGHT := 5.0

var color := Color.WHITE

func launch(from: Vector3, to: Vector3, seconds: float) -> void:
	global_position = from
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = SIZE
	sphere.height = SIZE * 2.0
	core.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color.lightened(0.4)
	core.material_override = mat
	add_child(core)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.0
	light.omni_range = 4.0
	add_child(light)
	add_child(_trail())
	var apex := (from + to) / 2.0 + Vector3(0, ARC_HEIGHT, 0)
	var fly := func(f: float) -> void:
		global_position = from.lerp(apex, f).lerp(apex.lerp(to, f), f)
	var tween := create_tween()
	tween.tween_method(fly, 0.0, 1.0, seconds)
	tween.tween_callback(_land)

func _land() -> void:
	var ring := StanceAttack.IMPACT_RING_SCENE.instantiate()
	get_parent().add_child(ring)
	ring.global_position = global_position + Vector3.UP * 0.05
	ring.play(1.5, color)
	queue_free()

func _trail() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 40
	particles.lifetime = 0.5
	particles.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 0.8
	process.gravity = Vector3.ZERO
	process.scale_min = 0.5
	process.scale_max = 1.0
	process.color = color
	particles.process_material = process
	var mote := SphereMesh.new()
	mote.radius = 0.07
	mote.height = 0.14
	var mote_mat := StandardMaterial3D.new()
	mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_mat.vertex_color_use_as_albedo = true
	mote_mat.albedo_color = color
	mote.material = mote_mat
	particles.draw_pass_1 = mote
	return particles
