extends MeshInstance3D
class_name AlmightyBeam
## A beam for the Almighty's eyes and lances: a white-hot core inside a
## coloured sheath, sparks and a light where it ends. place() aims it;
## hits() tests a point against it. fire() is a one-shot that flares and fades.

var width := 1.0
var color := Color(0.6, 0.5, 1.0)
var _from := Vector3.ZERO
var _dir := Vector3.FORWARD
var _length := 1.0

static func make(parent: Node, beam_color: Color, beam_width: float) -> AlmightyBeam:
	var beam := AlmightyBeam.new()
	beam.color = beam_color
	beam.width = beam_width
	parent.add_child(beam)
	beam._build()
	return beam

## A beam from `from` along `dir` that flares over `seconds` and goes out.
static func fire(parent: Node, from: Vector3, dir: Vector3, length: float, beam_color: Color, beam_width: float, seconds: float) -> AlmightyBeam:
	var beam := make(parent, beam_color, beam_width)
	beam.place(from, dir, length)
	beam.scale_width(0.2)
	var tween := beam.create_tween()
	tween.tween_method(beam.scale_width, 0.2, 1.3, seconds * 0.25)
	tween.tween_method(beam.scale_width, 1.3, 0.0, seconds * 0.75)
	tween.tween_callback(beam.queue_free)
	return beam

func _build() -> void:
	mesh = _cylinder(0.5)
	material_override = _material(Color(color, 0.45))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for layer in [["Core", 0.16, Color(1.0, 0.97, 1.0, 1.0)], ["Inner", 0.3, Color(color.lightened(0.4), 0.6)]]:
		var mi := MeshInstance3D.new()
		mi.name = layer[0]
		mi.mesh = _cylinder(layer[1])
		mi.material_override = _material(layer[2])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	var sparks := SpellFx.emitter(self, 30, 0.4)
	sparks.name = "EndSparks"
	sparks.top_level = true
	sparks.spread = 180.0
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 5.0
	sparks.gravity = Vector3(0, -6, 0)
	sparks.scale_amount_min = 0.06
	sparks.scale_amount_max = 0.14
	sparks.color_ramp = SpellFx.ramp(Color(1, 1, 1, 1), Color(color.lightened(0.3), 0.9), 0.2)
	sparks.mesh = SpellFx.glow_quad()
	var light := OmniLight3D.new()
	light.name = "EndLight"
	light.top_level = true
	light.light_color = color
	light.light_energy = 2.0
	light.omni_range = 4.5
	add_child(light)

func place(from: Vector3, dir: Vector3, length: float) -> void:
	_from = from
	_dir = dir.normalized()
	_length = maxf(length, 0.05)
	_apply(1.0)

func scale_width(factor: float) -> void:
	_apply(factor)

func _apply(factor: float) -> void:
	var side := _dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = _dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var w := width * maxf(factor, 0.001) * (1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.03))
	# The cylinder's Y axis runs along the beam.
	global_transform = Transform3D(Basis(side * w, _dir * _length, side.cross(_dir) * w), _from + _dir * _length / 2.0)
	var end := _from + _dir * _length
	for n in ["EndSparks", "EndLight"]:
		(get_node(n) as Node3D).global_position = end

## Flat (ground-plane) distance check against the beam's line.
func hits(point: Vector3, margin: float = 0.4) -> bool:
	var rel := point - _from
	rel.y = 0.0
	var flat := Vector3(_dir.x, 0.0, _dir.z)
	if flat.length() < 0.01:
		return false
	var scale_xz := flat.length()
	flat = flat.normalized()
	var along := rel.dot(flat)
	return along >= 0.0 and along <= _length * scale_xz and (rel - flat * along).length() <= width * 0.5 + margin

static func _material(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = c
	# A beam through the camera would white out the screen.
	SpellFx.fade_near_camera(mat, 0.6, 3.5)
	return mat

static func _cylinder(radius: float) -> CylinderMesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 1.0
	cylinder.radial_segments = 10
	return cylinder
