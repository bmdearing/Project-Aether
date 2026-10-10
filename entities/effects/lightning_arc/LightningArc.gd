extends MeshInstance3D
class_name LightningArc
## A brief jagged lightning arc between two points (Stormcall forks, Static
## Discharge chains, Stormcall's main bolt). Glowing ribbons
## (spell_lightning.gdshader) in two crossed planes with a couple of short
## forks; the path re-jitters as it flickers, then fades, with sparks where
## it lands. Frees itself.

const SHADER := preload("res://shaders/spell_lightning.gdshader")
const SEGMENT_LENGTH := 0.45
const JITTER := 0.32
const HALF_WIDTH := 0.16
const FORKS := 2
const HOLD := 0.1
const FADE := 0.18
const FLICKERS := 2

var _from: Vector3
var _to: Vector3
var _half_width: float = HALF_WIDTH
var _forks: int = FORKS

## width scales the ribbon (Stormcall's main bolt is thicker).
static func spawn(parent: Node, from: Vector3, to: Vector3, color: Color, width: float = 1.0, sparks: bool = true, forks: int = FORKS) -> LightningArc:
	var arc := LightningArc.new()
	parent.add_child(arc)
	arc.global_position = Vector3.ZERO
	arc._from = from
	arc._to = to
	arc._half_width = HALF_WIDTH * width
	arc._forks = forks
	arc._build()
	arc._style(color)
	if sparks:
		SpellFx.burst(parent, to, color, 10, Vector2(2.0, 5.0), 0.3, Vector2(0.03, 0.07), 120.0, -8.0)
	return arc

func _style(color: Color) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("color", color.lightened(0.15))
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tween := create_tween()
	for i in FLICKERS:
		tween.tween_interval(HOLD / FLICKERS)
		tween.tween_callback(_build)
	tween.tween_method(func(a: float) -> void: mat.set_shader_parameter("alpha", a), 1.0, 0.0, FADE)
	tween.tween_callback(queue_free)

func _build() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var main := _path(_from, _to, JITTER)
	_ribbon(st, main, _half_width)
	for i in _forks:
		var start := main[randi_range(1, maxi(main.size() - 2, 1))]
		var dir := (_to - _from).normalized()
		var off := Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)).normalized()
		var end := start + (dir * 0.6 + off).normalized() * randf_range(0.6, 1.4) * clampf(_from.distance_to(_to) * 0.3, 0.4, 2.0)
		_ribbon(st, _path(start, end, JITTER * 0.6), _half_width * 0.55)
	mesh = st.commit()

func _path(a: Vector3, b: Vector3, jitter: float) -> Array[Vector3]:
	var count := maxi(3, ceili(a.distance_to(b) / SEGMENT_LENGTH))
	var points: Array[Vector3] = []
	for i in count + 1:
		var t := float(i) / count
		var p := a.lerp(b, t)
		if i > 0 and i < count:
			p += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * jitter
		points.append(p)
	return points

## Two crossed ribbons along the path, UV.x across each, tapering at the tip.
func _ribbon(st: SurfaceTool, points: Array[Vector3], half_width: float) -> void:
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var dir := (b - a).normalized()
		var side := dir.cross(Vector3.UP)
		if side.length() < 0.01:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := dir.cross(side).normalized()
		var wa := half_width * (1.0 - 0.5 * float(i) / points.size())
		var wb := half_width * (1.0 - 0.5 * float(i + 1) / points.size())
		for perp in [side, up]:
			var quad := [[a - perp * wa, 0.0], [a + perp * wa, 1.0], [b + perp * wb, 1.0], [b - perp * wb, 0.0]]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_uv(Vector2(quad[idx][1], float(i) / points.size()))
				st.add_vertex(quad[idx][0])
