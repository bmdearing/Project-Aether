extends Node3D
## Screenshots every ProjectileLook kind frozen mid-flight, plus a hitscan
## tracer, from the side and from behind (first-person-ish).
## Run windowed: Godot --path . res://tests/ui_capture/capture_projectiles.tscn -- <out_prefix>
## Writes <out_prefix>_side.png and <out_prefix>_behind.png.

const KINDS := [
	[ProjectileLook.Kind.BULLET, Constants.DamageType.KINETIC],
	[ProjectileLook.Kind.ARROW, Constants.DamageType.PIERCING],
	[ProjectileLook.Kind.BOLT, Constants.DamageType.COLD],
	[ProjectileLook.Kind.JAVELIN, Constants.DamageType.KINETIC],
	[ProjectileLook.Kind.AXE, Constants.DamageType.KINETIC],
	[ProjectileLook.Kind.WEB, Constants.DamageType.KINETIC],
	[ProjectileLook.Kind.MAGIC, Constants.DamageType.AETHERIC],
	[ProjectileLook.Kind.MAGIC, Constants.DamageType.FIRE],
]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://projectiles"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.1, 0.11, 0.14)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.4
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	add_child(env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.22, 0.21, 0.2)
	ground.material_override = ground_mat
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var scene: PackedScene = load("res://entities/projectile/Projectile.tscn")
	for i in KINDS.size():
		var p: Projectile = scene.instantiate()
		p.look = KINDS[i][0]
		p.damage_type = KINDS[i][1]
		p.speed = 0.0
		p.lifetime = 60.0
		p.monitoring = false
		add_child(p)
		# In a row along X, two rows of four, flying away and to the right.
		var at := Vector3((i % 4) * 1.6 - 2.4, 1.4, -float(i / 4) * 4.0)
		p.global_transform = Transform3D(Basis.looking_at(Vector3(1, 0, -1.4).normalized(), Vector3.UP), at)
		if p.spin == 0.0:
			p.set_physics_process(false)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 60.0
	cam.make_current()
	for i in 6:
		await get_tree().process_frame
	cam.global_position = Vector3(-0.2, 1.7, 2.6)
	cam.look_at(Vector3(-0.2, 1.4, 0.0), Vector3.UP)
	await _shot(out + "_row_a.png")
	cam.global_position = Vector3(-0.2, 1.7, -1.4)
	cam.look_at(Vector3(-0.2, 1.4, -4.0), Vector3.UP)
	await _shot(out + "_row_b.png")
	# Behind and above, like the player watching their shots fly away.
	cam.global_position = Vector3(0.0, 1.7, 8.0)
	cam.look_at(Vector3(0.0, 1.4, -20.0), Vector3.UP)
	ProjectileLook.tracer(self, Vector3(0.25, 1.5, 7.6), Vector3(3.0, 1.2, -25.0), Constants.DamageType.KINETIC, 2.0)
	await get_tree().create_timer(0.25).timeout
	await _shot(out + "_behind.png")
	get_tree().quit()

func _shot(path: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
