extends Node
## Screenshots a generated map in a given style for visual review.
## Run windowed: Godot --path . res://tests/ui_capture/capture_map.tscn --resolution 1600x900 -- <out.png> <style_id> <view> [seed]
## Views: top (whole map from above), boss (inside the boss room), rarity
## (an Elite pack, a Champion pack and an Ascendant in front of you), spawn
## (the player's view), room (a camera in the first ordinary room).

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://map.png"
	var style: String = args[1] if args.size() > 1 else "dungeon_cellblock"
	var view: String = args[2] if args.size() > 2 else "top"
	GameState.reset_to_defaults()
	var figment := FigmentRoller.roll(1)
	figment.tileset_id = style
	GameState.active_map = figment
	if args.size() > 3:
		GameState.portal_map_state = {"seed": int(args[3]), "tileset_id": style}
		GameState.returning_through_portal = false
	var map: GeneratedMap = load("res://levels/generated_map/GeneratedMap.tscn").instantiate()
	get_tree().root.add_child(map)
	await get_tree().create_timer(1.5).timeout
	if view != "rarity":
		for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(node as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.far = 600.0
	map.add_child(cam)
	var vault := map._cell_to_world(map.graph.vault_cell)
	match view:
		"top":
			var size := map.cell_size * map.graph.grid_size
			var centre := Vector3((map.graph.grid_size - 1) * map.cell_size / 2.0, 0, (map.graph.grid_size - 1) * map.cell_size / 2.0)
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = size * 1.05
			cam.position = centre + Vector3(0, 120, 0)
			cam.rotation_degrees = Vector3(-90, 0, 0)
			var sun := DirectionalLight3D.new()  # rooms are lit for first person, not from above
			sun.rotation_degrees = Vector3(-70, 30, 0)
			sun.light_energy = 1.4
			map.add_child(sun)
		"boss":
			var to_altar := map.boss_portal_point - vault
			to_altar.y = 0
			var back := to_altar.normalized() if to_altar.length() > 0.1 else Vector3.FORWARD
			cam.position = vault - back * 11.0 + Vector3(0, 6.0, 0)
			cam.look_at(map.boss_portal_point, Vector3.UP)
		"rarity":
			var player := get_tree().get_first_node_in_group("player") as Player
			var existing := get_tree().get_nodes_in_group("enemy")
			var fwd := -player.global_transform.basis.z
			var champs: Array[String] = ["unchartered_brigand", "unchartered_brigand", "unchartered_cutthroat"]
			map._spawn_pack(champs, player.global_position + fwd * 7.0 + player.global_transform.basis.x * 3.0, Constants.EnemyRarity.CHAMPION)
			var elites: Array[String] = ["unchartered_javelineer", "unchartered_cutthroat"]
			map._spawn_pack(elites, player.global_position + fwd * 6.0 - player.global_transform.basis.x * 3.0, Constants.EnemyRarity.ELITE)
			var asc: Array[String] = []
			map._spawn_pack(asc, player.global_position + fwd * 10.0, Constants.EnemyRarity.ASCENDANT)
			for e in get_tree().get_nodes_in_group("enemy"):
				e.set_physics_process(false)
				if not existing.has(e):
					e._last_combat_msec = Time.get_ticks_msec() + 100000
			cam.global_transform = player.camera.global_transform
		"room":
			for cell in map.graph.rooms:
				var room: MapGraph.RoomData = map.graph.rooms[cell]
				if not room.is_start and not room.is_vault:
					var c := map._cell_to_world(cell)
					var half: Vector2 = map.room_half.get(cell, Vector2(8, 8))
					cam.position = c + Vector3(-half.x + 1.5, 3.2, -half.y + 1.5)
					cam.look_at(c + Vector3(half.x, 0, half.y) * 0.4, Vector3.UP)
					break
		_:
			var player := get_tree().get_first_node_in_group("player") as Player
			cam.global_transform = player.camera.global_transform
	cam.make_current()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
