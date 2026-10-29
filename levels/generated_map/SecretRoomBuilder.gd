extends RefCounted
class_name SecretRoomBuilder
## One hidden chamber per Figment, holding an encounter rolled from
## MapEncounters.SECRET_TABLE (a hoard, the Watcher, ...). Two shapes:
##   Rooms layouts - a chamber in an empty grid cell behind a closed wall of
##     a room off the start-to-Vault route. The way in is a CrackedWall: a
##     patch of that wall with hairline cracks and a little grit at its foot,
##     broken down with a few hits.
##   Open fields, canyons, streets - an OUTCROP: a rough rock mass shifted off
##     its cell's centre, hollow inside. The way in is a crack in its rim,
##     reached up two boulders among a few that lead nowhere.
##   Desert open fields (Dunes) - a SINKHOLE: a sandstone mesa placed like an
##     outcrop with a cave at ground level inside. The way in is a sinkhole in
##     its flat top, reached up two boulders; a CrackedWall in its side is the
##     way back out (or in, for whoever spots the cracks first).
## Everything is rolled from the map's seeded RNG, so a portal return builds
## the same secret; capture()/restore() carry what was done in it.

enum Access { CRACKED, OUTCROP, SINKHOLE }

## Rooms: the chamber's inner footprint (along the wall, away from it) and height.
const CHAMBER_WIDTH := 7.0
const CHAMBER_DEPTH := 7.0
const CHAMBER_HEIGHT := 3.4
## The cracked patch: width along the wall, height.
const HOLE_SIZE := Vector2(2.2, 2.6)
## OUTCROP: the hollow's floor (square, half size) and headroom, the rock
## skin around it, and the crack in its rim.
const OUTCROP_HALF := 4.5
const OUTCROP_FLOOR := 4.4
const OUTCROP_ROOM := 2.8
const OUTCROP_SKIN := 1.4
const CRACK_SIZE := Vector2(1.4, 2.2)
## The two boulders up to the crack: heights, rough size.
const STEP_HEIGHTS: Array[float] = [1.5, 2.9]
const STEP_SIZE := 2.4
const DECOY_COUNT := 6
## How far an outcrop moves off its cell's centre, toward a side with no
## way through.
const OUTCROP_SHIFT := 4.0
## How far packs and props keep from an outcrop's centre.
const OUTCROP_CLEARANCE := 9.5
## Chamber lights stay inside their walls.
const LIGHT_RANGE := 4.5
## SINKHOLE: the mesa's outer half size and height (its top is the outcrop's
## ledge height, so the same boulders reach it), wall and roof thickness, and
## the hole in the roof.
const MESA_HALF := 5.5
const MESA_SKIN := 1.2
const MESA_ROOF := 1.0
const SINKHOLE_SIZE := 2.0

var access: Access = Access.CRACKED
var encounter_id: String = ""
var encounter: Node3D
## Rooms only: the room the chamber hides behind, the wall it's behind, and
## that wall's hole (width, bottom, top above the floor).
var host_cell := Vector2i(-999, -999)
var host_dir := Vector2i.ZERO
var opening := Vector3.ZERO
var cracked_wall: CrackedWall
## OUTCROP only: the rock's centre on the ground and the side its crack faces.
var centre := Vector3.ZERO
var crack_dir := Vector2i.ZERO
## SINKHOLE only: the side its boulders climb, and the hole in its top.
var step_side := Vector2i.ZERO
var sinkhole_at := Vector3.ZERO
## Where the encounter stands.
var chamber_centre := Vector3.ZERO
var _map: GeneratedMap
var _found := false
var _found_area: Area3D

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

## Picks the host room and wall, or null when no closed wall backs onto an
## empty cell. Rooms on the way to the Vault host one only when nothing else can.
static func plan_in_rooms(map: GeneratedMap) -> SecretRoomBuilder:
	var candidates: Array = []
	var cells: Array = map.graph.rooms.keys()
	cells.sort()
	for cell in cells:
		var room: MapGraph.RoomData = map.graph.rooms[cell]
		if room.is_start or room.is_vault:
			continue
		var half: Vector2 = map.room_half[cell]
		for dir in DIRS:
			var n: Vector2i = cell + dir
			# Packs shift away from the wall (GeneratedMap.SECRET_HOST_PACK_SHIFT).
			var depth: float = half.y if dir.y != 0 else half.x
			if not room.connections.has(n) and not map.graph.rooms.has(n) and depth >= 7.0:
				candidates.append([cell, dir])
	if candidates.is_empty():
		return null
	var route := map._path_to_vault()
	var off_route := candidates.filter(func(c): return not route.has(c[0]))
	if not off_route.is_empty():
		candidates = off_route
	var pick: Array = candidates[randi() % candidates.size()]
	var s := SecretRoomBuilder.new()
	s._map = map
	s.host_cell = pick[0]
	s.host_dir = pick[1]
	s.access = Access.CRACKED
	s.opening = Vector3(HOLE_SIZE.x, 0.0, HOLE_SIZE.y)
	s.encounter_id = MapEncounters.roll(MapEncounters.SECRET_TABLE)
	return s

## An outcrop in the cell centred on `cell_centre`, for open layouts. `shift`
## moves it toward a side of the cell with no way through.
static func plan_outcrop(map: GeneratedMap, cell_centre: Vector3, shift: bool) -> SecretRoomBuilder:
	var s := SecretRoomBuilder.new()
	s._map = map
	s.access = Access.OUTCROP
	s.centre = Vector3(cell_centre.x, 0.0, cell_centre.z)
	var shifted := Vector2i.ZERO
	if shift:
		var cell := Vector2i(roundi(cell_centre.x / map.cell_size), roundi(cell_centre.z / map.cell_size))
		var room: MapGraph.RoomData = map.graph.rooms.get(cell)
		var sides: Array[Vector2i] = []
		for dir in DIRS:
			if room and not room.connections.has(cell + dir) and not map.room_floor.has(cell + dir):
				sides.append(dir)
		if not sides.is_empty():
			var dir: Vector2i = sides[randi() % sides.size()]
			var pos := s.centre + Vector3(dir.x, 0, dir.y) * OUTCROP_SHIFT
			if not (map.water and map.water.is_wet(pos, OUTCROP_CLEARANCE)):
				s.centre = pos
				shifted = dir
	if shifted != Vector2i.ZERO:
		# The crack faces along the cell's edge, not back toward its middle.
		s.crack_dir = Vector2i(shifted.y, shifted.x) * (1 if randf() < 0.5 else -1)
	else:
		s.crack_dir = DIRS[randi() % DIRS.size()]
	s.encounter_id = MapEncounters.roll(MapEncounters.SECRET_TABLE)
	# Props may crowd round it (the boulders reserve their own ground).
	if map._dresser:
		var r := OUTCROP_HALF + 1.5
		map._dresser.reserve(Rect2(Vector2(s.centre.x, s.centre.z) - Vector2.ONE * r, Vector2.ONE * r * 2.0))
	return s

## True when `pos` is close enough to an outcrop that a pack there would stand in it.
func blocks(pos: Vector3) -> bool:
	return access != Access.CRACKED and Vector2(pos.x - centre.x, pos.z - centre.z).length() < OUTCROP_CLEARANCE

## ---- Rooms: the chamber behind the host wall --------------------------------

## Called from GeneratedMap._build_room() for the host, before its dressing.
func build(host_origin: Vector3, host_half: Vector2) -> void:
	var out := Vector3(host_dir.x, 0, host_dir.y)
	var along := Vector3(absf(out.z), 0, absf(out.x))
	var reach: float = host_half.x if host_dir.x != 0 else host_half.y
	var wall_inner := host_origin + out * reach
	var floor_y := host_origin.y + opening.y
	var wt := GeneratedMap.WALL_THICKNESS
	# Floor from the host wall's inner face (under the patch) to the chamber's back.
	var floor_len := wt + CHAMBER_DEPTH
	var floor_mid := wall_inner + out * floor_len / 2.0
	floor_mid.y = floor_y + 0.01
	var size_x := floor_len if host_dir.x != 0 else CHAMBER_WIDTH
	var size_z := CHAMBER_WIDTH if host_dir.x != 0 else floor_len
	_map._build_floor(floor_mid, size_x, size_z, 0.0, GeneratedMap.VAULT_FLOOR_COLOR)
	if floor_y > 0.0:
		_solid(Vector3(floor_mid.x, floor_y / 2.0 - 0.02, floor_mid.z), Vector3(size_x, floor_y, size_z), false)
	var back := wall_inner + out * (wt + CHAMBER_DEPTH + wt / 2.0)
	var top := floor_y + CHAMBER_HEIGHT
	var horizontal := host_dir.y != 0
	_map._add_wall_segment(Vector3(back.x, 0, back.z), CHAMBER_WIDTH + wt * 2.0, horizontal, top)
	for side in [-1.0, 1.0]:
		var c: Vector3 = wall_inner + out * (wt + CHAMBER_DEPTH / 2.0) + along * side * (CHAMBER_WIDTH + wt) / 2.0
		_map._add_wall_segment(Vector3(c.x, 0, c.z), CHAMBER_DEPTH + wt * 2.0, not horizontal, top)
	var room_mid := wall_inner + out * (wt + CHAMBER_DEPTH / 2.0)
	room_mid.y = floor_y
	_map._build_ceiling(room_mid, CHAMBER_DEPTH + wt * 2.0 if host_dir.x != 0 else CHAMBER_WIDTH + wt * 2.0, CHAMBER_WIDTH + wt * 2.0 if host_dir.x != 0 else CHAMBER_DEPTH + wt * 2.0, CHAMBER_HEIGHT)
	_add_light(room_mid + Vector3(0, CHAMBER_HEIGHT - 0.5, 0), 2.5)
	chamber_centre = room_mid + out * 1.2
	_add_found_area(room_mid, Vector3(size_x, CHAMBER_HEIGHT, size_z))
	# The patch fills the hole the host wall leaves for it.
	cracked_wall = CrackedWall.new()
	cracked_wall.size = Vector3(HOLE_SIZE.x + 0.02, HOLE_SIZE.y, wt)
	cracked_wall.material = _map._wall_mat if _map._wall_mat else _map._plain_material(GeneratedMap.WALL_COLOR)
	cracked_wall.position = wall_inner + out * wt / 2.0
	cracked_wall.position.y = floor_y
	cracked_wall.rotation.y = atan2(-out.x, -out.z)
	_map.add_child(cracked_wall)
	if _map._dresser:
		var lane := wall_inner - out * 1.2
		_map._dresser.reserve(Rect2(Vector2(lane.x, lane.z) - Vector2.ONE * 1.6, Vector2.ONE * 3.2))
	_spawn_encounter(-out)

## ---- Open layouts: the outcrop ------------------------------------------------

func build_outcrop() -> void:
	if access == Access.SINKHOLE:
		build_sinkhole()
		return
	var walls_before := _map.interior_wall_count
	var n := Vector3(crack_dir.x, 0, crack_dir.y)
	var top := centre + Vector3.UP * OUTCROP_FLOOR
	var roof_y := OUTCROP_FLOOR + OUTCROP_ROOM
	# The core: its top is the hollow's floor, its edge at the crack the ledge
	# the last boulder reaches. Sunk so uneven ground leaves no gap under it.
	_solid(centre + Vector3(0, (OUTCROP_FLOOR - 1.5) / 2.0, 0), Vector3(OUTCROP_HALF * 2.0, OUTCROP_FLOOR + 1.5, OUTCROP_HALF * 2.0), false)
	_map._build_floor(top + Vector3(0, 0.01, 0), OUTCROP_HALF * 2.0, OUTCROP_HALF * 2.0, 0.0, GeneratedMap.VAULT_FLOOR_COLOR)
	# The skin: jagged blocks down each side, standing proud of the roof.
	var reach := OUTCROP_HALF - OUTCROP_SKIN / 2.0 + 0.3
	var span := OUTCROP_HALF * 2.0 + OUTCROP_SKIN
	for dir in DIRS:
		var side_n := Vector3(dir.x, 0, dir.y)
		var along := Vector3(absf(side_n.z), 0, absf(side_n.x))
		var yaw := atan2(side_n.x, side_n.z)
		var mid := centre + side_n * reach
		if dir != crack_dir:
			for k in [-1.0, 0.0, 1.0]:
				var pos: Vector3 = mid + along * k * span / 3.0 + side_n * randf_range(-0.1, 0.3)
				_rock(pos, Vector3(span / 3.0 + 0.8, roof_y + randf_range(0.3, 1.1), OUTCROP_SKIN), yaw + deg_to_rad(randf_range(-8.0, 8.0)), false)
			continue
		var piece := (span - CRACK_SIZE.x) / 2.0
		for k in [-1.0, 1.0]:
			_rock(mid + along * k * (CRACK_SIZE.x + piece) / 2.0, Vector3(piece, roof_y + randf_range(0.4, 1.0), OUTCROP_SKIN), yaw + deg_to_rad(randf_range(-3.0, 3.0)), false)
		# Over the crack, and under it down to the ground: the last is the ledge.
		_rock(mid + Vector3.UP * (OUTCROP_FLOOR + CRACK_SIZE.y), Vector3(CRACK_SIZE.x + 1.0, roof_y + 0.6 - OUTCROP_FLOOR - CRACK_SIZE.y, OUTCROP_SKIN), yaw, false)
		_rock(mid, Vector3(CRACK_SIZE.x + 0.2, OUTCROP_FLOOR, OUTCROP_SKIN), yaw, true)
	for corner in [Vector3(1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(-1, 0, -1)]:
		_rock(centre + corner * (OUTCROP_HALF - 0.2), Vector3(2.2, roof_y + randf_range(0.2, 0.9), 2.2), deg_to_rad(45.0 + randf_range(-10.0, 10.0)), false)
	_rock(centre + Vector3.UP * roof_y, Vector3(OUTCROP_HALF * 2.0 + 0.4, 1.0, OUTCROP_HALF * 2.0 + 0.4), randf_range(-0.1, 0.1), false)
	# The chamber isn't a room; open layouts still have no interior walls.
	_map.interior_wall_count = walls_before
	# Dim, so little glow escapes through the crack.
	_add_light(top + Vector3(0, OUTCROP_ROOM - 0.6, 0), 1.0)
	_add_found_area(top, Vector3(OUTCROP_HALF * 2.0 - 3.0, OUTCROP_ROOM, OUTCROP_HALF * 2.0 - 3.0))
	# Two boulders up to the crack, the lower one off to a side.
	var along_n := Vector3(absf(n.z), 0, absf(n.x)) * (1.0 if randf() < 0.5 else -1.0)
	var near := centre + n * (OUTCROP_HALF + 0.3 + STEP_SIZE / 2.0 - 0.1)
	_boulder(near, STEP_HEIGHTS[1], true)
	_boulder(near + n * (STEP_SIZE - 0.3) + along_n * 1.2, STEP_HEIGHTS[0], true)
	# A few that lead nowhere, around the other sides.
	var crack_angle := atan2(n.z, n.x)
	for i in DECOY_COUNT:
		# Spread right round the rock, some at step heights, so the real pair
		# doesn't stand out.
		var angle := crack_angle + deg_to_rad(randf_range(50.0, 310.0))
		var dist := OUTCROP_HALF + randf_range(1.0, 2.8)
		_boulder(centre + Vector3(cos(angle), 0, sin(angle)) * dist, randf_range(1.0, 3.0), i % 2 == 0)
	chamber_centre = top - n * 0.8
	_spawn_encounter(n)

## ---- Desert open fields: the sinkhole mesa ------------------------------------

func build_sinkhole() -> void:
	var walls_before := _map.interior_wall_count
	var n := Vector3(crack_dir.x, 0, crack_dir.y)
	# The boulders climb the side a quarter turn from the cracked one.
	var step_dir := Vector2i(crack_dir.y, -crack_dir.x) * (1 if randf() < 0.5 else -1)
	step_side = step_dir
	var s := Vector3(step_dir.x, 0, step_dir.y)
	var top := OUTCROP_FLOOR
	var inner := MESA_HALF - MESA_SKIN
	var cave_height := top - MESA_ROOF
	_map._build_floor(centre + Vector3(0, 0.01, 0), inner * 2.0, inner * 2.0, 0.0, GeneratedMap.VAULT_FLOOR_COLOR)
	# Walls, sunk a little so uneven sand leaves no gap. Only the step side's
	# rim can be mantled.
	for dir in DIRS:
		var side_n := Vector3(dir.x, 0, dir.y)
		var along := Vector3(absf(side_n.z), 0, absf(side_n.x))
		var mid := centre + side_n * (MESA_HALF - MESA_SKIN / 2.0)
		var size := Vector3(MESA_HALF * 2.0, top + 0.5, MESA_SKIN) if dir.y != 0 else Vector3(MESA_SKIN, top + 0.5, MESA_HALF * 2.0)
		if dir != crack_dir:
			_solid(mid + Vector3.UP * (top - 0.5) / 2.0, size, dir != step_dir)
			continue
		# The cracked side: two pieces either side of the patch and a lintel.
		var piece := (MESA_HALF * 2.0 - HOLE_SIZE.x) / 2.0
		for k in [-1.0, 1.0]:
			var at: Vector3 = mid + along * k * (HOLE_SIZE.x + piece) / 2.0 + Vector3.UP * (top - 0.5) / 2.0
			_solid(at, Vector3(piece, top + 0.5, MESA_SKIN) if dir.y != 0 else Vector3(MESA_SKIN, top + 0.5, piece), true)
		var lintel := top - HOLE_SIZE.y
		_solid(mid + Vector3.UP * (HOLE_SIZE.y + lintel / 2.0), Vector3(HOLE_SIZE.x, lintel, MESA_SKIN) if dir.y != 0 else Vector3(MESA_SKIN, lintel, HOLE_SIZE.x), true)
		cracked_wall = CrackedWall.new()
		cracked_wall.size = Vector3(HOLE_SIZE.x + 0.02, HOLE_SIZE.y, MESA_SKIN)
		cracked_wall.material = _map._wall_mat if _map._wall_mat else _map._plain_material(GeneratedMap.WALL_COLOR)
		cracked_wall.position = mid
		cracked_wall.rotation.y = atan2(side_n.x, side_n.z)
		_map.add_child(cracked_wall)
	# The roof, inside the rim, with the sinkhole off towards the far corner
	# from the boulders so the way across the top is a walk.
	var away := -s * inner * 0.45 + Vector3(s.z, 0, s.x) * inner * 0.35 * (1.0 if randf() < 0.5 else -1.0)
	var h := Vector2(away.x, away.z)
	var half := SINKHOLE_SIZE / 2.0
	var y := top - MESA_ROOF / 2.0
	var pieces: Array[Rect2] = [
		Rect2(-inner, -inner, h.x - half + inner, inner * 2.0),
		Rect2(h.x + half, -inner, inner - h.x - half, inner * 2.0),
		Rect2(h.x - half, -inner, SINKHOLE_SIZE, h.y - half + inner),
		Rect2(h.x - half, h.y + half, SINKHOLE_SIZE, inner - h.y - half),
	]
	for r in pieces:
		if r.size.x > 0.01 and r.size.y > 0.01:
			_solid(centre + Vector3(r.get_center().x, y, r.get_center().y), Vector3(r.size.x, MESA_ROOF, r.size.y), true)
	# Loose stones round the hole's lip.
	var hole := centre + Vector3(h.x, top, h.y)
	sinkhole_at = hole
	for i in 5:
		var a := TAU * i / 5.0 + randf_range(-0.3, 0.3)
		var d := half + randf_range(0.35, 0.8)
		_rock(hole + Vector3(cos(a), 0, sin(a)) * d, Vector3(randf_range(0.4, 0.8), randf_range(0.25, 0.5), randf_range(0.4, 0.8)), randf() * TAU, false)
	for corner in [Vector3(1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(-1, 0, -1)]:
		_rock(centre + corner * (MESA_HALF - 0.4) - Vector3.UP * 0.5, Vector3(1.6, top + randf_range(0.2, 0.7), 1.6), deg_to_rad(45.0 + randf_range(-10.0, 10.0)), false)
	_map.interior_wall_count = walls_before
	# A shaft of light from the hole; dim, so nothing glows through the cracks.
	_add_light(Vector3(hole.x, cave_height - 0.6, hole.z), 1.2)
	_add_found_area(centre, Vector3(inner * 2.0 - 1.0, cave_height, inner * 2.0 - 1.0))
	# Two boulders up the step side, the lower one off to a side.
	var along_s := Vector3(absf(s.z), 0, absf(s.x)) * (1.0 if randf() < 0.5 else -1.0)
	var near := centre + s * (MESA_HALF + STEP_SIZE / 2.0 - 0.1)
	_boulder(near, STEP_HEIGHTS[1], true)
	_boulder(near + s * (STEP_SIZE - 0.3) + along_s * 1.2, STEP_HEIGHTS[0], true)
	var step_angle := atan2(s.z, s.x)
	for i in DECOY_COUNT:
		var angle := step_angle + deg_to_rad(randf_range(50.0, 310.0))
		var dist := MESA_HALF + randf_range(1.0, 2.8)
		var foot := centre + Vector3(cos(angle), 0, sin(angle)) * dist
		# Keep the cracked patch clear.
		if Vector2(foot.x - (centre.x + n.x * MESA_HALF), foot.z - (centre.z + n.z * MESA_HALF)).length() < 2.6:
			continue
		_boulder(foot, randf_range(1.0, 3.0), i % 2 == 0)
	chamber_centre = centre - n * 1.2
	_spawn_encounter(n)

## A rough boulder standing on the ground at `foot`, `height` tall.
func _boulder(foot: Vector3, height: float, step: bool) -> void:
	var w := STEP_SIZE * randf_range(0.9, 1.1) if step else randf_range(1.4, 2.6)
	var d := STEP_SIZE * randf_range(0.9, 1.1) if step else randf_range(1.4, 2.6)
	_rock(foot - Vector3.UP * 0.5, Vector3(w, height + 0.5, d), deg_to_rad(randf_range(-20.0, 20.0)), true)
	if _map._dresser:
		var r := maxf(w, d) / 2.0 + 0.8
		_map._dresser.reserve(Rect2(Vector2(foot.x, foot.z) - Vector2.ONE * r, Vector2.ONE * r * 2.0))

## A block of the layout's wall rock, `size` tall from `bottom` (its foot's
## centre), turned by `yaw`.
func _rock(bottom: Vector3, size: Vector3, yaw: float, climbable: bool) -> void:
	var body := StaticBody3D.new()
	body.position = bottom + Vector3.UP * size.y / 2.0
	body.rotation.y = yaw
	if not climbable:
		# Leaning a little, so the mass reads as rock rather than masonry.
		body.rotation.x = randf_range(-0.05, 0.05)
		body.rotation.z = randf_range(-0.05, 0.05)
		LedgeClimb.forbid(body)
	_map.add_child(body)
	_shape(body, size)

## ---- Shared pieces -----------------------------------------------------------

func _solid(at: Vector3, size: Vector3, no_climb: bool) -> void:
	var body := StaticBody3D.new()
	body.position = at
	if no_climb:
		LedgeClimb.forbid(body)
	_map.add_child(body)
	_shape(body, size)

func _shape(body: StaticBody3D, size: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _map._wall_mat if _map._wall_mat else _map._plain_material(GeneratedMap.WALL_COLOR)
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

func _add_light(pos: Vector3, energy: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.45)
	light.light_energy = energy
	light.omni_range = LIGHT_RANGE
	light.position = pos
	_map._fade_with_distance(light)
	_map.add_child(light)

## Announces the find the first time the player steps inside.
func _add_found_area(at: Vector3, size: Vector3) -> void:
	_found_area = Area3D.new()
	_found_area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y / 2.0
	_found_area.add_child(shape)
	_map.add_child(_found_area)
	_found_area.global_position = at
	_found_area.body_entered.connect(func(body: Node3D):
		if body is Player and not _found:
			_found = true
			SecretFoundBanner.play(body))

func _spawn_encounter(facing: Vector3) -> void:
	encounter = MapEncounters.create(encounter_id, _map)
	if encounter == null:
		return
	_map.add_child(encounter)
	encounter.global_position = chamber_centre
	# Encounters face their local +Z.
	encounter.rotation.y = atan2(facing.x, facing.z)

## ---- Portal trips --------------------------------------------------------------

func capture() -> Dictionary:
	var state := {"found": _found, "opened": access != Access.OUTCROP and not is_instance_valid(cracked_wall)}
	if is_instance_valid(encounter) and encounter.has_method("capture_state"):
		state["encounter"] = encounter.capture_state()
	return state

func restore(state: Dictionary) -> void:
	_found = bool(state.get("found", false))
	if bool(state.get("opened", false)) and is_instance_valid(cracked_wall):
		cracked_wall.shatter(true)
	if is_instance_valid(encounter) and encounter.has_method("restore_state"):
		encounter.restore_state(state.get("encounter", {}))
