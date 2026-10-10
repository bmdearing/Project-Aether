extends RefCounted
class_name RoomDresser
## Dresses GeneratedMap rooms with a MapTileset's doodads: an arch on every
## doorway, props backed against walls, wall lights, rock/plant clusters in
## corners, and a few floor props off the doorway-to-doorway lanes
## (enemies chase in straight lines; packs spawn near the centre).
## Doodad models face +X (WC3 convention); placement turns that toward the
## room centre.
##
## Every placed prop claims its footprint (a world XZ rectangle); a prop
## whose footprint would overlap another prop, a pillar, a doorway or a
## kept-clear lane is moved or skipped, so props never pile into each other.

const WALL_INSET := 0.25            # gap between a prop's back and the wall face
const DOORWAY_CLEARANCE := 3.0      # half-width along a wall kept clear around a doorway
const DOORWAY_DEPTH := 3.0          # how far into the room a doorway is kept clear
const CORNER_INSET := 1.6           # cluster distance from the two walls of a corner
const LANE_WIDTH := 3.0             # doorway-to-doorway lanes through the centre
const CENTRE_CLEAR := 3.5           # half-size of the clear square packs stand in
const FOOTPRINT_GAP := 0.35         # minimum space between two props
const PLACE_ATTEMPTS := 8
const ARCH_OVERHANG := 1.4          # arch span = doorway width + this
const MIN_COLLISION_HEIGHT := 0.6   # smaller doodads (grass, bones) don't block movement
const COLLISION_SHRINK := 0.75      # collision box vs. visual bounds, so props don't snag
const LIGHT_HEIGHT_FALLBACK := 2.0
const SCALE_JITTER := 0.15
const LIGHT_PROP_SCALE := 1.8       # WC3 standing torches are ~1.1 m at unit scale; read as ~2 m
## Trees collide (and claim floor) only at the trunk; canopies may overlap.
const TRUNK_RADIUS := 0.45
const TRUNK_FOOTPRINT := 1.6

var _tileset: MapTileset
var _parent: Node3D
var _wall_thickness: float
var _doorway_width: float
## World XZ rectangles taken by props and kept-clear areas.
var _occupied: Array[Rect2] = []

func _init(tileset: MapTileset, parent: Node3D, wall_thickness: float, doorway_width: float) -> void:
	_tileset = tileset
	_parent = parent
	_wall_thickness = wall_thickness
	_doorway_width = doorway_width

## Marks a world XZ rectangle as taken (pillars, the boss altar...).
func reserve(rect: Rect2) -> void:
	_occupied.append(rect)

## half: the room's half-extents (x, z). open_sides: Vector2i directions with
## a doorway. sparse dresses only lights and corner clusters (the boss room).
func dress(origin: Vector3, half: Vector2, open_sides: Array, sparse: bool = false) -> void:
	var o := Vector2(origin.x, origin.z)
	# Keep doorways, the lanes between them and the pack area clear.
	for dir in open_sides:
		var d := Vector2(dir.x, dir.y)
		var along := Vector2(absf(d.y), absf(d.x))
		var mouth := o + d * (Vector2(half.x, half.y) * d.abs()).length()
		var size := along * DOORWAY_CLEARANCE * 2.0 + d.abs() * DOORWAY_DEPTH * 2.0
		reserve(Rect2(mouth - size / 2.0, size))
		var lane_len := (Vector2(half.x, half.y) * d.abs()).length()
		var lane_size := along * LANE_WIDTH + d.abs() * lane_len
		reserve(Rect2(o + d * lane_len / 2.0 - lane_size / 2.0, lane_size))
	reserve(Rect2(o - Vector2.ONE * CENTRE_CLEAR, Vector2.ONE * CENTRE_CLEAR * 2.0))

	for dir in open_sides:
		_place_archway(origin, half, dir)
	var sides := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	for i in _tileset.lights_per_room:
		_place_wall_light(origin, half, sides.pick_random(), open_sides)
	if not sparse:
		for i in randi_range(_tileset.wall_props_per_room.x, _tileset.wall_props_per_room.y):
			_place_against_wall(origin, half, _tileset.wall_props.pick_random(), sides.pick_random(), open_sides)
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	corners.shuffle()
	for i in mini(randi_range(_tileset.clusters_per_room.x, _tileset.clusters_per_room.y), corners.size()):
		var c: Vector2 = corners[i]
		var spot := Vector3(c.x * (half.x - CORNER_INSET), 0, c.y * (half.y - CORNER_INSET))
		spot += Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
		place_loose(origin + spot, _tileset.clusters.pick_random())
	if sparse:
		return
	for i in randi_range(_tileset.floor_props_per_room.x, _tileset.floor_props_per_room.y):
		var scene: PackedScene = _tileset.floor_props.pick_random()
		for attempt in PLACE_ATTEMPTS:
			var spot := Vector3(randf_range(-half.x + 2.0, half.x - 2.0), 0, randf_range(-half.y + 2.0, half.y - 2.0))
			if place_loose(origin + spot, scene):
				break

func _place_archway(origin: Vector3, half: Vector2, dir: Vector2i) -> void:
	if _tileset.archways.is_empty():
		return
	var arch := _spawn(_tileset.archways.pick_random())
	var bounds := _local_bounds(arch)
	# Turn the arch so its longer horizontal extent runs along the wall.
	var span_on_x := bounds.size.x >= bounds.size.z
	var wall_along_x := dir == Vector2i.UP or dir == Vector2i.DOWN
	var yaw := 0.0 if span_on_x == wall_along_x else PI / 2.0
	var span := maxf(bounds.size.x, bounds.size.z)
	var s := clampf((_doorway_width + ARCH_OVERHANG) / maxf(span, 0.01), 0.3, 4.0)
	arch.scale = Vector3.ONE * s
	arch.rotation.y = yaw
	var centre := Vector3(bounds.get_center().x, 0, bounds.get_center().z) * s
	arch.position = origin + Vector3(dir.x * half.x, 0, dir.y * half.y) - centre.rotated(Vector3.UP, yaw)

func _place_against_wall(origin: Vector3, half: Vector2, scene: PackedScene, dir: Vector2i, open_sides: Array, base_scale: float = 1.0) -> Node3D:
	if scene == null:
		return null
	var node := _spawn(scene)
	node.scale = Vector3.ONE * base_scale * randf_range(1.0 - SCALE_JITTER, 1.0 + SCALE_JITTER)
	var bounds := _local_bounds(node)
	var inward := -Vector3(dir.x, 0, dir.y)
	# +X faces the room: the prop's back (min x) sits WALL_INSET off the wall.
	node.rotation.y = atan2(-inward.z, inward.x)
	var depth_back := -bounds.position.x * node.scale.x
	var wall_dist := (half.x if dir.x != 0 else half.y) - _wall_thickness / 2.0
	var wall_len := half.y if dir.x != 0 else half.x
	for attempt in PLACE_ATTEMPTS:
		var along := _wall_spot(dir, open_sides, wall_len)
		if is_nan(along):
			continue
		var wall_point := Vector3(dir.x, 0, dir.y) * wall_dist + _along_vector(dir) * along
		var pos := origin + wall_point + inward * (WALL_INSET + depth_back)
		var rect := _footprint(pos, node.rotation.y, bounds, node.scale.x)
		if _overlaps(rect):
			continue
		node.position = pos
		_occupied.append(rect)
		_add_collision(node, bounds)
		return node
	node.queue_free()
	return null

func _place_wall_light(origin: Vector3, half: Vector2, dir: Vector2i, open_sides: Array) -> void:
	if _tileset.wall_lights.is_empty():
		return
	var node := _place_against_wall(origin, half, _tileset.wall_lights.pick_random(), dir, open_sides, LIGHT_PROP_SCALE)
	if node == null:
		return
	var bounds := _local_bounds(node)
	var top := bounds.end.y * node.scale.y if bounds.size.y > 0.1 else LIGHT_HEIGHT_FALLBACK
	var light := FlickerLight.new()
	light.light_color = _tileset.light_color
	light.light_energy = _tileset.light_energy
	light.omni_range = _tileset.light_range
	light.position = Vector3(0, top + 0.15, 0)
	node.add_child(light)

## Places a prop at position with a random turn, unless its footprint would
## overlap something already placed. Returns whether it was placed.
func place_loose(position: Vector3, scene: PackedScene) -> bool:
	if scene == null:
		return false
	var node := _spawn(scene)
	node.scale = Vector3.ONE * randf_range(1.0 - SCALE_JITTER, 1.0 + SCALE_JITTER)
	node.rotation.y = randf() * TAU
	var bounds := _local_bounds(node)
	var tree := _is_tree(node)
	var rect := Rect2(Vector2(position.x, position.z) - Vector2.ONE * TRUNK_FOOTPRINT / 2.0, Vector2.ONE * TRUNK_FOOTPRINT) if tree \
			else _footprint(position, node.rotation.y, bounds, node.scale.x)
	if _overlaps(rect):
		node.queue_free()
		return false
	node.position = position
	_occupied.append(rect)
	if tree:
		_add_trunk_collision(node, bounds)
	else:
		_add_collision(node, bounds)
	return true

## Places a prop at a set position, turn and scale unless it would overlap
## something already placed; returns it (with collision), or null.
func place_at(position: Vector3, scene: PackedScene, yaw: float, prop_scale: float = 1.0, collide: bool = true) -> Node3D:
	if scene == null:
		return null
	var node := _spawn(scene)
	node.scale = Vector3.ONE * prop_scale
	node.rotation.y = yaw
	var bounds := _local_bounds(node)
	var rect := _footprint(position, yaw, bounds, prop_scale)
	if _overlaps(rect):
		node.queue_free()
		return null
	node.position = position
	_occupied.append(rect)
	if collide:
		_add_collision(node, bounds)
	return node

## Visible-mesh bounds of a scene's instance (unscaled), for layout maths.
func measure(scene: PackedScene) -> AABB:
	var node := _spawn(scene)
	var bounds := _local_bounds(node)
	_parent.remove_child(node)
	node.free()
	return bounds

## World XZ rectangle covering a prop's visible bounds at pos and yaw.
func _footprint(pos: Vector3, yaw: float, bounds: AABB, s: float) -> Rect2:
	var rect := Rect2()
	var first := true
	for corner in [Vector3(bounds.position.x, 0, bounds.position.z), Vector3(bounds.end.x, 0, bounds.position.z),
			Vector3(bounds.position.x, 0, bounds.end.z), Vector3(bounds.end.x, 0, bounds.end.z)]:
		var p: Vector3 = pos + (corner * s).rotated(Vector3.UP, yaw)
		var point := Rect2(Vector2(p.x, p.z), Vector2.ZERO)
		rect = point if first else rect.merge(point)
		first = false
	return rect

func _overlaps(rect: Rect2) -> bool:
	var grown := rect.grow(FOOTPRINT_GAP)
	for other in _occupied:
		if grown.intersects(other):
			return true
	return false

## A point along the wall (local, -half_len..half_len) clear of doorways and corners, or NAN.
func _wall_spot(dir: Vector2i, open_sides: Array, half_len: float) -> float:
	var limit := half_len - 1.4
	for attempt in 6:
		var t := randf_range(-limit, limit)
		if not (dir in open_sides) or absf(t) > DOORWAY_CLEARANCE:
			return t
	return NAN

func _along_vector(dir: Vector2i) -> Vector3:
	return Vector3(1, 0, 0) if dir == Vector2i.UP or dir == Vector2i.DOWN else Vector3(0, 0, 1)

func _spawn(scene: PackedScene) -> Node3D:
	var node := scene.instantiate() as Node3D
	_parent.add_child(node)
	var size := _local_bounds(node).size * node.scale
	DrawDistance.apply(node, DrawDistance.range_for_size(maxf(size.x, maxf(size.y, size.z))))
	return node

## Visible-mesh bounds in the node's local space, before its own scale and rotation.
func _local_bounds(node: Node3D) -> AABB:
	var inv := node.global_transform.affine_inverse()
	var result := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var box := inv * mi.global_transform * mi.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func _add_collision(node: Node3D, bounds: AABB) -> void:
	if bounds.size.y * node.scale.y < MIN_COLLISION_HEIGHT:
		return
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(bounds.size.x * COLLISION_SHRINK, bounds.size.y, bounds.size.z * COLLISION_SHRINK)
	shape.shape = box
	shape.position = bounds.get_center()
	body.add_child(shape)
	node.add_child(body)

func _is_tree(node: Node3D) -> bool:
	return node.scene_file_path.get_file().to_lower().contains("tree")

func _add_trunk_collision(node: Node3D, bounds: AABB) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = TRUNK_RADIUS / maxf(node.scale.x, 0.01)
	cylinder.height = bounds.size.y
	shape.shape = cylinder
	shape.position = Vector3(0, bounds.position.y + bounds.size.y / 2.0, 0)
	body.add_child(shape)
	node.add_child(body)
