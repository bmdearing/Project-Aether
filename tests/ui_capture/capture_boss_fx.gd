extends Node
## Screenshots boss spell effects (BossFx) in a Pinnacle arena. Run windowed:
## Godot --path . res://tests/ui_capture/capture_boss_fx.tscn --resolution 1600x900 -- <out.png> <view>
## Views: impacts (every element landing in a row), beam (the Herald's Void
## Beam), lash (her Void Lash), hazard (Void Rift and fire pools), roar.

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://boss_fx.png"
	var view: String = args[1] if args.size() > 1 else "impacts"
	GameState.reset_to_defaults()
	GameState.pending_pinnacle = "herald_of_the_maw"
	var arena: PinnacleArena = (load("res://levels/pinnacle_boss/PinnacleArena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().create_timer(1.0).timeout
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	var herald := arena.boss as Xalatath
	var player := get_tree().get_first_node_in_group("player") as Player
	player.set_physics_process(false)
	player.health.max_health = 1.0e9
	player.health.current_health = 1.0e9
	herald.boss_brain.set_physics_process(false)
	for n in ["MeleeAttack", "RangedAttack"]:
		herald.get_node(n).set_physics_process(false)
	herald.set_physics_process(false)
	var maw := arena.maw
	herald.global_position = maw.to_global(Vector3(0, 0.05, -6))
	player.global_position = maw.to_global(Vector3(0, 0.1, 6))
	var cam := Camera3D.new()
	arena.add_child(cam)
	cam.global_position = maw.to_global(Vector3(9, 5, 12))
	cam.look_at(maw.to_global(Vector3(0, 1, -2)), Vector3.UP)
	cam.make_current()
	var wait := 0.25
	match view:
		"impacts":
			var types := [Constants.DamageType.FIRE, Constants.DamageType.COLD, Constants.DamageType.LIGHTNING, Constants.DamageType.ENTROPIC, Constants.DamageType.KINETIC]
			for i in types.size():
				BossFx.impact(arena, maw.to_global(Vector3(-10 + i * 5, 0.05, 2)), 2.2, types[i])
			wait = 0.12
		"beam":
			herald.boss_brain._player = player
			herald.cast_custom(herald.boss_brain.find("void_beam"))
			wait = 2.0
		"lash":
			player.global_position = herald.global_position + Vector3(0, 0.05, 4.5)
			herald.begin_attack_telegraph(0.3)
			await get_tree().create_timer(0.3).timeout
			herald.on_melee_strike()
			wait = 0.1
		"hazard":
			herald.boss_brain._player = player
			herald.boss_brain.cast(herald.boss_brain.find("void_rift"))
			wait = 2.0
		"roar":
			herald.boss_brain._enter_phase(2)
			wait = 0.3
		"charge":
			herald.boss_brain._player = player
			herald.boss_brain.cast(herald.boss_brain.find("entropic_volley"))
			wait = 0.7
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
