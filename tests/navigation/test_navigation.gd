extends Node
## Enemy pathfinding: a generated map bakes a navigation mesh, and an enemy
## in another room walks around the walls to reach the player instead of
## pressing into the nearest wall.
## Run: Godot --headless --path . res://tests/navigation/test_navigation.tscn --quit-after 6000

const MAP := "res://levels/generated_map/GeneratedMap.tscn"

var _checks := 0
var _failures := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	var figment := FigmentRoller.roll(1)
	figment.tileset_id = "dungeon_cellblock"
	GameState.active_map = figment
	var map: GeneratedMap = load(MAP).instantiate()
	add_child(map)
	var waited := 0.0
	while (map.nav_region == null or map.nav_region.navigation_mesh == null) and waited < 20.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_check(map.nav_region != null and map.nav_region.navigation_mesh != null and map.nav_region.navigation_mesh.get_polygon_count() > 0, "the map bakes a navigation mesh (%.1fs)" % waited)
	for i in 3:
		await get_tree().physics_frame
	var player := get_tree().get_first_node_in_group("player") as Player
	player.set_physics_process(false)
	# The enemy whose straight line to the player is blocked and that is
	# furthest away within a couple of rooms.
	var chaser: Enemy = null
	var best := 0.0
	for node in get_tree().get_nodes_in_group("enemy"):
		var e := node as Enemy
		if e == null or e.rank == Constants.EnemyRank.BOSS:
			continue
		var d := e.global_position.distance_to(player.global_position)
		e._player = player
		if d > 18.0 and d < 70.0 and d > best and not e.can_see_player() and not e.is_ranged_unit():
			best = d
			chaser = e
	for node in get_tree().get_nodes_in_group("enemy"):
		if node != chaser:
			node.set_physics_process(false)
			(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
	_check(chaser != null, "found an enemy out of sight in another room")
	if chaser:
		var start := chaser.global_position.distance_to(player.global_position)
		var path := NavigationServer3D.map_get_path(chaser.get_world_3d().navigation_map, chaser.global_position, player.global_position, true)
		_check(path.size() > 2, "there is a path with turns to the player (%d points)" % path.size())
		# Time for the path at the unit's own speed, with slack.
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i].distance_to(path[i - 1])
		var allowed := length / maxf(chaser.move_speed, 0.5) * 1.4 + 5.0
		var t := 0.0
		while t < allowed and chaser.global_position.distance_to(player.global_position) > chaser.stop_distance + 1.5:
			chaser._last_combat_msec = Time.get_ticks_msec()
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		var end := chaser.global_position.distance_to(player.global_position)
		_check(end <= chaser.stop_distance + 1.5, "the enemy reaches the player around the walls (%.1f m -> %.1f m in %.1fs)" % [start, end, t])
	print("navigation tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
