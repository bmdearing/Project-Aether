extends Node3D
class_name CometImpact

## Fired when the falling mass lands - damage is dealt then, not on cast.
signal impacted
## Comet's cast VFX: an icy ball falls from above and smashes into the
## ground at the cast point, bursting into ice-shard fragments plus the
## usual ground-shockwave ring. Purely visual - the real hit already
## lands the moment PlayerAbilityCast._cast() runs, so the fall doesn't
## delay the actual damage, just the payoff you see for it. The fall is
## short enough that the desync isn't noticeable.

const FALL_HEIGHT := 8.0
const FALL_DURATION := 0.32
const SHARD_COUNT := 16
const SHOCKWAVE_SCENE := preload("res://entities/effects/ability_range_effect/AbilityRangeEffect.tscn")

@onready var ball: MeshInstance3D = $Ball

var fall_duration: float = FALL_DURATION

func play(radius: float, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color.lightened(0.35)
	ball.material_override = mat
	ball.position = Vector3(0, FALL_HEIGHT, 0)
	ball.visible = true

	var tween := create_tween()
	tween.tween_property(ball, "position", Vector3.ZERO, fall_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_on_impact.bind(radius, color))

func _on_impact(radius: float, color: Color) -> void:
	ball.visible = false
	impacted.emit()
	AudioManager.play_at(SoundLib.pick_random(SoundLib.library.explosion), global_position)
	var shockwave: AbilityRangeEffect = SHOCKWAVE_SCENE.instantiate()
	get_parent().add_child(shockwave)
	shockwave.global_position = global_position
	shockwave.play(radius, color)
	_spawn_shards(color)
	get_tree().create_timer(0.6, true, false, true).timeout.connect(queue_free)

func _spawn_shards(color: Color) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.amount = SHARD_COUNT
	particles.lifetime = 0.5
	particles.explosiveness = 1.0
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 65.0
	particles.gravity = Vector3(0, -14.0, 0)
	particles.initial_velocity_min = 3.0
	particles.initial_velocity_max = 6.5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color.lightened(0.45)
	var shard_mesh := BoxMesh.new()
	shard_mesh.size = Vector3(0.07, 0.07, 0.07)
	shard_mesh.material = mat
	particles.mesh = shard_mesh
	add_child(particles)
	particles.emitting = true
