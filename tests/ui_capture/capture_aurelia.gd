extends Node
## Screenshots Aurelia's arena mid-spell. Run windowed:
## Godot --path . res://tests/ui_capture/capture_aurelia.tscn --resolution 1600x900 -- <out.png> <mode> [view: player|overview] [delay]
## mode: idle | wheel | firewall | spears | lightning | amaterasu | golem | bomb

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://aurelia.png"
	var mode: String = args[1] if args.size() > 1 else "idle"
	var view: String = args[2] if args.size() > 2 else "overview"
	var delay: float = float(args[3]) if args.size() > 3 else 0.6
	GameState.reset_to_defaults()
	GameState.debug_overlay_enabled = false
	GameState.game_started = false
	GameState.pending_pinnacle = "aurelia"
	var arena: PinnacleArena = (load("res://levels/pinnacle_boss/PinnacleArena.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().create_timer(1.0).timeout
	# CAPTURE_WEAPON=res://... puts that weapon in the player's hands (keeps a greatsword off the centre of the shot).
	var held := OS.get_environment("CAPTURE_WEAPON")
	if held != "":
		(get_tree().get_first_node_in_group("player") as Player).equipment.equip(load(held) as Item, true)
	var boss := arena.boss as Aurelia
	var wheel := arena.aurelia
	var player := get_tree().get_first_node_in_group("player") as Player
	player.health.max_health = 1000000.0
	player.health.current_health = player.health.max_health
	boss.boss_brain.set_physics_process(false)
	player.set_physics_process(false)
	player.global_position = wheel.to_global(Vector3(0, 0.1, 9))
	player.look_at(Vector3(boss.global_position.x, player.global_position.y, boss.global_position.z))
	match mode:
		"wheel":
			wheel.earth_wheel.call(3, 0.4)
		"firewall":
			boss._fire_wall.call(boss.boss_brain.find("fire_wall"))
		"spears":
			boss.upgraded.assign([Aurelia.Spell.ICE_SPEARS])
			boss._ice_spears.call(boss.boss_brain.find("ice_spears"))
		"lightning":
			boss._lightning_bolt.call(boss.boss_brain.find("lightning_bolt"))
		"amaterasu":
			wheel.start_amaterasu()
			wheel.amaterasu_safe_radius = 12.0
			wheel.add_fire_pot(wheel.to_global(Vector3(-5, 0, 3)), 1.0)
		"golem":
			boss.boss_brain.phase = 4
			boss._summon_golems.call()
		"bomb":
			boss.boss_brain.phase = 5
			boss._on_player_knocked_up(null, player)
		"icons":
			for id in ["ignite", "shock", "unraveling", "meager"]:
				if id == "meager":
					boss.status_effects.apply_curse(id, player, 6.0, 1.0)
				else:
					boss.status_effects.apply_effect(id, player, 50.0)
			for i in 2:
				boss.status_effects.apply_effect("chill", player)
			boss.composure.enter_broken_state()
			boss.boss_brain.phase = 4
			await boss._summon_golems()
			await get_tree().create_timer(0.3).timeout
			var golem := boss.living_golems()[0] as Enemy
			golem.status_effects.apply_effect("bleed", player, 40.0)
			golem.status_effects.apply_effect("electrocute", player)
			golem.status_effects.apply_timed_effect("entangle", 5.0)
			golem.composure.enter_broken_state()
			golem.set_physics_process(false)
			golem.global_position = player.global_position + (boss.global_position - player.global_position).normalized() * 6.0 + Vector3(2, 0, 0)
			golem._last_combat_msec = Time.get_ticks_msec()
	await get_tree().create_timer(delay).timeout
	var cam := Camera3D.new()
	arena.add_child(cam)
	if view == "player":
		cam.global_transform = player.camera.global_transform
	else:
		cam.global_position = arena.to_global(Vector3(0, 24, 26))
		cam.look_at(arena.to_global(Vector3(0, 0, -1)), Vector3.UP)
	cam.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
