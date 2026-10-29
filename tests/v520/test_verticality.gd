extends Node
## v5.2 verticality: raised dungeon rooms with climb links, the player
## mantling onto one and catching a ledge, an enemy hopping up after the
## player, secret rooms in each layout (a cracked wall struck down, the
## mantle into an outcrop's crack), the Watcher's deal and challenge.
## Open fields (terraces), canyons (raised basins) and streets (a causeway)
## need a climb to reach the Vault, bosses path without the links, and
## boundary bodies are no_climb. Dungeon staircases climb
## without a mantle, and the first climb toward the Vault stays a ledge.
## Run: Godot --headless --path . res://tests/v520/test_verticality.tscn --quit-after 80000

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

func _make_map(style: String, map_seed: int) -> GeneratedMap:
	var figment := FigmentRoller.roll(1)
	figment.tileset_id = style
	GameState.active_map = figment
	GameState.portal_map_state = {}
	GameState.returning_through_portal = false
	seed(map_seed)
	var map: GeneratedMap = load(MAP).instantiate()
	add_child(map)
	return map

func _free_map(map: GeneratedMap) -> void:
	map.queue_free()
	for i in 4:
		await get_tree().physics_frame

func _wait_nav(map: GeneratedMap) -> void:
	var frames := 0
	while (map.nav_region == null or map.nav_region.navigation_mesh == null) and frames < 3600:
		await get_tree().physics_frame
		frames += 1
	# The region syncs into the navigation map over a few more frames.
	var nav := map.get_world_3d().navigation_map
	var spawn := map.last_player_spawn
	while NavigationServer3D.map_get_closest_point(nav, spawn).distance_to(spawn) > 3.0 and frames < 3600:
		await get_tree().physics_frame
		frames += 1
	for i in 3:
		await get_tree().physics_frame

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	await _test_dungeon()
	await _test_stairs()
	for style in ["desert_dunes", "desert_badlands", "city_downtown", "forest_river_valley"]:
		await _test_outdoor(style)
	print("verticality tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _links(map: GeneratedMap) -> Array[NavigationLink3D]:
	var out: Array[NavigationLink3D] = []
	for child in map.get_children():
		if child is NavigationLink3D:
			out.append(child)
	return out

func _test_dungeon() -> void:
	var map := _make_map("dungeon_cellblock", 4242)
	await _wait_nav(map)
	_check(not map.room_floor.is_empty(), "a dungeon has raised rooms")
	var path := map._path_to_vault()
	_check(path.any(func(c): return map.room_floor.has(c)), "a raised room lies between the start and the Vault")
	var links := _links(map)
	_check(links.size() > 0, "raised rooms get climb links (%d)" % links.size())
	_check(map.secret != null and is_instance_valid(map.secret.encounter), "the dungeon has a secret room with an encounter")
	if map.secret:
		print("secret: access %d, encounter %s, host %s" % [map.secret.access, map.secret.encounter_id, map.secret.host_cell])
	await _test_climb(map, "dungeon", links, true)
	_test_route(map, "dungeon")
	await _test_cracked_wall(map)
	await _test_watcher(map)
	_check(map.capture_state().has("secret"), "the secret room's state is saved for a portal trip")
	await _free_map(map)

func _test_watcher(map: GeneratedMap) -> void:
	var w := Watcher.new()
	w.map = map
	map.add_child(w)
	w.global_position = map.last_player_spawn
	_check(w.offers.size() == Watcher.OFFER_COUNT, "the Watcher offers %d deals" % Watcher.OFFER_COUNT)
	var figment := GameState.active_map
	var quantity := figment.loot_quantity_multiplier
	var damage := figment.enemy_damage_multiplier
	w.accept("avarice")
	_check(is_equal_approx(figment.loot_quantity_multiplier, quantity + 0.4) and is_equal_approx(figment.enemy_damage_multiplier, damage * 1.25), "a deal writes its boon and price onto the Figment")
	_check(w.stage == Watcher.Stage.BARGAINED, "one deal per Watcher")
	var w2 := Watcher.new()
	w2.map = map
	map.add_child(w2)
	w2.global_position = map.last_player_spawn
	w2.challenge()
	_check(w2._champions.size() > 0, "a challenge brings its champion (%d)" % w2._champions.size())
	var champions: Array = w2._champions.values()
	for e in champions:
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for e in champions:
		EventBus.enemy_died.emit(e)
	for i in 3:
		await get_tree().physics_frame
	_check(w2.stage == Watcher.Stage.DEFEATED and is_instance_valid(w2._hoard), "beating the champion leaves a hoard")

func _test_outdoor(style: String) -> void:
	var map := _make_map(style, 777)
	for i in 4:
		await get_tree().physics_frame
	if map.secret == null:
		_check(style == "city_downtown" or style == "forest_river_valley", "%s has a secret outcrop" % style)
		print("note: %s rolled no plaza, so no outcrop" % style)
	else:
		var sinkhole := map.secret.access == SecretRoomBuilder.Access.SINKHOLE
		_check(map.secret.access == SecretRoomBuilder.Access.OUTCROP or (sinkhole and style.begins_with("desert")), "%s's secret is an outcrop (desert: a sinkhole)" % style)
		var c := map.secret.chamber_centre + Vector3(1.3, 0, 1.3)  # beside the encounter
		var q := PhysicsRayQueryParameters3D.create(c + Vector3.UP * 1.5, c + Vector3.DOWN * 3.0, 1)
		var hit := map.get_world_3d().direct_space_state.intersect_ray(q)
		_check(not hit.is_empty() and absf(hit["position"].y - (0.0 if sinkhole else SecretRoomBuilder.OUTCROP_FLOOR)) < 0.2, "%s's outcrop hollow has a floor up top (hit %s)" % [style, hit.get("position", "none")])
		var inside := 0
		for node in get_tree().get_nodes_in_group("enemy"):
			if map.secret.blocks((node as Node3D).global_position) and (node as Node3D).global_position.y < 3.0:
				inside += 1
		_check(inside == 0, "%s: no pack spawns inside the outcrop" % style)
		if sinkhole:
			await _test_sinkhole(map, style)
		else:
			await _test_crack_climb(map, style)
	await _wait_nav(map)
	var links := _links(map)
	_check(links.size() > 0, "%s has climb links (%d)" % [style, links.size()])
	print("%s: %d raised cells, %d terraces, %d links" % [style, map.room_floor.size(), map.terraces.size(), links.size()])
	if style != "city_downtown":
		_test_hills(map, style)
	_test_route(map, style)
	_test_boundary(map, style)
	await _test_climb(map, style, links, true)
	await _free_map(map)

## Hills are solid where terrace_top() says, and gentle enough to walk.
func _test_hills(map: GeneratedMap, label: String) -> void:
	_check(not map.hills.is_empty(), "%s has hills (%d)" % [label, map.hills.size()])
	var verified := 0
	for h in map.hills:
		var c: Vector2 = h["centre"]
		var edge := Vector3(c.x + float(h["footprint"]) * 0.7, 0, c.y)
		for p in [Vector3(c.x, 0, c.y), edge]:
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 20.0, p + Vector3.DOWN * 5.0, 1)
			var hit := map.get_world_3d().direct_space_state.intersect_ray(q)
			if hit.is_empty() or not String((hit["collider"] as Node).name).begins_with("Hill"):
				continue  # a prop stands there
			verified += 1
			var want := map.terrace_top(p)
			if absf(hit["position"].y - want) > 0.15:
				_check(false, "%s: hill ground at %s is where terrace_top says (%.2f vs %s)" % [label, p, want, hit.get("position", "none")])
				return
		var r: float = h["r"]
		_check(rad_to_deg(asin(float(h["footprint"]) / r)) < 32.0, "%s: hill foot is walkable" % label)
	_check(verified > 0, "%s: hill surfaces were probed (%d)" % [label, verified])

## Mantling up the first climb link's step, catching its ledge and letting
## go, and (with_chaser) a melee enemy hopping up after the player.
func _test_climb(map: GeneratedMap, label: String, links: Array[NavigationLink3D], with_chaser: bool) -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	for node in get_tree().get_nodes_in_group("enemy"):
		(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
	if links.is_empty():
		return
	var link := links[0]
	var low := link.start_position
	var high := link.end_position
	if low.y > high.y:
		var swap := low
		low = high
		high = swap
	var dir := Vector3(high.x - low.x, 0, high.z - low.z).normalized()
	# Jumping at the step while holding forward ends on top of it.
	player.global_position = low + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO
	player.rotation.y = atan2(-dir.x, -dir.z)
	for i in 3:
		await get_tree().physics_frame
	Input.action_press("move_forward")
	Input.action_press("jump")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("jump")
	for i in 150:
		await get_tree().physics_frame
		if player.global_position.y > high.y - 0.3 and not player.ledge_climb.busy() and player.is_on_floor():
			break
	Input.action_release("move_forward")
	_check(player.global_position.y > high.y - 0.3, "%s: the player mantles up the step (feet at %.2f, ledge %.2f)" % [label, player.global_position.y, high.y])
	# Without forward held, falling face-on past the ledge catches it.
	var face := low + dir * 0.4
	player.global_position = Vector3(face.x, high.y - 1.6, face.z)
	player.velocity = Vector3(0, -1.0, 0)
	player.rotation.y = atan2(-dir.x, -dir.z)
	var caught := false
	for i in 20:
		await get_tree().physics_frame
		caught = caught or player.ledge_climb.state == LedgeClimb.State.HANG
	_check(caught, "%s: falling against the ledge catches it" % label)
	Input.action_press("crouch")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("crouch")
	_check(not player.ledge_climb.busy(), "%s: crouch lets go of the ledge" % label)
	if not with_chaser:
		return
	# An enemy below the step hops up after a player standing on it.
	player.global_position = high + dir * 2.5 + Vector3.UP * 0.05
	player.set_physics_process(false)
	var chaser: Enemy = null
	for node in get_tree().get_nodes_in_group("enemy"):
		var e := node as Enemy
		if e and e.rank != Constants.EnemyRank.BOSS and not e.is_ranged_unit():
			chaser = e
			break
	_check(chaser != null, "%s: found a melee enemy to chase" % label)
	if chaser:
		chaser.process_mode = Node.PROCESS_MODE_INHERIT
		chaser.global_position = low - dir * 2.0 + Vector3.UP * 0.1
		chaser.velocity = Vector3.ZERO
		chaser._player = player
		var frames := 0
		while frames < 600 and chaser.global_position.y < high.y - 0.4:
			chaser._last_combat_msec = Time.get_ticks_msec()
			await get_tree().physics_frame
			frames += 1
		_check(chaser.global_position.y > high.y - 0.4, "%s: an enemy climbs the step after the player (y %.2f after %d frames)" % [label, chaser.global_position.y, frames])
		chaser.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_physics_process(true)

## The Vault can't be reached on foot without a climb link (a mantle for the
## player), and can with them; a boss leaves the links out.
func _test_route(map: GeneratedMap, label: String) -> void:
	var nav := map.get_world_3d().navigation_map
	var start := map.last_player_spawn
	var goal := map.boss_portal_point
	var with_links := 1 | (1 << (GeneratedMap.CLIMB_LINK_LAYER - 1))
	var walk := NavigationServer3D.map_get_path(nav, start, goal, true, 1)
	var climb := NavigationServer3D.map_get_path(nav, start, goal, true, with_links)
	_check(walk.is_empty() or walk[walk.size() - 1].distance_to(goal) > 2.5, "%s: the Vault can't be reached without a climb" % label)
	_check(not climb.is_empty() and climb[climb.size() - 1].distance_to(goal) < 2.5, "%s: the Vault is reachable over the climb links (end %s, goal %s)" % [label, climb[climb.size() - 1] if not climb.is_empty() else "none", goal])
	var boss: Enemy = null
	for node in get_tree().get_nodes_in_group("enemy"):
		if (node as Enemy).rank == Constants.EnemyRank.BOSS:
			boss = node
	_check(boss != null and boss.nav_layers() == 1, "%s: the boss paths without climb links" % label)

## Anything solid outside the playable square is boundary, so no_climb.
func _test_boundary(map: GeneratedMap, label: String) -> void:
	var lo := -map.cell_size / 2.0
	var hi := lo + map.cell_size * map.graph.grid_size
	var climbable := 0
	for child in map.get_children():
		var body := child as StaticBody3D
		if body == null or body.is_in_group(LedgeClimb.NO_CLIMB) or body.collision_layer & 1 == 0:
			continue
		var p := body.global_position
		if p.x < lo - 0.5 or p.x > hi + 0.5 or p.z < lo - 0.5 or p.z > hi + 0.5:
			climbable += 1
	_check(climbable == 0, "%s: boundary bodies are no_climb (%d climbable)" % [label, climbable])

## Some dungeon steps are staircases: walking up one needs no mantle.
func _test_stairs() -> void:
	var map: GeneratedMap = null
	var stairs: StaticBody3D = null
	for s in range(1, 12):
		map = _make_map("dungeon_cellblock", s)
		for i in 4:
			await get_tree().physics_frame
		var found := get_tree().get_nodes_in_group(&"stairs")
		if not found.is_empty():
			stairs = found[0]
			print("stairs: seed %d has %d flights" % [s, found.size()])
			break
		await _free_map(map)
		map = null
	_check(stairs != null, "some dungeon has a staircase")
	if stairs == null:
		return
	await _wait_nav(map)
	_test_route(map, "dungeon with stairs")
	for node in get_tree().get_nodes_in_group("enemy"):
		(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var out: Vector3 = stairs.get_meta(&"out")
	var rise: float = stairs.get_meta(&"rise")
	var foot := stairs.global_position
	var player := get_tree().get_first_node_in_group("player") as Player
	player.global_position = foot + out * (GeneratedMap.STAIR_STEPS * GeneratedMap.STAIR_RUN + 1.0) + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	player.rotation.y = atan2(out.x, out.z)  # facing -out, up the flight
	for i in 3:
		await get_tree().physics_frame
	var mantled := false
	Input.action_press("move_forward")
	for i in 150:
		await get_tree().physics_frame
		mantled = mantled or player.ledge_climb.busy()
		if player.global_position.y > foot.y + rise - 0.2 and player.is_on_floor():
			break
	Input.action_release("move_forward")
	_check(player.global_position.y > foot.y + rise - 0.2 and not mantled, "the player walks up a staircase without mantling (feet %.2f, top %.2f, mantled %s)" % [player.global_position.y, foot.y + rise, mantled])
	var nav := map.get_world_3d().navigation_map
	var bottom := foot + out * 3.0
	var top := foot - out * 2.0 + Vector3.UP * rise
	var path := NavigationServer3D.map_get_path(nav, bottom, top, true, 1)
	_check(not path.is_empty() and path[path.size() - 1].distance_to(top) < 1.0, "enemies path up a staircase without a climb link")
	await _free_map(map)

## The dungeon's way in is a cracked patch of wall that a few strikes bring down.
func _test_cracked_wall(map: GeneratedMap) -> void:
	var s := map.secret
	_check(s != null and s.access == SecretRoomBuilder.Access.CRACKED and is_instance_valid(s.cracked_wall), "the dungeon's secret hides behind a cracked wall")
	if s == null or not is_instance_valid(s.cracked_wall):
		return
	print("secret host %s is %s the Vault route" % [s.host_cell, "on" if map._path_to_vault().has(s.host_cell) else "off"])
	var wall := s.cracked_wall
	var face := wall.global_transform.basis.z
	var mid := wall.global_position + Vector3.UP * 1.2
	var q := PhysicsRayQueryParameters3D.create(mid + face * 2.0, mid - face * 3.0, 1)
	var player := get_tree().get_first_node_in_group("player") as Player
	q.exclude = [player.get_rid()]
	var space := map.get_world_3d().direct_space_state
	_check(space.intersect_ray(q).get("collider") == wall, "the cracked patch closes the way in")
	for i in CrackedWall.HITS_TO_BREAK:
		wall._last_strike_msec = -100000
		wall.strike()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not is_instance_valid(wall), "%d strikes break the patch" % CrackedWall.HITS_TO_BREAK)
	var hit := space.intersect_ray(q)
	_check(hit.is_empty(), "the way into the secret room is open (hit %s)" % hit.get("collider"))
	_check(bool(map.capture_state()["secret"].get("opened", false)), "a broken patch is remembered for a portal trip")

## From the upper boulder, jumping at the crack while holding forward ends
## up in the outcrop's hollow.
func _test_crack_climb(map: GeneratedMap, label: String) -> void:
	var s := map.secret
	var player := get_tree().get_first_node_in_group("player") as Player
	for node in get_tree().get_nodes_in_group("enemy"):
		(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var n := Vector3(s.crack_dir.x, 0, s.crack_dir.y)
	var out := SecretRoomBuilder.OUTCROP_HALF + 0.3 + SecretRoomBuilder.STEP_SIZE / 2.0 - 0.1
	player.global_position = s.centre + n * out + Vector3.UP * (SecretRoomBuilder.STEP_HEIGHTS[1] + 0.05)
	player.velocity = Vector3.ZERO
	player.rotation.y = atan2(n.x, n.z)  # facing -n, at the crack
	for i in 3:
		await get_tree().physics_frame
	Input.action_press("move_forward")
	Input.action_press("jump")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("jump")
	for i in 150:
		await get_tree().physics_frame
		if player.global_position.y > SecretRoomBuilder.OUTCROP_FLOOR - 0.3 and not player.ledge_climb.busy() and player.is_on_floor():
			break
	Input.action_release("move_forward")
	var flat := Vector2(player.global_position.x - s.centre.x, player.global_position.z - s.centre.z)
	_check(player.global_position.y > SecretRoomBuilder.OUTCROP_FLOOR - 0.3 and flat.length() < SecretRoomBuilder.OUTCROP_HALF, "%s: the player climbs through the outcrop's crack (feet %.2f, %.1f m from its centre)" % [label, player.global_position.y, flat.length()])

## Dunes: up the boulders onto the mesa, down the sinkhole into the cave.
func _test_sinkhole(map: GeneratedMap, label: String) -> void:
	var s := map.secret
	var player := get_tree().get_first_node_in_group("player") as Player
	for node in get_tree().get_nodes_in_group("enemy"):
		(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var n := Vector3(s.step_side.x, 0, s.step_side.y)
	var out := SecretRoomBuilder.MESA_HALF + SecretRoomBuilder.STEP_SIZE / 2.0 - 0.1
	player.global_position = s.centre + n * out + Vector3.UP * (SecretRoomBuilder.STEP_HEIGHTS[1] + 0.05)
	player.velocity = Vector3.ZERO
	player.rotation.y = atan2(n.x, n.z)  # facing the mesa
	for i in 3:
		await get_tree().physics_frame
	Input.action_press("move_forward")
	Input.action_press("jump")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("jump")
	for i in 150:
		await get_tree().physics_frame
		if player.global_position.y > SecretRoomBuilder.OUTCROP_FLOOR - 0.3 and not player.ledge_climb.busy() and player.is_on_floor():
			break
	Input.action_release("move_forward")
	var flat := Vector2(player.global_position.x - s.centre.x, player.global_position.z - s.centre.z)
	_check(player.global_position.y > SecretRoomBuilder.OUTCROP_FLOOR - 0.3 and flat.length() < SecretRoomBuilder.MESA_HALF * 1.42, "%s: the player climbs onto the mesa (feet %.2f, %.1f m from its centre)" % [label, player.global_position.y, flat.length()])
	player.global_position = s.sinkhole_at + Vector3.UP * 0.6
	player.velocity = Vector3.ZERO
	for i in 90:
		await get_tree().physics_frame
	_check(player.global_position.y < 0.5 and player.is_on_floor(), "%s: the sinkhole drops into the cave (feet %.2f)" % [label, player.global_position.y])
	_check(is_instance_valid(s.cracked_wall), "%s: the cave has a cracked wall out" % label)
