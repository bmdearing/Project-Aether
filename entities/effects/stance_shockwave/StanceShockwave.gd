extends Node3D
class_name StanceShockwave
## Shock Lance Discharge: a Lightning wave that runs along the ground,
## riding over slopes and stopping at walls, hitting each enemy within
## `half_width` of its path once. Frees itself when it ends.

const STEP_UP := 1.0      # how far above the wave the ground probe starts
const STEP_DOWN := 2.5
const BODY_RADIUS := 0.5
const SPARK_INTERVAL := 0.02
const SPARK_LIFETIME := 0.25
const SPARKS_PER_STEP := 3
const COLOR := Color(0.7, 0.85, 1.0)

var _direction: Vector3
var _remaining: float
var _half_width: float
var _speed: float
var _on_hit: Callable
var _hit: Dictionary = {}
var _spark_timer: float = 0.0
var _material: StandardMaterial3D

func launch(direction: Vector3, length: float, half_width: float, speed: float, on_hit: Callable) -> void:
	_direction = Vector3(direction.x, 0.0, direction.z).normalized()
	_remaining = length
	_half_width = half_width
	_speed = speed
	_on_hit = on_hit
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = COLOR
	_snap_to_ground()

func _physics_process(delta: float) -> void:
	if _remaining <= 0.0:
		queue_free()
		return
	var step := minf(_speed * delta, _remaining)
	var next := global_position + _direction * step
	var space := get_world_3d().direct_space_state
	var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.4, next + Vector3.UP * 0.4))
	if not wall.is_empty() and wall["collider"] is StaticBody3D:
		_remaining = 0.0
		return
	global_position = next
	_remaining -= step
	_snap_to_ground()
	_hit_enemies()
	_spark_timer -= delta
	if _spark_timer <= 0.0:
		_spark_timer = SPARK_INTERVAL
		_spawn_spark()

func _snap_to_ground() -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * STEP_UP, global_position + Vector3.DOWN * STEP_DOWN)
	var ground := space.intersect_ray(query)
	if not ground.is_empty() and ground["collider"] is StaticBody3D:
		global_position.y = ground["position"].y

func _hit_enemies() -> void:
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null or _hit.has(enemy.get_instance_id()) or not enemy.health.is_alive():
			continue
		var offset := enemy.global_position - global_position
		if Vector2(offset.x, offset.z).length() <= _half_width + BODY_RADIUS and absf(offset.y) < 2.0:
			_hit[enemy.get_instance_id()] = true
			_on_hit.call(enemy)

## A few thin, jittered bolts across the wave's width.
func _spawn_spark() -> void:
	var side := _direction.cross(Vector3.UP)
	for i in SPARKS_PER_STEP:
		var bolt := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.05, randf_range(0.25, 0.9), 0.05)
		bolt.mesh = box
		var mat := _material.duplicate() as StandardMaterial3D
		bolt.material_override = mat
		get_parent().add_child(bolt)
		bolt.global_position = global_position + side * randf_range(-_half_width, _half_width) + Vector3.UP * box.size.y * 0.5
		bolt.rotation = Vector3(randf_range(-0.5, 0.5), randf_range(-PI, PI), randf_range(-0.5, 0.5))
		var tween := bolt.create_tween()
		tween.tween_property(mat, "albedo_color:a", 0.0, SPARK_LIFETIME).set_ease(Tween.EASE_IN)
		tween.tween_callback(bolt.queue_free)
