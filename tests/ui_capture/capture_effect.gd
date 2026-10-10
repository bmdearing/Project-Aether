extends Node3D
## Screenshots an MdxEffect at several moments, next to a 1.8 m reference capsule.
## Run windowed: Godot --path . res://tests/ui_capture/capture_effect.tscn -- <out_prefix> <fx.json> <times,csv> [scale] [start_time] [speed] [geo|fx]
## Writes <out_prefix>_<time>.png per time (seconds of real time after play()).

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var times: PackedStringArray = args[2].split(",")
	var effect_scale: float = float(args[3]) if args.size() > 3 else 1.0
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.13, 0.16)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.5
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.25, 0.24, 0.22)
	ground.material_override = ground_mat
	add_child(ground)
	var capsule := MeshInstance3D.new()
	capsule.mesh = CapsuleMesh.new()
	(capsule.mesh as CapsuleMesh).height = 1.8
	(capsule.mesh as CapsuleMesh).radius = 0.3
	capsule.position = Vector3(3.0, 0.9, 0.0)
	add_child(capsule)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 4.5, 11.0)
	cam.look_at(Vector3(0, 2.0, 0), Vector3.UP)
	cam.make_current()

	var effect := MdxEffect.new()
	effect.fx_path = args[1]
	effect.autoplay = false
	effect.free_when_finished = false
	effect.scale = Vector3.ONE * effect_scale
	if args.size() > 4:
		effect.start_time = float(args[4])
	if args.size() > 5:
		effect.speed_scale = float(args[5])
	add_child(effect)
	for i in 3:
		await get_tree().process_frame
	var started := Time.get_ticks_msec()
	effect.play()
	var only: String = args[6] if args.size() > 6 else ""
	for child in effect.get_children():
		if only == "geo" and child is MultiMeshInstance3D or only == "fx" and not child is MultiMeshInstance3D:
			(child as Node3D).visible = false
	for t in times:
		while (Time.get_ticks_msec() - started) / 1000.0 < float(t):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, t])
		print("CAPTURED ", t, " effect time ", effect.get("_time"))
	print("CAPTURE_DONE")
	get_tree().quit()
