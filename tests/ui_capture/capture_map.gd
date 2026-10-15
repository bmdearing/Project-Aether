extends Node
## Screenshots a generated map in a given style for visual review.
## Run windowed: Godot --path . res://tests/ui_capture/capture_map.tscn --resolution 1600x900 -- <out.png> <style_id> <view> [seed]
## Views: top (whole map from above), boss (inside the boss room), rarity
## (an Elite pack, a Champion pack and an Ascendant in front of you), spawn
## (the player's view), room (a camera in the first ordinary room), stairs (up a
## dungeon staircase).

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://map.png"
	var style: String = args[1] if args.size() > 1 else "dungeon_cellblock"
	var view: String = args[2] if args.size() > 2 else "top"
	GameState.reset_to_defaults()
	GameState.debug_overlay_enabled = false
	var figment := FigmentRoller.roll(1)
	figment.tileset_id = style
	GameState.active_map = figment
	if args.size() > 3:
		GameState.portal_map_state = {"seed": int(args[3]), "tileset_id": style}
		GameState.returning_through_portal = false
	var map: GeneratedMap = load("res://levels/generated_map/GeneratedMap.tscn").instantiate()
	get_tree().root.add_child(map)
	await get_tree().create_timer(1.5).timeout
	# CAPTURE_WEAPON=res://... puts that weapon in the player's hands (keeps a greatsword off the centre of the shot).
	var held := OS.get_environment("CAPTURE_WEAPON")
	if held != "":
		(get_tree().get_first_node_in_group("player") as Player).equipment.equip(load(held) as Item, true)
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
			player._iframes_remaining = 999.0  # the packs can't kill the player before the shot
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
		"treetest":
			var player := get_tree().get_first_node_in_group("player") as Player
			var fwd := -player.global_transform.basis.z
			for i in 2:
				var scene: PackedScene = load(["res://entities/environment/doodads/forest_fall/LordaeronTreeTall0.tscn", "res://entities/environment/doodads/forest/Ashentree0.tscn"][i])
				var t := scene.instantiate() as Node3D
				map.add_child(t)
				t.global_position = player.global_position + fwd * 8.0 + player.global_transform.basis.x * (i * 5.0 - 2.5)
			cam.global_transform = player.camera.global_transform
		"minion":
			# A Wraith at the player's side and a Reap sweep in front.
			var player := get_tree().get_first_node_in_group("player") as Player
			player.ward.current_ward = 100.0
			var wraith := load("res://data/abilities/instances/wraith.tres") as Ability
			player.ability_cast._cast(wraith, player.global_position)
			await get_tree().create_timer(0.6).timeout
			player.ability_cast._cast(load("res://data/abilities/instances/reap.tres") as Ability, player.global_position)
			await get_tree().create_timer(0.08).timeout
			cam.global_transform = player.camera.global_transform
			cam.global_position += player.global_transform.basis.z * 2.5 + Vector3.UP * 1.2
			cam.rotation.x -= 0.25
		"aerial":
			# Angled overview from inside the draw distance (top is out of it).
			var centre := Vector3((map.graph.grid_size - 1) * map.cell_size / 2.0, 0, (map.graph.grid_size - 1) * map.cell_size / 2.0)
			cam.position = centre + Vector3(0, 38, map.cell_size * map.graph.grid_size * 0.42)
			cam.look_at(centre, Vector3.UP)
		"water":
			# From the bank, looking at a river's ford (or any channel's middle).
			if map.water and not map.water.channels.is_empty():
				var c: Dictionary = map.water.channels[0]
				var pts: PackedVector3Array = c["points"]
				var at := pts[pts.size() / 2]
				for p in pts:
					if not (c["fords"] as Array).is_empty() and absf((p.x if c["axis"] == "z" else p.z) - float(c["fords"][1 if c["fords"].size() > 1 else 0])) < 3.0:
						at = p
				var side := (pts[1] - pts[0]).normalized().cross(Vector3.UP)
				cam.position = at + side * 9.0 + Vector3(0, 3.0, 0) + (pts[1] - pts[0]).normalized() * 4.0
				cam.look_at(at, Vector3.UP)
		"secret":
			# The secret's way in at eye height: the host room's cracked wall,
			# or the outcrop from off its crack side.
			var s := map.secret
			if s and s.access == SecretRoomBuilder.Access.OUTCROP:
				var n := Vector3(s.crack_dir.x, 0, s.crack_dir.y)
				cam.position = s.centre + n * 13.0 + Vector3(n.z, 0, n.x) * 7.0 + Vector3(0, 1.7, 0)
				cam.look_at(s.centre + Vector3(0, 3.0, 0), Vector3.UP)
			elif s:
				var origin := map._cell_to_world(s.host_cell)
				var away := Vector3(s.host_dir.x, 0, s.host_dir.y)
				var half: Vector2 = map.room_half[s.host_cell]
				var reach: float = half.x if s.host_dir.x != 0 else half.y
				cam.position = origin + away * (reach - 3.5) + Vector3(0, 1.7, 0) + Vector3(away.z, 0, away.x) * 0.8
				cam.look_at(origin + away * reach + Vector3(0, 1.3, 0), Vector3.UP)
		"step":
			# Down a corridor at a raised room's ledge.
			for child in map.get_children():
				if child is NavigationLink3D:
					var link := child as NavigationLink3D
					var dir := (link.end_position - link.start_position) * Vector3(1, 0, 1)
					cam.position = link.start_position - dir.normalized() * 5.0 + Vector3(0, 1.6, 0)
					cam.look_at(link.end_position + Vector3(0, 1.0, 0), Vector3.UP)
					break
		"stairs":
			# Up a dungeon staircase from the floor below it.
			var flights := get_tree().get_nodes_in_group(&"stairs")
			if not flights.is_empty():
				var s := flights[0] as Node3D
				var down: Vector3 = s.get_meta(&"out")
				cam.position = s.global_position + down * 8.0 + Vector3(0, 1.7, 0) + Vector3(down.z, 0, down.x) * 0.8
				cam.look_at(s.global_position + Vector3.UP * 2.2, Vector3.UP)
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
