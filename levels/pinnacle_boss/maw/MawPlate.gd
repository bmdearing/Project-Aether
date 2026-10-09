extends StaticBody3D
class_name MawPlate
## One wedge of the Herald of the Maw's floor (MawArena): an annular sector
## from `inner_radius` to `outer_radius`, spanning `start_angle` to
## `end_angle` (radians from -Z, clockwise seen from above, in the arena's
## space). Plates crack (and then burn whoever stands on them, see
## MawArena) and, if `can_fall`, shake and drop into the void.
##
## The collision is one convex prism per arc segment, since an annular
## sector itself isn't convex.

enum State { INTACT, CRACKED, FALLING, GONE }

const THICKNESS := 1.0
## Gap left on each side, so the seams read between plates.
const SEAM := 0.05
const SEGMENT_DEGREES := 7.5
const FALL_DEPTH := 45.0
const FALL_SEC := 2.2
const SHAKE := 0.07

const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 stone_color : source_color = vec3(0.075, 0.065, 0.09);
uniform vec3 vein_color : source_color = vec3(0.55, 0.22, 0.85);
uniform float crack = 0.0;
uniform float heat = 0.0;
uniform float warn = 0.0;

varying vec3 world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float voronoi_edge(vec2 uv) {
	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 n = vec2(float(x), float(y));
			vec2 p = n + vec2(hash(cell + n), hash(cell + n + 17.0)) - f;
			float d = length(p);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fine = 1.0 - smoothstep(0.0, 0.05, voronoi_edge(world_pos.xz * 0.45));
	float broad = 1.0 - smoothstep(0.0, 0.09, voronoi_edge(world_pos.xz * 0.18 + 3.1));
	float pulse = 0.65 + 0.35 * sin(TIME * (1.4 + heat * 5.0) + world_pos.x * 0.4 + world_pos.z * 0.3);
	float veins = fine * 0.25 + broad * crack;
	vec3 glow = vein_color * (veins * pulse * (1.2 + heat * 3.0) + warn * 0.8 * (0.5 + 0.5 * sin(TIME * 14.0)));
	ALBEDO = mix(stone_color, vein_color * 0.4, veins * 0.6);
	EMISSION = glow;
	ROUGHNESS = 0.9;
}
"""

static var _shader: Shader

var inner_radius := 6.0
var outer_radius := 13.0
var start_angle := 0.0
var end_angle := PI / 4.0
## Only the outer ring falls; the inner ring can only crack, so the fight
## always has floor.
var can_fall := false
var state := State.INTACT
var _mesh_instance: MeshInstance3D
var _mat: ShaderMaterial
var _rest_position := Vector3.ZERO

func setup(r_inner: float, r_outer: float, a_start: float, a_end: float, falls: bool) -> MawPlate:
	inner_radius = r_inner
	outer_radius = r_outer
	start_angle = a_start
	end_angle = a_end
	can_fall = falls
	return self

func _ready() -> void:
	add_to_group("maw_plate")
	_rest_position = position
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_build()

## Arena-space direction for an angle (0 = -Z, clockwise from above).
static func direction(angle: float) -> Vector3:
	return Vector3(sin(angle), 0.0, -cos(angle))

static func angle_of(local_point: Vector3) -> float:
	return fposmod(atan2(local_point.x, -local_point.z), TAU)

## Whether an arena-space point lies over this plate.
func contains_local(local_point: Vector3) -> bool:
	var r := Vector2(local_point.x, local_point.z).length()
	if r < inner_radius or r > outer_radius:
		return false
	var a := angle_of(local_point)
	var span := fposmod(end_angle - start_angle, TAU)
	if span == 0.0:
		span = TAU
	return fposmod(a - start_angle, TAU) <= span

func is_solid() -> bool:
	return state == State.INTACT or state == State.CRACKED

func center_local() -> Vector3:
	return direction((start_angle + end_angle) * 0.5) * (inner_radius + outer_radius) * 0.5

func crack() -> void:
	if state != State.INTACT:
		return
	state = State.CRACKED
	create_tween().tween_method(func(v: float): _mat.set_shader_parameter("crack", v), 0.0, 1.0, 0.5)

## Entropic burn on whoever stands here (0..1), set by MawArena.
func set_heat(value: float) -> void:
	_mat.set_shader_parameter("heat", value)

## Shakes and glows for `warning` seconds, then drops into the void.
func fall(warning: float) -> void:
	if not can_fall or not is_solid():
		return
	state = State.FALLING
	_mat.set_shader_parameter("crack", 1.0)
	_mat.set_shader_parameter("warn", 1.0)
	var shake := create_tween().set_loops(maxi(int(warning / 0.08), 1))
	shake.tween_callback(func(): _mesh_instance.position = Vector3(randf_range(-SHAKE, SHAKE), randf_range(-SHAKE, SHAKE) * 0.5, randf_range(-SHAKE, SHAKE)))
	shake.tween_interval(0.08)
	await get_tree().create_timer(warning, false).timeout
	if not is_inside_tree():
		return
	shake.kill()
	state = State.GONE
	_set_collision(false)
	_mat.set_shader_parameter("warn", 0.0)
	var drop := create_tween().set_parallel()
	drop.tween_property(self, "position:y", _rest_position.y - FALL_DEPTH, FALL_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	drop.tween_property(self, "rotation", Vector3(randf_range(-0.4, 0.4), randf_range(-0.3, 0.3), randf_range(-0.4, 0.4)), FALL_SEC)
	drop.chain().tween_callback(hide)

func _set_collision(enabled: bool) -> void:
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", not enabled)

func _build() -> void:
	var span := fposmod(end_angle - start_angle, TAU)
	if span == 0.0:
		span = TAU
	var segments := maxi(int(ceil(rad_to_deg(span) / SEGMENT_DEGREES)), 1)
	# Each side loses SEAM metres of arc at its own radius.
	var r_in := inner_radius + (SEAM if inner_radius > 0.0 else 0.0)
	var r_out := outer_radius - SEAM
	var pad_out := SEAM / r_out
	var pad_in := SEAM / r_in if r_in > 0.0 else 0.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := 0.0
	var bottom := -THICKNESS
	for i in segments:
		var t0 := float(i) / segments
		var t1 := float(i + 1) / segments
		var ao0 := lerpf(start_angle + pad_out, start_angle + span - pad_out, t0)
		var ao1 := lerpf(start_angle + pad_out, start_angle + span - pad_out, t1)
		var ai0 := lerpf(start_angle + pad_in, start_angle + span - pad_in, t0)
		var ai1 := lerpf(start_angle + pad_in, start_angle + span - pad_in, t1)
		var o0 := direction(ao0) * r_out
		var o1 := direction(ao1) * r_out
		var n0 := direction(ai0) * r_in
		var n1 := direction(ai1) * r_in
		var up := Vector3.UP
		_quad(st, n0 + up * top, o0 + up * top, o1 + up * top, n1 + up * top, Vector3.UP)
		_quad(st, n1 + up * bottom, o1 + up * bottom, o0 + up * bottom, n0 + up * bottom, Vector3.DOWN)
		_quad(st, o0 + up * top, o0 + up * bottom, o1 + up * bottom, o1 + up * top, o0 + o1)
		if r_in > 0.0:
			_quad(st, n1 + up * top, n1 + up * bottom, n0 + up * bottom, n0 + up * top, -(n0 + n1))
		if i == 0:
			_quad(st, n0 + up * top, n0 + up * bottom, o0 + up * bottom, o0 + up * top, direction(ao0 - PI / 2.0))
		if i == segments - 1:
			_quad(st, o1 + up * top, o1 + up * bottom, n1 + up * bottom, n1 + up * top, direction(ao1 + PI / 2.0))
		var shape := ConvexPolygonShape3D.new()
		shape.points = PackedVector3Array([
			n0 + up * top, o0 + up * top, o1 + up * top, n1 + up * top,
			n0 + up * bottom, o0 + up * bottom, o1 + up * bottom, n1 + up * bottom,
		])
		var collision := CollisionShape3D.new()
		collision.shape = shape
		add_child(collision)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = st.commit()
	_mesh_instance.material_override = _mat
	add_child(_mesh_instance)

## Two triangles a-b-c, a-c-d with a flat normal facing `facing` (the
## material draws both sides, so winding doesn't matter).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3) -> void:
	var normal := (c - a).cross(b - a)
	if normal.length_squared() < 1e-8:
		normal = (d - a).cross(c - a)
	normal = normal.normalized()
	if normal.dot(facing) < 0.0:
		normal = -normal
	for v in [a, b, c, a, c, d]:
		st.set_normal(normal)
		st.add_vertex(v)
