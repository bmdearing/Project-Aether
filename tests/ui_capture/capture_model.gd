extends Node3D
## Screenshots one enemy model frozen in a clip, from the front and the side.
## Run windowed: Godot --path . res://tests/ui_capture/capture_model.tscn -- <out.png> <model.tscn> <clip> <seconds>

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var model: Node3D = (load(args[1]) as PackedScene).instantiate()
	var clip: String = args[2] if args.size() > 2 else ""
	var t: float = float(args[3]) if args.size() > 3 else 0.0
	var side := args.size() > 4 and args[4] == "side"
	add_child(model)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.55, 0.6)
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.8
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	print("ANIMS ", player.get_animation_list())
	if clip != "":
		if model.has_method("_apply_visibility"):
			model.call("_apply_visibility", clip)
		player.play(clip)
		player.seek(t, true)
		player.pause()
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(5.5, 1.4, 0) if side else Vector3(0, 1.4, 5.5)
	cam.look_at(Vector3(0, 1.1, 0), Vector3.UP)
	cam.make_current()
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
