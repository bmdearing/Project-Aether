extends Node3D
class_name BlackHoleField
## Black Hole ("26 - Ability Staging Ground", Esoteric/Entropic): "Summons
## a point of collapsing incoherence that drags surrounding enemies toward
## its center for a short duration. High setup potential, low direct
## damage." The instant hit already lands through PlayerAbilityCast._cast()'s
## normal enemy-damage loop before this scene is even spawned (a low
## motion_value on the .tres keeps that part thin, per the doc's "low
## direct damage") - this scene is purely the extra "drags enemies toward
## center" behavior + visuals, running for DURATION seconds after that.

const DURATION := 2.5
const PULL_SPEED := 3.0
const RISE_DURATION := 0.3

var _radius: float = 5.0
var _elapsed: float = 0.0

@onready var core: MeshInstance3D = $Core

func play(radius: float, color: Color) -> void:
	_radius = radius
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color.darkened(0.5)
	core.material_override = mat
	core.scale = Vector3.ONE * 0.2
	var tween := create_tween()
	tween.tween_property(core, "scale", Vector3.ONE * 0.6, RISE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy:
			continue
		var to_center: Vector3 = global_position - enemy.global_position
		to_center.y = 0.0
		var dist := to_center.length()
		if dist < 0.05 or dist > _radius:
			continue
		var pull: Vector3 = to_center.normalized() * PULL_SPEED * delta
		if pull.length() > dist:
			pull = to_center  # don't overshoot past the center
		enemy.global_position += pull
