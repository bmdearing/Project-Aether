extends Node3D
class_name BossTelegraph
## A ground warning for a boss ability: a translucent disc (or a rectangle,
## for charges) that fills from the centre over `duration`, with a bright
## outline at the full size. Frees itself when the fill completes, or stays
## as a hazard marker when `persist` is set (BossBrain frees it).

const FLOOR_LIFT := 0.04
const FILL_ALPHA := 0.35
const EDGE_ALPHA := 0.85

var color := Color(1.0, 0.25, 0.15)
var duration := 1.0
var persist := false
var _fill: MeshInstance3D
var _elapsed := 0.0

## A disc of `radius` metres.
static func circle(parent: Node, at: Vector3, radius: float, time: float, tint: Color) -> BossTelegraph:
	var t := BossTelegraph.new()
	t.color = tint
	t.duration = time
	parent.add_child(t)
	t.global_position = at + Vector3(0, FLOOR_LIFT, 0)
	t._build_circle(radius)
	return t

## A `width` x `length` strip from `from` along `direction`.
static func line(parent: Node, from: Vector3, direction: Vector3, length: float, width: float, time: float, tint: Color) -> BossTelegraph:
	var t := BossTelegraph.new()
	t.color = tint
	t.duration = time
	parent.add_child(t)
	var flat := Vector3(direction.x, 0, direction.z).normalized()
	t.global_position = from + flat * length / 2.0 + Vector3(0, FLOOR_LIFT, 0)
	if flat.length() > 0.01:
		t.look_at(t.global_position + flat, Vector3.UP)
	t._build_box(Vector3(width, 0.02, length))
	return t

func _build_circle(radius: float) -> void:
	var edge := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(radius - 0.12, 0.01)
	torus.outer_radius = radius
	torus.rings = 48
	edge.mesh = torus
	edge.scale = Vector3(1, 0.05, 1)
	edge.material_override = _material(EDGE_ALPHA)
	add_child(edge)
	_fill = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.02
	disc.radial_segments = 48
	_fill.mesh = disc
	_fill.material_override = _material(FILL_ALPHA)
	_fill.scale = Vector3(0.01, 1, 0.01)
	add_child(_fill)

func _build_box(size: Vector3) -> void:
	var edge := MeshInstance3D.new()
	var outline := BoxMesh.new()
	outline.size = size
	edge.mesh = outline
	edge.material_override = _material(FILL_ALPHA * 0.5)
	add_child(edge)
	_fill = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	_fill.mesh = box
	_fill.material_override = _material(FILL_ALPHA)
	_fill.scale = Vector3(1, 1, 0.01)
	add_child(_fill)

func _material(alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, alpha)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _process(delta: float) -> void:
	_elapsed += delta
	var f := clampf(_elapsed / maxf(duration, 0.01), 0.0, 1.0)
	if _fill and _fill.mesh is CylinderMesh:
		_fill.scale = Vector3(maxf(f, 0.01), 1, maxf(f, 0.01))
	elif _fill:
		_fill.scale = Vector3(1, 1, maxf(f, 0.01))
	if f >= 1.0 and not persist:
		queue_free()
