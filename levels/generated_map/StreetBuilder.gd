extends RefCounted
class_name StreetBuilder
## City (STREETS) layout geometry. Every MapGraph cell is an open square:
## a street-wide junction, a wider plaza, the start square or the boss
## courtyard. Every connection is a street between two squares. The edges of
## that walkable shape get a solid wall just behind them, and buildings
## (MapTileset.buildings, front = +X) line the walls facing the street, so
## the walls only show in the gaps. Lamps, props, steam vents, rails
## (Trainyard) and a waterfront (Harbor) dress it. Packs stand at
## spawn_points, which props keep clear of.

## Collision height; the visible wall is lower so short buildings in front
## of it (warehouses) aren't topped by bare wall.
const WALL_HEIGHT := 6.0
const WALL_VISIBLE_HEIGHT := 3.5
const WALL_THICKNESS := 1.0
## Walls stand this far behind the street line: building bounds include their
## eaves, and the facade itself sits a metre or two behind them.
const WALL_SETBACK := 2.5
## Building collision stops this far short of the bounds' front (the eaves).
const EAVE_DEPTH := 1.0
## Building fronts stand this far in front of the wall face.
const FRONT_PROTRUDE := 0.25
const BUILDING_GAP := 0.2
const MIN_FILL := 2.5
## Buildings may run this far past a square's corner (into the solid block
## behind the next wall), so short corner segments still get a facade.
const CORNER_OVERHANG := 4.0
## A building may shrink to this share of its scale to close a gap.
const MIN_FIT_SCALE := 0.7
const START_HALF := 8.0
const PLAZA_HALF := Vector2(10.0, 12.0)
const COURTYARD_HALF := 13.0
const SCALE_JITTER := Vector2(0.95, 1.08)
const LANDMARK_CHANCE := 0.5
const LAMP_SPACING := 12.0
const LAMP_INSET := 1.1
const MAX_LAMP_LIGHTS := 16
const PROP_DENSITY := 0.07         # loose props per metre of edge
const PROP_INSET := Vector2(1.2, 2.4)
const STREET_SPAWN_MIN_LENGTH := 12.0
const SPAWN_CLEAR := 3.0
const RAIL_GAUGE := 1.5
const SLEEPER_SPACING := 0.8
const QUAY_HEIGHT := 0.8
const WATER_REACH := 45.0
const PIER_SPACING := 12.0

var half: Dictionary = {}               # cell -> square half-size
## Boundary segments: {from, to, normal (into the street), grand, water}.
var edges: Array[Dictionary] = []
var spawn_points: Array[Vector3] = []
var building_count := 0
var lamp_count := 0
var vent_count := 0

var _map: GeneratedMap
var _tileset: MapTileset
var _dresser: RoomDresser
var _wall_mat: Material
var _street_w: float
var _bounds: Dictionary = {}            # PackedScene -> AABB
## Harbor: which side of the map is water, and the outermost row/column on it.
var _water_side := Vector2i.ZERO
## Squares and streets (XZ), so a deep building can't reach through a thin
## block into the street or plaza behind it.
var _walkable: Array[Rect2] = []
var _water_line := 0

func _init(map: GeneratedMap, tileset: MapTileset, dresser: RoomDresser, wall_mat: Material) -> void:
	_map = map
	_tileset = tileset
	_dresser = dresser
	_wall_mat = wall_mat

func build(graph: MapGraph, cell_size: float) -> void:
	_street_w = _map.layout.street_width
	if _tileset.waterfront:
		_pick_water_side(graph)
	_plan_squares(graph)
	var extent := cell_size * graph.grid_size
	var centre := Vector3((graph.grid_size - 1) * cell_size / 2.0, 0.0, (graph.grid_size - 1) * cell_size / 2.0)
	_map._build_floor(centre, extent, extent, 0.0, GeneratedMap.ROOM_FLOOR_COLORS[0])
	_collect_edges(graph)
	_plan_spawns(graph)
	for e in edges:
		if e["water"]:
			_build_quay(e)
		else:
			_build_wall(e)
			_line_with_buildings(e)
	if _water_side != Vector2i.ZERO:
		_build_harbor(graph, cell_size)
	_dress_squares(graph)
	_place_vents()
	_place_lamps()
	_scatter_props()
	if _tileset.rails:
		_lay_rails(graph)

## Line an arbitrary closed edge list (the Park's boundary) with walls and
## buildings: every segment faces `normal`.
func line_edges(segments: Array[Dictionary]) -> void:
	for e in segments:
		_build_wall(e)
		_line_with_buildings(e)

## ---- Planning -------------------------------------------------------------

func _plan_squares(graph: MapGraph) -> void:
	var junction := _street_w / 2.0
	for cell in graph.rooms:
		var room: MapGraph.RoomData = graph.rooms[cell]
		var h := junction
		if room.is_vault:
			h = COURTYARD_HALF
		elif room.is_start:
			h = maxf(START_HALF, junction)
		elif randf() < _map.layout.plaza_chance and not _on_water_line(cell):
			h = randf_range(PLAZA_HALF.x, PLAZA_HALF.y)
		half[cell] = h
		_map.room_half[cell] = Vector2(h, h)
		var o := _map._cell_to_world(cell)
		_walkable.append(Rect2(o.x - h, o.z - h, h * 2.0, h * 2.0))

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

func _collect_edges(graph: MapGraph) -> void:
	var w := _street_w / 2.0
	for cell in graph.rooms:
		var c: Vector2i = cell
		var origin := _map._cell_to_world(c)
		var h: float = half[c]
		var grand: bool = h > w + 0.1
		for d in DIRS:
			var out := Vector3(d.x, 0, d.y)
			var tangent := Vector3(absi(d.y), 0, absi(d.x))
			var side := origin + out * h
			if graph.has_connection(c, c + d):
				if h > w + 0.1:
					# Corner end extended (seals the corner), opening end not.
					_add_edge(side - tangent * h, side - tangent * w, -out, grand, false, true, false, true, false)
					_add_edge(side + tangent * w, side + tangent * h, -out, grand, false, false, true, false, true)
			else:
				var water := _on_water_line(c) and d == _water_side
				_add_edge(side - tangent * h, side + tangent * h, -out, grand, water, true, true, true, true)
		for d in [Vector2i.RIGHT, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if not graph.has_connection(c, n):
				continue
			var dir := Vector3(d.x, 0, d.y)
			var tangent := Vector3(absi(d.y), 0, absi(d.x))
			var a := origin + dir * h
			var b := _map._cell_to_world(n) - dir * float(half[n])
			var g := Vector2i(roundi(tangent.x), roundi(tangent.z))
			var street := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z))
			_walkable.append(street.grow_individual(tangent.x * w, tangent.z * w, tangent.x * w, tangent.z * w))
			_add_edge(a + tangent * w, b + tangent * w, -tangent, false, false, _street_end_inside(graph, c, g), _street_end_inside(graph, n, g))
			_add_edge(a - tangent * w, b - tangent * w, tangent, false, false, _street_end_inside(graph, c, -g), _street_end_inside(graph, n, -g))

## A street side ending at `cell` continues straight along the junction's
## closed side (true), or turns a block corner (false): past a plaza's
## edge, or where the junction opens toward `side` too.
func _street_end_inside(graph: MapGraph, cell: Vector2i, side: Vector2i) -> bool:
	return float(half[cell]) <= _street_w / 2.0 + 0.01 and not graph.has_connection(cell, cell + side)

func _add_edge(from: Vector3, to: Vector3, normal: Vector3, grand: bool, water: bool, extend_from: bool, extend_to: bool, overhang_from: bool = false, overhang_to: bool = false) -> void:
	if from.distance_to(to) < 0.2:
		return
	edges.append({"from": from, "to": to, "normal": normal, "grand": grand, "water": water,
		"extend_from": extend_from, "extend_to": extend_to, "overhang_from": overhang_from, "overhang_to": overhang_to})

func _plan_spawns(graph: MapGraph) -> void:
	for cell in graph.rooms:
		var room: MapGraph.RoomData = graph.rooms[cell]
		if room.is_start or room.is_vault:
			continue
		var centre := _map._cell_to_world(cell)
		var h: float = half[cell]
		# Plazas keep their centre for the fountain or statue.
		var offset := Vector3(h * 0.45 * (1 if randf() < 0.5 else -1), 0, h * 0.45 * (1 if randf() < 0.5 else -1)) if h > _street_w / 2.0 + 0.1 else Vector3.ZERO
		_add_spawn(centre + offset)
		for d in [Vector2i.RIGHT, Vector2i.DOWN]:
			var n: Vector2i = (cell as Vector2i) + d
			if not graph.has_connection(cell, n):
				continue
			var a := centre + Vector3(d.x, 0, d.y) * h
			var b := _map._cell_to_world(n) - Vector3(d.x, 0, d.y) * float(half[n])
			if a.distance_to(b) >= STREET_SPAWN_MIN_LENGTH and not (graph.rooms[n] as MapGraph.RoomData).is_start:
				_add_spawn((a + b) / 2.0)

func _add_spawn(p: Vector3) -> void:
	spawn_points.append(p)
	_dresser.reserve(Rect2(Vector2(p.x, p.z) - Vector2.ONE * SPAWN_CLEAR, Vector2.ONE * SPAWN_CLEAR * 2.0))

## ---- Walls and buildings -------------------------------------------------

func _build_wall(e: Dictionary) -> void:
	var from: Vector3 = e["from"]
	var to: Vector3 = e["to"]
	var n: Vector3 = e["normal"]
	var along := (to - from).normalized()
	var length := from.distance_to(to)
	# Set back from the line: inside corners extend the wall to meet its
	# neighbour's; block corners trim it back by the setback.
	var reach := WALL_SETBACK + WALL_THICKNESS
	var lo := -reach if e.get("extend_from", true) else WALL_SETBACK
	var hi := length + (reach if e.get("extend_to", true) else -WALL_SETBACK)
	if hi - lo < 0.1:
		return
	var mid := from + along * (lo + hi) / 2.0 - n * (WALL_SETBACK + WALL_THICKNESS / 2.0)
	var size := Vector3(hi - lo, WALL_HEIGHT, WALL_THICKNESS)
	var body := StaticBody3D.new()
	body.position = mid + Vector3(0, WALL_HEIGHT / 2.0, 0)
	body.rotation.y = atan2(-along.z, along.x)  # local X runs along the edge
	_map.add_child(body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	box.size.y = WALL_VISIBLE_HEIGHT
	mesh.position.y = (WALL_VISIBLE_HEIGHT - WALL_HEIGHT) / 2.0
	if _wall_mat:
		mesh.material_override = _wall_mat
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	_map.interior_wall_count += 1
	# Starts a little behind the face so props can stand right up to it.
	_dresser.reserve(_rect_behind(from - n * WALL_SETBACK, to - n * WALL_SETBACK, n, WALL_THICKNESS))

## Buildings shoulder to shoulder along the edge, fronts to the street.
func _line_with_buildings(e: Dictionary) -> void:
	var pool := _valid(_tileset.buildings)
	if pool.is_empty():
		return
	var grand_pool := _valid(_tileset.landmarks)
	var from: Vector3 = e["from"]
	var to: Vector3 = e["to"]
	var n: Vector3 = e["normal"]
	var along := (to - from).normalized()
	var length := from.distance_to(to)
	var yaw := atan2(-n.z, n.x)                  # local +X -> n
	var tz := Vector3(-n.z, 0, n.x)              # local +Z in the world
	# Square corners (extend_*) may take an overhang; street mouths may not.
	var cursor := -CORNER_OVERHANG if e.get("overhang_from", false) else 0.0
	var limit := length + (CORNER_OVERHANG if e.get("overhang_to", false) else 0.0)
	while length - cursor >= MIN_FILL:
		var placed := false
		for attempt in 5:
			var scene: PackedScene = grand_pool.pick_random() if e["grand"] and not grand_pool.is_empty() and randf() < LANDMARK_CHANCE else pool.pick_random()
			if attempt == 4:
				scene = _narrowest(pool)  # last try: whatever fits best
			var b := _measure(scene)
			if b.size.z <= 0.1:
				continue
			var s := _tileset.building_scale * randf_range(SCALE_JITTER.x, SCALE_JITTER.y)
			var w := b.size.z * s
			if cursor + w > limit + 0.6:
				# Last try: shrink it to the gap if that keeps it near full size.
				var fit := (limit + 0.3 - cursor) / b.size.z
				if attempt < 4 or fit < _tileset.building_scale * MIN_FIT_SCALE:
					continue
				s = fit
				w = b.size.z * s
			var centre_z := (b.position.z + b.end.z) / 2.0
			var pos := from + along * (cursor + w / 2.0) - tz * (centre_z * s) + n * (FRONT_PROTRUDE - b.end.x * s)
			if _reaches_walkable(_dresser._footprint(pos, yaw, b, s)):
				continue
			var node := _dresser._spawn(scene)
			node.scale = Vector3.ONE * s
			node.rotation.y = yaw
			node.position = pos
			_add_building_collision(node, b)
			building_count += 1
			e["placed"] = int(e.get("placed", 0)) + 1
			cursor += w + BUILDING_GAP
			placed = true
			break
		if not placed:
			break

func _narrowest(pool: Array[PackedScene]) -> PackedScene:
	var best: PackedScene = pool[0]
	for scene in pool:
		if _measure(scene).size.z < _measure(best).size.z:
			best = scene
	return best

func _measure(scene: PackedScene) -> AABB:
	if not _bounds.has(scene):
		_bounds[scene] = _dresser.measure(scene)
	return _bounds[scene]

## XZ rectangle covering the strip of `depth` behind an edge.
func _rect_behind(from: Vector3, to: Vector3, n: Vector3, depth: float) -> Rect2:
	var pts := [from, to, from - n * depth, to - n * depth]
	var r := Rect2(Vector2(from.x, from.z), Vector2.ZERO)
	for p in pts:
		r = r.expand(Vector2(p.x, p.z))
	return r

## ---- Waterfront ------------------------------------------------------------

## The outer row or column with the most cells and neither the start nor the
## boss square on it (their bigger squares would reach into the water).
func _pick_water_side(graph: MapGraph) -> void:
	var best := 1
	for side in DIRS:
		var axis_x := side.x != 0
		var extreme := -1 if (side.x + side.y) > 0 else 999
		for cell in graph.rooms:
			var v: int = (cell as Vector2i).x if axis_x else (cell as Vector2i).y
			extreme = maxi(extreme, v) if (side.x + side.y) > 0 else mini(extreme, v)
		var count := 0
		var blocked := false
		for cell in graph.rooms:
			var room: MapGraph.RoomData = graph.rooms[cell]
			if ((cell as Vector2i).x if axis_x else (cell as Vector2i).y) == extreme:
				count += 1
				blocked = blocked or room.is_start or room.is_vault
		if not blocked and count > best:
			best = count
			_water_side = side
			_water_line = extreme

func _on_water_line(cell: Vector2i) -> bool:
	if _water_side == Vector2i.ZERO:
		return false
	return (cell.x if _water_side.x != 0 else cell.y) == _water_line

## One water ribbon along the whole waterfront, from the quay line outward.
func _build_harbor(graph: MapGraph, cell_size: float) -> void:
	var out := Vector3(_water_side.x, 0, _water_side.y)
	var tangent := Vector3(absi(_water_side.y), 0, absi(_water_side.x))
	var near := _water_line * cell_size + _street_w / 2.0 * (_water_side.x + _water_side.y)
	var centre_line := out * (near * (_water_side.x + _water_side.y)) + out * (WATER_REACH / 2.0)
	var pts := PackedVector3Array()
	var t := -cell_size * 2.0
	while t <= cell_size * (graph.grid_size + 1):
		pts.append(centre_line + tangent * t + Vector3(0, WaterBuilder.SURFACE_Y, 0))
		t += WaterBuilder.STEP
	var ribbon := WaterBuilder.new(_map)._ribbon(pts, WATER_REACH / 2.0, 1.0)
	ribbon.name = "Harbor"
	_map.add_child(ribbon)

## A low quay wall (with full-height invisible collision) and open water
## beyond, with piers jutting out.
func _build_quay(e: Dictionary) -> void:
	var from: Vector3 = e["from"]
	var to: Vector3 = e["to"]
	var n: Vector3 = e["normal"]
	var along := (to - from).normalized()
	var length := from.distance_to(to)
	var mid := (from + to) / 2.0 - n * 0.3
	var body := StaticBody3D.new()
	body.position = mid
	body.rotation.y = atan2(-along.z, along.x)
	_map.add_child(body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(length + WALL_THICKNESS * 2.0, QUAY_HEIGHT, 0.6)
	mesh.mesh = box
	mesh.position.y = QUAY_HEIGHT / 2.0
	if _wall_mat:
		mesh.material_override = _wall_mat
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length + WALL_THICKNESS * 2.0, WALL_HEIGHT, 0.6)
	collision.shape = shape
	collision.position.y = WALL_HEIGHT / 2.0
	body.add_child(collision)
	var piers := _valid(_tileset.water_props)
	if piers.is_empty():
		return
	var t := PIER_SPACING * 0.5
	while t < length:
		var pier: Node3D = _dresser._spawn(piers.pick_random())
		pier.rotation.y = atan2(n.z, -n.x)  # long axis (+X) out over the water
		pier.position = from + along * t - n * 4.5
		t += PIER_SPACING

## ---- Dressing ----------------------------------------------------------------

func _dress_squares(graph: MapGraph) -> void:
	var pool := _valid(_tileset.plaza_props)
	if pool.is_empty():
		return
	for cell in graph.rooms:
		var room: MapGraph.RoomData = graph.rooms[cell]
		var h: float = half[cell]
		if room.is_vault or room.is_start or h <= _street_w / 2.0 + 0.1:
			continue
		var centre := _map._cell_to_world(cell)
		_dresser.place_at(centre, pool[0] if randf() < 0.5 else pool.pick_random(), randf() * TAU)
		for i in randi_range(2, 4):
			var angle := randf() * TAU
			var p := centre + Vector3(cos(angle), 0, sin(angle)) * h * randf_range(0.55, 0.8)
			_dresser.place_at(p, pool.pick_random(), angle + PI / 2.0)

func _street_edges() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in edges:
		if not e["water"] and not e["grand"]:
			out.append(e)
	return out

func _place_lamps() -> void:
	var pool := _valid(_tileset.street_lights)
	if pool.is_empty():
		return
	var flip := false
	for e in edges:
		if e["water"]:
			continue
		var from: Vector3 = e["from"]
		var to: Vector3 = e["to"]
		var length := from.distance_to(to)
		if length < LAMP_SPACING * 0.6:
			continue
		flip = not flip
		var along := (to - from).normalized()
		var n: Vector3 = e["normal"]
		# Opposite sides of a street stagger their lamps.
		var t := LAMP_SPACING * (0.25 if flip else 0.75)
		while t < length - 1.0:
			var lamp := _dresser.place_at(from + along * t + n * LAMP_INSET, pool.pick_random(), atan2(-n.z, n.x))
			if lamp:
				lamp_count += 1
				if lamp_count <= MAX_LAMP_LIGHTS:
					var light := OmniLight3D.new()
					light.light_color = _tileset.light_color
					light.light_energy = _tileset.light_energy
					light.omni_range = _tileset.light_range
					light.position = Vector3(0, 4.0, 0)
					_map._fade_with_distance(light)
					lamp.add_child(light)
			t += LAMP_SPACING

func _scatter_props() -> void:
	var pool := _valid(_tileset.floor_props + _tileset.clusters)
	if pool.is_empty():
		return
	for e in edges:
		if e["water"]:
			continue
		var from: Vector3 = e["from"]
		var to: Vector3 = e["to"]
		var n: Vector3 = e["normal"]
		var along := (to - from).normalized()
		var length := from.distance_to(to)
		for i in roundi(length * PROP_DENSITY + randf() * 0.5):
			var p := from + along * randf_range(1.0, maxf(length - 1.0, 1.0)) + n * randf_range(PROP_INSET.x, PROP_INSET.y)
			_dresser.place_loose(p, pool.pick_random())

func _place_vents() -> void:
	var candidates := _street_edges()
	if candidates.is_empty():
		return
	for i in _tileset.steam_vents * 3:
		if vent_count >= _tileset.steam_vents:
			break
		var e: Dictionary = candidates.pick_random()
		var from: Vector3 = e["from"]
		var to: Vector3 = e["to"]
		var n: Vector3 = e["normal"]
		var p := from.lerp(to, randf_range(0.15, 0.85)) + n * 1.4
		var rect := Rect2(Vector2(p.x, p.z) - Vector2(0.8, 0.8), Vector2(1.6, 1.6))
		if _dresser._overlaps(rect):
			continue
		_dresser.reserve(rect)
		var vent := SteamVent.new()
		vent.rotation.y = atan2(-n.z, n.x)
		_map.add_child(vent)
		vent.position = p
		vent_count += 1

## Two steel rails and wooden sleepers down every street, centre to centre.
func _lay_rails(graph: MapGraph) -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.32, 0.3, 0.28)
	steel.metallic = 0.85
	steel.roughness = 0.4
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.25, 0.17, 0.11)
	wood.roughness = 0.95
	var sleeper_mesh := BoxMesh.new()
	sleeper_mesh.size = Vector3(0.25, 0.08, RAIL_GAUGE + 0.9)
	sleeper_mesh.material = wood
	var transforms: Array[Transform3D] = []
	for cell in graph.rooms:
		for d in [Vector2i.RIGHT, Vector2i.DOWN]:
			var n: Vector2i = (cell as Vector2i) + d
			if not graph.has_connection(cell, n):
				continue
			var a := _map._cell_to_world(cell)
			var b := _map._cell_to_world(n)
			var along := (b - a).normalized()
			var side := Vector3(-along.z, 0, along.x)
			var length := a.distance_to(b)
			var yaw := atan2(-along.z, along.x)
			for offset in [-RAIL_GAUGE / 2.0, RAIL_GAUGE / 2.0]:
				var rail := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(length, 0.12, 0.1)
				rail.mesh = box
				rail.material_override = steel
				rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_map.add_child(rail)
				rail.position = (a + b) / 2.0 + side * offset + Vector3(0, 0.1, 0)
				rail.rotation.y = yaw
			var t := 0.0
			while t <= length:
				transforms.append(Transform3D(Basis(Vector3.UP, yaw), a + along * t + Vector3(0, 0.04, 0)))
				t += SLEEPER_SPACING
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sleeper_mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Sleepers"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_map.add_child(mmi)

static func _valid(scenes: Array[PackedScene]) -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	for s in scenes:
		if s != null:
			out.append(s)
	return out

## A box from the back of the building to just behind its eaves.
func _add_building_collision(node: Node3D, b: AABB) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var front := b.end.x - EAVE_DEPTH / maxf(node.scale.x, 0.01)
	box.size = Vector3(maxf(front - b.position.x, 0.5), b.size.y, b.size.z * 0.92)
	shape.shape = box
	shape.position = Vector3((b.position.x + front) / 2.0, b.get_center().y, b.get_center().z)
	body.add_child(shape)
	node.add_child(body)

## True when a building footprint (minus its eaves over its own street)
## overlaps any square or street.
func _reaches_walkable(footprint: Rect2) -> bool:
	var core := footprint.grow(-(FRONT_PROTRUDE + 0.4))
	if core.size.x <= 0.0 or core.size.y <= 0.0:
		return false
	for r in _walkable:
		if core.intersects(r):
			return true
	return false
