extends Node
## Windowed perf probe: builds a Dunes figment, tops it up to TARGET_ENEMIES,
## then logs frame/process/physics/render numbers for a few phases.
## Run windowed (real GPU): godot --path . res://tests/perf/perf_dunes.tscn

const MAP := "res://levels/generated_map/GeneratedMap.tscn"
const TARGET_ENEMIES := 64
const SAMPLE_SEC := 4.0

var map: GeneratedMap

func _ready() -> void:
	var figment := FigmentRoller.roll(1)
	figment.tileset_id = "desert_dunes"
	GameState.active_map = figment
	map = load(MAP).instantiate()
	add_child(map)
	await _frames(10)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var cells: Array = map.graph.rooms.keys()
	while map.get_living_enemy_count() < TARGET_ENEMIES:
		map._spawn_pack(EnemyRoster.roll_pack(Constants.ENEMY_PACKS_NORMAL), map._cell_to_world(cells.pick_random()))
	var player := get_tree().get_first_node_in_group("player") as Player
	print("PERF enemies=%d nodes=%d" % [map.get_living_enemy_count(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	# Face the middle of the field so most of it is on screen.
	var centre: Vector3 = map._cell_to_world(Vector2i(map.graph.grid_size / 2, map.graph.grid_size / 2))
	player.look_at(Vector3(centre.x, player.global_position.y, centre.z), Vector3.UP)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	await _sample("baseline")
	var slide_total := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		var t := Time.get_ticks_usec()
		e.move_and_slide()
		slide_total += Time.get_ticks_usec() - t
	print("PERF one move_and_slide for every enemy: %dus" % slide_total)
	for e in get_tree().get_nodes_in_group("enemy"):
		if e._anim_controller:
			e._anim_controller.set_process(false)
	await _sample("anim_off")
	for e in get_tree().get_nodes_in_group("enemy"):
		if e._anim_controller:
			e._anim_controller.set_process(true)
		e.set_physics_process(false)
	await _sample("enemy_physics_off")
	for e in get_tree().get_nodes_in_group("enemy"):
		e.set_physics_process(true)
		e.set_process(false)
	await _sample("enemy_process_off")
	for e in get_tree().get_nodes_in_group("enemy"):
		e.set_process(true)
	var enemies := get_tree().get_nodes_in_group("enemy")
	for e in enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED
	await _sample("enemies_paused")
	for e in enemies:
		e.process_mode = Node.PROCESS_MODE_INHERIT
		e.visible = false
	await _sample("enemies_hidden")
	for e in enemies:
		e.visible = true
	var sun := _find_sun(map)
	if sun:
		sun.shadow_enabled = false
		await _sample("no_sun_shadow")
		sun.shadow_enabled = true
	for e in enemies:
		e.queue_free()
	await _frames(3)
	await _sample("no_enemies")
	print("PERF_DONE")
	get_tree().quit()

func _find_sun(n: Node) -> DirectionalLight3D:
	for c in n.find_children("*", "DirectionalLight3D", true, false):
		return c
	return null

func _sample(label: String) -> void:
	await _frames(20)
	var frames := 0
	var t0 := Time.get_ticks_usec()
	var proc := 0.0
	var phys := 0.0
	var draws := 0.0
	var objects := 0.0
	var prims := 0.0
	while Time.get_ticks_usec() - t0 < SAMPLE_SEC * 1000000.0:
		await get_tree().process_frame
		frames += 1
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	print("PERF %-15s fps=%5.1f frame=%5.2fms process=%5.2fms physics=%5.2fms draws=%5.0f objects=%5.0f prims=%7.0f" % [
		label, 1000.0 / ms, ms, proc / frames * 1000.0, phys / frames * 1000.0, draws / frames, objects / frames, prims / frames])

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
