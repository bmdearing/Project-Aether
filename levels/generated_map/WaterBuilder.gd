extends RefCounted
class_name WaterBuilder
## Rivers and streams for the open layouts. Each runs edge to edge along the
## boundary between two rows (or columns) of cells, meandering, so pack spots
## at cell centres stay dry.
##   River  - wide and deep; invisible bank walls (collision layer 2, which
##            stops characters but not projectiles or sight lines) keep you
##            out except at one shallow ford per cell it passes, so every
##            cell stays reachable.
##   Stream - narrow and shallow; wade straight across.
## Wading (streams, fords) slows anyone in the water (wading_factor()).

const WATER_SHADER := preload("res://shaders/river_water.gdshader")
const STEP := 5.0
const RIVER_WIDTH := 9.0
const STREAM_WIDTH := 3.5
const FORD_WIDTH := 6.0
const MEANDER := 0.14               # of cell size
const SURFACE_Y := 0.06
const BANK_WALL_HEIGHT := 3.0
const BANK_WALL_LAYER := 2
const WADE_SLOW := 0.7
const PROP_SPACING := 3.2

## The map being played, for wading checks; null off a map with water.
static var current: WaterBuilder

## {"points": PackedVector3Array, "half": float, "deep": bool, "fords": Array[float]}
var channels: Array[Dictionary] = []

var _map: Node3D  # the GeneratedMap; untyped so Player/Enemy can use this class without a load cycle

static func wading_factor(pos: Vector3) -> float:
	if current == null or not is_instance_valid(current._map):
		return 1.0
	return WADE_SLOW if current.wading_at(pos) else 1.0

func _init(map: Node3D) -> void:
	_map = map
	current = self

## Builds `rivers` rivers then `streams` streams on free cell boundaries.
## Routes `rivers` rivers then `streams` streams on free cell boundaries.
## Called before the terrain so mounds can keep out of the channels.
func plan(graph: MapGraph, cell_size: float, rivers: int, streams: int) -> void:
	var boundaries := _free_boundaries(graph)
	boundaries.shuffle()
	for i in rivers + streams:
		if boundaries.is_empty():
			break
		channels.append(_route(boundaries.pop_back(), graph, cell_size, i < rivers))

## The water surfaces, bank walls and bank dressing for the planned channels.
func build(props: Array[PackedScene], dresser: Object) -> void:
	for channel in channels:
		_build_channel(channel, props, dresser)

func wading_at(pos: Vector3) -> bool:
	for c in channels:
		var d := _distance_to_channel(c, pos)
		if d <= c["half"]:
			return true
	return false

## Inside any channel (with margin), for keeping spawns and props dry.
func is_wet(pos: Vector3, margin: float = 1.0) -> bool:
	for c in channels:
		if _distance_to_channel(c, pos) <= float(c["half"]) + margin:
			return true
	return false

## Moves a point out of the water toward `toward` (a cell centre).
func dry_point(pos: Vector3, toward: Vector3) -> Vector3:
	var p := pos
	for i in 24:
		if not is_wet(p, 1.2):
			return p
		p = p.move_toward(toward, 1.0)
	return toward

## Boundaries between rows/columns that don't touch the vault's (its dais
## and ramp reach toward them): {"axis": "x"/"z", "index": i}.
func _free_boundaries(graph: MapGraph) -> Array:
	var out := []
	for i in graph.grid_size - 1:
		if i != graph.vault_cell.y and i + 1 != graph.vault_cell.y:
			out.append({"axis": "z", "index": i})
		if i != graph.vault_cell.x and i + 1 != graph.vault_cell.x:
			out.append({"axis": "x", "index": i})
	return out

func _route(b: Dictionary, graph: MapGraph, cell_size: float, deep: bool) -> Dictionary:
	var line: float = (int(b["index"]) + 0.5) * cell_size
	var start := -cell_size * 0.5
	var finish := (graph.grid_size - 0.5) * cell_size
	var amp := cell_size * MEANDER
	var f1 := randf_range(0.04, 0.08)
	var f2 := randf_range(0.11, 0.17)
	var p1 := randf() * TAU
	var p2 := randf() * TAU
	var points := PackedVector3Array()
	var t := start
	while t <= finish + 0.01:
		var off := amp * (0.7 * sin(t * f1 + p1) + 0.3 * sin(t * f2 + p2))
		points.append(Vector3(t, SURFACE_Y, line + off) if b["axis"] == "z" else Vector3(line + off, SURFACE_Y, t))
		t += STEP
	var fords: Array[float] = []
	if deep:
		for col in graph.grid_size:
			fords.append((col + randf_range(-0.25, 0.25)) * cell_size)
	return {"points": points, "half": (RIVER_WIDTH if deep else STREAM_WIDTH) / 2.0, "deep": deep, "fords": fords, "axis": b["axis"]}

func _along(c: Dictionary, p: Vector3) -> float:
	return p.x if c["axis"] == "z" else p.z

func _at_ford(c: Dictionary, along: float) -> bool:
	for f in c["fords"]:
		if absf(along - float(f)) <= FORD_WIDTH / 2.0:
			return true
	return false

func _distance_to_channel(c: Dictionary, pos: Vector3) -> float:
	var pts: PackedVector3Array = c["points"]
	var flat := Vector2(pos.x, pos.z)
	var best := INF
	for i in pts.size() - 1:
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		var ab := b - a
		var t := clampf((flat - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, flat.distance_to(a + ab * t))
	return best

func _build_channel(c: Dictionary, props: Array[PackedScene], dresser: Object) -> void:
	var pts: PackedVector3Array = c["points"]
	var half: float = c["half"]
	_map.add_child(_ribbon(pts, half, 1.0 if c["deep"] else 0.0))
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var mid := (a + b) * 0.5
		var dir := (b - a).normalized()
		var side := dir.cross(Vector3.UP).normalized()
		# Nothing loose (doodads, chests) is placed in the channel.
		if dresser:
			var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z)) - Vector2.ONE * (half + 0.8)
			var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z)) + Vector2.ONE * (half + 0.8)
			dresser.reserve(Rect2(lo, hi - lo))
		if c["deep"] and not _at_ford(c, _along(c, mid)):
			for s in [-1.0, 1.0]:
				_bank_wall(mid + side * s * (half + 0.3), a.distance_to(b) + 0.4, dir)
	_dress_banks(c, props)

## Bank walls: characters only. Projectiles and line-of-sight rays use
## layer 1, so they cross the river.
func _bank_wall(pos: Vector3, length: float, dir: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (BANK_WALL_LAYER - 1)
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, BANK_WALL_HEIGHT, length)
	shape.shape = box
	body.add_child(shape)
	_map.add_child(body)
	body.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), pos + Vector3(0, BANK_WALL_HEIGHT / 2.0, 0))

## Rushes and cattails along the banks; lilypads on deep water.
func _dress_banks(c: Dictionary, props: Array[PackedScene]) -> void:
	var usable := props.filter(func(s): return s != null)
	if usable.is_empty():
		return
	var lily := usable.filter(func(s: PackedScene): return s.resource_path.to_lower().contains("lily"))
	var reeds := usable.filter(func(s: PackedScene): return not s.resource_path.to_lower().contains("lily"))
	var pts: PackedVector3Array = c["points"]
	var half: float = c["half"]
	var travelled := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var dir := (b - a) / maxf(seg, 0.001)
		var side := dir.cross(Vector3.UP).normalized()
		var t := fmod(travelled, PROP_SPACING)
		while t < seg:
			var p := a + dir * t
			# Fords are left clear of reeds, so crossings read as gaps.
			if not reeds.is_empty() and randf() < 0.55 and not (c["deep"] and _at_ford(c, _along(c, p))):
				var s := -1.0 if randf() < 0.5 else 1.0
				_prop(reeds.pick_random(), p + side * s * (half + randf_range(-0.4, 0.6)))
			if c["deep"] and not lily.is_empty() and randf() < 0.3 and not _at_ford(c, _along(c, p)):
				_prop(lily.pick_random(), p + side * randf_range(-half * 0.7, half * 0.7))
			t += PROP_SPACING
		travelled += seg

func _prop(scene: PackedScene, at: Vector3) -> void:
	var node := scene.instantiate() as Node3D
	_map.add_child(node)
	node.global_position = Vector3(at.x, 0.0, at.z)
	node.rotation.y = randf() * TAU
	node.scale = Vector3.ONE * randf_range(0.8, 1.2)
	DrawDistance.apply(node, DrawDistance.range_for_size(2.0))

## The water surface: a strip along the points, UV.x in metres downstream,
## UV.y across.
func _ribbon(pts: PackedVector3Array, half: float, depth: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_u := 0.0
	for i in pts.size():
		var dir := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := dir.cross(Vector3.UP).normalized() * half
		var l := pts[i] - side
		var r := pts[i] + side
		if i > 0:
			along += pts[i].distance_to(pts[i - 1])
			for v in [[prev_l, prev_u, 0.0], [r, along, 1.0], [prev_r, prev_u, 1.0], [prev_l, prev_u, 0.0], [l, along, 0.0], [r, along, 1.0]]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(v[1], v[2]))
				st.add_vertex(v[0])
		prev_l = l
		prev_r = r
		prev_u = along
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("depth", depth)
	mi.material_override = mat
	return mi
