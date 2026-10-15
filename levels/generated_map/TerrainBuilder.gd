extends RefCounted
class_name TerrainBuilder
## Geometry for the open MapLayouts (OPEN_FIELD, CANYON). Rooms stay in
## GeneratedMap itself. Everything is plain boxes/ellipsoids with the
## tileset's ground and wall materials, built into `map`.

const DUNE_MOUND_RADIUS := Vector2(4.0, 7.5)
const DUNE_MOUND_HEIGHT := Vector2(1.6, 3.2)   # full ellipsoid height; a quarter of it shows
const DUNE_MOUND_SINK := 0.25                   # fraction of height the centre sits below ground
const MOUNDS_PER_CELL := Vector2i(1, 3)
const RIDGE_RADIUS := 7.0
const RIDGE_HEIGHT := 10.0
const RIDGE_SPACING := 8.0
const BOUNDARY_WALL_HEIGHT := 14.0

const CLIFF_STEP := 3.2
const CLIFF_LENGTH := Vector2(4.0, 5.5)
const CLIFF_DEPTH := Vector2(2.5, 4.0)
const CLIFF_HEIGHT := Vector2(6.0, 10.0)
const CLIFF_JITTER := 0.7
const CLIFF_YAW_JITTER_DEG := 12.0
const PASS_WIDTH := Vector2(8.0, 12.0)
const PASS_END_MARGIN := 2.5
const CORNER_PILLAR_SIZE := 4.5

const DAIS_RADIUS := 5.0
const DAIS_RAMP_LENGTH := 5.5
const DAIS_RAMP_WIDTH := 3.5
const DAIS_RAMP_THICKNESS := 0.5

## Loose doodads keep this far from a cell centre (packs gather there) and
## from the player spawn.
const SCATTER_MIN_FROM_CENTRE := 6.5
const SCATTER_MIN_FROM_SPAWN := 6.0

var _map: GeneratedMap
var _floor_mat: Material
var _wall_mat: Material
var cliff_count := 0

func _init(map: GeneratedMap, floor_mat: Material, wall_mat: Material) -> void:
	_map = map
	_floor_mat = floor_mat
	_wall_mat = wall_mat

## ---- Dunes: one open field ------------------------------------------------

func build_open_field(graph: MapGraph, cell_size: float) -> void:
	var extent := cell_size * graph.grid_size
	var centre := Vector3((graph.grid_size - 1) * cell_size / 2.0, 0.0, (graph.grid_size - 1) * cell_size / 2.0)
	_map._build_floor(centre, extent, extent, 0.0, GeneratedMap.ROOM_FLOOR_COLORS[0])
	for cell in graph.rooms:
		if _map.room_floor.has(cell):
			_map._build_terrace(_map.terrace_rect(cell), _map.room_floor[cell])
	if not (_map.tileset and _map.tileset.building_boundary):
		_build_ridge_boundary(centre, extent)
		_build_ridge_fins(graph, cell_size)
	_map._link_terraces()
	_reserve_link_ends()
	for cell in graph.rooms:
		var room: MapGraph.RoomData = graph.rooms[cell]
		if room.is_start or room.is_vault:
			continue
		for i in randi_range(_map.layout.mounds_per_cell.x, _map.layout.mounds_per_cell.y):
			var offset := Vector3(randf_range(-0.45, 0.45), 0.0, randf_range(-0.45, 0.45)) * cell_size
			var pos := _map._cell_to_world(cell) + offset
			pos.y = _map.terrace_top(pos)
			# Mounds stay out of rivers and streams (radius up to ~7.5 m, scaled).
			if _map.water and _map.water.is_wet(pos, DUNE_MOUND_RADIUS.y * _map.layout.mound_scale):
				continue
			if _map.secret and _map.secret.blocks(pos):
				continue
			_build_mound(pos)

## A mound never reaches a terrace face: banked against one it would be a
## ramp up past the ledge, and on top it would bury the climb links.
func _build_mound(pos: Vector3) -> void:
	var radius := randf_range(DUNE_MOUND_RADIUS.x, DUNE_MOUND_RADIUS.y) * _map.layout.mound_scale
	var height := randf_range(DUNE_MOUND_HEIGHT.x, DUNE_MOUND_HEIGHT.y) * _map.layout.mound_scale
	var room := _face_clearance(pos) - 1.5
	if room < radius:
		if room < DUNE_MOUND_RADIUS.x * 0.5:
			return
		height *= room / radius
		radius = room
	_add_ellipsoid(pos + Vector3(0, -height * DUNE_MOUND_SINK, 0), radius, height, _floor_mat, pos.y)

## Distance from pos to the nearest terrace face: the edge of the terrace
## it stands on, or of any higher one.
func _face_clearance(pos: Vector3) -> float:
	var p := Vector2(pos.x, pos.z)
	var best := INF
	for t in _map.terraces:
		var r: Rect2 = t["rect"]
		if r.has_point(p):
			best = minf(best, minf(minf(p.x - r.position.x, r.end.x - p.x), minf(p.y - r.position.y, r.end.y - p.y)))
		elif float(t["top"]) > pos.y + 0.1:
			var closest := p.clamp(r.position, r.end)
			best = minf(best, p.distance_to(closest))
	return best

## Nothing loose lands on a climb link's ends.
func _reserve_link_ends() -> void:
	if _map._dresser == null:
		return
	for child in _map.get_children():
		if child is NavigationLink3D:
			for p in [child.start_position, child.end_position]:
				_map._dresser.reserve(Rect2(Vector2(p.x, p.z) - Vector2.ONE * 1.6, Vector2.ONE * 3.2))

## Tall dune ridges along every edge, plus an invisible wall just outside so
## nothing walks over a ridge and off the field.
func _build_ridge_boundary(centre: Vector3, extent: float) -> void:
	var half := extent / 2.0
	var count := int(ceil(extent / RIDGE_SPACING)) + 1
	for side in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var along := Vector3(side.z, 0, side.x).abs()
		for i in count:
			var t := -half + i * RIDGE_SPACING
			var pos: Vector3 = centre + side * (half + 1.5) + along * t
			pos.y = _map.terrace_top(pos - side * 4.5)
			_add_ellipsoid(pos, RIDGE_RADIUS * randf_range(0.85, 1.2), RIDGE_HEIGHT * randf_range(0.8, 1.15), _wall_mat if _wall_mat else _floor_mat, 0.0, true)
		var wall_size := Vector3(extent + 8.0, BOUNDARY_WALL_HEIGHT, 1.0) if side.z != 0.0 else Vector3(1.0, BOUNDARY_WALL_HEIGHT, extent + 8.0)
		_add_invisible_wall(centre + side * (half + 3.0) + Vector3(0, BOUNDARY_WALL_HEIGHT / 2.0, 0), wall_size)

## Where a terrace face meets the boundary, the ridges either side of it
## would make a slope from one level to the other: an invisible no_climb fin
## along the face, from inside the ridges' reach out to the boundary wall,
## keeps the ledge the only way up.
const RIDGE_FIN_REACH := 8.0

func _build_ridge_fins(graph: MapGraph, cell_size: float) -> void:
	var last := graph.grid_size - 1
	for cell in graph.rooms:
		for d in [Vector2i.RIGHT, Vector2i.DOWN]:
			var n: Vector2i = cell + d
			if not graph.rooms.has(n) or is_equal_approx(float(_map.room_floor.get(cell, 0.0)), float(_map.room_floor.get(n, 0.0))):
				continue
			var low: Vector2i = n if float(_map.room_floor.get(cell, 0.0)) > float(_map.room_floor.get(n, 0.0)) else cell
			var to_low := Vector3(low.x - (cell.x + n.x - low.x), 0, low.y - (cell.y + n.y - low.y)).normalized()
			var face := (_map._cell_to_world(cell) + _map._cell_to_world(n)) / 2.0
			face.y = 0.0
			# The boundary sides both cells share: across the face's line.
			var across := Vector2i(absi(d.y), absi(d.x))
			for s in [-1, 1]:
				var c: int = cell.x if across.x != 0 else cell.y
				if (s < 0 and c != 0) or (s > 0 and c != last):
					continue
				var out: Vector3 = Vector3(across.x, 0, across.y) * s
				var inner := cell_size / 2.0 - RIDGE_FIN_REACH
				var outer := cell_size / 2.0 + 3.0
				var mid: Vector3 = face + out * (inner + outer) / 2.0 + to_low * 0.25 + Vector3.UP * BOUNDARY_WALL_HEIGHT / 2.0
				var size := Vector3(0.5, BOUNDARY_WALL_HEIGHT, outer - inner) if across.x == 0 else Vector3(outer - inner, BOUNDARY_WALL_HEIGHT, 0.5)
				_add_invisible_wall(mid, size)

## ---- Badlands: basins, passes and cliffs ----------------------------------

## Raised basins (GeneratedMap.room_floor) stand on a plinth, so the pass
## into one ends at a ledge to mantle; cliffs grow by the higher side's lift.
func build_canyon(graph: MapGraph, cell_size: float) -> void:
	var half := cell_size / 2.0
	var corners := {}
	var done := {}
	for cell in graph.rooms:
		var origin := _map._cell_to_world(cell)
		var ground := Vector3(origin.x, 0.0, origin.z)
		if origin.y > 0.0:
			_map._build_terrace(Rect2(origin.x - half, origin.z - half, cell_size, cell_size), origin.y)
		else:
			_map._build_floor(origin, cell_size, cell_size, 0.0, GeneratedMap.ROOM_FLOOR_COLORS[0])
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var neighbor: Vector2i = cell + dir
			var key := _map._pair_key(cell, neighbor)
			if done.has(key):
				continue
			done[key] = true
			var edge_centre := ground + Vector3(dir.x, 0, dir.y) * half
			var along := Vector3(absi(dir.y), 0, absi(dir.x))
			var lift := maxf(origin.y, _map.room_floor.get(neighbor, 0.0))
			if graph.has_connection(cell, neighbor):
				var gap := _build_pass(edge_centre, along, cell_size, lift)
				var other: float = _map.room_floor.get(neighbor, 0.0)
				if not is_equal_approx(origin.y, other):
					var out := Vector3(dir.x, 0, dir.y) * (1.0 if origin.y > other else -1.0)
					_map._add_climb_link(gap + out * 1.1 + Vector3.UP * minf(origin.y, other), gap - out * 1.1 + Vector3.UP * lift)
			else:
				_build_cliff_line(edge_centre - along * half, edge_centre + along * half, lift)
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var p := ground + Vector3(corner.x, 0, corner.y) * half
			var k := Vector2i(roundi(p.x), roundi(p.z))
			corners[k] = {"at": p, "lift": maxf(origin.y, float(corners[k]["lift"]) if corners.has(k) else 0.0)}
	for c in corners.values():
		_add_cliff_block(c["at"], Vector3(CORNER_PILLAR_SIZE, randf_range(CLIFF_HEIGHT.x, CLIFF_HEIGHT.y) * _map.layout.cliff_height_scale + float(c["lift"]), CORNER_PILLAR_SIZE), randf() * TAU)
	_reserve_link_ends()

## Cliffs along a connected edge, leaving one opening somewhere along it.
## Returns the opening's centre.
func _build_pass(edge_centre: Vector3, along: Vector3, cell_size: float, lift: float = 0.0) -> Vector3:
	var half := cell_size / 2.0
	var width := randf_range(PASS_WIDTH.x, PASS_WIDTH.y) * _map.layout.pass_width_scale
	var slack := half - width / 2.0 - PASS_END_MARGIN
	var offset := randf_range(-slack, slack) if slack > 0.0 else 0.0
	var gap_lo := offset - width / 2.0
	var gap_hi := offset + width / 2.0
	_build_cliff_line(edge_centre - along * half, edge_centre + along * gap_lo, lift)
	_build_cliff_line(edge_centre + along * gap_hi, edge_centre + along * half, lift)
	return edge_centre + along * offset

func _build_cliff_line(from: Vector3, to: Vector3, lift: float = 0.0) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var dir := (to - from) / length
	var normal := Vector3(dir.z, 0, -dir.x)
	var base_yaw := atan2(dir.x, dir.z)
	var t := 0.0
	while t < length:
		var block_len := minf(randf_range(CLIFF_LENGTH.x, CLIFF_LENGTH.y), length - t + 1.0)
		var pos := from + dir * (t + block_len / 2.0) + normal * randf_range(-CLIFF_JITTER, CLIFF_JITTER)
		var size := Vector3(randf_range(CLIFF_DEPTH.x, CLIFF_DEPTH.y), randf_range(CLIFF_HEIGHT.x, CLIFF_HEIGHT.y) * _map.layout.cliff_height_scale + lift, block_len)
		_add_cliff_block(pos, size, base_yaw + deg_to_rad(randf_range(-CLIFF_YAW_JITTER_DEG, CLIFF_YAW_JITTER_DEG)))
		t += CLIFF_STEP

func _add_cliff_block(pos: Vector3, size: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	LedgeClimb.forbid(body)
	body.position = pos + Vector3(0, size.y / 2.0 - 0.3, 0)
	body.rotation.y = yaw
	_map.add_child(body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	if _wall_mat:
		mesh.material_override = _wall_mat
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	cliff_count += 1

## ---- Shared ----------------------------------------------------------------

## A raised round platform with ramps on two opposite sides, for the boss.
## Returns where the boss stands.
func build_dais(centre: Vector3, height: float, material: Material) -> Vector3:
	var body := StaticBody3D.new()
	body.position = centre + Vector3(0, height / 2.0, 0)
	_map.add_child(body)
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = DAIS_RADIUS
	cylinder.bottom_radius = DAIS_RADIUS + 0.6
	cylinder.height = height
	mesh.mesh = cylinder
	mesh.material_override = material
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = DAIS_RADIUS
	shape.height = height
	collision.shape = shape
	body.add_child(collision)

	var slope := atan2(height, DAIS_RAMP_LENGTH)
	var ramp_len := sqrt(DAIS_RAMP_LENGTH * DAIS_RAMP_LENGTH + height * height) + 0.6
	var yaw0 := randf() * TAU
	for i in 2:
		var yaw := yaw0 + PI * i
		var out := Vector3(sin(yaw), 0, cos(yaw))
		var ramp := StaticBody3D.new()
		ramp.position = centre + out * (DAIS_RADIUS + DAIS_RAMP_LENGTH / 2.0 - 0.3) + Vector3(0, height / 2.0 - DAIS_RAMP_THICKNESS / 2.0, 0)
		ramp.rotation = Vector3(slope, yaw, 0)
		_map.add_child(ramp)
		var size := Vector3(DAIS_RAMP_WIDTH, DAIS_RAMP_THICKNESS, ramp_len)
		var rm := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = size
		rm.mesh = rb
		rm.material_override = material
		ramp.add_child(rm)
		var rc := CollisionShape3D.new()
		var rs := BoxShape3D.new()
		rs.size = size
		rc.shape = rs
		ramp.add_child(rc)
	return centre + Vector3(0, height + 0.05, 0)  # enemy origins are at the feet

## Forests: a tree line just inside the boundary ridges, so the edge reads
## as woods rather than bare mounds.
const TREE_LINE_SPACING := 5.0
const TREE_LINE_INSET := Vector2(8.5, 12.0)  # clear of the boundary ridges, which reach ~6 m in

func build_tree_line(dresser: RoomDresser, tileset: MapTileset, graph: MapGraph, cell_size: float) -> void:
	if dresser == null or tileset == null:
		return
	var trees := tileset.floor_props.filter(func(s: PackedScene): return s != null and s.resource_path.get_file().to_lower().contains("tree"))
	if trees.is_empty():
		return
	var extent := cell_size * graph.grid_size
	var half := extent / 2.0
	var centre := Vector3((graph.grid_size - 1) * cell_size / 2.0, 0.0, (graph.grid_size - 1) * cell_size / 2.0)
	for side in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var along := Vector3(side.z, 0, side.x).abs()
		var t := -half
		while t <= half:
			var inset := randf_range(TREE_LINE_INSET.x, TREE_LINE_INSET.y)
			var pos: Vector3 = centre + side * (half - inset) + along * (t + randf_range(-1.5, 1.5))
			pos.y = _map.terrace_top(pos)
			dresser.place_loose(pos, trees.pick_random())
			t += TREE_LINE_SPACING * randf_range(0.7, 1.3)

func scatter_doodads(dresser: RoomDresser, tileset: MapTileset, graph: MapGraph, cell_size: float, count_range: Vector2i, spawn: Vector3) -> void:
	if dresser == null or tileset == null:
		return
	var pool: Array = []
	pool.append_array(tileset.clusters)
	pool.append_array(tileset.floor_props)
	pool = pool.filter(func(s): return s != null)
	if pool.is_empty():
		return
	var max_off := cell_size / 2.0 - 2.5
	for cell in graph.rooms:
		var room: MapGraph.RoomData = graph.rooms[cell]
		if room.is_start or room.is_vault:
			continue
		var centre := _map._cell_to_world(cell)
		for i in randi_range(count_range.x, count_range.y):
			for attempt in 6:
				var offset := Vector3(randf_range(-max_off, max_off), 0, randf_range(-max_off, max_off))
				if offset.length() < SCATTER_MIN_FROM_CENTRE or (centre + offset).distance_to(spawn) < SCATTER_MIN_FROM_SPAWN:
					continue
				var at := centre + offset
				at.y = _map.terrace_top(at)
				if dresser.place_loose(at, pool.pick_random()):
					break

## ground: the level it stands on (a terrace top). Ridges are boundary, so no_climb.
func _add_ellipsoid(pos: Vector3, radius: float, height: float, material: Material, ground: float = 0.0, no_climb: bool = false) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = height
	sphere.radial_segments = 24
	sphere.rings = 10
	var body := StaticBody3D.new()
	body.position = pos
	if no_climb:
		LedgeClimb.forbid(body)
	_map.add_child(body)
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	if material:
		mesh.material_override = material
	body.add_child(mesh)
	# Collide against a sphere cap fitted to the part above the ground
	# (y = ground): a capsule sliding over a convex hull of the mesh cost
	# 0.5-2.5ms per move_and_slide, so packs standing on mounds dragged the
	# Dunes to single-digit fps. Sphere collisions are close to free.
	var half := height / 2.0
	var sunk := pos.y - ground
	var cap_height := half + sunk
	if cap_height <= 0.0:
		return
	var ground_t := clampf(-sunk / half, -1.0, 1.0)
	var footprint := radius * sqrt(1.0 - ground_t * ground_t)
	var shape := SphereShape3D.new()
	shape.radius = (footprint * footprint + cap_height * cap_height) / (2.0 * cap_height)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0, half - shape.radius, 0)  # tops coincide
	body.add_child(collision)

func _add_invisible_wall(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	LedgeClimb.forbid(body)
	body.position = pos
	_map.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
