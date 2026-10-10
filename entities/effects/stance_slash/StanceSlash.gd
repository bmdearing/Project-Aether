extends Node3D
class_name StanceSlash
## Cutlass Water Slices: a flat crescent of water flying forward at chest
## height. Hits each enemy within `half_width` of its path once, up to
## `pierce` enemies; stops at walls or after `range`.

const BODY_RADIUS := 0.5
const SIZE := Vector3(1.4, 0.05, 0.35)
const COLOR := Color(0.55, 0.85, 1.0, 0.8)
const FADE_TIME := 0.12

var _direction: Vector3
var _remaining: float
var _half_width: float
var _speed: float
var _pierce: int
var _on_hit: Callable
var _hit: Dictionary = {}
var _material: StandardMaterial3D
var _done := false

func launch(direction: Vector3, range_m: float, half_width: float, speed: float, pierce: int, on_hit: Callable) -> void:
	_direction = direction.normalized()
	_remaining = range_m
	_half_width = half_width
	_speed = speed
	_pierce = pierce
	_on_hit = on_hit
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = SIZE
	mesh.mesh = box
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = COLOR
	mesh.material_override = _material
	add_child(mesh)
	look_at(global_position + _direction, Vector3.UP)
	rotate_object_local(Vector3.FORWARD, deg_to_rad(-20.0))
	_hit_enemies()

func _physics_process(delta: float) -> void:
	if _done:
		return
	if _remaining <= 0.0 or _hit.size() >= _pierce:
		_finish()
		return
	var step := minf(_speed * delta, _remaining)
	var next := global_position + _direction * step
	var wall := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(global_position, next, 1))
	if not wall.is_empty() and wall["collider"] is StaticBody3D:
		_finish()
		return
	global_position = next
	_remaining -= step
	_hit_enemies()

func _hit_enemies() -> void:
	for node in get_tree().get_nodes_in_group("enemy"):
		if _hit.size() >= _pierce:
			return
		var enemy := node as Enemy
		if enemy == null or _hit.has(enemy.get_instance_id()) or not enemy.health.is_alive():
			continue
		var offset := enemy.global_position - global_position
		if Vector2(offset.x, offset.z).length() <= _half_width + BODY_RADIUS and offset.y > -2.2 and offset.y < 0.5:
			_hit[enemy.get_instance_id()] = true
			_on_hit.call(enemy)

func _finish() -> void:
	_done = true
	var tween := create_tween()
	tween.tween_property(_material, "albedo_color:a", 0.0, FADE_TIME)
	tween.tween_callback(queue_free)
