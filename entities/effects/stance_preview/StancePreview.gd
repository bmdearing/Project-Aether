extends MeshInstance3D
class_name StancePreview
## Ground outline of where a charging stance attack will land, redrawn every
## frame as the charge grows: a circle (slams), a strip (shockwaves, the path
## of a lunge), a cone (point-blank blasts) and a landing ring (lunges).

const COLOR := Color(1.0, 0.86, 0.55, 0.55)
const FILL_ALPHA := 0.12
const LIFT := 0.06
const SEGMENTS := 40

var _mesh := ImmediateMesh.new()

func _init() -> void:
	mesh = _mesh
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	material_override = mat

## Shapes: {"circle": [center, radius]}, {"strip": [from, dir, length, width]},
## {"cone": [apex, dir, reach, half_angle_deg]}, each optional.
func draw(shapes: Dictionary) -> void:
	_mesh.clear_surfaces()
	global_transform = Transform3D.IDENTITY
	if shapes.has("circle"):
		_circle(shapes["circle"][0], shapes["circle"][1])
	if shapes.has("strip"):
		var s: Array = shapes["strip"]
		_strip(s[0], s[1], s[2], s[3])
	if shapes.has("cone"):
		var c: Array = shapes["cone"]
		_cone(c[0], c[1], c[2], c[3])

func _circle(center: Vector3, radius: float) -> void:
	var c := center + Vector3.UP * LIFT
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGMENTS:
		var a := TAU * i / SEGMENTS
		var b := TAU * (i + 1) / SEGMENTS
		var pa := c + Vector3(cos(a), 0, sin(a)) * radius
		var pb := c + Vector3(cos(b), 0, sin(b)) * radius
		_tri(c, pa, pb, Color(COLOR, FILL_ALPHA))
		# Rim band.
		var ia := c + Vector3(cos(a), 0, sin(a)) * maxf(radius - 0.12, 0.0)
		var ib := c + Vector3(cos(b), 0, sin(b)) * maxf(radius - 0.12, 0.0)
		_tri(ia, pa, pb, COLOR)
		_tri(ia, pb, ib, COLOR)
	_mesh.surface_end()

func _strip(from: Vector3, dir: Vector3, length: float, width: float) -> void:
	var f := from + Vector3.UP * LIFT
	var side := dir.cross(Vector3.UP).normalized() * width * 0.5
	var to := f + dir * length
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_tri(f - side, f + side, to + side, Color(COLOR, FILL_ALPHA))
	_tri(f - side, to + side, to - side, Color(COLOR, FILL_ALPHA))
	for edge: float in [-1.0, 1.0]:
		var e: Vector3 = side * edge
		var inner: Vector3 = side * edge * maxf(1.0 - 0.12 / maxf(width * 0.5, 0.01), 0.0)
		_tri(f + inner, f + e, to + e, COLOR)
		_tri(f + inner, to + e, to + inner, COLOR)
	_mesh.surface_end()

func _cone(apex: Vector3, dir: Vector3, reach: float, half_angle: float) -> void:
	var a0 := apex + Vector3.UP * LIFT
	var steps := 16
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		var ta := deg_to_rad(lerpf(-half_angle, half_angle, float(i) / steps))
		var tb := deg_to_rad(lerpf(-half_angle, half_angle, float(i + 1) / steps))
		var pa := a0 + dir.rotated(Vector3.UP, ta) * reach
		var pb := a0 + dir.rotated(Vector3.UP, tb) * reach
		_tri(a0, pa, pb, Color(COLOR, FILL_ALPHA))
		var ia := a0 + dir.rotated(Vector3.UP, ta) * maxf(reach - 0.12, 0.0)
		var ib := a0 + dir.rotated(Vector3.UP, tb) * maxf(reach - 0.12, 0.0)
		_tri(ia, pa, pb, COLOR)
		_tri(ia, pb, ib, COLOR)
	_mesh.surface_end()

func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for p in [a, b, c]:
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(p)
