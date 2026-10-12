extends Node3D
class_name AureliaFireWall
## Aurelia's Fire Wall: a quarter circle of flame rolling outward from her.
## Once it's SPLIT_AT out it parts in the middle, leaving a gap GAP_WIDTH
## wide to step through; anywhere else along the arc burns. It hits a
## player once.

const SPEED := 8.5
const HALF_ARC := PI / 4.0
const MAX_RADIUS := 27.0
const SPLIT_AT := 3.0
## The gap opens over this many metres after SPLIT_AT.
const SPLIT_OPEN := 1.5
const GAP_WIDTH := 2.4
const HEIGHT := 2.4
const BAND := 0.7
const SEGMENTS := 20
const FLAME_SHADER := preload("res://shaders/spell_flame.gdshader")

## Emitted as the wall burns out, with its last radius.
signal finished(radius: float)

var forward := Vector3.FORWARD
var damage := 10.0
var source: Enemy

var radius := 0.6
var _hit := false
var _player: Player
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _spark_timer := 0.0

static func cast(parent: Node, origin: Vector3, dir: Vector3, hit: float, from: Enemy) -> AureliaFireWall:
	var wall := AureliaFireWall.new()
	wall.forward = Vector3(dir.x, 0.0, dir.z).normalized()
	wall.damage = hit
	wall.source = from
	parent.add_child(wall)
	wall.global_position = Vector3(origin.x, origin.y + 0.02, origin.z)
	return wall

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player
	_mesh = MeshInstance3D.new()
	_mat = ShaderMaterial.new()
	_mat.shader = FLAME_SHADER
	_mat.set_shader_parameter("fill", 0.18)
	_mat.set_shader_parameter("edge_soft", 0.05)
	_mat.set_shader_parameter("intensity", 0.95)
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_rebuild()

## Half the angle the gap covers at radius r (0 before it splits).
func gap_half_angle(r: float) -> float:
	if r <= SPLIT_AT:
		return 0.0
	var open := clampf((r - SPLIT_AT) / SPLIT_OPEN, 0.0, 1.0)
	return minf(asin(clampf(GAP_WIDTH * 0.5 * open / r, 0.0, 1.0)), HALF_ARC * 0.9)

func _physics_process(delta: float) -> void:
	radius += SPEED * delta
	_rebuild()
	_check_hit()
	_spark_timer -= delta
	if _spark_timer <= 0.0:
		_spark_timer = 0.08
		var a := randf_range(-HALF_ARC, HALF_ARC)
		if absf(a) > gap_half_angle(radius):
			SpellFx.burst(get_parent(), _point(a, radius) + Vector3.UP * 0.4, Color(1.0, 0.5, 0.15), 6, Vector2(1.5, 3.5), 0.5, Vector2(0.06, 0.14), 40.0, 2.0)
	if radius >= MAX_RADIUS:
		finished.emit(radius)
		var fade := create_tween()
		fade.tween_method(func(v: float): _mat.set_shader_parameter("burn", v), 1.0, 0.0, 0.35)
		fade.tween_callback(queue_free)
		set_physics_process(false)

func _point(angle: float, r: float) -> Vector3:
	return global_position + forward.rotated(Vector3.UP, angle) * r

## Two flame sheets, one each side of the gap.
func _rebuild() -> void:
	var gap := gap_half_angle(radius)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var basis_y := atan2(forward.x, forward.z)
	var arc_len := (HALF_ARC - gap) * radius
	for side in [-1.0, 1.0]:
		for i in SEGMENTS:
			var t0 := float(i) / SEGMENTS
			var t1 := float(i + 1) / SEGMENTS
			var a0: float = side * lerpf(gap, HALF_ARC, t0) + basis_y
			var a1: float = side * lerpf(gap, HALF_ARC, t1) + basis_y
			var p0 := Vector3(sin(a0), 0, cos(a0)) * radius
			var p1 := Vector3(sin(a1), 0, cos(a1)) * radius
			# UV.x in metres/3 along the sheet so tongues stay a steady size.
			var u0 := t0 * arc_len / 3.0
			var u1 := t1 * arc_len / 3.0
			var quad := [[p0, Vector2(u0, 0)], [p1, Vector2(u1, 0)], [p1 + Vector3.UP * HEIGHT, Vector2(u1, 1)], [p0 + Vector3.UP * HEIGHT, Vector2(u0, 1)]]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_uv(quad[idx][1])
				st.set_normal(Vector3(sin(a0), 0, cos(a0)))
				st.add_vertex(quad[idx][0])
	_mesh.mesh = st.commit()
	_mat.set_shader_parameter("tiles", 4.0)

func _check_hit() -> void:
	if _hit or not is_instance_valid(_player) or not _player.health.is_alive():
		return
	var rel := _player.global_position - global_position
	if rel.y > HEIGHT:
		return
	rel.y = 0.0
	if absf(rel.length() - radius) > BAND:
		return
	var angle := absf(forward.signed_angle_to(rel.normalized(), Vector3.UP))
	if angle > HALF_ARC + 0.03 or angle < gap_half_angle(rel.length()):
		return
	_hit = true
	AureliaAilments.hit(_player, damage, Constants.DamageType.FIRE, source)
	if _player.status_effects:
		_player.status_effects.apply_effect("ignite", source, damage)
	SpellFx.flash(get_parent(), _player.global_position + Vector3.UP, Color(1.0, 0.5, 0.15), 2.0, 0.2)
