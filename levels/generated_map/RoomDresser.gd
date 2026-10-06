extends RefCounted
class_name RoomDresser
## Dresses GeneratedMap rooms with a MapTileset's doodads: an arch on every
## doorway, props backed against walls, wall lights, rock/plant clusters in
## corners, and a few floor props off the doorway-to-doorway cross paths
## (enemies chase in straight lines; packs spawn near the centre).
## Doodad models face +X (WC3 convention); placement turns that toward the
## room centre.

const WALL_INSET := 0.25            # gap between a prop's back and the wall face
const DOORWAY_CLEARANCE := 3.0      # half-width along a wall kept clear around a doorway
const CORNER_DISTANCE := 5.2        # from room centre, per axis
const FLOOR_PROP_RANGE := Vector2(3.2, 4.6)  # per-axis distance band from room centre
const ARCH_OVERHANG := 1.4          # arch span = doorway width + this
const MIN_COLLISION_HEIGHT := 0.6   # smaller doodads (grass, bones) don't block movement
const COLLISION_SHRINK := 0.75      # collision box vs. visual bounds, so props don't snag
const LIGHT_HEIGHT_FALLBACK := 2.0
const SCALE_JITTER := 0.15
const LIGHT_PROP_SCALE := 1.8       # WC3 standing torches are ~1.1 m at unit scale; read as ~2 m

var _tileset: MapTileset
var _parent: Node3D
var _half: float
var _wall_face: float
var _doorway_width: float

func _init(tileset: MapTileset, parent: Node3D, room_footprint: float, wall_thickness: float, doorway_width: float) -> void:
	_tileset = tileset
	_parent = parent
	_half = room_footprint / 2.0
	_wall_face = _half - wall_thickness / 2.0
	_doorway_width = doorway_width

## open_sides: Vector2i directions with a doorway. min_z: props stay at or
## beyond this local z (the Vault keeps them on its main floor, off the gap).
func dress(origin: Vector3, open_sides: Array, min_z: float = -INF, max_z: float = INF) -> void:
	for dir in open_sides:
		_place_archway(origin, dir)
	var sides := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	for i in _tileset.lights_per_room:
		_place_wall_light(origin, sides.pick_random(), open_sides, min_z, max_z)
	for i in randi_range(_tileset.wall_props_per_room.x, _tileset.wall_props_per_room.y):
		_place_against_wall(origin, _tileset.wall_props.pick_random(), sides.pick_random(), open_sides, min_z, max_z)
	for i in randi_range(_tileset.clusters_per_room.x, _tileset.clusters_per_room.y):
		var corner := Vector3(signf(randf() - 0.5), 0, signf(randf() - 0.5)) * CORNER_DISTANCE
		corner += Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
		if corner.z >= min_z and corner.z <= max_z:
			_place_loose(origin + corner, _tileset.clusters.pick_random())
	for i in randi_range(_tileset.floor_props_per_room.x, _tileset.floor_props_per_room.y):
		var spot := Vector3(randf_range(FLOOR_PROP_RANGE.x, FLOOR_PROP_RANGE.y) * signf(randf() - 0.5), 0,
				randf_range(FLOOR_PROP_RANGE.x, FLOOR_PROP_RANGE.y) * signf(randf() - 0.5))
		if spot.z >= min_z and spot.z <= max_z:
			_place_loose(origin + spot, _tileset.floor_props.pick_random())
	if _tileset.room_light_energy > 0.0:
		var fill := OmniLight3D.new()
		fill.light_color = _tileset.light_color
		fill.light_energy = _tileset.room_light_energy
		fill.omni_range = _half * 1.6
		fill.position = origin + Vector3(0, 3.6, 0)
		_parent.add_child(fill)

func _place_archway(origin: Vector3, dir: Vector2i) -> void:
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
	arch.position = origin + Vector3(dir.x, 0, dir.y) * _half - centre.rotated(Vector3.UP, yaw)

func _place_against_wall(origin: Vector3, scene: PackedScene, dir: Vector2i, open_sides: Array, min_z: float, max_z: float, base_scale: float = 1.0) -> Node3D:
	if scene == null:
		return null
	var along := _wall_spot(dir, open_sides)
	if is_nan(along):
		return null
	var node := _spawn(scene)
	node.scale = Vector3.ONE * base_scale * randf_range(1.0 - SCALE_JITTER, 1.0 + SCALE_JITTER)
	var bounds := _local_bounds(node)
	var inward := -Vector3(dir.x, 0, dir.y)
	# +X faces the room: the prop's back (min x) sits WALL_INSET off the wall.
	node.rotation.y = atan2(-inward.z, inward.x)
	var depth_back := -bounds.position.x * node.scale.x
	var wall_point := Vector3(dir.x, 0, dir.y) * _wall_face + _along_vector(dir) * along
	var local := wall_point + inward * (WALL_INSET + depth_back)
	if local.z < min_z or local.z > max_z:
		node.queue_free()
		return null
	node.position = origin + local
	_add_collision(node, bounds)
	return node

func _place_wall_light(origin: Vector3, dir: Vector2i, open_sides: Array, min_z: float, max_z: float) -> void:
	if _tileset.wall_lights.is_empty():
		return
	var node := _place_against_wall(origin, _tileset.wall_lights.pick_random(), dir, open_sides, min_z, max_z, LIGHT_PROP_SCALE)
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

func _place_loose(position: Vector3, scene: PackedScene) -> void:
	if scene == null:
		return
	var node := _spawn(scene)
	node.scale = Vector3.ONE * randf_range(1.0 - SCALE_JITTER, 1.0 + SCALE_JITTER)
	node.rotation.y = randf() * TAU
	node.position = position
	_add_collision(node, _local_bounds(node))

## A point along the wall (local, -half..half) clear of doorways and corners, or NAN.
func _wall_spot(dir: Vector2i, open_sides: Array) -> float:
	var limit := _half - 1.2
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
