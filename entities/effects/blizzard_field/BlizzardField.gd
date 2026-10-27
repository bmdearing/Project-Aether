extends Node3D
class_name BlizzardField
## Blizzard: a storm over the cast point. Every ICICLE_INTERVAL an icicle
## falls on a random enemy inside it (or a random spot when none are there)
## and hits when it lands. Built in code; PlayerAbilityCast._cast_blizzard()
## places it and passes the hit callback.

const DURATION := 5.0
const ICICLE_INTERVAL := 0.3
const FALL_HEIGHT := 8.0
const FALL_TIME := 0.28
const CLOUD_HEIGHT := 7.0

var _radius := 4.0
var _duration := DURATION
var _elapsed := 0.0
var _timer := 0.1
var _color := Color(0.6, 0.85, 1.0)
## Called with the enemy an icicle lands on.
var _hit: Callable
var _snow: CPUParticles3D

func play(radius: float, duration: float, color: Color, hit: Callable) -> void:
	_radius = radius
	_duration = duration
	_color = color
	_hit = hit
	_build()

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _duration:
		if _snow:
			_snow.emitting = false
		SpellFx.free_after(self, 1.0)
		set_physics_process(false)
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = ICICLE_INTERVAL
	var targets: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy and enemy.health.is_alive() and enemy.distance_to_body(global_position) <= _radius:
			targets.append(enemy)
	var target: Enemy = targets.pick_random() if not targets.is_empty() else null
	var landing := target.global_position if target else global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf() * _radius
	_drop_icicle(landing, target)

func _drop_icicle(landing: Vector3, target: Enemy) -> void:
	var icicle := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.09
	cone.bottom_radius = 0.0
	cone.height = 0.9
	cone.radial_segments = 6
	icicle.mesh = cone
	icicle.material_override = SpellFx.energy_material(_color.lightened(0.3), 1.6, 0.35)
	icicle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(icicle)
	var start := landing + Vector3(randf_range(-0.6, 0.6), FALL_HEIGHT, randf_range(-0.6, 0.6))
	var end := landing + Vector3.UP * 0.5
	icicle.global_position = start
	icicle.look_at(end, Vector3.FORWARD if absf((end - start).normalized().y) > 0.99 else Vector3.UP)
	icicle.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	# The target may die and the field may be replaced while the icicle falls.
	var target_ref: WeakRef = weakref(target) if target else null
	var hit := _hit
	var color := _color
	var tween := icicle.create_tween()
	tween.tween_property(icicle, "global_position", end, FALL_TIME).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func():
		var scene := icicle.get_parent()
		SpellFx.shards(scene, end, color, 8, Vector2(2, 4), Vector2(0.04, 0.1), 0.5)
		var struck: Enemy = target_ref.get_ref() as Enemy if target_ref else null
		if struck and hit.is_valid():
			hit.call(struck)
		icicle.queue_free())

func _build() -> void:
	SpellFx.ground_mark(self, global_position, _radius, SpellFx.Mark.FROST, Color(_color, 0.35), _color, _duration, 0.8)
	_snow = SpellFx.emitter(self, 160, 1.4)
	_snow.position.y = CLOUD_HEIGHT
	_snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_snow.emission_sphere_radius = _radius
	_snow.scale = Vector3(1.0, 0.1, 1.0)
	_snow.direction = Vector3.DOWN
	_snow.spread = 12.0
	_snow.gravity = Vector3(0, -3.0, 0)
	_snow.initial_velocity_min = 3.0
	_snow.initial_velocity_max = 5.0
	_snow.scale_amount_min = 0.06
	_snow.scale_amount_max = 0.14
	_snow.color_ramp = SpellFx.ramp(Color(_color, 0.0), Color(_color.lightened(0.5), 0.8))
	_snow.mesh = SpellFx.glow_quad()
	_snow.emitting = true
