extends Node
## Screenshots a Pinnacle arena. Run windowed:
## Godot --path . res://tests/ui_capture/capture_pinnacle.tscn --resolution 1600x900 -- <out.png> <boss_id> [phase2] [view: player|overview]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://pinnacle.png"
	GameState.reset_to_defaults()
	GameState.pending_pinnacle = args[1] if args.size() > 1 else "ataras"
	var arena := (load("res://levels/pinnacle_boss/PinnacleArena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().create_timer(1.0).timeout
	var boss: Enemy = arena.boss
	var player := get_tree().get_first_node_in_group("player") as Player
	player.set_physics_process(false)
	if args.size() > 2 and args[2] == "phase2" and boss:
		boss.health.current_health = boss.health.max_health * 0.45
		await get_tree().create_timer(5.5).timeout
	var cam := Camera3D.new()
	arena.add_child(cam)
	var view: String = args[3] if args.size() > 3 else "overview"
	if view == "player":
		cam.global_transform = player.camera.global_transform
	else:
		cam.global_position = arena.to_global(Vector3(0, 26, 24))
		cam.look_at(arena.to_global(Vector3(0, 0, -2)), Vector3.UP)
	cam.make_current()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
