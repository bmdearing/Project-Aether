extends Node3D
class_name StormcallBolt
## Stormcall's cast VFX: a jagged bolt flashes from high above straight
## down to the cast point (procedural zigzag mesh, same ridge-building
## technique as MountainRange.gd's silhouettes, just vertical) and fades
## almost immediately - real lightning doesn't loiter - plus the usual
## ground-shockwave ring. Purely visual, same damage-timing note as
## CometImpact/InfernoPillar.

const BOLT_HEIGHT := 10.0
const SEGMENT_COUNT := 8
const JITTER := 0.35
const BOLT_HALF_WIDTH := 0.08
const FLASH_IN_DURATION := 0.04
const HOLD_DURATION := 0.06
const FADE_DURATION := 0.12
const SHOCKWAVE_SCENE := preload("res://entities/effects/ability_range_effect/AbilityRangeEffect.tscn")

@onready var bolt: MeshInstance3D = $Bolt

func play(radius: float, color: Color) -> void:
	_build_bolt_mesh()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var flash_color := color.lightened(0.6)
	flash_color.a = 0.0
	mat.albedo_color = flash_color
	bolt.material_override = mat

	var shockwave: AbilityRangeEffect = SHOCKWAVE_SCENE.instantiate()
	get_parent().add_child(shockwave)
	shockwave.global_position = global_position
	shockwave.play(radius, color)

	var tween := create_tween()
	tween.tween_property(mat, "albedo_color:a", 1.0, FLASH_IN_DURATION)
	tween.tween_interval(HOLD_DURATION)
	tween.tween_property(mat, "albedo_color:a", 0.0, FADE_DURATION)
	tween.tween_callback(queue_free)

## Two crossed vertical quads (like a mountain "flat" from two angles at
## once) following a jagged path from BOLT_HEIGHT down to the cast point
## at the origin - jitter narrows to zero at both ends so the bolt
## actually starts straight up and hits exactly on target.
func _build_bolt_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var step := BOLT_HEIGHT / float(SEGMENT_COUNT)
	var points: Array[Vector3] = []
	for i in range(SEGMENT_COUNT + 1):
		var y := BOLT_HEIGHT - step * i
		var at_end := i == 0 or i == SEGMENT_COUNT
		var jitter_amount: float = 0.0 if at_end else JITTER
		var x: float = rng.randf_range(-jitter_amount, jitter_amount)
		var z: float = rng.randf_range(-jitter_amount, jitter_amount)
		points.append(Vector3(x, y, z))

	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		_add_quad(st, a, b, Vector3(BOLT_HALF_WIDTH, 0, 0))
		_add_quad(st, a, b, Vector3(0, 0, BOLT_HALF_WIDTH))

	st.generate_normals()
	bolt.mesh = st.commit()

func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, perp: Vector3) -> void:
	st.add_vertex(a - perp)
	st.add_vertex(a + perp)
	st.add_vertex(b + perp)
	st.add_vertex(a - perp)
	st.add_vertex(b + perp)
	st.add_vertex(b - perp)
