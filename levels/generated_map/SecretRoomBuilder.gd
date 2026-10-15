extends RefCounted
class_name SecretRoomBuilder
## One hidden chamber per Figment, holding an encounter rolled from
## MapEncounters.SECRET_TABLE (a hoard, the Watcher, ...). Two shapes:
##   Rooms layouts - a chamber in an empty grid cell behind a closed wall of
##     an ordinary room. CLIMB: a window high in the wall, reached by a run
##     of stepping columns too tall to jump straight onto. TIMED: a barred
##     gate at floor level; a lever in the room's far corner lifts it for a
##     few seconds.
##   Open fields, canyons, streets - a SPIRE: a walled chamber on a pedestal,
##     reached by columns spiralling up around it.
## Everything is rolled from the map's seeded RNG, so a portal return builds
## the same secret; capture()/restore() carry what was done in it.

enum Access { CLIMB, TIMED, SPIRE }

## Rooms: the chamber's inner footprint (along the wall, away from it) and height.
const CHAMBER_WIDTH := 7.0
const CHAMBER_DEPTH := 7.0
const CHAMBER_HEIGHT := 3.4
## CLIMB: the window's sill above the host floor, its size, and the host room's
## wall height so the window fits under its ceiling.
const WINDOW_SILL := 6.0
const WINDOW_SIZE := Vector2(2.4, 2.3)
const CLIMB_HOST_WALL := 10.0
const COLUMN_SIZE := 1.5
## Stepping columns in front of the window: (along the wall, out from it,
## height). Each top is out of reach from the floor or the column before last.
const CLIMB_COLUMNS: Array[Vector3] = [Vector3(-0.4, 5.6, 1.8), Vector3(3.0, 4.2, 3.4), Vector3(0.0, 2.6, 4.9)]
## TIMED: the gate's size; it stays up for the sprint from the lever plus this.
const GATE_SIZE := Vector2(2.6, 3.0)
const GATE_GRACE := 2.0
const SPRINT_SPEED := 9.0
## SPIRE: pedestal (square, its top is the chamber floor) and columns.
const SPIRE_HALF := 4.0
const SPIRE_FLOOR := 6.6
const SPIRE_WALL := 3.0
const SPIRE_DOOR := Vector2(2.4, 2.4)
const SPIRE_COLUMN_GAP := 1.8
const SPIRE_STEP_DEGREES := 40.0
const SPIRE_COLUMN_HEIGHTS: Array[float] = [1.8, 3.3, 4.8, 5.9]
## How far packs and props keep from a spire's centre.
const SPIRE_CLEARANCE := 8.5

var access: Access = Access.CLIMB
var encounter_id: String = ""
var encounter: Node3D
## Rooms only: the room the chamber hides behind, the wall it's behind, and
## that wall's hole (width, bottom, top above the floor).
var host_cell := Vector2i(-999, -999)
var host_dir := Vector2i.ZERO
var opening := Vector3.ZERO
## Where the encounter stands, and the chamber floor's centre.
var chamber_centre := Vector3.ZERO
var _map: GeneratedMap
var _gate: SecretGate
var _found := false
var _found_area: Area3D

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

## Picks the host room and wall, or null when no closed wall backs onto an
## empty cell. A CLIMB host gets taller walls (set before it's built).
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
			# The column run needs room in front of the wall.
			var depth: float = half.y if dir.y != 0 else half.x
			if not room.connections.has(n) and not map.graph.rooms.has(n) and depth >= 7.0:
				candidates.append([cell, dir])
	if candidates.is_empty():
		return null
	var pick: Array = candidates[randi() % candidates.size()]
	var s := SecretRoomBuilder.new()
	s._map = map
	s.host_cell = pick[0]
	s.host_dir = pick[1]
	s.access = Access.CLIMB if randf() < 0.5 else Access.TIMED
	if s.access == Access.CLIMB:
		s.opening = Vector3(WINDOW_SIZE.x, WINDOW_SILL, WINDOW_SILL + WINDOW_SIZE.y)
		map.room_wall_height[s.host_cell] = maxf(CLIMB_HOST_WALL, map.layout.wall_height)
	else:
		s.opening = Vector3(GATE_SIZE.x, 0.0, GATE_SIZE.y)
	s.encounter_id = MapEncounters.roll(MapEncounters.SECRET_TABLE)
	return s

## A spire at `centre`, for open layouts.
static func plan_spire(map: GeneratedMap, centre: Vector3) -> SecretRoomBuilder:
	var s := SecretRoomBuilder.new()
	s._map = map
	s.access = Access.SPIRE
	s.chamber_centre = Vector3(centre.x, SPIRE_FLOOR, centre.z)
	s.encounter_id = MapEncounters.roll(MapEncounters.SECRET_TABLE)
	if map._dresser:
		map._dresser.reserve(Rect2(Vector2(centre.x, centre.z) - Vector2.ONE * SPIRE_CLEARANCE, Vector2.ONE * SPIRE_CLEARANCE * 2.0))
	return s

## True when `pos` is close enough to a spire that a pack there would stand in it.
func blocks(pos: Vector3) -> bool:
	return access == Access.SPIRE and Vector2(pos.x - chamber_centre.x, pos.z - chamber_centre.z).length() < SPIRE_CLEARANCE

## ---- Rooms: the chamber behind the host wall --------------------------------

## Called from GeneratedMap._build_room() for the host, before its dressing.
func build(host_origin: Vector3, host_half: Vector2) -> void:
	var out := Vector3(host_dir.x, 0, host_dir.y)
	var along := Vector3(absf(out.z), 0, absf(out.x))
	var reach: float = host_half.x if host_dir.x != 0 else host_half.y
	var wall_inner := host_origin + out * reach
	var floor_y := host_origin.y + opening.y
	var wt := GeneratedMap.WALL_THICKNESS
	# Floor from the host wall's inner face (so the gate's threshold is solid)
	# to the chamber's back.
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
	_add_light(room_mid + Vector3(0, CHAMBER_HEIGHT - 0.5, 0), 5.0 if access == Access.CLIMB else 2.5)
	chamber_centre = room_mid + out * 1.2
	_add_found_area(room_mid, Vector3(size_x, CHAMBER_HEIGHT, size_z))
	if access == Access.CLIMB:
		_build_columns(wall_inner, out, along, host_origin.y)
	else:
		_build_gate(wall_inner, out, along, host_origin, host_half)
	_spawn_encounter(-out)

func _build_columns(wall_inner: Vector3, out: Vector3, along: Vector3, floor_y: float) -> void:
	var flip := 1.0 if randf() < 0.5 else -1.0
	for c in CLIMB_COLUMNS:
		var pos := wall_inner - out * c.y + along * c.x * flip
		pos.y = floor_y
		_column(pos, c.z)

func _build_gate(wall_inner: Vector3, out: Vector3, along: Vector3, host_origin: Vector3, host_half: Vector2) -> void:
	var wt := GeneratedMap.WALL_THICKNESS
	var gate_pos := wall_inner + out * wt / 2.0
	gate_pos.y = host_origin.y
	_gate = SecretGate.new()
	_gate.size = Vector3(GATE_SIZE.x if host_dir.y != 0 else 0.25, GATE_SIZE.y, 0.25 if host_dir.y != 0 else GATE_SIZE.x)
	_map.add_child(_gate)
	_gate.global_position = gate_pos
	# The lever stands in a far corner, a sprint across the room.
	var depth: float = host_half.x if host_dir.x != 0 else host_half.y
	var width: float = host_half.y if host_dir.x != 0 else host_half.x
	var side := 1.0 if randf() < 0.5 else -1.0
	var lever_pos := host_origin - out * (depth - 1.0) + along * side * (width - 1.0)
	var lever := SecretLever.new()
	_map.add_child(lever)
	lever.global_position = lever_pos
	lever.rotation.y = atan2(out.x, out.z)
	var run := Vector2(lever_pos.x - gate_pos.x, lever_pos.z - gate_pos.z).length()
	var open_time := run / SPRINT_SPEED + GATE_GRACE
	lever.pulled.connect(func(): _gate.open_for(open_time))
	# A lever inside lets the player back out.
	var inner := SecretLever.new()
	_map.add_child(inner)
	inner.global_position = wall_inner + out * (wt + 0.8) + along * (GATE_SIZE.x / 2.0 + 0.9)
	inner.global_position.y = host_origin.y
	inner.rotation.y = atan2(-out.x, -out.z)
	inner.pulled.connect(func(): _gate.open_for(4.0))
	if _map._dresser:
		_map._dresser.reserve(Rect2(Vector2(lever_pos.x, lever_pos.z) - Vector2.ONE * 1.2, Vector2.ONE * 2.4))
		var lane := wall_inner - out * 2.0
		_map._dresser.reserve(Rect2(Vector2(lane.x, lane.z) - Vector2.ONE * 2.2, Vector2.ONE * 4.4))

## ---- Open layouts: the spire -----------------------------------------------

func build_spire() -> void:
	var c := chamber_centre
	var walls_before := _map.interior_wall_count
	var base := Vector3(c.x, 0.0, c.z)
	# Sunk a little so uneven ground doesn't leave a gap under it.
	_solid(base + Vector3(0, (SPIRE_FLOOR - 1.5) / 2.0, 0), Vector3(SPIRE_HALF * 2.0, SPIRE_FLOOR + 1.5, SPIRE_HALF * 2.0), false)
	_map._build_floor(c + Vector3(0, 0.01, 0), SPIRE_HALF * 2.0, SPIRE_HALF * 2.0, 0.0, GeneratedMap.VAULT_FLOOR_COLOR)
	var door_dir: Vector2i = DIRS[randi() % DIRS.size()]
	var wt := GeneratedMap.WALL_THICKNESS
	for dir in DIRS:
		var horizontal := dir.y != 0
		var n := Vector3(dir.x, 0, dir.y)
		var mid := c + n * (SPIRE_HALF - wt / 2.0)
		var length := SPIRE_HALF * 2.0
		if dir != door_dir:
			_map._add_wall_segment(mid, length, horizontal, SPIRE_WALL, SPIRE_FLOOR)
			continue
		var along := Vector3(absf(n.z), 0, absf(n.x))
		var seg := (length - SPIRE_DOOR.x) / 2.0
		for side in [-1.0, 1.0]:
			_map._add_wall_segment(mid + along * side * (SPIRE_DOOR.x + seg) / 2.0, seg, horizontal, SPIRE_WALL, SPIRE_FLOOR)
		_map._add_wall_segment(mid, SPIRE_DOOR.x + 0.02, horizontal, SPIRE_WALL - SPIRE_DOOR.y, SPIRE_FLOOR + SPIRE_DOOR.y)
	# The chamber's walls aren't room walls; open layouts still have none.
	_map.interior_wall_count = walls_before
	_map._build_ceiling(c, SPIRE_HALF * 2.0, SPIRE_HALF * 2.0, SPIRE_WALL)
	_add_light(c + Vector3(0, SPIRE_WALL - 0.5, 0), 2.5)
	_add_found_area(c, Vector3(SPIRE_HALF * 2.0 - 1.0, SPIRE_WALL, SPIRE_HALF * 2.0 - 1.0))
	# The last column stands in front of the door; the rest spiral down from it.
	var door_angle := atan2(float(door_dir.y), float(door_dir.x))
	var turn := deg_to_rad(SPIRE_STEP_DEGREES) * (1.0 if randf() < 0.5 else -1.0)
	var radius := SPIRE_HALF + SPIRE_COLUMN_GAP + COLUMN_SIZE / 2.0
	var count := SPIRE_COLUMN_HEIGHTS.size()
	for i in count:
		var angle := door_angle - turn * (count - 1 - i)
		_column(base + Vector3(cos(angle), 0, sin(angle)) * radius, SPIRE_COLUMN_HEIGHTS[i])
	chamber_centre = c - Vector3(door_dir.x, 0, door_dir.y) * 1.5
	_spawn_encounter(Vector3(door_dir.x, 0, door_dir.y))

## ---- Shared pieces -----------------------------------------------------------

## A stepping column from the floor up to `height`, its top edged in light.
func _column(foot: Vector3, height: float) -> void:
	var sink := 1.0
	_solid(foot + Vector3(0, (height - sink) / 2.0, 0), Vector3(COLUMN_SIZE, height + sink, COLUMN_SIZE), false)
	var cap := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(COLUMN_SIZE + 0.06, 0.08, COLUMN_SIZE + 0.06)
	cap.mesh = box
	var mat := StandardMaterial3D.new()
	var color: Color = _map.tileset.light_color if _map.tileset else Color(0.9, 0.75, 0.4)
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.6
	cap.material_override = mat
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cap.position = foot + Vector3(0, height - 0.03, 0)
	_map.add_child(cap)
	if _map._dresser:
		var r := COLUMN_SIZE / 2.0 + 0.8
		_map._dresser.reserve(Rect2(Vector2(foot.x, foot.z) - Vector2.ONE * r, Vector2.ONE * r * 2.0))

func _solid(centre: Vector3, size: Vector3, no_climb: bool) -> void:
	var body := StaticBody3D.new()
	body.position = centre
	if no_climb:
		LedgeClimb.forbid(body)
	_map.add_child(body)
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
	light.omni_range = 7.0
	light.position = pos
	_map._fade_with_distance(light)
	_map.add_child(light)

## Announces the find the first time the player steps inside.
func _add_found_area(centre: Vector3, size: Vector3) -> void:
	_found_area = Area3D.new()
	_found_area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y / 2.0
	_found_area.add_child(shape)
	_map.add_child(_found_area)
	_found_area.global_position = centre
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
	var state := {"found": _found}
	if is_instance_valid(encounter) and encounter.has_method("capture_state"):
		state["encounter"] = encounter.capture_state()
	return state

func restore(state: Dictionary) -> void:
	_found = bool(state.get("found", false))
	if is_instance_valid(encounter) and encounter.has_method("restore_state"):
		encounter.restore_state(state.get("encounter", {}))
