extends MeshInstance3D
class_name LightningArc
## A brief jagged lightning arc between two points (Stormcall forks, Static
## Discharge chains). Flat camera-independent ribbons in two planes, flashes
## in and fades out, then frees itself.

const SEGMENTS := 7
const JITTER := 0.35
const HALF_WIDTH := 0.06
const HOLD := 0.08
const FADE := 0.18

static func spawn(parent: Node, from: Vector3, to: Vector3, color: Color) -> LightningArc:
	var arc := LightningArc.new()
	parent.add_child(arc)
	arc.global_position = Vector3.ZERO
	arc._build(from, to, color)
	return arc

func _build(from: Vector3, to: Vector3, color: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3] = []
	for i in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		var p := from.lerp(to, t)
		if i > 0 and i < SEGMENTS:
			p += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * JITTER
		points.append(p)
	for i in SEGMENTS:
		var a := points[i]
		var b := points[i + 1]
		var dir := (b - a).normalized()
		var side := dir.cross(Vector3.UP)
		if side.length() < 0.01:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized() * HALF_WIDTH
		var up := dir.cross(side).normalized() * HALF_WIDTH
		for perp in [side, up]:
			for v in [a - perp, a + perp, b + perp, a - perp, b + perp, b - perp]:
				st.add_vertex(v)
	mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.lightened(0.6), 1.0)
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tween := create_tween()
	tween.tween_interval(HOLD)
	tween.tween_property(mat, "albedo_color:a", 0.0, FADE)
	tween.tween_callback(queue_free)
