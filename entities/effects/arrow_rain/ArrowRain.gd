extends Node3D
class_name ArrowRain
## Longbow Rain of Arrows: after the arc's flight time, `waves` volleys
## fall on a circle, each hitting every enemy inside it once. on_wave_hit
## (enemy) deals the damage; this only times, targets and draws.

const FLIGHT_TIME := 0.7
const WAVE_INTERVAL := 0.25
const ARROWS_PER_WAVE := 10
const DROP_HEIGHT := 9.0
const FALL_TIME := 0.18
const BODY_RADIUS := 0.5
const COLOR := Color(0.85, 0.8, 0.65)
const MARKER_COLOR := Color(0.9, 0.8, 0.5, 0.15)

var _radius: float
var _on_wave_hit: Callable
var _material: StandardMaterial3D
var _marker: MeshInstance3D

func launch(radius: float, waves: int, on_wave_hit: Callable) -> void:
	_radius = radius
	_on_wave_hit = on_wave_hit
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = COLOR
	_marker = _make_marker()
	var tween := create_tween()
	tween.tween_interval(FLIGHT_TIME)
	for i in waves:
		tween.tween_callback(_volley)
		tween.tween_interval(WAVE_INTERVAL)
	tween.tween_interval(FALL_TIME)
	tween.tween_callback(queue_free)

func _volley() -> void:
	for i in ARROWS_PER_WAVE:
		var angle := randf() * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * _radius * sqrt(randf())
		_drop_arrow(offset)
	get_tree().create_timer(FALL_TIME, false).timeout.connect(_land)

func _land() -> void:
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null or not enemy.health.is_alive():
			continue
		var offset := enemy.global_position - global_position
		if Vector2(offset.x, offset.z).length() <= _radius + BODY_RADIUS and absf(offset.y) < 3.0:
			_on_wave_hit.call(enemy)

func _drop_arrow(offset: Vector3) -> void:
	var arrow := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.03, 0.7, 0.03)
	arrow.mesh = box
	arrow.material_override = _material
	add_child(arrow)
	arrow.position = offset + Vector3.UP * DROP_HEIGHT
	arrow.rotation.x = randf_range(-0.15, 0.15)
	var tween := arrow.create_tween()
	tween.tween_property(arrow, "position:y", 0.35, FALL_TIME).set_ease(Tween.EASE_IN)
	tween.tween_interval(0.3)
	tween.tween_callback(arrow.queue_free)

## A faint disc showing where the volleys will land.
func _make_marker() -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = _radius
	mesh.bottom_radius = _radius
	mesh.height = 0.02
	disc.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = MARKER_COLOR
	disc.material_override = mat
	add_child(disc)
	disc.position.y = 0.03
	return disc
