extends MeshInstance3D
class_name LightningArc
## A brief jagged lightning arc between two points (Stormcall forks, Static
## Discharge chains, Stormcall's main bolt, Spark's crackle). Glowing ribbons
## (spell_lightning.gdshader) in two crossed planes along a midpoint-displaced
## path, so it kinks at every scale, with forks that can fork again; the path
## re-rolls as it flickers, then fades, with sparks where it lands. Frees itself.

const SHADER := preload("res://shaders/spell_lightning.gdshader")
const SEGMENT_LENGTH := 0.2
## Midpoint offset as a fraction of the segment being split.
const ROUGHNESS := 0.32
const HALF_WIDTH := 0.16
const FORKS := 2
const HOLD := 0.12
const FADE := 0.18
const FLICKERS := 3

var _from: Vector3
var _to: Vector3
var _half_width: float = HALF_WIDTH
var _forks: int = FORKS

## width scales the ribbon (Stormcall's main bolt is thicker). hud_clear fades
## it near the camera and low on screen, for small arcs round the player.
static func spawn(parent: Node, from: Vector3, to: Vector3, color: Color, width: float = 1.0, sparks: bool = true, forks: int = FORKS, hud_clear: bool = false) -> LightningArc:
	var arc := LightningArc.new()
	parent.add_child(arc)
	arc.global_position = Vector3.ZERO
	arc._from = from
	arc._to = to
	arc._half_width = HALF_WIDTH * width
	arc._forks = forks
	arc._build()
	arc._style(color, hud_clear)
	if sparks:
		SpellFx.burst(parent, to, color, 10, Vector2(2.0, 5.0), 0.3, Vector2(0.03, 0.07), 120.0, -8.0)
	return arc

func _style(color: Color, hud_clear: bool) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("color", color.lightened(0.15))
	mat.set_shader_parameter("seed", randf() * 100.0)
	mat.set_shader_parameter("hud_clear", 1.0 if hud_clear else 0.0)
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
	var main := _path(_from, _to)
	_ribbon(st, main, _half_width)
	var length := _from.distance_to(_to)
	for i in _forks:
		_fork(st, main, length * randf_range(0.2, 0.4), _half_width * 0.55, 1)
	mesh = st.commit()

## A branch off a random point of `trunk`, angled away from it and onward.
func _fork(st: SurfaceTool, trunk: Array[Vector3], length: float, half_width: float, depth: int) -> void:
	if trunk.size() < 3 or length < 0.15:
		return
	var at := randi_range(1, trunk.size() - 2)
	var start := trunk[at]
	var onward := (trunk[mini(at + 2, trunk.size() - 1)] - start).normalized()
	var off := _perpendicular(onward) * randf_range(0.6, 1.2)
	var branch := _path(start, start + (onward + off).normalized() * length)
	_ribbon(st, branch, half_width)
	if depth > 0 and randf() < 0.6:
		_fork(st, branch, length * 0.5, half_width * 0.6, depth - 1)

## Midpoint displacement: split every segment, nudging the midpoint sideways
## by ROUGHNESS of its length, until segments are under SEGMENT_LENGTH.
func _path(a: Vector3, b: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = [a, b]
	var seg := a.distance_to(b)
	while seg > SEGMENT_LENGTH and points.size() < 129:
		var next: Array[Vector3] = [points[0]]
		for i in points.size() - 1:
			var p := points[i]
			var q := points[i + 1]
			next.append((p + q) * 0.5 + _perpendicular(q - p) * seg * ROUGHNESS * randf_range(-1.0, 1.0))
			next.append(q)
		points = next
		seg *= 0.5
	return points

static func _perpendicular(dir: Vector3) -> Vector3:
	var d := dir.normalized()
	var r := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	var p := r - d * r.dot(d)
	return p.normalized() if p.length() > 0.01 else d.cross(Vector3.UP).normalized()

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
		var wa := half_width * (1.0 - 0.6 * float(i) / points.size())
		var wb := half_width * (1.0 - 0.6 * float(i + 1) / points.size())
		for perp in [side, up]:
			var quad := [[a - perp * wa, 0.0, i], [a + perp * wa, 1.0, i], [b + perp * wb, 1.0, i + 1], [b - perp * wb, 0.0, i + 1]]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_uv(Vector2(quad[idx][1], float(quad[idx][2]) / points.size()))
				st.add_vertex(quad[idx][0])
