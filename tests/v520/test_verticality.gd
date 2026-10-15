extends Node
## v5.2 verticality: raised dungeon rooms with climb links, the player
## mantling onto one and catching a ledge, an enemy hopping up after the
## player, secret rooms in each layout, the Watcher's deal and challenge,
## the timed gate.
## Run: Godot --headless --path . res://tests/v520/test_verticality.tscn --quit-after 20000

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
	while (map.nav_region == null or map.nav_region.navigation_mesh == null) and frames < 1200:
		await get_tree().physics_frame
		frames += 1
	for i in 3:
		await get_tree().physics_frame

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	await _test_dungeon()
	for style in ["desert_dunes", "desert_badlands", "city_downtown"]:
		await _test_outdoor(style)
	await _test_gate()
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
	var player := get_tree().get_first_node_in_group("player") as Player
	for node in get_tree().get_nodes_in_group("enemy"):
		(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
	if links.size() > 0:
		var link := links[0]
		var low := link.start_position
		var high := link.end_position
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
		Input.action_release("move_forward")
		_check(player.global_position.y > high.y - 0.3, "the player mantles onto a raised room (feet at %.2f, ledge %.2f)" % [player.global_position.y, high.y])
		# Without forward held, falling face-on past the ledge catches it.
		var face := low + dir * 0.4
		player.global_position = Vector3(face.x, high.y - 1.6, face.z)
		player.velocity = Vector3(0, -1.0, 0)
		player.rotation.y = atan2(-dir.x, -dir.z)
		var caught := false
		for i in 20:
			await get_tree().physics_frame
			caught = caught or player.ledge_climb.state == LedgeClimb.State.HANG
		_check(caught, "falling against the ledge catches it")
		Input.action_press("crouch")
		await get_tree().physics_frame
		await get_tree().physics_frame
		Input.action_release("crouch")
		_check(not player.ledge_climb.busy(), "crouch lets go of the ledge")
		# An enemy below the step hops up after a player standing on it.
		player.global_position = high + dir * 2.5 + Vector3.UP * 0.05
		player.set_physics_process(false)
		var chaser: Enemy = null
		for node in get_tree().get_nodes_in_group("enemy"):
			var e := node as Enemy
			if e and e.rank != Constants.EnemyRank.BOSS and not e.is_ranged_unit():
				chaser = e
				break
		_check(chaser != null, "found a melee enemy to chase")
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
			_check(chaser.global_position.y > high.y - 0.4, "an enemy climbs the step after the player (y %.2f after %d frames)" % [chaser.global_position.y, frames])
			chaser.process_mode = Node.PROCESS_MODE_DISABLED
		player.set_physics_process(true)
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
		_check(style == "city_downtown", "%s has a secret spire" % style)
		print("note: %s rolled no plaza, so no spire" % style)
	else:
		_check(map.secret.access == SecretRoomBuilder.Access.SPIRE, "%s's secret is a spire" % style)
		var c := map.secret.chamber_centre + Vector3(1.3, 0, 1.3)  # beside the encounter
		var q := PhysicsRayQueryParameters3D.create(c + Vector3.UP * 1.5, c + Vector3.DOWN * 3.0, 1)
		var hit := map.get_world_3d().direct_space_state.intersect_ray(q)
		_check(not hit.is_empty() and absf(hit["position"].y - SecretRoomBuilder.SPIRE_FLOOR) < 0.2, "%s's spire chamber has a floor up top (hit %s)" % [style, hit.get("position", "none")])
		var inside := 0
		for node in get_tree().get_nodes_in_group("enemy"):
			if map.secret.blocks((node as Node3D).global_position) and (node as Node3D).global_position.y < 3.0:
				inside += 1
		_check(inside == 0, "%s: no pack spawns inside the spire" % style)
	await _free_map(map)

func _test_gate() -> void:
	var gate := SecretGate.new()
	add_child(gate)
	gate.open_for(0.5)
	for i in 30:
		await get_tree().physics_frame
	_check(gate.position.y > 2.0, "the gate lifts (%.2f)" % gate.position.y)
	for i in 90:
		await get_tree().physics_frame
	_check(not gate.is_open() and gate.position.y < 0.1, "the gate drops again when time runs out")
	gate.queue_free()
