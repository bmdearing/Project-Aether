extends Node
## Headless checks for the v4.73 City family (StreetBuilder): every style
## builds with buildings along its streets, every street edge is sealed (a
## ray out of the street always hits a wall or building), the boss
## courtyard and every pack spot are reachable on the navmesh, packs stand
## clear of walls, plus the per-style extras (rails, harbor, the Park's
## building ring) and per-band tree points with the City family.
## Run: Godot --headless --path . res://tests/v473/test_v473.tscn --quit-after 12000
## Exits 0 when every check passes. Never writes the save file.

const MAP := "res://levels/generated_map/GeneratedMap.tscn"
const STREET_STYLES := ["city_residence", "city_downtown", "city_trainyard", "city_harbor"]
const SEEDS := [11, 29]

var _checks := 0
var _failures := 0
var _finished := 0
const TEST_COUNT := 3

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _run() -> void:
	GameState.reset_to_defaults()
	GameState.game_started = false
	_test_family()
	await _test_streets()
	await _test_park()
	_check(_finished == TEST_COUNT, "every test function ran to the end (%d/%d)" % [_finished, TEST_COUNT])
	print("v4.73 tests: %d checks, %d failures" % [_checks, _failures])
	GameState.active_map = null
	get_tree().quit(1 if _failures > 0 else 0)

func _test_family() -> void:
	var city := Array(MapTileset.all_ids()).filter(func(id: String): return MapTileset.family_of(id) == "city")
	_check(city.size() == 5, "five City styles (%s)" % [city])
	_check(MapTileset.FAMILIES.has("city"), "City is a family")
	_check(FigmentTree.get_node_by_id("city_notable") != null, "the tree can steer toward City Figments")
	for id in city:
		var style := MapTileset.load_style(id)
		_check(style != null and not style.buildings.is_empty(), "%s has buildings" % id)
	_finished += 1

func _build(style_id: String, map_seed: int) -> GeneratedMap:
	var figment := FigmentItem.new()
	figment.tileset_id = style_id
	GameState.active_map = figment
	GameState.portal_map_state = {"seed": map_seed, "tileset_id": style_id}
	GameState.returning_through_portal = true
	var map: GeneratedMap = load(MAP).instantiate()
	add_child(map)
	return map

func _test_streets() -> void:
	for style_id in STREET_STYLES:
		for map_seed in SEEDS:
			var map := _build(style_id, map_seed)
			await _frames(6)
			var label := "%s/%d" % [style_id, map_seed]
			var sb := map.streets
			_check(sb != null and map.layout.kind == MapLayout.Kind.STREETS, "%s uses the streets layout" % label)
			if sb == null:
				map.queue_free()
				continue
			_check(sb.building_count >= sb.edges.size() / 2, "%s lines its streets (%d buildings, %d edges)" % [label, sb.building_count, sb.edges.size()])
			_check(sb.lamp_count > 4, "%s has street lamps (%d)" % [label, sb.lamp_count])
			_check(map.get_living_enemy_count() > 10, "%s spawns packs (%d)" % [label, map.get_living_enemy_count()])
			_check(map.has_boss(), "%s has its boss" % label)
			_check_sealed(map, label)
			_check_spawns_clear(map, label)
			var waited := 0
			while map.nav_region.navigation_mesh == null and waited < 600:
				await get_tree().physics_frame
				waited += 1
			# The region only reaches queries after the nav map's next sync.
			var nav_map := map.get_world_3d().navigation_map
			var iteration := NavigationServer3D.map_get_iteration_id(nav_map)
			for i in 600:
				await get_tree().physics_frame
				if NavigationServer3D.map_get_iteration_id(nav_map) != iteration and NavigationServer3D.map_get_closest_point(nav_map, map._cell_to_world(map.graph.start_cell)) != Vector3.ZERO:
					break
			_check_reachable(map, label)
			if style_id == "city_trainyard":
				_check(map.get_node_or_null("Sleepers") != null, "%s lays rails" % label)
			if style_id == "city_harbor" and sb._water_side != Vector2i.ZERO:
				_check(map.get_node_or_null("Harbor") != null, "%s has its harbor" % label)
				for cell in map.graph.rooms:
					var room: MapGraph.RoomData = map.graph.rooms[cell]
					if sb._on_water_line(cell):
						_check(not room.is_start and not room.is_vault, "%s keeps the start and boss off the waterfront" % label)
			map.queue_free()
			await _frames(3)
	_finished += 1

## Rays from just inside each edge, straight out of the street, must hit a
## wall or building within the setback: at both ends and along the middle.
func _check_sealed(map: GeneratedMap, label: String) -> void:
	var space := map.get_world_3d().direct_space_state
	var leaks := 0
	for e in map.streets.edges:
		var from: Vector3 = e["from"]
		var to: Vector3 = e["to"]
		var n: Vector3 = e["normal"]
		var length := from.distance_to(to)
		var along := (to - from).normalized()
		# Near an end a ray may run out into the neighbouring street's
		# setback nook, which is fine; sample the edge's interior.
		var margin := StreetBuilder.WALL_SETBACK + 0.5
		if length < margin * 2.0:
			continue
		for t in [margin, length * 0.5, length - margin]:
			var origin: Vector3 = from + along * t + n * 0.3 + Vector3(0, 1.2, 0)
			var reach := StreetBuilder.WALL_SETBACK + StreetBuilder.WALL_THICKNESS + 1.0
			var query := PhysicsRayQueryParameters3D.create(origin, origin - n * reach)
			if space.intersect_ray(query).is_empty():
				if leaks == 0:
					print("  open ray at ", origin, " toward ", -n, " edge ", from, "->", to)
				leaks += 1
	_check(leaks == 0, "%s: every street edge is closed (%d open rays)" % [label, leaks])

func _check_spawns_clear(map: GeneratedMap, label: String) -> void:
	var space := map.get_world_3d().direct_space_state
	var blocked := 0
	for p in map.streets.spawn_points:
		var shape := SphereShape3D.new()
		shape.radius = 0.6
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis(), p + Vector3(0, 1.0, 0))
		query.collision_mask = 1
		for hit in space.intersect_shape(query, 8):
			if not hit["collider"] is CharacterBody3D:
				print("  pack spot ", p, " blocked by ", (hit["collider"] as Node).get_parent().scene_file_path)
				blocked += 1
				break
	_check(blocked == 0, "%s: pack spots are clear of walls and props (%d blocked)" % [label, blocked])

func _check_reachable(map: GeneratedMap, label: String) -> void:
	var nav := map.get_world_3d().navigation_map
	var start := map._cell_to_world(map.graph.start_cell)
	var targets: Array[Vector3] = [map._cell_to_world(map.graph.vault_cell)]
	targets.append_array(map.streets.spawn_points)
	var unreachable := 0
	for target in targets:
		var path := NavigationServer3D.map_get_path(nav, start, target, true)
		if path.is_empty() or path[path.size() - 1].distance_to(target) > 2.5:
			if unreachable == 0:
				print("  no path ", start, " -> ", target, " size ", path.size(), " end ", path[path.size() - 1] if not path.is_empty() else Vector3.INF, " closest start ", NavigationServer3D.map_get_closest_point(nav, start))
			unreachable += 1
	_check(unreachable == 0, "%s: the courtyard and every pack spot are reachable (%d not)" % [label, unreachable])

func _test_park() -> void:
	var map := _build("city_park", 5)
	await _frames(6)
	_check(map.layout.kind == MapLayout.Kind.OPEN_FIELD, "the Park is an open field")
	_check(map.streets != null and map.streets.building_count > 12, "the Park is ringed with buildings (%d)" % (map.streets.building_count if map.streets else 0))
	var space := map.get_world_3d().direct_space_state
	var centre := map._cell_to_world(Vector2i(map.graph.grid_size / 2, map.graph.grid_size / 2)) + Vector3(0, 1.2, 0)
	var open := 0
	for i in 16:
		var dir := Vector3(cos(TAU * i / 16.0), 0, sin(TAU * i / 16.0))
		var query := PhysicsRayQueryParameters3D.create(centre, centre + dir * map.cell_size * map.graph.grid_size)
		if space.intersect_ray(query).is_empty():
			open += 1
	_check(open == 0, "the Park's ring is closed (%d open directions)" % open)
	# A City Figment counts toward its band like any other style.
	GameState.figment_completions = {}
	_check(FigmentProgress.record("city_park", 3) and FigmentProgress.points_earned() == 1, "City Figments earn tree points")
	map.queue_free()
	await _frames(3)
	_finished += 1
