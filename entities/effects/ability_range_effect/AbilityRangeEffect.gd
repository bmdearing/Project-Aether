extends Node3D
class_name AbilityRangeEffect
## Simple "range pulse" VFX - a flat ring, colored by damage type, that
## expands from the caster out to the ability's actual radius and fades,
## so its range is genuinely visible instead of just a number on a
## tooltip. Procedural Tween, not a baked AnimationPlayer - same
## reasoning PlayerMeleeAttack's swing already uses (easier to author
## correctly without the visual editor). Frees itself when done.

@export var expand_duration: float = 0.35

@onready var ring: MeshInstance3D = $Ring

func play(radius: float, color: Color) -> void:
	var mesh := ring.mesh as TorusMesh
	mesh.outer_radius = max(radius, 0.2)
	mesh.inner_radius = max(radius - 0.15, 0.05)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var start_color := color
	start_color.a = 0.85
	mat.albedo_color = start_color
	ring.material_override = mat

	scale = Vector3(0.05, 0.05, 0.05)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ONE, expand_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, expand_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
